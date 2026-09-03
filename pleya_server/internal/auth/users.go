package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Gebruikersbeheer, stap 4 van de PS-9-implementatievolgorde (hoofdstuk 23,
// fase 9). De vijf endpoints eromheen staan in DEC-067; de rollen en de
// rechtenladder in DEC-065.
//
// Waarom dit in internal/auth staat en niet in internal/catalog, terwijl
// library_permissions daar gelezen wordt: DEC-065 §2 zet precies twee
// rechtenfuncties in de catalogus, VisibleLibraries en MayAccess, en die gaan
// over autoriseren. Rijen aanmaken en vervangen is gebruikersbeheer en hoort
// bij de identiteit, niet bij de catalogus. De scheiding is lezen-om-te-
// autoriseren tegenover schrijven-om-te-beheren; de tabel is dezelfde, de vraag
// niet.

// ErrUsernameTaken betekent dat users.username al bestaat.
var ErrUsernameTaken = errors.New("die gebruikersnaam is al in gebruik")

// ErrOwnerImmutable betekent dat de aanvraag de owner wilde degraderen of
// verwijderen. De partiële unieke index uit migratie 0007 dekt "twee owners";
// deze fout dekt de andere kant, en die kan een index niet zien.
var ErrOwnerImmutable = errors.New("de owner kan niet verwijderd of gedegradeerd worden")

// ErrLibraryNotFound betekent dat een library_id uit een rechtenlijst niet
// bestaat. Komt uit de foreign key en niet uit een controle vooraf: tussen de
// controle en de INSERT kan een bibliotheek verdwijnen, en dan is de FK de
// enige die het nog ziet.
var ErrLibraryNotFound = errors.New("bibliotheek bestaat niet")

// ErrRestrictedCannotManage is de trigger uit migratie 0007 (DEC-065 §3).
var ErrRestrictedCannotManage = errors.New("restricted mag geen manage krijgen")

// User is de identiteit zoals gebruikersbeheer hem kent. Zonder hash: die komt
// alleen bij het inloggen langs, via UserForLogin.
type User struct {
	ID       id.ID
	Username string
	Role     Role
}

// LibraryPermission is één trede van de ladder voor één bibliotheek.
type LibraryPermission struct {
	LibraryID  id.ID
	Permission string
}

// ValidRole zegt of s een van de vier rollen is.
func ValidRole(s string) bool {
	switch Role(s) {
	case RoleOwner, RoleAdmin, RoleMember, RoleRestricted:
		return true
	}
	return false
}

// ValidPermission zegt of s een trede van de ladder is.
func ValidPermission(s string) bool {
	return s == "view" || s == "download" || s == "manage"
}

// isUnique zegt of err de unieke index op users.username schond.
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

// CreateUser legt een nieuwe gebruiker vast.
//
// role mag hier nooit owner zijn; die rol ontstaat uitsluitend via /auth/setup
// (specificatie 16.3). De handler weigert dat al, maar de partiële unieke index
// uit migratie 0007 is het vangnet dat ook een tweede pad zou tegenhouden.
func (s *Store) CreateUser(ctx context.Context, username, passwordHash string, role Role, now time.Time) (User, error) {
	uid := id.New()
	_, err := s.pool.Exec(ctx, `
		INSERT INTO users (id, username, password_hash, role, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $5)`, uid, username, passwordHash, role, now)
	if isUniqueViolation(err) {
		return User{}, ErrUsernameTaken
	}
	if err != nil {
		return User{}, fmt.Errorf("gebruiker aanmaken: %w", err)
	}
	return User{ID: uid, Username: username, Role: role}, nil
}

// ListUsers geeft iedereen, oplopend op aanmaakmoment zodat de owner vooraan
// staat. Het filteren voor member en restricted gebeurt in de handler: dat is
// autorisatiebeleid (matrixregel 14) en geen opslagvraag.
func (s *Store) ListUsers(ctx context.Context) ([]User, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT id, username, role FROM users ORDER BY created_at, id`)
	if err != nil {
		return nil, fmt.Errorf("gebruikers lezen: %w", err)
	}
	defer rows.Close()

	users := []User{}
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Username, &u.Role); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, rows.Err()
}

// GetUser leest één gebruiker.
func (s *Store) GetUser(ctx context.Context, userID id.ID) (User, error) {
	var u User
	err := s.pool.QueryRow(ctx,
		`SELECT id, username, role FROM users WHERE id = $1`, userID).
		Scan(&u.ID, &u.Username, &u.Role)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrUserNotFound
	}
	if err != nil {
		return User{}, fmt.Errorf("gebruiker lezen: %w", err)
	}
	return u, nil
}

// UserForLogin zoekt op gebruikersnaam en geeft de hash mee.
//
// De enige plek waar password_hash de opslag verlaat. Een onbekende naam geeft
// ErrUserNotFound; de handler zet dat om in dezelfde
// auth.invalid_credentials als een fout wachtwoord, want anders verraadt het
// antwoord welke namen bestaan.
func (s *Store) UserForLogin(ctx context.Context, username string) (User, string, error) {
	var u User
	var hash string
	err := s.pool.QueryRow(ctx,
		`SELECT id, username, role, password_hash FROM users WHERE username = $1`, username).
		Scan(&u.ID, &u.Username, &u.Role, &hash)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, "", ErrUserNotFound
	}
	if err != nil {
		return User{}, "", fmt.Errorf("gebruiker voor login lezen: %w", err)
	}
	return u, hash, nil
}

// UpdateUser zet rol, wachtwoord, of beide. Een nil-veld blijft ongemoeid.
//
// De owner degraderen wordt hier geweigerd en niet aan de database overgelaten:
// de partiële unieke index laat nul owners toe, dus zonder deze controle zou
// een installatie stil zonder owner kunnen komen te staan.
func (s *Store) UpdateUser(ctx context.Context, userID id.ID, role *Role, passwordHash *string, now time.Time) (User, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return User{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var current Role
	var username string
	err = tx.QueryRow(ctx,
		`SELECT role, username FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&current, &username)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrUserNotFound
	}
	if err != nil {
		return User{}, fmt.Errorf("gebruiker vergrendelen: %w", err)
	}

	next := current
	if role != nil {
		if current == RoleOwner && *role != RoleOwner {
			return User{}, ErrOwnerImmutable
		}
		if current != RoleOwner && *role == RoleOwner {
			// Promoveren tot owner is geen rolwijziging maar een
			// eigendomsoverdracht, en die kent PS-9 niet. De index zou hem ook
			// weigeren; deze controle geeft er een leesbare fout bij.
			return User{}, ErrOwnerImmutable
		}
		next = *role
		if _, err := tx.Exec(ctx,
			`UPDATE users SET role = $1, updated_at = $2 WHERE id = $3`, next, now, userID); err != nil {
			return User{}, fmt.Errorf("rol bijwerken: %w", err)
		}
		// Een gebruiker die restricted wordt mag geen manage meer dragen. De
		// trigger uit migratie 0007 kijkt alleen naar INSERT en UPDATE op
		// library_permissions, dus een rol die de andere kant op beweegt komt
		// daar nooit langs. Zonder deze regel houdt een gedegradeerde gebruiker
		// stilzwijgend een recht dat zijn rol verbiedt.
		if next == RoleRestricted {
			if _, err := tx.Exec(ctx, `
				UPDATE library_permissions SET permission = 'download'
				WHERE user_id = $1 AND permission = 'manage'`, userID); err != nil {
				return User{}, fmt.Errorf("manage terugzetten na degradatie: %w", err)
			}
		}
	}

	if passwordHash != nil {
		if _, err := tx.Exec(ctx,
			`UPDATE users SET password_hash = $1, updated_at = $2 WHERE id = $3`,
			*passwordHash, now, userID); err != nil {
			return User{}, fmt.Errorf("wachtwoord bijwerken: %w", err)
		}
		// auth_owner blijft de compatibiliteitstabel achter LoadOwner
		// (specificatie 6.5), dus de owner-hash moet daar meelopen; zie
		// UpdatePasswordHash voor dezelfde redenering.
		if current == RoleOwner {
			if _, err := tx.Exec(ctx,
				`UPDATE auth_owner SET password_hash = $1, updated_at = $2 WHERE id = 1`,
				*passwordHash, now); err != nil {
				return User{}, fmt.Errorf("auth_owner-wachtwoord bijwerken: %w", err)
			}
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return User{}, err
	}
	return User{ID: userID, Username: username, Role: next}, nil
}

