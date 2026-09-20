package testsupport

import (
	"context"
	_ "embed"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// NASFixtureSchema is de schemaversie waarop de vangst is gemaakt. De fixture
// bevat alleen rijen, geen DDL: hij hoort geladen te worden op een database die
// precies op deze versie staat, en de migratietest brengt hem daarna omhoog.
const NASFixtureSchema = 7

//go:embed fixtures/nas-schema7.sql
var nasFixtureSQL string

// NASFixture is de geanonimiseerde vangst van de draaiende NAS, als een enkel
// SQL-blok met INSERT-statements in afhankelijkheidsvolgorde.
func NASFixture() string { return nasFixtureSQL }

// LoadNASFixture zet de fixture in het schema waar de pool naar wijst. De
// aanroeper zorgt dat de database op NASFixtureSchema staat; staat hij hoger of
// lager, dan is dat een fout van de test en niet van de fixture.
func LoadNASFixture(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	if _, err := pool.Exec(context.Background(), nasFixtureSQL); err != nil {
		t.Fatalf("NAS-fixture laden: %v", err)
	}
}
