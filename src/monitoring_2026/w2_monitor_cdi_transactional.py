"""
Window 2 (April) CDI monitoring for 2026 drought trigger.

Computes the Combined Drought Indicator (CDI) as a weighted sum of
z-scored indicators for 5 merged northern Afghan provinces, and compares
against the F1-optimized threshold.

CDI components (5 features from ridge model, ch12/ch13):
  - snow_cover (ERA5 Land, March)
  - volumetric_soil_water_1m (ERA5 Land, March, avg layers 1-3)
  - asi (FAO GIEWS, March dekad 3)
  - vhi (FAO GIEWS, March dekad 3)
  - mixed_fcast_obsv (mean of z-scores: ERA5 March precip + SEAS5 Apr + May)

Sends email via Listmonk transactional API.

Blob artifacts required:
  - monitoring_inputs/2026/trigger_thresholds.parquet (threshold + w_* weights)
  - monitoring_inputs/2026/cdi_distribution_params.parquet (mu/sigma)
  - monitoring_inputs/2026/cdi_historical_timeseries.parquet (plot context)
  - monitoring_inputs/{year}/{month}/era5_land.parquet (current year ERA5)
  - monitoring_inputs/2026/distribution_list.csv

Outputs (uploaded to blob):
  - monitoring_outputs/{year}/{year}04_cdi_w2_monitor.png
  - monitoring_outputs/{year}/{year}04_cdi_w2_summary.json
"""

import argparse
import base64
import json
import re
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

THRESHOLD_BLOB = (
    "ds-aa-afg-drought/monitoring_inputs/2026/trigger_thresholds.parquet"
)
DIST_PARAMS_BLOB = (
    "ds-aa-afg-drought/monitoring_inputs/2026/cdi_distribution_params.parquet"
)
HISTORICAL_BLOB = (
    "ds-aa-afg-drought/monitoring_inputs/2026/"
    "cdi_historical_timeseries.parquet"
)
AREA_BLOB = (
    "ds-aa-afg-drought/raw/vector/historical_era5_land_ndjfmam_lte2025.parquet"
)
OUTPUT_BLOB_BASE = "ds-aa-afg-drought/monitoring_outputs"
DISTRIBUTION_LIST_BLOB = (
    "ds-aa-afg-drought/monitoring_inputs/2026/distribution_list.csv"
)

FAO_ASI_URL = (
    "https://www.fao.org/giews/earthobservation/asis/data/country/AFG"
    "/MAP_ASI/DATA/ASI_Dekad_Season1_data.csv"
)
FAO_VHI_URL = (
    "https://www.fao.org/giews/earthobservation/asis/data/country/AFG"
    "/MAP_NDVI_ANOMALY/DATA/vhi_adm1_dekad_data.csv"
)


# ── data loading ─────────────────────────────────────────────────────
def load_cdi_config():
    """Load CDI threshold and w_* weights from trigger_thresholds.parquet."""
    df = stratus.load_parquet_from_blob(
        blob_name=THRESHOLD_BLOB,
        stage="dev",
        container_name="projects",
    )
    row = df.loc[df["indicator"] == "cdi"].iloc[0]
    threshold = float(row["threshold_value"])

    # Extract w_* columns as {feature_name: weight}
    w_cols = [c for c in df.columns if c.startswith("w_")]
    weights = {
        col[2:]: float(row[col]) for col in w_cols if pd.notna(row[col])
    }

    return threshold, weights


def load_distribution_params():
    """Load mu/sigma per parameter from blob."""
    return stratus.load_parquet_from_blob(
        blob_name=DIST_PARAMS_BLOB,
        stage="dev",
        container_name="projects",
    )


def load_area_weights():
    """Load province shape areas for regional aggregation."""
    df = stratus.load_parquet_from_blob(
        blob_name=AREA_BLOB,
        stage="dev",
        container_name="projects",
    )
    df.columns = df.columns.str.lower().str.replace(" ", "_")
    return df.loc[df["adm1_name"].isin(PROVINCES_AOI)][
        ["adm1_name", "shape_area"]
    ].drop_duplicates()


