# =============================================================================
# config.dev.sh — Development environment overrides
# Sourced by provision.sh after config.sh — values here win.
# Usage: bash infra/provision.sh dev
# =============================================================================

ENV="dev"
LOCATION="centralus"                           
RESOURCE_GROUP="rg-data-engineering-dev"
STORAGE_ACCOUNT="sadataeng${UNIQUE_SUFFIX}dev"  # no hyphens, max 24 chars → sadataeng260524dev (18)
ADF_NAME="adf-data-${UNIQUE_SUFFIX}-dev"
DATABRICKS_NAME="dbw-data-engineering-dev"
SYNAPSE_NAME="synapse-dataeng-dev"
KEY_VAULT_NAME="kv-dataengproj-dev"
