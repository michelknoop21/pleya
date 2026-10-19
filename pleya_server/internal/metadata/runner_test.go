package metadata

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

type fakeStore struct {
	targets    []catalog.MetadataTarget
	candidates map[id.ID]catalog.MetadataCandidate
	applied    map[id.ID]catalog.MetadataDetails
	art        map[string]catalog.ProviderArtwork
	localPost  map[id.ID]bool
}

func newFakeStore(ts ...catalog.MetadataTarget) *fakeStore {
	return &fakeStore{targets: ts, candidates: map[id.ID]catalog.MetadataCandidate{},
		applied: map[id.ID]catalog.MetadataDetails{}, art: map[string]catalog.ProviderArtwork{},
		localPost: map[id.ID]bool{}}
}

func (f *fakeStore) MetadataDue(_ context.Context, _ string, exclude []id.ID, limit int) ([]catalog.MetadataTarget, error) {
	skip := map[id.ID]bool{}
	for _, e := range exclude {
		skip[e] = true
	}
	var out []catalog.MetadataTarget
	for _, t := range f.targets {
		if _, done := f.candidates[t.ID]; !done && !skip[t.ID] && len(out) < limit {
			out = append(out, t)
		}
	}
	return out, nil
}
func (f *fakeStore) SaveCandidate(_ context.Context, c catalog.MetadataCandidate) error {
	f.candidates[c.ItemID] = c
	return nil
}
func (f *fakeStore) ApplyMetadata(_ context.Context, item id.ID, _ string, d catalog.MetadataDetails) error {
	f.applied[item] = d
	return nil
}
func (f *fakeStore) LocalArtwork(_ context.Context, item id.ID) (bool, bool, error) {
	return f.localPost[item], false, nil
}
func (f *fakeStore) GetProviderArtwork(_ context.Context, item id.ID, kind, _ string) (catalog.ProviderArtwork, bool, error) {
	a, ok := f.art[item.String()+kind]
	return a, ok, nil
}
func (f *fakeStore) UpsertProviderArtwork(_ context.Context, a catalog.ProviderArtwork) error {
	f.art[a.ItemID.String()+a.Kind] = a
	return nil
}

type fakeProvider struct {
	results map[string][]SearchResult
	fail    map[string]error
	imgs    int
	calls   int
}

func (p *fakeProvider) Search(_ context.Context, _ string, title string, _ *int) ([]SearchResult, error) {
	p.calls++
	if err := p.fail[title]; err != nil {
		return nil, err
	}
	return p.results[title], nil
}
func (p *fakeProvider) Details(_ context.Context, _ string, n int) (catalog.MetadataDetails, error) {
	return catalog.MetadataDetails{Summary: "tekst", Genres: []string{"Drama"}, ContentRating: "12",
		PosterRef: "/p.jpg", BackdropRef: "/b.jpg"}, nil
}
func (p *fakeProvider) Image(context.Context, string, string) ([]byte, string, error) {
	p.imgs++
	return []byte("jpegbytes"), ".jpg", nil
}

func testRunner(s Store, p Provider, dir string) *Runner {
	r := NewRunner(s, p, ProviderTMDB, dir, slog.New(slog.NewTextHandler(io.Discard, nil)))
	r.maxRateWait = time.Millisecond
	return r
}

