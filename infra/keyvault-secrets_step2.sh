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
#   sql-username        ← SQL_USERNAME      (ADF → on-prem SQL Server)
#   sql-password        ← SQL_PASSWORD      (ADF → on-prem SQL Server)
#   sp-client-id        ← SP_CLIENT_ID      (Databricks → ADLS Gen2 OAuth2)
#   sp-client-secret    ← SP_CLIENT_SECRET  (Databricks → ADLS Gen2 OAuth2)
#   sp-tenant-id        ← SP_TENANT_ID      (Databricks → ADLS Gen2 OAuth2)
#   databricks-token    ← DATABRICKS_TOKEN  (ADF → Databricks notebook activity)
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

# 3. Load secrets
if [[ -f "$SCRIPT_DIR/secrets.sh" ]]; then
    source "$SCRIPT_DIR/secrets.sh"
    echo "ℹ️  Loaded secrets from infra/secrets.sh"
else
    echo "❌ infra/secrets.sh not found — create it from secrets.sh.example" && exit 1
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
# SQL Server credentials (ADF linked service → on-prem SQL Server)
# =============================================================================
echo ""
echo "── SQL Server Credentials ──"
set_secret "sql-username" "${SQL_USERNAME:-}"      "fill SQL_USERNAME in secrets.sh"
set_secret "sql-password" "${SQL_PASSWORD:-}"      "fill SQL_PASSWORD in secrets.sh"

# =============================================================================
# Service Principal credentials (Databricks → ADLS Gen2 via OAuth2)
# Created in Phase 4 — fill SP_* vars in secrets.sh after az ad sp create
# =============================================================================
echo ""
echo "── Service Principal (OAuth2 for Databricks → ADLS) ──"
set_secret "sp-client-id"     "${SP_CLIENT_ID:-}"     "fill SP_CLIENT_ID after Phase 4"
set_secret "sp-client-secret" "${SP_CLIENT_SECRET:-}" "fill SP_CLIENT_SECRET after Phase 4"
set_secret "sp-tenant-id"     "${SP_TENANT_ID:-}"     "fill SP_TENANT_ID after Phase 4"

# =============================================================================
# Databricks personal access token (ADF → Databricks notebook activity)
# Created in Phase 7 — fill DATABRICKS_TOKEN in secrets.sh after workspace setup
# =============================================================================
echo ""
echo "── Databricks Token ──"
set_secret "databricks-token" "${DATABRICKS_TOKEN:-}" "fill DATABRICKS_TOKEN after Phase 7"

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
echo "Pending secrets (re-run this script after filling secrets.sh):"
echo "  Phase 4 → SP_CLIENT_ID, SP_CLIENT_SECRET, SP_TENANT_ID"
echo "  Phase 7 → DATABRICKS_TOKEN"
echo ""
echo "Next: Phase 4 — Create Service Principal"
echo "  bash infra/service-principal.sh $TARGET_ENV"
