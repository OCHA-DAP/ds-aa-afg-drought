#' `modis_masked_snow_frac_monthly_afg_adm1_historical.csv`
#' `Date:` 2024-04-22
#' This script generates the modis_snow_frac_masked_monthly_afg_adm1_historical.csv
#' https://www.google.com/search?q=snow+cover+remote+sensing&sca_esv=93dba3a330e5cf9e&rlz=1C5CHFA_enUS1035US1036&sxsrf=ADLYWIJ83Vrdbe2nhQkqpad2twDgz6A0mQ%3A1731363994484&ei=moQyZ8eXHY2v5NoP74-i-AY&ved=0ahUKEwjHzPi-qdWJAxWNF1kFHe-HCG8Q4dUDCBA&uact=5&oq=snow+cover+remote+sensing&gs_lp=Egxnd3Mtd2l6LXNlcnAiGXNub3cgY292ZXIgcmVtb3RlIHNlbnNpbmcyBhAAGBYYHjIIEAAYFhgeGA8yCxAAGIAEGIYDGIoFMgsQABiABBiGAxiKBTIIEAAYgAQYogQyCBAAGIAEGKIEMggQABiABBiiBDIIEAAYogQYiQUyCBAAGKIEGIkFSI4XUABYxRZwAHgAkAEBmAHmAqABqieqAQYyLTE5LjK4AQPIAQD4AQGYAhSgAoElwgIKECMYgAQYJxiKBcICChAAGIAEGEMYigXCAgsQABiABBiRAhiKBcICEBAuGIAEGLEDGBQY1AIYhwLCAhAQABiABBixAxhDGIMBGIoFwgIIEC4YgAQYsQPCAgoQABiABBgUGIcCwgIOEAAYgAQYsQMYgwEYigXCAgsQABiABBixAxiDAcICDRAAGIAEGLEDGBQYhwLCAhEQABiABBiRAhixAxiDARiKBcICDRAuGIAEGLEDGBQYhwLCAggQABiABBixA8ICBRAAGIAEwgIQEAAYgAQYsQMYgwEYFBiHAsICDhAuGBYYxwEYChgeGK8BmAMAkgcGMi0xOS4xoAessAE&sclient=gws-wiz-serp#fpstate=ive&vld=cid:49160f8d,vid:LzgrEZH6Hdw,st:0
#' @note `ANALYSIS & DATA PRDUCED ONLY USED IN EXPLORATORY`
#'
#' **Description:**
#' Using GEE temporally aggregate MODIS NDSI_Snow_Cover daily data to monthly.
#' We then run zonal means  for each yr_mo combination at the admin-1 level
#' For all of Afghanistan.
#'
#' **Limitation:**
#' It may not make sense to run this analysis without first applying a water mask.
#'
#' **Tip:*
#' Script can be run in the background (on Mac with terminal call)
#' `caffeinate -i -s Rscript data-raw/modis_snow_cover.R`
#'
#'
#' Originally set up before blob storage so gdrive was still being used.
#' Therefore, I've kept the code the same, but included a final step which
#' also uploads output files to blob.

library(rgee)
library(tidyrgee)
library(rhdx)
library(tidyverse)
ee_Initialize()

overwrite_csv <-  c(T,F)[1]
interactive_viz <- c(T,F)[2]
modis_snow_ic = ee$ImageCollection("MODIS/061/MOD10A1")$select('NDSI_Snow_Cover')$filterDate("2001-01-01","2023-12-31")
modis_lc_ic <- ee$ImageCollection("MODIS/061/MCD12Q1")$select("LC_Type1")$filterDate("2001-01-01","2023-12-31")
# as_tidyee(modis_lc_ic)
# wb <-  lc$eq(17)$Not()

modis_wb_ic <- modis_lc_ic$map(
  function(img) {
    img$eq(17)$Not()$
      # img$updateMask(crop_pixels)$
      copyProperties(img, img$propertyNames())
  }
)

