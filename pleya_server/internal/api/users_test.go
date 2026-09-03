package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/auth"
)

// De gebruikersbeheer-API van stap 4 (DEC-067), plus matrixregel 14 uit
// DEC-072. Het onderscheid dat deze tests bewaken is niet "werkt het endpoint"
// maar "kan een tweede gebruiker werkelijk bestaan en inloggen zonder
// handmatige SQL": dat is de voorwaarde die AC1 en het stopcriterium van PS-9
// stellen, en de fixtures van authorize_test.go slaan hem juist over.

// createUserViaAPI maakt een gebruiker via POST /users, als de aanvrager die
// e.access op dat moment draagt.
func (e *env) createUserViaAPI(username, password, role string, want int) api.UserWire {
	e.t.Helper()
	rec := e.do(http.MethodPost, "/pleya/v1/users", map[string]string{
		"username": username, "password": password, "role": role,
	})
	if rec.Code != want {
		e.t.Fatalf("POST /users gaf %d, verwacht %d: %s", rec.Code, want, rec.Body.String())
	}
	if rec.Code == http.StatusOK {
		e.record("User", http.MethodPost, "/pleya/v1/users", rec)
	}
	var user api.UserWire
	if rec.Code == http.StatusOK {
		if err := json.Unmarshal(rec.Body.Bytes(), &user); err != nil {
			e.t.Fatal(err)
		}
	}
	return user
}

// loginAs wisselt gebruikersnaam en wachtwoord in voor een accesstoken, via het
// echte endpoint. Het verschil met tokenFor is precies het punt: dit bewijst
// dat de gebruiker het product in komt en niet alleen dat de autorisatie klopt.
func (e *env) loginAs(username, password string, want int) string {
	e.t.Helper()
	rec := e.do(http.MethodPost, "/pleya/v1/auth/login", map[string]string{
		"username": username, "password": password,
	}, withoutAuth)
	if rec.Code != want {
		e.t.Fatalf("login als %s gaf %d, verwacht %d: %s", username, rec.Code, want, rec.Body.String())
	}
	if rec.Code != http.StatusOK {
		return ""
	}
	var pair api.TokenPair
	if err := json.Unmarshal(rec.Body.Bytes(), &pair); err != nil {
		e.t.Fatal(err)
	}
	return pair.AccessToken
}

// TestSecondUserCanBeCreatedAndLogIn is de voorwaarde onder AC1: zonder dit pad
// bestaat een tweede gebruiker alleen in een testfixture.
func TestSecondUserCanBeCreatedAndLogIn(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	created := e.createUserViaAPI("sanne", "nog-een-lang-wachtwoord", "member", http.StatusOK)
	if created.Username != "sanne" || created.Role != "member" || created.ID == "" {
		t.Fatalf("POST /users gaf %+v", created)
	}

	access := e.loginAs("sanne", "nog-een-lang-wachtwoord", http.StatusOK)
	if access == "" || access == e.access {
		t.Fatal("de tweede gebruiker kreeg geen eigen accesstoken")
	}

	// Het token draagt haar eigen subject en niet dat van de owner. Zonder deze
	// controle zou een login die stilletjes de owner teruggeeft er van buiten
	// precies zo uitzien.
	claims, err := e.signer.Verify(access, auth.TokenAccess)
	if err != nil {
		t.Fatal(err)
	}
	if claims.Subject != created.ID {
		t.Fatalf("het token draagt subject %s, verwacht %s", claims.Subject, created.ID)
	}
	if claims.Sid == "" {
		t.Fatal("het token draagt geen sid; de sessieketen van DEC-069 is dan niet gesloten")
	}
}

