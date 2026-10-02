package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Jobs over HTTP (S2.4, J.3 venster 2).

func TestCancelQueuedScanMarksBothCancelled(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	lib := e.createLibraryViaAPI(t, "Annuleerbaar", "movies", []string{"/media/annuleer"})
	started := e.do(http.MethodPost, "/pleya/v1/libraries/"+lib.ID+"/scan", nil)
	var scan struct {
		ID string `json:"id"`
	}
	json.Unmarshal(started.Body.Bytes(), &scan)

	list := e.do(http.MethodGet, "/pleya/v1/jobs?limit=5", nil)
	e.record("JobPage", http.MethodGet, "/pleya/v1/jobs", list)
	var page struct {
		Items []struct {
			ID     string `json:"id"`
			Kind   string `json:"kind"`
			ScanID string `json:"scan_id"`
		} `json:"items"`
	}
	json.Unmarshal(list.Body.Bytes(), &page)
	var jobID string
	for _, it := range page.Items {
		if it.Kind == "scan_library" && it.ScanID == scan.ID {
			jobID = it.ID
		}
	}
	if jobID == "" {
		t.Fatalf("scanjob niet in de lijst: %s", list.Body.String())
	}

	cancelled := e.do(http.MethodPost, "/pleya/v1/jobs/"+jobID+"/cancel", nil)
	if cancelled.Code != http.StatusOK {
		t.Fatalf("cancel gaf %d: %s", cancelled.Code, cancelled.Body.String())
	}
	e.record("Job", http.MethodPost, "/pleya/v1/jobs/{job_id}/cancel", cancelled)
	if !strings.Contains(cancelled.Body.String(), `"state":"cancelled"`) {
		t.Fatalf("job niet cancelled: %s", cancelled.Body.String())
	}
	run := e.do(http.MethodGet, "/pleya/v1/scans/"+scan.ID, nil)
	if !strings.Contains(run.Body.String(), `"state":"cancelled"`) {
		t.Fatalf("scan_runs-rij niet cancelled: %s", run.Body.String())
	}

	twice := e.do(http.MethodPost, "/pleya/v1/jobs/"+jobID+"/cancel", nil)
	if twice.Code != http.StatusConflict || errorCode(t, twice) != "job.not_cancellable" {
		t.Fatalf("tweede cancel gaf %d %s", twice.Code, twice.Body.String())
	}
	e.recordVariant("ErrorEnvelope", "not_cancellable", http.MethodPost, "/pleya/v1/jobs/{job_id}/cancel", twice)

	retried := e.do(http.MethodPost, "/pleya/v1/jobs/"+jobID+"/retry", nil)
	if retried.Code != http.StatusOK || !strings.Contains(retried.Body.String(), `"state":"pending"`) {
		t.Fatalf("retry gaf %d: %s", retried.Code, retried.Body.String())
	}
	e.record("Job", http.MethodPost, "/pleya/v1/jobs/{job_id}/retry", retried)
}

func TestRetryOfAScanJobResetsProbeAttemptsAndGetsAFreshRun(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()
	libraryID := e.libs[0].ID
	if _, err := e.pool.Exec(ctx, `UPDATE media_files SET probe_attempts = 3`); err != nil {
		t.Fatal(err)
	}
	jobID := id.New()
	args, _ := json.Marshal(api.ScanJobArgs{LibraryID: libraryID.String(), Trigger: "manual", ScanRunID: id.New().String()})
	if _, err := e.pool.Exec(ctx, `
		INSERT INTO jobs (id, kind, args, state, attempts, finished_at, last_error)
		VALUES ($1, 'scan_library', $2, 'failed', 3, now(), 'ffprobe gaf na 60 s geen antwoord')`, jobID, args); err != nil {
		t.Fatal(err)
	}

	rec := e.do(http.MethodPost, "/pleya/v1/jobs/"+jobID.String()+"/retry", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("retry gaf %d: %s", rec.Code, rec.Body.String())
	}
	var job struct {
		State  string `json:"state"`
		ScanID string `json:"scan_id"`
	}
	json.Unmarshal(rec.Body.Bytes(), &job)
	if job.State != "pending" || job.ScanID == "" {
		t.Fatalf("na retry: %s", rec.Body.String())
	}
	run := e.do(http.MethodGet, "/pleya/v1/scans/"+job.ScanID, nil)
	if run.Code != http.StatusOK || !strings.Contains(run.Body.String(), `"state":"queued"`) {
		t.Fatalf("retry gaf geen verse queued scan: %d %s", run.Code, run.Body.String())
	}
	var left int
	if err := e.pool.QueryRow(ctx, `
		SELECT count(*) FROM media_files f JOIN storage_locations l ON f.storage_location_id = l.id
		WHERE l.library_id = $1 AND f.probe_attempts > 0`, libraryID).Scan(&left); err != nil {
		t.Fatal(err)
	}
	if left != 0 {
		t.Fatalf("%d bestanden houden probe_attempts > 0 na retry", left)
	}
}
