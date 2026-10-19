package metadata

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func fastClient(t *testing.T, apiURL, imgURL string) *TMDB {
	t.Helper()
	c := newTMDB("sleutel123", "nl-NL", apiURL, imgURL)
	c.gap = 0
	return c
}

func TestSearchAndDetailsParseProviderAnswers(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		switch r.URL.Path {
		case "/search/movie":
			if r.URL.Query().Get("api_key") != "sleutel123" || r.URL.Query().Get("language") != "nl-NL" {
				t.Errorf("query %v", r.URL.Query())
			}
			_, _ = w.Write([]byte(`{"results":[{"id":348,"title":"Alien","original_title":"Alien","release_date":"1979-05-25"}]}`))
		case "/movie/348":
			if r.URL.Query().Get("language") == "en-US" {
				_, _ = w.Write([]byte(`{"overview":"English text"}`))
				return
			}
			_, _ = w.Write([]byte(`{"overview":"","poster_path":"/p.jpg","backdrop_path":"/b.jpg",
				"genres":[{"name":"Horror"},{"name":"Sciencefiction"}],
				"release_dates":{"results":[{"iso_3166_1":"US","release_dates":[{"certification":"R"}]},
				{"iso_3166_1":"NL","release_dates":[{"certification":""},{"certification":"16"}]}]}}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	c := fastClient(t, srv.URL, srv.URL)
	res, err := c.Search(context.Background(), "movie", "Alien", nil)
	if err != nil || len(res) != 1 || res[0].ID != 348 || res[0].Year != 1979 {
		t.Fatalf("Search = %+v, %v", res, err)
	}
	d, err := c.Details(context.Background(), "movie", 348)
	if err != nil {
		t.Fatal(err)
	}
	if d.ContentRating != "16" {
		t.Errorf("kijkwijzer %q, verwacht de Nederlandse 16", d.ContentRating)
	}
	if d.Summary != "English text" {
		t.Errorf("samenvatting %q, verwacht de Engelse terugval", d.Summary)
	}
	if len(d.Genres) != 2 || d.PosterRef != "/p.jpg" || d.BackdropRef != "/b.jpg" {
		t.Errorf("details %+v", d)
	}
}

func TestBearerTokenGoesInTheHeaderNotTheURL(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer eyJabc" || r.URL.Query().Get("api_key") != "" {
			t.Errorf("auth: header %q query %q", r.Header.Get("Authorization"), r.URL.RawQuery)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"results":[]}`))
	}))
	defer srv.Close()
	c := newTMDB("eyJabc", "nl-NL", srv.URL, srv.URL)
	c.gap = 0
	if _, err := c.Search(context.Background(), "show", "x", nil); err != nil {
		t.Fatal(err)
	}
}

func TestRateLimitIsReportedWithRetryAfter(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Retry-After", "7")
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer srv.Close()
	_, err := fastClient(t, srv.URL, srv.URL).Search(context.Background(), "movie", "x", nil)
	var rl ErrRateLimited
	if !errors.As(err, &rl) || rl.After != 7*time.Second {
		t.Fatalf("fout %v, verwacht ErrRateLimited{7s}", err)
	}
}

func TestHTMLAnswerIsRejected(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		_, _ = w.Write([]byte(`<html>Log in to the hotel wifi</html>`))
	}))
	defer srv.Close()
	if _, err := fastClient(t, srv.URL, srv.URL).Search(context.Background(), "movie", "x", nil); err == nil {
		t.Fatal("een HTML-antwoord werd als resultaat geaccepteerd")
	}
}

// De SSRF-grens: een redirect naar een andere host wordt niet gevolgd.
func TestRedirectsAreNotFollowed(t *testing.T) {
	var hit atomic.Bool
	other := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { hit.Store(true) }))
	defer other.Close()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, other.URL+"/intern", http.StatusFound)
	}))
	defer srv.Close()

	_, err := fastClient(t, srv.URL, srv.URL).Search(context.Background(), "movie", "x", nil)
	if err == nil || hit.Load() {
		t.Fatalf("redirect gevolgd of niet gemeld (err=%v, bereikt=%v)", err, hit.Load())
	}
}

func TestErrorsNeverCarryTheKey(t *testing.T) {
	c := fastClient(t, "http://127.0.0.1:1", "http://127.0.0.1:1")
	_, err := c.Search(context.Background(), "movie", "x", nil)
	if err == nil || strings.Contains(err.Error(), "sleutel123") {
		t.Fatalf("fout lekt de sleutel of ontbreekt: %v", err)
	}
}

func TestImageRejectsOddRefsAndTypes(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "html.jpg") {
			w.Header().Set("Content-Type", "text/html")
		} else {
			w.Header().Set("Content-Type", "image/jpeg")
		}
		_, _ = w.Write([]byte("bytes"))
	}))
	defer srv.Close()
	c := fastClient(t, srv.URL, srv.URL)

	if data, ext, err := c.Image(context.Background(), "poster", "/ok.jpg"); err != nil || ext != ".jpg" || string(data) != "bytes" {
		t.Fatalf("goede afbeelding: %v %q %q", err, ext, data)
	}
	for _, ref := range []string{"/html.jpg", "../etc/passwd", "/a/../b.jpg", "http://evil/x.jpg", "/x.jpg?y=1"} {
		if _, _, err := c.Image(context.Background(), "poster", ref); err == nil {
			t.Errorf("verwijzing %q werd geaccepteerd", ref)
		}
	}
}
