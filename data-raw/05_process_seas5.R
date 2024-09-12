box::use(
  ../R/raster_utils,
  ../R/blob_connect
)

box::use(
  AzureStor,
  dplyr,
  lubridate,
  readr,
  sf,
  stringr,
  terra,
  tidyr,
  utils
)

######################
#### LOAD IN DATA ####
######################

# admin data
utils$download.file(
  url = "https://data.fieldmaps.io/cod/originals/afg.shp.zip",
  destfile = zf <- tempfile(fileext = ".zip")
)

utils$unzip(
  zipfile = zf,
  exdir = td <- tempdir()
)

sf_faryab <- sf$read_sf(td, layer = "afg_adm1") |> 
  dplyr$filter(
    ADM1_EN == "Faryab"
  )

# seasonal forecasts
seas5 <- raster_utils$load_seas5_stack()

###################
#### AGGREGATE ####
###################

seas_faryab <- terra$extract(
  x = seas5,
  y = sf_faryab,
  fun = mean,
  weights = TRUE
)

# get dates and lead time
seas5_sources <- terra$sources(seas5)

seas5_data <- terra$sources(seas5) |> 
  stringr$str_match("(\\d{4}-\\d{2}-\\d{2})_(lt(\\d){1})") |> 
  dplyr$as_tibble(
    .name_repair = ~ c("full", "date", "small", "leadtime")
  )

# create and save out CSV

seas_faryab |> 
  tidyr$pivot_longer(
    cols = tidyr$everything(),
    names_to = NULL,
    values_to = "precipitation"
  ) |> 
  dplyr$bind_cols(
    seas5_data
  ) |> 
  dplyr$transmute(
    date,
    date_no_leap = as.Date(paste0("2021-", lubridate$month(date), "-20")),
    valid_date = date + months(leadtime),
    leadtime,
    precipitation = precipitation * 60*60*24*1000 * lubridate$days_in_month(date_no_leap)
  ) |> 
  dplyr$select(
    -date_no_leap
  ) |> 
  readr$write_csv(
    tf <- tempfile(fileext = ".csv")
  )

AzureStor$upload_blob(
  container = blob_connect$load_proj_containers()$PROJECTS_CONT,
  src = tf,
  dest = blob_connect$proj_blob_paths()$DF_FARYAB_SEAS5
)
