box::use(
  cumulus,
  glue,
  janitor,
  dplyr,
  stringr,
  lubridate
  )



#' @export
load_window_b_historical_plot_data <- function(version = "20250401"){
  cumulus$blob_read(
    container = "projects",
    # where is this made
    name = glue$glue("ds-aa-afg-drought/monitoring_inputs/window_b_historical_plot_data_{version}.parquet")
  )
}
#' load_window_b_thresholds
#'
#' @param version `character` version of thresholds based on date implemented
#'   in formt YYYYMMDD
#'
#' @returns data.frame with window B thresholds
#' @export

load_window_b_thresholds <- function(version = "20250401"){
  cumulus$blob_read(
    container = "projects",
    name = glue$glue("ds-aa-afg-drought/monitoring_inputs/window_b_cdi_thresholds_{version}.parquet")
  )
}

#' load_distribution_params
#'
#' @param version
#' @note this may not a `version` argument because these zscores are
#'   calculated pre-weighting... however if indicators change this would need
#'   updating.
#' @returns
#' @export
load_distribution_params <- function(version = "20250401"){
  cumulus$blob_read(
    container = "projects",
    name = glue$glue("ds-aa-afg-drought/monitoring_inputs/window_b_cdi_distribution_params_{version}.parquet")
  )

}

#' Title
#'
#' @returns
#' @note this should not need a `version` argument because these zscores are
#'   calculated pre-weighting
load_seas5_distribution_params <- function(){
  cumulus$blob_read(
  container = "projects",
  name = "ds-aa-afg-drought/monitoring_inputs/window_b_seas5_distribution_params_20250401.parquet"
)
}

load_era5_distribution_params <- function(){
  cumulus$blob_read(
  container = "projects",
  name = "ds-aa-afg-drought/monitoring_inputs/window_b_era5_precip_distribution_params_20250401.parquet"
)
}
#' load_mixed_fcast_obs_paramss
#'
#' @returns
#' @export

load_mixed_fcast_obs_params <- function(){
  list(
    era5 = load_era5_distribution_params(),
    seas5 = load_seas5_distribution_params()
  )
}


#' Title
#'
#' @param test
#'
#' @returns
#' @export
load_raw_era5_trigger_component <- function(test= TRUE){
  year_of_concern <- ifelse(test, 2024,lubridate$year(Sys.Date()))
  cumulus$blob_read(
    stage = "dev" ,
    name = glue$glue("ds-aa-afg-drought/monitoring_inputs/{year_of_concern}/era5_land.parquet"),
    container = "projects"
  ) |>
    janitor$clean_names()
}



#' Title
#'
#' @param test
#'
#' @returns
#' @export
load_seas5_trigger_component <-  function(test = TRUE){
  year_of_concern <-  ifelse(test, 2024,lubridate::year(Sys.Date()))
  pub_date <- glue$glue("{year_of_concern}-04-01")
  df_lookup <- load_trigger_lookup()

  con <-  cumulus$pg_con()
  df_seas5_aoi <- dplyr$tbl(con, "seas5") |>
    dplyr$filter(
      iso3 == "AFG",
      adm_level == 1,
      pcode %in%  df_lookup$adm1_pcode,
      issued_date %in% pub_date
    ) |>
    dplyr$collect() |>
    dplyr$mutate(
      precipitation = mean * lubridate$days_in_month(valid_date)
    )

}
load_trigger_lookup <-  function(aoi=c("Takhar","Sar-e-Pul", "Faryab")){
  df_admin_lookup <- cumulus$blob_load_admin_lookup()
  df_admin_lookup |>
    janitor$clean_names() |>
    dplyr$filter(
      adm_level ==1,
      adm1_name %in% aoi
    )

}


#' @export
label_parameters <- function(df){
  df |>
    dplyr$mutate(
      parameter_label = dplyr$case_when(
        stringr$str_detect(parameter, "era5_land_soil_moisture_1m")~ "Soil moisture",
        stringr$str_detect(parameter, "cdi")~ "CDI",
        stringr$str_detect(parameter,"NDSI")~"NDSI",
        stringr$str_detect(parameter,"asi")~"ASI",
        stringr$str_detect(parameter,"vhi")~"VHI",
        stringr$str_detect(parameter,"cumu_chirps_precipitation_sum")~"Precip cumu (CHIRPS) ",
        stringr$str_detect(parameter,"chirps_precipitation_sum")~"Precip (CHIRPS)",
        stringr$str_detect(parameter,"cumu_era5_land_total_precipitation_sum")~"Cumulative precip",
        stringr$str_detect(parameter,"era5_land_total_precipitation_sum")~"Precip (ERA)",
        stringr$str_detect(parameter,"mean_2m_air_temperature")~"Temp (ERA)",
        stringr$str_detect(parameter,"era5_land_snow_depth_water_equivalent")~"SDWE (ERA5)",
        stringr$str_detect(parameter,"era5_land_snow_cover")~"Snow Cover",
        stringr$str_detect(parameter,"era5_land_snowmelt_sum")~"Snow Melt (ERA5)",
        stringr$str_detect(parameter,"runoff_max")~"Runoff max (ERA5)",
        stringr$str_detect(parameter,"runoff_sum")~"Runoff sum (ERA5)",
        stringr$str_detect(parameter,"SWE_inst")~"SWE (FLDAS)",
        stringr$str_detect(parameter,"mam_mixed_seas_observed")~"MAM precip (mixed obs forecast)",
        .default = parameter
      )
    )
}
