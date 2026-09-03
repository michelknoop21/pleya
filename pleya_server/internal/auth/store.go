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

// Role is de waarde van users.role. Vier stuks (migratie 0007, DEC-065): owner
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
// stream_sessions.subject zijn nu een echte FK naar users(id) (DEC-065) en
// accepteren die string niet meer. Elders (handlers_watch.go, authorize.go)
// loopt Claims.Subject inmiddels rechtstreeks door de context (DEC-069,
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
// (DEC-065); auth_owner blijft ernaast bestaan als compatibiliteitstabel zolang
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
// sessie waarvoor hij is uitgegeven (DEC-069). Elke nieuwe rij draagt vanaf
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

// CreateSession opent een nieuwe sessie voor een gebruiker (DEC-069).
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
	// RefreshReplayed: dit token is net geroteerd, maar zijn opvolger is nooit
	// gebruikt. Dat is de vingerafdruk van een verloren antwoord, niet van een
	// aanvaller: wie het antwoord wél ontving zou de opvolger uitgeven, niet
	// het oude token. De nooit-geziene opvolger wordt ingetrokken en de
	// aanvrager krijgt een verse rotatie.
	RefreshReplayed
	// RefreshSessionRevoked: het token zelf was nog geldig, maar de sessie
	// waarbij het hoort is ingetrokken (DEC-069). Vóór stap 6 (het
	// intrekkingsendpoint) kan dit nog niet voorkomen; de controle hoort in
	// dezelfde commit als het schema thuis, niet in een opruimronde erna.
	RefreshSessionRevoked
)

