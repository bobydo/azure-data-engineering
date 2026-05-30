#!/usr/bin/env bash
# =============================================================================
# provision.sh — Phase 2: Azure Resource Provisioning via CLI
# Azure E2E Data Engineering Project
#
# Idempotent: safely re-run at any time — skips resources that already exist.
#
# Prerequisites:
#   1. Install Azure CLI: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
#   2. az login
#   3. Fill infra/secrets.sh with passwords/tokens
#
# Usage:
#   bash infra/provision.sh [dev|uat|prod]         (default: dev, runs all steps)
#   bash infra/provision.sh [dev|uat|prod] <step>  (resume from a specific step)
#
# Steps:
#   0.1  Register resource providers
#   2.1  Resource Group
#   2.2  Azure Data Factory
#   2.3  Storage Account (ADLS Gen2) + containers
#   2.4  Databricks Workspace
#   2.5  Synapse Analytics Workspace
#   2.6  Key Vault + RBAC role assignment
#
# Examples:
#   bash infra/provision.sh dev       # run all steps
#   bash infra/provision.sh dev 2.5   # skip 0.1–2.4, start from Synapse
#   bash infra/provision.sh dev 2.6   # skip to Key Vault only
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIG — base → env override → secrets
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Load base config (shared values + defaults)
source "$SCRIPT_DIR/config.sh"

# 2. Load environment-specific overrides
TARGET_ENV="${1:-dev}"
case "$TARGET_ENV" in
    dev|uat|prod) ;;
    *) echo "❌ Invalid environment '$TARGET_ENV'. Allowed: dev | uat | prod" && exit 1 ;;
esac
source "$SCRIPT_DIR/config.${TARGET_ENV}.sh"
echo "ℹ️  Environment : $TARGET_ENV"

# 3. FROM_STEP — passed as arg OR chosen from interactive menu
FROM_STEP="${2:-}"
if [[ -n "$FROM_STEP" ]]; then
    echo "ℹ️  Resuming from step: $FROM_STEP"
else
    echo ""
    echo "══════════════════════════════════════════════════════"
    echo " Select start step  (Enter = run all)"
    echo "══════════════════════════════════════════════════════"
    echo "  0)  All steps (default)"
    echo "  1)  0.1  Register resource providers"
    echo "  2)  2.1  Resource Group"
    echo "  3)  2.2  Azure Data Factory"
    echo "  4)  2.3  Storage Account + containers"
    echo "  5)  2.4  Databricks Workspace"
    echo "  6)  2.5  Synapse Analytics Workspace"
    echo "  7)  2.6  Key Vault + RBAC"
    echo "══════════════════════════════════════════════════════"
    read -p " Enter [0-7] or step label (e.g. 2.5): " MENU_CHOICE
    case "$MENU_CHOICE" in
        ""|0)  FROM_STEP="" ;;
        1)     FROM_STEP="0.1" ;;
        2)     FROM_STEP="2.1" ;;
        3)     FROM_STEP="2.2" ;;
        4)     FROM_STEP="2.3" ;;
        5)     FROM_STEP="2.4" ;;
        6)     FROM_STEP="2.5" ;;
        7)     FROM_STEP="2.6" ;;
        *)     FROM_STEP="$MENU_CHOICE" ;;  # accept raw label e.g. "2.5" directly
    esac
    [[ -n "$FROM_STEP" ]] && echo "ℹ️  Resuming from step: $FROM_STEP"
fi

# 4. Load secrets — .env is optional
#    Priority: env var → .env → interactive prompt
#    CI/CD: set SYNAPSE_SQL_PASSWORD as a GitHub Secret env var (no .env needed)
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
if [[ -f "$REPO_ROOT/.env" ]]; then
    source "$REPO_ROOT/.env"
    echo "ℹ️  Loaded secrets from .env"
fi

if [[ -z "${SYNAPSE_SQL_PASSWORD:-}" ]]; then
    read -s -p "Enter SYNAPSE_SQL_PASSWORD: " SYNAPSE_SQL_PASSWORD
    echo ""
fi

# =============================================================================
# Helpers
# =============================================================================
exists()  { echo "   ⏭️  Already exists — skipping"; }
created() { echo "   ✅ Created"; }

# Returns 0 (true) if STEP >= FROM_STEP, or if FROM_STEP is empty (run all)
# Comparison: strips the dot so "2.5" → 25, "0.1" → 1
step_enabled() {
    [[ -z "$FROM_STEP" ]] && return 0
    local this req
    this=$(echo "$1"         | tr -d '.' | sed 's/^0*//')
    req=$(echo  "$FROM_STEP" | tr -d '.' | sed 's/^0*//')
    [[ "${this:-0}" -ge "${req:-0}" ]]
}

