STORAGE_ACCOUNT = Sys.getenv("DSCI_AZ_STORAGE_ACCOUNT")
SAS_TOKEN = Sys.getenv("DSCI_AZ_SAS_DEV")
CONTAINER_NAME = "projects"
BASE_BLOB_URL = glue::glue("https://{STORAGE_ACCOUNT}.blob.core.windows.net")
# CONTAINER_URL = glue::glue("{BASE_BLOB_URL}/{CONTAINER_NAME}/{blob_path}?{SAS_TOKEN}")
#
# upload_blob <- function(blob_path, df) {
#
# }
