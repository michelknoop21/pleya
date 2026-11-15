package catalog_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

// WritableRoots meet echt: een schrijfbare map komt erin (opgelost en zonder
// achtergebleven testbestand), een map die er niet is en een bestand niet. Een
// map zonder schrijfrecht telt alleen buiten root mee, want root schrijft overal.
func TestWritableRootsMeetSchrijfbaarheid(t *testing.T) {
	writable := t.TempDir()
	missing := filepath.Join(t.TempDir(), "niet-gemount")
	file := filepath.Join(t.TempDir(), "een-bestand")
	if err := os.WriteFile(file, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	locked := t.TempDir()
	if err := os.Chmod(locked, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(locked, 0o755) })

	got, readOnly := catalog.WritableRoots([]string{writable, missing, file, locked})
	want, _ := filepath.EvalSymlinks(writable)
	if len(got) < 1 || got[0] != want {
		t.Fatalf("schrijfbaar %v, wil eerst %s", got, want)
	}
	if os.Geteuid() != 0 {
		if len(got) != 1 || len(readOnly) != 3 {
			t.Fatalf("schrijfbaar %v, alleen-lezen %v; wil 1 en 3", got, readOnly)
		}
	} else if len(readOnly) < 2 || readOnly[0] != missing || readOnly[1] != file {
		t.Fatalf("alleen-lezen %v, wil minstens %s en %s", readOnly, missing, file)
	}
	entries, err := os.ReadDir(writable)
	if err != nil || len(entries) != 0 {
		t.Fatalf("de meting liet iets achter: %v (%v)", entries, err)
	}
}
