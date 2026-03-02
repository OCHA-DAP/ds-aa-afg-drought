"""
Window 1 (March) SEAS5 forecast monitoring for 2026 drought trigger.
(Transactional email variant)

Queries SEAS5 MAM seasonal forecast from the prod postgres database,
computes the area-weighted regional aggregate for 5 northern Afghan
provinces, and compares against the RP6 threshold.

Sends email via Listmonk transactional API (not campaign).

The threshold parquet is read from blob:
    ds-aa-afg-drought/monitoring_inputs/2026/trigger_thresholds.parquet

Outputs (uploaded to blob):
    - Plot: .../monitoring_outputs/{year}/YYYYMM_seas5_w1_monitor.png
    - Summary: .../monitoring_outputs/{year}/YYYYMM_seas5_w1_summary.json
"""

import argparse
import base64
import json
from calendar import monthrange
from datetime import UTC, datetime
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import ocha_stratus as stratus
import pandas as pd
from listmonk import send_transactional
from sqlalchemy import text

# ── constants ────────────────────────────────────────────────────────
PROVINCES_AOI = ["Faryab", "Sar-e-Pul", "Jawzjan", "Balkh", "Badghis"]
VALID_MONTHS = [3, 4, 5]
BASELINE_START_YEAR = 1984

THRESHOLD_BLOB = (
    "ds-aa-afg-drought/monitoring_inputs/2026/trigger_thresholds.parquet"
)
AREA_BLOB = (
    "ds-aa-afg-drought/raw/vector/historical_era5_land_ndjfmam_lte2025.parquet"
)
ADMIN_LOOKUP_BLOB = "admin_lookup.parquet"
OUTPUT_BLOB_BASE = "ds-aa-afg-drought/monitoring_outputs"


# ── data loading ─────────────────────────────────────────────────────
def load_admin_lookup():
    """Load admin lookup from blob (replicates cumulus blob_load_admin_lookup).

    Returns a DataFrame filtered to AFG adm1 provinces of interest
    with columns: adm1_name, adm1_pcode.
    """
    df = stratus.load_parquet_from_blob(
        blob_name=ADMIN_LOOKUP_BLOB,
        stage="dev",
        container_name="polygon",
    )
    df.columns = df.columns.str.lower()
    df = df.loc[
        (df["iso3"] == "AFG")
        & (df["adm_level"] == 1)
        & (df["adm1_name"].isin(PROVINCES_AOI)),
        ["adm1_name", "adm1_pcode"],
    ].drop_duplicates()
    return df


def load_threshold_mm():
    """Load the SEAS5 RP6 mm threshold from blob."""
    df = stratus.load_parquet_from_blob(
        blob_name=THRESHOLD_BLOB,
        stage="dev",
        container_name="projects",
    )
    row = df.loc[df["indicator"] == "seas5_mam"].iloc[0]
    return float(row["threshold_value"])


def load_area_weights():
    """Load province shape areas for regional aggregation."""
    df = stratus.load_parquet_from_blob(
        blob_name=AREA_BLOB,
        stage="dev",
        container_name="projects",
    )
    df.columns = df.columns.str.lower().str.replace(" ", "_")
    df = df.loc[df["adm1_name"].isin(PROVINCES_AOI)][
        ["adm1_name", "shape_area"]
    ].drop_duplicates()
    return df


def query_seas5_mam(engine, pcodes):
    """
    Query all March-issued SEAS5 MAM forecasts from prod postgres.

    Parameters
    ----------
    engine : sqlalchemy engine
    pcodes : list of str
        Admin1 pcodes to filter (e.g. ['AF29', 'AF22', ...]).

    Returns per-province, per-year rows with columns:
        issued_date, pcode, valid_date, mean, leadtime
    """
    pcode_list = ", ".join(f"'{p}'" for p in pcodes)
    valid_month_list = ", ".join(str(m) for m in VALID_MONTHS)

    sql = text(f"""
        SELECT iso3, pcode, valid_date, issued_date,
               leadtime, mean
        FROM seas5
        WHERE iso3 = 'AFG'
          AND adm_level = 1
          AND pcode IN ({pcode_list})
          AND EXTRACT(MONTH FROM issued_date) = 3
          AND EXTRACT(MONTH FROM valid_date) IN ({valid_month_list})
        ORDER BY issued_date, pcode, valid_date
    """)

    with engine.connect() as conn:
        df = pd.read_sql(sql, conn)

    return df


