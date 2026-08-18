package catalog

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Store is de toegang tot de catalogus.
type Store struct {
	pool *pgxpool.Pool
}

// NewStore bouwt de opslag rond de pool.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// ErrNotFound is de enige fout die de leeslaag naar buiten brengt. Een resource
// die u niet mag zien bestaat voor u niet, dus 404 en geen 403; met één
// identiteit is dat vandaag theoretisch, maar de regel staat er nu zodat PS-9
// hem niet hoeft te introduceren.
var ErrNotFound = errors.New("bestaat niet")

// LibrarySpec beschrijft één geconfigureerde bibliotheek met zijn roots.
type LibrarySpec struct {
	Slug  string
	Title string
	Kind  string
	Roots []RootSpec
}

// RootSpec is één root met wat er over het bestandssysteem gemeten is.
type RootSpec struct {
	Path         string
	FSType       string
	InodeTrusted bool
	TrustSource  string
}

// SyncLibraries brengt de database in lijn met de configuratie.
//
// De slug is de matchsleutel, niet de titel en niet het pad: daarom overleeft
// een id een hernoemde bibliotheek en een verplaatste root. Wat uit de
// configuratie verdwijnt wordt niet verwijderd; een root die er even niet is
// mag geen bibliotheek opruimen.
func (s *Store) SyncLibraries(ctx context.Context, specs []LibrarySpec) ([]Library, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	out := make([]Library, 0, len(specs))
	for _, spec := range specs {
		var lib Library
		lib.Slug, lib.Title, lib.Kind = spec.Slug, spec.Title, spec.Kind

		err := tx.QueryRow(ctx, `
			INSERT INTO libraries (id, slug, title, kind)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (slug) DO UPDATE
			SET title = EXCLUDED.title, kind = EXCLUDED.kind, updated_at = now()
			RETURNING id`, id.New(), spec.Slug, spec.Title, spec.Kind).Scan(&lib.ID)
		if err != nil {
			return nil, fmt.Errorf("bibliotheek %q vastleggen: %w", spec.Slug, err)
		}

		for _, root := range spec.Roots {
			if _, err := tx.Exec(ctx, `
				INSERT INTO storage_locations (id, library_id, root_path, fs_type, inode_trusted, inode_trust_source, last_seen_at)
				VALUES ($1, $2, $3, $4, $5, $6, now())
				ON CONFLICT (root_path) DO UPDATE
				SET library_id = EXCLUDED.library_id,
				    fs_type = EXCLUDED.fs_type,
				    inode_trusted = EXCLUDED.inode_trusted,
				    inode_trust_source = EXCLUDED.inode_trust_source,
				    last_seen_at = now()`,
				id.New(), lib.ID, root.Path, nullString(root.FSType),
				root.InodeTrusted, root.TrustSource); err != nil {
				return nil, fmt.Errorf("root %s vastleggen: %w", root.Path, err)
			}
		}
		out = append(out, lib)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return out, nil
}

// Libraries geeft alle bibliotheken met hun aantal items.
//
// item_count telt uitsluitend wat de bibliotheek op het hoogste niveau toont:
// films in een movies-bibliotheek, series in een shows-bibliotheek. Seizoenen en
// afleveringen meetellen zou een getal opleveren dat nergens mee overeenkomt.
func (s *Store) Libraries(ctx context.Context) ([]Library, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT l.id, l.slug, l.title, l.kind,
		       (SELECT count(*) FROM media_items i
		         WHERE i.library_id = l.id AND i.kind IN ('movie', 'show'))
		FROM libraries l
		ORDER BY l.title, l.id`)
	if err != nil {
		return nil, fmt.Errorf("bibliotheken lezen: %w", err)
	}
	defer rows.Close()

	var out []Library
	for rows.Next() {
		var l Library
		if err := rows.Scan(&l.ID, &l.Slug, &l.Title, &l.Kind, &l.ItemCount); err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}

// Library geeft één bibliotheek.
func (s *Store) Library(ctx context.Context, libraryID id.ID) (Library, error) {
	var l Library
	err := s.pool.QueryRow(ctx,
		`SELECT id, slug, title, kind FROM libraries WHERE id = $1`, libraryID).
		Scan(&l.ID, &l.Slug, &l.Title, &l.Kind)
	if errors.Is(err, pgx.ErrNoRows) {
		return l, ErrNotFound
	}
	return l, err
}

// StorageLocations geeft de roots van een bibliotheek.
func (s *Store) StorageLocations(ctx context.Context, libraryID id.ID) ([]StorageLocation, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, library_id, root_path, coalesce(fs_type, ''), inode_trusted, inode_trust_source
		FROM storage_locations WHERE library_id = $1 ORDER BY root_path`, libraryID)
	if err != nil {
		return nil, fmt.Errorf("roots lezen: %w", err)
	}
	defer rows.Close()

	var out []StorageLocation
	for rows.Next() {
		var loc StorageLocation
		if err := rows.Scan(&loc.ID, &loc.LibraryID, &loc.RootPath, &loc.FSType,
			&loc.InodeTrusted, &loc.TrustSource); err != nil {
			return nil, err
		}
		out = append(out, loc)
	}
	return out, rows.Err()
}

