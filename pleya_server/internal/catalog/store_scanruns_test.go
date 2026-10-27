package catalog_test

import (
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// TestFailAbandonedScanRunsClosesOnlyRunningRuns: een ronde die na een herstart nog
// "running" is, is van een proces dat er niet meer is. Alleen die wordt afgesloten;
// een wachtende ronde is van een job, en afgeronde rondes blijven zoals ze waren.
func TestFailAbandonedScanRunsClosesOnlyRunningRuns(t *testing.T) {
	f := filterLibrary(t, "movies")

	orphan, err := f.store.StartScanRun(f.ctx, f.lib, "startup")
	if err != nil {
		t.Fatal(err)
	}
	// Een ronde die al een fout had, houdt die: de oorzaak van de scan is
	// belangrijker dan de oorzaak van het afbreken.
	withError, err := f.store.StartScanRun(f.ctx, f.lib, "schedule")
	if err != nil {
		t.Fatal(err)
	}
	if err := f.store.UpdateScanProgress(f.ctx, withError, catalog.ScanCounters{FilesSeen: 12, Errors: 1, LastError: "root onleesbaar"}); err != nil {
		t.Fatal(err)
	}
	queued, err := f.store.CreateQueuedScanRun(f.ctx, f.lib, "manual")
	if err != nil {
		t.Fatal(err)
	}
	done, err := f.store.StartScanRun(f.ctx, f.lib, "startup")
	if err != nil {
		t.Fatal(err)
	}
	if err := f.store.FinishScanRun(f.ctx, done, "succeeded", catalog.ScanCounters{FilesSeen: 5}); err != nil {
		t.Fatal(err)
	}

	n, err := f.store.FailAbandonedScanRuns(f.ctx)
	if err != nil {
		t.Fatal(err)
	}
	if n != 2 {
		t.Fatalf("%d rondes afgesloten, verwacht 2 (de twee die nog liepen)", n)
	}

	check := func(name string, runID id.ID, state string, finished bool, lastError string) {
		t.Helper()
		run, err := f.store.ScanRun(f.ctx, runID)
		if err != nil {
			t.Fatal(err)
		}
		if run.State != state || (run.FinishedAt != nil) != finished || run.LastError != lastError {
			t.Errorf("%s: state %q, eindtijd %v, laatste fout %q; verwacht %q, eindtijd %v, %q",
				name, run.State, run.FinishedAt, run.LastError, state, finished, lastError)
		}
	}
	check("achtergebleven", orphan, "failed", true, "server gestopt tijdens de scan")
	check("met eigen fout", withError, "failed", true, "root onleesbaar")
	check("wachtend", queued, "queued", false, "")
	check("afgerond", done, "succeeded", true, "")

	if again, err := f.store.FailAbandonedScanRuns(f.ctx); err != nil || again != 0 {
		t.Fatalf("tweede keer: %d rondes, %v; verwacht 0", again, err)
	}
}
