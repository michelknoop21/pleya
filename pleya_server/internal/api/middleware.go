package api

import (
	"context"
	"log/slog"
	"net/http"
	"runtime/debug"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// maxRequestBodyBytes begrenst elke aanvraagbody die deze server leest.
//
// De grens stond eerder alleen in decodeBody, en dan geldt hij alleen voor een
// handler die decodeBody aanroept. Een handler die r.Body zelf leest, of een
// route die er later bij komt, viel er buiten. Als middleware geldt hij voor
// alles, ook voor een route die nog niet bestaat.
//
// 8 KiB is dezelfde grens die de authroutes al hanteerden. Elk verzoekschema in
// het contract is een handvol velden; een body die hier tegenaan loopt is geen
// grote aanvraag maar een verkeerde.
const maxRequestBodyBytes = 8 << 10

// Handler geeft de router met de middlewareketen eromheen.
//
// De volgorde is niet vrij. logging staat buitenop omdat hij de request-id
// aanmaakt en de uiteindelijke status wil zien, ook de 500 die recovery
// schrijft. recovery staat daaronder zodat hij die id uit de context kan lezen.
// securityHeaders zet zijn headers op de heenweg, dus ze staan er ook op een
// antwoord dat recovery schrijft. bodyLimit staat het dichtst bij de mux, want
// hij raakt alleen het verzoek.
func (s *Server) Handler() http.Handler { return s.chain(s.mux) }

// chain is de keten zelf, los van de mux, zodat een test hem op een eigen
// handler kan leggen. Zou de test de volgorde overschrijven, dan bewees hij een
// keten die niet draait.
func (s *Server) chain(inner http.Handler) http.Handler {
	return s.logging(s.recovery(s.securityHeaders(s.bodyLimit(inner))))
}

// recovery vangt een panic af en maakt er de foutvorm van het protocol van.
//
// Zonder deze laag beëindigt net/http de verbinding zonder lichaam. Een client
// ziet dan een transportfout waar een serverfout hoorde te staan, en verwart
// "de server viel om" met "het netwerk was weg". Sinds venster 1 (DEC-110,
// DEC-111) bestaat `server.internal`, dus er is een code om het mee te zeggen.
//
// De stack blijft in het log. Wat de client krijgt is de request-id, en dat is
// genoeg: dezelfde id staat op de logregel met de stack, dus een melder kan hem
// doorgeven zonder dat de server iets over zijn binnenkant prijsgeeft.
func (s *Server) recovery(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

		defer func() {
			cause := recover()
			if cause == nil {
				return
			}
			// ErrAbortHandler is de afgesproken manier om een antwoord af te
			// breken zonder dat het een fout is. Hem afvangen zou van elke
			// afgebroken stream een 500 in het log maken.
			if cause == http.ErrAbortHandler {
				panic(cause)
			}

			requestID := requestIDFrom(r.Context())
			s.log.Error("panic in handler",
				slog.String("request_id", requestID),
				slog.String("method", r.Method),
				slog.String("path", r.URL.Path),
				slog.Any("panic", cause),
				slog.String("stack", string(debug.Stack())))

			if rec.written {
				// De statusregel is al weg, dus een envelop past er niet meer
				// achter. Doorbreken is dan eerlijker dan JSON achter een half
				// antwoord plakken: de client ziet een afgekapt lichaam en
				// behandelt dat als fout, in plaats van een geldig ogend
				// antwoord met rommel erin.
				panic(cause)
			}

			// Zonder id geen veld. logging slaat /healthz en /readyz over, dus
			// daar is er geen; een lege string meesturen zou een client een
			// referentie geven die nergens op slaat.
			var details map[string]any
			if requestID != "" {
				details = map[string]any{"request_id": requestID}
			}
			writeError(w, s.log, CodeInternal, "internal error", details)
		}()

		next.ServeHTTP(rec, r)
	})
}

// securityHeaders zet op /pleya/v1 wat internal/web al op de bundel zette.
//
// Twee headers, en verder niets. De rest van de set in internal/web gaat over
// een document in een browser: framing, openers, permissions. Een JSON-antwoord
// heeft daar niets aan. Deze twee wel: nosniff omdat een browser anders van een
// foutlichaam iets anders kan maken dan JSON, en no-referrer omdat een
// mediapad in een Referer-header een bibliotheek prijsgeeft aan waar de speler
// daarna heen gaat.
//
// Ze staan op de heenweg, dus ook een antwoord dat recovery schrijft draagt ze.
// De webhandler zet zijn eigen set daarna nog een keer met dezelfde waarden.
func (s *Server) securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		next.ServeHTTP(w, r)
	})
}

// bodyLimit begrenst wat een handler uit de aanvraag kan lezen.
//
// MaxBytesReader en niet io.LimitReader: een LimitReader kapt stil af, waarna
// de JSON-decoder struikelt over een body die tot halverwege klopt en de fout
// iets anders lijkt dan hij is. MaxBytesReader geeft een echte fout terug, en
// de handler vertaalt die naar de code die het contract voor dat endpoint kent.
func (s *Server) bodyLimit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Body != nil {
			r.Body = http.MaxBytesReader(w, r.Body, maxRequestBodyBytes)
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
			next.ServeHTTP(w, r)
			return
		}

		started := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		requestID := id.New().String()

		ctx := context.WithValue(r.Context(), requestIDKey{}, requestID)
		next.ServeHTTP(rec, r.WithContext(ctx))

		s.log.Info("request",
			slog.String("request_id", requestID),
			slog.String("method", r.Method),
			slog.String("path", r.URL.Path),
			slog.Int("status", rec.status),
			slog.Duration("duration", time.Since(started)))
	})
}

type requestIDKey struct{}

// requestIDFrom geeft de id die logging aan deze aanvraag gaf, of een lege
// string op een pad dat logging overslaat.
func requestIDFrom(ctx context.Context) string {
	value, _ := ctx.Value(requestIDKey{}).(string)
	return value
}

type statusRecorder struct {
	http.ResponseWriter
	status  int
	written bool
}

func (r *statusRecorder) WriteHeader(status int) {
	if !r.written {
		r.status = status
		r.written = true
	}
	r.ResponseWriter.WriteHeader(status)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	r.written = true
	return r.ResponseWriter.Write(b)
}

// Unwrap geeft http.ResponseController toegang tot de echte ResponseWriter.
//
// Flush staat er los naast omdat handlers_stream.go rechtstreeks op
// http.Flusher test. Zonder deze twee methoden slikt de wrapper die interface
// op, en dan slaat de doorspoellus in de streamhandler stil over: precies wat
// het commentaar daar zegt te willen voorkomen, alleen deed hij het niet meer
// zodra er een wrapper omheen stond.
func (r *statusRecorder) Unwrap() http.ResponseWriter { return r.ResponseWriter }

func (r *statusRecorder) Flush() {
	if flusher, ok := r.ResponseWriter.(http.Flusher); ok {
		flusher.Flush()
	}
}
