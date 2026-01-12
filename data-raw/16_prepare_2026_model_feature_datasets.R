# =============================================================================
# Feature Set Preparation for Drought Trigger Optimization (2026)
# =============================================================================
#
# PURPOSE:
# Prepare z-score standardized feature sets for CDI (Combined Drought Index)
# optimization. Creates two feature sets corresponding to two potential trigger
# decision points: March publication and April publication.
#
# STUDY AREA:
# 5 Northern Afghan provinces: Faryab, Sar-e-Pul, Jawzjan, Balkh, Badghis
# Values are area-weighted means across the 5 provinces.
#
# DATA SOURCES:
# 1. ERA5 Land (via GEE): snow_cover, total_precipitation_sum,
#    volumetric_soil_water_1m (avg of 3 layers), precip_cumsum (derived)
# 2. FAO ASI/VHI: Agricultural Stress Index & Vegetation Health Index (dekad 3)
# 3. SEAS5: Seasonal precipitation forecasts from ECMWF
#
# PUBLICATION vs VALID DATE LOGIC:
# - "valid_date": when the observation/forecast is valid for
# - "pub_date": when data would realistically be available for decision-making
# - pub_date = valid_date + ~1 month (accounts for processing/release lag)
#
# TWO FEATURE SETS:
# 1. MARCH PUBLICATION (mar_pub):
#    - Will likely be the forecast-oriented trigger window, but i've left in
#.     some observational data (valid feb) to see if there is anything interesting.
#    - ERA5: Feb observational data (snow, precip, soil moisture, cumulative precip)
#    - SEAS5 MAM: 3-month aggregated seasonal forecast (Mar-Apr-May) issued in March
#    - Earliest possible trigger, relies heavily on seasonal forecast skill
#
# 2. APRIL PUBLICATION (april_pub):
#    - More observational-oriented trigger window
#    - ERA5: Mar observational data (snow, precip, soil moisture, cumulative precip)
#    - ASI/VHI: Mar observational vegetation indices
#    - SEAS5: Apr (lt0) and May (lt1) individual month forecasts
#    - mixed_fcast_obsv: composite indicator averaging z-scores of:
#        * total_precipitation_sum (observed March precip)
#        * seas5 Apr (forecasted April precip)
#        * seas5 May (forecasted May precip)
#      This blends the critical observed March precip with remaining season forecasts.
#    - total_precipitation_sum also kept as separate feature
#
# Z-SCORE STANDARDIZATION:
# - All indicators converted to z-scores (mean=0, sd=1) by parameter and month
# - Sign convention: POSITIVE z-score = drought conditions
#   * ASI: kept as-is (high ASI = more agricultural stress = drought)
#   * All others: inverted (low precip/snow/soil moisture/VHI = drought)
#
# OUTCOME VARIABLE:
# - End-of-season (EOS) ASI z-score from June publication (valid May)
# - Joined to feature sets by year for model training
#
# OUTPUT:
# Two parquet files uploaded to blob:
# - 2026_mar_pub_feature_set_v1.parquet
# - 2026_april_pub_feature_set_v1.parquet
# =============================================================================

box::use(
  dplyr[...],
  lubridate[...],
  tidyr[...],
  stringr[...],
  cumulus[...],
  janitor[...],
  purrr[...],
  glue[...]
)

# Provinces of interest (no Bamyan)
PROVINCES_AOI <- c(
  "Faryab",
  "Sar-e-Pul",
  "Jawzjan",
  "Balkh",
  "Badghis"
)

# Load ERA5 data from blob
df_era5 <- blob_read(
  name = "ds-aa-afg-drought/raw/vector/historical_era5_land_ndjfmam_lte2025.parquet",
  stage = "dev",
  container_name = "projects"
)

# Quick inspection
glimpse(df_era5)
df_era5 |> count(ADM1_NAME)
df_era5 |> count(parameter)
df_era5 |> summarise(min_date = min(date), max_date = max(date))