def load_admin_lookup():
    """Load admin lookup filtered to AOI provinces."""
    df = stratus.load_parquet_from_blob(
        blob_name="admin_lookup.parquet",
        stage="dev",
        container_name="polygon",
    )
    df.columns = df.columns.str.lower()
    return df.loc[
        (df["iso3"] == "AFG")
        & (df["adm_level"] == 1)
        & (df["adm1_name"].isin(PROVINCES_AOI)),
        ["adm1_name", "adm1_pcode"],
    ].drop_duplicates()


def load_era5_data(year):
    """Load ERA5 March parquet for given year."""
    blob = f"ds-aa-afg-drought/monitoring_inputs/{year}/03/era5_land.parquet"
    df = stratus.load_parquet_from_blob(
        blob_name=blob,
        stage="dev",
        container_name="projects",
    )
    df.columns = df.columns.str.lower().str.replace(" ", "_")
    return df


def load_fao_data():
    """Download ASI and VHI from FAO GIEWS."""
    import io
    import urllib.request

    headers = {"User-Agent": "Mozilla/5.0"}

    def _read_fao_csv(url):
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req) as resp:
            return pd.read_csv(io.BytesIO(resp.read()))

    df_asi = _read_fao_csv(FAO_ASI_URL)
    df_asi["parameter"] = "asi"
    df_vhi = _read_fao_csv(FAO_VHI_URL)
    df_vhi["parameter"] = "vhi"
    df = pd.concat([df_asi, df_vhi], ignore_index=True)
    df.columns = df.columns.str.lower().str.replace(" ", "_")
    if "province" in df.columns:
        df = df.rename(columns={"province": "adm1_name"})
    if "data" in df.columns:
        df = df.rename(columns={"data": "value"})
    return df


def query_seas5_april(engine, pcodes):
    """Query SEAS5 April-issued forecasts (leadtime 0=Apr, 1=May)."""
    pcode_list = ", ".join(f"'{p}'" for p in pcodes)
    sql = text(f"""
        SELECT iso3, pcode, valid_date, issued_date,
               leadtime, mean
        FROM seas5
        WHERE iso3 = 'AFG'
          AND adm_level = 1
          AND pcode IN ({pcode_list})
          AND EXTRACT(MONTH FROM issued_date) = 4
          AND leadtime IN (0, 1)
        ORDER BY issued_date, pcode, valid_date
    """)
    with engine.connect() as conn:
        return pd.read_sql(sql, conn)


def load_historical_timeseries():
    """Load historical CDI + component z-scores for the plot."""
    return stratus.load_parquet_from_blob(
        blob_name=HISTORICAL_BLOB,
        stage="dev",
        container_name="projects",
    )


def load_distribution_list(group="full_list"):
    """Load email distribution list from blob and split to/cc."""
    df = stratus.load_csv_from_blob(
        blob_name=DISTRIBUTION_LIST_BLOB,
        stage="dev",
        container_name="projects",
    )
    df = df.loc[df[group].fillna(False).astype(bool)]

    email_re = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    df = df.loc[df["email"].str.match(email_re, na=False)]

    def _to_tuples(sub):
        return [
            (
                "" if pd.isna(row.get("name")) else row["name"],
                row["email"],
            )
            for _, row in sub.iterrows()
        ]

    to_emails = _to_tuples(df.loc[df["to_cc"] == "to"])
    cc_emails = _to_tuples(df.loc[df["to_cc"] == "cc"])
    return to_emails, cc_emails


# ── processing ───────────────────────────────────────────────────────
def _area_weighted_mean(df, group_col):
    """Area-weighted mean per group, returns DataFrame with group + value."""
    return (
        df.groupby(group_col)[["value", "shape_area"]]
        .apply(lambda g: np.average(g["value"], weights=g["shape_area"]))
        .reset_index(name="value")
    )


