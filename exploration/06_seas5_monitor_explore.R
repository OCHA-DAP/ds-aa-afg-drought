

box::use(
  ../R/blob_connect,
  ../R/utils[download_fieldmaps_sf]
)

box::use(
  dplyr[...],
  forcats[...],
  ggplot2[...],
  gghdx,
  DBI,
  RPostgres,
  janitor[clean_names],
  lubridate[...],
  purrr,
  readr,
  scales,
  stats,
  stringr,
  tidyr[...]
)
gdf <- download_fieldmaps_sf("AFG","afg_adm1")
gdf <- gdf |>
  clean_names()

gghdx$gghdx()

con <- DBI$dbConnect(
  drv = RPostgres$Postgres(),
  user = Sys.getenv("AZURE_DB_USER_ADMIN"),
  host = Sys.getenv("AZURE_DB_HOST"),
  password = Sys.getenv("AZURE_DB_PW"),
  port = 5432,
  dbname = "postgres"
)
# DBI::dbListTables(con)
# tbl(con,"iso3")

db_faryab <- tbl(con, "seas5") |>
  filter(
    iso3 == "AFG",
    adm_level ==1,
    pcode == "AF29"
  ) |>
  collect()




df_mam <- db_faryab |>
  mutate(
    precipitation = mean *days_in_month(valid_date)
  ) |>
  filter(
    month(valid_date) %in% c(3:5)
  ) |>

  group_by(
    pub_date = issued_date,
    valid_year = year(valid_date)
  ) |>
  arrange(issued_date) |>
  filter(
    year(valid_date)>1984
  ) |>
  print(n=20) |>
  mutate(
    n=n()
  )

  filter(
    n() == 3
  ) |>
  summarize(
    precipitation = sum(precipitation),
    leadtime = min(leadtime),
    pub_month = month(min(issued_date)),
    .groups = "drop"
  ) |>
  filter(
    # valid_year >= 1984
  ) |>
  group_by(
    leadtime
  ) |>
  arrange(
    pub_date
  )


  df_mam |>
    ggplot(
      aes(x= precipitation)
    )+
    geom_histogram()


  #'. some decent difference b/w lts .... bias is not super uniderctional
  df_mam |>
    ggplot(
      aes(y= precipitation, x = as_factor(leadtime),fill = as_factor(leadtime))
    )+
    geom_boxplot()

ma_valid <- c(3,4)

df_ma <- db_faryab |>
  mutate(
    precipitation = mean *days_in_month(valid_date)
  ) |>

  filter(year(valid_date)>1981) |>
    group_by(issued_date) %>%
    filter(
      month(valid_date) %in% ma_valid,
      all(ma_valid %in% month(valid_date))
      ) |>
    arrange(
     issued_date, leadtime
    ) |>
    group_by(issued_date) |>
    mutate(
      count = length(unique(leadtime))
    ) |>
  arrange(issued_date) |>
    summarise(
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
    )

df_ma_oct <- df_ma |>
  filter(
    month(issued_date)==10
  ) |>
  mutate(
    latest_forecast = year(issued_date)==2024
  )

df_ma_oct_rp <- df_ma_oct |>
  arrange(mm) |>
  mutate(
    rank = row_number(),
    q_rank = rank/(nrow(df_ma_oct)+1),
    rp_emp = 1/q_rank,

  )

# rp_func = approxfun(df_ma_oct_rp$mm, df_ma_oct_rp$rp_emp, rule=2)
rp_func = approxfun( df_ma_oct_rp$rp_emp, df_ma_oct_rp$mm,rule=2)




df_ma_oct |>
  filter(year(issued_date)==2024)

df_ma_oct |>
  ggplot(
    aes(x=as_factor(1), y= mm, color = latest_forecast, size = latest_forecast)
  )+
  geom_jitter(width = 0.1, alpha=0.5)+
  geom_hline(
    yintercept = rp_func(c(3,5,10))
  )+
  theme(
    axis.title.x = element_blank(),
    axis.text.x = element_blank(),
    legend.position = "none"
  )


# correlate ths w/ 5 year rp for MAM
# at any time step
df_ma_oct |>
  mutate(
    issue_year=year(issued_date),
    valid_year = issue_year +1,
    ckt= mm<=106
  )


df_mam |>
  mutate(
    valid_year = year(valid_date)
  )

df_ma_oct |>
  ggplot(
    aes(x= issued_date, y= mm, color = color)
  )+
  geom_point()+
  geom_line()+
  geom_hline(yintercept = mean(df_ma_oct$mm))






db_faryab |>
  mutate(
    precipitation = mean * days_in_month(valid_date)
  ) |>
  filter(
    month(valid_date) %in% c(3:4)
  ) |>
  group_by(
    pub_date = issued_date,
    valid_year = year(valid_date)
  ) |>
  arrange(pub_date,pub_date) |>
  print(n =20)
  filter(
    n() == 4
  ) |>
  summarize(
    precipitation = sum(precipitation),
    leadtime = min(leadtime),
    pub_month = month(min(issued_date)),
    .groups = "drop"
  ) |>
  filter(
    # valid_year >= 1984
  ) |>
  group_by(
    leadtime
  ) |>
  arrange(
    pub_date
  )