# ── aggregation ──────────────────────────────────────────────────────
def aggregate_regional_mam(df_seas5, df_areas, df_lookup):
    """
    Convert daily-rate forecast to MAM total (mm), then compute
    area-weighted regional mean per issued year.

    Pipeline mirrors the R feature-set creation (data-raw/16_*):
        1. precipitation = mean × days_in_month  (daily rate → monthly)
        2. sum across valid months per province   (→ MAM total)
        3. weighted.mean across provinces         (→ regional)
    """
    df = df_seas5.copy()

    # daily rate → monthly total (mm)
    df["days"] = df["valid_date"].apply(
        lambda d: monthrange(d.year, d.month)[1]
    )
    df["precip_mm"] = df["mean"] * df["days"]

    # sum MAM months per province per issued_date
    df_province = (
        df.groupby(["issued_date", "pcode"], as_index=False)["precip_mm"]
        .sum()
        .rename(columns={"precip_mm": "mam_mm"})
    )

    # join pcode → adm1_name via admin lookup
    df_province = df_province.merge(
        df_lookup.rename(columns={"adm1_pcode": "pcode"}),
        on="pcode",
        how="left",
    )

    # area-weighted regional mean
    df_province = df_province.merge(df_areas, on="adm1_name", how="left")

    def _weighted_mean(g):
        return np.average(g["mam_mm"], weights=g["shape_area"])

    df_regional = (
        df_province.groupby("issued_date", as_index=False)
        .apply(_weighted_mean, include_groups=False)
        .rename(columns={None: "mam_mm"})
    )
    df_regional["year"] = pd.to_datetime(df_regional["issued_date"]).dt.year

    return df_regional


# ── plotting ─────────────────────────────────────────────────────────
def make_plot(df_regional, current_year, threshold_mm, output_path):
    """
    Bar chart of historical + current year MAM forecast vs RP6
    threshold. Current year highlighted; bars below threshold in red.
    """
    df = df_regional.sort_values("year").copy()
    df["below"] = df["mam_mm"] <= threshold_mm
    df["is_current"] = df["year"] == current_year

    fig, ax = plt.subplots(figsize=(12, 5))

    colors = []
    for _, row in df.iterrows():
        if row["is_current"]:
            colors.append("#1EBFB3" if not row["below"] else "#F2645A")
        elif row["below"]:
            colors.append("#F2645A66")
        else:
            colors.append("#1EBFB366")

    ax.bar(df["year"], df["mam_mm"], color=colors, width=0.8)

    # threshold line
    ax.axhline(
        threshold_mm,
        color="#333333",
        linestyle="--",
        linewidth=1.5,
        label=f"RP6 threshold ({threshold_mm:.0f} mm)",
    )

    # annotate current year
    current_row = df.loc[df["year"] == current_year]
    if not current_row.empty:
        val = current_row["mam_mm"].iloc[0]
        triggered = val <= threshold_mm
        status = "TRIGGERED" if triggered else "Not triggered"
        color = "#F2645A" if triggered else "#1EBFB3"
        ax.annotate(
            f"{current_year}: {val:.0f} mm\n{status}",
            xy=(current_year, val),
            xytext=(0, 15),
            textcoords="offset points",
            ha="center",
            fontsize=10,
            fontweight="bold",
            color=color,
            arrowprops=dict(arrowstyle="-", color=color, lw=1.5),
        )

    ax.set_xlabel("Issued year (March forecast)")
    ax.set_ylabel("MAM precipitation forecast (mm)")
    ax.set_title(
        "SEAS5 MAM Forecast – Regional Aggregate\n"
        "Afghanistan Northern Provinces Drought Trigger (Window 1)",
        fontsize=12,
    )
    ax.legend(loc="upper right")
    ax.set_ylim(bottom=0)

    # only label every 5th year to avoid crowding
    years = df["year"].values
    ax.set_xticks(years[::5])
    ax.set_xticklabels(years[::5], rotation=45, ha="right")

    fig.tight_layout()
    fig.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"Plot saved: {output_path}")


