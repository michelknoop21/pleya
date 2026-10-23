package metrics

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestCountsRequestsByMethodAndClassWithoutThePath(t *testing.T) {
	var reg Registry
	h := reg.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/missing" {
			http.NotFound(w, r)
		}
	}))
	for _, p := range []string{"/a", "/b", "/missing"} {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, p, nil))
	}

	rec := httptest.NewRecorder()
	reg.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	body := rec.Body.String()
	for _, want := range []string{
		`pleya_http_requests_total{method="GET",class="2xx"} 2`,
		`pleya_http_requests_total{method="GET",class="4xx"} 1`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("mist %q in:\n%s", want, body)
		}
	}
	if strings.Contains(body, "/missing") {
		t.Errorf("het pad staat in de metrics:\n%s", body)
	}
}

func TestANilRegistryIsHarmless(t *testing.T) {
	var reg *Registry
	reg.Inc("x", "y", "a", "b")
}
