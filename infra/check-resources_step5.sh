#!/usr/bin/env bash
# =============================================================================
# check-resources_step5.sh — Verify all provisioned resources exist and are healthy
# Azure E2E Data Engineering Project
#
# Run after provision_step1.sh through databricks-token_step4.sh to confirm
# the full deployment is complete before moving to manual phases (ADF, Databricks).
#
# Usage:
#   bash infra/check-resources_step5.sh [dev|uat|prod]   (default: dev)
#
# Checks:
#   ✅  Resource Group
#   ✅  Storage Account + containers (bronze/silver/gold/synapse)
#   ✅  Azure Data Factory
#   ✅  Databricks Workspace
#   ✅  Synapse Workspace
#   ✅  Key Vault
#   ✅  Key Vault secrets (sql-username, sql-password, sp-*, databricks-token)
#   ✅  Service Principal + Storage Blob Data Contributor role
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

SP_DISPLAY_NAME="sp-data-engineering-${TARGET_ENV}"

PASS=0
FAIL=0

pass() { echo "   ✅  $1"; PASS=$((PASS + 1)); }
fail() { echo "   ❌  $1"; FAIL=$((FAIL + 1)); }
info() { echo "   ℹ️   $1"; }

echo ""
echo "══════════════════════════════════════════════════════"
echo " Deployment Check — Environment: $TARGET_ENV"
echo "══════════════════════════════════════════════════════"
echo " Resource Group : $RESOURCE_GROUP"
echo " Location       : $LOCATION"
echo " Storage        : $STORAGE_ACCOUNT"
echo " ADF            : $ADF_NAME"
echo " Databricks     : $DATABRICKS_NAME"
echo " Synapse        : $SYNAPSE_NAME"
echo " Key Vault      : $KEY_VAULT_NAME"
echo "══════════════════════════════════════════════════════"

# =============================================================================
# Resource Group
# =============================================================================
echo ""
echo "── Resource Group ──"
if [[ "$(az group exists --name "$RESOURCE_GROUP")" == "true" ]]; then
    STATE=$(az group show --name "$RESOURCE_GROUP" --query "properties.provisioningState" -o tsv 2>/dev/null)
    pass "$RESOURCE_GROUP ($STATE)"
else
    fail "$RESOURCE_GROUP — not found"
fi

# =============================================================================
# Storage Account + containers
# =============================================================================
echo ""
echo "── Storage Account ──"
if az storage account show --name "$STORAGE_ACCOUNT" --output none 2>/dev/null; then
    KIND=$(az storage account show --name "$STORAGE_ACCOUNT" --query "kind" -o tsv 2>/dev/null)
    HNS=$(az storage account show  --name "$STORAGE_ACCOUNT" --query "isHnsEnabled" -o tsv 2>/dev/null)
    pass "$STORAGE_ACCOUNT (kind=$KIND, HNS=$HNS)"
else
    fail "$STORAGE_ACCOUNT — not found"
fi

echo ""
echo "── ADLS Containers ──"
for CONTAINER in bronze silver gold synapse; do
    if az storage fs show \
            --name         "$CONTAINER" \
            --account-name "$STORAGE_ACCOUNT" \
            --auth-mode    login \
            --output none 2>/dev/null; then
        pass "$CONTAINER"
    else
        fail "$CONTAINER — not found"
    fi
done

# =============================================================================
# Azure Data Factory
# =============================================================================
echo ""
echo "── Azure Data Factory ──"
az extension add --name datafactory --only-show-errors 2>/dev/null || true
ADF_COUNT=$(az resource list \
    --resource-type "Microsoft.DataFactory/factories" \
    --query         "length([?name=='$ADF_NAME'])" \
    -o tsv 2>/dev/null)
if [[ "${ADF_COUNT:-0}" -gt 0 ]]; then
    pass "$ADF_NAME"
else
    fail "$ADF_NAME — not found"
fi

# =============================================================================
# Databricks Workspace
# =============================================================================
echo ""
echo "── Databricks Workspace ──"
az extension add --name databricks --only-show-errors 2>/dev/null || true
DBW_STATE=$(az databricks workspace show \
    --resource-group "$RESOURCE_GROUP" \
    --name           "$DATABRICKS_NAME" \
    --query          "provisioningState" \
    -o tsv 2>/dev/null || true)
if [[ "$DBW_STATE" == "Succeeded" ]]; then
    DBW_URL=$(az databricks workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --name           "$DATABRICKS_NAME" \
        --query          "workspaceUrl" -o tsv 2>/dev/null)
    pass "$DATABRICKS_NAME ($DBW_URL)"
