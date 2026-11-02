package metadata

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestImagesOfficieleLijstBegrensdEnItemgebonden(t *testing.T) {
	calls := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if r.URL.Path != "/movie/42/images" && r.URL.Path != "/tv/42/images" {
			t.Errorf("onverwachte fanout %s", r.URL.Path)
		}
		if r.URL.Query().Get("api_key") != "sleutel123" || r.URL.Query().Get("language") != "" {
			t.Errorf("images-query %v", r.URL.Query())
		}
		entries := []map[string]any{{"file_path": "https://evil.test/a.jpg", "width": 20, "height": 20}, {"file_path": "/../bad.jpg", "width": 20, "height": 20}, {"file_path": "/zero.jpg", "width": 0, "height": 20}, {"file_path": "/huge.jpg", "width": 20000, "height": 20000}}
		for n := 0; n < 30; n++ {
			entries = append(entries, map[string]any{"file_path": fmt.Sprintf("/a%d.jpg", n), "width": 300, "height": 450, "iso_639_1": "nl"})
		}
		entries = append(entries, entries[4])
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"id": 42, "posters": entries, "backdrops": []map[string]any{{"file_path": "/b.png", "width": 800, "height": 450, "iso_639_1": nil}}, "logos": entries})
	}))
	defer srv.Close()
	c := fastClient(t, srv.URL, srv.URL)
	for _, kind := range []string{"movie", "show"} {
		choices, err := c.Images(context.Background(), kind, 42)
		if err != nil || len(choices) != 17 {
			t.Fatalf("lijst %+v %v", choices, err)
		}
		if choices[0].Ref != "/a0.jpg" || choices[0].Kind != "poster" || choices[0].Language == nil || *choices[0].Language != "nl" || choices[16].Kind != "backdrop" || choices[16].Language != nil {
			t.Fatalf("rollen/taal %+v", choices)
		}
	}
	if calls != 2 {
		t.Fatalf("%d calls", calls)
	}
	for _, kind := range []string{"episode", ""} {
		if _, err := c.Images(context.Background(), kind, 42); err == nil {
			t.Fatal("ongeldige kind geaccepteerd")
		}
	}
	if _, err := c.Images(context.Background(), "movie", 0); err == nil || calls != 2 {
		t.Fatal("ongeldige identiteit bereikte provider")
	}
}

func TestImagesAndereIdentiteitEnVeiligeProviderfouten(t *testing.T) {
	for _, body := range []string{`{"id":7,"posters":[]}`, `<html>secret</html>`, `{"id":42} {"id":43}`} {
		t.Run(body, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(body))
			}))
			defer srv.Close()
			_, err := fastClient(t, srv.URL, srv.URL).Images(context.Background(), "movie", 42)
			if err == nil || strings.Contains(err.Error(), "sleutel123") {
				t.Fatalf("onveilige/ontbrekende fout %v", err)
			}
		})
	}
}
