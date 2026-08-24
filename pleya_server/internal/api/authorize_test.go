package api_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// libraryByKind geeft de bibliotheek van een soort, rechtstreeks uit de
// fixture en niet via HTTP: de autorisatietests hebben het interne id.ID
// nodig voor grantLibrary.
func (e *env) libraryByKind(kind string) catalog.Library {
	e.t.Helper()
	for _, l := range e.libs {
		if l.Kind == kind {
			return l
		}
	}
	e.t.Fatalf("geen bibliotheek van soort %s", kind)
	return catalog.Library{}
}

// TestLibraryAuthorizationOwnerAndAdminSeeEverything dekt matrixpunt 6: de
// bestaande owner-route blijft werken volgens het vastgelegde model, en admin
// (nul library_permissions-rijen, net als owner) evenzo.
func TestLibraryAuthorizationOwnerAndAdminSeeEverything(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryByKind("movies")
	series := e.libraryByKind("shows")

	admin := e.createUser("admin", "beheerder")
	adminToken := e.tokenFor(admin)

	for _, tok := range []string{e.access, adminToken} {
		var list api.LibraryList
		rec := e.do(http.MethodGet, "/pleya/v1/libraries", nil, asUser(tok))
		if rec.Code != http.StatusOK {
			t.Fatalf("libraries gaf %d: %s", rec.Code, rec.Body.String())
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil {
			t.Fatal(err)
		}
		if len(list.Items) != 2 {
			t.Fatalf("%d bibliotheken zichtbaar, verwacht 2", len(list.Items))
		}

		for _, libID := range []string{films.ID.String(), series.ID.String()} {
			rec := e.do(http.MethodGet, "/pleya/v1/libraries/"+libID+"/items", nil, asUser(tok))
			if rec.Code != http.StatusOK {
				t.Fatalf("items van %s gaf %d: %s", libID, rec.Code, rec.Body.String())
			}
		}
	}
}

// TestLibraryAuthorizationMemberSeesOnlyGrantedLibrary dekt matrixpunt 1, 2 en
// 3: een member met recht op precies één bibliotheek ziet die, en niets van de
// andere, noch los noch in de lijst.
func TestLibraryAuthorizationMemberSeesOnlyGrantedLibrary(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryByKind("movies")
	series := e.libraryByKind("shows")

	member := e.createUser("member", "huisgenoot")
	e.grantLibrary(member, films.ID, "view")
	token := e.tokenFor(member)

	var list api.LibraryList
	rec := e.do(http.MethodGet, "/pleya/v1/libraries", nil, asUser(token))
	if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil {
		t.Fatal(err)
	}
	if len(list.Items) != 1 || list.Items[0].ID != films.ID.String() {
		t.Fatalf("bibliotheeklijst is %+v, verwacht alleen %s", list.Items, films.ID)
	}

	ok := e.do(http.MethodGet, "/pleya/v1/libraries/"+films.ID.String()+"/items", nil, asUser(token))
	if ok.Code != http.StatusOK {
		t.Fatalf("toegestane bibliotheek gaf %d: %s", ok.Code, ok.Body.String())
	}

	denied := e.do(http.MethodGet, "/pleya/v1/libraries/"+series.ID.String()+"/items", nil, asUser(token))
	if denied.Code != http.StatusNotFound {
		t.Fatalf("verboden bibliotheek gaf %d, verwacht 404", denied.Code)
	}
	e.expectCode(denied, api.CodeNotFound)
}

// TestLibraryAuthorizationDirectIDGuessesReturn404 dekt matrixpunt 4: rechtstreeks
// raden van een item-, versie-, ondertitel- of artwork-id in een verboden
// bibliotheek levert dezelfde 404 als een id dat niet bestaat, en geen 403.
func TestLibraryAuthorizationDirectIDGuessesReturn404(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	grease := e.findMovie("Grease")
	version := grease.Versions[0]
	var subtitleURL string
	for _, st := range version.SubtitleStreams {
		if st.IsExternal {
			subtitleURL = *st.URL
		}
	}
	if subtitleURL == "" {
		t.Fatal("geen extern ondertitelspoor om te testen")
	}
	if grease.Artwork.PosterID == nil {
		t.Fatal("geen poster om te testen")
	}

	member := e.createUser("member", "buitenstaander")
	// Bewust geen enkele grantLibrary-aanroep: deze gebruiker heeft nul rechten.
	token := e.tokenFor(member)

	cases := []struct {
		name string
		path string
	}{
		{"item", "/pleya/v1/items/" + grease.ID},
		{"children", "/pleya/v1/items/" + grease.ID + "/children"},
		{"stream", "/pleya/v1/stream/" + version.ID},
		{"subtitle", subtitleURL},
		{"artwork", "/pleya/v1/artwork/" + *grease.Artwork.PosterID},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			rec := e.do(http.MethodGet, c.path, nil, asUser(token))
			if rec.Code != http.StatusNotFound {
				t.Fatalf("%s gaf %d, verwacht 404: %s", c.name, rec.Code, rec.Body.String())
			}
			e.expectCode(rec, api.CodeNotFound)
		})
	}
}

