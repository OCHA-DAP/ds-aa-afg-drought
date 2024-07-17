#' `modis_snow_frac_monthly_afg_adm1_historical.csv`
#' `Date:` 2024-04-22
#' This script generates the modis_snow_frac_monthly_afg_adm1_historical.csv
#' @note `ANALYSIS & DATA PRDUCED ONLY USED IN EXPLORATORY`
#'
#' **Description:**
#' Using GEE temporally aggregate MODIS NDSI_Snow_Cover daily data to monthly.
#' We then run zonal means  for each yr_mo combination at the admin-1 level
#' For all of Afghanistan.
#'
#' **Limitation:**
#' It may not make sense to run this analysis without first applying a water mask.
#'
#' **Tip:*
#' Script can be run in the background (on Mac with terminal call)
#' `caffeinate -i -s Rscript data-raw/modis_snow_cover.R`
#'
#'
#' Originally set up before blob storage so gdrive was still being used.
#' Therefore, I've kept the code the same, but included a final step which
#' also uploads output files to blob.

library(rgee)
library(tidyrgee)
library(rhdx)
library(tidyverse)
ee_Initialize()

overwrite_csv <-  c(T,F)[1]
interactive_viz <- c(T,F)[2]
mod_ic = ee$ImageCollection("MODIS/061/MOD10A1")$select('NDSI_Snow_Cover')
mod_tic <- as_tidyee(mod_ic)



adm1_fc <- ee$FeatureCollection("FAO/GAUL_SIMPLIFIED_500m/2015/level1")
adm1_afghanistan <- adm1_fc$filter(ee$Filter$eq("ADM0_NAME", "Afghanistan"))

if(interactive_viz){
  mod_img_samp <- mod_ic$filterDate("2022-12-28","2022-12-29")
  vis_snow = list(
    min= 0.0,
    max= 100.0,
    palette= c('black', '0dffff', '0524ff', 'ffffff')
  )
  Map$centerObject(adm1_afghanistan, 5)
  Map$addLayer(eeObject = mod_img_samp,
               visParams=  vis_snow,
               name =  'Snow Cover')

}

mod_tic_summarised <- mod_tic |>
  group_by(year,month) |>
  summarise(
    stat=list("mean","min","max")
  )

df_snow_frac_monthly <- ee_extract_tidy(
  x=mod_tic_summarised,
  y= adm1_afghanistan,
  scale = 500,
  stat = "mean",
  via = "drive"
)

# write as csv
df_csv_outpath <-file.path(
  Sys.getenv("AA_DATA_DIR_NEW"),
  "public",
  "processed",
  "afg",
  "modis_snow_frac_monthly_afg_adm1_historical.csv"
)

if(overwrite_csv){
  write_csv(x = df_snow_frac_monthly,
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
  dest = fps$DF_ADM1_SNOW_MODIS
)
