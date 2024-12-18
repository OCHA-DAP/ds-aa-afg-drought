#' Helper functions to load data sets
box::use(
  janitor,
  readr,
  dplyr,
  purrr,
  cumulus,
  lubridate,
  stringr,
  ../R/blob_connect
)

load_wfp_chirps <- function(){

  chirps_url <- "https://data.humdata.org/dataset/3b5e8a5c-e4e0-4c58-9c58-d87e33520e08/resource/a8c98023-e078-4684-ade3-9fdfd66a1361/download/afg-rainfall-adm2-full.csv"
  download.file(chirps_url, tf <- tempfile("afg-rainfall-adm2-full.csv"))
  df_chirps_adm2 <- readr$read_csv(tf)

  df_chirps_adm2[-1,] |>
    janitor$clean_names() |>
    readr$type_convert()
}

load_wfp_ndvi <- function(){
  url <- "https://data.humdata.org/dataset/fa36ae79-984e-4819-b0eb-a79fbb168f6c/resource/d79de660-6e50-418b-a971-e0dfaa02586f/download/afg-ndvi-adm2-full.csv"
  download.file(url, tf <- tempfile("afg-ndvi-adm2-full.csv"))
  df_adm2 <- readr$read_csv(tf)

  df_adm2[-1,] |>
    janitor$clean_names() |>
    readr$type_convert()
}


load_fao_vegetation_data <- function(){
  df_asi <- readr$read_csv("https://www.fao.org/giews/earthobservation/asis/data/country/AFG/MAP_ASI/DATA/ASI_Dekad_Season1_data.csv") |>
    janitor$clean_names() |>
    dplyr$mutate(
      type = "asi"
    )

  df_vhi <-  readr$read_csv("https://www.fao.org/giews/earthobservation/asis/data/country/AFG/MAP_NDVI_ANOMALY/DATA/vhi_adm1_dekad_data.csv") |>
    janitor$clean_names() |>
    dplyr$mutate(
      type = "vhi"
    )
  dplyr$bind_rows(df_asi, df_vhi)
}


load_era5_land_multiband <- function(){
  bps <- blob_connect$proj_blob_paths()
  cumulus$blob_read(
  name = bps$DF_ADM1_ERA5_LAND_MULTIBAND,
  stage = "dev"
) |>
    dplyr$mutate(
      parameter = paste0("era5_land_",parameter)
    )
}


wrangle_fao <- function(df){
  df |>
    dplyr$rename(
    adm1_name =province,
    value = data,
    parameter = type,

    ) |>
      dplyr$mutate(
        mo_label  = lubridate$month(date, abbr= T,label =T),
        yr_date =lubridate$floor_date(date, "year")
      ) |>
      dplyr$filter(
        mo_label %in% c("May","Jun"),
        dekad==3
        ) |>
      dplyr$mutate(
        parameter = paste0(parameter,"_",mo_label)
      )
}
wrangle_chirps <- function(df){
  dfg <- df |>
    janitor$clean_names() |>
      dplyr$group_by(
      adm0_code,
      adm0_name,
      adm1_name,
      adm1_code,
      yr_date = lubridate$floor_date(date, "year")
    )
      df_mam <- dfg |>
    dplyr$summarise(
      value = sum(value[lubridate$month(date)%in%c(3,4,5)]),
      .groups = "drop"
    ) |>
    dplyr$mutate(
      parameter = "chirps_mam"
    ) |>
        dplyr$ungroup()

  df_cumu <- dfg |>
    dplyr$arrange(date) |>
    dplyr$mutate(
      value = cumsum(value),
      parameter = paste0("chirps_cumu", lubridate$month(date,label=T,abbr=T))
    )
  dplyr$bind_rows(
    df_mam,
    df_cumu
  ) |>
    dplyr$select(
      adm0_code,
      adm0_name,
      adm1_name,
      adm1_code,
      yr_date,
      value, parameter
    ) |>
    dplyr$ungroup()
}

