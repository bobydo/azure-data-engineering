# Azure Data Engineering — Interview Preparation

> **Role:** Data Analyst / Data Engineer
> **Project:** AdventureWorks E2E Azure Data Pipeline
> **GitHub:** https://github.com/bobydo/azure-data-engineering

---

## 1. Elevator Pitch (30 seconds)

I built an end-to-end Azure data pipeline that extracts sales and customer data from an on-premises SQL Server (AdventureWorks), transforms it through a **medallion architecture** (Bronze → Silver → Gold) using Azure Data Factory and Databricks, and delivers KPI insights via a Power BI dashboard through Synapse Analytics.

Enterprise patterns applied: OAuth2 authentication via Key Vault (no hardcoded credentials), Delta Lake format for ACID-compliant transformations, CI/CD deployment of Databricks notebooks via GitHub Actions, and infrastructure-as-code for reproducible multi-environment provisioning.

---

## 2. Architecture

```
On-Premises SQL Server (AdventureWorks — 19 Sales tables)
        │
        │  Azure Data Factory + Self-hosted Integration Runtime
        │  Lookup → ForEach → Copy (Parquet, parallel ×4)
        ▼
ADLS Gen2 — Bronze Layer  (raw Parquet, schema preserved)
        │
        │  Databricks: validate_bronze (row counts, nulls, min/max)
        │  Databricks: bronze_to_silver (datetime → date string, Delta)
        ▼
ADLS Gen2 — Silver Layer  (cleansed Delta Lake)
        │
        │  Databricks: silver_to_gold (PascalCase → snake_case, Delta)
        ▼
ADLS Gen2 — Gold Layer    (analytics-ready Delta Lake)
        │
        │  Azure Synapse Analytics (serverless SQL views — no dedicated pool)
        ▼
Power BI Dashboard        (gender split, revenue by category, slicers)
```

---

## 3. Azure Resources — What & Why

Provisioned via `bash infra/provision_step1.sh dev` (idempotent, multi-environment).

| Resource | Type | Purpose |
|---|---|---|
| `adf-data-260524-dev` | Data Factory | Orchestrate ingestion pipeline (Lookup + ForEach + Copy) |
| `sadataeng260524dev` | ADLS Gen2 | Store Bronze / Silver / Gold data layers |
| `dbw-data-engineering-dev` | Databricks workspace | PySpark transformation + Delta Lake writes |
| `kv-dataengproj-dev` | Key Vault | Securely store SP credentials + Databricks PAT |
| `synapse-dataeng-dev` | Synapse Analytics | Serverless SQL views over Gold Delta files |
| `ir-selfhosted-dev` | Integration Runtime | Bridge on-premises SQL Server → ADF cloud |
| `email-me-dev` | Action Group | ADF pipeline failure email alerts |

**Why Key Vault?** Service Principal credentials (client ID, secret, tenant ID) are read at runtime via `dbutils.secrets.get()` — never stored in notebooks or committed to Git.

**Why Self-hosted IR?** ADF cloud cannot reach on-premises SQL Server directly. The IR is installed as a Windows service on the same machine as SQL Server, making outbound HTTPS calls to ADF.

---

## 4. Implementation Flow

| Phase | Stage | How |
|---|---|---|
| 1–4 | ⚙️ Provision all Azure resources + store secrets | `bash infra/provision_step1.sh dev` |
| 5 | 🔌 Connect local machine → ADF | Install Self-hosted IR (Windows service) |
| 6 | 📥 Load SQL Server → Bronze | ADF Studio: linked services + Lookup/ForEach pipeline |
| 7 | ⚙️ Transform Bronze → Silver → Gold | Databricks + Delta Lake (CI/CD deploys notebooks) |
| 8 | 🔑 Store Databricks PAT so ADF can trigger notebooks | `bash infra/databricks-token_step4.sh dev` |
| 9 | 🔗 Orchestrate full pipeline end-to-end | ADF: add 3 Databricks Notebook activities |
| 10 | 🗄️ Expose Gold as SQL views | Synapse Studio: serverless SQL + stored procedure |
| 11 | 📊 KPI dashboard + scheduled daily refresh | Power BI Desktop → Synapse endpoint |

