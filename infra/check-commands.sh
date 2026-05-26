#!/usr/bin/env bash
# =============================================================================
# check-commands.sh — Verify which az check commands work in your CLI version
#
# Run this BEFORE provision_step1.sh to confirm each existence-check command works.
# Update provision_step1.sh with alternatives if any show ❌.
#
# Usage:
#   bash infra/check-commands.sh [dev|uat|prod]   (default: dev)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
TARGET_ENV="${1:-dev}"
case "$TARGET_ENV" in
    dev|uat|prod) ;;
    *) echo "❌ Invalid environment '$TARGET_ENV'. Allowed: dev | uat | prod" && exit 1 ;;
esac
source "$SCRIPT_DIR/config.${TARGET_ENV}.sh"

echo ""
echo "══════════════════════════════════════════════════════"
echo " Checking az commands for env: $TARGET_ENV"
echo "══════════════════════════════════════════════════════"
echo " Resource Group   : $RESOURCE_GROUP"
echo " Storage Account  : $STORAGE_ACCOUNT"
echo " ADF              : $ADF_NAME"
echo " Databricks       : $DATABRICKS_NAME"
echo " Synapse          : $SYNAPSE_NAME"
echo " Key Vault        : $KEY_VAULT_NAME"
echo "══════════════════════════════════════════════════════"
echo ""

pass() { echo "  ✅  $1"; }
fail() { echo "  ❌  $1"; }
skip() { echo "  ⏭️   $1 (extension not installed)"; }

# ── 2.1 Resource Group ────────────────────────────────────────────────────────
echo "── 2.1 Resource Group ──"
echo "    CMD: az group exists --name \$RESOURCE_GROUP"
RESULT=$(az group exists --name "$RESOURCE_GROUP" 2>/dev/null)
if [[ "$RESULT" == "true" || "$RESULT" == "false" ]]; then
    pass "az group exists  →  returned '$RESULT'"
else
    fail "az group exists  →  unexpected output: '$RESULT'"
fi
echo ""

# ── 2.2 Azure Data Factory ────────────────────────────────────────────────────
echo "── 2.2 Azure Data Factory ──"
echo "    CMD: az datafactory show --resource-group \$RESOURCE_GROUP --factory-name \$ADF_NAME"
az extension add --name datafactory --only-show-errors 2>/dev/null || true
if az datafactory show \
        --resource-group "$RESOURCE_GROUP" \
        --factory-name   "$ADF_NAME" \
        --output none 2>/dev/null; then
    pass "az datafactory show  →  resource found"
else
    fail "az datafactory show  →  not found OR command failed"
    echo "    ALT: az resource list --resource-type Microsoft.DataFactory/factories --query \"[?name=='\$ADF_NAME']\""
fi
echo ""

# ── 2.3 Storage Account ───────────────────────────────────────────────────────
echo "── 2.3 Storage Account ──"
echo "    CMD: az storage account show --name \$STORAGE_ACCOUNT"
if az storage account show \
        --name    "$STORAGE_ACCOUNT" \
        --output  none 2>/dev/null; then
    pass "az storage account show  →  resource found"
else
    fail "az storage account show  →  not found OR command failed"
    echo "    ALT: az storage account list --query \"[?name=='\$STORAGE_ACCOUNT']\""
fi
echo ""

# ── 2.3 Storage Containers ────────────────────────────────────────────────────
echo "── 2.3 Storage Containers ──"
echo "    CMD: az storage fs show --name <container> --account-name \$STORAGE_ACCOUNT --auth-mode login"
for CONTAINER in bronze silver gold synapse; do
    if az storage fs show \
            --name         "$CONTAINER" \
            --account-name "$STORAGE_ACCOUNT" \
            --auth-mode    login \
            --output none 2>/dev/null; then
        pass "az storage fs show  →  '$CONTAINER' found"
    else
        fail "az storage fs show  →  '$CONTAINER' not found OR command failed"
        echo "    ALT: az storage container show --name $CONTAINER --account-name \$STORAGE_ACCOUNT"
    fi
done
echo ""

# ── 2.4 Databricks Workspace ──────────────────────────────────────────────────
echo "── 2.4 Databricks Workspace ──"
echo "    CMD: az databricks workspace show --resource-group \$RESOURCE_GROUP --name \$DATABRICKS_NAME"
az extension add --name databricks --only-show-errors 2>/dev/null || true
if az databricks workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --name           "$DATABRICKS_NAME" \
        --output none 2>/dev/null; then
    pass "az databricks workspace show  →  resource found"
else
    fail "az databricks workspace show  →  not found OR command failed"
    echo "    ALT: az resource list --resource-type Microsoft.Databricks/workspaces --query \"[?name=='\$DATABRICKS_NAME']\""
fi
echo ""

# ── 2.5 Synapse Workspace ─────────────────────────────────────────────────────
echo "── 2.5 Synapse Workspace ──"
echo "    CMD: az synapse workspace show --resource-group \$RESOURCE_GROUP --name \$SYNAPSE_NAME"
if az synapse workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --name           "$SYNAPSE_NAME" \
        --output none 2>/dev/null; then
    pass "az synapse workspace show  →  resource found"
else
    fail "az synapse workspace show  →  not found OR command failed"
    echo "    ALT: az resource list --resource-type Microsoft.Synapse/workspaces --query \"[?name=='\$SYNAPSE_NAME']\""
fi
echo ""

# ── 2.6 Key Vault ─────────────────────────────────────────────────────────────
echo "── 2.6 Key Vault ──"
echo "    CMD: az keyvault show --name \$KEY_VAULT_NAME"
if az keyvault show \
        --name    "$KEY_VAULT_NAME" \
        --output  none 2>/dev/null; then
    pass "az keyvault show  →  resource found"
else
    fail "az keyvault show  →  not found OR command failed"
    echo "    ALT: az keyvault list --query \"[?name=='\$KEY_VAULT_NAME']\""
fi
echo ""

echo "══════════════════════════════════════════════════════"
echo " Done. Fix any ❌ commands in provision_step1.sh before running."
echo "══════════════════════════════════════════════════════"
