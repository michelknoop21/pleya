package api_test

import (
	"bytes"
	"context"
	"encoding/json"
	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/artwork"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	"image"
	"image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestArtworkCacheAdminStatsAndClosedConfirmation(t *testing.T) {
	var resize *artwork.Resizer
	e := newEnv(t, func(o *api.Options) {
		resize = artwork.New("ffmpeg", t.TempDir(), o.Logger)
		o.Artwork = resize
		o.Jobs.Register("artwork_cache_purge", func(ctx context.Context, _ jobs.Job) error { return resize.PurgeContext(ctx) })
	})
	e.setup(e.putSetupCode())
	if err := os.MkdirAll(resize.Dir(), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(resize.Dir(), "019a0000-0000-7000-8000-000000000001_1_480.jpg"), []byte("ladder"), 0600); err != nil {
		t.Fatal(err)
	}
	rec := e.do(http.MethodGet, "/pleya/v1/artwork/cache", nil)
	if rec.Code != 200 {
		t.Fatalf("stats %d: %s", rec.Code, rec.Body.String())
	}
	var got map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got["bytes"] != float64(6) || got["files"] != float64(1) {
		t.Fatalf("stats gesloten/exact: %v", got)
	}
	e.record("ArtworkCacheStats", http.MethodGet, "/pleya/v1/artwork/cache", rec)
	infoResponse := e.do(http.MethodGet, "/pleya/v1/info", nil)
	var info struct {
		Capabilities map[string]any `json:"capabilities"`
	}
	if err := json.Unmarshal(infoResponse.Body.Bytes(), &info); err != nil {
		t.Fatal(err)
	}
	if info.Capabilities["artwork_cache_admin"] != true {
		t.Fatal("volledige geregistreerde keten adverteert capability niet")
	}
	e.record("Info", http.MethodGet, "/pleya/v1/info", infoResponse)
	for _, body := range []string{"", `{}`, `null`, `{"confirm":"PURGE"}`, `{"confirm":"purge","path":"/media"}`, `{"confirm":"purge"} {}`, `{"confirm":"purge"} null`, `{"confirm":"no","confirm":"purge"}`, `{"Confirm":"purge"}`} {
		rec := e.do(http.MethodDelete, "/pleya/v1/artwork/cache", nil, rawBody(body))
		e.recordVariant("ErrorEnvelope", "cache_confirm", http.MethodDelete, "/pleya/v1/artwork/cache", rec)
		if rec.Code != 409 {
			t.Errorf("body %q: %d %s", body, rec.Code, rec.Body.String())
		}
	}
	var count int
	e.pool.QueryRow(t.Context(), `SELECT count(*) FROM jobs WHERE kind='artwork_cache_purge'`).Scan(&count)
	if count != 0 {
		t.Fatalf("ongeldige bevestiging plant %d jobs", count)
	}
	for i := 0; i < 2; i++ {
		rec = e.do(http.MethodDelete, "/pleya/v1/artwork/cache", map[string]string{"confirm": "purge"})
		if rec.Code != 202 || rec.Body.Len() != 0 {
			t.Fatalf("ontvangst %d %s", rec.Code, rec.Body.String())
		}
	}
	e.pool.QueryRow(t.Context(), `SELECT count(*) FROM jobs WHERE kind='artwork_cache_purge' AND state='pending'`).Scan(&count)
	if count != 1 {
		t.Fatalf("duurzame dedupe = %d", count)
	}
	if _, files, err := resize.Stats(); err != nil || files != 1 {
		t.Fatalf("202 heeft cache al gewist: %d %v", files, err)
	}
}

func TestArtworkCacheAdminUnavailableCannotAccept(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	rec := e.do(http.MethodGet, "/pleya/v1/info", nil)
	var info struct {
		Capabilities map[string]any `json:"capabilities"`
	}
	json.Unmarshal(rec.Body.Bytes(), &info)
	if info.Capabilities["artwork_cache_admin"] == true {
		t.Fatal("onvolledige keten adverteert capability")
	}
	rec = e.do(http.MethodDelete, "/pleya/v1/artwork/cache", map[string]string{"confirm": "purge"})
	if rec.Code == 202 {
		t.Fatal("geen volledige keten maar toch202")
	}
}

