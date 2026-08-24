// Package migrate voert de voorwaartse schemamigraties uit bij het opstarten.
//
// Hoofdstuk 17.3 van de architectuur legt drie dingen vast. Migraties zijn
// voorwaarts en genummerd. Er zijn geen automatische neerwaartse migraties:
// terugrollen gebeurt met een back-up, want een gegenereerde down-migratie die
// data weggooit is gevaarlijker dan de situatie die hij oplost. En de binary
// weigert te starten als de database nieuwer is dan hijzelf.
package migrate

import (
	"context"
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed sql/*.sql
var files embed.FS

// MinVersion is de laagste schemaversie waarmee deze binary wil werken. Draait
// hij tegen iets ouders, dan zijn de migraties overgeslagen en is doorgaan
// gevaarlijker dan stoppen.
const MinVersion = 3

// advisoryLockKey serialiseert het migreren tussen instanties. Twee containers
// die tegelijk opkomen mogen niet allebei dezelfde CREATE TABLE proberen.
const advisoryLockKey int64 = 0x504C4559_41303031 // "PLEYA001"

// ErrDatabaseNewer betekent dat de database een hogere versie draagt dan deze
// binary kent.
var ErrDatabaseNewer = errors.New("de database is nieuwer dan deze binary")

// ErrTooOld betekent dat het schema onder de minimumversie ligt.
var ErrTooOld = errors.New("schemaversie ligt onder het minimum van deze binary")

// Migration is één genummerd bestand.
type Migration struct {
	Version  int
	Name     string
	SQL      string
	Checksum string
}

// Result vat samen wat Run gedaan heeft.
type Result struct {
	From    int
	To      int
	Applied []Migration
}

// Load leest de ingebedde migraties, gesorteerd op versie.
func Load() ([]Migration, error) {
	entries, err := fs.ReadDir(files, "sql")
	if err != nil {
		return nil, err
	}

	out := make([]Migration, 0, len(entries))
	seen := map[int]string{}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".sql") {
			continue
		}
		version, name, err := parseName(e.Name())
		if err != nil {
			return nil, err
		}
		if prev, dup := seen[version]; dup {
			return nil, fmt.Errorf("migratie %d staat er twee keer in: %s en %s", version, prev, e.Name())
		}
		seen[version] = e.Name()

		body, err := files.ReadFile("sql/" + e.Name())
		if err != nil {
			return nil, err
		}
		sum := sha256.Sum256(body)
		out = append(out, Migration{
			Version:  version,
			Name:     name,
			SQL:      string(body),
			Checksum: hex.EncodeToString(sum[:]),
		})
	}

	sort.Slice(out, func(a, b int) bool { return out[a].Version < out[b].Version })

	for i, m := range out {
		if m.Version != i+1 {
			return nil, fmt.Errorf("migratie %d ontbreekt; de nummering moet aaneengesloten zijn", i+1)
		}
	}
	return out, nil
}

// Target is de versie waar deze binary naartoe migreert.
func Target() (int, error) {
	all, err := Load()
	if err != nil {
		return 0, err
	}
	if len(all) == 0 {
		return 0, errors.New("er zijn geen migraties ingebed")
	}
	return all[len(all)-1].Version, nil
}

func parseName(filename string) (int, string, error) {
	base := strings.TrimSuffix(filename, ".sql")
	parts := strings.SplitN(base, "_", 2)
	if len(parts) != 2 {
		return 0, "", fmt.Errorf("migratienaam %q mist een nummer of een naam", filename)
	}
	v, err := strconv.Atoi(parts[0])
	if err != nil || v < 1 {
		return 0, "", fmt.Errorf("migratienaam %q begint niet met een versienummer", filename)
	}
	return v, parts[1], nil
}

// Run brengt het schema naar de versie van deze binary.
//
// Elke migratie draait in zijn eigen transactie, samen met de regel die hem in
// schema_migrations vastlegt. Faalt er een, dan is die migratie in het geheel
// niet gebeurd en staan de eerdere er wel.
func Run(ctx context.Context, pool *pgxpool.Pool, log *slog.Logger) (Result, error) {
	return runTo(ctx, pool, log, -1)
}

// RunTo brengt het schema naar een specifieke versie, niet verder.
//
// Alleen voor tests die een bestaande, oudere database willen naspelen: eerst
// hierheen migreren, dan handmatig rijen invoegen zoals een live installatie ze
// zou hebben, en dan Run aanroepen voor de rest. Productiecode roept dit nooit
// aan; die wil altijd de laatste versie.
func RunTo(ctx context.Context, pool *pgxpool.Pool, log *slog.Logger, target int) (Result, error) {
	return runTo(ctx, pool, log, target)
}

// cap kleiner dan 0 betekent geen grens: migreer naar de laatste versie.
func runTo(ctx context.Context, pool *pgxpool.Pool, log *slog.Logger, cap int) (Result, error) {
	all, err := Load()
	if err != nil {
		return Result{}, err
	}

	conn, err := pool.Acquire(ctx)
	if err != nil {
		return Result{}, fmt.Errorf("verbinding voor migreren: %w", err)
	}
	defer conn.Release()

	if _, err := conn.Exec(ctx, `SELECT pg_advisory_lock($1)`, advisoryLockKey); err != nil {
		return Result{}, fmt.Errorf("migratieslot nemen: %w", err)
	}
	defer func() {
		unlockCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_, _ = conn.Exec(unlockCtx, `SELECT pg_advisory_unlock($1)`, advisoryLockKey)
	}()

	if err := ensureTable(ctx, conn.Conn()); err != nil {
		return Result{}, err
	}

	applied, err := appliedVersions(ctx, conn.Conn())
	if err != nil {
		return Result{}, err
	}

	current := 0
	for v := range applied {
		if v > current {
			current = v
		}
	}

	target := all[len(all)-1].Version
	if cap >= 0 && cap < target {
		target = cap
	}
	if current > target {
		return Result{}, fmt.Errorf("%w: schema %d, binary %d", ErrDatabaseNewer, current, target)
	}

	result := Result{From: current, To: current}

	for _, m := range all {
		if m.Version > target {
			break
		}
		if sum, done := applied[m.Version]; done {
			if sum != "" && sum != m.Checksum {
				return result, fmt.Errorf(
					"migratie %d (%s) is na het toepassen gewijzigd; een toegepaste migratie bewerken is geen migratie",
					m.Version, m.Name)
			}
			continue
		}

		start := time.Now()
		if err := apply(ctx, conn.Conn(), m); err != nil {
			return result, fmt.Errorf("migratie %d (%s): %w", m.Version, m.Name, err)
		}
		result.Applied = append(result.Applied, m)
		result.To = m.Version

		if log != nil {
			log.Info("migratie toegepast",
				slog.Int("version", m.Version),
				slog.String("name", m.Name),
				slog.Duration("duration", time.Since(start)))
		}
	}

	if result.To < MinVersion {
		return result, fmt.Errorf("%w: schema %d, minimum %d", ErrTooOld, result.To, MinVersion)
	}
	return result, nil
}

func ensureTable(ctx context.Context, conn *pgx.Conn) error {
	const ddl = `
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    integer     PRIMARY KEY,
    name       text        NOT NULL,
    checksum   text        NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now()
)`
	if _, err := conn.Exec(ctx, ddl); err != nil {
		return fmt.Errorf("schema_migrations aanmaken: %w", err)
	}
	return nil
}

func appliedVersions(ctx context.Context, conn *pgx.Conn) (map[int]string, error) {
	rows, err := conn.Query(ctx, `SELECT version, checksum FROM schema_migrations`)
	if err != nil {
		return nil, fmt.Errorf("toegepaste migraties lezen: %w", err)
	}
	defer rows.Close()

	out := map[int]string{}
	for rows.Next() {
		var v int
		var sum string
		if err := rows.Scan(&v, &sum); err != nil {
			return nil, err
		}
		out[v] = sum
	}
	return out, rows.Err()
}

func apply(ctx context.Context, conn *pgx.Conn, m Migration) error {
	tx, err := conn.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, m.SQL); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO schema_migrations (version, name, checksum) VALUES ($1, $2, $3)`,
		m.Version, m.Name, m.Checksum); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
