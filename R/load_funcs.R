

load_wfp_chirps <- function(){

  chirps_url <- "https://data.humdata.org/dataset/3b5e8a5c-e4e0-4c58-9c58-d87e33520e08/resource/a8c98023-e078-4684-ade3-9fdfd66a1361/download/afg-rainfall-adm2-full.csv"
  download.file(chirps_url, tf <- tempfile("afg-rainfall-adm2-full.csv"))
  df_chirps_adm2 <- read_csv(tf)

  df_chirps_adm2[-1,] |>
    clean_names() |>
    type_convert()
}
