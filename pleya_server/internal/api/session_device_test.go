package api_test

import (
	"context"
	"net/http"
	"testing"
)

// Wat de server doet met een device_id dat hij al kent (DEC-123, DEC-164).
//
// Pleya Web stuurt sinds DEC-164 een vaste device_id per browserprofiel. Deze
// test legt vast dat een tweede login met dezelfde id een tweede sessie opent
// en de eerste niet vervangt: het stapelen voorkomen is de taak van uitloggen
// (POST /auth/logout trekt de eigen sessie in) en van de opruimronde, niet van
// login. Verandert dat gedrag, dan moet de webclient opnieuw bekeken worden.
func TestLoginWithAKnownDeviceIDAddsASession(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	body := map[string]string{
		"username":    "michel",
		"password":    "een-lang-genoeg-wachtwoord",
		"device_id":   "web-0f6c3d2e-1b8a-4c5d-9e7f-123456789abc",
		"device_name": "Safari op macOS",
	}
	for range 2 {
		if rec := e.do(http.MethodPost, "/pleya/v1/auth/login", body, withoutAuth); rec.Code != http.StatusOK {
			t.Fatalf("login gaf %d: %s", rec.Code, rec.Body.String())
		}
	}

	var rows int
	if err := e.pool.QueryRow(context.Background(), `
		SELECT count(*) FROM sessions
		WHERE device_id = $1 AND device_name = 'Safari op macOS' AND revoked_at IS NULL`,
		body["device_id"]).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 2 {
		t.Fatalf("twee logins met dezelfde device_id gaven %d levende sessies, verwacht 2", rows)
	}

	// Zonder device_name valt de server terug op de plaatshouder die de
	// webclient als "Onbekend toestel" toont.
	if rec := e.do(http.MethodPost, "/pleya/v1/auth/login", map[string]string{
		"username": "michel", "password": "een-lang-genoeg-wachtwoord",
	}, withoutAuth); rec.Code != http.StatusOK {
		t.Fatalf("login zonder toestel gaf %d", rec.Code)
	}
	var unknown int
	if err := e.pool.QueryRow(context.Background(), `
		SELECT count(*) FROM sessions WHERE device_id IS NULL AND device_name = 'Unknown device'
		AND kind = 'device' AND revoked_at IS NULL`).Scan(&unknown); err != nil {
		t.Fatal(err)
	}
	if unknown < 1 {
		t.Fatal("een login zonder device_name kreeg niet de plaatshouder Unknown device")
	}
}
