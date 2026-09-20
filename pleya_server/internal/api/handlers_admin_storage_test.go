package api_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

// GET /storage/roots en POST /storage/roots/recheck (S2.3, J.3 venster 2). De
// drie-rollen-ronde staat tabelgedreven in authorize_matrix_test.go (regels 31
// en 32); hier staat het functionele gedrag.

// TestStorageRootsListsCandidatesAndClaimedRoots dekt de kern van S2.3: een
// root uit MediaRoots die geen bibliotheek heeft komt gewoon mee (een
// kandidaat), en een geclaimde root draagt de bibliotheek die hem gebruikt.
func TestStorageRootsListsCandidatesAndClaimedRoots(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	lib := e.createLibraryViaAPI(t, "Documentaires", "movies", []string{"/media/docs"})

	rec := e.do(http.MethodGet, "/pleya/v1/storage/roots", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /storage/roots gaf %d, verwacht 200: %s", rec.Code, rec.Body.String())
	}
	e.record("StorageRootList", http.MethodGet, "/pleya/v1/storage/roots", rec)

	var list api.StorageRootList
	if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil {
		t.Fatal(err)
	}

	byPath := map[string]api.StorageRoot{}
	for _, r := range list.Roots {
		byPath[r.Path] = r
	}

	claimed, ok := byPath["/media/docs"]
	if !ok {
		t.Fatalf("/media/docs ontbreekt in de lijst: %+v", list.Roots)
	}
	if len(claimed.Libraries) != 1 || claimed.Libraries[0].ID != lib.ID {
		t.Errorf("Libraries van /media/docs = %+v, verwacht [%s]", claimed.Libraries, lib.ID)
	}
	if claimed.Libraries[0].Title != "Documentaires" {
		t.Errorf("Libraries[0].Title = %q, verwacht Documentaires", claimed.Libraries[0].Title)
	}

	// /media zelf staat in MediaRoots (harness_test.go) en heeft geen
	// bibliotheek: een kandidaat, geen geclaimde root.
	candidate, ok := byPath["/media"]
	if !ok {
		t.Fatalf("/media (de kandidaat uit MediaRoots) ontbreekt: %+v", list.Roots)
	}
	if len(candidate.Libraries) != 0 {
		t.Errorf("Libraries van de kandidaat /media = %+v, verwacht leeg", candidate.Libraries)
	}
}

// TestStorageRootsReportsUnmountedCandidateWithoutError dekt de "losgekoppelde
// schijf"-regel uit hoofdstuk 17e.4: een offered root die niet bestaat komt
// mee met mounted: false, en de aanvraag faalt niet.
func TestStorageRootsReportsUnmountedCandidateWithoutError(t *testing.T) {
	e := newEnv(t, func(o *api.Options) {
		o.MediaRoots = []string{"/media", "/mnt/nooit-gemount"}
	})
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodGet, "/pleya/v1/storage/roots", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /storage/roots gaf %d, verwacht 200: %s", rec.Code, rec.Body.String())
	}

	var list api.StorageRootList
	if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil {
		t.Fatal(err)
	}
	for _, r := range list.Roots {
		if r.Path != "/mnt/nooit-gemount" {
			continue
		}
		if r.Mounted {
			t.Error("Mounted = true voor een pad dat niet bestaat")
		}
		if r.FSType != nil {
			t.Errorf("FSType = %v, verwacht null voor een niet-gemounte kandidaat", *r.FSType)
		}
		return
	}
	t.Fatalf("/mnt/nooit-gemount ontbreekt in de lijst: %+v", list.Roots)
}

// TestRecheckStorageRootsEnqueuesAJob dekt dat POST /storage/roots/recheck
// werkelijk iets inplant en niet alleen 202 antwoordt zonder gevolg.
func TestRecheckStorageRootsEnqueuesAJob(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodPost, "/pleya/v1/storage/roots/recheck", nil)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("POST /storage/roots/recheck gaf %d, verwacht 202: %s", rec.Code, rec.Body.String())
	}
	if rec.Body.Len() != 0 {
		t.Errorf("antwoordlichaam = %q, verwacht leeg bij 202", rec.Body.String())
	}

	var count int
	if err := e.pool.QueryRow(t.Context(),
		`SELECT count(*) FROM jobs WHERE kind = $1`, api.JobStorageRecheckRoots).Scan(&count); err != nil {
		t.Fatalf("jobs tellen: %v", err)
	}
	if count != 1 {
		t.Fatalf("jobs met kind %q = %d, verwacht 1", api.JobStorageRecheckRoots, count)
	}
}

// TestRecheckStorageRootsDedupesConcurrentTicks dekt de dedupe-sleutel: een
// tweede tik terwijl de eerste nog in de wachtrij staat mag geen tweede rij
// opleveren, dezelfde regel als bij een scanronde.
func TestRecheckStorageRootsDedupesConcurrentTicks(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	for i := 0; i < 2; i++ {
		rec := e.do(http.MethodPost, "/pleya/v1/storage/roots/recheck", nil)
		if rec.Code != http.StatusAccepted {
			t.Fatalf("tik %d gaf %d, verwacht 202: %s", i, rec.Code, rec.Body.String())
		}
	}

	var count int
	if err := e.pool.QueryRow(t.Context(),
		`SELECT count(*) FROM jobs WHERE kind = $1`, api.JobStorageRecheckRoots).Scan(&count); err != nil {
		t.Fatalf("jobs tellen: %v", err)
	}
	if count != 1 {
		t.Fatalf("jobs met kind %q na twee tikken = %d, verwacht 1 (dedupe)", api.JobStorageRecheckRoots, count)
	}
}

// TestRootOfferedRejectsTraversalAndForeignPaths dekt K rij 10: een pad dat
// niet letterlijk (na filepath.Clean) onder een aangeboden mount valt wordt
// geweigerd, zonder dat het bestandssysteem er ooit bij komt kijken.
func TestRootOfferedRejectsTraversalAndForeignPaths(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	cases := []string{
		"/etc/passwd",           // buiten elke aangeboden mount
		"/media/../etc/passwd",  // ../ die na Clean buiten /media uitkomt
		"relatief/pad",          // geen absoluut pad
		"/media/docs/",          // trailing slash: filepath.Clean(pad) != pad
		"/media//docs",          // dubbele slash: idem
	}
	for _, root := range cases {
		t.Run(root, func(t *testing.T) {
			rec := e.do(http.MethodPost, "/pleya/v1/libraries", map[string]any{
				"title": "Root-test " + root, "kind": "movies", "root_paths": []string{root},
			})
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("root_path %q gaf %d, verwacht 400: %s", root, rec.Code, rec.Body.String())
			}
			e.expectCode(rec, api.CodeStorageRootNotOffered)
		})
	}
}