def process_era5_indicators(df_era5, df_areas):
    """
    Extract March ERA5 indicators and area-weight merge to regional.

    Returns DataFrame with columns: parameter, value
    (one row per parameter: snow_cover, volumetric_soil_water_1m,
    total_precipitation_sum)
    """
    df = df_era5.copy()
    df["date"] = pd.to_datetime(df["date"])
    df = df.loc[
        (df["adm1_name"].isin(PROVINCES_AOI)) & (df["date"].dt.month == 3)
    ]

    # Average soil water layers 1-3
    soil_mask = df["parameter"].str.startswith("volumetric_soil_water_layer_")
    df.loc[soil_mask, "parameter"] = "volumetric_soil_water_1m"
    df = df.groupby(["adm1_name", "parameter", "date"], as_index=False)[
        "value"
    ].mean()

    keep = [
        "snow_cover",
        "volumetric_soil_water_1m",
        "total_precipitation_sum",
    ]
    df = df.loc[df["parameter"].isin(keep)]

    # Area-weighted merge
    df = df.merge(df_areas, on="adm1_name", how="left")
    regional = _area_weighted_mean(df, "parameter")
    return regional


def process_fao_indicators(df_fao, year, df_areas):
    """
    Extract March dekad 3 ASI + VHI and area-weight merge.

    Returns DataFrame with columns: parameter, value
    """
    df = df_fao.copy()
    df["date"] = pd.to_datetime(df["date"])
    df = df.loc[
        (df["adm1_name"].isin(PROVINCES_AOI))
        & (df["month"] == 3)
        & (df["dekad"] == 3)
        & (df["date"].dt.year == year)
    ]

    df = df.merge(df_areas, on="adm1_name", how="left")
    regional = _area_weighted_mean(df, "parameter")
    return regional


def process_seas5_indicators(df_seas5, year, df_areas, df_lookup):
    """
    Extract April-issued SEAS5 forecasts and area-weight merge.

    Returns DataFrame with columns: parameter, value
    (seas5 Apr and seas5 May)
    """
    df = df_seas5.copy()
    df["issued_date"] = pd.to_datetime(df["issued_date"])
    df["valid_date"] = pd.to_datetime(df["valid_date"])
    df = df.loc[df["issued_date"].dt.year == year]

    # daily rate → monthly total (mm)
    df["days"] = df["valid_date"].apply(
        lambda d: monthrange(d.year, d.month)[1]
    )
    df["value"] = df["mean"] * df["days"]

    # month label
    df["parameter"] = df["valid_date"].dt.strftime("seas5 %b")

    # Join pcode → adm1_name
    df = df.merge(
        df_lookup.rename(columns={"adm1_pcode": "pcode"}),
        on="pcode",
        how="left",
    )
    df = df.merge(df_areas, on="adm1_name", how="left")
    regional = _area_weighted_mean(df, "parameter")
    return regional


def compute_cdi(df_indicators, df_params, weights):
    """
    Z-score indicators, compute mixed_fcast_obsv, then CDI.

    Parameters
    ----------
    df_indicators : DataFrame with columns: parameter, value
        Raw regional values for current year.
    df_params : DataFrame with columns: parameter, mu, sigma
    weights : dict {feature_name: weight}

    Returns
    -------
    cdi_value : float
    components : dict {parameter: {"zscore": float, "weight": float}}
    """
    df = df_indicators.merge(df_params, on="parameter", how="left")

    # Z-score and invert (positive = drought)
    df["zscore"] = (df["value"] - df["mu"]) / df["sigma"]
    # Invert all except ASI (high ASI = drought already)
    df.loc[df["parameter"] != "asi", "zscore"] *= -1

    # Compute mixed_fcast_obsv = mean of 3 sub-component z-scores
    mixed_params = [
        "total_precipitation_sum",
        "seas5 Apr",
        "seas5 May",
    ]
    mixed_z = df.loc[df["parameter"].isin(mixed_params), "zscore"].mean()

    # Build CDI feature vector
    features = {}
    for _, row in df.iterrows():
        if row["parameter"] in weights:
            features[row["parameter"]] = row["zscore"]
    features["mixed_fcast_obsv"] = mixed_z

    # CDI = dot product
    cdi_value = sum(features.get(feat, 0.0) * w for feat, w in weights.items())

    # Component details for reporting
    components = {}
    for feat, w in weights.items():
        components[feat] = {
            "zscore": round(features.get(feat, 0.0), 4),
            "weight": round(w, 4),
        }

    return cdi_value, components


