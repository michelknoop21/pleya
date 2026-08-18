// Package testsupport geeft tests een wegwerpdatabase.
//
// De integratietests draaien tegen een echte Postgres in dezelfde gepinde versie
// als de productiestack. Staat er geen database klaar, dan slaan ze zichzelf
// over in plaats van te falen: `go test ./...` moet ook werken op een machine
// waar scripts/test-db.sh niet gedraaid is.
package testsupport

import (
	"context"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// EnvDatabaseURL is de omgevingsvariabele die scripts/test-db.sh zet.
const EnvDatabaseURL = "PLEYA_TEST_DATABASE_URL"

var schemaCounter int64

// Pool geeft een pool die naar een vers, leeg schema wijst en dat schema aan het
// eind weer weggooit. Elke test krijgt zo een eigen naamruimte zonder dat er een
// database per test opgestart hoeft te worden.
func Pool(t *testing.T) *pgxpool.Pool {
	t.Helper()

	dsn := strings.TrimSpace(os.Getenv(EnvDatabaseURL))
	if dsn == "" {
		t.Skipf("%s is niet gezet; draai eval \"$(scripts/test-db.sh up)\"", EnvDatabaseURL)
	}

	schemaCounter++
	schema := fmt.Sprintf("t_%d_%d", time.Now().UnixNano(), schemaCounter)

	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatalf("dsn: %v", err)
	}
	cfg.MaxConns = 4
	cfg.ConnConfig.RuntimeParams["search_path"] = schema

	ctx := context.Background()

	admin, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("adminpool: %v", err)
	}
	defer admin.Close()

	if _, err := admin.Exec(ctx, "CREATE SCHEMA "+schema); err != nil {
		t.Fatalf("schema aanmaken: %v", err)
	}

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}

	t.Cleanup(func() {
		pool.Close()
		cleanup, err := pgxpool.New(context.Background(), dsn)
		if err != nil {
			return
		}
		defer cleanup.Close()
		_, _ = cleanup.Exec(context.Background(), "DROP SCHEMA IF EXISTS "+schema+" CASCADE")
	})

	return pool
}
