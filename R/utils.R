box::use(
  dplyr,
  rlang,
  utils,
  stringr,
  tools,
  sf,
  glue,
  tidyr,
  cumulus
)




#' return_period empirical
#'
#' @param x
#' @param direction `character` representing directioality/ polarity supplied
#'   supplied to rank() function options are "1" and "-1". Default is "1"
#'   which maintains the same default setting as rank()
#' @param ties_method `character` representing the method to break ties.
#'   options are inherited from rank and include “average” (default),
#'    “first”, “last”, “random”, “max”, “min”
#'
#' @returns vector of length x with empirical return period values
#' @export
#'
#' @examples
rp_empirical <- function(x, direction=c("1","-1"),ties_method = "average"){
  direction <- as.numeric(rlang::arg_match(direction))
  rank = rank(x*direction,ties.method = ties_method)
  q_rank = rank/(length(x)+1)
  rp = 1/q_rank
  return(rp)
}

#' threshold_var
#' @description
#' useful utility function doing grouped return period thresholding all in one
#' currently only used in book_afg_analysis/06_indicator_expansion.qmd
#' with one directionality. In this case i deal w/ directionality as a pre
#' processing step. However, in future it would be cool if this function worked
#' with directions `1` & `-1`
#'
#' @param df
#' @param var
#' @param by
#' @param rp_threshold
#' @param direction
#'
#' @returns
#' @export
#'
#' @examples
threshold_var <-  function(df,var, by,rp_threshold,direction=1){
  if(direction==1){
    df |>
      dplyr$group_by(
        dplyr$across({{by}})
      ) |>
      dplyr$arrange(
        dplyr$desc(!!rlang$sym(var))
      ) |>
      dplyr$mutate(
        rank = dplyr$row_number(),
        q_rank = rank/(max(rank)+1),
        rp_emp = 1/q_rank,
        !!rlang$sym(glue$glue("{var}_flag")):= rp_emp>=rp_threshold
      ) |>
      dplyr$select(-rank,-q_rank,-rp_emp)
  }
}

#' @export
load_aoi_names <-  function(){
  c(
    "Takhar",
    "Badakhshan",
    "Badghis",
    "Sar-e-Pul" ,
    "Faryab"
  )
}

#' Download shapefile and read
#'
#' Download shapefile to temp file, unzipping zip files if necessary. Deals with zipped
#' files like geojson or gpkg files as well as shapefiles, when the unzipping
#' returns a folder. The file is then read with `sf::st_read()`.
#'
#' @param url URL to download
#' @param layer Layer to read
#' @param iso3 `character` string of ISO3 code to add to the file.
#' @param boundary_source `character` name of source for the admin 0 boundaries
#'     layer. If supplied a column named "boundary_source"
#'     will added to sf object with the specified input. If `NULL` (default)
#'     no column added.
#'
#' @returns sf object
#'
#' @export
download_shapefile <- function(
    url,
    layer = NULL,
    iso3 = NULL,
    boundary_source = NULL
) {
  if (stringr$str_ends(url, ".zip")) {
    utils$download.file(
      url = url,
      destfile = zf <- tempfile(fileext = ".zip"),
      quiet = TRUE
    )

    utils$unzip(
      zipfile = zf,
      exdir = td <- tempdir()
    )

    # if the file extension is just `.zip`, we return the temp dir alone
    # because that works for shapefiles, otherwise we return the file unzipped
    fn <- stringr$str_remove(basename(url), ".zip")
    if (tools$file_ext(fn) == "") {
      fn <- td
    } else {
      fn <- file.path(td, fn)
    }
  } else {
    utils$download.file(
      url = url,
      destfile = fn <- tempfile(fileext = paste0(".", tools$file_ext(url))),
      quiet = TRUE
    )
  }

  if (!is.null(layer)) {
    ret <- sf$st_read(
      fn,
      layer = layer,
      quiet = TRUE
    )
  } else {
    ret <- sf$st_read(
      fn,
      quiet = TRUE
    )
  }

  # add in iso3 and boundary source. if NULL, no change will happen
  ret$iso3 <- iso3
  ret$boundary_source <- boundary_source

  ret
}

#' @export
download_fieldmaps_sf <- function(iso3, layer = NULL) {
  iso3 <- tolower(iso3)
  download_shapefile(
    url = glue$glue("https://data.fieldmaps.io/cod/originals/{iso3}.gpkg.zip"),
    layer = layer,
    iso3 = iso3,
    boundary_source = "FieldMaps, OCHA"
  )
}

