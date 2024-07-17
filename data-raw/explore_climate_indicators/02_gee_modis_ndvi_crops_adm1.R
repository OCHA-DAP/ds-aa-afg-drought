#' Code to extract NDVI from MODIS per Admin 1 only over the crop land mask
#' @note `ANALYSIS & DATA PRDUCED ONLY USED IN EXPLORATORY`
#' @details
#' Methodology:
#'     1. using GEE/RGEE all modis data from both Terra & Aqua sensors are
#'     processed (cloud & quality masked and then scaled)
#'     2. Processed Terra & Aqua sensor data are merged and cropped to MODIS
#'     MCD12Q1 cropland product.
#'     3. The mean values per year month are extracted at admin 1 level.
#'
#' Originally set up before blob storage so gdrive was still being used.
#' Therefore, I've kept the code the same, but included a final step which
#' also uploads output files to blob.

library(rgee)
library(tidyrgee)
library(tidyverse)
library(glue)

# simplify gif making w/
library(rgeeExtra) # remotes::install_github("r-earthengine/rgeeExtra")

source(here(file.path("R","utils_gee.R")))
source(here(file.path("R","blob_connect.R")))
ee_Initialize()


overwrite_csv <- T

# was having GEE timeout issues when I tried to run the extraction all at once
# therefor I had to play w/ looping/mapping to produce extract csvs in batches.
# Leaving in the option to to run all at once as sometimes it works fine and
# is faster.

loop_iteration <- T


out_dir <-file.path(
  Sys.getenv("AA_DATA_DIR_NEW"),
  "public",
  "processed",
  "afg"
)

fc_adm1 <- ee$FeatureCollection("FAO/GAUL/2015/level1")
fc_afg <- fc_adm1$filter(ee$Filter$eq("ADM0_NAME", "Afghanistan"))


terra_modis_link <- get_modis_link("terra")
aqua_modis_link <- get_modis_link("aqua")
process_mask <- "cloud&quality"

terra_ic <- ee$ImageCollection(terra_modis_link)
aqua_ic <- ee$ImageCollection(aqua_modis_link)
terra_ic_proc <- cloud_scale_modis_ndvi(x = terra_ic, mask = process_mask)
aqua_ic_proc <- cloud_scale_modis_ndvi(x = aqua_ic, mask = process_mask)
terra_aqua_ndvi_merged <- terra_ic_proc$merge(aqua_ic_proc)

modis_lulc_ic <- ee$ImageCollection("MODIS/061/MCD12Q1")$select("LC_Type1")
modis_cropcover_ic <- modis_lulc_ic$map(
  function(img) {
    img$eq(12)$
    # img$updateMask(crop_pixels)$
      copyProperties(img, img$propertyNames())
  }
)
# landcover goes from 2001-2022
# modis ndvi goes from 2000-22024-03-29
ta_merged_filt <- terra_aqua_ndvi_merged$filterDate(
  "2001-01-01","2022-12-31"
)

terra_aqua_ndvi_merged_masked <- ta_merged_filt$map(function(img) {
  # Get the year of the current image
  eedate <- ee$Date(img$get("system:time_start"))
  eeyear <- eedate$get("year")

  # Find the corresponding crop mask in the modis_cropcover_ic collection
  # crop_mask <- modis_cropcover_ic$filter(ee$Filter$eq("year", eeyear))$first()
  crop_mask <- modis_cropcover_ic$filter(rgee::ee$Filter$calendarRange(eeyear, eeyear, "year"))$first()
  # Apply the crop mask to the image
  masked_img <- img$updateMask(crop_mask)

  # Return the masked image
  return(masked_img)
})



tic <- as_tidyee(terra_aqua_ndvi_merged_masked)
if(!loop_iteration){
  tic_monthly_mean <- tic |>
    group_by(year, month) |>
    summarise(
      stat= "mean"
    )
  df_tic <- tidyrgee::ee_extract_tidy(
    x=tic_monthly_mean,
    y= fc_afg,
    scale = 250,
    fun = "mean",
    via = "drive"
  )

  fp_out <-  file.path(out_dir,
                       "modis_ndvi_crop_2001_2022.csv")
  write_csv(df_tic,
            fp_out)
}



