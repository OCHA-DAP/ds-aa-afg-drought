library(tidyverse)
library(sf)
library(janitor)

zf <- "afg_admbnda_agcho.zip"
zf_vp <- paste0("/vsizip/",zf)

gdf_adm2 <- sf::st_read(zf_vp,"afg_admbnda_adm2_agcho_20211117") |>
  janitor::clean_names() |>
  dplyr::select(matches("adm\\d_[pe]"))
gdf_adm1 <- sf::st_read(zf_vp,"afg_admbnda_adm1_agcho_20211117") |>
  janitor::clean_names() |>
  dplyr::select(matches("adm\\d_[pe]"))


df_adm2_w_area <- gdf_adm2 %>%
  mutate(
    area = st_area(.)
  ) |>
  group_by(adm1_pcode, adm1_en) %>%
  mutate(
    adm1_area = sum(area)
  ) |>
  ungroup() |>
  mutate(
    pct_area = area / adm1_area
  ) |>
  st_drop_geometry()
chirps_url <- "https://data.humdata.org/dataset/3b5e8a5c-e4e0-4c58-9c58-d87e33520e08/resource/a8c98023-e078-4684-ade3-9fdfd66a1361/download/afg-rainfall-adm2-full.csv"
# download zip from url
download.file(chirps_url, "afg-rainfall-adm2-full.csv")
df_chirps_adm2 <- read_csv("afg-rainfall-adm2-full.csv")
df_chirps_adm2 <- df_chirps_adm2[-1,] |>
  clean_names() |>
  type_convert()

df_chirps_adm2$date |> range()

df_chirps_monthly_adm2 <- df_chirps_adm2 |>
  mutate(
    mo_date = floor_date(date,"month"),.before = "date"
  ) |>
    group_by(
      across(
        matches("adm\\d_[pe]")
      ),
      mo_date
    ) |>
  summarise(
    precip = sum(rfh)
  ) |>
  left_join(
    df_adm2_w_area
  )

df_chirps_monthly_adm1 <- df_chirps_monthly_adm2 |>
  group_by(
      across(
        matches("adm[01]_[pe]")
      ),
      mo_date
    ) |>
  summarise(
    precip = weighted.mean(x= as.numeric(precip), w=as.numeric(pct_area)),
    .groups="drop"
  )

df_chirps_yearly_adm1 <- df_chirps_monthly_adm1 |>
  group_by(
    across(
      matches("adm\\d_[pe]")
    ),
    yr_date = floor_date(mo_date, "year")
  ) |>
  summarise(
    precip = sum(precip)
  )

baseline_years <- c(1981:2020)

yearly_baseline_avg <- df_chirps_yearly_adm1 |>
  filter(
    year(yr_date) %in% baseline_years
  ) |>
  group_by(
  across(
    matches("adm\\d_[pe]")
  )
  ) |>
  summarise(
    avg_precip = mean(precip)
  )
df_chirps_adm1_anomaly <- df_chirps_yearly_adm1 |>
  left_join(
    yearly_baseline_avg
  ) |>
  mutate(
    anom_abs = precip - avg_precip
  )

df_chirps_adm1_anomaly |>
  filter(year(yr_date) %in% c(2020:2023)) |>
  group_by(
    yr_date
  ) |>
  arrange(
    yr_date,
    desc(-anom_abs)
  ) |>
  mutate(
    yr = as_factor(year(yr_date)),
    rank = row_number()
  ) |>
  ggplot(
    aes(
      x= reorder(adm1_en,anom_abs),
      y= anom_abs,
      fill= rank
    )
  )+
  geom_bar(
    stat="identity"
  )+
  scale_fill_continuous(type = "viridis",direction =-1)+
  coord_flip()+
  facet_wrap(~yr, scales = "free")


gdf_adm1_ranked <- gdf_adm1 |>
  left_join(
    df_chirps_adm1_anomaly |>
      filter(year(yr_date) %in% c(2020:2023)) |>
      group_by(
        yr_date
      ) |>
      arrange(
        yr_date,
        desc(-anom_abs)
      ) |>
      mutate(
        yr = as_factor(year(yr_date)),
        rank = row_number(),
        top5_dry = rank %in% c(1:7),
        top5_anom = if_else(top5_dry,anom_abs,NA_real_)
      )
  )


limit <- max(abs(gdf_adm1_ranked$top5_anom)) * c(-1, 1)
library(ggfx)

ggplot()+
  geom_sf(
    data= gdf_adm1_ranked,
    aes(fill = anom_abs,color = top5_dry),
    show.legend = c(color =FALSE, fill=TRUE)
  )+
  scale_color_manual(values= c("black","red"))+
  scale_fill_distiller(type = "div", limit = limit, direction=1)+
  facet_wrap(~yr)

gdf_top5_diss <- gdf_adm1_ranked |>
  group_by(yr) |>
  filter(top5_dry) |>
  summarise()

library(gghdx)
gghdx()
ggplot()+
  geom_sf(
    data= gdf_adm1_ranked,
    aes(fill = anom_abs),
    show.legend = c(color =FALSE, fill=TRUE)
  )+
  with_shadow(
    geom_sf(
      data = gdf_top5_diss,
      # aes(fill= diff),
      fill = NA,
      alpha = 1,
      color = "black",
      lwd = 0.7
    ),
    sigma = 3,
    x_offset = 0.5,
    y_offset = 0.25
  ) +
  scale_fill_gradient2(low = "#FD7446", high = "#709AE1") +
  # scale_fill_distiller(type = "div", limit = limit, direction=1)+
  facet_wrap(~yr)

gdf_adm1_ranked_overall<- gdf_adm1_ranked |>
  mutate(
    weights = case_when(
      yr ==2020~0.15,
      yr==2021~0.2,
      yr==2022~0.3,
      yr==2023~0.35

    )
  ) |>
  group_by(
    across(matches("adm\\d_[pe]"))
  ) |>
  summarise(
    weighted_anom = weighted.mean(x= anom_abs, w=weights)
  )

gdf_adm1_ranked_overall |>
arrange(
  desc(-weighted_anom)
) |>
  mutate(
    # yr = as_factor(year(yr_date)),
    rank = row_number(),
    top5_dry = rank %in% c(1:7),
    top5_anom = if_else(top5_dry,weighted_anom,NA_real_)
  )
ggplot()+
  geom_sf(
    data= gdf_adm1_ranked_overall,
    aes(fill = weighted_anom),
    show.legend = c(color =FALSE, fill=TRUE)
  )+
  # with_shadow(
  #   geom_sf(
  #     data = gdf_top5_diss,
  #     # aes(fill= diff),
  #     fill = NA,
  #     alpha = 1,
  #     color = "black",
  #     lwd = 0.7
  #   ),
  #   sigma = 3,
  #   x_offset = 0.5,
  #   y_offset = 0.25
  # ) +
  scale_fill_gradient2(low = "#FD7446", high = "#709AE1")
  # scale_fill_distiller(type = "div", limit = limit, direction=1)+



ggplot()+
  geom_sf(
    data= gdf_adm1_ranked,
    aes(fill = top5_dry)
  )+
  facet_wrap(~yr)


# IPC ---------------------------------------------------------------------
