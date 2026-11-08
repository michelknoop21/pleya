package main

import (
	"context"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/scanner"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	"github.com/jackc/pgx/v5"
)

// TestEmptyTrashJobRunsThroughTheRunner zet een empty_library_trash-job in de
// wachtrij zoals de API dat doet en laat de runner hem uitvoeren. Een root die
// als lege map achterblijft laat de job mislukken met een leesbare reden en
// verwijdert niets; daarna, met de root terug, gaat de verdwenen film en
// blijft de aanwezige.
func TestEmptyTrashJobRunsThroughTheRunner(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	store := catalog.NewStore(pool)
	root := t.TempDir()
	testsupport.MakeVideo(t, filepath.Join(root, "Gone (2001)", "Gone (2001).mkv"), 1)
	testsupport.MakeVideo(t, filepath.Join(root, "Kept (2002)", "Kept (2002).mkv"), 1)
	lib, err := store.CreateLibrary(ctx, "Films", "movies", []string{root})
	if err != nil {
		t.Fatal(err)
	}
	sc := scanner.New(scanner.Options{Store: store, Prober: ffprobe.New("ffprobe", 60*time.Second), Logger: log, Concurrency: 1})
	if _, err := sc.ScanLibraryRun(ctx, lib, "manual", id.Nil); err != nil {
		t.Fatal(err)
	}
	if err := os.RemoveAll(filepath.Join(root, "Gone (2001)")); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `UPDATE media_files SET missing_since = now() WHERE relative_path LIKE 'Gone%'`); err != nil {
		t.Fatal(err)
	}
	titles := func() []string {
		rows, err := pool.Query(ctx, `SELECT title FROM media_items WHERE library_id = $1 ORDER BY title`, lib.ID)
		if err != nil {
			t.Fatal(err)
		}
		out, err := pgx.CollectRows(rows, pgx.RowTo[string])
		if err != nil {
			t.Fatal(err)
		}
		return out
	}

	runner := jobs.New(jobs.Options{Pool: pool, Logger: log, Interval: 20 * time.Millisecond, Instance: "test"})
	runner.Register(api.JobEmptyLibraryTrash, emptyTrashHandler(store, log))
	runCtx, stop := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() { runner.Run(runCtx); close(done) }()
	defer func() { stop(); <-done }()

	runJob := func() jobs.Record {
		t.Helper()
		jobID, inserted, err := runner.Enqueue(ctx, api.JobEmptyLibraryTrash,
			api.ScanJobArgs{LibraryID: lib.ID.String(), Trigger: "manual"}, "scan:"+lib.ID.String(), time.Time{})
		if err != nil || !inserted {
			t.Fatalf("inplannen: %v (ingepland %v)", err, inserted)
		}
		deadline := time.Now().Add(20 * time.Second)
		for {
			rec, err := runner.Get(ctx, jobID)
			if err != nil {
				t.Fatal(err)
			}
			if rec.State == "succeeded" || rec.State == "failed" || (rec.State == "pending" && rec.LastError != "") {
				return rec
			}
			if time.Now().After(deadline) {
				t.Fatalf("job bleef op %s staan", rec.State)
			}
			time.Sleep(20 * time.Millisecond)
		}
	}

	// Eerst de root als lege map, zoals een share die niet gemount is.
	if err := os.Rename(root, root+"-offline"); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(root, 0o755); err != nil {
		t.Fatal(err)
	}
	rec := runJob()
	if rec.State == "succeeded" || !strings.Contains(rec.LastError, "root niet te lezen of leeg") {
		t.Fatalf("job op een lege root: %s, %q", rec.State, rec.LastError)
	}
	if got := titles(); len(got) != 2 {
		t.Fatalf("na een lege root: %v, wil beide films", got)
	}
	// De mislukte job uit de dedupe key halen voor de tweede ronde.
	if _, err := pool.Exec(ctx, `UPDATE jobs SET state = 'failed', run_at = now() + interval '1 day' WHERE id = $1`, rec.ID); err != nil {
		t.Fatal(err)
	}

	if err := os.Remove(root); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(root+"-offline", root); err != nil {
		t.Fatal(err)
	}
	if rec := runJob(); rec.State != "succeeded" {
		t.Fatalf("job: %s, %q", rec.State, rec.LastError)
	}
	if got := titles(); len(got) != 1 || got[0] != "Kept" {
		t.Fatalf("na legen: %v, wil alleen Kept", got)
	}
}
