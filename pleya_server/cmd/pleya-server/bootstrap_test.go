package main

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/config"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// TestSyncLibrariesLogsEverySkippedRoot: noemen twee .env-regels een root van
// een db-bibliotheek, dan slaan beide hem over en staat er per regel één
// logregel met de slug en het pad.
func TestSyncLibrariesLogsEverySkippedRoot(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)
	if _, err := store.CreateLibrary(ctx, "Archief", "movies", []string{"/media/archief"}); err != nil {
		t.Fatalf("CreateLibrary: %v", err)
	}

	cfg := &config.Config{Libraries: []config.LibrarySpec{
		{Slug: "eerste", Title: "Eerste", Kind: "movies", Roots: []string{"/media/archief"}},
		{Slug: "tweede", Title: "Tweede", Kind: "movies", Roots: []string{"/media/archief"}},
	}}
	var buf bytes.Buffer
	log := slog.New(slog.NewJSONHandler(&buf, nil))

	if _, err := syncLibraries(ctx, store, cfg, log); err != nil {
		t.Fatalf("syncLibraries: %v", err)
	}

	var slugs []string
	dec := json.NewDecoder(&buf)
	for dec.More() {
		var rec map[string]any
		if err := dec.Decode(&rec); err != nil {
			t.Fatalf("logregel lezen: %v", err)
		}
		if rec["msg"] != "root hoort bij een bibliotheek in de database; de .env-regel claimt hem niet" {
			continue
		}
		if rec["root"] != "/media/archief" {
			t.Errorf("logregel noemt root %v, verwacht /media/archief", rec["root"])
		}
		slugs = append(slugs, rec["slug"].(string))
	}
	if len(slugs) != 2 || slugs[0] != "eerste" || slugs[1] != "tweede" {
		t.Fatalf("logregels voor overgeslagen roots: %v, verwacht [eerste tweede]", slugs)
	}
}
