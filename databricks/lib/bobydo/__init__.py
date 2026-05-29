# bobydo — Azure Data Engineering shared library
# ─────────────────────────────────────────────────
# Namespace: bobydo
# Author:    bobydo
#
# Usage in any notebook:
#   %run ./lib/bootstrap
#   auth  = bobydo.AdlsAuth(dbutils, spark)
#   paths = auth.setup("sadataeng260524dev")

from .adls_auth import AdlsAuth, setup_logger  # noqa: F401

__all__    = ["AdlsAuth", "setup_logger"]
__version__ = "0.1.0"
__author__  = "bobydo"
