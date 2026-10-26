package backup

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/database"
)

// transientTables zijn de tabellen waarvan de rijen niet in een back-up horen.
// De wachtrij is werkvoorraad: een teruggezette lopende back-upjob zou na de
// herstart opnieuw draaien. Het register van back-ups en hersteltests hoort bij
// de map en niet bij het moment van de dump (zie het pakketcommentaar). De
// tabellen zelf gaan wel mee, alleen hun inhoud niet.
var transientTables = []string{"jobs", "backups", "backup_restore_tests"}

// pgEnv is de omgeving voor pg_dump en psql: de verbindingsgegevens van de pool,
// naar een gekozen database. Het wachtwoord gaat in PGPASSWORD en nooit op de
// commandoregel, want die is voor elk proces in de container leesbaar.
func (s *Service) pgEnv(databaseName string) []string {
	cfg := s.o.Pool.Config().ConnConfig
	env := []string{
		"PGHOST=" + cfg.Host,
		"PGPORT=" + strconv.Itoa(int(cfg.Port)),
		"PGUSER=" + cfg.User,
		"PGDATABASE=" + databaseName,
		"PGCONNECT_TIMEOUT=10",
		"PGAPPNAME=pleya-backup",
		// De NOTICE's van DROP SCHEMA ... CASCADE zeggen niets wat het log niet
		// al weet, en ze verdringen de ene foutregel die er wel toe doet.
		"PGOPTIONS=-c client_min_messages=warning",
		"PATH=" + os.Getenv("PATH"),
		"LC_ALL=C",
	}
	if cfg.Password != "" {
		env = append(env, "PGPASSWORD="+cfg.Password)
	}
	if cfg.TLSConfig == nil {
		env = append(env, "PGSSLMODE=disable")
	} else {
		env = append(env, "PGSSLMODE=require")
	}
	return env
}

// liveDatabase is de naam van de database waar de server zelf op draait.
func (s *Service) liveDatabase() string { return s.o.Pool.Config().ConnConfig.Database }

// recordingWriter onthoudt de eerste schrijffout. exec meldt bij een kapotte
// uitvoer het afgebroken proces en niet de oorzaak, en de oorzaak (ENOSPC) is
// precies wat het faalpad "schijf vol" moet herkennen.
type recordingWriter struct {
	w   io.Writer
	err error
}

func (r *recordingWriter) Write(p []byte) (int, error) {
	n, err := r.w.Write(p)
	if err != nil && r.err == nil {
		r.err = err
	}
	return n, err
}

// dump schrijft een SQL-dump van schema naar w, in de snapshot die de aanroeper
// exporteerde. pg_trgm gaat expliciet mee: de extensie hoort bij de database en
// niet bij het schema (0017), en zonder haar faalt het terugzetten van de
// trigramindexen op een lege database.
//
// Alleen als de extensie er is: migratie 0017 maakt haar aan, en de back-up
// vóór de migratie van een oudere database (de upgradeguard) heeft haar nog
// niet. pg_dump weigert dan met "no matching extensions were found" en de
// server start niet. Zo'n dump heeft ook geen trigramindexen die haar nodig
// hebben; 0017 maakt de extensie bij het terugzetten en migreren zelf weer aan.
func (s *Service) dump(ctx context.Context, schema, snapshot string, w io.Writer) error {
	args := []string{"--format=plain", "--no-owner", "--no-privileges", "--schema=" + schema}
	has, err := s.hasTrigramExtension(ctx)
	if err != nil {
		return err
	}
	if has {
		args = append(args, "--extension=pg_trgm")
	}
	args = append(args, "--snapshot="+snapshot)
	for _, t := range transientTables {
		args = append(args, "--exclude-table-data="+schema+"."+t)
	}
	cmd := exec.CommandContext(ctx, s.o.PgDump, args...)
	cmd.Env = s.pgEnv(s.liveDatabase())
	out := &recordingWriter{w: w}
	cmd.Stdout = out
	var stderr bytes.Buffer
	cmd.Stderr = &limitedBuffer{buf: &stderr, max: 4096}
	err = cmd.Run()
	if out.err != nil {
		return fmt.Errorf("dump wegschrijven: %w", out.err)
	}
	if err != nil {
		return toolError("pg_dump", err, stderr.String())
	}
	return nil
}

