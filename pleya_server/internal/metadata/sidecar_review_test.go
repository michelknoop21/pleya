package metadata

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

func TestChildFileSelectionRejectsOtherRootsAndInheritance(t *testing.T) {
	root := t.TempDir()
	for _, name := range []string{"tvshow.nfo", "season.nfo", "movie.nfo"} {
		if err := os.WriteFile(filepath.Join(root, name), []byte(`<season><plot>Do not inherit</plot></season>`), 0600); err != nil {
			t.Fatal(err)
		}
	}
	target := catalog.MetadataTarget{Kind: "episode", MediaRoot: root, MediaPath: "S01E01.mkv"}
	if result, err := (FSSidecar{}).ReadChecked(target); result != nil || err != nil {
		t.Fatalf("episode inherited sidecar: %+v %v", result, err)
	}
	file := filepath.Join(root, "S01E01.nfo")
	for _, kind := range []string{"season", "movie", "tvshow"} {
		if err := os.WriteFile(file, []byte(`<`+kind+`><plot>Wrong root</plot></`+kind+`>`), 0600); err != nil {
			t.Fatal(err)
		}
		if result, err := (FSSidecar{}).ReadChecked(target); result != nil || err == nil {
			t.Fatalf("accepted %s for episode: %+v %v", kind, result, err)
		}
	}
	if err := os.WriteFile(file, []byte(`<episodedetails><plot>Own episode</plot></episodedetails>`), 0600); err != nil {
		t.Fatal(err)
	}
	if result, err := (FSSidecar{}).ReadChecked(target); err != nil || result == nil || result.Summary != "Own episode" {
		t.Fatalf("wrong episode file selected: %+v %v", result, err)
	}
}
