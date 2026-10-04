-- 0009 S2.1: libraries schrijfbaar maken vraagt eerst te weten wie de eigenaar is.
--
-- `managed` zegt of een rij door de omgeving (`config`, `PLEYA_SERVER_LIBRARIES`)
-- of door een beheerder via de API (`db`, S2.2) wordt onderhouden. De default is
-- `config` en niet `db`: elke bestaande bibliotheek komt vandaag uitsluitend uit
-- de omgeving, en een rij die per ongeluk zonder expliciete waarde wordt
-- ingevoegd hoort bij het pad dat er al is en niet bij het pad dat S2.2 toevoegt.
-- Zonder dit onderscheid zou de periodieke config-sync (`SyncLibraries`) een via
-- de API bewerkte bibliotheek bij de volgende herstart overschrijven met wat er
-- op dat moment in de omgeving staat; S2.5 legt vast hoe die sync een
-- `db`-beheerde rij met rust laat.
--
-- De scaninstellingen staan op de bibliotheek en niet in `server_settings`: ze
-- horen bij één bibliotheek, niet bij de server. `scan_interval_seconds` is
-- nullable en betekent bij NULL "gebruik de globale `PLEYA_SERVER_SCAN_INTERVAL`",
-- zodat een bestaande installatie die deze kolom nooit zet precies hetzelfde
-- gedrag houdt als vandaag. `scan_on_start` krijgt default `true`, want dat is
-- het gedrag dat elke bibliotheek nu al heeft: `enqueueScans` draait vandaag
-- onvoorwaardelijk bij het opstarten.
ALTER TABLE libraries
    ADD COLUMN managed               text    NOT NULL DEFAULT 'config' CHECK (managed IN ('config', 'db')),
    ADD COLUMN scan_interval_seconds integer NULL CHECK (scan_interval_seconds IS NULL OR scan_interval_seconds > 0),
    ADD COLUMN scan_on_start         boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN libraries.managed IS
    'config: overschreven door PLEYA_SERVER_LIBRARIES bij elke sync. db: alleen door de API (S2.2).';

COMMENT ON COLUMN libraries.scan_interval_seconds IS
    'NULL: gebruik de globale scan-interval van de server. Anders overschrijft deze waarde die voor deze bibliotheek.';

COMMENT ON COLUMN libraries.scan_on_start IS
    'Of deze bibliotheek meedoet aan de scanronde die de server bij het opstarten inplant.';
