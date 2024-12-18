box::use(
  AzureStor,
  glue,
  readr,
  readxl,
  rlang,
  tools
)

#' @export
load_proj_containers <- function() {
  # storage endpoint
  sdev <- AzureStor$storage_endpoint(azure_endpoint_url(), sas = Sys.getenv("DSCI_AZ_SAS_DEV"))
  sprod <- AzureStor$storage_endpoint(azure_endpoint_url(stage = "prod"), sas = Sys.getenv("DSCI_AZ_SAS_PROD"))
  # storage container
  sc_global <- AzureStor$storage_container(sprod, "raster")
  sc_projects <- AzureStor$storage_container(sdev, "projects")
  list(
    GLOBAL_CONT = sc_global,
    PROJECTS_CONT = sc_projects
  )
}

#' @export
azure_endpoint_url <- function(
    service = c("blob", "file"),
    stage = c("dev", "prod"),
    storage_account = "imb0chd0") {
  blob_url <- "https://{storage_account}{stage}.{service}.core.windows.net/"
  service <- rlang$arg_match(service)
  stage <- rlang$arg_match(stage)
  storae_account <- rlang$arg_match(storage_account)
  endpoint <- glue$glue(blob_url)
  return(endpoint)
}


#' proj_blob_paths
#' @description
#' convenience function to easily load in blob paths required for project.
#' being built on an as needed basis.
#'
#' @export
proj_blob_paths <- function(){
  proj_root <- "ds-aa-afg-drought/"
  raw_root <- paste0(proj_root, "raw/")
  processed_root <- paste0(proj_root, "processed/")

  vector_raw <- paste0(raw_root, "vector/")
  vector_processed <- paste0(processed_root, "vector/")

  list(
    GDF_ADM1 = paste0(vector_raw, "afg_admbnda_agcho_adm1.parquet"),
    GDF_ADM2 = paste0(vector_raw, "afg_admbnda_agcho_adm2.parquet"),
    DF_ADM2_CHIRPS_WFP = paste0(vector_raw, "wfp-chirps-adm2.csv"),
    DF_ADM2_NDVI_WFP = paste0(vector_raw, "wfp-ndvi-adm2.csv"),
    DF_ADM1_CHIRPS = paste0(vector_processed,"chirps_monthly_afg_adm1_historical.csv"),
    DF_ADM1_MODIS_NDVI_CROPS = paste0(vector_processed, "modis_ndvi_crops_adm1.csv"),
    DF_ADM1_MODIS_SNOW = paste0(vector_processed, "modis_snow_frac_monthly_afg_adm1_historical.csv"),
    DF_ADM1_MODIS_SNOWMELT_M2010 = paste0(vector_processed, "modis_first_day_no_snow_2010_mask.csv"),
    DF_ADM1_MODIS_SNOWMELT_M2006 = paste0(vector_processed, "modis_first_day_no_snow_m2006_14e_120c.csv"),
    DF_ADM1_SMI = paste0(raw_root, "country_data/Afghanistan Monthly Soil moisture 2018-2024.csv"),
    DF_ADM1_FLDAS_SWE = paste0(vector_processed,"fldas_snow_SWE_adm1.csv"),
    DF_FARYAB_SEAS5 = paste0(vector_processed, "ecmwf_seas5_faryab.csv"),
    GIF_MODIS_NDVI_CROPS = paste0(processed_root, "modis_ndvi_crops_hirat_animation.gif"),
    DIR_COGS = paste0(raw_root, "cogs/"),
    DF_EMDAT = paste0(raw_root, "country_data/Major Drought Events_Afghanistan_2000-2023.xlsx"),
    DF_PRODUCTION_DATA = paste0(raw_root, "country_data/16 Years Irrigated and Rainfed Wheat Data.xlsx")
  )
}

#' Reads file if included in `proj_blob_paths()` by passing in the named list item.
#' Since files should be stored in the project container on dev, that is where we look.
#'
#' Pass additional arguments as necessary through `...`. Currently reads CSV and XLSX.
#'
#' @export
read_blob_file <- function(blob_name, ...) {
  blob_path <- proj_blob_paths()[[blob_name]]
  blob_ext <- tools$file_ext(blob_path)
  AzureStor$download_blob(
    container = load_proj_containers()$PROJECTS_CONT,
    src = blob_path,
    dest = tf <- tempfile(fileext = paste0(".", blob_ext))
  )

  switch(
    blob_ext,
    csv = readr$read_csv(tf, ...),
    xls = readxl$read_xls(tf, ...),
    xlsx = readxl$read_xlsx(tf, ...)
  )
}
