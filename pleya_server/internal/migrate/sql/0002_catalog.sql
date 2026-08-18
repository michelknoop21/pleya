-- 0002 catalogus: bibliotheken, identiteit en de bestanden eronder.
--
-- Volgt hoofdstuk 7 van de architectuur. De kernregel daaruit: een item is niet
-- een bestand, en een pad is nooit een identiteit. Een film die in 1080p en in
-- 4K op schijf staat is één item met twee versies, en een versie die over twee
-- bestanden is gesplitst is één versie met twee bestanden.
--
-- Alle ids zijn UUIDv7 en worden door de applicatie gegenereerd. De tijdsprefix
-- maakt ze sorteerbaar op aanmaakmoment, wat de index-locality op grote tabellen
-- beter maakt dan een willekeurige v4, en ze zijn uitdeelbaar zonder rondgang
-- naar de database.

CREATE TABLE libraries (
    id          uuid        PRIMARY KEY,
    -- De slug komt uit de configuratie en is de matchsleutel bij het opstarten.
    -- Een gewijzigde titel of een verplaatste root maakt daardoor geen tweede
    -- bibliotheek, en de ids overleven een herstart.
    slug        text        NOT NULL UNIQUE,
    title       text        NOT NULL,
    kind        text        NOT NULL CHECK (kind IN ('movies', 'shows')),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

-- Een storage location is één geconfigureerde root van een bibliotheek. Het
-- bestandssysteemtype en de inodebetrouwbaarheid staan hier en niet in de
-- scanner: of de goedkope laag uit 7.3 op deze mount op inodes mag bouwen is een
-- eigenschap van de root. Op deze NAS is /volume1 btrfs en /volumeUSB5
-- fuseblk.ntfs, en dat verschil hoort meetbaar te zijn en niet aangenomen.
CREATE TABLE storage_locations (
    id                  uuid        PRIMARY KEY,
    library_id          uuid        NOT NULL REFERENCES libraries (id) ON DELETE CASCADE,
    root_path           text        NOT NULL UNIQUE,
    fs_type             text        NULL,
    inode_trusted       boolean     NOT NULL DEFAULT true,
    inode_trust_source  text        NOT NULL DEFAULT 'fstype_default'
        CHECK (inode_trust_source IN ('fstype_default', 'config_override', 'measured')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    last_seen_at        timestamptz NULL
);

CREATE INDEX storage_locations_library_idx ON storage_locations (library_id);

CREATE TABLE media_items (
    id          uuid        PRIMARY KEY,
    library_id  uuid        NOT NULL REFERENCES libraries (id) ON DELETE CASCADE,
    parent_id   uuid        NULL REFERENCES media_items (id) ON DELETE CASCADE,
    kind        text        NOT NULL CHECK (kind IN ('movie', 'show', 'season', 'episode')),

    -- grouping_key heet bewust niet identity_key. Hoofdstuk 7.2 verbiedt het door
    -- elkaar lopen van detectie en identiteit; deze sleutel doet één ding, en dat
    -- is een NIEUW gevonden bestand aan een bestaand item hangen. Een hernoemd
    -- bestand komt er nooit langs: dat wordt een laag eerder aan zijn inode
    -- herkend en houdt daarmee zijn media_files-rij, zijn versie en zijn item.
    grouping_key text       NOT NULL,

    title        text       NOT NULL,
    sort_title   text       NULL,
    year         integer    NULL,
    item_index   integer    NULL,
    added_at     timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT media_items_parent_kind CHECK (
        (kind = 'movie'   AND parent_id IS NULL) OR
        (kind = 'show'    AND parent_id IS NULL) OR
        (kind = 'season'  AND parent_id IS NOT NULL) OR
        (kind = 'episode' AND parent_id IS NOT NULL)
    )
);

-- NULLS NOT DISTINCT, want anders ontsnapt elke film aan de sleutel: die heeft
-- geen ouder, en Postgres ziet twee NULL-ouders standaard als verschillend.
CREATE UNIQUE INDEX media_items_grouping_key_uidx
    ON media_items (library_id, parent_id, kind, grouping_key) NULLS NOT DISTINCT;

CREATE INDEX media_items_library_kind_title_idx ON media_items (library_id, kind, sort_title, id);
CREATE INDEX media_items_library_added_idx      ON media_items (library_id, added_at DESC, id);
CREATE INDEX media_items_parent_index_idx       ON media_items (parent_id, item_index, id);
-- Zoeken gaat over de genormaliseerde titel. Bij een paar duizend items is een
-- sequentiële scan sneller klaar dan de planner erover doet; een trigram-index
-- komt erbij wanneer een meting daarom vraagt, niet ervoor.
CREATE INDEX media_items_search_idx ON media_items (library_id, kind);

CREATE TABLE media_versions (
    id           uuid        PRIMARY KEY,
    item_id      uuid        NOT NULL REFERENCES media_items (id) ON DELETE CASCADE,
    grouping_key text        NOT NULL,

    -- NOT NULL: een versie ontstaat pas na een geslaagde ffprobe. Een bestand dat
    -- nog niet of niet met succes geanalyseerd is heeft een media_files-rij
    -- zonder versie. Zo is het wire-type totaal en hoeft de HTTP-laag nooit een
    -- half ingevulde versie te verzwijgen.
    container    text        NOT NULL,
    duration_ms  bigint      NOT NULL CHECK (duration_ms >= 0),

    edition      text        NULL,
    bitrate_bps  bigint      NULL,

    -- Per veld een detectionStatus en een source volgens hoofdstuk 7.4. Vorm:
    -- {"duration_ms": {"status": "confirmed", "source": "ffprobe_stream"}}.
    -- Bewust geen enkele confidence-score van hoog tot laag: dan moet de planner
    -- zelf verzinnen wat "middel" betekent voor Dolby Vision tegenover wat het
    -- betekent voor een kanaalindeling, en juist dat verschil doet ertoe.
    detection    jsonb       NOT NULL DEFAULT '{}'::jsonb,

    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),

    UNIQUE (item_id, grouping_key)
);

CREATE INDEX media_versions_item_idx ON media_versions (item_id, id);

-- Elk pad dat de scanner volgt staat hier, met zijn verandersdetectie. De
-- testbibliotheek heeft 2601 videobestanden, 5578 losse .srt en 2923 .jpg; die
-- sidecars hebben exact dezelfde goedkope detectie nodig als de media zelf, dus
-- één tabel houdt de scannerlus uniform over elk pad.
CREATE TABLE media_files (
    id                   uuid        PRIMARY KEY,
    storage_location_id  uuid        NOT NULL REFERENCES storage_locations (id) ON DELETE CASCADE,
    relative_path        text        NOT NULL,
    role                 text        NOT NULL CHECK (role IN ('media', 'subtitle', 'artwork')),

    -- media en subtitle hangen aan een versie, artwork aan een item. Beide zijn
    -- nullable: een net ontdekt bestand is nog nergens aan gehangen, en een
    -- bestand dat niet te ontleden of niet te analyseren is blijft bestaan zodat
    -- het niet elke ronde opnieuw geprobeerd wordt.
    version_id           uuid        NULL REFERENCES media_versions (id) ON DELETE CASCADE,
    item_id              uuid        NULL REFERENCES media_items (id) ON DELETE CASCADE,
    part_index           integer     NOT NULL DEFAULT 0,
    artwork_kind         text        NULL CHECK (artwork_kind IN ('poster', 'backdrop')),

    -- Laag 1 uit 7.3: één stat per bestand. Onveranderd betekent niets te doen.
    size_bytes           bigint      NOT NULL,
    mtime_unix           bigint      NOT NULL,
    inode                bigint      NULL,

    -- Laag 2: hash over de eerste en de laatste megabyte plus de grootte, zoals
    -- hij stond bij de laatste geslaagde analyse. Hoofdstuk 7.2 is hier
    -- onvoorwaardelijk: dit is een optimalisatie en nooit bewijs van gelijkheid.
    -- De signature beslist alleen of er verder gekeken wordt.
    scan_signature       text        NULL,

    -- Sterker bewijs dat twee paden dezelfde bytes dragen, voor relocatie tussen
    -- mounts. Te duur om elke ronde te draaien, dus nullable en alleen berekend
    -- waar hij gevraagd wordt (7.3).
    content_fingerprint  text        NULL,

    -- Loopt op zodra laag 3 het bestand opnieuw analyseert. Hier hangt bewust
    -- geen ETag aan: dat is poort 4 uit docs/pleya-server-gates.md en die staat
    -- open tot PS-4.
    generation           bigint      NOT NULL DEFAULT 1,

    -- De eigen duur van dit bestand, zoals ffprobe hem gaf. Bij een versie van
    -- één bestand is dat dezelfde waarde als op de versie; bij een gestapelde
    -- versie (cd1, cd2) is de duur van de versie de som van de delen, en zonder
    -- dit veld valt die som niet te maken zonder opnieuw te analyseren.
    probe_duration_ms    bigint      NULL,

    probe_attempts       integer     NOT NULL DEFAULT 0,
    last_probe_at        timestamptz NULL,
    last_probe_error     text        NULL,

    first_seen_at        timestamptz NOT NULL DEFAULT now(),
    last_seen_at         timestamptz NOT NULL DEFAULT now(),
    missing_since        timestamptz NULL,

    UNIQUE (storage_location_id, relative_path),

    CONSTRAINT media_files_owner_by_role CHECK (
        (role IN ('media', 'subtitle') AND item_id IS NULL) OR
        (role = 'artwork' AND version_id IS NULL)
    ),
    -- artwork_kind hoort alleen bij artwork, en mag daar leeg zijn zolang de
    -- scanner nog niet weet bij welk item het hoort. Een net ontdekt bestand is
    -- nergens aan gehangen; dat is een tussenstand en geen fout.
    CONSTRAINT media_files_artwork_kind CHECK (
        role = 'artwork' OR artwork_kind IS NULL
    )
);

-- Hernoemdetectie: hetzelfde bestand op een nieuw pad wordt aan zijn inode
-- herkend en houdt zijn id. Dat is precies het scenario waarin Plex vandaag een
-- dubbele entry maakt.
CREATE INDEX media_files_inode_idx ON media_files (storage_location_id, inode)
    WHERE inode IS NOT NULL;

CREATE INDEX media_files_version_idx ON media_files (version_id) WHERE version_id IS NOT NULL;
CREATE INDEX media_files_item_idx    ON media_files (item_id)    WHERE item_id IS NOT NULL;
CREATE INDEX media_files_unattached_idx
    ON media_files (storage_location_id, role) WHERE version_id IS NULL AND item_id IS NULL;

CREATE TABLE media_streams (
    id           uuid        PRIMARY KEY,
    version_id   uuid        NOT NULL REFERENCES media_versions (id) ON DELETE CASCADE,
    -- In welk bestand het spoor zit. Bij een ingebed spoor is dat de mediafile,
    -- bij een extern ondertitelspoor het .srt-bestand ernaast.
    file_id      uuid        NOT NULL REFERENCES media_files (id) ON DELETE CASCADE,
    kind         text        NOT NULL CHECK (kind IN ('video', 'audio', 'subtitle')),
    stream_index integer     NULL,
    ordinal      integer     NOT NULL,

    codec        text        NULL,
    profile      text        NULL,
    width        integer     NULL,
    height       integer     NULL,
    bit_depth    integer     NULL,
    frame_rate   double precision NULL,
    channels     integer     NULL,
    channel_layout text      NULL,
    language     text        NULL,
    title        text        NULL,

    is_default            boolean NOT NULL DEFAULT false,
    is_forced             boolean NOT NULL DEFAULT false,
    is_hearing_impaired   boolean NOT NULL DEFAULT false,
    is_external           boolean NOT NULL DEFAULT false,

    subtitle_format text NULL CHECK (subtitle_format IN ('srt', 'ass', 'ssa', 'vtt', 'pgs', 'dvdsub')),

    -- Rauw zoals ffprobe ze geeft. Er wordt hier bewust geen hdr_format uit
    -- afgeleid: die interpretatie is planner-beleid en dus PS-6. Opslaan wat de
    -- bron zegt hoort bij deze fase, er beleid van maken niet.
    color_transfer  text NULL,
    color_primaries text NULL,
    color_space     text NULL,
    dovi_profile            integer NULL,
    dovi_bl_compatible_id   integer NULL,

    detection    jsonb       NOT NULL DEFAULT '{}'::jsonb,

    created_at   timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT media_streams_external_is_subtitle CHECK (
        NOT is_external OR kind = 'subtitle'
    ),
    CONSTRAINT media_streams_index_by_origin CHECK (
        (is_external AND stream_index IS NULL) OR (NOT is_external AND stream_index IS NOT NULL)
    ),
    CONSTRAINT media_streams_format_by_kind CHECK (
        (kind = 'subtitle') OR subtitle_format IS NULL
    )
);

CREATE INDEX media_streams_version_idx ON media_streams (version_id, kind, ordinal);
CREATE INDEX media_streams_file_idx    ON media_streams (file_id);