# ── summary ──────────────────────────────────────────────────────────
def write_summary(df_regional, current_year, threshold_mm, output_path):
    """Write JSON summary with trigger decision."""
    current = df_regional.loc[df_regional["year"] == current_year]
    if current.empty:
        raise ValueError(
            f"No SEAS5 forecast found for {current_year}. "
            "Has the March forecast been issued?"
        )

    forecast_mm = float(current["mam_mm"].iloc[0])
    triggered = forecast_mm <= threshold_mm

    summary = {
        "window": "W1_SEAS5",
        "issued_year": current_year,
        "issued_month": 3,
        "forecast_mam_mm": round(forecast_mm, 2),
        "threshold_mm": round(threshold_mm, 2),
        "threshold_rp": 6,
        "triggered": triggered,
        "direction": "forecast <= threshold",
        "provinces": PROVINCES_AOI,
        "generated_utc": datetime.now(UTC).isoformat(timespec="seconds"),
    }

    output_path.write_text(json.dumps(summary, indent=2))
    print(f"Summary saved: {output_path}")

    # also print to stdout for GHA logs
    status = "TRIGGERED" if triggered else "NOT TRIGGERED"
    print(f"\n{'=' * 50}")
    print(f"  SEAS5 W1 Result: {status}")
    print(f"  Forecast: {forecast_mm:.1f} mm")
    print(f"  Threshold (RP6): {threshold_mm:.1f} mm")
    print(f"{'=' * 50}\n")

    return summary


# ── email ─────────────────────────────────────────────────────────────
TO_EMAILS = [("Zachary Arno", "zachary.arno@un.org")]
CC_EMAILS = [("Tristan Downing", "tristan.downing@un.org")]


def build_email_html(summary: dict, plot_path: Path) -> str:
    """Build HTML email body with trigger results and inline chart."""
    triggered = summary["triggered"]
    status = "ACTIVATED" if triggered else "NOT ACTIVATED"
    forecast_mm = summary["forecast_mam_mm"]
    threshold_mm = summary["threshold_mm"]
    status_color = "#F2645A" if triggered else "#1EBFB3"

    plot_b64 = base64.b64encode(plot_path.read_bytes()).decode()

    return f"""
Dear colleagues,
<br><br>
This is an automated monitoring update for the
<b>Anticipatory Action framework for drought in Afghanistan</b>,
Window 1 (SEAS5 seasonal precipitation forecast).
<br><br>
<table style="border-collapse:collapse;width:100%;" cellpadding="0"
 cellspacing="0">
<tr><td style="padding:12px 16px;background-color:{status_color};
color:#FFFFFF;font-size:18px;font-weight:bold;text-align:center;">
Window 1 SEAS5 trigger: {status}</td></tr>
</table>
<br>
<table style="border-collapse:collapse;" cellpadding="8" cellspacing="0">
<tr>
  <td style="border:1px solid #DDD;font-weight:bold;">
  SEAS5 MAM forecast</td>
  <td style="border:1px solid #DDD;">{forecast_mm:.1f} mm</td>
</tr>
<tr>
  <td style="border:1px solid #DDD;font-weight:bold;">
  RP6 threshold</td>
  <td style="border:1px solid #DDD;">{threshold_mm:.1f} mm</td>
</tr>
<tr>
  <td style="border:1px solid #DDD;font-weight:bold;">
  Trigger direction</td>
  <td style="border:1px solid #DDD;">
  Forecast &le; threshold (low precipitation indicates drought risk)
  </td>
</tr>
</table>
<br>
The chart below shows the historical and current SEAS5
March&ndash;April&ndash;May (MAM) precipitation forecast for the five
northern Afghan provinces (Badghis, Balkh, Faryab, Jawzjan, Sar-e-Pul),
compared against the return-period 6 threshold.
<br><br>
<img src="data:image/png;base64,{plot_b64}"
 alt="SEAS5 MAM forecast bar chart"
 style="max-width:100%;height:auto;" />
<br><br>
<p style="font-size:12px;color:#666;">
<b>About the framework:</b> Under the anticipatory action framework
for drought in Afghanistan, Window 1 evaluates the SEAS5 seasonal
precipitation forecast issued in March for the
March&ndash;April&ndash;May season. An area-weighted regional aggregate
across the five target provinces is compared against a return-period 6
threshold. If the forecast falls at or below the threshold, the trigger
is activated.
</p>
"""


