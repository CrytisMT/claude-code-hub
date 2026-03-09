#!/bin/bash
set -euo pipefail

PG_DATA="/var/lib/postgresql/data"
PG_USER="postgres"
DB_NAME="${DB_NAME:-claude_code_hub}"
DB_PASSWORD="${DB_PASSWORD:-postgres}"

# ──────────────────────────────────────────
# 1. Initialize PostgreSQL on first boot
# ──────────────────────────────────────────
if [ ! -d "${PG_DATA}/base" ]; then
  echo "[entrypoint] First boot: Initializing PostgreSQL data directory..."
  mkdir -p "${PG_DATA}"
  chown -R "${PG_USER}:${PG_USER}" "${PG_DATA}"

  gosu "${PG_USER}" initdb \
    -D "${PG_DATA}" \
    --auth=trust \
    --username="${PG_USER}" \
    --encoding=UTF8 \
    --locale=C

  # Allow local connections
  echo "host all all 127.0.0.1/32 trust" >> "${PG_DATA}/pg_hba.conf"
  echo "host all all ::1/128 trust"       >> "${PG_DATA}/pg_hba.conf"

  echo "[entrypoint] Starting temporary PostgreSQL instance to create database..."
  gosu "${PG_USER}" pg_ctl \
    -D "${PG_DATA}" \
    -o "-c listen_addresses='127.0.0.1'" \
    -w start

  echo "[entrypoint] Creating database: ${DB_NAME}"
  gosu "${PG_USER}" psql -c "CREATE DATABASE \"${DB_NAME}\";"
  gosu "${PG_USER}" psql -c "ALTER USER \"${PG_USER}\" WITH PASSWORD '${DB_PASSWORD}';"

  echo "[entrypoint] Stopping temporary PostgreSQL instance..."
  gosu "${PG_USER}" pg_ctl -D "${PG_DATA}" -w stop

  echo "[entrypoint] PostgreSQL initialized successfully."
else
  echo "[entrypoint] PostgreSQL data directory already exists, skipping init."
  # Ensure correct ownership in case of volume remount
  chown -R "${PG_USER}:${PG_USER}" "${PG_DATA}"
fi

# ──────────────────────────────────────────
# 2. Export DSN for the app (override any
#    externally provided value with the
#    correct internal address)
# ──────────────────────────────────────────
export DSN="postgresql://${PG_USER}:${DB_PASSWORD}@127.0.0.1:5432/${DB_NAME}"

echo "[entrypoint] Starting all services via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
