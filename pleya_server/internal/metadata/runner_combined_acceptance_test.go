package metadata

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"reflect"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

func TestManualFieldsAndPosterSurviveThreeProviderRoundsAndScannerUpdate(t *testing.T) {
	store, ctx, pool, item, dir, before := publicationFixture(t)
	publishA(t, store, ctx, item, dir)
	manual := map[string]json.RawMessage{"title": json.RawMessage(`"Fixture"`), "summary": json.RawMessage(`"Handmatig"`)}
	if err := store.SetMetadataOverrides(ctx, item, manual); err != nil {
		t.Fatal(err)
	}
	state, err := store.ArtworkState(ctx, item)
	if err != nil {
		t.Fatal(err)
	}
	ref := "/A.jpg"
	digest := sha256.Sum256([]byte("synthetische bytes"))
	pin := catalog.ArtworkPin{ID: id.New(), ItemID: item, Kind: "poster", Source: ProviderTMDB, Ref: &ref, SHA256: hex.EncodeToString(digest[:]), Extension: ".jpg"}
	if err := store.CommitArtworkPins(ctx, state, map[string]*catalog.ArtworkPin{"poster": &pin}); err != nil {
		t.Fatal(err)
	}
	if err := store.SetManualMatch(ctx, item, ProviderTMDB, "2"); err != nil {
		t.Fatal(err)
	}
	for round := 0; round < 3; round++ {
		if round > 0 {
			if _, err := pool.Exec(ctx, `UPDATE metadata_candidates SET next_attempt_at=now()-interval '1 second' WHERE item_id=$1`, item); err != nil {
				t.Fatal(err)
			}
		}
		fresh := catalog.NewStore(pool)
		provider := &publicationProvider{details: catalog.MetadataDetails{Summary: "Provider B", PosterRef: "/B.jpg", BackdropRef: "/B-bg.jpg"}}
		stats, err := testRunner(fresh, provider, dir).Round(ctx)
		if err != nil || stats.Matched != 1 || !reflect.DeepEqual(provider.ids, []int{2}) || provider.searches != 0 {
			t.Fatalf("ronde%d: %+v %v", round, stats, err)
		}
		status, err := fresh.MetadataMatchStatus(ctx, item)
		if err != nil || status.State != catalog.MetadataApplicationApplied || status.AppliedExternalID == nil || *status.AppliedExternalID != "2" {
			t.Fatalf("ronde%d publicatie-identiteit: %+v %v", round, status, err)
		}
		if status.RequestedExternalID == nil || *status.RequestedExternalID != "2" || status.RequestedProvider == nil || *status.RequestedProvider != ProviderTMDB || status.AppliedProvider == nil || *status.AppliedProvider != ProviderTMDB {
			t.Fatalf("ronde%d gekozen match verloren: %+v", round, status)
		}
		resolved, _, err := fresh.ResolveItem(ctx, catalog.ItemRef{LibraryID: state.LibraryID, Kind: "movie", GroupingKey: "fixture", Title: "Scanner nieuw"})
		if err != nil || resolved != item {
			t.Fatalf("scanner veranderde identiteit: %s %v", resolved, err)
		}
		fields, err := catalog.NewStore(pool).MetadataFields(ctx, item)
		if err != nil {
			t.Fatal(err)
		}
		for name, want := range manual {
			got := fields.Fields[name]
			if !got.Locked || string(got.Value) != string(want) {
				t.Fatalf("ronde%d veld%s: %+v", round, name, got)
			}
		}
		got, library, err := catalog.NewStore(pool).ArtworkPin(ctx, pin.ID)
		if err != nil || library != state.LibraryID || !reflect.DeepEqual(got, pin) {
			t.Fatalf("ronde%d pin gewijzigd: %+v %v", round, got, err)
		}
		visible, err := catalog.NewStore(pool).Item(ctx, item)
		if err != nil || visible.PosterID == nil || *visible.PosterID != pin.ID || visible.Title != "Fixture" || visible.Summary == nil || *visible.Summary != "Handmatig" {
			t.Fatalf("ronde%d catalogus verliest handmatige presentatie: %+v %v", round, visible, err)
		}
		if after := metadataReferenceSnapshot(t, ctx, pool, item); after != before {
			t.Fatalf("ronde%d wijzigde identiteit of persoonlijke verwijzingen", round)
		}
	}
}
