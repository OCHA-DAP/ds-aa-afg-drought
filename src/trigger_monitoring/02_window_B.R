
box::use(
  loaders = ../../R/load_funcs,
  dplyr[...],
  tidyr[...],
  stringr[...],
  glue[...],
  ggplot2[...],
  gghdx[...],
  forcats[...],
  readr[...],
  lubridate[...],
  purrr[...],
  ggrepel[...],
  cumulus,
  ggfx
)


gghdx()

IS_TEST_RUN <- c(T,F)[2]
YEAR_RUN <- ifelse(IS_TEST_RUN,2024,year(Sys.Date()))
AOI_ADM1 <- c("Takhar","Sar-e-Pul", "Faryab")

box::use(
  ../../R/utils,
  ./R_monitoring/wranglers,
  mload= ./R_monitoring/monitoring
)


# todo - standardzie version name
df_thresholds <- mload$load_window_b_thresholds(version = "20250408")
df_dist_params <-  mload$load_distribution_params(version = "20250408")
df_weighting <- utils$design_weights()$`20250401`

# historical data for plotting
dfz_historical_plot <-  mload$load_window_b_historical_plot_data(version = "20250408")


# Load indicator components -----------------------------------------------

## FAO: ASI & VHI ####
df_fao <- loaders$load_fao_vegetation_data()


# quick check
df_fao |>
  group_by(
    parameter
  ) |>
  filter(
    date == max(date)
  ) |>
  distinct(date,dekad)


df_fao_processed <- wranglers$process_fao_trigger_component(
  df = df_fao,
  aoi = AOI_ADM1,
  test = IS_TEST_RUN
  )

## ERA5 ####

df_era5_raw <- mload$load_raw_era5_trigger_component(test = IS_TEST_RUN)

### Soil Moisture #####

df_era5_sm_processed <- wranglers$process_era5_soil_moisture(df= df_era5_raw,valid_month = 3)


### Cumulative precip #####

df_era5_cumu_precip_processed <- wranglers$process_era5_cumu_precip_component(df = df_era5_raw, cutoff_month=3)

### Snow Cover ####

df_era5_snow_cover_processed <- wranglers$process_era5_snowcover_component(df = df_era5_raw)

## Mixed Forecast Observation  (SEAS5 + ERA5) ####

# load forecast data in
df_seas5 <- mload$load_seas5_trigger_component(test = IS_TEST_RUN)

df_mixed_fcast_obs_processed <- wranglers$aggregate_mixed_fcast_obs(
  df_fcast = df_seas5,
  df_observed = df_era5_raw
  )

# Create Composite Indicator ####

df_cdi_trigger <- bind_rows(
  df_fao_processed,
  df_era5_sm_processed,
  df_era5_cumu_precip_processed,
  df_era5_snow_cover_processed,
  df_mixed_fcast_obs_processed
)


# here we join the distribution parameters (1984-2024) to calculate z-score of
# 2025 data
df_cdi_trigger_indicators <- df_cdi_trigger |>
  left_join(
    df_dist_params
  ) |>
  mutate(
    zscore_raw=(value - mu)/sigma,
    zscore = ifelse(parameter != "asi",zscore_raw*-1,zscore_raw)
  ) |>
  left_join(
    df_weighting,by ="parameter"
  )


# a quick view - can help understand drivers
df_cdi_trigger_indicators |>
  arrange(adm1_name,desc(zscore))



df_cdi_agg <- df_cdi_trigger_indicators |>
  group_by(
    adm1_name, pub_mo_label
  ) |>
  summarise(
    cdi = weighted.mean(zscore,w = weight),.groups="drop"
  )

# Evaluate & Visualize Results ####

df_activation_status <- df_cdi_agg |>
  left_join(
    df_thresholds
  ) |>
  mutate(
    flag = cdi>=rv,
    status = fct_expand(ifelse(flag,"Activation","No Activation"),"Activation","No Activation")
  )


## Simple plot - Activation Status ####

# simple visualization of above
p_cdi <- df_activation_status |>
  ggplot(
    aes(x= adm1_name, y= cdi),
    width =0.2
  )+
  geom_point(
    aes(
      color=status,
    ) ,
    show.legend = c(color=TRUE)
  ) +
  scale_color_manual(
    values = c(
      `No Activation`="#55b284ff",
      `Activation` ="#F2645A"
    ),
    drop=F
  ) +
  geom_hline(
    aes(
      yintercept= rv),
    linetype="dashed",
    color="tomato"
  )+
  scale_y_continuous(
    limits=c(
      min(df_activation_status$cdi),
      ifelse(max(df_activation_status$cdi)>=max(df_activation_status$rv),
             max(df_activation_status$cdi),
             max(df_activation_status$rv)),
    expand = expansion(mult = c(0.1,0.1))
  )
  )+
  facet_wrap(
    ~adm1_name,
    scales = "free_x",
    nrow = 1,ncol=3
  )+
  labs(
    title = "Window B - Combined Drought Indicator",
    subtitle = glue("April {YEAR_RUN} Activation Moment"),
    caption = "Horizonal red dashed lines indicate trigger threshold level."
  )+
  theme(
    axis.title.x = element_blank(),
    title = element_text(size=16),
    plot.subtitle = element_text(size=16),
    legend.title = element_blank(),
    legend.text = element_text(size=15),
    axis.text.y = element_text(angle=90,size=15),
    strip.text = element_text(size= 16),
    axis.text.x = element_blank(),
    plot.caption = element_text(hjust=0, size =14)
  )



