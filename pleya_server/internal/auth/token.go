package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

// TokenType onderscheidt de drie soorten die het protocol uitgeeft.
type TokenType string

const (
	// TokenAccess gaat mee in de Authorization-header, nooit in een querystring.
	TokenAccess TokenType = "access"
	// TokenStream is de enige uitzondering daarop: externe spelers kunnen geen
	// header zetten. Kortlevend, gebonden aan één mediaresource, en zonder enig
	// recht op de rest van de API (specificatie 6.4).
	TokenStream TokenType = "stream"
)

// tokenPrefix maakt het formaat herkenbaar en versienbaar. Een token uit een
// ander schema valt daarmee af voordat er iets ontleed wordt.
const tokenPrefix = "ply1"

var (
	// ErrTokenMalformed betekent dat het token niet de vorm van dit schema heeft.
	ErrTokenMalformed = errors.New("token is onleesbaar")
	// ErrTokenSignature betekent dat de handtekening niet klopt.
	ErrTokenSignature = errors.New("handtekening klopt niet")
	// ErrTokenExpired betekent dat het token verlopen is.
	ErrTokenExpired = errors.New("token is verlopen")
)

// Claims is de inhoud van een token.
//
// Klein gehouden met opzet. Een accesstoken hoeft niets te dragen behalve wie
// hij is en tot wanneer; een streamtoken daarnaast één resource, want hij mag
// niets anders openen.
type Claims struct {
	Subject   string    `json:"sub"`
	Type      TokenType `json:"typ"`
	IssuedAt  int64     `json:"iat"`
	ExpiresAt int64     `json:"exp"`
	Resource  string    `json:"res,omitempty"`
}

// Signer ondertekent en verifieert tokens met HMAC-SHA256.
//
// Geen JWT-bibliotheek. Het formaat is vast, er is één algoritme, en daarmee
// bestaat de hele klasse fouten rond een alg-veld dat de aanvaller kiest hier
// niet. Wat een JWT verder biedt (meerdere algoritmes, sleutelrotatie via een
// header, een publieke verificatiesleutel) heeft deze server niet nodig.
type Signer struct {
	key []byte
	now func() time.Time
}

// NewSigner bouwt een ondertekenaar rond de sleutel.
func NewSigner(key []byte) (*Signer, error) {
	if len(key) < 32 {
		return nil, fmt.Errorf("ondertekensleutel is %d bytes; minimaal 32 nodig", len(key))
	}
	return &Signer{key: key, now: time.Now}, nil
}

// SetClock laat een test de tijd bepalen.
func (s *Signer) SetClock(now func() time.Time) { s.now = now }

// Mint geeft een ondertekend token uit.
func (s *Signer) Mint(subject string, typ TokenType, ttl time.Duration, resource string) (string, Claims, error) {
	now := s.now().UTC()
	claims := Claims{
		Subject:   subject,
		Type:      typ,
		IssuedAt:  now.Unix(),
		ExpiresAt: now.Add(ttl).Unix(),
		Resource:  resource,
	}

	payload, err := json.Marshal(claims)
	if err != nil {
		return "", claims, err
	}

	body := tokenPrefix + "." + base64.RawURLEncoding.EncodeToString(payload)
	return body + "." + base64.RawURLEncoding.EncodeToString(s.sign(body)), claims, nil
}

// Verify controleert handtekening en houdbaarheid en geeft de claims terug.
func (s *Signer) Verify(token string, want TokenType) (Claims, error) {
	var claims Claims

	parts := strings.Split(token, ".")
	if len(parts) != 3 || parts[0] != tokenPrefix {
		return claims, ErrTokenMalformed
	}

	sig, err := base64.RawURLEncoding.Strict().DecodeString(parts[2])
	if err != nil {
		return claims, ErrTokenMalformed
	}
	// Eerst de handtekening, dan pas ontleden. Wie de payload van een
	// ongesigneerd token al leest, laat de aanvaller de parser bedienen.
	if subtle.ConstantTimeCompare(sig, s.sign(parts[0]+"."+parts[1])) != 1 {
		return claims, ErrTokenSignature
	}

	payload, err := base64.RawURLEncoding.Strict().DecodeString(parts[1])
	if err != nil {
		return claims, ErrTokenMalformed
	}
	if err := json.Unmarshal(payload, &claims); err != nil {
		return claims, ErrTokenMalformed
	}

	if claims.Type != want {
		return claims, fmt.Errorf("%w: dit is een %s-token", ErrTokenMalformed, claims.Type)
	}
	if s.now().UTC().Unix() >= claims.ExpiresAt {
		return claims, ErrTokenExpired
	}
	return claims, nil
}

func (s *Signer) sign(body string) []byte {
	mac := hmac.New(sha256.New, s.key)
	mac.Write([]byte(body))
	return mac.Sum(nil)
}

// RefreshToken is een ondoorzichtig geheim dat de server niet bewaart.
//
// Wat er in de database staat is de SHA-256 ervan: een identificatie die niet
// naar het token terug te rekenen is (specificatie 6.5, eigenschap 2). Rotatie
// met hergebruikdetectie is alleen iets waard als een databasedump geen
// bruikbaar token oplevert.
func NewRefreshToken() (token string, hash []byte, err error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", nil, fmt.Errorf("refreshtoken genereren: %w", err)
	}
	token = base64.RawURLEncoding.EncodeToString(raw)
	return token, HashOpaque(token), nil
}

// HashOpaque geeft de opslagvorm van een ondoorzichtig geheim.
func HashOpaque(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}

// SetupCode is de eenmalige code die de eerste start op de console afdrukt.
//
// Vorm: drie groepen van drie tekens uit een alfabet zonder 0/O en 1/I/L, want
// hij wordt met de hand overgetypt van een terminal.
func NewSetupCode() (code string, hash []byte, err error) {
	const alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

	buf := make([]byte, 9)
	if _, err := rand.Read(buf); err != nil {
		return "", nil, fmt.Errorf("setupcode genereren: %w", err)
	}

	var sb strings.Builder
	for i, b := range buf {
		if i > 0 && i%3 == 0 {
			sb.WriteByte('-')
		}
		sb.WriteByte(alphabet[int(b)%len(alphabet)])
	}
	code = sb.String()
	return code, HashOpaque(code), nil
}

// EqualHash vergelijkt twee hashes in constante tijd.
func EqualHash(a, b []byte) bool { return hmac.Equal(a, b) }
