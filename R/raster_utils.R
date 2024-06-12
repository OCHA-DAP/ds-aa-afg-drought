
load_mars_stack <- function(){
  cog_folder_contents <- cumulus::list_contents(
    container = "projects",dir = "ds-aa-afg-drought/cogs/"
  )

  container_vp <- paste0("/vsiaz/projects/")
  urls <- paste0(container_vp, cog_folder_contents$name)

  Sys.setenv(AZURE_STORAGE_SAS_TOKEN=Sys.getenv("DSCI_AZ_SAS_DEV"))
  Sys.setenv(AZURE_STORAGE_ACCOUNT=Sys.getenv("DSCI_AZ_STORAGE_ACCOUNT"))

  r <- terra::rast(urls)
  r
}
