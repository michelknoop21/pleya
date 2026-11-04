-- Additive, source-bound detail presentation. Existing item fields remain unchanged.
ALTER TABLE media_items ADD COLUMN detail_presentation jsonb NULL;
ALTER TABLE provider_artwork DROP CONSTRAINT provider_artwork_kind_check;
ALTER TABLE provider_artwork ADD CONSTRAINT provider_artwork_kind_check CHECK (
  kind IN ('poster','backdrop') OR kind ~ '^(logo|portrait):[0-9a-f]{64}$'
);
