-- 0027 wanneer een server zonder providersleutel een item voor het laatst naliep.
--
-- Eigenaar: internal/catalog en internal/metadata. Zonder TMDB-sleutel draait de
-- metadataronde alleen op lokale .nfo-bestanden en legde ze niets vast: elk item
-- bleef aan de beurt, elke ronde opnieuw, na elke scan en elke zes uur.
--
-- Een eigen kolom en geen rij in metadata_candidates. Die tabel heeft één rij per
-- item en is van de provider: een rij met provider 'nfo' zou een eerdere
-- TMDB-uitkomst overschrijven zodra de sleutel even weg is, ook een afwijzing van
-- een beheerder, en elk item zou als 'unmatched' in zijn werklijst staan.
--
-- NULL betekent nog nooit nagelopen. Geen backfill: de eerste ronde loopt alles
-- één keer na, en schrijft niets zolang de .nfo niets nieuws zegt.
--
-- Terugdraaien: kolom droppen. De ronde wordt dan weer eeuwig, niet fout.

ALTER TABLE media_items ADD COLUMN sidecar_checked_at timestamptz NULL;

COMMENT ON COLUMN media_items.sidecar_checked_at IS
    'Laatste ronde zonder provider die dit item naliep. Alleen betekenisvol zonder providersleutel.';
