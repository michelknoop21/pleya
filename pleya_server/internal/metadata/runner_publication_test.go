package metadata

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

type publicationProvider struct {
	details              catalog.MetadataDetails
	detailsErr, imageErr error
	ids                  []int
	searches             int
}

func (p *publicationProvider) Search(context.Context, string, string, *int) ([]SearchResult, error) {
	p.searches++
	return []SearchResult{{ID: 99, Title: "Fixture"}}, nil
}
func (p *publicationProvider) Details(_ context.Context, _ string, n int) (catalog.MetadataDetails, error) {
	p.ids = append(p.ids, n)
	return p.details, p.detailsErr
}
func (p *publicationProvider) Image(context.Context, string, string) ([]byte, string, error) {
	return []byte("synthetische bytes"), ".jpg", p.imageErr
}

func publicationFixture(t *testing.T) (*catalog.Store, context.Context, *pgxpool.Pool, id.ID, string, string) {
	t.Helper()
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatal(err)
	}
	store := catalog.NewStore(pool)
	libs, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{{Slug: "fixture", Title: "Fixture", Kind: "movies"}})
	if err != nil {
		t.Fatal(err)
	}
	item := id.New()
	if _, err := pool.Exec(ctx, `INSERT INTO media_items(id,library_id,kind,grouping_key,title) VALUES($1,$2,'movie','fixture','Fixture')`, item, libs[0].ID); err != nil {
		t.Fatal(err)
	}
	before := seedMetadataReferences(t, ctx, pool, item, libs[0].ID)
	dir := t.TempDir()
	return store, ctx, pool, item, dir, before
}

func publishA(t *testing.T, store *catalog.Store, ctx context.Context, item id.ID, dir string) {
	t.Helper()
	if err := store.SetManualMatch(ctx, item, ProviderTMDB, "1"); err != nil {
		t.Fatal(err)
	}
	p := &publicationProvider{details: catalog.MetadataDetails{Summary: "A", Genres: []string{"A"}, ContentRating: "A", People: []catalog.Person{{Name: "A", Role: "actor"}}, PosterRef: "/A.jpg", BackdropRef: "/A-bg.jpg"}}
	st, err := testRunner(store, p, dir).Round(ctx)
	if err != nil || st.Matched != 1 || st.ArtworkSaved != 2 {
		t.Fatalf("A niet gepubliceerd: %+v %v", st, err)
	}
}

func TestPublicationEmptyReplacementSurvivesThreeRoundsAndRestart(t *testing.T) {
	store, ctx, pool, item, dir, before := publicationFixture(t)
	publishA(t, store, ctx, item, dir)
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
		p := &publicationProvider{}
		st, err := testRunner(fresh, p, dir).Round(ctx)
		if err != nil || st.Matched != 1 || !reflect.DeepEqual(p.ids, []int{2}) || p.searches != 0 {
			t.Fatalf("ronde %d: %+v %+v %v", round, st, p, err)
		}
		var empty bool
		if err := pool.QueryRow(ctx, `SELECT summary IS NULL AND genres IS NULL AND content_rating IS NULL AND people IS NULL AND metadata_sources='{}'::jsonb FROM media_items WHERE id=$1`, item).Scan(&empty); err != nil {
			t.Fatal(err)
		}
		if !empty {
			t.Fatal("lege B laat providerwaarden van A staan")
		}
		for _, kind := range []string{"poster", "backdrop"} {
			if a, found, err := fresh.GetProviderArtwork(ctx, item, kind, ProviderTMDB); err != nil || found {
				t.Fatalf("A-artwork bleef na B staan: %+v %v", a, err)
			}
		}
	}
	if after := metadataReferenceSnapshot(t, ctx, pool, item); after != before {
		t.Fatal("identiteit/persoonlijke data gewijzigd")
	}
}

