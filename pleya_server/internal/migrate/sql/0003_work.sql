-- 0003 werk: de jobwachtrij en de scanadministratie.
--
-- Hoofdstuk 17.1 legt de eigenschap vast en niet de bibliotheek: duurzame jobs
-- met retries en zichtbaarheid, in dezelfde database, zonder tweede
-- infrastructuurcomponent. Eén transactie kan daarmee een scanresultaat en de
-- bijbehorende vervolgjob atomair wegschrijven.
--
-- Deze tabel is een eigen implementatie en geen keuze tegen River. PS-2 heeft
-- twee soorten werk in één proces; overstappen blijft een migratie.

CREATE TABLE jobs (
    id            uuid        PRIMARY KEY,
    kind          text        NOT NULL,
    args          jsonb       NOT NULL DEFAULT '{}'::jsonb,
    state         text        NOT NULL DEFAULT 'pending'
        CHECK (state IN ('pending', 'running', 'succeeded', 'failed', 'cancelled')),
    priority      integer     NOT NULL DEFAULT 0,
    run_at        timestamptz NOT NULL DEFAULT now(),
    attempts      integer     NOT NULL DEFAULT 0,
    max_attempts  integer     NOT NULL DEFAULT 3,

    -- Houdt een tweede scanverzoek voor dezelfde bibliotheek uit de wachtrij
    -- zolang de eerste nog loopt of wacht. Alleen daar uniek: een afgeronde job
    -- mag zijn sleutel weer vrijgeven.
    dedupe_key    text        NULL,

    locked_at     timestamptz NULL,
    locked_by     text        NULL,
    last_error    text        NULL,

    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    finished_at   timestamptz NULL
);

CREATE UNIQUE INDEX jobs_dedupe_key_uidx ON jobs (dedupe_key)
    WHERE dedupe_key IS NOT NULL AND state IN ('pending', 'running');

-- De claimquery: pending, toe aan een beurt, hoogste prioriteit eerst en daarna
-- op id, wat door UUIDv7 gelijkstaat aan aanmaakvolgorde.
CREATE INDEX jobs_claim_idx ON jobs (run_at, priority DESC, id) WHERE state = 'pending';
CREATE INDEX jobs_state_idx ON jobs (state, updated_at DESC);

-- Zonder websocket is dit het antwoord op "hangt de scanner of is de NAS
-- gewoon traag". De tellers lopen tijdens de ronde op, zodat voortgang zichtbaar
-- is in de database, in de logs en in de metrics.
CREATE TABLE scan_runs (
    id               uuid        PRIMARY KEY,
    library_id       uuid        NOT NULL REFERENCES libraries (id) ON DELETE CASCADE,
    trigger          text        NOT NULL CHECK (trigger IN ('startup', 'schedule', 'manual')),
    state            text        NOT NULL DEFAULT 'running'
        CHECK (state IN ('running', 'succeeded', 'failed', 'cancelled')),

    started_at       timestamptz NOT NULL DEFAULT now(),
    finished_at      timestamptz NULL,

    files_seen       bigint      NOT NULL DEFAULT 0,
    files_new        bigint      NOT NULL DEFAULT 0,
    files_renamed    bigint      NOT NULL DEFAULT 0,
    files_changed    bigint      NOT NULL DEFAULT 0,
    files_probed     bigint      NOT NULL DEFAULT 0,
    files_missing    bigint      NOT NULL DEFAULT 0,
    bytes_hashed     bigint      NOT NULL DEFAULT 0,
    items_created    bigint      NOT NULL DEFAULT 0,
    versions_created bigint      NOT NULL DEFAULT 0,
    error_count      bigint      NOT NULL DEFAULT 0,
    last_error       text        NULL,
    current_path     text        NULL
);

CREATE INDEX scan_runs_library_started_idx ON scan_runs (library_id, started_at DESC);
