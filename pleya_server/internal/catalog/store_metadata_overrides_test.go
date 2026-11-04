package catalog_test

import (
	"encoding/json"
	"errors"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

func overrideValues(t *testing.T, values map[string]any) map[string]json.RawMessage {
	t.Helper()
	out := map[string]json.RawMessage{}
	for k, v := range values {
		raw, err := json.Marshal(v)
		if err != nil {
			t.Fatal(err)
		}
		out[k] = raw
	}
	return out
}
func TestMetadataOverridesSurviveRoundsRematchRestartAndReject(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	item := ids["alien"]
	if err := store.ApplyMetadata(ctx, item, "tmdb", publicationA()); err != nil {
		t.Fatal(err)
	}
	values := overrideValues(t, map[string]any{"title": "Mijn titel", "year": nil, "summary": "", "genres": []string{}, "content_rating": "", "people": []catalog.Person{}})
	if err := store.SetMetadataOverrides(ctx, item, values); err != nil {
		t.Fatal(err)
	}
	for round := 1; round <= 3; round++ {
		if err := store.SetManualMatch(ctx, item, "tmdb", "2"); err != nil {
			t.Fatal(err)
		}
		targets, err := store.MetadataDue(ctx, "tmdb", 3, nil, 20)
		if err != nil {
			t.Fatal(err)
		}
		for _, target := range targets {
			if target.ID != item {
				continue
			}
			d := catalog.MetadataDetails{Summary: "B", Genres: []string{"B"}, ContentRating: "B", People: []catalog.Person{{Name: "B", Role: "actor"}}}
			nfo := publicationNFO()
			c := catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "2", Pass: round}
			if err := store.CommitMetadata(ctx, target, c, &d, &nfo, nil); err != nil {
				t.Fatal(err)
			}
		}
		// Nieuwe Store leest duurzame toestand; geen in-memory lockregister.
		store = catalog.NewStore(pool)
		fields, err := store.MetadataFields(ctx, item)
		if err != nil {
			t.Fatal(err)
		}
		for name, want := range values {
			got := fields.Fields[name]
			if !got.Locked || got.Source != "manual" || string(got.Value) != string(want) {
				t.Fatalf("ronde%d %s=%+v verwacht %s", round, name, got, want)
			}
		}
	}
	state := readApplication(t, ctx, pool, item)
	if state.applied != "2" {
		t.Fatalf("override verdraaide applied: %+v", state)
	}
	if _, err := store.RejectMatch(ctx, item, "tmdb"); err != nil {
		t.Fatal(err)
	}
	fields, err := store.MetadataFields(ctx, item)
	if err != nil {
		t.Fatal(err)
	}
	if !fields.Fields["summary"].Locked {
		t.Fatal("reject verloor lock")
	}
	if err := store.DeleteMetadataOverride(ctx, item, "summary"); err != nil {
		t.Fatal(err)
	}
	fields, _ = store.MetadataFields(ctx, item)
	if fields.Fields["summary"].Source != "nfo" || string(fields.Fields["summary"].Value) != `"actuele NFO"` {
		t.Fatalf("reject unlock: %+v", fields.Fields["summary"])
	}
}

