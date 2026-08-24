package api_test

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/scanner"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	"github.com/edde746/plezy/pleya_server/internal/watch"
	"github.com/jackc/pgx/v5/pgxpool"
)

// EnvResponseDir laat de test elk antwoord op schijf zetten, zodat
// scripts/check_server_responses.py ze tegen openapi.yaml kan houden.
//
// Dat is acceptatiecriterium 4, en het is bewust geen Go-validator: dan zou de
// server tegen zijn eigen lezing van het contract toetsen. De Python-validator
// leest hetzelfde openapi.yaml als de fixtures, dus beide kanten meten met
// dezelfde meetlat.
const EnvResponseDir = "PLEYA_RESPONSE_DIR"

type capture struct {
	mu      sync.Mutex
	dir     string
	entries []captureEntry
}

type captureEntry struct {
	File   string `json:"file"`
	Schema string `json:"schema"`
	Method string `json:"method"`
	Path   string `json:"path"`
	Status int    `json:"status"`
}

type env struct {
	t       *testing.T
	server  *api.Server
	store   *catalog.Store
	auth    *auth.Store
	watch   *watch.Store
	pool    *pgxpool.Pool
	root    string
	access  string
	refresh string
	cap     *capture
	libs    []catalog.Library
	argon2  auth.Argon2Params
}

func newEnv(t *testing.T) *env {
	t.Helper()
	testsupport.HasFFmpeg(t)

	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}

	root := t.TempDir()
	buildLibrary(t, root)

	store := catalog.NewStore(pool)
	authStore := auth.NewStore(pool)

	libs, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{
		{Slug: "films", Title: "Films", Kind: "movies", Roots: []catalog.RootSpec{
			{Path: filepath.Join(root, "films"), FSType: "tmpfs", InodeTrusted: true, TrustSource: "fstype_default"}}},
		{Slug: "series", Title: "Series", Kind: "shows", Roots: []catalog.RootSpec{
			{Path: filepath.Join(root, "series"), FSType: "tmpfs", InodeTrusted: true, TrustSource: "fstype_default"}}},
	})
	if err != nil {
		t.Fatalf("bibliotheken: %v", err)
	}

	scanAll(t, store, libs)

	serverID, err := authStore.ServerID(ctx)
	if err != nil {
		t.Fatal(err)
	}

	key := make([]byte, 32)
	for i := range key {
		key[i] = byte(i + 1)
	}
	signer, err := auth.NewSigner(key)
	if err != nil {
		t.Fatal(err)
	}

	// Lichte Argon2-parameters in de test. De echte staan in
	// auth.DefaultArgon2Params en worden daar gemeten; hier zou een kwart seconde
	// per login de suite onnodig traag maken.
	light := auth.Argon2Params{Memory: 8 * 1024, Iterations: 1, Parallelism: 1, SaltLength: 16, KeyLength: 32}

	watchStore := watch.NewStore(pool)

	srv := api.New(api.Options{
		Catalog:          store,
		Auth:             authStore,
		Watch:            watchStore,
		Signer:           signer,
		Logger:           slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError})),
		Ready:            func() bool { return true },
		ServerID:         serverID,
		Name:             "Zolder",
		Version:          "0.2.0-test",
		StartedAt:        time.Date(2026, 8, 18, 19, 25, 33, 0, time.UTC),
		AccessTokenTTL:   15 * time.Minute,
		RefreshTokenTTL:  24 * time.Hour,
		RefreshGraceWindow: 2 * time.Minute,
		StreamTokenTTL:   5 * time.Minute,
		SetupCodeTTL:     30 * time.Minute,
		StreamSessionTTL: 30 * time.Minute,
		WatchLease:       watch.MinLease,
		Argon2:           light,
	})

	return &env{t: t, server: srv, store: store, auth: authStore, watch: watchStore, pool: pool,
		root: root, libs: libs, cap: shared, argon2: light}
}

