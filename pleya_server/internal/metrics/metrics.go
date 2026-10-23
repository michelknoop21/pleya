// Package metrics levert tellers in het Prometheus-tekstformaat, zonder
// externe afhankelijkheid. De server telt alleen wat een operator nodig heeft
// om te zien dat hij gezond is; er gaat niets naar buiten en de listener staat
// standaard op loopback (S24.3).
package metrics

import (
	"fmt"
	"net/http"
	"sort"
	"strings"
	"sync"
)

// Registry houdt tellers met labels bij. De nulwaarde is bruikbaar.
type Registry struct {
	mu     sync.Mutex
	help   map[string]string
	counts map[string]map[string]uint64 // naam -> labelreeks -> teller
}

// Inc telt één op. labels zijn paren: "mode", "transcode", "code", "2xx".
// Een label dat de server zelf kiest (geen vrije invoer) houdt de reeks klein.
func (r *Registry) Inc(name, help string, labels ...string) {
	if r == nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.counts == nil {
		r.counts = map[string]map[string]uint64{}
		r.help = map[string]string{}
	}
	r.help[name] = help
	series := r.counts[name]
	if series == nil {
		series = map[string]uint64{}
		r.counts[name] = series
	}
	series[labelString(labels)]++
}

func labelString(labels []string) string {
	if len(labels) < 2 {
		return ""
	}
	parts := make([]string, 0, len(labels)/2)
	for i := 0; i+1 < len(labels); i += 2 {
		parts = append(parts, fmt.Sprintf("%s=%q", labels[i], labels[i+1]))
	}
	return "{" + strings.Join(parts, ",") + "}"
}

// Handler schrijft alle tellers, gesorteerd zodat de uitvoer stabiel is.
func (r *Registry) Handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if req.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		r.mu.Lock()
		defer r.mu.Unlock()
		names := make([]string, 0, len(r.counts))
		for name := range r.counts {
			names = append(names, name)
		}
		sort.Strings(names)
		w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
		var b strings.Builder
		for _, name := range names {
			fmt.Fprintf(&b, "# HELP %s %s\n# TYPE %s counter\n", name, r.help[name], name)
			series := r.counts[name]
			keys := make([]string, 0, len(series))
			for k := range series {
				keys = append(keys, k)
			}
			sort.Strings(keys)
			for _, k := range keys {
				fmt.Fprintf(&b, "%s%s %d\n", name, k, series[k])
			}
		}
		_, _ = w.Write([]byte(b.String()))
	})
}

// Middleware telt elke aanvraag op methode en statusklasse. Het pad staat er
// bewust niet in: het bevat ids, en een teller per id groeit zonder grens.
func (r *Registry) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, req)
		r.Inc("pleya_http_requests_total", "HTTP-aanvragen per methode en statusklasse.",
			"method", req.Method, "class", fmt.Sprintf("%dxx", rec.status/100))
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

// Flush en Unwrap houden streaming (HLS, bytes met Range) intact.
func (s *statusRecorder) Flush() {
	if f, ok := s.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

func (s *statusRecorder) Unwrap() http.ResponseWriter { return s.ResponseWriter }
