package catalog

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// ItemRef beschrijft het item waar een bestand aan gehangen moet worden.
type ItemRef struct {
	LibraryID   id.ID
	ParentID    *id.ID
	Kind        string
	GroupingKey string
	Title       string
	SortTitle   string
	Year        *int
	Index       *int
}

// ResolveItem zoekt het item op zijn grouping key en maakt het aan als het er
// niet is.
//
// De sleutel doet precies één ding: een nieuw gevonden bestand aan een bestaand
// item hangen. De weergavevelden worden wel bijgewerkt, en dat is geen
// tegenspraak: de sleutel is afgeleid uit de titel, dus een titel die
// wezenlijk verandert levert een andere sleutel op en daarmee een ander item.
// Wat hier langskomt zijn de verschillen die de sleutel al gelijk maakt, zoals
// hoofdletters en leestekens, en dan hoort de nieuwste schrijfwijze te winnen.
//
// added_at blijft staan. Dat is het moment waarop dit item in de bibliotheek
// kwam, en dat verandert niet doordat een bestand hernoemd wordt.
func (s *Store) ResolveItem(ctx context.Context, ref ItemRef) (id.ID, bool, error) {
	var existing id.ID
	var created bool

	err := s.pool.QueryRow(ctx, `
		INSERT INTO media_items (id, library_id, parent_id, kind, grouping_key, title, sort_title, year, item_index)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (library_id, parent_id, kind, grouping_key) DO UPDATE
		SET title = EXCLUDED.title,
		    sort_title = EXCLUDED.sort_title,
		    year = coalesce(EXCLUDED.year, media_items.year),
		    item_index = coalesce(EXCLUDED.item_index, media_items.item_index),
		    updated_at = now()
		RETURNING id, (xmax = 0)`,
		id.New(), ref.LibraryID, ref.ParentID, ref.Kind, ref.GroupingKey,
		ref.Title, nullString(ref.SortTitle), ref.Year, ref.Index).Scan(&existing, &created)
	if err != nil {
		return id.Nil, false, fmt.Errorf("item vastleggen: %w", err)
	}
	return existing, created, nil
}

// ResolveVersion zoekt of maakt de versie en werkt zijn technische velden bij.
func (s *Store) ResolveVersion(ctx context.Context, itemID id.ID, groupingKey string, probed ProbedVersion, edition string) (id.ID, bool, error) {
	detection, err := jsonb(detectionOrEmpty(probed.Detection))
	if err != nil {
		return id.Nil, false, err
	}

	var versionID id.ID
	var created bool
	err = s.pool.QueryRow(ctx, `
		INSERT INTO media_versions (id, item_id, grouping_key, container, duration_ms, edition, bitrate_bps, detection)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (item_id, grouping_key) DO UPDATE
		SET container = EXCLUDED.container,
		    duration_ms = EXCLUDED.duration_ms,
		    edition = EXCLUDED.edition,
		    bitrate_bps = EXCLUDED.bitrate_bps,
		    detection = EXCLUDED.detection,
		    updated_at = now()
		RETURNING id, (xmax = 0)`,
		id.New(), itemID, groupingKey, probed.Container, probed.DurationMs,
		nullString(edition), nullInt64(probed.BitrateBps), detection).Scan(&versionID, &created)
	if err != nil {
		return id.Nil, false, fmt.Errorf("versie vastleggen: %w", err)
	}
	return versionID, created, nil
}