wrangle_era5 <- function(df){
  dfg <- df |>
    janitor$clean_names() |>
      dplyr$group_by(
      parameter,
      adm0_code,
      adm0_name,
      adm1_name,
      adm1_code,
      yr_date = lubridate$floor_date(date, "year")
    )
    df_mam <- dfg |>
      dplyr$summarise(
      value_sum = sum(value[lubridate$month(date)%in%c(3,4,5)]),
      value_mean = mean(value[lubridate$month(date)%in%c(3,4,5)]),
    ) |>
    dplyr$ungroup() |>
    dplyr$mutate(
      value = ifelse(stringr$str_detect(parameter,"precip"),value_sum,value_mean),
      parameter = ifelse(stringr$str_detect(parameter,"precip"),"era5_precip_mam_sum","era5_temp_mam_mean")
    ) |>
    dplyr$select(-value_sum,-value_mean)

    dfg <- dfg |>
      dplyr$mutate(
        mo = lubridate$month(date,label=T,abbr=T)
      )

    df_temp_month <- dfg |>
      dplyr$ungroup() |>
      dplyr$filter(
        stringr$str_detect(parameter,"temperature"),
        mo %in% c("Feb","Mar","Apr","May","Jun")
      ) |>
      dplyr$mutate(
        parameter = paste0("era5_temp_",mo)
      )
  df_cumu_precip <- dfg |>
    dplyr$arrange(date) |>
    dplyr$filter(
      stringr$str_detect(parameter,"precip"),
      mo %in% c("Feb","Mar","Apr","May","Jun")
    ) |>
    dplyr$mutate(
      value = cumsum(value),
      parameter = paste0("era5_cumu_precip_", lubridate$month(date,label=T,abbr=T))
    )
  dplyr$bind_rows(
    df_mam,
    df_cumu_precip,
    df_temp_month
  ) |>
    dplyr$select(
      adm0_code,
      adm0_name,
      adm1_name,
      adm1_code,
      yr_date,
      value, parameter
    ) |>
    dplyr$ungroup()
}


wrangle_era5_land <- function(df){
  df |>
    janitor$clean_names() |>
    dplyr$group_by(
      parameter,
      adm0_code,
      adm0_name,
      adm1_name,
      adm1_code,
      yr_date = lubridate$floor_date(date, "year")
    ) |>
    dplyr$mutate(
      mo = lubridate$month(date,label=T,abbr=T)
    ) |>
    dplyr$filter(
     mo %in% c("Feb","Mar","April","May")
    ) |>
    dplyr$mutate(
      parameter = paste0(parameter,"_", lubridate$month(date,label=T,abbr=T))
    ) |>
    dplyr$ungroup()
}
wrangle_modis_ndvi <- function(df){
  df_mo <- df |>
    janitor$clean_names() |>
    dplyr$group_by(
      parameter,
      adm0_code,
      adm0_name,
      adm1_name,
      adm1_code,
      yr_date = lubridate$floor_date(date, "year")
    ) |>
    dplyr$mutate(
      mo = lubridate$month(date,label=T,abbr=T)
    ) |>
    dplyr$filter(
     mo %in% c("Mar","Apr","May")
    ) |>
    dplyr$mutate(
      parameter = paste0(parameter,"_", lubridate$month(date,label=T,abbr=T))
    ) |>
    dplyr$ungroup()

  df_mam <- df |>
    janitor$clean_names() |>
    dplyr$group_by(
      parameter,
      adm0_code,
      adm0_name,
      adm1_name,
      adm1_code,
      yr_date = lubridate$floor_date(date, "year")
    ) |>
    dplyr$mutate(
      mo = lubridate$month(date,label=T,abbr=T)
    ) |>
    dplyr$summarise(
      value =  mean(value[mo%in%c("Mar","Apr","May")])
    ) |>
    dplyr$mutate(
      parameter = "modis_ndvi_mam_mean"
    ) |>
    dplyr$ungroup()

  dplyr$bind_rows(
    df_mam,
    df_mo
  ) |>
    dplyr$select(
      adm0_code,
      adm0_name,
      adm1_name,
      adm1_code,
      yr_date,
      value,
      parameter
    )
}