# =============================================================================
# 0. Verify login & subscription  (always runs — not skippable)
# =============================================================================
echo ""
echo "══════════════════════════════════════════════════════"
echo " Checking Azure CLI login..."
echo "══════════════════════════════════════════════════════"
az account show --query "{Subscription:name, ID:id}" -o table
echo ""
# Skip confirmation in CI/CD: set CI=true or pass --yes as any argument
if [[ "${CI:-}" == "true" || " $* " == *" --yes "* ]]; then
    echo "ℹ️  CI mode — subscription confirmed automatically"
else
    read -p "Is this the correct subscription? (y/n): " CONFIRM
    [[ "$CONFIRM" != "y" ]] && echo "Aborted." && exit 1
fi

# =============================================================================
# 0.1 — Register required resource providers (idempotent — safe to re-run)
# =============================================================================
if step_enabled "0.1"; then
    echo ""
    echo "── 0.1 Resource Provider Registration ──"
    for NS in \
        Microsoft.Storage \
        Microsoft.DataFactory \
        Microsoft.Databricks \
        Microsoft.Synapse \
        Microsoft.Sql \
        Microsoft.KeyVault \
        microsoft.insights \
        microsoft.alertsmanagement; do
        STATE=$(az provider show --namespace "$NS" --query "registrationState" -o tsv 2>/dev/null)
        if [[ "$STATE" == "Registered" ]]; then
            echo "   ⏭️  $NS — already registered"
        else
            echo "   ⏳  Registering $NS..."
            az provider register --namespace "$NS" --wait
            echo "   ✅ $NS — registered"
        fi
    done
fi

# =============================================================================
# 2.1 — Resource Group
# =============================================================================
if step_enabled "2.1"; then
    echo ""
    echo "── 2.1 Resource Group: $RESOURCE_GROUP ──"
    if [[ "$(az group exists --name "$RESOURCE_GROUP")" == "true" ]]; then
        exists
    else
        az group create \
            --name     "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --output   none
        created
    fi
fi

# =============================================================================
# 2.2 — Azure Data Factory
# Note: ADF names are globally unique. Azure holds the name ~30 min after
# deletion. UNIQUE_SUFFIX in config.sh avoids collisions across tenants/runs.
# =============================================================================
if step_enabled "2.2"; then
    echo ""
    echo "── 2.2 Azure Data Factory: $ADF_NAME ──"
    az extension add --name datafactory --only-show-errors 2>/dev/null || true
    ADF_COUNT=$(az resource list \
        --resource-type "Microsoft.DataFactory/factories" \
        --query         "length([?name=='$ADF_NAME'])" \
        -o tsv 2>/dev/null)
    if [[ "${ADF_COUNT:-0}" -gt 0 ]]; then
        exists
    else
        az datafactory create \
            --resource-group "$RESOURCE_GROUP" \
            --factory-name   "$ADF_NAME" \
            --location       "$LOCATION" \
            --output         none
        created
    fi
fi

# =============================================================================
# 2.3 — Storage Account (ADLS Gen2) + containers
# =============================================================================
if step_enabled "2.3"; then
    echo ""
    echo "── 2.3 Storage Account (ADLS Gen2): $STORAGE_ACCOUNT ──"
    if az storage account show --name "$STORAGE_ACCOUNT" --output none 2>/dev/null; then
        exists
    else
        az storage account create \
            --name           "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location       "$LOCATION" \
            --sku            Standard_LRS \
            --kind           StorageV2 \
            --hns            true \
            --output         none
        created
    fi

    echo "   Checking containers..."
    for CONTAINER in bronze silver gold synapse; do
        if az storage fs show \
                --name         "$CONTAINER" \
                --account-name "$STORAGE_ACCOUNT" \
                --auth-mode    login \
                --output none 2>/dev/null; then
            echo "   ⏭️  $CONTAINER — already exists"
        else
            az storage fs create \
                --name         "$CONTAINER" \
                --account-name "$STORAGE_ACCOUNT" \
                --auth-mode    login \
                --output       none
            echo "   ✅ $CONTAINER — created"
        fi
    done
fi

# =============================================================================
# 2.4 — Azure Databricks Workspace
# =============================================================================
if step_enabled "2.4"; then
    echo ""
    echo "── 2.4 Databricks Workspace: $DATABRICKS_NAME ──"
    az extension add --name databricks --only-show-errors 2>/dev/null || true
    DBW_COUNT=$(az resource list \
        --resource-type "Microsoft.Databricks/workspaces" \
        --query         "length([?name=='$DATABRICKS_NAME'])" \
        -o tsv 2>/dev/null)
    if [[ "${DBW_COUNT:-0}" -gt 0 ]]; then
        exists
    else
        az databricks workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --name           "$DATABRICKS_NAME" \
            --location       "$LOCATION" \
            --sku            premium \
            --output         none
        created
    fi
fi