func TestMetadataOverrideUnlockCurrentSourceAndUncertainFallback(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	item := ids["alien"]
	if err := store.ApplyMetadata(ctx, item, "tmdb", publicationA()); err != nil {
		t.Fatal(err)
	}
	if err := store.SetMetadataOverrides(ctx, item, overrideValues(t, map[string]any{"summary": "manual"})); err != nil {
		t.Fatal(err)
	}
	if err := store.SetManualMatch(ctx, item, "tmdb", "2"); err != nil {
		t.Fatal(err)
	}
	targets, _ := store.MetadataDue(ctx, "tmdb", 3, nil, 20)
	var target catalog.MetadataTarget
	for _, v := range targets {
		if v.ID == item {
			target = v
		}
	}
	target.SidecarReadError = errors.New("synthetische onleesbare NFO")
	d := publicationA()
	d.Summary = ""
	c := catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "2", Pass: 3}
	if err := store.CommitMetadata(ctx, target, c, &d, nil, nil); err != nil {
		t.Fatal(err)
	}
	if err := store.DeleteMetadataOverride(ctx, item, "summary"); !errors.Is(err, catalog.ErrOverrideFallback) {
		t.Fatalf("onzeker unlock: %v", err)
	}
	fields, _ := store.MetadataFields(ctx, item)
	if !fields.Fields["summary"].Locked {
		t.Fatal("onzeker unlock verloor lock")
	}
	if err := store.SetManualMatch(ctx, item, "tmdb", "3"); err != nil {
		t.Fatal(err)
	}
	targets, _ = store.MetadataDue(ctx, "tmdb", 3, nil, 20)
	for _, v := range targets {
		if v.ID == item {
			target = v
		}
	}
	d.Summary = "C"
	c.ExternalID = "3"
	if err := store.CommitMetadata(ctx, target, c, &d, nil, nil); err != nil {
		t.Fatal(err)
	}
	if err := store.DeleteMetadataOverride(ctx, item, "summary"); err != nil {
		t.Fatal(err)
	}
	fields, _ = store.MetadataFields(ctx, item)
	if got := fields.Fields["summary"]; got.Locked || got.Source != "tmdb" || string(got.Value) != `"C"` {
		t.Fatalf("actuele bron: %+v", got)
	}
	// Een oude runner mag ook de verborgen bronwaarden niet terugschrijven.
	if err := store.SetManualMatch(ctx, item, "tmdb", "4"); err != nil {
		t.Fatal(err)
	}
	if err := store.CommitMetadata(ctx, target, c, &d, nil, nil); !errors.Is(err, catalog.ErrMetadataSuperseded) {
		t.Fatalf("stale=%v", err)
	}
	_ = pool
}

func TestMetadataOverrideScannerAndSafeEmptyUnlock(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	item := ids["alien"]
	var lib id.ID
	var grouping string
	if err := pool.QueryRow(ctx, `SELECT library_id,grouping_key FROM media_items WHERE id=$1`, item).Scan(&lib, &grouping); err != nil {
		t.Fatal(err)
	}
	if err := store.SetMetadataOverrides(ctx, item, overrideValues(t, map[string]any{"title": "Manual", "year": nil, "summary": "manual"})); err != nil {
		t.Fatal(err)
	}
	year := 2002
	if got, _, err := store.ResolveItem(ctx, catalog.ItemRef{LibraryID: lib, Kind: "movie", GroupingKey: grouping, Title: "Scanner nieuw", Year: &year}); err != nil || got != item {
		t.Fatalf("resolve: %s %v", got, err)
	}
	fields, _ := store.MetadataFields(ctx, item)
	if string(fields.Fields["title"].Value) != `"Manual"` || string(fields.Fields["year"].Value) != "null" {
		t.Fatal("scanner verloor manual")
	}
	for _, field := range []string{"title", "year"} {
		if err := store.DeleteMetadataOverride(ctx, item, field); err != nil {
			t.Fatal(err)
		}
	}
	fields, _ = store.MetadataFields(ctx, item)
	if string(fields.Fields["title"].Value) != `"Scanner nieuw"` || string(fields.Fields["year"].Value) != "2002" {
		t.Fatalf("scanner unlock: %+v", fields)
	}
	if err := store.SetManualMatch(ctx, item, "tmdb", "2"); err != nil {
		t.Fatal(err)
	}
	targets, _ := store.MetadataDue(ctx, "tmdb", 3, nil, 20)
	for _, target := range targets {
		if target.ID == item {
			d := catalog.MetadataDetails{}
			if err := store.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "2", Pass: 3}, &d, nil, nil); err != nil {
				t.Fatal(err)
			}
		}
	}
	if err := store.DeleteMetadataOverride(ctx, item, "summary"); err != nil {
		t.Fatal(err)
	}
	fields, _ = store.MetadataFields(ctx, item)
	if f := fields.Fields["summary"]; f.Locked || string(f.Value) != "null" || f.Source != "none" {
		t.Fatalf("lege bron=%+v", f)
	}
}

