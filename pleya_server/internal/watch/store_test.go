package watch_test

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	"github.com/edde746/plezy/pleya_server/internal/watch"
)

var when = time.Date(2026, 8, 21, 20, 0, 0, 0, time.UTC)

// createUser zet rechtstreeks een gebruikersrij neer.
//
// Niet via een endpoint: het gebruikersbeheer-API van stap 4 bestaat hier nog
// niet, en watch_states.subject is sinds migratie 0007 een echte FK naar
// users(id) (DEC-065), dus elke test die een subject nodig heeft moet een
// echte rij hebben om naar te verwijzen.
func createUser(t *testing.T, pool *pgxpool.Pool, username, role string) string {
	t.Helper()

	uid := id.New()
	if _, err := pool.Exec(context.Background(),
		`INSERT INTO users (id, username, password_hash, role) VALUES ($1, $2, 'x', $3)`,
		uid, username, role); err != nil {
		t.Fatalf("gebruiker %q aanmaken: %v", username, err)
	}
	return uid.String()
}

// fixture zet een gemigreerde database met één film en één gebruiker erin
// neer.
//
// De item-rij is echt en geen losse uuid: watch_states heeft een foreign key
// naar media_items, en een test die die sleutel omzeilt bewijst niets over het
// gedrag dat de server straks vertoont. Hetzelfde geldt sinds migratie 0007
// voor het subject.
func fixture(t *testing.T) (*pgxpool.Pool, *watch.Store, id.ID, string) {
	t.Helper()

	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}

	store := catalog.NewStore(pool)
	libs, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{
		{Slug: "films", Title: "Films", Kind: "movies", Roots: []catalog.RootSpec{
			{Path: t.TempDir(), FSType: "tmpfs", InodeTrusted: true, TrustSource: "fstype_default"}}},
	})
	if err != nil {
		t.Fatalf("bibliotheken: %v", err)
	}

	itemID, _, err := store.ResolveItem(ctx, catalog.ItemRef{
		LibraryID: libs[0].ID, Kind: "movie", GroupingKey: "grease-1978", Title: "Grease",
	})
	if err != nil {
		t.Fatalf("item: %v", err)
	}

	subject := createUser(t, pool, "wietske", "owner")
	return pool, watch.NewStore(pool), itemID, subject
}

func rev(v int64) *int64 { return &v }

// TestApplyPersistsAndReadsBack is de ronde die elke andere test aanneemt.
func TestApplyPersistsAndReadsBack(t *testing.T) {
	_, store, itemID, subject := fixture(t)
	ctx := context.Background()

	out, err := store.Apply(ctx, subject, itemID, watch.Event{
		SessionID: "tv", Action: watch.ActionPlaybackStarted, Cause: watch.CauseUserStarted,
	}, when, watch.MinLease)
	if err != nil {
		t.Fatal(err)
	}
	if !out.Accepted || out.Next.Revision != 1 {
		t.Fatalf("eerste event: %+v", out)
	}

	progress, err := store.Apply(ctx, subject, itemID, watch.Event{
		SessionID: "tv", PositionMs: 1_800_000, BaseRevision: rev(1),
	}, when.Add(time.Second), watch.MinLease)
	if err != nil {
		t.Fatal(err)
	}
	if !progress.Accepted || progress.Next.PositionMs != 1_800_000 {
		t.Fatalf("voortgang: %+v", progress)
	}

	got, err := store.Get(ctx, subject, itemID)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Exists || got.PositionMs != 1_800_000 || got.Revision != 2 {
		t.Fatalf("uit de database: %+v", got)
	}
	if got.OwnerSessionID != "tv" {
		t.Fatalf("eigenaar is %q", got.OwnerSessionID)
	}
}

// TestApplyOnUnknownItemIsNotFound: de foreign key mag nooit de foutmelding zijn
// die een client te zien krijgt.
func TestApplyOnUnknownItemIsNotFound(t *testing.T) {
	_, store, _, subject := fixture(t)

	_, err := store.Apply(context.Background(), subject, id.New(), watch.Event{
		SessionID: "tv", Action: watch.ActionPlaybackStarted, Cause: watch.CauseUserStarted,
	}, when, watch.MinLease)
	if err != watch.ErrItemNotFound {
		t.Fatalf("fout is %v, wil ErrItemNotFound", err)
	}
}