// TestLibraryAuthorizationSearchAndHubFilterResults dekt matrixpunt 3 voor de
// twee endpoints die over meerdere bibliotheken filteren: zoeken en een hub
// zonder library_id mogen nooit een resultaat uit een verboden bibliotheek
// bevatten.
func TestLibraryAuthorizationSearchAndHubFilterResults(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryByKind("movies")
	member := e.createUser("member", "kijker")
	e.grantLibrary(member, films.ID, "view")
	token := e.tokenFor(member)

	var search api.ItemPage
	e.getJSON("/pleya/v1/search?q=How", "", http.StatusOK, &search) // als owner: treft de serie
	if len(search.Items) == 0 {
		t.Fatal("owner zou de serie moeten vinden; testopzet klopt niet")
	}

	rec := e.do(http.MethodGet, "/pleya/v1/search?q=How", nil, asUser(token))
	if rec.Code != http.StatusOK {
		t.Fatalf("search gaf %d: %s", rec.Code, rec.Body.String())
	}
	var memberSearch api.ItemPage
	if err := json.Unmarshal(rec.Body.Bytes(), &memberSearch); err != nil {
		t.Fatal(err)
	}
	if len(memberSearch.Items) != 0 {
		t.Fatalf("member zonder recht op de series-bibliotheek kreeg %d treffers, verwacht 0", len(memberSearch.Items))
	}

	hubRec := e.do(http.MethodGet, "/pleya/v1/hubs/recently_added", nil, asUser(token))
	if hubRec.Code != http.StatusOK {
		t.Fatalf("hub gaf %d: %s", hubRec.Code, hubRec.Body.String())
	}
	var hub api.ItemPage
	if err := json.Unmarshal(hubRec.Body.Bytes(), &hub); err != nil {
		t.Fatal(err)
	}
	for _, it := range hub.Items {
		if it.Kind == "episode" {
			// De enige episodes in de fixture horen bij de series-bibliotheek,
			// waar deze member geen recht op heeft.
			t.Fatalf("hub leverde een episode terwijl alleen films is toegestaan: %+v", it)
		}
	}
}

// TestLibraryAuthorizationTwoUsersDifferentPermissions dekt matrixpunt 5:
// twee gebruikers met andere library_permissions krijgen aantoonbaar andere
// resultaten van hetzelfde endpoint.
func TestLibraryAuthorizationTwoUsersDifferentPermissions(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryByKind("movies")
	series := e.libraryByKind("shows")

	filmsUser := e.createUser("member", "filmskijker")
	e.grantLibrary(filmsUser, films.ID, "view")
	filmsToken := e.tokenFor(filmsUser)

	seriesUser := e.createUser("member", "serieskijker")
	e.grantLibrary(seriesUser, series.ID, "view")
	seriesToken := e.tokenFor(seriesUser)

	filmsOK := e.do(http.MethodGet, "/pleya/v1/libraries/"+films.ID.String()+"/items", nil, asUser(filmsToken))
	filmsDenied := e.do(http.MethodGet, "/pleya/v1/libraries/"+films.ID.String()+"/items", nil, asUser(seriesToken))
	if filmsOK.Code != http.StatusOK || filmsDenied.Code != http.StatusNotFound {
		t.Fatalf("films: eigen gebruiker gaf %d, andere gebruiker gaf %d", filmsOK.Code, filmsDenied.Code)
	}

	seriesOK := e.do(http.MethodGet, "/pleya/v1/libraries/"+series.ID.String()+"/items", nil, asUser(seriesToken))
	seriesDenied := e.do(http.MethodGet, "/pleya/v1/libraries/"+series.ID.String()+"/items", nil, asUser(filmsToken))
	if seriesOK.Code != http.StatusOK || seriesDenied.Code != http.StatusNotFound {
		t.Fatalf("series: eigen gebruiker gaf %d, andere gebruiker gaf %d", seriesOK.Code, seriesDenied.Code)
	}
}

