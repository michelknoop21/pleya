package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// DELETE /items/{item_id} (DEC-XXX, media verwijderen). De autorisatie staat in
// de matrix (regel 112); hier staat wat er van schijf en uit de database gaat,
// tegen echte bestanden in een tijdelijke map.

// withMediaDelete zet het verwijderen aan met deze gemeten schrijfbare roots.
// nil laat het uit, zoals een server zonder PLEYA_SERVER_ALLOW_MEDIA_DELETE.
func withMediaDelete(roots []string) envOption {
	return func(o *api.Options) { o.MediaDelete = roots }
}

// resolved geeft het pad met opgeloste symlinks, zoals WritableRoots het meet.
func resolved(t *testing.T, path string) string {
	t.Helper()
	out, err := filepath.EvalSymlinks(path)
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func (e *env) itemIDWhere(where string, args ...any) string {
	e.t.Helper()
	var itemID string
	if err := e.pool.QueryRow(context.Background(), `SELECT id::text FROM media_items WHERE `+where, args...).Scan(&itemID); err != nil {
		e.t.Fatalf("item %q: %v", where, err)
	}
	return itemID
}

func exists(t *testing.T, path string) bool {
	t.Helper()
	_, err := os.Lstat(path)
	return err == nil
}

// newDeleteEnv bouwt de omgeving met verwijderen aan. De gemeten schrijfbare
// root is / : dan beslist alleen de bibliotheekroot zelf wat er mag, en de
// tests op een pad of symlink naar buiten meten precies die grens.
func newDeleteEnv(t *testing.T) *env {
	t.Helper()
	e := newEnv(t, withMediaDelete([]string{"/"}))
	e.setup(e.putSetupCode())
	return e
}

type deleteFailure struct {
	Error struct {
		Code    string `json:"code"`
		Details struct {
			Reason       string `json:"reason"`
			RemovedFiles int    `json:"removed_files"`
			RemovedItems int    `json:"removed_items"`
			Failed       []struct {
				Path   string `json:"path"`
				Reason string `json:"reason"`
			} `json:"failed"`
		} `json:"details"`
	} `json:"error"`
}

func decodeFailure(t *testing.T, body []byte) deleteFailure {
	t.Helper()
	var out deleteFailure
	if err := json.Unmarshal(body, &out); err != nil {
		t.Fatalf("%v: %s", err, body)
	}
	return out
}

func TestVerwijderenWistEenFilmMetTweeVersiesEnLaatDeRestStaan(t *testing.T) {
	e := newDeleteEnv(t)
	films := filepath.Join(e.root, "films")
	blade := e.itemIDWhere(`title = 'Blade Runner'`)

	rec := e.do(http.MethodDelete, "/pleya/v1/items/"+blade, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("verwijderen gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("ItemDeleted", http.MethodDelete, "/pleya/v1/items/{item_id}", rec)
	var out api.ItemDeleted
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if out.RemovedFiles != 2 || out.RemovedItems != 1 {
		t.Fatalf("antwoord %s, wil 2 bestanden en 1 titel", rec.Body.String())
	}
	if exists(t, filepath.Join(films, "Blade Runner (1982)")) {
		t.Fatal("de map van Blade Runner staat er nog, terwijl hij leeg raakte")
	}
	for _, keep := range []string{
		"Grease (1978)/Grease (1978).mkv",
		"The Matrix (1999)/The Matrix (1999).mkv",
	} {
		if !exists(t, filepath.Join(films, keep)) {
			t.Fatalf("%s is gewist", keep)
		}
	}
	if e.itemExists(e.libs[0].ID, "movie", "Blade Runner") {
		t.Fatal("Blade Runner staat nog in de catalogus")
	}
	if !e.itemExists(e.libs[0].ID, "movie", "Grease") || !e.itemExists(e.libs[0].ID, "movie", "The Matrix") {
		t.Fatal("een andere film is uit de catalogus verdwenen")
	}
}

// Bijbestanden: wat de catalogus aan de titel hing gaat mee, wat hij niet
// kende (een .nfo) blijft staan, en dan blijft de map ook.
func TestVerwijderenNeemtBekendeBijbestandenMeeEnLaatOnbekendeStaan(t *testing.T) {
	e := newDeleteEnv(t)
	dir := filepath.Join(e.root, "films", "Grease (1978)")
	testsupport.WriteFile(t, filepath.Join(dir, "Grease (1978).nfo"), "<movie/>")
	grease := e.itemIDWhere(`title = 'Grease'`)
	e.markWatched(grease, "sessie-verwijderen")

	var posterKnown bool
	if err := e.pool.QueryRow(context.Background(),
		`SELECT EXISTS (SELECT 1 FROM media_files WHERE relative_path = 'Grease (1978)/poster.jpg' AND item_id IS NOT NULL)`).
		Scan(&posterKnown); err != nil {
		t.Fatal(err)
	}

	rec := e.do(http.MethodDelete, "/pleya/v1/items/"+grease, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("verwijderen gaf %d: %s", rec.Code, rec.Body.String())
	}
	if exists(t, filepath.Join(dir, "Grease (1978).mkv")) || exists(t, filepath.Join(dir, "Grease (1978).nld.srt")) {
		t.Fatal("film of ondertitel staat er nog")
	}
	if got := exists(t, filepath.Join(dir, "poster.jpg")); got == posterKnown {
		t.Fatalf("poster.jpg aanwezig=%v, terwijl de catalogus hem kende=%v", got, posterKnown)
	}
	if !exists(t, filepath.Join(dir, "Grease (1978).nfo")) {
		t.Fatal("het onbekende .nfo-bestand is gewist")
	}
	var watched int
	if err := e.pool.QueryRow(context.Background(), `SELECT count(*) FROM watch_states WHERE item_id = $1`, grease).Scan(&watched); err != nil || watched != 0 {
		t.Fatalf("kijkstatus van Grease: %d (%v), wil 0", watched, err)
	}
}

func TestVerwijderenVanEenSeizoenEnDaarnaDeSerie(t *testing.T) {
	e := newDeleteEnv(t)
	show := filepath.Join(e.root, "series", "How I Met Your Mother (2005)")
	season1 := e.itemIDWhere(`kind = 'season' AND item_index = 1`)

	rec := e.do(http.MethodDelete, "/pleya/v1/items/"+season1, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("seizoen verwijderen gaf %d: %s", rec.Code, rec.Body.String())
	}
	var out api.ItemDeleted
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if out.RemovedFiles != 2 || out.RemovedItems != 2 {
		t.Fatalf("antwoord %s, wil 2 bestanden en 2 afleveringen", rec.Body.String())
	}
	if exists(t, filepath.Join(show, "Season 01")) {
		t.Fatal("Season 01 staat er nog")
	}
	if !exists(t, filepath.Join(show, "Season 02", "How I Met Your Mother - S02E01 - Where Were We.mkv")) {
		t.Fatal("een aflevering van seizoen 2 is gewist")
	}
	var seasons, shows int
	if err := e.pool.QueryRow(context.Background(), `SELECT count(*) FILTER (WHERE kind = 'season'), count(*) FILTER (WHERE kind = 'show')
		FROM media_items WHERE library_id = $1`, e.libs[1].ID).Scan(&seasons, &shows); err != nil {
		t.Fatal(err)
	}
	if seasons != 1 || shows != 1 {
		t.Fatalf("%d seizoenen en %d series, wil 1 en 1", seasons, shows)
	}

	rec = e.do(http.MethodDelete, "/pleya/v1/items/"+e.itemIDWhere(`kind = 'show'`), nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("serie verwijderen gaf %d: %s", rec.Code, rec.Body.String())
	}
	if exists(t, show) {
		t.Fatal("de map van de serie staat er nog")
	}
	if !exists(t, filepath.Join(e.root, "series")) {
		t.Fatal("de bibliotheekroot zelf is gewist")
	}
	var left int
	if err := e.pool.QueryRow(context.Background(), `SELECT count(*) FROM media_items WHERE library_id = $1`, e.libs[1].ID).Scan(&left); err != nil || left != 0 {
		t.Fatalf("%d items over in de seriebibliotheek (%v), wil 0", left, err)
	}
}

// Een bestand dat een symlink naar buiten de root is, of een pad in de
// database dat buiten de root wijst: niets daarbuiten gaat weg.
func TestVerwijderenRaaktNietsBuitenDeRoot(t *testing.T) {
	e := newDeleteEnv(t)
	outside := t.TempDir()
	target := filepath.Join(outside, "dierbaar.mkv")
	testsupport.WriteFile(t, target, "niet van Pleya")

	matrix := filepath.Join(e.root, "films", "The Matrix (1999)", "The Matrix (1999).mkv")
	if err := os.Remove(matrix); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, matrix); err != nil {
		t.Fatal(err)
	}
	rec := e.do(http.MethodDelete, "/pleya/v1/items/"+e.itemIDWhere(`title = 'The Matrix'`), nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("symlink: %d %s, wil 409", rec.Code, rec.Body.String())
	}
	got := decodeFailure(t, rec.Body.Bytes())
	if got.Error.Code != "library.media_delete_incomplete" || len(got.Error.Details.Failed) != 1 || got.Error.Details.Failed[0].Reason != "symlink" {
		t.Fatalf("antwoord %s", rec.Body.String())
	}
	if !exists(t, target) || !exists(t, matrix) {
		t.Fatal("de symlink of zijn doel is gewist")
	}
	if !e.itemExists(e.libs[0].ID, "movie", "The Matrix") {
		t.Fatal("The Matrix is uit de catalogus verdwenen terwijl het bestand bleef")
	}

	// Een relatief pad in de database dat naar buiten wijst.
	escape, err := filepath.Rel(filepath.Join(e.root, "films"), target)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := e.pool.Exec(context.Background(),
		`UPDATE media_files SET relative_path = $1 WHERE relative_path = 'Grease (1978)/Grease (1978).mkv'`, filepath.ToSlash(escape)); err != nil {
		t.Fatal(err)
	}
	rec = e.do(http.MethodDelete, "/pleya/v1/items/"+e.itemIDWhere(`title = 'Grease'`), nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("pad naar buiten: %d %s, wil 409", rec.Code, rec.Body.String())
	}
	got = decodeFailure(t, rec.Body.Bytes())
	if got.Error.Details.Failed[0].Reason != "outside_root" {
		t.Fatalf("antwoord %s", rec.Body.String())
	}
	if !exists(t, target) {
		t.Fatal("het bestand buiten de root is gewist")
	}
	// Het mediabestand bleef, dus ondertitel en poster blijven ook.
	if !exists(t, filepath.Join(e.root, "films", "Grease (1978)", "Grease (1978).nld.srt")) {
		t.Fatal("de ondertitel ging weg terwijl het mediabestand bleef")
	}
}

// Fout halverwege: één van de twee versies is niet te wissen. Het antwoord
// zegt wat wel en niet lukte, en de database volgt precies dat.
func TestVerwijderenHalverwegeFoutZegtWatBleef(t *testing.T) {
	e := newDeleteEnv(t)
	dir := filepath.Join(e.root, "films", "Blade Runner (1982)")
	final := filepath.Join(dir, "Blade Runner (1982) {edition-Final Cut}.mkv")
	other := filepath.Join(t.TempDir(), "elders.mkv")
	testsupport.WriteFile(t, other, "x")
	if err := os.Remove(final); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(other, final); err != nil {
		t.Fatal(err)
	}

	rec := e.do(http.MethodDelete, "/pleya/v1/items/"+e.itemIDWhere(`title = 'Blade Runner'`), nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("%d %s, wil 409", rec.Code, rec.Body.String())
	}
	got := decodeFailure(t, rec.Body.Bytes())
	d := got.Error.Details
	if d.RemovedFiles != 1 || d.RemovedItems != 0 || len(d.Failed) != 1 ||
		d.Failed[0].Path != "Blade Runner (1982)/Blade Runner (1982) {edition-Final Cut}.mkv" {
		t.Fatalf("antwoord %s", rec.Body.String())
	}
	if exists(t, filepath.Join(dir, "Blade Runner (1982).mkv")) {
		t.Fatal("de gewone versie staat er nog")
	}
	if got := e.versionCount(e.libs[0].ID, "Blade Runner"); got != 1 {
		t.Fatalf("Blade Runner heeft %d versies, wil 1 (de versie die bleef)", got)
	}
	var missing int
	if err := e.pool.QueryRow(context.Background(), `SELECT count(*) FROM media_files WHERE relative_path LIKE 'Blade Runner%' AND missing_since IS NOT NULL`).Scan(&missing); err != nil || missing != 0 {
		// De gewiste versie is met haar bestandsrij weg; de overgebleven is niet gemarkeerd.
		t.Fatalf("%d gemarkeerde bestanden (%v), wil 0", missing, err)
	}
}

// Uit, of de root is niet schrijfbaar: een foutcode en niets gewist.
func TestVerwijderenUitOfAlleenLezenWistNiets(t *testing.T) {
	for _, tc := range []struct {
		name   string
		roots  func(t *testing.T) []string
		reason string
	}{
		{"uit", func(*testing.T) []string { return nil }, "disabled"},
		{"geen schrijfbare root", func(*testing.T) []string { return []string{} }, "read_only"},
		{"andere root schrijfbaar", func(t *testing.T) []string { return []string{resolved(t, t.TempDir())} }, "read_only"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			e := newEnv(t, withMediaDelete(tc.roots(t)))
			e.setup(e.putSetupCode())
			rec := e.do(http.MethodDelete, "/pleya/v1/items/"+e.itemIDWhere(`title = 'The Matrix'`), nil)
			if rec.Code != http.StatusConflict {
				t.Fatalf("%d %s, wil 409", rec.Code, rec.Body.String())
			}
			got := decodeFailure(t, rec.Body.Bytes())
			if got.Error.Code != "library.media_delete_unavailable" || got.Error.Details.Reason != tc.reason {
				t.Fatalf("antwoord %s, wil reden %s", rec.Body.String(), tc.reason)
			}
			if !exists(t, filepath.Join(e.root, "films", "The Matrix (1999)", "The Matrix (1999).mkv")) {
				t.Fatal("het bestand is gewist")
			}
		})
	}
}

// Geen recht: buiten zicht 404, zichtbaar zonder manage 403, en ook met manage
// 403 zolang de aanvrager geen beheerder is (owner of admin). Een admin mag.
func TestVerwijderenVraagtManageEnEenBeheerder(t *testing.T) {
	e := newDeleteEnv(t)
	films := e.libs[0].ID
	matrix := e.itemIDWhere(`title = 'The Matrix'`)
	file := filepath.Join(e.root, "films", "The Matrix (1999)", "The Matrix (1999).mkv")
	member := e.createUser("member", "kijker")
	owner := e.access
	e.access = e.tokenFor(member)

	if rec := e.do(http.MethodDelete, "/pleya/v1/items/"+matrix, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("zonder recht: %d %s, wil 404", rec.Code, rec.Body.String())
	}
	for _, permission := range []string{"download", "manage"} {
		e.revokeLibrary(member, films)
		e.grantLibrary(member, films, permission)
		rec := e.do(http.MethodDelete, "/pleya/v1/items/"+matrix, nil)
		if rec.Code != http.StatusForbidden || decodeFailure(t, rec.Body.Bytes()).Error.Code != "library.delete_not_permitted" {
			t.Fatalf("lid met %s: %d %s, wil 403 library.delete_not_permitted", permission, rec.Code, rec.Body.String())
		}
		if !exists(t, file) {
			t.Fatalf("een lid met %s heeft het bestand gewist", permission)
		}
	}
	e.access = e.tokenFor(e.createUser("admin", "beheerder"))
	if rec := e.do(http.MethodDelete, "/pleya/v1/items/"+matrix, nil); rec.Code != http.StatusOK {
		t.Fatalf("admin: %d %s, wil 200", rec.Code, rec.Body.String())
	}
	e.access = owner
	if exists(t, file) {
		t.Fatal("het bestand staat er nog")
	}
}

// Een API-token wist niets, ook niet onder bereik admin.
func TestVerwijderenWeigertEenAPIToken(t *testing.T) {
	e := newDeleteEnv(t)
	created := e.createToken(map[string]any{"name": "Beheeragent", "scope": "admin"}, http.StatusCreated)
	file := filepath.Join(e.root, "films", "The Matrix (1999)", "The Matrix (1999).mkv")
	rec := e.do(http.MethodDelete, "/pleya/v1/items/"+e.itemIDWhere(`title = 'The Matrix'`), nil, asToken(created.Secret))
	if rec.Code != http.StatusForbidden || decodeFailure(t, rec.Body.Bytes()).Error.Code != "auth.scope_insufficient" {
		t.Fatalf("API-token: %d %s, wil 403 auth.scope_insufficient", rec.Code, rec.Body.String())
	}
	if !exists(t, file) {
		t.Fatal("een API-token heeft het bestand gewist")
	}
}

// Een tussenmap die een symlink naar buiten de root is, met daarbuiten een
// bestand met precies dezelfde naam: dat bestand blijft.
func TestVerwijderenVolgtGeenTussenmapNaarBuiten(t *testing.T) {
	e := newDeleteEnv(t)
	outside := t.TempDir()
	twin := filepath.Join(outside, "The Matrix (1999).mkv")
	testsupport.WriteFile(t, twin, "niet van Pleya")
	dir := filepath.Join(e.root, "films", "The Matrix (1999)")
	if err := os.RemoveAll(dir); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, dir); err != nil {
		t.Fatal(err)
	}
	rec := e.do(http.MethodDelete, "/pleya/v1/items/"+e.itemIDWhere(`title = 'The Matrix'`), nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("%d %s, wil 409", rec.Code, rec.Body.String())
	}
	if got := decodeFailure(t, rec.Body.Bytes()); len(got.Error.Details.Failed) != 1 || got.Error.Details.Failed[0].Reason != "outside_root" {
		t.Fatalf("antwoord %s", rec.Body.String())
	}
	if !exists(t, twin) {
		t.Fatal("het bestand buiten de root is gewist")
	}
	if !e.itemExists(e.libs[0].ID, "movie", "The Matrix") {
		t.Fatal("The Matrix is uit de catalogus verdwenen")
	}
}

