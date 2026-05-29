# databricks/lib — Azure Databricks shared library
# ──────────────────────────────────────────────────
# Reusable modules for this Azure Data Engineering project.
# Load in any notebook with:
#
#   %run ./lib/adls_auth
#
# Modules
# -------
# adls_auth.py  — AdlsAuth class: ADLS Gen2 OAuth2 via Service Principal
#                 setup_logger() utility
#
# Usage
# -----
#   auth  = AdlsAuth(dbutils, spark, scope="kv-scope")
#   paths = auth.setup("sadataeng260524dev")
#   BRONZE, SILVER, GOLD = paths["BRONZE"], paths["SILVER"], paths["GOLD"]