**CI/CD:** Every push to `main` triggers GitHub Actions (`databricks-deploy.yml`) which deploys all `.ipynb` notebooks and `lib/` Python files to the Databricks workspace via REST API — no manual upload needed.

---

## 5. Troubleshooting Stories

### Story 1 — Databricks Library Import: OSError [Errno 95]

**Situation:**  
I built an enterprise shared library (`bobydo.AdlsAuth`) encapsulating ADLS Gen2 OAuth2 authentication — logging, secret validation, Spark config, path helpers. CI/CD deployed it to the Databricks workspace under `/Workspace/notebooks/lib/bobydo/`. When notebooks tried to `import bobydo`, Python raised `OSError [Errno 95]: Operation not supported`.

**Task:**  
Make the shared library importable across all notebooks without duplicating authentication code in every notebook.

**Action:**  
I diagnosed that `/Workspace/` is a **virtual filesystem** in Databricks — it presents files through a FUSE layer that blocks standard Python import operations. Attempted `shutil.copytree` from `/Workspace/` to `/tmp/` (real Linux filesystem) — this also failed with the same error because even file reading from `/Workspace/` is restricted.

Root cause confirmed: the workspace upload approach fundamentally cannot support runtime Python imports. Enterprise alternatives (Databricks Repos, cluster init scripts, wheel packages) require additional setup.

Pragmatic solution: embed the full `AdlsAuth` class definition **inline** inside `autoload.ipynb`. Used `types.SimpleNamespace` to reconstruct the `bobydo` namespace so all notebooks continue calling `bobydo.AdlsAuth(dbutils, spark)` without API changes:
```python
bobydo = types.SimpleNamespace(AdlsAuth=AdlsAuth, setup_logger=setup_logger)
```
Documented the long-term fix (migrate to Databricks Repos) in `TroubleShooting.txt`.

**Result:**  
All notebooks load `bobydo.AdlsAuth` cleanly via `%run ./autoload`. Zero code duplication. The library source of truth (`lib/bobydo/adls_auth.py`) remains in version control for editing. Pattern documented for the team.

---

### Story 2 — Key Vault PERMISSION_DENIED: Azure Identity Naming Confusion

**Situation:**  
Created a Key Vault-backed Databricks secret scope (`kv-scope`) successfully. When running `dbutils.secrets.get(scope="kv-scope", key="sp-client-id")`, the call failed with `PERMISSION_DENIED: Caller is not authorized to perform action on resource` — despite the scope being visible and the Key Vault secrets existing.

**Task:**  
Allow the Databricks runtime to read SP credentials from Key Vault so OAuth2 authentication to ADLS Gen2 could be configured.

**Action:**  
Read the full error message carefully: the caller was identified as `name=AzureDatabricks; appid=2ff814a6-3304-4ab8-85cb-cd0e6f879c1d`. This was a Key Vault RBAC issue — the Databricks service itself had no read permission on the vault.

The tricky part: Azure uses **four different names** for the same identity depending on which screen you're on:

| Screen | Label |
|---|---|
| Entra ID | Enterprise Application |
| Key Vault IAM | Service Principal |
| Databricks docs | Managed Identity |
| Old Azure docs | AAD Application |

Searched Entra ID → Enterprise Applications for `AzureDatabricks`, found the Microsoft-managed app, then assigned **Key Vault Secrets User** role via IAM on the vault. Also updated `keyvault-secrets_step2.sh` to automate this role assignment for future environments using the known app ID.

**Result:**  
All 3 SP secrets readable ✅. Spark OAuth2 configured. ADLS Gen2 access confirmed (`dbutils.fs.ls` returned Bronze container contents). The shell script now handles this automatically — no manual portal step needed for UAT/prod.

---

### Story 3 — ADF Pipeline Failure: Azure Quota Exceeded

