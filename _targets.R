library(targets)

# Set target options:
tar_option_set(
  packages = c(
    "tibble",
    "sf",
    "tidyverse",
    "terra"

  )
)

# Run the R scripts in the R/ folder with your custom functions:
tar_source()
# tar_source("other_functions.R") # Source other scripts as needed.
library(dplyr)
zf <- "afg_admbnda_agcho.zip"
zf_vp <- paste0("/vsizip/",zf)
gdf_adm2 <- sf::st_read(zf_vp,"afg_admbnda_adm2_agcho_20211117") |>
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
    command = load_wfp_chirps()
  ),
  tar_target(
    name = df_mars_zonal_raw,
    command = zonal_tidy(
      r= load_mars_stack(),
      geom = gdf_adm2,
      geom_cols_keep = colnames(gdf_adm2),
      stat = "mean")
  ),
  tar_target(
    name = df_mars_zonal,
    command = df_mars_zonal_raw |>
      mutate(
        pub_date= as_date(str_extract(name,"\\d{4}-\\d{2}-\\d{2}")),
        lt = parse_number(str_extract(name,"lt\\d{1}")),
        valid_date = pub_date + months(lt)
      ) |>
      select(-name)
  )
)
