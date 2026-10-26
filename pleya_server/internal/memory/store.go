// Package memory bewaart persoonlijk Big P-geheugen (BP-08b). Geen inhoud verlaat
// deze laag via fouten: databasefouten kunnen statementparameters bevatten.
package memory

import (
	"context"
	"errors"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrStorage   = errors.New("geheugenopslag mislukt")
	ErrInvalid   = errors.New("memory.invalid")
	ErrConflict  = errors.New("memory.conflict")
	ErrEpoch     = errors.New("memory.epoch_changed")
	ErrDeleted   = errors.New("memory.deleted")
	ErrLimit     = errors.New("memory.limit_reached")
	ErrDuplicate = errors.New("memory.duplicate")
)

const MaxRevision int64 = 9007199254740991

type Fact struct {
	ID                      id.ID
	Category, Value, Source string
	CreatedAt, UpdatedAt    time.Time
}
type Snapshot struct {
	Epoch    id.ID
	Revision int64
	Facts    []Fact
}
type Store struct{ pool *pgxpool.Pool }

func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// begin vergrendelt één account. Ook de eerste twee GETs krijgen dezelfde epoch.
func (s *Store) begin(ctx context.Context, user id.ID) (pgx.Tx, Snapshot, error) {
	var snap Snapshot
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return nil, snap, ErrStorage
	}
	if _, err = tx.Exec(ctx, `INSERT INTO assistant_memory_states(user_id,epoch) VALUES($1,$2) ON CONFLICT(user_id) DO NOTHING`, user, id.New()); err == nil {
		err = tx.QueryRow(ctx, `SELECT epoch,revision FROM assistant_memory_states WHERE user_id=$1 FOR UPDATE`, user).Scan(&snap.Epoch, &snap.Revision)
	}
	if err != nil {
		_ = tx.Rollback(ctx)
		return nil, snap, ErrStorage
	}
	snap.Facts = []Fact{}
	rows, err := tx.Query(ctx, `SELECT id,category,value,source,created_at,updated_at FROM assistant_memory_facts WHERE user_id=$1 ORDER BY id`, user)
	if err != nil {
		_ = tx.Rollback(ctx)
		return nil, snap, ErrStorage
	}
	defer rows.Close()
	for rows.Next() {
		var f Fact
		if err = rows.Scan(&f.ID, &f.Category, &f.Value, &f.Source, &f.CreatedAt, &f.UpdatedAt); err != nil {
			break
		}
		snap.Facts = append(snap.Facts, f)
	}
	if err != nil || rows.Err() != nil {
		_ = tx.Rollback(ctx)
		return nil, snap, ErrStorage
	}
	return tx, snap, nil
}
func (s *Store) Read(ctx context.Context, user id.ID) (Snapshot, error) {
	tx, snap, err := s.begin(ctx, user)
	if err != nil {
		return Snapshot{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if tx.Commit(ctx) != nil {
		return Snapshot{}, ErrStorage
	}
	return snap, nil
}

// Replace schrijft een volledig snapshot met CAS; niets verandert bij een weigering.
func (s *Store) Replace(ctx context.Context, user, epoch id.ID, revision int64, facts []Fact, now time.Time) (Snapshot, error) {
	if revision < 0 || revision > MaxRevision || epoch == id.Nil {
		return Snapshot{}, ErrInvalid
	}
	if len(facts) > 200 {
		return Snapshot{}, ErrLimit
	}
	keys := map[string]bool{}
	ids := map[id.ID]bool{}
	for i, f := range facts {
		value, key, ok := Validate(f.Value)
		if !ok || f.ID == id.Nil || !ValidCategory(f.Category) || !ValidSource(f.Source) {
			return Snapshot{}, ErrInvalid
		}
		if keys[key] || ids[f.ID] {
			return Snapshot{}, ErrDuplicate
		}
		keys[key] = true
		ids[f.ID] = true
		facts[i].Value = value
	}
	tx, current, err := s.begin(ctx, user)
	if err != nil {
		return Snapshot{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if current.Epoch != epoch {
		return Snapshot{}, ErrEpoch
	}
	if current.Revision != revision {
		return Snapshot{}, ErrConflict
	}
	if revision == MaxRevision {
		return Snapshot{}, ErrStorage
	}
	previous := map[id.ID]Fact{}
	for _, f := range current.Facts {
		previous[f.ID] = f
	}
	now = now.UTC().Truncate(time.Microsecond)
	for i, f := range facts {
		var deleted bool
		if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM assistant_memory_tombstones WHERE user_id=$1 AND fact_id=$2)`, user, f.ID).Scan(&deleted); err != nil {
			return Snapshot{}, ErrStorage
		}
		if deleted {
			return Snapshot{}, ErrDeleted
		}
		if old, exists := previous[f.ID]; exists {
			facts[i].CreatedAt = old.CreatedAt
			facts[i].UpdatedAt = old.UpdatedAt
			if old.Value != facts[i].Value || old.Category != f.Category || old.Source != f.Source {
				facts[i].UpdatedAt = now
				if !now.After(old.UpdatedAt) {
					facts[i].UpdatedAt = old.UpdatedAt.Add(time.Microsecond)
				}
			}
		} else {
			facts[i].CreatedAt = now
			facts[i].UpdatedAt = now
		}
	}
	next := revision + 1
	for _, f := range current.Facts {
		if !ids[f.ID] {
			if _, err = tx.Exec(ctx, `INSERT INTO assistant_memory_tombstones(user_id,fact_id,deleted_revision) VALUES($1,$2,$3)`, user, f.ID, next); err != nil {
				return Snapshot{}, ErrStorage
			}
		}
	}
	// Eerst alle levende rijen vervangen: twee gelijktijdig omgewisselde valueKeys
	// botsen zo niet op de unieke index tijdens een geldige atomische snapshot.
	if _, err = tx.Exec(ctx, `DELETE FROM assistant_memory_facts WHERE user_id=$1`, user); err != nil {
		return Snapshot{}, ErrStorage
	}
	for _, f := range facts {
		_, key, _ := Validate(f.Value)
		if _, err = tx.Exec(ctx, `INSERT INTO assistant_memory_facts(user_id,id,category,value,value_key,source,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, user, f.ID, f.Category, f.Value, key, f.Source, f.CreatedAt, f.UpdatedAt); err != nil {
			return Snapshot{}, ErrStorage
		}
	}
	if _, err = tx.Exec(ctx, `UPDATE assistant_memory_states SET revision=$2 WHERE user_id=$1`, user, next); err != nil {
		return Snapshot{}, ErrStorage
	}
	if tx.Commit(ctx) != nil {
		return Snapshot{}, ErrStorage
	}
	return Snapshot{Epoch: epoch, Revision: next, Facts: facts}, nil
}
func (s *Store) Clear(ctx context.Context, user, epoch id.ID, revision int64) (Snapshot, error) {
	tx, current, err := s.begin(ctx, user)
	if err != nil {
		return Snapshot{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if current.Epoch != epoch {
		return Snapshot{}, ErrEpoch
	}
	if revision != current.Revision {
		return Snapshot{}, ErrConflict
	}
	if revision == MaxRevision {
		return Snapshot{}, ErrStorage
	}
	next := Snapshot{Epoch: id.New(), Revision: revision + 1, Facts: []Fact{}}
	if _, err = tx.Exec(ctx, `DELETE FROM assistant_memory_facts WHERE user_id=$1`, user); err != nil {
		return Snapshot{}, ErrStorage
	}
	if _, err = tx.Exec(ctx, `DELETE FROM assistant_memory_tombstones WHERE user_id=$1`, user); err != nil {
		return Snapshot{}, ErrStorage
	}
	if _, err = tx.Exec(ctx, `UPDATE assistant_memory_states SET epoch=$2,revision=$3 WHERE user_id=$1`, user, next.Epoch, next.Revision); err != nil {
		return Snapshot{}, ErrStorage
	}
	if tx.Commit(ctx) != nil {
		return Snapshot{}, ErrStorage
	}
	return next, nil
}
