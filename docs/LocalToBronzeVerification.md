# Local SQL Server → Bronze ADLS Verification Guide

## Context

| Item | Detail |
|---|---|
| **Source** | SQL Server Express (local), `AdventureWorksLT2019`, schema `Sales`, 19 tables |
| **Sink** | ADLS Gen2, container `bronze`, path `bronze/Sales/TableName.parquet`, Snappy-compressed Parquet |
| **Pipeline** | ADF: Lookup + ForEach + Copy activity (`pl-ingestion-sqlserver-to-bronze`) |
| **Databricks** | Not available until Phase 7 |

---

## Current Manual Verification Options

### 1. Row Count via ADF Monitor
- ADF Studio → Monitor → Pipeline runs → last run
- Click each `copytabletobronze` activity → Output tab
- Check `rowsRead` (from SQL) == `rowsCopied` (to parquet)
- ⚠️ Must click each of 19 activities **individually** — no bulk view

### 2. SQL Side Row Counts (SSMS)
```sql
USE AdventureWorksLT2019;
SELECT 
    s.name AS SchemaName,
    t.name AS TableName,
    p.rows AS RowCount
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
JOIN sys.partitions p ON t.object_id = p.object_id
WHERE s.name = 'Sales' AND p.index_id IN (0,1)
ORDER BY t.name;
```
- ✅ Returns all 19 counts at once
- ❌ No way to read parquet side from SSMS

### 3. Parquet Side via ADF Dataset Preview
- Open `ds_adls_bronze_parquet` → Preview data
- ⚠️ Shows **max 10 rows only** — no row count, no aggregates

---

## What Is NOT Possible Without Databricks

| Check | Available? |
|---|---|
| Total parquet row count | ❌ |
| Null checks | ❌ |
| Min / Max value checks | ❌ |
| Schema / column type validation | ❌ |
| Side-by-side SQL vs parquet comparison | ❌ |

---

## Recommended: Ask ChatGPT / Research

**Question to ask:**
> What is the easiest way to verify bronze Parquet files in ADLS Gen2 against a local SQL Server source — including row count, null checks, min/max — without Databricks, using tools like Azure CLI, PowerShell, Python (pyarrow/pandas), or ADF Data Flow?

---

## Enterprise Recommendation: Databricks + PySpark ✅

Per modern Azure data engineering standards, Databricks is the enterprise-level validation tool.
Run `validate_bronze` notebook (Phase 7, step 7.5) **before** any silver transformation.

**ADF orchestrates the full automated flow:**
```
Lookup → ForEach (copytabletobronze ×19) → nbbronzevalidate → nbbronzetosilver → nbsilvertogold
```
ADF stops the pipeline if `nbbronzevalidate` fails — silver never runs on bad data.

Typical enterprise validation includes:
- Row count checks
- Schema drift detection
- Null thresholds
- Duplicate detection
- Business rules / anomaly detection

Common frameworks: Great Expectations, Delta Live Tables expectations, custom PySpark QA.

---

## Phase 7 Bronze Validation (Databricks) — validate_bronze.ipynb

Once Databricks is set up, run a validation notebook **before** any silver transformation:

```python
from pyspark.sql import functions as F

tables = ["CountryRegionCurrency", "CreditCard", "Currency", ...]  # all 19

for table in tables:
    df = spark.read.parquet(f"{BRONZE}/Sales/{table}.parquet")
    print(f"\n=== {table} ===")
    print(f"  Row count : {df.count()}")
    print(f"  Null check: {df.select([F.count(F.when(F.col(c).isNull(), c)).alias(c) for c in df.columns]).show()}")
    df.select([F.min(c).alias(f'min_{c}') for c in df.columns if dict(df.dtypes)[c] in ('int','double','long')]).show()
    df.select([F.max(c).alias(f'max_{c}') for c in df.columns if dict(df.dtypes)[c] in ('int','double','long')]).show()
```
