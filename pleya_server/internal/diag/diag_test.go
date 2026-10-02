package diag_test

import (
	"context"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/diag"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// De meting komt van een echte database. Een test met een nagemaakte pool zou
// bewijzen dat het Go-type klopt en niets over de query, en juist daar zit het
// risico: current_setting en de FILTER-vorm zijn Postgres en geen Go.
func TestReadCountsJobsAndSchema(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()

	result, err := migrate.Run(ctx, pool, nil)
	if err != nil {
		t.Fatalf("migreren: %v", err)
	}

	for _, state := range []string{"running", "running", "failed", "succeeded", "pending"} {
		if _, err := pool.Exec(ctx,
			`INSERT INTO jobs (id, kind, state) VALUES ($1, 'scan_library', $2)`,
			id.New(), state); err != nil {
			t.Fatalf("job %s: %v", state, err)
		}
	}

	got, err := diag.NewStore(pool).Read(ctx)
	if err != nil {
		t.Fatalf("lezen: %v", err)
	}

	if got.SchemaVersion != result.To {
		t.Errorf("schema = %d, de migratie kwam op %d", got.SchemaVersion, result.To)
	}
	if got.JobsRunning != 2 {
		t.Errorf("jobs_running = %d, verwacht 2", got.JobsRunning)
	}
	if got.JobsFailed != 1 {
		t.Errorf("jobs_failed = %d, verwacht 1", got.JobsFailed)
	}
	// Alleen het versienummer, want de distributieregel erachter zegt welke
	// image er draait en dat hoort niet in een antwoord aan een client.
	if got.DatabaseVersion == "" {
		t.Fatal("geen databaseversie")
	}
	for _, unwanted := range []string{" ", "(", "Debian"} {
		if strings.Contains(got.DatabaseVersion, unwanted) {
			t.Errorf("databaseversie %q draagt meer dan het nummer", got.DatabaseVersion)
		}
	}
}
