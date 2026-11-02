package api_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/artwork"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/metadata"
	"image"
	"image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestArtworkPinsRoutesAndClosedWrites(t *testing.T) {
	e := newEnv(t, withCacheDir(t.TempDir()))
	e.setup(e.putSetupCode())
	path := "/pleya/v1/items/" + e.findMovie("Grease").ID
	if r := e.do(http.MethodGet, path+"/artwork-candidates", nil); r.Code != http.StatusOK {
		t.Fatalf("artwork candidates: %d %s", r.Code, r.Body.String())
	}
	for _, body := range []any{map[string]any{}, map[string]any{"poster": "https://evil.test/poster.jpg"}, map[string]any{"base_token": "bad", "poster": nil}, map[string]any{"base_token": "bad", "upload": "bytes"}} {
		if r := e.do(http.MethodPut, path+"/artwork", body); r.Code != http.StatusBadRequest {
			t.Fatalf("invalid artwork body %+v: %d %s", body, r.Code, r.Body.String())
		}
	}
}

type pinProvider struct {
	mu sync.Mutex
	previewProvider
	imageCalls, listCalls int
	listKind              string
	listID                int
	images                []metadata.ImageChoice
	imageAfter            func(context.Context)
}

func (p *pinProvider) Images(ctx context.Context, kind string, n int) ([]metadata.ImageChoice, error) {
	p.listCalls++
	p.listKind = kind
	p.listID = n
	return p.images, p.err
}
func (p *pinProvider) Image(ctx context.Context, kind, ref string) ([]byte, string, error) {
	p.mu.Lock()
	p.imageCalls++
	p.mu.Unlock()
	if p.imageAfter != nil {
		p.imageAfter(ctx)
	}
	return p.image, ".png", p.err
}
func withPinProvider(p *pinProvider) envOption {
	return func(o *api.Options) { o.MetadataProvider = p }
}
func pinPNG(t *testing.T) []byte {
	t.Helper()
	var b bytes.Buffer
	if err := png.Encode(&b, image.NewRGBA(image.Rect(0, 0, 4, 6))); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}
func pinApplied(t *testing.T, e *env, item string) {
	t.Helper()
	_, err := e.pool.Exec(context.Background(), `INSERT INTO metadata_candidates(item_id,provider,state,external_id,applied_provider,applied_external_id,application_state) VALUES($1,'tmdb','matched','2','tmdb','1','applied')`, item)
	if err != nil {
		t.Fatal(err)
	}
}
func pinChoices(t *testing.T, e *env, path string) api.ArtworkCandidates {
	t.Helper()
	var c api.ArtworkCandidates
	e.getJSON(path+"/artwork-candidates", "ArtworkCandidates", 200, &c)
	return c
}
func pinCandidate(t *testing.T, c api.ArtworkCandidates, role, source string) string {
	t.Helper()
	for _, v := range c.Candidates {
		if v.Role == role && v.Source == source && v.Available {
			return v.ID
		}
	}
	t.Fatalf("geen %s/%s kandidaat %+v", role, source, c)
	return ""
}
func putPin(t *testing.T, e *env, path, base, role string, choice *string, want int) api.ArtworkSelection {
	t.Helper()
	r := e.do(http.MethodPut, path+"/artwork", map[string]any{"base_token": base, role: choice})
	if r.Code != want {
		t.Fatalf("pin: %d %s, verwacht%d", r.Code, r.Body.String(), want)
	}
	var out api.ArtworkSelection
	if want == 200 {
		e.record("ArtworkSelection", http.MethodPut, path+"/artwork", r)
		if err := json.Unmarshal(r.Body.Bytes(), &out); err != nil {
			t.Fatal(err)
		}
	}
	return out
}

