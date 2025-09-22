#!/usr/bin/env sh
set -e

DATA_DIR="${N8N_DATA_DIR:-/home/node/.n8n}"
WF_DIR="/config/workflows"
CREDS_DIR="/config/credentials"

mkdir -p "$WF_DIR" "$CREDS_DIR"

echo "[n8n-init] Using workflows dir:    $WF_DIR"
echo "[n8n-init] Using credentials dir:  $CREDS_DIR"

if [ -n "$(ls -A "$WF_DIR" 2>/dev/null)" ]; then
  echo "[n8n-init] Importing workflows..."
  # Don't die on import errors:
  n8n import:workflow --input="$WF_DIR" --separate --yes || echo "[n8n-init] Workflow import had errors (continuing)"
else
  echo "[n8n-init] No workflows to import."
fi

if [ -n "$(ls -A "$CREDS_DIR" 2>/dev/null)" ]; then
  echo "[n8n-init] Importing credentials..."
  # Creds import requires a matching N8N_ENCRYPTION_KEY; don't die if mismatched:
  n8n import:credentials --input="$CREDS_DIR" --separate --yes || echo "[n8n-init] Credential import had errors (continuing)"
else
  echo "[n8n-init] No credentials to import."
fi

echo "[n8n-init] Starting n8n..."
exec n8n start