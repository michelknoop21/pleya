// Package httpserver levert de HTTP-laag met de twee operationele endpoints.
package httpserver

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"
)

// ReadyTimeout begrenst de databasecontrole van /readyz. Kort, want een
// readinesscontrole die blijft hangen is zelf een storing.
const ReadyTimeout = 2 * time.Second

// Pinger is alles wat kan zeggen of de database bereikbaar is. Een
// *pgxpool.Pool voldoet; de interface bestaat zodat een test geen database
// nodig heeft.
type Pinger interface {
	Ping(ctx context.Context) error
}

// Options bundelt wat de server nodig heeft.
type Options struct {
	Addr   string
	DB     Pinger
	Logger *slog.Logger
}

// Server draait de HTTP-laag.
type Server struct {
	http *http.Server
	log  *slog.Logger
}

// New bouwt de server. Er wordt nog niet geluisterd.
func New(opts Options) *Server {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", healthz)
	mux.HandleFunc("GET /readyz", readyz(opts.DB))

	return &Server{
		http: &http.Server{
			Addr:              opts.Addr,
			Handler:           mux,
			ReadHeaderTimeout: 10 * time.Second,
		},
		log: opts.Logger,
	}
}

// Handler geeft de router, zodat een test hem zonder luisterende socket kan
// aanroepen.
func (s *Server) Handler() http.Handler { return s.http.Handler }

// Addr geeft het geconfigureerde luisteradres.
func (s *Server) Addr() string { return s.http.Addr }

// ListenAndServe blokkeert tot de server stopt. Een nette afsluiting geeft nil.
func (s *Server) ListenAndServe() error {
	err := s.http.ListenAndServe()
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}

// Shutdown weigert nieuwe aanvragen en laat lopende aanvragen binnen de
// gegeven termijn aflopen.
func (s *Server) Shutdown(ctx context.Context) error {
	return s.http.Shutdown(ctx)
}
