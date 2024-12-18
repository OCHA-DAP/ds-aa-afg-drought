
library(sf)
library(tidyverse)
library(gghdx)
library(glue)
library(ggiraph)
library(glue)
library(rgee)
library(tidyrgee) # recommend github verison : devtools::install_github("r-tidy-remote-sensing/tidyrgee")
library(logger)
# ee_check()
ee_Initialize()
aoi_adm1 <- c(
  "Takhar",
  "Badakhshan",
  "Badghis",
  "Sar-e-Pul" ,
  "Faryab"
)

"total_precipitation"

# ic_era <- ee$ImageCollection("ECMWF/ERA5_LAND/DAILY_AGGR")
ic_era_monthly <- ee$ImageCollection("ECMWF/ERA5/MONTHLY")
ic_temp_k <- ic_era_monthly$select(list("mean_2m_air_temperature","total_precipitation"))

ic_temp_c <- ic_temp_k$map(function(img){
  img$subtract(273.15)$
    copyProperties(
      img, img$propertyNames()
    )
})

log_info("creating tidy image collection")
tic_temp_c <- as_tidyee(ic_temp_k)


adm1_fc <- ee$FeatureCollection("FAO/GAUL_SIMPLIFIED_500m/2015/level1")
adm1_afghanistan <- adm1_fc$filter(ee$Filter$eq("ADM0_NAME", "Afghanistan"))
fc_filtered <- adm1_afghanistan$filter(
  ee$Filter$inList("ADM1_NAME", aoi_adm1)
)

log_info("Running Zonal Stats")
df_era5_temp <- ee_extract_tidy(
  x = tic_temp_c,
  y=fc_filtered,
  stat = "mean",
  scale = 27830
)

log_info("Writing outputs")
readr::write_csv(df_era5_temp,"mean_2m_air_temperature_total_precipitation_era5_monthly.csv")

cumulus::blob_write(
  df_era5_temp,
    stage = "dev" ,
    name = "ds-aa-afg-drought/processed/vector/afg_mean_2m_air_temperature_total_precipitation_era5_monthly.csv",
    container = "projects"
)

df_temp <- readr::read_csv("../mean_2m_air_temperature_total_precipitation_era5_monthly.csv")
df_temp |> count(parameter)
df_temp |>
  filter(
    month(date) %in% c(4)
    ) |>
  ggplot(
    aes(x= date, y= value,group = ADM1_NAME)
  )+
  geom_line()+
  # facet_wrap(~ADM1_NAME)+
  scale_x_date(
    limits = c(as_date("2010-01-01"),as_date("2024-12-01"))
  )
