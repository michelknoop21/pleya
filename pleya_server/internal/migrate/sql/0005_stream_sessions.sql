-- 0005 PS-4: browser-streamsessies.
--
-- Volgt DEC-051. Apart van 0004 omdat het een andere verantwoordelijkheid is:
-- 0004 gaat over wie de kijkstatus bezit, dit gaat over wie bytes mag ophalen.
-- Migraties zijn voorwaarts en genummerd, dus twee bestanden kost niets en
-- houdt de geschiedenis leesbaar.
--
-- Dit is persistente auth-state, en specificatie 6.5 somt uitputtend op wat een
-- server daarvan mag hebben. Deze tabel komt er niet stilzwijgend bij: DEC-051
-- voegt hem toe aan die lijst, met dezelfde eigenschap als een refreshtoken. De
-- server bewaart het geheim NIET; er staat een SHA-256 van, zodat een
-- databasedump geen speelbare sessies oplevert.

-- Kortlevend, en gebonden aan één subject en één versie.
CREATE TABLE stream_sessions (
    id            uuid        PRIMARY KEY,
    subject       text        NOT NULL,
    version_id    uuid        NOT NULL REFERENCES media_versions (id) ON DELETE CASCADE,
    secret_hash   bytea       NOT NULL,

    created_at    timestamptz NOT NULL DEFAULT now(),
    expires_at    timestamptz NOT NULL,
    revoked_at    timestamptz NULL,
    last_used_at  timestamptz NULL
);

-- De telling van acht actieve sessies per subject loopt over deze index, en de
-- opruiming van verlopen sessies ook.
CREATE INDEX stream_sessions_subject_active_idx
    ON stream_sessions (subject, expires_at) WHERE revoked_at IS NULL;
