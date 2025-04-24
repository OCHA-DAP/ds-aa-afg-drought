box::use(
  dplyr,
  stringr,
  janitor,
  glue,
  lubridate,
  mload = ./monitoring
  )


#' Title
#'
#' @param df_fcast
#' @param df_observed
#'
#' @returns
#' @export
aggregate_mixed_fcast_obs <-  function(df_fcast, df_observed){
  df_mixed_table <- compile_mixed_fcast_obs_table(
    df_fcast = df_fcast,
    df_observed= df_observed
    )

  df_mixed_table |>
    dplyr$group_by(
      adm1_name,
      pub_mo_date,
      pub_mo_label
      ) |>
    dplyr$summarise(
      value = mean(zscore),.groups="drop"
    ) |>
    dplyr$mutate(
      parameter = "mam_mixed_seas_observed"
    )
}

#'@export
compile_mixed_fcast_obs_table <- function(df_fcast, df_observed){
  df_params  <- mload$load_mixed_fcast_obs_params()
  df_params_era5 <- df_params$era5 |>
    dplyr$select(-c("parameter","pub_mo_label","iso3"))

  df_params_seas5 <- df_params$seas5 |>
    # renaming to match how it comes out of postgres db
    dplyr$rename(pcode = "adm1_pcode") |>
    dplyr$select(-parameter)

  df_obs_filt <- df_observed |>
    dplyr$filter(
      parameter == "total_precipitation_sum",
      lubridate$month(date) ==3
    )

  df_obs_normalized <- df_obs_filt |>
    standardize_monitoring_columns() |>
    dplyr$left_join(
      df_params_era5
    ) |>
    dplyr$mutate(
      zscore = (value-mu)/sigma
    )


  # forecast normalized
  df_fcast_normalized <- dplyr$inner_join(
    df_fcast |>
      dplyr$mutate(
        parameter= glue$glue("seas5_lt{leadtime}")
      ),
    df_params_seas5
  ) |>
    dplyr$mutate(
      zscore = (precipitation - mu)/sigma
    ) |>
    dplyr$rename(
      pub_mo_date= "issued_date",
      value= "precipitation"
    ) |>
    dplyr$select(
      pub_mo_date, pub_mo_label, adm1_name,value,parameter, mu,sigma,zscore
    )

  # boom mixed inidcator
   dplyr$bind_rows(
     df_obs_normalized,
     df_fcast_normalized
  ) |>
    dplyr$select(
      adm1_name,pub_mo_date, pub_mo_label,value,parameter, mu, sigma, zscore
    ) |>
    dplyr$arrange(
      adm1_name
    )
}

#' Title
#' @param df data.frame containing extracted zonal stats for ERA5 precip
#' @param cutoff_month date to cumulate rainfall to (default 3 - march)
#'   remember if we change this we need to update the parameter
#'   distributions (mu & sigma)
#'
#' @returns
#' @export
process_era5_cumu_precip_component <-  function(df,cutoff_month = 3){
  df_era5_precip <- df  |>
    dplyr$filter(
      parameter == "total_precipitation_sum",
      lubridate$month(date)<= cutoff_month
    ) |>
    dplyr$group_by(
      adm1_name
    ) |>
    dplyr$summarise(
      date = max(date),
      value = sum(value),.groups="drop"
    ) |>
    dplyr$mutate(
      parameter ="cumu_era5_land_total_precipitation_sum"
    ) |>
    standardize_monitoring_columns()

}




#' Title
#'
#' @param df
#'
#' @returns
#' @export

process_era5_snowcover_component <- function(df){
  df |>
    dplyr$filter(
      parameter == "snow_cover",
      lubridate$month(date)==3
    ) |>
    standardize_monitoring_columns() |>
    dplyr$mutate(
      # wrangling step so it matches other tables
      parameter = paste0("era5_land_",parameter)
    )

}

#' @export
process_era5_soil_moisture <-  function(df,valid_month){
  df |>
    janitor$clean_names() |>
    dplyr$filter(
      stringr$str_detect(parameter,"volumetric_soil_water_layer_[123]"),
      lubridate$month(date)==valid_month
      ) |>
    dplyr$group_by(
      dplyr$across(c(-parameter,-value))
    ) |>
    dplyr$summarise(
      parameter = "era5_land_soil_moisture_1m",
      value = mean(value),
      .groups="drop"
    ) |>
    standardize_monitoring_columns()
}


#' @export
process_fao_trigger_component <-  function(df,aoi, test = TRUE){

  framework_year <- ifelse(test, 2024,lubridate$year(Sys.Date()))

  df_fao_aoi <- df |>
    dplyr$filter(
      adm1_name %in% aoi
    )

  df_fao_aoi |>
    dplyr$filter(
      month == "03",
      year ==framework_year,
      dekad==3
    ) |>
    standardize_monitoring_columns()
}

standardize_monitoring_columns <-  function(df){
  df |>
    dplyr$select(
      date,
      adm1_name,
      parameter,
      value ) |>
    dplyr$mutate(
      pub_mo_date = date + months(1),
      pub_mo_label = lubridate$month(pub_mo_date,label = TRUE, abbr= TRUE),.after = date
    )
}
