# GeoNames Postal Codes with PostgreSQL

This project provides a simple and reproducible way to load **postal codes and place names** into a **PostgreSQL** database using data from **GeoNames**.

It is designed to be used in a **Docker / docker-compose** environment and supports loading one or more countries at startup.

---

## Overview

The loader:
- Creates the database table and indexes 
- Downloads postal code datasets from **https://download.geonames.org/export/zip/**
- Extracts country-specific ZIP archives (e.g. `CH.zip`)
- Loads the data into a PostgreSQL table using `COPY / \copy`
- Performs a vacuum analyze on the geonames_postal table
- Is fully **idempotent** (safe to run multiple times)

The database is treated as **rebuildable reference data**:
- **No database backup is required**, as the entire dataset is reloaded automatically each time the loader container starts
- The database can be safely dropped and recreated at any time
- Reload times are short enough to make full rebuilds practical (see Performances section)

It is recommended to **re-import the data on a regular basis** (weekly or monthly) in order to keep postal code information up to date with the latest GeoNames releases.

This setup is well suited for:
- Micro-services performing postal code lookups - no database backup is needed
- Reference data rebuilt at startup
- Lightweight read-only workloads backed by PostgreSQL

---

## Data Source

This project uses **GeoNames Postal Code Data**, provided by:

> **GeoNames**  
> https://www.geonames.org/  
> https://download.geonames.org/export/zip/

The GeoNames postal code files contain the following fields (tab-separated):

1. country code (ISO 3166-1 alpha-2)
2. postal code
3. place name
4. admin name 1 (state)
5. admin code 1
6. admin name 2 (county / province)
7. admin code 2
8. admin name 3 (community)
9. admin code 3
10. latitude (WGS84)
11. longitude (WGS84)
12. accuracy

Note:
- A single postal code may map to **multiple places**
- Some fields (e.g. `accuracy`) may be empty
- GeoNames data may contain duplicate logical rows

Please refer to GeoNames’ license and terms of use:
https://www.geonames.org/export/

---

## Database Schema

The data is stored in a single table:

```sql
public.geonames_postal
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
```

## Docker Setup

### Services

The project is composed of two services:

- **PostgreSQL**
  - Stores the postal codes and place names
  - Can be configured to use `UNLOGGED` tables for fast reloads

- **Loader**
  - Downloads GeoNames postal code ZIP files
  - Extracts and loads the data into PostgreSQL
  - Can load one or multiple countries
  - Is safe to run multiple times (idempotent)

---

## Environment Variables

The loader is configured via environment variables.

| Variable | Description | Example |
|--------|-------------|---------|
| `COUNTRIES` | ISO 3166-1 alpha-2 country codes to load | `CH,FR,DE,IT,AT,LI` |
| `PGHOST` | PostgreSQL hostname | `db` |
| `PGPORT` | PostgreSQL port | `5432` |
| `PGDATABASE` | Database name | `geonames` |
| `PGUSER` | Database user | `geonames` |
| `PGPASSWORD` | Database password | `geonames` |
| `UNLOGGED` | Use UNLOGGED tables (`true` / `false`) | `true` |

---

## Running the Stack

### Start PostgreSQL and load data

```bash
docker compose up --build
```

This will:
	•	start PostgreSQL
	•	run the loader once
	•	download and import the configured countries

## Data Source and License

This project uses GeoNames Postal Code Data:
	•	https://www.geonames.org/
	•	https://download.geonames.org/export/zip/

GeoNames data is subject to GeoNames’ license and terms of use.
Please ensure compliance when using or redistributing the data.

## Performances

Tests were performed on a MacBook Pro M4 Pro with 24 GB of memory.

### Load performances

The docker compose file uses a command parameter to fit with pgTune parameters (2 cpu, 256 MB of memory).


Loading all European countries except Greece (no data for this country) : AT,BE,BG,CY,CZ,DE,DK,EE,ES,FI,FR,HR,HU,IE,IT,LT,LU,LV,MT,NL,PL,PT,RO,SE,SI,SK

Parameters :
- COUNTRIES: "AT,BE,BG,CY,CZ,DE,DK,EE,ES,FI,FR,HR,HU,IE,IT,LT,LU,LV,MT,NL,PL,PT,RO,SE,SI,SK"
- UNLOGGED: "true"
- TRUNCATE_BEFORE_LOAD: "false"

Runs :
- First load (empty database) : **10 seconds, 552'914 rows**
- Second load : **11 seconds, 552'914 rows**

Database size : **114 MB**

### Query performances

Queries performed on the 'European database'

```sql
select * from geonames_postal gp where gp.postal_code =$1 and gp.country_code =$2
```

Average query performances : **0.08 ms**


```sql
SELECT * FROM public.geonames_postal WHERE lower(place_name) LIKE $1 || lower($2) || $3
```

Average query performances : **0.30 ms**

