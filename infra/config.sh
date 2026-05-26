# =============================================================================
# config.sh — Shared configuration (all environments)
# Azure E2E Data Engineering Project
#
# ⚠️  Do NOT put resource names here — those live in config.{env}.sh
#
# Load order in provision.sh:
#   1. config.sh          (shared — this file)
#   2. config.{env}.sh    (env-specific resource names, wins over this file)
#   3. secrets.sh         (local passwords/tokens, gitignored)
#
# CI/CD — Required GitHub Secrets:
#   AZURE_CLIENT_ID        → Service Principal app ID
#   AZURE_CLIENT_SECRET    → Service Principal secret
#   AZURE_TENANT_ID        → Entra ID tenant ID
#   AZURE_SUBSCRIPTION_ID  → Azure subscription ID
#   SYNAPSE_SQL_PASSWORD   → Synapse SQL admin password
#   DATABRICKS_TOKEN       → Databricks personal access token
#   SQL_PASSWORD           → On-prem SQL Server login password
# =============================================================================

# ── Azure Identity (same across all environments) ─────────────────────────────
AZURE_SUBSCRIPTION_ID="dc003f8b-ecbb-4bd5-a698-e8208a2efc06"
AZURE_USER="baoshenyi7768@outlook.com"

# ── Unique suffix — fixed creation date (yymmdd) ─────────────────────────────
# Appended to globally-unique resource names (ADF) to avoid cross-tenant name
# collisions and post-delete reservation (~30 min hold after deletion).
# ⚠️  Do NOT use $(date ...) here — dynamic dates break idempotency.
#     Update manually only if you need to recreate resources with a fresh name.
UNIQUE_SUFFIX="260524"

# ── Region (change if prod needs a different region) ──────────────────────────
LOCATION="eastus"

# ── Storage containers (same names across all environments) ───────────────────
CONTAINERS=("bronze" "silver" "gold" "synapse")

# ── Synapse SQL admin username (same across all environments) ─────────────────
SYNAPSE_SQL_USER="sqladmin"
# SYNAPSE_SQL_PASSWORD → secrets.sh or GitHub Secret

# ── Databricks secret scope name (same across all environments) ───────────────
DATABRICKS_SECRET_SCOPE="kv-scope"

# ── Key Vault secret key names (the keys inside KV, not the values) ───────────
# These names are the same in every environment's Key Vault
KV_SECRET_SQL_USER="sql-username"
KV_SECRET_SQL_PASS="sql-password"
KV_SECRET_SP_CLIENT_ID="sp-client-id"
KV_SECRET_SP_CLIENT_SECRET="sp-client-secret"
KV_SECRET_SP_TENANT_ID="sp-tenant-id"
KV_SECRET_DATABRICKS_TOKEN="databricks-token"
