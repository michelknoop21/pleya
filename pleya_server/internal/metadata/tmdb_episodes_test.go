package metadata

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

// Een nep-TMDB: de seizoensroute geeft naam en still per aflevering, een still
// komt in de stillmaat van de afbeeldingshost.
func TestSeasonEpisodesAndStillSize(t *testing.T) {
	var imagePath string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/tv/10/season/1":
			if r.URL.Query().Get("api_key") != "sleutel123" || r.URL.Query().Get("language") != "nl-NL" {
				t.Errorf("query %v", r.URL.Query())
			}
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"episodes":[
				{"episode_number":1,"name":" Pilot ","still_path":"/a.jpg"},
				{"episode_number":2,"name":"Episode 2","still_path":null},
				{"episode_number":3,"name":"Raar","still_path":"/../x.jpg"},
				{"episode_number":0,"name":"Geen nummer","still_path":"/b.jpg"}]}`))
		case "/original/a.jpg":
			imagePath = r.URL.Path
			w.Header().Set("Content-Type", "image/jpeg")
			_, _ = w.Write([]byte("jpeg"))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	c := fastClient(t, srv.URL, srv.URL)
	got, err := c.SeasonEpisodes(context.Background(), 10, 1)
	if err != nil {
		t.Fatal(err)
	}
	want := []SeasonEpisode{{1, "Pilot", "/a.jpg"}, {2, "Episode 2", ""}, {3, "Raar", ""}}
	if len(got) != len(want) {
		t.Fatalf("SeasonEpisodes = %+v", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("aflevering %d = %+v, verwacht %+v", i, got[i], want[i])
		}
	}
	if _, _, err := c.Image(context.Background(), "still", "/a.jpg"); err != nil || imagePath != "/original/a.jpg" {
		t.Fatalf("still in maat %q: %v", imagePath, err)
	}
	if _, err := c.SeasonEpisodes(context.Background(), 10, 9); err == nil {
		t.Fatal("een onbekend seizoen hoort een fout te geven")
	}
}
