package api_test

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/edde746/plezy/pleya_server/internal/auth"
)

// Wat een inlogpoging zonder wachtwoord mag kosten. Het pad is public, dus de aanvrager
// kiest de naam, het tempo en de lengte zelf.

const (
	loginAuditBurst = 12
	loginPassword   = "een-lang-genoeg-wachtwoord"
)

func (e *env) tryLogin(username string, opts ...func(*http.Request)) int {
	e.t.Helper()
	return e.do(http.MethodPost, loginPath, map[string]string{"username": username, "password": "verkeerd"},
		append([]func(*http.Request){withoutAuth}, opts...)...).Code
}

func (e *env) deniedLoginNames() []string {
	e.t.Helper()
	rows, err := e.pool.Query(context.Background(), `
		SELECT detail->>'username' FROM admin_audit WHERE operation = 'login' AND outcome = 'denied'`)
	if err != nil {
		e.t.Fatal(err)
	}
	defer rows.Close()
	var names []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			e.t.Fatal(err)
		}
		names = append(names, name)
	}
	return names
}

func TestLoginCutsALongNameBeforeTheAuditLogAndTheBucket(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	long := strings.Repeat("ä", 3000)

	if code := e.tryLogin(long); code != http.StatusUnauthorized {
		t.Fatalf("gaf %d", code)
	}
	names := e.deniedLoginNames()
	if len(names) != 1 || utf8.RuneCountInString(names[0]) != 64 || !utf8.ValidString(names[0]) {
		t.Fatalf("in het auditlog: %d regels, %d tekens", len(names), utf8.RuneCountInString(names[0]))
	}

	// Na het knippen zijn dit dezelfde sleutel: één naam, vijf pogingen.
	last := 0
	for i := range 5 {
		last = e.tryLogin(long + strconv.Itoa(i))
	}
	if last != http.StatusTooManyRequests {
		t.Fatalf("de zesde poging gaf %d", last)
	}
}

func TestLoginDenialsStopAtTheAuditBound(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	for i := range 40 {
		if code := e.tryLogin("verzonnen-" + strconv.Itoa(i)); code != http.StatusUnauthorized {
			t.Fatalf("poging %d gaf %d", i, code)
		}
	}
	for range 20 {
		e.tryLogin("dezelfde")
	}
	// De klok loopt door tijdens de test; één regel per vijf seconden is de bijvulling.
	if rows := len(e.deniedLoginNames()); rows > loginAuditBurst+3 {
		t.Fatalf("%d auditregels, de grens is %d", rows, loginAuditBurst)
	}
}

func TestLoginRunsAtMostTwoPasswordChecksAtOnce(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	release := make(chan struct{})
	var running atomic.Int32
	e.server.SetPasswordVerifier(func(string, string, auth.Argon2Params) (bool, bool, error) {
		running.Add(1)
		<-release
		return false, false, nil
	})

	var wg sync.WaitGroup
	for i := range 3 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			e.tryLogin("gelijktijdig-" + strconv.Itoa(i))
		}()
	}
	for running.Load() < 2 {
		time.Sleep(time.Millisecond)
	}
	// Ruim de tijd voor de derde om binnen te komen, als dat zou kunnen.
	time.Sleep(500 * time.Millisecond)
	got := running.Load()
	close(release)
	wg.Wait()
	if got != 2 {
		t.Fatalf("%d tegelijk, verwacht 2", got)
	}
	if done := running.Load(); done != 3 {
		t.Fatalf("%d controles, de derde hoort na het wachten alsnog te draaien", done)
	}
}

// Wie wegloopt terwijl hij op een plek wacht, kost geen Argon2 meer.
func TestLoginGivesUpWaitingWhenTheClientLeaves(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	release := make(chan struct{})
	var calls atomic.Int32
	e.server.SetPasswordVerifier(func(string, string, auth.Argon2Params) (bool, bool, error) {
		calls.Add(1)
		<-release
		return false, false, nil
	})
	var wg sync.WaitGroup
	for i := range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			e.tryLogin("bezet-" + strconv.Itoa(i))
		}()
	}
	for calls.Load() < 2 {
		time.Sleep(time.Millisecond)
	}

	// Na de databasevragen, dus terwijl hij op een plek wacht.
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()
	code := e.tryLogin("wegloper", func(r *http.Request) { *r = *r.WithContext(ctx) })
	close(release)
	wg.Wait()
	if code != http.StatusTooManyRequests {
		t.Fatalf("gaf %d", code)
	}
	if got := calls.Load(); got != 2 {
		t.Fatalf("%d controles, de wegloper hoort er geen te kosten", got)
	}
}

func TestLoginStillWorksWithTheAuditBoundSpent(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	for i := range loginAuditBurst + 3 {
		e.tryLogin("vuller-" + strconv.Itoa(i))
	}

	e.login("gewoon")

	var ok int
	if err := e.pool.QueryRow(context.Background(), `
		SELECT count(*) FROM admin_audit WHERE operation = 'login' AND outcome = 'ok'`).Scan(&ok); err != nil {
		t.Fatal(err)
	}
	if ok == 0 {
		t.Fatal("een geslaagde login staat niet in het auditlog")
	}
}

func TestAWrongLoginUnderTheBoundStaysInTheAuditLog(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	if code := e.tryLogin("michel"); code != http.StatusUnauthorized {
		t.Fatalf("gaf %d", code)
	}
	var reason, detail string
	if err := e.pool.QueryRow(context.Background(), `
		SELECT detail->>'reason', detail::text FROM admin_audit
		WHERE operation = 'login' AND outcome = 'denied' AND detail->>'username' = 'michel'`).Scan(&reason, &detail); err != nil {
		t.Fatalf("geen auditregel: %v", err)
	}
	if reason != "invalid_credentials" || strings.Contains(detail, "verkeerd") || strings.Contains(detail, loginPassword) {
		t.Fatalf("auditregel: %s", detail)
	}
}