**Situation:**  
Configured the ADF linked service `lsdatabricks` with "New job cluster" as recommended for production. Running the ADF pipeline failed immediately after the ForEach copy activities completed, with error: `AZURE_QUOTA_EXCEEDED_EXCEPTION — Current Limit: 4, Current Usage: 4, Additional Required: 4`.

**Task:**  
Get the full ADF pipeline (copy + validate + bronze→silver + silver→gold) to run successfully within the free-tier Azure subscription.

**Action:**  
Analysed the error: free Azure subscription has a **4 vCPU regional quota** in West US 2. The existing `cluster-dev` (Standard_DS3_v2 = 4 cores) already consumed the full quota. "New job cluster" attempted to provision an additional 4-core VM = quota exceeded.

Root cause: "New job cluster" is the correct production pattern (isolated, clean environment, auto-terminates per job) but requires either a higher quota or a different VM size. For development, it's unnecessary overhead.

Fix: Edited `lsdatabricks` linked service → changed **Select cluster** from `New job cluster` to **Existing interactive cluster** → selected `cluster-dev`. This reuses the already-running cluster — zero additional cores required.

Documented the dev vs prod pattern in both `RunProcess.txt` and `TroubleShooting.txt` so the next person doesn't hit the same wall.

**Result:**  
Full pipeline ran end-to-end ✅ — 19 Sales tables copied to Bronze, validated, transformed to Silver (Delta), transformed to Gold (Delta, snake_case columns). Total runtime ~8 minutes.

---

## 6. Key Concepts Q&A

**Q: What is medallion architecture?**  
A: A data organisation pattern with three layers: **Bronze** (raw, as-is from source), **Silver** (cleansed, typed, deduplicated), **Gold** (aggregated, analytics-ready). Each layer is a quality gate — downstream consumers only see validated data.

**Q: Why Delta Lake instead of plain Parquet for Silver/Gold?**  
A: Delta Lake adds ACID transactions, schema enforcement, and time travel on top of Parquet files. This means overwrites are atomic (no partial writes), schema changes are caught before they corrupt downstream, and you can roll back to a previous version if a transformation has a bug.

**Q: How do you secure credentials in Azure?**  
A: Store secrets in Azure Key Vault. In Databricks, create a Key Vault-backed secret scope — notebooks call `dbutils.secrets.get()` which retrieves values at runtime without ever exposing them. Values are automatically redacted in notebook output. No credentials in code or Git.

**Q: What is a Service Principal?**  
A: A non-human identity (like a service account) that applications use to authenticate to Azure resources. In this project, the SP has `Storage Blob Data Contributor` on ADLS — Databricks uses its credentials (client ID + secret + tenant ID) to generate OAuth2 tokens for ADLS access.

**Q: What does ADF do vs Databricks?**  
A: ADF **moves** data (orchestration, scheduling, connections to 90+ sources). Databricks **transforms** data (PySpark, Delta Lake, complex business logic). ADF triggers Databricks notebooks as activities in the pipeline — ADF is the conductor, Databricks is the engine.

**Q: What is CI/CD in this project?**  
A: GitHub Actions workflow (`databricks-deploy.yml`) runs on every push to `main`. It uses the Databricks REST API to upload all `.ipynb` notebooks and `lib/` Python files to the workspace — no manual upload needed. This ensures the deployed code always matches the Git repository.

**Q: What is a Self-hosted Integration Runtime?**  
A: A Windows service installed on the on-premises machine (same machine as SQL Server). It makes outbound HTTPS calls to ADF, allowing ADF to reach data sources that are not publicly accessible — like a local SQL Server behind a firewall.

---

## 7. Full System Diagram

