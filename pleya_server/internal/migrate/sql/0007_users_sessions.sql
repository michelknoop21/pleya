-- 0007 PS-9: gebruikers, sessies, bibliotheekrechten.
--
-- Volgt DEC-098 (rollen en rechten), DEC-102 (sessie- en tokenketen) en
-- DEC-104 (migratie van bestaande refreshketens). Specificatie 6.5 zei dat een
-- users- en een sessions-tabel PS-9 zijn; dit is die migratie.
--
-- Eén bestand, één transactie, zoals elke migratie hier. De volgorde hieronder
-- ligt vast: latere onderdelen steunen op eerdere (de owner moet in users
-- staan voordat watch_states.subject naar hem kan verwijzen, en de
-- legacy-sessies hebben diezelfde owner-rij nodig).

-- 1. Gebruikers. Precies één owner, afgedwongen met een partiële unieke index
-- en niet met applicatiecode: twee owners maakt de vraag "wie degradeert wie"
-- onbeantwoordbaar (DEC-098).
CREATE TABLE users (
    id             uuid        PRIMARY KEY,
    username       text        NOT NULL UNIQUE,
    password_hash  text        NOT NULL,
    role           text        NOT NULL CHECK (role IN ('owner', 'admin', 'member', 'restricted')),
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX users_single_owner_idx ON users ((role)) WHERE role = 'owner';

COMMENT ON TABLE users IS
    'Vier rollen (DEC-098): owner precies een, admin/member/restricted nul of meer.';

-- 2. Sessies. Een toestel, niet een gebruiker (DEC-102): sid loopt door de
-- volledige tokenketen, zodat intrekking van sessie A niet elk toestel van
-- dezelfde gebruiker uitlogt.
CREATE TABLE sessions (
    id            uuid        PRIMARY KEY,
    user_id       uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    device_id     text        NULL,
    device_name   text        NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    last_seen_at  timestamptz NOT NULL DEFAULT now(),
    revoked_at    timestamptz NULL
);

CREATE INDEX sessions_user_id_idx ON sessions (user_id);

COMMENT ON TABLE sessions IS
    'device_id is PreferenceDeviceId van de client, NULL zonder de capability. device_name draagt dan een vaste plaatshouder.';

-- 3. Bibliotheekrechten, als geordende ladder in een kolom en niet als drie
-- booleans (DEC-098): view < download < manage, per constructie in plaats van
-- als afspraak die elders afgedwongen moet worden. owner en admin krijgen hier
-- geen rijen; hun toegang volgt uit de rol.
CREATE TABLE library_permissions (
    user_id     uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    library_id  uuid NOT NULL REFERENCES libraries (id) ON DELETE CASCADE,
    permission  text NOT NULL CHECK (permission IN ('view', 'download', 'manage')),
    PRIMARY KEY (user_id, library_id)
);

-- restricted mag nooit manage krijgen. Een gewone CHECK ziet alleen de eigen
-- rij en kan role dus niet raadplegen; dat kan alleen met een trigger.
CREATE FUNCTION library_permissions_restricted_no_manage() RETURNS trigger AS $$
BEGIN
    IF NEW.permission = 'manage' AND EXISTS (
        SELECT 1 FROM users WHERE id = NEW.user_id AND role = 'restricted'
    ) THEN
        RAISE EXCEPTION 'restricted mag geen manage krijgen (DEC-098)'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER library_permissions_restricted_no_manage_trg
    BEFORE INSERT OR UPDATE ON library_permissions
    FOR EACH ROW EXECUTE FUNCTION library_permissions_restricted_no_manage();

-- 4. De bestaande owner overzetten. WHERE username IS NOT NULL maakt dit
-- correct voor zowel de live NAS (voltooide setup) als een vers systeem (geen
-- rij; dan blijft /auth/setup het eerste-gebruikerpad, nu ook naar users).
INSERT INTO users (id, username, password_hash, role, created_at, updated_at)
SELECT gen_random_uuid(), username, password_hash, 'owner', created_at, updated_at
FROM auth_owner
WHERE username IS NOT NULL;

-- 5. watch_states.subject en stream_sessions.subject van text naar uuid, met
-- een FK. Er heeft nooit een andere waarde dan 'owner' bestaan; een controle
-- die iets anders vindt laat de migratie falen in plaats van data te
-- verzinnen.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM watch_states WHERE subject <> 'owner') THEN
        RAISE EXCEPTION 'watch_states.subject bevat een andere waarde dan ''owner''; migratie 0007 stopt';
    END IF;
    IF EXISTS (SELECT 1 FROM stream_sessions WHERE subject <> 'owner') THEN
        RAISE EXCEPTION 'stream_sessions.subject bevat een andere waarde dan ''owner''; migratie 0007 stopt';
    END IF;
END $$;

UPDATE watch_states SET subject = (SELECT id::text FROM users WHERE role = 'owner') WHERE subject = 'owner';
ALTER TABLE watch_states ALTER COLUMN subject TYPE uuid USING subject::uuid;
ALTER TABLE watch_states
    ADD CONSTRAINT watch_states_subject_fkey FOREIGN KEY (subject) REFERENCES users (id) ON DELETE CASCADE;

UPDATE stream_sessions SET subject = (SELECT id::text FROM users WHERE role = 'owner') WHERE subject = 'owner';
ALTER TABLE stream_sessions ALTER COLUMN subject TYPE uuid USING subject::uuid;
ALTER TABLE stream_sessions
    ADD CONSTRAINT stream_sessions_subject_fkey FOREIGN KEY (subject) REFERENCES users (id) ON DELETE CASCADE;

-- stream_sessions.session_id: additief, zodat intrekking van een sessie ook de
-- browserstreamsessies meeneemt (DEC-102). Nullable: een bestaande rij (op de
-- NAS in de praktijk altijd al verlopen) droeg nooit een sessie, en die
-- geschiedenis wordt niet verzonnen.
ALTER TABLE stream_sessions ADD COLUMN session_id uuid NULL REFERENCES sessions (id) ON DELETE CASCADE;

-- 6. Legacy-sessies voor bestaande actieve refreshketens (DEC-104). Een sessie
-- per keten en niet een gedeelde: twee oude toestellen delen dan geen
-- revoke-domein, en hergebruik van de ene raakt de andere niet. Ingetrokken en
-- verlopen rijen houden session_id NULL; dat is geschiedenis en hoeft geen
-- sessie.
ALTER TABLE auth_refresh_tokens ADD COLUMN session_id uuid NULL REFERENCES sessions (id) ON DELETE CASCADE;

WITH legacy AS (
    SELECT token_hash, gen_random_uuid() AS session_id, issued_at
    FROM auth_refresh_tokens
    WHERE revoked_at IS NULL AND expires_at > now()
),
new_sessions AS (
    INSERT INTO sessions (id, user_id, device_id, device_name, created_at, last_seen_at)
    SELECT legacy.session_id, (SELECT id FROM users WHERE role = 'owner'), NULL, 'Legacy device',
           legacy.issued_at, legacy.issued_at
    FROM legacy
    RETURNING id
)
UPDATE auth_refresh_tokens
SET session_id = legacy.session_id
FROM legacy
WHERE auth_refresh_tokens.token_hash = legacy.token_hash
  AND legacy.session_id IN (SELECT id FROM new_sessions);

-- 7. auth_owner blijft staan en wordt niet gedropt. Migraties gaan alleen
-- vooruit; verwijderen kan in een latere migratie nadat de overzet op de NAS
-- bevestigd is.
