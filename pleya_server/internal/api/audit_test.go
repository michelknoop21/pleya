package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/audit"
)

// GET /audit (S1.5, J.2 rij 14), met het bereik uit VRAGENLIJST 23 en de regel
// per mutatie uit K rij 22.

const auditPath = "/pleya/v1/audit"

func (e *env) auditPage(path string, want int, opts ...func(*http.Request)) api.AuditPageWire {
	e.t.Helper()
	rec := e.do(http.MethodGet, path, nil, opts...)
	if rec.Code != want {
		e.t.Fatalf("GET %s gaf %d, verwacht %d: %s", path, rec.Code, want, rec.Body.String())
	}
	if want != http.StatusOK {
		return api.AuditPageWire{}
	}
	e.record("AuditPage", http.MethodGet, auditPath, rec)

	var out api.AuditPageWire
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatalf("antwoord onleesbaar: %v", err)
	}
	return out
}

// operations telt hoe vaak elke operatie met deze uitkomst in de lijst staat.
func operations(page api.AuditPageWire) map[string]int {
	out := map[string]int{}
	for _, entry := range page.Items {
		out[entry.Operation+":"+entry.Outcome]++
	}
	return out
}

// K rij 22, vierde test: elke mutatie krijgt een regel, en het bereik is dat
// van VRAGENLIJST 23 en niet alleen de beheerendpoints.
//
// De test doet elke beherende handeling die vandaag bestaat en telt daarna. Een
// implementatie die de haak op een handler vergeet zakt hier, en dat is precies
// de fout die anders pas na een incident opvalt.
func TestAuditCoversEveryAdministrativeMutation(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	// Een geslaagde en een mislukte login.
	if rec := e.do(http.MethodPost, "/pleya/v1/auth/login", map[string]string{
		"username": "michel", "password": "een-lang-genoeg-wachtwoord",
	}, withoutAuth); rec.Code != http.StatusOK {
		t.Fatalf("login gaf %d", rec.Code)
	}
	if rec := e.do(http.MethodPost, "/pleya/v1/auth/login", map[string]string{
		"username": "michel", "password": "fout",
	}, withoutAuth); rec.Code != http.StatusUnauthorized {
		t.Fatalf("de mislukte login gaf %d", rec.Code)
	}

	// Gebruikersbeheer: aanmaken, wijzigen, rechten, verwijderen.
	target := e.createUser("member", "sanne")
	created := e.do(http.MethodPost, "/pleya/v1/users", map[string]string{
		"username": "wim", "password": "een-lang-genoeg-wachtwoord", "role": "member",
	})
	if created.Code != http.StatusOK {
		t.Fatalf("POST /users gaf %d: %s", created.Code, created.Body.String())
	}
	var createdUser api.UserWire
	if err := json.Unmarshal(created.Body.Bytes(), &createdUser); err != nil {
		t.Fatal(err)
	}
	if rec := e.do(http.MethodPatch, "/pleya/v1/users/"+createdUser.ID,
		map[string]string{"role": "admin"}); rec.Code != http.StatusOK {
		t.Fatalf("PATCH /users gaf %d: %s", rec.Code, rec.Body.String())
	}
	if rec := e.do(http.MethodPut, "/pleya/v1/users/"+target.String()+"/permissions",
		map[string]any{"permissions": []map[string]string{
			{"library_id": e.libs[0].ID.String(), "permission": "view"},
		}}); rec.Code != http.StatusOK {
		t.Fatalf("PUT permissions gaf %d: %s", rec.Code, rec.Body.String())
	}
	if rec := e.do(http.MethodDelete, "/pleya/v1/users/"+createdUser.ID, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("DELETE /users gaf %d: %s", rec.Code, rec.Body.String())
	}

	// Securitygevoelige configuratie.
	if rec := e.do(http.MethodPatch, "/pleya/v1/settings",
		map[string]any{"access_token_ttl": "30m"}); rec.Code != http.StatusOK {
		t.Fatalf("PATCH /settings gaf %d: %s", rec.Code, rec.Body.String())
	}

	// Een token aanmaken en weer intrekken.
	token := e.createToken(map[string]any{"name": "agent", "scope": "read"}, http.StatusCreated)
	if rec := e.do(http.MethodDelete, "/pleya/v1/sessions/"+token.Token.ID, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("intrekken gaf %d", rec.Code)
	}

	got := operations(e.auditPage(auditPath, http.StatusOK))
	for _, want := range []string{
		"setup:ok",
		"login:ok",
		"login:denied",
		"createUser:ok",
		"updateUser:ok",
		"setPermissions:ok",
		"deleteUser:ok",
		"patchSettings:ok",
		"createApiToken:ok",
		"revokeSession:ok",
	} {
		if got[want] < 1 {
			t.Errorf("het auditlog mist %s; wat er staat: %+v", want, got)
		}
	}
}