// RecomputeVersionDuration zet de duur van een versie op de som van zijn delen.
//
// Bij één bestand levert dat dezelfde waarde als de analyse. Bij een gestapelde
// versie (cd1 naast cd2) is de som het enige juiste antwoord: het eerste deel
// alleen zou een film van drie uur als anderhalf uur tonen.
func (s *Store) RecomputeVersionDuration(ctx context.Context, versionID id.ID) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE media_versions v
		SET duration_ms = sub.total, updated_at = now()
		FROM (
			SELECT coalesce(sum(probe_duration_ms), 0) AS total
			FROM media_files
			WHERE version_id = $1 AND role = 'media' AND probe_duration_ms IS NOT NULL
		) sub
		WHERE v.id = $1 AND sub.total > 0`, versionID)
	return err
}

// InsertFile legt een nieuw ontdekt bestand vast.
func (s *Store) InsertFile(ctx context.Context, f *File) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO media_files (id, storage_location_id, relative_path, role, size_bytes, mtime_unix, inode, scan_signature)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		f.ID, f.StorageLocationID, f.RelativePath, string(f.Role),
		f.SizeBytes, f.MtimeUnix, f.Inode, nullString(f.Signature))
	if err != nil {
		return fmt.Errorf("bestand %s vastleggen: %w", f.RelativePath, err)
	}
	return nil
}

// MoveFile verplaatst een bestaande rij naar een nieuw pad.
//
// Dit is de kern van criterium 3: hetzelfde bestand op een nieuw pad houdt zijn
// id, en daarmee zijn versie, zijn item en straks zijn kijkstatus. Dat is
// precies het scenario waarin Plex vandaag een dubbele entry maakt.
func (s *Store) MoveFile(ctx context.Context, fileID id.ID, newPath string) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE media_files
		SET relative_path = $2, missing_since = NULL, last_seen_at = now()
		WHERE id = $1`, fileID, newPath)
	if err != nil {
		return fmt.Errorf("bestand verplaatsen naar %s: %w", newPath, err)
	}
	return nil
}

// RecordProbe legt vast wat de analyse van dit bestand opleverde.
func (s *Store) RecordProbe(ctx context.Context, fileID id.ID, size, mtime int64, inode *int64, signature string, durationMs int64, versionID id.ID, partIndex int) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE media_files
		SET size_bytes = $2, mtime_unix = $3, inode = $4, scan_signature = $5,
		    probe_duration_ms = $6, version_id = $7, item_id = NULL, part_index = $8,
		    generation = generation + 1, probe_attempts = 0, last_probe_at = now(),
		    last_probe_error = NULL, missing_since = NULL, last_seen_at = now()
		WHERE id = $1`,
		fileID, size, mtime, inode, nullString(signature), nullInt64(durationMs), versionID, partIndex)
	if err != nil {
		return fmt.Errorf("analyse vastleggen: %w", err)
	}
	return nil
}

// RecordProbeFailure onthoudt dat dit bestand niet te analyseren was, zodat de
// volgende ronde het niet opnieuw probeert alsof er niets gebeurd is.
//
// De koppeling gaat er daarbij af. De nieuwe inhoud wordt vastgelegd, en dan is
// alles wat uit de vórige inhoud kwam onjuist geworden: de versie, de duur en de
// sporen. Blijven ze staan, dan serveert de bibliotheek de metadata van iets dat
// er niet meer ligt, en houdt PruneEmpty de versie in leven omdat de rij nog een
// version_id draagt. 0002_catalog.sql legt bij media_versions al vast dat een
// versie pas na een geslaagde ffprobe ontstaat; loskoppelen is die invariant
// naleven en geen nieuwe regel. Gevolg: een film waarvan het bestand stukgaat
// verdwijnt uit de bibliotheek tot hij weer analyseerbaar is.
func (s *Store) RecordProbeFailure(ctx context.Context, fileID id.ID, size, mtime int64, inode *int64, signature, reason string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, `DELETE FROM media_streams WHERE file_id = $1`, fileID); err != nil {
		return fmt.Errorf("sporen van een mislukte analyse wissen: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		UPDATE media_files
		SET size_bytes = $2, mtime_unix = $3, inode = $4, scan_signature = $5,
		    version_id = NULL, part_index = 0, probe_duration_ms = NULL,
		    generation = generation + 1,
		    probe_attempts = probe_attempts + 1, last_probe_at = now(),
		    last_probe_error = $6, missing_since = NULL, last_seen_at = now()
		WHERE id = $1`, fileID, size, mtime, inode, nullString(signature), truncate(reason, 500)); err != nil {
		return fmt.Errorf("mislukte analyse vastleggen: %w", err)
	}
	return tx.Commit(ctx)
}