# ── plotting ─────────────────────────────────────────────────────────
PARAM_COLORS = {
    "cdi": "#000000",
    "asi": "#FBB4AE",
    "vhi": "#CCEBC5",
    "snow_cover": "#FFFF90",
    "volumetric_soil_water_1m": "#fec44f",
    "mixed_fcast_obsv": "#DECBE4",
}

PARAM_LABELS = {
    "cdi": "CDI",
    "asi": "ASI",
    "vhi": "VHI",
    "snow_cover": "Snow Cover",
    "volumetric_soil_water_1m": "Soil Moisture",
    "mixed_fcast_obsv": "MAM Precip (mixed obs/forecast)",
}


def make_plot(
    df_hist,
    current_year,
    current_components,
    cdi_value,
    threshold,
    triggered,
    output_path,
):
    """Historical time series + current year CDI vs threshold."""
    fig, ax = plt.subplots(figsize=(13, 5.5))
    ax.set_facecolor("#FAFAFA")
    fig.patch.set_facecolor("white")

    # Draw components first (behind CDI)
    for param in df_hist["parameter"].unique():
        if param == "cdi":
            continue
        sub = df_hist.loc[df_hist["parameter"] == param].sort_values("year")
        color = PARAM_COLORS.get(param, "#AAAAAA")
        label = PARAM_LABELS.get(param, param)
        ax.plot(
            sub["year"],
            sub["zscore"],
            color=color,
            linewidth=2.0,
            alpha=0.5,
            label=label,
        )

    # CDI line on top — bold black
    cdi_sub = df_hist.loc[df_hist["parameter"] == "cdi"].sort_values("year")
    ax.plot(
        cdi_sub["year"],
        cdi_sub["zscore"],
        color="black",
        linewidth=2.5,
        alpha=0.9,
        label="CDI",
        zorder=4,
    )

    # Threshold line
    ax.axhline(
        threshold,
        color="#C0392B",
        linestyle="--",
        linewidth=1.2,
        alpha=0.8,
    )
    ax.annotate(
        f"Threshold: {threshold:.3f}",
        xy=(df_hist["year"].min() + 1, threshold),
        xytext=(0, 6),
        textcoords="offset points",
        fontsize=8,
        color="#C0392B",
        alpha=0.8,
    )

    # Historical CDI activation dots
    hist_cdi = df_hist.loc[df_hist["parameter"] == "cdi"].copy()
    hist_activated = hist_cdi.loc[
        hist_cdi["zscore"].round(10) >= round(threshold, 10)
    ]
    if not hist_activated.empty:
        ax.scatter(
            hist_activated["year"],
            hist_activated["zscore"],
            color="#E74C3C",
            s=50,
            zorder=6,
            alpha=0.8,
            edgecolors="white",
            linewidths=0.5,
        )
        for _, row in hist_activated.iterrows():
            if int(row["year"]) != current_year:
                ax.annotate(
                    f"'{int(row['year']) % 100:02d}",
                    (row["year"], row["zscore"]),
                    textcoords="offset points",
                    xytext=(0, 9),
                    ha="center",
                    fontsize=7,
                    color="#E74C3C",
                    fontweight="bold",
                )

    # Current year CDI point — larger, prominent
    dot_color = "#E74C3C" if triggered else "#1EBFB3"
    ax.scatter(
        [current_year],
        [cdi_value],
        color=dot_color,
        s=150,
        zorder=10,
        edgecolors="white",
        linewidths=2,
    )
    status = "Threshold reached" if triggered else "Threshold not reached"
    ax.annotate(
        f"{current_year}: CDI={cdi_value:.3f}\n{status}",
        xy=(current_year, cdi_value),
        xytext=(0, 20),
        textcoords="offset points",
        ha="center",
        fontsize=9,
        fontweight="bold",
        color=dot_color,
        arrowprops=dict(arrowstyle="-", color=dot_color, lw=1.5),
    )

    ax.set_xlabel("")
    ax.set_ylabel("Indicator anomaly (z-score)", fontsize=10)
    ax.set_title(
        "Drought AA Afghanistan: Window 2 CDI Monitoring",
        fontsize=13,
        fontweight="bold",
        pad=12,
    )

    # Clean up axes
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["left"].set_alpha(0.3)
    ax.spines["bottom"].set_alpha(0.3)
    ax.tick_params(axis="both", which="both", length=0)
    ax.grid(axis="y", alpha=0.2, linewidth=0.5)

    # Legend
    ax.legend(
        loc="upper left",
        fontsize=8,
        ncol=3,
        framealpha=0.9,
        edgecolor="none",
    )

    years = sorted(df_hist["year"].unique())
    ax.set_xticks(years[::5])
    ax.set_xticklabels([str(int(y)) for y in years[::5]], fontsize=9)

    fig.tight_layout()
    fig.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"Plot saved: {output_path}")


