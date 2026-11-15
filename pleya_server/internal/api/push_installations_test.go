package api_test

import (
	"net/http"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

const pushInstallationsPath = "/pleya/v1/users/me/push-installations"

// DELETE zonder id trekt alles van de aanroepende sessie in, en niets van een
// andere sessie of een ander account (A-21).
func TestDeletePushInstallationsWithdrawsOnlyTheCallingSession(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	phone := e.login("phone")
	e.login("tablet")

	sessionOf := func(device string) id.ID {
		t.Helper()
		var session id.ID
		if err := e.pool.QueryRow(t.Context(), `SELECT id FROM sessions WHERE device_id=$1`, device).Scan(&session); err != nil {
			t.Fatal(err)
		}
		return session
	}
	other, otherSession := id.New(), id.New()
	if _, err := e.pool.Exec(t.Context(), `INSERT INTO users(id,username,password_hash,role) VALUES ($1,'kind','x','member')`, other); err != nil {
		t.Fatal(err)
	}
	if _, err := e.pool.Exec(t.Context(), `INSERT INTO sessions(id,user_id,device_name) VALUES ($1,$2,'ipad')`, otherSession, other); err != nil {
		t.Fatal(err)
	}
	install := func(session id.ID, token string) {
		t.Helper()
		if _, err := e.pool.Exec(t.Context(), `INSERT INTO push_installations(id,session_id,device_token,environment,locale,movies_since)
			VALUES ($1,$2,$3,'sandbox','nl',now())`, id.New(), session, token); err != nil {
			t.Fatal(err)
		}
	}
	install(sessionOf("phone"), "aa01")
	install(sessionOf("phone"), "aa02")
	install(sessionOf("tablet"), "aa03")
	install(otherSession, "aa04")
	count := func(session id.ID) int {
		t.Helper()
		var n int
		if err := e.pool.QueryRow(t.Context(), `SELECT count(*) FROM push_installations WHERE session_id=$1`, session).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	asPhone := func(r *http.Request) { r.Header.Set("Authorization", "Bearer "+phone.AccessToken) }

	for range 2 {
		rec := e.do(http.MethodDelete, pushInstallationsPath, nil, asPhone)
		if rec.Code != http.StatusNoContent || rec.Header().Get("Cache-Control") != "no-store" {
			t.Fatalf("gaf %d (%q), verwacht 204 no-store: %s", rec.Code, rec.Header().Get("Cache-Control"), rec.Body.String())
		}
	}
	if count(sessionOf("phone")) != 0 {
		t.Fatal("de eigen sessie hield een registratie")
	}
	if count(sessionOf("tablet")) != 1 || count(otherSession) != 1 {
		t.Fatal("een andere sessie of een ander account verloor een registratie")
	}

	token := e.createToken(map[string]any{"name": "agent", "scope": "admin"}, http.StatusCreated).Secret
	rec := e.do(http.MethodDelete, pushInstallationsPath, nil, asToken(token))
	if rec.Code != http.StatusForbidden {
		t.Fatalf("een API-token gaf %d, verwacht 403: %s", rec.Code, rec.Body.String())
	}
	if count(sessionOf("tablet")) != 1 {
		t.Fatal("een API-token trok iets in")
	}
}

// DELETE met een id raakt alleen een registratie van de eigen sessie: niet die
// van een ander account (IDOR) en niet die van een andere sessie van hetzelfde
// account.
func TestDeletePushInstallationByIDStaysInsideTheCallingSession(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	// De setup-sessie is ouder dan die van de telefoon: de oude regel liet een
	// nieuwere sessie van hetzelfde account haar registraties intrekken.
	var older id.ID
	if err := e.pool.QueryRow(t.Context(), `SELECT id FROM sessions ORDER BY created_at LIMIT 1`).Scan(&older); err != nil {
		t.Fatal(err)
	}
	phone := e.login("phone")
	other, otherSession := id.New(), id.New()
	if _, err := e.pool.Exec(t.Context(), `INSERT INTO users(id,username,password_hash,role) VALUES ($1,'kind','x','member')`, other); err != nil {
		t.Fatal(err)
	}
	if _, err := e.pool.Exec(t.Context(), `INSERT INTO sessions(id,user_id,device_name) VALUES ($1,$2,'ipad')`, otherSession, other); err != nil {
		t.Fatal(err)
	}
	theirs, mineElsewhere := id.New(), id.New()
	for _, row := range []struct {
		installation, session id.ID
		token                 string
	}{{theirs, otherSession, "bb01"}, {mineElsewhere, older, "bb02"}} {
		if _, err := e.pool.Exec(t.Context(), `INSERT INTO push_installations(id,session_id,device_token,environment,locale,movies_since)
			VALUES ($1,$2,$3,'sandbox','nl',now())`, row.installation, row.session, row.token); err != nil {
			t.Fatal(err)
		}
	}
	asPhone := func(r *http.Request) { r.Header.Set("Authorization", "Bearer "+phone.AccessToken) }
	for _, target := range []id.ID{theirs, mineElsewhere} {
		rec := e.do(http.MethodDelete, pushInstallationsPath+"/"+target.String(), nil, asPhone)
		if rec.Code != http.StatusNoContent {
			t.Fatalf("gaf %d, verwacht 204 zonder onderscheid: %s", rec.Code, rec.Body.String())
		}
		var n int
		if err := e.pool.QueryRow(t.Context(), `SELECT count(*) FROM push_installations WHERE id=$1`, target).Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != 1 {
			t.Fatalf("de registratie %s van een andere sessie verdween", target)
		}
	}
}
