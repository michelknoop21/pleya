package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

func TestAppliedIdentityWireAndStatusKeepRequestedSeparate(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()
	movie := e.findMovie("Grease")
	item := id.MustParse(movie.ID)
	var info map[string]any
	e.getJSON("/pleya/v1/info", "", http.StatusOK, &info)
	caps := info["capabilities"].(map[string]any)
	if caps["applied_external_identity"] != true || caps["metadata_match_status"] != true {
		t.Fatalf("nieuwe grens ontbreekt: %+v", caps)
	}
	statusPath := "/pleya/v1/items/" + movie.ID + "/metadata-match"
	var status map[string]any
	e.getJSON(statusPath, "", http.StatusOK, &status)
	if status["application_state"] != "unknown" || status["requested_external_ids"] != nil || status["applied_external_ids"] != nil || status["updated_at"] != nil {
		t.Fatalf("zonder kandidaat: %+v", status)
	}
	// Echte guarded publicatie A, daarna de nog niet gepubliceerde keuze B.
	if err := e.store.SetManualMatch(ctx, item, "tmdb", "621"); err != nil {
		t.Fatal(err)
	}
	targets, err := e.store.MetadataDue(ctx, "tmdb", 3, nil, 100)
	if err != nil {
		t.Fatal(err)
	}
	var target catalog.MetadataTarget
	for _, v := range targets {
		if v.ID == item {
			target = v
		}
	}
	if target.ID != item {
		t.Fatal("geen target")
	}
	d := catalog.MetadataDetails{Summary: "toegepast A"}
	if err := e.store.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", ExternalID: "621", State: catalog.CandidateMatched, Pass: 3}, &d, nil, nil); err != nil {
		t.Fatal(err)
	}
	if err := e.store.SetManualMatch(ctx, item, "tmdb", "622"); err != nil {
		t.Fatal(err)
	}
	for _, state := range []string{"pending", "failed"} {
		if state == "failed" {
			targets, err = e.store.MetadataDue(ctx, "tmdb", 3, nil, 100)
			if err != nil {
				t.Fatal(err)
			}
			for _, v := range targets {
				if v.ID == item {
					target = v
				}
			}
			if err := e.store.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", ExternalID: "622", State: catalog.CandidateFailed, Pass: 3}, nil, nil, nil); err != nil {
				t.Fatal(err)
			}
		}
		status = nil
		e.getJSON(statusPath, "", http.StatusOK, &status)
		if status["application_state"] != state || status["requested_external_ids"].(map[string]any)["tmdb"] != float64(622) || status["applied_external_ids"].(map[string]any)["tmdb"] != float64(621) || status["updated_at"] == nil {
			t.Fatalf("%s status: %+v", state, status)
		}
		if state == "failed" && status["error_code"] != "application_failed" {
			t.Fatalf("onveilige of ontbrekende fout: %+v", status)
		}
		var detail map[string]any
		e.getJSON("/pleya/v1/items/"+movie.ID, "", http.StatusOK, &detail)
		if detail["applied_external_ids"].(map[string]any)["tmdb"] != float64(621) || detail["summary"] != "toegepast A" {
			t.Fatalf("gemengde Item: %+v", detail)
		}
		var page api.ItemPage
		e.getJSON("/pleya/v1/libraries/"+e.libraryID("movies")+"/items?applied_external_id=tmdb:621", "", http.StatusOK, &page)
		if len(page.Items) != 1 || page.Items[0].ID != movie.ID {
			t.Fatalf("applied A kwijt in %s: %+v", state, page)
		}
		e.getJSON("/pleya/v1/libraries/"+e.libraryID("movies")+"/items?applied_external_id=tmdb:622", "", http.StatusOK, &page)
		if len(page.Items) != 0 {
			t.Fatalf("intentie B als applied: %+v", page)
		}
	}
	if r := e.do(http.MethodGet, statusPath, nil, withoutAuth); r.Code != http.StatusUnauthorized {
		t.Fatalf("anoniem status=%d", r.Code)
	}
	if _, err := e.store.RejectMatch(ctx, item, "tmdb"); err != nil {
		t.Fatal(err)
	}
	status = nil
	e.getJSON(statusPath, "", http.StatusOK, &status)
	if status["application_state"] != "unknown" || status["applied_external_ids"] != nil {
		t.Fatalf("reject: %+v", status)
	}
	var detail map[string]any
	e.getJSON("/pleya/v1/items/"+movie.ID, "", http.StatusOK, &detail)
	if detail["applied_external_ids"] != nil {
		t.Fatalf("reject item: %+v", detail)
	}
}