func TestArtworkCacheAdminDurableFailureRetryCancelAndAudit(t *testing.T) {
	var resize *artwork.Resizer
	var runner *jobs.Runner
	e := newEnv(t, func(o *api.Options) {
		resize = artwork.New("ffmpeg", t.TempDir(), o.Logger)
		o.Artwork = resize
		runner = o.Jobs
		runner.Register(api.JobArtworkCachePurge, func(ctx context.Context, _ jobs.Job) error { return resize.PurgeContext(ctx) })
	})
	e.setup(e.putSetupCode())
	outside := t.TempDir()
	source := filepath.Join(outside, "019a0000-0000-7000-8000-000000000001_1_480.jpg")
	if err := os.WriteFile(source, []byte("bron"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, resize.Dir()); err != nil {
		t.Fatal(err)
	}
	if rec := e.do(http.MethodDelete, "/pleya/v1/artwork/cache", map[string]string{"confirm": "purge"}); rec.Code != 202 {
		t.Fatal(rec.Code, rec.Body.String())
	}
	var jobID string
	if err := e.pool.QueryRow(t.Context(), `UPDATE jobs SET max_attempts=1 WHERE kind=$1 RETURNING id`, api.JobArtworkCachePurge).Scan(&jobID); err != nil {
		t.Fatal(err)
	}
	var auditCount int
	if err := e.pool.QueryRow(t.Context(), `SELECT count(*) FROM admin_audit WHERE operation='purgeArtworkCache' AND outcome='ok'`).Scan(&auditCount); err != nil {
		t.Fatal(err)
	}
	if auditCount != 1 {
		t.Fatalf("ontvangstaudit %d", auditCount)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { runner.Run(ctx); close(done) }()
	defer func() { cancel(); <-done }()
	waitState := func(want string) {
		t.Helper()
		deadline := time.Now().Add(5 * time.Second)
		for time.Now().Before(deadline) {
			rec, err := runner.Get(t.Context(), id.MustParse(jobID))
			if err == nil && rec.State == want {
				if want == "failed" && rec.LastError == "" {
					t.Fatal("fout verdwenen")
				}
				return
			}
			time.Sleep(10 * time.Millisecond)
		}
		t.Fatalf("job werd niet %s", want)
	}
	waitState("failed")
	if got, err := os.ReadFile(source); err != nil || string(got) != "bron" {
		t.Fatalf("bron geraakt %q %v", got, err)
	}
	if err := os.Remove(resize.Dir()); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(resize.Dir(), 0755); err != nil {
		t.Fatal(err)
	}
	cache := filepath.Join(resize.Dir(), filepath.Base(source))
	if err := os.WriteFile(cache, []byte("ladder"), 0600); err != nil {
		t.Fatal(err)
	}
	if rec := e.do(http.MethodPost, "/pleya/v1/jobs/"+jobID+"/retry", nil); rec.Code != 200 {
		t.Fatal(rec.Code, rec.Body.String())
	}
	waitState("succeeded")
	if _, files, err := resize.Stats(); err != nil || files != 0 {
		t.Fatalf("taak zei klaar maar cache %d %v", files, err)
	}
	// Pending annulering en retry gebruiken dezelfde bestaande jobroutes.
	cancel()
	<-done

	if rec := e.do(http.MethodDelete, "/pleya/v1/artwork/cache", map[string]string{"confirm": "purge"}); rec.Code != 202 {
		t.Fatal(rec.Code)
	}
	var pending string
	if err := e.pool.QueryRow(t.Context(), `SELECT id FROM jobs WHERE kind=$1 AND state='pending'`, api.JobArtworkCachePurge).Scan(&pending); err != nil {
		t.Fatal(err)
	}
	if rec := e.do(http.MethodPost, "/pleya/v1/jobs/"+pending+"/cancel", nil); rec.Code != 200 || !strings.Contains(rec.Body.String(), `"state":"cancelled"`) {
		t.Fatal(rec.Code, rec.Body.String())
	}
	if rec := e.do(http.MethodPost, "/pleya/v1/jobs/"+pending+"/retry", nil); rec.Code != 200 || !strings.Contains(rec.Body.String(), `"state":"pending"`) {
		t.Fatal(rec.Code, rec.Body.String())
	}
}

func TestArtworkCacheAdminRolesRevocationAndCookieCannotMutate(t *testing.T) {
	e := newEnv(t, func(o *api.Options) {
		r := artwork.New("ffmpeg", t.TempDir(), o.Logger)
		o.Artwork = r
		o.Jobs.Register(api.JobArtworkCachePurge, func(ctx context.Context, _ jobs.Job) error { return r.PurgeContext(ctx) })
	})
	e.setup(e.putSetupCode())
	// Bestaande tokenhelper geeft echte serverrollen en sessies, geen handlerbypass.
	tokens := map[string]string{roleOwner: e.access}
	for _, role := range []string{roleAdmin, roleMember, roleRestricted} {
		tokens[role] = e.tokenFor(e.createUser(role, "cache-"+role))
	}
	for _, role := range []string{roleOwner, roleAdmin, roleMember, roleRestricted} {
		for _, method := range []string{http.MethodGet, http.MethodDelete} {
			var body any
			if method == http.MethodDelete {
				body = map[string]string{"confirm": "purge"}
			}
			rec := e.do(method, "/pleya/v1/artwork/cache", body, asUser(tokens[role]))
			want := 200
			if method == http.MethodDelete {
				want = 202
			}
			if role == roleMember || role == roleRestricted {
				want = 404
			}
			if rec.Code != want {
				t.Errorf("%s %s: %d %s", role, method, rec.Code, rec.Body.String())
			}
		}
	}
	for _, method := range []string{http.MethodGet, http.MethodDelete} {
		rec := e.do(method, "/pleya/v1/artwork/cache", map[string]string{"confirm": "purge"}, withoutAuth)
		if rec.Code != 401 {
			t.Errorf("anoniem %s: %d", method, rec.Code)
		}
	}
	foreign := e.loginCookieMode("michel", "een-lang-genoeg-wachtwoord", foreignOrigin, http.StatusForbidden)
	if foreign.Code != 403 {
		t.Fatal(foreign.Code)
	}
	cookie := &http.Cookie{Name: "pleya_refresh", Value: "geen-accesstoken"}
	rec := e.do(http.MethodDelete, "/pleya/v1/artwork/cache", map[string]string{"confirm": "purge"}, withoutAuth, withCookie(cookie), withHeader("Origin", foreignOrigin))
	if rec.Code != 401 {
		t.Fatalf("cookie-only CSRF muteert: %d", rec.Code)
	}
	// Intrekking via de bestaande logout maakt dezelfde bearer onbruikbaar.
	token := e.access
	if rec := e.do(http.MethodPost, "/pleya/v1/auth/logout", nil); rec.Code != 204 {
		t.Fatal(rec.Code, rec.Body.String())
	}
	rec = e.do(http.MethodDelete, "/pleya/v1/artwork/cache", map[string]string{"confirm": "purge"}, asUser(token))
	if rec.Code != 401 {
		t.Fatalf("ingetrokken sessie %d", rec.Code)
	}
}

type cacheHeldResponse struct {
	*httptest.ResponseRecorder
	started chan struct{}
	release chan struct{}
	once    sync.Once
}

func (w *cacheHeldResponse) Write(p []byte) (int, error) {
	w.once.Do(func() { close(w.started) })
	<-w.release
	return w.ResponseRecorder.Write(p)
}

func TestArtworkCacheAdminPurgeDoesNotWaitForSlowHTTPResponse(t *testing.T) {
	cache := t.TempDir()
	var resize *artwork.Resizer
	var runner *jobs.Runner
	e := newEnv(t, withArtwork(cache), func(o *api.Options) {
		resize = o.Artwork
		runner = o.Jobs
		runner.Register(api.JobArtworkCachePurge, func(ctx context.Context, _ jobs.Job) error { return resize.PurgeContext(ctx) })
	})
	e.setup(e.putSetupCode())
	art := seedBigPoster(t, e, cache, "poster")
	path := "/pleya/v1/artwork/" + art + "?width=300"
	original := e.do(http.MethodGet, path, nil)
	if original.Code != 200 || bodyWidth(t, original.Body.Bytes()) != 480 {
		t.Fatal("geen echte gecachete trede")
	}
	held := &cacheHeldResponse{ResponseRecorder: httptest.NewRecorder(), started: make(chan struct{}), release: make(chan struct{})}
	req := httptest.NewRequest(http.MethodGet, path, nil)
	req.Header.Set("Authorization", "Bearer "+e.access)
	served := make(chan struct{})
	go func() { e.server.Handler().ServeHTTP(held, req); close(served) }()
	select {
	case <-held.started:
	case <-time.After(5 * time.Second):
		t.Fatal("response niet begonnen")
	}
	defer func() {
		select {
		case <-held.release:
		default:
			close(held.release)
		}
		<-served
	}()
	ctx, cancel := context.WithCancel(context.Background())
	finished := make(chan struct{})
	go func() { runner.Run(ctx); close(finished) }()
	defer func() { cancel(); <-finished }()
	if rec := e.do(http.MethodDelete, "/pleya/v1/artwork/cache", map[string]string{"confirm": "purge"}); rec.Code != 202 {
		t.Fatal(rec.Code, rec.Body.String())
	}
	var jobID string
	if err := e.pool.QueryRow(t.Context(), `SELECT id FROM jobs WHERE kind=$1`, api.JobArtworkCachePurge).Scan(&jobID); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		record, err := runner.Get(t.Context(), id.MustParse(jobID))
		if err == nil && record.State == "succeeded" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("purge wacht op trage HTTPresponse")
		}
		time.Sleep(10 * time.Millisecond)
	}
	if _, files, err := resize.Stats(); err != nil || files != 0 {
		t.Fatalf("purge is niet leeg %d %v", files, err)
	}
	// De geblokkeerde HTTP-kopie bezit de oude geopende inode. Laat haar nu door.
	close(held.release)
	<-served
	if held.Code != 200 || !bytes.Equal(held.Body.Bytes(), original.Body.Bytes()) {
		t.Fatal("lopende HTTPresponse verloor bytes")
	}
	rebuilt := e.do(http.MethodGet, path, nil)
	if rebuilt.Code != 200 || !bytes.Equal(rebuilt.Body.Bytes(), original.Body.Bytes()) || rebuilt.Header().Get("ETag") != original.Header().Get("ETag") {
		t.Fatal("rebuild veranderde trede/validator")
	}
}