# ── main ─────────────────────────────────────────────────────────────
def main(year: int):
    print(f"SEAS5 Window 1 monitoring for {year}")

    # load threshold, area weights, and admin lookup from blob (dev)
    threshold_mm = load_threshold_mm()
    print(f"Threshold (RP6): {threshold_mm:.2f} mm")

    df_areas = load_area_weights()
    print(f"Area weights loaded for {len(df_areas)} provinces")

    df_lookup = load_admin_lookup()
    pcodes = df_lookup["adm1_pcode"].tolist()
    print(f"Admin lookup: {len(df_lookup)} provinces, pcodes={pcodes}")

    # query SEAS5 from prod postgres
    print("Querying SEAS5 from prod database...")
    engine = stratus.get_engine(stage="prod")
    df_seas5 = query_seas5_mam(engine, pcodes)
    print(f"Rows returned: {len(df_seas5)}")

    # aggregate to regional MAM
    df_regional = aggregate_regional_mam(df_seas5, df_areas, df_lookup)
    df_regional = df_regional.loc[df_regional["year"] >= BASELINE_START_YEAR]
    print(f"Regional MAM series: {len(df_regional)} years")

    # outputs
    prefix = f"{year}03"
    out_dir = Path("outputs")
    out_dir.mkdir(parents=True, exist_ok=True)

    plot_name = f"{prefix}_seas5_w1_monitor.png"
    summary_name = f"{prefix}_seas5_w1_summary.json"
    plot_path = out_dir / plot_name
    summary_path = out_dir / summary_name

    make_plot(df_regional, year, threshold_mm, plot_path)
    summary = write_summary(df_regional, year, threshold_mm, summary_path)

    # upload to blob
    blob_dir = f"{OUTPUT_BLOB_BASE}/{year}"
    print(f"Uploading outputs to blob: {blob_dir}/...")
    stratus.upload_blob_data(
        data=plot_path.read_bytes(),
        blob_name=f"{blob_dir}/{plot_name}",
        stage="dev",
        container_name="projects",
        content_type="image/png",
    )
    stratus.upload_blob_data(
        data=json.dumps(summary, indent=2).encode(),
        blob_name=f"{blob_dir}/{summary_name}",
        stage="dev",
        container_name="projects",
        content_type="application/json",
    )
    print("Upload complete.")

    # email notification (transactional)
    triggered = summary["triggered"]
    status = "ACTIVATED" if triggered else "NOT ACTIVATED"

    body_html = build_email_html(summary, plot_path)
    subject = (
        "Anticipatory action Afghanistan: "
        f"Drought W1 SEAS5 forecast [{status}]"
    )

    print(f"Sending transactional email to {TO_EMAILS}...")
    send_transactional(
        to_emails=TO_EMAILS,
        cc_emails=CC_EMAILS,
        subject=subject,
        data={"content": body_html},
    )
    print("Transactional email sent.")

    return summary


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="SEAS5 Window 1 monitoring (March MAM forecast)"
    )
    parser.add_argument(
        "--year",
        type=int,
        default=datetime.now().year,
        help="Forecast year to monitor (default: current year)",
    )
    args = parser.parse_args()
    main(year=args.year)
