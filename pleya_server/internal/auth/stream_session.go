package auth

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// MaxActiveStreamSessions is de bovengrens uit DEC-051.
//
// Acht, en de negende wordt geweigerd in plaats van dat de oudste sneuvelt. De
// grens bestaat omdat een cookienaam per sessie niet ongelimiteerd schaalt:
// browsers begrenzen het aantal cookies per domein, en een lek van sessies zou
// die grens opsouperen. Hem afdwingen door te evicten zou iemand midden in een
// film afbreken, en dat is erger dan een geweigerde negende stream.
const MaxActiveStreamSessions = 8

// StreamCookiePrefix staat vóór de sessie-id in de cookienaam.
//
// De naam draagt de sessie, en dat is het hele punt van DEC-051: cookies met
// dezelfde naam, hetzelfde domein en hetzelfde pad vervangen elkaar, dus één
// vaste naam zou twee gelijktijdige streams elkaar laten breken.
const StreamCookiePrefix = "pleya_ss_"

// StreamCookiePath begrenst waar de cookie heen reist. Geen securitygrens; het
// beperkt alleen bij welke aanvragen hij meegaat.
const StreamCookiePath = "/pleya/v1/stream/"

// ErrStreamSessionLimit betekent dat er al acht actieve sessies zijn.
var ErrStreamSessionLimit = errors.New("te veel actieve streamsessies")

// ErrStreamSessionInvalid betekent dat de sessie niet bestaat, verlopen is,
// ingetrokken is, of niet bij dit subject of deze versie hoort.
var ErrStreamSessionInvalid = errors.New("streamsessie is ongeldig")

// StreamSession is wat de client terugkrijgt.
type StreamSession struct {
	ID        id.ID
	Secret    string
	ExpiresAt time.Time
}

// CookieName is de naam waaronder het geheim reist.
func (s StreamSession) CookieName() string { return StreamCookiePrefix + s.ID.String() }

// CreateStreamSession opent een sessie voor één subject en één versie.
//
// sid is de auth-sessie (DEC-069) waarvan dit verzoek werd gedaan; hij komt in
// stream_sessions.session_id te staan zodat intrekking van die sessie ook deze
// browserstreamsessie meeneemt.
//
// De volgorde is niet vrij. Eerst verlopen en ingetrokken sessies opruimen, dan
// pas tellen: anders weigert de server de negende terwijl er drie dood in de
// tabel staan. Beide stappen zitten in dezelfde transactie, zodat twee
// tabbladen die tegelijk beginnen niet allebei op zeven uitkomen.
func (s *Store) CreateStreamSession(ctx context.Context, subject id.ID, sid id.ID, versionID id.ID, ttl time.Duration, now time.Time) (StreamSession, error) {
	var out StreamSession

	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return out, fmt.Errorf("streamsessie genereren: %w", err)
	}
	secret := base64.RawURLEncoding.EncodeToString(raw)

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return out, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx,
		`DELETE FROM stream_sessions WHERE subject = $1 AND (expires_at <= $2 OR revoked_at IS NOT NULL)`,
		subject, now); err != nil {
		return out, err
	}

	var active int
	if err := tx.QueryRow(ctx,
		`SELECT count(*) FROM stream_sessions WHERE subject = $1 AND revoked_at IS NULL AND expires_at > $2`,
		subject, now).Scan(&active); err != nil {
		return out, err
	}
	if active >= MaxActiveStreamSessions {
		return out, fmt.Errorf("%w: %d actief", ErrStreamSessionLimit, active)
	}

	sessionID := id.New()
	expires := now.Add(ttl)
	if _, err := tx.Exec(ctx, `
		INSERT INTO stream_sessions (id, subject, version_id, secret_hash, created_at, expires_at, session_id)
		VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		sessionID, subject, versionID, HashOpaque(secret), now, expires, sid); err != nil {
		return out, err
	}
	if err := tx.Commit(ctx); err != nil {
		return out, err
	}

	return StreamSession{ID: sessionID, Secret: secret, ExpiresAt: expires}, nil
}

// VerifyStreamSession controleert de vijf dingen uit DEC-051: de sessie bestaat,
// het geheim klopt in een constant-time vergelijking, het subject klopt, de
// binding aan de versie klopt, en hij is niet verlopen of ingetrokken.
//
// Het geheim staat niet in de database; er staat een SHA-256 van, net als bij een
// refreshtoken. Een databasedump levert dus geen speelbare sessies op.
func (s *Store) VerifyStreamSession(ctx context.Context, sessionID id.ID, secret string, subject id.ID, versionID id.ID, now time.Time) error {
	var storedHash []byte
	var storedSubject id.ID
	var storedVersion id.ID
	var expiresAt time.Time
	var revokedAt *time.Time

	err := s.pool.QueryRow(ctx, `
		SELECT secret_hash, subject, version_id, expires_at, revoked_at
		FROM stream_sessions WHERE id = $1`, sessionID).
		Scan(&storedHash, &storedSubject, &storedVersion, &expiresAt, &revokedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrStreamSessionInvalid
	}
	if err != nil {
		return err
	}

	// De geheimvergelijking gaat als eerste en altijd, ook wanneer een van de
	// andere velden al niet klopt. Vroeg uitstappen zou het verschil tussen "de
	// sessie bestaat, het geheim niet" en "de sessie bestaat niet" meetbaar maken
	// in de tijd.
	ok := subtle.ConstantTimeCompare(storedHash, HashOpaque(secret)) == 1
	if !ok || storedSubject != subject || storedVersion != versionID ||
		revokedAt != nil || !now.Before(expiresAt) {
		return ErrStreamSessionInvalid
	}
	return nil
}

// TouchStreamSession verlengt één sessie en zet alleen die ene opnieuw.
//
// Verlengen per sessie is de reden dat het model werkt: twee gelijktijdige
// streams roteren onafhankelijk, en het verlengen van de een raakt de ander niet.
func (s *Store) TouchStreamSession(ctx context.Context, sessionID id.ID, ttl time.Duration, now time.Time) (time.Time, error) {
	expires := now.Add(ttl)
	_, err := s.pool.Exec(ctx,
		`UPDATE stream_sessions SET expires_at = $2, last_used_at = $3
		 WHERE id = $1 AND revoked_at IS NULL`, sessionID, expires, now)
	return expires, err
}

// RevokeStreamSession sluit één sessie. Het vangnet voor een tabblad dat hard
// verdwijnt is de TTL; dit is de beleefde weg.
func (s *Store) RevokeStreamSession(ctx context.Context, sessionID id.ID, now time.Time) error {
	_, err := s.pool.Exec(ctx,
		`UPDATE stream_sessions SET revoked_at = $2 WHERE id = $1 AND revoked_at IS NULL`,
		sessionID, now)
	return err
}

// ActiveStreamSessions telt wat er nu open staat. Voor tests en voor de
// foutdetails bij een geweigerde negende.
func (s *Store) ActiveStreamSessions(ctx context.Context, subject id.ID, now time.Time) (int, error) {
	var n int
	err := s.pool.QueryRow(ctx,
		`SELECT count(*) FROM stream_sessions WHERE subject = $1 AND revoked_at IS NULL AND expires_at > $2`,
		subject, now).Scan(&n)
	return n, err
}
