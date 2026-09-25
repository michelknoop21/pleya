package api_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

// POST /libraries/{id}/scan en de leesendpoints van S2.4 (J.3 venster 2).

func TestStartScanQueuesARunAndRefusesASecond(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	lib := e.createLibraryViaAPI(t, "Scanbaar", "movies", []string{"/media/scan"})

	rec := e.do(http.MethodPost, "/pleya/v1/libraries/"+lib.ID+"/scan", nil)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("POST scan gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("Scan", http.MethodPost, "/pleya/v1/libraries/{library_id}/scan", rec)
	var scan struct {
		ID    string `json:"id"`
		State string `json:"state"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &scan); err != nil {
		t.Fatal(err)
	}
	if scan.State != "queued" {
		t.Fatalf("nieuwe scan staat op %q", scan.State)
	}

	again := e.do(http.MethodPost, "/pleya/v1/libraries/"+lib.ID+"/scan", nil)
	if again.Code != http.StatusConflict || errorCode(t, again) != "library.scan_in_progress" {
		t.Fatalf("tweede POST gaf %d %s", again.Code, again.Body.String())
	}
	e.recordVariant("ErrorEnvelope", "scan_in_progress", http.MethodPost, "/pleya/v1/libraries/{library_id}/scan", again)

	one := e.do(http.MethodGet, "/pleya/v1/scans/"+scan.ID, nil)
	if one.Code != http.StatusOK {
		t.Fatalf("GET scan gaf %d", one.Code)
	}
	e.record("Scan", http.MethodGet, "/pleya/v1/scans/{scan_id}", one)

	list := e.do(http.MethodGet, "/pleya/v1/scans?library_id="+lib.ID+"&limit=1", nil)
	if list.Code != http.StatusOK {
		t.Fatalf("GET scans gaf %d", list.Code)
	}
	e.record("ScanPage", http.MethodGet, "/pleya/v1/scans", list)
	if !strings.Contains(list.Body.String(), scan.ID) {
		t.Fatalf("lijst mist de nieuwe scan: %s", list.Body.String())
	}
}
