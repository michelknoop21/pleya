package httpserver

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type stubPinger struct {
	err   error
	delay time.Duration
}

func (s stubPinger) Ping(ctx context.Context) error {
	if s.delay > 0 {
		select {
		case <-time.After(s.delay):
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return s.err
}

func newTestServer(db Pinger) *Server {
	return New(Options{
		Addr:   "127.0.0.1:0",
		DB:     db,
		Logger: slog.New(slog.NewJSONHandler(io.Discard, nil)),
	})
}

func do(t *testing.T, srv *Server, path string) *http.Response {
	t.Helper()
	rec := httptest.NewRecorder()
	srv.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	return rec.Result()
}

// /healthz zegt alleen of het proces leeft, en wordt dus niet rood van een
// database die weg is.
func TestHealthzStaysGreenWithoutDatabase(t *testing.T) {
	for name, db := range map[string]Pinger{
		"database in orde": stubPinger{},
		"database weg":     stubPinger{err: errors.New("verbinding geweigerd")},
		"geen pool":        nil,
	} {
		t.Run(name, func(t *testing.T) {
			resp := do(t, newTestServer(db), "/healthz")
			defer resp.Body.Close()
			if resp.StatusCode != http.StatusOK {
				t.Fatalf("status = %d, verwacht 200", resp.StatusCode)
			}
		})
	}
}

func TestReadyzGreenWithDatabase(t *testing.T) {
	resp := do(t, newTestServer(stubPinger{}), "/readyz")
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, verwacht 200", resp.StatusCode)
	}
	body, _ := io.ReadAll(resp.Body)
	if !strings.Contains(string(body), `"ready"`) {
		t.Errorf("body = %q, verwacht status ready", body)
	}
}

func TestReadyzRedWithoutDatabase(t *testing.T) {
	for name, db := range map[string]Pinger{
		"ping faalt": stubPinger{err: errors.New("verbinding geweigerd")},
		"geen pool":  nil,
	} {
		t.Run(name, func(t *testing.T) {
			resp := do(t, newTestServer(db), "/readyz")
			defer resp.Body.Close()
			if resp.StatusCode != http.StatusServiceUnavailable {
				t.Fatalf("status = %d, verwacht 503", resp.StatusCode)
			}
		})
	}
}

// Een ping die blijft hangen mag de readinesscontrole niet laten hangen.
func TestReadyzTimesOut(t *testing.T) {
	start := time.Now()
	resp := do(t, newTestServer(stubPinger{delay: 5 * time.Second}), "/readyz")
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, verwacht 503", resp.StatusCode)
	}
	if elapsed := time.Since(start); elapsed > 4*time.Second {
		t.Fatalf("readyz duurde %v, verwacht rond %v", elapsed, ReadyTimeout)
	}
}

// Het antwoord mag geen verbindingsgegevens, hostnaam of versie bevatten.
func TestHealthEndpointsLeakNothing(t *testing.T) {
	for _, path := range []string{"/healthz", "/readyz"} {
		resp := do(t, newTestServer(stubPinger{}), path)
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		for _, forbidden := range []string{"postgres", "5432", "pleya:", "version"} {
			if strings.Contains(string(body), forbidden) {
				t.Errorf("%s lekte %q: %s", path, forbidden, body)
			}
		}
	}
}

// Shutdown moet lopende aanvragen laten aflopen en ListenAndServe netjes laten
// terugkeren, zodat het proces met code 0 kan eindigen.
func TestGracefulShutdown(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("luisteren mislukt: %v", err)
	}
	addr := ln.Addr().String()
	_ = ln.Close()

	srv := New(Options{
		Addr:   addr,
		DB:     stubPinger{},
		Logger: slog.New(slog.NewJSONHandler(io.Discard, nil)),
	})

	done := make(chan error, 1)
	go func() { done <- srv.ListenAndServe() }()

	waitUntilServing(t, addr)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		t.Fatalf("Shutdown gaf een fout: %v", err)
	}

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("ListenAndServe gaf %v, verwacht nil na een nette afsluiting", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("ListenAndServe keerde niet terug na Shutdown")
	}
}

func waitUntilServing(t *testing.T, addr string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		resp, err := http.Get("http://" + addr + "/healthz")
		if err == nil {
			resp.Body.Close()
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("server begon niet te luisteren")
}
