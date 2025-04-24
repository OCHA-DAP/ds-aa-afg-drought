#' Script creates the yearly csv files for the financial allocation simulation
#' Output is a `csv` with cols: "yr_date", "AFG (window A)", "AFG (window B)"
#' File is read in by ds-aa-cerf-global-trigger-allocations repo
box::use(
  DBI,
  RPostgres,
  cumulus,
  dplyr[...],
  purrr[...],
  lubridate[...],
  janitor[clean_names],
  seas5 = ../R/seas5_utils,
  ../R/pg
)

# Window B ----------------------------------------------------------------

dfz_historical <-  mload$load_window_b_historical_plot_data(version = "20250408")
df_window_b <- dfz_historical |>
  filter(parameter=="cdi") |>
  group_by(
    yr_date = floor_date(yr_season,"year")
  ) |>
  summarise(
    `AFG (window B)` = any(flag),.groups="drop"
  )

# Window A ----------------------------------------------------------------


SEASON_OF_INTEREST <- c(3,4,5)
AOI_ADM1 <- c(
  "Takhar",
  "Sar-e-Pul" ,
  "Faryab"
)
WRITE_OUTPUT <- c(T,F)[2]

con <- cumulus$pg_con()

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

prov_threshold <- 4.2
df_seas5_rps_historical <- df_seas5_mam |>
  mutate(
    pub_mo = month(issued_date,label =T, abbr=T)
  ) |>
  group_by(iso3, pcode, pub_mo, leadtime) |>
  arrange(
    pcode,pub_mo,mm
  ) |>
  mutate(
    rp_emp = utils$rp_empirical(x = mm  , direction="-1"),
    flag = rp_emp>=prov_threshold
    # rank = row_number(),
    # q_rank = rank/(max(rank)+1),
    # rp_emp = 1/q_rank,

  ) |>
  arrange(pcode,pub_mo,mm) |>
  ungroup()


df_seas5_rps_historical |>
  filter(
    pub_mo == "Feb"
  ) |>
  group_by(
    iso3,pcode
  ) |>
  summarise(
    mean(flag)
  )
df_window_a <- df_seas5_rps_historical |>
  filter(
    pub_mo == "Feb"
  ) |>
  group_by(
    yr_date= floor_date(issued_date,"year")
    ) |>
  arrange(yr_date,pcode) |>
  summarise(
    `AFG (window A)` = any(flag)
  )

df_historical_flagged <- full_join(df_window_a,df_window_b)

cumulus$blob_write(df = df_historical_flagged,
                   name = "ds-aa-cerf-global-trigger-allocations/aa_historical/yearly/afg_drought_aa_yearly.csv"
                   )