# as_tidyee(modis_wb_ic)
modis_snow_masked <- modis_snow_ic$map(function(img) {
  # Get the year of the current image

  eedate <- ee$Date(img$get("system:time_start"))
  eeyear <- eedate$get("year")

  # Find the corresponding crop mask in the modis_cropcover_ic collection
  # crop_mask <- modis_cropcover_ic$filter(ee$Filter$eq("year", eeyear))$first()
  water_mask <- modis_wb_ic$filter(rgee::ee$Filter$calendarRange(eeyear, eeyear, "year"))$first()

  # Apply the water mask to the image
  masked_img <- img$updateMask(water_mask)

  # Return the masked image
  return(masked_img)
})



mod_tic_masked <- as_tidyee(modis_snow_masked)
# mod_tic <- as_tidyee(mod_ic)



adm1_fc <- ee$FeatureCollection("FAO/GAUL_SIMPLIFIED_500m/2015/level1")
adm1_afghanistan <- adm1_fc$filter(ee$Filter$eq("ADM0_NAME", "Afghanistan"))

if(interactive_viz){
  mod_img_samp <- mod_ic$filterDate("2022-12-28","2022-12-29")$first()
  mod_masked_samp <- modis_snow_masked$filterDate("2022-12-28","2022-12-29")$first()
  vis_snow = list(
    min= 0.0,
    max= 100.0,
    palette= c('black', '0dffff', '0524ff', 'ffffff')
  )
  Map$centerObject(adm1_afghanistan, 5)
  m1 <- Map$addLayer(eeObject = mod_img_samp,
               visParams=  vis_snow,
               name =  'Snow Cover')
  m2 <- Map$addLayer(eeObject = mod_masked_samp,
                     visParams=  vis_snow,
                     name =  'Snow Cover Masked')
  # m3 <- Map$addLayer(eeObject = wb,visParams = list(palette = "red"),name = "Water Mask")
  m1+m2

  Map$addLayer(adm1_afghanistan)

}

mod_tic_summarised <- mod_tic_masked |>
  group_by(year,month) |>
  summarise(
    stat=list("mean","min","max")
  )

yrs_unique <- mod_tic_summarised$vrt$year |>
  unique()


df_snow_frac_monthly <-
  map(yrs_unique,
      \(yt){
        cat(yt,"\n")
        mod_tic_filt <- mod_tic_masked |>
          filter(year == yt)


        dft <- ee_extract_tidy(
          x=mod_tic_filt,
          y= adm1_afghanistan,
          scale = 500,
          stat = "mean",
          via = "drive"
        )
        write_csv(dft, glue("modis_masked_snow_frac_{yt}.csv"))
      }
  )
# df_snow_frac_monthly <- mod_tic_masked |>
#   group_split(year) |>
#   map(
#     \(ict){
#       yt <- unique(ict$vrt$year)
#       cat(yt,"\n")
#       dft <- ee_extract_tidy(
#         x=ict,
#         y= adm1_afghanistan,
#         scale = 500,
#         stat = "mean",
#         via = "drive"
#       )
#       write_csv(dft, glue("modis_masked_snow_frac_{yt}.csv"))
#     }
#   )

# df_snow_frac_monthly <- ee_extract_tidy(
#   x=mod_tic_summarised,
#   y= adm1_afghanistan,
#   scale = 500,
#   stat = "mean",
#   via = "drive"
# )

# write as csv
# df_csv_outpath <-file.path(
#   Sys.getenv("AA_DATA_DIR_NEW"),
#   "public",
#   "processed",
#   "afg",
#   "modis_masked_snow_frac_monthly_afg_adm1_historical.csv"
# )
#
# if(overwrite_csv){
#   write_csv(x = df_snow_frac_monthly,
#             file = df_csv_outpath)
# }
#
#
# # Write to blob -----------------------------------------------------------
#
#
# # read all csv files
# df_snow_frac_processed <- read_csv(
#   df_csv_outpath
# )
#
# # write to temp and then upload to blob
# tf <- tempfile(fileext = ".csv")
# write_csv(
#   df_snow_frac_processed,
#   tf
# )
#
# pc <-  load_proj_containers()
# fps <- proj_blob_paths()
#
#
# AzureStor::upload_blob(
#   container = pc$PROJECTS_CONT,
#   src = tf,
#   dest = fps$DF_ADM1_SNOW_MODIS
# )
