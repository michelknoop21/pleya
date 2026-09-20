package migrate_test

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// De migratietest uit J.7. Een leeg schema bewijst niet dat een migratie een
// gevulde installatie overleeft: de rijen die eroverheen moeten zijn er niet, dus
// een kolom die niet nullable mag zijn, een backfill die op een lege tabel klopt
// en een constraint die alleen op echte data bijt komen er nooit uit. Deze test
// zet de database op de versie die op de NAS draait, laadt de geanonimiseerde
// vangst daarvan, migreert door naar de huidige versie en eist dat de identiteit
// en de telling er onveranderd doorheen komen.
//
// Zolang de NAS-versie en de codeversie gelijk zijn is de migratiestap zelf leeg.
// Dat maakt de test niet zinloos maar wel beperkt, en het is precies de reden dat
// hij nu al bestaat: hij is de plek waar 0008 en verder hun bewijs neerleggen, en
// hij bewaakt vandaag al dat de fixture laadbaar en compleet blijft.

type snapshot struct {
	libraries map[string]string // id -> slug
	items     map[string]int    // library_id -> aantal
	watch     map[string]int64  // item_id -> position_ms
	counts    map[string]int
}

func take(t *testing.T, ctx context.Context, pool *pgxpool.Pool) snapshot {
	t.Helper()
	s := snapshot{
		libraries: map[string]string{},
		items:     map[string]int{},
		watch:     map[string]int64{},
		counts:    map[string]int{},
	}

	rows, err := pool.Query(ctx, `SELECT id::text, slug FROM libraries`)
	if err != nil {
		t.Fatalf("libraries lezen: %v", err)
	}
	for rows.Next() {
		var id, slug string
		if err := rows.Scan(&id, &slug); err != nil {
			t.Fatal(err)
		}
		s.libraries[id] = slug
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}

	rows, err = pool.Query(ctx, `SELECT library_id::text, count(*) FROM media_items GROUP BY library_id`)
	if err != nil {
		t.Fatalf("item_count lezen: %v", err)
	}
	for rows.Next() {
		var id string
		var n int
		if err := rows.Scan(&id, &n); err != nil {
			t.Fatal(err)
		}
		s.items[id] = n
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}

	rows, err = pool.Query(ctx, `SELECT item_id::text, position_ms FROM watch_states`)
	if err != nil {
		t.Fatalf("watch_states lezen: %v", err)
	}
	for rows.Next() {
		var id string
		var pos int64
		if err := rows.Scan(&id, &pos); err != nil {
			t.Fatal(err)
		}
		s.watch[id] = pos
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}

	for _, tbl := range []string{
		"media_items", "media_versions", "media_files", "media_streams",
		"storage_locations", "users", "sessions", "auth_refresh_tokens",
		"jobs", "scan_runs",
	} {
		var n int
		if err := pool.QueryRow(ctx, `SELECT count(*) FROM `+tbl).Scan(&n); err != nil {
			t.Fatalf("%s tellen: %v", tbl, err)
		}
		s.counts[tbl] = n
	}
	return s
}