func TestArtworkPinsDuurzameKeuzeCacheherstelEnBronverlies(t *testing.T) {
	cache := t.TempDir()
	p := &pinProvider{images: []metadata.ImageChoice{{Kind: "poster", Ref: "/alternative.png"}, {Kind: "backdrop", Ref: "/wide.png"}}}
	p.image = pinPNG(t)
	e := newEnv(t, withArtwork(cache), withPinProvider(p))
	e.setup(e.putSetupCode())
	item := e.findMovie("Grease")
	path := "/pleya/v1/items/" + item.ID
	pinApplied(t, e, item.ID)
	choices := pinChoices(t, e, path)
	if p.listID != 1 || p.listKind != "movie" {
		t.Fatalf("requested identiteit gebruikt: %+v", p)
	}
	choice := pinCandidate(t, choices, "poster", "tmdb")
	selected := putPin(t, e, path, choices.BaseToken, "poster", &choice, 200)
	pin := selected.Pins["poster"]
	if pin == nil || pin.State != "ready" || pin.ArtworkID == "" {
		t.Fatalf("status %+v", selected)
	}
	get := func() *httptest.ResponseRecorder {
		return e.do(http.MethodGet, "/pleya/v1/artwork/"+pin.ArtworkID, nil)
	}
	first := get()
	if first.Code != 200 || !bytes.Equal(first.Body.Bytes(), p.image) {
		t.Fatalf("pinkeuze %d %s", first.Code, first.Body.String())
	}
	after := e.findMovie("Grease")
	if after.Artwork.PosterID == nil || *after.Artwork.PosterID != pin.ArtworkID {
		t.Fatalf("lokale ladder won van pin: %+v", after.Artwork)
	}
	if err := os.RemoveAll(filepath.Join(cache, "artwork-pins")); err != nil {
		t.Fatal(err)
	}
	freshStore := catalog.NewStore(e.pool)
	fresh := artwork.NewPins(freshStore, p, cache)
	stored, _, err := freshStore.ArtworkPin(context.Background(), id.MustParse(pin.ArtworkID))
	if err != nil {
		t.Fatal(err)
	}
	recovered, err := fresh.Resolve(context.Background(), stored)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(recovered.AbsPath, []byte("gewijzigde cachebytes"), 0600); err != nil {
		t.Fatal(err)
	}
	// Een gewijzigde cache is afgeleid en mag uitsluitend uit dezelfde bron herstellen.

	if rebuilt := get(); rebuilt.Code != 200 || rebuilt.Header().Get("ETag") != first.Header().Get("ETag") {
		t.Fatalf("herstel %d %s", rebuilt.Code, rebuilt.Body.String())
	}
	_ = seedBigPoster(t, e, cache, "poster")
	if got := e.findMovie("Grease"); got.Artwork.PosterID == nil || *got.Artwork.PosterID != pin.ArtworkID {
		t.Fatal("provider overschreef keuze")
	}
	if err := os.RemoveAll(filepath.Join(cache, "artwork-pins")); err != nil {
		t.Fatal(err)
	}
	p.err = errors.New("synthetische bron verdwenen")
	if gone := get(); gone.Code != 503 || !strings.Contains(gone.Body.String(), "library.artwork_source_unavailable") {
		t.Fatalf("bronverlies %d %s", gone.Code, gone.Body.String())
	}
	state := pinChoices(t, e, path)
	if state.Pins["poster"] == nil || state.Pins["poster"].ArtworkID != pin.ArtworkID || state.Pins["poster"].State != "unavailable" {
		t.Fatal("bronverlies ontpinde of gaf vals succes")
	}
	p.err = nil
	p.image = append(pinPNG(t), 0)
	if changed := get(); changed.Code != 409 || !strings.Contains(changed.Body.String(), "library.artwork_source_changed") {
		t.Fatalf("bronwijziging %d %s", changed.Code, changed.Body.String())
	}
	p.image = pinPNG(t)
	e.access = e.tokenFor(e.createUser("admin", "pin-next-admin")) // onafhankelijke beheerder; geen wall-clock-wacht voor de per-account limiter
	current := pinChoices(t, e, path)
	newChoice := pinCandidate(t, current, "poster", "tmdb")
	second := putPin(t, e, path, current.BaseToken, "poster", &newChoice, 200)
	if second.Pins["poster"].ArtworkID == pin.ArtworkID {
		t.Fatal("nieuwe keuze kreeg oude cache-identiteit")
	}
	secondImage := e.do(http.MethodGet, "/pleya/v1/artwork/"+second.Pins["poster"].ArtworkID, nil)
	if secondImage.Code != 200 || secondImage.Header().Get("ETag") == first.Header().Get("ETag") {
		t.Fatal("nieuwe keuze kreeg oude ETag")
	}
	putPin(t, e, path, choices.BaseToken, "poster", nil, 409)
	unpinned := putPin(t, e, path, second.BaseToken, "poster", nil, 200)
	if unpinned.Pins["poster"] != nil {
		t.Fatal("ontpinnen faalde")
	}
	var applied, requested string
	if err := e.pool.QueryRow(context.Background(), `SELECT applied_external_id,external_id FROM metadata_candidates WHERE item_id=$1`, item.ID).Scan(&applied, &requested); err != nil || applied != "1" || requested != "2" {
		t.Fatalf("identiteit gewijzigd: %s %s %v", applied, requested, err)
	}
}