// TestRejectedEventLeavesNoRow: een geweigerd event op een onaangeraakt item
// laat geen lege rij achter, en telt dus niet mee in GET /watch-state.
func TestRejectedEventLeavesNoRow(t *testing.T) {
	_, store, itemID, subject := fixture(t)
	ctx := context.Background()

	out, err := store.Apply(ctx, subject, itemID, watch.Event{
		SessionID: "telefoon", PositionMs: 5000,
	}, when, watch.MinLease)
	if err != nil {
		t.Fatal(err)
	}
	if out.Accepted {
		t.Fatal("een passief event zonder eigenaar werd geaccepteerd")
	}

	got, err := store.Get(ctx, subject, itemID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Exists {
		t.Fatal("er staat een rij voor een item dat niemand heeft aangeraakt")
	}
}

// TestConcurrentEventsSerialiseOnTheRow is de reden dat Apply een transactie met
// FOR UPDATE is.
//
// Twee sessies schrijven tegelijk met dezelfde base_revision. Precies één mag
// slagen: zonder de rijvergrendeling lezen ze allebei dezelfde revision, tellen
// ze er allebei eentje bij op, en dan is de causaliteitsclaim uit regel 3
// waardeloos.
func TestConcurrentEventsSerialiseOnTheRow(t *testing.T) {
	_, store, itemID, subject := fixture(t)
	ctx := context.Background()

	if _, err := store.Apply(ctx, subject, itemID, watch.Event{
		SessionID: "tv", Action: watch.ActionPlaybackStarted, Cause: watch.CauseUserStarted,
	}, when, watch.MinLease); err != nil {
		t.Fatal(err)
	}

	var wg sync.WaitGroup
	results := make([]watch.Outcome, 2)
	errs := make([]error, 2)
	sessions := []string{"tv", "telefoon"}

	for i := range results {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			results[i], errs[i] = store.Apply(ctx, subject, itemID, watch.Event{
				SessionID: sessions[i], PositionMs: int64(1000 * (i + 1)),
				Action: watch.ActionMarkWatched, BaseRevision: rev(1),
			}, when.Add(time.Second), watch.MinLease)
		}(i)
	}
	wg.Wait()

	for i, err := range errs {
		if err != nil {
			t.Fatalf("schrijving %d: %v", i, err)
		}
	}

	final, err := store.Get(ctx, subject, itemID)
	if err != nil {
		t.Fatal(err)
	}
	// Beide zijn expliciete handelingen, dus beide slagen (regel 5), maar ze
	// gaan achter elkaar en de revision loopt met twee op in plaats van met een.
	if final.Revision != 3 {
		t.Fatalf("revision is %d, wil 3; dan liepen de twee schrijvingen door elkaar", final.Revision)
	}
}