func TestPublicationFailureKeepsManualIDAndRetriesExactChoice(t *testing.T) {
	store, ctx, pool, item, dir, before := publicationFixture(t)
	publishA(t, store, ctx, item, dir)
	old, _, err := store.GetProviderArtwork(ctx, item, "poster", ProviderTMDB)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.SetManualMatch(ctx, item, ProviderTMDB, "2"); err != nil {
		t.Fatal(err)
	}
	p := &publicationProvider{detailsErr: errors.New("synthetische Details-fout")}
	st, err := testRunner(store, p, dir).Round(ctx)
	if err != nil || st.Failed != 1 {
		t.Fatalf("foutpad: %+v %v", st, err)
	}
	var ext, state, summary string
	var manual bool
	if err := pool.QueryRow(ctx, `SELECT coalesce(c.external_id,''),c.state,c.manual,i.summary FROM metadata_candidates c JOIN media_items i ON i.id=c.item_id WHERE i.id=$1`, item).Scan(&ext, &state, &manual, &summary); err != nil {
		t.Fatal(err)
	}
	if ext != "2" || state != catalog.CandidateFailed || !manual || summary != "A" {
		t.Fatalf("fout verloor keuze of oude metadata: %s %s %v %s", ext, state, manual, summary)
	}
	var intact bool
	if err := pool.QueryRow(ctx, `SELECT genres=ARRAY['A'] AND content_rating='A' AND people->0->>'name'='A' AND metadata_sources='{"summary":"tmdb","genres":"tmdb","content_rating":"tmdb","people":"tmdb"}'::jsonb FROM media_items WHERE id=$1`, item).Scan(&intact); err != nil || !intact {
		t.Fatalf("Details-fout veranderde velden/bronnen: %v", err)
	}
	a, found, err := store.GetProviderArtwork(ctx, item, "poster", ProviderTMDB)
	if err != nil || !found || a != old {
		t.Fatalf("fout veranderde bruikbaar artwork: %+v %v", a, err)
	}
	if _, err := os.Stat(filepath.Join(dir, "artwork", old.FileName)); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `UPDATE metadata_candidates SET next_attempt_at=now()-interval '1 second' WHERE item_id=$1`, item); err != nil {
		t.Fatal(err)
	}
	p = &publicationProvider{details: catalog.MetadataDetails{Summary: "B"}}
	st, err = testRunner(catalog.NewStore(pool), p, dir).Round(ctx)
	if err != nil || st.Matched != 1 || !reflect.DeepEqual(p.ids, []int{2}) || p.searches != 0 {
		t.Fatalf("retry verlaat exacte keuze: %+v %+v %v", st, p, err)
	}
	if after := metadataReferenceSnapshot(t, ctx, pool, item); after != before {
		t.Fatal("identiteit/persoonlijke data gewijzigd")
	}
}

func TestPublicationFailedArtworkRemovesOnlyDifferentBinding(t *testing.T) {
	store, ctx, pool, item, dir, _ := publicationFixture(t)
	publishA(t, store, ctx, item, dir)
	old, _, err := store.GetProviderArtwork(ctx, item, "poster", ProviderTMDB)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.SetManualMatch(ctx, item, ProviderTMDB, "2"); err != nil {
		t.Fatal(err)
	}
	p := &publicationProvider{details: catalog.MetadataDetails{Summary: "B", PosterRef: "/B.jpg", BackdropRef: "/A-bg.jpg"}, imageErr: errors.New("synthetische downloadfout")}
	st, err := testRunner(store, p, dir).Round(ctx)
	if err != nil || st.Matched != 1 {
		t.Fatalf("tekstpublicatie: %+v %v", st, err)
	}
	if a, found, err := store.GetProviderArtwork(ctx, item, "poster", ProviderTMDB); err != nil || found {
		t.Fatalf("oude A-poster bleef bij mislukte B: %+v %v", a, err)
	}
	if a, found, err := store.GetProviderArtwork(ctx, item, "backdrop", ProviderTMDB); err != nil || !found || a.SourceRef != "/A-bg.jpg" {
		t.Fatalf("dezelfde gewenste binding verloren: %+v %v", a, err)
	}
	var retry bool
	if err := pool.QueryRow(ctx, `SELECT next_attempt_at>now() FROM metadata_candidates WHERE item_id=$1`, item).Scan(&retry); err != nil || !retry {
		t.Fatalf("geen bestaande retry: %v", err)
	}
	// Bindings verwijderen is geen toestemming om bytes vóór bewezen commit weg te halen.
	if _, err := os.Stat(filepath.Join(dir, "artwork", old.FileName)); err != nil {
		t.Fatal(err)
	}
}

