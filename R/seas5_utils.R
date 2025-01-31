box::use(
  dplyr,
  lubridate,
  glue,
  rlang,
  purrr,
  cumulus,
  assertthat
)

#' @export
aggregate_forecast <-  function(df,valid_months=c(3,4,5), by = c("iso3", "pcode","issued_date")){
  soi <- glue$glue_collapse(lubridate$month(valid_months,abbr=T,label =T),sep = "-")
  df |>
    dplyr$group_by(dplyr$across(dplyr$all_of(by))) |>
    dplyr$filter(
      lubridate$month(valid_date) %in% valid_months,
      all(valid_months %in% lubridate$month(valid_date))

    ) |>
    dplyr$summarise(
      mm = sum(precipitation),
      # **min() - BECAUSE**  for MJJA (5,6,7,8) at each pub_date we have a set of leadtimes
      # for EXAMPLE in March we have the following leadtimes 2
      # 2 : March + 2 = May,
      # 3 : March + 3 = June,
      # 4 : March + 4 = July
      # 5:  March + 5 = Aug
      # Therefore when we sum those leadtime precip values we take min() of lt integer so we get the leadtime to first month being aggregated
      leadtime = min(leadtime),
      .groups = "drop"
    ) |>
    dplyr$arrange(issued_date) |>
    dplyr$mutate(
      valid_month_label = soi
    )
}

#' @export
seas5_rp <- function(df,value,last_baseline_year){
  df |>
    # rename(
    #   mm = mean,
    #   pub_mo_date = issued_date
    # ) |>
    dplyr$filter(lubridate$year(issued_date)<=last_baseline_year) |>
    dplyr$mutate(
      pub_mo_label = lubridate$month(issued_date,label =T, abbr=T)
    ) |>
    dplyr$group_by(iso3, pcode, pub_mo_label, leadtime) |>
    dplyr$arrange(
      pcode,pub_mo_label,!!rlang$sym(value)
    ) |>
    dplyr$mutate(
      rank = dplyr$row_number(),
      q_rank = rank/(max(rank)+1),
      rp_emp = 1/q_rank,

    ) |>
    dplyr$arrange(pcode,pub_mo_label,!!rlang$sym(value)) |>
    dplyr$ungroup()
}

#' @export
prep_seas5_historical <- function(df,aoi){
  df |>
  dplyr$mutate(
    yr_season = lubridate$floor_date(issued_date+months(leadtime),"year"),
    parameter = "SEAS5-MAM"
  ) |>
  dplyr$rename(
    rp_relevant_direction = rp_emp,
    value = mean,
    adm1_name = name
  ) |>
  dplyr$filter(
    adm1_name %in% aoi
  ) |>
  dplyr$select(
    yr_season, adm1_name, pub_mo_date =issued_date,pub_mo_label, rp_relevant_direction, value,parameter
  )
}


load_weight_tables <- function(weight_set=c("WT_ADM2","WT_ADM1")){
  weight_set <- rlang$arg_match(weight_set)
  root_path <- "ds-aa-afg-drought/processed/vector/"
  bp <- switch(
    weight_set,
    "WT_ADM2" = "weights_adm2_no_wakhan.parquet",
    "WT_ADM1" = "weights_adm1_all_admins.parquet"
  )
  cumulus$blob_read(
    name = paste0(root_path,bp),
    stage = "dev",
    container = "projects"
  )
}

#' @export
load_seas5_historical_weighted <- function(
    weight_set=c("WT_ADM2","WT_ADM1"),
    exclude_adm1 = NULL
){
  weight_set =rlang$arg_match(weight_set)

  df_weight <- load_weight_tables(weight_set = weight_set)

  if(!is.null(exclude_adm1)){
    assertthat$assert_that(
      weight_set =="WT_ADM1",
      msg = "If excluding adm1 `weight_set` must be 'WT_ADM1"
      )

    df_weight <- df_weight |>
      dplyr$filter(
        adm1_name!= "Badakhshan"
      )
  }
  con <- cumulus$pg_con()
  adm_level_wt <- unique(df_weight$adm_level)
  pcodes_unique <- unique(df_weight$pcode)

  df_historical <- dplyr$tbl(con, "seas5") |>
    dplyr$filter(
      iso3 == "AFG",
      adm_level ==adm_level_wt,
      pcode %in% pcodes_unique
    ) |>
    dplyr$collect() |>
    dplyr$mutate(
      precipitation = mean * lubridate$days_in_month(valid_date)
    )

  dplyr$left_join(
    df_historical,
    df_weight ,
    by =c("iso3","pcode","adm_level")
    )
}


#' @export
load_seas5_threshold_tables <- function(threshold_type = c("ADM1_AOI4","ADM1_AOI4_NO_WAKHAN", "ADM1_AOI2","ADM1_AOI1")){
  root_path <- "ds-aa-afg-drought/processed/vector/"

  threshold_type <- rlang$arg_match(
    threshold_type
  )

  bp <- switch(
    threshold_type,
    "ADM1_AOI4" = "afg_SEAS5_thresholds.parquet",
    "ADM1_AOI4_NO_WAKHAN" = "afg_SEAS5_thresholds_wakhan_removed.parquet",
    "ADM1_AOI2" = "afg_SEAS5_thresholds_regional_grouped_2.parquet",
    "ADM1_AOI1" = "afg_SEAS5_thresholds_regional_grouped_1.parquet"
  )

  cumulus$blob_read(
    name = paste0(root_path,bp),
    stage = "dev",
    container = "projects"
  )
}
