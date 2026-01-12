#'I realized the imageCollections from ERA5 extracted/downloaded in script
#' data-raw/09_* only go to 2020. Whereas the ERA5-Land ImageCollection is
#' more up to date. Rather than re-process/extract all data in
#' script data-raw/10_* I will just get precip and temp from ERA5-Land IC
#' in this script and later append it to the tabular ERA5-Land data set.

library(sf)
library(tidyverse)
library(gghdx)
library(glue)
library(ggiraph)
library(glue)
library(rgee)
# recommend github verison:
# devtools::install_github("r-tidy-remote-sensing/tidyrgee")
library(tidyrgee)
library(logger)
# ee_check()
# my current set up is that this needs to be re-authenticated 1x per week
ee_Initialize()
aoi_adm1 <- c(
  "Takhar",
  "Badakhshan",
  "Badghis",
  "Sar-e-Pul" ,
  "Faryab"
)


ic_era_monthly <- ee$ImageCollection("ECMWF/ERA5_LAND/MONTHLY_AGGR")

vars <-  c("total_precipitation_sum","temperature_2m")
ic_vars_sel <- ic_era_monthly$select(vars)
tic <-  as_tidyee(ic_era_monthly)

log_info("creating tidy image collection")
tic_vars<- as_tidyee(ic_vars_sel)
tic_vars_filt <-tic_vars |>  filter(year>1980) # dont need back to 1950

adm1_fc <- ee$FeatureCollection("FAO/GAUL_SIMPLIFIED_500m/2015/level1")
adm1_afghanistan <- adm1_fc$filter(ee$Filter$eq("ADM0_NAME", "Afghanistan"))
fc_filtered <- adm1_afghanistan$filter(
  ee$Filter$inList("ADM1_NAME", aoi_adm1)
)

log_info("Running Zonal Stats")

# Create a grouping variable for each 5-year period
yrs_unique <- unique(tic_vars_filt$vrt$year)
group <- (yrs_unique - min(yrs_unique)) %/% 5

# Split the years into a list by the grouping variable
five_year_groups <- split(yrs_unique, group)
five_year_groups |>
  map(
    \(yr_tmp){
      label <- glue("{min(yr_tmp)}_{max(yr_tmp)}")
      log_info("processing year: {label}")
      df_ecmwf_yr_tmp <- tic_vars_filt |>
        filter(year %in% yr_tmp) |>
        ee_extract_tidy(
          y=fc_filtered,
          stat = "mean",
          scale = 11132
        )

      cumulus::blob_write(
        df_ecmwf_yr_tmp,
        stage = "dev" ,
        name = glue("ds-aa-afg-drought/processed/vector/ecmwf_era5_multiband/era5-land_temp_precip_{label}.csv"),
        container = "projects"
      )
    }
  )

bc <- cumulus::blob_containers(
  stage = "dev"
)
df_blob_names <- AzureStor::list_blobs(
  bc$projects,
  prefix = "ds-aa-afg-drought/processed/vector/ecmwf_era5_multiband/era5-land_temp_precip_"
)


ldf_rs <- map(
  df_blob_names$name,
  \(x){
    cumulus::blob_read(
      stage = "dev",
      name = x,
      container = "projects",
      progress_show = T

    )
  }
)

ldf_rs |>
  list_rbind() |>
  cumulus::blob_write(
    stage = "dev" ,
    name = "ds-aa-afg-drought/processed/vector/era5-land_temp_precip_gte1981.parquet",
    container = "projects"
  )
