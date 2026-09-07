package main

import (
	"context"
	"log/slog"
	"os"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/config"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError}))
}

// TestStorageRecheckHandlerMeasuresEveryClaimedRoot dekt de rechecktaak achter
// POST /storage/roots/recheck: een root met een echt bestandssysteem eronder
// (een tijdelijke map, geen aangemaakt /media-pad zoals de API-tests) hoort na
// de ronde inode_trust_source measured te dragen en niet de kolomdefault.
func TestStorageRecheckHandlerMeasuresEveryClaimedRoot(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	root := t.TempDir()
	if _, err := store.CreateLibrary(ctx, "Documentaires", "movies", []string{root}); err != nil {
		t.Fatalf("CreateLibrary: %v", err)
	}

	cfg := &config.Config{}
	handler := storageRecheckHandler(store, cfg, testLogger())
	if err := handler(ctx, jobs.Job{Kind: api.JobStorageRecheckRoots}); err != nil {
		t.Fatalf("storageRecheckHandler: %v", err)
	}

	locations, err := store.AllStorageLocations(ctx)
	if err != nil {
		t.Fatalf("AllStorageLocations: %v", err)
	}
	if len(locations) != 1 {
		t.Fatalf("AllStorageLocations gaf %d rijen, verwacht 1", len(locations))
	}
	got := locations[0]
	if got.TrustSource != "measured" {
		t.Errorf("TrustSource = %q, verwacht measured (root bestaat werkelijk)", got.TrustSource)
	}
	if got.FSType == "" {
		t.Error("FSType is leeg na de meting, verwacht een echt bestandssysteemtype")
	}
}

// TestStorageRecheckHandlerHonorsInodeTrustOverride dekt dat
// PLEYA_SERVER_INODE_TRUST de meting overrulet, dezelfde regel als bij het
// opstarten (bootstrap.go).
func TestStorageRecheckHandlerHonorsInodeTrustOverride(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	root := t.TempDir()
	if _, err := store.CreateLibrary(ctx, "Documentaires", "movies", []string{root}); err != nil {
		t.Fatalf("CreateLibrary: %v", err)
	}

	cfg := &config.Config{InodeTrust: map[string]config.InodeTrust{root: config.InodeTrustNever}}
	handler := storageRecheckHandler(store, cfg, testLogger())
	if err := handler(ctx, jobs.Job{}); err != nil {
		t.Fatalf("storageRecheckHandler: %v", err)
	}

	locations, err := store.AllStorageLocations(ctx)
	if err != nil {
		t.Fatalf("AllStorageLocations: %v", err)
	}
	got := locations[0]
	if got.InodeTrusted {
		t.Error("InodeTrusted = true, verwacht false door PLEYA_SERVER_INODE_TRUST=never")
	}
	if got.TrustSource != "config_override" {
		t.Errorf("TrustSource = %q, verwacht config_override", got.TrustSource)
	}
}
