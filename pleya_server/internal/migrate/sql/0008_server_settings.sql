-- 0008 S1: beheerbare serverinstellingen, plus de kolommen en de tabel die S1.5
-- nodig heeft.
--
-- Twee onderdelen in één bestand, precies zoals J.6 ze opschrijft (0008 en
-- 0008b, "in hetzelfde bestand als 0008"). Migraties gaan alleen vooruit en de
-- nummers liggen in dat plan vast: 0009 is `libraries` beheerbaar en hoort bij
-- S2. De tokenkolommen en de audittabel hier weglaten zou S1.5 dwingen een
-- nummer te lenen dat aan een latere slice toebehoort, en dat is een duurdere
-- afwijking dan schema dat een commit vroeger klaarstaat dan zijn endpoint.
-- Wat er met deze commit meekomt is `GET`/`PATCH /settings`; de API-tokens en
-- het auditbereik komen met S1.5.
--
-- Eén bestand, één transactie, zoals elke migratie hier.

-- 1. Instellingen die een beheerder mag wijzigen (J.6, K rij 14).
--
-- Geen backfill en geen rij per default. Een ontbrekende sleutel betekent "neem
-- de omgeving", en daarmee is de `source` in het antwoord af te lezen aan het
-- bestaan van de rij. Zou elke sleutel bij de migratie een rij krijgen, dan
-- stond de default op twee plekken tegelijk en zou een gewijzigde default in de
-- binary een bestaande installatie niet meer bereiken.
--
-- `value` is jsonb en niet text: het type hoort bij de sleutel (een duur, een
-- getal, een naam) en jsonb bewaart dat onderscheid in plaats van het aan de
-- lezer over te laten.
CREATE TABLE server_settings (
    key        text        PRIMARY KEY,
    value      jsonb       NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid        NULL REFERENCES users (id) ON DELETE SET NULL
);

COMMENT ON TABLE server_settings IS
    'Beheerbare serverinstellingen (J.6). Een ontbrekende sleutel betekent: neem de omgeving.';

COMMENT ON COLUMN server_settings.updated_by IS
    'De beheerder die de waarde zette. ON DELETE SET NULL: een verwijderde gebruiker mag de instelling niet meenemen.';

-- 2. Sessies dragen straks ook API-tokens (J.6 0008b, RB-20).
--
-- `kind` krijgt een default zodat bestaande rijen geldig blijven zonder dat de
-- migratie ze allemaal hoeft aan te raken. De backfill eronder herkent de
-- sessies die 0007 zelf heeft aangemaakt voor de refreshketens die er al waren:
-- die hebben geen `device_id` en de vaste naam uit die migratie.
--
-- `token_hash` is uniek en nullable: een toestelsessie heeft er geen, en twee
-- API-tokens met dezelfde hash zou betekenen dat intrekken van het ene het
-- andere meeneemt.
ALTER TABLE sessions
    ADD COLUMN kind       text        NOT NULL DEFAULT 'device' CHECK (kind IN ('device', 'api', 'legacy')),
    ADD COLUMN scope      text        NULL,
    ADD COLUMN token_hash bytea       NULL UNIQUE,
    ADD COLUMN expires_at timestamptz NULL;

UPDATE sessions
SET kind = 'legacy'
WHERE device_id IS NULL AND device_name = 'Legacy device';

COMMENT ON COLUMN sessions.kind IS
    'device (een toestel), api (een API-token, S1.5) of legacy (een keten die 0007 overnam).';

-- 3. Audit over beherende handelingen (J.6 0008b, VRAGENLIJST 23).
--
-- `user_id` en `session_id` zijn nullable met ON DELETE SET NULL: een regel over
-- wat er gebeurd is mag niet verdwijnen omdat de gebruiker verdwijnt. De index
-- op `(at DESC)` bedient de enige leesvorm die het endpoint kent: de laatste N.
CREATE TABLE admin_audit (
    id         uuid        PRIMARY KEY,
    at         timestamptz NOT NULL DEFAULT now(),
    user_id    uuid        NULL REFERENCES users (id) ON DELETE SET NULL,
    session_id uuid        NULL REFERENCES sessions (id) ON DELETE SET NULL,
    source     text        NOT NULL CHECK (source IN ('http', 'mcp')),
    operation  text        NOT NULL,
    target     text        NULL,
    outcome    text        NOT NULL CHECK (outcome IN ('ok', 'denied', 'failed')),
    detail     jsonb       NULL
);

CREATE INDEX admin_audit_at_idx ON admin_audit (at DESC);

COMMENT ON TABLE admin_audit IS
    'Beherende handelingen, 90 dagen bewaard door housekeeping (J.6 0008b).';