func TestRoundMatchesAppliesAndCachesArtwork(t *testing.T) {
	year := 1979
	alien := catalog.MetadataTarget{ID: id.New(), Kind: "movie", Title: "Alien", Year: &year}
	dub := catalog.MetadataTarget{ID: id.New(), Kind: "movie", Title: "Hamlet"}
	none := catalog.MetadataTarget{ID: id.New(), Kind: "movie", Title: "Onbekend"}
	st := newFakeStore(alien, dub, none)
	prov := &fakeProvider{results: map[string][]SearchResult{
		"Alien":  {{ID: 348, Title: "Alien", Year: 1979}},
		"Hamlet": {{ID: 1, Title: "Hamlet", Year: 1996}, {ID: 2, Title: "Hamlet", Year: 1990}},
	}}
	dir := t.TempDir()

	stats, err := testRunner(st, prov, dir).Round(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if stats.Matched != 1 || stats.Ambiguous != 1 || stats.Unmatched != 1 || stats.ArtworkSaved != 2 {
		t.Fatalf("stats %+v", stats)
	}
	if st.candidates[alien.ID].ExternalID != "348" || st.applied[alien.ID].Summary != "tekst" {
		t.Errorf("match niet toegepast: %+v", st.candidates[alien.ID])
	}
	if _, applied := st.applied[dub.ID]; applied {
		t.Error("een ambigu item kreeg toch providerwaarden")
	}
	if c := st.candidates[none.ID]; c.State != catalog.CandidateUnmatched || c.NextAttempt == nil {
		t.Errorf("unmatched zonder nieuwe poging: %+v", c)
	}
	if c := st.candidates[dub.ID]; c.State != catalog.CandidateAmbiguous || c.NextAttempt != nil {
		t.Errorf("ambigu hoort nooit vanzelf terug te komen: %+v", c)
	}
	poster := st.art[alien.ID.String()+"poster"]
	if _, err := os.Stat(filepath.Join(dir, "artwork", poster.FileName)); err != nil {
		t.Errorf("afbeelding niet in de cache: %v", err)
	}
}

func TestLocalPosterWinsOverProviderPoster(t *testing.T) {
	year := 1979
	alien := catalog.MetadataTarget{ID: id.New(), Kind: "movie", Title: "Alien", Year: &year}
	st := newFakeStore(alien)
	st.localPost[alien.ID] = true
	prov := &fakeProvider{results: map[string][]SearchResult{"Alien": {{ID: 348, Title: "Alien", Year: 1979}}}}

	stats, err := testRunner(st, prov, t.TempDir()).Round(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if _, has := st.art[alien.ID.String()+"poster"]; has || stats.ArtworkSaved != 1 {
		t.Fatalf("de lokale poster is overruled: stats %+v", stats)
	}
}

func TestTransientFailureLeavesItemForNextRound(t *testing.T) {
	a := catalog.MetadataTarget{ID: id.New(), Kind: "movie", Title: "A"}
	st := newFakeStore(a)
	prov := &fakeProvider{fail: map[string]error{"A": errors.New("provider onbereikbaar")}}

	stats, err := testRunner(st, prov, t.TempDir()).Round(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if _, recorded := st.candidates[a.ID]; recorded || stats.Failed != 1 {
		t.Fatalf("een tijdelijke fout werd als uitkomst vastgelegd: %+v", stats)
	}
	if prov.calls != 1 {
		t.Fatalf("het item werd binnen dezelfde ronde opnieuw geprobeerd (%d aanroepen)", prov.calls)
	}
}

func TestRateLimitIsRetriedThenSucceeds(t *testing.T) {
	a := catalog.MetadataTarget{ID: id.New(), Kind: "movie", Title: "A"}
	st := newFakeStore(a)
	n := 0
	prov := &flaky{inner: &fakeProvider{results: map[string][]SearchResult{"A": {{ID: 1, Title: "A"}}}}, failures: &n}

	stats, err := testRunner(st, prov, t.TempDir()).Round(context.Background())
	if err != nil || stats.Matched != 1 || n != 2 {
		t.Fatalf("stats %+v err %v 429's %d", stats, err, n)
	}
}

type flaky struct {
	inner    *fakeProvider
	failures *int
}

func (f *flaky) Search(ctx context.Context, k, t string, y *int) ([]SearchResult, error) {
	if *f.failures < 2 {
		*f.failures++
		return nil, ErrRateLimited{After: time.Second}
	}
	return f.inner.Search(ctx, k, t, y)
}
func (f *flaky) Details(ctx context.Context, k string, n int) (catalog.MetadataDetails, error) {
	return f.inner.Details(ctx, k, n)
}
func (f *flaky) Image(ctx context.Context, k, r string) ([]byte, string, error) {
	return f.inner.Image(ctx, k, r)
}

func TestRoundStopsAfterRepeatedFailures(t *testing.T) {
	var ts []catalog.MetadataTarget
	fail := map[string]error{}
	for _, n := range []string{"a", "b", "c", "d", "e", "f", "g"} {
		ts = append(ts, catalog.MetadataTarget{ID: id.New(), Kind: "movie", Title: n})
		fail[n] = errors.New("plat")
	}
	prov := &fakeProvider{fail: fail}
	_, err := testRunner(newFakeStore(ts...), prov, t.TempDir()).Round(context.Background())
	if err == nil || prov.calls != 5 {
		t.Fatalf("ronde stopte niet na vijf fouten: err=%v calls=%d", err, prov.calls)
	}
}
