package api

import (
	"context"
	"errors"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/metadata"
)

// Candidate previews are read-only: they never write candidates, catalog fields or artwork.
type MetadataSearchCandidate struct {
	ExternalID    string `json:"external_id"`
	Title         string `json:"title"`
	OriginalTitle string `json:"original_title,omitempty"`
	Year          *int   `json:"year"`
}
type MetadataSearchResults struct {
	Items []MetadataSearchCandidate `json:"items"`
}
type MetadataCandidateDetails struct {
	ExternalID    string   `json:"external_id"`
	Summary       string   `json:"summary"`
	Genres        []string `json:"genres"`
	ContentRating string   `json:"content_rating"`
	PosterRef     *string  `json:"poster_ref"`
	BackdropRef   *string  `json:"backdrop_ref"`
}

// A single provider filename, never a URL, path traversal, query or alternate host.
var previewRefPattern = regexp.MustCompile(`^/[A-Za-z0-9_-]{1,200}\.(jpg|png|webp)$`)

func previewRef(ref string) *string {
	if !previewRefPattern.MatchString(ref) {
		return nil
	}
	return &ref
}

func (s *Server) metadataPreviewTarget(w http.ResponseWriter, r *http.Request) (catalog.Item, bool) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return catalog.Item{}, false
	}
	itemID, ok := s.pathID(w, r, "item_id")
	if !ok {
		return catalog.Item{}, false
	}
	item, err := s.opts.Catalog.Item(r.Context(), itemID)
	if err != nil {
		s.writeStoreError(w, err)
		return item, false
	}
	if item.Kind != "movie" && item.Kind != "show" {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return item, false
	}
	if !s.authorizeLibrary(w, r, item.LibraryID) {
		return item, false
	}
	return item, true
}

func (s *Server) beginMetadataPreview(w http.ResponseWriter, r *http.Request) (catalog.Item, bool) {
	item, ok := s.metadataPreviewTarget(w, r)
	if !ok {
		return item, false
	}
	if s.opts.MetadataProvider == nil {
		writeError(w, s.log, CodeMetadataUnavailable, "metadata provider unavailable", nil)
		return item, false
	}
	subject, _ := s.subjectID(r)
	if ok, wait := s.metadataLimiter.allow(subject.String()); !ok {
		w.Header().Set("Retry-After", strconv.Itoa(max(1, int(wait.Seconds())+1)))
		writeError(w, s.log, CodeRateLimited, "too many attempts", map[string]any{"retry_after_ms": wait.Milliseconds()})
		return item, false
	}
	return item, true
}

// Re-enter the existing authentication path after network waits: session/API-token
// revocation, current role, token scope and item/library visibility all remain live.
func (s *Server) finishMetadataPreview(w http.ResponseWriter, r *http.Request, write func()) {
	if r.Context().Err() != nil {
		return
	}
	s.authenticated(func(w http.ResponseWriter, r *http.Request) {
		if _, ok := s.metadataPreviewTarget(w, r); ok {
			write()
		}
	}).ServeHTTP(w, r)
}
func (s *Server) metadataPreviewError(w http.ResponseWriter, err error) {
	var limited metadata.ErrRateLimited
	if errors.As(err, &limited) {
		wait := max(time.Second, min(limited.After, time.Hour))
		w.Header().Set("Retry-After", strconv.Itoa(int(wait.Seconds())+1))
		writeError(w, s.log, CodeRateLimited, "metadata provider rate limited", map[string]any{"retry_after_ms": wait.Milliseconds()})
		return
	}
	writeError(w, s.log, CodeMetadataFailed, "metadata provider request failed", nil)
}
func closedPreviewQuery(r *http.Request, allowed ...string) bool {
	for k, v := range r.URL.Query() {
		found := false
		for _, a := range allowed {
			if a == k {
				found = true
			}
		}
		if !found || len(v) != 1 {
			return false
		}
	}
	return true
}
func (s *Server) invalidPreview(w http.ResponseWriter) {
	writeError(w, s.log, CodeMetadataInvalid, "metadata query invalid", nil)
}

