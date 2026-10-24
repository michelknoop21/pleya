package api_test

import (
	"io"
	"net/http"
	"net/http/httptest"
	"net/http/httputil"
	"net/url"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/config"
)

// S24.3: de gekozen leveringswijze telt mee, zodat een operator ziet wat de
// server werkelijk doet. Een direct-play-plan telt één keer, een weigering niet.
func TestMetricsCountThePlanByDeliveryMode(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease")

	e.planFor(map[string]any{"item_id": movie.ID}, http.StatusOK)
	e.planFor(map[string]any{"item_id": movie.ID}, http.StatusOK)

	rec := httptest.NewRecorder()
	e.metrics.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if want := `pleya_playback_plans_total{mode="direct_play"} 2`; !strings.Contains(rec.Body.String(), want) {
		t.Fatalf("mist %q in:\n%s", want, rec.Body.String())
	}
}

// S24.4 en S24.1: drie proxy-opstellingen vóór de server, en in beide blijft Range heel.
// De ene is een doorgeefproxy zoals een tunnel (de header blijft staan), de
// andere voegt forwarded-headers toe zoals een omgekeerde proxy dat doet.
func TestRangeSurvivesTwoProxySetups(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease")
	version := movie.Versions[0].ID

	origin := httptest.NewServer(e.server.Handler())
	defer origin.Close()
	target, _ := url.Parse(origin.URL)

	forwarded := &httputil.ReverseProxy{Rewrite: func(r *httputil.ProxyRequest) {
		r.SetURL(target)
		r.SetXForwarded()
		r.Out.Header.Set("X-Forwarded-Proto", "https")
	}}
	// Een subpad is een proxy die zijn voorvoegsel afstript; de server zelf kent
	// het niet, want de client plakt zijn basis-URL (met voorvoegsel) voor elk pad.
	setups := map[string]struct {
		handler http.Handler
		prefix  string
	}{
		"doorgeven": {httputil.NewSingleHostReverseProxy(target), ""},
		"forwarded": {forwarded, ""},
		"subpad":    {http.StripPrefix("/media", forwarded), "/media"},
	}
	for name, setup := range setups {
		handler, prefix := setup.handler, setup.prefix
		t.Run(name, func(t *testing.T) {
			front := httptest.NewServer(handler)
			defer front.Close()

			get := func(rangeHeader string) (*http.Response, []byte) {
				req, _ := http.NewRequest(http.MethodGet, front.URL+prefix+"/pleya/v1/stream/"+version, nil)
				req.Header.Set("Authorization", "Bearer "+e.access)
				if rangeHeader != "" {
					req.Header.Set("Range", rangeHeader)
				}
				resp, err := http.DefaultClient.Do(req)
				if err != nil {
					t.Fatal(err)
				}
				defer resp.Body.Close()
				body, _ := io.ReadAll(resp.Body)
				return resp, body
			}

			full, fullBody := get("")
			if full.StatusCode != http.StatusOK || full.Header.Get("Accept-Ranges") != "bytes" {
				t.Fatalf("zonder range: %d, Accept-Ranges %q", full.StatusCode, full.Header.Get("Accept-Ranges"))
			}

			part, partBody := get("bytes=10-29")
			if part.StatusCode != http.StatusPartialContent || len(partBody) != 20 {
				t.Fatalf("bytes=10-29: %d met %d bytes", part.StatusCode, len(partBody))
			}
			if string(partBody) != string(fullBody[10:30]) {
				t.Fatal("het deel komt niet overeen met het bestand")
			}
			if cr := part.Header.Get("Content-Range"); !strings.HasPrefix(cr, "bytes 10-29/") {
				t.Fatalf("Content-Range %q", cr)
			}

			tail, tailBody := get("bytes=-5")
			if tail.StatusCode != http.StatusPartialContent || string(tailBody) != string(fullBody[len(fullBody)-5:]) {
				t.Fatalf("bytes=-5: %d", tail.StatusCode)
			}
		})
	}
}

// S24.1: een vertrouwde proxy mag Forwarded-headers sturen, een andere niet.
func TestTrustedProxyListParsesAddressesAndRanges(t *testing.T) {
	list, err := config.ParseTrustedProxies("172.18.0.0/16, 10.0.0.5")
	if err != nil || len(list) != 2 {
		t.Fatalf("lijst %v, fout %v", list, err)
	}
	if !config.RemoteAddrIsTrustedProxy(list, "172.18.4.9:51000") || config.RemoteAddrIsTrustedProxy(list, "192.168.1.9:1") {
		t.Fatal("de vertrouwde lijst past niet bij de adressen")
	}
}
