package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Store bewaart de bootstrap-auth-state.
//
// Specificatie 6.5 somt uitputtend op wat dat mag zijn: één credential-record,
// per refreshtoken een identificatie plus vervalmoment en ingetrokken-vlag, en
// de setupcode plus de vlag of setup gedaan is. De ondertekensleutel staat op
// schijf en komt hier niet langs.
type Store struct {
	pool *pgxpool.Pool
}

// NewStore bouwt de opslag rond de pool.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// Owner is de enige identiteit die vóór PS-9 bestaat.
type Owner struct {
	Username         string
	PasswordHash     string
	SetupCompletedAt *time.Time
	SetupCodeHash    []byte
	SetupCodeExpires *time.Time
}

// ErrNoOwner betekent dat setup nog niet gedaan is.
var ErrNoOwner = errors.New("er is nog geen eigenaar aangemaakt")

// ErrSetupCompleted betekent dat er al een eigenaar is.
var ErrSetupCompleted = errors.New("er is al een eigenaar")

// ErrSetupCodeInvalid betekent dat de setupcode niet klopt of verlopen is.
var ErrSetupCodeInvalid = errors.New("de setupcode klopt niet")

// LoadOwner leest de singleton. Bestaat de rij nog niet, dan is dat geen fout:
// een verse server heeft er geen.
func (s *Store) LoadOwner(ctx context.Context) (*Owner, error) {
	var o Owner
	var username, hash *string

	err := s.pool.QueryRow(ctx, `
		SELECT username, password_hash, setup_completed_at, setup_code_hash, setup_code_expires_at
		FROM auth_owner WHERE id = 1`).
		Scan(&username, &hash, &o.SetupCompletedAt, &o.SetupCodeHash, &o.SetupCodeExpires)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("eigenaar lezen: %w", err)
	}
	if username != nil {
		o.Username = *username
	}
	if hash != nil {
		o.PasswordHash = *hash
	}
	return &o, nil
}

// SetupRequired zegt of GET /info het setupscherm moet laten tonen.
func (s *Store) SetupRequired(ctx context.Context) (bool, error) {
	owner, err := s.LoadOwner(ctx)
	if err != nil {
		return false, err
	}
	return owner == nil || owner.SetupCompletedAt == nil, nil
}

