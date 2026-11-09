package push

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func TestDeliveryRequiresOptInAnActiveSessionAndLibraryAccess(t *testing.T) {
	ctx := context.Background()
	pool := testsupport.Pool(t)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	if _, err := migrate.Run(ctx, pool, log); err != nil {
		t.Fatal(err)
	}
	exec := func(sql string, args ...any) {
		t.Helper()
		if _, err := pool.Exec(ctx, sql, args...); err != nil {
			t.Fatal(err)
		}
	}
	count := func(sql string) int {
		t.Helper()
		var count int
		if err := pool.QueryRow(ctx, sql).Scan(&count); err != nil {
			t.Fatal(err)
		}
		return count
	}
	var status atomic.Int64
	var sends atomic.Int64
	apns := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sends.Add(1)
		var payload struct {
			APS struct{ Alert struct{ Body string } }
		}
		if r.Method != http.MethodPost || r.ProtoMajor != 2 || r.URL.Path != "/3/device/aabb" ||
			r.Header.Get("apns-topic") != bundleID || r.Header.Get("apns-push-type") != "alert" ||
			r.Header.Get("apns-collapse-id") == "" || r.Header.Get("apns-id") == "" || r.Header.Get("apns-expiration") != "0" ||
			!strings.HasPrefix(r.Header.Get("Authorization"), "bearer ") ||
			json.NewDecoder(r.Body).Decode(&payload) != nil || payload.APS.Alert.Body != "Er staat iets nieuws in je bibliotheek." {
			t.Error("invalid APNs request")
		}
		w.WriteHeader(int(status.Load()))
		if status.Load() == http.StatusGone {
			_, _ = io.WriteString(w, `{"reason":"Unregistered"}`)
		}
	}))
	apns.EnableHTTP2 = true
	apns.StartTLS()
	defer apns.Close()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	s := New(pool, &APNs{key: key, topic: bundleID, environment: "sandbox", host: apns.URL, client: apns.Client()})
	user, session, other, otherSession, installation := id.New(), id.New(), id.New(), id.New(), id.New()
	library, location, item, version := id.New(), id.New(), id.New(), id.New()
	exec("INSERT INTO users(id,username,password_hash,role) VALUES ($1,'member','test','member'),($2,'other','test','member')", user, other)
	exec("INSERT INTO sessions(id,user_id,device_name) VALUES ($1,$2,'phone'),($3,$4,'other phone')", session, user, otherSession, other)
	exec("INSERT INTO libraries(id,slug,title,kind) VALUES ($1,'films','Films','movies')", library)
	exec("INSERT INTO storage_locations(id,library_id,root_path) VALUES ($1,$2,'/films')", location, library)
	exec("INSERT INTO media_items(id,library_id,kind,grouping_key,title,added_at) VALUES ($1,$2,'movie','film','Private film title',now()-interval '10 minutes')", item, library)
	exec("INSERT INTO media_versions(id,item_id,grouping_key,container,duration_ms) VALUES ($1,$2,'main','mp4',60000)", version, item)
	exec("INSERT INTO media_files(id,storage_location_id,relative_path,role,version_id,size_bytes,mtime_unix) VALUES (gen_random_uuid(),$1,'film.mp4','media',$2,1,1)", location, version)
	exec("INSERT INTO scan_runs(id,library_id,trigger,state,started_at,finished_at) VALUES (gen_random_uuid(),$1,'manual','succeeded',now()-interval '8 minutes',now()-interval '5 minutes')", library)
	exec("INSERT INTO library_permissions(user_id,library_id,permission) VALUES ($1,$2,'view')", user, library)

	materialize := func(want int) {
		t.Helper()
		if err := s.materialize(ctx); err != nil {
			t.Fatal(err)
		}
		if got := count("SELECT count(*) FROM push_deliveries"); got != want {
			t.Fatalf("queued %d, want %d", got, want)
		}
	}
	deliver := func(wantSends int64, wantWork bool) {
		t.Helper()
		work, err := s.deliver(ctx, log)
		if err != nil || work != wantWork || sends.Load() != wantSends {
			t.Fatalf("work=%v, sent=%d, err=%v, want work=%v sent=%d", work, sends.Load(), err, wantWork, wantSends)
		}
	}

	materialize(0)
	if err := s.Register(ctx, installation, user, session, "aabb", "sandbox", "nl", true, false); err != nil {
		t.Fatal(err)
	}
	if err := s.Register(ctx, installation, other, otherSession, "ccee", "sandbox", "nl", true, false); !errors.Is(err, ErrConflict) {
		t.Fatalf("other account replaced installation: %v", err)
	}
	if err := s.Remove(ctx, installation, other, otherSession); err != nil {
		t.Fatal(err)
	}
	if got := count("SELECT count(*) FROM push_installations"); got != 1 {
		t.Fatal("other session removed the opt-in")
	}
	exec("UPDATE push_installations SET movies_since=now()-interval '30 minutes'")
	materialize(0) // First successful scan only establishes a baseline.
	exec("INSERT INTO scan_runs(id,library_id,trigger,state,started_at,finished_at,error_count) VALUES (gen_random_uuid(),$1,'manual','succeeded',now()-interval '45 minutes',now()-interval '40 minutes',1)", library)
	materialize(0) // A disconnected mount did not establish a baseline.
	exec("INSERT INTO scan_runs(id,library_id,trigger,state,started_at,finished_at) VALUES (gen_random_uuid(),$1,'manual','succeeded',now()-interval '40 minutes',now()-interval '35 minutes')", library)
	materialize(1)
	materialize(1)
	exec("DELETE FROM library_permissions WHERE user_id=$1", user)
	deliver(0, true)
	exec("INSERT INTO library_permissions(user_id,library_id,permission) VALUES ($1,$2,'view')", user, library)
	exec("DELETE FROM push_deliveries")
	materialize(1)

	status.Store(http.StatusServiceUnavailable)
	deliver(1, true)
	deliver(1, false)
	exec("UPDATE push_deliveries SET next_attempt_at=now()")
	status.Store(http.StatusOK)
	deliver(2, true)
	materialize(1)
	deliver(2, false)

	exec("DELETE FROM push_deliveries")
	materialize(1)
	status.Store(http.StatusGone)
	deliver(3, true)
	materialize(0)
	if got := count("SELECT count(*) FROM push_installations"); got != 0 {
		t.Fatal("unregistered APNs token was retained")
	}

	if err := s.Register(ctx, installation, user, session, "aabb", "sandbox", "nl", true, false); err != nil {
		t.Fatal(err)
	}
	exec("UPDATE push_installations SET movies_since=now()-interval '30 minutes'")
	materialize(1)
	exec("UPDATE sessions SET revoked_at=now() WHERE id=$1", session)
	deliver(3, false)
	materialize(0)
	if err := s.Register(ctx, installation, user, session, "aabb", "sandbox", "nl", true, false); !errors.Is(err, ErrConflict) {
		t.Fatalf("revoked session registered: %v", err)
	}
	nextSession := id.New()
	exec("INSERT INTO sessions(id,user_id,device_name,created_at) VALUES ($1,$2,'phone',now()+interval '1 minute')", nextSession, user)
	exec("UPDATE sessions SET revoked_at=NULL WHERE id=$1", session)
	if err := s.Register(ctx, installation, user, session, "aabb", "sandbox", "nl", true, false); err != nil {
		t.Fatal(err)
	}
	if err := s.Register(ctx, installation, user, nextSession, "aabb", "sandbox", "nl", true, false); err != nil {
		t.Fatalf("same account and device could not register on new session: %v", err)
	}
	if err := s.Register(ctx, installation, user, session, "aabb", "sandbox", "nl", true, false); !errors.Is(err, ErrConflict) {
		t.Fatalf("old session reclaimed installation: %v", err)
	}
	for range 7 {
		if err := s.Register(ctx, id.New(), user, nextSession, "aabb", "sandbox", "nl", true, false); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.Register(ctx, id.New(), user, nextSession, "aabb", "sandbox", "nl", true, false); !errors.Is(err, ErrConflict) {
		t.Fatalf("session exceeded installation quota: %v", err)
	}
}