// TestLibraryAuthorizationStreamTokenAndSessionRespectPermission dekt
// matrixpunt 2 en 4 voor de twee endpoints die een streamtoken of
// -sessie uitgeven: zonder bibliotheekrecht komt er geen credential.
func TestLibraryAuthorizationStreamTokenAndSessionRespectPermission(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	grease := e.findMovie("Grease")
	version := grease.Versions[0]

	member := e.createUser("member", "geen-toegang")
	token := e.tokenFor(member)

	tokenRec := e.do(http.MethodPost, "/pleya/v1/auth/stream-token",
		map[string]string{"version_id": version.ID}, asUser(token))
	if tokenRec.Code != http.StatusNotFound {
		t.Fatalf("stream-token zonder recht gaf %d, verwacht 404: %s", tokenRec.Code, tokenRec.Body.String())
	}
	e.expectCode(tokenRec, api.CodeNotFound)

	sessionRec := e.do(http.MethodPost, "/pleya/v1/auth/stream-session",
		map[string]string{"version_id": version.ID}, asUser(token))
	if sessionRec.Code != http.StatusNotFound {
		t.Fatalf("stream-session zonder recht gaf %d, verwacht 404: %s", sessionRec.Code, sessionRec.Body.String())
	}
	e.expectCode(sessionRec, api.CodeNotFound)

	films := e.libraryByKind("movies")
	e.grantLibrary(member, films.ID, "view")

	allowedRec := e.do(http.MethodPost, "/pleya/v1/auth/stream-token",
		map[string]string{"version_id": version.ID}, asUser(token))
	if allowedRec.Code != http.StatusOK {
		t.Fatalf("stream-token mét recht gaf %d: %s", allowedRec.Code, allowedRec.Body.String())
	}
}

// TestStreamTokenRevalidatesOnEveryRequest dekt matrixpunt 8 en 9: een
// streamtoken wordt gecontroleerd op het aanvraagpad, niet alleen bij het
// minten. Het bewijst tegelijk dat het token echt aan het niet-owner-subject
// hangt en niet stilzwijgend aan de owner: trok het token de owner-bypass met
// zich mee, dan zou het intrekken van het recht van dit ene lid geen effect
// hebben, en zou de laatste aanvraag hieronder blijven slagen.
func TestStreamTokenRevalidatesOnEveryRequest(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryByKind("movies")
	grease := e.findMovie("Grease")
	versionID := grease.Versions[0].ID

	member := e.createUser("member", "leent-tijdelijk")
	e.grantLibrary(member, films.ID, "view")
	token := e.tokenFor(member)

	tokenRec := e.do(http.MethodPost, "/pleya/v1/auth/stream-token",
		map[string]string{"version_id": versionID}, asUser(token))
	if tokenRec.Code != http.StatusOK {
		t.Fatalf("stream-token mét recht gaf %d: %s", tokenRec.Code, tokenRec.Body.String())
	}
	var streamToken api.StreamToken
	if err := json.Unmarshal(tokenRec.Body.Bytes(), &streamToken); err != nil {
		t.Fatal(err)
	}

	path := "/pleya/v1/stream/" + versionID + "?stream_token=" + streamToken.StreamToken
	before := e.do(http.MethodGet, path, nil, withoutAuth)
	if before.Code != http.StatusOK {
		t.Fatalf("streamen mét recht gaf %d: %s", before.Code, before.Body.String())
	}

	e.revokeLibrary(member, films.ID)

	after := e.do(http.MethodGet, path, nil, withoutAuth)
	if after.Code != http.StatusNotFound {
		t.Fatalf("hetzelfde token na intrekking gaf %d, verwacht 404: %s", after.Code, after.Body.String())
	}
	e.expectCode(after, api.CodeNotFound)
}

// TestStreamSessionRevalidatesOnEveryRequest is TestStreamTokenRevalidatesOnEveryRequest
// voor de browser-streamsessie (matrixpunt 9, het derde pad): het geheim en de
// versie blijven kloppen na intrekking, dus alleen een verse rechtencontrole op
// het aanvraagpad kan dit tegenhouden.
func TestStreamSessionRevalidatesOnEveryRequest(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryByKind("movies")
	grease := e.findMovie("Grease")
	versionID := grease.Versions[0].ID

	member := e.createUser("member", "kijkt-in-de-browser")
	e.grantLibrary(member, films.ID, "view")
	token := e.tokenFor(member)

	sessionRec := e.do(http.MethodPost, "/pleya/v1/auth/stream-session",
		map[string]string{"version_id": versionID}, asUser(token))
	if sessionRec.Code != http.StatusOK {
		t.Fatalf("stream-session mét recht gaf %d: %s", sessionRec.Code, sessionRec.Body.String())
	}
	var session api.StreamSession
	if err := json.Unmarshal(sessionRec.Body.Bytes(), &session); err != nil {
		t.Fatal(err)
	}
	var cookie *http.Cookie
	for _, c := range sessionRec.Result().Cookies() {
		if c.Name == auth.StreamCookiePrefix+session.StreamSessionID {
			cookie = c
		}
	}
	if cookie == nil {
		t.Fatalf("geen cookie met de naam %s%s", auth.StreamCookiePrefix, session.StreamSessionID)
	}

	path := "/pleya/v1/stream/" + versionID + "?ss=" + session.StreamSessionID
	before := e.do(http.MethodGet, path, nil, withoutAuth, withCookie(cookie))
	if before.Code != http.StatusOK {
		t.Fatalf("streamen mét recht gaf %d: %s", before.Code, before.Body.String())
	}

	e.revokeLibrary(member, films.ID)

	after := e.do(http.MethodGet, path, nil, withoutAuth, withCookie(cookie))
	if after.Code != http.StatusNotFound {
		t.Fatalf("dezelfde sessie na intrekking gaf %d, verwacht 404: %s", after.Code, after.Body.String())
	}
	e.expectCode(after, api.CodeNotFound)
}

