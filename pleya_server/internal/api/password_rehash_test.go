package api_test

import (
	"context"
	"net/http"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/auth"
)

// TestLoginRehashKeepsUsersAndOwnerPasswordInSync is de regressietest voor de
// bug waarbij UpdatePasswordHash alleen auth_owner.password_hash bijwerkte.
// users is sinds PS-9 de bron van waarheid (auth/store.go), maar kreeg zijn
// nieuwe hash nooit te zien zodra een geslaagde login een herhash triggerde:
// de twee kopieën liepen dan stil uiteen.
func TestLoginRehashKeepsUsersAndOwnerPasswordInSync(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()

	// Een bewust lichtere hash neerzetten dan de serverconfiguratie (de
	// "light" Argon2-parameters uit newEnv), zodat VerifyPassword bij de
	// volgende login needsRehash=true teruggeeft. Dat is precies het pad dat
	// handleLogin bij elke geslaagde login doorloopt (specificatie 6.5,
	// eigenschap 3), en de enige aanroeper van UpdatePasswordHash.
	weakParams := auth.Argon2Params{Memory: 1024, Iterations: 1, Parallelism: 1, SaltLength: 16, KeyLength: 32}
	weakHash, err := auth.HashPassword("een-lang-genoeg-wachtwoord", weakParams)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := e.pool.Exec(ctx, `UPDATE auth_owner SET password_hash = $1 WHERE id = 1`, weakHash); err != nil {
		t.Fatal(err)
	}
	if _, err := e.pool.Exec(ctx, `UPDATE users SET password_hash = $1 WHERE role = 'owner'`, weakHash); err != nil {
		t.Fatal(err)
	}

	rec := e.do(http.MethodPost, "/pleya/v1/auth/login",
		map[string]string{"username": "michel", "password": "een-lang-genoeg-wachtwoord"}, withoutAuth)
	if rec.Code != http.StatusOK {
		t.Fatalf("login gaf %d: %s", rec.Code, rec.Body.String())
	}

	var ownerHash, userHash string
	if err := e.pool.QueryRow(ctx, `SELECT password_hash FROM auth_owner WHERE id = 1`).Scan(&ownerHash); err != nil {
		t.Fatal(err)
	}
	if err := e.pool.QueryRow(ctx, `SELECT password_hash FROM users WHERE role = 'owner'`).Scan(&userHash); err != nil {
		t.Fatal(err)
	}

	if ownerHash == weakHash {
		t.Fatal("auth_owner.password_hash is niet herhasht; needsRehash werkte niet")
	}
	if userHash != ownerHash {
		t.Fatalf("users.password_hash (%s) loopt uiteen van auth_owner.password_hash (%s) na de herhash",
			userHash, ownerHash)
	}

	// De nieuwe hash logt zelf niet meer als "lichter": een volgende login
	// mag geen tweede herhash meer triggeren.
	ok, needsRehash, err := auth.VerifyPassword("een-lang-genoeg-wachtwoord", userHash, e.argon2)
	if err != nil {
		t.Fatal(err)
	}
	if !ok {
		t.Fatal("de herhashte hash verifieert het wachtwoord niet meer")
	}
	if needsRehash {
		t.Fatal("de herhashte hash vraagt meteen weer om een herhash")
	}
}
