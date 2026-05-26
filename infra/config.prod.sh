# =============================================================================
# config.prod.sh — Production environment overrides
# Sourced by provision.sh after config.sh — values here win.
# Usage: bash infra/provision.sh prod
# =============================================================================

ENV="prod"
RESOURCE_GROUP="rg-data-engineering-prod"
STORAGE_ACCOUNT="sadataeng${UNIQUE_SUFFIX}prod" # no hyphens, max 24 chars → sadataeng260524prod (19)
ADF_NAME="adf-data-${UNIQUE_SUFFIX}-prod"
DATABRICKS_NAME="dbw-data-engineering-prod"
SYNAPSE_NAME="synapse-dataeng-prod"
KEY_VAULT_NAME="kv-dataengproj"             # existing prod Key Vault