// TestListPagesAndFilters dekt de leeskant met cursor en updated_since.
func TestListPagesAndFilters(t *testing.T) {
	pool, store, first, subject := fixture(t)
	ctx := context.Background()

	// Nog twee items, zodat er iets te pagineren valt.
	catalogStore := catalog.NewStore(pool)
	var libraryID id.ID
	if err := pool.QueryRow(ctx, `SELECT id FROM libraries LIMIT 1`).Scan(&libraryID); err != nil {
		t.Fatal(err)
	}
	ids := []id.ID{first}
	for _, key := range []string{"matrix-1999", "blade-runner-1982"} {
		itemID, _, err := catalogStore.ResolveItem(ctx, catalog.ItemRef{
			LibraryID: libraryID, Kind: "movie", GroupingKey: key, Title: key,
		})
		if err != nil {
			t.Fatal(err)
		}
		ids = append(ids, itemID)
	}

	for i, itemID := range ids {
		if _, err := store.Apply(ctx, subject, itemID, watch.Event{
			SessionID: "tv", Action: watch.ActionPlaybackStarted, Cause: watch.CauseUserStarted,
		}, when.Add(time.Duration(i)*time.Minute), watch.MinLease); err != nil {
			t.Fatal(err)
		}
	}

	page, err := store.List(ctx, subject, nil, 2, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Entries) != 2 || page.NextCursor == "" {
		t.Fatalf("eerste pagina: %d regels, cursor %q", len(page.Entries), page.NextCursor)
	}
	if page.Entries[0].ItemID != ids[2] {
		t.Fatal("de lijst staat niet op updated_at aflopend")
	}

	second, err := store.List(ctx, subject, nil, 2, page.NextCursor)
	if err != nil {
		t.Fatal(err)
	}
	if len(second.Entries) != 1 || second.NextCursor != "" {
		t.Fatalf("tweede pagina: %d regels, cursor %q", len(second.Entries), second.NextCursor)
	}

	seen := map[id.ID]bool{}
	for _, e := range append(page.Entries, second.Entries...) {
		if seen[e.ItemID] {
			t.Fatalf("%s kwam twee keer langs", e.ItemID)
		}
		seen[e.ItemID] = true
	}
	if len(seen) != 3 {
		t.Fatalf("%d unieke regels over twee pagina's", len(seen))
	}

	since := when.Add(30 * time.Second)
	filtered, err := store.List(ctx, subject, &since, 10, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(filtered.Entries) != 2 {
		t.Fatalf("updated_since leverde %d regels, wil 2", len(filtered.Entries))
	}

	if _, err := store.List(ctx, subject, nil, 10, "geen-geldige-cursor"); err != watch.ErrCursorInvalid {
		t.Fatalf("een kapotte cursor gaf %v", err)
	}
}

// TestForItemsIsOneRound dekt de weg waarlangs elk itemantwoord zijn kijkstatus
// krijgt.
func TestForItemsIsOneRound(t *testing.T) {
	_, store, itemID, subject := fixture(t)
	ctx := context.Background()

	if _, err := store.Apply(ctx, subject, itemID, watch.Event{
		SessionID: "tv", Action: watch.ActionPlaybackStarted, Cause: watch.CauseUserStarted,
	}, when, watch.MinLease); err != nil {
		t.Fatal(err)
	}

	states, err := store.ForItems(ctx, subject, []id.ID{itemID, id.New()})
	if err != nil {
		t.Fatal(err)
	}
	if len(states) != 1 {
		t.Fatalf("%d toestanden, wil 1", len(states))
	}
	if _, ok := states[itemID]; !ok {
		t.Fatal("het aangeraakte item ontbreekt")
	}
}

// TestSubjectsAreIsolated is de test die stap 3 nieuw maakt: twee gebruikers
// die hetzelfde item kijken krijgen elk hun eigen (subject, item_id)-rij, en
// geen van beide ziet de kijkstatus van de ander.
func TestSubjectsAreIsolated(t *testing.T) {
	pool, store, itemID, first := fixture(t)
	ctx := context.Background()
	second := createUser(t, pool, "huisgenoot", "member")

	if _, err := store.Apply(ctx, first, itemID, watch.Event{
		SessionID: "tv", Action: watch.ActionPlaybackStarted, Cause: watch.CauseUserStarted,
	}, when, watch.MinLease); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Apply(ctx, second, itemID, watch.Event{
		SessionID: "telefoon", PositionMs: 42_000, Action: watch.ActionPlaybackStarted, Cause: watch.CauseUserStarted,
	}, when.Add(time.Minute), watch.MinLease); err != nil {
		t.Fatal(err)
	}

	gotFirst, err := store.Get(ctx, first, itemID)
	if err != nil {
		t.Fatal(err)
	}
	if !gotFirst.Exists || gotFirst.PositionMs != 0 || gotFirst.OwnerSessionID != "tv" {
		t.Fatalf("eerste subject: %+v", gotFirst)
	}

	gotSecond, err := store.Get(ctx, second, itemID)
	if err != nil {
		t.Fatal(err)
	}
	if !gotSecond.Exists || gotSecond.PositionMs != 42_000 || gotSecond.OwnerSessionID != "telefoon" {
		t.Fatalf("tweede subject: %+v", gotSecond)
	}

	firstList, err := store.List(ctx, first, nil, 10, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(firstList.Entries) != 1 {
		t.Fatalf("eerste subject ziet %d regels, wil 1 (zijn eigen)", len(firstList.Entries))
	}
}
