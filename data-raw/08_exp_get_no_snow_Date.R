
aoi_adm1 <- c("Takhar",
"Badakhshan",
"Badghis",
"Faryab",
"Sar-e-Pul" )


library(rgee)
library(sf)
library(tidyverse)
library(gghdx)
library(glue)
library(ggiraph)
library(glue)
library(tidyrgee)
gghdx()
box::use(../R/blob_connect)

df_chirps <- blob_connect$read_blob_file("DF_ADM1_CHIRPS") |>
  filter(
    ADM1_NAME %in% aoi_adm1
  ) |>
  group_by(
    mo = month(date)
  ) |>
  mutate(
    chirps_z = (value - mean(value)) / sd(value)
  ) |>
  ungroup()

df_chirps |>
  mutate(
    yr = year(date)
  ) |>
  # filter(yr %in% c(2015:2020)) |>
  ggplot(
    aes(
      x = month(mo,label = T, abbr= T), y= value, group = yr
    )
  )+
  geom_line(alpha=0.2)+
  labs(x= "month")+
  facet_wrap(~ADM1_NAME)+
  theme(
    axis.text.x = element_text(angle= 90)
  )

df_chirps_dec_jan <- df_chirps |>
  filter(
    mo %in% c(12,1)
  ) |>
  mutate(
    yr_adj = ifelse(mo==1,year(date),year(date)+1)
  )|>
  arrange(ADM1_NAME, date) |>
  filter(yr_adj>1981) |>
  group_by(
    ADM0_NAME, ADM1_NAME, yr_adj
  ) |>
  summarise(
    value = sum(value)
  ) |>
  mutate(
    long_term_mean = mean(value),
    long_term_median = median(value),
      diff = abs(value - long_term_median),
      # min_diff = diff== min(diff),
    min_diff = diff%in% diff[ which(diff %in% sort(diff)[1:3])]
    )

df_chirps_dec_jan |>
  ggplot(
    aes(x= yr_adj,y= value)
  )+
  geom_point()+
  geom_line()+
  facet_wrap(~ADM1_NAME)

p_chirps_dec_jan <- df_chirps_dec_jan |>
  ggplot(
    aes(x= ADM1_NAME,y= value)
  )+
  geom_boxplot(color = "grey", fill = "black")+
  geom_jitter_interactive(aes(color = min_diff, tooltip= glue("{yr_adj}")))+
  ggrepel::geom_text_repel(
    data= df_chirps_dec_jan |>
      filter(min_diff),
    aes(x= ADM1_NAME, y= value, label= yr_adj), color= "red", size =5
  )
girafe(ggobj = p_chirps_dec_jan)

df_chirps_dec_jan |>
  mutate(
    yoi = yr_adj %in% c(2010,2016,2006)
  ) |>
  ggplot(
    aes(x= ADM1_NAME,y= value)
  )+
  geom_boxplot(color = "grey", fill = "black")+
  geom_jitter(aes(color = yoi))
  # ggrepel::geom_text_repel(
  #   data= df_chirps_dec_jan |>
  #     filter(yr_201),
  #   aes(x= ADM1_NAME, y= value, label= yr_adj), color= "red", size =5
  # )

# Initialize the Earth Engine API
ee_Initialize()

basin_levels = c("4"=4,"5"=5,"6"=6,"7"= 7)

img_dem = ee$Image('NASA/NASADEM_HGT/001')$select('elevation')
terrain = ee$Terrain$products(img_dem)


fc_river = ee$FeatureCollection('WWF/HydroSHEDS/v1/FreeFlowingRivers')
img_river = ee$Image()$byte()$paint(fc_river, 'RIV_ORD', 2);
adm1_fc <- ee$FeatureCollection("FAO/GAUL_SIMPLIFIED_500m/2015/level1")

# filter adm1 to get only those in Afghanistan
adm1_afghanistan <- adm1_fc$filter(ee$Filter$eq("ADM0_NAME", "Afghanistan"))
fc_faryab <- adm1_afghanistan$filter(ee$Filter$eq("ADM1_NAME","Faryab"))

