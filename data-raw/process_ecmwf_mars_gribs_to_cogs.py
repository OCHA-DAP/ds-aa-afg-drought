import os
import tempfile
from pathlib import Path

import numpy as np
import pandas as pd
import rasterio
import xarray as xr
from affine import Affine
from rasterio.crs import CRS
from scipy.interpolate import griddata

from src.blob_utils import (
    download_file,
    list_blobs,
    load_env_vars,
    upload_file,
)

sas_token, container_name, storage_account = load_env_vars()


grib_files = list_blobs(
    sas_token=sas_token,
    container_name=container_name,
    storage_account=storage_account,
    name_starts_with="ds-aa-afg-drought/raw",
)

grib_files = [file for file in grib_files if file.endswith(".grib")]
grib_file_samp = grib_files[:1]
# Loop through each blob path
for blob_name in grib_file_samp:
    print(f"name: {os.path.basename(blob_name)}")

    # Create a temporary file
    with tempfile.TemporaryDirectory() as td:
        temp_base_path = os.path.basename(blob_name)
        td = Path(td)
        tf = td / temp_base_path
        # Download the file
        download_file(
            sas_token=sas_token,
            container_name=container_name,
            storage_account=storage_account,
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
        da_mean = da_mean.rio.set_crs("EPSG:4326", inplace=True)

        # set up grid
        rRes = 0.4
        points = list(zip(da_mean.longitude.values, da_mean.latitude.values))
        xRange = np.arange(da.longitude.min(), da.longitude.max() + rRes, rRes)
        yRange = np.arange(da.latitude.min(), da.latitude.max() + rRes, rRes)

        gridX, gridY = np.meshgrid(xRange, yRange)

        # define transform and CRS
        transform = Affine.translation(
            gridX[0][0] - rRes / 2, gridY[0][0] - rRes / 2
        ) * Affine.scale(rRes, rRes)
        rasterCrs = CRS.from_epsg(4326)

        for pub_date in pub_dates:
            da_filt = da_mean.sel(time=pub_date)
            time_temp = pd.to_datetime(str(pub_date))
            time_str_temp = time_temp.strftime("%Y-%m-%d")
            print(time_str_temp)

            # create forecast month vector to loop through
            fms = da_filt.forecastMonth.values
            for i, fm_temp in enumerate(fms):
                print(fm_temp)
                da_filt_lt = da_filt.sel(forecastMonth=fm_temp)
                grid_ecmwf = griddata(
                    points, da_filt_lt.values, (gridX, gridY), method="linear"
                )

                # Use a different filename for each forecast month
                out_raster = (
                    f"ecmwf_seas5_mars_{time_str_temp}_lt{fm_temp-1}.tif"
                )
                out_path = td / out_raster

                with rasterio.open(
                    out_path,
                    "w",
                    driver="COG",
                    height=gridX.shape[0],
                    width=gridX.shape[1],
                    count=1,  # Only one band per file
                    dtype=gridX.dtype,
                    crs={"init": "epsg:4326"},
                    transform=transform,
                ) as dst:
                    dst.write(
                        grid_ecmwf, 1
                    )  # Write to the first (and only) band

                upload_file(
                    sas_token=sas_token,
                    container_name=container_name,
                    storage_account=storage_account,
                    local_file_path=out_path,
                    blob_path=os.path.join(
                        "ds-aa-afg-drought/cogs", out_raster
                    ),
                )
