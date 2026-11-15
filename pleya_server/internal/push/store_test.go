package push

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	"github.com/jackc/pgx/v5/pgxpool"
)

type queueFixture struct {
	t             *testing.T
	ctx           context.Context
	pool          *pgxpool.Pool
	s             *Service
	log           *slog.Logger
	sends, status atomic.Int64
	lastBody      atomic.Value
	onSend        func()
	user, session id.ID
	library, root id.ID
}

// newQueueFixture: an owner with one session, a films library whose first
// scan (the baseline) finished 35 minutes ago, and a fake APNs.
func newQueueFixture(t *testing.T) *queueFixture {
	f := &queueFixture{t: t, ctx: context.Background(), pool: testsupport.Pool(t),
		log: slog.New(slog.NewTextHandler(io.Discard, nil)), user: id.New(), session: id.New(), library: id.New(), root: id.New()}
	if _, err := migrate.Run(f.ctx, f.pool, f.log); err != nil {
		t.Fatal(err)
	}
	f.status.Store(http.StatusOK)
	apns := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.sends.Add(1)
		body, _ := io.ReadAll(r.Body)
		f.lastBody.Store(body)
		if f.onSend != nil {
			f.onSend()
		}
		w.WriteHeader(int(f.status.Load()))
		if f.status.Load() == http.StatusGone {
			_, _ = io.WriteString(w, `{"reason":"Unregistered"}`)
		}
	}))
	apns.EnableHTTP2 = true
	apns.StartTLS()
	t.Cleanup(apns.Close)
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	f.s = New(f.pool, &APNs{key: key, topic: bundleID, environment: "sandbox", host: apns.URL, client: apns.Client()})
	f.exec("INSERT INTO users(id,username,password_hash,role) VALUES ($1,'owner','test','owner')", f.user)
	f.exec("INSERT INTO sessions(id,user_id,device_name) VALUES ($1,$2,'ipad')", f.session, f.user)
	f.exec("INSERT INTO libraries(id,slug,title,kind) VALUES ($1,'films','Films','movies')", f.library)
	f.exec("INSERT INTO storage_locations(id,library_id,root_path) VALUES ($1,$2,'/films')", f.root, f.library)
	f.exec("INSERT INTO scan_runs(id,library_id,trigger,state,started_at,finished_at) VALUES (gen_random_uuid(),$1,'manual','succeeded',now()-interval '40 minutes',now()-interval '35 minutes')", f.library)
	return f
}

func (f *queueFixture) exec(sql string, args ...any) {
	f.t.Helper()
	if _, err := f.pool.Exec(f.ctx, sql, args...); err != nil {
		f.t.Fatal(err)
	}
}

func (f *queueFixture) count(sql string, args ...any) int {
	f.t.Helper()
	var n int
	if err := f.pool.QueryRow(f.ctx, sql, args...).Scan(&n); err != nil {
		f.t.Fatal(err)
	}
	return n
}

// optIn registers a film opt-in that predates the new films.
func (f *queueFixture) optIn(installation id.ID) {
	f.t.Helper()
	if err := f.s.Register(f.ctx, installation, f.user, f.session, "aabb", "sandbox", "nl", true, false, nil); err != nil {
		f.t.Fatal(err)
	}
	f.exec("UPDATE push_installations SET movies_since=now()-interval '30 minutes' WHERE id=$1", installation)
}

// newFilms adds n playable films and the scan that found them.
func (f *queueFixture) newFilms(n int) {
	f.t.Helper()
	for range n {
		item, version := id.New(), id.New()
		f.exec("INSERT INTO media_items(id,library_id,kind,grouping_key,title,added_at) VALUES ($1,$2,'movie',$3,'Film',now()-interval '10 minutes')", item, f.library, item.String())
		f.exec("INSERT INTO media_versions(id,item_id,grouping_key,container,duration_ms) VALUES ($1,$2,'main','mp4',60000)", version, item)
		f.exec("INSERT INTO media_files(id,storage_location_id,relative_path,role,version_id,size_bytes,mtime_unix) VALUES (gen_random_uuid(),$1,$2,'media',$3,1,1)", f.root, item.String()+".mp4", version)
	}
	f.exec("INSERT INTO scan_runs(id,library_id,trigger,state,started_at,finished_at) VALUES (gen_random_uuid(),$1,'manual','succeeded',now()-interval '8 minutes',now()-interval '5 minutes')", f.library)
	if err := f.s.materialize(f.ctx); err != nil {
		f.t.Fatal(err)
	}
}