func (s *Service) hasTrigramExtension(ctx context.Context) (bool, error) {
	var has bool
	err := s.o.Pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm')`).Scan(&has)
	if err != nil {
		return false, fmt.Errorf("extensies lezen: %w", err)
	}
	return has, nil
}

// load zet een dump terug in databaseName, in één transactie: eerst het schema
// weg, dan de dump, die het schema zelf weer aanmaakt. Faalt er een regel, dan
// stopt psql en rolt alles terug.
//
// De invoer wordt zelf gekopieerd en niet aan exec overgelaten. psql commit bij
// het einde van zijn invoer, ook als die invoer halverwege afbrak: een gzip die
// stukgaat zou zonder deze lus een half teruggezet schema opleveren. Bij een
// leesfout wordt psql daarom gedood vóór de invoer sluit, en dan ziet Postgres
// een verbroken verbinding en rolt hij terug.
func (s *Service) load(ctx context.Context, databaseName, schema string, dump io.Reader) error {
	cmd := exec.CommandContext(ctx, s.o.Psql,
		"--no-psqlrc", "--quiet", "--single-transaction", "--set=ON_ERROR_STOP=1", "--output=/dev/null")
	cmd.Env = s.pgEnv(databaseName)
	var stderr bytes.Buffer
	cmd.Stderr = &limitedBuffer{buf: &stderr, max: 4096}
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return toolError("psql", err, "")
	}
	preamble := "DROP SCHEMA IF EXISTS " + pgx.Identifier{schema}.Sanitize() + " CASCADE;\n"
	_, copyErr := io.Copy(stdin, io.MultiReader(strings.NewReader(preamble), dump, strings.NewReader(memoryRestoreFence(schema))))
	if copyErr != nil {
		_ = cmd.Process.Kill()
		_ = stdin.Close()
		_ = cmd.Wait()
		return fmt.Errorf("dump lezen: %w", copyErr)
	}
	if err := stdin.Close(); err != nil {
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
		return err
	}
	if err := cmd.Wait(); err != nil {
		return toolError("psql", err, stderr.String())
	}
	return nil
}

// toolError maakt van een mislukte pg_dump of psql een fout met de laatste
// regel van stderr erbij. Een tool die de server niet kon bereiken wordt
// database.ErrUnavailable, zodat het faalpad "database weg" zijn eigen code
// krijgt; de tools melden dat alleen in tekst.
func toolError(tool string, err error, stderr string) error {
	text := strings.TrimSpace(stderr)
	if i := strings.LastIndex(text, "\n"); i >= 0 {
		text = text[i+1:]
	}
	if strings.Contains(stderr, "connection to server") || strings.Contains(stderr, "could not connect") ||
		strings.Contains(stderr, "could not translate host name") {
		return fmt.Errorf("%s: %w: %s", tool, database.ErrUnavailable, text)
	}
	if text == "" {
		return fmt.Errorf("%s: %w", tool, err)
	}
	return fmt.Errorf("%s: %v: %s", tool, err, text)
}

// limitedBuffer houdt de eerste max bytes van stderr vast. Een psql die op elke
// regel van een dump klaagt, hoort het geheugen niet te vullen.
type limitedBuffer struct {
	buf *bytes.Buffer
	max int
}

func (l *limitedBuffer) Write(p []byte) (int, error) {
	if room := l.max - l.buf.Len(); room > 0 {
		if len(p) > room {
			l.buf.Write(p[:room])
		} else {
			l.buf.Write(p)
		}
	}
	return len(p), nil
}

// memoryRestoreFence maakt herstelde feiten herkenbaar vóór dezelfde psql-transactie
// commit. Ook een restore die daarna faalt bij /config kan nooit de oude epoch aanbieden.
func memoryRestoreFence(schema string) string {
	literal := strings.ReplaceAll(schema, "'", "''")
	return "\nSELECT format('UPDATE %I.assistant_memory_states SET epoch = gen_random_uuid()', nspname) FROM pg_namespace WHERE nspname = '" + literal + "' AND to_regclass(format('%I.assistant_memory_states', nspname)) IS NOT NULL\n\\gexec\n"
}
