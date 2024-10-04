box::use(
  AzureStor,
  terra
)

box::use(./blob_connect)

load_mars_stack <- function(){

  pc <- blob_connect$load_proj_containers()

  cog_df <- AzureStor$list_blobs(
    container = pc$PROJECTS_CONT,
    prefix = "ds-aa-afg-drought/cogs/ecmwf_seas5_mars_"
  )

  container_vp <- paste0("/vsiaz/projects/")
  urls <- paste0(container_vp, cog_df$name)

  Sys.setenv(AZURE_STORAGE_SAS_TOKEN=Sys.getenv("DSCI_AZ_SAS_DEV"))
  Sys.setenv(AZURE_STORAGE_ACCOUNT=Sys.getenv("DSCI_AZ_STORAGE_ACCOUNT"))

  r <- terra$rast(urls)
  r
}

load_seas5_stack <- function() {
  pc <- blob_connect$load_proj_containers()
  cog_df <- AzureStor$list_blobs(
    container = pc$GLOBAL_CONT,
    dir = "seas5/monthly/processed"
  )

  container_vp <- paste0("/vsiaz/raster/")
  urls <- paste0(container_vp, cog_df$name)

  Sys.setenv(AZURE_STORAGE_SAS_TOKEN=Sys.getenv("DSCI_AZ_SAS_PROD"))
  Sys.setenv(AZURE_STORAGE_ACCOUNT="imb0chd0prod")
  terra$rast(urls)
}
