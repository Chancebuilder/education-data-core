#!/usr/bin/env bash
# Create the local Postgres roles and database used by .env.example.
# Safe to re-run. Development passwords are local-only defaults.
set -euo pipefail

if ! pg_isready -q; then
  echo "PostgreSQL is not accepting connections. Start the server, then re-run this script." >&2
  exit 1
fi

sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'edu_migrator') THEN
    CREATE ROLE edu_migrator LOGIN SUPERUSER PASSWORD 'edu_migrator';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'edu_api') THEN
    CREATE ROLE edu_api LOGIN NOSUPERUSER NOBYPASSRLS PASSWORD 'edu_api';
  END IF;
END $$;
SELECT 'CREATE DATABASE education_data_core OWNER edu_migrator'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'education_data_core')\gexec
SQL

echo "Local database education_data_core is ready."
echo "Next: cp .env.example .env && npm run db:setup && npm run dev"
