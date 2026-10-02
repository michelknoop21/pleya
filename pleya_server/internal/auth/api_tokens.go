package auth

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// API-tokens zijn sessies (RB-20, J.2 rij 12 en 13).
//
// Een agent kan de refreshflow niet lopen: die vraagt een client die een
// antwoord bewaart, opnieuw aanbiedt en op een rotatie reageert. Wat een agent
// wel kan is één bearer meesturen. Dat token is hier een gewone rij in
// `sessions` met `kind = 'api'`, en dat is de hele architectuurkeuze: er is
// één intrekkingspad, één register, één overzicht. Een apart tokenmodel ernaast
// zou twee intrekkingspaden opleveren, en dan is de vraag "is dit credential
// nog geldig" op twee plekken te beantwoorden en op één plek te vergeten.
//
// Wat er van dat token in de database staat is de SHA-256 ervan, net als bij
// een refreshtoken: een databasedump levert geen bruikbaar token op.

// APITokenPrefix staat vooraan in elk uitgegeven geheim.
//
// Twee redenen, en geen ervan is cosmetisch. De eerste is dat authenticated()
// zonder gokken weet welk van de twee verificatiepaden hij moet lopen: een
// accesstoken begint met `ply1.` en wordt met de sleutel geverifieerd, dit
// begint met `plyat1_` en wordt op zijn hash opgezocht. Zonder dat onderscheid
// zou elke mislukte handtekeningcontrole een databaseronde uitlokken, en dan is
// een stroom onzin-tokens een gratis query per aanvraag. De tweede is dat een
// herkenbaar voorvoegsel een geheim vindbaar maakt in een logbestand, een
// repository of een screenshot; dat is precies waar een langlevend token
// belandt.
const APITokenPrefix = "plyat1_"

// APITokenScope is het bereik van een API-token (J.2 rij 12).
//
// Een ladder en geen verzameling: `read` kan minder dan `maintenance`, dat weer
// minder kan dan `admin`. De waarde staat in `sessions.scope` en wordt per
// aanvraag gelezen, net als de rol, zodat een verlaagd bereik niet pas ingaat
// wanneer een token verloopt.
type APITokenScope string

const (
	// APIScopeRead mag lezen wat de eigenaar mag lezen, en niets beheren.
	APIScopeRead APITokenScope = "read"
	// APIScopeMaintenance is gereserveerd voor de operationele handelingen die
	// S25 maakt (back-up, onderhoudsmodus, herstel). Vandaag bestaat geen enkele
	// operatie die hem van `read` onderscheidt, en dat staat hier expliciet in
	// plaats van dat het gedrag het stilzwijgend suggereert.
	APIScopeMaintenance APITokenScope = "maintenance"
	// APIScopeAdmin haalt de adminklasse, mits de rol van de eigenaar dat ook
	// doet.
	APIScopeAdmin APITokenScope = "admin"
)

// APITokenScopes is de volgorde van de ladder, laag naar hoog.
var APITokenScopes = []APITokenScope{APIScopeRead, APIScopeMaintenance, APIScopeAdmin}

// ParseAPITokenScope leest een bereik uit de aanvraag.
func ParseAPITokenScope(raw string) (APITokenScope, bool) {
	for _, s := range APITokenScopes {
		if string(s) == raw {
			return s, true
		}
	}
	return "", false
}

// ScopeWithinRole is K rij 22 in één functie: het bereik komt nooit boven de
// rol van de eigenaar uit.
//
// De vertaling is de autorisatiematrix zelf. `admin` is de adminklasse, en die
// halen alleen owner en admin (specificatie 16.1). `maintenance` en `read`
// vragen niets wat een gewone gebruiker niet al heeft, dus die staan voor elke
// rol open; wat zo'n token mag blijft begrensd door de rechten van de eigenaar,
// en die worden per aanvraag opnieuw gelezen.
func ScopeWithinRole(scope APITokenScope, role Role) bool {
	if scope == APIScopeAdmin {
		return role == RoleOwner || role == RoleAdmin
	}
	return true
}

// DefaultAPITokenDays is de standaardgeldigheid uit RB-20.
//
// Niet "nooit". Een token zonder vervaldatum is de vorm die jaren later nog in
// een oude configuratie meeloopt en die niemand mist tot iemand hem vindt.
const DefaultAPITokenDays = 90

// MaxAPITokenDays is de bovengrens die de aanvraag mag noemen.
//
// Tien jaar is geen beveiligingsgrens maar een leesbaarheidsgrens: hij vangt
// een tikfout in `expires_in_days` af voordat die een token oplevert dat de
// server overleeft.
const MaxAPITokenDays = 3650

// APIToken is één token in het overzicht. Het geheim staat er niet in; dat
// bestaat na het aanmaken alleen nog bij de aanvrager (J.2 rij 13).
type APIToken struct {
	ID         id.ID
	UserID     id.ID
	Name       string
	Scope      APITokenScope
	CreatedAt  time.Time
	LastSeenAt time.Time
	ExpiresAt  time.Time
}

// APITokenIdentity is wat een geldig API-token over zijn drager zegt.
type APITokenIdentity struct {
	SessionID id.ID
	UserID    id.ID
	Scope     APITokenScope
	ExpiresAt time.Time
}

var (
	// ErrAPITokenInvalid betekent dat dit geheim geen levend token is: nooit
	// uitgegeven, of ingetrokken.
	ErrAPITokenInvalid = errors.New("api-token bestaat niet of is ingetrokken")
	// ErrAPITokenExpired betekent dat het token bestond en over zijn datum is.
	ErrAPITokenExpired = errors.New("api-token is verlopen")
)

