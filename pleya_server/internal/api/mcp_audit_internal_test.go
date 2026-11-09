package api

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
	tools "github.com/edde746/plezy/pleya_server/internal/mcp"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func TestMCPAuditPreservesSubjectAndRecordsActorSeparately(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatal(err)
	}
	actor, actorSession, subject, subjectSession := id.New(), id.New(), id.New(), id.New()
	for _, user := range []id.ID{actor, subject} {
		if _, err := pool.Exec(ctx, `INSERT INTO users(id,username,password_hash,role) VALUES($1,$2,'synthetic-not-a-login','member')`, user, user.String()); err != nil {
			t.Fatal(err)
		}
	}
	for _, pair := range [][2]id.ID{{actorSession, actor}, {subjectSession, subject}} {
		if _, err := pool.Exec(ctx, `INSERT INTO sessions(id,user_id,device_name) VALUES($1,$2,'audit fixture')`, pair[0], pair[1]); err != nil {
			t.Fatal(err)
		}
	}

	ctx = context.WithValue(ctx, claimsContextKey{}, auth.Claims{Subject: actor.String(), Sid: actorSession.String()})
	ctx = context.WithValue(ctx, mcpAuditKey{}, &mcpAuditState{operation: "fixtureSubject"})
	request := httptest.NewRequest("GET", "http://fixture/mcp", nil).WithContext(ctx)
	server := &Server{opts: Options{Audit: audit.NewStore(pool)}, now: time.Now}
	server.auditWrite(request, audit.Entry{UserID: &subject, SessionID: &subjectSession, Operation: "fixtureSubject", Outcome: audit.OutcomeOK})
	var gotUser, gotSession, gotActor, gotActorSession string
	err := pool.QueryRow(ctx, `SELECT user_id::text,session_id::text,detail->>'actor_user_id',detail->>'actor_session_id' FROM admin_audit WHERE operation='fixtureSubject'`).Scan(&gotUser, &gotSession, &gotActor, &gotActorSession)
	if err != nil || gotUser != subject.String() || gotSession != subjectSession.String() || gotActor != actor.String() || gotActorSession != actorSession.String() {
		t.Fatalf("subject/actor lost: %s %s %s %s %v", gotUser, gotSession, gotActor, gotActorSession, err)
	}
}

func TestMCPBucketsCannotBeEvictedToResetBudgets(t *testing.T) {
	limiter := newLimiter()
	limiter.preserveBuckets = true
	limiter.burst = 1
	limiter.refill = 1
	now := time.Now()
	limiter.now = func() time.Time { return now }
	if ok, _ := limiter.allow("original"); !ok {
		t.Fatal("initial request refused")
	}
	for n := 1; n < limiterMaxBuckets; n++ {
		if ok, _ := limiter.allow(id.New().String()); !ok {
			t.Fatal("capacity filled early")
		}
	}
	if ok, wait := limiter.allow("overflow"); ok || wait <= 0 {
		t.Fatal("overflow evicted a live budget")
	}
	if ok, _ := limiter.allow("original"); ok {
		t.Fatal("original budget was reset")
	}
}

func TestMCPInnerDispatchChecksMaintenance(t *testing.T) {
	server := &Server{mux: http.NewServeMux(), log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	server.maintenance.Store(true)
	called := false
	server.mux.HandleFunc("GET /pleya/v1/info", func(w http.ResponseWriter, r *http.Request) { called = true })
	handler := tools.New(http.HandlerFunc(server.dispatchMCP), nil)
	request := httptest.NewRequest("POST", "http://fixture/mcp", strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"getInfo","arguments":{}}}`))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Accept", "application/json, text/event-stream")
	request.Header.Set("MCP-Protocol-Version", "2025-06-18")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if called || !strings.Contains(response.Body.String(), CodeMaintenance) {
		t.Fatalf("inner maintenance bypass: %d %s", response.Code, response.Body)
	}
}