// Een client die ophangt nadat de bestanden weg zijn, laat de catalogus niet
// half staan.
func TestVerwijderenMaaktDeCatalogusAfNaEenAfgebrokenAanvraag(t *testing.T) {
	e := newDeleteEnv(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	e.server.SetMediaDeleteHooks(nil, cancel)
	rec := e.do(http.MethodDelete, "/pleya/v1/items/"+e.itemIDWhere(`title = 'Blade Runner'`), nil,
		func(r *http.Request) { *r = *r.WithContext(ctx) })
	if rec.Code != http.StatusOK {
		t.Fatalf("%d %s, wil 200", rec.Code, rec.Body.String())
	}
	if e.itemExists(e.libs[0].ID, "movie", "Blade Runner") {
		t.Fatal("de bestanden zijn weg, maar Blade Runner staat nog in de catalogus")
	}
}

// Een bestand dat er niet meer is zonder dat de scanner het als verdwenen had
// gemarkeerd (de share viel weg na de controle) telt niet als gewist.
func TestVerwijderenTeltEenOnverwachtOntbrekendBestandNietAlsGewist(t *testing.T) {
	e := newDeleteEnv(t)
	// De share valt weg: de root blijft als lege map achter, zoals een
	// koppelpunt zonder mount.
	root := filepath.Join(e.root, "films")
	e.server.SetMediaDeleteHooks(func() {
		if err := os.Rename(root, root+"-offline"); err != nil {
			t.Error(err)
		}
		if err := os.Mkdir(root, 0o755); err != nil {
			t.Error(err)
		}
	}, nil)
	rec := e.do(http.MethodDelete, "/pleya/v1/items/"+e.itemIDWhere(`title = 'The Matrix'`), nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("%d %s, wil 409", rec.Code, rec.Body.String())
	}
	if got := decodeFailure(t, rec.Body.Bytes()); got.Error.Details.Failed[0].Reason != "remove_failed" {
		t.Fatalf("antwoord %s", rec.Body.String())
	}
	if !e.itemExists(e.libs[0].ID, "movie", "The Matrix") {
		t.Fatal("The Matrix is uit de catalogus verdwenen terwijl niets gewist is")
	}
}

// Een bestand dat iets anders net wiste, terwijl de share er gewoon is, telt
// als gewist: de titel gaat uit de catalogus.
func TestVerwijderenTeltEenNetGewistBestandAlsGewist(t *testing.T) {
	e := newDeleteEnv(t)
	dir := filepath.Join(e.root, "films", "The Matrix (1999)")
	file := filepath.Join(dir, "The Matrix (1999).mkv")
	// De map blijft gevuld: een .nfo die de scanner niet kent.
	testsupport.WriteFile(t, filepath.Join(dir, "The Matrix (1999).nfo"), "<movie/>")
	e.server.SetMediaDeleteHooks(func() {
		if err := os.Remove(file); err != nil {
			t.Error(err)
		}
	}, nil)
	rec := e.do(http.MethodDelete, "/pleya/v1/items/"+e.itemIDWhere(`title = 'The Matrix'`), nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("%d %s, wil 200", rec.Code, rec.Body.String())
	}
	if e.itemExists(e.libs[0].ID, "movie", "The Matrix") {
		t.Fatal("The Matrix staat nog in de catalogus")
	}
}

// Een share die binnen de gevulde root gemount was en wegviel laat een lege map
// achter. Het bestand ontbreekt dan, maar is niet gewist: de titel blijft.
func TestVerwijderenTeltEenLegeGenesteMountNietAlsGewist(t *testing.T) {
	e := newDeleteEnv(t)
	dir := filepath.Join(e.root, "films", "The Matrix (1999)")
	e.server.SetMediaDeleteHooks(func() {
		if err := os.Rename(dir, dir+"-offline"); err != nil {
			t.Error(err)
		}
		if err := os.Mkdir(dir, 0o755); err != nil {
			t.Error(err)
		}
	}, nil)
	rec := e.do(http.MethodDelete, "/pleya/v1/items/"+e.itemIDWhere(`title = 'The Matrix'`), nil)
	if rec.Code != http.StatusConflict || decodeFailure(t, rec.Body.Bytes()).Error.Code != "library.media_delete_incomplete" {
		t.Fatalf("%d %s, wil 409 library.media_delete_incomplete", rec.Code, rec.Body.String())
	}
	if !e.itemExists(e.libs[0].ID, "movie", "The Matrix") {
		t.Fatal("The Matrix is uit de catalogus verdwenen terwijl het bestand op de weggevallen share staat")
	}
}

// Het opruimen van lege mappen haalt een symlink naar een map niet weg.
func TestVerwijderenLaatEenSymlinkNaarEenMapStaan(t *testing.T) {
	e := newDeleteEnv(t)
	films := filepath.Join(e.root, "films")
	alias := filepath.Join(films, "Alias (1999)")
	if err := os.Symlink("The Matrix (1999)", alias); err != nil {
		t.Fatal(err)
	}
	if _, err := e.pool.Exec(context.Background(),
		`UPDATE media_files SET relative_path = 'Alias (1999)/The Matrix (1999).mkv' WHERE relative_path = 'The Matrix (1999)/The Matrix (1999).mkv'`); err != nil {
		t.Fatal(err)
	}
	rec := e.do(http.MethodDelete, "/pleya/v1/items/"+e.itemIDWhere(`title = 'The Matrix'`), nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("%d %s, wil 200", rec.Code, rec.Body.String())
	}
	if _, err := os.Lstat(alias); err != nil {
		t.Fatalf("de symlink naar de map is weggehaald: %v", err)
	}
}

// Een bibliotheek waarvan de root via een symlink dezelfde map is: niets gewist.
func TestVerwijderenWeigertEenRootDieEenAndereOverlapt(t *testing.T) {
	e := newDeleteEnv(t)
	alias := filepath.Join(e.root, "alias")
	if err := os.Symlink(filepath.Join(e.root, "films"), alias); err != nil {
		t.Fatal(err)
	}
	spec := func(slug, title, kind, root string) catalog.LibrarySpec {
		return catalog.LibrarySpec{Slug: slug, Title: title, Kind: kind, Roots: []catalog.RootSpec{
			{Path: root, FSType: "tmpfs", InodeTrusted: true, TrustSource: "fstype_default"}}}
	}
	if _, err := e.store.SyncLibraries(context.Background(), []catalog.LibrarySpec{
		spec("films", "Films", "movies", filepath.Join(e.root, "films")),
		spec("series", "Series", "shows", filepath.Join(e.root, "series")),
		spec("alias", "Alias", "movies", alias),
	}); err != nil {
		t.Fatal(err)
	}
	rec := e.do(http.MethodDelete, "/pleya/v1/items/"+e.itemIDWhere(`title = 'The Matrix' AND library_id = $1`, e.libs[0].ID), nil)
	if rec.Code != http.StatusConflict || decodeFailure(t, rec.Body.Bytes()).Error.Details.Reason != "root_overlap" {
		t.Fatalf("%d %s, wil 409 met reden root_overlap", rec.Code, rec.Body.String())
	}
	if !exists(t, filepath.Join(e.root, "films", "The Matrix (1999)", "The Matrix (1999).mkv")) {
		t.Fatal("het bestand is gewist")
	}
}

// Niet naast een scan van dezelfde bibliotheek.
func TestVerwijderenWachtOpEenScan(t *testing.T) {
	e := newDeleteEnv(t)
	if rec := e.do(http.MethodPost, "/pleya/v1/libraries/"+e.libs[0].ID.String()+"/scan", nil); rec.Code != http.StatusAccepted {
		t.Fatalf("scan gaf %d", rec.Code)
	}
	rec := e.do(http.MethodDelete, "/pleya/v1/items/"+e.itemIDWhere(`title = 'The Matrix'`), nil)
	if rec.Code != http.StatusConflict || decodeFailure(t, rec.Body.Bytes()).Error.Code != "library.scan_in_progress" {
		t.Fatalf("%d %s, wil 409 library.scan_in_progress", rec.Code, rec.Body.String())
	}
	if !exists(t, filepath.Join(e.root, "films", "The Matrix (1999)", "The Matrix (1999).mkv")) {
		t.Fatal("het bestand is gewist naast een scan")
	}
}