```
╔══════════════════════════════════════════════════════════════════════════════════╗
║            AZURE DATA ENGINEERING — COMPLETE SYSTEM OVERVIEW                    ║
╚══════════════════════════════════════════════════════════════════════════════════╝

 ┌──────────────────────────────────────────────────────────────────────────────┐
 │  KEY VAULT  kv-dataengproj-dev   ← single source of truth for all secrets   │
 │                                                                              │
 │  sql-username / sql-password       ──► lssqlserveronprem  (SQL auth)        │
 │  sp-client-id / sp-client-secret                                             │
 │  sp-tenant-id                      ──► lsadlsgen2  (OAuth2)                 │
 │                                    ──► kv-scope → dbutils.secrets.get()     │
 │  databricks-token  (PAT, 90-day)   ──► lsdatabricks  (REST API auth)        │
 │                                                                              │
 │  IAM grants on this vault:                                                   │
 │    Your account (MSA)             → Key Vault Administrator                 │
 │    AzureDatabricks (app 2ff814a6) → Key Vault Secrets User                  │
 └──────────────────────────────────────────────────────────────────────────────┘
      ↑ all values fetched at runtime — no credential ever in code or Git


 Triggerdaily  ·  Schedule  ·  8:00 AM MST  ·  daily
      │  fires
      ▼
 ╔══════════════════════════════════════════════════════════════════════════════╗
 ║  ADF PIPELINE  pl-ingestion-sqlserver-to-bronze                              ║
 ║                                                                              ║
 ║  ┌────────────────────────────────────────────────────────────────────────┐  ║
 ║  │ ① Lookup: lkpgetalltables                                              │  ║
 ║  │   Linked service → lssqlserveronprem                                   │  ║
 ║  │   Auth: SQL login (adf_user · db_datareader) via ir-selfhosted-dev     │  ║
 ║  │         ir-selfhosted-dev = Windows service on local machine           │  ║
 ║  │         makes outbound HTTPS to ADF — no inbound firewall port needed  │  ║
 ║  │   Query: SELECT TABLE_SCHEMA, TABLE_NAME                               │  ║
 ║  │          FROM Sales WHERE TABLE_TYPE='BASE TABLE' → 19 tables          │  ║
 ║  └──────────────────────────────────────┬─────────────────────────────────┘  ║
 ║                  ┌─────────────────────────────────────────────────────────┐  ║
 ║                  │  On-Premises SQL Server                                  │  ║
 ║                  │  localhost\SQLEXPRESS · AdventureWorksLT2019             │  ║
 ║                  │  19 Sales tables (Customer, Product, SalesOrder, …)     │  ║
 ║                  └─────────────────────────────────────────────────────────┘  ║
 ║                                         │ 19 table names                      ║
 ║  ┌──────────────────────────────────────▼─────────────────────────────────┐  ║
 ║  │ ② ForEach: foreachtables  (parallel ×4–5)                              │  ║
 ║  │   └─ Copy: copytabletobronze  (runs ×19, once per table)               │  ║
 ║  │        Source: lssqlserveronprem → SELECT * FROM [Sales].[{Table}]     │  ║
 ║  │        Sink:   lsadlsgen2                                              │  ║
 ║  │                Auth: Service Principal OAuth2                          │  ║
 ║  │                      sp-client-id/secret/tenant-id ← Key Vault         │  ║
 ║  │                IAM:  sp-data-engineering-dev                            │  ║
 ║  │                      → Storage Blob Data Contributor on ADLS            │  ║
 ║  │        Output: bronze/Sales/{Table}.parquet  (Snappy Parquet × 19)     │  ║
 ║  └──────────────────────────────────────┬─────────────────────────────────┘  ║
 ║                  ┌─────────────────────────────────────────────────────────┐  ║
 ║                  │  ADLS Gen2  sadataeng260524dev                           │  ║
 ║                  │  bronze/Sales/{Table}.parquet  × 19                     │  ║
 ║                  └─────────────────────────────────────────────────────────┘  ║
 ║                                         │                                     ║
 ║  ┌──────────────────────────────────────▼─────────────────────────────────┐  ║
 ║  │ ③ Notebook: nbbronzevalidate                             ~7 min 42 s   │  ║
 ║  │   Linked service → lsdatabricks                                        │  ║
 ║  │   Auth: PAT (databricks-token from Key Vault) → Databricks REST API    │  ║
 ║  │   Inside notebook: %run ./autoload → bobydo.AdlsAuth.setup()           │  ║
 ║  │     kv-scope → dbutils.secrets.get() → sp credentials                 │  ║
 ║  │     spark.conf OAuth2 → Azure AD token → ADLS Gen2 read               │  ║
 ║  │   Checks: row counts ≥ 1 per table · nulls · min/max sanity            │  ║
 ║  │   ⛔ Pipeline stops here if any check fails — silver never sees bad data│  ║
 ║  └──────────────────────────────────────┬─────────────────────────────────┘  ║
 ║                  ┌─────────────────────────────────────────────────────────┐  ║
 ║                  │  Databricks Workspace  dbw-data-engineering-dev          │  ║
 ║                  │  cluster-dev  (Standard_DS3_v2 · Runtime 13.3 LTS)      │  ║
 ║                  │  Secret scope: kv-scope → backed by kv-dataengproj-dev  │  ║
 ║                  │  Shared library: bobydo.AdlsAuth (inline in autoload)   │  ║
 ║                  └─────────────────────────────────────────────────────────┘  ║
 ║                                         │ validation passed                   ║
 ║  ┌──────────────────────────────────────▼─────────────────────────────────┐  ║
 ║  │ ④ Notebook: nbbronzetosilver                             ~1 min 24 s   │  ║
 ║  │   Linked service → lsdatabricks                                        │  ║
 ║  │   %run ./autoload → bobydo.AdlsAuth.setup() → configure OAuth2         │  ║
 ║  │   Reads : bronze/Sales/*.parquet      (raw Parquet)                    │  ║
 ║  │   Writes: silver/Sales/{Table}/       (Delta Lake — ACID, versioned)   │  ║
 ║  │   Transform: datetime columns → date string · schema enforced           │  ║
 ║  └──────────────────────────────────────┬─────────────────────────────────┘  ║
 ║                  ┌─────────────────────────────────────────────────────────┐  ║
 ║                  │  ADLS Gen2  silver/Sales/{Table}/  (Delta Lake)          │  ║
 ║                  └─────────────────────────────────────────────────────────┘  ║
 ║                                         │                                     ║
 ║  ┌──────────────────────────────────────▼─────────────────────────────────┐  ║
 ║  │ ⑤ Notebook: nbsilvertogold                               ~1 min 8 s    │  ║
 ║  │   Linked service → lsdatabricks                                        │  ║
 ║  │   %run ./autoload → bobydo.AdlsAuth.setup() → configure OAuth2         │  ║
 ║  │   Reads : silver/Sales/{Table}/       (Delta Lake)                     │  ║
 ║  │   Writes: gold/Sales/{Table}/         (Delta Lake)                     │  ║
 ║  │   Transform: PascalCase → snake_case column rename                     │  ║
 ║  └──────────────────────────────────────┬─────────────────────────────────┘  ║
 ║                  ┌─────────────────────────────────────────────────────────┐  ║
 ║                  │  ADLS Gen2  gold/Sales/{Table}/  (Delta Lake)            │  ║
 ║                  └─────────────────────────────────────────────────────────┘  ║
 ╚══════════════════════════════════════════════════════════════════════════════╝
      Total runtime: ~9 min  (trigger fires → gold layer fully refreshed)
                              │
                              ▼
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │  Synapse Analytics  synapse-dataeng-dev  (serverless SQL — no dedicated pool)│
 │  IAM: synapse-dataeng-dev (Managed Identity) → Storage Blob Data Reader      │
 │       on sadataeng260524dev                                                  │
 │  Views via OPENROWSET(BULK '…/gold/Sales/{Table}/', FORMAT='DELTA')          │
 │  Database: gold_db  →  Sales_Customer, Sales_SalesOrderHeader, …            │
 └──────────────────────────────────────┬───────────────────────────────────────┘
                                         │
                                         ▼
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │  Power BI Desktop  (Synapse serverless SQL endpoint)                         │
 │  KPIs: gender split · revenue by category · slicers · daily scheduled refresh│
 └──────────────────────────────────────────────────────────────────────────────┘


 LINKED SERVICES — ADF stores no credentials directly; all fetched from Key Vault at runtime
 ──────────────────────────────────────────────────────────────────────────────────────────────
 lssqlserveronprem   SQL Authentication via ir-selfhosted-dev
                     Secrets: sql-username / sql-password
                     IR:      Windows service on local machine → outbound HTTPS to ADF
                     IAM:     adf_user has db_datareader on AdventureWorksLT2019

 lsadlsgen2          Service Principal OAuth2
                     Secrets: sp-client-id / sp-client-secret / sp-tenant-id
                     IAM:     sp-data-engineering-dev → Storage Blob Data Contributor
                              on sadataeng260524dev

 lsdatabricks        PAT (Personal Access Token)
                     Secret:  databricks-token (auto-generated, 90-day, rotated by script)
                     Auth:    ADF calls Databricks REST API to submit notebook jobs


 IAM ROLE ASSIGNMENTS — every identity needs an explicit grant; nothing in Azure is implicit
 ──────────────────────────────────────────────────────────────────────────────────────────────
 Identity                            Type                  Role                    Resource
 ──────────────────────────────────────────────────────────────────────────────────────────────
 Your Azure account                  User (MSA)            KV Administrator        kv-dataengproj-dev
 sp-data-engineering-dev             Service Principal     Storage Blob Contributor sadataeng260524dev
 AzureDatabricks  (app 2ff814a6)     Enterprise App (MSFT) KV Secrets User         kv-dataengproj-dev
 synapse-dataeng-dev                 Managed Identity      Storage Blob Reader     sadataeng260524dev

 ⚠  AzureDatabricks (appid 2ff814a6) = one Microsoft-managed identity, four names:
    Entra ID → Enterprise Application     Key Vault IAM  → Service Principal
    Databricks docs → Managed Identity    Old Azure docs → AAD Application
```

