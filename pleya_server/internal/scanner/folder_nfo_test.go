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
	"github.com/edde746/plezy/pleya_server/internal/metadata"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// silentProvider kent geen enkele titel, zoals TMDB voor een map met clips.
type silentProvider struct{}

func (silentProvider) Search(context.Context, string, string, *int) ([]metadata.SearchResult, error) {
	return nil, nil
}
func (silentProvider) Details(context.Context, string, int) (catalog.MetadataDetails, error) {
	return catalog.MetadataDetails{}, nil
}
func (silentProvider) Image(context.Context, string, string) ([]byte, string, error) {
	return nil, "", io.EOF
}

const folderNFO = `<?xml version="1.0" encoding="UTF-8"?>
<movie>
  <title>Clipmap</title>
  <plot>Een map met losse filmpjes.</plot>
  <genre>Animatie</genre>
  <genre>Familie</genre>
</movie>
`

// TestMovieNFOInAFolderOfClipsLandsOnTheOneItem is het bewijs achter de Kids-
// bibliotheek van productie: een map met veel losse bestanden is voor de server
// één film met veel versies, en één movie.nfo in die map levert er genres aan,
// ook als de provider de titel niet kent. Met genres bij vier van de vijf titels
// gaat de dekkingspoort open (80 procent) en worden ze zichtbaar.
func TestMovieNFOInAFolderOfClipsLandsOnTheOneItem(t *testing.T) {
	h := newHarness(t, "movies")

	// Vier mappen met een movie.nfo, waarvan de eerste zes verschillend
	// genoemde clips heeft, en één map zonder.
	for i, name := range []string{"Clipmap", "Tweede", "Derde", "Vierde", "Zonder nfo"} {
		clips := 2
		if i == 0 {
			clips = 6
		}
		for c := 0; c < clips; c++ {
			testsupport.MakeVideo(t, h.path(name, fmt.Sprintf("Clip %d - los filmpje.mkv", c+1)), 1)
		}
		if name != "Zonder nfo" {
			if err := os.WriteFile(filepath.Join(h.root, name, "movie.nfo"), []byte(folderNFO), 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}

	h.scan()

	items := h.items()
	if len(items) != 5 {
		t.Fatalf("vijf mappen leverden %d items op, verwacht 5", len(items))
	}
	var clipmap *catalog.Item
	for i := range items {
		if items[i].Title == "Clipmap" {
			clipmap = &items[i]
		}
	}
	if clipmap == nil {
		t.Fatalf("geen item Clipmap tussen %d items", len(items))
	}
	if len(clipmap.Versions) != 6 {
		t.Fatalf("de map met zes clips is %d versies, verwacht 6 op één item", len(clipmap.Versions))
	}

	ctx := context.Background()
	runner := metadata.NewRunner(h.store, silentProvider{}, metadata.ProviderTMDB, t.TempDir(),
		slog.New(slog.NewTextHandler(io.Discard, nil))).WithSidecar(metadata.FSSidecar{})
	stats, err := runner.Round(ctx)
	if err != nil {
		t.Fatalf("Round: %v", err)
	}
	if stats.Unmatched != 5 {
		t.Fatalf("verwacht dat de provider geen van de vijf kent, stats %+v", stats)
	}

	cov, err := h.store.MetadataCoverage(ctx, h.lib.ID)
	if err != nil {
		t.Fatal(err)
	}
	if cov.Items != 5 || cov.WithGenres != 4 || !cov.GateMet {
		t.Fatalf("dekking %+v, verwacht 4 van 5 titels met genres en een open poort", cov)
	}

	var source string
	if err := h.pool.QueryRow(ctx, `SELECT metadata_sources->>'genres' FROM media_items WHERE id = $1`, clipmap.ID).Scan(&source); err != nil {
		t.Fatal(err)
	}
	if source != catalog.SourceNFO {
		t.Fatalf("genres van de map komen uit %q, verwacht %q", source, catalog.SourceNFO)
	}

	// De poort is open, dus de genres zijn ook zichtbaar via de gewone lijst.
	for _, it := range h.items() {
		visible := len(it.Genres) == 2 && it.Genres[0] == "Animatie"
		if it.Title == "Zonder nfo" && len(it.Genres) != 0 {
			t.Errorf("%q heeft geen .nfo maar toont genres %v", it.Title, it.Genres)
		}
		if it.Title != "Zonder nfo" && !visible {
			t.Errorf("%q toont genres %v, verwacht [Animatie Familie]", it.Title, it.Genres)
		}
	}
}
