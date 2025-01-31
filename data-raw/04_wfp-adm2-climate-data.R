#' wfp-adm2-climate data sets
#' Code to download wfp adm2 level climate data sets from HDX.
#'
#' Here we download NDVI & CHIRPS data and upload them to blob.
#' The `load_wfp_*` functions loads and parses the data directly from HDX
#' Nonetheless the files are being stored in the blob in case of any future
#' changes to links and to make qmd -> html rendering faster


box::use(
  AzureStor,
  readr[write_csv],
  purrr[map2]
  )

box::use(
  ../R/load_funcs[...],
  blob = ../R/blob_connect[...]
)


pc <- blob$load_proj_containers()
fps <- blob$proj_blob_paths()


df_chirps_adm2 <- load_wfp_chirps()
df_ndvi_adm2 <- load_wfp_ndvi()

fp_names <- c("DF_ADM2_CHIRPS_WFP","DF_ADM2_NDVI_WFP")


map2(fp_names, list(df_chirps_adm2,df_ndvi_adm2),
    \(fp_name,df){
      tf <-  tempfile(fileext = ".csv")
      write_csv(df,tf)
      AzureStor$upload_blob(
        container = pc$PROJECTS_CONT,
        src = tf,
        dest = fps[[fp_name]]
      )
    }
)


box::use(
  ../R/load_funcs
)
box::reload(load_funcs)
df_adm2_chirps <- load_funcs$load_wfp_chirps()

df_adm2_yr_mo <- df_adm2_chirps |>
  group_by(
    yr_mo_date = floor_date(date,"month"),
    adm2_id,
    adm2_pcode
  ) |>
  summarise(
    precipitation = sum(rfh),
    n_pixels = unique(n_pixels)
  ) |>
  ungroup()
df_lookup <- cumulus$blob_load_admin_lookup()

df_chirps_adm1 <- df_lookup |>
  clean_names() |>
  filter(adm_level ==2) |>
  right_join(df_adm2_yr_mo) |>
  group_by(date=yr_mo_date, adm1_name,adm1_pcode) |>
  summarise(
    value = weighted.mean(precipitation,n_pixels),
    .groups= "drop"
  ) |>
  mutate(
    parameter = "CHIRPS (WFP)"
  )

cumulus$blob_write(df_chirps_adm1,name= fps$DF_ADM2_CHIRPS_WFP, stage="dev")


# df_chirps_gee <- load_funcs$load_chirps()
# df_chirps_gee |>
#   clean_names() |>
#   select(adm1_code,adm1_name,date,value) |>
#   right_join(
#     df_chirps_adm1, by= c("adm1_name","date")
#   ) |>
#   pull(date) |>
#   range()
#   range(date)
