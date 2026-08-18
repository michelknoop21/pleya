package mounts

import (
	"os"
	"path/filepath"
	"testing"
)

func TestInspectWritableDir(t *testing.T) {
	dir := t.TempDir()

	info := Inspect(dir)
	if !info.Exists {
		t.Fatalf("Exists = false voor %s (%s)", dir, info.Err)
	}
	if !info.IsDir {
		t.Error("IsDir = false voor een map")
	}
	if !info.Readable {
		t.Error("Readable = false voor een leesbare map")
	}
	if !info.Writable {
		t.Error("Writable = false voor een beschrijfbare map")
	}
	if info.ReadOnly {
		t.Error("ReadOnly = true voor een beschrijfbare map")
	}
}

// De schrijfcontrole mag niets achterlaten; anders vervuilt elke start de
// mediamounts met sporen.
func TestInspectLeavesNothingBehind(t *testing.T) {
	dir := t.TempDir()
	Inspect(dir)

	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("map lezen mislukt: %v", err)
	}
	if len(entries) != 0 {
		t.Fatalf("Inspect liet %d bestand(en) achter: %v", len(entries), entries)
	}
}

func TestInspectMissingPath(t *testing.T) {
	info := Inspect(filepath.Join(t.TempDir(), "bestaat-niet"))
	if info.Exists {
		t.Error("Exists = true voor een ontbrekend pad")
	}
	if info.Err == "" {
		t.Error("Err is leeg voor een ontbrekend pad")
	}
}

func TestInspectFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "film.mkv")
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatalf("testbestand schrijven mislukt: %v", err)
	}

	info := Inspect(path)
	if !info.Exists || info.IsDir {
		t.Errorf("Exists = %v, IsDir = %v, verwacht true/false", info.Exists, info.IsDir)
	}
	if !info.Readable {
		t.Error("Readable = false voor een leesbaar bestand")
	}
}

func TestEnsureDir(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config", "diep")
	if err := EnsureDir(path); err != nil {
		t.Fatalf("EnsureDir gaf een fout: %v", err)
	}
	if info := Inspect(path); !info.Exists || !info.Writable {
		t.Fatalf("map niet bruikbaar na EnsureDir: %+v", info)
	}
	if err := EnsureDir(path); err != nil {
		t.Fatalf("EnsureDir is niet idempotent: %v", err)
	}
}

// LogValue moet de meting als één groep opnemen, zodat een logregel leesbaar
// blijft.
func TestInfoLogValue(t *testing.T) {
	v := Inspect(t.TempDir()).LogValue()
	if v.Kind().String() != "Group" {
		t.Fatalf("LogValue soort = %s, verwacht Group", v.Kind())
	}
	var sawPath bool
	for _, a := range v.Group() {
		if a.Key == "path" {
			sawPath = true
		}
	}
	if !sawPath {
		t.Error("veld path ontbreekt in LogValue")
	}
}
