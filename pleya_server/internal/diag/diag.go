// Package diag levert de meetwaarden die het beheerscherm van GET /server
// vraagt: de databaseversie, de schemaversie en de stand van de wachtrij.
//
// Het staat los van internal/api omdat de HTTP-laag geen databasepool kent en
// dat zo hoort te blijven: alles wat daar praat gaat via een store met een
// eigen verantwoordelijkheid. Dit is die store voor diagnostiek, en meer dan
// tellen doet hij niet.
//
// Geen van deze waarden is een geheim, en dat is bij het schrijven van elke
// query de toets: K rij 15 zegt dat een beheerantwoord geen DSN, sleutel of
// token draagt, dus de databaseversie komt hier binnen als versie en niet als
// verbindingsstring.
package diag

import (
	"context"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Snapshot is één meting.
type Snapshot struct {
	// DatabaseVersion is het versienummer van Postgres, zonder de
	// distributieregel erachter: "18.6" en niet "18.6 (Debian 18.6-1.pgdg13+1)".
	DatabaseVersion string

	// SchemaVersion is de hoogste toegepaste migratie. Dat is het getal dat
	// ertoe doet bij een meldingsonderzoek: de binary weigert te starten op een
	// nieuwer schema, dus een verschil met de verwachting is meteen de oorzaak.
	SchemaVersion int

	JobsRunning int
	JobsFailed  int
}

// Store leest de meting uit dezelfde pool als de rest van de server.
type Store struct{ pool *pgxpool.Pool }

func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// Read doet één ronde naar de database.
//
// Vier waarden in één query en niet vier queries: het antwoord hoort één
// moment te beschrijven. Twee tellingen uit verschillende rondes kunnen een
// wachtrij tonen die nooit zo geweest is, en dat is precies het soort
// tegenstrijdigheid waar een beheerder achteraan gaat zoeken.
func (s *Store) Read(ctx context.Context) (Snapshot, error) {
	const query = `
		SELECT current_setting('server_version'),
		       (SELECT coalesce(max(version), 0) FROM schema_migrations),
		       (SELECT count(*) FROM jobs WHERE state = 'running'),
		       (SELECT count(*) FROM jobs WHERE state = 'failed')`

	var out Snapshot
	var version string
	var running, failed int64
	if err := s.pool.QueryRow(ctx, query).Scan(&version, &out.SchemaVersion, &running, &failed); err != nil {
		return Snapshot{}, fmt.Errorf("diagnostiek lezen: %w", err)
	}

	out.DatabaseVersion = strings.TrimSpace(strings.Fields(version+" ")[0])
	out.JobsRunning = int(running)
	out.JobsFailed = int(failed)
	return out, nil
}
