package api_test

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/auth"
)

const companionTicketPath = "/pleya/v1/companion/ticket"

func newDeviceKey(t *testing.T) string {
	t.Helper()
	pub, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return base64.RawURLEncoding.EncodeToString(pub)
}

// companionTicket vraagt een ticket en controleert het zoals een host op het
// netwerk dat doet: met de publieke sleutel uit hetzelfde antwoord.
func (e *env) companionTicket(deviceKey string, opts ...func(*http.Request)) (api.CompanionTicket, auth.CompanionClaims) {
	e.t.Helper()
	rec := e.do(http.MethodPost, companionTicketPath, map[string]string{"device_key": deviceKey}, opts...)
	if rec.Code != http.StatusOK {
		e.t.Fatalf("POST /companion/ticket gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("CompanionTicket", http.MethodPost, companionTicketPath, rec)
	var out api.CompanionTicket
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatal(err)
	}
	pub, err := base64.RawURLEncoding.DecodeString(out.PublicKey)
	if err != nil {
		e.t.Fatal(err)
	}
	claims, err := auth.VerifyCompanionTicket(out.Ticket, pub, time.Now())
	if err != nil {
		e.t.Fatalf("het ticket verifieert niet met de sleutel uit het antwoord: %v", err)
	}
	return out, claims
}

func (e *env) serverIDFromInfo() string {
	e.t.Helper()
	var info struct {
		Server struct {
			ID string `json:"id"`
		} `json:"server"`
	}
	e.decodeInto(e.do(http.MethodGet, "/pleya/v1/info", nil, withoutAuth), &info)
	return info.Server.ID
}

// Elke rol krijgt een ticket, en altijd over zichzelf: sub is de aanvrager,
// srv deze server, cnf de toestelsleutel uit de aanvraag. Een restricted
// gebruiker kan zo nooit een ticket over de owner krijgen.
func TestCompanionTicketIsAlwaysAboutTheRequester(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	serverID := e.serverIDFromInfo()

	restricted := e.createUserViaAPI("tim", "nog-een-lang-wachtwoord", "restricted", http.StatusOK)

	var self api.UserWire
	e.getJSON("/pleya/v1/users/me", "User", http.StatusOK, &self)
	ownerID := self.ID

	key := newDeviceKey(t)
	ticket, claims := e.companionTicket(key)
	if claims.Subject != ownerID || claims.ServerID != serverID || claims.DeviceKey != key {
		t.Fatalf("owner-ticket draagt %+v", claims)
	}
	if ticket.KeyID != claims.KeyID {
		t.Fatalf("key_id %q hoort bij het ticket (%q)", ticket.KeyID, claims.KeyID)
	}
	if claims.ExpiresAt-claims.IssuedAt != int64(auth.CompanionTicketTTL/time.Second) {
		t.Fatalf("geldigheid %d s, verwacht %v", claims.ExpiresAt-claims.IssuedAt, auth.CompanionTicketTTL)
	}

	access := e.loginAs(restricted.Username, "nog-een-lang-wachtwoord", http.StatusOK)
	_, kid := e.companionTicket(newDeviceKey(t), asUser(access))
	if kid.Subject != restricted.ID || kid.Subject == ownerID {
		t.Fatalf("restricted kreeg een ticket over %q, verwacht zichzelf (%q)", kid.Subject, restricted.ID)
	}

	// Er is geen veld om een ander te noemen: een poging valt op de gesloten body.
	rec := e.do(http.MethodPost, companionTicketPath,
		map[string]string{"device_key": newDeviceKey(t), "user_id": ownerID}, asUser(access))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("een user_id in de body gaf %d, verwacht 400", rec.Code)
	}
}

func TestCompanionTicketRefusesABadDeviceKeyAndAnAPIToken(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	for _, key := range []string{"", "geen-base64!", base64.RawURLEncoding.EncodeToString([]byte("te kort"))} {
		rec := e.do(http.MethodPost, companionTicketPath, map[string]string{"device_key": key})
		if rec.Code != http.StatusBadRequest || errorCode(t, rec) != "auth.device_key_invalid" {
			t.Fatalf("device_key %q gaf %d %q", key, rec.Code, errorCode(t, rec))
		}
	}

	created := e.createToken(map[string]any{"name": "script", "scope": "admin"}, http.StatusCreated)
	rec := e.do(http.MethodPost, companionTicketPath,
		map[string]string{"device_key": newDeviceKey(t)}, asToken(created.Secret))
	if rec.Code != http.StatusForbidden || errorCode(t, rec) != "auth.scope_insufficient" {
		t.Fatalf("een API-token gaf %d %q", rec.Code, errorCode(t, rec))
	}

	rec = e.do(http.MethodPost, companionTicketPath, map[string]string{"device_key": newDeviceKey(t)}, withoutAuth)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("zonder token %d, verwacht 401", rec.Code)
	}
}

// Rotatie van de ondertekensleutel geeft een nieuwe companion-sleutel: een oud
// ticket verifieert niet meer met de nieuwe, en de kid verandert.
func TestCompanionTicketDiesWithSigningKeyRotation(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	before, _ := e.companionTicket(newDeviceKey(t))

	rec := e.do(http.MethodPost, "/pleya/v1/server/rotate-signing-key", map[string]string{"confirm": "rotate"})
	if rec.Code != http.StatusNoContent {
		t.Fatalf("roteren gaf %d: %s", rec.Code, rec.Body.String())
	}
	// Roteren trekt elke sessie in; een vers token van dezelfde owner.
	access := e.loginAs("michel", "een-lang-genoeg-wachtwoord", http.StatusOK)
	after, _ := e.companionTicket(newDeviceKey(t), asUser(access))

	if after.KeyID == before.KeyID {
		t.Fatal("de kid bleef gelijk na rotatie")
	}
	newKey, _ := base64.RawURLEncoding.DecodeString(after.PublicKey)
	if _, err := auth.VerifyCompanionTicket(before.Ticket, newKey, time.Now()); err == nil {
		t.Fatal("een ticket van voor de rotatie verifieert met de nieuwe sleutel")
	}
}