// RotateRefreshToken wisselt een refreshtoken in.
//
// Het oude vervalt onmiddellijk en het nieuwe komt ervoor in de plaats, in
// dezelfde transactie, met replaced_by als wijzer naar de opvolger. Komt een
// al gebruikt token terug, dan zijn er twee gevallen. Is de opvolger nooit
// gebruikt en ligt de rotatie korter dan [grace] terug, dan is dit de
// herhaling van een antwoord dat de client nooit bereikte: de intrekking van
// dat antwoord is voor beide partijen onzichtbaar geweest, dus de
// nooit-geziene opvolger gaat eruit en de aanvrager krijgt een verse rotatie
// (RefreshReplayed). Alles daarbuiten — een gebruikte opvolger, of een
// herhaling buiten het venster — trekt de refreshketens van DIE SESSIE in
// (DEC-069): sessie-scoped sinds PS-9, want zonder apparaatkolom zou
// hergebruik door één toestel elk toestel van dezelfde gebruiker uitloggen.
//
// Het venster rekt niet op: revoked_at van het oude token blijft de
// oorspronkelijke rotatie, dus herhalingen zijn alleen mogelijk binnen
// [grace] van dat ene moment.
//
// Geeft naast de uitkomst de sid en de gebruiker van de sessie terug waarbij
// dit token hoort, zodat de aanroeper het volgende accesstoken met dezelfde
// sid kan minten. Alleen betekenisvol bij RefreshOK en RefreshReplayed.
func (s *Store) RotateRefreshToken(ctx context.Context, oldHash, newHash []byte, newExpires, now time.Time, grace time.Duration) (RefreshOutcome, id.ID, id.ID, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var expiresAt time.Time
	var revokedAt *time.Time
	var replacedBy []byte
	var sessionID *id.ID
	var sessionRevokedAt *time.Time
	var userID *id.ID
	err = tx.QueryRow(ctx, `
		SELECT rt.expires_at, rt.revoked_at, rt.replaced_by, rt.session_id, s.revoked_at, s.user_id
		FROM auth_refresh_tokens rt
		LEFT JOIN sessions s ON s.id = rt.session_id
		WHERE rt.token_hash = $1
		FOR UPDATE OF rt`,
		oldHash).Scan(&expiresAt, &revokedAt, &replacedBy, &sessionID, &sessionRevokedAt, &userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return RefreshUnknown, id.Nil, id.Nil, nil
	}
	if err != nil {
		return RefreshUnknown, id.Nil, id.Nil, fmt.Errorf("refreshtoken lezen: %w", err)
	}

	if revokedAt != nil {
		if replacedBy != nil && grace > 0 && now.Sub(*revokedAt) <= grace {
			outcome, sid, uid, err := s.replayLostRotation(ctx, tx, oldHash, replacedBy, newHash, newExpires, now, sessionID)
			if err != nil || outcome == RefreshReplayed {
				return outcome, sid, uid, err
			}
			// De opvolger blijkt wél gebruikt: door naar de intrekking.
		}
		// IS NOT DISTINCT FROM: een historische rij van vóór migratie 0007 kan
		// nog session_id NULL dragen, en dan is "dezelfde sessie" ook NULL = NULL.
		if _, err := tx.Exec(ctx,
			`UPDATE auth_refresh_tokens SET revoked_at = $1
			 WHERE revoked_at IS NULL AND session_id IS NOT DISTINCT FROM $2`,
			now, sessionID); err != nil {
			return RefreshUnknown, id.Nil, id.Nil, err
		}
		if err := tx.Commit(ctx); err != nil {
			return RefreshUnknown, id.Nil, id.Nil, err
		}
		return RefreshReused, id.Nil, id.Nil, nil
	}
	if now.After(expiresAt) {
		return RefreshExpired, id.Nil, id.Nil, nil
	}
	if sessionRevokedAt != nil {
		return RefreshSessionRevoked, id.Nil, id.Nil, nil
	}
	if sessionID == nil || userID == nil {
		return RefreshUnknown, id.Nil, id.Nil, fmt.Errorf("refreshtoken zonder sessie kan niet roteren")
	}

	if _, err := tx.Exec(ctx,
		`UPDATE auth_refresh_tokens SET revoked_at = $1 WHERE token_hash = $2`, now, oldHash); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO auth_refresh_tokens (token_hash, expires_at, session_id) VALUES ($1, $2, $3)`,
		newHash, newExpires, *sessionID); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE auth_refresh_tokens SET replaced_by = $1 WHERE token_hash = $2`, newHash, oldHash); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE sessions SET last_seen_at = $1 WHERE id = $2`, now, *sessionID); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	return RefreshOK, *sessionID, *userID, nil
}

// replayLostRotation handelt de herhaling van een verloren rotatie-antwoord af.
//
// De server bewaart alleen hashes, dus de opvolger die de client nooit zag is
// niet opnieuw uit te geven: hij wordt ingetrokken en [newHash] komt ervoor in
// de plaats, met replaced_by van het oude token doorgeschoven zodat een
// volgende herhaling binnen hetzelfde venster opnieuw herkenbaar is. Geeft
// (RefreshReused, ...) zonder te committen wanneer de opvolger wél gebruikt
// blijkt; de aanroeper voert dan de ketenintrekking uit.
func (s *Store) replayLostRotation(ctx context.Context, tx pgx.Tx, oldHash, successorHash, newHash []byte, newExpires, now time.Time, sessionID *id.ID) (RefreshOutcome, id.ID, id.ID, error) {
	var succRevoked *time.Time
	var succReplaced []byte
	var userID *id.ID
	err := tx.QueryRow(ctx, `
		SELECT rt.revoked_at, rt.replaced_by, s.user_id
		FROM auth_refresh_tokens rt
		LEFT JOIN sessions s ON s.id = rt.session_id
		WHERE rt.token_hash = $1
		FOR UPDATE OF rt`,
		successorHash).Scan(&succRevoked, &succReplaced, &userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return RefreshReused, id.Nil, id.Nil, nil
	}
	if err != nil {
		return RefreshUnknown, id.Nil, id.Nil, fmt.Errorf("opvolger lezen: %w", err)
	}
	// Een ingetrokken of doorgeroteerde opvolger is bij de client aangekomen,
	// dus het oude token in deze aanvraag is echt hergebruik.
	if succRevoked != nil || succReplaced != nil {
		return RefreshReused, id.Nil, id.Nil, nil
	}
	if sessionID == nil || userID == nil {
		return RefreshUnknown, id.Nil, id.Nil, fmt.Errorf("refreshtoken zonder sessie kan niet herhalen")
	}

	if _, err := tx.Exec(ctx,
		`UPDATE auth_refresh_tokens SET revoked_at = $1 WHERE token_hash = $2`, now, successorHash); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO auth_refresh_tokens (token_hash, expires_at, session_id) VALUES ($1, $2, $3)`,
		newHash, newExpires, *sessionID); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE auth_refresh_tokens SET replaced_by = $1 WHERE token_hash = $2`, newHash, oldHash); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE sessions SET last_seen_at = $1 WHERE id = $2`, now, *sessionID); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	return RefreshReplayed, *sessionID, *userID, nil
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
