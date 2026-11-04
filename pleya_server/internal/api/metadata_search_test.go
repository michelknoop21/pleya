package api_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/metadata"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestMetadataSearchProviderOff(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	base := "/pleya/v1/items/" + e.findMovie("Grease").ID
	for _, suffix := range []string{"/metadata-search?title=Grease", "/metadata-candidates/1", "/metadata-candidate-artwork?role=poster&ref=/safe.png"} {
		rec := e.do(http.MethodGet, base+suffix, nil)
		if rec.Code != http.StatusServiceUnavailable {
			t.Fatalf("provider off: got %d, want 503: %s", rec.Code, rec.Body.String())
		}
	}
	var info api.Info
	e.getJSON("/pleya/v1/info", "", 200, &info)
	if info.Capabilities.MetadataSearch {
		t.Fatal("provider-off advertised search")
	}
}

type previewProvider struct {
	calls       int
	err         error
	after       func(context.Context)
	kind, title string
	year        *int
	image       []byte
}

func (p *previewProvider) Search(ctx context.Context, k, title string, y *int) ([]metadata.SearchResult, error) {
	p.calls++
	p.kind, p.title, p.year = k, title, y
	if p.after != nil {
		p.after(ctx)
	}
	var out []metadata.SearchResult
	for n := 1; n <= 25; n++ {
		out = append(out, metadata.SearchResult{ID: n, Title: fmt.Sprintf("Candidate %d", n), Year: 2001, OriginalTitle: "Original"})
	}
	return out, p.err
}
func (p *previewProvider) Details(ctx context.Context, k string, n int) (catalog.MetadataDetails, error) {
	p.calls++
	p.kind = k
	if p.after != nil {
		p.after(ctx)
	}
	return catalog.MetadataDetails{Summary: "Provider summary", Genres: []string{"Drama"}, PosterRef: "/safe.jpg", BackdropRef: "https://evil.test/key"}, p.err
}
func (p *previewProvider) Image(ctx context.Context, k, ref string) ([]byte, string, error) {
	p.calls++
	if p.after != nil {
		p.after(ctx)
	}
	return p.image, ".png", p.err
}
func withPreview(p *previewProvider) envOption {
	return func(o *api.Options) { o.MetadataProvider = p }
}
func TestMetadataSearchReadOnlyBoundedAndDetails(t *testing.T) {
	p := &previewProvider{}
	e := newEnv(t, withPreview(p))
	e.setup(e.putSetupCode())
	item := e.findMovie("Grease")
	path := "/pleya/v1/items/" + item.ID
	var results api.MetadataSearchResults
	e.getJSON(path+"/metadata-search?title=%20New%20title%20&year=2001", "MetadataSearchResults", 200, &results)
	if len(results.Items) != 20 || p.calls != 1 || p.title != "New title" || p.kind != "movie" || p.year == nil || *p.year != 2001 {
		t.Fatalf("results/binding: %+v %+v", results, p)
	}
	var d api.MetadataCandidateDetails
	e.getJSON(path+"/metadata-candidates/1", "MetadataCandidateDetails", 200, &d)
	if d.ExternalID != "1" || d.Summary != "Provider summary" || d.PosterRef == nil || d.BackdropRef != nil || p.calls != 2 {
		t.Fatalf("details: %+v calls %d", d, p.calls)
	}
	after := e.findMovie("Grease")
	if after.Title != item.Title || after.Year == nil || *after.Year != *item.Year {
		t.Fatal("preview changed scanner identity")
	}
	var count int
	if err := e.pool.QueryRow(context.Background(), `SELECT count(*) FROM metadata_candidates WHERE item_id=$1`, item.ID).Scan(&count); err != nil || count != 0 {
		t.Fatalf("preview wrote candidate: %d %v", count, err)
	}
	var info api.Info
	e.getJSON("/pleya/v1/info", "", 200, &info)
	if !info.Capabilities.MetadataSearch {
		t.Fatal("missing capability")
	}
}
func TestMetadataSearchClosedInputs(t *testing.T) {
	for _, suffix := range []string{"/metadata-search", "/metadata-search?title=", "/metadata-search?title=A&year=0", "/metadata-search?title=A&year=02001", "/metadata-search?title=A&year=10000", "/metadata-search?title=A&title=B", "/metadata-search?title=A&url=https://evil.test", "/metadata-search?title=A%0Asecret", "/metadata-search?title=" + strings.Repeat("a", 201), "/metadata-candidates/01", "/metadata-candidates/0", "/metadata-candidates/99999999999", "/metadata-candidates/1?x=y", "/metadata-candidate-artwork?role=poster&ref=https://evil.test/a.jpg", "/metadata-candidate-artwork?role=poster&ref=/../a.jpg", "/metadata-candidate-artwork?role=poster&ref=//evil.jpg", "/metadata-candidate-artwork?role=avatar&ref=/safe.jpg"} {
		t.Run(suffix, func(t *testing.T) {
			p := &previewProvider{}
			e := newEnv(t, withPreview(p))
			e.setup(e.putSetupCode())
			rec := e.do(http.MethodGet, "/pleya/v1/items/"+e.findMovie("Grease").ID+suffix, nil)
			if rec.Code != 400 || p.calls != 0 {
				t.Fatalf("input: %d calls %d %s", rec.Code, p.calls, rec.Body.String())
			}
		})
	}
}
func TestMetadataSearchProviderFailuresAreSafe(t *testing.T) {
	for _, err := range []error{errors.New("secret https://host/api?api_key=private /media/file"), metadata.ErrRateLimited{After: 2 * time.Second}} {
		p := &previewProvider{err: err}
		e := newEnv(t, withPreview(p))
		e.setup(e.putSetupCode())
		rec := e.do(http.MethodGet, "/pleya/v1/items/"+e.findMovie("Grease").ID+"/metadata-search?title=A", nil)
		want := 502
		if _, ok := err.(metadata.ErrRateLimited); ok {
			want = 429
			if rec.Header().Get("Retry-After") == "" {
				t.Fatal("missing retry")
			}
		}
		if rec.Code != want || strings.Contains(rec.Body.String(), "private") || strings.Contains(rec.Body.String(), "/media") {
			t.Fatalf("unsafe failure: %d %s", rec.Code, rec.Body.String())
		}
	}
}
func TestMetadataSearchImagePayloadAndRateLimit(t *testing.T) {
	p := &previewProvider{image: []byte("<svg>bad</svg>")}
	e := newEnv(t, withPreview(p))
	e.setup(e.putSetupCode())
	path := "/pleya/v1/items/" + e.findMovie("Grease").ID
	rec := e.do(http.MethodGet, path+"/metadata-candidate-artwork?role=poster&ref=/safe.png", nil)
	if rec.Code != 502 {
		t.Fatalf("unsafe image: %d", rec.Code)
	}
	// Real PNG signature plus IHDR, recognized by net/http; only synthetic bytes.
	p.image = []byte{137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82}
	rec = e.do(http.MethodGet, path+"/metadata-candidate-artwork?role=poster&ref=/safe.png", nil)
	if rec.Code != 200 || rec.Header().Get("Content-Type") != "image/png" || rec.Header().Get("Cache-Control") != "private, no-store" {
		t.Fatalf("image response: %d %v", rec.Code, rec.Header())
	}
	for n := 0; n < 3; n++ {
		e.do(http.MethodGet, path+"/metadata-search?title=A", nil)
	}
	rec = e.do(http.MethodGet, path+"/metadata-search?title=A", nil)
	if rec.Code != 429 || p.calls != 5 {
		t.Fatalf("rate limit: %d calls %d", rec.Code, p.calls)
	}
}
func TestMetadataSearchRechecksRoleAfterProviderAwait(t *testing.T) {
	p := &previewProvider{}
	e := newEnv(t, withPreview(p))
	e.setup(e.putSetupCode())
	p.after = func(context.Context) {
		if _, err := e.pool.Exec(context.Background(), `UPDATE users SET role='member' WHERE username='michel'`); err != nil {
			t.Fatal(err)
		}
	}
	rec := e.do(http.MethodGet, "/pleya/v1/items/"+e.findMovie("Grease").ID+"/metadata-search?title=A", nil)
	if rec.Code != 404 || strings.Contains(rec.Body.String(), "Candidate") {
		t.Fatalf("role changed: %d %s", rec.Code, rec.Body.String())
	}
}
func TestMetadataSearchMissingAndUnauthorized(t *testing.T) {
	p := &previewProvider{}
	e := newEnv(t, withPreview(p))
	e.setup(e.putSetupCode())
	path := "/pleya/v1/items/" + e.findMovie("Grease").ID
	for _, suffix := range []string{"/metadata-search?title=A", "/metadata-candidates/1", "/metadata-candidate-artwork?role=poster&ref=/safe.png"} {
		if rec := e.do(http.MethodGet, path+suffix, nil, withoutAuth); rec.Code != 401 {
			t.Fatalf("unauth %d", rec.Code)
		}
	}
	rec := e.do(http.MethodGet, "/pleya/v1/items/00000000-0000-0000-0000-000000000001/metadata-search?title=A", nil)
	if rec.Code != 404 || p.calls != 0 {
		t.Fatalf("missing %d calls %d", rec.Code, p.calls)
	}
	var info map[string]any
	rec = e.do(http.MethodGet, "/pleya/v1/info", nil)
	_ = json.Unmarshal(rec.Body.Bytes(), &info)
}

