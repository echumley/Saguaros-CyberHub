#!/usr/bin/env sh
set -euo pipefail

echo "[modules] ENABLED_MODULES=${ENABLED_MODULES:-<none>}"

# If nothing is set, skip quietly
[ -z "${ENABLED_MODULES:-}" ] && { echo "[modules] No modules enabled. Skipping."; exit 0; }

# Wait until the DB is up (entrypoint usually is, but be safe for dependent calls)
# The entrypoint will call this during initdb. At this point psql should work with $POSTGRES_DB.
DB_NAME="${POSTGRES_DB:-postgres}"
DB_USER="${POSTGRES_USER:-postgres}"

for mod in ${ENABLED_MODULES}; do
  file="/docker-entrypoint-initdb.d/modules/${mod}.sql"
  if [ -f "$file" ]; then
    echo "[modules] Applying module: ${mod} -> ${file}"
    psql -v ON_ERROR_STOP=1 -U "${DB_USER}" -d "${DB_NAME}" -f "$file"
  else
    echo "[modules] WARNING: No file for module '${mod}' at ${file}; skipping."
  fi
done

echo "[modules] Done."