COLS_STANDARD <-  c("adm0_name","adm1_name","parameter","valid_date","pub_date","value", "shape_area")
# Filter to provinces of interest and March/April
df_era5_c1 <- df_era5 |>
  clean_names() |>
  filter(
    adm1_name %in% PROVINCES_AOI,
    # month(date) %in% c(3, 4)  # March & April
  ) |>
  mutate(
    # just adding 5 days and flooring because i dont want anything funny
    # happening on leap years
    valid_date = floor_date(as_date(date + days(5)), "month" ),
    pub_date = floor_date(valid_date + months(1)+days(10),"month"),
    valid_year = floor_date(valid_date, "year")
  ) |>
  select(all_of(COLS_STANDARD))


# quickly make the cumsum precip parameter data.frame on it's own to then
# bind back
df_precip_cumsum <- df_era5_c1 |>
  filter(
    parameter == "total_precipitation_sum"
  ) |>
  group_by(
    adm0_name, adm1_name,
  ) |>
  mutate(
    valid_year = floor_date(valid_date,"year")
  ) |>
  arrange(adm1_name, valid_year, valid_date) |>
  group_by(adm0_name, adm1_name, valid_year) |>
  mutate(
    parameter = "precip_cumsum" ,
    value = cumsum(value),
  ) |>
  ungroup()

# will leave in all precip features and see how they shake out later
df_era5_c2 <- bind_rows(
  df_era5_c1,
  df_precip_cumsum
)


# Time-Space filter (ts_filter)
# The March-April published data is what what will be available for our triggers
df_era_ts_fliterd <- df_era5_c2 |>
  filter(
    month(pub_date)%in% c(3,4),
    adm1_name %in% PROVINCES_AOI
    )


# make area lookup for weighted means
df_area_lookup <- df_era_ts_fliterd |>
  distinct(
    adm0_name, adm1_name, shape_area
  )


df_asi <- cumulus::fao_asi_adm1_tabular(iso3 = "afg")
df_vhi <- cumulus::fao_vhi_adm1_tabular(iso3 = "afg")
df_fao <- bind_rows(df_asi, df_vhi)

df_fao_filtered <- df_fao |>
  clean_names() |>
  filter(
    province %in% PROVINCES_AOI,
    dekad == 3
  ) |>
  mutate(
    parameter = if_else(str_detect(indicator,"ASI"),"asi","vhi"),
    valid_date =floor_date(date,"month"),
    pub_date = floor_date(valid_date + months(1)+days(10),"month")
  ) |>
  rename(
    value = data,
    adm0_name = country,
    adm1_name = province
  ) |>
  left_join(df_area_lookup) |>
  select(all_of(COLS_STANDARD)) |>
  # include all months they will get divied up later to correct sets
  filter(month(pub_date) %in% c(3,4,5,6))


df_seas5 <- cumulus::pg_load_seas5_historical(
  iso3= "AFG",
  adm_name = PROVINCES_AOI,
  adm_level =1,
  convert_units = T
)

# a handy function for seasonal aggregations, just requires a bit
# of wrangling after
df_seas5_mam <- cumulus::seas5_aggregate_forecast(
  df = df_seas5,
  value = "mean",
  valid_months = c(3,4,5),
  by = c("iso3","pcode","name","issued_date")
  ) |>
  filter(month(issued_date)==3) |>
  mutate(
    parameter = glue("seas5 {valid_month_label}"),
    adm0_name = "Afghanistan",
    # forecast doesnt fit so well, but let's just put this in
    valid_date = issued_date + months(leadtime)
  ) |>
  rename(
    pub_date = issued_date,
    adm1_name = name,
    value = mean
  )

# april publication - april prediction (seas5 lt0)
# april publication - may prediction (seas5 lt1)
# For mixed seasonal forecast, we need them separate.
df_seas5_am <- df_seas5 |>
  filter(
      month(issued_date) == 4,
      leadtime %in% c(0,1)
  ) |>
  mutate(
    parameter = glue("seas5 {month(valid_date, abbr= TRUE, label = TRUE)}"),
    adm0_name = "Afghanistan"
  ) |>
  rename(
    pub_date = issued_date,
    adm1_name = name,
    value = mean
  )



