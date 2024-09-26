"
This script evaluates various environmental indicators for their utility as
trigger metrics in Faryab Province in Afghanistna. The triggers are evaluated:
  
Forecasted:
  SEAS5 – cumulative predicted rainfall for MAM predicted form Nov-March
Observational:
  CHIRPS – Monthly rainfall: November - May
  SWE – Monthly SWE: November – May
  NDVI – Monthly NDVI: March- May
  Combined Monthly CHIRPS & SWE: March- May

For each indicator we determine the worst years on record (drought-wise) across
each monitoring moment/time-step. We then see how well the worst years at each
of these indicator-timestep combinations line up with the worst years
calculated according to ASI Dekad 3 calculation. We look at ASI Dekad 3 of May
because ASI is a measure of scale of drought at a geographical level based on
NDVI and crop specific coefficients. May Dekad 3 is after the growing season
and just as the harvest begins for spring wheat, so is a good time to measure
this cumulative indicator. It corresponded with the EMDAT dataset on historical
drought in Faryab.


The heatmap & rainfall time-series produced here are included in this
[slide deck](https://docs.google.com/presentation/d/1pfqpEGx-MB_-1A8PiCnDmcOwifUQ-EXyTDuqQyBiw1c/edit#slide=id.g2fe5782e44e_0_45)
"

box::use(
  ../R/blob_connect
)

box::use(
  dplyr,
  forcats,
  gg = ggplot2,
  gghdx,
  janitor,
  lubridate,
  purrr,
  readr,
  scales,
  stats,
  stringr,
  tidyr
)

gghdx$gghdx()

#############################
#### PERFORMANCE METRICS ####
#############################

# We calculate performance in a specific way. It is by passing in a dataset
# that has years when we would want to activate, `y`, and and years when we would
# activate for a certain indicator, `x`. These are then used to calculate precision
# and recall. We also use bootstrapping to test if we are better than random.
#
# Since we have a set return period for the historical activation data, and also
# the same desired activation rate as the return period, in this instance, sum(x)
# and sum(y) are equal, so precision and recall are equal.

# functions to calculate metrics
precision <- function(x, y) {
  sum(x & y) / sum(x)
}

recall <- function(x, y) {
  sum(x & y) / sum(y)
}

#' Compares level of metric (calcualted by `fun`) to "random" values
#' by bootstrapping `y` 1,000 times. Returns the % of times the actual metric is higher than the
#' random. Expect 95% of the time or more we are better than random!
#'
#' If the values are the same, considers it "good" (better than random).
metric_calc <- function(x, y, fun, indicator) {
  threshold <- fun(x = x, y = y)
  pct_better <- purrr$map_lgl(
    .x = 1:1000,
    .f = \(a) fun(x = sample(x, size = length(x), replace = FALSE), y = y) <= threshold
  ) |> 
    mean()
  
  metric_name <- deparse(substitute(fun))
  
  dplyr$tibble(
    "{metric_name}" := threshold,
    "{metric_name}_beq_random" := pct_better
  )
}

calc_metrics <- function(df, x, y) {
  df |> 
    dplyr$summarise(
      precision = metric_calc({{ x }}, {{ y }}, precision),
      recall = metric_calc({{ x }}, {{ y }}, recall),
      indicator = unique(indicator),
      .groups = "drop"
    ) |> 
    tidyr$unnest(
      cols = tidyr$everything()
    )
}

##############
#### DATA ####
##############

# blob processed data
df_chirps <- blob_connect$read_blob_file("DF_ADM1_CHIRPS") |> 
  dplyr$filter(
    ADM1_NAME == "Faryab"
  ) |> 
  dplyr$group_by(
    mo = lubridate$month(date)
  ) |> 
  dplyr$mutate(
    chirps_z = (value - mean(value)) / stats$sd(value)
  ) |>
  dplyr$ungroup()

df_seas5 <- blob_connect$read_blob_file("DF_FARYAB_SEAS5") |> 
  dplyr$mutate(
    valid_month = lubridate$month(valid_date),
    valid_year = lubridate$year(valid_date)
  )

df_snow <- blob_connect$read_blob_file("DF_ADM1_MODIS_SNOW") |> 
  dplyr$filter(
    ADM1_NAME == "Faryab",
    parameter == "NDSI_Snow_Cover_mean"
  ) |> 
  dplyr$group_by(
    mo = lubridate$month(date)
  ) |> 
  dplyr$mutate(
    swe_z = (value - mean(value)) / stats$sd(value)
  ) |> 
  dplyr$ungroup()

# not used later on because the time series is much more limited than the rest
df_smi <- blob_connect$read_blob_file("DF_ADM1_SMI", skip = 1) |> 
  dplyr$slice(-1) |>  # first line is just an extra line of headers
  dplyr$transmute(
    date = as.Date(paste0(Province, "-01")),
    year = lubridate$year(date),
    month = lubridate$month(date),
    smi = Faryab
  )

# FAO GIEWS data
df_ndvi <- readr$read_csv("https://eo.apps.fao.org/asis/data/country/AFG/GRAPH_NDVI_AGRI/ndvi_adm1_data.csv") |> 
  dplyr$filter(Province == "Faryab")
df_vhi <- readr$read_csv("https://www.fao.org/giews/earthobservation/asis/data/country/AFG/MAP_NDVI_ANOMALY/DATA/vhi_adm1_dekad_data.csv") |> 
  dplyr$filter(Province == "Faryab")
df_asi <- readr$read_csv("https://www.fao.org/giews/earthobservation/asis/data/country/AFG/MAP_ASI/DATA/ASI_Dekad_Season1_data.csv") |>
  dplyr$filter(Province == "Faryab")

# EMDAT
df_emdat <- blob_connect$read_blob_file("DF_EMDAT")

# Production data
df_prod_init <- blob_connect$read_blob_file("DF_PRODUCTION_DATA", skip = 3)

names_2 <- as.character(df_prod_init[1,4:ncol(df_prod_init)])

df_prod <- df_prod_init |> 
  dplyr$slice(
    2
  ) |> 
  dplyr$select(
    -c(1:3)
  ) |> 
  tidyr$pivot_longer(
    cols = tidyr$everything(),
    values_transform = as.numeric
  ) |> 
  dplyr$mutate(
    name = ifelse(
      stringr$str_detect(name, "\\.\\.\\."),
      NA_character_,
      name
    )
  ) |> 
  tidyr$fill(
    name
  ) |> 
  dplyr$mutate(
    metric = names_2
  )

##########################
#### FIND WORST YEARS ####
##########################

# worst end of season vegetation health index
df_vhi_wy <- df_vhi |> 
  dplyr$filter(
    Month == "05",
    Dekad == 3
  ) |> 
  dplyr$arrange(
    Data
  ) |> 
  dplyr$slice(
    1:8 # 1 in 5 year RP
  ) |> 
  dplyr$transmute(
    indicator = "VHI",
    year = Year
  )

# look from 2000 onward
df_vhi_wy_2000 <- df_vhi |> 
  dplyr$filter(
    Month == "05",
    Dekad == 3,
    Year >= 2000
  ) |> 
  dplyr$arrange(
    Data
  ) |> 
  dplyr$slice(
    1:5
  ) |> 
  dplyr$transmute(
    indicator = "VHI",
    year = Year
  )

df_seas5_wy <- df_seas5 |> 
  dplyr$filter(
    valid_month %in% 3:5
  ) |> 
  dplyr$group_by(
    pub_date,
    valid_year
  ) |> 
  dplyr$filter(
    dplyr$n() == 3
  ) |> 
  dplyr$summarize(
    precipitation = mean(precip_mm_day),
    leadtime = min(leadtime),
    pub_month = lubridate$month(min(pub_date)),
    .groups = "drop"
  ) |> 
  dplyr$filter(
    valid_year >= 1984
  ) |> 
  dplyr$group_by(
    leadtime
  ) |> 
  dplyr$arrange(
    precipitation,
    .by_group = TRUE
  ) |>
  dplyr$slice(
    1:8 # 1 in 5 year RP
  ) |> 
  dplyr$ungroup() |> 
  dplyr$transmute(
    indicator = "SEAS5",
    year = valid_year,
    leadtime,
    pub_month
  )

df_ndvi_wy <- df_ndvi |>
  dplyr$filter(
    Month %in% c("03", "04", "05")
  ) |> 
  dplyr$group_by(
    Year
  ) |> 
  dplyr$mutate(
    ndvi_cum = cumsum(Data),
    ndvi_cum_avg = cumsum(Data_long_term_Average),
    ndvi_cum_anom = ndvi_cum / ndvi_cum_avg
  ) |> 
  dplyr$group_by(
    Month,
    Dekad
  ) |> 
  dplyr$arrange(
    ndvi_cum,
    .by_group = TRUE
  ) |> 
  dplyr$slice(
    1:8 # 1 in 5 year RP
  ) |> 
  dplyr$ungroup() |> 
  dplyr$transmute(
    indicator = "NDVI",
    month = as.numeric(Month),
    dekad = as.numeric(Dekad),
    year = Year
  )

# since 2000
NDVI <- df_ndvi |>
  dplyr$filter(
    Month %in% c("03", "04", "05"),
    Year >= 2000
  ) |> 
  dplyr$group_by(
    Year
  ) |> 
  dplyr$mutate(
    ndvi_cum = cumsum(Data),
    ndvi_cum_avg = cumsum(Data_long_term_Average),
    ndvi_cum_anom = ndvi_cum / ndvi_cum_avg
  ) |> 
  dplyr$group_by(
    Month,
    Dekad
  ) |> 
  dplyr$arrange(
    ndvi_cum,
    .by_group = TRUE
  ) |> 
  dplyr$slice(
    1:5
  ) |> 
  dplyr$ungroup() |> 
  dplyr$transmute(
    indicator = "NDVI",
    month = as.numeric(Month),
    dekad = as.numeric(Dekad),
    year = Year
  ) |> 
  dplyr$filter(
    month == 5,
    dekad == 3
  )

df_chirps_wy <- df_chirps |> 
  dplyr$mutate(
    month = lubridate$month(date),
    year = lubridate$year(date)
  ) |> 
  dplyr$filter(
    month %in% 1:5,
    year >= 1984
  ) |> 
  dplyr$group_by(
    year
  ) |> 
  dplyr$mutate(
    precipitation_cum = cumsum(value)
  ) |>
  dplyr$group_by(
    month
  ) |> 
  dplyr$arrange(
    precipitation_cum,
    .by_group = TRUE
  ) |> 
  dplyr$slice(
    1:8 # 1 in 5 year RP
  ) |> 
  dplyr$ungroup() |> 
  dplyr$transmute(
    indicator = "CHIRPS",
    month,
    year
  )

df_chirps_wy_2000 <- df_chirps |> 
  dplyr$mutate(
    month = lubridate$month(date),
    year = lubridate$year(date)
  ) |> 
  dplyr$filter(
    month %in% 1:5,
    year >= 2000
  ) |> 
  dplyr$group_by(
    year
  ) |> 
  dplyr$mutate(
    precipitation_cum = cumsum(value)
  ) |>
  dplyr$group_by(
    month
  ) |> 
  dplyr$arrange(
    precipitation_cum,
    .by_group = TRUE
  ) |> 
  dplyr$slice(
    1:5
  ) |> 
  dplyr$ungroup() |> 
  dplyr$transmute(
    indicator = "CHIRPS",
    month,
    year
  )

# look at CHIRPS just across MAM

df_chirps_mam_wy <- df_chirps |> 
  dplyr$mutate(
    month = lubridate$month(date),
    year = lubridate$year(date)
  ) |> 
  dplyr$filter(
    month %in% 3:5,
    year >= 1984
  ) |> 
  dplyr$group_by(
    year
  ) |> 
  dplyr$mutate(
    precipitation_cum = cumsum(value)
  ) |>
  dplyr$group_by(
    month
  ) |> 
  dplyr$arrange(
    precipitation_cum,
    .by_group = TRUE
  ) |> 
  dplyr$slice(
    1:8 # 1 in 5 year RP
  ) |> 
  dplyr$ungroup() |> 
  dplyr$transmute(
    indicator = "CHIRPS",
    month,
    year
  )

df_emdat_wy <- df_emdat |> 
  dplyr$transmute(
    indicator = "EMDAT",
    year = c(2000, 2001, 2002, 2007, 2008, 2011, 2018, 2019, 2021, 2022, 2023),
    faryab = stringr$str_detect(`Location (Affected provinces)`, "Faryab")
  ) 

# used for potential monitoring
df_asi_dek_wy <- df_asi |> 
  dplyr$mutate(
    month = as.numeric(Month),
    dekad = Dekad,
    year = Year
  ) |> 
  dplyr$filter(
    month <= 5
  ) |> 
  dplyr$group_by(
    month,
    dekad
  ) |> 
  dplyr$arrange(
    dplyr$desc(Data),
    .by_group = TRUE
  ) |> 
  dplyr$slice(
    1:8 # 1 in 5 year RP
  ) |> 
  dplyr$transmute(
    indicator = "ASI",
    year = Year
  ) |> 
  dplyr$ungroup()


df_asi_wy <- df_asi |>
  dplyr$filter(
    Month == "05",
    Dekad == 3
  ) |> 
  dplyr$arrange(
    dplyr$desc(Data)
  ) |> 
  dplyr$slice(
    1:8 # 1 in 5 year RP
  ) |> 
  dplyr$transmute(
    indicator = "ASI",
    year = Year
  )

df_asi_wy_2000 <- df_asi |>
  dplyr$filter(
    Month == "05",
    Dekad == 3,
    Year >= 2000
  ) |> 
  dplyr$arrange(
    dplyr$desc(Data)
  ) |> 
  dplyr$slice(
    1:5
  ) |> 
  dplyr$transmute(
    indicator = "ASI",
    year = Year
  )

df_snow_wy <- df_snow |> 
  dplyr$mutate(
    month = lubridate$month(date)
  ) |> 
  dplyr$filter(
    month %in% c(1:5, 11:12)
  ) |> 
  dplyr$group_by(month) |> 
  dplyr$slice_min(
    order_by = value,
    n = 5,
    with_ties = FALSE
  ) |> 
  dplyr$mutate(
    year = ifelse(month > 5, lubridate$year(date) + 1, lubridate$year(date))
  ) |> 
  dplyr$ungroup() |> 
  dplyr$transmute(
    indicator = "SWE",
    month,
    year
  )

df_smi_wy <- df_smi |> 
  dplyr$group_by(
    month
  ) |> 
  dplyr$arrange(
    smi,
    .by_group = TRUE
  ) |> 
  dplyr$slice(
    1:2
  ) |> 
  dplyr$ungroup() |> 
  dplyr$transmute(
    indicator = "SMI",
    month,
    year
  )

# CHIRPS AND SWE COMBINATION

df_combo_wy <- df_chirps |> 
  dplyr$select(
    date,
    chirps_z
  ) |> 
  dplyr$left_join(
    dplyr$select(
      df_snow,
      date,
      swe_z
    )
  ) |>
  dplyr$mutate(
    year = lubridate$year(date),
    month = lubridate$month(date),
    combo = chirps_z + swe_z
  ) |> 
  dplyr$filter(
    year >= 2000,
    month %in% 1:5
  ) |> 
  dplyr$group_by(
    month
  ) |> 
  dplyr$arrange(
    combo
  ) |> 
  dplyr$slice(
    1:5
  )

# look at worst years just for production on rainfed agri.
df_prod_wy <- df_prod |> 
  dplyr$filter(
    stringr$str_detect(metric, "Prod"),
    stringr$str_detect(name, "Rainfed")
  ) |> 
  dplyr$arrange(
    value
  ) |> 
  dplyr$slice(1:3)

#####################################
#### CREATE SOME VALIDATION SETS ####
#####################################

# seasonal forecasts
df_val <- dplyr$tibble(
  year = 1984:2024,
  vhi = year %in% df_vhi_wy$year,
  asi = year %in% df_asi_wy$year,
  emdat = year %in% df_emdat_wy$year,
  asi_2000 = year %in% df_asi_wy_2000$year
)

#################################
#### EXPLORATION OF TRIGGERS ####
#################################

# Seasonal forecasts
df_seas5_perf <- df_seas5_wy |>
  dplyr$mutate(
    worst_year = TRUE
  ) |> 
  tidyr$complete(
    year = 1984:2024,
    pub_month = c(11, 12, 1:3),
    fill = list(
      indicator = "SEAS5",
      worst_year = FALSE
    )
  ) |> 
  dplyr$left_join(
    df_val,
    by = "year"
  ) |>
  dplyr$group_by(
    pub_month
  ) |> 
  calc_metrics(
    x = worst_year,
    y = asi
  )


# CHIRPS

df_chirps_perf <- df_chirps_wy |> 
  dplyr$mutate(
    worst_year = TRUE
  ) |> 
  tidyr$complete(
    year = 1984:2024,
    month = 1:5,
    fill = list(
      indicator = "CHIRPS",
      worst_year = FALSE
    )
  ) |> 
  dplyr$left_join(
    df_val,
    by = "year"
  ) |>
  dplyr$group_by(
    month
  ) |> 
  calc_metrics(
    x = worst_year,
    y = asi
  )

# performance just looking at MAM
df_chirps_mam_perf <- df_chirps_mam_wy |> 
  dplyr$mutate(
    worst_year = TRUE
  ) |> 
  tidyr$complete(
    year = 1984:2024,
    month = 1:5,
    fill = list(
      indicator = "CHIRPS",
      worst_year = FALSE
    )
  ) |> 
  dplyr$left_join(
    df_val,
    by = "year"
  ) |>
  dplyr$group_by(
    month
  ) |> 
  calc_metrics(
    x = worst_year,
    y = asi
  )

# CHIRPS (from 2000)
df_chirps_wy_2000 |> 
  dplyr$mutate(
    worst_year = TRUE
  ) |> 
  tidyr$complete(
    year = 2000:2024,
    month = 1:5,
    fill = list(
      indicator = "CHIRPS",
      worst_year = FALSE
    )
  ) |> 
  dplyr$left_join(
    df_val,
    by = "year"
  ) |>
  dplyr$group_by(
    month
  ) |> 
  calc_metrics(
    x = worst_year,
    y = asi_2000
  )


# SNOW

df_snow_perf <- df_snow_wy |> 
  dplyr$mutate(
    worst_year = TRUE
  ) |> 
  tidyr$complete(
    year = 2000:2024,
    month = c(11:12, 1:3),
    fill = list(
      indicator = "SWE",
      worst_year = FALSE
    )
  ) |> 
  dplyr$left_join(
    df_val,
    by = "year"
  ) |>
  dplyr$group_by(
    month
  ) |> 
  calc_metrics(
    x = worst_year,
    y = asi_2000
  )

# ASI

df_asi_perf <- df_asi_dek_wy |> 
  dplyr$mutate(
    worst_year = TRUE
  ) |> 
  tidyr$complete(
    year = 1984:2024,
    month = 1:5,
    dekad = 1:3,
    fill = list(
      indicator = "ASI",
      worst_year = FALSE
    )
  ) |> 
  dplyr$left_join(
    df_val,
    by = "year"
  ) |>
  dplyr$group_by(
    month,
    dekad
  ) |> 
  calc_metrics(
    x = worst_year,
    y = asi
  )

# Combo
df_combo_perf <- df_combo_wy |> 
  dplyr$ungroup() |> 
  dplyr$mutate(
    worst_year = TRUE,
    indicator = "CHIRPS\n& SWE"
  ) |> 
  tidyr$complete(
    year = 2000:2024,
    month = 1:5,
    fill = list(
      indicator = "CHIRPS\n& SWE",
      worst_year = FALSE
    )
  ) |> 
  dplyr$left_join(
    df_val,
    by = "year"
  ) |> 
  dplyr$group_by(month) |> 
  calc_metrics(
    x = worst_year,
    y = asi_2000
  )

# NDVI

df_ndvi_perf <- df_ndvi_wy |> 
  dplyr$mutate(
    worst_year = TRUE
  ) |> 
  tidyr$complete(
    year = 1984:2024,
    month = 3:5,
    dekad = 1:3,
    fill = list(
      indicator = "NDVI",
      worst_year = FALSE
    )
  ) |> 
  dplyr$left_join(
    df_val,
    by = "year"
  ) |>
  dplyr$group_by(
    month,
    dekad
  ) |> 
  calc_metrics(
    x = worst_year,
    y = asi
  )

###########################
#### RAINFALL TIMELINE ####
###########################

df_chirps |>
  dplyr$mutate(
    month = factor(months(date, abbreviate = TRUE), levels = month.abb)
  ) |>
  gg$ggplot(
    mapping = gg$aes(x = month, y = value)
  ) +
  gg$geom_boxplot() +
  gg$labs(
    x = "",
    y = "Precipitation (mm)",
    title = "Distribution of monthly rainfall, 1984 to 2024, CHIRPS"
  )

###########################
#### JOINT PERFORMANCE ####
###########################

dplyr$bind_rows(
  df_chirps_perf,
  df_seas5_perf |> dplyr$rename(month = pub_month),
  df_ndvi_perf |> dplyr$filter(dekad == 3) |> dplyr$select(-dekad), # last dekad best performance
  df_snow_perf,
  df_combo_perf,
  df_asi_perf |> dplyr$filter(dekad == 3) |> dplyr$select(-dekad), # last dekad
) |> 
  dplyr$mutate(
    month_label = factor(month.name[month], levels = month.name[c(11:12, 1:5)])
  ) |> 
  gg$ggplot(
    mapping = gg$aes(
      x = indicator,
      y = forcats$fct_rev(month_label),
      fill = precision
    )
  ) +
  gg$geom_tile(
    linewidth = 2,
    color = "white"
  ) +
  gg$geom_text(
    mapping = gg$aes(
      label = scales$label_percent(accuracy = 1)(precision)
    ),
    check_overlap = TRUE,
    fontface = "bold",
    color = "white"
  ) +
  gg$labs(
    y = "",
    x = "",
    fill = "Precision/Recall",
    title = "How well can we predict worst years",
    subtitle = "Measured against ASI end-of-season (May)",
    caption = "Methodology compares how well a 1 in 5 year RP level threshold correlates\nto the the worst to 1 in 5 year level drought at the end of the spring wheat season as measured by ASIS"
  ) +
  gg$scale_fill_gradient(
    low = gghdx$hdx_hex("sapphire-ultra-light"),
    high = gghdx$hdx_hex("sapphire-dark"),
    labels = scales$label_percent(accuracy = 1),
    breaks = scales$trans_breaks(identity, identity, n = 3)
  ) +
  gg$theme(
    axis.text.x = gg$element_text(vjust = 1),
    axis.line.x = gg$element_blank(),
    panel.grid = gg$element_blank()
  )