# ── summary ──────────────────────────────────────────────────────────
def write_summary(
    cdi_value, threshold, triggered, components, year, output_path
):
    """Write JSON summary with trigger decision."""
    summary = {
        "window": "W2_CDI",
        "year": year,
        "publication_month": 4,
        "cdi_value": round(cdi_value, 4),
        "threshold": round(threshold, 4),
        "threshold_rp": 4,
        "triggered": bool(triggered),
        "direction": "CDI >= threshold",
        "provinces": PROVINCES_AOI,
        "components": components,
        "generated_utc": datetime.now(UTC).isoformat(timespec="seconds"),
    }

    output_path.write_text(json.dumps(summary, indent=2))
    print(f"Summary saved: {output_path}")

    status = "THRESHOLD REACHED" if triggered else "THRESHOLD NOT REACHED"
    print(f"\n{'=' * 50}")
    print(f"  CDI W2 Result: {status}")
    print(f"  CDI: {cdi_value:.4f}")
    print(f"  Threshold: {threshold:.4f}")
    print(f"{'=' * 50}\n")

    return summary


# ── email ────────────────────────────────────────────────────────────
def build_email_html(summary, plot_path):
    """Build HTML email body with trigger results and inline chart."""
    triggered = summary["triggered"]
    status = "THRESHOLD REACHED" if triggered else "THRESHOLD NOT REACHED"
    cdi_val = summary["cdi_value"]
    threshold = summary["threshold"]
    status_color = "#F2645A" if triggered else "#1EBFB3"

    plot_b64 = base64.b64encode(plot_path.read_bytes()).decode()

    # Component table rows
    comp_rows = ""
    for param, info in sorted(
        summary["components"].items(),
        key=lambda x: abs(x[1]["weight"]),
        reverse=True,
    ):
        label = PARAM_LABELS.get(param, param)
        comp_rows += (
            f"<tr>"
            f"<td style='border:1px solid #DDD;padding:6px;'>"
            f"{label}</td>"
            f"<td style='border:1px solid #DDD;padding:6px;"
            f"text-align:right;'>{info['zscore']:.3f}</td>"
            f"<td style='border:1px solid #DDD;padding:6px;"
            f"text-align:right;'>{info['weight']:.3f}</td>"
            f"</tr>"
        )

    return f"""
Dear colleagues,
<br><br>
This is an automated monitoring update for the
<b>Anticipatory Action framework for drought in Afghanistan</b>,
Window 2 (April CDI &ndash; Combined Drought Indicator).
<br><br>
<table style="border-collapse:collapse;width:100%;" cellpadding="0"
 cellspacing="0">
<tr><td style="padding:12px 16px;background-color:{status_color};
color:#FFFFFF;font-size:18px;font-weight:bold;text-align:center;">
Window 2 CDI: {status}</td></tr>
</table>
<br>
<table style="border-collapse:collapse;" cellpadding="8" cellspacing="0">
<tr>
  <td style="border:1px solid #DDD;font-weight:bold;">CDI value</td>
  <td style="border:1px solid #DDD;">{cdi_val:.4f}</td>
</tr>
<tr>
  <td style="border:1px solid #DDD;font-weight:bold;">
  CDI threshold (~RP4)</td>
  <td style="border:1px solid #DDD;">{threshold:.4f}</td>
</tr>
<tr>
  <td style="border:1px solid #DDD;font-weight:bold;">
  Trigger direction</td>
  <td style="border:1px solid #DDD;">
  CDI &ge; threshold (high CDI indicates drought conditions)
  </td>
</tr>
</table>
<br>
<b>Component breakdown:</b>
<table style="border-collapse:collapse;" cellpadding="6" cellspacing="0">
<tr style="background-color:#F5F5F5;">
  <th style="border:1px solid #DDD;text-align:left;">Indicator</th>
  <th style="border:1px solid #DDD;text-align:right;">Z-score</th>
  <th style="border:1px solid #DDD;text-align:right;">Weight</th>
</tr>
{comp_rows}
</table>
<br>
The chart below shows the historical CDI and component indicator anomalies
(1984&ndash;present) for the five northern Afghan provinces
(Badghis, Balkh, Faryab, Jawzjan, Sar-e-Pul), compared against the
return-period ~4 threshold.
<br><br>
<img src="data:image/png;base64,{plot_b64}"
 alt="CDI historical time series"
 style="max-width:100%;height:auto;" />
<br><br>
<p style="font-size:12px;color:#666;">
<b>About the framework:</b> Under the anticipatory action framework
for drought in Afghanistan, Window 2 evaluates a Combined Drought
Indicator (CDI) computed from five indicators: ASI and VHI (vegetation
stress), snow cover, soil moisture, and a mixed
observational&ndash;forecast precipitation composite. Each indicator is
z-score standardized against the 1984&ndash;2025 baseline, and the CDI
is their weighted sum (weights from ridge regression). If the CDI
reaches or exceeds the threshold, the trigger is considered reached.
</p>
"""