func TestMetadataSearchScopeRevocationAndCancellation(t *testing.T) {
	t.Run("member and token scope", func(t *testing.T) {
		p := &previewProvider{}
		e := newEnv(t, withPreview(p))
		e.setup(e.putSetupCode())
		member := e.tokenFor(e.createUser("member", "search-member"))
		limited := e.createToken(map[string]any{"name": "search read", "scope": "read"}, http.StatusCreated)
		path := "/pleya/v1/items/" + e.findMovie("Grease").ID
		for _, suffix := range []string{"/metadata-search?title=A", "/metadata-candidates/1", "/metadata-candidate-artwork?role=poster&ref=/safe.png"} {
			for _, token := range []string{member, limited.Secret} {
				rec := e.do(http.MethodGet, path+suffix, nil, asUser(token))
				if rec.Code != 404 {
					t.Fatalf("scope: %d %s", rec.Code, rec.Body.String())
				}
			}
		}
		if p.calls != 0 {
			t.Fatal("unauthorized provider call")
		}
	})
	t.Run("revoked during provider", func(t *testing.T) {
		p := &previewProvider{}
		e := newEnv(t, withPreview(p))
		e.setup(e.putSetupCode())
		claims, err := e.signer.Verify(e.access, auth.TokenAccess)
		if err != nil {
			t.Fatal(err)
		}
		p.after = func(context.Context) { e.revocations.Revoke(id.MustParse(claims.Sid), time.Now()) }
		rec := e.do(http.MethodGet, "/pleya/v1/items/"+e.findMovie("Grease").ID+"/metadata-candidates/1", nil)
		if rec.Code != 401 || strings.Contains(rec.Body.String(), "Provider summary") {
			t.Fatalf("revoked: %d %s", rec.Code, rec.Body.String())
		}
	})
	t.Run("canceled read", func(t *testing.T) {
		p := &previewProvider{}
		e := newEnv(t, withPreview(p))
		e.setup(e.putSetupCode())
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		p.after = func(context.Context) { cancel() }
		rec := e.do(http.MethodGet, "/pleya/v1/items/"+e.findMovie("Grease").ID+"/metadata-search?title=A", nil, func(r *http.Request) { *r = *r.WithContext(ctx) })
		if rec.Body.Len() != 0 {
			t.Fatalf("canceled preview leaked body: %s", rec.Body.String())
		}
	})
	t.Run("show binding", func(t *testing.T) {
		p := &previewProvider{}
		e := newEnv(t, withPreview(p))
		e.setup(e.putSetupCode())
		var shows api.ItemPage
		e.getJSON("/pleya/v1/libraries/"+e.libraryID("shows")+"/items", "", 200, &shows)
		rec := e.do(http.MethodGet, "/pleya/v1/items/"+shows.Items[0].ID+"/metadata-search?title=Show", nil)
		if rec.Code != 200 || p.kind != "show" {
			t.Fatalf("show: %d kind %s", rec.Code, p.kind)
		}
	})
	t.Run("wrong kind", func(t *testing.T) {
		p := &previewProvider{}
		e := newEnv(t, withPreview(p))
		e.setup(e.putSetupCode())
		var season string
		if err := e.pool.QueryRow(context.Background(), `SELECT id FROM media_items WHERE kind='season' LIMIT 1`).Scan(&season); err != nil {
			t.Fatal(err)
		}
		for _, suffix := range []string{"/metadata-search?title=A", "/metadata-candidates/1", "/metadata-candidate-artwork?role=poster&ref=/safe.png"} {
			if rec := e.do(http.MethodGet, "/pleya/v1/items/"+season+suffix, nil); rec.Code != 404 {
				t.Fatalf("wrong kind %d", rec.Code)
			}
		}
		if p.calls != 0 {
			t.Fatal("wrong kind hit provider")
		}
	})
}
