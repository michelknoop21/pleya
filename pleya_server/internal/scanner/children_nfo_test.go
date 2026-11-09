package scanner_test

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/metadata"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

type topLevelOnlyProvider struct {
	t     *testing.T
	calls int
}

func (p *topLevelOnlyProvider) Search(_ context.Context, kind, title string, _ *int) ([]metadata.SearchResult, error) {
	p.calls++
	if kind != "movie" && kind != "show" {
		p.t.Fatalf("lokale kindmetadata naar provider gestuurd: %s", kind)
	}
	return nil, nil
}
func (p *topLevelOnlyProvider) Details(context.Context, string, int) (catalog.MetadataDetails, error) {
	p.t.Fatal("onverwachte provider-id uit kind-NFO")
	return catalog.MetadataDetails{}, nil
}
func (p *topLevelOnlyProvider) Image(context.Context, string, string) ([]byte, string, error) {
	p.t.Fatal("NFO mag geen artwork ophalen")
	return nil, "", io.EOF
}

func TestSeasonAndEpisodeNFOThroughRealScanAndMetadataRound(t *testing.T) {
	for _, withProvider := range []bool{false, true} {
		t.Run(fmt.Sprint("provider=", withProvider), func(t *testing.T) {
			h := newHarness(t, "shows")
			dir := filepath.Join("Eigen serie", "Season 01")
			for n := 1; n <= 2; n++ {
				testsupport.MakeVideo(t, h.path(dir, fmt.Sprintf("Eigen serie - S01E%02d.mkv", n)), 1)
			}
			write := func(relative, body string) {
				t.Helper()
				if err := os.WriteFile(h.path(relative), []byte(body), 0600); err != nil {
					t.Fatal(err)
				}
			}
			seasonPath := filepath.Join(dir, "season.nfo")
			episodePath := filepath.Join(dir, "Eigen serie - S01E01.nfo")
			write(filepath.Join("Eigen serie", "tvshow.nfo"), `<tvshow><plot>Seriebeschrijving</plot><genre>Drama</genre><actor><name>Serieacteur</name></actor></tvshow>`)
			write(seasonPath, `<season><plot>Seizoenbeschrijving</plot><actor><name>Seizoenacteur</name></actor><uniqueid type="tmdb">900001</uniqueid></season>`)
			write(episodePath, `<episodedetails><plot>Afleveringbeschrijving</plot><director>Regisseur</director><actor><name>Gastacteur</name><role>Gast</role></actor><uniqueid type="tmdb">900002</uniqueid><thumb>http://169.254.169.254/secret</thumb></episodedetails>`)
			h.scan()
			ctx := context.Background()
			ids := map[string]id.ID{}
			for key, condition := range map[string]string{"show": "kind='show'", "season": "kind='season'", "episode": "kind='episode' AND item_index=1", "empty": "kind='episode' AND item_index=2"} {
				var item id.ID
				if err := h.pool.QueryRow(ctx, `SELECT id FROM media_items WHERE `+condition).Scan(&item); err != nil {
					t.Fatal(err)
				}
				ids[key] = item
			}
			snapshot := func() string {
				t.Helper()
				var state string
				if err := h.pool.QueryRow(ctx, `SELECT jsonb_agg(jsonb_build_array(id,item_id,grouping_key) ORDER BY id)::text FROM media_versions`).Scan(&state); err != nil {
					t.Fatal(err)
				}
				return state
			}
			original := snapshot()
			var provider metadata.Provider
			checked := &topLevelOnlyProvider{t: t}
			source := catalog.SourceNFO
			if withProvider {
				provider = checked
				source = metadata.ProviderTMDB
			}
			runner := metadata.NewRunner(h.store, provider, source, t.TempDir(), slog.New(slog.NewTextHandler(io.Discard, nil))).WithSidecar(metadata.FSSidecar{})
			round := func() {
				t.Helper()
				if _, err := runner.Round(ctx); err != nil {
					t.Fatal(err)
				}
			}
			round()
			for key, want := range map[string]string{"show": "Seriebeschrijving", "season": "Seizoenbeschrijving", "episode": "Afleveringbeschrijving"} {
				item, err := h.store.Item(ctx, ids[key])
				if err != nil {
					t.Fatal(err)
				}
				if item.Summary == nil || *item.Summary != want || len(item.People) == 0 {
					t.Fatalf("%s mist eigen metadata: %+v", key, item)
				}
				var provenance string
				if err := h.pool.QueryRow(ctx, `SELECT metadata_sources->>'summary' FROM media_items WHERE id=$1`, item.ID).Scan(&provenance); err != nil || provenance != "nfo" {
					t.Fatalf("herkomst %s: %q %v", key, provenance, err)
				}
			}
			empty, err := h.store.Item(ctx, ids["empty"])
			if err != nil || empty.Summary != nil || len(empty.People) != 0 {
				t.Fatalf("ontbrekende aflevering-NFO erfde andere metadata: %+v %v", empty, err)
			}
			var candidates int
			if err := h.pool.QueryRow(ctx, `SELECT count(*) FROM metadata_candidates c JOIN media_items i ON i.id=c.item_id WHERE i.kind IN ('season','episode')`).Scan(&candidates); err != nil || candidates != 0 {
				t.Fatalf("kinderen kregen providermatch: %d %v", candidates, err)
			}
			write(episodePath, `<episodedetails><plot>Bijgewerkt zonder videowijziging</plot><actor><name>Nieuwe gastacteur</name></actor></episodedetails>`)
			if _, err := h.pool.Exec(ctx, `UPDATE media_items SET sidecar_checked_at=now()-interval '8 days' WHERE kind IN ('season','episode')`); err != nil {
				t.Fatal(err)
			}
			h.scan()
			round()
			updated, err := h.store.Item(ctx, ids["episode"])
			if err != nil || updated.Summary == nil || *updated.Summary != "Bijgewerkt zonder videowijziging" || len(updated.People) != 1 || updated.People[0].Name != "Nieuwe gastacteur" {
				t.Fatalf("NFO-update niet gepubliceerd: %+v %v", updated, err)
			}
			if snapshot() != original {
				t.Fatal("NFO veranderde versie- of itemidentiteit")
			}
			if withProvider && checked.calls == 0 {
				t.Fatal("providerpad niet uitgevoerd")
			}
		})
	}
}