// AttachSidecar hangt een ondertitel- of artworkbestand aan zijn eigenaar.
func (s *Store) AttachSidecar(ctx context.Context, fileID id.ID, size, mtime int64, inode *int64, signature string, versionID, itemID *id.ID, artworkKind string) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE media_files
		SET size_bytes = $2, mtime_unix = $3, inode = $4, scan_signature = $5,
		    version_id = $6, item_id = $7, artwork_kind = $8,
		    generation = generation + 1, missing_since = NULL, last_seen_at = now()
		WHERE id = $1`,
		fileID, size, mtime, inode, nullString(signature), versionID, itemID, nullString(artworkKind))
	if err != nil {
		return fmt.Errorf("sidecar koppelen: %w", err)
	}
	return nil
}

// DetachSidecar maakt een sidecar los van de versie of het item waar hij aan
// hing, sporen inbegrepen.
//
// Nodig zodra een sidecar verhuist naar een plek waar geen eigenaar te vinden
// is. De koppeling volgt uit het pad, dus een verplaatsing die niets nieuws
// oplevert hoort de oude koppeling weg te halen en niet te laten staan.
func (s *Store) DetachSidecar(ctx context.Context, fileID id.ID) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, `DELETE FROM media_streams WHERE file_id = $1`, fileID); err != nil {
		return fmt.Errorf("sporen van een losgemaakte sidecar wissen: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		UPDATE media_files
		SET version_id = NULL, item_id = NULL, artwork_kind = NULL,
		    generation = generation + 1
		WHERE id = $1`, fileID); err != nil {
		return fmt.Errorf("sidecar losmaken: %w", err)
	}
	return tx.Commit(ctx)
}

// ReplaceStreams vervangt alle sporen die uit dit bestand komen.
//
// Per bestand en niet per versie: een gestapelde versie krijgt zijn sporen uit
// het eerste deel, en een extern ondertitelbestand draagt zijn eigen spoor. Wie
// per versie zou wissen gooit bij elke sidecar de sporen van de media weg.
func (s *Store) ReplaceStreams(ctx context.Context, versionID, fileID id.ID, streams []ffprobe.Stream, external bool) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, `DELETE FROM media_streams WHERE file_id = $1`, fileID); err != nil {
		return fmt.Errorf("oude sporen wissen: %w", err)
	}

	for _, st := range streams {
		detection, err := jsonb(detectionOrEmpty(st.Detection))
		if err != nil {
			return err
		}

		var streamIndex *int
		if !external {
			idx := st.Index
			streamIndex = &idx
		}

		if _, err := tx.Exec(ctx, `
			INSERT INTO media_streams (
				id, version_id, file_id, kind, stream_index, ordinal,
				codec, profile, width, height, bit_depth, frame_rate,
				channels, channel_layout, language, title,
				is_default, is_forced, is_hearing_impaired, is_external,
				subtitle_format, color_transfer, color_primaries, color_space,
				dovi_profile, dovi_bl_compatible_id, detection)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27)`,
			id.New(), versionID, fileID, st.Kind, streamIndex, st.Ordinal,
			nullString(st.Codec), nullString(st.Profile),
			nullInt(st.Width), nullInt(st.Height), nullInt(st.BitDepth), nullFloat(st.FrameRate),
			nullInt(st.Channels), nullString(st.ChannelLayout),
			nullString(st.Language), nullString(st.Title),
			st.IsDefault, st.IsForced, st.IsHearingImpaired, external,
			nullString(st.SubtitleFormat), nullString(st.ColorTransfer),
			nullString(st.ColorPrimaries), nullString(st.ColorSpace),
			st.DoviProfile, st.DoviBLCompatibleID, detection); err != nil {
			return fmt.Errorf("spoor vastleggen: %w", err)
		}
	}
	return tx.Commit(ctx)
}

