---
jupyter:
  jupytext:
    formats: ipynb,md
    text_representation:
      extension: .md
      format_name: markdown
      format_version: '1.3'
      jupytext_version: 1.16.1
  kernelspec:
    display_name: ds-aa-afg-drought
    language: python
    name: ds-aa-afg-drought
---

# Combined RP

```python
%load_ext jupyter_black
%load_ext autoreload
%autoreload 2
```

```python
import ocha_stratus as stratus
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.ticker import FormatStrFormatter

from src.constants import *
from src.rp_calc import calculate_groups_rp
```

## Load and process

### Load data

```python
query = """SELECT * FROM public.polygon WHERE iso3 = 'AFG' AND adm_level = 1"""
df_adm = pd.read_sql(query, stratus.get_engine(stage="prod"))
```

```python
wt_id = 11209
blob_name = f"ds-aa-afg-drought/trigger_timeseries/cdi_wt_id_{wt_id}.parquet"
df_cdi = stratus.load_parquet_from_blob(blob_name)
df_cdi = df_cdi.merge(
    df_adm[["pcode", "name"]], left_on="adm1_name", right_on="name"
)
```

```python
df_cdi
```

```python
pcodes = AOI_ADM1_PCODES
valid_months = [3, 4, 5]
issued_month = 2

query = f"""
SELECT * FROM public.seas5
WHERE pcode IN {tuple(pcodes)}
AND EXTRACT(MONTH FROM issued_date) = {issued_month}
AND EXTRACT(MONTH FROM valid_date) IN {tuple(valid_months)}
"""
df_seas5 = pd.read_sql(
    query,
    stratus.get_engine(stage="prod"),
    parse_dates=["issued_date", "valid_date"],
)
```

### Group into seasons

```python
df_seas5_season = (
    df_seas5.groupby(["pcode", "issued_date"])["mean"].sum().reset_index()
)
df_seas5_season["mean"] *= 30
df_seas5_season["year"] = df_seas5_season["issued_date"].dt.year
```

```python
for pcode, group in df_seas5_season.groupby("pcode"):
    print(pcode)
    print(group["mean"].quantile(1 / 4))
```

### Merge CDI and SEAS5

```python
df_combined = df_seas5_season.merge(df_cdi, on=["year", "pcode"])
df_combined = df_combined.rename(columns={"zscore": "cdi", "mean": "seas5"})
cols = ["pcode", "name", "year", "cdi", "seas5"]
df_combined = df_combined[cols]
```

```python
df_combined
```

```python
df_combined = calculate_groups_rp(
    df_combined, by=["pcode"], col_name="cdi", ascending=False
)
df_combined = calculate_groups_rp(
    df_combined, by=["pcode"], col_name="seas5", ascending=True
)
total_years = df_combined["year"].nunique()
```

```python
dff
```

```python
dicts = []
for cdi_rp in df_combined["cdi_rp"].unique():
    dff = df_combined[df_combined["cdi_rp"] >= cdi_rp]
    dicts.append(
        {
            "rp_cdi_ind": cdi_rp,
            "rp_cdi_combined": (
                (total_years + 1) / dff["year"].nunique()
                if dff["year"].nunique() > 0
                else np.inf
            ),
        }
    )

df_cdi_rps = pd.DataFrame(dicts)
```

```python
fig, ax = plt.subplots(dpi=200, figsize=(6, 6))

df_cdi_rps.sort_values("rp_cdi_ind").plot(
    x="rp_cdi_ind", y="rp_cdi_combined", legend=False, ax=ax
)

ax.set_xlim([1, 43])
ax.set_ylim([1, 43])

ax.set_title("Window B (Apr CDI) RP")
ax.set_xlabel("Individual province RP (years)")
ax.set_ylabel("Combined Window B RP (years)")

ax.spines["top"].set_visible(False)
ax.spines["right"].set_visible(False)
```

```python
dicts = []
for seas5_rp in df_combined["seas5_rp"].unique():
    dff = df_combined[df_combined["seas5_rp"] >= seas5_rp]
    dicts.append(
        {
            "rp_seas5_ind": seas5_rp,
            "rp_seas5_combined": (
                (total_years + 1) / dff["year"].nunique()
                if dff["year"].nunique() > 0
                else np.inf
            ),
        }
    )

df_seas5_rps = pd.DataFrame(dicts)
```

```python
fig, ax = plt.subplots(dpi=200, figsize=(6, 6))

df_seas5_rps.sort_values("rp_seas5_ind").plot(
    x="rp_seas5_ind", y="rp_seas5_combined", legend=False, ax=ax
)

ax.set_xlim([1, 43])
ax.set_ylim([1, 43])

ax.set_title("Window A (Feb SEAS5) RP")
ax.set_xlabel("Individual province RP (years)")
ax.set_ylabel("Combined Window A RP (years)")

ax.spines["top"].set_visible(False)
ax.spines["right"].set_visible(False)
```

```python
dff
```

```python
dicts = []
for cdi_rp in df_combined["cdi_rp"].unique():
    for seas5_rp in df_combined["seas5_rp"].unique():
        dff = df_combined[
            (df_combined["cdi_rp"] >= cdi_rp)
            | (df_combined["seas5_rp"] >= seas5_rp)
        ]
        dicts.append(
            {
                "rp_cdi_ind": cdi_rp,
                "rp_seas5_ind": seas5_rp,
                "rp_overall": (
                    (total_years + 1) / dff["year"].nunique()
                    if dff["year"].nunique() > 0
                    else np.inf
                ),
            }
        )

df_rps = pd.DataFrame(dicts)
```

