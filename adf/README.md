# ADF — Azure Data Factory ARM Files

This folder is managed by **ADF Studio Git integration**.  
Do **not** edit files here manually — ADF Studio writes them automatically on Publish.

---

## How to Connect ADF Studio to This Repo

1. **ADF Studio** → Manage → Source control → Git configuration → Configure
2. Fill in:

   | Field | Value |
   |---|---|
   | Repository type | GitHub |
   | GitHub account | your GitHub username |
   | Repository name | azure-data-engineering |
   | Collaboration branch | `main` |
   | Publish branch | `adf_publish` |
   | Root folder | `/adf` |

3. Click **Apply** → ADF Studio switches to Git mode
4. All future saves go to your branch (not live in Azure)
5. **Publish All** → deploys to Azure AND writes ARM JSON to this folder

---

## Folder Contents (auto-managed by ADF Studio)

| Folder | Contents |
|---|---|
| `pipeline/` | Pipeline definitions — e.g. `pl-ingestion-sqlserver-to-bronze.json` |
| `dataset/` | Dataset definitions — e.g. `ds_sqlserver_source.json` |
| `linkedService/` | Linked service definitions (resource refs only — no secrets) |
| `trigger/` | Trigger definitions — e.g. `triggerdaily.json` |
| `integrationRuntime/` | IR definitions — e.g. `ir-selfhosted-dev.json` |
| `factory/` | Factory-level global settings |

---

## Important Notes

- **Secrets are never stored here** — linked services reference Key Vault, not raw credentials
- **Publish branch** (`adf_publish`) contains the final ARM template used for CI/CD deployment
- Until ADF Git integration is configured, these folders contain only `.gitkeep` placeholders