// TestStreamBearerUsesTheBearerSubject dekt matrixpunt 9 voor het gewone
// accesstoken: een member mét recht mag rechtstreeks met de Authorization-
// header streamen, zonder ooit een streamtoken of -sessie aan te vragen.
func TestStreamBearerUsesTheBearerSubject(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryByKind("movies")
	grease := e.findMovie("Grease")
	versionID := grease.Versions[0].ID

	member := e.createUser("member", "kijkt-rechtstreeks")
	e.grantLibrary(member, films.ID, "view")
	token := e.tokenFor(member)

	rec := e.do(http.MethodGet, "/pleya/v1/stream/"+versionID, nil, asUser(token))
	if rec.Code != http.StatusOK {
		t.Fatalf("bearer-stream mét recht gaf %d: %s", rec.Code, rec.Body.String())
	}
	if rec.Body.Len() == 0 {
		t.Fatal("er kwamen geen bytes")
	}
}

// TestStreamTokenAdminBypassesPermissions dekt matrixpunt 6 voor de twee
// endpoints die een credential uitgeven: admin heeft, net als owner, geen
// enkele library_permissions-rij nodig.
func TestStreamTokenAdminBypassesPermissions(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	grease := e.findMovie("Grease")
	versionID := grease.Versions[0].ID

	admin := e.createUser("admin", "systeembeheerder")
	token := e.tokenFor(admin)

	tokenRec := e.do(http.MethodPost, "/pleya/v1/auth/stream-token",
		map[string]string{"version_id": versionID}, asUser(token))
	if tokenRec.Code != http.StatusOK {
		t.Fatalf("admin zonder library_permissions-rij kreeg %d: %s", tokenRec.Code, tokenRec.Body.String())
	}
	var streamToken api.StreamToken
	if err := json.Unmarshal(tokenRec.Body.Bytes(), &streamToken); err != nil {
		t.Fatal(err)
	}

	path := "/pleya/v1/stream/" + versionID + "?stream_token=" + streamToken.StreamToken
	rec := e.do(http.MethodGet, path, nil, withoutAuth)
	if rec.Code != http.StatusOK {
		t.Fatalf("admin-streamtoken gaf %d: %s", rec.Code, rec.Body.String())
	}
}

// TestNonexistentAndForbiddenVersionAreIndistinguishable dekt de kern van
// hoofdstuk 3: een niet-bestaande versie en een bestaande versie in een
// verboden bibliotheek moeten hetzelfde contract opleveren, anders verraadt de
// respons of een geraden id werkelijk bestaat.
func TestNonexistentAndForbiddenVersionAreIndistinguishable(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	grease := e.findMovie("Grease")

	member := e.createUser("member", "ziet-niets")
	// Bewust geen enkele grantLibrary-aanroep.
	token := e.tokenFor(member)

	forbidden := e.do(http.MethodPost, "/pleya/v1/auth/stream-token",
		map[string]string{"version_id": grease.Versions[0].ID}, asUser(token))
	nonexistent := e.do(http.MethodPost, "/pleya/v1/auth/stream-token",
		map[string]string{"version_id": id.New().String()}, asUser(token))

	if forbidden.Code != nonexistent.Code {
		t.Fatalf("verboden gaf %d, niet-bestaand gaf %d: horen gelijk te zijn", forbidden.Code, nonexistent.Code)
	}
	if forbidden.Body.String() != nonexistent.Body.String() {
		t.Fatalf("verboden en niet-bestaand leverden verschillende bodies:\n%s\nvs\n%s",
			forbidden.Body.String(), nonexistent.Body.String())
	}
	e.expectCode(forbidden, api.CodeNotFound)
}

// episodeInLibrary geeft het id van een episode in de series-bibliotheek,
// rechtstreeks uit de database: er is geen endpoint dat een episode isoleert
// zonder eerst de show op te zoeken, en de autorisatietests hebben alleen het
// id nodig.
func (e *env) episodeInLibrary(libraryID id.ID) string {
	e.t.Helper()
	var itemID id.ID
	if err := e.pool.QueryRow(context.Background(),
		`SELECT id FROM media_items WHERE library_id = $1 AND kind = 'episode' LIMIT 1`,
		libraryID).Scan(&itemID); err != nil {
		e.t.Fatalf("episode in bibliotheek %s opzoeken: %v", libraryID, err)
	}
	return itemID.String()
}

