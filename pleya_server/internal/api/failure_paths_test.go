package api_test

import (
	"context"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	"github.com/edde746/plezy/pleya_server/internal/transcode"
)

// crashingFFmpeg is een ffmpeg die meteen aan een segfault sterft: de crash van
// de omzetter, zonder een echte omzetting af te wachten.
const crashingFFmpeg = "#!/bin/sh\nkill -SEGV $$\n"

// TestFailurePathsEachHaveTheirOwnCode is de settest van S25.5 (RB-26): de vier
// faalpaden, elk met een echte oorzaak en elk met zijn eigen foutcode. Ze staan
// in één test omdat de belofte over de set gaat: geen twee paden met dezelfde
// code, en geen pad dat als server.internal eindigt.
func TestFailurePathsEachHaveTheirOwnCode(t *testing.T) {
	seen := map[string]string{}
	claim := func(t *testing.T, path, code string) {
		t.Helper()
		if code == api.CodeInternal {
			t.Fatalf("faalpad %s eindigt als server.internal", path)
		}
		if other, dup := seen[code]; dup {
			t.Fatalf("faalpad %s deelt zijn code %s met %s", path, code, other)
		}
		seen[code] = path
	}

	// Schijf vol: de back-up schrijft naar /dev/full, en de kernel geeft ENOSPC.
	t.Run("schijf vol", func(t *testing.T) {
		testsupport.HasPostgresClient(t)
		e := newEnv(t, func(o *api.Options) {
			o.Backups = o.Backups.WithCreate(func(string) (*os.File, error) {
				return os.OpenFile("/dev/full", os.O_WRONLY, 0)
			})
		})
		e.setup(e.putSetupCode())
		rec := e.do(http.MethodPost, "/pleya/v1/backups", nil)
		if rec.Code != http.StatusAccepted {
			t.Fatalf("POST /backups gaf %d: %s", rec.Code, rec.Body.String())
		}
		var b api.BackupWire
		e.decodeInto(rec, &b)
		e.runBackupJobs()
		e.getJSON("/pleya/v1/backups/"+b.ID, "Backup", http.StatusOK, &b)
		if b.Status != "failed" || b.FailureCode == nil || *b.FailureCode != api.CodeStorageFull {
			t.Fatalf("volle schijf: %+v, verwacht failed met storage.full", b)
		}
		claim(t, "schijf vol", *b.FailureCode)
	})

	// Database weg: een server waarvan de pool naar een poort wijst waar niets
	// luistert. De handtekening van het token is in orde, dus de aanvraag komt
	// tot de eerste query.
	t.Run("database weg", func(t *testing.T) {
		e := newEnv(t)
		dead, err := pgxpool.New(context.Background(), "postgres://pleya:x@127.0.0.1:1/pleya?sslmode=disable&connect_timeout=2")
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(dead.Close)
		srv := api.New(api.Options{
			Catalog: catalog.NewStore(dead), Auth: auth.NewStore(dead), Signer: e.signer, Logger: e.log,
			Ready: func() bool { return false }, AccessTokenTTL: 15 * time.Minute,
		})
		token, _, err := e.signer.Mint(id.New().String(), id.New().String(), auth.TokenAccess, 15*time.Minute, "")
		if err != nil {
			t.Fatal(err)
		}
		e.server = srv
		e.access = token
		rec := e.do(http.MethodGet, "/pleya/v1/libraries", nil)
		if rec.Code != http.StatusServiceUnavailable {
			t.Fatalf("zonder database gaf GET /libraries %d: %s", rec.Code, rec.Body.String())
		}
		e.expectCode(rec, api.CodeDatabaseUnavailable)
		e.recordVariant("ErrorEnvelope", "database_unavailable", http.MethodGet, "/pleya/v1/libraries", rec)
		claim(t, "database weg", api.CodeDatabaseUnavailable)
	})

	// Transcoder-crash en kapot bestand delen een omgeving: dezelfde crashende
	// ffmpeg, eerst op een gaaf bestand, dan op een bestand dat stuk is.
	e, abs := crashingTranscodeEnv(t)
	movie := e.findMovie("Grease")
	t.Run("transcoder-crash", func(t *testing.T) {
		_, rec := e.planFor(map[string]any{"item_id": movie.ID, "capabilities": vp9Only()}, http.StatusBadGateway)
		e.expectCode(rec, api.CodeTranscodeFailed)
		e.recordVariant("ErrorEnvelope", "transcode_failed", http.MethodPost, "/pleya/v1/playback/plan", rec)
		claim(t, "transcoder-crash", api.CodeTranscodeFailed)
	})
	t.Run("kapot bestand", func(t *testing.T) {
		if err := os.WriteFile(abs, []byte("dit is geen matroska maar rommel"), 0o644); err != nil {
			t.Fatal(err)
		}
		_, rec := e.planFor(map[string]any{"item_id": movie.ID, "capabilities": vp9Only()}, http.StatusUnprocessableEntity)
		e.expectCode(rec, api.CodeFileCorrupt)
		e.recordVariant("ErrorEnvelope", "file_corrupt", http.MethodPost, "/pleya/v1/playback/plan", rec)
		claim(t, "kapot bestand", api.CodeFileCorrupt)
	})
}

// crashingTranscodeEnv is een omgeving met een omzetter die elke sessie laat
// crashen, plus het pad van het bestand achter Grease.
func crashingTranscodeEnv(t *testing.T) (*env, string) {
	t.Helper()
	dir := t.TempDir()
	stub := filepath.Join(dir, "ffmpeg")
	if err := os.WriteFile(stub, []byte(crashingFFmpeg), 0o755); err != nil {
		t.Fatal(err)
	}
	m, err := transcode.New(transcode.Options{
		FFmpegPath: stub, Dir: filepath.Join(dir, "work"), Max: 2,
		IdleTimeout: time.Minute, StartTimeout: 10 * time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(m.Close)
	e := newEnv(t, func(o *api.Options) { o.Transcode = m })
	e.setup(e.putSetupCode())
	_, abs := e.moviePath("Grease")
	return e, abs
}
