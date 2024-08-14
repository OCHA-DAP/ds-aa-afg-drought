# Process Funcs -----------------------------------------------------------
zonal_tidy <-  function(
    r,
    geom,
    geom_cols_keep = NULL,
    stat = "mean"
) {

  df_stats_wide <- exactextractr::exact_extract(
    x = r,
    y = geom,
    fun =stat,
    append_cols= geom_cols_keep,
    force_df = TRUE
  )

  df_stats_wide |>
    tidyr::pivot_longer(
      cols = dplyr::starts_with(stat)
    )
}
