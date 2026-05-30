#!/usr/bin/env bash
# =============================================================================
# keyvault-secrets_step2.sh — Phase 3: Store secrets in Azure Key Vault
# Azure E2E Data Engineering Project
#
# Idempotent: re-running overwrites secrets with the current values in secrets.sh.
# Secrets with empty values in secrets.sh are skipped with a reminder.
#
# Prerequisites:
#   1. Phase 2 complete (provision.sh) — Key Vault must exist
#   2. infra/secrets.sh filled with SQL credentials
#   3. After Phase 4: fill SP_CLIENT_ID / SP_CLIENT_SECRET / SP_TENANT_ID
#   4. After Phase 7: fill DATABRICKS_TOKEN
#
# Usage:
#   bash infra/keyvault-secrets_step2.sh [dev|uat|prod]   (default: dev)
#
# Secrets written:
#   sql-username  ← SQL_USERNAME  (ADF → on-prem SQL Server)
#   sql-password  ← SQL_PASSWORD  (ADF → on-prem SQL Server)
#
# Other secrets are handled by dedicated scripts (no manual copy needed):
#   sp-client-id / sp-client-secret / sp-tenant-id → service-principal_step3.sh
#   databricks-token                               → databricks-token_step4.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Load shared config
source "$SCRIPT_DIR/config.sh"

# 2. Load env-specific overrides
TARGET_ENV="${1:-dev}"
case "$TARGET_ENV" in
    dev|uat|prod) ;;
    *) echo "❌ Invalid environment '$TARGET_ENV'. Allowed: dev | uat | prod" && exit 1 ;;
esac
source "$SCRIPT_DIR/config.${TARGET_ENV}.sh"
echo "ℹ️  Environment : $TARGET_ENV"
echo "ℹ️  Key Vault   : $KEY_VAULT_NAME"

# 3. Load secrets — .env is optional
#    Priority: env var → .env → interactive prompt
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
if [[ -f "$REPO_ROOT/.env" ]]; then
    source "$REPO_ROOT/.env"
    echo "ℹ️  Loaded secrets from .env"
fi

if [[ -z "${SQL_USERNAME:-}" ]]; then
    read -p "Enter SQL_USERNAME: " SQL_USERNAME
fi
if [[ -z "${SQL_PASSWORD:-}" ]]; then
    read -s -p "Enter SQL_PASSWORD: " SQL_PASSWORD
    echo ""
fi

echo ""
echo "══════════════════════════════════════════════════════"
echo " Phase 3 — Key Vault Secrets: $KEY_VAULT_NAME"
echo "══════════════════════════════════════════════════════"

# =============================================================================
# Wait for Key Vault RBAC to propagate (polls up to 5 min)
# Azure RBAC role assignments can take 1–5 min to take effect after assignment.
# =============================================================================
echo ""
echo "── Checking Key Vault access (waiting for RBAC propagation) ──"
# Fixed 20 attempts × 15s = 5 min max — no infinite loop possible
MAX_ATTEMPTS=20
INTERVAL=15
ACCESS_OK=false
for i in $(seq 1 $MAX_ATTEMPTS); do
    if az keyvault secret list --vault-name "$KEY_VAULT_NAME" --output none 2>/dev/null; then
        echo "   ✅ Access confirmed (attempt $i/${MAX_ATTEMPTS})"
        ACCESS_OK=true
        break
    fi
    echo "   ⏳ Not yet propagated — retrying in ${INTERVAL}s... (attempt $i/${MAX_ATTEMPTS})"
    sleep $INTERVAL
done

if [[ "$ACCESS_OK" != "true" ]]; then
    echo "   ❌ Timed out after $((MAX_ATTEMPTS * INTERVAL))s — verify role is assigned:"
    echo "      Portal → Key Vault '$KEY_VAULT_NAME' → Access Control (IAM)"
    exit 1
fi

# =============================================================================
# Helper: set a secret if value is non-empty, skip with reminder if empty
# Usage: set_secret <kv-secret-name> <value> <description>
# =============================================================================
set_secret() {
    local SECRET_NAME="$1"
    local SECRET_VALUE="$2"
    local DESCRIPTION="$3"

    if [[ -z "$SECRET_VALUE" ]]; then
        echo "   ⏭️  $SECRET_NAME — empty in secrets.sh, skipping ($DESCRIPTION)"
    else
        az keyvault secret set \
            --vault-name "$KEY_VAULT_NAME" \
            --name       "$SECRET_NAME" \
            --value      "$SECRET_VALUE" \
            --output     none
        echo "   ✅ $SECRET_NAME — set"
    fi
}

# =============================================================================
# Grant AzureDatabricks read access to Key Vault secrets
# Required for Databricks kv-scope (Key Vault-backed secret scope).
# AzureDatabricks is a Microsoft-managed enterprise application (global app ID
# 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d) present in every Azure tenant.
# Without this, dbutils.secrets.get() fails with PERMISSION_DENIED.
# =============================================================================
echo ""
echo "── Granting AzureDatabricks Key Vault Secrets User role ──"
ADB_SP_APP_ID="2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"
KV_SCOPE="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}"

ADB_OID=$(az ad sp show --id "$ADB_SP_APP_ID" --query id -o tsv 2>/dev/null || true)
if [[ -z "$ADB_OID" ]]; then
    echo "   ⚠️  AzureDatabricks SP not found — skipping"
    echo "      (Normal if Databricks not yet provisioned — re-run after Phase 7)"
else
    az role assignment create \
        --assignee-object-id    "$ADB_OID" \
        --assignee-principal-type ServicePrincipal \
        --role                  "Key Vault Secrets User" \
        --scope                 "$KV_SCOPE" \
        --output none 2>/dev/null \
    && echo "   ✅ AzureDatabricks → Key Vault Secrets User" \
    || echo "   ℹ️  Role already assigned — skipping"
fi

# =============================================================================
# SQL Server credentials (ADF linked service → on-prem SQL Server)
# =============================================================================
echo ""
echo "── SQL Server Credentials ──"
set_secret "sql-username" "${SQL_USERNAME:-}"      "fill SQL_USERNAME in secrets.sh"
set_secret "sql-password" "${SQL_PASSWORD:-}"      "fill SQL_PASSWORD in secrets.sh"

# SP secrets → handled by service-principal_step3.sh (writes directly to KV)
# Databricks token → handled by databricks-token_step4.sh (after Phase 7)

# =============================================================================
# Done
# =============================================================================
echo ""
echo "══════════════════════════════════════════════════════"
echo " ✅ Phase 3 Complete"
echo "══════════════════════════════════════════════════════"
echo ""
echo "Verify in Portal: Key Vault '$KEY_VAULT_NAME' → Secrets"
echo ""
echo "Next: Phase 4 — Create Service Principal"
echo "  bash infra/service-principal_step3.sh $TARGET_ENV"
