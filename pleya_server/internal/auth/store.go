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

// ErrUserNotFound betekent dat er geen rij in users staat met dit id.
var ErrUserNotFound = errors.New("gebruiker bestaat niet")

// Role is de waarde van users.role. Vier stuks (migratie 0007, DEC-119): owner
// precies één, admin/member/restricted nul of meer. De ladder in
// library_permissions (view < download < manage) is er los van: owner en
// admin krijgen daar nooit een rij, hun toegang volgt uit de rol zelf.
type Role string

const (
	RoleOwner      Role = "owner"
	RoleAdmin      Role = "admin"
	RoleMember     Role = "member"
	RoleRestricted Role = "restricted"
)

// UserRole leest de rol van een gebruiker.
func (s *Store) UserRole(ctx context.Context, userID id.ID) (Role, error) {
	var role Role
	err := s.pool.QueryRow(ctx, `SELECT role FROM users WHERE id = $1`, userID).Scan(&role)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrUserNotFound
	}
	if err != nil {
		return "", fmt.Errorf("rol lezen: %w", err)
	}
	return role, nil
}

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
	// Vanaf PS-9 is users de bron van waarheid voor rollen en rechten; auth_owner
	// blijft ernaast bestaan voor LoadOwner (specificatie 6.5). Een verse
	// installatie na migratie 0007 heeft nog geen users-rij, dus die komt hier
	// vandaan; een gemigreerde installatie kreeg zijn owner-rij al in 0007 en
	// doorloopt dit pad nooit opnieuw (setup is eenmalig).
	if _, err := tx.Exec(ctx, `
		INSERT INTO users (id, username, password_hash, role, created_at, updated_at)
		VALUES ($1, $2, $3, 'owner', $4, $4)`,
		id.New(), username, passwordHash, now); err != nil {
		return fmt.Errorf("owner-gebruiker vastleggen: %w", err)
	}
	return tx.Commit(ctx)
}

// OwnerUserID leest het users.id van de owner-rij.
//
// Setup, login en refresh lossen hun subject hiermee op, in plaats van met de
// vaste "owner"-string van vóór PS-9, want watch_states.subject en
// stream_sessions.subject zijn nu een echte FK naar users(id) (DEC-119) en
// accepteren die string niet meer. Elders (handlers_watch.go, authorize.go)
// loopt Claims.Subject inmiddels rechtstreeks door de context (DEC-123,
// stap 3); dat gebruikt deze functie niet meer, want daar staat het
// aanvragende subject al vast.
func (s *Store) OwnerUserID(ctx context.Context) (id.ID, error) {
	var uid id.ID
	err := s.pool.QueryRow(ctx, `SELECT id FROM users WHERE role = 'owner'`).Scan(&uid)
	if errors.Is(err, pgx.ErrNoRows) {
		return id.Nil, ErrNoOwner
	}
	if err != nil {
		return id.Nil, fmt.Errorf("owner-gebruiker lezen: %w", err)
	}
	return uid, nil
}

