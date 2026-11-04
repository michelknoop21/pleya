-- 0030 indexen op de twee kolommen waarop auth_refresh_tokens gevonden wordt.
--
-- Eigenaar: internal/auth. replaced_by is een foreign key naar de eigen tabel met ON
-- DELETE SET NULL, dus Postgres zoekt per verwijderde rij wie ernaar wijst, en zonder
-- index is dat de hele tabel: bij een miljoen rijen 480 ms per verwijderde rij, gemeten
-- op een lokale container. Het afmelden van een sessie en het vervangen van de kop
-- zochten net zo.
--
-- replaced_by is partieel: een kop heeft geen opvolger, en NULL wordt hier nooit gezocht.
-- Gewoon CREATE INDEX, want de runner draait elke migratie in een transactie en daar kan
-- CONCURRENTLY niet. Het schrijfslot duurt zolang de index bouwt; de server luistert dan
-- nog niet.
--
-- Schema-effect: alleen deze twee indexen, zonder een rij te raken. Ze droppen is geen
-- downgrade: schema_migrations blijft op 30 en een oudere binary weigert dan nog steeds
-- te starten (ErrDatabaseNewer in internal/migrate/migrate.go). Terug naar een oudere
-- versie loopt via de bestaande back-up- en restoreroute, met verlies van wat er na het
-- back-upmoment geschreven is.

CREATE INDEX auth_refresh_tokens_session_id_idx ON auth_refresh_tokens (session_id);
CREATE INDEX auth_refresh_tokens_replaced_by_idx ON auth_refresh_tokens (replaced_by) WHERE replaced_by IS NOT NULL;
