package api_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

const (
	collectionsPath = "/pleya/v1/collections"
	playlistsPath   = "/pleya/v1/playlists"
)

func (e *env) createCollection(body map[string]any, opts ...func(*http.Request)) api.Collection {
	e.t.Helper()
	rec := e.do(http.MethodPost, collectionsPath, body, opts...)
	e.record("Collection", http.MethodPost, collectionsPath, rec)
	if rec.Code != http.StatusCreated {
		e.t.Fatalf("verzameling maken gaf %d: %s", rec.Code, rec.Body.String())
	}
	var c api.Collection
	e.decodeInto(rec, &c)
	return c
}

func (e *env) createPlaylist(title string, opts ...func(*http.Request)) api.Playlist {
	e.t.Helper()
	rec := e.do(http.MethodPost, playlistsPath, map[string]any{"title": title}, opts...)
	e.record("Playlist", http.MethodPost, playlistsPath, rec)
	if rec.Code != http.StatusCreated {
		e.t.Fatalf("afspeellijst maken gaf %d: %s", rec.Code, rec.Body.String())
	}
	var p api.Playlist
	e.decodeInto(rec, &p)
	return p
}

func (e *env) putItems(path string, want int, opts []func(*http.Request), ids ...string) {
	e.t.Helper()
	if ids == nil {
		ids = []string{}
	}
	rec := e.do(http.MethodPut, path+"/items", map[string]any{"item_ids": ids}, opts...)
	if rec.Code != want {
		e.t.Fatalf("PUT items gaf %d, verwacht %d: %s", rec.Code, want, rec.Body.String())
	}
}

func (e *env) listTitles(path string, opts ...func(*http.Request)) []string {
	e.t.Helper()
	rec := e.do(http.MethodGet, path+"/items", nil, opts...)
	e.record("ItemPage", http.MethodGet, path+"/items", rec)
	if rec.Code != http.StatusOK {
		e.t.Fatalf("items lezen gaf %d: %s", rec.Code, rec.Body.String())
	}
	var page api.ItemPage
	e.decodeInto(rec, &page)
	out := make([]string, 0, len(page.Items))
	for _, it := range page.Items {
		out = append(out, it.Title)
	}
	return out
}

func TestPlaylistFlowThroughTheProtocol(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease, matrix := e.findMovie("Grease"), e.findMovie("The Matrix")

	list := e.createPlaylist("  Avond  ")
	if list.Title != "Avond" || list.ItemCount != 0 || len(list.Artwork) != 0 {
		t.Fatalf("nieuwe lijst: %+v", list)
	}
	path := playlistsPath + "/" + list.ID

	e.putItems(path, http.StatusNoContent, nil, matrix.ID, grease.ID)
	if got := strings.Join(e.listTitles(path), ","); got != "The Matrix,Grease" {
		t.Fatalf("volgorde %s", got)
	}

	// Herordenen, en een dubbel item verandert niets.
	e.putItems(path, http.StatusBadRequest, nil, grease.ID, grease.ID)
	if got := strings.Join(e.listTitles(path), ","); got != "The Matrix,Grease" {
		t.Fatalf("een geweigerde PUT veranderde de lijst: %s", got)
	}
	e.putItems(path, http.StatusNoContent, nil, grease.ID, matrix.ID)
	if got := strings.Join(e.listTitles(path), ","); got != "Grease,The Matrix" {
		t.Fatalf("volgorde %s", got)
	}

	var read api.Playlist
	e.getJSON(path, "Playlist", http.StatusOK, &read)
	want := *grease.DurationMs + *matrix.DurationMs
	if read.ItemCount != 2 || read.DurationMs != want {
		t.Fatalf("telling %d en duur %d, verwacht 2 en %d", read.ItemCount, read.DurationMs, want)
	}

	var page api.PlaylistPage
	e.getJSON(playlistsPath, "PlaylistPage", http.StatusOK, &page)
	if len(page.Items) != 1 || page.Items[0].ID != list.ID {
		t.Fatalf("lijst van lijsten: %+v", page.Items)
	}

	rec := e.do(http.MethodPatch, path, map[string]any{"title": "Zondag"})
	e.record("Playlist", http.MethodPatch, path, rec)
	if rec.Code != http.StatusOK {
		t.Fatalf("hernoemen gaf %d", rec.Code)
	}

	// Toevoegen is herhaalbaar en zet achteraan; verwijderen ook.
	for range 2 {
		if rec := e.do(http.MethodPost, path+"/items", map[string]any{"item_ids": []string{grease.ID}}); rec.Code != http.StatusNoContent {
			t.Fatalf("toevoegen gaf %d: %s", rec.Code, rec.Body.String())
		}
	}
	if got := strings.Join(e.listTitles(path), ","); got != "Grease,The Matrix" {
		t.Fatalf("herhaald toevoegen verschoof de lijst: %s", got)
	}
	for range 2 {
		if rec := e.do(http.MethodDelete, path+"/items/"+matrix.ID, nil); rec.Code != http.StatusNoContent {
			t.Fatalf("verwijderen gaf %d: %s", rec.Code, rec.Body.String())
		}
	}
	if got := strings.Join(e.listTitles(path), ","); got != "Grease" {
		t.Fatalf("na verwijderen: %s", got)
	}

	if rec := e.do(http.MethodDelete, path, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("lijst wissen gaf %d", rec.Code)
	}
	if rec := e.do(http.MethodGet, path, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("een gewiste lijst gaf %d", rec.Code)
	}
}

