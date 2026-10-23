package api_test

import (
	"bytes"
	"context"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/backup"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// runBackupJobs voert de wachtende back-up- en hersteltestjobs uit, zoals de
// runner dat in productie doet, en zet ze daarna op afgerond.
func (e *env) runBackupJobs() {
	e.t.Helper()
	ctx := context.Background()
	for {
		var job jobs.Job
		err := e.pool.QueryRow(ctx, `SELECT id, kind, args FROM jobs WHERE kind IN ($1, $2) AND state = 'pending' ORDER BY id LIMIT 1`,
			backup.JobCreate, backup.JobVerify).Scan(&job.ID, &job.Kind, &job.Args)
		if err != nil {
			return
		}
		handler := backup.VerifyHandler(e.backups)
		if job.Kind == backup.JobCreate {
			handler = backup.CreateHandler(e.backups, nil)
		}
		if err := handler(ctx, job); err != nil {
			e.t.Fatalf("job %s: %v", job.Kind, err)
		}
		if _, err := e.pool.Exec(ctx, `UPDATE jobs SET state = 'succeeded', finished_at = now() WHERE id = $1`, job.ID); err != nil {
			e.t.Fatal(err)
		}
	}
}

// makeBackup start een back-up over de API, voert hem uit en geeft hem terug.
func (e *env) makeBackup() api.BackupWire {
	e.t.Helper()
	rec := e.do(http.MethodPost, "/pleya/v1/backups", nil)
	if rec.Code != http.StatusAccepted {
		e.t.Fatalf("POST /backups gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("Backup", http.MethodPost, "/pleya/v1/backups", rec)
	var started api.BackupWire
	e.decodeInto(rec, &started)
	if started.Status != "running" || started.RestoreConfirmation != nil {
		e.t.Fatalf("een nieuwe back-up hoort te lopen en nog niets te bevestigen: %+v", started)
	}
	e.runBackupJobs()
	var done api.BackupWire
	e.getJSON("/pleya/v1/backups/"+started.ID, "Backup", http.StatusOK, &done)
	return done
}

func TestBackupIsMadeVerifiedAndListedForAnAdmin(t *testing.T) {
	testsupport.HasPostgresClient(t)
	e := newEnv(t)
	e.setup(e.putSetupCode())

	var info api.Info
	e.getJSON("/pleya/v1/info", "", http.StatusOK, &info)
	if !info.Capabilities.Backups {
		t.Fatal("capabilities.backups staat uit terwijl de service er is")
	}
	if err := os.WriteFile(filepath.Join(e.config, "token-signing.key"), []byte("sleutelmateriaal"), 0o600); err != nil {
		t.Fatal(err)
	}

	b := e.makeBackup()
	if b.Status != "ok" || b.Titles == nil || *b.Titles == 0 || !b.SecretsIncluded || b.RestoreConfirmation == nil {
		t.Fatalf("back-up: %+v", b)
	}

	rec := e.do(http.MethodPost, "/pleya/v1/backups/"+b.ID+"/verify", nil)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("hersteltest starten gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("Backup", http.MethodPost, "/pleya/v1/backups/"+b.ID+"/verify", rec)
	e.runBackupJobs()
	var verified api.BackupWire
	e.getJSON("/pleya/v1/backups/"+b.ID, "Backup", http.StatusOK, &verified)
	lt := verified.LastRestoreTest
	if lt == nil || lt.Status != "ok" || lt.TitlesFound == nil || *lt.TitlesFound != *b.Titles {
		t.Fatalf("hersteltest: %+v", lt)
	}

	var list api.BackupList
	e.getJSON("/pleya/v1/backups", "BackupList", http.StatusOK, &list)
	if len(list.Items) != 1 || list.Schedule != "03:30" || list.RetentionDays != 14 || !list.SecretsKeyConfigured {
		t.Fatalf("lijst: %+v", list)
	}
	// Twee tijdelijke mappen op hetzelfde bestandssysteem: de waarschuwing staat aan.
	if !list.SameFailureDomain {
		t.Fatal("same_failure_domain staat uit terwijl de back-up naast /config staat")
	}

	// Er is geen route om een back-up te downloaden, ook niet voor de owner.
	if rec := e.do(http.MethodGet, "/pleya/v1/backups/"+b.ID+"/file", nil); rec.Code != http.StatusNotFound {
		t.Fatalf("GET /backups/{id}/file gaf %d; een back-up hoort niet over HTTP te gaan", rec.Code)
	}
}

func TestRestoreNeedsTheExactConfirmationAndRunsInMaintenance(t *testing.T) {
	testsupport.HasPostgresClient(t)
	e := newEnv(t)
	e.setup(e.putSetupCode())
	key := filepath.Join(e.config, "token-signing.key")
	if err := os.WriteFile(key, []byte("sleutel-van-voor-de-backup"), 0o600); err != nil {
		t.Fatal(err)
	}
	b := e.makeBackup()
	later := e.createUser("member", "na-de-backup")
	if err := os.WriteFile(key, []byte("sleutel-van-na-de-backup"), 0o600); err != nil {
		t.Fatal(err)
	}
	path := "/pleya/v1/backups/" + b.ID + "/restore"

	for _, confirm := range []string{"", "herstel", "ja"} {
		rec := e.do(http.MethodPost, path, map[string]string{"confirm": confirm})
		if rec.Code != http.StatusConflict {
			t.Fatalf("restore met %q gaf %d, verwacht 409: %s", confirm, rec.Code, rec.Body.String())
		}
		e.expectCode(rec, api.CodeConfirmMismatch)
		e.recordVariant("ErrorEnvelope", "restore_confirm", http.MethodPost, path, rec)
		var env struct {
			Error struct {
				Details map[string]string `json:"details"`
			} `json:"error"`
		}
		e.decodeInto(rec, &env)
		if env.Error.Details["expected"] != *b.RestoreConfirmation {
			t.Fatalf("details.expected %q, verwacht de zin uit restore_confirmation %q", env.Error.Details["expected"], *b.RestoreConfirmation)
		}
	}
	if !userExists(e, later) {
		t.Fatal("een geweigerde restore heeft toch iets teruggezet")
	}

	rec := e.do(http.MethodPost, path, map[string]string{"confirm": *b.RestoreConfirmation})
	if rec.Code != http.StatusAccepted {
		t.Fatalf("restore met de juiste zin gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("Backup", http.MethodPost, path, rec)

	// Vanaf nu is de server in onderhoud, ook voor een geldige aanvraag.
	busy := e.do(http.MethodGet, "/pleya/v1/libraries", nil)
	if busy.Code != http.StatusServiceUnavailable {
		t.Fatalf("tijdens de restore gaf een aanvraag %d, verwacht 503", busy.Code)
	}
	e.expectCode(busy, api.CodeMaintenance)
	e.recordVariant("ErrorEnvelope", "maintenance", http.MethodGet, "/pleya/v1/libraries", busy)

	select {
	case err := <-e.restored:
		if err != nil {
			t.Fatalf("restore: %v", err)
		}
	case <-time.After(2 * time.Minute):
		t.Fatal("de restore kwam niet terug")
	}
	if userExists(e, later) {
		t.Fatal("de gebruiker van na de back-up bestaat na de restore nog")
	}
	if got, _ := os.ReadFile(key); !bytes.Equal(got, []byte("sleutel-van-voor-de-backup")) {
		t.Fatalf("de ondertekensleutel is niet die van de back-up: %q", got)
	}
}

func TestRestoreAndVerifyRefuseWhatCannotBeRestored(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	failed := id.New()
	if _, err := e.pool.Exec(context.Background(), `
		INSERT INTO backups (id, trigger, status, failure, finished_at) VALUES ($1, 'manual', 'failed', 'disk_full', now())`, failed); err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{"/verify", "/restore"} {
		rec := e.do(http.MethodPost, "/pleya/v1/backups/"+failed.String()+p, map[string]string{"confirm": "x"})
		if rec.Code != http.StatusConflict {
			t.Fatalf("%s op een mislukte back-up gaf %d", p, rec.Code)
		}
		e.expectCode(rec, api.CodeBackupNotRestorable)
		e.recordVariant("ErrorEnvelope", "backup_not_restorable", http.MethodPost, "/pleya/v1/backups/"+failed.String()+p, rec)
	}
	var b api.BackupWire
	e.getJSON("/pleya/v1/backups/"+failed.String(), "Backup", http.StatusOK, &b)
	if b.FailureCode == nil || *b.FailureCode != api.CodeStorageFull || b.RestoreConfirmation != nil {
		t.Fatalf("mislukte back-up: %+v", b)
	}

	// Eén back-up tegelijk.
	if rec := e.do(http.MethodPost, "/pleya/v1/backups", nil); rec.Code != http.StatusAccepted {
		t.Fatalf("eerste back-up gaf %d", rec.Code)
	}
	rec := e.do(http.MethodPost, "/pleya/v1/backups", nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("een tweede back-up terwijl de eerste wacht gaf %d", rec.Code)
	}
	e.expectCode(rec, api.CodeBackupBusy)
	e.recordVariant("ErrorEnvelope", "backup_busy", http.MethodPost, "/pleya/v1/backups", rec)

	if rec := e.do(http.MethodGet, "/pleya/v1/backups/"+id.New().String(), nil); rec.Code != http.StatusNotFound {
		t.Fatalf("een onbekende back-up gaf %d", rec.Code)
	}
}

func userExists(e *env, uid id.ID) bool {
	e.t.Helper()
	var n int
	if err := e.pool.QueryRow(context.Background(), `SELECT count(*) FROM users WHERE id = $1`, uid).Scan(&n); err != nil {
		e.t.Fatal(err)
	}
	return n == 1
}
