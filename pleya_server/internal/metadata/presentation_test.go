package metadata

import (
	"errors"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"testing"
)

func TestPresentationRunnerPublishesAssetsRefreshesAppliedIdentityAndDropsOldAssets(t *testing.T) {
	store, ctx, pool, item, dir, _ := publicationFixture(t)
	if err := store.SetManualMatch(ctx, item, "tmdb", "1"); err != nil {
		t.Fatal(err)
	}
	p := &publicationProvider{details: catalog.MetadataDetails{People: []catalog.Person{{Name: "Actual", Role: "actor"}}, Presentation: &catalog.DetailPresentation{LogoRef: "/A.png", Portraits: []catalog.CreditPortrait{{Name: "Actual", Role: "actor", Ref: "/actor.jpg"}}, Ratings: []catalog.ExternalRating{{Source: "tmdb", Value: 8.2, MaxValue: 10, VoteCount: 100}}}}}
	stats, err := testRunner(store, p, dir).Round(ctx)
	if err != nil || stats.ArtworkSaved != 2 {
		t.Fatal("presentation images not prepared", stats, err)
	}
	got, err := store.Item(ctx, item)
	if err != nil || got.LogoID == nil || got.People[0].PortraitID == nil || len(got.ExternalRatings) != 1 {
		t.Fatal("prepared assets not published coherently", got, err)
	}
	// A normal enrichment pass must reuse applied identity1, not Search's99.
	if _, err := pool.Exec(ctx, `UPDATE metadata_candidates SET manual=false,pass=3 WHERE item_id=$1`, item); err != nil {
		t.Fatal(err)
	}
	if _, err := testRunner(store, p, dir).Round(ctx); err != nil {
		t.Fatal(err)
	}
	if p.searches != 0 || len(p.ids) != 2 || p.ids[1] != 1 {
		t.Fatal("enrichment rematched the title", p.searches, p.ids)
	}
	if err := store.SetManualMatch(ctx, item, "tmdb", "2"); err != nil {
		t.Fatal(err)
	}
	p.details = catalog.MetadataDetails{People: []catalog.Person{{Name: "New actor", Role: "actor"}}, Presentation: &catalog.DetailPresentation{LogoRef: "/B.png", Portraits: []catalog.CreditPortrait{{Name: "New actor", Role: "actor", Ref: "/new-actor.jpg"}}}}
	p.imageErr = errors.New("synthetic image download failure")
	if _, err := testRunner(store, p, dir).Round(ctx); err != nil {
		t.Fatal(err)
	}
	got, err = store.Item(ctx, item)
	if err != nil || got.LogoID != nil || len(got.ExternalRatings) != 0 || got.People[0].PortraitID != nil || got.People[0].Name != "New actor" {
		t.Fatal("failed replacement retained old title images or scores", got, err)
	}
	var retry bool
	if err := pool.QueryRow(ctx, `SELECT next_attempt_at IS NOT NULL FROM metadata_candidates WHERE item_id=$1`, item).Scan(&retry); err != nil || !retry {
		t.Fatal("failed enrichment is not retryable", err)
	}
}
