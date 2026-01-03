#!/usr/bin/env bash
set -euo pipefail

BASE_URL="https://download.geonames.org/export/zip"
COUNTRIES_RAW="${COUNTRIES:-CH}"
COUNTRIES="$(echo "$COUNTRIES_RAW" | tr ',' ' ' | xargs)"

UNLOGGED="${UNLOGGED:-true}"
TRUNCATE_BEFORE_LOAD="${TRUNCATE_BEFORE_LOAD:-false}"

echo "Countries to load: ${COUNTRIES}"
echo "UNLOGGED: ${UNLOGGED}"
echo "TRUNCATE_BEFORE_LOAD: ${TRUNCATE_BEFORE_LOAD}"

psql -v ON_ERROR_STOP=1 -c "SELECT version();"

# CHANGED: table dans le schéma public
TABLE_EXISTS="$(psql -tA -v ON_ERROR_STOP=1 \
  -c "SELECT to_regclass('public.geonames_postal') IS NOT NULL;")"

if [[ "${TABLE_EXISTS}" != "t" ]]; then
  echo "Creating table public.geonames_postal..."
  if [[ "${UNLOGGED}" == "true" ]]; then
    psql -v ON_ERROR_STOP=1 <<'SQL'
CREATE UNLOGGED TABLE public.geonames_postal (
  country_code  CHAR(2)      NOT NULL,
  postal_code   VARCHAR(20)  NOT NULL,
  place_name    VARCHAR(180) NOT NULL,
  admin_name1   VARCHAR(100),
  admin_code1   VARCHAR(20),
  admin_name2   VARCHAR(100),
  admin_code2   VARCHAR(20),
  admin_name3   VARCHAR(100),
  admin_code3   VARCHAR(20),
  latitude      DOUBLE PRECISION,
  longitude     DOUBLE PRECISION,
  accuracy      SMALLINT
);
SQL
  else
    psql -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE public.geonames_postal (
  country_code  CHAR(2)      NOT NULL,
  postal_code   VARCHAR(20)  NOT NULL,
  place_name    VARCHAR(180) NOT NULL,
  admin_name1   VARCHAR(100),
  admin_code1   VARCHAR(20),
  admin_name2   VARCHAR(100),
  admin_code2   VARCHAR(20),
  admin_name3   VARCHAR(100),
  admin_code3   VARCHAR(20),
  latitude      DOUBLE PRECISION,
  longitude     DOUBLE PRECISION,
  accuracy      SMALLINT
);
SQL
  fi

  # Index + contraintes
  psql -v ON_ERROR_STOP=1 -f /app/create_table.sql
else
  echo "Table public.geonames_postal already exists."
  psql -v ON_ERROR_STOP=1 -f /app/create_table.sql
fi

if [[ "${TRUNCATE_BEFORE_LOAD}" == "true" ]]; then
  echo "Truncating public.geonames_postal..."
  psql -v ON_ERROR_STOP=1 -c "TRUNCATE public.geonames_postal;"
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

for CC in ${COUNTRIES}; do
  CC_UP="$(echo "${CC}" | tr '[:lower:]' '[:upper:]')"

  ZIP_URL="${BASE_URL}/${CC_UP}.zip"
  ZIP_PATH="${WORKDIR}/${CC_UP}.zip"
  OUT_DIR="${WORKDIR}/${CC_UP}"

  echo "----"
  echo "Downloading ${ZIP_URL}"
  mkdir -p "${OUT_DIR}"
  curl -fsSL --retry 3 --retry-delay 2 -o "${ZIP_PATH}" "${ZIP_URL}"

  echo "Unzipping ${CC_UP}.zip"
  unzip -oq "${ZIP_PATH}" -d "${OUT_DIR}"

  TXT_FILE="${OUT_DIR}/${CC_UP}.txt"


  if [[ ! -f "${TXT_FILE}" ]]; then
    echo "ERROR: Expected file not found: ${TXT_FILE}"
    exit 1
  fi

  echo "Deleting existing rows for country_code=${CC_UP}"
  psql -v ON_ERROR_STOP=1 \
    -c "DELETE FROM public.geonames_postal WHERE country_code = '${CC_UP}';"

  echo "Loading ${TXT_FILE} into public.geonames_postal"
  COPY_CMD="\\copy public.geonames_postal (country_code, postal_code, place_name,  admin_name1, admin_code1, admin_name2, admin_code2, admin_name3, admin_code3, latitude, longitude, accuracy ) FROM '${TXT_FILE}' WITH (FORMAT csv, DELIMITER E'\\t', NULL '', HEADER false, QUOTE E'\\x01', ESCAPE E'\\x01' , LOG_VERBOSITY verbose);"


  echo "----- COPY command to execute -----"
  echo "${COPY_CMD}"
  echo "----------------------------------"
  printf '%s\n' "${COPY_CMD}" | psql -v ON_ERROR_STOP=0

  psql -tA -v ON_ERROR_STOP=1 \
    -c "SELECT count(*) FROM public.geonames_postal WHERE country_code='${CC_UP}';"
done

echo "Total rows:"
psql -tA -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM public.geonames_postal;"
echo "Done."

echo "Vacuum ANALYZE public.geonames_postal:"
psql -tA -v ON_ERROR_STOP=1 -c "VACUUM ANALYZE public.geonames_postal;"
echo "Done."
