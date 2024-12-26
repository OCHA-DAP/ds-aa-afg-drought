box::use(
  dplyr,
  cumulus,
  rlang
)
upsampled_pixel_col <- function(ds_name){
  switch(
    ds_name,
    "seas5"= "seas5_n_upsampled_pixels",
    "era5" = "era5_n_upsampled_pixels",
    "imerg" = "imerg_n_upsampled_pixels"
  )
}


#' @export
get_pixel_counts <- function(
    conn = NULL,
    adm_level,
    pcode,
    ds_name= c("seas5","era5","imerg")
){
  ds_name <- rlang$arg_match(ds_name)
  if(is.null(conn)){
    conn <- cumulus$pg_con()
  }

  dplyr$tbl(conn,"polygon") |>
    dplyr$filter(
      adm_level == {{adm_level}},
      pcode %in% c({{pcode}})
    ) |>
    dplyr$select(
      dplyr$all_of(c("iso3", "adm_level","pcode", n_upsampled_pixels = upsampled_pixel_col(ds_name)))
    ) |>
    dplyr$collect() |>
    dplyr$mutate(
      dataset = ds_name
    )
}
