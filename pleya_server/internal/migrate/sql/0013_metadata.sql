-- 0013 metadata: beschrijvende velden op het item, de kandidatenlaag en
-- artwork dat een provider heeft opgehaald.
--
-- De regel uit RB-27: een provider schrijft nooit op het canonieke record. Het
-- resultaat van een zoekopdracht landt in metadata_candidates, en een aparte
-- stap past dat toe op media_items. metadata_sources zegt per veld wie het
-- gezet heeft, zodat een latere sidecar of handmatige correctie (S4, S22.5) de
-- providerwaarde kan overrulen zonder dat een volgende ronde hem terugdraait.
-- Voorrang per veld: handmatig, dan sidecar, dan provider.

ALTER TABLE media_items
    ADD COLUMN summary          text    NULL,
    ADD COLUMN content_rating   text    NULL,
    ADD COLUMN genres           text[]  NULL,
    -- {"summary": "tmdb", "genres": "tmdb"}. Een veld zonder sleutel is nog door
    -- niemand gezet.
    ADD COLUMN metadata_sources jsonb   NOT NULL DEFAULT '{}'::jsonb;

CREATE TABLE metadata_candidates (
    item_id         uuid        PRIMARY KEY REFERENCES media_items (id) ON DELETE CASCADE,
    provider        text        NOT NULL,
    -- 'matched' is de uitkomst van de driestapsregel; 'ambiguous' wordt nooit
    -- vanzelf opgelost en wacht op een mens (S22.5); 'unmatched' wordt na een
    -- tijd opnieuw geprobeerd, want de provider groeit.
    state           text        NOT NULL CHECK (state IN ('matched', 'ambiguous', 'unmatched')),
    external_id     text        NULL,
    -- Wat de provider antwoordde, in de vorm die wij gebruiken. Geen ruw
    -- antwoord: een HTML-foutpagina komt hier nooit terecht (zie de client).
    details         jsonb       NULL,
    attempts        integer     NOT NULL DEFAULT 0,
    last_attempt_at timestamptz NOT NULL DEFAULT now(),
    next_attempt_at timestamptz NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT metadata_candidates_matched_has_id CHECK (state <> 'matched' OR external_id IS NOT NULL)
);

CREATE INDEX metadata_candidates_due_idx ON metadata_candidates (next_attempt_at)
    WHERE next_attempt_at IS NOT NULL;

-- Een afbeelding in CacheDir. De bytes zijn te herhalen vanuit de provider, dus
-- dit is cache en geen bron van waarheid; het bestand heet na het id.
CREATE TABLE provider_artwork (
    id          uuid        PRIMARY KEY,
    item_id     uuid        NOT NULL REFERENCES media_items (id) ON DELETE CASCADE,
    kind        text        NOT NULL CHECK (kind IN ('poster', 'backdrop')),
    provider    text        NOT NULL,
    source_ref  text        NOT NULL,
    file_name   text        NOT NULL,
    sha256      text        NOT NULL,
    -- Loopt op als de bytes vervangen worden; het artwork-ETag leunt erop.
    generation  bigint      NOT NULL DEFAULT 1,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),

    UNIQUE (item_id, kind, provider)
);

CREATE INDEX provider_artwork_item_idx ON provider_artwork (item_id);