if(loop_iteration){
  # Create a vector of group indices
  yr_seq <- 2001:2022
  groups <- (yr_seq - min(yr_seq)) %/% 5



  # Split the years into lists of 2 years
  year_pairs <- split(yr_seq, groups)

  yr_seq |>
    map(
      \(y){
        cat("running",y,"\n")
        # y <- year_pairs[[2]]
        # y <- 2008
        tic_filt <- tic |>
          filter(year %in%y)

        tic_composite <- tic_filt |>
          group_by(year,month) |>
          summarise(
            stat="mean"
          )
        df_tic <- tidyrgee::ee_extract_tidy(
          x=tic_composite,
          y= fc_afg,
          scale = 250,
          fun = "mean",
          via = "drive"
        )

        yr_tag <- glue_collapse(range(y),"_")

        fp_tmp <-  file.path(out_dir,
                             paste0("modis_ndvi_",yr_tag,".csv")
        )
        write_csv(df_tic,
                  fp_tmp)
      }
    )
}



# Write to blob -----------------------------------------------------------


# read all csv files
df_ndvi_processed <- read_csv(
  list.files(out_dir,"^modis_ndvi_.*csv$",full.names = T)
)

# write to temp and then upload to blob
tf <- tempfile(fileext = ".csv")
write_csv(
  df_ndvi_processed,
  tf
)

pc <-  load_proj_containers()
fps <- proj_blob_paths()


AzureStor::upload_blob(
  container = pc$PROJECTS_CONT,
  src = tf,
  dest = fps$DF_ADM1_NDVI_CROPS
)



# Create Gif --------------------------------------------------------------


fc_hirat <- fc_adm1$filter(ee$Filter$eq("ADM1_NAME", "Hirat"))
geom_hirat <- fc_hirat$geometry()
animParams <- list(region= geom_hirat,
                   framesPerSecond=1,
                   dimensions=600

)


ic_masked <- as_tidyee(terra_aqua_ndvi_merged_masked)
tic_yrmo <- ic_masked |>
  group_by(year) |>
  summarise(stat="median")

ic_yrmo <-as_ee(tic_yrmo)
#// Create RGB visualization images for use as animation frames.
icViz = ic_yrmo$map(function(img) {
  img$visualize(
    min=0,
    max=1,
    palette= c(
      "ffffff", "ce7e45", "df923d", "f1b555", "fcd163", "99b718", "74a901",
      "66a000", "529400", "3e8601", "207401", "056201", "004c00", "023b01",
      "012e01", "011d01", "011301"
    ),
    bands= "NDVI_median"
  )$clip(geom_hirat)$
    set("year", img$get("year"))
})


empty <- ee$Image()$byte();
afgOutline = empty$paint(
  featureCollection= fc_adm1,
  color= 1,
  width= 1
)$
  visualize(palette= 'white')


tempColOutline <-  icViz$map(function(img) {
  img$blend(afgOutline)
})


ndvi_anim <- rgeeExtra::ee_utils_gif_creator(
  ic = tempColOutline,
  parameters  = animParams,
  scale=5000
)



get_years <- icViz$aggregate_array("year")$getInfo()

ndvi_anim_annotated <- ndvi_anim |>
  rgeeExtra::ee_utils_gif_annotate(get_years,
                                   size = 15,
                                   location = "+90+40",
                                   boxcolor = "#FFFFFF")



# write gif to blob
tf <- tempfile(fileext = ".gif")

rgeeExtra::ee_utils_gif_save(
  ndvi_anim_annotated,
  tf
  )


AzureStor::upload_blob(
  container = pc$PROJECTS_CONT,
  src = tf,
  dest = fps$GIF_MODIS_NDVI_CROPS
)
