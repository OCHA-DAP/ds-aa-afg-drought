#' Helper functions to load data sets

load_wfp_chirps <- function(){

  chirps_url <- "https://data.humdata.org/dataset/3b5e8a5c-e4e0-4c58-9c58-d87e33520e08/resource/a8c98023-e078-4684-ade3-9fdfd66a1361/download/afg-rainfall-adm2-full.csv"
  download.file(chirps_url, tf <- tempfile("afg-rainfall-adm2-full.csv"))
  df_chirps_adm2 <- read_csv(tf)

  df_chirps_adm2[-1,] |>
    janitor::clean_names() |>
    readr::type_convert()
}

load_wfp_ndvi <- function(){
  url <- "https://data.humdata.org/dataset/fa36ae79-984e-4819-b0eb-a79fbb168f6c/resource/d79de660-6e50-418b-a971-e0dfaa02586f/download/afg-ndvi-adm2-full.csv"
  download.file(url, tf <- tempfile("afg-ndvi-adm2-full.csv"))
  df_adm2 <- read_csv(tf)

  df_adm2[-1,] |>
    janitor::clean_names() |>
    readr::type_convert()
}
