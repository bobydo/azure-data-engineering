# lib/bootstrap.py — one-line loader for the bobydo namespace
# ─────────────────────────────────────────────────────────────
# Add ONE cell at the top of every notebook:
#
#   %run ./lib/bootstrap
#
# After that, use the bobydo namespace:
#
#   auth  = bobydo.AdlsAuth(dbutils, spark)
#   paths = auth.setup("sadataeng260524dev")

import sys

# Discover lib/ path from the calling notebook's workspace location.
# notebookPath() returns the CALLER's path (not bootstrap.py's path),
# so this resolves correctly regardless of where notebooks are deployed.
_ctx  = dbutils.notebook.entry_point.getDbutils().notebook().getContext()
_root = '/Workspace' + _ctx.notebookPath().get().rsplit('/', 1)[0]
_lib  = f"{_root}/lib"

if _lib not in sys.path:
    sys.path.insert(0, _lib)

# Import bobydo namespace — available as bobydo.AdlsAuth after %run
import bobydo  # noqa: E402

print(f"bobydo v{bobydo.__version__} loaded from: {_lib}")
