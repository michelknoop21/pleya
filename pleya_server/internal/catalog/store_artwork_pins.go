package catalog

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/jackc/pgx/v5"
)

var ErrArtworkStale = errors.New("artworkkeuze ingehaald")
var ErrArtworkInvalid = errors.New("ongeldige artworkkeuze")

type ArtworkPin struct {
	ID        id.ID
	ItemID    id.ID
	Kind      string
	Source    string
	FileID    *id.ID
	Ref       *string
	SHA256    string
	Extension string
}
type ArtworkSource struct {
	Kind       string
	Source     string
	ArtworkID  *id.ID
	FileID     *id.ID
	Ref        string
	Generation int64
	SHA256     string
}

// ArtworkState is één database-snapshot; Token is berekend uit bestaande bron-
// en keuzetoestand, geen nieuwe duurzame revisie of algemene headarchitectuur.
type ArtworkState struct {
	ItemID             id.ID
	LibraryID          id.ID
	Kind               string
	AppliedProvider    *string
	AppliedExternalID  *string
	CandidateUpdatedAt *time.Time
	Sources            []ArtworkSource
	Pins               []ArtworkPin
	Token              string
}

func (s *Store) ArtworkState(ctx context.Context, itemID id.ID) (ArtworkState, error) {
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return ArtworkState{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	state, err := readArtworkState(ctx, tx, itemID)
	if err != nil {
		return state, err
	}
	return state, tx.Commit(ctx)
}
func readArtworkState(ctx context.Context, reader itemReader, itemID id.ID) (ArtworkState, error) {
	state := ArtworkState{ItemID: itemID, Sources: []ArtworkSource{}, Pins: []ArtworkPin{}}
	err := reader.QueryRow(ctx, `SELECT i.library_id,i.kind,c.applied_provider,c.applied_external_id,c.updated_at
 FROM media_items i LEFT JOIN metadata_candidates c ON c.item_id=i.id WHERE i.id=$1 AND i.kind IN ('movie','show')`, itemID).Scan(&state.LibraryID, &state.Kind, &state.AppliedProvider, &state.AppliedExternalID, &state.CandidateUpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return state, ErrNotFound
	}
	if err != nil {
		return state, err
	}
	rows, err := reader.Query(ctx, `WITH sources AS (
 SELECT artwork_kind AS kind,'local' AS source,id AS artwork_id,id AS file_id,NULL::text AS ref,generation,''::text AS sha FROM media_files
 WHERE item_id=$1 AND role='artwork' AND missing_since IS NULL AND artwork_kind IN ('poster','backdrop')
 UNION ALL SELECT kind,provider,id,NULL,source_ref,generation,sha256 FROM provider_artwork WHERE item_id=$1 AND provider='tmdb'
 ), bounded AS (SELECT *,row_number() OVER(PARTITION BY kind ORDER BY source,artwork_id) AS rank FROM sources)
 SELECT kind,source,artwork_id,file_id,ref,generation,sha FROM bounded WHERE rank<=20 ORDER BY kind,source,artwork_id`, itemID)
	if err != nil {
		return state, err
	}
	for rows.Next() {
		var source ArtworkSource
		var ref *string
		if err := rows.Scan(&source.Kind, &source.Source, &source.ArtworkID, &source.FileID, &ref, &source.Generation, &source.SHA256); err != nil {
			rows.Close()
			return state, err
		}
		if ref != nil {
			source.Ref = *ref
		}
		state.Sources = append(state.Sources, source)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return state, err
	}
	rows, err = reader.Query(ctx, `SELECT id,item_id,kind,source,source_file_id,source_ref,sha256,extension FROM artwork_pins WHERE item_id=$1 ORDER BY kind`, itemID)
	if err != nil {
		return state, err
	}
	for rows.Next() {
		var pin ArtworkPin
		if err := rows.Scan(&pin.ID, &pin.ItemID, &pin.Kind, &pin.Source, &pin.FileID, &pin.Ref, &pin.SHA256, &pin.Extension); err != nil {
			rows.Close()
			return state, err
		}
		state.Pins = append(state.Pins, pin)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return state, err
	}
	raw, err := json.Marshal(state)
	if err != nil {
		return state, err
	}
	sum := sha256.Sum256(raw)
	state.Token = hex.EncodeToString(sum[:])
	return state, nil
}

// CommitArtworkPins publiceert alle gevraagde rollen atomair. Voorbereide bytes
// zijn al veilig geschreven. Ook ontpinnen toetst dezelfde gelezen toestand.
func (s *Store) CommitArtworkPins(ctx context.Context, expected ArtworkState, changes map[string]*ArtworkPin) error {
	if len(changes) == 0 || len(changes) > 2 {
		return ErrArtworkInvalid
	}
	for kind, pin := range changes {
		if kind != "poster" && kind != "backdrop" {
			return ErrArtworkInvalid
		}
		if pin != nil && (pin.Kind != kind || pin.ItemID != expected.ItemID) {
			return ErrArtworkInvalid
		}
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := lockMetadataItem(ctx, tx, expected.ItemID); err != nil {
		return err
	}
	current, err := readArtworkState(ctx, tx, expected.ItemID)
	if err != nil {
		return err
	}
	if current.Token != expected.Token {
		return ErrArtworkStale
	}
	kinds := make([]string, 0, len(changes))
	for kind := range changes {
		kinds = append(kinds, kind)
	}
	sort.Strings(kinds)
	for _, kind := range kinds {
		pin := changes[kind]
		if pin == nil {
			if _, err := tx.Exec(ctx, `DELETE FROM artwork_pins WHERE item_id=$1 AND kind=$2`, expected.ItemID, kind); err != nil {
				return err
			}
			continue
		}
		if pin.Source == "local" {
			if pin.FileID == nil {
				return ErrArtworkInvalid
			}
			var generation int64
			found := false
			for _, source := range expected.Sources {
				if source.FileID != nil && *source.FileID == *pin.FileID && source.Kind == kind {
					generation = source.Generation
					found = true
					break
				}
			}
			if !found {
				return ErrArtworkStale
			}
			var locked id.ID
			err := tx.QueryRow(ctx, `SELECT id FROM media_files WHERE id=$1 AND item_id=$2 AND role='artwork' AND artwork_kind=$3 AND missing_since IS NULL AND generation=$4 FOR SHARE`, pin.FileID, expected.ItemID, kind, generation).Scan(&locked)
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrArtworkStale
			}
			if err != nil {
				return err
			}
		}
		_, err := tx.Exec(ctx, `INSERT INTO artwork_pins(item_id,kind,id,source,source_file_id,source_ref,sha256,extension)
  VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(item_id,kind) DO UPDATE SET id=EXCLUDED.id,source=EXCLUDED.source,source_file_id=EXCLUDED.source_file_id,source_ref=EXCLUDED.source_ref,sha256=EXCLUDED.sha256,extension=EXCLUDED.extension,created_at=clock_timestamp()`, pin.ItemID, pin.Kind, pin.ID, pin.Source, pin.FileID, pin.Ref, pin.SHA256, pin.Extension)
		if err != nil {
			return fmt.Errorf("artworkpin bewaren: %w", err)
		}
	}
	if _, err := tx.Exec(ctx, `UPDATE media_items SET updated_at=GREATEST(updated_at+interval '1 microsecond',clock_timestamp()) WHERE id=$1`, expected.ItemID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
func (s *Store) ArtworkPin(ctx context.Context, pinID id.ID) (ArtworkPin, id.ID, error) {
	var pin ArtworkPin
	var libraryID id.ID
	err := s.pool.QueryRow(ctx, `SELECT p.id,p.item_id,p.kind,p.source,p.source_file_id,p.source_ref,p.sha256,p.extension,i.library_id FROM artwork_pins p JOIN media_items i ON i.id=p.item_id WHERE p.id=$1`, pinID).Scan(&pin.ID, &pin.ItemID, &pin.Kind, &pin.Source, &pin.FileID, &pin.Ref, &pin.SHA256, &pin.Extension, &libraryID)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrNotFound
	}
	return pin, libraryID, err
}

func (s *Store) ListArtworkPins(ctx context.Context) ([]ArtworkPin, error) {
	rows, err := s.pool.Query(ctx, `SELECT id,item_id,kind,source,source_file_id,source_ref,sha256,extension FROM artwork_pins`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ArtworkPin{}
	for rows.Next() {
		var pin ArtworkPin
		if err := rows.Scan(&pin.ID, &pin.ItemID, &pin.Kind, &pin.Source, &pin.FileID, &pin.Ref, &pin.SHA256, &pin.Extension); err != nil {
			return nil, err
		}
		out = append(out, pin)
	}
	return out, rows.Err()
}

// ArtworkSourceFile bindt ook bij herstel de bewaarde bron-ID aan exact item/rol;
// de begrenzing van de keuzelijst mag een bestaande pin niet onherstelbaar maken.
func (s *Store) ArtworkSourceFile(ctx context.Context, fileID, itemID id.ID, kind string) (FileOnDisk, error) {
	var file FileOnDisk
	err := s.pool.QueryRow(ctx, `SELECT f.id,l.root_path||'/'||f.relative_path,f.generation FROM media_files f JOIN storage_locations l ON l.id=f.storage_location_id WHERE f.id=$1 AND f.item_id=$2 AND f.role='artwork' AND f.artwork_kind=$3 AND f.missing_since IS NULL`, fileID, itemID, kind).Scan(&file.ID, &file.AbsPath, &file.Generation)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrNotFound
	}
	file.Role = RoleArtwork
	file.Kind = kind
	return file, err
}
