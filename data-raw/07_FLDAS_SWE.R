overwrite_csv <- TRUE

box::use(
  rgee[...],
  tidyrgee[...],
  readr[...],
  janitor[...],
  dplyr[...],
  logger,
  AzureStor,
  ../R/blob_connect

  )
# ee_check()
ee_Initialize()


ic <- ee$ImageCollection("NASA/FLDAS/NOAH01/C/GL/M/V001")

logger$log_info("converting to tidy ImageCollection")
tic <- as_tidyee(ic)


tic_filt <- tic |>
  select("SWE_inst") |>
  filter(
    month %in% c(11,12,1,2,3,4,5)
  )


adm1_fc <- ee$FeatureCollection("FAO/GAUL_SIMPLIFIED_500m/2015/level1")

# filter adm1 to get only those in Afghanistan
adm1_afghanistan <- adm1_fc$filter(ee$Filter$eq("ADM0_NAME", "Afghanistan"))


img <- ic$first()
img_scale <- img$projection()$nominalScale()$getInfo()


logger$log_info("Running Zonal Statistics")
df_swe_monthly <- ee_extract_tidy(
  x=tic_filt,
  y= adm1_afghanistan,
  scale = img_scale,
  stat = "mean",
  via = "drive"
)

# write as csv
df_csv_outpath <-file.path(
  Sys.getenv("AA_DATA_DIR_NEW"),
  "public",
  "processed",
  "afg",
  "fldas_monthly_snow_SWE_afg_adm1_historical.csv"
)

logger$log_info("Writing to CSV")
if(overwrite_csv){
  write_csv(x = df_swe_monthly,
            file = df_csv_outpath)
}

df_swe <- read_csv(df_csv_outpath) |>
  clean_names() |>
  select(
    date, matches("^adm\\d_"),parameter,value
  )

write_csv(x= df_swe,
          file = tf <- tempfile(fileext = ".csv"))

pc <- blob_connect$load_proj_containers()

AzureStor$upload_blob(
container = pc$PROJECTS_CONT,
src = tf,
dest = "ds-aa-afg-drought/processed/vector/fldas_snow_SWE_adm1.csv"
)
