#!/usr/bin/env bash
# Dev entrypoint: install gems, prepare the (multi-shard) database, seed demo
# data, then boot the Rails server bound to all interfaces so Docker can map it.
set -e
cd /app

echo "==> Ruby: $(ruby -v)"

echo "==> bundle install"
bundle install

echo "==> Waiting for PostgreSQL at ${PGHOST}:${PGPORT} ..."
until pg_isready -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" >/dev/null 2>&1; do
  sleep 1
done
echo "    PostgreSQL is ready."

# db:prepare creates + migrates the primary DB and the tenant/demo shards
# (see config/database.yml) and seeds when the DB is fresh. PGHOST/PGUSER/
# PGPASSWORD route every shard to the db service.
# Kept non-fatal on purpose: a failing seed step must NOT stop the server from
# booting, so we can always inspect the app and refine seeding separately.
echo "==> rails db:prepare (primary + shards, seeds on fresh DB)"
set +e
bundle exec rails db:prepare
prep_status=$?
set -e
if [ "$prep_status" -ne 0 ]; then
  echo "    WARN: db:prepare exited $prep_status (likely a seed step) — booting anyway."
fi

# Our LATAM tenant setup (idempotent): subdomain 'default' so the dev/admin
# tenant resolver finds the demo website, plus locale/currency defaults.
echo "==> rails latam:configure_demo"
bundle exec rails latam:configure_demo || echo "    (configure_demo returned non-zero; continuing)"

echo "==> Starting Rails server on 0.0.0.0:${PORT:-3000}"
exec bundle exec rails server -b 0.0.0.0 -p "${PORT:-3000}"