func TestPlaylistRefusesWhatDoesNotPlay(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	var show string
	if err := e.pool.QueryRow(t.Context(), `SELECT id::text FROM media_items WHERE kind = 'show' LIMIT 1`).Scan(&show); err != nil {
		t.Fatal(err)
	}
	list := e.createPlaylist("Avond")
	rec := e.do(http.MethodPut, playlistsPath+"/"+list.ID+"/items", map[string]any{"item_ids": []string{show}})
	if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "library.list_invalid") {
		t.Fatalf("een serie in een afspeellijst gaf %d: %s", rec.Code, rec.Body.String())
	}
	collection := e.createCollection(map[string]any{"title": "Set"})
	e.putItems(collectionsPath+"/"+collection.ID, http.StatusNoContent, nil, show)
}

func TestCollectionVisibilityBetweenTwoUsers(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	bobID := e.createUser("member", "bob")
	carolID := e.createUser("member", "carol")
	library := e.libs[0].ID
	e.grantLibrary(bobID, library, "view")
	e.grantLibrary(carolID, library, "view")
	bob, carol := asUser(e.tokenFor(bobID)), asUser(e.tokenFor(carolID))
	movie := e.findMovie("Grease")

	private := e.createCollection(map[string]any{"title": "Privé"})
	everyone := e.createCollection(map[string]any{"title": "Open", "visibility": "everyone"})
	shared := e.createCollection(map[string]any{"title": "Voor Bob", "visibility": "users", "shared_with": []string{bobID.String()}})
	if len(shared.SharedWith) != 1 || shared.SharedWith[0].Username != "bob" {
		t.Fatalf("de eigenaar ziet zijn ontvanger niet: %+v", shared.SharedWith)
	}
	for _, c := range []api.Collection{private, everyone, shared} {
		e.putItems(collectionsPath+"/"+c.ID, http.StatusNoContent, nil, movie.ID)
	}

	cases := []struct {
		name string
		id   string
		as   func(*http.Request)
		want int
	}{
		{"privé door bob", private.ID, bob, http.StatusNotFound},
		{"open door bob", everyone.ID, bob, http.StatusOK},
		{"gedeeld door bob", shared.ID, bob, http.StatusOK},
		{"gedeeld door carol", shared.ID, carol, http.StatusNotFound},
	}
	missing := e.do(http.MethodGet, collectionsPath+"/"+id.New().String(), nil, bob).Body.String()
	for _, c := range cases {
		rec := e.do(http.MethodGet, collectionsPath+"/"+c.id, nil, c.as)
		if rec.Code != c.want {
			t.Errorf("%s gaf %d, verwacht %d", c.name, rec.Code, c.want)
		}
		if c.want == http.StatusNotFound && rec.Body.String() != missing {
			t.Errorf("%s verschilt van een id dat niet bestaat: %s", c.name, rec.Body.String())
		}
	}

	var page api.CollectionPage
	rec := e.do(http.MethodGet, collectionsPath, nil, bob)
	e.record("CollectionPage", http.MethodGet, collectionsPath, rec)
	e.decodeInto(rec, &page)
	if len(page.Items) != 2 {
		t.Fatalf("bob ziet %d verzamelingen, verwacht 2", len(page.Items))
	}
	for _, c := range page.Items {
		if c.IsOwner || c.SharedWith != nil || c.Owner.Username == "" {
			t.Fatalf("bob ziet eigendom verkeerd: %+v", c)
		}
	}
	mine := e.do(http.MethodGet, collectionsPath+"?owned=true", nil, bob)
	e.decodeInto(mine, &page)
	if len(page.Items) != 0 {
		t.Fatalf("owned=true gaf %d verzamelingen van een ander", len(page.Items))
	}

	// Schrijven door wie wel kijkt maar niet bezit.
	open := collectionsPath + "/" + everyone.ID
	writes := []struct {
		name         string
		method, path string
		body         any
	}{
		{"PATCH", http.MethodPatch, open, map[string]any{"title": "Van mij"}},
		{"DELETE", http.MethodDelete, open, nil},
		{"PUT items", http.MethodPut, open + "/items", map[string]any{"item_ids": []string{}}},
		{"POST items", http.MethodPost, open + "/items", map[string]any{"item_ids": []string{movie.ID}}},
		{"DELETE item", http.MethodDelete, open + "/items/" + movie.ID, nil},
	}
	for _, write := range writes {
		rec := e.do(write.method, write.path, write.body, bob)
		if rec.Code != http.StatusForbidden || !strings.Contains(rec.Body.String(), "library.list_not_owner") {
			t.Errorf("%s door een kijker gaf %d: %s", write.name, rec.Code, rec.Body.String())
		}
		hidden := strings.Replace(write.path, everyone.ID, private.ID, 1)
		if rec := e.do(write.method, hidden, write.body, bob); rec.Code != http.StatusNotFound {
			t.Errorf("%s buiten zicht gaf %d", write.name, rec.Code)
		}
	}
	if got := strings.Join(e.listTitles(open), ","); got != "Grease" {
		t.Fatalf("de geweigerde schrijfacties veranderden de lijst: %s", got)
	}

	// Een afspeellijst deelt niemand.
	list := e.createPlaylist("Van mij")
	if rec := e.do(http.MethodGet, playlistsPath+"/"+list.ID, nil, bob); rec.Code != http.StatusNotFound {
		t.Fatalf("een afspeellijst van een ander gaf %d", rec.Code)
	}
}

