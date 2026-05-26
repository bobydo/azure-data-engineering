#!/usr/bin/env bash
# =============================================================================
# cleanup.sh — Delete all resources for a given environment
# Azure E2E Data Engineering Project
#
# ⚠️  DESTRUCTIVE — deletes resource groups and ALL resources inside them.
#     Use with caution, especially for prod.
#
# Usage:
#   bash infra/cleanup.sh [dev|uat|prod]   (default: dev)
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

echo ""
echo "══════════════════════════════════════════════════════"
echo " ⚠️  CLEANUP — Environment: $TARGET_ENV"
echo "══════════════════════════════════════════════════════"
echo " Will delete:"
echo "   Resource Group : $RESOURCE_GROUP (+ all resources inside)"
echo "   Databricks RGs : any 'databricks-rg-*' managed resource groups"
echo "══════════════════════════════════════════════════════"
echo ""
read -p "Type '$TARGET_ENV' to confirm deletion: " CONFIRM
[[ "$CONFIRM" != "$TARGET_ENV" ]] && echo "Aborted." && exit 0

# ── Delete main resource group (cascades to ADF, Storage, Synapse, KV etc.) ──
echo ""
echo "── Deleting resource group: $RESOURCE_GROUP ──"
if [[ "$(az group exists --name "$RESOURCE_GROUP")" == "true" ]]; then
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    echo "   🗑️  Deletion triggered (runs in background — takes ~5 min)"
else
    echo "   ⏭️  Does not exist — skipping"
fi

# ── Delete Databricks-managed resource groups (auto-created, not always cleaned up) ──
echo ""
echo "── Checking Databricks managed resource groups ──"
DBW_MANAGED_RGS=$(az group list \
    --query "[?starts_with(name, 'databricks-rg-$DATABRICKS_NAME') || \
              starts_with(name, 'mrg-$DATABRICKS_NAME') || \
              starts_with(name, 'mrg-databricks')].name" \
    -o tsv 2>/dev/null || true)

if [[ -z "$DBW_MANAGED_RGS" ]]; then
    echo "   ⏭️  None found — skipping"
else
    while IFS= read -r RG; do
        echo "   🗑️  Deleting: $RG"
        az group delete --name "$RG" --yes --no-wait
    done <<< "$DBW_MANAGED_RGS"
fi

echo ""
echo "══════════════════════════════════════════════════════"
echo " ✅ Cleanup triggered for env: $TARGET_ENV"
echo "    Deletion runs in background — wait ~5 min then"
echo "    verify in Azure Portal before re-running provision_step1.sh"
echo "══════════════════════════════════════════════════════"
echo ""
echo "    Next: bash infra/provision_step1.sh $TARGET_ENV"
