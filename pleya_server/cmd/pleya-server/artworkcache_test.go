package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/config"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func TestArtworkCacheProtectsOldClaimedRootRemovedFromMediaDirs(t *testing.T) {
	testsupport.HasFFmpeg(t)
	pool := testsupport.Pool(t)
	if _, err := migrate.Run(t.Context(), pool, nil); err != nil {
		t.Fatal(err)
	}
	store := catalog.NewStore(pool)
	oldRoot := t.TempDir()
	if _, err := store.CreateLibrary(t.Context(), "Oude bibliotheek", "movies", []string{oldRoot}); err != nil {
		t.Fatal(err)
	}
	cfg := &config.Config{FFmpegPath: "ffmpeg", CacheDir: oldRoot, ConfigDir: t.TempDir(), MediaDirs: []string{t.TempDir()}}
	resizer, _ := newArtworkResizer(context.Background(), store, cfg, t.TempDir(), testLogger())
	if err := os.MkdirAll(resizer.Dir(), 0755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(resizer.Dir(), "019a0000-0000-7000-8000-000000000001_1_480.jpg")
	if err := os.WriteFile(path, []byte("oude-media"), 0600); err != nil {
		t.Fatal(err)
	}
	if resizer.Available() {
		t.Error("oude geclaimde root werd cache")
	}
	if err := resizer.Purge(); err == nil {
		t.Error("purge in oude root was succes")
	}
	if got, err := os.ReadFile(path); err != nil || string(got) != "oude-media" {
		t.Fatalf("oude bibliotheek geraakt %q %v", got, err)
	}
}

func TestArtworkCacheInventoryFailureOnlyDisablesPurgeChain(t *testing.T) {
	testsupport.HasFFmpeg(t)
	pool := testsupport.Pool(t)
	// Echt nieuw schema zonder tabellen: AllStorageLocations moet falen.
	cfg := &config.Config{FFmpegPath: "ffmpeg", CacheDir: t.TempDir(), ConfigDir: t.TempDir(), MediaDirs: []string{t.TempDir()}}
	resizer, admin := newArtworkResizer(t.Context(), catalog.NewStore(pool), cfg, t.TempDir(), testLogger())
	if admin {
		t.Fatal("onvolledige inventaris activeerde purgeketen")
	}
	if !resizer.Available() {
		t.Fatal("inventarisatiefout schakelde bestaande artworklezers uit")
	}
}