Map$centerObject(fc_faryab,7)

l_hybas = map(basin_levels,\(x)ee$FeatureCollection(paste0('WWF/HydroSHEDS/v1/Basins/hybas_',x)))
riv_vis = list(
  min= 1,
  max= 10,
  palette= list('#08519c', '#3182bd', '#6baed6', '#bdd7e7', '#eff3ff')
)
hybas_vis = list(
  color= '#808080',
  strokeWidth= 1
)

img_b5 = ee$Image()$byte()$paint(l_hybas$`5`, 'BAS5', 2)


m_hydro <- Map$addLayer(img_river,riv_vis, "hydroshed rivers")+
  Map$addLayer(img_b5,list(min = 0 ,max= 1, palette= "black"),"basin5")

m_hillshade <- Map$addLayer(terrain$select('hillshade'), list(min = 0,max=255), 'Hillshade')

m_hydro|m_hillshade
hybas_draw = hybas_5$draw(hybas_vis)


Map$addLayer(hybas_draw, {}, 'Basins');

# Define constants
start_doy <- 1
start_year <- 2000
end_year <- 2024

# Define function to add date bands
add_date_bands <- function(img) {
  # Get image date
  date <- img$date()

  # Get calendar day-of-year
  cal_doy <- date$getRelative('day', 'year')

  # Get relative day-of-year
  rel_doy <- date$difference(ee$Date(start_date), 'day')

  # Get the date as milliseconds from Unix epoch
  millis <- date$millis()

  # Add date bands to the image
  date_bands <- ee$Image$constant(c(cal_doy, rel_doy, millis, start_year))$
    rename(c("calDoy", "relDoy", "millis", "year"))$
    cast(list(calDoy = "int", relDoy = "int", millis = "long", year = "int"))

  img$addBands(date_bands)$set(list(millis = millis))
}

# Define water mask
water_mask <- ee$Image("MODIS/MOD44W/MOD44W_005_2000_02_24")$
  select("water_mask")$Not()


# Define complete collection
complete_col <- ee$ImageCollection("MODIS/061/MOD10A1")$
  select("NDSI_Snow_Cover")

# Define snow cover ephemeral mask
snow_cover_ephem <- complete_col$
  filterDate("2010-01-01", "2011-01-01")$
  map(function(img) img$gte(10))$
  sum()$
  gte(14) # at least 2 weeks > 10 %

# Define snow cover constraint mask
snow_cover_const <- complete_col$
  filterDate("2010-01-01", "2011-01-01")$
  map(function(img) img$gte(10))$
  sum()$
  lte(124)

# Define analysis mask
analysis_mask <- water_mask$multiply(snow_cover_ephem)$multiply(snow_cover_const)

# Define years
years <- ee$List$sequence(start_year, end_year)

# Process each year
annual_list <- years$map(ee_utils_pyfunc(function(year) {
  # Update global variables
  start_year <<- year
  start_date <<- ee$Date$fromYMD(year, 1, 1)$advance(start_doy - 1, "day")
  # end_date <- start_date$advance(1, "year")$advance(1, "day")
  end_date <- start_date$advance(250, "day")$advance(1, "day")

  # Filter collection by year
  year_col <- complete_col$filterDate(start_date, end_date)

  # Generate no-snow image
  no_snow_img <- year_col$
    map(add_date_bands)$
    sort("millis")$
    reduce(ee$Reducer$min(5))$
    rename(c("snowCover", "calDoy", "relDoy", "millis", "year"))$
    updateMask(analysis_mask)$
    set("year", year)

  no_snow_img$updateMask(no_snow_img$select("snowCover")$eq(0))
}))

annual_list <- years$map(ee_utils_pyfunc(function(year) {
  # Define date range for the year
  start_date <- ee$Date$fromYMD(year, 1, 1)$advance(start_doy - 1, "day")
  end_date <- start_date$advance(250, "day")$advance(1, "day")

  sys_date <- ee$Date$fromYMD(year, 1, 1)
  # Filter collection by year
  year_col <- complete_col$filterDate(start_date, end_date)

  # Generate no-snow image
  no_snow_img <- year_col$
    map(add_date_bands)$
    sort("millis")$
    reduce(ee$Reducer$min(5))$
    rename(c("snowCover", "calDoy", "relDoy", "millis", "year"))$
    updateMask(analysis_mask)$
    set("year", year)$
    set("system:time_start",sys_date)

  no_snow_img$updateMask(no_snow_img$select("snowCover")$eq(0))
}))