```python
df_rps = df_rps.merge(df_seas5_rps).merge(df_cdi_rps)
```

```python
total_years
```

```python
cols = ["rp_seas5_combined", "rp_cdi_combined"]
df_rps_acceptable.sort_values(cols).drop_duplicates(subset=cols, keep="last")
```

```python
total_years
```

```python
WINDOW_A_AMOUNT = 3
WINDOW_B_AMOUNT = 7
```

```python
df_rps["spend_seas5_combined"] = WINDOW_A_AMOUNT / df_rps["rp_seas5_combined"]
df_rps["spend_cdi_combined"] = WINDOW_B_AMOUNT / df_rps["rp_cdi_combined"]
df_rps["spend_overall"] = (
    df_rps["spend_seas5_combined"] + df_rps["spend_cdi_combined"]
)
```

```python
def plot_overall_rp(
    ind_comb,
    min_rp_overall=3,
    max_rp_overall=5,
    rp_axis_min=None,
    rp_axis_max=43,
    include_ind_rps=False,
):
    ind_comb_str = "individual province" if ind_comb == "ind" else "combined"
    ind_comb_title_str = (
        "province-level" if ind_comb == "ind" else "window-level"
    )

    if rp_axis_min is None:
        rp_axis_min = min_rp_overall - 0.3

    fig, ax = plt.subplots(dpi=200, figsize=(6, 6))

    df_rps_acceptable = df_rps[
        (df_rps["rp_overall"] >= min_rp_overall)
        & (df_rps["rp_overall"] <= max_rp_overall)
    ]

    cols = ["rp_seas5_combined", "rp_cdi_combined"]
    df_rps_acceptable = df_rps_acceptable.sort_values(cols).drop_duplicates(
        subset=cols, keep="first"
    )

    xcol, ycol = f"rp_seas5_{ind_comb}", f"rp_cdi_{ind_comb}"

    def format_rp(val):
        return f"{val:.1f}" if val < 10 else f"{val:.0f}"

    for rp_overall, group in df_rps_acceptable.groupby("rp_overall"):
        group_sorted = group.sort_values(ycol)
        line = group_sorted.plot(
            x=xcol,
            y=ycol,
            label=f"{rp_overall:.01f}",
            linewidth=0,
            marker=".",
            markersize=4 if include_ind_rps else 8,
            zorder=-rp_overall,
            ax=ax,
        )
        marker_color = line.get_lines()[-1].get_color()
        if include_ind_rps:
            for _, row in group.iterrows():
                ax.annotate(
                    format_rp(row["rp_cdi_ind"]) + " ",
                    (row[xcol], row[ycol]),
                    va="center",
                    ha="right",
                    fontsize=6,
                    color=marker_color,
                )
                ax.annotate(
                    format_rp(row["rp_seas5_ind"]) + " ",
                    (row[xcol], row[ycol]),
                    va="top",
                    ha="center",
                    fontsize=6,
                    color=marker_color,
                    rotation=90,
                )
                ax.annotate(
                    f'${row["spend_overall"]:.1f}M',
                    (row[xcol], row[ycol]),
                    va="bottom",
                    ha="left",
                    fontsize=6,
                    fontstyle="italic",
                    color=marker_color,
                    rotation=45,
                )

    ax.plot(
        [0, 100], [0, 100], linewidth=0.5, linestyle="--", color="k", alpha=0.5
    )

    if rp_axis_max < 10:
        xticks = sorted(
            [x for x in df_rps["rp_seas5_ind"].unique() if x >= min_rp_overall]
        )
        yticks = sorted(
            [x for x in df_rps["rp_cdi_ind"].unique() if x >= min_rp_overall]
        )
        ax.set_xticks(xticks)
        ax.set_yticks(yticks)
        ax.grid(True, linestyle="--", linewidth=0.5, alpha=0.2)
        ax.tick_params(axis="x", rotation=90)
        ax.xaxis.set_major_formatter(FormatStrFormatter("%.1f"))
        ax.yaxis.set_major_formatter(FormatStrFormatter("%.1f"))

    ax.set_xlim(rp_axis_min, rp_axis_max)
    ax.set_ylim(rp_axis_min, rp_axis_max)

    ax.legend(title="Overall RP\n(years)")
    ax.legend(
        title="Overall RP\n(years)",
        bbox_to_anchor=(1.05, 1),
        loc="upper left",
        borderaxespad=0.0,
    )

    title_append = (
        "\n(small numbers indicate province-level RPs\n"
        "and average historical payout)"
        if include_ind_rps
        else ""
    )

    ax.set_title(f"Overall RP from {ind_comb_title_str} RPs" + title_append)
    ax.set_xlabel(f"Window A (Feb SEAS5) {ind_comb_str} RP (years)")
    ax.set_ylabel(f"Window B (Apr CDI) {ind_comb_str} RP (years)")

    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
```

```python
plot_overall_rp("combined", rp_axis_max=9, include_ind_rps=True)
```

```python
3 / 3.8
```

```python
7 / 4.2
```

```python
plot_overall_rp(
    "combined",
    min_rp_overall=2,
    max_rp_overall=3.3,
    rp_axis_min=1.9,
    rp_axis_max=5,
    include_ind_rps=True,
)
```

```python
10 / 3
```

```python
5 / 3
```

```python
plot_overall_rp("ind")
```

```python
plot_overall_rp("ind", rp_axis_max=15)
```

```python
plot_overall_rp("combined")
```

```python
plot_overall_rp("combined", rp_axis_max=10)
```

```python

```