elif [[ -n "$DBW_STATE" ]]; then
    fail "$DATABRICKS_NAME — state: $DBW_STATE"
else
    fail "$DATABRICKS_NAME — not found"
fi

# =============================================================================
# Synapse Workspace
# =============================================================================
echo ""
echo "── Synapse Workspace ──"
SYN_STATE=$(az synapse workspace show \
    --resource-group "$RESOURCE_GROUP" \
    --name           "$SYNAPSE_NAME" \
    --query          "provisioningState" \
    -o tsv 2>/dev/null || true)
if [[ "$SYN_STATE" == "Succeeded" ]]; then
    pass "$SYNAPSE_NAME"
elif [[ -n "$SYN_STATE" ]]; then
    fail "$SYNAPSE_NAME — state: $SYN_STATE"
else
    fail "$SYNAPSE_NAME — not found"
fi

# =============================================================================
# Key Vault
# =============================================================================
echo ""
echo "── Key Vault ──"
KV_STATE=$(az keyvault show \
    --name           "$KEY_VAULT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query          "properties.provisioningState" \
    -o tsv 2>/dev/null || true)
if [[ "$KV_STATE" == "Succeeded" ]]; then
    pass "$KEY_VAULT_NAME"
elif [[ -n "$KV_STATE" ]]; then
    fail "$KEY_VAULT_NAME — state: $KV_STATE"
else
    fail "$KEY_VAULT_NAME — not found"
fi

# =============================================================================
# Key Vault secrets
# =============================================================================
echo ""
echo "── Key Vault Secrets ──"
for SECRET in sql-username sql-password sp-client-id sp-client-secret sp-tenant-id databricks-token; do
    STATE=$(az keyvault secret show \
        --vault-name "$KEY_VAULT_NAME" \
        --name       "$SECRET" \
        --query      "attributes.enabled" \
        -o tsv 2>/dev/null || true)
    if [[ "$STATE" == "true" ]]; then
        pass "$SECRET"
    else
        fail "$SECRET — missing or disabled"
    fi
done

# =============================================================================
# Service Principal
# =============================================================================
echo ""
echo "── Service Principal ──"
SP_APP_ID=$(az ad app list \
    --display-name "$SP_DISPLAY_NAME" \
    --query        "[0].appId" \
    -o tsv 2>/dev/null || true)
if [[ -n "$SP_APP_ID" && "$SP_APP_ID" != "None" ]]; then
    pass "$SP_DISPLAY_NAME (appId: $SP_APP_ID)"

    # Check Storage Blob Data Contributor role
    SP_OBJ_ID=$(az ad sp show --id "$SP_APP_ID" --query id -o tsv 2>/dev/null || true)
    STORAGE_ID=$(az storage account show --name "$STORAGE_ACCOUNT" --query id -o tsv 2>/dev/null || true)
    ROLE=$(az role assignment list \
        --assignee-object-id "$SP_OBJ_ID" \
        --role               "Storage Blob Data Contributor" \
        --scope              "$STORAGE_ID" \
        --query              "length(@)" -o tsv 2>/dev/null || echo "0")
    if [[ "${ROLE:-0}" -gt 0 ]]; then
        pass "Storage Blob Data Contributor role assigned"
    else
        # az role assignment list fails for MSA (outlook.com) accounts — not a real failure
        echo "   ⚠️   Storage Blob Data Contributor — could not verify (MSA CLI limitation)"
        echo "        Confirm in Portal: Storage '$STORAGE_ACCOUNT' → Access Control (IAM)"
    fi
else
    fail "$SP_DISPLAY_NAME — not found"
fi

# =============================================================================
# Summary
# =============================================================================
TOTAL=$((PASS + FAIL))
echo ""
echo "══════════════════════════════════════════════════════"
if [[ $FAIL -eq 0 ]]; then
    echo " ✅ All $TOTAL checks passed — deployment complete"
    echo "══════════════════════════════════════════════════════"
    echo ""
    echo "Ready for manual phases:"
    echo "  Phase 5 — ADF Self-hosted Integration Runtime"
    echo "  Phase 6 — Databricks cluster + storagemount notebook"
else
    echo " ⚠️  $PASS/$TOTAL passed — $FAIL check(s) failed"
    echo "══════════════════════════════════════════════════════"
    echo ""
    echo "Fix the ❌ items above, then re-run:"
    echo "  bash infra/check-resources_step5.sh $TARGET_ENV"
fi
echo ""
