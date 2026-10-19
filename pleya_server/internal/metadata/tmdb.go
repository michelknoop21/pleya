// Package metadata haalt beschrijvingen en artwork bij een externe provider.
//
// De provider schrijft nooit op het canonieke record: een ronde legt een
// kandidaat vast (catalog.MetadataCandidate) en past die daarna per veld toe.
// Dit is S22.1 tot S22.4 in de kleinst mogelijke vorm; correcties, overrides en
// attributie in de clients volgen met de rest van S22.
package metadata

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

// ProviderTMDB is de naam in metadata_candidates.provider en
// metadata_sources.
const ProviderTMDB = "tmdb"

const (
	tmdbAPIBase   = "https://api.themoviedb.org/3"
	tmdbImageBase = "https://image.tmdb.org/t/p"

	maxJSONBytes  = 2 << 20
	maxImageBytes = 12 << 20

	posterSize   = "w780"
	backdropSize = "w1280"
)

// ErrRateLimited meldt een 429 van de provider met het gevraagde wachten.
type ErrRateLimited struct{ After time.Duration }

func (e ErrRateLimited) Error() string {
	return fmt.Sprintf("provider vraagt %s te wachten", e.After)
}

// TMDB is de client. Hij praat uitsluitend met de twee hosts uit de
// constructor; een redirect naar een andere host wordt niet gevolgd maar is een
// fout (SSRF-grens uit RB-27).
type TMDB struct {
	key      string
	language string
	api      *url.URL
	image    *url.URL
	hc       *http.Client

	mu       sync.Mutex
	nextCall time.Time
	gap      time.Duration
}

// NewTMDB bouwt de client voor productie.
func NewTMDB(key, language string) *TMDB {
	return newTMDB(key, language, tmdbAPIBase, tmdbImageBase)
}

func newTMDB(key, language, apiBase, imageBase string) *TMDB {
	api, _ := url.Parse(apiBase)
	img, _ := url.Parse(imageBase)
	return &TMDB{
		key:      key,
		language: language,
		api:      api,
		image:    img,
		gap:      100 * time.Millisecond,
		hc: &http.Client{
			Timeout: 30 * time.Second,
			// Een 3xx is een antwoord, geen opdracht om ergens anders heen te gaan.
			CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
		},
	}
}

// throttle houdt de eigen aanvraagsnelheid ruim onder de limiet van de provider.
func (c *TMDB) throttle(ctx context.Context) error {
	c.mu.Lock()
	wait := time.Until(c.nextCall)
	if wait < 0 {
		wait = 0
	}
	c.nextCall = time.Now().Add(wait + c.gap)
	c.mu.Unlock()
	if wait == 0 {
		return nil
	}
	select {
	case <-time.After(wait):
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (c *TMDB) get(ctx context.Context, base *url.URL, path string, q url.Values, accept string, limit int64) ([]byte, string, error) {
	if err := c.throttle(ctx); err != nil {
		return nil, "", err
	}
	u := *base
	u.Path = strings.TrimRight(base.Path, "/") + path
	if q == nil {
		q = url.Values{}
	}
	bearer := base == c.api && strings.HasPrefix(c.key, "eyJ")
	if base == c.api && !bearer {
		// Een v4 read-token is een JWT en gaat als Bearer; een v3-sleutel is hex.
		q.Set("api_key", c.key)
	}
	u.RawQuery = q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, "", err
	}
	if bearer {
		req.Header.Set("Authorization", "Bearer "+c.key)
	}
	req.Header.Set("Accept", accept)

	resp, err := c.hc.Do(req)
	if err != nil {
		// De fout bevat de URL en daarmee mogelijk de sleutel in de querystring.
		return nil, "", errors.New("provider onbereikbaar: " + redact(err.Error(), c.key))
	}
	defer resp.Body.Close()

	switch {
	case resp.StatusCode == http.StatusTooManyRequests:
		after := 10 * time.Second
		if s, err := strconv.Atoi(resp.Header.Get("Retry-After")); err == nil && s > 0 {
			after = time.Duration(s) * time.Second
		}
		return nil, "", ErrRateLimited{After: after}
	case resp.StatusCode >= 300 && resp.StatusCode < 400:
		return nil, "", fmt.Errorf("provider verwees door (%d); redirects worden niet gevolgd", resp.StatusCode)
	case resp.StatusCode == http.StatusUnauthorized:
		return nil, "", errors.New("provider weigert de sleutel (401)")
	case resp.StatusCode == http.StatusNotFound:
		return nil, "", catalog.ErrNotFound
	case resp.StatusCode != http.StatusOK:
		return nil, "", fmt.Errorf("provider antwoordde %d", resp.StatusCode)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, limit+1))
	if err != nil {
		return nil, "", err
	}
	if int64(len(body)) > limit {
		return nil, "", errors.New("antwoord van de provider is groter dan de grens")
	}
	return body, resp.Header.Get("Content-Type"), nil
}

func redact(s, key string) string {
	if key == "" {
		return s
	}
	return strings.ReplaceAll(s, key, "***")
}

func (c *TMDB) getJSON(ctx context.Context, path string, q url.Values, out any) error {
	body, ctype, err := c.get(ctx, c.api, path, q, "application/json", maxJSONBytes)
	if err != nil {
		return err
	}
	// Een HTML-foutpagina of een captive portal mag geen record beschadigen.
	if !strings.HasPrefix(strings.ToLower(ctype), "application/json") {
		return fmt.Errorf("provider antwoordde geen JSON (%s)", ctype)
	}
	if err := json.Unmarshal(body, out); err != nil {
		return errors.New("provider-antwoord onleesbaar")
	}
	return nil
}

