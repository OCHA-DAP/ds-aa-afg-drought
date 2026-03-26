# ds-aa-afg-drought

Anticipatory Action framework for drought in Afghanistan. Develops and operationalizes drought triggers for two decision windows using seasonal forecasts and observational indicators across five northern provinces (Badghis, Balkh, Faryab, Jawzjan, Sar-e-Pul).

## Background

Work began in April 2024 exploring potential ways to monitor drought in Afghanistan for Anticipatory Action (AA). The framework was first implemented operationally in 2025 (3 provinces, per-province CDI thresholds), then updated and re-endorsed for 2026 with a revised trigger design (5 merged provinces, ridge-based CDI, two-stage OR logic).

## Framework

The 2026 trigger system uses **OR logic** across two windows:

- **Window 1 (March)**: SEAS5 seasonal precipitation forecast — triggers if area-weighted MAM forecast falls below RP6 threshold
- **Window 2 (April)**: Combined Drought Indicator (CDI) from ridge regression on 5 z-scored indicators (ASI, VHI, snow cover, soil moisture, mixed obs/forecast precipitation) — triggers if CDI exceeds F1-optimized threshold

A year activates if **either** window fires.

## Repository Structure

| Directory | Description |
|---|---|
| `book_afg_analysis/` | Quarto book documenting the full analysis: indicator exploration, model development, trigger optimization, and threshold proposals |
| `src/monitoring_2026/` | Python monitoring scripts for W1 (SEAS5) and W2 (CDI) with email notifications via Listmonk |
| `src/trigger_monitoring/` | ERA5 monthly data ingestion from GEE, plus legacy R monitoring scripts |
| `data-raw/` | One-time data preparation scripts (ERA5 historical download, feature set creation, etc.) |
| `R/` | Shared R utility functions (data loaders, z-score helpers, blob I/O) |
| `.github/workflows/` | GitHub Actions for automated monitoring |

## Docs

- [Monitoring Workflows](.github/MONITORING.md) — operational runbook for the GHA pipelines (when to run, in what order, secrets required)

## Setup

**R** (analysis book, data preparation):
- R 4.x with dependencies managed via `renv` / manual install
- `cumulus` and `gghdx` packages (internal OCHA tools)

**Python** (monitoring scripts, ERA5 ingestion):
```bash
uv sync   # installs from pyproject.toml / uv.lock
```
