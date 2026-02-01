
-- Main index (query by country_code + postal_code)
CREATE INDEX IF NOT EXISTS geonames_postal_postal_code_idx
  ON public.geonames_postal (country_code,postal_code);

-- optionnal indexe (query by place_name)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

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

ALTER TABLE public.geonames_postal
ADD COLUMN IF NOT EXISTS place_name_search VARCHAR(180)
GENERATED ALWAYS AS (public.immutable_unaccent_latin_lower(place_name)) STORED;

CREATE INDEX IF NOT EXISTS geonames_postal_place_name_search_trgm_idx
ON public.geonames_postal
USING GIN (place_name_search gin_trgm_ops);