func TestNASFixtureSurvivesMigrationToHead(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()

	start, err := migrate.RunTo(ctx, pool, nil, testsupport.NASFixtureSchema)
	if err != nil {
		t.Fatalf("naar schema %d migreren: %v", testsupport.NASFixtureSchema, err)
	}
	if start.To != testsupport.NASFixtureSchema {
		t.Fatalf("database staat op %d, verwacht %d", start.To, testsupport.NASFixtureSchema)
	}

	testsupport.LoadNASFixture(t, pool)
	before := take(t, ctx, pool)

	if len(before.libraries) == 0 || len(before.watch) == 0 || before.counts["media_items"] == 0 {
		t.Fatal("de fixture laadde leeg; dan bewijst de rest van deze test niets")
	}

	target, err := migrate.Target()
	if err != nil {
		t.Fatalf("Target: %v", err)
	}
	res, err := migrate.Run(ctx, pool, nil)
	if err != nil {
		t.Fatalf("migreren op een gevulde database: %v", err)
	}
	if res.From != testsupport.NASFixtureSchema || res.To != target {
		t.Fatalf("migratie ging van %d naar %d, verwacht %d naar %d",
			res.From, res.To, testsupport.NASFixtureSchema, target)
	}

	after := take(t, ctx, pool)

	// Identiteit. Een bibliotheek die zijn id of slug verliest breekt elke client
	// die hem bewaard heeft, en dat is precies wat een migratie stil kan doen.
	if len(after.libraries) != len(before.libraries) {
		t.Fatalf("aantal bibliotheken ging van %d naar %d", len(before.libraries), len(after.libraries))
	}
	for id, slug := range before.libraries {
		got, ok := after.libraries[id]
		if !ok {
			t.Errorf("bibliotheek %s bestaat niet meer", id)
			continue
		}
		if got != slug {
			t.Errorf("bibliotheek %s heet nu %q in plaats van %q", id, got, slug)
		}
	}

	// item_count per bibliotheek.
	for id, n := range before.items {
		if after.items[id] != n {
			t.Errorf("bibliotheek %s had %d items en heeft er nu %d", id, n, after.items[id])
		}
	}

	// Kijkstatus. De server is er eigenaar van (DEC-049), dus een migratie mag er
	// geen enkele positie van kwijtraken of verschuiven.
	if len(after.watch) != len(before.watch) {
		t.Errorf("watch_states ging van %d naar %d rijen", len(before.watch), len(after.watch))
	}
	for id, pos := range before.watch {
		got, ok := after.watch[id]
		if !ok {
			t.Errorf("kijkstatus voor %s is weg", id)
			continue
		}
		if got != pos {
			t.Errorf("kijkstatus voor %s stond op %d en staat nu op %d", id, pos, got)
		}
	}

	// Tellingen. Geen enkele tabel mag rijen verliezen; erbij mag wel, want een
	// migratie met een backfill doet dat per definitie.
	for tbl, n := range before.counts {
		if after.counts[tbl] < n {
			t.Errorf("%s ging van %d naar %d rijen", tbl, n, after.counts[tbl])
		}
	}

	// Het equivalent van readyz: de database staat op de versie die de binary wil.
	var version int
	if err := pool.QueryRow(ctx, `SELECT max(version) FROM schema_migrations`).Scan(&version); err != nil {
		t.Fatalf("schemaversie lezen: %v", err)
	}
	if version != target {
		t.Errorf("schema staat op %d, de binary wil %d", version, target)
	}
}

// De fixture is een steekproef en geen volledige dump, dus zijn waarde zit in de
// vormen die erin zitten. Deze test legt die vormen vast: raakt er een uit de
// steekproef, dan dekt de migratietest hierboven minder dan hij lijkt te dekken,
// en dat hoort op te vallen bij het vernieuwen van de vangst.
func TestNASFixtureCoversTheShapesItWasSampledFor(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()

	if _, err := migrate.RunTo(ctx, pool, nil, testsupport.NASFixtureSchema); err != nil {
		t.Fatalf("naar schema %d migreren: %v", testsupport.NASFixtureSchema, err)
	}
	testsupport.LoadNASFixture(t, pool)

	checks := []struct {
		naam  string
		query string
		min   int
	}{
		{"alle vier de itemsoorten", `SELECT count(DISTINCT kind) FROM media_items`, 4},
		{"meer dan een bibliotheek", `SELECT count(*) FROM libraries`, 2},
		{"een niet-vertrouwde opslaglocatie", `SELECT count(*) FROM storage_locations WHERE NOT inode_trusted`, 1},
		{"een container die geen mkv is", `SELECT count(*) FROM media_versions WHERE container <> 'mkv'`, 1},
		{"een bestand dat verdwenen is", `SELECT count(*) FROM media_files WHERE missing_since IS NOT NULL`, 1},
		{"artwork naast media en ondertitels", `SELECT count(DISTINCT role) FROM media_files`, 3},
		{"alle drie de streamsoorten", `SELECT count(DISTINCT kind) FROM media_streams`, 3},
		{"een item zonder jaar", `SELECT count(*) FROM media_items WHERE year IS NULL`, 1},
		{"een versie met meer dan vier bestanden", `
			SELECT count(*) FROM (
				SELECT version_id FROM media_files WHERE version_id IS NOT NULL
				GROUP BY version_id HAVING count(*) > 4
			) x`, 1},
		{"een ingetrokken refreshtoken", `SELECT count(*) FROM auth_refresh_tokens WHERE revoked_at IS NOT NULL`, 1},
		{"een rotatieketen met replaced_by", `SELECT count(*) FROM auth_refresh_tokens WHERE replaced_by IS NOT NULL`, 1},
		{"kijkstatus", `SELECT count(*) FROM watch_states`, 1},
		{"een sessie", `SELECT count(*) FROM sessions`, 1},
	}

	for _, c := range checks {
		var n int
		if err := pool.QueryRow(ctx, c.query).Scan(&n); err != nil {
			t.Fatalf("%s: %v", c.naam, err)
		}
		if n < c.min {
			t.Errorf("%s: %d gevonden, minstens %d verwacht", c.naam, n, c.min)
		}
	}
}
