package catalog_test

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func TestArtworkPinsConcurrenteKeuzeEnAtomischeRollen(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatal(err)
	}
	store := catalog.NewStore(pool)
	libs, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{{Slug: "pins", Title: "Pins", Kind: "movies"}})
	if err != nil {
		t.Fatal(err)
	}
	item := id.New()
	if _, err := pool.Exec(ctx, `INSERT INTO media_items(id,library_id,kind,grouping_key,title) VALUES($1,$2,'movie','pins','Pins')`, item, libs[0].ID); err != nil {
		t.Fatal(err)
	}
	state, err := store.ArtworkState(ctx, item)
	if err != nil {
		t.Fatal(err)
	}
	ref := "/chosen.png"
	pin := func(kind string) *catalog.ArtworkPin {
		return &catalog.ArtworkPin{ID: id.New(), ItemID: item, Kind: kind, Source: "tmdb", Ref: &ref, SHA256: strings.Repeat("a", 64), Extension: ".png"}
	}
	results := make(chan error, 2)
	start := make(chan struct{})
	var wg sync.WaitGroup
	for n := 0; n < 2; n++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			results <- store.CommitArtworkPins(ctx, state, map[string]*catalog.ArtworkPin{"poster": pin("poster")})
		}()
	}
	close(start)
	wg.Wait()
	close(results)
	success, stale := 0, 0
	for err := range results {
		if err == nil {
			success++
		} else if errors.Is(err, catalog.ErrArtworkStale) {
			stale++
		} else {
			t.Fatal(err)
		}
	}
	if success != 1 || stale != 1 {
		t.Fatalf("concurrente publicatie success%d stale%d", success, stale)
	}
	fresh, err := store.ArtworkState(ctx, item)
	if err != nil || len(fresh.Pins) != 1 {
		t.Fatalf("keuze %+v %v", fresh, err)
	}
	original := fresh.Pins[0].ID
	bad := pin("poster")
	bad.Extension = ".svg"
	good := pin("backdrop")
	if err := store.CommitArtworkPins(ctx, fresh, map[string]*catalog.ArtworkPin{"poster": bad, "backdrop": good}); err == nil {
		t.Fatal("ongeldige bron geaccepteerd")
	}
	after, err := store.ArtworkState(ctx, item)
	if err != nil || after.Token != fresh.Token || len(after.Pins) != 1 || after.Pins[0].ID != original {
		t.Fatal("halve rolpublicatie na bronfout")
	}
	// Een nieuwe matchrequest maakt ook een null-ontpinning met oude guard ongeldig.
	if err := store.SetManualMatch(ctx, item, "tmdb", "3"); err != nil {
		t.Fatal(err)
	}
	if err := store.CommitArtworkPins(ctx, fresh, map[string]*catalog.ArtworkPin{"poster": nil}); !errors.Is(err, catalog.ErrArtworkStale) {
		t.Fatalf("stale unpin %v", err)
	}
	if _, _, err := catalog.NewStore(pool).ArtworkPin(ctx, original); err != nil {
		t.Fatal("stale unpin wiste pin")
	}
}
