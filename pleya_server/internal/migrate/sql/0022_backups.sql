-- 0022 back-ups en hersteltests (S25, PS-11B, RB-26).
--
-- Eigenaar: internal/backup. Een back-up is een tar in de back-upmap met de
-- databasedump, /config en de verpakte geheimen; deze tabel is het register
-- erbij en niet de waarheid. Het bestand en zijn manifest zijn dat wel: na een
-- restore zijn deze twee tabellen leeg (pg_dump neemt hun rijen bewust niet
-- mee), en het opstarten registreert dan opnieuw wat er in de map staat.
--
-- status loopt running -> ok of failed. missing betekent dat het bestand uit de
-- map verdween zonder dat de server het weghaalde. failure is de soort fout,
-- want een faalpad hoort een eigen foutcode te krijgen (RB-26): disk_full wordt
-- storage.full, database_unavailable wordt server.database_unavailable, failed
-- is al het andere. error is de tekst voor het log en komt niet op de lijn.
--
-- Een hersteltest hangt aan zijn back-up met ON DELETE CASCADE: valt een
-- back-up buiten de bewaartermijn, dan heeft zijn hersteltest niets meer te
-- bewijzen. Terugdraaien: beide tabellen droppen en capabilities.backups
-- uitzetten.

CREATE TABLE backups (
    id               uuid        PRIMARY KEY,
    file_name        text        NULL,
    trigger          text        NOT NULL CHECK (trigger IN ('schedule', 'manual', 'upgrade')),
    status           text        NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'ok', 'failed', 'missing')),
    failure          text        NULL CHECK (failure IS NULL OR failure IN ('disk_full', 'database_unavailable', 'failed')),
    error            text        NULL,
    schema_version   integer     NULL,
    size_bytes       bigint      NULL CHECK (size_bytes IS NULL OR size_bytes >= 0),
    titles           bigint      NULL CHECK (titles IS NULL OR titles >= 0),
    secrets_included boolean     NOT NULL DEFAULT false,
    started_at       timestamptz NOT NULL DEFAULT now(),
    finished_at      timestamptz NULL
);

CREATE INDEX backups_started_idx ON backups (started_at DESC, id DESC);

CREATE TABLE backup_restore_tests (
    id              uuid        PRIMARY KEY,
    backup_id       uuid        NOT NULL REFERENCES backups (id) ON DELETE CASCADE,
    status          text        NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'ok', 'failed')),
    failure         text        NULL CHECK (failure IS NULL OR failure IN ('disk_full', 'database_unavailable', 'failed')),
    error           text        NULL,
    schema_from     integer     NULL,
    schema_to       integer     NULL,
    titles_expected bigint      NULL,
    titles_found    bigint      NULL,
    started_at      timestamptz NOT NULL DEFAULT now(),
    finished_at     timestamptz NULL
);

CREATE INDEX backup_restore_tests_backup_idx ON backup_restore_tests (backup_id, started_at DESC);