---

## 10. How It Actually Came Together — The Learning Journey

### 10.1 What I Assumed vs What Reality Required

| What I assumed at the start | What reality actually required |
|---|---|
| ADF can transform data with built-in activities | ADF is an *orchestrator* — it moves data. Complex transformation (type casting, column rename, Delta Lake writes) required Databricks PySpark |
| Upload a Python file to Databricks and `import` it | Databricks `/Workspace/` is a virtual FUSE filesystem — it blocks both Python `import` and `shutil.copytree` with `OSError [Errno 95]` |
| SP credentials are simple config values to paste in | Every credential lives in Key Vault; every component needs an *explicit IAM role assignment* to read it — nothing is implicit |
| One ADF linked service connects everything | Databricks needed its own separate linked service (`lsdatabricks`) plus a PAT stored in Key Vault, on top of the ADLS linked service |
| One round of permission setup covers everything | Three separate IAM roles, on two different resources, for three different identity types (user, SP, Microsoft-managed app) |
| ADF "New job cluster" is the recommended setting | "New job cluster" tries to spin up additional VMs — the free subscription's 4 vCPU quota was already fully used by `cluster-dev` |

### 10.2 The Pipeline Grew in 5 Stages

**Stage 1 — ADF Copy to Bronze (thought this was the end)**  
Built Lookup + ForEach + Copy pipeline. 19 Sales tables landed in
`bronze/Sales/{Table}.parquet` in ~20 seconds each. Assumed this was the complete
data engineering work.