func tmdbKind(kind string) string {
	if kind == "show" {
		return "tv"
	}
	return "movie"
}

func yearOf(date string) int {
	if len(date) < 4 {
		return 0
	}
	n, err := strconv.Atoi(date[:4])
	if err != nil {
		return 0
	}
	return n
}

// Search zoekt een titel. kind is het itemsoort uit de catalogus (movie of show).
func (c *TMDB) Search(ctx context.Context, kind, title string, year *int) ([]SearchResult, error) {
	q := url.Values{"query": {title}, "language": {c.language}, "include_adult": {"false"}}
	var raw struct {
		Results []struct {
			ID            int    `json:"id"`
			Title         string `json:"title"`
			Name          string `json:"name"`
			OriginalTitle string `json:"original_title"`
			OriginalName  string `json:"original_name"`
			ReleaseDate   string `json:"release_date"`
			FirstAirDate  string `json:"first_air_date"`
		} `json:"results"`
	}
	if err := c.getJSON(ctx, "/search/"+tmdbKind(kind), q, &raw); err != nil {
		return nil, err
	}
	out := make([]SearchResult, 0, len(raw.Results))
	for _, r := range raw.Results {
		res := SearchResult{ID: r.ID, Title: r.Title, OriginalTitle: r.OriginalTitle, Year: yearOf(r.ReleaseDate)}
		if kind == "show" {
			res = SearchResult{ID: r.ID, Title: r.Name, OriginalTitle: r.OriginalName, Year: yearOf(r.FirstAirDate)}
		}
		out = append(out, res)
	}
	return out, nil
}

type tmdbDetails struct {
	Overview     string `json:"overview"`
	PosterPath   string `json:"poster_path"`
	BackdropPath string `json:"backdrop_path"`
	Genres       []struct {
		Name string `json:"name"`
	} `json:"genres"`
	ReleaseDates struct {
		Results []struct {
			Country string `json:"iso_3166_1"`
			Dates   []struct {
				Certification string `json:"certification"`
			} `json:"release_dates"`
		} `json:"results"`
	} `json:"release_dates"`
	ContentRatings struct {
		Results []struct {
			Country string `json:"iso_3166_1"`
			Rating  string `json:"rating"`
		} `json:"results"`
	} `json:"content_ratings"`
}

// ratingCountries is de voorkeursvolgorde voor de kijkwijzer: eerst het land van
// de taal, dan de Amerikaanse.
func (c *TMDB) ratingCountries() []string {
	out := []string{}
	if i := strings.LastIndex(c.language, "-"); i >= 0 && i+1 < len(c.language) {
		out = append(out, strings.ToUpper(c.language[i+1:]))
	}
	return append(out, "US")
}

// Details haalt samenvatting, genres, kijkwijzer en afbeeldingsverwijzingen.
// Is de samenvatting in de voorkeurstaal leeg, dan volgt één poging in het
// Engels: een Engelse tekst is voor de kijker beter dan een lege plek.
func (c *TMDB) Details(ctx context.Context, kind string, tmdbID int) (catalog.MetadataDetails, error) {
	extra := "release_dates"
	if kind == "show" {
		extra = "content_ratings"
	}
	var d tmdbDetails
	path := fmt.Sprintf("/%s/%d", tmdbKind(kind), tmdbID)
	if err := c.getJSON(ctx, path, url.Values{"language": {c.language}, "append_to_response": {extra}}, &d); err != nil {
		return catalog.MetadataDetails{}, err
	}

	out := catalog.MetadataDetails{
		Summary:     strings.TrimSpace(d.Overview),
		PosterRef:   d.PosterPath,
		BackdropRef: d.BackdropPath,
	}
	for _, g := range d.Genres {
		if g.Name != "" {
			out.Genres = append(out.Genres, g.Name)
		}
	}
	for _, country := range c.ratingCountries() {
		if out.ContentRating = rating(&d, country); out.ContentRating != "" {
			break
		}
	}

	if out.Summary == "" && !strings.HasPrefix(c.language, "en") {
		var en tmdbDetails
		if err := c.getJSON(ctx, path, url.Values{"language": {"en-US"}}, &en); err == nil {
			out.Summary = strings.TrimSpace(en.Overview)
		}
	}
	return out, nil
}

func rating(d *tmdbDetails, country string) string {
	for _, r := range d.ReleaseDates.Results {
		if r.Country != country {
			continue
		}
		for _, rd := range r.Dates {
			if rd.Certification != "" {
				return rd.Certification
			}
		}
	}
	for _, r := range d.ContentRatings.Results {
		if r.Country == country && r.Rating != "" {
			return r.Rating
		}
	}
	return ""
}

// Image haalt de bytes van een afbeelding. ref is het pad dat Details gaf.
func (c *TMDB) Image(ctx context.Context, kind, ref string) ([]byte, string, error) {
	size := posterSize
	if kind == "backdrop" {
		size = backdropSize
	}
	// ref komt van de provider; alleen een eenvoudig pad is toegestaan.
	if !strings.HasPrefix(ref, "/") || strings.Contains(ref, "..") || strings.ContainsAny(ref, "?#\\") {
		return nil, "", errors.New("onbruikbare afbeeldingsverwijzing")
	}
	body, ctype, err := c.get(ctx, c.image, "/"+size+ref, nil, "image/*", maxImageBytes)
	if err != nil {
		return nil, "", err
	}
	switch strings.ToLower(strings.TrimSpace(strings.Split(ctype, ";")[0])) {
	case "image/jpeg":
		return body, ".jpg", nil
	case "image/png":
		return body, ".png", nil
	case "image/webp":
		return body, ".webp", nil
	}
	return nil, "", fmt.Errorf("onverwacht afbeeldingstype %q", ctype)
}
