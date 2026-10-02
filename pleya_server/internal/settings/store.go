package settings

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Store leest en schrijft server_settings.
type Store struct {
	pool *pgxpool.Pool
}

// NewStore bouwt de opslag rond de pool.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// All leest elke opgeslagen sleutel in zijn ruwe JSON-vorm.
func (s *Store) All(ctx context.Context) (map[string]json.RawMessage, error) {
	rows, err := s.pool.Query(ctx, `SELECT key, value FROM server_settings`)
	if err != nil {
		return nil, fmt.Errorf("instellingen lezen: %w", err)
	}
	defer rows.Close()

	out := map[string]json.RawMessage{}
	for rows.Next() {
		var key string
		var value []byte
		if err := rows.Scan(&key, &value); err != nil {
			return nil, fmt.Errorf("instelling lezen: %w", err)
		}
		out[key] = json.RawMessage(value)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("instellingen lezen: %w", err)
	}
	return out, nil
}

// Put schrijft een reeks sleutels in één transactie.
//
// Alles of niets: een PATCH met drie sleutels waarvan de derde de database niet
// haalt zou anders een halve wijziging achterlaten, en dan klopt het antwoord
// niet met wat er staat.
//
// updatedBy mag id.Nil zijn (geen gebruiker bekend); dan blijft de kolom leeg.
func (s *Store) Put(ctx context.Context, values map[string]json.RawMessage, updatedBy id.ID) error {
	if len(values) == 0 {
		return nil
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var by any
	if updatedBy != id.Nil {
		by = updatedBy
	}

	for key, value := range values {
		if _, err := tx.Exec(ctx, `
			INSERT INTO server_settings (key, value, updated_at, updated_by)
			VALUES ($1, $2, now(), $3)
			ON CONFLICT (key) DO UPDATE
			SET value = EXCLUDED.value, updated_at = now(), updated_by = EXCLUDED.updated_by`,
			key, []byte(value), by); err != nil {
			return fmt.Errorf("instelling %s schrijven: %w", key, err)
		}
	}

	return tx.Commit(ctx)
}
