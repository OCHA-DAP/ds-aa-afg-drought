
<!-- README.md is generated from README.Rmd. Please edit that file -->

# ds-aa-afg-drought

<!-- badges: start -->
<!-- badges: end -->

This repo contains analysis/exploratory analysis of climatic variables
in Afghanistan related to potential AA activities.

## Background Info

22 April 2024, work began with the objective of exploring potential ways
to monitor drought in Afghanistan in the context of Anticipatory Action
(AA) activities.

As of now, the only the visuals/analysis that has been shared or
discussed with partners are the quarto documents in the exploration
folder.

Quarto outputs for sharing will be linked as the one below:

[1. Exploratory - Exploration of Climate
indicators](https://rpubs.com/zackarno/1176973)

[2. Exploratory - Prioritization support (rainfall +
IPC)](https://rpubs.com/zackarno/1200340)

## Overview of Analysis

TBD

## Data description

TBD

## Directory structure

The code in this repository is organized as follows:

``` shell
├── R                                           # general R functions
│   ├── blob_connect.R
│   ├── load_funcs.R
│   ├── raster_utils.R
│   ├── utils.R
│   ├── utils_gee.R
│   └── zonal_tidy.R
├── README.Rmd
├── README.md
├── _targets.R                                  # analytical pipeline scripts
├── data-raw                                    # scripts to download process
│   ├── 01_download_ecmwf_mars_gribs.py         # any data required for
│   ├── 02_process_mars_gribs_to_COGS.py        # analysis
│   ├── 03_adm_boundary_parquets.R
│   ├── 04_wfp-adm2-climate-data.R
│   └── explore_climate_indicators              # data sets created in GEE -
│       ├── 01_gee_chirps_adm1.R                # required for exploration/01_*
│       ├── 02_gee_modis_ndvi_crops_adm1.R
│       └── 03_gee_modis_snow_cover.R
├── ds-aa-afg-drought.Rproj
├── exploration                                 # exploratory analysis
│   ├── 01_explore_climate_indicators.qmd
│   ├── 02_prioritization_rainfall.qmd
├── requirements.txt
├── src                                         # general python funcs &
    └── blob_utils.py                           # scripts to run monitoring
                                                # system pipeline


```

## Development

TBD