wrangle_monthly_generic <- function(df,months = c(12,1,2,3,4,5)){
  df |>
    janitor$clean_names() |>
    dplyr$group_by(
      parameter,
      adm0_code,
      adm0_name,
      adm1_name,
      adm1_code,
      yr_date = lubridate$floor_date(date, "year")
    ) |>
    dplyr$mutate(
      mo_num = lubridate$month(date)
    ) |>
    dplyr$filter(
      mo_num %in% months
    ) |>
    dplyr$mutate(
      parameter = paste0(parameter,"_", lubridate$month(date,label=T,abbr=T))
    ) |>
    dplyr$ungroup()
}

append_aggregate <-  function(df,months_aggregatee){
  months_aggregate_label <- lubridate$month(months_aggregatee,label=T,abbr=T)
  df_agg <- df |>
    janitor$clean_names() |>
    dplyr$group_by(
      parameter,
      adm0_code,
      adm0_name,
      adm1_name,
      adm1_code,
      yr_date = lubridate$floor_date(date, "year")
    ) |>
    dplyr$mutate(
      mo_label = lubridate$month(date,label=T,abbr=T)
    ) |>
    dplyr$summarise(
      value =  mean(value[mo_label%in% months_aggregate_label])
    ) |>
    dplyr$mutate(
      parameter = "modis_ndvi_mam_mean"
    ) |>
    dplyr$ungroup()

  dplyr$bind_rows(
    df,
    df_agg
  ) |>
    dplyr$select(
      adm0_code,
      adm0_name,
      adm1_name,
      adm1_code,
      yr_date,
      value,
      parameter
    )
}



load_all_environmental_data <- function(){

  bps <- blob_connect$proj_blob_paths()

  df_ndvi <- cumulus$blob_read(
    name = bps$DF_ADM1_MODIS_NDVI_CROPS,
    stage= "dev"
  ) |>
    wrangle_modis_ndvi()

  df_fao <- load_fao_vegetation_data() |>
    wrangle_fao()

  df_chirps <-   cumulus$blob_read(
    name = bps$DF_ADM1_CHIRPS,
    stage= "dev"
  ) |>
    wrangle_chirps()

  df_ndsi <- cumulus$blob_read(
    bps$DF_ADM1_MODIS_SNOW,
    stage= "dev"
    ) |>
    dplyr$filter(parameter == "NDSI_Snow_Cover_mean") |>
    wrangle_monthly_generic(months = c(12,1,2,3,4,5)) |>
    append_aggregate(months_aggregatee = c(2,3,4))

  df_swe <- cumulus$blob_read(
    bps$DF_ADM1_FLDAS_SWE,
    stage= "dev"
    ) |>
    wrangle_monthly_generic(months = c(12,1,2,3,4,5)) |>
    append_aggregate(months_aggregatee = c(2,3,4))


  df_era5_land = load_era5_land_multiband() |>
    wrangle_era5_land()

  df_era5 <-  cumulus$blob_read(
    name = bps$DF_ADM1_ERA5_TEMP_PRECIP,
    stage= "dev"
  ) |>
    wrangle_era5()

  ldf_raw <-  list(
    chirps = df_chirps,
    ndvi =  df_ndvi,
    fao  = df_fao,
    era5 = df_era5,
    ndsi = df_ndsi,
    swe = df_swe,
    era5_land = df_era5_land
  )


  ldf_raw |>
    purrr$map(
      \(dft) {
        dftc <- dft |>
        janitor$clean_names() |>
          dplyr$select(
            dplyr$any_of(c("yr_date","adm1_code","adm1_name","value","parameter"))
          )
      }
    ) |>
    purrr$list_rbind()
}
