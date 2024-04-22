proj_paths <-  function(){
  list(
    "ADM1_GAUL"= file.path(
      Sys.getenv("AA_DATA_DIR"),
      "public",
      "raw",
      "eth","gaul",
      "gaul1_asap_v04"),
    
    "ADM1_CHIRPS_MONTHLY"= file.path(
      Sys.getenv("AA_DATA_DIR_NEW"),
      "public",
      "processed",
      "afg",
      "chirps_monthly_afg_adm1_historical.csv"
    ) ,
    "ONI_LINK"= "https://origin.cpc.ncep.noaa.gov/products/analysis_monitoring/ensostuff/detrend.nino34.ascii.txt"
  )
    
}