func (f *queueFixture) drain() {
	f.t.Helper()
	for range 50 {
		more, err := f.s.deliver(f.ctx, f.log)
		if err != nil {
			f.t.Fatal(err)
		}
		if !more {
			return
		}
	}
	f.t.Fatal("queue did not drain")
}

func TestASeasonOfNewItemsIsOneAlertPerDevice(t *testing.T) {
	f := newQueueFixture(t)
	f.optIn(id.New())
	f.newFilms(24)
	if got := f.count("SELECT count(*) FROM push_deliveries WHERE NOT finished"); got != 24 {
		t.Fatalf("queued %d, want 24", got)
	}
	f.drain()
	if got := f.sends.Load(); got != 1 {
		t.Fatalf("sent %d alerts for 24 new items, want 1", got)
	}
	if got := f.count("SELECT count(*) FROM push_deliveries WHERE NOT finished"); got != 0 {
		t.Fatalf("%d deliveries left open", got)
	}
}

func TestRevocationDuringTheAPNsCallIsNotBlockedAndStopsRetries(t *testing.T) {
	f := newQueueFixture(t)
	f.optIn(id.New())
	f.newFilms(1)
	var revokeErr error
	f.onSend = func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_, revokeErr = f.pool.Exec(ctx, "UPDATE sessions SET revoked_at=now() WHERE id=$1", f.session)
	}
	f.status.Store(http.StatusServiceUnavailable)
	f.drain()
	if revokeErr != nil {
		t.Fatalf("revoking the session waited on the APNs call: %v", revokeErr)
	}
	f.exec("UPDATE push_deliveries SET next_attempt_at=now()")
	f.drain()
	if got := f.sends.Load(); got != 1 {
		t.Fatalf("sent %d times after the revocation, want only the alert in flight", got)
	}
	if got := f.count("SELECT count(*) FROM push_installations"); got != 0 {
		t.Fatal("installation of a revoked session kept")
	}
}

func TestADeviceTokenBelongsToOneInstallation(t *testing.T) {
	f := newQueueFixture(t)
	first := id.New()
	f.optIn(first)
	other, otherSession, second := id.New(), id.New(), id.New()
	f.exec("INSERT INTO users(id,username,password_hash,role) VALUES ($1,'kind','test','member')", other)
	f.exec("INSERT INTO sessions(id,user_id,device_name) VALUES ($1,$2,'ipad')", otherSession, other)
	if err := f.s.Register(f.ctx, second, other, otherSession, "aabb", "sandbox", "nl", true, false, nil); err != nil {
		t.Fatal(err)
	}
	if got := f.count("SELECT count(*) FROM push_installations WHERE id=$1", first); got != 0 {
		t.Fatal("previous account kept the shared device token")
	}
	if got := f.count("SELECT count(*) FROM push_installations WHERE id=$1", second); got != 1 {
		t.Fatal("new registration missing")
	}
}

func TestPurgeRevokedWorksWithPushOff(t *testing.T) {
	f := newQueueFixture(t)
	f.optIn(id.New())
	f.exec("UPDATE sessions SET revoked_at=now() WHERE id=$1", f.session)
	if n, err := New(f.pool, nil).PurgeRevoked(f.ctx); err != nil || n != 1 {
		t.Fatalf("purged %d, err %v", n, err)
	}
}

func TestARefusedTokenOnlyDropsAnInstallationThatStillHasIt(t *testing.T) {
	f := newQueueFixture(t)
	installation := id.New()
	f.optIn(installation)
	f.newFilms(1)
	// The device registers a new token while APNs is refusing the old one.
	f.onSend = func() {
		f.exec("UPDATE push_installations SET device_token='ccdd' WHERE id=$1", installation)
	}
	f.status.Store(http.StatusGone)
	f.drain()
	if got := f.count("SELECT count(*) FROM push_installations WHERE id=$1", installation); got != 1 {
		t.Fatal("the registration with the new token was removed for the old token's refusal")
	}
}

