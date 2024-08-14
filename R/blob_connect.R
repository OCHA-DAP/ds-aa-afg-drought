
#' @export
load_proj_containers <- function() {
  es <- azure_endpoint_url()
  # storage endpoint
  se <- AzureStor::storage_endpoint(es, sas = Sys.getenv("DSCI_AZ_SAS_DEV"))
  # storage container
  sc_global <- AzureStor::storage_container(se, "global")
  sc_projects <- AzureStor::storage_container(se, "projects")
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
  service <- rlang::arg_match(service)
  stage <- rlang::arg_match(stage)
  storae_account <- rlang::arg_match(storage_account)
  endpoint <- glue::glue(blob_url)
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
    GIF_MODIS_NDVI_CROPS = paste0(processed_root, "modis_ndvi_crops_hirat_animation.gif"),
    DIR_COGS = paste0(raw_root, "cogs/")
  )
}
