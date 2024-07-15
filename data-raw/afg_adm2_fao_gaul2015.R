#'  afg_adm2_fao_gaul2015.rds
#'  Global fao GAUL admin 2 data set in GDRIVE is a subset of countries that doesn't include Afghanistan.
#'  Suspect that is because it is version 4 which may not be fully updated?
#'
#'  Since GEE data sets were extracted to admin 1 boundaries using simplified GAUL dataset in GEE
#'  We need an admin 2 data set which has ID's that can be joined.
#'
library(sf)
library(rgee)
library(tidyverse)

fc_adm2 <- ee$FeatureCollection("FAO/GAUL/2015/level2")
fc_afg <- fc_adm2$filter(ee$Filter$eq("ADM0_NAME", "Afghanistan"))
gdf_adm2 <- ee_as_sf(fc_afg)

# write as csv
fp_out <-file.path(
  Sys.getenv("AA_DATA_DIR_NEW"),
  "public",
  "raw",
  "afg",
  "afg_adm2_fao_gaul2015.rds"
)

write_rds(gdf_adm2, fp_out)
