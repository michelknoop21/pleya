-- 0024 wie zijn kijkactiviteit met het huishouden deelt (DEC-169, activiteit van
-- het huishouden, roadmapregel A-25).
--
-- Eigenaar: internal/personal. GET /items/{id}/activity leest play_history over
-- gebruikers heen, en deze kolom is de eigen keuze daarop. false haalt de
-- gebruiker uit het antwoord aan anderen, true zet hem erin, en zijn eigen regel
-- blijft altijd staan.
--
-- NULL betekent dat de gebruiker niets gekozen heeft, en dan beslist de rol:
-- restricted deelt niet (opt-in), elke andere rol wel (opt-out). Geen vaste
-- default, want die kent de rol niet, en een nullable kolom maakt elke bestaande
-- rij meteen correct zonder backfill. Bestaande geschiedenis van gewone
-- gebruikers, inclusief de backfill uit 0020, is na deze migratie dus zichtbaar
-- voor het huishouden. Dat is het besluit, geen bijwerking.
--
-- 0020 belooft in zijn kop dat niemand anders de geschiedenis ziet. Die belofte
-- geldt sinds dit besluit niet meer voor play_history. Het bestand zelf blijft
-- staan zoals het is: een toegepaste migratie wordt nooit bewerkt, de checksum
-- houdt de server anders tegen.
--
-- Terugdraaien: kolom droppen, capabilities.item_activity gaat uit.

ALTER TABLE users ADD COLUMN share_activity boolean NULL;

COMMENT ON COLUMN users.share_activity IS
    'Eigen keuze op GET /items/{id}/activity. NULL volgt de rol: restricted deelt niet, de rest wel.';
