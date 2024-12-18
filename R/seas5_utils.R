box::use(
  dplyr,
  lubridate,
  glue
)

#' @export
aggregate_forecast <-  function(df,valid_months=c(3,4,5), by = c("iso3", "pcode","issued_date")){
  soi <- glue$glue_collapse(lubridate$month(valid_months,abbr=T,label =T),sep = "-")
  df |>
    dplyr$group_by(dplyr$across(dplyr$all_of(by))) |>
    dplyr$filter(
      lubridate$month(valid_date) %in% valid_months,
      all(valid_months %in% lubridate$month(valid_date))

    ) |>
    dplyr$summarise(
      mm = sum(precipitation),
      # **min() - BECAUSE**  for MJJA (5,6,7,8) at each pub_date we have a set of leadtimes
      # for EXAMPLE in March we have the following leadtimes 2
      # 2 : March + 2 = May,
      # 3 : March + 3 = June,
      # 4 : March + 4 = July
      # 5:  March + 5 = Aug
      # Therefore when we sum those leadtime precip values we take min() of lt integer so we get the leadtime to first month being aggregated
      leadtime = min(leadtime),
      .groups = "drop"
    ) |>
    dplyr$arrange(issued_date) |>
    dplyr$mutate(
      valid_month_label = soi
    )
}
