"""
Download historical ERA5 Land monthly data for Afghan provinces.

Extracts zonal mean statistics for Nov-May (NDJFMAM) from 1981-2025.
Variables: snow_cover, total_precipitation_sum,
    volumetric_soil_water_1m (avg of layers 1-3)

Provinces: Faryab, Sar-e-Pul, Jawzjan, Balkh, Badghis, Bamyan, Ghor,
    Samangan, Kunduz, Takhar
"""

import re

import ee
import geemap
import ocha_stratus as stratus
import pandas as pd

ee.Initialize()

# Configuration
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
TARGET_MONTHS = [11, 12, 1, 2, 3, 4, 5]  # Nov-May
START_DATE = "1981-01-01"
END_DATE = "2026-01-01"  # Exclusive, includes through Dec 2025
SCALE = 11132  # ~0.1 degree, matches R script
BLOB_NAME = (
    "ds-aa-afg-drought/raw/vector/historical_era5_land_ndjfmam_lte2025.parquet"  # noqa: E501
)


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

    # Reorder columns
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


def main():
    print("Setting up extraction...")

    # Get Afghan provinces
    adm1_fc = ee.FeatureCollection("FAO/GAUL_SIMPLIFIED_500m/2015/level1")
    adm1_afghanistan = adm1_fc.filter(ee.Filter.eq("ADM0_NAME", "Afghanistan"))
    fc_filtered = adm1_afghanistan.filter(
        ee.Filter.inList("ADM1_NAME", AOI_PROVINCES)
    )
    print(f"Provinces selected: {fc_filtered.size().getInfo()}")

    # Get and process ERA5 collection
    ic_era = ee.ImageCollection("ECMWF/ERA5_LAND/MONTHLY_AGGR").map(
        process_image
    )
    ic_filtered = ic_era.filter(ee.Filter.inList("month", TARGET_MONTHS))
    ic_subset = ic_filtered.filterDate(START_DATE, END_DATE)

    n_images = ic_subset.size().getInfo()
    print(f"Images to process: {n_images} (Nov-May, 1981-2025)")

    # Convert ImageCollection to multi-band image
    img_bands = ic_subset.toBands()
    n_bands = img_bands.bandNames().size().getInfo()
    print(f"Total bands: {n_bands}")

    # Run zonal statistics
    print("Running zonal statistics (this may take several minutes)...")
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
    print(f"Date range: {df_long['date'].min()} to {df_long['date'].max()}")
    print(f"Parameters: {df_long['parameter'].unique().tolist()}")

    # Upload to blob
    print(f"Uploading to blob: {BLOB_NAME}")
    stratus.upload_parquet_to_blob(
        df=df_long,
        blob_name=BLOB_NAME,
        stage="dev",
        container_name="projects",
    )
    print("Upload complete!")

    return df_long


if __name__ == "__main__":
    df = main()
