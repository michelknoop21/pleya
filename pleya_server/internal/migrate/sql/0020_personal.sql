-- 0020 de persoonlijke laag (S20, PS-9P en PS-9T).
--
-- Eigenaar: internal/watch (geschiedenis) en internal/personal (de rest). Alles
-- hangt aan de gebruiker met ON DELETE CASCADE: een gebruiker weg is zijn
-- geschiedenis, favorieten, waarderingen en spoorvoorkeuren weg, en niemand
-- anders ziet ze.
--
-- play_history is één rij per afspeelsessie (user, item, de door de client
-- gekozen sessie-id), geen rij per event: een film van twee uur met een
-- voortgangsmelding per tien seconden is één regel in de geschiedenis. De rij
-- groeit mee met de events van die sessie. Een geweigerd event van een
-- backlog (offline gekeken) komt er ook in, want dat is precies wat een
-- geschiedenis is die de toestand niet verplaatst (DEC-049, regel 5).
--
-- Backfill: uit watch_states, want de gebeurtenissen zelf zijn nooit bewaard.
-- Elk item met een afspeelmoment krijgt één rij met sessie 'backfill', zodat
-- de lijst bij de eerste keer niet leeg is. Terugdraaien: tabellen droppen,
-- capabilities.history, favorites, ratings en track_preferences gaan uit.

CREATE TABLE play_history (
    id                uuid        PRIMARY KEY,
    user_id           uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    item_id           uuid        NOT NULL REFERENCES media_items (id) ON DELETE CASCADE,
    session_id        text        NOT NULL,
    auth_session_id   uuid        NULL REFERENCES sessions (id) ON DELETE SET NULL,
    started_at        timestamptz NOT NULL,
    last_event_at     timestamptz NOT NULL,
    start_position_ms bigint      NOT NULL CHECK (start_position_ms >= 0),
    end_position_ms   bigint      NOT NULL CHECK (end_position_ms >= 0),
    duration_ms       bigint      NULL CHECK (duration_ms IS NULL OR duration_ms >= 0),
    completed         boolean     NOT NULL DEFAULT false,
    UNIQUE (user_id, item_id, session_id)
);

CREATE INDEX play_history_user_idx ON play_history (user_id, last_event_at DESC, id);
CREATE INDEX play_history_item_idx ON play_history (item_id, last_event_at DESC);

INSERT INTO play_history (id, user_id, item_id, session_id, started_at, last_event_at,
                          start_position_ms, end_position_ms, duration_ms, completed)
SELECT gen_random_uuid(), subject, item_id, 'backfill',
       coalesce(last_played_at, updated_at), coalesce(last_played_at, updated_at),
       0, position_ms, duration_ms, watched
FROM watch_states
WHERE watched OR position_ms > 0 OR play_count > 0;

CREATE TABLE favorites (
    user_id    uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    item_id    uuid        NOT NULL REFERENCES media_items (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, item_id)
);

CREATE INDEX favorites_user_idx ON favorites (user_id, created_at DESC, item_id);

CREATE TABLE ratings (
    user_id    uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    item_id    uuid        NOT NULL REFERENCES media_items (id) ON DELETE CASCADE,
    rating     smallint    NOT NULL CHECK (rating BETWEEN 1 AND 10),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, item_id)
);

-- Een voorkeur voor audio en ondertitels per (gebruiker, item). Het item is een
-- film, een serie of een aflevering; bij het afspelen van een aflevering telt
-- de voorkeur van de aflevering, daarna die van de serie. Een kolom die NULL is
-- zegt niets over die keuze (neem de standaard), en ondertitels uit is
-- subtitle_mode 'off' en niet een lege taal.
CREATE TABLE track_preferences (
    user_id           uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    item_id           uuid        NOT NULL REFERENCES media_items (id) ON DELETE CASCADE,
    audio_language    text        NULL,
    subtitle_language text        NULL,
    subtitle_mode     text        NULL CHECK (subtitle_mode IS NULL OR subtitle_mode IN ('off', 'on', 'forced')),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, item_id)
);
