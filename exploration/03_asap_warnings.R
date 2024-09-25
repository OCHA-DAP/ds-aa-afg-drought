box::use(
  dplyr,
  gg = ggplot2,
  gghdx,
  lubridate,
  readr,
  readxl,
  tidyr,
  utils
)

box::use(
  ../R/blob_connect
)

gghdx$gghdx()

#######################
#### DOWNLOAD DATA ####
#######################

utils$download.file(
  url = "https://agricultural-production-hotspots.ec.europa.eu/files/warnings_ts.zip",
  destfile = zf <- tempfile(fileext = ".zip")
)

utils$unzip(
  zipfile = zf,
  exdir = td <- tempdir()
)

df_warnings <- readr$read_delim(
  file = file.path(td, "warnings_ts.csv"),
  delim = ";"
)

#############################
#### BRING IN EMDAT DATA ####
#############################

# provided directly by the Afghanistan team by email
# pre-processed to all drought disasters type in Afghanistan
df_emdat <- blob_connect$read_blob_file("DF_EMDAT")

################################
#### FILTER TO FARYAB CROPS ####
################################

# you can check the `w_crop_na` column to see what the warnings correspond to,
# but basically the second digit (or only digit) corresponds to the warning level
# so 0 and 20 are no warning/successful season, and so on.

df_faryab <- df_warnings |> 
  dplyr$filter(
    asap1_name == "Faryab"
  ) |> 
  dplyr$mutate(
    crop_warning = ifelse(
      w_crop > 20,
      0,
      w_crop %% 10 # just the last digit indicates warning level
    )
  )

#############################
#### GET DATES OF ALERTS ####
#############################

# get consecutive dates where warning levels are 9 from ASAP
df_alert_9 <- df_faryab |> 
  dplyr$arrange(
    desc(date)
  ) |> 
  tidyr$complete(
    date = seq.Date(min(date), max(date), by = "day")
  ) |> 
  tidyr$fill(
    crop_warning,
    .direction = "down"
  ) |> 
  dplyr$filter(
    crop_warning == 9
  ) |> 
  dplyr$mutate(
    date_group = cumsum(date - dplyr$lag(date, default = min(date)) != 1)
  ) |>
  dplyr$group_by(
    date_group
  ) |> 
  dplyr$summarize(
    dataset = "JRC ASAP",
    start_date = min(date),
    end_date = max(date),
    .groups = "drop"
  ) |> 
  dplyr$select(
    -date_group
  )

# get emdat data in same format
df_emdat_span <- df_emdat |> 
  dplyr$mutate(
    `End Month` = tidyr$replace_na(`End Month`, 12)
  ) |> 
  dplyr$transmute(
    dataset = "EMDAT",
    start_date = as.Date(paste(`Start Year`, `Start Month`, "01", sep = "-")),
    end_date = as.Date(paste(`End Year`, `End Month`, "01", sep = "-")) + months(1) - lubridate$days(1),
  )

#################################
#### PLOT THE SPANS TOGETHER ####
#################################

df_span <- dplyr$bind_rows(df_alert_9, df_emdat_span)

# for years covered, get the sowing to harvest period for spring wheat
df_season <- df_span |> 
  dplyr$transmute(
    start_year = lubridate$year(start_date),
    end_year = lubridate$year(end_date)
  ) |> 
  tidyr$pivot_longer(
    cols = everything(),
    values_to = "year"
  ) |> 
  dplyr$distinct(
    year
  ) |> 
  dplyr$mutate(
    start_date = as.Date(paste(year, "05", "01", sep = "-")),
    end_date = as.Date(paste(year, "07", "31", sep = "-")),
  )
  

gg$ggplot() +
  gg$geom_rect(
    data = df_season,
    mapping = gg$aes(
      xmin = start_date,
      xmax = end_date
    ),
    ymin = -Inf,
    ymax = Inf,
    fill = "#fafafa"
  ) +
  gg$geom_segment(
    data = df_span,
    mapping = gg$aes(
      x = start_date,
      xend = end_date,
      y = dataset,
      yend = dataset
    ),
    linewidth = 2
  ) +
  gghdx$scale_color_hdx_tomato() +
  gg$geom_text(
    x = as.Date("2010-01-01"),
    y = 1.5,
    label = "Spring wheat season",
    hjust = 0,
    vjust = 0,
    check_overlap = FALSE
  ) +
  gg$labs(
    x = "",
    y = ""
  )
