
-- Main index (query by country_code + postal_code)
CREATE INDEX IF NOT EXISTS geonames_postal_postal_code_idx
  ON public.geonames_postal (country_code,postal_code);

-- optionnal indexe (query by place_name)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE INDEX IF NOT EXISTS geonames_postal_place_name_lower_trgm_idx
ON public.geonames_postal
USING GIN ((lower(place_name)) gin_trgm_ops);