func TestMetadataOverrideUnlockRejectsUncertainNFO(t *testing.T) {
	store, ctx, ids, _ := metadataFixture(t)
	item := ids["alien"]
	if err := store.ApplyMetadata(ctx, item, catalog.SourceNFO, catalog.MetadataDetails{Summary: "NFO A"}); err != nil {
		t.Fatal(err)
	}
	if err := store.SetMetadataOverrides(ctx, item, overrideValues(t, map[string]any{"summary": "manual"})); err != nil {
		t.Fatal(err)
	}
	if err := store.SetManualMatch(ctx, item, "tmdb", "2"); err != nil {
		t.Fatal(err)
	}
	targets, _ := store.MetadataDue(ctx, "tmdb", 3, nil, 20)
	for _, target := range targets {
		if target.ID == item {
			target.SidecarReadError = errors.New("synthetisch onleesbaar")
			d := catalog.MetadataDetails{}
			if err := store.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "2", Pass: 3}, &d, nil, nil); err != nil {
				t.Fatal(err)
			}
		}
	}
	if err := store.DeleteMetadataOverride(ctx, item, "summary"); !errors.Is(err, catalog.ErrOverrideFallback) {
		t.Fatalf("onzekere oude NFO hersteld: %v", err)
	}
	fields, _ := store.MetadataFields(ctx, item)
	if f := fields.Fields["summary"]; !f.Locked || string(f.Value) != `"manual"` {
		t.Fatalf("lock verloren: %+v", f)
	}
}

func TestMetadataOverrideEmptyUnlockAllowsLaterNFO(t *testing.T) {
	store, ctx, ids, _ := metadataFixture(t)
	item := ids["alien"]
	if err := store.SetMetadataOverrides(ctx, item, overrideValues(t, map[string]any{"summary": "manual"})); err != nil {
		t.Fatal(err)
	}
	if err := store.ApplyMetadata(ctx, item, "tmdb", catalog.MetadataDetails{}); err != nil {
		t.Fatal(err)
	}
	if err := store.CommitSidecar(ctx, catalog.MetadataTarget{ID: item}, nil); err != nil {
		t.Fatal(err)
	}
	if err := store.DeleteMetadataOverride(ctx, item, "summary"); err != nil {
		t.Fatal(err)
	}
	if err := store.ApplyMetadata(ctx, item, catalog.SourceNFO, catalog.MetadataDetails{Summary: "verse NFO"}); err != nil {
		t.Fatal(err)
	}
	fields, err := store.MetadataFields(ctx, item)
	if err != nil {
		t.Fatal(err)
	}
	if f := fields.Fields["summary"]; f.Source != "nfo" || string(f.Value) != `"verse NFO"` || f.Locked {
		t.Fatalf("ontgrendeld leeg blokkeerde verse NFO: %+v", f)
	}
}

func TestMetadataOverrideScannerKeepsMonotoneTimestamp(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	item := ids["alien"]
	if err := store.SetMetadataOverrides(ctx, item, overrideValues(t, map[string]any{"title": "manual"})); err != nil {
		t.Fatal(err)
	}
	var lib id.ID
	var grouping string
	if err := pool.QueryRow(ctx, `UPDATE media_items SET updated_at=now()+interval '1 day' WHERE id=$1 RETURNING library_id,grouping_key`, item).Scan(&lib, &grouping); err != nil {
		t.Fatal(err)
	}
	if _, _, err := store.ResolveItem(ctx, catalog.ItemRef{LibraryID: lib, Kind: "movie", GroupingKey: grouping, Title: "scan"}); err != nil {
		t.Fatal(err)
	}
	var monotone bool
	if err := pool.QueryRow(ctx, `SELECT updated_at>now()+interval '23 hours' FROM media_items WHERE id=$1`, item).Scan(&monotone); err != nil || !monotone {
		t.Fatalf("scanner liet timestamp teruglopen: %v %v", monotone, err)
	}
}
