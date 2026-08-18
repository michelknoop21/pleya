package catalog

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

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
func (s *Store) RecordProbeFailure(ctx context.Context, fileID id.ID, size, mtime int64, inode *int64, signature, reason string) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE media_files
		SET size_bytes = $2, mtime_unix = $3, inode = $4, scan_signature = $5,
		    probe_attempts = probe_attempts + 1, last_probe_at = now(),
		    last_probe_error = $6, missing_since = NULL, last_seen_at = now()
		WHERE id = $1`, fileID, size, mtime, inode, nullString(signature), truncate(reason, 500))
	return err
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