func TestArtworkCacheAdminRunningPurgeCancellationReleasesQueuedReaders(t *testing.T) {
	control := t.TempDir()
	ready, release := filepath.Join(control, "ready"), filepath.Join(control, "release")
	wrapper := filepath.Join(control, "ffmpeg")
	if err := os.WriteFile(wrapper, []byte("#!/bin/sh\ntouch '"+ready+"'\nwhile ! test -f '"+release+"'; do sleep .01; done\nexec ffmpeg \"$@\"\n"), 0700); err != nil {
		t.Fatal(err)
	}
	defer os.WriteFile(release, nil, 0600)
	var resize *artwork.Resizer
	var runner *jobs.Runner
	e := newEnv(t, func(o *api.Options) {
		resize = artwork.New(wrapper, t.TempDir(), o.Logger)
		o.Artwork = resize
		runner = o.Jobs
		runner.Register(api.JobArtworkCachePurge, func(ctx context.Context, _ jobs.Job) error { return resize.PurgeContext(ctx) })
	})
	e.setup(e.putSetupCode())
	src := filepath.Join(t.TempDir(), "source.jpg")
	testsupport.MakeImage(t, src, 1200, 1800)
	made := make(chan error, 1)
	go func() {
		f, err := resize.Open(context.Background(), src, "019a0000-0000-7000-8000-000000000001_1", 480)
		if f != nil {
			f.Close()
		}
		made <- err
	}()
	deadline := time.Now().Add(5 * time.Second)
	for {
		if _, err := os.Stat(ready); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("render startte niet")
		}
		time.Sleep(5 * time.Millisecond)
	}
	if rec := e.do(http.MethodDelete, "/pleya/v1/artwork/cache", map[string]string{"confirm": "purge"}); rec.Code != 202 {
		t.Fatal(rec.Code)
	}
	var jobID string
	if err := e.pool.QueryRow(t.Context(), `SELECT id FROM jobs WHERE kind=$1`, api.JobArtworkCachePurge).Scan(&jobID); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { runner.Run(ctx); close(done) }()
	defer func() { cancel(); <-done }()
	for {
		record, err := runner.Get(t.Context(), id.MustParse(jobID))
		if err == nil && record.State == "running" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("purge niet running")
		}
		time.Sleep(10 * time.Millisecond)
	}
	if rec := e.do(http.MethodPost, "/pleya/v1/jobs/"+jobID+"/cancel", nil); rec.Code != 200 {
		t.Fatal(rec.Code, rec.Body.String())
	}
	for {
		record, err := runner.Get(t.Context(), id.MustParse(jobID))
		if err == nil && record.State == "cancelled" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("lopende purge annuleerde niet")
		}
		time.Sleep(10 * time.Millisecond)
	}
	if err := os.WriteFile(release, nil, 0600); err != nil {
		t.Fatal(err)
	}
	if err := <-made; err != nil {
		t.Fatal(err)
	}
	if _, files, err := resize.Stats(); err != nil || files != 1 {
		t.Fatalf("geannuleerde purge raakte actieve publicatie: %d %v", files, err)
	}
}

