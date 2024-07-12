import os
import tempfile

import pandas as pd
from ecmwfapi import ECMWFService

from src.blob_utils import load_env_vars, upload_file

SAS_TOKEN, CONTAINER_NAME, STORAGE_ACCOUNT = load_env_vars()

# make abounding box around afghanistan
xmin = 60
ymin = 29
xmax = 76
ymax = 39

bounding_box = [xmin, ymin, xmax, ymax]

# turn bounding box coordinates into string with each coord separted by: "/"
bounding_box_str = "/".join(
    [
        str(round(coord, 1))
        for coord in [
            bounding_box[3],
            bounding_box[0],
            bounding_box[1],
            bounding_box[2],
        ]
    ]
)


server = ECMWFService("mars")

# accoring to documentation 1981-2016 have 25 ens members, after 51

start_year = 1981
end_year = 2024


for year in range(start_year, end_year):
    print(f"downloading {year}")
    # Create a temporary directory
    with tempfile.TemporaryDirectory() as td:
        # create outpath in temp dir
        tp = os.path.join(td, f"ecmwf_mars_{year}.grib")
        temp_base = os.path.basename(tp)
        BLOB_OUTPATH = os.path.join("ds-aa-afg-drought", "raw", temp_base)

        start_date = pd.to_datetime(f"{year}-01-01")
        end_date = pd.to_datetime(f"{year}-12-01")

        # Generate a sequence of monthly dates
        date_range = pd.date_range(start=start_date, end=end_date, freq="MS")

        # Convert the date range to a list of formatted strings
        date_strings = [date.strftime("%Y-%m-%d") for date in date_range]

        # Join the list of formatted strings into a single string with "/"
        dates_use = "/".join(date_strings)

        if year <= 2016:
            number_use = "/".join([str(i) for i in range(25)])
        else:
            number_use = "/".join([str(i) for i in range(51)])

        grid_setup = "0.4/0.4"
        server.execute(
            {
                "class": "od",
                "date": dates_use,
                "expver": "1",
                "fcmonth": "1/2/3/4/5/6/7",
                "levtype": "sfc",
                "method": "1",
                "area": bounding_box_str,
                "grid": grid_setup,
                "number": number_use,
                "origin": "ecmwf",
                "param": "228.172",
                "stream": "msmm",
                "system": "5",
                "time": "00:00:00",
                "type": "fcmean",
                "target": "output",
            },
            tp,
        )
        upload_file(
            local_file_path=tp,
            sas_token=SAS_TOKEN,
            container_name=CONTAINER_NAME,
            storage_account=STORAGE_ACCOUNT,
            blob_path=BLOB_OUTPATH,
        )
