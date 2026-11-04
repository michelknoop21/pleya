package catalog_test

import (
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"testing"
	"time"
)

func TestPresentationPublishesWithIdentityAndClearsOnReplacement(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	item := ids["alien"]
	due, err := store.MetadataDue(ctx, "tmdb", 4, nil, 10)
	if err != nil {
		t.Fatal(err)
	}
	var target catalog.MetadataTarget
	for _, d := range due {
		if d.ID == item {
			target = d
		}
	}
	logo, portrait := id.New(), id.New()
	details := catalog.MetadataDetails{People: []catalog.Person{{Name: "Real actor", Role: "actor", Character: "Character"}}, Presentation: &catalog.DetailPresentation{
		LogoRef: "/logo.png", LogoID: &logo, Ratings: []catalog.ExternalRating{{Source: "tmdb", Value: 8.2, MaxValue: 10, VoteCount: 100}},
		Portraits: []catalog.CreditPortrait{{Name: "Real actor", Role: "actor", Character: "Character", Ref: "/actor.jpg", ID: &portrait}},
	}}
	assets := []catalog.ProviderArtwork{
		{ID: logo, ItemID: item, Kind: catalog.LogoKind("/logo.png"), Provider: "tmdb", SourceRef: "/logo.png", FileName: "logo.png", SHA256: "logo"},
		{ID: portrait, ItemID: item, Kind: catalog.PortraitKind("/actor.jpg"), Provider: "tmdb", SourceRef: "/actor.jpg", FileName: "actor.jpg", SHA256: "actor"},
	}
	candidate := catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "42", Pass: 4}
	if err := store.CommitMetadata(ctx, target, candidate, &details, nil, assets); err != nil {
		t.Fatal(err)
	}
	got, err := store.Item(ctx, item)
	if err != nil {
		t.Fatal(err)
	}
	if got.LogoID == nil || len(got.People) != 1 || got.People[0].PortraitID == nil || len(got.ExternalRatings) != 1 || got.AppliedExternalIDs.TMDB == nil || *got.AppliedExternalIDs.TMDB != 42 {
		t.Fatalf("publication not coherent: %+v", got)
	}
	var before time.Time
	if err := pool.QueryRow(ctx, `SELECT updated_at FROM media_items WHERE id=$1`, item).Scan(&before); err != nil {
		t.Fatal(err)
	}
	// The applied identity is reused by a new enrichment pass, never title search.
	due, err = store.MetadataDue(ctx, "tmdb", 5, nil, 10)
	if err != nil {
		t.Fatal(err)
	}
	for _, d := range due {
		if d.ID == item {
			target = d
		}
	}
	if target.RefreshExternalID != "42" {
		t.Fatalf("refresh lost applied identity: %+v", target)
	}
	details.Presentation.Ratings[0].Value = 8.3
	if err := store.CommitMetadata(ctx, target, candidate, &details, nil, nil); err != nil {
		t.Fatal(err)
	}
	var after time.Time
	if err := pool.QueryRow(ctx, `SELECT updated_at FROM media_items WHERE id=$1`, item).Scan(&after); err != nil || !after.After(before) {
		t.Fatal("presentation-only update did not invalidate item freshness", err)
	}
	if err := store.SetMetadataOverrides(ctx, item, overrideValues(t, map[string]any{"people": []catalog.Person{{Name: "Real actor", Role: "actor", Character: "Character"}}})); err != nil {
		t.Fatal(err)
	}
	got, err = store.Item(ctx, item)
	if err != nil || got.People[0].PortraitID != nil || got.LogoID == nil {
		t.Fatal("manual credit inherited provider photo", err)
	}
	// A failed new download may not keep assets from the previous identity.
	if err := store.SetManualMatch(ctx, item, "tmdb", "43"); err != nil {
		t.Fatal(err)
	}
	due, err = store.MetadataDue(ctx, "tmdb", 4, nil, 10)
	if err != nil {
		t.Fatal(err)
	}
	for _, d := range due {
		if d.ID == item {
			target = d
		}
	}
	replacement := catalog.MetadataDetails{People: []catalog.Person{{Name: "New actor", Role: "actor"}}, Presentation: &catalog.DetailPresentation{LogoRef: "/new.png"}}
	candidate.ExternalID = "43"
	if err := store.CommitMetadata(ctx, target, candidate, &replacement, nil, nil); err != nil {
		t.Fatal(err)
	}
	got, err = store.Item(ctx, item)
	if err != nil || got.LogoID != nil || len(got.ExternalRatings) != 0 {
		t.Fatal("replacement exposed prior presentation", err)
	}
	if _, found, err := store.GetProviderArtwork(ctx, item, catalog.LogoKind("/logo.png"), "tmdb"); err != nil || found {
		t.Fatal("old logo asset retained after replacement", err)
	}
}
