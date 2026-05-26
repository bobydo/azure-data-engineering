#!/usr/bin/env bash
# =============================================================================
# databricks-token_step4.sh — Phase 7: Generate Databricks PAT → Key Vault
# Azure E2E Data Engineering Project
#
# Fully automated — no UI interaction needed.
# Uses your Azure AD login to authenticate to Databricks, generates a PAT,
# and writes it directly to Key Vault.
#
# Prerequisites:
#   Phase 2 complete — Databricks workspace and Key Vault must exist
#   az login already done
#
# Usage:
#   bash infra/databricks-token_step4.sh [dev|uat|prod]   (default: dev)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

TARGET_ENV="${1:-dev}"
case "$TARGET_ENV" in
    dev|uat|prod) ;;
    *) echo "❌ Invalid environment '$TARGET_ENV'. Allowed: dev | uat | prod" && exit 1 ;;
esac
source "$SCRIPT_DIR/config.${TARGET_ENV}.sh"

echo "ℹ️  Environment  : $TARGET_ENV"
echo "ℹ️  Databricks   : $DATABRICKS_NAME"
echo "ℹ️  Key Vault    : $KEY_VAULT_NAME"

echo ""
echo "══════════════════════════════════════════════════════"
echo " Phase 7 — Databricks PAT → Key Vault (automated)"
echo "══════════════════════════════════════════════════════"

# =============================================================================
# 7.1 — Get Databricks workspace URL
# =============================================================================
echo ""
echo "── 7.1 Databricks workspace URL ──"
az extension add --name databricks --only-show-errors 2>/dev/null || true
DBW_URL=$(az databricks workspace show \
    --resource-group "$RESOURCE_GROUP" \
    --name           "$DATABRICKS_NAME" \
    --query          "workspaceUrl" \
    -o tsv 2>/dev/null)
echo "   ✅ $DBW_URL"

# =============================================================================
# 7.2 — Get Azure AD token for Databricks resource
#        Resource ID 2ff814a6-... is the fixed Databricks AAD app ID (all tenants)
# =============================================================================
echo ""
echo "── 7.2 Acquiring Azure AD token for Databricks ──"
DBW_AAD_TOKEN=$(az account get-access-token \
    --resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" \
    --query    accessToken \
    -o tsv 2>/dev/null)
echo "   ✅ Token acquired"

# =============================================================================
# 7.3 — Create Databricks PAT via REST API
#        Lifetime: 90 days (7776000 seconds) — rotate with this script
# =============================================================================
echo ""
echo "── 7.3 Generating Databricks PAT ──"
TOKEN_RESPONSE=$(curl -sf \
    -X POST "https://${DBW_URL}/api/2.0/token/create" \
    -H "Authorization: Bearer ${DBW_AAD_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"lifetime_seconds\": 7776000, \"comment\": \"adf-integration-${TARGET_ENV}\"}")

DATABRICKS_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"token_value":"[^"]*"' | cut -d'"' -f4)

if [[ -z "$DATABRICKS_TOKEN" ]]; then
    echo "   ❌ Failed to generate PAT — response: $TOKEN_RESPONSE"
    exit 1
fi
echo "   ✅ PAT generated (90-day lifetime)"

# =============================================================================
# 7.4 — Write PAT to Key Vault
# =============================================================================
echo ""
echo "── 7.4 Writing databricks-token to Key Vault ──"
MAX_ATTEMPTS=20
INTERVAL=15
ACCESS_OK=false
for i in $(seq 1 $MAX_ATTEMPTS); do
    if az keyvault secret list --vault-name "$KEY_VAULT_NAME" --output none 2>/dev/null; then
        ACCESS_OK=true
        break
    fi
    echo "   ⏳ Waiting for KV access... (attempt $i/${MAX_ATTEMPTS})"
    sleep $INTERVAL
done

if [[ "$ACCESS_OK" != "true" ]]; then
    echo "   ❌ KV access timed out — check Key Vault Administrator role assignment"
    exit 1
fi

az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name       "databricks-token" \
    --value      "$DATABRICKS_TOKEN" \
    --output     none
echo "   ✅ databricks-token — set in Key Vault"

# =============================================================================
# Done
# =============================================================================
echo ""
echo "══════════════════════════════════════════════════════"
echo " ✅ Phase 7 Complete"
echo "══════════════════════════════════════════════════════"
echo ""
echo "Databricks PAT generated and stored in Key Vault automatically."
echo "To rotate: re-run this script — it creates a new PAT and overwrites the secret."
echo ""
echo "Next: Phase 8 — Build ADF pipeline"
echo "  ADF Studio → Author → Pipelines → New pipeline"
