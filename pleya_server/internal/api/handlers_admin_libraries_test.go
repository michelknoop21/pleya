package api_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

// De CRUD-API van S2.2 (J.3 venster 2). De drie-rollen-ronde staat
// tabelgedreven in authorize_matrix_test.go (regels 28 tot en met 30); hier
// staat het functionele gedrag: wat een geslaagde aanroep oplevert, en de
// specifieke foutcodes die J.3 aan deze drie endpoints hangt.

func TestCreateLibrarySucceedsAsAdmin(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodPost, "/pleya/v1/libraries", map[string]any{
		"title": "Documentaires", "kind": "movies", "root_paths": []string{"/media/docs"},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("POST /libraries gaf %d, verwacht 201: %s", rec.Code, rec.Body.String())
	}
	e.record("Library", http.MethodPost, "/pleya/v1/libraries", rec)

	var lib api.Library
	if err := json.Unmarshal(rec.Body.Bytes(), &lib); err != nil {
		t.Fatal(err)
	}
	if lib.Title != "Documentaires" || lib.Kind != "movies" || lib.ID == "" {
		t.Fatalf("POST /libraries gaf %+v", lib)
	}
	if lib.Managed == nil || *lib.Managed != "db" {
		t.Fatalf("een via de API aangemaakte bibliotheek gaf managed %v, verwacht \"db\"", lib.Managed)
	}
	if lib.ScanOnStart == nil || !*lib.ScanOnStart {
		t.Fatalf("POST /libraries gaf scan_on_start %v, verwacht true", lib.ScanOnStart)
	}

	// Ze staat ook echt in GET /libraries, en niet alleen in het antwoord van
	// de aanmaak zelf.
	var list api.LibraryList
	e.getJSON("/pleya/v1/libraries", "LibraryList", http.StatusOK, &list)
	found := false
	for _, l := range list.Items {
		if l.ID == lib.ID {
			found = true
		}
	}
	if !found {
		t.Fatal("de aangemaakte bibliotheek staat niet in GET /libraries")
	}
}

func TestCreateLibrarySlugCollisionIsRejected(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	// newEnv seedt zelf al een bibliotheek met slug "films"; deze titels
	// vereenvoudigen allebei tot "documentaires" en botsen dus alleen met
	// elkaar, niet met de fixture.
	first := e.do(http.MethodPost, "/pleya/v1/libraries", map[string]any{
		"title": "Documentaires!", "kind": "movies", "root_paths": []string{"/media/a"},
	})
	if first.Code != http.StatusCreated {
		t.Fatalf("eerste POST /libraries gaf %d: %s", first.Code, first.Body.String())
	}

	second := e.do(http.MethodPost, "/pleya/v1/libraries", map[string]any{
		"title": "Documentaires?", "kind": "movies", "root_paths": []string{"/media/b"},
	})
	if second.Code != http.StatusConflict {
		t.Fatalf("tweede POST /libraries (zelfde slug) gaf %d, verwacht 409: %s", second.Code, second.Body.String())
	}
	e.recordVariant("ErrorEnvelope", "slug_taken", http.MethodPost, "/pleya/v1/libraries", second)
	if code := errorCode(t, second); code != "library.slug_taken" {
		t.Fatalf("tweede POST /libraries gaf code %q, verwacht library.slug_taken", code)
	}
}

func TestCreateLibraryOverlappingRootIsRejected(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodPost, "/pleya/v1/libraries", map[string]any{
		"title": "Dubbel", "kind": "movies", "root_paths": []string{"/media/a", "/media/a/sub"},
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("overlappende root_paths gaven %d, verwacht 400: %s", rec.Code, rec.Body.String())
	}
	if code := errorCode(t, rec); code != "storage.root_not_offered" {
		t.Fatalf("overlappende root_paths gaven code %q, verwacht storage.root_not_offered", code)
	}
}

func TestCreateLibraryUnknownKindIsRejected(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodPost, "/pleya/v1/libraries", map[string]any{
		"title": "Boeken", "kind": "books", "root_paths": []string{"/media/books"},
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("kind \"books\" (nog geen S3) gaf %d, verwacht 400: %s", rec.Code, rec.Body.String())
	}
	if code := errorCode(t, rec); code != "storage.root_not_offered" {
		t.Fatalf("kind \"books\" gaf code %q, verwacht storage.root_not_offered", code)
	}
}