func TestArtworkPinsGeslotenRequestGeenWriteOfAudit(t *testing.T) {
	e := newEnv(t, withArtwork(t.TempDir()))
	e.setup(e.putSetupCode())
	path := "/pleya/v1/items/" + e.findMovie("Grease").ID
	c := pinChoices(t, e, path)
	valid := `{"base_token":"` + c.BaseToken + `","poster":null}`
	var before int
	if err := e.pool.QueryRow(context.Background(), `SELECT count(*) FROM admin_audit`).Scan(&before); err != nil {
		t.Fatal(err)
	}
	for n, body := range []string{valid + ` {}`, valid + ` 1`, valid + ` garbage`, `{"base_token":"` + c.BaseToken + `","poster":null,"poster":null}`, `{"base_token":"` + c.BaseToken + `","poster":null,"url":"https://evil.test"}`} {
		e.access = e.tokenFor(e.createUser("admin", fmt.Sprintf("pin-invalid-%d", n)))
		r := e.do(http.MethodPut, path+"/artwork", nil, rawBody(body))
		if r.Code != 400 {
			t.Fatalf("geaccepteerd %s: %d %s", body, r.Code, r.Body.String())
		}
	}
	var after, pins int
	if err := e.pool.QueryRow(context.Background(), `SELECT count(*) FROM admin_audit`).Scan(&after); err != nil {
		t.Fatal(err)
	}
	if err := e.pool.QueryRow(context.Background(), `SELECT count(*) FROM artwork_pins`).Scan(&pins); err != nil {
		t.Fatal(err)
	}
	if after != before || pins != 0 {
		t.Fatalf("ongeldige write/audit %d->%d pins%d", before, after, pins)
	}
	if r := e.do(http.MethodPut, path+"/artwork", nil, rawBody(valid+" \n\t")); r.Code != 200 {
		t.Fatalf("whitespace %d %s", r.Code, r.Body.String())
	}
}

func TestArtworkPinsKeylessLokaleBronEnOntpinnen(t *testing.T) {
	cache := t.TempDir()
	e := newEnv(t, withArtwork(cache))
	e.setup(e.putSetupCode())
	item := e.findMovie("Grease")
	path := "/pleya/v1/items/" + item.ID
	var sourceID id.ID
	var sourcePath string
	err := e.pool.QueryRow(context.Background(), `SELECT f.id,l.root_path||'/'||f.relative_path FROM media_files f JOIN storage_locations l ON l.id=f.storage_location_id WHERE f.item_id=$1 AND f.artwork_kind='poster' AND f.missing_since IS NULL LIMIT 1`, item.ID).Scan(&sourceID, &sourcePath)
	if err != nil {
		t.Fatal(err)
	}
	original := pinPNG(t)
	if err := os.WriteFile(sourcePath, original, 0600); err != nil {
		t.Fatal(err)
	}
	c := pinChoices(t, e, path)
	if c.ProviderState != "not_configured" {
		t.Fatal(c.ProviderState)
	}
	choice := pinCandidate(t, c, "poster", "local")
	selected := putPin(t, e, path, c.BaseToken, "poster", &choice, 200)
	pin := selected.Pins["poster"]
	url := "/pleya/v1/artwork/" + pin.ArtworkID
	if err := os.RemoveAll(filepath.Join(cache, "artwork-pins")); err != nil {
		t.Fatal(err)
	}
	if r := e.do(http.MethodGet, url, nil); r.Code != 200 || !bytes.Equal(r.Body.Bytes(), original) {
		t.Fatalf("keyless herstel %d %s", r.Code, r.Body.String())
	}
	if err := os.Remove(sourcePath); err != nil {
		t.Fatal(err)
	}
	if err := os.RemoveAll(filepath.Join(cache, "artwork-pins")); err != nil {
		t.Fatal(err)
	}
	if _, err := e.pool.Exec(context.Background(), `DELETE FROM media_files WHERE id=$1`, sourceID); err != nil {
		t.Fatal(err)
	}
	if r := e.do(http.MethodGet, url, nil); r.Code != 503 {
		t.Fatalf("verdwenen lokale bron %d %s", r.Code, r.Body.String())
	}
	current := pinChoices(t, e, path)
	if current.Pins["poster"] == nil || current.Pins["poster"].ArtworkID != pin.ArtworkID || current.Pins["poster"].State != "unavailable" {
		t.Fatal("lokale bronverwijdering trok intentie in")
	}
	putPin(t, e, path, current.BaseToken, "poster", nil, 200)
	if r := e.do(http.MethodGet, url, nil); r.Code != 404 {
		t.Fatalf("oude pinURL gaf %d", r.Code)
	}
}

