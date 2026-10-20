-- 0017 filters en facetten (S5.1, venster 3 pakket D1).
--
-- pg_trgm voor de zoekopdracht en de titelfilters: ILIKE '%term%' heeft op een
-- paar duizend items geen index nodig, maar een bibliotheek groeit en de
-- kosten van een index zijn klein.
-- Expliciet in public: een extensie hoort bij de database en niet bij het schema
-- waarin de eerste migratie toevallig draait, en de operatorklasse hieronder
-- wordt met haar schema genoemd zodat hij overal te vinden is.
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;

CREATE INDEX media_items_title_trgm_idx ON media_items USING gin (title public.gin_trgm_ops);
CREATE INDEX media_items_sort_title_trgm_idx ON media_items USING gin (sort_title public.gin_trgm_ops);

-- Het moment waarop deze identiteit voor het laatst met voortgang naar dit item
-- keek: de serverontvangst van de laatste geaccepteerde schrijving met een
-- positie boven nul of watched. Een mark_unwatched of restart zet beide terug en
-- laat de waarde dus staan. De sorteerwaarde voor "laatst gekeken".
ALTER TABLE watch_states ADD COLUMN IF NOT EXISTS last_played_at timestamptz NULL;

-- Bestaande kijkgeschiedenis krijgt een waarde uit updated_at: dat is de
-- dichtstbijzijnde waarheid. Zonder deze stap is "laatst gekeken" leeg tot
-- iedereen opnieuw kijkt (afwijking van 8.1 van het contractvoorstel, zie 4.4).
UPDATE watch_states SET last_played_at = updated_at
 WHERE last_played_at IS NULL AND (position_ms > 0 OR watched);

CREATE INDEX IF NOT EXISTS watch_states_subject_last_played_idx
    ON watch_states (subject, last_played_at DESC NULLS LAST, item_id)
    WHERE last_played_at IS NOT NULL;