// Rich push (DEC-XXX): with a registered key the alert carries the sealed
// title and a poster reference only this installation's session can open;
// Apple's part stays the generic text. Without a key nothing rich is sent.
func TestRichDeliverySealsTitleAndPosterAndFallsBackWithoutAKey(t *testing.T) {
	f := newQueueFixture(t)
	signingKey := bytes.Repeat([]byte{7}, auth.KeyLength)
	signer, err := auth.NewSigner(signingKey)
	if err != nil {
		t.Fatal(err)
	}
	f.s.Items, f.s.Signer = catalog.NewStore(f.pool), signer
	key := bytes.Repeat([]byte{42}, 32)
	installation := id.New()
	register := func(key []byte) {
		t.Helper()
		if err := f.s.Register(f.ctx, installation, f.user, f.session, "aabb", "sandbox", "nl", true, false, key); err != nil {
			t.Fatal(err)
		}
		f.exec("UPDATE push_installations SET movies_since=now()-interval '30 minutes' WHERE id=$1", installation)
	}
	register(key)
	f.newFilms(2)
	var first, poster id.ID
	if err := f.pool.QueryRow(f.ctx, "SELECT id FROM media_items ORDER BY id LIMIT 1").Scan(&first); err != nil {
		t.Fatal(err)
	}
	poster = id.New()
	f.exec("UPDATE media_items SET title='Dune', added_at=added_at-interval '1 minute' WHERE id=$1", first)
	f.exec(`INSERT INTO media_files(id,storage_location_id,relative_path,role,item_id,artwork_kind,size_bytes,mtime_unix)
		VALUES ($1,$2,'dune/poster.jpg','artwork',$3,'poster',1,1)`, poster, f.root, first)
	f.drain()

	raw, _ := f.lastBody.Load().([]byte)
	if bytes.Contains(raw, []byte("Dune")) || bytes.Contains(raw, []byte(poster.String())) {
		t.Fatalf("Apple sees the title or the poster: %s", raw)
	}
	var msg struct {
		APS struct {
			Alert          struct{ Body string }
			MutableContent int `json:"mutable-content"`
		}
		Pleya          *struct{ I, C string }
		NotificationID string `json:"notification_id"`
	}
	if err := json.Unmarshal(raw, &msg); err != nil {
		t.Fatal(err)
	}
	if msg.APS.MutableContent != 1 || msg.Pleya == nil || msg.Pleya.I != installation.String() ||
		msg.APS.Alert.Body != "Er staat iets nieuws in je bibliotheek." {
		t.Fatalf("no rich part next to the generic alert: %s", raw)
	}
	sealed, err := base64.StdEncoding.DecodeString(msg.Pleya.C)
	if err != nil {
		t.Fatal(err)
	}
	block, _ := aes.NewCipher(key)
	gcm, _ := cipher.NewGCM(block)
	aad := []byte(installation.String() + "|" + msg.NotificationID)
	plain, err := gcm.Open(nil, sealed[:12], sealed[12:], aad)
	if err != nil {
		t.Fatalf("installation key does not open the content: %v", err)
	}
	if _, err := gcm.Open(nil, sealed[:12], sealed[12:], nil); err == nil {
		t.Fatal("content opens without its notification binding")
	}
	var content richContent
	if err := json.Unmarshal(plain, &content); err != nil {
		t.Fatal(err)
	}
	if content.Title != "Nieuw: Dune en 1 meer" || content.Artwork != poster.String() {
		t.Fatalf("content %+v", content)
	}
	claims, err := signer.Verify(content.Token, auth.TokenArtwork)
	if err != nil || claims.Resource != poster.String() || claims.Subject != f.user.String() || claims.Sid != f.session.String() {
		t.Fatalf("poster token %+v, %v", claims, err)
	}
	if time.Unix(claims.ExpiresAt, 0).After(time.Now().Add(auth.ArtworkTokenTTL + time.Minute)) {
		t.Fatal("poster token outlives the delivery")
	}

	// A PUT without a key (an older app) clears it: generic alert only.
	register(nil)
	f.newFilms(1)
	f.drain()
	raw, _ = f.lastBody.Load().([]byte)
	msg.Pleya, msg.APS.MutableContent = nil, 0
	if err := json.Unmarshal(raw, &msg); err != nil {
		t.Fatal(err)
	}
	if msg.Pleya != nil || msg.APS.MutableContent != 0 || f.sends.Load() != 2 {
		t.Fatalf("rich content without a key (sends %d): %s", f.sends.Load(), raw)
	}
}
