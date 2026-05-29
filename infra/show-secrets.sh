#!/bin/bash
# Show all Key Vault secret values
# Usage (Azure Cloud Shell):
#   bash infra/show-secrets.sh

VAULT="kv-dataengproj-dev"

echo "=== Key Vault: $VAULT ==="
for name in $(az keyvault secret list --vault-name "$VAULT" --query "[].name" -o tsv); do
  val=$(az keyvault secret show --vault-name "$VAULT" --name "$name" --query value -o tsv)
  echo "  $name = $val"
done
