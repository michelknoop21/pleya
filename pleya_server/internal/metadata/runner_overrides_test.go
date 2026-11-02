package metadata

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/nfo"
)

func TestMetadataOverridesRealRunnerFailureThreeRoundsAndReferences(t *testing.T) {
	store, ctx, pool, item, dir, before := publicationFixture(t)
	publishA(t, store, ctx, item, dir)
	manual := map[string]json.RawMessage{"summary": json.RawMessage(`""`), "genres": json.RawMessage(`[]`), "content_rating": json.RawMessage(`""`), "people": json.RawMessage(`[]`)}
	if err := store.SetMetadataOverrides(ctx, item, manual); err != nil {
		t.Fatal(err)
	}
	for round := 0; round < 3; round++ {
		fresh := catalog.NewStore(pool)
		if err := fresh.SetManualMatch(ctx, item, "tmdb", "2"); err != nil {
			t.Fatal(err)
		}
		provider := &publicationProvider{details: catalog.MetadataDetails{Summary: "B", Genres: []string{"B"}}}
		if round == 1 {
			provider.detailsErr = errors.New("synthetische providerfout")
		}
		stats, err := testRunner(fresh, provider, dir).WithSidecar(fakeSidecar{item: &nfo.Result{Summary: "NFO"}}).Round(ctx)
		if err != nil || (round == 1 && stats.Failed != 1) || (round != 1 && stats.Matched != 1) {
			t.Fatalf("ronde%d: %+v %v", round, stats, err)
		}
		fields, err := catalog.NewStore(pool).MetadataFields(ctx, item)
		if err != nil {
			t.Fatal(err)
		}
		for field, want := range manual {
			got := fields.Fields[field]
			if !got.Locked || string(got.Value) != string(want) {
				t.Fatalf("ronde%d %s=%+v", round, field, got)
			}
		}
		if got := metadataReferenceSnapshot(t, ctx, pool, item); got != before {
			t.Fatal("override/runner wijzigde identiteit/file/version/watch/history/list/download")
		}
	}
	if err := store.DeleteMetadataOverride(ctx, item, "summary"); err != nil {
		t.Fatal(err)
	}
	fields, _ := store.MetadataFields(ctx, item)
	if got := fields.Fields["summary"]; got.Source != "tmdb" || string(got.Value) != `"B"` || got.Locked {
		t.Fatalf("runner unlock: %+v", got)
	}
}

func TestMetadataOverridesKeylessMissingNFOInvalidatesHiddenFallback(t *testing.T) {
	store, ctx, pool, item, dir, _ := publicationFixture(t)
	runner := testRunner(store, nil, dir).WithSidecar(fakeSidecar{item: &nfo.Result{Summary: "NFO A"}})
	if _, err := runner.Round(ctx); err != nil {
		t.Fatal(err)
	}
	if err := store.SetMetadataOverrides(ctx, item, map[string]json.RawMessage{"summary": json.RawMessage(`"manual"`)}); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `UPDATE media_items SET sidecar_checked_at=now()-interval '8 days' WHERE id=$1`, item); err != nil {
		t.Fatal(err)
	}
	// Een nieuwe runner zonder NFO moet het opgeslagen oude NFO-bewijs intrekken.
	if _, err := testRunner(catalog.NewStore(pool), nil, dir).WithSidecar(fakeSidecar{}).Round(ctx); err != nil {
		t.Fatal(err)
	}
	if err := store.DeleteMetadataOverride(ctx, item, "summary"); !errors.Is(err, catalog.ErrOverrideFallback) {
		t.Fatalf("oude NFO hersteld: %v", err)
	}
	fields, _ := store.MetadataFields(ctx, item)
	if got := fields.Fields["summary"]; !got.Locked || string(got.Value) != `"manual"` {
		t.Fatalf("onzekere unlock verloor manual: %+v", got)
	}
	var count int
	if err := pool.QueryRow(context.Background(), `SELECT count(*) FROM metadata_candidates WHERE item_id=$1`, item).Scan(&count); err != nil || count != 0 {
		t.Fatalf("keyless schreef kandidaat %d %v", count, err)
	}
}

func TestMetadataOverridesLateEditKeepsCurrentMissingNFOEvidence(t *testing.T) {
	for _, missing := range []string{"bestand", "velden"} {
		t.Run(missing, func(t *testing.T) {
			store, ctx, pool, item, dir, _ := publicationFixture(t)
			targets, err := store.MetadataDue(ctx, catalog.SourceNFO, 3, nil, 10)
			if err != nil || len(targets) != 1 || targets[0].MediaRoot == "" {
				t.Fatalf("keyless doel ontbreekt: %+v %v", targets, err)
			}
			path := filepath.Join(targets[0].MediaRoot, "fixture.nfo")
			if err := os.WriteFile(path, []byte(`<movie><plot>NFO A</plot><genre>A</genre><mpaa>A</mpaa><actor><name>A</name></actor></movie>`), 0600); err != nil {
				t.Fatal(err)
			}
			if stats, err := testRunner(store, nil, dir).WithSidecar(FSSidecar{}).Round(ctx); err != nil || stats.SidecarApplied != 1 {
				t.Fatalf("eerste NFO: %+v %v", stats, err)
			}
			if missing == "bestand" {
				if err := os.Remove(path); err != nil {
					t.Fatal(err)
				}
			} else {
				if err := os.WriteFile(path, []byte(`<movie></movie>`), 0600); err != nil {
					t.Fatal(err)
				}
			}
			if _, err := pool.Exec(ctx, `UPDATE media_items SET sidecar_checked_at=now()-interval '8 days' WHERE id=$1`, item); err != nil {
				t.Fatal(err)
			}
			if _, err := testRunner(catalog.NewStore(pool), nil, dir).WithSidecar(FSSidecar{}).Round(ctx); err != nil {
				t.Fatal(err)
			}
			manual := map[string]json.RawMessage{"summary": json.RawMessage(`"manual M"`), "genres": json.RawMessage(`[]`), "content_rating": json.RawMessage(`"M"`), "people": json.RawMessage(`[]`)}
			fresh := catalog.NewStore(pool)
			if err := fresh.SetMetadataOverrides(ctx, item, manual); err != nil {
				t.Fatal(err)
			}
			for field, want := range manual {
				var underlying string
				if err := pool.QueryRow(ctx, `SELECT (metadata_field_layers->'nfo'->$2)::text FROM media_items WHERE id=$1`, item, field).Scan(&underlying); err != nil || underlying != "null" {
					t.Fatalf("manual herschreef actuele NFO-afwezigheid voor %s: %s %v", field, underlying, err)
				}
				fresh = catalog.NewStore(pool)
				if err := fresh.DeleteMetadataOverride(ctx, item, field); !errors.Is(err, catalog.ErrOverrideFallback) {
					t.Fatalf("oude NFO A hersteld voor %s: %v", field, err)
				}
				fields, err := catalog.NewStore(pool).MetadataFields(ctx, item)
				if err != nil {
					t.Fatal(err)
				}
				if got := fields.Fields[field]; !got.Locked || string(got.Value) != string(want) {
					t.Fatalf("manual verloren voor %s: %+v", field, got)
				}
			}
		})
	}
}
