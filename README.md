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
13. place_name_search : lower unaccent place name using the function immutable_unaccent_latin_lowerß

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
  place_name    VARCHAR(180) NULL,
  admin_name1   VARCHAR(100),
  admin_code1   VARCHAR(20),
  admin_name2   VARCHAR(100),
  admin_code2   VARCHAR(20),
  admin_name3   VARCHAR(100),
  admin_code3   VARCHAR(20),
  latitude      DOUBLE PRECISION,
  longitude     DOUBLE PRECISION,
  accuracy      SMALLINT,
	place_name_search VARCHAR(180) GENERATED ALWAYS AS (immutable_unaccent_latin_lower(place_name::text)) STORED NULL
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


Loading all European countries except Greece (no data for this country) : AT,BE,BG,CY,CZ,DE,DK,EE,ES,FI,FR,HR,HU,IE,IT,LT,LU,LV,MT,NL,PL,PT,RO,SE,SI,SK,CH

Parameters :
- COUNTRIES: "AT,BE,BG,CY,CZ,DE,DK,EE,ES,FI,FR,HR,HU,IE,IT,LT,LU,LV,MT,NL,PL,PT,RO,SE,SI,SK,CH"
- UNLOGGED: "true"
- TRUNCATE_BEFORE_LOAD: "false"

Runs :
- First load (empty database) : **11 seconds, 579'304 rows**
- Second load : **12 seconds, 5579'304 rows**

Database size : **121 MB**

# Accent and Case-Insensitive Search Pattern

This project demonstrates a **generic and reusable text search pattern** suitable for:

- people names  
- product names  
- place names  
- any human-entered text containing accents, punctuation, or formatting variations  

The goal is to provide a **robust, user-friendly search** without requiring a full-text search engine.

---

## Principle

All searchable text is **normalized once** using a deterministic SQL function that:

- removes Latin accents (`é → e`, `ü → u`)
- expands ligatures (`Æ → AE`, `Œ → OE`)
- converts text to lowercase
- removes all non-alphanumeric characters

The normalized value is stored in a **generated column** and indexed using a **GIN trigram index**.

This makes searches:
- accent-insensitive
- case-insensitive
- resilient to formatting differences

Here is the function code :
```sql
CREATE OR REPLACE FUNCTION public.immutable_unaccent_latin_lower(txt text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT regexp_replace(
    -- Step 2: keep only letters and digits
    lower(
      -- Step 1: remove Latin diacritics / normalize ligatures
      regexp_replace(
        regexp_replace(
          translate(
            txt,
            -- Latin diacritics (common European set)
            'ÀÁÂÃÄÅĀĂĄÇĆĈČĎĐÈÉÊËĒĔĖĘĚÌÍÎÏĪĮÑŃŇÒÓÔÕÖØŌŐŔŘŚŜŠȘŤŢȚÙÚÛÜŪŮŰŲÝŸŹŻŽ' ||
            'àáâãäåāăąçćĉčďđèéêëēĕėęěìíîïīįñńňòóôõöøōőŕřśŝšșťţțùúûüūůűųýÿźżž',
            'AAAAAAAAACCCCDD' || 'EEEEEEEEE' || 'IIIIII' || 'NNN' || 'OOOOOOOO' || 'RR' || 'SSSS' || 'TTT' || 'UUUUUUUU' || 'YY' || 'ZZZ' ||
            'aaaaaaaaaccccdd' || 'eeeeeeeee' || 'iiiiii' || 'nnn' || 'oooooooo' || 'rr' || 'ssss' || 'ttt' || 'uuuuuuuu' || 'yy' || 'zzz'
          ),
          -- Ligatures / digraphs (1→2): expand before stripping non-alnum
          'Æ', 'AE', 'g'
        ),
        'Œ', 'OE', 'g'
      )
    ),
    '[^a-z0-9]+',
    '',
    'g'
  );
$$;
```

And this is how this function is used :

```sql
ALTER TABLE public.geonames_postal
ADD COLUMN IF NOT EXISTS place_name_search VARCHAR(180)
GENERATED ALWAYS AS (public.immutable_unaccent_latin_lower(place_name)) STORED;

CREATE INDEX IF NOT EXISTS geonames_postal_place_name_search_trgm_idx
ON public.geonames_postal
USING GIN (place_name_search gin_trgm_ops);
```

---

## Example Query

```sql
WITH q AS (
  SELECT public.immutable_unaccent_latin_lower('Crans pres-Céligny') AS needle
)
SELECT gp.postal_code, gp.place_name 
FROM public.geonames_postal gp
CROSS JOIN q
WHERE gp.place_name_search LIKE '%' || q.needle || '%'
ORDER BY gp.place_name_search <-> q.needle
LIMIT 50;
```

The real name of this place name is 'Crans-près-Céligny'. 

```sql
select immutable_unaccent_latin_lower('Crans pres-Céligny')
give this result : cranspresceligny
```

Thanks to this normalization, users can successfully find the same result using a wide range of inputs, for example:

| User input | Normalized input |
|-----------|------------------|
| `Crans-près-Céligny` | `cranspresceligny` |
| `Crans pres Celigny` | `cranspresceligny` |
| `CRANS PRES-CELIGNY` | `cranspresceligny` |
| `celigny` | `celigny` |

All of these inputs are normalized using the same function and matched against the indexed searchable column.


### Query Behavior

The query:
- Normalizes the user input 
- Filters rows whose normalized value contains the input (substring match)
- Orders results by trigram similarity so closer matches appear first
- Returns the top results

Why This Pattern?
- Simple and predictable behavior
- Fast and index-friendly
- Handles accents and spelling variations naturally
- Well suited for search bars and autocomplete

**Normalize once → store → index → search consistently**


