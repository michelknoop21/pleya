package api_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

// De grens tussen credential en eigen gegevens (17c.2), en wat er over delen
// in het auditlog komt (17c.3).

func (e *env) tokenPerScope() map[string]string {
	e.t.Helper()
	out := map[string]string{}
	for _, scope := range []string{"read", "maintenance", "admin"} {
		out[scope] = e.createToken(map[string]any{"name": "agent " + scope, "scope": scope}, http.StatusCreated).Secret
	}
	return out
}

func assertScopeRefused(t *testing.T, rec *httptest.ResponseRecorder, scope string) {
	t.Helper()
	var body struct {
		Error struct {
			Code    string         `json:"code"`
			Details map[string]any `json:"details"`
		} `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("antwoord onleesbaar: %s", rec.Body.String())
	}
	if rec.Code != http.StatusForbidden || body.Error.Code != "auth.scope_insufficient" || body.Error.Details["scope"] != scope {
		t.Fatalf("gaf %d, verwacht 403 auth.scope_insufficient met scope %s: %s", rec.Code, scope, rec.Body.String())
	}
}

// Een leestoken van de owner ziet alles wat de owner ziet, maar delen is geen lezen.
func TestListSharingFollowsTheTokenScope(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	tokens := e.tokenPerScope()
	made := e.createCollection(map[string]any{"title": "Privé"})
	path := collectionsPath + "/" + made.ID

	for _, tc := range []struct {
		scope string
		want  int
	}{{"read", http.StatusForbidden}, {"maintenance", http.StatusForbidden}, {"admin", http.StatusNoContent}} {
		t.Run(tc.scope, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPatch, path, strings.NewReader(""))
			asToken(tokens[tc.scope])(req)
			rec := httptest.NewRecorder()
			e.server.ListSharingProbe().ServeHTTP(rec, req)
			if rec.Code != tc.want {
				t.Fatalf("de regel zelf gaf %d, verwacht %d: %s", rec.Code, tc.want, rec.Body.String())
			}
			if tc.want == http.StatusForbidden && !strings.Contains(rec.Body.String(), "library.list_share_not_permitted") {
				t.Fatalf("verkeerde code: %s", rec.Body.String())
			}
		})
	}

	for _, scope := range []string{"read", "maintenance"} {
		rec := e.do(http.MethodPatch, path, map[string]any{"visibility": "everyone"}, asToken(tokens[scope]))
		e.record("ErrorEnvelope", http.MethodPatch, path, rec)
		assertScopeRefused(t, rec, scope)
		rec = e.do(http.MethodPost, collectionsPath, map[string]any{"title": "Open", "visibility": "everyone"}, asToken(tokens[scope]))
		assertScopeRefused(t, rec, scope)
	}
	var read api.Collection
	e.getJSON(path, "Collection", http.StatusOK, &read)
	if read.Visibility != "private" {
		t.Fatalf("een geweigerd token veranderde de zichtbaarheid: %q", read.Visibility)
	}

	rec := e.do(http.MethodPatch, path, map[string]any{"visibility": "everyone"}, asToken(tokens["admin"]))
	if rec.Code != http.StatusOK {
		t.Fatalf("een admintoken van de owner gaf %d: %s", rec.Code, rec.Body.String())
	}
}

func TestAPITokenBelowAdminCannotRewriteOwnData(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	tokens := e.tokenPerScope()
	grease := e.findMovie("Grease")
	e.startAndProgress(grease.ID, "tv", 600_000, 6_720_000)
	history := e.historyIDs()
	collection := e.createCollection(map[string]any{"title": "Blijft"})
	playlist := e.createPlaylist("Blijft")
	collectionPath, playlistPath := collectionsPath+"/"+collection.ID, playlistsPath+"/"+playlist.ID
	e.putItems(collectionPath, http.StatusNoContent, nil, grease.ID)
	e.putItems(playlistPath, http.StatusNoContent, nil, grease.ID)

	items := map[string]any{"item_ids": []string{}}
	title := map[string]any{"title": "Weg"}
	routes := []struct {
		method, path string
		body         any
	}{
		{http.MethodDelete, "/pleya/v1/history", nil},
		{http.MethodDelete, "/pleya/v1/history/" + history[0], nil},
		{http.MethodPost, collectionsPath, title},
		{http.MethodPatch, collectionPath, title},
		{http.MethodDelete, collectionPath, nil},
		{http.MethodPut, collectionPath + "/items", items},
		{http.MethodPost, collectionPath + "/items", items},
		{http.MethodDelete, collectionPath + "/items/" + grease.ID, nil},
		{http.MethodPost, playlistsPath, title},
		{http.MethodPatch, playlistPath, title},
		{http.MethodDelete, playlistPath, nil},
		{http.MethodPut, playlistPath + "/items", items},
		{http.MethodPost, playlistPath + "/items", items},
		{http.MethodDelete, playlistPath + "/items/" + grease.ID, nil},
	}
	for _, scope := range []string{"read", "maintenance"} {
		for _, route := range routes {
			t.Run(scope+" "+route.method+" "+route.path, func(t *testing.T) {
				rec := e.do(route.method, route.path, route.body, asToken(tokens[scope]))
				if strings.Contains(route.path, "/history") || route.method == http.MethodPost {
					e.record("ErrorEnvelope", route.method, route.path, rec)
				}
				assertScopeRefused(t, rec, scope)
			})
		}
	}

	// Niets is geraakt, en lezen blijft mogen.
	if got := e.historyIDs(); len(got) != 1 {
		t.Fatalf("de geschiedenis veranderde: %v", got)
	}
	for _, path := range []string{collectionPath, playlistPath} {
		if got := e.listTitles(path, asToken(tokens["read"])); len(got) != 1 || got[0] != "Grease" {
			t.Fatalf("%s veranderde: %v", path, got)
		}
	}

	// Een admintoken en een gewone sessie halen de grens wel.
	if rec := e.do(http.MethodDelete, "/pleya/v1/history/"+history[0], nil, asToken(tokens["admin"])); rec.Code != http.StatusNoContent {
		t.Fatalf("een admintoken gaf %d: %s", rec.Code, rec.Body.String())
	}
	if rec := e.do(http.MethodDelete, collectionPath+"/items/"+grease.ID, nil, asToken(tokens["admin"])); rec.Code != http.StatusNoContent {
		t.Fatalf("een admintoken gaf %d: %s", rec.Code, rec.Body.String())
	}
	if rec := e.do(http.MethodDelete, "/pleya/v1/history", nil); rec.Code != http.StatusNoContent {
		t.Fatalf("een gewone sessie gaf %d: %s", rec.Code, rec.Body.String())
	}
	if rec := e.do(http.MethodDelete, playlistPath, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("een gewone sessie gaf %d: %s", rec.Code, rec.Body.String())
	}

	// Een lid kan geen admintoken krijgen, dus zijn token komt hier nooit door.
	member := asUser(e.tokenFor(e.createUser("member", "bob")))
	own := e.createToken(map[string]any{"name": "bob", "scope": "read"}, http.StatusCreated, member)
	assertScopeRefused(t, e.do(http.MethodPost, playlistsPath, title, asToken(own.Secret)), "read")
	if rec := e.do(http.MethodPost, playlistsPath, title, member); rec.Code != http.StatusCreated {
		t.Fatalf("de sessie van een lid gaf %d: %s", rec.Code, rec.Body.String())
	}
}

// Beeld 17 noemt de deler, dus owner staat ook in het antwoord aan een lid
// (14b). shared_with blijft van de eigenaar.
func TestOwnerNameIsVisibleToWhoeverSeesTheList(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	recipient := e.createUser("member", "bob")
	kid := asUser(e.tokenFor(e.createUser("restricted", "kim")))
	e.createCollection(map[string]any{"title": "Gedeeld", "visibility": "users", "shared_with": []string{recipient.String()}})
	e.createCollection(map[string]any{"title": "Voor iedereen", "visibility": "everyone"})

	for name, as := range map[string]func(*http.Request){"lid": asUser(e.tokenFor(recipient)), "beperkt": kid} {
		rec := e.do(http.MethodGet, collectionsPath, nil, as)
		var page api.CollectionPage
		e.decodeInto(rec, &page)
		if len(page.Items) == 0 {
			t.Fatalf("%s ziet niets", name)
		}
		for _, list := range page.Items {
			if list.Owner.Username != "michel" || list.SharedWith != nil {
				t.Fatalf("%s: owner %q, shared_with %v", name, list.Owner.Username, list.SharedWith)
			}
		}
	}
}

func TestNULInAListTitleIsAClientError(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	playlist := e.createPlaylist("Goed")
	collection := e.createCollection(map[string]any{"title": "Goed"})
	bad := map[string]any{"title": "a\x00b"}

	for _, tc := range []struct{ method, path string }{
		{http.MethodPost, playlistsPath},
		{http.MethodPost, collectionsPath},
		{http.MethodPatch, playlistsPath + "/" + playlist.ID},
		{http.MethodPatch, collectionsPath + "/" + collection.ID},
	} {
		rec := e.do(tc.method, tc.path, bad)
		if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "library.list_invalid") || !strings.Contains(rec.Body.String(), `"field":"title"`) {
			t.Fatalf("%s %s gaf %d: %s", tc.method, tc.path, rec.Code, rec.Body.String())
		}
	}
}

// Na een lek is dit de vraag: welk credential heeft dit opengezet? Bewaren zonder
// wijziging is geen antwoord op die vraag en geeft geen regel, want de web stuurt
// de zichtbaarheid bij elke hernoeming mee.
func TestAuditRecordsWhoChangedASharedCollection(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	bob := e.createUser("member", "bob")
	ada := e.createUser("member", "ada")
	admin := e.createToken(map[string]any{"name": "beheer", "scope": "admin"}, http.StatusCreated)

	shareRows := func() []api.AuditEntryWire {
		t.Helper()
		var out []api.AuditEntryWire
		for _, entry := range e.auditPage(auditPath+"?limit=100", http.StatusOK).Items {
			if entry.Operation == "createCollection" || entry.Operation == "updateCollection" {
				out = append(out, entry)
			}
		}
		return out
	}
	wantRows := func(step string, want int) {
		t.Helper()
		if got := shareRows(); len(got) != want {
			t.Fatalf("%s: %d regels, verwacht %d: %+v", step, len(got), want, got)
		}
	}

	private := e.createCollection(map[string]any{"title": "Privé"})
	e.createPlaylist("Afspeellijst")
	wantRows("privé maken", 0)

	open := e.createCollection(map[string]any{"title": "Open", "visibility": "everyone"})
	wantRows("meteen delen", 1)
	if got := shareRows()[0]; got.Operation != "createCollection" || got.Target != open.ID || got.Outcome != "ok" {
		t.Fatalf("regel %+v", got)
	}

	path := collectionsPath + "/" + private.ID
	patch := func(body map[string]any, opts ...func(*http.Request)) {
		t.Helper()
		if rec := e.do(http.MethodPatch, path, body, opts...); rec.Code != http.StatusOK {
			t.Fatalf("wijzigen gaf %d: %s", rec.Code, rec.Body.String())
		}
	}
	patch(map[string]any{"title": "Hernoemd"})
	patch(map[string]any{"title": "Nog eens", "visibility": "private"})
	wantRows("hernoemen", 1)

	toBob := map[string]any{"visibility": "users", "shared_with": []string{bob.String()}}
	patch(toBob, asToken(admin.Secret))
	wantRows("delen met bob", 2)
	if got := shareRows()[0]; got.Operation != "updateCollection" || got.Target != private.ID || got.SessionID != admin.Token.ID {
		t.Fatalf("de regel noemt het credential niet: %+v, verwacht sessie %s", got, admin.Token.ID)
	}
	patch(toBob)
	wantRows("dezelfde keuze opnieuw", 2)

	patch(map[string]any{"shared_with": []string{ada.String()}})
	wantRows("andere ontvanger", 3)
	patch(map[string]any{"visibility": "private"})
	wantRows("intrekken", 4)
}

func TestHistoryCursorBelongsToItsKind(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	e.startAndProgress(e.findMovie("Grease").ID, "tv", 600_000, 6_720_000)
	e.startAndProgress(e.findMovie("Blade Runner").ID, "tv2", 300_000, 7_000_000)

	cursorFor := func(query string) string {
		t.Helper()
		var page api.HistoryPage
		e.getJSON("/pleya/v1/history?limit=1"+query, "HistoryPage", http.StatusOK, &page)
		if page.NextCursor == nil {
			t.Fatalf("geen cursor voor %q", query)
		}
		return *page.NextCursor
	}
	filtered, plain := cursorFor("&kind=movie"), cursorFor("")

	for _, tc := range []struct {
		name, query string
		want        int
	}{
		{"zelfde soort", "?kind=movie&cursor=" + filtered, http.StatusOK},
		{"zonder filter", "?cursor=" + plain, http.StatusOK},
		{"andere soort", "?kind=episode&cursor=" + filtered, http.StatusBadRequest},
		{"filter eraf", "?cursor=" + filtered, http.StatusBadRequest},
		{"filter erbij", "?kind=movie&cursor=" + plain, http.StatusBadRequest},
	} {
		rec := e.do(http.MethodGet, "/pleya/v1/history"+tc.query, nil)
		if rec.Code != tc.want {
			t.Fatalf("%s gaf %d, verwacht %d: %s", tc.name, rec.Code, tc.want, rec.Body.String())
		}
		if tc.want == http.StatusBadRequest && !strings.Contains(rec.Body.String(), "library.cursor_invalid") {
			t.Fatalf("%s: verkeerde code: %s", tc.name, rec.Body.String())
		}
	}
}
