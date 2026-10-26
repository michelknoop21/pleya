package config

import (
	"os"
	"strings"
	"testing"
)

// TestComposePassesMediaDirs: PLEYA_SERVER_MEDIA_DIRS bepaalt welke roots een
// bibliotheek mag gebruiken. Staat hij niet in compose.yaml, dan komt een regel
// in de .env nooit in de container en valt de lijst terug op /media/library,
// zonder dat iets daarover klaagt (productie, 26 oktober 2026).
func TestComposePassesMediaDirs(t *testing.T) {
	raw, err := os.ReadFile("../../compose.yaml")
	if err != nil {
		t.Fatalf("compose.yaml lezen: %v", err)
	}
	const want = "PLEYA_SERVER_MEDIA_DIRS: ${PLEYA_SERVER_MEDIA_DIRS:-}"
	if !strings.Contains(string(raw), want) {
		t.Fatalf("compose.yaml geeft PLEYA_SERVER_MEDIA_DIRS niet door; verwacht de regel %q", want)
	}
}
