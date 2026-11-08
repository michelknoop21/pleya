package auth

import (
	"crypto/ed25519"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

// Companion-tickets (DEC-XXX): een kortlevend bewijs van wie een toestel is,
// voor Pleya Fly en de Companion Remote tussen twee toestellen van hetzelfde
// huishouden.
//
// Waarom een handtekening en geen geheim. Twee toestellen controleren elkaar op
// het lokale netwerk, zonder de server te vragen. Een gedeeld geheim kan een
// lid niet aan een andere gebruiker binden: wie het kent, kan elke naam noemen.
// Een ticket draagt de gebruiker (sub) en de publieke sleutel van het toestel
// dat hem vroeg (cnf); de server ondertekent met Ed25519 en een host controleert
// met de publieke sleutel. Een lid krijgt alleen een ticket over zichzelf, en
// een afgeluisterd ticket is zonder de privésleutel van het toestel niets waard,
// want de client ondertekent ook de handdruk zelf.
//
// Waarom de sleutel uit de ondertekensleutel komt. Een eigen sleutelbestand zou
// een tweede geheim op schijf zijn met een eigen rotatie. Het zaad is
// HMAC-SHA256(ondertekensleutel, companionSeedLabel): dezelfde HMAC als die van
// de tokens, maar een tokenbericht begint altijd met "ply1." en kan dit label
// dus nooit zijn. POST /server/rotate-signing-key roteert daarmee ook deze
// sleutel, en een nieuwe kid maakt elk oud ticket ongeldig.
const (
	companionTicketPrefix = "plc1"
	companionSeedLabel    = "pleya-companion-ticket-v1"

	// CompanionTicketTTL is kort, omdat er geen intrekking per ticket bestaat:
	// een ingetrokken sessie krijgt geen nieuw ticket, en een oud verloopt
	// binnen deze tijd.
	CompanionTicketTTL = 10 * time.Minute
)

var (
	// ErrCompanionDeviceKey betekent dat de toestelsleutel geen Ed25519-sleutel is.
	ErrCompanionDeviceKey = errors.New("toestelsleutel is geen publieke Ed25519-sleutel")
	// ErrCompanionTicket betekent dat het ticket niet klopt: vorm, sleutel of handtekening.
	ErrCompanionTicket = errors.New("companion-ticket klopt niet")
)

// CompanionClaims is de inhoud van een companion-ticket.
type CompanionClaims struct {
	KeyID     string `json:"kid"`
	ServerID  string `json:"srv"`
	Subject   string `json:"sub"`
	IssuedAt  int64  `json:"iat"`
	ExpiresAt int64  `json:"exp"`
	// DeviceKey is de publieke Ed25519-sleutel van het toestel, base64url
	// zonder opvulling. Alleen wie de privésleutel heeft, kan het ticket gebruiken.
	DeviceKey string `json:"cnf"`
}

func (s *Signer) companionKey() ed25519.PrivateKey {
	mac := hmac.New(sha256.New, *s.key.Load())
	mac.Write([]byte(companionSeedLabel))
	return ed25519.NewKeyFromSeed(mac.Sum(nil))
}

// CompanionKeyID is de kid van een publieke sleutel: de eerste acht bytes van
// de SHA-256 ervan. Een host ziet aan een andere kid dat er geroteerd is.
func CompanionKeyID(pub ed25519.PublicKey) string {
	sum := sha256.Sum256(pub)
	return base64.RawURLEncoding.EncodeToString(sum[:8])
}

// MintCompanionTicket geeft een ticket uit voor subject op serverID, gebonden
// aan deviceKey, met de publieke sleutel die het ondertekende. Die komt uit
// dezelfde lezing van de sleutel, zodat een rotatie ertussen geen ticket
// oplevert met de sleutel van een ander.
func (s *Signer) MintCompanionTicket(serverID, subject string, deviceKey []byte, ttl time.Duration) (string, CompanionClaims, ed25519.PublicKey, error) {
	if len(deviceKey) != ed25519.PublicKeySize {
		return "", CompanionClaims{}, nil, ErrCompanionDeviceKey
	}
	priv := s.companionKey()
	pub := priv.Public().(ed25519.PublicKey)
	now := s.now().UTC()
	claims := CompanionClaims{
		KeyID:     CompanionKeyID(pub),
		ServerID:  serverID,
		Subject:   subject,
		IssuedAt:  now.Unix(),
		ExpiresAt: now.Add(ttl).Unix(),
		DeviceKey: base64.RawURLEncoding.EncodeToString(deviceKey),
	}
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", claims, nil, err
	}
	body := companionTicketPrefix + "." + base64.RawURLEncoding.EncodeToString(payload)
	return body + "." + base64.RawURLEncoding.EncodeToString(ed25519.Sign(priv, []byte(body))), claims, pub, nil
}

// VerifyCompanionTicket controleert vorm, handtekening en houdbaarheid. De
// server zelf heeft hem niet nodig (een host op het netwerk controleert); hij
// bestaat als referentie voor de client en voor de tests.
func VerifyCompanionTicket(ticket string, pub ed25519.PublicKey, now time.Time) (CompanionClaims, error) {
	var claims CompanionClaims
	parts := strings.Split(ticket, ".")
	if len(parts) != 3 || parts[0] != companionTicketPrefix {
		return claims, ErrCompanionTicket
	}
	sig, err := base64.RawURLEncoding.Strict().DecodeString(parts[2])
	if err != nil || !ed25519.Verify(pub, []byte(parts[0]+"."+parts[1]), sig) {
		return claims, ErrCompanionTicket
	}
	payload, err := base64.RawURLEncoding.Strict().DecodeString(parts[1])
	if err != nil || json.Unmarshal(payload, &claims) != nil {
		return claims, ErrCompanionTicket
	}
	if claims.KeyID != CompanionKeyID(pub) {
		return claims, ErrCompanionTicket
	}
	if now.UTC().Unix() >= claims.ExpiresAt {
		return claims, ErrTokenExpired
	}
	return claims, nil
}
