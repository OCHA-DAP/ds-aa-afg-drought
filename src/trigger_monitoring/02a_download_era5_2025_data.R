#' Script to download 2025 ERA5 data for monitoring
#' this should be run. manually before running 02b_window_B.R
#'
#' When run with **test** = TRUE, the script downloads data for 2024
#' When set to FALSE it will download for 2025 (first official year of framework)

library(sf)
library(tidyverse)
library(gghdx)
library(glue)
library(ggiraph)
library(glue)
library(rgee)
library(tidyrgee) # recommend github verison : devtools::install_github("r-tidy-remote-sensing/tidyrgee")
library(logger)
# ee_check()
ee_Initialize()

test <- c(T,F)[2]
year_of_concern <- ifelse(test,year(Sys.Date())-1,year(Sys.Date()))

AOI_ADM1 <- c(
  "Takhar",
  "Sar-e-Pul" ,
  "Faryab"
)

ic_era_monthly <- ee$ImageCollection("ECMWF/ERA5_LAND/MONTHLY_AGGR")
vol_soil_water <- paste0("volumetric_soil_water_layer_",1:4)
vars <- c("snow_cover","total_precipitation_sum",vol_soil_water)

ic_vars_sel <- ic_era_monthly$
  select(vars )$
  filterDate(
    glue("{year_of_concern}-01-01"),
    glue("{year_of_concern}-03-02") # date is non-inclusive so add 1 day to get march data
    )


# can actually remove this step - but nice to include for visual inspection
# and debugging
log_info("creating tidy image collection")
tic_vars <- as_tidyee(ic_vars_sel) # this is really just for viewing in this

adm1_fc <- ee$FeatureCollection("FAO/GAUL_SIMPLIFIED_500m/2015/level1")
adm1_afghanistan <- adm1_fc$filter(ee$Filter$eq("ADM0_NAME", "Afghanistan"))
fc_filtered <- adm1_afghanistan$filter(
  ee$Filter$inList("ADM1_NAME", AOI_ADM1)
)

log_info("Running Zonal Stats")


df_era5 <- ee_extract_tidy(
  x = ic_vars_sel,
  y=fc_filtered,
  stat = "mean",
  scale = 11132
)

cumulus::blob_write(
  df_era5,
  stage = "dev" ,
  name = glue("ds-aa-afg-drought/monitoring_inputs/{year_of_concern}/era5_land.parquet"),
  container = "projects"
)