// scanAll draait één volledige scanronde over elke bibliotheek.
func scanAll(t *testing.T, store *catalog.Store, libs []catalog.Library) {
	t.Helper()

	sc := scanner.New(scanner.Options{
		Store:  store,
		Prober: ffprobe.New("ffprobe", 60*time.Second),
		Logger: slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelWarn})),
	})
	for _, lib := range libs {
		stats, err := sc.ScanLibrary(context.Background(), lib, "manual")
		if err != nil {
			t.Fatalf("scannen: %v", err)
		}
		if stats.Errors != 0 {
			t.Fatalf("%d fouten tijdens het scannen: %s", stats.Errors, stats.LastError)
		}
	}
}

// rescan draait een tweede ronde, voor tests die een bestand op schijf wijzigen.
func (e *env) rescan() {
	e.t.Helper()
	scanAll(e.t, e.store, e.libs)
}

// generation leest de generation van een bestand rechtstreeks uit de database.
//
// De HTTP-laag toont hem nergens, en dat hoort ook zo: hij is intern. Een test
// die wil bewijzen dat de validator de bytes volgt en niet het id moet hem wel
// kunnen zien.
func (e *env) generation(fileID string) int64 {
	e.t.Helper()

	var generation int64
	err := e.pool.QueryRow(context.Background(),
		`SELECT generation FROM media_files WHERE id = $1`, fileID).Scan(&generation)
	if err != nil {
		e.t.Fatalf("generation van %s lezen: %v", fileID, err)
	}
	return generation
}

// revokeStreamSession en expireStreamSession draaien aan de klok en aan de
// ingetrokken-vlag van een streamsessie.
//
// Rechtstreeks op de tabel en niet via een endpoint: het protocol kent geen
// endpoint om een sessie te beëindigen (dat is de TTL plus het sluiten van het
// tabblad), en een test die de tijd vooruit zet zou de hele server een
// testklok moeten geven voor één veld.
func (e *env) revokeStreamSession(sessionID string) {
	e.t.Helper()
	if _, err := e.pool.Exec(context.Background(),
		`UPDATE stream_sessions SET revoked_at = now() WHERE id = $1`, sessionID); err != nil {
		e.t.Fatalf("sessie intrekken: %v", err)
	}
}

func (e *env) expireStreamSession(sessionID string) {
	e.t.Helper()
	if _, err := e.pool.Exec(context.Background(),
		`UPDATE stream_sessions SET expires_at = now() - interval '1 minute' WHERE id = $1`,
		sessionID); err != nil {
		e.t.Fatalf("sessie laten verlopen: %v", err)
	}
}

// shared is één opvangpunt voor alle tests in dit pakket.
//
// Per test een eigen manifest schrijven levert een manifest op met alleen de
// laatste test erin, en dan meet de contractcontrole een fractie van wat er
// getoetst lijkt. Dat is precies het soort dekking dat geruststelt zonder iets
// te bewijzen.
var shared *capture

func TestMain(m *testing.M) {
	if dir := strings.TrimSpace(os.Getenv(EnvResponseDir)); dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			panic(err)
		}
		shared = &capture{dir: dir}
	}

	code := m.Run()
	if shared != nil {
		shared.writeManifest()
	}
	os.Exit(code)
}

// buildLibrary zet een kleine maar volledige bibliotheek neer: twee films met
// meerdere versies en sidecars, en een serie met twee seizoenen.
func buildLibrary(t *testing.T, root string) {
	t.Helper()

	films := filepath.Join(root, "films")
	testsupport.MakeVideo(t, filepath.Join(films, "Grease (1978)", "Grease (1978).mkv"), 1)
	testsupport.WriteFile(t, filepath.Join(films, "Grease (1978)", "Grease (1978).nld.srt"),
		"1\n00:00:01,000 --> 00:00:02,000\nhallo\n")
	testsupport.WriteFile(t, filepath.Join(films, "Grease (1978)", "poster.jpg"), "geen echte jpeg")

	testsupport.MakeVideo(t, filepath.Join(films, "Blade Runner (1982)", "Blade Runner (1982).mkv"), 1)
	testsupport.MakeVideo(t, filepath.Join(films, "Blade Runner (1982)", "Blade Runner (1982) {edition-Final Cut}.mkv"), 2)

	testsupport.MakeVideo(t, filepath.Join(films, "The Matrix (1999)", "The Matrix (1999).mkv"), 1)

	series := filepath.Join(root, "series")
	base := filepath.Join(series, "How I Met Your Mother (2005)")
	testsupport.MakeVideo(t, filepath.Join(base, "Season 01", "How I Met Your Mother - S01E09 - Slap Bet.mkv"), 1)
	testsupport.MakeVideo(t, filepath.Join(base, "Season 01", "How I Met Your Mother - S01E10 - The Pineapple Incident.mkv"), 1)
	testsupport.MakeVideo(t, filepath.Join(base, "Season 02", "How I Met Your Mother - S02E01 - Where Were We.mkv"), 1)
}

