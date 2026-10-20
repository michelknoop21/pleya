-- 0019 transcodesessies (S18.1, PS-8).
--
-- Eigenaar: internal/transcode. Een sessie is een lopend ffmpeg-proces dat een
-- versie omzet naar HLS voor één speler; de rij bestaat voor beheer ("wie
-- transcodeert nu") en om na een herstart te weten dat er niets meer loopt.
-- Het proces zelf en zijn bestanden zijn vluchtig en staan in /transcode.
--
-- Sleutels: user_id volgt de gebruiker (weg = sessie weg), version_id de
-- versie. Een sessie zonder inlogsessie (token ingetrokken) blijft staan tot
-- hij eindigt, dus session_id wordt NULL in plaats van te cascaderen.
-- Backfill: geen, de tabel is nieuw. Terugdraaien: tabel droppen, het
-- planbeleid valt terug op alleen direct play (capabilities.transcode uit).
CREATE TABLE transcode_sessions (
    id              uuid        PRIMARY KEY,
    user_id         uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    session_id      uuid        NULL REFERENCES sessions (id) ON DELETE SET NULL,
    version_id      uuid        NOT NULL REFERENCES media_versions (id) ON DELETE CASCADE,
    mode            text        NOT NULL CHECK (mode IN ('remux', 'direct_stream', 'transcode')),
    state           text        NOT NULL CHECK (state IN ('running', 'finished', 'failed', 'stopped')),
    hw_accel        text        NULL,
    started_at      timestamptz NOT NULL DEFAULT now(),
    ended_at        timestamptz NULL,
    error           text        NULL
);

CREATE INDEX transcode_sessions_state_idx ON transcode_sessions (state) WHERE state = 'running';
CREATE INDEX transcode_sessions_user_idx ON transcode_sessions (user_id, started_at DESC);
