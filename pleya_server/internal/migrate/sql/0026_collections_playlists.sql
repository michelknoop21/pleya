-- 0026 verzamelingen en afspeellijsten (S19, PS-9C, DEC-XXX).
--
-- Eigenaar: internal/catalog. Het plan noemde 0018; dat nummer en alles tot en
-- met 0025 was bij het bouwen bezet.
--
-- Een verzameling heeft een eigenaar en een zichtbaarheid (privé, iedereen of
-- per gebruiker, VRAGENLIJST 30). Een afspeellijst is van één gebruiker en
-- speelt op volgorde. Beide zijn many-to-many met media_items, want een titel
-- hoort in meer lijsten tegelijk en parent_id is één kolom.
--
-- position is een stabiele sleutel met gaten, geen rijnummer: één item
-- verplaatsen schrijft één rij. UNIQUE is DEFERRABLE omdat een hernummering
-- binnen één transactie tijdelijk botsingen kent.
--
-- ON DELETE CASCADE op media_items: een item dat uit de catalogus verdwijnt
-- verdwijnt uit elke lijst, en de gaten die dat achterlaat zijn onschadelijk.
-- Een hernoemd of verplaatst bestand houdt zijn item-id en dus zijn plek.
-- ON DELETE CASCADE op users: een gebruiker weg is zijn lijsten weg, en wat hij
-- met anderen deelde gaat mee.
--
-- Geen backfill, de tabellen beginnen leeg. Terugdraaien: tabellen droppen,
-- capabilities.collections en capabilities.playlists gaan uit.

CREATE TABLE collections (
    id         uuid        PRIMARY KEY,
    owner_id   uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title      text        NOT NULL CHECK (char_length(title) BETWEEN 1 AND 200),
    visibility text        NOT NULL DEFAULT 'private'
        CHECK (visibility IN ('private', 'everyone', 'users')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX collections_owner_idx ON collections (owner_id, updated_at DESC, id);
CREATE INDEX collections_everyone_idx ON collections (updated_at DESC, id) WHERE visibility = 'everyone';

-- Alleen betekenisvol bij visibility = 'users'; een andere zichtbaarheid wist de rijen.
CREATE TABLE collection_users (
    collection_id uuid NOT NULL REFERENCES collections (id) ON DELETE CASCADE,
    user_id       uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    PRIMARY KEY (collection_id, user_id)
);

CREATE INDEX collection_users_user_idx ON collection_users (user_id, collection_id);

CREATE TABLE collection_items (
    collection_id uuid        NOT NULL REFERENCES collections (id) ON DELETE CASCADE,
    item_id       uuid        NOT NULL REFERENCES media_items (id) ON DELETE CASCADE,
    position      bigint      NOT NULL,
    added_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (collection_id, item_id),
    CONSTRAINT collection_items_position_key
        UNIQUE (collection_id, position) DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX collection_items_item_idx ON collection_items (item_id);

CREATE TABLE playlists (
    id         uuid        PRIMARY KEY,
    owner_id   uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title      text        NOT NULL CHECK (char_length(title) BETWEEN 1 AND 200),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX playlists_owner_idx ON playlists (owner_id, updated_at DESC, id);

CREATE TABLE playlist_items (
    playlist_id uuid        NOT NULL REFERENCES playlists (id) ON DELETE CASCADE,
    item_id     uuid        NOT NULL REFERENCES media_items (id) ON DELETE CASCADE,
    position    bigint      NOT NULL,
    added_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (playlist_id, item_id),
    CONSTRAINT playlist_items_position_key
        UNIQUE (playlist_id, position) DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX playlist_items_item_idx ON playlist_items (item_id);
