-- 0028 een refreshtoken dat de server verving voordat iemand het aanbood.
--
-- Eigenaar: internal/auth. Twee tabbladen verversen tegelijk met hetzelfde token.
-- Het eerste krijgt A, het tweede is een herhaling binnen het respijt: A gaat eruit
-- en B komt ervoor in de plaats. Komen de antwoorden in omgekeerde volgorde aan, dan
-- eindigt de browser op A, en dat token is ingetrokken zonder ooit gebruikt te zijn.
-- Bood de browser het een kwartier later aan, dan telde dat als hergebruik en ging de
-- hele sessie eruit, terwijl niemand iets twee keer had aangeboden.
--
-- Deze kolom maakt dat onderscheid zichtbaar: gezet op het moment van vervangen, en
-- weer leeg zodra het token toch wordt aangeboden. replaced_by kan dat niet dragen,
-- want NULL staat daar ook bij een rij van vóór 0006 en bij elke ketenintrekking.
--
-- Geen backfill: een rij van vóór deze migratie blijft zich gedragen als vroeger.
-- Terugdraaien: kolom droppen, de oude uitkomst (sessie ingetrokken) komt terug.

ALTER TABLE auth_refresh_tokens ADD COLUMN superseded_at timestamptz NULL;

COMMENT ON COLUMN auth_refresh_tokens.superseded_at IS
    'Vervangen door een herhaling voordat het ooit is aangeboden. Leeg na de eerste aanbieding.';
