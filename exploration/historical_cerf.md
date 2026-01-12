---
jupyter:
  jupytext:
    formats: ipynb,md
    text_representation:
      extension: .md
      format_name: markdown
      format_version: '1.3'
      jupytext_version: 1.16.1
  kernelspec:
    display_name: ds-aa-afg-drought
    language: python
    name: ds-aa-afg-drought
---

# Historical CERF

```python
%load_ext jupyter_black
%load_ext autoreload
%autoreload 2
```

```python
import pandas as pd
```

```python
data = [
    (2021, 14998459),  # Apr 2021
    (2018, 11937469),  # Aug 2018
    (2007, 8002060),  # Feb 2008
    (2006, 19536289),  # Dec 2006
    (2006, 12768338),  # Aug 2006
]
```

```python
df_cerf = pd.DataFrame(data=data, columns=["year", "amount"])
```

```python
df_cerf_yearly = df_cerf.groupby("year").sum().reset_index()
```

```python
total_years = 2024 - 2006 + 1
```

```python
total_years
```

```python
(total_years + 1) / len(df_cerf_yearly)
```

```python
f'{df_cerf_yearly["amount"].mean():,.0f}'
```

```python
f'{df_cerf_yearly["amount"].sum():,.0f}'
```

```python
f'{df_cerf_yearly["amount"].sum() / total_years:,.0f}'
```

```python

```