// Wat er niet in het auditlog hoort (VRAGENLIJST 23): catalogusreads en
// playbackticks. Volume zonder beveiligingsbetekenis, en een log dat daarin
// verdrinkt wordt niet gelezen.
func TestAuditIgnoresReadsAndPlaybackTicks(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	before := len(e.auditPage(auditPath, http.StatusOK).Items)

	grease := e.findMovie("Grease")
	for i := 0; i < 5; i++ {
		e.do(http.MethodGet, "/pleya/v1/libraries", nil)
		e.do(http.MethodGet, "/pleya/v1/items/"+grease.ID, nil)
		e.do(http.MethodGet, "/pleya/v1/sessions", nil)
		e.do(http.MethodGet, auditPath, nil)
	}
	e.report(event(grease.ID, "tv", map[string]any{"position_ms": 1000}), http.StatusOK)

	after := len(e.auditPage(auditPath, http.StatusOK).Items)
	if after != before {
		t.Fatalf("het auditlog groeide van %d naar %d regels door reads en een tick", before, after)
	}
}

// Een mislukte login draagt geen user_id.
//
// De naam die geprobeerd is staat wel in de tabel, maar niet in het antwoord en
// niet als identiteit: een niet-bestaande naam koppelen aan een uuid zou een
// gebruiker impliceren die er niet is, en een bestaande naam koppelen zou het
// account van een ander een mislukte login in de schoenen schuiven.
func TestFailedLoginCarriesNoIdentity(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	if rec := e.do(http.MethodPost, "/pleya/v1/auth/login", map[string]string{
		"username": "michel", "password": "fout",
	}, withoutAuth); rec.Code != http.StatusUnauthorized {
		t.Fatalf("de mislukte login gaf %d", rec.Code)
	}

	page := e.auditPage(auditPath, http.StatusOK)
	var found bool
	for _, entry := range page.Items {
		if entry.Operation != "login" || entry.Outcome != "denied" {
			continue
		}
		found = true
		if entry.UserID != "" || entry.SessionID != "" {
			t.Errorf("de mislukte login draagt een identiteit: %+v", entry)
		}
	}
	if !found {
		t.Fatalf("de mislukte login staat niet in het log: %+v", page.Items)
	}

	// De geslaagde login draagt er wel een, en dat is het onderscheid dat de
	// regel bruikbaar maakt.
	if rec := e.do(http.MethodPost, "/pleya/v1/auth/login", map[string]string{
		"username": "michel", "password": "een-lang-genoeg-wachtwoord",
	}, withoutAuth); rec.Code != http.StatusOK {
		t.Fatalf("login gaf %d", rec.Code)
	}
	page = e.auditPage(auditPath, http.StatusOK)
	for _, entry := range page.Items {
		if entry.Operation == "login" && entry.Outcome == "ok" {
			if entry.UserID == "" || entry.SessionID == "" {
				t.Fatalf("de geslaagde login draagt geen identiteit: %+v", entry)
			}
			return
		}
	}
	t.Fatal("de geslaagde login staat niet in het log")
}

// De drie rollen (K rij 2).
func TestAuditThreeRoles(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	admin := e.tokenFor(e.createUser("admin", "aya"))
	member := e.tokenFor(e.createUser("member", "sanne"))
	restricted := e.tokenFor(e.createUser("restricted", "kind"))

	e.auditPage(auditPath, http.StatusOK)
	e.auditPage(auditPath, http.StatusOK, asUser(admin))
	e.auditPage(auditPath, http.StatusNotFound, asUser(member))
	e.auditPage(auditPath, http.StatusNotFound, asUser(restricted))

	memberBody := e.do(http.MethodGet, auditPath, nil, asUser(member)).Body.String()
	restrictedBody := e.do(http.MethodGet, auditPath, nil, asUser(restricted)).Body.String()
	if memberBody != restrictedBody {
		t.Fatalf("de weigering verschilt per rol:\n%s\n%s", memberBody, restrictedBody)
	}

	other := e.do(http.MethodPatch, "/pleya/v1/users/"+e.createUser("member", "wim").String(),
		map[string]string{"role": "admin"}, asUser(member))
	if other.Body.String() != memberBody {
		t.Fatalf("de weigering van /audit verschilt van die van een beheerhandeling op een ander:\n%s\n%s",
			memberBody, other.Body.String())
	}

	if rec := e.do(http.MethodGet, auditPath, nil, withoutAuth); rec.Code != http.StatusUnauthorized {
		t.Fatalf("zonder token gaf %d, verwacht 401", rec.Code)
	}
}