// UpdatePasswordHash herhasht bij een geslaagde login onder lichtere parameters.
//
// userID en niet "de owner": sinds stap 4 van PS-9 logt elke rij in users in,
// dus de herhash moet naar de gebruiker die zojuist inlogde en niet naar de
// enige die er vroeger was. users.password_hash is de bron van waarheid
// (DEC-119); auth_owner blijft ernaast bestaan als compatibiliteitstabel zolang
// LoadOwner er nog rechtstreeks uit leest (specificatie 6.5), en loopt daarom
// voor de owner in dezelfde transactie mee. Schrijf je alleen users, dan
// verifieert de volgende LoadOwner-lezing nog tegen de oude hash; schrijf je
// alleen auth_owner, dan is de leidende rij stil verouderd.
func (s *Store) UpdatePasswordHash(ctx context.Context, userID id.ID, hash string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var role Role
	err = tx.QueryRow(ctx, `SELECT role FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&role)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrUserNotFound
	}
	if err != nil {
		return fmt.Errorf("rol lezen voor herhash: %w", err)
	}

	if _, err := tx.Exec(ctx,
		`UPDATE users SET password_hash = $1, updated_at = now() WHERE id = $2`, hash, userID); err != nil {
		return fmt.Errorf("users.password_hash bijwerken: %w", err)
	}
	if role == RoleOwner {
		if _, err := tx.Exec(ctx,
			`UPDATE auth_owner SET password_hash = $1, updated_at = now() WHERE id = 1`, hash); err != nil {
			return fmt.Errorf("auth_owner.password_hash bijwerken: %w", err)
		}
	}
	return tx.Commit(ctx)
}

// StoreRefreshToken legt een uitgegeven refreshtoken vast, gebonden aan de
// sessie waarvoor hij is uitgegeven (DEC-123). Elke nieuwe rij draagt vanaf
// PS-9 een sessie; alleen historische rijen van vóór migratie 0007 kunnen er
// nog zonder zitten.
func (s *Store) StoreRefreshToken(ctx context.Context, hash []byte, sessionID id.ID, expiresAt time.Time) error {
	_, err := s.pool.Exec(ctx,
		`INSERT INTO auth_refresh_tokens (token_hash, expires_at, session_id) VALUES ($1, $2, $3)`,
		hash, expiresAt, sessionID)
	if err != nil {
		return fmt.Errorf("refreshtoken vastleggen: %w", err)
	}
	return nil
}

// CreateSession opent een nieuwe sessie voor een gebruiker (DEC-123).
//
// device_id is het PreferenceDeviceId van de client, of nil zonder de
// capability of zonder een ondersteunende client; device_name draagt dan een
// vaste plaatshouder in plaats van iets verzonnens.
func (s *Store) CreateSession(ctx context.Context, userID id.ID, deviceID *string, deviceName string, now time.Time) (id.ID, error) {
	sessionID := id.New()
	_, err := s.pool.Exec(ctx, `
		INSERT INTO sessions (id, user_id, device_id, device_name, created_at, last_seen_at)
		VALUES ($1, $2, $3, $4, $5, $5)`,
		sessionID, userID, deviceID, deviceName, now)
	if err != nil {
		return id.Nil, fmt.Errorf("sessie aanmaken: %w", err)
	}
	return sessionID, nil
}

// PurgeExpiredRefreshTokens ruimt op wat niemand meer kan gebruiken. Verlopen
// rijen laten staan levert een tabel op die alleen maar groeit en die de
// hergebruikdetectie niets extra's oplevert.
//
// Per sessie, met de sessie eerst, zoals elke andere schrijver van tokenrijen
// (lockSessionOfRefreshToken). Een rotatie houdt meerdere tokenrijen vast, en een
// herhaling binnen het respijt kijkt niet naar expires_at, dus één DELETE over de
// hele tabel kon ze in de omgekeerde volgorde nemen, ook via de wijzer in replaced_by.
// Een eigen transactie per sessie houdt bovendien niemands sessie langer vast dan
// het opruimen van die sessie duurt. Rijen zonder sessie heeft niemand op slot.
func (s *Store) PurgeExpiredRefreshTokens(ctx context.Context, before time.Time) (int64, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT DISTINCT session_id FROM auth_refresh_tokens WHERE expires_at < $1 AND session_id IS NOT NULL`, before)
	if err != nil {
		return 0, err
	}
	sessions, err := pgx.CollectRows(rows, pgx.RowTo[id.ID])
	if err != nil {
		return 0, err
	}

	var purged int64
	for _, sessionID := range sessions {
		n, err := s.purgeExpiredOfSession(ctx, sessionID, before)
		if err != nil {
			return purged, err
		}
		purged += n
	}
	tag, err := s.pool.Exec(ctx,
		`DELETE FROM auth_refresh_tokens WHERE expires_at < $1 AND session_id IS NULL`, before)
	if err != nil {
		return purged, err
	}
	return purged + tag.RowsAffected(), nil
}

func (s *Store) purgeExpiredOfSession(ctx context.Context, sessionID id.ID, before time.Time) (int64, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, `SELECT 1 FROM sessions WHERE id = $1 FOR NO KEY UPDATE`, sessionID); err != nil {
		return 0, fmt.Errorf("sessie vergrendelen voor opruimen: %w", err)
	}
	tag, err := tx.Exec(ctx,
		`DELETE FROM auth_refresh_tokens WHERE session_id = $1 AND expires_at < $2`, sessionID, before)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), tx.Commit(ctx)
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