func (s *Server) handleMetadataSearch(w http.ResponseWriter, r *http.Request) {
	item, ok := s.beginMetadataPreview(w, r)
	if !ok {
		return
	}
	title := strings.TrimSpace(r.URL.Query().Get("title"))
	if !closedPreviewQuery(r, "title", "year") || title == "" || !utf8.ValidString(title) || utf8.RuneCountInString(title) > 200 || strings.ContainsFunc(title, unicode.IsControl) {
		s.invalidPreview(w)
		return
	}
	var year *int
	if raw, exists := r.URL.Query()["year"]; exists {
		n, err := strconv.Atoi(raw[0])
		if err != nil || n < 1 || n > 9999 || strconv.Itoa(n) != raw[0] {
			s.invalidPreview(w)
			return
		}
		year = &n
	}
	ctx, cancel := context.WithTimeout(r.Context(), 35*time.Second)
	defer cancel()
	results, err := s.opts.MetadataProvider.Search(ctx, item.Kind, title, year)
	s.finishMetadataPreview(w, r, func() {
		if err != nil {
			s.metadataPreviewError(w, err)
			return
		}
		out := MetadataSearchResults{Items: []MetadataSearchCandidate{}}
		seen := map[int]bool{}
		for _, v := range results {
			raw := strconv.Itoa(v.ID)
			if !externalIDPattern.MatchString(raw) || strings.TrimSpace(v.Title) == "" || seen[v.ID] {
				continue
			}
			seen[v.ID] = true
			out.Items = append(out.Items, MetadataSearchCandidate{ExternalID: raw, Title: v.Title, OriginalTitle: v.OriginalTitle, Year: positiveInt(v.Year)})
			if len(out.Items) == 20 {
				break
			}
		}
		writeJSON(w, http.StatusOK, out)
	})
}
func (s *Server) handleMetadataCandidate(w http.ResponseWriter, r *http.Request) {
	item, ok := s.beginMetadataPreview(w, r)
	if !ok {
		return
	}
	raw := r.PathValue("external_id")
	n, err := strconv.Atoi(raw)
	if !externalIDPattern.MatchString(raw) || err != nil || !closedPreviewQuery(r) {
		s.invalidPreview(w)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 35*time.Second)
	defer cancel()
	d, err := s.opts.MetadataProvider.Details(ctx, item.Kind, n)
	s.finishMetadataPreview(w, r, func() {
		if err != nil {
			s.metadataPreviewError(w, err)
			return
		}
		genres := d.Genres
		if genres == nil {
			genres = []string{}
		}
		if len(genres) > 50 {
			genres = genres[:50]
		}
		summary := []rune(d.Summary)
		if len(summary) > 10000 {
			summary = summary[:10000]
		}
		writeJSON(w, http.StatusOK, MetadataCandidateDetails{ExternalID: raw, Summary: string(summary), Genres: genres, ContentRating: d.ContentRating, PosterRef: previewRef(d.PosterRef), BackdropRef: previewRef(d.BackdropRef)})
	})
}
func (s *Server) handleMetadataCandidateArtwork(w http.ResponseWriter, r *http.Request) {
	_, ok := s.beginMetadataPreview(w, r)
	if !ok {
		return
	}
	ref, role := r.URL.Query().Get("ref"), r.URL.Query().Get("role")
	if !closedPreviewQuery(r, "ref", "role") || previewRef(ref) == nil || (role != "poster" && role != "backdrop") {
		s.invalidPreview(w)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 35*time.Second)
	defer cancel()
	body, ext, err := s.opts.MetadataProvider.Image(ctx, role, ref)
	s.finishMetadataPreview(w, r, func() {
		if err != nil {
			s.metadataPreviewError(w, err)
			return
		}
		mime := http.DetectContentType(body)
		expected := map[string]string{".jpg": "image/jpeg", ".png": "image/png", ".webp": "image/webp"}[ext]
		if len(body) == 0 || len(body) > 12<<20 || expected == "" || mime != expected {
			s.metadataPreviewError(w, errors.New("invalid image payload"))
			return
		}
		w.Header().Set("Content-Type", mime)
		// Revalidation always requires current authentication; no shared or persistent cache.
		w.Header().Set("Cache-Control", "private, no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(body)
	})
}