// TestLoginRejectsUnknownUserAndWrongPassword houdt de twee antwoorden gelijk.
func TestLoginRejectsUnknownUserAndWrongPassword(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	e.createUserViaAPI("sanne", "nog-een-lang-wachtwoord", "member", http.StatusOK)

	// Een naam die niet bestaat en een wachtwoord dat niet klopt geven allebei
	// auth.invalid_credentials. Een verschil hier zou een naamlijst opleveren.
	for _, tc := range []struct{ username, password string }{
		{"bestaat-niet", "nog-een-lang-wachtwoord"},
		{"sanne", "een-verkeerd-wachtwoord"},
	} {
		rec := e.do(http.MethodPost, "/pleya/v1/auth/login", map[string]string{
			"username": tc.username, "password": tc.password,
		}, withoutAuth)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("login %s gaf %d: %s", tc.username, rec.Code, rec.Body.String())
		}
		e.expectCode(rec, api.CodeInvalidCredentials)
	}
}

// TestListUsersFiltersForMemberAndRestricted is matrixregel 14.
func TestListUsersFiltersForMemberAndRestricted(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	member := e.createUserViaAPI("sanne", "nog-een-lang-wachtwoord", "member", http.StatusOK)
	restricted := e.createUserViaAPI("tim", "nog-een-lang-wachtwoord", "restricted", http.StatusOK)

	var all api.UserListWire
	e.getJSON("/pleya/v1/users", "UserList", http.StatusOK, &all)
	if len(all.Items) != 3 {
		t.Fatalf("de owner ziet %d gebruikers, verwacht 3: %+v", len(all.Items), all.Items)
	}

	for _, tc := range []struct {
		name string
		user api.UserWire
	}{{"member", member}, {"restricted", restricted}} {
		access := e.loginAs(tc.user.Username, "nog-een-lang-wachtwoord", http.StatusOK)
		rec := e.do(http.MethodGet, "/pleya/v1/users", nil, asUser(access))
		if rec.Code != http.StatusOK {
			t.Fatalf("%s kreeg %d op GET /users", tc.name, rec.Code)
		}
		var mine api.UserListWire
		if err := json.Unmarshal(rec.Body.Bytes(), &mine); err != nil {
			t.Fatal(err)
		}
		if len(mine.Items) != 1 || mine.Items[0].ID != tc.user.ID {
			t.Fatalf("%s ziet %+v, verwacht alleen zichzelf", tc.name, mine.Items)
		}
	}
}

// TestUserAdminEndpointsAreInvisibleToMember dekt de admin-klasse: 404 en geen
// 403, zodat het beheeroppervlak niet lekt naar wie er niet bij mag.
func TestUserAdminEndpointsAreInvisibleToMember(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	member := e.createUserViaAPI("sanne", "nog-een-lang-wachtwoord", "member", http.StatusOK)
	other := e.createUserViaAPI("tim", "nog-een-lang-wachtwoord", "member", http.StatusOK)
	access := e.loginAs("sanne", "nog-een-lang-wachtwoord", http.StatusOK)

	cases := []struct {
		method, path string
		body         any
	}{
		{http.MethodPost, "/pleya/v1/users", map[string]string{
			"username": "nieuw", "password": "nog-een-lang-wachtwoord", "role": "member"}},
		{http.MethodPatch, "/pleya/v1/users/" + other.ID, map[string]string{"role": "admin"}},
		{http.MethodDelete, "/pleya/v1/users/" + other.ID, nil},
		{http.MethodPut, "/pleya/v1/users/" + other.ID + "/permissions",
			map[string]any{"permissions": []any{}}},
	}
	for _, tc := range cases {
		rec := e.do(tc.method, tc.path, tc.body, asUser(access))
		if rec.Code != http.StatusNotFound {
			t.Fatalf("%s %s gaf een member %d, verwacht 404: %s", tc.method, tc.path, rec.Code, rec.Body.String())
		}
		e.expectCode(rec, api.CodeUserNotFound)
	}

	// Zichzelf bijwerken mag wel: dat is de "of op zichzelf"-clausule.
	rec := e.do(http.MethodPatch, "/pleya/v1/users/"+member.ID,
		map[string]string{"password": "een-heel-ander-wachtwoord"}, asUser(access))
	if rec.Code != http.StatusOK {
		t.Fatalf("een member mag zijn eigen wachtwoord zetten, kreeg %d: %s", rec.Code, rec.Body.String())
	}
	e.loginAs("sanne", "een-heel-ander-wachtwoord", http.StatusOK)
}

