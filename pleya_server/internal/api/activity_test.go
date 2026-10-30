package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// GET /items/{id}/activity en de opt-out (DEC-169, matrixregels 74 tot en met
// 76). De vier rollen op de route zelf staan in authorize_matrix_test.go; hier
// staat wat er in het antwoord zit, en vooral wat er niet in zit.

const activitySharingPath = "/pleya/v1/users/me/activity-sharing"

func activityPath(itemID string) string { return "/pleya/v1/items/" + itemID + "/activity" }

// activity leest de activiteit als deze gebruiker.
func (e *env) activity(itemID, token string) api.ItemActivityWire {
	e.t.Helper()
	rec := e.do(http.MethodGet, activityPath(itemID), nil, asUser(token))
	if rec.Code != http.StatusOK {
		e.t.Fatalf("activiteit gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("ItemActivity", http.MethodGet, "/pleya/v1/items/{item_id}/activity", rec)
	var out api.ItemActivityWire
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatalf("antwoord onleesbaar: %v", err)
	}
	return out
}

// playAs speelt een item in één sessie als deze gebruiker. e.access staat er
// daarna weer op zoals hij stond.
func (e *env) playAs(token, itemID, session string, completed bool) {
	e.t.Helper()
	previous := e.access
	e.access = token
	defer func() { e.access = previous }()

	started := e.report(event(itemID, session, map[string]any{
		"explicit_action": "playback_started", "cause": "user_started",
	}), http.StatusOK)
	e.report(event(itemID, session, map[string]any{
		"position_ms": 60000, "duration_ms": 6000000, "base_revision": started.Revision, "completed": completed,
	}), http.StatusOK)
}

func (e *env) shareActivity(token string, share bool) {
	e.t.Helper()
	rec := e.do(http.MethodPut, activitySharingPath, map[string]bool{"share_activity": share}, asUser(token))
	if rec.Code != http.StatusOK {
		e.t.Fatalf("opt-out zetten gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("ActivitySharing", http.MethodPut, activitySharingPath, rec)
}

func (e *env) sharesActivity(token string) bool {
	e.t.Helper()
	rec := e.do(http.MethodGet, activitySharingPath, nil, asUser(token))
	if rec.Code != http.StatusOK {
		e.t.Fatalf("opt-out lezen gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("ActivitySharing", http.MethodGet, activitySharingPath, rec)
	var out api.ActivitySharingWire
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatalf("antwoord onleesbaar: %v", err)
	}
	return out.ShareActivity
}

// member maakt een gebruiker met leesrecht op de genoemde bibliotheken.
func (e *env) member(role, name string, kinds ...string) (id.ID, string) {
	e.t.Helper()
	user := e.createUser(role, name)
	for _, kind := range kinds {
		e.grantLibrary(user, id.MustParse(e.libraryID(kind)), "view")
	}
	return user, e.tokenFor(user)
}

func usernames(a api.ItemActivityWire) []string {
	out := make([]string, 0, len(a.Items))
	for _, it := range a.Items {
		out = append(out, it.Username)
	}
	return out
}

func entryOf(t *testing.T, a api.ItemActivityWire, username string) api.ItemActivityEntryWire {
	t.Helper()
	for _, it := range a.Items {
		if it.Username == username {
			return it
		}
	}
	t.Fatalf("%s staat niet in %v", username, usernames(a))
	return api.ItemActivityEntryWire{}
}

// De basis: iedereen in het huishouden ziet wie iets keek, de laatste eerst, en
// is_self volgt de aanvrager.
func TestItemActivityShowsTheHousehold(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease").ID
	owner := e.access
	_, sam := e.member("member", "sam", "movies")

	e.playAs(owner, movie, "tv", true)
	e.playAs(sam, movie, "ipad", false)

	got := e.activity(movie, owner)
	if names := usernames(got); len(names) != 2 || names[0] != "sam" || names[1] != "michel" {
		t.Fatalf("volgorde %v, verwacht de laatste kijker eerst", names)
	}
	self := entryOf(t, got, "michel")
	if !self.IsSelf || self.CompletedItems != 1 || self.PlayCount != 1 || self.Initials != "M" || self.LastWatchedAt == "" {
		t.Errorf("eigen regel %+v", self)
	}
	other := entryOf(t, got, "sam")
	if other.IsSelf || other.CompletedItems != 0 || other.PlayCount != 1 {
		t.Errorf("regel van sam %+v", other)
	}

	seenBySam := e.activity(movie, sam)
	if !entryOf(t, seenBySam, "sam").IsSelf || entryOf(t, seenBySam, "michel").IsSelf {
		t.Errorf("is_self volgt de aanvrager niet: %+v", seenBySam.Items)
	}

	rec := e.do(http.MethodGet, activityPath(movie), nil, asUser(sam))
	if rec.Header().Get("Cache-Control") != "no-store" {
		t.Errorf("Cache-Control %q; dit antwoord verschilt per aanvrager", rec.Header().Get("Cache-Control"))
	}
	for _, leak := range []string{"device", "session", "position"} {
		if strings.Contains(rec.Body.String(), leak) {
			t.Errorf("het antwoord noemt %q: %s", leak, rec.Body.String())
		}
	}
}

// Een item zonder sessies is een lege lijst en geen fout, en markeren als gezien
// is geen afspelen (DEC-159, punt 1).
func TestItemActivityIsEmptyWithoutPlays(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease").ID

	e.markWatched(movie, "tv")

	rec := e.do(http.MethodGet, activityPath(movie), nil)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"items":[]`) {
		t.Fatalf("gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("ItemActivity", http.MethodGet, "/pleya/v1/items/{item_id}/activity", rec)
}

// Een serie telt alle afleveringen eronder, een seizoen de zijne, een aflevering
// alleen zichzelf. De fixture heeft twee afleveringen in seizoen 1 en één in
// seizoen 2.
func TestItemActivityAggregatesSeasonAndSeries(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	owner := e.access
	_, sam := e.member("member", "sam", "shows")

	var shows api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+e.libraryID("shows")+"/items", "", http.StatusOK, &shows)
	series := shows.Items[0].ID
	var seasons api.ItemPage
	e.getJSON("/pleya/v1/items/"+series+"/children", "", http.StatusOK, &seasons)
	first, second := seasons.Items[0].ID, seasons.Items[1].ID
	episodes := e.episodesInOrder()
	e9, e10, s2e1 := episodes[0].ID, episodes[1].ID, episodes[2].ID

	e.playAs(owner, e9, "tv-1", true)
	e.playAs(owner, e9, "tv-2", true)
	e.playAs(owner, e10, "tv-3", false)
	e.playAs(sam, s2e1, "ipad", true)

	episode := entryOf(t, e.activity(e9, owner), "michel")
	if episode.PlayCount != 2 || episode.CompletedItems != 1 {
		t.Errorf("aflevering: %+v, twee sessies op één uitgekeken item", episode)
	}

	season := e.activity(first, owner)
	if len(season.Items) != 1 {
		t.Fatalf("seizoen 1 noemt %v, sam keek alleen seizoen 2", usernames(season))
	}
	if got := season.Items[0]; got.PlayCount != 3 || got.CompletedItems != 1 {
		t.Errorf("seizoen 1: %+v", got)
	}
	if got := e.activity(second, owner); len(got.Items) != 1 || got.Items[0].Username != "sam" {
		t.Errorf("seizoen 2: %v", usernames(got))
	}

	whole := e.activity(series, owner)
	if len(whole.Items) != 2 || whole.Items[0].Username != "sam" {
		t.Fatalf("serie: %v, verwacht beide kijkers met de laatste eerst", usernames(whole))
	}
	if got := entryOf(t, whole, "michel"); got.PlayCount != 3 || got.CompletedItems != 1 {
		t.Errorf("serie, michel: %+v", got)
	}
	if got := entryOf(t, whole, "sam"); got.PlayCount != 1 || got.CompletedItems != 1 {
		t.Errorf("serie, sam: %+v", got)
	}
}

// Bibliotheekrechten tellen twee keer: de aanvrager moet het item mogen zien, en
// een andere gebruiker telt alleen mee zolang hij het zelf ook mag zien.
func TestItemActivityFollowsLibraryRights(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease").ID
	owner := e.access
	samID, sam := e.member("member", "sam", "movies")
	_, outsider := e.member("member", "kim", "shows")

	e.playAs(sam, movie, "ipad", true)

	rec := e.do(http.MethodGet, activityPath(movie), nil, asUser(outsider))
	missing := e.do(http.MethodGet, activityPath(id.New().String()), nil, asUser(outsider))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("een item buiten bereik gaf %d: %s", rec.Code, rec.Body.String())
	}
	if rec.Body.String() != missing.Body.String() {
		t.Fatalf("item buiten bereik en onbekend item verschillen:\n%s\n%s", rec.Body.String(), missing.Body.String())
	}

	// Sam verliest de bibliotheek: zijn rijen blijven bestaan, hij telt niet meer mee.
	films := id.MustParse(e.libraryID("movies"))
	e.revokeLibrary(samID, films)
	if got := e.activity(movie, owner); len(got.Items) != 0 {
		t.Fatalf("na het intrekken staat er nog %v", usernames(got))
	}
	if rec := e.do(http.MethodGet, activityPath(movie), nil, asUser(sam)); rec.Code != http.StatusNotFound {
		t.Fatalf("sam kreeg na het intrekken %d", rec.Code)
	}
	e.grantLibrary(samID, films, "view")
	if got := e.activity(movie, owner); len(got.Items) != 1 || got.Items[0].Username != "sam" {
		t.Fatalf("na het terugzetten: %v", usernames(got))
	}
}

// De keuze verbergt iemand voor iedereen behalve hemzelf, ook voor een
// beheerder en ook in de optelling van een serie, en hij geldt meteen.
func TestItemActivityOptOutHidesFromOthersOnly(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease").ID
	owner := e.access
	_, sam := e.member("member", "sam", "movies", "shows")
	_, kim := e.member("member", "kim", "movies")
	_, admin := e.member("admin", "beheer")
	var shows api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+e.libraryID("shows")+"/items", "", http.StatusOK, &shows)
	series := shows.Items[0].ID
	episode := e.episodesInOrder()[0].ID

	e.playAs(owner, movie, "tv", true)
	e.playAs(sam, movie, "ipad", true)
	e.playAs(sam, episode, "ipad", true)

	if !e.sharesActivity(sam) {
		t.Fatal("een nieuwe gebruiker hoort standaard te delen")
	}
	e.shareActivity(sam, false)
	if e.sharesActivity(sam) {
		t.Fatal("de opt-out is niet bewaard")
	}
	if !e.sharesActivity(owner) {
		t.Fatal("de opt-out van sam raakte de owner")
	}

	for name, token := range map[string]string{"owner": owner, "beheerder": admin, "lid": kim} {
		if got := e.activity(movie, token); len(got.Items) != 1 || got.Items[0].Username != "michel" {
			t.Errorf("%s ziet %v", name, usernames(got))
		}
	}
	if got := e.activity(series, owner); len(got.Items) != 0 {
		t.Errorf("de serie noemt nog %v", usernames(got))
	}

	// Zelf blijft hij zichzelf zien, en de anderen ook.
	own := e.activity(movie, sam)
	if len(own.Items) != 2 || !entryOf(t, own, "sam").IsSelf {
		t.Fatalf("sam ziet %v", usernames(own))
	}

	e.shareActivity(sam, true)
	if got := e.activity(movie, kim); len(got.Items) != 2 {
		t.Fatalf("na aanzetten: %v", usernames(got))
	}
}

// De beheerroute kijkt bewust niet naar de opt-out; dat staat zo in DEC-143 en
// in het besluit, en deze test houdt die twee uit elkaar.
func TestActivityOptOutDoesNotReachTheAdminHistory(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease").ID
	owner := e.access
	_, sam := e.member("member", "sam", "movies")

	e.access = sam
	e.markWatched(movie, "ipad")
	e.access = owner
	e.shareActivity(sam, false)

	got := e.watchHistory("?days=7", http.StatusOK)
	if len(got.Items) != 1 || got.Items[0].Username != "sam" {
		t.Fatalf("beheerhistorie %+v", got.Items)
	}
}

func TestActivitySharingRejectsABadBody(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	for _, body := range []string{`{}`, `{"share_activity":null}`, `{"share_activity":"nee"}`,
		`{"share_activity":false,"reden":"x"}`, ``} {
		rec := e.do(http.MethodPut, activitySharingPath, nil, rawBody(body))
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("body %q gaf %d: %s", body, rec.Code, rec.Body.String())
		}
		e.expectCode(rec, api.CodePersonalInvalid)
	}
	if !e.sharesActivity(e.access) {
		t.Fatal("een afgewezen aanvraag veranderde de keuze")
	}
}

// De vlag en de routes horen bij elkaar: zonder opslag zegt de server nee en
// zijn alle drie de routes onbekend.
func TestActivityCapabilityFollowsTheStore(t *testing.T) {
	e := newEnv(t)
	var info api.Info
	e.getJSON("/pleya/v1/info", "Info", http.StatusOK, &info)
	if !info.Capabilities.ItemActivity {
		t.Fatal("de vlag staat uit terwijl de opslag er is")
	}

	bare := newEnv(t, func(o *api.Options) { o.Personal = nil })
	bare.setup(bare.putSetupCode())
	var without api.Info
	bare.getJSON("/pleya/v1/info", "Info", http.StatusOK, &without)
	if without.Capabilities.ItemActivity {
		t.Fatal("de vlag staat aan zonder opslag")
	}
	movie := bare.findMovie("Grease").ID
	for _, probe := range []struct {
		method, path string
		body         any
	}{
		{http.MethodGet, activityPath(movie), nil},
		{http.MethodGet, activitySharingPath, nil},
		{http.MethodPut, activitySharingPath, map[string]bool{"share_activity": false}},
	} {
		rec := bare.do(probe.method, probe.path, probe.body)
		if rec.Code != http.StatusNotFound {
			t.Fatalf("%s %s gaf %d zonder opslag", probe.method, probe.path, rec.Code)
		}
		bare.expectCode(rec, api.CodeNotFound)
	}
}

// Een accesstoken dat zijn gebruiker overleeft krijgt een 404 en geen 500,
// dezelfde uitkomst als GET /users/me.
func TestActivitySharingAfterTheUserIsGone(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	user, token := e.member("member", "sam")
	if _, err := e.pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, user); err != nil {
		t.Fatal(err)
	}
	for _, method := range []string{http.MethodGet, http.MethodPut} {
		rec := e.do(method, activitySharingPath, map[string]bool{"share_activity": false}, asUser(token))
		if rec.Code != http.StatusNotFound {
			t.Fatalf("%s gaf %d", method, rec.Code)
		}
		e.expectCode(rec, api.CodeUserNotFound)
	}
}
