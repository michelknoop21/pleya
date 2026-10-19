-- 0015: cast en crew op het item (venster 3, pakket B4).
--
-- jsonb en geen aparte tabel: een persoon is hier een weergavenaam met een rol,
-- zonder eigen identiteit of pagina. Komt er ooit een personenpagina (zoeken op
-- acteur), dan is dat een eigen tabel in een eigen migratie; de lijst hier is
-- dan de bron om uit te vullen.
ALTER TABLE media_items ADD COLUMN people jsonb NULL;

-- Een rondenummer op de kandidaat. Een nieuwe versie van de ronde (een extra
-- bron, een betere regel) verhoogt het nummer in de code, en elk item met een
-- lager nummer komt dan één keer opnieuw aan de beurt, ook een eerder
-- 'matched' of 'ambiguous' item. Bestaande rijen blijven op 1.
ALTER TABLE metadata_candidates ADD COLUMN pass integer NOT NULL DEFAULT 1;
