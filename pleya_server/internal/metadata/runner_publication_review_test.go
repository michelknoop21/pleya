package metadata

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

type publicationReviewProvider struct {
	publicationProvider
	failedIDs map[int]bool
}

func (p *publicationReviewProvider) Details(ctx context.Context, kind string, n int) (catalog.MetadataDetails, error) {
	if p.failedIDs[n] {
		p.ids = append(p.ids, n)
		return catalog.MetadataDetails{}, errors.New("synthetische providerfout")
	}
	return p.publicationProvider.Details(ctx, kind, n)
}

func TestPublicationLocalFallbackDoesNotStopHealthyProviderRound(t *testing.T) {
	for _, tc := range []struct {
		name     string
		attempts string // L: lokale blokkade; P: providerfout; G: gezonde titel.
	}{
		{"vijf_lokale_blokkades", "LLLLLG"},
		{"lokale_blokkade_reset_providerreeks", "PPPPLPPPPG"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store, ctx, pool, first, dir, _ := publicationFixture(t)
			var library, location id.ID
			var root string
			if err := pool.QueryRow(ctx, `SELECT library_id,id,root_path FROM storage_locations LIMIT 1`).Scan(&library, &location, &root); err != nil {
				t.Fatal(err)
			}
			items := []id.ID{first}
			p := &publicationReviewProvider{failedIDs: map[int]bool{}}
			wantFailed, wantIDs := 0, []int{}
			for i, action := range tc.attempts {
				item, path := first, "fixture.mkv"
				if i > 0 {
					item, path = id.New(), fmt.Sprintf("fixture-%d.mkv", i)
					version := id.New()
					if _, err := pool.Exec(ctx, `INSERT INTO media_items(id,library_id,kind,grouping_key,title) VALUES($1,$2,'movie',$3,'Fixture')`, item, library, path); err != nil {
						t.Fatal(err)
					}
					if _, err := pool.Exec(ctx, `INSERT INTO media_versions(id,item_id,grouping_key,container,duration_ms) VALUES($1,$2,$3,'mkv',90000)`, version, item, path); err != nil {
						t.Fatal(err)
					}
					if _, err := pool.Exec(ctx, `INSERT INTO media_files(id,storage_location_id,relative_path,role,version_id,size_bytes,mtime_unix) VALUES($1,$2,$3,'media',$4,16,1)`, id.New(), location, path, version); err != nil {
						t.Fatal(err)
					}
					items = append(items, item)
				}
				chosen := i + 1
				wantIDs = append(wantIDs, chosen)
				if err := store.SetManualMatch(ctx, item, ProviderTMDB, fmt.Sprint(chosen)); err != nil {
					t.Fatal(err)
				}
				switch action {
				case 'L':
					wantFailed++
					if err := store.ApplyMetadata(ctx, item, ProviderTMDB, catalog.MetadataDetails{Summary: "A"}); err != nil {
						t.Fatal(err)
					}
					if err := os.WriteFile(filepath.Join(root, path[:len(path)-4]+".nfo"), []byte("<movie><plot>"), 0600); err != nil {
						t.Fatal(err)
					}
				case 'P':
					wantFailed++
					p.failedIDs[chosen] = true
				}
			}
			st, err := testRunner(store, p, dir).WithSidecar(FSSidecar{}).Round(ctx)
			if err != nil || st.Failed != wantFailed || st.Matched != 1 || !reflect.DeepEqual(p.ids, wantIDs) || p.searches != 0 {
				t.Fatalf("lokale blokkade stopte gezonde providerronde: stats=%+v ids=%v zoek=%d err=%v", st, p.ids, p.searches, err)
			}
			for i, item := range items {
				var intact bool
				switch tc.attempts[i] {
				case 'L':
					err = pool.QueryRow(ctx, `SELECT i.summary='A' AND i.metadata_sources->>'summary'='tmdb' AND c.state='failed' AND c.manual AND c.external_id=$2 AND c.next_attempt_at>now() FROM media_items i JOIN metadata_candidates c ON c.item_id=i.id WHERE i.id=$1`, item, fmt.Sprint(i+1)).Scan(&intact)
				case 'P':
					err = pool.QueryRow(ctx, `SELECT state='failed' AND manual AND external_id=$2 AND next_attempt_at>now() FROM metadata_candidates WHERE item_id=$1`, item, fmt.Sprint(i+1)).Scan(&intact)
				case 'G':
					err = pool.QueryRow(ctx, `SELECT state='matched' AND external_id=$2 FROM metadata_candidates WHERE item_id=$1`, item, fmt.Sprint(i+1)).Scan(&intact)
				}
				if err != nil || !intact {
					t.Fatalf("item %d verloor eigen waarde/keuze/retry of publicatie: %v", i, err)
				}
			}
		})
	}
}

