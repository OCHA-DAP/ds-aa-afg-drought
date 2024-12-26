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
  janitor[clean_names],
  seas5 = ../R/seas5_utils,
  ../R/pg
)

SEASON_OF_INTEREST <- c(3,4,5)
AOI_ADM1 <- c(
  "Takhar",
  "Badakhshan",
  "Badghis",
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

if(WRITE_OUTPUT){
  cumulus$blob_write(
    df = df_seas5_rp_rv,
    name = "ds-aa-afg-drought/processed/vector/afg_SEAS5_thresholds.parquet",
    stage = "dev",
    container = "projects"
  )
}


# Now let's do the whole thing again, but this time remove Wakhan from
# Badkhshan. We think it's a bit of a different ecosystem w/ low population
# low operational presence and may be throwing the trigger off to an extent.

# to do this we have to look at admin 1 and run weighted zonal stats
# for good measure  i verified the results of this method in a gist:
# https://gist.github.com/zackarno/f562510b53d4acb9fc0f8a2b9c688b1c



# these are handy and came available after i wrote the top part
df_labels <- cumulus$blob_read(
  name = "admin_lookup.parquet",
  stage = "dev",
  container = "polygon"
) |>
  clean_names()


df_adm2_labels <- df_labels |>
  filter(
    adm0_name == "Afghanistan",
    adm1_pcode %in% df_adm1_labels_aoi$pcode
  )


df_adm2_pixel_counts <- pg$get_pixel_counts(
  adm_level =2,
  pcode = df_adm2_labels$adm2_pcode,
  ds_name = "seas5"
  )

df_pixel_counts_meta <- df_adm2_pixel_counts |>
  left_join(
    df_adm2_labels,
    by = c("iso3","adm_level","pcode" = "adm2_pcode")
    )



df_adm2_weights_no_wakhan <- df_pixel_counts_meta |>
  filter(adm2_name != "Wakhan") |>
  group_by(adm1_name, adm1_pcode) |>
  arrange(adm1_name) |>
  mutate(
    weights = n_upsampled_pixels/sum(n_upsampled_pixels)
  ) |>
  ungroup()

if(WRITE_OUTPUT){
  cumulus$blob_write(
    df = df_adm2_weights_no_wakhan,
    name = "ds-aa-afg-drought/processed/vector/weights_adm2_no_wakhan.parquet",
    stage = "dev",
    container = "projects"
  )
}

# Load SEAS 5 Forecast
pcode_wakhan <- df_adm2_labels |>
  filter(
    adm2_name=="Wakhan"
  ) |> pull(
    adm2_pcode
  )
df_seas5_adm2 <- tbl(con, "seas5") |>
  filter(
    iso3 == "AFG",
    adm_level ==2,

    pcode %in% df_adm2_labels$adm2_pcode,
    pcode!=pcode_wakhan
  ) |>

  collect() |>
  mutate(
    precipitation = mean *days_in_month(valid_date)
  )


df_seas5_with_weights <- df_seas5_adm2 |>
  left_join(
    df_adm2_weights_no_wakhan,
    by = c("iso3", "adm_level","pcode")
  )


df_seas5_custom_adm1 <- df_seas5_with_weights |>
  group_by(
    iso3, adm0_name, adm1_name, adm1_pcode, valid_date,issued_date,leadtime
  ) |>
  summarise(
    precipitation = weighted.mean(precipitation,w = weights),
    .groups="drop"
  )


df_seas5_custom_mam <- seas5$aggregate_forecast(
  df_seas5_custom_adm1,
  valid_months = SEASON_OF_INTEREST,
  by = c("iso3","adm0_name","adm1_name","adm1_pcode","issued_date")
)

df_seas5_custom_rps_historical <- df_seas5_custom_mam |>
  mutate(
    pub_mo = month(issued_date,label =T, abbr=T)
  ) |>
  group_by(iso3, adm1_name,adm1_pcode, pub_mo, leadtime) |>
  arrange(
    adm1_pcode,pub_mo,mm
  ) |>
  mutate(
    rank = row_number(),
    q_rank = rank/(max(rank)+1),
    rp_emp = 1/q_rank,

  ) |>
  arrange(adm1_pcode,pub_mo,mm) |>
  ungroup()



df_seas5_custom_rp_rv <- df_seas5_custom_rps_historical |>
  group_by(iso3, adm1_name,adm1_pcode, pub_mo, leadtime) |>
  reframe(
    rp_func = list(approxfun( rp_emp, mm,rule=2)), #interpolation function
    rp = 2:7, # calculate for RPs 2-7 - should give sufficient options
    rv = map_dbl(rp, rp_func)
  ) |>
  select(-rp_func) |>
  mutate(
    # tagging on a few columns in case i want to start compiling a thresholds
    # table with more indicators in future.
    parameter = "SEAS5 - MAM Forecast (Wakhan removed)",
    rp_type = "Empirical"
  )

if(WRITE_OUTPUT){
  cumulus$blob_write(
    df = df_seas5_custom_rp_rv,
    name = "ds-aa-afg-drought/processed/vector/afg_SEAS5_thresholds_wakhan_removed.parquet",
    stage = "dev",
    container = "projects"
  )
}



# Regional Thresholds -----------------------------------------------------


# 3. Create custom areas for monitoring:
# Scenario A: 2 groups
#
# - North Central: Faryab, Sar-e-Pul provinces
# - North East: Takhar, Badakshan
# Scenario B: 1 group (no Badakhshan)
# - Regional group: Faryab, Sar-e-Pul, Takhar



# at time of writing noticed issue in parquet file where some iso3s have only
# admin 1 or admin 2 labels. For example AFG has only admin 2! Since i expect
# changes to this file to deal with it I'll just use the postgres db for the
# admin 1 lables

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

# get forecast for all areas in potential AOI
df_seas5_adm1 <- tbl(con, "seas5") |>
  filter(
    iso3 == "AFG",
    adm_level ==1,
    pcode %in% df_adm1_labels_aoi$pcode
  ) |>
  collect() |>
  mutate(
    precipitation = mean *days_in_month(valid_date)
  )


# get pixel counts at admin level for same areas
df_adm1_pixel_counts <- pg$get_pixel_counts(
  adm_level = 1,
  pcode= df_adm1_labels_aoi$pcode,
  ds_name = "seas5"
)

# label pixel count data
df_adm1_pixel_counts_meta <- df_adm1_pixel_counts |>
  left_join(
    df_adm1_labels_aoi,
    by = c("iso3","pcode" = "pcode")
  )


# scenario A weights
df_adm1_weights_a <- df_adm1_pixel_counts_meta|>
  filter(adm1_name!= "Badghis") |>
  mutate(
    weights = n_upsampled_pixels/sum(n_upsampled_pixels)
  ) |>
  mutate(
    parameter ="adm1 weights (4 admins)"
  )

df_adm1_weights_b <- df_adm1_weights_a |>
  filter(adm1_name!= "Badakhshan") |>
  mutate(
    weights = n_upsampled_pixels/sum(n_upsampled_pixels)
  )

# if we write out these admin 1 weights we don't have to faff around
# with accessing so many distinct end points return period notebooks alter
if(WRITE_OUTPUT){
  cumulus$blob_write(
    df = df_adm1_weights_a, # this is actually the only one needed for later
    name = "ds-aa-afg-drought/processed/vector/weights_adm1_all_admins.parquet",
    stage = "dev",
    container = "projects"
  )
}

pcode_badghis <-  "AF31"
pcode_badakhshan <- "AF17"

# get seasonal forecast values re-aggregated to scenario A groups
df_seas5_grouped_weighted_a <- df_seas5_adm1|>
  filter(!pcode %in% pcode_badghis) |>
  left_join(
    df_adm1_weights_a
  ) |>
  mutate(
    region = ifelse(adm1_name %in% c("Faryab","Sar-e-Pul"),
                    "North Central","North East")
  ) |>
  group_by(
    iso3, region, valid_date,issued_date,leadtime
  ) |>
  summarise(
    precipitation = weighted.mean(precipitation,w = weights),
    .groups="drop"
  )


# get seasonal forecast values re-aggregated to scenario B groups
df_seas5_grouped_weighted_b <- df_seas5_adm1 |>
  filter(!pcode %in% c(pcode_badghis,pcode_badakhshan)) |>
  left_join(
    df_adm1_weights_b,
    by = c("iso3","pcode")
  ) |>
  group_by(
    iso3, valid_date,issued_date,leadtime
  ) |>
  summarise(
    precipitation = weighted.mean(precipitation,w = weights),
    .groups="drop"
  )


# Aggregate these both to MAM seaason
df_seas5_region_mam_a <- seas5$aggregate_forecast(
  df_seas5_grouped_weighted_a,
  valid_months = SEASON_OF_INTEREST,
  by = c("iso3","region","issued_date")
)

df_seas5_region_mam_b <- seas5$aggregate_forecast(
  df_seas5_grouped_weighted_b,
  valid_months = SEASON_OF_INTEREST,
  by = c("iso3","issued_date")
)


df_mam_ranked_empirical_rps_a <- df_seas5_region_mam_a |>
  mutate(
    pub_mo = month(issued_date,label =T, abbr=T)
  ) |>
  group_by(iso3,region, pub_mo, leadtime) |>
  arrange(
    region,pub_mo,mm
  ) |>
  mutate(
    rank = row_number(),
    q_rank = rank/(max(rank)+1),
    rp_emp = 1/q_rank,

  ) |>
  arrange(region,pub_mo,mm) |>
  ungroup()

df_mam_ranked_empirical_rps_b <- df_seas5_region_mam_b |>
  mutate(
    pub_mo = month(issued_date,label =T, abbr=T)
  ) |>
  group_by(iso3, pub_mo, leadtime) |>
  arrange(
    pub_mo,mm
  ) |>
  mutate(
    rank = row_number(),
    q_rank = rank/(max(rank)+1),
    rp_emp = 1/q_rank,

  ) |>
  arrange(pub_mo,mm) |>
  ungroup()



df_seas5_rps_interpolated_a <- df_mam_ranked_empirical_rps_a |>
  group_by(iso3, region, pub_mo, leadtime) |>
  reframe(
    rp_func = list(approxfun( rp_emp, mm,rule=2)), #interpolation function
    rp = 2:7, # calculate for RPs 2-7 - should give sufficient options
    rv = map_dbl(rp, rp_func)
  ) |>
  select(-rp_func) |>
  mutate(
    # tagging on a few columns in case i want to start compiling a thresholds
    # table with more indicators in future.
    parameter = "SEAS5 - MAM Forecast (Regional 2 groups)",
    rp_type = "Empirical"
  )

df_seas5_rps_interpolated_b <- df_mam_ranked_empirical_rps_b |>
  group_by(iso3, pub_mo, leadtime) |>
  reframe(
    rp_func = list(approxfun( rp_emp, mm,rule=2)), #interpolation function
    rp = 2:7, # calculate for RPs 2-7 - should give sufficient options
    rv = map_dbl(rp, rp_func)
  ) |>
  select(-rp_func) |>
  mutate(
    # tagging on a few columns in case i want to start compiling a thresholds
    # table with more indicators in future.
    parameter = "SEAS5 - MAM Forecast (regional 1 group)",
    rp_type = "Empirical"
  )

if(WRITE_OUTPUT){
  cumulus$blob_write(
    df = df_seas5_rps_interpolated_a,
    name = "ds-aa-afg-drought/processed/vector/afg_SEAS5_thresholds_regional_grouped_2.parquet",
    stage = "dev",
    container = "projects"
  )
  cumulus$blob_write(
    df = df_seas5_rps_interpolated_b,
    name = "ds-aa-afg-drought/processed/vector/afg_SEAS5_thresholds_regional_grouped_1.parquet",
    stage = "dev",
    container = "projects"
  )
}