// Pagineren, filteren en de grenzen eromheen.
func TestAuditPagesFiltersAndBounds(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	// Genoeg regels om over twee pagina's te lopen. Mislukte logins, want die
	// zijn goedkoop en dragen geen identiteit die de test moet opruimen.
	for i := 0; i < 5; i++ {
		e.do(http.MethodPost, "/pleya/v1/auth/login",
			map[string]string{"username": "michel", "password": "fout"}, withoutAuth)
	}

	first := e.auditPage(auditPath+"?limit=3", http.StatusOK)
	if len(first.Items) != 3 || first.NextCursor == nil {
		t.Fatalf("de eerste pagina heeft %d regels, cursor %v", len(first.Items), first.NextCursor)
	}
	second := e.auditPage(auditPath+"?limit=3&cursor="+*first.NextCursor, http.StatusOK)
	if len(second.Items) == 0 {
		t.Fatal("de tweede pagina is leeg")
	}
	for _, a := range first.Items {
		for _, b := range second.Items {
			if a.ID == b.ID {
				t.Fatalf("regel %s staat op beide pagina's", a.ID)
			}
		}
	}

	// Nieuwste eerst.
	for i := 1; i < len(first.Items); i++ {
		prev, _ := time.Parse(time.RFC3339, first.Items[i-1].At)
		cur, _ := time.Parse(time.RFC3339, first.Items[i].At)
		if cur.After(prev) {
			t.Fatalf("de volgorde is niet aflopend: %s na %s", first.Items[i].At, first.Items[i-1].At)
		}
	}

	// Filteren op bron.
	if page := e.auditPage(auditPath+"?source=http", http.StatusOK); len(page.Items) == 0 {
		t.Fatal("source=http levert niets op terwijl alles via http binnenkwam")
	}
	if page := e.auditPage(auditPath+"?source=mcp", http.StatusOK); len(page.Items) != 0 {
		t.Fatalf("source=mcp levert %d regels op terwijl er nog geen MCP is", len(page.Items))
	}
	// Een onbekende bron is een filter dat niets oplevert, geen fout.
	if page := e.auditPage(auditPath+"?source=telepathie", http.StatusOK); len(page.Items) != 0 {
		t.Fatalf("een onbekende bron leverde %d regels op", len(page.Items))
	}

	// Een cursor die niet van dit endpoint komt.
	if rec := e.do(http.MethodGet, auditPath+"?cursor=nietvanhier", nil); rec.Code != http.StatusBadRequest {
		t.Fatalf("een kapotte cursor gaf %d, verwacht 400", rec.Code)
	}

	// De bovengrens van limit is geen fout maar een klem.
	if page := e.auditPage(auditPath+"?limit=100000", http.StatusOK); len(page.Items) == 0 {
		t.Fatal("een limiet boven het maximum leverde niets op")
	}
}

// De bewaartermijn is negentig dagen (VRAGENLIJST 23), en de opruimronde
// gebruikt dezelfde constante als het commentaar op de tabel belooft.
func TestAuditPurgeKeepsNinetyDays(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	ctx := context.Background()
	now := time.Now().UTC()

	if err := e.audit.Write(ctx, now.Add(-91*24*time.Hour), audit.Entry{
		Source: audit.SourceHTTP, Operation: "login", Outcome: audit.OutcomeOK,
	}); err != nil {
		t.Fatal(err)
	}
	if err := e.audit.Write(ctx, now.Add(-89*24*time.Hour), audit.Entry{
		Source: audit.SourceHTTP, Operation: "login", Outcome: audit.OutcomeOK,
	}); err != nil {
		t.Fatal(err)
	}

	before := len(e.auditPage(auditPath, http.StatusOK).Items)
	removed, err := e.audit.Purge(ctx, now.Add(-audit.Retention))
	if err != nil {
		t.Fatal(err)
	}
	if removed != 1 {
		t.Fatalf("de opruimronde haalde %d regels weg, verwacht precies de regel van 91 dagen oud", removed)
	}
	if after := len(e.auditPage(auditPath, http.StatusOK).Items); after != before-1 {
		t.Fatalf("er staan %d regels, verwacht %d", after, before-1)
	}
	if audit.Retention != 90*24*time.Hour {
		t.Fatalf("de bewaartermijn is %s, en het tabelcommentaar belooft negentig dagen", audit.Retention)
	}
}
