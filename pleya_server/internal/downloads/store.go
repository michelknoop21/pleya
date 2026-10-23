// Package downloads bewaart de afspraken "deze gebruiker haalt deze versie op
// voor offline kijken" (S23) en rekent de controlesom uit die een client nodig
// heeft om het bestand te controleren en te hervatten.
//
// Het bestand zelf wordt hier niet geleverd; dat doet de API vanaf het
// mediabestand. Dit pakket weet alleen welke download van wie is, in welke
// toestand hij staat en welke hash bij welke bestandsgrootte en -tijd hoort.
package downloads

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// ErrNotFound: de download bestaat niet, of is van een ander.
var ErrNotFound = errors.New("downloads: onbekend")

// Status is de toestand van een download.
type Status string

const (
	Preparing Status = "preparing"
	Ready     Status = "ready"
	Failed    Status = "failed"
)

// Download is een rij uit downloads.
type Download struct {
	ID        id.ID
	UserID    id.ID
	ItemID    id.ID
	VersionID id.ID
	Status    Status
	SizeBytes *int64
	MtimeNS   *int64
	SHA256    string
	CreatedAt time.Time
	UpdatedAt time.Time
}

// Store is de opslag van downloads.
type Store struct{ pool *pgxpool.Pool }

// NewStore maakt een Store.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

const columns = `id, user_id, item_id, version_id, status, size_bytes, mtime_ns, coalesce(sha256, ''), created_at, updated_at`

func scan(row pgx.Row) (Download, error) {
	var d Download
	var status string
	err := row.Scan(&d.ID, &d.UserID, &d.ItemID, &d.VersionID, &status, &d.SizeBytes, &d.MtimeNS, &d.SHA256, &d.CreatedAt, &d.UpdatedAt)
	d.Status = Status(status)
	return d, err
}

// Create legt een download aan in toestand preparing.
func (s *Store) Create(ctx context.Context, user, item, version id.ID) (Download, error) {
	d, err := scan(s.pool.QueryRow(ctx, `
		INSERT INTO downloads (id, user_id, item_id, version_id) VALUES ($1, $2, $3, $4)
		RETURNING `+columns, id.New(), user, item, version))
	if err != nil {
		return Download{}, fmt.Errorf("download aanmaken: %w", err)
	}
	return d, nil
}

// Get leest een download van deze gebruiker. Die van een ander bestaat niet.
func (s *Store) Get(ctx context.Context, user, dl id.ID) (Download, error) {
	d, err := scan(s.pool.QueryRow(ctx, `SELECT `+columns+` FROM downloads WHERE id = $1 AND user_id = $2`, dl, user))
	if errors.Is(err, pgx.ErrNoRows) {
		return Download{}, ErrNotFound
	}
	return d, err
}

// GetAny leest een download zonder eigenaarscontrole, voor de achtergrondtaak.
func (s *Store) GetAny(ctx context.Context, dl id.ID) (Download, error) {
	d, err := scan(s.pool.QueryRow(ctx, `SELECT `+columns+` FROM downloads WHERE id = $1`, dl))
	if errors.Is(err, pgx.ErrNoRows) {
		return Download{}, ErrNotFound
	}
	return d, err
}

// List geeft de downloads van deze gebruiker, nieuwste eerst.
func (s *Store) List(ctx context.Context, user id.ID) ([]Download, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT `+columns+` FROM downloads WHERE user_id = $1 ORDER BY created_at DESC, id DESC LIMIT 500`, user)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Download
	for rows.Next() {
		d, err := scan(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// Delete haalt een download van deze gebruiker weg. Het mediabestand blijft.
func (s *Store) Delete(ctx context.Context, user, dl id.ID) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM downloads WHERE id = $1 AND user_id = $2`, dl, user)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// MarkReady legt de controlesom vast en maakt de download leverbaar.
func (s *Store) MarkReady(ctx context.Context, dl id.ID, size, mtimeNS int64, sum string) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE downloads SET status = 'ready', size_bytes = $2, mtime_ns = $3, sha256 = $4, updated_at = now()
		WHERE id = $1`, dl, size, mtimeNS, sum)
	return err
}

// MarkFailed zet een download op failed; de oorzaak staat in het serverlog.
func (s *Store) MarkFailed(ctx context.Context, dl id.ID) error {
	_, err := s.pool.Exec(ctx, `UPDATE downloads SET status = 'failed', updated_at = now() WHERE id = $1`, dl)
	return err
}

// KnownSum geeft een eerder berekende hash voor dezelfde versie, mits grootte en
// wijzigingstijd van het bestand gelijk zijn. Een tweede download van dezelfde
// film hoeft het bestand dan niet nog eens te lezen.
func (s *Store) KnownSum(ctx context.Context, version id.ID, size, mtimeNS int64) (string, bool, error) {
	var sum string
	err := s.pool.QueryRow(ctx, `
		SELECT sha256 FROM downloads
		WHERE version_id = $1 AND status = 'ready' AND size_bytes = $2 AND mtime_ns = $3
		ORDER BY updated_at DESC LIMIT 1`, version, size, mtimeNS).Scan(&sum)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", false, nil
	}
	return sum, err == nil, err
}

// Fingerprint is grootte en wijzigingstijd van een bestand op dit moment.
type Fingerprint struct {
	Size    int64
	MtimeNS int64
}

// Stat leest de Fingerprint van een pad.
func Stat(path string) (Fingerprint, error) {
	info, err := os.Stat(path)
	if err != nil {
		return Fingerprint{}, err
	}
	return Fingerprint{Size: info.Size(), MtimeNS: info.ModTime().UnixNano()}, nil
}

// Matches zegt of de download nog bij het bestand op schijf hoort.
func (d Download) Matches(fp Fingerprint) bool {
	return d.SizeBytes != nil && d.MtimeNS != nil && *d.SizeBytes == fp.Size && *d.MtimeNS == fp.MtimeNS
}

// Sum rekent de SHA-256 (hex) over het hele bestand en geeft daarbij de
// Fingerprint van vóór het lezen terug. Verandert het bestand tijdens het
// lezen, dan wijkt de Fingerprint van daarna af en geeft Sum een fout: een hash
// over een bestand dat halverwege veranderde is nergens voor te gebruiken.
func Sum(ctx context.Context, path string) (string, Fingerprint, error) {
	before, err := Stat(path)
	if err != nil {
		return "", Fingerprint{}, err
	}
	f, err := os.Open(path)
	if err != nil {
		return "", Fingerprint{}, err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, &ctxReader{ctx: ctx, r: f}); err != nil {
		return "", Fingerprint{}, err
	}
	after, err := Stat(path)
	if err != nil {
		return "", Fingerprint{}, err
	}
	if after != before {
		return "", Fingerprint{}, errors.New("bestand veranderde tijdens het hashen")
	}
	return hex.EncodeToString(h.Sum(nil)), before, nil
}

type ctxReader struct {
	ctx context.Context
	r   io.Reader
}

func (c *ctxReader) Read(p []byte) (int, error) {
	if err := c.ctx.Err(); err != nil {
		return 0, err
	}
	return c.r.Read(p)
}
