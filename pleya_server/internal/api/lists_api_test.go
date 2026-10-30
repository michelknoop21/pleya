package api_test

import (
	"net/http"
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