## Historical Line Plot #####
if(!IS_TEST_RUN){
  # will have to combine new 2025 indicators in
  dfz_historical_indicators_w_new <- bind_rows(
    dfz_historical_plot,
    # add 2025 indicator values
    df_cdi_trigger_indicators |>
      select(pub_mo_date,pub_mo_label,adm1_name,parameter,value, zscore)
  )

  # To the historical record of indicators (including 2025) add 2025 CDI
  # calculated indicator as well for plotting
    dfz_lineplot_prepped <- bind_rows(
      dfz_historical_indicators_w_new,
      # just some wrangling of 2025 CDI data so it fits format
      df_activation_status |>
        mutate(
          parameter = "cdi",
          pub_mo_date = as_date("2025-04-01")
        ) |>
        select(adm1_name, pub_mo_label,parameter,pub_mo_date,zscore =cdi,flag)
    )
}

if(IS_TEST_RUN){
  dfz_lineplot_prepped <- dfz_historical_plot

}

pal_historical <- c(
  "CDI" = "black",
  "ASI" = "#FBB4AE",
  "VHI" = "#CCEBC5",
  "Cumulative precip" ="#B3CDE3",
  "MAM precip (mixed obs forecast)" ="#DECBE4",
  # "Soil moisture" = "#FED9A6",
  "Soil moisture" = "#fec44f",
  # "Snow Cover" = "#FFFFCC"
  # "Snow Cover" = "#FFFF4C"
  "Snow Cover" = "#FFFF90"
  # "Snow Cover" = 'lightgrey'
  # "Snow Cover" = "yellow"
  # "Snow Cover" = "#ede89f"
)

dfz_plot <- dfz_lineplot_prepped |>
  mload$label_parameters() |>
  mutate(
    parameter_label = fct_relevel(fct_expand(parameter_label,names(pal_historical)),names(pal_historical)),
    yr_season = floor_date(pub_mo_date, "year"),
    yr_label = year(yr_season)
  )



dfz_plot |>
  mutate(
    yr_season = floor_date(pub_mo_date, "year")
  ) |>
  ggplot(
    aes(x = yr_season, y= zscore,group= parameter_label)

  )+

  ggfx$with_shadow(
  geom_line(
    aes(x = yr_season, y= zscore,group= parameter_label, color =parameter_label),
    alpha=1,
    linewidth = 1
  ),
  sigma = 1.0,
  x_offset = 0.5,
  y_offset = 0.25
  )+

  geom_hline(
    data= df_thresholds,
    aes(yintercept = rv),
    color = hdx_hex("tomato-dark"),
    linetype= "dashed", linewidth = 1
  )+
  ggfx$with_shadow(
    geom_line(
      data= dfz_plot |>
        filter(parameter == "cdi"),
      aes(x = yr_season, y= zscore,group= parameter_label),
      color = "black",
      linewidth = 1.3
    ),
    sigma = 2,
    x_offset = 0.5,
    y_offset = 0.25)+

  geom_point(
    data= dfz_plot |>
      filter(parameter == "cdi",year(yr_season)==2025,flag),
    aes(x = yr_season, y= zscore,group= parameter_label),
    # aes(x = yr_season, y= zscore,group= parameter),
    color = hdx_hex("tomato-light"),
    size = 7,
    alpha = 1
  )+
    geom_point(
      data= dfz_plot |>
        filter(parameter == "cdi",flag),
      aes(x = yr_season, y= zscore,group= parameter_label),
      color = hdx_hex("tomato-hdx"),
      size = 3, alpha = 0.7
    )+

  geom_point(
    data= dfz_plot |>
      filter(parameter == "cdi",year(yr_season)==2025,!flag),
    aes(x = yr_season, y= zscore,group= parameter_label),
    color = hdx_hex("sapphire-hdx"),
    size = 5, alpha = 1
  )+
  geom_label(
    data = df_thresholds |> mutate(parameter_label=NA),
    x= as_date("1992-11-01"),
    aes(y = rv, label = paste0("Threshold: " ,round(rv,2))),
    vjust = -0.5, #-0.5,         # Adjust to position above the line
    hjust = 0,            # Left-align text at 2025 position
    color = hdx_hex("tomato-dark"),     # Match line color
    size = 3,alpha=0.5
  )+
  geom_text_repel(
    data= dfz_plot |>
      filter(parameter == "cdi",flag) ,
    aes(label = yr_label),

    color = hdx_hex("tomato-hdx"),
    vjust= -2,
    size = 3.5,
    alpha =1
  )+

  scale_color_manual(values =pal_historical,drop = FALSE)+
  facet_wrap(
    ~adm1_name, scales= "free", ncol =1
  )+
  scale_x_date(
    date_labels = "%Y",
    breaks = seq.Date(
      from = as.Date("1985-01-01"),
      to = as.Date("2025-01-01"),
      by = "5 years"),
    expand = expansion(mult = c(0,.01)),
  )+
  labs(y= "Indicator anomaly")+

  theme(
    axis.title.x = element_blank(),
    axis.title.y = element_text(size=14),
    title = element_text(size=16),
    legend.key.width = unit(1,"cm"),
    plot.subtitle = element_text(size=16),
    legend.title = element_blank(),
    legend.text = element_text(size=12),
    axis.text.y = element_text(angle=90,size=10),
    strip.text = element_text(size= 12),
    axis.text.x = element_text(size=10),
    plot.caption = element_text(hjust=0, size =14)
  )+
  guides(linetype = guide_legend(override.aes = list(size = 10)))+
  labs(
    title = "Drought AA Afghanistan: 2025 April Monitoring",
    subtitle = "Red dashed line represents 5.2 year RP threshold by province"
  )
