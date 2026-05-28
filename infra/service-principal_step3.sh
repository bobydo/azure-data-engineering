#!/usr/bin/env bash
# =============================================================================
# service-principal_step3.sh — Phase 4: Create Service Principal for ADLS Access
# Azure E2E Data Engineering Project
#
# Creates a Service Principal and grants it Storage Blob Data Contributor on
# the ADLS Gen2 storage account so Databricks can authenticate via OAuth2.
#
# Idempotent: if the SP already exists (same display name), reuses it and
# only creates a new client secret if --reset-secret is passed.
#
# Prerequisites:
#   Phase 2 complete (provision_step1.sh) — storage account must exist
#
# Usage:
#   bash infra/service-principal_step3.sh [dev|uat|prod]   (default: dev)
#   bash infra/service-principal_step3.sh dev --reset-secret  # rotate client secret
#
# After this script: nothing — SP credentials are written directly to Key Vault.
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

RESET_SECRET="${2:-}"
SP_DISPLAY_NAME="sp-data-engineering-${TARGET_ENV}"

echo "ℹ️  Environment    : $TARGET_ENV"
echo "ℹ️  SP Display Name: $SP_DISPLAY_NAME"
echo "ℹ️  Storage Account: $STORAGE_ACCOUNT"

echo ""
echo "══════════════════════════════════════════════════════"
echo " Phase 4 — Service Principal: $SP_DISPLAY_NAME"
echo "══════════════════════════════════════════════════════"

# =============================================================================
# 4.1 — Create or reuse Service Principal
# =============================================================================
echo ""
echo "── 4.1 Service Principal ──"
EXISTING_APP_ID=$(az ad app list \
    --display-name "$SP_DISPLAY_NAME" \
    --query        "[0].appId" \
    -o tsv 2>/dev/null || true)

if [[ -n "$EXISTING_APP_ID" && "$EXISTING_APP_ID" != "None" ]]; then
    echo "   ⏭️  Already exists (appId: $EXISTING_APP_ID)"
    SP_CLIENT_ID="$EXISTING_APP_ID"

    if [[ "$RESET_SECRET" == "--reset-secret" ]]; then
        echo "   🔄 Resetting client secret..."
        SECRET_JSON=$(az ad app credential reset \
            --id    "$SP_CLIENT_ID" \
            --years 2 \
            --output json 2>/dev/null)
        SP_CLIENT_SECRET=$(echo "$SECRET_JSON" | grep -o '"password": *"[^"]*"' | cut -d'"' -f4)
        echo "   ✅ Secret reset"
    else
        echo "   ℹ️  To rotate the secret: bash infra/service-principal_step3.sh $TARGET_ENV --reset-secret"
        SP_CLIENT_SECRET="<existing — check secrets.sh or Key Vault>"
    fi
else
    echo "   ⏳  Creating..."
    SECRET_JSON=$(az ad sp create-for-rbac \
        --name   "$SP_DISPLAY_NAME" \
        --years  2 \
        --output json 2>/dev/null)
    SP_CLIENT_ID=$(echo     "$SECRET_JSON" | grep -o '"appId": *"[^"]*"'    | cut -d'"' -f4)
    SP_CLIENT_SECRET=$(echo "$SECRET_JSON" | grep -o '"password": *"[^"]*"' | cut -d'"' -f4)
    echo "   ✅ Created (appId: $SP_CLIENT_ID)"
fi

# SP tenant ID is always the subscription tenant
SP_TENANT_ID=$(az account show --query tenantId -o tsv)

# =============================================================================
# 4.2 — Assign Storage Blob Data Contributor on the ADLS storage account
#        Databricks needs this to read/write bronze / silver / gold containers
# Note: az role assignment list fails for MSA (outlook.com) accounts.
#       Skip the check — attempt create directly and swallow RoleAssignmentExists.
# =============================================================================
echo ""
echo "── 4.2 Role: Storage Blob Data Contributor → $STORAGE_ACCOUNT ──"
STORAGE_RESOURCE_ID=$(az storage account show \
    --name  "$STORAGE_ACCOUNT" \
    --query id \
    -o tsv 2>/dev/null)

# Get SP object ID (not appId) — required for --assignee-object-id
SP_OBJECT_ID=$(az ad sp show --id "$SP_CLIENT_ID" --query id -o tsv 2>/dev/null || true)

if [[ -z "$SP_OBJECT_ID" ]]; then
    echo "   ❌ Cannot resolve SP object ID for appId '$SP_CLIENT_ID'"
    echo "      The SP may not exist or may not be visible in this tenant."
    echo "      Assign the role manually:"
    echo "      Portal → Storage '$STORAGE_ACCOUNT' → Access Control (IAM)"
    echo "      → Add role assignment → Storage Blob Data Contributor"
    echo "      → Search by display name: $SP_DISPLAY_NAME"
    exit 1
