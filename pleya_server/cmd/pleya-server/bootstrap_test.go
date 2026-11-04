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
		if rec["msg"] != skippedRootMsg {
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

// TestSyncLibrariesLogsNestedSkippedRoot (S2.8): een .env-root binnen een root
// van een db-bibliotheek komt in dezelfde logregel, en het opstarten gaat door.
func TestSyncLibrariesLogsNestedSkippedRoot(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)
	if _, err := store.CreateLibrary(ctx, "Films", "movies", []string{"/media/films"}); err != nil {
		t.Fatalf("CreateLibrary: %v", err)
	}

	cfg := &config.Config{Libraries: []config.LibrarySpec{
		{Slug: "kids", Title: "Kids", Kind: "movies", Roots: []string{"/media/films/kids"}},
	}}
	var buf bytes.Buffer
	log := slog.New(slog.NewJSONHandler(&buf, nil))

	if _, err := syncLibraries(ctx, store, cfg, log); err != nil {
		t.Fatalf("syncLibraries: %v", err)
	}

	var logged []string
	dec := json.NewDecoder(&buf)
	for dec.More() {
		var rec map[string]any
		if err := dec.Decode(&rec); err != nil {
			t.Fatalf("logregel lezen: %v", err)
		}
		if rec["msg"] == skippedRootMsg {
			logged = append(logged, rec["slug"].(string)+" "+rec["root"].(string))
		}
	}
	if len(logged) != 1 || logged[0] != "kids /media/films/kids" {
		t.Fatalf("logregels voor overgeslagen roots: %v, verwacht [kids /media/films/kids]", logged)
	}
}

// TestEmptyEnvLeavesDatabaseLibrariesAlone: haalt een beheerder
// PLEYA_SERVER_LIBRARIES weg nadat alles is overgenomen, dan blijven de
// bibliotheken en hun roots zoals ze waren en meldt de server dat als Info.
// Een waarschuwing hoort er alleen als de database ook niets heeft.
func TestEmptyEnvLeavesDatabaseLibrariesAlone(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)
	created, err := store.CreateLibrary(ctx, "Films", "movies", []string{"/media/library/Films"})
	if err != nil {
		t.Fatalf("CreateLibrary: %v", err)
	}

	var buf bytes.Buffer
	log := slog.New(slog.NewJSONHandler(&buf, nil))
	if _, err := syncLibraries(ctx, store, &config.Config{}, log); err != nil {
		t.Fatalf("syncLibraries: %v", err)
	}

	libs, err := store.Libraries(ctx)
	if err != nil {
		t.Fatalf("Libraries: %v", err)
	}
	if len(libs) != 1 || libs[0].ID != created.ID || libs[0].Managed != catalog.ManagedDB {
		t.Fatalf("na een lege omgeving staat er %+v, verwacht de db-bibliotheek ongewijzigd", libs)
	}
	for _, level := range logLevels(t, &buf) {
		if level == "WARN" {
			t.Fatalf("een lege omgeving met db-bibliotheken geeft een waarschuwing")
		}
	}
}

func TestEmptyEnvAndEmptyDatabaseWarns(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	var buf bytes.Buffer
	log := slog.New(slog.NewJSONHandler(&buf, nil))
	if _, err := syncLibraries(ctx, catalog.NewStore(pool), &config.Config{}, log); err != nil {
		t.Fatalf("syncLibraries: %v", err)
	}
	levels := logLevels(t, &buf)
	if len(levels) != 1 || levels[0] != "WARN" {
		t.Fatalf("zonder enige bibliotheek verwacht één waarschuwing, kreeg %v", levels)
	}
}

func logLevels(t *testing.T, buf *bytes.Buffer) []string {
	t.Helper()
	var out []string
	dec := json.NewDecoder(buf)
	for dec.More() {
		var rec map[string]any
		if err := dec.Decode(&rec); err != nil {
			t.Fatalf("logregel lezen: %v", err)
		}
		out = append(out, rec["level"].(string))
	}
	return out
}