df_seas5_mam_2pubs <-  bind_rows(
  df_seas5_mam,
  df_seas5_am
  ) |>
  left_join(
    df_area_lookup
  ) |>
  select(
    all_of(COLS_STANDARD)
  )


# join the seas5 components to era5-land components
df_full_long <- list_rbind(
  list(
    df_era_ts_fliterd,
    df_fao_filtered,
    df_seas5_mam_2pubs
  )
) |>
  # just standardize range to ASI range (outcome var)
  filter(
    year(pub_date)>=1984
  )


# a couple extra months in there that will get removed, but looks good
df_full_long |>
  count(
    parameter, month(pub_date)
  ) |>
  print(n= 40)

# merge provinces via weighted mean
df_full_merged_long <- df_full_long |>
  group_by(adm0_name, parameter, pub_date,valid_date) |>
  summarise(
    value = weighted.mean(value, w = shape_area, na.rm = TRUE),
    .groups= "drop"
  )


# Calculate z-scores per parameter and month
df_zscores <- df_full_merged_long |>
  ungroup() |>
  mutate(
    pub_year = year(pub_date),
    pub_month = month(pub_date),
    pub_month_label = month.abb[pub_month]
  ) |>
  group_by(parameter, pub_month) |>
  mutate(
    zscore = scale(value, center = TRUE, scale = TRUE)[, 1],
    # Invert z-scores for indicators where low = drought
    # Keep ASI as-is (high ASI = drought)
    # Invert: soil moisture, precip, snow, VHI (low values = drought)
    zscore = case_when(
      str_detect(parameter, "^asi") ~ zscore,
      TRUE ~ -zscore
    )
  ) |>
  ungroup()

df_zscores |>
  count(parameter)

df_mar_set <- df_zscores |>
  filter(
    month (pub_date) ==3
  )
df_mar_set |>
  count(
    parameter
  )

df_april_set <- df_zscores |>
  filter(
    month (pub_date) ==4
  )

df_april_set |>
  count(
    parameter
  )


# Now we create the mixed_fcast_obsv by taking the average
# of each components z-score

# Create the mixed_fcast_obsv composite indicator separately
df_mixed_fcast <- df_april_set |>
  filter(parameter %in% c("total_precipitation_sum", "seas5 Apr", "seas5 May")) |>
  mutate(parameter = "mixed_fcast_obsv") |>
  group_by(adm0_name, parameter, pub_date, pub_year) |>
  summarise(zscore = mean(zscore), .groups = "drop")

# Keep all original features and add the composite
df_april_set_clean <- df_april_set |>
  select(adm0_name, parameter, pub_date, pub_year, zscore) |>
  bind_rows(df_mixed_fcast)

df_april_wide <- df_april_set_clean |>
  pivot_wider(
    names_from = parameter, values_from = zscore
  ) |>
  mutate(
    timestep = "apr_publication"
  )

# this just feb data for all observational.
df_mar_wide <- df_mar_set |>
  select(
    adm0_name, parameter, pub_date,pub_year,zscore
  ) |>
  pivot_wider(
    names_from = parameter, values_from = zscore
  ) |>
  mutate(
    timestep = "mar_publication"
  )

ldf_features <- list(
  "mar_pub" = df_mar_wide,
  "april_pub" = df_april_wide
)

# Get the EOS ASI outcome
df_outcome <- df_zscores |>
  filter(
    parameter == "asi",
    month(pub_date)==6
  ) |>
  rename(outcome_asi_zscore = zscore) |>
  select(
    # get rid of this all as we need to join to predictors just based on year
    -all_of(c("parameter","pub_date","valid_date","pub_month","pub_month_label","value"))
  )


ldf_pred_outcome <- ldf_features |>
  map(
    \(dft){
      dft |>
        left_join(
          df_outcome, by = "pub_year"
        )
    }
  )

ldf_pred_outcome |>
  iwalk(
    \(dft,nmt){
      blob_write(
        df= dft,
        name = glue::glue("ds-aa-afg-drought/processed/vector/2026_{nmt}_feature_set_v1.parquet"),
        stage = "dev",
        container = "projects"
      )
    }
  )
