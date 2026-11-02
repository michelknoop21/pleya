package artwork

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"syscall"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// De eerste poging verliest werkelijk haar map op de syscallgrens; de volgende
// schrijft via dezelfde atomische writer als Prepare en Resolve. Zonder herhaling
// blijft de pin onleesbaar, ook al zijn de gevalideerde bronbytes beschikbaar.
func TestPinCacheHersteltVerdwenenMap(t *testing.T) {
	for _, grens := range []string{"createtemp", "rename"} {
		t.Run(grens, func(t *testing.T) {
			p := &Pins{cache: t.TempDir()}
			pin := catalog.ArtworkPin{ID: id.New(), SHA256: "synthetische-sha", Extension: ".png"}
			body := []byte("dezelfde reeds gevalideerde pinbytes")
			dir := filepath.Join(p.cache, "artwork-pins")
			attempts := 0
			err := retryPinCacheWrite(context.Background(), func() error {
				attempts++
				if attempts == 1 {
					return verdwijnendePinMap(t, dir, grens)
				}
				return p.writeCacheAttempt(pin, body)
			})
			if err != nil {
				t.Fatal(err)
			}
			got, err := os.ReadFile(p.cachePath(pin))
			if err != nil || !bytes.Equal(got, body) {
				t.Fatalf("pin niet hersteld: %q %v", got, err)
			}
			entries, err := os.ReadDir(dir)
			if err != nil || len(entries) != 1 || entries[0].Name() != filepath.Base(p.cachePath(pin)) {
				t.Fatalf("achtergebleven tijdelijke bestanden: %v %v", entries, err)
			}
		})
	}
}

// Alleen de ontbrekende-mapfout wordt opgewekt; geen namaak-ENOENT in de
// hersteltest. Dit legt geen claim over de interne virtiofs-oorzaak vast.
func verdwijnendePinMap(t *testing.T, dir, grens string) error {
	t.Helper()
	if err := os.MkdirAll(dir, 0755); err != nil {
		t.Fatal(err)
	}
	name := ""
	if grens == "rename" {
		f, err := os.CreateTemp(dir, ".incoming-*")
		if err != nil {
			t.Fatal(err)
		}
		name = f.Name()
		if _, err := f.Write([]byte("afgeleide bytes")); err != nil {
			t.Fatal(err)
		}
		if err := f.Sync(); err != nil {
			t.Fatal(err)
		}
		if err := f.Close(); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.RemoveAll(dir); err != nil {
		t.Fatal(err)
	}
	var err error
	if grens == "rename" {
		err = os.Rename(name, filepath.Join(dir, "pin.png"))
	} else {
		f, openErr := os.CreateTemp(dir, ".incoming-*")
		if f != nil {
			f.Close()
		}
		err = openErr
	}
	if !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("fixture geen echte ENOENT: %v", err)
	}
	return err
}

func TestPinCacheBlijvendMapverliesBlijftBegrensd(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "artwork-pins")
	attempts := 0
	err := retryPinCacheWrite(context.Background(), func() error {
		attempts++
		return verdwijnendePinMap(t, dir, "createtemp")
	})
	if !errors.Is(err, os.ErrNotExist) || attempts != 3 {
		t.Fatalf("onbegrensd of vals succes: pogingen=%d fout=%v", attempts, err)
	}
	if _, err := os.Stat(dir); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("onverwacht resultaat: %v", err)
	}
}

func TestPinCacheMaskeertAndereSchrijffoutenNiet(t *testing.T) {
	for _, failure := range []error{syscall.ENOSPC, syscall.EACCES} {
		t.Run(failure.Error(), func(t *testing.T) {
			expected := &os.PathError{Op: "open", Path: "/synthetic-cache/.incoming", Err: failure}
			attempts := 0
			err := retryPinCacheWrite(context.Background(), func() error { attempts++; return expected })
			if err != expected || attempts != 1 {
				t.Fatalf("schrijffout gemaskeerd of herhaald: %v pogingen=%d", err, attempts)
			}
		})
	}
}

func TestPinCacheWachtAnnuleerbaarNaMapverlies(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	entered := make(chan struct{})
	done := make(chan error, 1)
	attempts := 0
	go func() {
		done <- retryPinCacheWrite(ctx, func() error {
			attempts++
			if attempts == 1 {
				close(entered)
			}
			return &os.PathError{Op: "open", Path: "/synthetic-cache/.incoming", Err: syscall.ENOENT}
		})
	}()
	<-entered
	cancel()
	if err := <-done; !errors.Is(err, context.Canceled) || attempts != 1 {
		t.Fatalf("annulering verloren: %v pogingen=%d", err, attempts)
	}
}

func TestPinCacheGeannuleerdRequestSchrijftNiet(t *testing.T) {
	p := &Pins{cache: t.TempDir()}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	err := p.writeCache(ctx, catalog.ArtworkPin{ID: id.New(), SHA256: "synthetische-sha", Extension: ".png"}, []byte("bytes"))
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("annulering verloren: %v", err)
	}
	entries, err := os.ReadDir(p.cache)
	if err != nil || len(entries) != 0 {
		t.Fatalf("geannuleerd request schreef cache: %v %v", entries, err)
	}
}

func TestPinCacheMisluktePublicatieRuimtTempOp(t *testing.T) {
	p := &Pins{cache: t.TempDir()}
	pin := catalog.ArtworkPin{ID: id.New(), SHA256: "synthetische-sha", Extension: ".png"}
	// Een directory op de doellocatie maakt de echte Rename onmogelijk.
	// De bestaande pinlocatie blijft staan en de tijdelijke bytes verdwijnen.
	if err := os.MkdirAll(p.cachePath(pin), 0755); err != nil {
		t.Fatal(err)
	}
	if err := p.writeCache(context.Background(), pin, []byte("bytes")); err == nil || errors.Is(err, os.ErrNotExist) {
		t.Fatalf("fixture geen permanente publicatiefout: %v", err)
	}
	entries, err := os.ReadDir(filepath.Dir(p.cachePath(pin)))
	if err != nil || len(entries) != 1 || entries[0].Name() != filepath.Base(p.cachePath(pin)) || !entries[0].IsDir() {
		t.Fatalf("tempbytes achtergelaten of doel gewijzigd: %v %v", entries, err)
	}
}