// MarkMissing zet een vervalmoment op alles wat deze ronde niet is gezien.
//
// Wissen gebeurt niet. Een root die tijdelijk niet gemount is mag geen halve
// bibliotheek opruimen, en een bestand dat terugkomt hoort zijn id terug te
// krijgen en niet een nieuwe.
func (s *Store) MarkMissing(ctx context.Context, locationID id.ID, seenPaths []string, now time.Time) (int64, error) {
	tag, err := s.pool.Exec(ctx, `
		UPDATE media_files
		SET missing_since = $3
		WHERE storage_location_id = $1
		  AND missing_since IS NULL
		  AND NOT (relative_path = ANY($2))`, locationID, seenPaths, now)
	if err != nil {
		return 0, fmt.Errorf("verdwenen bestanden markeren: %w", err)
	}
	return tag.RowsAffected(), nil
}

// ClearMissing haalt de vlag weg van bestanden die weer opdoken.
func (s *Store) ClearMissing(ctx context.Context, locationID id.ID, seenPaths []string) (int64, error) {
	tag, err := s.pool.Exec(ctx, `
		UPDATE media_files
		SET missing_since = NULL
		WHERE storage_location_id = $1
		  AND missing_since IS NOT NULL
		  AND relative_path = ANY($2)`, locationID, seenPaths)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}

// PruneEmpty ruimt op wat na een ronde nergens meer bij hoort: versies zonder
// bestand en items zonder versie of kind. Een lege serie of een lege versie
// blijven anders in de bibliotheek staan als een titel die niets afspeelt.
func (s *Store) PruneEmpty(ctx context.Context, libraryID id.ID) error {
	statements := []string{
		`DELETE FROM media_versions v
		 WHERE v.item_id IN (SELECT id FROM media_items WHERE library_id = $1)
		   AND NOT EXISTS (
		       SELECT 1 FROM media_files f
		       WHERE f.version_id = v.id AND f.role = 'media' AND f.missing_since IS NULL)`,

		`DELETE FROM media_items i
		 WHERE i.library_id = $1 AND i.kind IN ('movie', 'episode')
		   AND NOT EXISTS (SELECT 1 FROM media_versions v WHERE v.item_id = i.id)`,

		`DELETE FROM media_items i
		 WHERE i.library_id = $1 AND i.kind = 'season'
		   AND NOT EXISTS (SELECT 1 FROM media_items c WHERE c.parent_id = i.id)`,

		`DELETE FROM media_items i
		 WHERE i.library_id = $1 AND i.kind = 'show'
		   AND NOT EXISTS (SELECT 1 FROM media_items c WHERE c.parent_id = i.id)`,
	}
	for _, stmt := range statements {
		if _, err := s.pool.Exec(ctx, stmt, libraryID); err != nil {
			return fmt.Errorf("opruimen: %w", err)
		}
	}
	return nil
}

func nullInt(v int) any {
	if v == 0 {
		return nil
	}
	return v
}

func nullInt64(v int64) any {
	if v == 0 {
		return nil
	}
	return v
}

