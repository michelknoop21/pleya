-- 0001 bootstrap: serveridentiteit en de bootstrap-auth-state.
--
-- Specificatie 6.5 somt uitputtend op welke persistente auth-state een server
-- vóór PS-9 mag hebben: één credential-record, een ondertekensleutel (op schijf,
-- niet hier), per refreshtoken een identificatie plus vervalmoment en
-- ingetrokken-vlag, en de setupcode plus de vlag of setup gedaan is.
--
-- Er staat hier dus geen users-tabel en geen sessions-tabel. Die dragen rollen,
-- rechten en apparaatbeheer, en dat is PS-9.

CREATE TABLE server_instance (
    id          smallint    PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    server_id   uuid        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE server_instance IS
    'Singleton. Draagt server.id uit GET /info; moet een herstart overleven omdat de client er opgeslagen verbindingen aan herkent.';

-- Eén rij, afgedwongen door de primaire sleutel. Dat is geen stijlkeuze: het
-- maakt "meer dan één identiteit" structureel onmogelijk zolang PS-9 er niet is.
CREATE TABLE auth_owner (
    id                     smallint    PRIMARY KEY DEFAULT 1 CHECK (id = 1),

    -- De setupcode staat niet leesbaar opgeslagen; de server hoeft hem alleen te
    -- vergelijken. Hij is kortlevend en vervalt bij de eerste geslaagde
    -- inwisseling (specificatie 6.5, eigenschap 1).
    setup_code_hash        bytea       NULL,
    setup_code_expires_at  timestamptz NULL,
    setup_completed_at     timestamptz NULL,

    -- Argon2id in PHC-vorm: de gebruikte parameters staan in de hash zelf, dus
    -- verifiëren leunt nergens op de configuratie en zwaarder hashen vraagt geen
    -- schemawijziging (specificatie 6.5, eigenschap 3).
    username               text        NULL,
    password_hash          text        NULL,

    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT auth_owner_credential_complete CHECK (
        (username IS NULL) = (password_hash IS NULL)
    ),
    CONSTRAINT auth_owner_setup_implies_credential CHECK (
        setup_completed_at IS NULL OR username IS NOT NULL
    )
);

COMMENT ON TABLE auth_owner IS
    'Singleton met de bootstrap-eigenaar. Geen rol, geen rechten, geen weergavenaam: dit is geen users-tabel.';

-- Een refreshtoken is een ondoorzichtig geheim dat de server niet bewaart. Wat
-- hier staat is de SHA-256 ervan: een identificatie die niet naar het token
-- terug te rekenen is (specificatie 6.5, eigenschap 2). Rotatie met
-- hergebruikdetectie is alleen iets waard als een databasedump geen bruikbaar
-- token oplevert.
CREATE TABLE auth_refresh_tokens (
    token_hash  bytea       PRIMARY KEY,
    issued_at   timestamptz NOT NULL DEFAULT now(),
    expires_at  timestamptz NOT NULL,
    revoked_at  timestamptz NULL
);

COMMENT ON TABLE auth_refresh_tokens IS
    'Geen apparaatnaam, geen IP, geen user agent en geen gebruikersverwijzing. Apparaatbeheer is PS-9.';

CREATE INDEX auth_refresh_tokens_expires_at_idx ON auth_refresh_tokens (expires_at);
