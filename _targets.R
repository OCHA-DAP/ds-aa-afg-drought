library(targets)
library(dplyr)
library(sf)
library(arrow)
library(geoarrow)

tar_source() # source custom funcs

# packages required for targets
tar_option_set(
  packages = c(
    "tibble",
    "sf",
    "tidyverse",
    "terra"
  )
)

# Load files req for pipeline ---------------------------------------------

fbps <- proj_blob_paths()
pc <- load_proj_containers()
tf <- tempfile(fileext = ".parquet")

AzureStor::download_blob(
  container = pc$PROJECTS_CONT,
  src = fbps$GDF_ADM2,
  dest = tf,
  overwrite =T
)

gdf_adm2 <- open_dataset(tf) |>
  st_as_sf()


  gdf_adm2 <- gdf_adm2 |>
  janitor::clean_names() |>
  dplyr::select(matches("adm\\d_[pe]")) %>%
  # adding this in so we can run weighted stats to aggregate all other admin zones
  # plus needed for easy integration for shiny app
  dplyr::mutate(
    area= sf::st_area(sf::st_geometry(.)),
    pct_area = as.numeric(area/sum(area))
  )



# Replace the target list below with your own:
list(
  tar_target(
    name = df_chirps_adm2,
    command = load_wfp_chirps(),
    description = "Afghanistan: Rainfall Indicators at Subnational (admin 2) Level - WFP - HDX"
  ),
  tar_target(
    name = df_mars_zonal_raw,
    command = zonal_tidy(
      r= load_mars_stack(),
      geom = gdf_adm2,
      geom_cols_keep = colnames(gdf_adm2),
      stat = "mean"),
    description = "MARS Seasonal Forecast: Zonal Means at admin 2"
  ),
  tar_target(
    name = df_mars_zonal,
    command = df_mars_zonal_raw |>
      mutate(
        pub_date= as_date(str_extract(name,"\\d{4}-\\d{2}-\\d{2}")),
        lt = parse_number(str_extract(name,"lt\\d{1}")),
        valid_date = pub_date + months(lt)
      ) |>
      select(-name),
    description = "MARS Seasonal Zonal Forecast Means Wrangled"
  )
)
