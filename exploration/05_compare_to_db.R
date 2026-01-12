

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
"duffel-algebra-rebound7"
"chd-admin"
duffel-algebra-rebound7
AZURE_DB_HOST

con <- DBI$dbConnect(
  drv = RPostgres$Postgres(),
  user = Sys.getenv("AZURE_DB_USER_ADMIN"),
  host = "chd-rasterstats-prod.postgres.database.azure.com",
  password = "duffel-algebra-rebound7",
  port = 5432,
  dbname = "postgres"
)
DBI::dbListTables(con)
# tbl(con,"iso3")

db_faryab <- tbl(con, "seas5") |>
  filter(
    iso3 == "AFG",
    adm_level ==1,
    pcode == "AF29"
    ) |>
  collect()

df_faryab <- blob_connect$read_blob_file("DF_FARYAB_SEAS5") |>
  mutate(
    valid_month = month(valid_date),
    valid_year = year(valid_date)
  ) |>
  mutate(
    method = "terra"
  )


faryab_from_db <- db_faryab |>
  mutate(
    valid_month = month(valid_date),
    valid_year = year(valid_date),
    pub_date = valid_date - months(as.numeric(leadtime))
  ) |>
  arrange(pub_date) |>
  rename(
    precip_mm_day= mean
  ) |>
  select(
    any_of(colnames(df_faryab))
  ) |>
  mutate(
    method = "DB"
  )


df_faryab$pub_date |> range()
df_rb <- bind_rows(
  df_faryab ,
  faryab_from_db
)

df_rb |>
  ggplot(
    aes(x= valid_date, y= precip_mm_day, color= method,group=method)
  )+
  geom_point(size =0.5,alpha=0.4)+
  geom_line(alpha=0.4)+
  facet_wrap(~leadtime)

df_rb |>
  pivot_wider(
    names_from = method, values_from = precip_mm_day
  ) |>
  ggplot(
    aes(x= terra, y= DB)
  )+
  geom_line(alpha=0.4,lwd= 2)+
  geom_point(size =2,alpha=1)+

  facet_wrap(~leadtime)+
  geom_abline(slope=1, color ="red")


df_rb |>
  group_by(method) |>
  filter(leadtime == 1)


df_wide <- df_rb |>
  filter(
    valid_month %in% 3:5
  ) |>
  group_by(
    method,
    pub_date,
    valid_year
  ) |>
  filter(
    n() == 3
  ) |>
  summarize(
    precipitation = mean(precip_mm_day),
    leadtime = min(leadtime),
    pub_month = month(min(pub_date)),
    .groups = "drop"
  ) |>
  filter(
    valid_year >= 1984, year(pub_date)<=2023
  ) |>
  group_by(
    method,leadtime
  ) |>
  arrange(
    precipitation,
    .by_group = TRUE
  ) |>
  mutate(
    rank = dense_rank(precipitation)
  ) |>
  pivot_wider(
    id_cols = c(valid_year, leadtime, pub_date),
    names_from = method,
    values_from = c("rank","precipitation")
  )

df_wide |>
  group_by(leadtime,`Year (ranked)` =rank_DB) |>
  summarise(
    n=n()
  ) |>
  filter(n>1)

p1 <- df_wide |>
  mutate(diff = precipitation_terra -  precipitation_DB) |>
  ggplot(
    aes(x= as.character(leadtime), diff)
  )+
  geom_boxplot()+
  geom_jitter(alpha=0.2, color = "black",width = 0.15)+
  labs(
    # title = "SEAS5 MAM Precipitation in Faryab Afghanistan",
    subtitle = "(terra values)-(DB values): Always negative, DB is always greater"
  )

p1
p2 <- df_wide |>
  pivot_longer(
    cols = c(precipitation_terra, precipitation_DB),
    names_to = "method",
    values_to = "precipitation"
  ) |>
  ggplot(
    aes(x= as.character(leadtime), y= precipitation,fill = method)
  )+
  geom_boxplot()+
  scale_fill_brewer()+
  labs(
    title = "SEAS5 MAM Precipitation in Faryab Afghanistan",
    subtitle = "Comparison of Admin 1 Zonal Extracttions"
  )
box::use(patchwork[...])

p2 +
  p1  +
  plot_layout(nrow=2)

df_wide |>
  group_by(leadtime,rank_terra) |>
  summarise(
    n=n()
  ) |>
  filter(n>1)

box::use(gt)
df_wide  |>
  mutate(
    rank_neq = rank_terra!=rank_DB,
    rank_eq = rank_terra == rank_DB ,
    rank_terra_gt  = rank_terra>rank_DB,
    rank_db_gt = rank_DB> rank_terra
  ) |>
  filter(rank_neq) |>
  mutate(
    rank_diff = rank_terra - rank_DB
  ) |>
  ungroup() |>
  arrange(valid_year) |>
  gt$gt() |>
  gt$cols_hide(
    columns = c("rank_eq", "rank_neq", "rank_db_gt", "rank_terra_gt")
  )
  group_by(leadtime) |>
  summarise(
    mean(rank_neq,na.rm=T)
  )

df_wide |>
  filter(is.na(rank_DB))

ggplot(
    aes(x= rank_DB, y= n)
  )+
  geom_bar(stat= "identity")+
  facet_wrap(~leadtime)
  arrange(desc(n))


?dense_rank
  dplyr$slice(
    1:8 # 1 in 5 year RP
  ) |>
  dplyr$ungroup() |>
  dplyr$transmute(
    indicator = "SEAS5",
    year = valid_year,
    leadtime,
    pub_month
  )
