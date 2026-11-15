package catalog

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Een tussenmap die na de padcontrole door een symlink naar buiten vervangen
// wordt: os.Root weigert, en het bestand met dezelfde naam buiten de root
// blijft staan.
func TestRemoveItemFilesBlijftBinnenDeRootAlsEenMapOnderwegWisselt(t *testing.T) {
	base, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(base, "films")
	outside := filepath.Join(base, "buiten")
	for _, d := range []string{filepath.Join(root, "Film (2000)"), outside} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	for _, f := range []string{filepath.Join(root, "Film (2000)", "Film (2000).mkv"), filepath.Join(outside, "Film (2000).mkv"), filepath.Join(root, "ander.mkv")} {
		if err := os.WriteFile(f, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	afterPathCheck = func(DeleteFile) {
		if err := os.RemoveAll(filepath.Join(root, "Film (2000)")); err != nil {
			t.Error(err)
		}
		if err := os.Symlink(outside, filepath.Join(root, "Film (2000)")); err != nil {
			t.Error(err)
		}
	}
	t.Cleanup(func() { afterPathCheck = nil })

	file := DeleteFile{ID: id.New(), Root: root, Rel: "Film (2000)/Film (2000).mkv", Role: "media"}
	removed, failed := RemoveItemFiles([]DeleteFile{file}, []string{base})
	if len(removed) != 0 || len(failed) != 1 || failed[0].Reason != DeleteReasonOutsideRoot {
		t.Fatalf("gewist %v, bleef %v; wil niets gewist en outside_root", removed, failed)
	}
	if _, err := os.Stat(filepath.Join(outside, "Film (2000).mkv")); err != nil {
		t.Fatalf("het bestand buiten de root is gewist: %v", err)
	}
}

// Een andere root die dezelfde map is als een map in deze root, zoals /films
// als tweede bind-mount van /media/films: de paden tonen het niet, de mappen wel.
func TestOverlapOnDiskZietDezelfdeMapOnderEenAnderPad(t *testing.T) {
	base, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	video := filepath.Join(base, "volume1", "video")
	if err := os.MkdirAll(filepath.Join(video, "films", "Film (2000)"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(video, "series"), 0o755); err != nil {
		t.Fatal(err)
	}
	// Twee ingangen zonder het NAS-pad erin, zoals een container twee
	// bind-mounts onder eigen namen ziet.
	media := filepath.Join(base, "media")
	films := filepath.Join(base, "films")
	if err := os.Symlink(video, media); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(video, "films"), films); err != nil {
		t.Fatal(err)
	}
	if within(films, media) || within(media, films) {
		t.Fatal("de opzet deugt niet: de paden tonen de overlap al")
	}
	stat := func(p string) os.FileInfo {
		info, err := os.Stat(p)
		if err != nil {
			t.Fatal(err)
		}
		return info
	}
	if !overlapOnDisk(media, "films/Film (2000)/Film (2000).mkv", []os.FileInfo{stat(films)}, map[string]bool{}) {
		t.Fatal("/films is dezelfde map als /media/films, maar de overlap is niet gezien")
	}
	if overlapOnDisk(media, "series/Serie.mkv", []os.FileInfo{stat(films)}, map[string]bool{}) {
		t.Fatal("een bestand buiten /media/films telt als overlap")
	}
}
