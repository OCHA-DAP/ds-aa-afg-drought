import os
import tempfile
from pathlib import Path

import pandas as pd
import xarray as xr

from src.blob_utils import (
    download_file,
    list_blobs,
    load_env_vars,
    upload_file,
)

SAS_TOKEN, CONTAINER_NAME, STORAGE_ACCOUNT = load_env_vars()

grib_files = list_blobs(
    sas_token=SAS_TOKEN,
    container_name=CONTAINER_NAME,
    storage_account=STORAGE_ACCOUNT,
    name_starts_with="ds-aa-afg-drought/raw/",
)

grib_files = [file for file in grib_files if file.endswith(".grib")]

for blob_name in grib_files:
    print(f"name: {os.path.basename(blob_name)}")

    # Create a temporary file
    with tempfile.TemporaryDirectory() as td:
        temp_base_path = os.path.basename(blob_name)
        td = Path(td)
        tf = td / temp_base_path
        # Download the file
        download_file(
            sas_token=SAS_TOKEN,
            container_name=CONTAINER_NAME,
            storage_account=STORAGE_ACCOUNT,
            blob_path=blob_name,
            local_file_path=tf,
        )

        # Open the file with xarray
        ds = xr.open_dataset(
            tf,
            engine="cfgrib",
            drop_variables=["surface", "values"],
            backend_kwargs=dict(time_dims=("time", "forecastMonth")),
        )

        ds["longitude"] = (ds["longitude"] + 180) % 360 - 180
        ds["precip"] = (
            ds["tprate"] * ds["time"].dt.days_in_month * 24 * 3600 * 1000
        )
        ds = ds.drop_vars("tprate")
        da = ds["precip"]
        da_mean = da.mean(dim=["number"])

        # loop through pub dates & COGS
        pub_dates = da_mean.time.values
        forecast_months = da_mean.forecastMonth.values

        # give a CRS
        da_mean = da_mean.rio.write_crs("EPSG:4326", inplace=False)

        for pub_date in pub_dates:
            da_out = da_mean.sel(time=pub_date)
            date_str = pd.to_datetime(pub_date).strftime("%Y-%m-%d")
            filename_prefix = f"seas5_mars_tprate_em_{date_str}"
            print(filename_prefix)

            fms = da_out.forecastMonth.values
            for i, fm_tmp in enumerate(fms):
                da_lt_out = da_out.sel(forecastMonth=fm_tmp)

                lt = fm_tmp - 1
                tmp_tif_basename = f"{filename_prefix}_lt{lt}_afg.tif"
                tmp_tif_path = td / tmp_tif_basename
                da_lt_out.rio.to_raster(tmp_tif_path, driver="COG")
                upload_file(
                    sas_token=SAS_TOKEN,
                    container_name=CONTAINER_NAME,
                    storage_account=STORAGE_ACCOUNT,
                    local_file_path=tmp_tif_path,
                    blob_path=os.path.join(
                        "ds-aa-afg-drought/cogs", tmp_tif_basename
                    ),
                )