// watchStateRowExists controleert rechtstreeks in de database of er een
// watch_states-rij bestaat, buiten het autorisatiepad om: matrixregel 13 eist
// dat een ingetrokken recht de rij verbergt en niet verwijdert, en dat is
// alleen op deze manier te onderscheiden van "de rij is echt weg".
func (e *env) watchStateRowExists(subject id.ID, itemID string) bool {
	e.t.Helper()
	parsed, err := id.Parse(itemID)
	if err != nil {
		e.t.Fatal(err)
	}
	var exists bool
	err = e.pool.QueryRow(context.Background(),
		`SELECT true FROM watch_states WHERE subject = $1 AND item_id = $2`, subject, parsed).Scan(&exists)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		e.t.Fatalf("watch_states-rij controleren: %v", err)
	}
	return exists
}

// TestWatchStateReportRequiresLibraryAccess dekt matrixregel 12: een member
// zonder recht op de bibliotheek van het item krijgt op POST /watch-state
// dezelfde 404 als een item-id dat niet bestaat, en het event wordt niet
// toegepast. Met het recht erbij slaagt exact dezelfde aanvraag.
func TestWatchStateReportRequiresLibraryAccess(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	grease := e.findMovie("Grease")
	films := e.libraryByKind("movies")

	member := e.createUser("member", "geen-filmrecht")
	token := e.tokenFor(member)

	forbidden := e.do(http.MethodPost, "/pleya/v1/watch-state",
		event(grease.ID, "tv", map[string]any{"explicit_action": "playback_started", "cause": "user_started"}),
		asUser(token))
	if forbidden.Code != http.StatusNotFound {
		t.Fatalf("watch-state zonder bibliotheekrecht gaf %d, verwacht 404: %s", forbidden.Code, forbidden.Body.String())
	}
	e.expectCode(forbidden, api.CodeNotFound)

	nonexistent := e.do(http.MethodPost, "/pleya/v1/watch-state",
		event(id.New().String(), "tv", map[string]any{"explicit_action": "playback_started", "cause": "user_started"}),
		asUser(token))
	if nonexistent.Code != http.StatusNotFound {
		t.Fatalf("watch-state op niet-bestaand item gaf %d, verwacht 404: %s", nonexistent.Code, nonexistent.Body.String())
	}
	if forbidden.Body.String() != nonexistent.Body.String() {
		t.Fatalf("verboden en niet-bestaand item leverden verschillende bodies:\n%s\nvs\n%s",
			forbidden.Body.String(), nonexistent.Body.String())
	}

	if e.watchStateRowExists(member, grease.ID) {
		t.Fatal("een geweigerd event liet toch een watch_states-rij achter")
	}

	e.grantLibrary(member, films.ID, "view")
	allowed := e.do(http.MethodPost, "/pleya/v1/watch-state",
		event(grease.ID, "tv", map[string]any{"explicit_action": "playback_started", "cause": "user_started"}),
		asUser(token))
	if allowed.Code != http.StatusOK {
		t.Fatalf("watch-state mét recht gaf %d: %s", allowed.Code, allowed.Body.String())
	}
	if !e.watchStateRowExists(member, grease.ID) {
		t.Fatal("een geaccepteerd event liet geen watch_states-rij achter")
	}
}

// TestWatchStateListFiltersToVisibleLibraries dekt matrixregel 13: GET
// /watch-state levert alleen rijen van items in bibliotheken die de
// aanvrager nu mag zien, niet alle rijen met zijn subject. De filter moet in
// de query zitten en niet als naloop: met limit=1 en precies één zichtbare
// rij mag er geen next_cursor overblijven, ook al bestaat er nog een tweede,
// onzichtbare rij.
func TestWatchStateListFiltersToVisibleLibraries(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryByKind("movies")
	series := e.libraryByKind("shows")
	grease := e.findMovie("Grease")
	episodeID := e.episodeInLibrary(series.ID)

	member := e.createUser("member", "kijkt-overal")
	token := e.tokenFor(member)
	e.grantLibrary(member, films.ID, "view")
	e.grantLibrary(member, series.ID, "view")

	for _, itemID := range []string{grease.ID, episodeID} {
		rec := e.do(http.MethodPost, "/pleya/v1/watch-state",
			event(itemID, "tv", map[string]any{"explicit_action": "playback_started", "cause": "user_started"}),
			asUser(token))
		if rec.Code != http.StatusOK {
			t.Fatalf("watch-state op %s gaf %d: %s", itemID, rec.Code, rec.Body.String())
		}
	}

	var full api.WatchStatePage
	fullRec := e.do(http.MethodGet, "/pleya/v1/watch-state", nil, asUser(token))
	if fullRec.Code != http.StatusOK {
		t.Fatalf("watch-state lijst gaf %d: %s", fullRec.Code, fullRec.Body.String())
	}
	if err := json.Unmarshal(fullRec.Body.Bytes(), &full); err != nil {
		t.Fatal(err)
	}
	if len(full.Items) != 2 {
		t.Fatalf("%d regels met beide rechten, verwacht 2", len(full.Items))
	}

	e.revokeLibrary(member, series.ID)

	var afterRevoke api.WatchStatePage
	revokedRec := e.do(http.MethodGet, "/pleya/v1/watch-state?limit=1", nil, asUser(token))
	if revokedRec.Code != http.StatusOK {
		t.Fatalf("watch-state lijst na intrekking gaf %d: %s", revokedRec.Code, revokedRec.Body.String())
	}
	if err := json.Unmarshal(revokedRec.Body.Bytes(), &afterRevoke); err != nil {
		t.Fatal(err)
	}
	if len(afterRevoke.Items) != 1 || afterRevoke.Items[0].ItemID != grease.ID {
		t.Fatalf("na intrekking: %+v, verwacht alleen %s", afterRevoke.Items, grease.ID)
	}
	if afterRevoke.NextCursor != nil {
		t.Fatalf("next_cursor staat op %q terwijl er nog maar één zichtbare regel is; de filter draait blijkbaar na de paginering",
			*afterRevoke.NextCursor)
	}
}

