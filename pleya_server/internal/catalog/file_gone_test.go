package catalog

import (
	"os"
	"path/filepath"
	"testing"
)

// TestFileGoneKeepsFilesWhenTheRootEmptiedAfterTheCheck bewaakt het venster
// tussen de roottoets van EmptyTrash en de toets per bestand: valt de share
// daartussen weg, dan is de root een lege map en bewijst een ontbrekend pad
// niets.
func TestFileGoneKeepsFilesWhenTheRootEmptiedAfterTheCheck(t *testing.T) {
	root := t.TempDir()
	if FileGone(root, "Film (2020)/film.mkv") {
		t.Fatal("een bestand onder een lege root telde als weg")
	}
	if err := os.WriteFile(filepath.Join(root, "ander.mkv"), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	if !FileGone(root, "Film (2020)/film.mkv") {
		t.Fatal("onder een gevulde root telde een verdwenen map niet als weg")
	}
}