func TestArtworkPinsRechtenIntrekkingEnStalePublicatie(t *testing.T) {
	for _, mode := range []string{"revoked", "role", "rematch"} {
		t.Run(mode, func(t *testing.T) {
			p := &pinProvider{images: []metadata.ImageChoice{{Kind: "poster", Ref: "/safe.png"}}}
			p.image = pinPNG(t)
			e := newEnv(t, withArtwork(t.TempDir()), withPinProvider(p))
			e.setup(e.putSetupCode())
			item := e.findMovie("Grease")
			path := "/pleya/v1/items/" + item.ID
			pinApplied(t, e, item.ID)
			c := pinChoices(t, e, path)
			choice := pinCandidate(t, c, "poster", "tmdb")
			claims, err := e.signer.Verify(e.access, auth.TokenAccess)
			if err != nil {
				t.Fatal(err)
			}
			p.imageAfter = func(ctx context.Context) {
				switch mode {
				case "revoked":
					e.revocations.Revoke(id.MustParse(claims.Sid), time.Now())
				case "role":
					_, err = e.pool.Exec(ctx, `UPDATE users SET role='member' WHERE id=$1`, claims.Subject)
				case "rematch":
					err = e.store.SetManualMatch(ctx, id.MustParse(item.ID), "tmdb", "3")
				}
				if err != nil {
					t.Fatal(err)
				}
			}
			want := 409
			if mode == "revoked" {
				want = 401
			}
			if mode == "role" {
				want = 404
			}
			putPin(t, e, path, c.BaseToken, "poster", &choice, want)
			var pins, audit int
			if err := e.pool.QueryRow(context.Background(), `SELECT count(*) FROM artwork_pins`).Scan(&pins); err != nil {
				t.Fatal(err)
			}
			if err := e.pool.QueryRow(context.Background(), `SELECT count(*) FROM admin_audit WHERE operation='setArtworkPins'`).Scan(&audit); err != nil {
				t.Fatal(err)
			}
			if pins != 0 || audit != 0 {
				t.Fatalf("late write/audit %d/%d", pins, audit)
			}
		})
	}
}

func TestArtworkPinsAdminScopeEnKandidaatbinding(t *testing.T) {
	p := &pinProvider{images: []metadata.ImageChoice{{Kind: "poster", Ref: "/safe.png"}}}
	p.image = pinPNG(t)
	e := newEnv(t, withArtwork(t.TempDir()), withPinProvider(p))
	e.setup(e.putSetupCode())
	item := e.findMovie("Grease")
	path := "/pleya/v1/items/" + item.ID
	pinApplied(t, e, item.ID)
	member := e.tokenFor(e.createUser("member", "pin-member"))
	limited := e.createToken(map[string]any{"name": "pin-read", "scope": "read"}, 201)
	for _, token := range []string{member, limited.Secret} {
		for _, method := range []string{http.MethodGet, http.MethodPut} {
			suffix := "/artwork-candidates"
			if method == http.MethodPut {
				suffix = "/artwork"
			}
			if r := e.do(method, path+suffix, map[string]any{}, asUser(token)); r.Code != 404 {
				t.Fatalf("scope %s %d %s", method, r.Code, r.Body.String())
			}
		}
	}
	c := pinChoices(t, e, path)
	choice := pinCandidate(t, c, "poster", "tmdb")
	putPin(t, e, path, c.BaseToken, "backdrop", &choice, 409)
	otherPath := "/pleya/v1/items/" + e.findMovie("Blade Runner").ID
	other := pinChoices(t, e, otherPath)
	putPin(t, e, otherPath, other.BaseToken, "poster", &choice, 409)
	if p.imageCalls != 0 {
		t.Fatal("ongeldige binding haalde bytes op")
	}
}

