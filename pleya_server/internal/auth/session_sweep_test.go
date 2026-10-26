package auth_test

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// De opruimronde uit DEC-164 tegen een echte database met een vaste klok.
//
// Elke rij hieronder is een geval dat de ronde moet onderscheiden. De klok is
// vast omdat de grens een tijdstip is: met time.Now zou een test die op de rand
// van een dag draait de verkeerde kant van de grens kunnen raken.

var sweepNow = time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)

const sweepTTL = 30 * 24 * time.Hour

type sweepFixture struct {
	t     *testing.T
	pool  *pgxpool.Pool
	store *auth.Store
	user  id.ID
}

func newSweepFixture(t *testing.T) *sweepFixture {
	t.Helper()
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatal(err)
	}
	user := id.New()
	if _, err := pool.Exec(ctx, `
		INSERT INTO users (id, username, password_hash, role, created_at, updated_at)
		VALUES ($1, 'michel', 'x', 'owner', $2, $2)`, user, sweepNow.Add(-365*24*time.Hour)); err != nil {
		t.Fatal(err)
	}
	return &sweepFixture{t: t, pool: pool, store: auth.NewStore(pool), user: user}
}

// device maakt een toestelsessie die het laatst gezien is op seen, met een
// refreshtoken dat verloopt op tokenExpires (of geen token bij de nulwaarde).
func (f *sweepFixture) device(kind string, seen, tokenExpires time.Time) id.ID {
	f.t.Helper()
	ctx := context.Background()
	sid, err := f.store.CreateSession(ctx, f.user, nil, "Unknown device", seen)
	if err != nil {
		f.t.Fatal(err)
	}
	if kind != "device" {
		if _, err := f.pool.Exec(ctx, `UPDATE sessions SET kind = $1 WHERE id = $2`, kind, sid); err != nil {
			f.t.Fatal(err)
		}
	}
	if !tokenExpires.IsZero() {
		_, hash, err := auth.NewRefreshToken()
		if err != nil {
			f.t.Fatal(err)
		}
		if err := f.store.StoreRefreshToken(ctx, hash, sid, tokenExpires); err != nil {
			f.t.Fatal(err)
		}
	}
	return sid
}

func (f *sweepFixture) revokedAt(sid id.ID) *time.Time {
	f.t.Helper()
	var at *time.Time
	if err := f.pool.QueryRow(context.Background(),
		`SELECT revoked_at FROM sessions WHERE id = $1`, sid).Scan(&at); err != nil {
		f.t.Fatal(err)
	}
	return at
}

func days(n int) time.Duration { return time.Duration(n) * 24 * time.Hour }