// TestRestrictedDoesNotManageOwnPassword is het tweede van de drie verschillen
// uit DEC-065 §3. Het derde (nooit manage) staat hieronder, het eerste (alleen
// zichzelf zien) in TestListUsersFiltersForMemberAndRestricted.
func TestRestrictedDoesNotManageOwnPassword(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	restricted := e.createUserViaAPI("tim", "nog-een-lang-wachtwoord", "restricted", http.StatusOK)
	access := e.loginAs("tim", "nog-een-lang-wachtwoord", http.StatusOK)

	rec := e.do(http.MethodPatch, "/pleya/v1/users/"+restricted.ID,
		map[string]string{"password": "een-heel-ander-wachtwoord"}, asUser(access))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("restricted zette zijn eigen wachtwoord: %d %s", rec.Code, rec.Body.String())
	}

	// De owner mag het wel, en het oude wachtwoord werkt daarna niet meer.
	rec = e.do(http.MethodPatch, "/pleya/v1/users/"+restricted.ID,
		map[string]string{"password": "een-heel-ander-wachtwoord"})
	if rec.Code != http.StatusOK {
		t.Fatalf("de owner kon het wachtwoord van restricted niet zetten: %d %s", rec.Code, rec.Body.String())
	}
	e.loginAs("tim", "nog-een-lang-wachtwoord", http.StatusUnauthorized)
	e.loginAs("tim", "een-heel-ander-wachtwoord", http.StatusOK)
}

// TestOwnerIsImmutable dekt AC4's andere kant: de owner blijft bestaan.
func TestOwnerIsImmutable(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	var all api.UserListWire
	e.getJSON("/pleya/v1/users", "", http.StatusOK, &all)
	var ownerID string
	for _, u := range all.Items {
		if u.Role == "owner" {
			ownerID = u.ID
		}
	}
	if ownerID == "" {
		t.Fatal("er staat geen owner in users na setup")
	}

	rec := e.do(http.MethodPatch, "/pleya/v1/users/"+ownerID, map[string]string{"role": "member"})
	if rec.Code != http.StatusConflict {
		t.Fatalf("de owner degraderen gaf %d, verwacht 409: %s", rec.Code, rec.Body.String())
	}
	e.expectCode(rec, api.CodeOwnerImmutable)

	rec = e.do(http.MethodDelete, "/pleya/v1/users/"+ownerID, nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("de owner verwijderen gaf %d, verwacht 409", rec.Code)
	}
	e.expectCode(rec, api.CodeOwnerImmutable)

	// En een tweede owner ontstaat niet via POST /users; die rol komt alleen uit
	// /auth/setup.
	rec = e.do(http.MethodPost, "/pleya/v1/users", map[string]string{
		"username": "tweede-eigenaar", "password": "nog-een-lang-wachtwoord", "role": "owner"})
	if rec.Code != http.StatusConflict {
		t.Fatalf("een tweede owner aanmaken gaf %d, verwacht 409: %s", rec.Code, rec.Body.String())
	}
	e.expectCode(rec, api.CodeOwnerImmutable)
}

// TestUsernameTaken dekt de unieke index als contractantwoord.
func TestUsernameTaken(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	e.createUserViaAPI("sanne", "nog-een-lang-wachtwoord", "member", http.StatusOK)
	rec := e.do(http.MethodPost, "/pleya/v1/users", map[string]string{
		"username": "sanne", "password": "weer-een-lang-wachtwoord", "role": "member"})
	if rec.Code != http.StatusConflict {
		t.Fatalf("een dubbele gebruikersnaam gaf %d, verwacht 409: %s", rec.Code, rec.Body.String())
	}
	e.expectCode(rec, api.CodeUsernameTaken)
}