func TestRevokedLibraryHidesItemsWithoutLosingThem(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	memberID := e.createUser("member", "lid")
	library := e.libs[0].ID
	e.grantLibrary(memberID, library, "view")
	member := asUser(e.tokenFor(memberID))
	grease, matrix := e.findMovie("Grease"), e.findMovie("The Matrix")

	// De owner vult een open verzameling; het lid telt mee met zijn rechten.
	open := e.createCollection(map[string]any{"title": "Open", "visibility": "everyone"})
	path := collectionsPath + "/" + open.ID
	e.putItems(path, http.StatusNoContent, nil, grease.ID, matrix.ID)

	// Het lid maakt zijn eigen lijst terwijl hij nog alles ziet.
	list := e.createPlaylist("Lid", member)
	own := playlistsPath + "/" + list.ID
	e.putItems(own, http.StatusNoContent, []func(*http.Request){member}, grease.ID, matrix.ID)

	var seen api.Collection
	e.decodeInto(e.do(http.MethodGet, path, nil, member), &seen)
	if seen.ItemCount != 2 {
		t.Fatalf("het lid telt %d, verwacht 2", seen.ItemCount)
	}

	e.revokeLibrary(memberID, library)

	e.decodeInto(e.do(http.MethodGet, path, nil, member), &seen)
	if seen.ItemCount != 0 || len(seen.Artwork) != 0 {
		t.Fatalf("na intrekken nog %d items en %d posters", seen.ItemCount, len(seen.Artwork))
	}
	if got := e.listTitles(path, member); len(got) != 0 {
		t.Fatalf("na intrekken lekt de inhoud: %v", got)
	}

	// Een item-mutatie op een item buiten zicht is 404, en de lege PUT wist niets.
	rec := e.do(http.MethodPost, own+"/items", map[string]any{"item_ids": []string{grease.ID}}, member)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("toevoegen buiten zicht gaf %d", rec.Code)
	}
	if rec := e.do(http.MethodDelete, own+"/items/"+grease.ID, nil, member); rec.Code != http.StatusNotFound {
		t.Fatalf("verwijderen buiten zicht gaf %d", rec.Code)
	}
	e.putItems(own, http.StatusNoContent, []func(*http.Request){member})

	e.grantLibrary(memberID, library, "view")
	if got := strings.Join(e.listTitles(own, member), ","); got != "Grease,The Matrix" {
		t.Fatalf("na herstel staat er %q", got)
	}
}

