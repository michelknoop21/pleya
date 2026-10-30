-- 0024 het toestel achter een download (S23.4, DEC-XXX).
--
-- Eigenaar: internal/downloads. Een download krijgt dezelfde verwijzing naar de
-- inlogsessie als play_history (0020), en de naam komt bij het lezen uit
-- sessions: er is één plek voor de toestelnaam, en die volgt een hernoemd
-- toestel. ON DELETE SET NULL omdat een download de sessie die hem aanvroeg
-- mag overleven.
--
-- Geen backfill: wie een bestaande download aanvroeg is nergens vastgelegd. Die
-- rijen dragen NULL en de client toont zijn terugval. Terugdraaien: kolom
-- droppen, device_name verdwijnt dan uit Download zonder dat een client breekt.

ALTER TABLE downloads
    ADD COLUMN auth_session_id uuid NULL REFERENCES sessions (id) ON DELETE SET NULL;
