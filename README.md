# Azure End-to-End Data Engineering Pipeline

AdventureWorks on-premises SQL Server → ADF ingestion → Medallion Architecture (Bronze / Silver / Gold) → Synapse serverless SQL → Power BI KPI dashboard.

---

## Summary

This project builds a production-grade Azure data pipeline from scratch. Sales and customer data from an on-premises SQL Server (AdventureWorks, 19 Sales tables) is ingested into Azure Data Lake Storage Gen2 via Azure Data Factory, then transformed through three quality layers using Azure Databricks and Delta Lake, and finally exposed as serverless SQL views in Azure Synapse Analytics for a Power BI KPI dashboard.

**What was built:**
- ADF ingestion pipeline with a Lookup + ForEach + Copy pattern — dynamically copies all Sales tables to Bronze in parallel
- Databricks transformation notebooks (validate → bronze→silver → silver→gold) triggered by ADF and deployed via CI/CD
- Synapse serverless SQL views over Gold Delta files — no dedicated pool, no extra cost
- Power BI dashboard with gender split, revenue by category, and date/category/gender slicers
- Daily schedule trigger so the full pipeline runs automatically every morning

**Enterprise patterns applied:**
- **Medallion Architecture** — Bronze (raw), Silver (cleansed Delta), Gold (analytics-ready Delta)
- **Zero credentials in code** — all secrets in Azure Key Vault, fetched at runtime via `dbutils.secrets.get()` and ADF Key Vault references
- **Service Principal OAuth2** — Databricks authenticates to ADLS Gen2 with short-lived tokens, not storage keys
- **CI/CD** — GitHub Actions deploys Databricks notebooks on every push to `main`; ADF compiles source JSON to ARM templates on the `adf_publish` branch
- **Infrastructure as Code** — idempotent bash scripts provision all Azure resources across dev / UAT / prod from a single command

---

## Pipeline Flow

```
On-Premises SQL Server
  │  ADF + Self-hosted Integration Runtime
  ▼
ADLS Gen2 — Bronze Layer   (raw Parquet, schema preserved)
  │  Databricks: validate row counts, nulls, min/max
  │  Databricks: cast datetime → date string
  ▼
ADLS Gen2 — Silver Layer   (cleansed Delta Lake)
  │  Databricks: rename columns PascalCase → snake_case
  ▼
ADLS Gen2 — Gold Layer     (analytics-ready Delta Lake)
  │  Synapse: serverless SQL views (OPENROWSET over Delta files)
  ▼
Power BI Dashboard         (gender split, revenue by category, slicers)
```

**Daily trigger:** ADF fires the full pipeline at 8:00 AM MST. Total runtime ~9 min.

---

## Folder Structure

```
azure-data-engineering/
│
├── adf/                        # ADF Studio JSON (auto-managed by ADF Git integration)
│   ├── pipeline/               # Pipeline definitions
│   ├── dataset/                # Dataset definitions
│   ├── linkedService/          # Linked service definitions (no secrets — resource refs only)
│   ├── trigger/                # Schedule trigger (Triggerdaily)
│   ├── integrationRuntime/     # Self-hosted IR definition
│   └── factory/                # Factory-level settings
│
├── databricks/                 # Databricks notebooks (deployed to workspace via CI/CD)
│   ├── autoload.ipynb          # Shared library loader — %run this first in every notebook
│   ├── validate_bronze.ipynb   # Quality gate: row counts, nulls, min/max
│   ├── bronze_to_silver.ipynb  # Transform: Parquet → Delta Lake, datetime casts
│   ├── silver_to_gold.ipynb    # Transform: Delta Lake, column rename
│   ├── storagemount.ipynb      # OAuth2 config + path setup (run once)
│   └── lib/bobydo/             # Shared Python library source (AdlsAuth, setup_logger)
│
├── infra/                      # Azure provisioning scripts (bash, idempotent)
│   ├── provision_step1.sh      # Phase 1–4: provision all Azure resources
│   ├── keyvault-secrets_step2.sh  # Store SQL credentials in Key Vault
│   ├── service-principal_step3.sh # Create SP + assign ADLS role
│   ├── databricks-token_step4.sh  # Generate Databricks PAT → Key Vault
│   ├── config.sh               # Shared config (subscription, suffix)
│   ├── config.dev.sh           # Dev resource names
│   └── cleanup.sh              # Remove all Azure resources
│
├── sql/
│   ├── setup/                  # Run once: restore DB, create login, grant access
│   └── queries/                # Reference queries + Synapse stored procedure
│
├── docs/
│   ├── images/                 # Screenshots (referenced below)
│   ├── Interview.md            # Interview preparation guide
│   └── LocalToBronzeVerification.md
│
├── .github/workflows/
│   └── databricks-deploy.yml   # CI/CD: deploy notebooks on push to main
│
├── RunProcess.txt              # Step-by-step guide (Phase 5 → 11)
├── TroubleShooting.txt         # Known issues and fixes
└── .env                        # Local secrets — gitignored, never commit
```

---

## Pipeline Phases

