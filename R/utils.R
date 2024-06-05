proj_paths <-  function(){
  
  AA_DIR_NEW <- Sys.getenv("AA_DATA_DIR_NEW")
  AA_DIR_OLD <- Sys.getenv("AA_DATA_DIR")
  
  PUB_PROCESSED_AFG <-   file.path(
    AA_DIR_NEW ,
    "public",
    "processed",
    "afg"
  )
  PUB_RAW_AFG <-   file.path(
    AA_DIR_NEW,
    "public",
    "raw",
    "afg"
  )
  
  PUB_RAW_GLB <- file.path(
    AA_DIR_OLD,
    "public",
    "raw",
    "glb")
  
  
  list(
    "PUB_RAW_AFG" = PUB_RAW_AFG,
    "PUB_PROCESSED_AFG"= PUB_PROCESSED_AFG,
    "PUB_RAW_GLB" = PUB_RAW_GLB,
    "ADM1_GAUL"= file.path(
      PUB_RAW_GLB,
      "asap",
      "reference_data",
      "gaul1_asap_v04" ) ,
    
    "ADM2_GAUL"= file.path(PUB_RAW_GLB,
                           "asap",
                           "reference_data",
                           "gaul2_asap_v04" ) ,
    
    "ADM1_CHIRPS_MONTHLY"= file.path(
      PUB_PROCESSED_AFG,
      "chirps_monthly_afg_adm1_historical.csv"
    ) ,
    
    "ADM2_AFG_GAUL" = file.path(
      PUB_RAW_AFG,
      "afg_adm2_fao_gaul2015.rds"
    ),
    "ADM_TABULAR_COD"= file.path(
      PUB_RAW_AFG,
      "afg_adminboundaries_tabulardata.xlsx"
    ),
    "ADM1_MODIS_SNOW" = file.path(
      PUB_PROCESSED_AFG,
      "modis_snow_frac_monthly_afg_adm1_historical.csv"
    ),
    
    "ONI_LINK"= "https://origin.cpc.ncep.noaa.gov/products/analysis_monitoring/ensostuff/detrend.nino34.ascii.txt",
    
    "ASAP_ACTIVE_SEASON_RASTER" = file.path(
      Sys.getenv("AA_DATA_DIR"),
      "public",
      "processed",
      "glb",
      "asap",
      "season",
      "month"
    ),
    "ADM2_NDVI_WFP_HDX" = file.path(
      PUB_RAW_AFG,
      "afg-ndvi-adm2-full.csv"
    ),
    "FS_INDICATORS_FAO" = file.path(
      PUB_RAW_AFG,
      "suite-of-food-security-indicators_afg.csv"
    ),
    "AMD1_NDVI_CROP_MODIS" = file.path(
      PUB_PROCESSED_AFG,
      "modis_ndvi_2000_2004.csv"
    )
  )
  
}


#' oni_to_enso_class
#'
#' @param oni `numeric` 
#'
#' @return
#' @export
#'
#' @examples \dontrun{
#' df_oni <- read_table()
#' df_oni |> 
#'   mutate(
#'   enso_class = oni_to_enso_class(anom)
#'   )
#' }
oni_to_enso_class <-  function(x){
  x_class <- case_when(x<=-.5~"La Nina",
            x< 0.5~"Neutral",
            x>= 0.5 ~"El Nino")
  fct_relevel(x_class, "La Nina","Neutral","El Nino")
}

months_of_interest <- function(){
  list(
    winter_wheat = c(12,1,2,3,4)
  ) 
}


# update_theme_gghdx()
update_theme_gghdx <-  function(context = "rpubs"){
  if(context == "rpubs"){
    theme_update(
    plot.title = element_text(size=10),
    plot.subtitle  = element_text(size=10),
    axis.title = element_text(size=8),
    axis.text= element_text(size=8),
    plot.caption = element_text(hjust= 0, size=8),
    strip.text = element_text(size=8),
    axis.text.x = element_text(angle = 90, hjust = 1),
    legend.title  =element_blank()
  )
  }
  
}

proj_palettes <-  function(){
  list(
    "enso_palette" =  c("La Nina"= "#FBB4AE" ,
                        "El Nino" = "#B3CDE3" ,
                        "Neutral" ="#CCEBC5"
    )
  )
}

