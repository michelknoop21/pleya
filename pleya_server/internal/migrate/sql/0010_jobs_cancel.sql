-- 0010 annuleren en de wachtende scanronde: de kolom die het verzoek draagt, en
-- de toestand die een scanronde nu al kan hebben vóórdat de scanner hem claimt.
--
-- `cancel_requested_at` is een spoor en geen staat. De job zelf schrijft
-- `state = 'cancelled'`, deze kolom onderscheidt alleen "een beheerder vroeg
-- erom" van "de server ging uit terwijl hij liep" bij een herstart: Requeue
-- (internal/jobs) sluit een `running` job met deze kolom gezet af naar
-- `cancelled` in plaats van hem terug te zetten naar `pending`.
--
-- Geen wijziging aan `claim()` is hiervoor nodig. Een gestempelde `running`-rij
-- kan zijn stempel nooit meer kwijtraken zonder via Cancel of Requeue naar
-- `cancelled` te gaan, en geen van beide zet hem terug naar `pending` zolang de
-- kolom gezet is.
ALTER TABLE jobs
    ADD COLUMN cancel_requested_at timestamptz NULL;

COMMENT ON COLUMN jobs.cancel_requested_at IS
    'Wanneer een beheerder annulering vroeg. NULL: geen verzoek. Alleen een spoor; de staat zelf staat in state.';

-- `queued` komt vóór `running`: `POST /libraries/{id}/scan` maakt de
-- `scan_runs`-rij aan vóórdat de bijbehorende job ooit geclaimd wordt, want het
-- antwoord van dat endpoint draagt een `Scan`-id dat er al moet zijn. Postgres
-- kent geen ALTER CHECK; de oude constraint moet eerst weg.
ALTER TABLE scan_runs DROP CONSTRAINT scan_runs_state_check;
ALTER TABLE scan_runs
    ADD CONSTRAINT scan_runs_state_check
    CHECK (state IN ('queued', 'running', 'succeeded', 'failed', 'cancelled'));
