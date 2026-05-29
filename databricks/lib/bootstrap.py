# lib/bootstrap.py — one-line loader for all lib/ modules
# ──────────────────────────────────────────────────────────
# Add ONE cell at the top of every notebook:
#
#   %run ./lib/bootstrap
#
# After that, both styles work:
#
#   from adls_auth import AdlsAuth        # direct import
#   import adls_auth; adls_auth.AdlsAuth  # module namespace

import sys

# Discover lib/ path from the calling notebook's workspace location.
# notebookPath() returns the CALLER's path (not bootstrap.py's path),
# so this resolves correctly regardless of where the notebooks are deployed.
_ctx  = dbutils.notebook.entry_point.getDbutils().notebook().getContext()
_root = '/Workspace' + _ctx.notebookPath().get().rsplit('/', 1)[0]
_lib  = f"{_root}/lib"

if _lib not in sys.path:
    sys.path.insert(0, _lib)

# Pre-import all lib modules so callers get them in scope immediately
import adls_auth                              # noqa: E402
from adls_auth import AdlsAuth, setup_logger  # noqa: E402, F401

print(f"lib loaded from: {_lib}")
