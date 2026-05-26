# =============================================================================
# config.uat.sh — UAT environment overrides
# Sourced by provision.sh after config.sh — values here win.
# Usage: bash infra/provision.sh uat
# =============================================================================

ENV="uat"
RESOURCE_GROUP="rg-data-engineering-uat"
STORAGE_ACCOUNT="sadataeng${UNIQUE_SUFFIX}uat"  # no hyphens, max 24 chars → sadataeng260524uat (18)
ADF_NAME="adf-data-${UNIQUE_SUFFIX}-uat"
DATABRICKS_NAME="dbw-data-engineering-uat"
SYNAPSE_NAME="synapse-dataeng-uat"
KEY_VAULT_NAME="kv-dataengproj-uat"