// do voert één aanvraag uit tegen de router.
func (e *env) do(method, path string, body any, opts ...func(*http.Request)) *httptest.ResponseRecorder {
	e.t.Helper()

	var reader *strings.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			e.t.Fatal(err)
		}
		reader = strings.NewReader(string(raw))
	} else {
		reader = strings.NewReader("")
	}

	req := httptest.NewRequest(method, path, reader)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if e.access != "" {
		req.Header.Set("Authorization", "Bearer "+e.access)
	}
	for _, opt := range opts {
		opt(req)
	}

	rec := httptest.NewRecorder()
	e.server.Handler().ServeHTTP(rec, req)
	return rec
}

func withoutAuth(r *http.Request) { r.Header.Del("Authorization") }

func rawBody(v string) func(*http.Request) {
	return func(r *http.Request) { r.Body = io.NopCloser(strings.NewReader(v)) }
}

// getJSON doet een aanvraag, eist de status, en legt het antwoord vast voor de
// contractcontrole.
func (e *env) getJSON(path, schema string, want int, target any) {
	e.t.Helper()
	rec := e.do(http.MethodGet, path, nil)
	if rec.Code != want {
		e.t.Fatalf("GET %s gaf %d, verwacht %d: %s", path, rec.Code, want, rec.Body.String())
	}
	e.record(schema, http.MethodGet, path, rec)
	if target != nil {
		if err := json.Unmarshal(rec.Body.Bytes(), target); err != nil {
			e.t.Fatalf("GET %s: antwoord onleesbaar: %v", path, err)
		}
	}
}

func (e *env) record(schema, method, path string, rec *httptest.ResponseRecorder) {
	if e.cap == nil || schema == "" {
		return
	}
	e.cap.add(e.t, schema, method, path, rec)
}

func (c *capture) add(t *testing.T, schema, method, path string, rec *httptest.ResponseRecorder) {
	c.mu.Lock()
	defer c.mu.Unlock()

	// Dezelfde endpoint met dezelfde status komt in meerdere tests langs. Eén
	// bestand per combinatie is genoeg; twee keer valideren voegt niets toe.
	name := sanitize(schema + "_" + method + "_" + path + "_" + itoa(rec.Code))
	for _, existing := range c.entries {
		if existing.File == name+".json" {
			return
		}
	}
	file := name + ".json"
	if err := os.WriteFile(filepath.Join(c.dir, file), rec.Body.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
	c.entries = append(c.entries, captureEntry{
		File: file, Schema: schema, Method: method, Path: path, Status: rec.Code,
	})
}

func (c *capture) writeManifest() {
	c.mu.Lock()
	defer c.mu.Unlock()

	raw, err := json.MarshalIndent(map[string]any{
		"comment":   "Antwoorden van de draaiende server, vastgelegd door internal/api. Gelezen door scripts/check_server_responses.py.",
		"responses": c.entries,
	}, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(filepath.Join(c.dir, "manifest.json"), append(raw, '\n'), 0o644)
}

func sanitize(v string) string {
	var b strings.Builder
	for _, r := range v {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
			b.WriteRune(r)
		default:
			b.WriteByte('_')
		}
	}
	return strings.Trim(b.String(), "_")
}

func itoa(v int) string {
	if v == 0 {
		return "0"
	}
	out := ""
	for v > 0 {
		out = string(rune('0'+v%10)) + out
		v /= 10
	}
	return out
}