func TestFullListFitsTheBodyLimit(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	list := e.createPlaylist("Lang")
	ids := make([]string, 5000)
	for i := range ids {
		ids[i] = id.New().String()
	}
	// Onbekende ids zijn 404; de grens van 8 KiB zou hier 400 geven.
	rec := e.do(http.MethodPut, playlistsPath+"/"+list.ID+"/items", map[string]any{"item_ids": ids})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("5000 ids gaf %d: %s", rec.Code, rec.Body.String())
	}
	rec = e.do(http.MethodPut, playlistsPath+"/"+list.ID+"/items", map[string]any{"item_ids": append(ids, id.New().String())})
	if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "library.list_invalid") {
		t.Fatalf("5001 ids gaf %d: %s", rec.Code, rec.Body.String())
	}
}

// Delen is voor owner en admin. Dat geldt bij aanmaken en bij wijzigen, en de
// afwijzing laat niets achter.
func TestOnlyOwnerAndAdminShareACollection(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	adminID := e.createUser("admin", "ada")
	memberID := e.createUser("member", "bob")
	restrictedID := e.createUser("restricted", "kim")
	admin, member, restricted := asUser(e.tokenFor(adminID)), asUser(e.tokenFor(memberID)), asUser(e.tokenFor(restrictedID))
	shareWith := []string{memberID.String()}

	share := []struct {
		name string
		body map[string]any
	}{
		{"iedereen", map[string]any{"visibility": "everyone"}},
		{"gekozen gebruikers", map[string]any{"visibility": "users", "shared_with": shareWith}},
		{"alleen shared_with", map[string]any{"shared_with": shareWith}},
		{"privé met gebruikers", map[string]any{"visibility": "private", "shared_with": shareWith}},
	}
	withTitle := func(body map[string]any, title string) map[string]any {
		out := map[string]any{"title": title}
		for k, v := range body {
			out[k] = v
		}
		return out
	}
	refused := func(t *testing.T, rec *httptest.ResponseRecorder) {
		t.Helper()
		if rec.Code != http.StatusForbidden || !strings.Contains(rec.Body.String(), "library.list_share_not_permitted") {
			t.Fatalf("gaf %d, verwacht 403 library.list_share_not_permitted: %s", rec.Code, rec.Body.String())
		}
	}

	for _, who := range []struct {
		name string
		as   func(*http.Request)
	}{{"member", member}, {"restricted", restricted}} {
		mine := e.createCollection(map[string]any{"title": "Eigen " + who.name}, who.as)
		if mine.Visibility != "private" {
			t.Fatalf("%s: de default is %q", who.name, mine.Visibility)
		}
		path := collectionsPath + "/" + mine.ID
		for _, c := range share {
			t.Run(who.name+" maakt "+c.name, func(t *testing.T) {
				rec := e.do(http.MethodPost, collectionsPath, withTitle(c.body, "Nee"), who.as)
				e.record("ErrorEnvelope", http.MethodPost, collectionsPath, rec)
				refused(t, rec)
			})
			t.Run(who.name+" wijzigt naar "+c.name, func(t *testing.T) {
				rec := e.do(http.MethodPatch, path, c.body, who.as)
				e.record("ErrorEnvelope", http.MethodPatch, path, rec)
				refused(t, rec)
			})
		}
		rec := e.do(http.MethodGet, collectionsPath, nil, who.as)
		var page api.CollectionPage
		e.decodeInto(rec, &page)
		if len(page.Items) != 1 || page.Items[0].Visibility != "private" {
			t.Fatalf("%s: een afwijzing liet iets achter: %+v", who.name, page.Items)
		}

		// Wat niet deelt blijft mogen.
		if rec := e.do(http.MethodPatch, path, map[string]any{"title": "Hernoemd"}, who.as); rec.Code != http.StatusOK {
			t.Fatalf("%s: hernoemen gaf %d", who.name, rec.Code)
		}
		if rec := e.do(http.MethodPatch, path, map[string]any{"visibility": "private"}, who.as); rec.Code != http.StatusOK {
			t.Fatalf("%s: privé zetten gaf %d", who.name, rec.Code)
		}
		e.createCollection(map[string]any{"title": "Ook privé", "visibility": "private"}, who.as)
		e.createPlaylist("Afspeellijst "+who.name, who.as)
	}

	for _, who := range []struct {
		name string
		as   func(*http.Request)
	}{{"admin", admin}, {"owner", func(*http.Request) {}}} {
		for _, c := range share[:2] {
			t.Run(who.name+" deelt "+c.name, func(t *testing.T) {
				made := e.createCollection(map[string]any{"title": who.name + " " + c.name}, who.as)
				if rec := e.do(http.MethodPatch, collectionsPath+"/"+made.ID, c.body, who.as); rec.Code != http.StatusOK {
					t.Fatalf("wijzigen gaf %d: %s", rec.Code, rec.Body.String())
				}
			})
		}
		if c := e.createCollection(map[string]any{"title": "Meteen open " + who.name, "visibility": "everyone"}, who.as); c.Visibility != "everyone" {
			t.Fatalf("%s: aanmaken met everyone gaf %q", who.name, c.Visibility)
		}
	}

	// Een gedegradeerde beheerder houdt wat hij deelde en kan het hernoemen,
	// maar niet opnieuw delen.
	open := e.createCollection(map[string]any{"title": "Van Ada", "visibility": "everyone"}, admin)
	if _, err := e.pool.Exec(context.Background(), `UPDATE users SET role = 'member' WHERE id = $1`, adminID); err != nil {
		t.Fatal(err)
	}
	path := collectionsPath + "/" + open.ID
	refused(t, e.do(http.MethodPatch, path, map[string]any{"visibility": "users", "shared_with": shareWith}, admin))
	if rec := e.do(http.MethodPatch, path, map[string]any{"title": "Nog steeds van Ada"}, admin); rec.Code != http.StatusOK {
		t.Fatalf("hernoemen na degradatie gaf %d", rec.Code)
	}

	// Intrekken blijft mogen, ook zonder rol; de weg terug is er dan niet meer.
	rec := e.do(http.MethodPatch, path, map[string]any{"visibility": "private"}, admin)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"visibility":"private"`) {
		t.Fatalf("privé zetten na degradatie gaf %d: %s", rec.Code, rec.Body.String())
	}
	refused(t, e.do(http.MethodPatch, path, map[string]any{"visibility": "everyone"}, admin))
}

// Oude clients sturen geen voorwaarde en worden bediend; een nieuwe client krijgt een
// conflict in plaats van andermans wijziging te overschrijven.
func TestReplaceWithABaseRevision(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	first, second := e.findMovie("Grease").ID, e.findMovie("The Matrix").ID
	created := e.createPlaylist("Avond")
	path := playlistsPath + "/" + created.ID
	e.putItems(path, http.StatusNoContent, nil, first)

	read := func() api.Playlist {
		t.Helper()
		var list api.Playlist
		e.getJSON(path, "Playlist", http.StatusOK, &list)
		return list
	}
	seen := read().Revision
	if rec := e.do(http.MethodPost, path+"/items", map[string]any{"item_ids": []string{second}}); rec.Code != http.StatusNoContent {
		t.Fatalf("toevoegen gaf %d: %s", rec.Code, rec.Body.String())
	}

	rec := e.do(http.MethodPut, path+"/items", map[string]any{"item_ids": []string{first}, "base_revision": seen})
	e.record("ErrorEnvelope", http.MethodPut, path+"/items", rec)
	if rec.Code != http.StatusConflict {
		t.Fatalf("oude revisie gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.expectCode(rec, api.CodeListConflict)
	var body struct {
		Error struct {
			Details struct {
				Revision int64 `json:"revision"`
			} `json:"details"`
		} `json:"error"`
	}
	e.decodeInto(rec, &body)
	if want := read().Revision; body.Error.Details.Revision != want {
		t.Fatalf("details.revision %d, huidig %d", body.Error.Details.Revision, want)
	}
	if got := e.listTitles(path); len(got) != 2 {
		t.Fatalf("een geweigerde aanvraag raakte de lijst: %v", got)
	}

	current := read().Revision
	rec = e.do(http.MethodPut, path+"/items", map[string]any{"item_ids": []string{second, first}, "base_revision": current})
	if rec.Code != http.StatusNoContent {
		t.Fatalf("huidige revisie gaf %d: %s", rec.Code, rec.Body.String())
	}
	if read().Revision != current+1 {
		t.Fatal("de revisie liep niet op")
	}
	// Zonder voorwaarde blijft vervangen werken, en POST kent het veld niet.
	e.putItems(path, http.StatusNoContent, nil, first, second)
	rec = e.do(http.MethodPost, path+"/items", map[string]any{"item_ids": []string{first}, "base_revision": current})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("POST met base_revision gaf %d", rec.Code)
	}
}

// Privé met een lege shared_with deelt met niemand: dat is de vorm waarin een client
// "alleen ik" stuurt, en die hoort voor een lid dezelfde uitkomst te hebben.
func TestMemberMayKeepACollectionPrivateWithAnEmptyShareList(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	member := asUser(e.tokenFor(e.createUser("member", "lid")))
	body := map[string]any{"title": "Van mij", "visibility": "private", "shared_with": []string{}}

	rec := e.do(http.MethodPost, collectionsPath, body, member)
	if rec.Code != http.StatusCreated {
		t.Fatalf("aanmaken gaf %d: %s", rec.Code, rec.Body.String())
	}
	var made api.Collection
	e.decodeInto(rec, &made)
	if rec := e.do(http.MethodPatch, collectionsPath+"/"+made.ID, body, member); rec.Code != http.StatusOK {
		t.Fatalf("wijzigen gaf %d: %s", rec.Code, rec.Body.String())
	}
}

func TestCapabilitiesAnnounceListsAndUnknownVisibilityIsRefused(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	var info api.Info
	e.getJSON("/pleya/v1/info", "Info", http.StatusOK, &info)
	if !info.Capabilities.Collections || !info.Capabilities.Playlists {
		t.Fatalf("vlaggen uit: %+v", info.Capabilities)
	}
	rec := e.do(http.MethodPost, collectionsPath, map[string]any{"title": "x", "visibility": "vrienden"})
	e.record("ErrorEnvelope", http.MethodPost, collectionsPath, rec)
	if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), `"field":"visibility"`) {
		t.Fatalf("onbekende zichtbaarheid gaf %d: %s", rec.Code, rec.Body.String())
	}
	created := e.createCollection(map[string]any{"title": "x"})
	rec = e.do(http.MethodPatch, collectionsPath+"/"+created.ID, nil, rawBody(`{"title": null}`))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("title null gaf %d", rec.Code)
	}
	rec = e.do(http.MethodPost, playlistsPath, map[string]any{"title": "x", "visibility": "everyone"})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("een afspeellijst nam een zichtbaarheid aan: %d", rec.Code)
	}
	if created.Visibility != "private" {
		t.Fatalf("de default is %q", created.Visibility)
	}
}