// TestWatchStateHiddenNotDeletedOnRevoke dekt de rest van matrixregel 13: een
// ingetrokken bibliotheekrecht verbergt bestaande kijkstatus, het verwijdert
// hem niet. Met het recht terug staat exact dezelfde toestand er weer.
func TestWatchStateHiddenNotDeletedOnRevoke(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryByKind("movies")
	grease := e.findMovie("Grease")

	member := e.createUser("member", "tijdelijke-kijker")
	token := e.tokenFor(member)
	e.grantLibrary(member, films.ID, "view")

	reported := e.do(http.MethodPost, "/pleya/v1/watch-state",
		event(grease.ID, "tv", map[string]any{
			"explicit_action": "playback_started", "cause": "user_started",
			"position_ms": 900_000,
		}), asUser(token))
	if reported.Code != http.StatusOK {
		t.Fatalf("watch-state mét recht gaf %d: %s", reported.Code, reported.Body.String())
	}
	var before api.UserState
	if err := json.Unmarshal(reported.Body.Bytes(), &before); err != nil {
		t.Fatal(err)
	}

	e.revokeLibrary(member, films.ID)

	if !e.watchStateRowExists(member, grease.ID) {
		t.Fatal("intrekking verwijderde de watch_states-rij; hij hoort te blijven bestaan, alleen onzichtbaar")
	}

	hiddenRec := e.do(http.MethodGet, "/pleya/v1/watch-state", nil, asUser(token))
	var hidden api.WatchStatePage
	if err := json.Unmarshal(hiddenRec.Body.Bytes(), &hidden); err != nil {
		t.Fatal(err)
	}
	if len(hidden.Items) != 0 {
		t.Fatalf("kijkstatus is zichtbaar zonder bibliotheekrecht: %+v", hidden.Items)
	}

	e.grantLibrary(member, films.ID, "view")

	restoredRec := e.do(http.MethodGet, "/pleya/v1/watch-state", nil, asUser(token))
	var restored api.WatchStatePage
	if err := json.Unmarshal(restoredRec.Body.Bytes(), &restored); err != nil {
		t.Fatal(err)
	}
	if len(restored.Items) != 1 || restored.Items[0].ItemID != grease.ID {
		t.Fatalf("na herstel: %+v, verwacht alleen %s", restored.Items, grease.ID)
	}
	if restored.Items[0].State.Revision == nil || before.Revision == nil ||
		*restored.Items[0].State.Revision != *before.Revision {
		t.Fatalf("revision na herstel is %v, verwacht dezelfde als vóór intrekking (%v)",
			restored.Items[0].State.Revision, before.Revision)
	}
	if restored.Items[0].State.PositionMs != before.PositionMs {
		t.Fatalf("position_ms na herstel is %d, verwacht %d (dezelfde rij, niet opnieuw aangemaakt)",
			restored.Items[0].State.PositionMs, before.PositionMs)
	}
}

