package api_test

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/downloads"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
)

// runDigest voert de achtergrondtaak van één download uit, zoals de runner dat
// in productie doet.
func (e *env) runDigest(downloadID string) {
	e.t.Helper()
	args, _ := json.Marshal(map[string]string{"download_id": downloadID})
	h := downloads.DigestHandler(downloads.NewStore(e.pool), e.store, e.log)
	if err := h(context.Background(), jobs.Job{Args: args}); err != nil {
		e.t.Fatalf("digest-taak: %v", err)
	}
}

func (e *env) startDownload(itemID string, opts ...func(*http.Request)) api.DownloadWire {
	e.t.Helper()
	rec := e.do(http.MethodPost, "/pleya/v1/downloads", map[string]any{"item_id": itemID}, opts...)
	if rec.Code != http.StatusCreated {
		e.t.Fatalf("download starten gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("Download", http.MethodPost, "/pleya/v1/downloads", rec)
	var d api.DownloadWire
	e.decodeInto(rec, &d)
	return d
}

func (e *env) moviePath(title string) (item api.Item, abs string) {
	e.t.Helper()
	item = e.findMovie(title)
	file, _, err := e.store.StreamFile(context.Background(), mustID(e.t, item.Versions[0].ID))
	if err != nil {
		e.t.Fatal(err)
	}
	return item, file.AbsPath
}

func mustID(t *testing.T, raw string) id.ID {
	t.Helper()
	v, err := id.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	return v
}

func TestDownloadIsPreparedThenDeliveredWithDigestAndResumesOnlyOnEqualContent(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie, abs := e.moviePath("Grease")

	dl := e.startDownload(movie.ID)
	if dl.Status != "preparing" || dl.SHA256 != nil {
		t.Fatalf("een nieuwe download hoort te wachten op zijn hash: %+v", dl)
	}
	// Vóór de hash levert hij niets, en dat is een herhaalbare weigering.
	rec := e.do(http.MethodGet, dl.FileURL, nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("bestand vóór de hash gaf %d", rec.Code)
	}
	e.expectCode(rec, api.CodeDownloadNotReady)
	e.recordVariant("ErrorEnvelope", "download_not_ready", http.MethodGet, dl.FileURL, rec)

	e.runDigest(dl.ID)
	var ready api.DownloadWire
	e.getJSON("/pleya/v1/downloads/"+dl.ID, "Download", http.StatusOK, &ready)
	raw, err := os.ReadFile(abs)
	if err != nil {
		t.Fatal(err)
	}
	want := sha256.Sum256(raw)
	if ready.Status != "ready" || ready.SHA256 == nil || *ready.SHA256 != hex.EncodeToString(want[:]) {
		t.Fatalf("hash of toestand klopt niet: %+v", ready)
	}

	rec = e.do(http.MethodGet, ready.FileURL, nil)
	if rec.Code != http.StatusOK || rec.Body.Len() != len(raw) {
		t.Fatalf("volledig bestand gaf %d met %d van %d bytes", rec.Code, rec.Body.Len(), len(raw))
	}
	got := sha256.Sum256(rec.Body.Bytes())
	if got != want {
		t.Fatal("de geleverde bytes hebben een andere hash dan de aangekondigde")
	}
	if d := rec.Header().Get("Digest"); d != "sha-256="+base64.StdEncoding.EncodeToString(want[:]) {
		t.Fatalf("Digest is %q", d)
	}
	etag := rec.Header().Get("ETag")
	if etag != `"sha256-`+hex.EncodeToString(want[:])+`"` {
		t.Fatalf("de validator hoort sterk te zijn en de hash te dragen: %q", etag)
	}

	// Hervatten met de juiste validator: een deelantwoord vanaf byte 10.
	rec = e.do(http.MethodGet, ready.FileURL, nil, withHeader("Range", "bytes=10-"), withHeader("If-Range", etag))
	if rec.Code != http.StatusPartialContent || rec.Body.Len() != len(raw)-10 {
		t.Fatalf("hervatten gaf %d met %d bytes", rec.Code, rec.Body.Len())
	}
	if string(rec.Body.Bytes()) != string(raw[10:]) {
		t.Fatal("het hervatte stuk is niet het staartstuk van het bestand")
	}
	// Hervatten met een validator van andere inhoud: het hele bestand opnieuw.
	rec = e.do(http.MethodGet, ready.FileURL, nil, withHeader("Range", "bytes=10-"), withHeader("If-Range", `"sha256-`+hex.EncodeToString(make([]byte, 32))+`"`))
	if rec.Code != http.StatusOK || rec.Body.Len() != len(raw) {
		t.Fatalf("hervatten op andere inhoud gaf %d met %d bytes: dat moet een volledig antwoord zijn", rec.Code, rec.Body.Len())
	}
}

func TestDownloadBelongsToItsOwnerAndNeedsTheDownloadRight(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie, _ := e.moviePath("Grease")
	films := e.libraryByKind("movies")

	viewer := e.createUser("member", "kijker")
	e.grantLibrary(viewer, films.ID, "view")
	viewerTok := e.tokenFor(viewer)
	rec := e.do(http.MethodPost, "/pleya/v1/downloads", map[string]any{"item_id": movie.ID}, asUser(viewerTok))
	if rec.Code != http.StatusForbidden {
		t.Fatalf("alleen kijken gaf %d, verwacht 403", rec.Code)
	}
	e.expectCode(rec, api.CodeDownloadNotPermitted)
	e.recordVariant("ErrorEnvelope", "download_not_permitted", http.MethodPost, "/pleya/v1/downloads", rec)

	nobody := e.createUser("member", "vreemde")
	rec = e.do(http.MethodPost, "/pleya/v1/downloads", map[string]any{"item_id": movie.ID}, asUser(e.tokenFor(nobody)))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("een bibliotheek die hij niet ziet gaf %d, verwacht 404", rec.Code)
	}

	loader := e.createUser("member", "binnenhaler")
	e.grantLibrary(loader, films.ID, "download")
	loaderTok := e.tokenFor(loader)
	dl := e.startDownload(movie.ID, asUser(loaderTok))
	e.runDigest(dl.ID)

	// De eigenaar van de installatie, ook beheerder in alles, ziet de download van een ander niet.
	for _, path := range []string{"/pleya/v1/downloads/" + dl.ID, dl.FileURL} {
		if rec := e.do(http.MethodGet, path, nil); rec.Code != http.StatusNotFound {
			t.Fatalf("download van een ander op %s gaf %d, verwacht 404", path, rec.Code)
		}
	}
	if rec := e.do(http.MethodDelete, "/pleya/v1/downloads/"+dl.ID, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("verwijderen van een ander gaf %d", rec.Code)
	}
	var list api.DownloadList
	e.getJSON("/pleya/v1/downloads", "DownloadList", http.StatusOK, &list)
	if len(list.Items) != 0 {
		t.Fatalf("de lijst van de owner bevat downloads van een ander: %+v", list.Items)
	}

	// Het recht wordt bij elke byte-aanvraag opnieuw getoetst.
	if _, err := e.pool.Exec(context.Background(), `UPDATE library_permissions SET permission = 'view' WHERE user_id = $1`, loader); err != nil {
		t.Fatal(err)
	}
	rec = e.do(http.MethodGet, dl.FileURL, nil, asUser(loaderTok))
	if rec.Code != http.StatusForbidden {
		t.Fatalf("na het intrekken gaf het bestand %d, verwacht 403", rec.Code)
	}
}

func TestDownloadRefusesAFileThatChangedAfterTheHash(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie, abs := e.moviePath("Grease")
	dl := e.startDownload(movie.ID)
	e.runDigest(dl.ID)
	if rec := e.do(http.MethodGet, dl.FileURL, nil); rec.Code != http.StatusOK {
		t.Fatalf("vóór de wijziging gaf het bestand %d", rec.Code)
	}

	future := time.Now().Add(time.Hour)
	if err := os.Chtimes(abs, future, future); err != nil {
		t.Fatal(err)
	}
	rec := e.do(http.MethodGet, dl.FileURL, nil, withHeader("Range", "bytes=10-"), withHeader("If-Range", `"x"`))
	if rec.Code != http.StatusConflict {
		t.Fatalf("na de wijziging gaf het bestand %d, verwacht 409", rec.Code)
	}
	e.expectCode(rec, api.CodeDownloadChanged)
	e.recordVariant("ErrorEnvelope", "download_changed", http.MethodGet, dl.FileURL, rec)
}

func TestDownloadCanBeDeletedAndTheMediaFileStays(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie, abs := e.moviePath("Grease")
	dl := e.startDownload(movie.ID)
	if rec := e.do(http.MethodDelete, "/pleya/v1/downloads/"+dl.ID, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("verwijderen gaf %d", rec.Code)
	}
	if rec := e.do(http.MethodGet, "/pleya/v1/downloads/"+dl.ID, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("na verwijderen gaf de download %d", rec.Code)
	}
	if _, err := os.Stat(abs); err != nil {
		t.Fatalf("het mediabestand verdween met de download: %v", err)
	}
}

func TestANewDownloadReplacesTheEarlierOneOfTheSameVersion(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	item, _ := e.moviePath("Grease")
	first := e.startDownload(item.ID)
	second := e.startDownload(item.ID)
	if first.ID == second.ID {
		t.Fatal("een tweede aanvraag gaf dezelfde download")
	}
	if rec := e.do(http.MethodGet, "/pleya/v1/downloads/"+first.ID, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("de eerdere download bestaat nog: %d", rec.Code)
	}
}

func TestDownloadCarriesTheDeviceOfTheSessionThatAskedForIt(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease")

	login := e.do(http.MethodPost, "/pleya/v1/auth/login", map[string]any{
		"username": "michel", "password": "een-lang-genoeg-wachtwoord", "device_id": "tv-1", "device_name": "Apple TV",
	}, withoutAuth)
	if login.Code != http.StatusOK {
		t.Fatalf("inloggen gaf %d: %s", login.Code, login.Body.String())
	}
	var pair api.TokenPair
	e.decodeInto(login, &pair)

	d := e.startDownload(movie.ID, asUser(pair.AccessToken))
	if d.DeviceName == nil || *d.DeviceName != "Apple TV" {
		t.Fatalf("aanmaken gaf toestel %v", d.DeviceName)
	}
	e.runDigest(d.ID)
	var read api.DownloadWire
	e.getJSON("/pleya/v1/downloads/"+d.ID, "Download", http.StatusOK, &read)
	if read.DeviceName == nil || *read.DeviceName != "Apple TV" {
		t.Fatalf("lezen gaf toestel %v", read.DeviceName)
	}
	var list api.DownloadList
	e.getJSON("/pleya/v1/downloads", "DownloadList", http.StatusOK, &list)
	if len(list.Items) != 1 || list.Items[0].DeviceName == nil || *list.Items[0].DeviceName != "Apple TV" {
		t.Fatalf("lijst %+v", list.Items)
	}

	// Een download van vóór 0024 heeft geen sessie: null, en geen fout.
	if _, err := e.pool.Exec(context.Background(), `UPDATE downloads SET auth_session_id = NULL WHERE id = $1`, d.ID); err != nil {
		t.Fatal(err)
	}
	e.getJSON("/pleya/v1/downloads/"+d.ID, "Download", http.StatusOK, &read)
	if read.DeviceName != nil {
		t.Fatalf("zonder sessie gaf de download toestel %q", *read.DeviceName)
	}
}

// De plaatshouder van een sessie zonder naam is geen toestelnaam.
func TestDownloadOfASessionWithoutANameHasNoDevice(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	d := e.startDownload(e.findMovie("Grease").ID)
	if d.DeviceName != nil {
		t.Fatalf("toestel %q, verwacht null", *d.DeviceName)
	}
}

func TestLibrariesCarryTheOwnPermission(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movies := e.libraryByKind("movies")
	shows := e.libraryByKind("shows")

	permissions := func(opts ...func(*http.Request)) map[string]string {
		t.Helper()
		var list api.LibraryList
		e.decodeInto(e.do(http.MethodGet, "/pleya/v1/libraries", nil, opts...), &list)
		out := map[string]string{}
		for _, l := range list.Items {
			if l.Permission == nil {
				t.Fatalf("bibliotheek %s zonder recht", l.Title)
			}
			out[l.ID] = *l.Permission
		}
		return out
	}

	got := permissions()
	if got[movies.ID.String()] != "manage" || got[shows.ID.String()] != "manage" {
		t.Fatalf("eigenaar %v", got)
	}

	member := e.createUser("member", "huisgenoot")
	e.grantLibrary(member, movies.ID, "download")
	theirs := permissions(asUser(e.tokenFor(member)))
	if len(theirs) != 1 || theirs[movies.ID.String()] != "download" {
		t.Fatalf("lid %v", theirs)
	}
}