fi

ASSIGN_OUTPUT=$(az role assignment create \
    --assignee-object-id      "$SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role                    "Storage Blob Data Contributor" \
    --scope                   "$STORAGE_RESOURCE_ID" \
    --output                  json 2>&1 || true)

if echo "$ASSIGN_OUTPUT" | grep -q "RoleAssignmentExists"; then
    echo "   ⏭️  Already assigned — skipping"
elif echo "$ASSIGN_OUTPUT" | grep -q "roleDefinitionId"; then
    echo "   ✅ Role assigned"
else
    echo "   ❌ Role assignment failed — assign manually and re-run to continue:"
    echo "      Portal → Storage '$STORAGE_ACCOUNT' → Access Control (IAM)"
    echo "      → Add role assignment → Storage Blob Data Contributor → $SP_DISPLAY_NAME"
    echo "      Error details: $ASSIGN_OUTPUT"
    exit 1
fi

# Verify role was actually assigned
echo "   🔍 Verifying role assignment..."
VERIFY=$(az role assignment list \
    --assignee "$SP_OBJECT_ID" \
    --scope    "$STORAGE_RESOURCE_ID" \
    --query    "[?roleDefinitionName=='Storage Blob Data Contributor'].roleDefinitionName" \
    -o tsv 2>/dev/null || true)

if [[ "$VERIFY" == "Storage Blob Data Contributor" ]]; then
    echo "   ✅ Role verified on storage account"
else
    echo "   ⚠️  Could not verify role (common with MSA accounts — check Portal IAM tab)"
fi

# =============================================================================
# 4.3 — Write SP secrets directly to Key Vault (CI/CD approach — no copy-paste)
# Polls for KV access first (RBAC propagation can take ~2 min after assignment)
# =============================================================================
echo ""
echo "── 4.3 Writing SP secrets to Key Vault: $KEY_VAULT_NAME ──"

MAX_ATTEMPTS=20
INTERVAL=15
ACCESS_OK=false
for i in $(seq 1 $MAX_ATTEMPTS); do
    if az keyvault secret list --vault-name "$KEY_VAULT_NAME" --output none 2>/dev/null; then
        ACCESS_OK=true
        break
    fi
    echo "   ⏳ Waiting for KV access... (attempt $i/${MAX_ATTEMPTS}, ${INTERVAL}s interval)"
    sleep $INTERVAL
done

if [[ "$ACCESS_OK" != "true" ]]; then
    echo "   ❌ KV access timed out — run keyvault-secrets_step2.sh manually after fixing access"
else
    for SECRET_NAME in sp-client-id sp-client-secret sp-tenant-id; do
        case "$SECRET_NAME" in
            sp-client-id)     VALUE="$SP_CLIENT_ID"     ;;
            sp-client-secret) VALUE="$SP_CLIENT_SECRET" ;;
            sp-tenant-id)     VALUE="$SP_TENANT_ID"     ;;
        esac
        if [[ -n "$VALUE" && "$VALUE" != "<existing"* ]]; then
            az keyvault secret set \
                --vault-name "$KEY_VAULT_NAME" \
                --name       "$SECRET_NAME" \
                --value      "$VALUE" \
                --output     none
            echo "   ✅ $SECRET_NAME — set"
        else
            echo "   ⏭️  $SECRET_NAME — skipped (existing SP, secret unknown — use --reset-secret)"
        fi
    done
fi

# =============================================================================
# Done
# =============================================================================
echo ""
echo "══════════════════════════════════════════════════════"
echo " ✅ Phase 4 Complete"
echo "══════════════════════════════════════════════════════"
echo ""
echo "SP credentials written directly to Key Vault — no manual copy needed."
echo "⚠️  For local secrets.sh (optional — used by keyvault-secrets_step2.sh):"
echo "──────────────────────────────────────────────────────"
echo "SP_CLIENT_ID=\"$SP_CLIENT_ID\""
echo "SP_CLIENT_SECRET=\"$SP_CLIENT_SECRET\""
echo "SP_TENANT_ID=\"$SP_TENANT_ID\""
echo "──────────────────────────────────────────────────────"
echo ""
echo "To rotate secret later: bash infra/service-principal_step3.sh $TARGET_ENV --reset-secret"
echo ""
echo "Next: Phase 5 — ADF Self-hosted Integration Runtime"
echo "  ADF Studio → Manage → Integration Runtimes → New → Self-hosted → install on local machine"