// TestSubtitleStreamTokenRevalidatesOnEveryRequest dekt het streamtokenpad van
// matrixregel 8, dat TestStreamTokenRevalidatesOnEveryRequest alleen voor
// /stream bewijst: streamAuthorized is dezelfde middleware voor beide routes
// en herbeoordeelt het bibliotheekrecht op elke aanvraag, maar zonder een
// eigen test voor /subtitles bewijst niets dat een toekomstige wijziging aan
// handleSubtitle die revalidatie niet per ongeluk overslaat.
func TestSubtitleStreamTokenRevalidatesOnEveryRequest(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryByKind("movies")
	grease := e.findMovie("Grease")
	version := grease.Versions[0]
	var subtitleURL string
	for _, st := range version.SubtitleStreams {
		if st.IsExternal {
			subtitleURL = *st.URL
		}
	}
	if subtitleURL == "" {
		t.Fatal("geen extern ondertitelspoor om te testen")
	}

	member := e.createUser("member", "leest-ondertitels")
	e.grantLibrary(member, films.ID, "view")
	token := e.tokenFor(member)

	tokenRec := e.do(http.MethodPost, "/pleya/v1/auth/stream-token",
		map[string]string{"version_id": version.ID}, asUser(token))
	if tokenRec.Code != http.StatusOK {
		t.Fatalf("stream-token mét recht gaf %d: %s", tokenRec.Code, tokenRec.Body.String())
	}
	var streamToken api.StreamToken
	if err := json.Unmarshal(tokenRec.Body.Bytes(), &streamToken); err != nil {
		t.Fatal(err)
	}

	path := subtitleURL + "?stream_token=" + streamToken.StreamToken
	before := e.do(http.MethodGet, path, nil, withoutAuth)
	if before.Code != http.StatusOK {
		t.Fatalf("ondertitel mét recht gaf %d: %s", before.Code, before.Body.String())
	}

	e.revokeLibrary(member, films.ID)

	after := e.do(http.MethodGet, path, nil, withoutAuth)
	if after.Code != http.StatusNotFound {
		t.Fatalf("hetzelfde streamtoken na intrekking gaf %d, verwacht 404: %s", after.Code, after.Body.String())
	}
	e.expectCode(after, api.CodeNotFound)
}

// TestHubLibraryIDParamRespectsPermission dekt matrixregel 6 voor de tweede
// lekvector: niet alleen de resultaten van een hub moeten gefilterd zijn,
// maar ook een expliciete ?library_id= naar een bibliotheek zonder recht
// moet 404 geven en niet de ongefilterde inhoud van die bibliotheek.
func TestHubLibraryIDParamRespectsPermission(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryByKind("movies")
	series := e.libraryByKind("shows")

	member := e.createUser("member", "alleen-films")
	e.grantLibrary(member, films.ID, "view")
	token := e.tokenFor(member)

	allowed := e.do(http.MethodGet, "/pleya/v1/hubs/recently_added?library_id="+films.ID.String(), nil, asUser(token))
	if allowed.Code != http.StatusOK {
		t.Fatalf("hub met toegestane library_id gaf %d: %s", allowed.Code, allowed.Body.String())
	}

	denied := e.do(http.MethodGet, "/pleya/v1/hubs/recently_added?library_id="+series.ID.String(), nil, asUser(token))
	if denied.Code != http.StatusNotFound {
		t.Fatalf("hub met verboden library_id gaf %d, verwacht 404: %s", denied.Code, denied.Body.String())
	}
	e.expectCode(denied, api.CodeNotFound)
}

// TestSubtitleWrongScopeTokenIsIndistinguishableFromNonexistent dekt de
// bevinding die codex challenge naar boven haalde: een streamtoken dat voor
// een andere versie is gemint gaf voorheen 401 (tokenfout) op een bestaand
// subtitle_id, en 404 op een niet-bestaand subtitle_id. Die twee
// statuscodes samen waren een oracle: elke geldige streamtoken, voor om het
// even welke versie, kon zo het bestaan van elk subtitle_id in de hele
// catalogus aftasten, los van bibliotheekrecht. Beide moeten nu byte-voor-
// byte dezelfde 404 zijn.
func TestSubtitleWrongScopeTokenIsIndistinguishableFromNonexistent(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	grease := e.findMovie("Grease")
	var subtitleURL string
	for _, st := range grease.Versions[0].SubtitleStreams {
		if st.IsExternal {
			subtitleURL = *st.URL
		}
	}
	if subtitleURL == "" {
		t.Fatal("geen extern ondertitelspoor om te testen")
	}

	other := e.findMovie("Blade Runner")
	tokenRec := e.do(http.MethodPost, "/pleya/v1/auth/stream-token",
		map[string]string{"version_id": other.Versions[0].ID})
	if tokenRec.Code != http.StatusOK {
		t.Fatalf("stream-token gaf %d: %s", tokenRec.Code, tokenRec.Body.String())
	}
	var token api.StreamToken
	if err := json.Unmarshal(tokenRec.Body.Bytes(), &token); err != nil {
		t.Fatal(err)
	}

	wrongScope := e.do(http.MethodGet, subtitleURL+"?stream_token="+token.StreamToken, nil, withoutAuth)
	if wrongScope.Code != http.StatusNotFound {
		t.Fatalf("bestaand subtitle_id met verkeerd-gescoped token gaf %d, verwacht 404: %s",
			wrongScope.Code, wrongScope.Body.String())
	}

	nonexistent := e.do(http.MethodGet,
		"/pleya/v1/subtitles/"+id.New().String()+"?stream_token="+token.StreamToken, nil, withoutAuth)
	if nonexistent.Code != http.StatusNotFound {
		t.Fatalf("niet-bestaand subtitle_id gaf %d, verwacht 404: %s", nonexistent.Code, nonexistent.Body.String())
	}

	if wrongScope.Body.String() != nonexistent.Body.String() {
		t.Fatalf("verkeerd-gescoped en niet-bestaand leverden verschillende bodies:\n%s\nvs\n%s",
			wrongScope.Body.String(), nonexistent.Body.String())
	}
	e.expectCode(wrongScope, api.CodeNotFound)
}