// NewAPITokenSecret genereert een geheim en zijn opslagvorm.
func NewAPITokenSecret() (secret string, hash []byte, err error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", nil, fmt.Errorf("api-token genereren: %w", err)
	}
	secret = APITokenPrefix + base64.RawURLEncoding.EncodeToString(raw)
	return secret, HashOpaque(secret), nil
}

// LooksLikeAPIToken zegt of dit geheim de vorm van een API-token heeft.
func LooksLikeAPIToken(token string) bool {
	return strings.HasPrefix(token, APITokenPrefix)
}

// CreateAPIToken legt een nieuw token vast en geeft het geheim één keer terug.
//
// De rij gaat in `sessions` en niet in een eigen tabel: `device_name` draagt de
// naam die de beheerder gaf, `expires_at` de vervaldatum, en `token_hash` het
// enige dat de server van het geheim bewaart. Daarmee valt het token onder
// DELETE /sessions/{id}, onder het intrekkingsregister en onder het overzicht
// van ingelogde toestellen, zonder dat een van die drie iets over API-tokens
// hoeft te weten.
func (s *Store) CreateAPIToken(ctx context.Context, userID id.ID, name string, scope APITokenScope, expiresAt, now time.Time) (APIToken, string, error) {
	secret, hash, err := NewAPITokenSecret()
	if err != nil {
		return APIToken{}, "", err
	}

	token := APIToken{
		ID:         id.New(),
		UserID:     userID,
		Name:       name,
		Scope:      scope,
		CreatedAt:  now,
		LastSeenAt: now,
		ExpiresAt:  expiresAt,
	}
	if _, err := s.pool.Exec(ctx, `
		INSERT INTO sessions (id, user_id, device_id, device_name, created_at, last_seen_at, kind, scope, token_hash, expires_at)
		VALUES ($1, $2, NULL, $3, $4, $4, 'api', $5, $6, $7)`,
		token.ID, userID, name, now, string(scope), hash, expiresAt); err != nil {
		return APIToken{}, "", fmt.Errorf("api-token vastleggen: %w", err)
	}
	return token, secret, nil
}

// ListAPITokens geeft de levende API-tokens van één gebruiker.
//
// Verlopen tokens staan er niet in, net zomin als ingetrokken sessies in
// ListSessions staan: het overzicht beantwoordt "wat kan er nu met mijn account
// praten", en een rij die op zijn eerstvolgende aanvraag 401 geeft maakt die
// vraag alleen moeilijker.
func (s *Store) ListAPITokens(ctx context.Context, userID id.ID, now time.Time) ([]APIToken, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, user_id, device_name, scope, created_at, last_seen_at, expires_at
		FROM sessions
		WHERE user_id = $1 AND kind = 'api' AND revoked_at IS NULL
		  AND (expires_at IS NULL OR expires_at > $2)
		ORDER BY created_at, id`, userID, now)
	if err != nil {
		return nil, fmt.Errorf("api-tokens lezen: %w", err)
	}
	defer rows.Close()

	tokens := []APIToken{}
	for rows.Next() {
		var t APIToken
		var scope *string
		var expires *time.Time
		if err := rows.Scan(&t.ID, &t.UserID, &t.Name, &scope, &t.CreatedAt, &t.LastSeenAt, &expires); err != nil {
			return nil, err
		}
		if scope != nil {
			t.Scope = APITokenScope(*scope)
		}
		if expires != nil {
			t.ExpiresAt = *expires
		}
		tokens = append(tokens, t)
	}
	return tokens, rows.Err()
}

// VerifyAPIToken zoekt het geheim op zijn hash op en zegt wie hem draagt.
//
// Drie voorwaarden, en alle drie in de query: de rij bestaat, hij is niet
// ingetrokken, en hij is niet verlopen. De intrekking staat hier én in het
// register: het register geeft de garantie van twee seconden zonder
// databaseronde, deze query overleeft een herstart van het proces. Het verschil
// telt, want een register in het geheugen is na een herstart leeg terwijl
// `revoked_at` blijft staan.
//
// Het onderscheid tussen "bestaat niet" en "verlopen" blijft binnen de server.
// De handler vertaalt allebei naar auth.token_invalid: een drager die het
// verschil kan meten, kan raden welke geheimen ooit bestaan hebben.
func (s *Store) VerifyAPIToken(ctx context.Context, secret string, now time.Time) (APITokenIdentity, error) {
	var out APITokenIdentity
	var scope *string
	var expires *time.Time
	var revoked *time.Time

	err := s.pool.QueryRow(ctx, `
		SELECT id, user_id, scope, expires_at, revoked_at
		FROM sessions WHERE token_hash = $1 AND kind = 'api'`, HashOpaque(secret)).
		Scan(&out.SessionID, &out.UserID, &scope, &expires, &revoked)
	if errors.Is(err, pgx.ErrNoRows) {
		return out, ErrAPITokenInvalid
	}
	if err != nil {
		return out, fmt.Errorf("api-token opzoeken: %w", err)
	}
	if revoked != nil {
		return out, ErrAPITokenInvalid
	}
	if expires != nil {
		out.ExpiresAt = *expires
		if !expires.After(now) {
			return out, ErrAPITokenExpired
		}
	}
	if scope != nil {
		out.Scope = APITokenScope(*scope)
	}
	return out, nil
}