proj_paths <-  function(){

  AA_DIR_NEW <- Sys.getenv("AA_DATA_DIR_NEW")
  AA_DIR_OLD <- Sys.getenv("AA_DATA_DIR")

  PUB_PROCESSED_AFG <-   file.path(
    AA_DIR_NEW ,
    "public",
    "processed",
    "afg"
  )
  PUB_RAW_AFG <-   file.path(
    AA_DIR_NEW,
    "public",
    "raw",
    "afg"
  )

  PUB_RAW_GLB <- file.path(
    AA_DIR_OLD,
    "public",
    "raw",
    "glb")


  list(
    "PUB_RAW_AFG" = PUB_RAW_AFG,
    "PUB_PROCESSED_AFG"= PUB_PROCESSED_AFG,
    "PUB_RAW_GLB" = PUB_RAW_GLB,
    "ADM1_GAUL"= file.path(
      PUB_RAW_GLB,
      "asap",
      "reference_data",
      "gaul1_asap_v04" ) ,

    "ADM2_GAUL"= file.path(PUB_RAW_GLB,
                           "asap",
                           "reference_data",
                           "gaul2_asap_v04" ) ,

    "ADM1_CHIRPS_MONTHLY"= file.path(
      PUB_PROCESSED_AFG,
      "chirps_monthly_afg_adm1_historical.csv"
    ) ,

    "ADM2_AFG_GAUL" = file.path(
      PUB_RAW_AFG,
      "afg_adm2_fao_gaul2015.rds"
    ),
    "ADM_TABULAR_COD"= file.path(
      PUB_RAW_AFG,
      "afg_adminboundaries_tabulardata.xlsx"
    ),
    "ADM1_MODIS_SNOW" = file.path(
      PUB_PROCESSED_AFG,
      "modis_snow_frac_monthly_afg_adm1_historical.csv"
    ),

    "ONI_LINK"= "https://origin.cpc.ncep.noaa.gov/products/analysis_monitoring/ensostuff/detrend.nino34.ascii.txt",

    "ASAP_ACTIVE_SEASON_RASTER" = file.path(
      Sys.getenv("AA_DATA_DIR"),
      "public",
      "processed",
      "glb",
      "asap",
      "season",
      "month"
    ),
    "ADM2_NDVI_WFP_HDX" = file.path(
      PUB_RAW_AFG,
      "afg-ndvi-adm2-full.csv"
    ),
    "FS_INDICATORS_FAO" = file.path(
      PUB_RAW_AFG,
      "suite-of-food-security-indicators_afg.csv"
    ),
    "AMD1_NDVI_CROP_MODIS" = file.path(
      PUB_PROCESSED_AFG,
      "modis_ndvi_2000_2004.csv"
    )
  )

}


#' oni_to_enso_class
#'
#' @param oni `numeric`
#'
#' @return
#' @export
#'
#' @examples \dontrun{
#' df_oni <- read_table()
#' df_oni |>
#'   mutate(
#'   enso_class = oni_to_enso_class(anom)
#'   )
#' }
oni_to_enso_class <-  function(x){
  x_class <- case_when(x<=-.5~"La Nina",
            x< 0.5~"Neutral",
            x>= 0.5 ~"El Nino")
  fct_relevel(x_class, "La Nina","Neutral","El Nino")
}

months_of_interest <- function(){
  list(
    winter_wheat = c(12,1,2,3,4)
  )
}


# update_theme_gghdx()
update_theme_gghdx <-  function(context = "rpubs"){
  if(context == "rpubs"){
    theme_update(
    plot.title = element_text(size=10),
    plot.subtitle  = element_text(size=10),
    axis.title = element_text(size=8),
    axis.text= element_text(size=8),
    plot.caption = element_text(hjust= 0, size=8),
    strip.text = element_text(size=8),
    axis.text.x = element_text(angle = 90, hjust = 1),
    legend.title  =element_blank()
  )
  }

}

proj_palettes <-  function(){
  list(
    "enso_palette" =  c("La Nina"= "#FBB4AE" ,
                        "El Nino" = "#B3CDE3" ,
                        "Neutral" ="#CCEBC5"
    )
  )
}


#' @export
label_parameters <- function(df){
  df |>
    dplyr$mutate(
      parameter_label = dplyr$case_when(
        stringr$str_detect(parameter, "era5_land_volumetric_soil")~ "Soil Moisture (ERA5)",
        stringr$str_detect(parameter,"NDSI")~"NDSI",
        stringr$str_detect(parameter,"asi")~"ASI",
        stringr$str_detect(parameter,"vhi")~"VHI",
        stringr$str_detect(parameter,"cumu_chirps_precipitation_sum")~"Precip cumu (CHIRPS) ",
        stringr$str_detect(parameter,"chirps_precipitation_sum")~"Precip (CHIRPS)",
        stringr$str_detect(parameter,"cumu_era5_land_total_precipitation_sum")~"Precip cumu (ERA)",
        stringr$str_detect(parameter,"era5_land_total_precipitation_sum")~"Precip (ERA)",
        stringr$str_detect(parameter,"mean_2m_air_temperature")~"Temp (ERA)",
        stringr$str_detect(parameter,"era5_land_snow_depth_water_equivalent")~"SDWE (ERA5)",
        stringr$str_detect(parameter,"era5_land_snow_cover")~"Snow Cover (ERA5)",
        stringr$str_detect(parameter,"era5_land_snowmelt_sum")~"Snow Melt (ERA5)",
        stringr$str_detect(parameter,"runoff_max")~"Runoff max (ERA5)",
        stringr$str_detect(parameter,"runoff_sum")~"Runoff sum (ERA5)",
        stringr$str_detect(parameter,"SWE_inst")~"SWE (FLDAS)",
        stringr$str_detect(parameter,"mam_mixed_seas_observed")~"Mixed forecast & obs -MAM",
        .default = parameter
      )
    )
}


#' Load design weights
#'
#' @returns list of named data.frames. Name reflects date at which the weights
#'   were considered weights use for trigger mechanism. If new weight
#'   compositions are decided upon they will be added as new data.frames
#' @export

design_weights <- function(){
  list(
    "20250401" =tidyr$tibble(
      parameter = c(
        "era5_land_snow_cover",
        "cumu_era5_land_total_precipitation_sum",
        "era5_land_soil_moisture_1m",
        "mam_mixed_seas_observed",
        "asi",
        "vhi"
      ),
      weight = c(0.15, 0.05,0.05,0.25,0.25,0.25)
    )
  )
}


#' load_window_b_thresholds
#'
#' @param version `character` version of thresholds based on date implemented
#'   in formt YYYYMMDD
#'
#' @returns data.frame with window B thresholds
#' @export

load_window_b_thresholds <- function(version = "20250401"){
  cumulus$blob_read(
    container = "projects",
    name = glue$glue("ds-aa-afg-drought/monitoring_inputs/window_b_cdi_thresholds_{version}.parquet")
  )
}
