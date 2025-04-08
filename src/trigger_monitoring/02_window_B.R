
box::use(
  # ../R/blob_connect,
  ../../R/utils,
  loaders = ../../R/load_funcs,
  # seas5 = ../R/seas5_utils,
  # loaders = ../R/load_funcs,
  dplyr[...],
  tidyr[...],
  stringr[...],
  glue[...],
  # glue[...],
  # janitor[...],
  # yardstick[...],
  ggplot2[...],
  gghdx[...],
  forcats[...],
  # ggrepel[...],
  # lubridate[...],
  # sf[...],
  readr[...],
  lubridate[...],
  purrr[...],
  ggrepel[...],
  # patchwork[...],
  cumulus
)
gghdx()
test_run <- c(T,F)[2]
year_run <- ifelse(test_run,2024,year(Sys.Date()))
AOI_ADM1 <- c("Takhar","Sar-e-Pul", "Faryab")

box::reload(utils)
box::use(
  ./R_monitoring/wranglers,
  mload= ./R_monitoring/monitoring
)
box::reload(mload)
box::reload(wranglers)
df_thresholds <- mload$load_window_b_thresholds()
df_dist_params <-  mload$load_distribution_params()
df_weighting <- utils$design_weights()$`20250401`

dfz_historical_plot <-  mload$load_window_b_historical_plot_data()


# Load indicator components -----------------------------------------------

## FAO: ASI & VHI ####
df_fao <- loaders$load_fao_vegetation_data()

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
  test = test_run
  )

## ERA5 ####

df_era5_raw <- mload$load_raw_era5_trigger_component(test = test_run)

### Soil Moisture #####

df_era5_sm_processed <- wranglers$process_era5_soil_moisture(df= df_era5_raw,valid_month = 3)


### Cumulative precip #####

df_era5_cumu_precip_processed <- wranglers$process_era5_cumu_precip_component(df = df_era5_raw, cutoff_month=3)

### Snow Cover ####

df_era5_snow_cover_processed <- wranglers$process_era5_snowcover_component(df = df_era5_raw)

## Mixed Forecast Observation  (SEAS5 + ERA5) ####

# load forecast data in
df_seas5 <- mload$load_seas5_trigger_component(test = test_run)

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

df_cdi_trigger_indicators <- df_cdi_trigger |>
  left_join(
    df_dist_params
  ) |>
  mutate(
    zscore=(value - mu)/sigma,
    zscore = ifelse(parameter != "asi",zscore*-1,zscore)
  ) |>
  left_join(
    df_weighting,by ="parameter"
  )

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
    subtitle = glue("April {year_run} Activation Moment"),
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


pal_historical <- c(
  "CDI" = "black",
  "ASI" = "#FBB4AE",
  "VHI" = "#CCEBC5",
  "Cumulative precip" ="#B3CDE3",
  "MAM precip (mixed obs forecast)" ="#DECBE4",
  "Soil moisture" = "#FED9A6",
  "Snow Cover" = "#FFFFCC"
)

if(!test_run){
  # will have to combine new 2025 indicators in
  dfz_plot1 <- bind_rows(
    dfz_historical_plot,
    df_cdi_trigger_indicators |>
      select(pub_mo_date,pub_mo_label,adm1_name,parameter,value, zscore)
  ) |>
    bind_rows(
      df_activation_status |>
        mutate(
          parameter = "cdi",
          pub_mo_date = as_date("2025-04-01")
        ) |>
        select(adm1_name, pub_mo_label,parameter,pub_mo_date,zscore =cdi,flag)
    ) |>
    mload$label_parameters()

}


dfz_plot <- dfz_plot1 |>
  mutate(
    parameter_label = fct_relevel(fct_expand(parameter_label,names(pal_historical)),names(pal_historical)),
    yr_season = floor_date(pub_mo_date, "year"),
    yr_label = year(yr_season)
  )

dfz_plot |>
  mutate(
    yr_season = floor_date(pub_mo_date, "year")
  ) |>
  filter(
    year(yr_season )==2025
  ) |>
  print(n=2021)
  filter(

  )

# NEED TO DYNAMICALLY SUPPLY COLOR OF CURRENT YEAR POINT.
# df_activation_status


dfz_plot$pub_mo_date |>
  range(na.rm=T)


dfz_plot |>
  mutate(
    yr_season = floor_date(pub_mo_date, "year")
  ) |>
  ggplot(
    aes(x = yr_season, y= zscore,group= parameter_label)

  )+
  # indicator components
  geom_line(
    # aes(color = parameter_label),
    aes(x = yr_season, y= zscore,group= parameter_label, color =parameter_label),
    alpha=1,
    linewidth = 0.6
  )+
  geom_line(
    data= dfz_plot |>
      filter(parameter == "cdi"),
    aes(x = yr_season, y= zscore,group= parameter_label),
    color = "black",
    linewidth = 1.3
  )+
  geom_point(
    data= dfz_plot |>
      filter(parameter == "cdi",flag),
    aes(x = yr_season, y= zscore,group= parameter_label),
    color = hdx_hex("tomato-hdx"),
    size = 3, alpha = 1
  )+
  geom_point(
    data= dfz_plot |>
      filter(parameter == "cdi",year(yr_season)==2025,flag),
    aes(x = yr_season, y= zscore,group= parameter_label),
    # aes(x = yr_season, y= zscore,group= parameter),
    color = hdx_hex("tomato-dark"),
    size = 5, alpha = 0.5
  )+
  geom_point(
    data= dfz_plot |>
      filter(parameter == "cdi",year(yr_season)==2025,!flag),
    aes(x = yr_season, y= zscore,group= parameter_label),
    # aes(x = yr_season, y= zscore,group= parameter),
    color = hdx_hex("sapphire-hdx"),
    size = 5, alpha = 1
  )+
  geom_hline(
    data= df_thresholds,
    aes(yintercept = rv),
    color = hdx_hex("tomato-dark"),
    linetype= "dashed"
  )+
  geom_label(
    data = df_thresholds |> mutate(parameter_label=NA),
    x= as_date("2025-06-01"),
    aes(y = rv, label = round(rv,2)),
    vjust = -0.5,         # Adjust to position above the line
    hjust = 0,            # Left-align text at 2025 position
    color = hdx_hex("tomato-dark"),     # Match line color
    size = 3
  )+
  geom_text_repel(
    data= dfz_plot |>
      filter(parameter == "cdi",flag) ,
    aes(label = yr_label),

    color = hdx_hex("tomato-hdx"),
    vjust= -2,
    size = 3,
    alpha =1
  )+
  # geom_text_repel(
  #   data= dfz_plot |>
  #     filter(parameter == "cdi",year(pub_mo_date)==2025),
  #   aes(label = yr_label),
  #   color = "blue",
  #   vjust= -2,
  #   size = 3,
  #   alpha =1
  # )+
  scale_color_manual(values =pal_historical,drop = FALSE)+
  facet_wrap(
    ~adm1_name, scales= "free", ncol =1
  )+
  scale_x_date(
    date_labels = "%%Y",
    date_breaks = "2 years",
    expand = expansion(mult = c(0,.09)),
    # expand = c(0,0)
  )+
  labs(y= "Indicator anomaly")+
  theme(
    axis.title.x = element_blank(),
    axis.title.y = element_text(size=14),
    title = element_text(size=16),
    plot.subtitle = element_text(size=16),
    legend.title = element_blank(),
    legend.text = element_text(size=8),
    axis.text.y = element_text(angle=90,size=10),
    strip.text = element_text(size= 12),
    axis.text.x = element_blank(),
    plot.caption = element_text(hjust=0, size =14)
  )