| Phase | What | How |
|---|---|---|
| 1–4 | Provision all Azure resources + store secrets | `bash infra/provision_step1.sh dev` |
| 5 | Install Self-hosted Integration Runtime | ADF Studio → Manage → Integration Runtimes |
| 6 | Build ADF linked services, datasets, pipeline | ADF Studio |
| 7 | Databricks cluster + notebooks + secret scope | Databricks UI + CI/CD auto-deploys notebooks |
| 8 | Generate Databricks PAT → Key Vault | `bash infra/databricks-token_step4.sh dev` |
| 9 | Add Databricks Notebook activities to ADF pipeline | ADF Studio |
| 10 | Create Synapse serverless SQL views over Gold | Synapse Studio |
| 11 | Build Power BI dashboard + schedule daily refresh | Power BI Desktop |

Full step-by-step: [`RunProcess.txt`](RunProcess.txt)

---

## CI/CD

### Databricks Notebooks — GitHub Actions

Every push to `main` automatically deploys all notebooks and the shared library to the Databricks workspace. No manual upload needed.

**Workflow:** [`.github/workflows/databricks-deploy.yml`](.github/workflows/databricks-deploy.yml)

What it does:
1. Uploads all `databricks/*.ipynb` notebooks to `/Users/baoshenyi7768@outlook.com/notebooks/`
2. Uploads `databricks/lib/**` to the same workspace folder
3. Uses `DATABRICKS_HOST` and `DATABRICKS_TOKEN` from GitHub Secrets

To trigger manually: GitHub → Actions → **Deploy Databricks Notebooks** → Run workflow.

### ADF Pipeline — `adf_publish` Branch

ADF uses two branches with different roles:

| Branch | Written by | Contains | Purpose |
|---|---|---|---|
| `main` | You (VS Code / ADF Studio saves) | Source JSON (`adf/pipeline/`, `adf/dataset/`, etc.) | Development, code review, history |
| `adf_publish` | ADF Studio (on every Publish click) | Compiled ARM template | Deployment to Azure |

**You never push to `adf_publish` directly.** When you click **Publish All** in ADF Studio, it compiles the source JSON into an ARM template and pushes it to `adf_publish` automatically. GitHub Actions can then read that ARM template and deploy it to UAT/prod.

To configure ADF Git integration: ADF Studio → **Manage** → **Git configuration**
- Repository type: GitHub
- Collaboration branch: `main`
- Root folder: `adf`

---

## Quick Start

```bash
# Clone
git clone https://github.com/bobydo/azure-data-engineering.git
cd azure-data-engineering

# Fill in credentials (never commit this file)
cp .env.example .env
# edit .env with your SQL password and service principal values

# Provision all Azure resources (dev)
bash infra/provision_step1.sh dev

# Store secrets in Key Vault
bash infra/keyvault-secrets_step2.sh dev

# Create service principal + assign ADLS role
bash infra/service-principal_step3.sh dev

# (After Phase 7) Generate Databricks PAT
bash infra/databricks-token_step4.sh dev
```

> Azure Cloud Shell (`portal.azure.com` → `>_`) is recommended: pre-authenticated, no local CLI setup needed.

---

## Screenshots

### Azure Resources — Resource Group Overview
<!-- TODO: Portal → rg-data-engineering-dev → overview showing all 6 resources -->

### Phase 5 — Self-Hosted Integration Runtime Installed
![IR Installed](docs/images/IntegrationRuntimeInstalled.png)

### Phase 6 — ADF Linked Services
#### SQL Server Linked Service
<!-- TODO: ADF Studio → Manage → Linked Services → lssqlserveronprem -->

#### ADLS Gen2 Linked Service
<!-- TODO: ADF Studio → Manage → Linked Services → lsadlsgen2 (Service Principal auth) -->

#### Databricks Linked Service
<!-- TODO: ADF Studio → Manage → Linked Services → lsdatabricks (Existing cluster) -->

### Phase 6 — ADF Datasets
#### SQL Server Source Dataset
![SQL Server Dataset](docs/images/1779901354821.png)

#### ADLS Bronze Parquet Sink Dataset
<!-- TODO: ADF Studio → Author → Datasets → ds_adls_bronze_parquet -->

### Phase 6 — ADF Pipeline Design
<!-- TODO: ADF Studio → pl-ingestion-sqlserver-to-bronze canvas (Lookup → ForEach → 3 Notebooks) -->

### Phase 7 — Databricks Workspace (Notebooks Deployed)
<!-- TODO: Databricks → Workspace → Users → baoshenyi7768@outlook.com → notebooks folder -->

### Phase 7 — Databricks Cluster Running
<!-- TODO: Databricks → Compute → cluster-dev → Running status -->

### Phase 8 — Key Vault Secrets
<!-- TODO: Portal → kv-dataengproj-dev → Secrets (show all 5 secret names, not values) -->

### Phase 9 — Full Pipeline Run Succeeded
<!-- TODO: ADF → Monitor → Pipeline run showing all 5 activities green (copy + 3 notebooks) -->

### Phase 9 — ADF Daily Trigger
<!-- TODO: ADF Studio → Manage → Triggers → Triggerdaily → Started status -->

### Phase 10 — Bronze / Silver / Gold in ADLS
<!-- TODO: Portal → sadataeng260524dev → Storage browser → bronze, silver, gold containers -->

### Phase 10 — Synapse SQL Views
<!-- TODO: Synapse Studio → Data → gold_db → Views list -->

### Phase 11 — Power BI Dashboard
<!-- TODO: Power BI Desktop showing final KPI dashboard (gender split + revenue by category) -->

### ADF Pipeline Failure Alert
![ADF Alert Rule](docs/images/1779831292177.png)