// DeleteUser verwijdert een gebruiker. De owner wordt geweigerd.
//
// Alles wat aan de gebruiker hangt gaat mee via ON DELETE CASCADE uit migratie
// 0007: sessies, refreshtokens (via sessions), kijkstatus, browserstreamsessies
// en bibliotheekrechten. Dat staat bewust in het schema en niet hier: een
// opsomming in Go loopt uit de pas zodra er een tabel bijkomt.
func (s *Store) DeleteUser(ctx context.Context, userID id.ID) error {
	var role Role
	err := s.pool.QueryRow(ctx, `SELECT role FROM users WHERE id = $1`, userID).Scan(&role)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrUserNotFound
	}
	if err != nil {
		return fmt.Errorf("rol lezen voor verwijderen: %w", err)
	}
	if role == RoleOwner {
		return ErrOwnerImmutable
	}
	if _, err := s.pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, userID); err != nil {
		return fmt.Errorf("gebruiker verwijderen: %w", err)
	}
	return nil
}

// ListPermissions geeft de bibliotheekrechten van een gebruiker.
//
// Voor owner en admin is dat altijd leeg, en dat is geen bug: hun toegang volgt
// uit de rol en niet uit rijen (DEC-065 §2).
func (s *Store) ListPermissions(ctx context.Context, userID id.ID) ([]LibraryPermission, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT library_id, permission FROM library_permissions
		WHERE user_id = $1 ORDER BY library_id`, userID)
	if err != nil {
		return nil, fmt.Errorf("bibliotheekrechten lezen: %w", err)
	}
	defer rows.Close()

	perms := []LibraryPermission{}
	for rows.Next() {
		var p LibraryPermission
		if err := rows.Scan(&p.LibraryID, &p.Permission); err != nil {
			return nil, err
		}
		perms = append(perms, p)
	}
	return perms, rows.Err()
}

// SetPermissions vervangt de volledige rechtenlijst van een gebruiker.
//
// Vervangen en niet samenvoegen, zoals PUT belooft: wie een recht weghaalt doet
// dat door het niet meer mee te sturen. In één transactie, want een lijst die
// halverwege blijft steken laat een gebruiker met minder rechten achter dan
// beide kanten bedoelden.
func (s *Store) SetPermissions(ctx context.Context, userID id.ID, perms []LibraryPermission) error {
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
		return fmt.Errorf("gebruiker vergrendelen: %w", err)
	}

	if _, err := tx.Exec(ctx, `DELETE FROM library_permissions WHERE user_id = $1`, userID); err != nil {
		return fmt.Errorf("bestaande rechten verwijderen: %w", err)
	}

	for _, p := range perms {
		_, err := tx.Exec(ctx, `
			INSERT INTO library_permissions (user_id, library_id, permission)
			VALUES ($1, $2, $3)`, userID, p.LibraryID, p.Permission)
		if err != nil {
			var pgErr *pgconn.PgError
			switch {
			case errors.As(err, &pgErr) && pgErr.Code == "23503":
				return ErrLibraryNotFound
			case errors.As(err, &pgErr) && pgErr.Code == "23514":
				// De trigger uit migratie 0007. Dat de rol restricted is weten we
				// hier ook zelf, maar de trigger is de bron: hij dekt ook een pad
				// dat deze functie niet ziet.
				return ErrRestrictedCannotManage
			default:
				return fmt.Errorf("bibliotheekrecht vastleggen: %w", err)
			}
		}
	}
	return tx.Commit(ctx)
}
