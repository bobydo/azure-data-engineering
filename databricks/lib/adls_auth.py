# lib/adls_auth.py — Azure ADLS Gen2 authentication library
# ───────────────────────────────────────────────────────────
# Usage in any notebook:
#   %run ./lib/adls_auth
#   auth  = AdlsAuth(dbutils, spark)
#   paths = auth.setup(storage_account)   # {"BRONZE": ..., "SILVER": ..., "GOLD": ...}

import logging
import sys


# ── Logging ──────────────────────────────────────────────────────────────────

def setup_logger(name: str = "de_project") -> logging.Logger:
    """Create a logger with timestamp + level formatting.

    Idempotent — calling twice on the same name returns the same logger
    without adding duplicate handlers.
    """
    logger = logging.getLogger(name)
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(logging.Formatter(
            fmt="%(asctime)s [%(levelname)-8s] %(name)s — %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S"
        ))
        logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    return logger


# ── ADLS Auth ────────────────────────────────────────────────────────────────

class AdlsAuth:
    """Manages ADLS Gen2 OAuth2 authentication via Service Principal.

    Enterprise pattern:
      - Reads credentials from Key Vault via Databricks secret scope
      - Validates secrets before touching Spark config
      - Logs every step with timestamps
      - Raises descriptive RuntimeError on failure (never silently swallows)

    Args:
        dbutils: Databricks dbutils object (injected — enables unit testing)
        spark:   Active SparkSession (injected)
        scope:   Databricks secret scope name backed by Key Vault
    """

    REQUIRED_SECRETS = ["sp-client-id", "sp-client-secret", "sp-tenant-id"]

    def __init__(self, dbutils, spark, scope: str = "kv-scope"):
        self._dbutils = dbutils
        self._spark   = spark
        self._scope   = scope
        self._log     = setup_logger("AdlsAuth")

    # ── Preflight ──────────────────────────────────────────────────────────

    def verify_secrets(self) -> None:
        """Verify secret scope exists and all required secrets are readable.

        Raises:
            RuntimeError: if scope is missing or any secret is unreadable.
        """
        self._log.info(f"Verifying secret scope: '{self._scope}'")

        try:
            scopes = [s.name for s in self._dbutils.secrets.listScopes()]
        except Exception as e:
            raise RuntimeError(f"Cannot list secret scopes: {e}") from e

        if self._scope not in scopes:
            raise RuntimeError(
                f"Secret scope '{self._scope}' not found. "
                f"Available: {scopes}. "
                "→ Create scope at <workspace-url>#secrets/createScope"
            )
        self._log.info(f"Scope '{self._scope}' found ✅")

        missing = []
        for key in self.REQUIRED_SECRETS:
            try:
                val = self._dbutils.secrets.get(scope=self._scope, key=key)
                self._log.info(f"  Secret '{key}' readable ({len(val)} chars) ✅")
            except Exception as e:
                self._log.error(f"  Secret '{key}' NOT readable: {e}")
                missing.append(key)

        if missing:
            raise RuntimeError(
                f"Missing secrets in scope '{self._scope}': {missing}. "
                "Check Key Vault contents and scope configuration."
            )

        self._log.info("All secrets verified ✅")

    # ── OAuth2 config ──────────────────────────────────────────────────────

    def configure_oauth2(self, storage_account: str) -> None:
        """Configure Spark OAuth2 for the given ADLS Gen2 storage account.

        Args:
            storage_account: Azure storage account name (e.g. 'sadataeng260524dev')

        Raises:
            RuntimeError: if secrets cannot be read or Spark config fails.
        """
        self._log.info(f"Configuring OAuth2 for: {storage_account}")
        acct = f"{storage_account}.dfs.core.windows.net"

        try:
            client_id     = self._dbutils.secrets.get(self._scope, "sp-client-id")
            client_secret = self._dbutils.secrets.get(self._scope, "sp-client-secret")
            tenant_id     = self._dbutils.secrets.get(self._scope, "sp-tenant-id")
        except Exception as e:
            raise RuntimeError(
                f"Failed to read SP credentials from scope '{self._scope}': {e}"
            ) from e

        endpoint = f"https://login.microsoftonline.com/{tenant_id}/oauth2/token"

        try:
            self._spark.conf.set(f"fs.azure.account.auth.type.{acct}", "OAuth")
            self._spark.conf.set(
                f"fs.azure.account.oauth.provider.type.{acct}",
                "org.apache.hadoop.fs.azurebfs.oauth2.ClientCredsTokenProvider"
            )
            self._spark.conf.set(f"fs.azure.account.oauth2.client.id.{acct}",       client_id)
            self._spark.conf.set(f"fs.azure.account.oauth2.client.secret.{acct}",   client_secret)
            self._spark.conf.set(f"fs.azure.account.oauth2.client.endpoint.{acct}", endpoint)
        except Exception as e:
            raise RuntimeError(f"Failed to set Spark OAuth2 config for '{acct}': {e}") from e

        self._log.info(f"OAuth2 ready for {acct} ✅")

    # ── Path helpers ───────────────────────────────────────────────────────

    def get_paths(self, storage_account: str) -> dict:
        """Return abfss:// paths for bronze, silver, gold containers.

        Returns:
            dict with keys BRONZE, SILVER, GOLD
        """
        def path(container):
            return f"abfss://{container}@{storage_account}.dfs.core.windows.net"

        return {
            "BRONZE": path("bronze"),
            "SILVER": path("silver"),
            "GOLD":   path("gold"),
        }

    # ── Combined setup ─────────────────────────────────────────────────────

    def setup(self, storage_account: str) -> dict:
        """Verify secrets, configure OAuth2, and return paths in one call.

        Args:
            storage_account: Azure storage account name

        Returns:
            dict with BRONZE, SILVER, GOLD paths

        Raises:
            RuntimeError: on any failure — secrets, Spark config, or access
        """
        self.verify_secrets()
        self.configure_oauth2(storage_account)
        paths = self.get_paths(storage_account)
        self._log.info(f"Setup complete — BRONZE={paths['BRONZE']}")
        return paths