func TestSweepRevokesOnlySessionsWhoseRefreshChainIsDead(t *testing.T) {
	f := newSweepFixture(t)
	ctx := context.Background()

	// Het geval van productie: 52 dagen niet gezien, laatste token 22 dagen
	// geleden verlopen.
	dead := f.device("device", sweepNow.Add(-days(52)), sweepNow.Add(-days(22)))
	// Een keten van vóór migratie 0007, net zo dood.
	deadLegacy := f.device("legacy", sweepNow.Add(-days(60)), time.Time{})
	// Eergisteren nog ververst.
	recent := f.device("device", sweepNow.Add(-days(2)), sweepNow.Add(days(28)))
	// Gezien binnen de ondergrens en zonder token: de ronde raakt hem niet,
	// want het tijdstip alleen al beschermt hem.
	recentNoToken := f.device("device", sweepNow.Add(-time.Hour), time.Time{})
	// Lang niet gezien, maar met een token dat nog loopt: de levensduur is
	// verlaagd terwijl dit token er al was. Dat token werkt nog, dus de sessie
	// ook.
	liveToken := f.device("device", sweepNow.Add(-days(40)), sweepNow.Add(days(50)))
	// Al eerder ingetrokken: niet nog eens.
	revoked := f.device("device", sweepNow.Add(-days(90)), time.Time{})
	earlier := sweepNow.Add(-days(10))
	if err := f.store.RevokeSession(ctx, revoked, earlier); err != nil {
		t.Fatal(err)
	}
	// Een API-token heeft een eigen einddatum en geen refreshketen.
	api, _, err := f.store.CreateAPIToken(ctx, f.user, "agent", auth.APIScopeRead,
		sweepNow.Add(days(300)), sweepNow.Add(-days(200)))
	if err != nil {
		t.Fatal(err)
	}

	swept, err := f.store.SweepIdleSessions(ctx, sweepNow, sweepTTL)
	if err != nil {
		t.Fatal(err)
	}
	got := map[id.ID]bool{}
	for _, sid := range swept {
		got[sid] = true
	}
	if len(swept) != 2 || !got[dead] || !got[deadLegacy] {
		t.Fatalf("ingetrokken: %v, verwacht precies %s en %s", swept, dead, deadLegacy)
	}

	for name, sid := range map[string]id.ID{
		"recent": recent, "recent zonder token": recentNoToken, "lopend token": liveToken, "api-token": api.ID,
	} {
		if at := f.revokedAt(sid); at != nil {
			t.Errorf("%s is ingetrokken op %s", name, at)
		}
	}
	if at := f.revokedAt(dead); at == nil || !at.Equal(sweepNow) {
		t.Fatalf("de dode sessie heeft revoked_at %v, verwacht %s", at, sweepNow)
	}
	if at := f.revokedAt(revoked); at == nil || !at.Equal(earlier) {
		t.Fatalf("de al ingetrokken sessie kreeg een nieuw tijdstip: %v, verwacht %s", at, earlier)
	}

	// De cascade van RevokeSession: het verlopen token van de dode sessie is
	// nu ook ingetrokken, het token van de recente sessie niet.
	var open int
	if err := f.pool.QueryRow(ctx, `
		SELECT count(*) FROM auth_refresh_tokens WHERE session_id = $1 AND revoked_at IS NULL`, dead).Scan(&open); err != nil {
		t.Fatal(err)
	}
	if open != 0 {
		t.Fatalf("de dode sessie houdt %d niet-ingetrokken refreshtokens", open)
	}
	if err := f.pool.QueryRow(ctx, `
		SELECT count(*) FROM auth_refresh_tokens WHERE session_id = $1 AND revoked_at IS NULL`, recent).Scan(&open); err != nil {
		t.Fatal(err)
	}
	if open != 1 {
		t.Fatalf("de recente sessie heeft %d open refreshtokens, verwacht 1", open)
	}

	// GET /sessions leest ListSessions: de dode toestellen staan er niet meer in.
	list, err := f.store.ListSessions(ctx, f.user, sweepNow)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 4 {
		t.Fatalf("na de ronde staan er %d sessies in de lijst, verwacht 4", len(list))
	}

	// Een tweede ronde vindt niets meer.
	again, err := f.store.SweepIdleSessions(ctx, sweepNow.Add(time.Minute), sweepTTL)
	if err != nil {
		t.Fatal(err)
	}
	if len(again) != 0 {
		t.Fatalf("een tweede ronde trok %v in", again)
	}
}

// De ondergrens: een aanroeper die een te korte duur doorgeeft ruimt toch
// niets op dat binnen een dag gezien is.
func TestSweepNeverGoesBelowTheFloor(t *testing.T) {
	f := newSweepFixture(t)
	ctx := context.Background()

	twoHours := f.device("device", sweepNow.Add(-2*time.Hour), time.Time{})
	twoDays := f.device("device", sweepNow.Add(-days(2)), time.Time{})

	for _, idle := range []time.Duration{0, -time.Hour, time.Minute, time.Hour} {
		swept, err := f.store.SweepIdleSessions(ctx, sweepNow, idle)
		if err != nil {
			t.Fatal(err)
		}
		for _, sid := range swept {
			if sid == twoHours {
				t.Fatalf("met idle %s is een sessie van twee uur oud ingetrokken", idle)
			}
		}
	}
	if at := f.revokedAt(twoDays); at == nil {
		t.Fatal("een sessie van twee dagen zonder token bleef staan, terwijl de ondergrens één dag is")
	}
}
