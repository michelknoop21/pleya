-- 0029 revisie op de inhoud van een lijst (S19, DEC-XXX over herordenen).
--
-- Eigenaar: internal/catalog. Herordenen vervangt de hele lijst met PUT, dus wie een
-- oude lijst terugstuurt draait uit wat een ander tabblad of toestel intussen deed.
-- updated_at is daar te grof voor: op de lijn staat hij in hele seconden, en hij
-- loopt ook mee met een nieuwe titel.
--
-- revision telt elke schrijfactie op de rijen van de lijst. De kolom bestaat alleen om
-- op te vergelijken, de waarde zelf zegt niets. Bestaande lijsten beginnen op 1.
--
-- Terugdraaien: kolommen droppen. PUT zonder base_revision werkt daarna als vanouds.

ALTER TABLE collections ADD COLUMN revision bigint NOT NULL DEFAULT 1;
ALTER TABLE playlists   ADD COLUMN revision bigint NOT NULL DEFAULT 1;

COMMENT ON COLUMN collections.revision IS 'Loopt op bij elke schrijfactie op collection_items.';
COMMENT ON COLUMN playlists.revision IS 'Loopt op bij elke schrijfactie op playlist_items.';