**Stage 2 — Discovered Databricks Was Needed**  
Silver/gold transformations — casting datetime columns to date strings, renaming columns
from PascalCase to snake_case, writing ACID-compliant Delta Lake format — all required
PySpark. Added Databricks workspace, created `cluster-dev` (Standard_DS3_v2, 13.3 LTS
runtime), built three transformation notebooks.

**Stage 3 — Python Library Import Failed: OSError [Errno 95]**  
Built a shared authentication library (`bobydo.AdlsAuth`) to avoid duplicating OAuth2
configuration code in every notebook. CI/CD deployed it to `/Workspace/notebooks/lib/`.
When notebooks tried `import bobydo`, Python raised `OSError [Errno 95]: Operation not
supported`. Even `shutil.copytree` from `/Workspace/` to `/tmp/` failed with the same
error — the Databricks workspace virtual filesystem blocks both Python imports and standard
file reads.

Solution: embed the full `AdlsAuth` class definition *inline* in `autoload.ipynb`, then
restore the `bobydo.` namespace with:
```python
bobydo = types.SimpleNamespace(AdlsAuth=AdlsAuth, setup_logger=setup_logger)
```
All notebooks continue calling `bobydo.AdlsAuth(dbutils, spark)` — no API changes. The
class source of truth remains in `databricks/lib/bobydo/adls_auth.py` for editing.