func TestArtworkPinsDrieVerseRunnersRematchRejectEnGC(t *testing.T) {
	cache := t.TempDir()
	p := &pinProvider{images: []metadata.ImageChoice{{Kind: "poster", Ref: "/chosen.png"}}}
	p.image = pinPNG(t)
	e := newEnv(t, withArtwork(cache), withPinProvider(p))
	e.setup(e.putSetupCode())
	item := e.findMovie("Grease")
	itemID := id.MustParse(item.ID)
	path := "/pleya/v1/items/" + item.ID
	pinApplied(t, e, item.ID)
	c := pinChoices(t, e, path)
	choice := pinCandidate(t, c, "poster", "tmdb")
	selection := putPin(t, e, path, c.BaseToken, "poster", &choice, 200)
	chosenID := selection.Pins["poster"].ArtworkID
	pins := artwork.NewPins(catalog.NewStore(e.pool), p, cache)
	stored, _, err := e.store.ArtworkPin(context.Background(), id.MustParse(chosenID))
	if err != nil {
		t.Fatal(err)
	}
	file, err := pins.Resolve(context.Background(), stored)
	if err != nil {
		t.Fatal(err)
	}
	old := time.Now().Add(-2 * time.Hour)
	if err := os.Chtimes(file.AbsPath, old, old); err != nil {
		t.Fatal(err)
	}
	orphan := filepath.Join(cache, "artwork-pins", "old-orphan.png")
	if err := os.WriteFile(orphan, []byte("orphan"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(orphan, old, old); err != nil {
		t.Fatal(err)
	}
	for n := 0; n < 3; n++ {
		if err := e.store.SetManualMatch(context.Background(), itemID, "tmdb", fmt.Sprint(n+10)); err != nil {
			t.Fatal(err)
		}
		runner := metadata.NewRunner(catalog.NewStore(e.pool), p, "tmdb", cache, e.log)
		if _, err := runner.Round(context.Background()); err != nil {
			t.Fatal(err)
		}
		if got := e.findMovie("Grease"); got.Artwork.PosterID == nil || *got.Artwork.PosterID != chosenID {
			t.Fatalf("ronde%d overschreef pin", n)
		}
	}
	if _, err := e.store.RejectMatch(context.Background(), itemID, "tmdb"); err != nil {
		t.Fatal(err)
	}
	if got := e.findMovie("Grease"); got.Artwork.PosterID == nil || *got.Artwork.PosterID != chosenID {
		t.Fatal("reject wiste pin")
	}
	if err := pins.Trim(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(file.AbsPath); err != nil {
		t.Fatal("actieve pincache door GC verwijderd")
	}
	if _, err := os.Stat(orphan); !os.IsNotExist(err) {
		t.Fatal("oude verweesde cache niet opgeruimd")
	}
	if r := e.do(http.MethodGet, "/pleya/v1/artwork/"+chosenID, nil); r.Code != 200 {
		t.Fatalf("gekozen bron na reject %d %s", r.Code, r.Body.String())
	}
}

func TestArtworkPinsKapottePixelsVervangenBestaandeKeuzeNiet(t *testing.T) {
	p := &pinProvider{images: []metadata.ImageChoice{{Kind: "poster", Ref: "/safe.png"}}}
	p.image = pinPNG(t)
	e := newEnv(t, withArtwork(t.TempDir()), withPinProvider(p))
	e.setup(e.putSetupCode())
	item := e.findMovie("Grease")
	path := "/pleya/v1/items/" + item.ID
	pinApplied(t, e, item.ID)
	c := pinChoices(t, e, path)
	choice := pinCandidate(t, c, "poster", "tmdb")
	first := putPin(t, e, path, c.BaseToken, "poster", &choice, 200)
	next := pinChoices(t, e, path)
	choice = pinCandidate(t, next, "poster", "tmdb")
	p.image = p.image[:33] // Volledige geldige PNG-IHDR, geen IDAT/pixelpayload.
	putPin(t, e, path, next.BaseToken, "poster", &choice, 502)
	state, err := e.store.ArtworkState(context.Background(), id.MustParse(item.ID))
	if err != nil || len(state.Pins) != 1 || state.Pins[0].ID.String() != first.Pins["poster"].ArtworkID {
		t.Fatalf("kapotte afbeelding publiceerde nieuwe intentie %+v %v", state, err)
	}
}

func TestArtworkPinsConcurrentCacheherbouwBegrensdEnAnnuleerbaar(t *testing.T) {
	cache := t.TempDir()
	p := &pinProvider{}
	p.image = pinPNG(t)
	e := newEnv(t, withArtwork(cache), withPinProvider(p))
	e.setup(e.putSetupCode())
	ctx := context.Background()
	var lib id.ID
	if err := e.pool.QueryRow(ctx, `SELECT library_id FROM media_items WHERE kind='movie' LIMIT 1`).Scan(&lib); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(p.image)
	digest := hex.EncodeToString(sum[:])
	ref := "/rebuild.png"
	stored := []catalog.ArtworkPin{}
	for n := 0; n < 3; n++ {
		item := id.New()
		if _, err := e.pool.Exec(ctx, `INSERT INTO media_items(id,library_id,kind,grouping_key,title) VALUES($1,$2,'movie',$3,'Herbouw')`, item, lib, fmt.Sprint(n)); err != nil {
			t.Fatal(err)
		}
		state, err := e.store.ArtworkState(ctx, item)
		if err != nil {
			t.Fatal(err)
		}
		pin := catalog.ArtworkPin{ID: id.New(), ItemID: item, Kind: "poster", Source: "tmdb", Ref: &ref, SHA256: digest, Extension: ".png"}
		if err := e.store.CommitArtworkPins(ctx, state, map[string]*catalog.ArtworkPin{"poster": &pin}); err != nil {
			t.Fatal(err)
		}
		stored = append(stored, pin)
	}
	entered := make(chan struct{}, 3)
	release := make(chan struct{})
	var releaseOnce sync.Once
	releaseAll := func() { releaseOnce.Do(func() { close(release) }) }
	defer releaseAll()
	var active, maxActive atomic.Int32
	p.imageAfter = func(ctx context.Context) {
		n := active.Add(1)
		for old := maxActive.Load(); n > old && !maxActive.CompareAndSwap(old, n); old = maxActive.Load() {
		}
		entered <- struct{}{}
		select {
		case <-release:
		case <-ctx.Done():
		}
		active.Add(-1)
	}
	pins := artwork.NewPins(catalog.NewStore(e.pool), p, cache)
	results := make(chan error, 3)
	for n := 0; n < 2; n++ {
		go func(pin catalog.ArtworkPin) { _, err := pins.Resolve(ctx, pin); results <- err }(stored[n])
	}
	for n := 0; n < 2; n++ {
		select {
		case <-entered:
		case <-time.After(2 * time.Second):
			t.Fatal("herbouw startte niet")
		}
	}
	cancelled, cancel := context.WithCancel(ctx)
	go func() { _, err := pins.Resolve(cancelled, stored[2]); results <- err }()
	select {
	case <-entered:
		t.Fatal("meer dan twee echte herbouw-I/O/decodepaden tegelijk")
	case <-time.After(50 * time.Millisecond):
	}
	cancel()
	select {
	case err := <-results:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("wachtende herbouw niet geannuleerd: %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("annulering bleef hangen")
	}
	releaseAll()
	for n := 0; n < 2; n++ {
		if err := <-results; err != nil {
			t.Fatal(err)
		}
	}
	if maxActive.Load() != 2 {
		t.Fatalf("werkelijke concurrentie %d", maxActive.Load())
	}
	for _, pin := range stored {
		if _, _, err := e.store.ArtworkPin(ctx, pin.ID); err != nil {
			t.Fatal("annulering/verlies wiste intentie")
		}
	}
}