# Convert to an ImageCollection
annual_col <- ee$ImageCollection$fromImages(annual_list)

# Define visualization arguments
vis_args <- list(
  bands = c("calDoy"),
  min = 150,
  max = 200,
  palette = c("0D0887", "5B02A3", "9A179B", "CB4678", "EB7852", "FBB32F", "F0F921")
)

# Visualize a specific year
this_year <- 2024
first_day_no_snow <- annual_col$filter(ee$Filter$eq("year", this_year))$first()
# Map$setCenter(-95.78, 59.451, 5)
Map$addLayer(first_day_no_snow, vis_args, "First day of no snow, 2018")


tic_annual <-  as_tidyee(annual_col$select('calDoy'))



# Filter features where ADM1_NAME matches any value in aoi
fc_filtered <- adm1_afghanistan$filter(
  ee$Filter$inList("ADM1_NAME", aoi_adm1)
  )
ee_print(fc_filtered)

complete_col$first()$projection()$nominalScale()$getInfo()

df_avg_snowmelt <- ee_extract_tidy(
  x = tic_annual,
  y=fc_filtered,
  stat = "mean",
  scale = 500
  )

write_csv(df_avg_snowmelt,"data/modis_first_day_no_snow_2010_mask.csv")

cumulus::blob_write(df_avg_snowmelt,stage = "dev" , name = "ds-aa-afg-drought/processed/vector/modis_first_day_no_snow_2010_mask.csv",container = "projects")

# Compute difference image between two years
first_year <- 2005
second_year <- 2015
first_img <- annual_col$filter(ee$Filter$eq("year", first_year))$first()$select("calDoy")
second_img <- annual_col$filter(ee$Filter$eq("year", second_year))$first()$select("calDoy")
dif <- second_img$subtract(first_img)

# Visualize difference image
vis_args_diff <- list(
  min = -15,
  max = 15,
  palette = c("b2182b", "ef8a62", "fddbc7", "f7f7f7", "d1e5f0", "67a9cf", "2166ac")
)
Map$setCenter(95.427, 29.552, 8)
Map$addLayer(dif, vis_args_diff, "2015-2005 first day no snow difference")

# Calculate slope
slope <- annual_col$sort("year")$select(c("year", "calDoy"))$
  reduce(ee$Reducer$linearFit())$select("scale")

# Visualize slope
vis_args_slope <- list(
  min = -1,
  max = 1,
  palette = c("b2182b", "ef8a62", "fddbc7", "f7f7f7", "d1e5f0", "67a9cf", "2166ac")
)
Map$setCenter(11.25, 59.88, 6)
Map$addLayer(slope, vis_args_slope, "2000-2019 first day no snow slope")

# Define AOI
aoi <- ee$Geometry$Point(-94.242, 65.79)$buffer(1e4)
Map$addLayer(aoi, NULL, "Area of interest")

# Compute annual mean DOY for AOI
annual_aoi_mean <- annual_col$select("calDoy")$map(ee_utils_pyfunc(function(img) {
  summary <- img$reduceRegion(
    reducer = ee$Reducer$mean(),
    geometry = aoi,
    scale = 1e3,
    bestEffort = TRUE,
    maxPixels = 1e14,
    tileScale = 4
  )
  ee$Feature(NULL, summary)$set("year", img$get("year"))
}))

# Plot chart
chart <- ee$Chart$feature$byFeature(annual_aoi_mean, "year", "calDoy")$
  setOptions(list(
    title = "Regional mean first day of year with no snow cover",
    legend = list(position = "none"),
    hAxis = list(title = "Year", format = "####"),
    vAxis = list(title = "Day-of-year")
  ))
print(chart)