func TestAppliedLookupRejectsMalformedAndMixedFilters(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	path := "/pleya/v1/libraries/" + e.libraryID("movies") + "/items?"
	for _, q := range []string{"external_id=tmdb:621&applied_external_id=tmdb:621", "external_id=&applied_external_id=", "external_id=bad&applied_external_id=tmdb:621"} {
		r := e.do(http.MethodGet, path+q, nil)
		if r.Code != http.StatusBadRequest {
			t.Fatalf("%s: %d", q, r.Code)
		}
	}
	for _, bad := range []string{"", "tmdb:abc", "tmdb:0", "imdb:tt1", "621", "tmdb:-3", "tmdb:+5", "tmdb:0621", "tmdb: 5", "tmdb:999999999999999999999999"} {
		r := e.do(http.MethodGet, path+"applied_external_id="+url.QueryEscape(bad), nil)
		var envelope map[string]any
		_ = json.Unmarshal(r.Body.Bytes(), &envelope)
		if r.Code != http.StatusBadRequest {
			t.Fatalf("%q: %d %+v", bad, r.Code, envelope)
		}
	}
	var shows api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+e.libraryID("shows")+"/items", "", http.StatusOK, &shows)
	var children api.ItemPage
	e.getJSON("/pleya/v1/items/"+shows.Items[0].ID+"/children", "", http.StatusOK, &children)
	for _, item := range []string{id.New().String(), "invalid", children.Items[0].ID} {
		r := e.do(http.MethodGet, "/pleya/v1/items/"+item+"/metadata-match", nil)
		if r.Code != http.StatusNotFound {
			t.Fatalf("ongeldig/afwezig %s: %d", item, r.Code)
		}
	}
}

func TestAppliedStatusChecksCurrentAdminScopeAndRevocation(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	path := "/pleya/v1/items/" + e.findMovie("Grease").ID + "/metadata-match"
	for _, scope := range []string{"read", "maintenance", "admin"} {
		token := e.createToken(map[string]any{"name": "scopeproef", "scope": scope}, http.StatusCreated)
		want := http.StatusNotFound
		if scope == "admin" {
			want = http.StatusOK
		}
		if r := e.do(http.MethodGet, path, nil, asToken(token.Secret)); r.Code != want {
			t.Fatalf("%s gaf %d", scope, r.Code)
		}
		if scope == "admin" {
			if r := e.do(http.MethodDelete, "/pleya/v1/sessions/"+token.Token.ID, nil); r.Code != http.StatusNoContent {
				t.Fatal(r.Code)
			}
			if r := e.do(http.MethodGet, path, nil, asToken(token.Secret)); r.Code != http.StatusUnauthorized {
				t.Fatalf("ingetrokken admin gaf %d", r.Code)
			}
		}
	}
	// Een nog geldig bearer krijgt geen beheerrecht uit zijn oude claim.
	ctx := context.Background()
	if _, err := e.pool.Exec(ctx, `UPDATE users SET role='member' WHERE username='michel'`); err != nil {
		t.Fatal(err)
	}
	if r := e.do(http.MethodGet, path, nil); r.Code != http.StatusNotFound {
		t.Fatalf("verouderde ownerclaim gaf %d", r.Code)
	}

}

// Twee keuzes binnen dezelfde toekomstige seconde verschillen echt één
// PostgreSQL-microseconde. De status mag die generatie niet afronden.
func TestAppliedStatusPreservesExactMonotoneGeneration(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()
	movie := e.findMovie("Grease")
	item := id.MustParse(movie.ID)
	if err := e.store.SetManualMatch(ctx, item, "tmdb", "621"); err != nil {
		t.Fatal(err)
	}
	future := time.Date(2035, 1, 1, 12, 34, 56, 123456000, time.UTC)
	if _, err := e.pool.Exec(ctx, `UPDATE metadata_candidates SET updated_at=$2 WHERE item_id=$1`, item, future); err != nil {
		t.Fatal(err)
	}
	var previous time.Time
	for i := 0; i < 2; i++ {
		if i > 0 {
			if err := e.store.SetManualMatch(ctx, item, "tmdb", "621"); err != nil {
				t.Fatal(err)
			}
		}
		var stored time.Time
		if err := e.pool.QueryRow(ctx, `SELECT updated_at FROM metadata_candidates WHERE item_id=$1`, item).Scan(&stored); err != nil {
			t.Fatal(err)
		}
		want := future.Add(time.Duration(i) * time.Microsecond)
		if !stored.Equal(want) {
			t.Fatalf("fixturegeneratie=%s, verwacht %s", stored, want)
		}
		var wire struct {
			UpdatedAt *string `json:"updated_at"`
		}
		e.getJSON("/pleya/v1/items/"+movie.ID+"/metadata-match", "MetadataMatchStatus", http.StatusOK, &wire)
		if wire.UpdatedAt == nil {
			t.Fatal("generatie ontbreekt")
		}
		got, err := time.Parse(time.RFC3339Nano, *wire.UpdatedAt)
		if err != nil {
			t.Fatal(err)
		}
		if !got.Equal(stored) {
			t.Errorf("wiregeneratie %s verliest opslaggeneratie %s", got.Format(time.RFC3339Nano), stored.Format(time.RFC3339Nano))
		}
		if i > 0 && !got.After(previous) {
			t.Errorf("wiregeneratie nam niet strikt toe: %s -> %s", previous, got)
		}
		previous = got
	}
}
