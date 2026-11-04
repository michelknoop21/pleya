package api_test

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
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

// Een vol slot wordt binnen de grens een 429 met een wachttijd, en daarna werkt inloggen.
func TestLoginAnswers429WhenNoSlotComesFree(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	e.server.SetLoginSlotWait(150 * time.Millisecond)

	release := make(chan struct{})
	var running atomic.Int32
	e.server.SetPasswordVerifier(func(string, string, auth.Argon2Params) (bool, bool, error) {
		running.Add(1)
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
	for running.Load() < 2 {
		time.Sleep(time.Millisecond)
	}

	// De context vangt de test op als de wachttijdgrens er niet is.
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	started := time.Now()
	rec := e.do(http.MethodPost, loginPath, map[string]string{"username": "derde", "password": "verkeerd"}, withoutAuth,
		func(r *http.Request) { *r = *r.WithContext(ctx) })
	elapsed := time.Since(started)
	close(release)
	wg.Wait()

	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.expectCode(rec, "auth.rate_limited")
	if rec.Header().Get("Retry-After") == "" || !strings.Contains(rec.Body.String(), "retry_after_ms") {
		t.Fatalf("geen wachttijd: %v %s", rec.Header(), rec.Body.String())
	}
	if elapsed > 2*time.Second {
		t.Fatalf("wachtte %s", elapsed)
	}

	e.server.SetPasswordVerifier(auth.VerifyPassword)
	e.login("na-het-vrijgeven")
}

// Eén adres kan de Argon2-stap niet alleen vullen, en een ander adres merkt er niets van.
func TestLoginCountsAttemptsPerAddress(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	var checks atomic.Int32
	e.server.SetPasswordVerifier(func(string, string, auth.Argon2Params) (bool, bool, error) {
		checks.Add(1)
		return false, false, nil
	})
	from := func(address string) func(*http.Request) {
		return func(r *http.Request) { r.RemoteAddr = address }
	}

	refused := 0
	for i := range 80 {
		if e.tryLogin("adres-"+strconv.Itoa(i), from("203.0.113.9:4000")) == http.StatusTooManyRequests {
			refused++
		}
	}
	if refused < 15 || checks.Load() > 65 {
		t.Fatalf("%d geweigerd, %d controles", refused, checks.Load())
	}
	if code := e.tryLogin("ander-adres", from("203.0.113.10:4000")); code != http.StatusUnauthorized {
		t.Fatalf("een ander adres gaf %d", code)
	}
}

// Zonder vertrouwde proxy is X-Forwarded-For wat de client zelf opschrijft. Een vervalst
// adres, ook een ander per aanvraag, blijft dus op de emmer van het echte adres.
func TestAForgedForwardedForStaysOnTheAddressBucket(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	var checks atomic.Int32
	e.server.SetPasswordVerifier(func(string, string, auth.Argon2Params) (bool, bool, error) {
		checks.Add(1)
		return false, false, nil
	})

	refused := 0
	for i := range 80 {
		forged := withHeader("X-Forwarded-For", "198.51.100."+strconv.Itoa(i%250))
		if e.tryLogin("vervalst-"+strconv.Itoa(i), forged) == http.StatusTooManyRequests {
			refused++
		}
	}
	if refused < 15 || checks.Load() > 65 {
		t.Fatalf("%d geweigerd, %d controles", refused, checks.Load())
	}
}

// Een bestaande en een verzonnen naam krijgen hetzelfde antwoord, compleet, terwijl de
// auditregel nog moet komen. Zo is de INSERT die alleen de bestaande naam altijd doet niet
// te klokken, en raakt een fout daarin de aanvraag niet.
func TestAWrongPasswordIsAnsweredBeforeTheAuditLine(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()
	server := httptest.NewServer(e.server.Handler())
	defer server.Close()

	block, err := e.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = block.Rollback(ctx) }()
	if _, err := block.Exec(ctx, `LOCK TABLE admin_audit IN ACCESS EXCLUSIVE MODE`); err != nil {
		t.Fatal(err)
	}

	// Een eigen verbinding per aanvraag: op dezelfde verbinding wacht de volgende aanvraag
	// wel tot de handler klaar is, en die meet deze test niet.
	client := &http.Client{Transport: &http.Transport{DisableKeepAlives: true}}
	answer := func(username string) (int, string) {
		t.Helper()
		started := time.Now()
		body := `{"username":"` + username + `","password":"verkeerd"}`
		res, err := client.Post(server.URL+loginPath, "application/json", strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		raw, err := io.ReadAll(res.Body)
		if err != nil {
			t.Fatal(err)
		}
		if elapsed := time.Since(started); elapsed > 2*time.Second {
			t.Fatalf("%s kreeg zijn antwoord pas na %s", username, elapsed)
		}
		return res.StatusCode, string(raw)
	}
	knownStatus, knownBody := answer("michel")
	madeUpStatus, madeUpBody := answer("verzonnen")
	if knownStatus != http.StatusUnauthorized || knownStatus != madeUpStatus || knownBody != madeUpBody {
		t.Fatalf("%d %q tegen %d %q", knownStatus, knownBody, madeUpStatus, madeUpBody)
	}

	if err := block.Rollback(ctx); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(5 * time.Second)
	for len(e.deniedLoginNames()) < 2 {
		if time.Now().After(deadline) {
			t.Fatalf("auditregels: %v", e.deniedLoginNames())
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// Zonder wachtwoord en zonder emmer was dit één regel per aanvraag, met de hele header.
func TestARejectedOriginStaysInsideTheAuditBoundAndIsCut(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	long := "https://" + strings.Repeat("a", 4000) + ".example"

	var body string
	for range 30 {
		rec := e.do(http.MethodPost, loginPath,
			map[string]string{"username": "x", "password": "y", "credential_mode": "cookie"},
			withoutAuth, withHeader("Origin", long))
		if rec.Code != http.StatusForbidden {
			t.Fatalf("gaf %d", rec.Code)
		}
		body = rec.Body.String()
	}
	if strings.Contains(body, long) {
		t.Fatal("de hele Origin staat in het antwoord")
	}

	rows, err := e.pool.Query(context.Background(), `
		SELECT detail->>'origin' FROM admin_audit WHERE operation = 'login' AND outcome = 'denied'`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	count := 0
	for rows.Next() {
		var origin string
		if err := rows.Scan(&origin); err != nil {
			t.Fatal(err)
		}
		count++
		if utf8.RuneCountInString(origin) > 64 {
			t.Fatalf("Origin van %d tekens in het auditlog", utf8.RuneCountInString(origin))
		}
	}
	if count == 0 || count > loginAuditBurst+3 {
		t.Fatalf("%d auditregels, de grens is %d", count, loginAuditBurst)
	}
}

// Wie de emmer vult met namen die niet bestaan, verbergt daarmee geen poging op een echt account.
func TestAWrongPasswordOnARealAccountIsAuditedWithTheBoundSpent(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	for i := range loginAuditBurst + 5 {
		e.tryLogin("verzonnen-" + strconv.Itoa(i))
	}

	if code := e.tryLogin("michel"); code != http.StatusUnauthorized {
		t.Fatalf("gaf %d", code)
	}
	found := false
	for _, name := range e.deniedLoginNames() {
		found = found || name == "michel"
	}
	if !found {
		t.Fatal("de poging op het echte account staat niet in het auditlog")
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