# =============================================================================
# 2.5 — Azure Synapse Analytics Workspace
# =============================================================================
if step_enabled "2.5"; then
    echo ""
    echo "── 2.5 Synapse Workspace: $SYNAPSE_NAME ──"
    SYN_COUNT=$(az resource list \
        --resource-type "Microsoft.Synapse/workspaces" \
        --query         "length([?name=='$SYNAPSE_NAME'])" \
        -o tsv 2>/dev/null)
    if [[ "${SYN_COUNT:-0}" -gt 0 ]]; then
        exists
    else
        az synapse workspace create \
            --name                     "$SYNAPSE_NAME" \
            --resource-group           "$RESOURCE_GROUP" \
            --storage-account          "$STORAGE_ACCOUNT" \
            --file-system              synapse \
            --sql-admin-login-user     "$SYNAPSE_SQL_USER" \
            --sql-admin-login-password "$SYNAPSE_SQL_PASSWORD" \
            --location                 "$LOCATION" \
            --output                   none
        created
    fi
fi

# =============================================================================
# 2.6 — Azure Key Vault
# =============================================================================
if step_enabled "2.6"; then
    echo ""
    echo "── 2.6 Key Vault: $KEY_VAULT_NAME ──"
    KV_COUNT=$(az keyvault list \
        --query "length([?name=='$KEY_VAULT_NAME'])" \
        -o tsv 2>/dev/null)
    if [[ "${KV_COUNT:-0}" -gt 0 ]]; then
        exists
    else
        az keyvault create \
            --name                       "$KEY_VAULT_NAME" \
            --resource-group             "$RESOURCE_GROUP" \
            --location                   "$LOCATION" \
            --enable-rbac-authorization  true \
            --output                     none
        created
    fi

    # Assign Key Vault Administrator role if not already assigned.
    # ⚠️  az role assignment commands fail for personal Microsoft accounts (outlook.com)
    #     with MissingSubscription. The entire block runs under set +e so failures
    #     never abort the script — a Portal fallback message is shown instead.
    echo "   Checking Key Vault Administrator role..."
    set +e

    TOKEN_PAYLOAD=$(az account get-access-token \
        --resource "https://management.azure.com/" \
        --query    accessToken -o tsv 2>/dev/null | cut -d'.' -f2)
    CURRENT_USER_OID=$(printf '%s' "${TOKEN_PAYLOAD:-}" | \
        awk '{n=length($0)%4; if(n==2)print $0"=="; else if(n==3)print $0"="; else print $0}' | \
        base64 -d 2>/dev/null | \
        grep -o '"oid":"[^"]*"' | cut -d'"' -f4 2>/dev/null)

    if [[ -z "${CURRENT_USER_OID:-}" ]]; then
        echo "   ⚠️  Could not determine OID (MSA account limitation)"
    else
        KV_RESOURCE_ID=$(az keyvault show \
            --name           "$KEY_VAULT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query id -o tsv 2>/dev/null)

        ROLE_EXISTS=$(az role assignment list \
            --assignee-object-id "$CURRENT_USER_OID" \
            --role               "Key Vault Administrator" \
            --scope              "$KV_RESOURCE_ID" \
            --query              "length(@)" -o tsv 2>/dev/null)

        if [[ "${ROLE_EXISTS:-0}" -gt 0 ]]; then
            echo "   ⏭️  Role already assigned — skipping"
        else
            ASSIGN_RESULT=$(az role assignment create \
                --assignee-object-id      "$CURRENT_USER_OID" \
                --assignee-principal-type User \
                --role                    "Key Vault Administrator" \
                --scope                   "$KV_RESOURCE_ID" \
                --output                  json 2>&1)
            if echo "$ASSIGN_RESULT" | grep -q "roleDefinitionId"; then
                echo "   ✅ Key Vault Administrator role assigned"
            else
                echo "   ⚠️  CLI role assignment failed — assign via Portal if not already done:"
                echo "      Portal → Key Vault '$KEY_VAULT_NAME' → Access Control (IAM)"
                echo "              → Add role assignment → Key Vault Administrator → (your user)"
            fi
        fi
    fi

    set -e
fi

# =============================================================================
# Done
# =============================================================================
echo ""
echo "══════════════════════════════════════════════════════"
echo " ✅ Phase 2 Complete — all resources provisioned"
echo "══════════════════════════════════════════════════════"
echo ""
echo "Resource Group : $RESOURCE_GROUP"
echo "Location       : $LOCATION"
echo "Storage        : $STORAGE_ACCOUNT  (bronze / silver / gold / synapse)"
echo "ADF            : $ADF_NAME"
echo "Databricks     : $DATABRICKS_NAME"
echo "Synapse        : $SYNAPSE_NAME"
echo "Key Vault      : $KEY_VAULT_NAME"
echo ""
echo "Next: Phase 3 — add secrets to Key Vault (SQL login + Service Principal)"
echo "  bash infra/keyvault-secrets_step2.sh $TARGET_ENV"