// TestSetPermissionsReplacesTheWholeList dekt PUT als vervanging en niet als
// samenvoeging, plus de doorwerking naar de catalogus.
func TestSetPermissionsReplacesTheWholeList(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryByKind("movies")
	series := e.libraryByKind("shows")
	member := e.createUserViaAPI("sanne", "nog-een-lang-wachtwoord", "member", http.StatusOK)
	access := e.loginAs("sanne", "nog-een-lang-wachtwoord", http.StatusOK)

	// Zonder rechten ziet ze niets.
	var libs api.LibraryList
	rec := e.do(http.MethodGet, "/pleya/v1/libraries", nil, asUser(access))
	if err := json.Unmarshal(rec.Body.Bytes(), &libs); err != nil {
		t.Fatal(err)
	}
	if len(libs.Items) != 0 {
		t.Fatalf("een gebruiker zonder rechten ziet %d bibliotheken", len(libs.Items))
	}

	// Twee rechten zetten.
	rec = e.do(http.MethodPut, "/pleya/v1/users/"+member.ID+"/permissions", map[string]any{
		"permissions": []map[string]string{
			{"library_id": films.ID.String(), "permission": "view"},
			{"library_id": series.ID.String(), "permission": "download"},
		}})
	if rec.Code != http.StatusOK {
		t.Fatalf("rechten zetten gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("LibraryPermissionList", http.MethodPut, "/pleya/v1/users/{id}/permissions", rec)
	var stored api.LibraryPermissionListWire
	if err := json.Unmarshal(rec.Body.Bytes(), &stored); err != nil {
		t.Fatal(err)
	}
	if len(stored.Items) != 2 {
		t.Fatalf("het antwoord draagt %d rechten, verwacht 2", len(stored.Items))
	}

	rec = e.do(http.MethodGet, "/pleya/v1/libraries", nil, asUser(access))
	if err := json.Unmarshal(rec.Body.Bytes(), &libs); err != nil {
		t.Fatal(err)
	}
	if len(libs.Items) != 2 {
		t.Fatalf("met twee rechten ziet ze %d bibliotheken", len(libs.Items))
	}

	// Vervangen door één recht haalt het andere weg. Samenvoegen zou hier twee
	// laten staan, en dat is het verschil tussen PUT en PATCH.
	rec = e.do(http.MethodPut, "/pleya/v1/users/"+member.ID+"/permissions", map[string]any{
		"permissions": []map[string]string{
			{"library_id": films.ID.String(), "permission": "view"},
		}})
	if rec.Code != http.StatusOK {
		t.Fatalf("rechten vervangen gaf %d: %s", rec.Code, rec.Body.String())
	}
	rec = e.do(http.MethodGet, "/pleya/v1/libraries", nil, asUser(access))
	if err := json.Unmarshal(rec.Body.Bytes(), &libs); err != nil {
		t.Fatal(err)
	}
	if len(libs.Items) != 1 || libs.Items[0].ID != films.ID.String() {
		t.Fatalf("na vervangen ziet ze %+v", libs.Items)
	}
}

// TestRestrictedNeverGetsManage is het derde verschil uit DEC-065 §3, en het
// bewijs dat de trigger uit migratie 0007 meedoet in plaats van alleen in de UI
// te bestaan.
func TestRestrictedNeverGetsManage(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryByKind("movies")
	restricted := e.createUserViaAPI("tim", "nog-een-lang-wachtwoord", "restricted", http.StatusOK)

	rec := e.do(http.MethodPut, "/pleya/v1/users/"+restricted.ID+"/permissions", map[string]any{
		"permissions": []map[string]string{
			{"library_id": films.ID.String(), "permission": "manage"},
		}})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("manage voor restricted gaf %d: %s", rec.Code, rec.Body.String())
	}

	// De transactie draaide terug: er staat geen half toegekende lijst.
	var count int
	if err := e.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM library_permissions WHERE user_id = $1`, restricted.ID).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 0 {
		t.Fatalf("er staan %d rechten na een geweigerde lijst", count)
	}

	// download mag wel, en een latere degradatie naar restricted laat geen
	// manage achter: dat pad komt langs UpdateUser en niet langs de trigger.
	member := e.createUserViaAPI("sanne", "nog-een-lang-wachtwoord", "member", http.StatusOK)
	rec = e.do(http.MethodPut, "/pleya/v1/users/"+member.ID+"/permissions", map[string]any{
		"permissions": []map[string]string{
			{"library_id": films.ID.String(), "permission": "manage"},
		}})
	if rec.Code != http.StatusOK {
		t.Fatalf("manage voor een member gaf %d: %s", rec.Code, rec.Body.String())
	}
	rec = e.do(http.MethodPatch, "/pleya/v1/users/"+member.ID, map[string]string{"role": "restricted"})
	if rec.Code != http.StatusOK {
		t.Fatalf("degraderen naar restricted gaf %d: %s", rec.Code, rec.Body.String())
	}
	var permission string
	if err := e.pool.QueryRow(context.Background(),
		`SELECT permission FROM library_permissions WHERE user_id = $1`, member.ID).Scan(&permission); err != nil {
		t.Fatal(err)
	}
	if permission == "manage" {
		t.Fatal("een gedegradeerde gebruiker houdt manage; DEC-065 §3 verbiedt dat voor restricted")
	}
}

// TestDeleteUserCascades dekt het cascadegedrag uit DEC-065 §5: alles wat aan
// de gebruiker hangt gaat mee, en de kijkstatus van een ander blijft staan.
func TestDeleteUserCascades(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()

	films := e.libraryByKind("movies")
	member := e.createUserViaAPI("sanne", "nog-een-lang-wachtwoord", "member", http.StatusOK)
	if rec := e.do(http.MethodPut, "/pleya/v1/users/"+member.ID+"/permissions", map[string]any{
		"permissions": []map[string]string{{"library_id": films.ID.String(), "permission": "view"}},
	}); rec.Code != http.StatusOK {
		t.Fatalf("rechten zetten gaf %d", rec.Code)
	}
	access := e.loginAs("sanne", "nog-een-lang-wachtwoord", http.StatusOK)

	item := e.findMovie("Grease").ID
	if rec := e.do(http.MethodPost, "/pleya/v1/watch-state",
		event(item, "sessie-van-sanne", nil), asUser(access)); rec.Code != http.StatusOK {
		t.Fatalf("kijkstatus melden gaf %d: %s", rec.Code, rec.Body.String())
	}

	if rec := e.do(http.MethodDelete, "/pleya/v1/users/"+member.ID, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("verwijderen gaf %d: %s", rec.Code, rec.Body.String())
	}

	for table, query := range map[string]string{
		"sessions":            `SELECT count(*) FROM sessions WHERE user_id = $1`,
		"library_permissions": `SELECT count(*) FROM library_permissions WHERE user_id = $1`,
		"watch_states":        `SELECT count(*) FROM watch_states WHERE subject = $1`,
	} {
		var count int
		if err := e.pool.QueryRow(ctx, query, member.ID).Scan(&count); err != nil {
			t.Fatal(err)
		}
		if count != 0 {
			t.Fatalf("%s houdt %d rijen van een verwijderde gebruiker", table, count)
		}
	}

	// Het accesstoken van de verwijderde gebruiker is niet meer bruikbaar: de
	// handtekening klopt nog, de gebruiker bestaat niet meer.
	if rec := e.do(http.MethodGet, "/pleya/v1/libraries", nil, asUser(access)); rec.Code != http.StatusNotFound {
		t.Fatalf("een verwijderde gebruiker kreeg %d op /libraries", rec.Code)
	}
}