func TestArtworkCacheAdminPNGSourceKeepsJPEGHeadAndFallbackValidator(t *testing.T) {
	cache := t.TempDir()
	var resize *artwork.Resizer
	e := newEnv(t, withArtwork(cache), func(o *api.Options) { resize = o.Artwork })
	e.setup(e.putSetupCode())
	art := seedBigPoster(t, e, cache, "poster")
	name := art + ".png"
	source := filepath.Join(cache, "artwork", name)
	f, err := os.Create(source)
	if err != nil {
		t.Fatal(err)
	}
	if err := png.Encode(f, image.NewRGBA(image.Rect(0, 0, 1000, 1500))); err != nil {
		f.Close()
		t.Fatal(err)
	}
	f.Close()
	if _, err := e.pool.Exec(t.Context(), `UPDATE provider_artwork SET file_name=$2 WHERE id=$1`, id.MustParse(art), name); err != nil {
		t.Fatal(err)
	}
	path := "/pleya/v1/artwork/" + art
	original := e.do(http.MethodGet, path, nil)
	if original.Code != 200 || original.Header().Get("Content-Type") != "image/png" {
		t.Fatal("bronPNG niet geleverd")
	}
	small := e.do(http.MethodGet, path+"?width=300", nil)
	if small.Code != 200 || small.Header().Get("Content-Type") != "image/jpeg" || bodyWidth(t, small.Body.Bytes()) != 480 {
		t.Fatal("PNGtrede niet als JPEG geleverd")
	}
	if small.Header().Get("Content-Length") != strconv.Itoa(small.Body.Len()) {
		t.Fatal("JPEG Content-Length klopt niet")
	}
	head := e.do(http.MethodHead, path+"?width=300", nil)
	if head.Code != 200 || head.Body.Len() != 0 || head.Header().Get("Content-Length") != small.Header().Get("Content-Length") || head.Header().Get("ETag") != small.Header().Get("ETag") || head.Header().Get("Content-Type") != "image/jpeg" {
		t.Fatal("HEAD verloor tredeheaders")
	}
	if err := os.Rename(resize.Dir(), resize.Dir()+"-opened"); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Dir(source), resize.Dir()); err != nil {
		t.Fatal(err)
	}
	fallback := e.do(http.MethodGet, path+"?width=300", nil)
	if fallback.Code != 200 || fallback.Header().Get("Content-Type") != "image/png" || fallback.Header().Get("ETag") != original.Header().Get("ETag") || !bytes.Equal(fallback.Body.Bytes(), original.Body.Bytes()) {
		t.Fatal("fallback had tredevalidator of verkeerde bronbytes")
	}
}