func TestPublicationUsesCurrentNFOAndRefusesUnreadableFallback(t *testing.T) {
	for _, broken := range []bool{false, true} {
		t.Run(map[bool]string{false: "actuele_nfo", true: "onleesbaar"}[broken], func(t *testing.T) {
			store, ctx, pool, item, dir, _ := publicationFixture(t)
			publishA(t, store, ctx, item, dir)
			var root string
			if err := pool.QueryRow(ctx, `SELECT root_path FROM storage_locations LIMIT 1`).Scan(&root); err != nil {
				t.Fatal(err)
			}
			data := `<movie><plot>actuele NFO</plot></movie>`
			if broken {
				data = `<movie><plot>`
			}
			if err := os.WriteFile(filepath.Join(root, "fixture.nfo"), []byte(data), 0600); err != nil {
				t.Fatal(err)
			}
			if err := store.SetManualMatch(ctx, item, ProviderTMDB, "2"); err != nil {
				t.Fatal(err)
			}
			st, err := testRunner(store, &publicationProvider{}, dir).WithSidecar(FSSidecar{}).Round(ctx)
			if err != nil {
				t.Fatal(err)
			}
			var summary string
			if err := pool.QueryRow(ctx, `SELECT coalesce(summary,'') FROM media_items WHERE id=$1`, item).Scan(&summary); err != nil {
				t.Fatal(err)
			}
			if broken {
				if st.Failed != 1 || summary != "A" {
					t.Fatalf("onzekere fallback destructief gepubliceerd: %+v %s", st, summary)
				}
			} else if st.Matched != 1 || summary != "actuele NFO" {
				t.Fatalf("actuele fallback ontbreekt: %+v %s", st, summary)
			}
		})
	}
}

func TestPublicationKeepsLocalArtworkAndDropsOldProviderBinding(t *testing.T) {
	store, ctx, pool, item, dir, _ := publicationFixture(t)
	publishA(t, store, ctx, item, dir)
	var location id.ID
	if err := pool.QueryRow(ctx, `SELECT id FROM storage_locations LIMIT 1`).Scan(&location); err != nil {
		t.Fatal(err)
	}
	poster := id.New()
	if _, err := pool.Exec(ctx, `INSERT INTO media_files(id,storage_location_id,relative_path,role,item_id,artwork_kind,size_bytes,mtime_unix) VALUES($1,$2,'poster.jpg','artwork',$3,'poster',16,1)`, poster, location, item); err != nil {
		t.Fatal(err)
	}
	before := metadataReferenceSnapshot(t, ctx, pool, item)
	if err := store.SetManualMatch(ctx, item, ProviderTMDB, "2"); err != nil {
		t.Fatal(err)
	}
	st, err := testRunner(store, &publicationProvider{details: catalog.MetadataDetails{PosterRef: "/B.jpg"}}, dir).Round(ctx)
	if err != nil || st.Matched != 1 || st.ArtworkSaved != 0 {
		t.Fatalf("lokale poster gaf providerdownload: %+v %v", st, err)
	}
	it, err := store.Item(ctx, item)
	if err != nil || it.PosterID == nil || *it.PosterID != poster {
		t.Fatalf("lokale poster verloren: %+v %v", it, err)
	}
	if _, found, err := store.GetProviderArtwork(ctx, item, "poster", ProviderTMDB); err != nil || found {
		t.Fatalf("oude providerbinding onder lokale poster: gevonden=%v %v", found, err)
	}
	if after := metadataReferenceSnapshot(t, ctx, pool, item); after != before {
		t.Fatal("lokale artworkrij/identiteit gewijzigd")
	}
}

