#' @title: Calculate SEAS5 empirical RP-thresholds
#' Script calculates empirical return period based threshold from SEAS5 data
#' by publication/issued month & leadtime for the 5 admins under consideration
#' Afghanistan drought AA.

#' @note
#' you will want to `devtools::install_github("OCHA-DAP/cumulus")`

box::use(
  DBI,
  RPostgres,
  cumulus,
  dplyr[...],
  purrr[...],
  lubridate[...],
  seas5 = ../R/seas5_utils
)

SEASON_OF_INTEREST <- c(3,4,5)
AOI_ADM1 <- c(
  "Takhar",
  "Badakhshan",
  "Badghis",
  "Sar-e-Pul" ,
  "Faryab"
)


con <- DBI$dbConnect(
  drv = RPostgres$Postgres(),
  user = Sys.getenv("DS_AZ_DB_PROD_UID_WRITE"),
  host = Sys.getenv("DS_AZ_DB_PROD_HOST"),
  password = Sys.getenv("DS_AZ_DB_PROD_PW_WRITE"),
  port = 5432,
  dbname = "postgres"
)

df_adm1_labels <- tbl(con,"polygon") |>
  filter(
    iso3 == "AFG",
    adm_level == 1
  ) |>
  select(
    iso3, pcode, name
  ) |>
  collect()

df_adm1_labels_aoi <- df_adm1_labels |>
  filter(
    name %in% AOI_ADM1
  ) |>
  rename(
    adm1_name =name
  )

df_seas5_aoi <- tbl(con, "seas5") |>
  filter(
    iso3 == "AFG",
    adm_level ==1,
    pcode %in%  df_adm1_labels_aoi$pcode
  ) |>
  collect() |>
  mutate(
    precipitation = mean * days_in_month(valid_date)
  )


df_seas5_mam <- seas5$aggregate_forecast(
  df_seas5_aoi,
  valid_months = SEASON_OF_INTEREST,
  by = c("iso3","pcode","issued_date")
)

df_seas5_rps_historical <- df_seas5_mam |>
  mutate(
    pub_mo = month(issued_date,label =T, abbr=T)
  ) |>
  group_by(iso3, pcode, pub_mo, leadtime) |>
  arrange(
    pcode,pub_mo,mm
  ) |>
  mutate(
    rank = row_number(),
    q_rank = rank/(max(rank)+1),
    rp_emp = 1/q_rank,

  ) |>
  arrange(pcode,pub_mo,mm) |>
  ungroup()



df_seas5_rp_rv <- df_seas5_rps_historical |>
  group_by(iso3, pcode, pub_mo, leadtime) |>
  reframe(
    rp_func = list(approxfun( rp_emp, mm,rule=2)), #interpolation function
    rp = 2:7, # calculate for RPs 2-7 - should give sufficient options
    rv = map_dbl(rp, rp_func)
  ) |>
  select(-rp_func) |>
  left_join(df_adm1_labels_aoi, by = c("iso3","pcode")) |>
  mutate(
    # tagging on a few columns in case i want to start compiling a thresholds
    # table with more indicators in future.
    parameter = "SEAS5 - MAM Forecast",
    rp_type = "Empirical"
  )

cumulus$blob_write(
  df = df_seas5_rp_rv,
  name = "ds-aa-afg-drought/processed/vector/afg_SEAS5_thresholds.parquet",
  stage = "dev",
  container = "projects"
)