**Stage 4 — Key Vault PERMISSION_DENIED on `dbutils.secrets.get()`**  
Created a Key Vault-backed Databricks secret scope (`kv-scope`). First call to
`dbutils.secrets.get(scope="kv-scope", key="sp-client-id")` returned:
`PERMISSION_DENIED: Caller is not authorized to perform action on resource`.

The error message identified the caller as `name=AzureDatabricks; appid=2ff814a6...`.
After untangling Azure's four different names for the same identity (Enterprise Application /
Service Principal / Managed Identity / AAD Application), found the Microsoft-managed
`AzureDatabricks` app in Entra ID and assigned `Key Vault Secrets User` via IAM. Automated
in `keyvault-secrets_step2.sh` for future environments.

**Stage 5 — Wired ADF → Databricks + Added Daily Trigger**  
Generated a Databricks PAT via `bash infra/databricks-token_step4.sh dev` (stored
automatically in Key Vault). Created `lsdatabricks` linked service (PAT from Key Vault).
Added three Databricks Notebook activities to the ADF pipeline in sequence.

Hit `AZURE_QUOTA_EXCEEDED_EXCEPTION` — "New job cluster" tried to provision 4 additional
vCPUs; free subscription limit is 4 (all used by `cluster-dev`). Fixed by switching
`lsdatabricks` to "Existing interactive cluster → cluster-dev".

Added `Triggerdaily` (schedule: 8:00 AM MST, daily) so the full pipeline runs automatically
without manual trigger. Total end-to-end: ~9 minutes from trigger fire to Gold layer updated.

### 10.3 End-to-End Credential Flow

Every component authenticates via a credential stored in Key Vault. No credential ever
appears in a notebook, pipeline JSON, or Git commit.

```
Azure Key Vault  (kv-dataengproj-dev)
  │
  ├─ sql-username
  ├─ sql-password
  │      └─► ADF lssqlserveronprem ──► Self-hosted IR (outbound HTTPS) ──► SQL Server
  │               (ADF fetches secret at pipeline run time)
  │
  ├─ sp-client-id
  ├─ sp-client-secret
  ├─ sp-tenant-id
  │      └─► Databricks dbutils.secrets.get("kv-scope", ...)
  │               └─► spark.conf OAuth2 token endpoint  ──► Azure AD token
  │                       └─► ADLS Gen2 read/write        (bronze / silver / gold)
  │
  └─ databricks-token  (PAT — 90-day lifetime, auto-rotated by shell script)
         └─► ADF lsdatabricks ──► Databricks REST API ──► submit notebook job
```

**Why Key Vault for everything?**
- Secrets are never hardcoded in notebooks, JSON configs, or environment variables
- Values are automatically redacted (`[REDACTED]`) in all Databricks cell output
- Rotating a credential = one Key Vault update; all consumers pick up the new value
  automatically on next run — no code changes needed
- Shell scripts handle provisioning: `keyvault-secrets_step2.sh`, `service-principal_step3.sh`,
  `databricks-token_step4.sh` — idempotent, reproducible across dev/UAT/prod