func nullFloat(v float64) any {
	if v == 0 {
		return nil
	}
	return v
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

// ScanCounters zijn de tellers van één scanronde.
type ScanCounters struct {
	FilesSeen       int64
	FilesNew        int64
	FilesRenamed    int64
	FilesChanged    int64
	FilesProbed     int64
	FilesMissing    int64
	BytesHashed     int64
	ItemsCreated    int64
	VersionsCreated int64
	Errors          int64
	LastError       string
	CurrentPath     string
}

// StartScanRun opent een ronde.
func (s *Store) StartScanRun(ctx context.Context, libraryID id.ID, trigger string) (id.ID, error) {
	runID := id.New()
	_, err := s.pool.Exec(ctx,
		`INSERT INTO scan_runs (id, library_id, trigger) VALUES ($1, $2, $3)`,
		runID, libraryID, trigger)
	if err != nil {
		return id.Nil, fmt.Errorf("scanronde openen: %w", err)
	}
	return runID, nil
}

// UpdateScanProgress schrijft de tussenstand weg.
//
// Dit is wat "scanvoortgang moet meetbaar zijn ook zonder websocket" concreet
// betekent: een trage NAS laat de scanner hangen lijken, en dan is een teller
// die oploopt het verschil tussen wachten en ingrijpen.
func (s *Store) UpdateScanProgress(ctx context.Context, runID id.ID, c ScanCounters) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE scan_runs
		SET files_seen = $2, files_new = $3, files_renamed = $4, files_changed = $5,
		    files_probed = $6, files_missing = $7, bytes_hashed = $8,
		    items_created = $9, versions_created = $10, error_count = $11,
		    last_error = $12, current_path = $13
		WHERE id = $1`,
		runID, c.FilesSeen, c.FilesNew, c.FilesRenamed, c.FilesChanged,
		c.FilesProbed, c.FilesMissing, c.BytesHashed, c.ItemsCreated,
		c.VersionsCreated, c.Errors, nullString(truncate(c.LastError, 500)),
		nullString(truncate(c.CurrentPath, 500)))
	return err
}

// FinishScanRun sluit een ronde af.
func (s *Store) FinishScanRun(ctx context.Context, runID id.ID, state string, c ScanCounters) error {
	if err := s.UpdateScanProgress(ctx, runID, c); err != nil {
		return err
	}
	_, err := s.pool.Exec(ctx, `
		UPDATE scan_runs SET state = $2, finished_at = now(), current_path = NULL
		WHERE id = $1`, runID, state)
	return err
}

// LatestScanRun geeft de laatste ronde van een bibliotheek.
func (s *Store) LatestScanRun(ctx context.Context, libraryID id.ID) (id.ID, string, time.Time, error) {
	var runID id.ID
	var state string
	var started time.Time
	err := s.pool.QueryRow(ctx, `
		SELECT id, state, started_at FROM scan_runs
		WHERE library_id = $1 ORDER BY started_at DESC LIMIT 1`, libraryID).
		Scan(&runID, &state, &started)
	if errors.Is(err, pgx.ErrNoRows) {
		return id.Nil, "", time.Time{}, ErrNotFound
	}
	return runID, state, started, err
}

// De schrijflaag van S2.2: bibliotheken die een beheerder over de API
// aanmaakt, aanpast en verwijdert.

// ErrSlugTaken betekent dat libraries.slug al bestaat: twee titels die naar
// dezelfde slug afronden ("Films!" en "Films?" worden allebei "films"), of een
// titel die toevallig samenvalt met de slug van een bibliotheek uit
// PLEYA_SERVER_LIBRARIES.
var ErrSlugTaken = errors.New("die slug is al in gebruik")

// ErrLibraryNotEmpty betekent dat de bibliotheek nog media_items draagt.
var ErrLibraryNotEmpty = errors.New("de bibliotheek bevat nog items")

// ErrRootNotOffered betekent dat een root_path niet uniek beschikbaar is: hij
// overlapt met een root die al bij een andere bibliotheek hoort, of met een
// andere root in dezelfde aanvraag. S2.3 breidt deze controle uit met de echte
// opsomming uit de mounts; tot dan is "beschikbaar" niet meer dan "nog niet
// geclaimd".
var ErrRootNotOffered = errors.New("deze root is niet beschikbaar")

// slugify maakt van een titel een slug: kleine letters, cijfers en
// koppeltekens, zonder leidende, dubbele of afsluitende streepjes. Een titel
// zonder een enkel bruikbaar teken (bijvoorbeeld enkel leestekens) valt terug
// op "library"; een botsing daarop is ErrSlugTaken, zoals elke andere.
func slugify(title string) string {
	var b strings.Builder
	prevDash := true
	for _, r := range strings.ToLower(title) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
			prevDash = false
		default:
			if !prevDash {
				b.WriteByte('-')
				prevDash = true
			}
		}
	}
	out := strings.TrimRight(b.String(), "-")
	if out == "" {
		return "library"
	}
	return out
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

// rootsOverlap zegt of twee absolute paden elkaar bevatten of gelijk zijn,
// dezelfde controle als config.ParseLibraries voor de omgeving al draait.
func rootsOverlap(a, b string) bool {
	if a == b {
		return true
	}
	return strings.HasPrefix(a, strings.TrimSuffix(b, "/")+"/") ||
		strings.HasPrefix(b, strings.TrimSuffix(a, "/")+"/")
}

// CreateLibrary voegt een door de API beheerde bibliotheek toe (S2.2, managed
// = db: dit is het enige pad dat dat ooit zet).
//
// Geen enkel bestand wordt aangeraakt: root_paths komen letterlijk uit de
// aanvraag, en tot S2.3 de opsomming uit de mounts bouwt is er niets om ze
// veilig tegen te toetsen (mounts.Inspect doet ook een schrijfprobe, en die op
// een door de client verzonnen pad loslaten zou K rij 10 juist schenden). Een
// aanroeper met een pad buiten de mounts krijgt dus vandaag geen weigering
// daarop; dat komt met S2.3. fs_type en inode_trusted blijven op hun
// kolomdefault staan tot een latere scan of S2.3 ze meet.
func (s *Store) CreateLibrary(ctx context.Context, title, kind string, rootPaths []string) (Library, error) {
	for i, a := range rootPaths {
		for _, b := range rootPaths[i+1:] {
			if rootsOverlap(a, b) {
				return Library{}, ErrRootNotOffered
			}
		}
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Library{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	slug := slugify(title)
	var lib Library
	err = tx.QueryRow(ctx, `
		INSERT INTO libraries (id, slug, title, kind, managed)
		VALUES ($1, $2, $3, $4, 'db')
		RETURNING id`, id.New(), slug, title, kind).Scan(&lib.ID)
	if isUniqueViolation(err) {
		return Library{}, ErrSlugTaken
	}
	if err != nil {
		return Library{}, fmt.Errorf("bibliotheek %q vastleggen: %w", title, err)
	}

	for _, root := range rootPaths {
		if _, err := tx.Exec(ctx, `
			INSERT INTO storage_locations (id, library_id, root_path)
			VALUES ($1, $2, $3)`, id.New(), lib.ID, root); err != nil {
			if isUniqueViolation(err) {
				return Library{}, ErrRootNotOffered
			}
			return Library{}, fmt.Errorf("root %s vastleggen: %w", root, err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return Library{}, err
	}
	lib.Slug, lib.Title, lib.Kind = slug, title, kind
	lib.Managed, lib.ScanOnStart = ManagedDB, true
	return lib, nil
}

// LibraryUpdate draagt de optionele velden van PATCH /libraries/{id}.
//
// Een nil veld betekent onveranderd. RootPaths vervangt bij niet-nil de hele
// set (de handler wijst een lege lijst af vóórdat dit de store bereikt).
// ScanIntervalSet onderscheidt "niet meegestuurd" van "meegestuurd met null"
// (gebruik de globale interval): een kale *int kan dat onderscheid niet dragen.
type LibraryUpdate struct {
	Title     *string
	Kind      *string
	RootPaths []string

	ScanIntervalSet     bool
	ScanIntervalSeconds *int
	ScanOnStart         *bool
}

// UpdateLibrary past een bibliotheek aan.
//
// Of kind mag wisselen (alleen als de bibliotheek leeg is) controleert de
// aanroeper vooraf met LibraryIsEmpty: de foutcode bij "niet leeg" is
// library.not_empty en niet storage.root_not_offered, dus die keuze hoort in
// de handler en niet hier verstopt.
func (s *Store) UpdateLibrary(ctx context.Context, libraryID id.ID, patch LibraryUpdate) (Library, error) {
	for i, a := range patch.RootPaths {
		for _, b := range patch.RootPaths[i+1:] {
			if rootsOverlap(a, b) {
				return Library{}, ErrRootNotOffered
			}
		}
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Library{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if patch.Title != nil {
		if _, err := tx.Exec(ctx, `UPDATE libraries SET title = $2, updated_at = now() WHERE id = $1`,
			libraryID, *patch.Title); err != nil {
			return Library{}, fmt.Errorf("titel bijwerken: %w", err)
		}
	}
	if patch.Kind != nil {
		if _, err := tx.Exec(ctx, `UPDATE libraries SET kind = $2, updated_at = now() WHERE id = $1`,
			libraryID, *patch.Kind); err != nil {
			return Library{}, fmt.Errorf("soort bijwerken: %w", err)
		}
	}
	if patch.ScanIntervalSet {
		if _, err := tx.Exec(ctx, `UPDATE libraries SET scan_interval_seconds = $2 WHERE id = $1`,
			libraryID, patch.ScanIntervalSeconds); err != nil {
			return Library{}, fmt.Errorf("scaninterval bijwerken: %w", err)
		}
	}
	if patch.ScanOnStart != nil {
		if _, err := tx.Exec(ctx, `UPDATE libraries SET scan_on_start = $2 WHERE id = $1`,
			libraryID, *patch.ScanOnStart); err != nil {
			return Library{}, fmt.Errorf("scan_on_start bijwerken: %w", err)
		}
	}
	if patch.RootPaths != nil {
		if _, err := tx.Exec(ctx, `DELETE FROM storage_locations WHERE library_id = $1`, libraryID); err != nil {
			return Library{}, fmt.Errorf("oude roots wissen: %w", err)
		}
		for _, root := range patch.RootPaths {
			if _, err := tx.Exec(ctx, `
				INSERT INTO storage_locations (id, library_id, root_path)
				VALUES ($1, $2, $3)`, id.New(), libraryID, root); err != nil {
				if isUniqueViolation(err) {
					return Library{}, ErrRootNotOffered
				}
				return Library{}, fmt.Errorf("root %s vastleggen: %w", root, err)
			}
		}
	}

	var lib Library
	err = tx.QueryRow(ctx, `
		SELECT id, slug, title, kind, managed, scan_interval_seconds, scan_on_start
		FROM libraries WHERE id = $1`, libraryID).
		Scan(&lib.ID, &lib.Slug, &lib.Title, &lib.Kind, &lib.Managed, &lib.ScanIntervalSeconds, &lib.ScanOnStart)
	if errors.Is(err, pgx.ErrNoRows) {
		return Library{}, ErrNotFound
	}
	if err != nil {
		return Library{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Library{}, err
	}
	return lib, nil
}

// LibraryIsEmpty zegt of een bibliotheek nog enig media_items-item draagt, op
// elk niveau. Dit is de voorwaarde voor S2.2's kind-wissel en geen telling
// voor de UI; die blijft item_count.
func (s *Store) LibraryIsEmpty(ctx context.Context, libraryID id.ID) (bool, error) {
	var exists bool
	err := s.pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM media_items WHERE library_id = $1)`, libraryID).Scan(&exists)
	return !exists, err
}

// DeleteLibrary verwijdert een bibliotheek en alles wat eronder hangt.
//
// Uitsluitend in de database: storage_locations, media_items, media_versions,
// media_files en media_streams cascaderen via de FK's uit 0002_catalog.sql.
// Geen bestand op schijf wordt aangeraakt, want de scanner heeft nooit
// schrijftoegang tot een mediamount.
func (s *Store) DeleteLibrary(ctx context.Context, libraryID id.ID) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM libraries WHERE id = $1`, libraryID)
	if err != nil {
		return fmt.Errorf("bibliotheek verwijderen: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