func TestUpdateLibraryChangesTitleAndScanSettings(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	created := e.createLibraryViaAPI(t, "Origineel", "movies", []string{"/media/orig"})

	seconds := 1800
	rec := e.do(http.MethodPatch, "/pleya/v1/libraries/"+created.ID, map[string]any{
		"title": "Hernoemd", "scan_interval_seconds": seconds, "scan_on_start": false,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("PATCH /libraries/{id} gaf %d, verwacht 200: %s", rec.Code, rec.Body.String())
	}
	e.record("Library", http.MethodPatch, "/pleya/v1/libraries/{library_id}", rec)

	var lib api.Library
	if err := json.Unmarshal(rec.Body.Bytes(), &lib); err != nil {
		t.Fatal(err)
	}
	if lib.Title != "Hernoemd" {
		t.Fatalf("PATCH gaf title %q, verwacht \"Hernoemd\"", lib.Title)
	}
	if lib.ScanIntervalSeconds == nil || *lib.ScanIntervalSeconds == nil || **lib.ScanIntervalSeconds != 1800 {
		t.Fatalf("PATCH gaf scan_interval_seconds %v, verwacht 1800", lib.ScanIntervalSeconds)
	}
	if lib.ScanOnStart == nil || *lib.ScanOnStart {
		t.Fatalf("PATCH gaf scan_on_start %v, verwacht false", lib.ScanOnStart)
	}

	// scan_interval_seconds terugzetten op null (gebruik de globale interval).
	clear := e.do(http.MethodPatch, "/pleya/v1/libraries/"+created.ID, map[string]any{
		"scan_interval_seconds": nil,
	})
	if clear.Code != http.StatusOK {
		t.Fatalf("PATCH (null) gaf %d: %s", clear.Code, clear.Body.String())
	}
	// Niet in api.Library decoderen: Go zet een **int bij het JSON-literaal
	// null zelf al op nil, dus "het veld staat er met null" en "het veld staat
	// er niet" zijn dan niet meer te onderscheiden. Een kale map met de `,ok`
	// idioom bewijst wél het echte contract: de sleutel staat er, de waarde is
	// null.
	var raw map[string]any
	if err := json.Unmarshal(clear.Body.Bytes(), &raw); err != nil {
		t.Fatal(err)
	}
	value, present := raw["scan_interval_seconds"]
	if !present {
		t.Fatal("PATCH (null) liet scan_interval_seconds helemaal weg, verwacht het veld met waarde null")
	}
	if value != nil {
		t.Fatalf("PATCH (null) liet scan_interval_seconds op %v staan, verwacht null", value)
	}
}

func TestUpdateLibraryKindRejectedWhenNotEmpty(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	// e.libs[0] is "films" (movies), gevuld door newEnv's scanAll.
	filmsID := e.libs[0].ID.String()
	rec := e.do(http.MethodPatch, "/pleya/v1/libraries/"+filmsID, map[string]any{"kind": "shows"})
	if rec.Code != http.StatusConflict {
		t.Fatalf("kind-wissel op een gevulde bibliotheek gaf %d, verwacht 409: %s", rec.Code, rec.Body.String())
	}
	e.recordVariant("ErrorEnvelope", "not_empty", http.MethodPatch, "/pleya/v1/libraries/{library_id}", rec)
	if code := errorCode(t, rec); code != "library.not_empty" {
		t.Fatalf("kind-wissel op een gevulde bibliotheek gaf code %q, verwacht library.not_empty", code)
	}
}

func TestUpdateLibraryKindAllowedWhenEmpty(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	created := e.createLibraryViaAPI(t, "Leeg", "movies", []string{"/media/leeg"})

	rec := e.do(http.MethodPatch, "/pleya/v1/libraries/"+created.ID, map[string]any{"kind": "shows"})
	if rec.Code != http.StatusOK {
		t.Fatalf("kind-wissel op een lege bibliotheek gaf %d, verwacht 200: %s", rec.Code, rec.Body.String())
	}
	var lib api.Library
	if err := json.Unmarshal(rec.Body.Bytes(), &lib); err != nil {
		t.Fatal(err)
	}
	if lib.Kind != "shows" {
		t.Fatalf("PATCH gaf kind %q, verwacht \"shows\"", lib.Kind)
	}
}

func TestDeleteLibraryRequiresExactConfirm(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	created := e.createLibraryViaAPI(t, "Te verwijderen", "movies", []string{"/media/verwijder"})

	wrong := e.do(http.MethodDelete, "/pleya/v1/libraries/"+created.ID,
		map[string]string{"confirm": "verkeerd"})
	if wrong.Code != http.StatusConflict {
		t.Fatalf("DELETE met foute confirm gaf %d, verwacht 409: %s", wrong.Code, wrong.Body.String())
	}
	e.recordVariant("ErrorEnvelope", "confirm_mismatch", http.MethodDelete, "/pleya/v1/libraries/{library_id}", wrong)
	if code := errorCode(t, wrong); code != "library.confirm_mismatch" {
		t.Fatalf("DELETE met foute confirm gaf code %q, verwacht library.confirm_mismatch", code)
	}

	// Nog steeds bereikbaar: de foute confirm heeft niets verwijderd.
	var list api.LibraryList
	e.getJSON("/pleya/v1/libraries", "", http.StatusOK, &list)
	stillThere := false
	for _, l := range list.Items {
		if l.ID == created.ID {
			stillThere = true
		}
	}
	if !stillThere {
		t.Fatal("een DELETE met foute confirm heeft de bibliotheek toch verwijderd")
	}

	right := e.do(http.MethodDelete, "/pleya/v1/libraries/"+created.ID,
		map[string]string{"confirm": "Te verwijderen"})
	if right.Code != http.StatusNoContent {
		t.Fatalf("DELETE met juiste confirm gaf %d, verwacht 204: %s", right.Code, right.Body.String())
	}

	e.getJSON("/pleya/v1/libraries", "", http.StatusOK, &list)
	for _, l := range list.Items {
		if l.ID == created.ID {
			t.Fatal("de bibliotheek staat er na verwijdering nog steeds in")
		}
	}
}

// TestLibraryListHidesManagementFieldsFromMembers dekt J.3: managed,
// scan_interval_seconds en scan_on_start gaan alleen mee voor klasse admin. Een
// lid ziet dezelfde vier velden die het endpoint altijd al gaf.
func TestLibraryListHidesManagementFieldsFromMembers(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	memberID := e.createUser("member", "kijker")
	e.grantLibrary(memberID, e.libs[0].ID, "view")
	member := e.tokenFor(memberID)

	rec := e.do(http.MethodGet, "/pleya/v1/libraries", nil, asUser(member))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /libraries als lid gaf %d: %s", rec.Code, rec.Body.String())
	}
	var raw struct {
		Items []map[string]any `json:"items"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &raw); err != nil {
		t.Fatal(err)
	}
	if len(raw.Items) == 0 {
		t.Fatal("een lid met recht op films zag geen enkele bibliotheek")
	}
	for _, item := range raw.Items {
		for _, field := range []string{"managed", "scan_interval_seconds", "scan_on_start"} {
			if _, present := item[field]; present {
				t.Fatalf("GET /libraries voor een lid droeg %q, dat is klasse admin (J.3)", field)
			}
		}
	}

	admin := e.tokenFor(e.createUser("admin", "beheerder"))
	adminRec := e.do(http.MethodGet, "/pleya/v1/libraries", nil, asUser(admin))
	var adminRaw struct {
		Items []map[string]any `json:"items"`
	}
	if err := json.Unmarshal(adminRec.Body.Bytes(), &adminRaw); err != nil {
		t.Fatal(err)
	}
	if len(adminRaw.Items) == 0 {
		t.Fatal("een admin zag geen enkele bibliotheek")
	}
	for _, field := range []string{"managed", "scan_interval_seconds", "scan_on_start"} {
		if _, present := adminRaw.Items[0][field]; !present {
			t.Fatalf("GET /libraries voor een admin miste %q", field)
		}
	}
}

// createLibraryViaAPI is de testhulp die de handlers hierboven al bewijst; hij
// bestaat zodat andere tests een db-beheerde bibliotheek kunnen opzetten
// zonder de aanmaak zelf opnieuw te controleren.
func (e *env) createLibraryViaAPI(t *testing.T, title, kind string, rootPaths []string) api.Library {
	t.Helper()
	rec := e.do(http.MethodPost, "/pleya/v1/libraries", map[string]any{
		"title": title, "kind": kind, "root_paths": rootPaths,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("POST /libraries voor %q gaf %d: %s", title, rec.Code, rec.Body.String())
	}
	var lib api.Library
	if err := json.Unmarshal(rec.Body.Bytes(), &lib); err != nil {
		t.Fatal(err)
	}
	return lib
}