func TestPublicationMovieNFOFallbackPreservesIDAndFields(t *testing.T) {
	for _, first := range []string{"<movie><plot>", "<tvshow><title>Andere soort</title></tvshow>"} {
		t.Run(first, func(t *testing.T) {
			store, ctx, pool, item, dir, _ := publicationFixture(t)
			var root string
			if err := pool.QueryRow(ctx, `SELECT root_path FROM storage_locations LIMIT 1`).Scan(&root); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(root, "fixture.nfo"), []byte(first), 0600); err != nil {
				t.Fatal(err)
			}
			fallback := `<movie><tmdbid>2</tmdbid><plot>NFO-plot</plot><genre>NFO-genre</genre><mpaa>NFO-rating</mpaa><actor><name>NFO-acteur</name></actor></movie>`
			if err := os.WriteFile(filepath.Join(root, "movie.nfo"), []byte(fallback), 0600); err != nil {
				t.Fatal(err)
			}
			if err := store.ApplyMetadata(ctx, item, ProviderTMDB, catalog.MetadataDetails{Summary: "A"}); err != nil {
				t.Fatal(err)
			}
			p := &publicationProvider{}
			st, err := testRunner(store, p, dir).WithSidecar(FSSidecar{}).Round(ctx)
			if err != nil || st.Matched != 1 || st.ByID != 1 || p.searches != 0 || !reflect.DeepEqual(p.ids, []int{2}) {
				t.Fatalf("geldige movie.nfo verloor ID-voorrang: stats=%+v ids=%v zoek=%d err=%v", st, p.ids, p.searches, err)
			}
			var intact bool
			if err := pool.QueryRow(ctx, `SELECT summary='NFO-plot' AND genres=ARRAY['NFO-genre'] AND content_rating='NFO-rating' AND people->0->>'name'='NFO-acteur' AND metadata_sources='{"summary":"nfo","genres":"nfo","content_rating":"nfo","people":"nfo"}'::jsonb FROM media_items WHERE id=$1`, item).Scan(&intact); err != nil || !intact {
				t.Fatalf("geldige movie.nfo verloor actuele fallbackvelden: %v", err)
			}
		})
	}
}

func TestCheckedSeriesKeepsNearestInvalidNFOSemantics(t *testing.T) {
	root := t.TempDir()
	season := filepath.Join(root, "Serie", "Season 1")
	if err := os.MkdirAll(season, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(season, "tvshow.nfo"), []byte("<tvshow><plot>"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "Serie", "tvshow.nfo"), []byte("<tvshow><plot>Andere bron</plot></tvshow>"), 0600); err != nil {
		t.Fatal(err)
	}
	side, err := (FSSidecar{}).ReadChecked(catalog.MetadataTarget{Kind: "show", MediaRoot: root, MediaPath: "Serie/Season 1/fixture.mkv"})
	if err == nil || side != nil {
		t.Fatalf("series mogen dichtstbijzijnde onzekere NFO niet overslaan: %+v %v", side, err)
	}
}
