#' produce: `afg_admbnda_agcho_adm1.parquet` `afg_admbnda_agcho_adm2.parquet`
#' as geoparquets on blob storage
#' AFG OCHA team provided: afg_admbnda_agcho.zip. This file was manually
#' uploaded to blob. This code takes the zip and processes it to adm1/2
#' geoparquets

box::use(AzureStor)
box::use(sf[...])
box::use(janitor[...])
box::use(dplyr[...])
box::use(arrow[...])
box::use(geoarrow[...]) # when loaded parquets with geoms can be written.

box::use(cloud = ../R/blob_connect)



# Process zip -------------------------------------------------------------

# load storage containers
pc <- cloud$load_proj_contatiners()
tf <- tempfile(fileext = ".zip")

# zip file provided from AFG country team (wasn't on HDX at time of writing)
AzureStor$download_blob(
  pc$PROJECTS_CONT,
  "ds-aa-afg-drought/raw/vector/afg_admbnda_agcho.zip",
  tf
)
zf_vp <- paste0("/vsizip/",tf)

gdf_adm2 <- st_read(zf_vp,"afg_admbnda_adm2_agcho_20211117") |>
  clean_names() |>
  select(matches("adm\\d_[pe]"))

gdf_adm1 <- st_read(zf_vp,"afg_admbnda_adm1_agcho_20211117") |>
  clean_names() |>
  select(matches("adm\\d_[pe]"))



# write parquets ----------------------------------------------------------

# write adm1 as geoparquet
 write_parquet(
  x= gdf_adm1,
  sink= tf
  )

AzureStor$upload_blob(
  container = pc$PROJECTS_CONT,
  src= tf,
  dest = "ds-aa-afg-drought/raw/vector/afg_admbnda_agcho_adm1.parquet"
)

# write adm2 as geoparquet
 write_parquet(
  x= gdf_adm2,
  sink= tf
  )

AzureStor$upload_blob(
  container = pc$PROJECTS_CONT,
  src= tf,
  dest = "ds-aa-afg-drought/raw/vector/afg_admbnda_agcho_adm2.parquet"
)
