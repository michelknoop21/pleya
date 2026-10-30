-- 0024 wie zijn kijkactiviteit met het huishouden deelt (DEC-XXX, activiteit van
-- het huishouden, roadmapregel A-25).
--
-- Eigenaar: internal/personal. GET /items/{id}/activity leest play_history over
-- gebruikers heen, en deze kolom is de opt-out daarop: false haalt de gebruiker
-- uit het antwoord aan anderen en laat zijn eigen regel staan. Standaard aan,
-- dus bestaande rijen, inclusief de backfill uit 0020, zijn na deze migratie
-- zichtbaar voor het huishouden. Dat is het besluit, geen bijwerking.
--
-- 0020 belooft in zijn kop dat niemand anders de geschiedenis ziet. Die belofte
-- geldt sinds dit besluit niet meer voor play_history. Het bestand zelf blijft
-- staan zoals het is: een toegepaste migratie wordt nooit bewerkt, de checksum
-- houdt de server anders tegen.
--
-- Terugdraaien: kolom droppen, capabilities.item_activity gaat uit.

ALTER TABLE users ADD COLUMN share_activity boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN users.share_activity IS
    'Opt-out op GET /items/{id}/activity: false verbergt deze gebruiker voor anderen, niet voor zichzelf.';
