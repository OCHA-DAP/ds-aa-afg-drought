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
    .name_repair = ~ c("full", "pub_date", "small", "leadtime")
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
    pub_date = as.Date(pub_date),
    valid_date = pub_date + months(as.numeric(leadtime)),
    leadtime,
    precip_mm_day = precipitation * 60 * 60 * 1000 * 24 # TODO: remove once blob updated
  ) |> 
  readr$write_csv(
    tf <- tempfile(fileext = ".csv")
  )

AzureStor$upload_blob(
  container = blob_connect$load_proj_containers()$PROJECTS_CONT,
  src = tf,
  dest = blob_connect$proj_blob_paths()$DF_FARYAB_SEAS5
)
