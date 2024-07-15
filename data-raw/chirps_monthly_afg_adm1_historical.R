#' `chirps_monthly_afg_adm1_historical.csv`
#' `Date:` 2024-04-22
#' This script generates the chirps_monthly_afg_adm1_historical.csv
#'
#' **Description:**
#' Using GEE temporally aggregate CHIRPS daily data to monthly.
#' We then run zonal means  for each yr_mo combination at the admin-1 level
#' For all of Afghanistan.
#'
#' **Tip:*
#' Script can be run in the background (on Mac with terminal call)
#' `caffeinate -i -s Rscript data-raw/chirps_monthly_afg_adm1.R`
#'
#' Originally set up before blob storage so gdrive was still being used.
#' Therefore, I've kept the code the same, but included a final step which
#' also uploads output files to blob.


library(rgee)
library(tidyrgee)
library(rhdx)
library(tidyverse)
ee_Initialize()

overwrite_csv <-  c(T,F)[2]

chirps_daily_url <- "UCSB-CHG/CHIRPS/DAILY"
chirps_ic <- ee$ImageCollection(chirps_daily_url)

adm1_fc <- ee$FeatureCollection("FAO/GAUL_SIMPLIFIED_500m/2015/level1")

# filter adm1 to get only those in Afghanistan
adm1_afghanistan <- adm1_fc$filter(ee$Filter$eq("ADM0_NAME", "Afghanistan"))

# Add to map to quickly check - only for interactive viewing (not backaground job)
# Map$addLayer(adm1_afghanistan, list(color = "red"), "Afghanistan")

# convert to tidyee IC for easy temporal aggregation
chirps_tic <-  as_tidyee(chirps_ic)

chirps_monthly_tic <- chirps_tic |>
  group_by(year, month) |>
  summarise(
    stat= "sum"
  )


# zonal means for each year-month at admin 1
df_chirps_monthly <- ee_extract_tidy(
  x=chirps_monthly_tic,
  y= adm1_afghanistan,
  scale = 5566,
  stat = "mean",
  via = "drive"
)

# write as csv
df_csv_outpath <-file.path(
  Sys.getenv("AA_DATA_DIR_NEW"),
  "public",
  "processed",
  "afg",
  "chirps_monthly_afg_adm1_historical.csv"
  )

if(overwrite_csv){
  write_csv(x = df_chirps_monthly,
            file = df_csv_outpath)
}




# Write to blob -----------------------------------------------------------


# read all csv files
df_snow_frac_processed <- read_csv(
  df_csv_outpath
)

# write to temp and then upload to blob
tf <- tempfile(fileext = ".csv")
write_csv(
  df_snow_frac_processed,
  tf
)

pc <-  load_proj_containers()
fps <- proj_blob_paths()


AzureStor::upload_blob(
  container = pc$PROJECTS_CONT,
  src = tf,
  dest = fps$DF_ADM1_CHIRPS
)
