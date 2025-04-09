box::use(
  dplyr[...],
  janitor,
  lubridate[...],
  cumulus
)

box::use(
  loaders =../R/load_funcs,
  utils = ../R/utils,

)


aoi_adm1 <- c(
  "Takhar",
  "Sar-e-Pul" ,
  "Faryab"
)


# need to define range specifically before calculating any z-scores
asi_validation_date_range <-   c( "1984-01-01","2024-05-01")


# pull seas forecast -- pulling more data than necessary, but thats okay
# we will filter in memory -- just to save coding time.
df_seas5_aoi <- cumulus$pg_load_seas5_historical(
  iso3 = "AFG",
  adm_level = 1,
  adm_name = aoi_adm1,
  convert_units = T
)


# set up data w/ standard columns being output from loaders$load_compiled_indicators()
df_filt <- df_seas5_aoi |>
  rename(
    pub_mo_date = issued_date
  ) |>
  mutate(
    valid_mo = month(valid_date,label =T,abbr=T),
    pub_mo_label = as.character(month(pub_mo_date, label = T,abbr=T)),
    parameter = paste0("SEAS5-",valid_mo),
    yr_date =floor_date(valid_date, "year")
  ) |>
  # were only intereted in the April- May forecasts produced in both April & May
  filter(
    valid_mo %in% c("Apr","May"),
    pub_mo_label %in% c("Apr","May"),
    pub_mo_date >= asi_validation_date_range[1],
    pub_mo_date <= asi_validation_date_range[2]

)

# manual check - 2 forecasts from april, 1 from May - bueno
df_filt |>
  distinct(pub_mo_label, valid_mo) |>
  arrange(
    pub_mo_label
  )

# calcualte the z-scores
df_seas_z <- df_filt |>
  group_by(
    iso3,
    # a little more col name harmonization on the fly in the selects
    adm1_pcode = pcode,
    adm1_name =name,
    pub_mo_label,
    leadtime
  ) |>
  mutate(
    zscore = scale(mean,center=T,scale=T)[,1],
  ) |>
  ungroup()

# split so I have 1 df per publication date/activation moments
ldf_seas5_z <- split(df_seas_z, df_seas_z$pub_mo_label)

# Going to out put mu & sigma to be used in monitoring

df_seas_dist_params <- df_filt |>
  filter(pub_mo_label == "Apr"  ) |>
  group_by(
    iso3,
    # a little more col name harmonization on the fly in the selects
    adm1_pcode = pcode,
    adm1_name =name,
    pub_mo_label,
    leadtime
  ) |>
  summarise(
    mu = mean(mean),
    sigma = sd(mean)
    # zscore = scale(mean,center=T,scale=T)[,1],
  ) |>
  ungroup() |>
  mutate(
    parameter = "seas5"
  )

cumulus$blob_write(
  df= df_seas_dist_params,
  name = "ds-aa-afg-drought/monitoring_inputs/window_b_seas5_distribution_params_20250401.parquet"
)

# grab all the ERA5-LAND data from blob
df_era5 <- loaders$load_era5_land_multiband()

# do the same sort of filtering/harmonizations
df_era5_filt <- df_era5 |>
  janitor$clean_names() |>
  filter(
    date >= asi_validation_date_range[1],
    date <= asi_validation_date_range[2],
    adm1_name %in% aoi_adm1,
    parameter =="era5_land_total_precipitation_sum" ,
    # this date is the actual date of the data (not pub_date)
    month(date) %in% c(3,4)
  ) |>
  mutate(
    # so we can make the pub date as well so we can align it better w/ forecast
    pub_mo_date =date + months(1),

    pub_mo_label = as.character(month(pub_mo_date, label = T, abbr = T)),
    yr_date = floor_date(date,"year")
  )