# ── main ─────────────────────────────────────────────────────────────
def main(
    year: int,
    test: bool = False,
    email_group: str = "core_developer",
    dry_run: bool = False,
):
    print(f"CDI Window 2 monitoring for {year}")

    # Load configuration
    threshold, weights = load_cdi_config()
    print(f"Threshold: {threshold:.4f}")
    print(f"Weights: {weights}")

    df_params = load_distribution_params()
    print(f"Distribution params: {len(df_params)} parameters")

    df_areas = load_area_weights()
    print(f"Area weights: {len(df_areas)} provinces")

    df_lookup = load_admin_lookup()
    pcodes = df_lookup["adm1_pcode"].tolist()

    # Load current year data
    print("Loading ERA5 data...")
    df_era5 = load_era5_data(year)

    print("Loading FAO ASI/VHI data...")
    df_fao = load_fao_data()

    print("Querying SEAS5 from prod database...")
    engine = stratus.get_engine(stage="prod")
    df_seas5 = query_seas5_april(engine, pcodes)
    print(f"SEAS5 rows: {len(df_seas5)}")

    # Process indicators → regional values
    df_era5_regional = process_era5_indicators(df_era5, df_areas)
    print(f"ERA5 indicators: {df_era5_regional['parameter'].tolist()}")

    df_fao_regional = process_fao_indicators(df_fao, year, df_areas)
    print(f"FAO indicators: {df_fao_regional['parameter'].tolist()}")

    df_seas5_regional = process_seas5_indicators(
        df_seas5, year, df_areas, df_lookup
    )
    print(f"SEAS5 indicators: {df_seas5_regional['parameter'].tolist()}")

    # Combine all raw regional indicators
    df_indicators = pd.concat(
        [df_era5_regional, df_fao_regional, df_seas5_regional],
        ignore_index=True,
    )
    print(f"\nAll indicators:\n{df_indicators}")

    # Compute CDI
    # Round to 10 decimal places to avoid floating point noise
    # at the threshold boundary (R vs Python accumulation differs
    # at ~1e-15, which can flip borderline years)
    cdi_value, components = compute_cdi(df_indicators, df_params, weights)
    triggered = round(cdi_value, 10) >= round(threshold, 10)

    # Outputs
    prefix = f"{year}04"
    out_dir = Path("outputs")
    out_dir.mkdir(parents=True, exist_ok=True)

    plot_name = f"{prefix}_cdi_w2_monitor.png"
    summary_name = f"{prefix}_cdi_w2_summary.json"
    plot_path = out_dir / plot_name
    summary_path = out_dir / summary_name

    # Plot: load historical + append current year
    print("Loading historical timeseries for plot...")
    df_hist = load_historical_timeseries()

    # Append current year component z-scores + CDI
    current_rows = []
    for param, info in components.items():
        current_rows.append(
            {"year": year, "parameter": param, "zscore": info["zscore"]}
        )
    current_rows.append(
        {"year": year, "parameter": "cdi", "zscore": cdi_value}
    )
    df_current = pd.DataFrame(current_rows)
    df_plot = pd.concat([df_hist, df_current], ignore_index=True)

    make_plot(
        df_plot,
        year,
        components,
        cdi_value,
        threshold,
        triggered,
        plot_path,
    )
    summary = write_summary(
        cdi_value, threshold, triggered, components, year, summary_path
    )

    if dry_run:
        print("\n[DRY RUN] Skipping blob upload and email.")
        return summary

    # Upload to blob
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

    # Email
    to_emails, cc_emails = load_distribution_list(group=email_group)
    print(
        f"Distribution list ({email_group}): "
        f"{len(to_emails)} to, {len(cc_emails)} cc"
    )

    body_html = build_email_html(summary, plot_path)
    status = "THRESHOLD REACHED" if triggered else "THRESHOLD NOT REACHED"
    subject = (
        f"Anticipatory Action Afghanistan: Drought Window 2 CDI [{status}]"
    )
    if test:
        subject = f"[test] {subject}"

    print(f"Sending transactional email to {[e for _, e in to_emails]}...")
    send_transactional(
        to_emails=to_emails,
        cc_emails=cc_emails,
        subject=subject,
        data={"content": body_html},
    )
    print("Transactional email sent.")

    return summary


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="CDI Window 2 monitoring (April CDI)"
    )
    parser.add_argument(
        "--year",
        type=int,
        default=datetime.now().year,
        help="Framework year to monitor (default: current year)",
    )
    parser.add_argument(
        "--test",
        action="store_true",
        help="Add [test] prefix to subject line",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Run pipeline but skip blob upload and email",
    )
    parser.add_argument(
        "--email-group",
        type=str,
        default="core_developer",
        choices=[
            "core_developer",
            "developers",
            "internal_chd",
            "full_list",
        ],
        help="Distribution list group (default: core_developer)",
    )
    args = parser.parse_args()
    main(
        year=args.year,
        test=args.test,
        email_group=args.email_group,
        dry_run=args.dry_run,
    )