// TestStreamSessionRejectedWhenAuthSessionRevoked dekt de tweede bevinding
// die codex challenge naar boven haalde: VerifyStreamSession controleerde
// stream_sessions.revoked_at, maar nooit sessions.revoked_at via de
// session_id-FK, terwijl CreateStreamSession precies daarvoor session_id
// draagt (DEC-069). Vandaag zet niets sessions.revoked_at (dat komt met
// DEC-070), dus deze test trekt de auth-sessie rechtstreeks in, zoals
// grantLibrary/revokeLibrary elders in dit bestand ook buiten het protocol om
// werken.
func TestStreamSessionRejectedWhenAuthSessionRevoked(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryByKind("movies")
	grease := e.findMovie("Grease")
	versionID := grease.Versions[0].ID

	member := e.createUser("member", "sessie-ingetrokken")
	e.grantLibrary(member, films.ID, "view")

	sessionID, err := e.auth.CreateSession(context.Background(), member, nil, "test device", time.Now().UTC())
	if err != nil {
		t.Fatal(err)
	}
	access, _, err := e.signer.Mint(member.String(), sessionID.String(), auth.TokenAccess, 15*time.Minute, "")
	if err != nil {
		t.Fatal(err)
	}

	sessionRec := e.do(http.MethodPost, "/pleya/v1/auth/stream-session",
		map[string]string{"version_id": versionID}, asUser(access))
	if sessionRec.Code != http.StatusOK {
		t.Fatalf("stream-session gaf %d: %s", sessionRec.Code, sessionRec.Body.String())
	}
	var session api.StreamSession
	if err := json.Unmarshal(sessionRec.Body.Bytes(), &session); err != nil {
		t.Fatal(err)
	}
	var cookie *http.Cookie
	for _, c := range sessionRec.Result().Cookies() {
		if c.Name == auth.StreamCookiePrefix+session.StreamSessionID {
			cookie = c
		}
	}
	if cookie == nil {
		t.Fatalf("geen cookie met de naam %s%s", auth.StreamCookiePrefix, session.StreamSessionID)
	}

	path := "/pleya/v1/stream/" + versionID + "?ss=" + session.StreamSessionID
	before := e.do(http.MethodGet, path, nil, withoutAuth, withCookie(cookie))
	if before.Code != http.StatusOK {
		t.Fatalf("streamen vóór intrekking gaf %d: %s", before.Code, before.Body.String())
	}

	if _, err := e.pool.Exec(context.Background(),
		`UPDATE sessions SET revoked_at = now() WHERE id = $1`, sessionID); err != nil {
		t.Fatalf("auth-sessie intrekken: %v", err)
	}

	after := e.do(http.MethodGet, path, nil, withoutAuth, withCookie(cookie))
	if after.Code != http.StatusUnauthorized {
		t.Fatalf("streamsessie na intrekking van de auth-sessie gaf %d, verwacht 401: %s", after.Code, after.Body.String())
	}
	e.expectCode(after, api.CodeTokenInvalid)
}

// TestDeletedUserAccessTokenGetsNotFoundNotInternalError dekt de bevinding uit
// de /code-review-run (angle C): authenticated() controleert alleen de
// handtekening van het accesstoken, geen databaserij, dus een verwijderde
// gebruiker met een nog niet verlopen token bereikt authorizeLibraryFor en
// accessibleLibraryIDs alsnog. catalog.userRole() geeft dan catalog.ErrNotFound
// terug (geen rij in users), en vóór deze fix werd dat ongefilterd naar
// writeInternal doorgezet: een 500 op elk leesendpoint voor de resterende
// levensduur van het token, in plaats van dezelfde 404 als elke andere
// niet-bestaande resource.
func TestDeletedUserAccessTokenGetsNotFoundNotInternalError(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryByKind("movies")
	member := e.createUser("member", "wordt-verwijderd")
	e.grantLibrary(member, films.ID, "view")
	token := e.tokenFor(member)

	if _, err := e.pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, member); err != nil {
		t.Fatalf("gebruiker verwijderen: %v", err)
	}

	cases := []struct {
		name string
		path string
	}{
		{"libraries (accessibleLibraryIDs)", "/pleya/v1/libraries"},
		{"search (accessibleLibraryIDs)", "/pleya/v1/search?q=x"},
		{"library items (authorizeLibrary)", "/pleya/v1/libraries/" + films.ID.String() + "/items"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			rec := e.do(http.MethodGet, c.path, nil, asUser(token))
			if rec.Code != http.StatusNotFound {
				t.Fatalf("verwijderde gebruiker op %s gaf %d, verwacht 404: %s", c.name, rec.Code, rec.Body.String())
			}
			e.expectCode(rec, api.CodeNotFound)
		})
	}
}
