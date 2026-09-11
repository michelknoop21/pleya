-- 0010 D1: het canonieke loudnessbewijs per audiostroom.
--
-- Volgt `docs/pleya-server-loudness-measurement-proposal.md` (D0, goedgekeurd) en het canonieke
-- bewijsmodel uit het implementatieplan, hetzelfde objectvorm als de client's `LoudnessEvidence`
-- (`lib/media/loudness_evidence.dart`) en straks Go's `loudness.Evidence`. Eén rij is één meting of
-- één vertaalde tag, voor één stream, op één decodebasis, met één methode: verschillende methodes op
-- dezelfde stream zijn verschillende rijen, geen versies van elkaar.
--
-- FK gaat naar media_files en nooit naar media_streams: een herscan vervangt media_streams-rijen met
-- nieuwe id's, terwijl een bestand zijn identiteit en zijn generation-teller behoudt. stream_index is
-- daarom de identiteit hier, niet een verwijzing naar een rij die een volgende scan kan vervangen.
CREATE TABLE stream_loudness (
    file_id       uuid    NOT NULL REFERENCES media_files (id) ON DELETE CASCADE,
    stream_index  integer NOT NULL,
    -- Wire-veld "basis": de decodeconfiguratie waaronder gemeten is, bijvoorbeeld
    -- "pcm-native-tl31-drc1". Een meting op de ene basis zegt niets over een andere, dus de basis
    -- hoort in de sleutel en niet in een kolom ernaast.
    basis_key     text    NOT NULL,
    -- "ffmpeg-loudnorm-1", "tag-opus-r128-1", enzovoort. Twee methodes op dezelfde stream en basis
    -- zijn twee rijen: de tag-vertaling en de eigen meting bestaan naast elkaar, en store.go (D2)
    -- verwerpt de tag-rij pas als hij inhoudelijk van de metingsrij afwijkt.
    method        text    NOT NULL,
    method_version integer NOT NULL,

    -- server_scan (eigen ffmpeg-pass) of opus_r128/replaygain (vertaalde tag). realtime_estimator en
    -- unknown staan bewust niet in deze lijst: het bewijsmodel zegt met zoveel woorden dat een
    -- realtime schatting nooit opgeslagen bewijs is, alleen runtime-status, en unknown is de
    -- client-only fallback voor een onherkende wire-waarde. Een rij die hier niet in past, past hier
    -- niet in de tabel.
    source        text NOT NULL CHECK (source IN ('server_scan', 'opus_r128', 'replaygain')),

    -- Geen 'pending': de jobtabel (0003_work.sql, kind analyze_loudness, D3) is de wachtrij. Een rij
    -- in deze tabel bestaat pas als er een uitkomst is, goed of slecht.
    state         text NOT NULL CHECK (state IN ('ready', 'failed_permanent', 'rejected')),

    -- Momentopname van media_files.generation ten tijde van de meting, geen live verwijzing. Geldig
    -- is: deze waarde gelijk aan de huidige media_files.generation. Er is geen invalidatiejob; een
    -- verouderde rij wordt gewoon niet meer gevonden zodra de opzoekquery op gelijkheid filtert, en
    -- store.go's ON CONFLICT (D2) laat een oudere generation nooit een nieuwere overschrijven.
    generation    bigint NOT NULL,

    integrated_lufs double precision NULL,
    true_peak_dbtp  double precision NULL,
    lra_lu          double precision NULL,
    threshold_lufs  double precision NULL,
    -- Alleen gevuld voor tag-bronnen die een gain en geen absolute meting geven (Opus R128), samen
    -- met de referentie waartegen die gain is uitgedrukt (Opus: -23 LUFS). Voor server_scan blijven
    -- beide NULL: de meting staat al absoluut in integrated_lufs.
    gain_db         double precision NULL,
    reference_lufs  double precision NULL,

    coverage_complete boolean NOT NULL,

    -- Basisbewijs: codec en kanaallayout zoals ze golden op het moment van meten, zodat een latere
    -- vraag "welke stream was dit precies" niet terug hoeft naar media_streams, wiens rij inmiddels
    -- vervangen kan zijn. codec is altijd bekend: de decoder-args per basis (basis.go, D2) hangen er
    -- al vanaf vóór er gemeten wordt. channel_layout is nullable, gelijk aan media_streams, want niet
    -- elke probe geeft hem mee.
    codec           text NOT NULL,
    channel_layout  text NULL,

    -- Gesanitiseerd: nooit een pad of ruwe stderr, dat kan filesysteeminformatie lekken naar een
    -- API-client. Alleen ingevuld waar de rij ook echt niet ready is.
    reject_reason   text NULL CHECK (state = 'ready' OR reject_reason IS NOT NULL),

    measured_at     timestamptz NOT NULL DEFAULT now(),

    PRIMARY KEY (file_id, stream_index, basis_key, method),
    CONSTRAINT stream_loudness_ready_has_no_reason CHECK (state != 'ready' OR reject_reason IS NULL)
);

COMMENT ON TABLE stream_loudness IS
    'Eén rij per (bestand, stream, decodebasis, methode): een meting of een vertaalde tag, nooit een realtime schatting. D1 uit pleya-server-loudness-measurement-proposal.md.';

COMMENT ON COLUMN stream_loudness.generation IS
    'Momentopname van media_files.generation bij het meten. Geldig = gelijk aan de huidige waarde; geen invalidatiejob.';

COMMENT ON COLUMN stream_loudness.reject_reason IS
    'Gesanitiseerd: nooit een bestandspad of ruwe procesfout. NULL bij state=ready, verplicht ingevuld bij elke andere state.';
