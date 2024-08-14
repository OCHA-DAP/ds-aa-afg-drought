#' wfp-adm2-climate data sets
#' Code to download wfp adm2 level climate data sets from HDX.
#'
#' Here we download NDVI & CHIRPS data and upload them to blob.
#' The `load_wfp_*` functions loads and parses the data directly from HDX
#' Nonetheless the files are being stored in the blob in case of any future
#' changes to links and to make qmd -> html rendering faster

box::use(purrr[map2])
box::use(readr[write_csv])
box::use(AzureStor)

box::use(../R/load_funcs[...])
box::use(blob = ../R/blob_connect[...])

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