# get March-April "observed" ERA5
df_MA_observed <- df_era5_filt |>
  group_by(
   yr_date ,adm1_name,
  ) |>
  # summarise(
  #   pub_mo_date = max(pub_mo_date),
  #   value = sum(value),.groups="drop"
  # ) |>
  mutate(
    parameter = "era5_land_precip_MA_observed"
  ) |>
  group_by(
    adm1_name,parameter
  ) |>
  mutate(
    zscore = scale(value,center=T,scale=T)[,1],
  ) |>
  ungroup()


# get M "observed" ERA5
df_M_observed <- df_era5_filt |>
  filter(
    month(date) == 3
  ) |>
  mutate(
    parameter = "era5_land_precip_M_observed"
  ) |>
  group_by(
    adm1_name,parameter
  ) |>
  mutate(
    zscore = scale(value,center=T,scale=T)[,1],
  ) |>
  ungroup()

df_M_observed_dist_params <- df_era5_filt |>
  filter(
    month(date) == 3
  ) |>
  mutate(
    parameter = "era5_land_precip_M_observed"
  ) |>
  group_by(
    adm1_name,parameter
  ) |>
  summarise(
    mu = mean(value),
    sigma = sd(value)
  ) |>
  ungroup() |>
  mutate(
    iso3="AFG",
    pub_mo_label = "Apr"
  )

cumulus$blob_write(
  df= df_M_observed_dist_params,
  name = "ds-aa-afg-drought/monitoring_inputs/window_b_era5_precip_distribution_params_20250401.parquet"
)


# No we will join the relevant seasonal forecast data.frame to the
# the relevant ERA5 data.frame and average the Z-scores

# here is April moment: 1 observational month, 2 forecasts (Mar & Apr)
df_april_mam_mixed_seas_observ <- bind_rows(
  df_M_observed,
  ldf_seas5_z$Apr
) |>
  select(
    adm1_name,yr_date, pub_mo_label, parameter,value, zscore, pub_mo_date
  ) |>
  group_by(
    adm1_name,
    # pub_mo_label,
    yr_date
  ) |>
  summarise(
    pub_mo_date = max(pub_mo_date),
    pub_mo_label = month(pub_mo_date,label = T , abbr= T),
    zscore = mean(zscore),.groups="drop"
  ) |>
  mutate(
    parameter = "mam_mixed_seas_observed"
  )


# here is May moment: 2 observational month (Mar & Apr), 1 forecasts (May)
df_may_mam_mixed_seas_observ <- bind_rows(
  df_MA_observed,
  ldf_seas5_z$May
) |>

  select(
    adm1_name,yr_date, pub_mo_label, parameter,value, zscore, pub_mo_date,
  ) |>
  group_by(
    adm1_name,
    # pub_mo_label,
    yr_date
  ) |>
  summarise(
    pub_mo_date= max(pub_mo_date),
    pub_mo_label = month(pub_mo_date, label = T, abbr= T),
    zscore = mean(zscore),.groups="drop"
  ) |>
  mutate(
    parameter = "mam_mixed_seas_observed"
  )


# mix together and good to go - using same parameter name as they will be
# distinguished later by pub_mo_label.



df_mam_mixed_seas_observ <- bind_rows(
  df_april_mam_mixed_seas_observ,
  df_may_mam_mixed_seas_observ
) |>
  mutate(
    # df_compiled_indicators has both -- in some cases they are different
    # i.e snowfall from nov/dec, but in this case doesnt matter
    yr_season = yr_date
  )

# so the RP vals in data.frame are not necessary for chapter 7, but are
# necessary for chapter 6... so i'll add them in so we can update plots in
# chapter 6.

df_mam_mixed_w_rp <- df_mam_mixed_seas_observ |>
  group_by(adm1_name, parameter, pub_mo_label) |>
  mutate(
    rp_relevant_direction = utils$rp_empirical(zscore,ties_method = "average"),
  ) |>
  ungroup()

# just going to write this out independently
cumulus$blob_write(
  df_mam_mixed_w_rp,
  container = "projects",
  name = "ds-aa-afg-drought/processed/vector/df_combined_era5_seas5.parquet"
)