// FileIndex is de bestandsstand van één root, zoals hij vóór deze scanronde in
// de database stond.
type FileIndex struct {
	ByPath  map[string]*File
	ByInode map[int64]*File

	// bySignature is de terugval voor roots waar de inode niets betekent. Daar
	// wordt de hash uit laag 2 toch al voor elk bestand berekend, dus een
	// hernoeming is er gratis aan te herkennen. Een signature die twee bestanden
	// draagt levert geen match op: dan bewijst hij niets over welk van de twee
	// dit is.
	bySignature map[string]*File
}

// BySignature zoekt een bestand op zijn scan-signature.
//
// Hoofdstuk 7.2 blijft gelden: dit is geen bewijs van gelijkheid. Het is genoeg
// om een verplaatst bestand aan zijn item te blijven hangen, en niet genoeg om
// er iets over de bytes uit af te leiden.
func (i *FileIndex) BySignature(signature string, size int64) *File {
	f := i.bySignature[signature]
	if f == nil || f.SizeBytes != size {
		return nil
	}
	return f
}

// LoadFileIndex leest de hele bestandsstand van één root in het geheugen.
//
// Bij 2601 videobestanden plus 8501 sidecars is dat een paar megabyte, en het
// bespaart een query per bestand op een NAS waar elke rondgang telt. Groeit dat
// de pan uit, dan is een cursor per map het antwoord, maar dat is een meting en
// geen voorzorg.
func (s *Store) LoadFileIndex(ctx context.Context, locationID id.ID) (*FileIndex, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, storage_location_id, relative_path, role, version_id, item_id,
		       part_index, coalesce(artwork_kind, ''), size_bytes, mtime_unix, inode,
		       coalesce(scan_signature, ''), generation, missing_since
		FROM media_files WHERE storage_location_id = $1`, locationID)
	if err != nil {
		return nil, fmt.Errorf("bestandsstand lezen: %w", err)
	}
	defer rows.Close()

	idx := &FileIndex{
		ByPath:      map[string]*File{},
		ByInode:     map[int64]*File{},
		bySignature: map[string]*File{},
	}
	for rows.Next() {
		var f File
		if err := rows.Scan(&f.ID, &f.StorageLocationID, &f.RelativePath, &f.Role,
			&f.VersionID, &f.ItemID, &f.PartIndex, &f.ArtworkKind, &f.SizeBytes,
			&f.MtimeUnix, &f.Inode, &f.Signature, &f.Generation, &f.MissingSince); err != nil {
			return nil, err
		}
		file := f
		idx.ByPath[f.RelativePath] = &file
		if f.Signature != "" {
			if _, clash := idx.bySignature[f.Signature]; clash {
				idx.bySignature[f.Signature] = nil
			} else {
				idx.bySignature[f.Signature] = &file
			}
		}
		if f.Inode != nil {
			// Een inode die twee paden draagt is geen identiteit meer. Dan is de
			// goedkope laag hier onbruikbaar en telt alleen het pad.
			if _, clash := idx.ByInode[*f.Inode]; clash {
				idx.ByInode[*f.Inode] = nil
			} else {
				idx.ByInode[*f.Inode] = &file
			}
		}
	}
	return idx, rows.Err()
}

func nullString(v string) any {
	if v == "" {
		return nil
	}
	return v
}

func jsonb(v any) ([]byte, error) {
	if v == nil {
		return []byte("{}"), nil
	}
	return json.Marshal(v)
}

// detectionOrEmpty houdt een lege map uit de kolom in plaats van null.
func detectionOrEmpty(m ffprobe.DetectionMap) ffprobe.DetectionMap {
	if m == nil {
		return ffprobe.DetectionMap{}
	}
	return m
}

func nowUTC() time.Time { return time.Now().UTC() }
