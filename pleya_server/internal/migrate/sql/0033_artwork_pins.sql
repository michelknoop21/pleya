-- Alleen bewuste keuze/bronidentiteit; bytes blijven herbouwbare cache, geen mediaback-up.
CREATE TABLE artwork_pins (
    item_id uuid NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
    kind text NOT NULL CHECK(kind IN ('poster','backdrop')),
    id uuid NOT NULL UNIQUE,
    source text NOT NULL CHECK(source IN ('local','tmdb')),
    source_file_id uuid NULL,
    source_ref text NULL,
    sha256 text NOT NULL CHECK(sha256 ~ '^[a-f0-9]{64}$'),
    extension text NOT NULL CHECK(extension IN ('.jpg','.png','.webp')),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(item_id,kind),
    CHECK((source='local' AND source_file_id IS NOT NULL AND source_ref IS NULL)
       OR (source='tmdb' AND source_file_id IS NULL AND source_ref IS NOT NULL AND source_ref ~ '^/[A-Za-z0-9_-]{1,200}\.(jpg|png|webp)$'))
);
-- source_file_id is bewust geen cascade-FK: bronverlies mag de intentie niet wissen.
