package auth

import (
	"bytes"
	"crypto/ed25519"
	"encoding/base64"
	"errors"
	"strings"
	"testing"
	"time"
)

func companionSigner(t *testing.T, fill byte) *Signer {
	t.Helper()
	s, err := NewSigner(bytes.Repeat([]byte{fill}, KeyLength))
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestCompanionTicketRoundTripAndBinding(t *testing.T) {
	s := companionSigner(t, 1)
	device := bytes.Repeat([]byte{7}, ed25519.PublicKeySize)
	ticket, claims, pub, err := s.MintCompanionTicket("srv", "user-a", device, CompanionTicketTTL)
	if err != nil {
		t.Fatal(err)
	}
	got, err := VerifyCompanionTicket(ticket, pub, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if got != claims || got.Subject != "user-a" || got.ServerID != "srv" ||
		got.DeviceKey != base64.RawURLEncoding.EncodeToString(device) || got.KeyID != CompanionKeyID(pub) {
		t.Fatalf("claims %+v", got)
	}
}

func TestCompanionTicketRejects(t *testing.T) {
	s := companionSigner(t, 1)
	device := bytes.Repeat([]byte{7}, ed25519.PublicKeySize)
	ticket, _, pub, err := s.MintCompanionTicket("srv", "kid", device, CompanionTicketTTL)
	if err != nil {
		t.Fatal(err)
	}
	parts := strings.Split(ticket, ".")

	// Een kind dat zijn payload naar de owner herschrijft: de handtekening breekt.
	payload, _ := base64.RawURLEncoding.DecodeString(parts[1])
	forged := strings.Replace(string(payload), `"sub":"kid"`, `"sub":"owner"`, 1)
	if forged == string(payload) {
		t.Fatal("de vervalsing raakte niets")
	}
	tampered := parts[0] + "." + base64.RawURLEncoding.EncodeToString([]byte(forged)) + "." + parts[2]
	if _, err := VerifyCompanionTicket(tampered, pub, time.Now()); !errors.Is(err, ErrCompanionTicket) {
		t.Fatalf("aangepaste payload: %v", err)
	}

	// Een ticket van een andere server verifieert niet met de sleutel van deze.
	other := companionSigner(t, 2)
	foreign, _, otherPub, err := other.MintCompanionTicket("srv", "kid", device, CompanionTicketTTL)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Equal(otherPub, pub) {
		t.Fatal("twee ondertekensleutels gaven dezelfde companion-sleutel")
	}
	if _, err := VerifyCompanionTicket(foreign, pub, time.Now()); !errors.Is(err, ErrCompanionTicket) {
		t.Fatalf("ander server: %v", err)
	}

	// Verlopen.
	if _, err := VerifyCompanionTicket(ticket, pub, time.Now().Add(CompanionTicketTTL+time.Second)); !errors.Is(err, ErrTokenExpired) {
		t.Fatalf("verlopen: %v", err)
	}

	// Onzin en een accesstoken zijn geen ticket.
	access, _, err := s.Mint("kid", "sid", TokenAccess, time.Minute, "")
	if err != nil {
		t.Fatal(err)
	}
	for _, bad := range []string{"", "plc1.x", access, "plc1." + parts[1] + ".!!"} {
		if _, err := VerifyCompanionTicket(bad, pub, time.Now()); !errors.Is(err, ErrCompanionTicket) {
			t.Fatalf("%q: %v", bad, err)
		}
	}

	// Een toestelsleutel van de verkeerde lengte krijgt geen ticket.
	if _, _, _, err := s.MintCompanionTicket("srv", "kid", device[:31], CompanionTicketTTL); !errors.Is(err, ErrCompanionDeviceKey) {
		t.Fatalf("korte toestelsleutel: %v", err)
	}
}

// Rotatie van de ondertekensleutel geeft een andere companion-sleutel.
func TestCompanionKeyFollowsRotation(t *testing.T) {
	s := companionSigner(t, 1)
	device := bytes.Repeat([]byte{7}, ed25519.PublicKeySize)
	_, before, oldPub, _ := s.MintCompanionTicket("srv", "u", device, time.Minute)
	if err := s.Rotate(bytes.Repeat([]byte{3}, KeyLength)); err != nil {
		t.Fatal(err)
	}
	ticket, after, _, _ := s.MintCompanionTicket("srv", "u", device, time.Minute)
	if before.KeyID == after.KeyID {
		t.Fatal("de kid bleef gelijk")
	}
	if _, err := VerifyCompanionTicket(ticket, oldPub, time.Now()); !errors.Is(err, ErrCompanionTicket) {
		t.Fatalf("nieuw ticket met oude sleutel: %v", err)
	}
}

// TestCompanionTicketVector legt één ticket vast dat de app ook leest
// (test/services/companion_remote/pleya_server_remote_auth_test.dart), zodat
// Go en Dart hetzelfde formaat en dezelfde Ed25519 spreken.
func TestCompanionTicketVector(t *testing.T) {
	s := companionSigner(t, 1)
	s.SetClock(func() time.Time { return time.Unix(1794131200, 0) })
	device := ed25519.NewKeyFromSeed(bytes.Repeat([]byte{9}, ed25519.SeedSize))
	ticket, _, pub, err := s.MintCompanionTicket("srv", "u-anna", device.Public().(ed25519.PublicKey), CompanionTicketTTL)
	if err != nil {
		t.Fatal(err)
	}
	deviceSig := base64.RawURLEncoding.EncodeToString(ed25519.Sign(device, []byte("vector-transcript")))
	got := ticket + " " + base64.RawURLEncoding.EncodeToString(pub) + " " + deviceSig
	if got != companionVector {
		t.Fatalf("vector veranderd:\n%s", got)
	}
}

const companionVector = "plc1.eyJraWQiOiJUT2RuRVdPYm9xayIsInNydiI6InNydiIsInN1YiI6InUtYW5uYSIsImlhdCI6MTc5NDEzMTIwMCwiZXhwIjoxNzk0MTMxODAwLCJjbmYiOiJfUmNrT0ZxZ3gxdGstM2pOWUMtaDJaSDk2X2RyRThXTzF3THF5RFhwOWhnIn0.VKQWBFLLqFskfG8xOy7qAXZeqytVnoHYYBz6NBewUeaj3b2BO4eMv46WXRu_ji8CAPHJoCy13jxB7GvTTwrpDg _uF5MUwlc6n_9hwYDZ0xQ7LFZST0b_1Lrf7tGQJqf_0 bIcGd3n1jJ1NR_hsCk1EAFYyOvJ1ccmPiw2jvRK7dXQl3OQZ_1ppfMWjm9UWbr_gJiilNawJn5ucEAqgkrP8DA"