// PutSetupCode legt een verse setupcode vast. Hij vervangt een eventuele
// vorige: een server die opnieuw start zonder eigenaar drukt een nieuwe code af,
// en de oude hoort dan niet meer te werken.
func (s *Store) PutSetupCode(ctx context.Context, hash []byte, expiresAt time.Time) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO auth_owner (id, setup_code_hash, setup_code_expires_at)
		VALUES (1, $1, $2)
		ON CONFLICT (id) DO UPDATE
		SET setup_code_hash = EXCLUDED.setup_code_hash,
		    setup_code_expires_at = EXCLUDED.setup_code_expires_at,
		    updated_at = now()
		WHERE auth_owner.setup_completed_at IS NULL`, hash, expiresAt)
	if err != nil {
		return fmt.Errorf("setupcode vastleggen: %w", err)
	}
	return nil
}

// CompleteSetup wisselt de setupcode in voor de eigenaar.
//
// Alles in één transactie met een rijvergrendeling, zodat twee gelijktijdige
// pogingen niet allebei slagen. De code vervalt bij de eerste geslaagde
// inwisseling (specificatie 6.5, eigenschap 1).
func (s *Store) CompleteSetup(ctx context.Context, code, username, passwordHash string, now time.Time) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var storedHash []byte
	var expires, completed *time.Time
	err = tx.QueryRow(ctx, `
		SELECT setup_code_hash, setup_code_expires_at, setup_completed_at
		FROM auth_owner WHERE id = 1 FOR UPDATE`).
		Scan(&storedHash, &expires, &completed)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrSetupCodeInvalid
	}
	if err != nil {
		return fmt.Errorf("setupstatus lezen: %w", err)
	}
	if completed != nil {
		return ErrSetupCompleted
	}
	if len(storedHash) == 0 || expires == nil || now.After(*expires) {
		return ErrSetupCodeInvalid
	}
	if !EqualHash(storedHash, HashOpaque(code)) {
		return ErrSetupCodeInvalid
	}

	if _, err := tx.Exec(ctx, `
		UPDATE auth_owner
		SET username = $1, password_hash = $2, setup_completed_at = $3,
		    setup_code_hash = NULL, setup_code_expires_at = NULL, updated_at = now()
		WHERE id = 1`, username, passwordHash, now); err != nil {
		return fmt.Errorf("eigenaar vastleggen: %w", err)
	}
	return tx.Commit(ctx)
}

// UpdatePasswordHash herhasht bij een geslaagde login onder lichtere parameters.
func (s *Store) UpdatePasswordHash(ctx context.Context, hash string) error {
	_, err := s.pool.Exec(ctx,
		`UPDATE auth_owner SET password_hash = $1, updated_at = now() WHERE id = 1`, hash)
	return err
}

// StoreRefreshToken legt een uitgegeven refreshtoken vast.
func (s *Store) StoreRefreshToken(ctx context.Context, hash []byte, expiresAt time.Time) error {
	_, err := s.pool.Exec(ctx,
		`INSERT INTO auth_refresh_tokens (token_hash, expires_at) VALUES ($1, $2)`, hash, expiresAt)
	if err != nil {
		return fmt.Errorf("refreshtoken vastleggen: %w", err)
	}
	return nil
}

// RefreshOutcome zegt wat er met een aangeboden refreshtoken gebeurde.
type RefreshOutcome int

const (
	// RefreshUnknown: dit token is nooit uitgegeven of al opgeruimd.
	RefreshUnknown RefreshOutcome = iota
	// RefreshReused: dit token is al eerder gebruikt of ingetrokken. De hele
	// keten gaat dan om, want een van de twee partijen die het nu draagt is de
	// aanvaller en welke dat is valt niet vast te stellen.
	RefreshReused
	// RefreshExpired: het token bestond maar is verlopen.
	RefreshExpired
	// RefreshOK: het token is geldig en zojuist ingetrokken.
	RefreshOK
)

// RotateRefreshToken wisselt een refreshtoken in.
//
// Het oude vervalt onmiddellijk en het nieuwe komt ervoor in de plaats, in
// dezelfde transactie. Komt een al gebruikt token terug, dan wordt de hele keten
// ongeldig; met één identiteit is dat elke uitstaande rij.
func (s *Store) RotateRefreshToken(ctx context.Context, oldHash, newHash []byte, newExpires, now time.Time) (RefreshOutcome, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return RefreshUnknown, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var expiresAt time.Time
	var revokedAt *time.Time
	err = tx.QueryRow(ctx,
		`SELECT expires_at, revoked_at FROM auth_refresh_tokens WHERE token_hash = $1 FOR UPDATE`,
		oldHash).Scan(&expiresAt, &revokedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return RefreshUnknown, nil
	}
	if err != nil {
		return RefreshUnknown, fmt.Errorf("refreshtoken lezen: %w", err)
	}

	if revokedAt != nil {
		if _, err := tx.Exec(ctx,
			`UPDATE auth_refresh_tokens SET revoked_at = $1 WHERE revoked_at IS NULL`, now); err != nil {
			return RefreshUnknown, err
		}
		if err := tx.Commit(ctx); err != nil {
			return RefreshUnknown, err
		}
		return RefreshReused, nil
	}
	if now.After(expiresAt) {
		return RefreshExpired, nil
	}

	if _, err := tx.Exec(ctx,
		`UPDATE auth_refresh_tokens SET revoked_at = $1 WHERE token_hash = $2`, now, oldHash); err != nil {
		return RefreshUnknown, err
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO auth_refresh_tokens (token_hash, expires_at) VALUES ($1, $2)`, newHash, newExpires); err != nil {
		return RefreshUnknown, err
	}
	if err := tx.Commit(ctx); err != nil {
		return RefreshUnknown, err
	}
	return RefreshOK, nil
}

// PurgeExpiredRefreshTokens ruimt op wat niemand meer kan gebruiken. Verlopen
// rijen laten staan levert een tabel op die alleen maar groeit en die de
// hergebruikdetectie niets extra's oplevert.
func (s *Store) PurgeExpiredRefreshTokens(ctx context.Context, before time.Time) (int64, error) {
	tag, err := s.pool.Exec(ctx,
		`DELETE FROM auth_refresh_tokens WHERE expires_at < $1`, before)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}

// ServerID leest de serveridentiteit en maakt hem aan bij de eerste start.
func (s *Store) ServerID(ctx context.Context) (id.ID, error) {
	var existing id.ID
	err := s.pool.QueryRow(ctx, `SELECT server_id FROM server_instance WHERE id = 1`).Scan(&existing)
	if err == nil {
		return existing, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return id.Nil, fmt.Errorf("serveridentiteit lezen: %w", err)
	}

	fresh := id.New()
	err = s.pool.QueryRow(ctx, `
		INSERT INTO server_instance (id, server_id) VALUES (1, $1)
		ON CONFLICT (id) DO UPDATE SET server_id = server_instance.server_id
		RETURNING server_id`, fresh).Scan(&existing)
	if err != nil {
		return id.Nil, fmt.Errorf("serveridentiteit aanmaken: %w", err)
	}
	return existing, nil
}
