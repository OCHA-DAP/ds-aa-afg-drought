"""
Download ERA5 Land monthly data for a single month from GEE.

Extracts zonal mean statistics for 10 Afghan provinces.
Variables: snow_cover, total_precipitation_sum,
    volumetric_soil_water_1m (avg of layers 1-3)

Designed to run monthly via GitHub Actions or locally.
"""

import argparse
import json
import os
import re
from datetime import datetime

import ee
import geemap
import ocha_stratus as stratus
import pandas as pd

AOI_PROVINCES = [
    "Faryab",
    "Sar-e-Pul",
    "Jawzjan",
    "Balkh",
    "Badghis",
    "Bamyan",
    "Ghor",
    "Samangan",
    "Kunduz",
    "Takhar",
]

SCALE = 11132  # ~0.1 degree, matches R script


def initialize_ee():
    """Initialize Earth Engine with service account or default credentials."""
    key_json = os.environ.get("GEE_SERVICE_ACCOUNT_KEY")
    if key_json:
        key_data = json.loads(key_json)
        credentials = ee.ServiceAccountCredentials(
            key_data["client_email"],
            key_data=key_json,
        )
        ee.Initialize(credentials)
        print("Authenticated with GEE service account.")
    else:
        ee.Initialize()
        print("Authenticated with default GEE credentials.")


def process_image(img):
    """
    Process ERA5 image to create simplified band structure.
    Averages soil water layers 1-3 to create single 1m depth band.
    """
    soil_water_1m = (
        img.select(
            [
                "volumetric_soil_water_layer_1",
                "volumetric_soil_water_layer_2",
                "volumetric_soil_water_layer_3",
            ]
        )
        .reduce(ee.Reducer.mean())
        .rename("volumetric_soil_water_1m")
    )

    other_bands = img.select(["snow_cover", "total_precipitation_sum"])
    month = ee.Date(img.get("system:time_start")).get("month")

    return (
        other_bands.addBands(soil_water_1m)
        .set("month", month)
        .copyProperties(img, ["system:time_start"])
    )


def pivot_to_long(df):
    """
    Pivot wide zonal stats DataFrame to long format.
    Keeps: ADM0_NAME, ADM1_CODE, ADM1_NAME, Shape_Area,
        band_name, date, parameter, value
    """
    id_cols = ["ADM0_NAME", "ADM1_CODE", "ADM1_NAME", "Shape_Area"]
    data_pattern = re.compile(r"^\d{6}_")
    data_cols = [c for c in df.columns if data_pattern.match(c)]

    df_long = df[id_cols + data_cols].melt(
        id_vars=id_cols,
        value_vars=data_cols,
        var_name="band_name",
        value_name="value",
    )

    # Parse date and parameter from band_name (e.g., '202403_snow_cover')
    df_long["date"] = pd.to_datetime(
        df_long["band_name"].str[:6], format="%Y%m"
    )
    df_long["parameter"] = df_long["band_name"].str[7:]

    df_long = df_long[
        [
            "ADM0_NAME",
            "ADM1_CODE",
            "ADM1_NAME",
            "Shape_Area",
            "band_name",
            "date",
            "parameter",
            "value",
        ]
    ]

    return df_long


def main(year: int, month: int):
    print(f"Extracting ERA5 Land data for {year}-{month:02d}")

    initialize_ee()

    # Get Afghan provinces
    adm1_fc = ee.FeatureCollection("FAO/GAUL_SIMPLIFIED_500m/2015/level1")
    adm1_afghanistan = adm1_fc.filter(ee.Filter.eq("ADM0_NAME", "Afghanistan"))
    fc_filtered = adm1_afghanistan.filter(
        ee.Filter.inList("ADM1_NAME", AOI_PROVINCES)
    )
    print(f"Provinces selected: {fc_filtered.size().getInfo()}")

    # Filter ERA5 to the single target month
    start_date = f"{year}-{month:02d}-01"
    if month == 12:
        end_date = f"{year + 1}-01-01"
    else:
        end_date = f"{year}-{month + 1:02d}-01"

    ic_era = ee.ImageCollection("ECMWF/ERA5_LAND/MONTHLY_AGGR").map(
        process_image
    )
    ic_subset = ic_era.filterDate(start_date, end_date)

    n_images = ic_subset.size().getInfo()
    print(f"Images to process: {n_images}")

    if n_images == 0:
        print(
            f"No ERA5 data available for {year}-{month:02d}. "
            "Data may not yet be published."
        )
        return None

    # Convert ImageCollection to multi-band image
    img_bands = ic_subset.toBands()
    n_bands = img_bands.bandNames().size().getInfo()
    print(f"Total bands: {n_bands}")

    # Run zonal statistics
    print("Running zonal statistics...")
    result_fc = geemap.zonal_stats(
        in_value_raster=img_bands,
        in_zone_vector=fc_filtered,
        stat_type="MEAN",
        scale=SCALE,
        tile_scale=4,
        return_fc=True,
        verbose=True,
        timeout=600,
    )

    # Convert to DataFrame
    print("Converting to DataFrame...")
    features = result_fc.getInfo()["features"]
    rows = [f["properties"] for f in features]
    df = pd.DataFrame(rows)
    print(f"Wide format shape: {df.shape}")

    # Pivot to long format
    print("Pivoting to long format...")
    df_long = pivot_to_long(df)
    print(f"Long format shape: {df_long.shape}")
    print(f"Provinces: {df_long['ADM1_NAME'].unique().tolist()}")
    print(f"Parameters: {df_long['parameter'].unique().tolist()}")

    # Upload to blob
    blob_name = (
        f"ds-aa-afg-drought/monitoring_inputs/"
        f"{year}/{month:02d}/era5_land.parquet"
    )
    print(f"Uploading to blob: {blob_name}")
    stratus.upload_parquet_to_blob(
        df=df_long,
        blob_name=blob_name,
        stage="dev",
        container_name="projects",
    )
    print("Upload complete!")

    return df_long


if __name__ == "__main__":
    now = datetime.now()
    parser = argparse.ArgumentParser(
        description="Download ERA5 Land monthly data from GEE"
    )
    parser.add_argument(
        "--year",
        type=int,
        default=now.year,
        help="Year to extract (default: current year)",
    )
    parser.add_argument(
        "--month",
        type=int,
        default=now.month,
        help="Month to extract (default: current month)",
    )
    args = parser.parse_args()
    main(year=args.year, month=args.month)
