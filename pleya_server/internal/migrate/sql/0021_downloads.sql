-- 0021 downloads naar de app (S23, PS-10).
--
-- Eigenaar: internal/downloads. Een download is de afspraak "deze gebruiker haalt
-- deze versie op voor offline kijken"; de bytes blijven in het mediabestand. De
-- rij draagt wat de client nodig heeft om dat bestand te controleren en te
-- hervatten: de SHA-256 over het hele bestand, de grootte en de wijzigingstijd
-- waarvoor die hash gold. Hash en grootte staan op de rij en niet op media_files,
-- omdat het hashen duur is (minuten op een NAS-schijf) en alleen zin heeft voor
-- een bestand dat ook echt gedownload wordt.
--
-- status loopt preparing -> ready of failed. Alleen een ready-rij levert bytes.
-- Een bestand dat na het hashen van grootte of tijd verandert maakt de rij
-- ongeldig (409 library.download_changed): de client begint dan opnieuw met een nieuwe
-- download in plaats van een half oud, half nieuw bestand te krijgen.
--
-- Hangt aan de gebruiker en aan de versie met ON DELETE CASCADE. Terugdraaien:
-- tabel droppen en capabilities.downloads uitzetten.

CREATE TABLE downloads (
    id          uuid        PRIMARY KEY,
    user_id     uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    item_id     uuid        NOT NULL REFERENCES media_items (id) ON DELETE CASCADE,
    version_id  uuid        NOT NULL REFERENCES media_versions (id) ON DELETE CASCADE,
    status      text        NOT NULL DEFAULT 'preparing' CHECK (status IN ('preparing', 'ready', 'failed')),
    size_bytes  bigint      NULL CHECK (size_bytes IS NULL OR size_bytes >= 0),
    mtime_ns    bigint      NULL,
    sha256      text        NULL CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX downloads_user_idx ON downloads (user_id, created_at DESC, id);
CREATE INDEX downloads_version_ready_idx ON downloads (version_id) WHERE status = 'ready';