func TestPublicationUnreadableNFODoesNotBlockCompleteProviderDetails(t *testing.T) {
	store, ctx, pool, item, dir, _ := publicationFixture(t)
	var root string
	if err := pool.QueryRow(ctx, `SELECT root_path FROM storage_locations LIMIT 1`).Scan(&root); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "fixture.nfo"), []byte("<movie><plot>"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := store.SetManualMatch(ctx, item, ProviderTMDB, "2"); err != nil {
		t.Fatal(err)
	}
	p := &publicationProvider{details: catalog.MetadataDetails{Summary: "B", Genres: []string{"B"}, ContentRating: "B", People: []catalog.Person{{Name: "B", Role: "actor"}}}}
	st, err := testRunner(store, p, dir).WithSidecar(FSSidecar{}).Round(ctx)
	if err != nil || st.Matched != 1 || st.Failed != 0 {
		t.Fatalf("complete provider heeft geen fallback nodig: %+v %v", st, err)
	}
}

func TestPublicationUnreadableNFOOnlyBlocksDestructiveReplacement(t *testing.T) {
	for _, source := range []string{"vers", "manual", "nfo", "onbekend", "eigen_zonder_waarde"} {
		t.Run(source, func(t *testing.T) {
			store, ctx, pool, item, dir, _ := publicationFixture(t)
			if source != "vers" {
				publishA(t, store, ctx, item, dir)
				if source == "eigen_zonder_waarde" {
					if _, err := pool.Exec(ctx, `UPDATE media_items SET people=NULL WHERE id=$1`, item); err != nil {
						t.Fatal(err)
					}
				} else if _, err := pool.Exec(ctx, `UPDATE media_items SET metadata_sources=jsonb_set(metadata_sources,'{people}',to_jsonb($2::text)) WHERE id=$1`, item, source); err != nil {
					t.Fatal(err)
				}
			}
			var root string
			if err := pool.QueryRow(ctx, `SELECT root_path FROM storage_locations LIMIT 1`).Scan(&root); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(root, "fixture.nfo"), []byte("<movie><plot>"), 0600); err != nil {
				t.Fatal(err)
			}
			if err := store.SetManualMatch(ctx, item, ProviderTMDB, "2"); err != nil {
				t.Fatal(err)
			}
			// TMDB levert normaal geen credits; alleen oude eigen people met een
			// echte waarde zou hier destructief worden ingetrokken.
			p := &publicationProvider{details: catalog.MetadataDetails{Summary: "B", Genres: []string{"B"}, ContentRating: "B"}}
			st, err := testRunner(store, p, dir).WithSidecar(FSSidecar{}).Round(ctx)
			if err != nil || st.Matched != 1 || st.Failed != 0 {
				t.Fatalf("geen destructieve vervanging, toch geblokkeerd: %+v %v", st, err)
			}
			var preserved bool
			if source == "vers" || source == "eigen_zonder_waarde" {
				err = pool.QueryRow(ctx, `SELECT people IS NULL FROM media_items WHERE id=$1`, item).Scan(&preserved)
			} else {
				err = pool.QueryRow(ctx, `SELECT people->0->>'name'='A' AND metadata_sources->>'people'=$2 FROM media_items WHERE id=$1`, item, source).Scan(&preserved)
			}
			if err != nil || !preserved {
				t.Fatalf("beschermde/lege people veranderd: %v", err)
			}
		})
	}
}
