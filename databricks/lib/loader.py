# lib/loader.py — Dynamic sys.path loader for Databricks notebooks
# ─────────────────────────────────────────────────────────────────
# Paste this block at the top of any notebook to import lib/ modules
# as proper Python namespaces (no %run needed).
#
# Usage — add ONE cell at the top of each notebook:
#
#   import sys
#   _ctx  = dbutils.notebook.entry_point.getDbutils().notebook().getContext()
#   _root = '/Workspace' + _ctx.notebookPath().get().rsplit('/', 1)[0]
#   if f"{_root}/lib" not in sys.path:
#       sys.path.insert(0, f"{_root}/lib")
#
#   from adls_auth import AdlsAuth, setup_logger
#
# Why this works
# ──────────────
# Databricks runs notebooks from /Workspace/<user>/<folder>/.
# notebookPath() returns e.g. /Users/user@email.com/notebooks/storagemount
# rsplit('/', 1)[0]  → /Users/user@email.com/notebooks
# prepend /Workspace → /Workspace/Users/user@email.com/notebooks
# append  /lib       → /Workspace/Users/user@email.com/notebooks/lib
#
# Python then finds adls_auth.py there and imports it normally.
# sys.path guard ensures the path is only added once per session.
