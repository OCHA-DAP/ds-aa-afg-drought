#' script to load previously compiled indictors which used to be loaded
#' on the fly w/ load_compiled_indicators() and merged them with
#' the mixed-seas5-era5 forecast/observational indicator created in
#' data-raw/12_mixed_observational_forecast_indicator.R.
#'
#' The output is saved on the blob

box::use(
  dplyr[...],
  cumulus
)

box::use(
  loaders = ../R/load_funcs
)

aoi_adm1 <- c(
  "Takhar",
  "Sar-e-Pul" ,
  "Faryab"
)

# this file is created in data-raw/12_mixed_observational_forecast_indicator.R
df_mam_mixed_seas_observ <- cumulus$blob_read(
  container = "projects",
  name = "ds-aa-afg-drought/processed/vector/df_combined_era5_seas5.parquet"
)


# this object was typically created on the fly w/ the func below. Now
# i'm going to combine it w/ the above and save on the blob.
df_compiled_indicators <- loaders$load_compiled_indicators(aoi_adm1 = aoi_adm1)


df_mam_mixed_seas_observ_renamed <- df_mam_mixed_seas_observ |>
  rename(
    value = zscore
  )
# taking this over to chap 6.
df_new_compiled_indicators <- bind_rows(
  df_compiled_indicators,
  df_mam_mixed_seas_observ_renamed
)


# v2 created 2025-02-14
cumulus$blob_write(
  df_new_compiled_indicators,
  container = "projects",
  name = "ds-aa-afg-drought/processed/vector/df_all_combined_indicators_v2.parquet"
)
