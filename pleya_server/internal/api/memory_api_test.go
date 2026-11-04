package api_test

import (
	"context"
	"encoding/json"
	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"net/http"
	"strings"
	"testing"
	"time"
)

func (e *env) memoryGet(opts ...func(*http.Request)) api.MemorySnapshotWire {
	e.t.Helper()
	rec := e.do(http.MethodGet, "/pleya/v1/users/me/memory", nil, opts...)
	if rec.Code != 200 {
		e.t.Fatalf("GET memory: %d %s", rec.Code, rec.Body.String())
	}
	if rec.Header().Get("Cache-Control") != "no-store" {
		e.t.Fatal("geen no-store")
	}
	var out api.MemorySnapshotWire
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatal(err)
	}
	return out
}
func TestMemoryAccountSnapshotAndClosedRequests(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	base := e.memoryGet()
	fact := map[string]any{"id": id.New().String(), "category": "preference", "value": "Houdt van duistere detectives", "source": "settings_manual"}
	body := map[string]any{"epoch": base.Epoch, "base_revision": base.Revision, "facts": []any{fact}}
	rec := e.do(http.MethodPut, "/pleya/v1/users/me/memory", body)
	if rec.Code != 200 {
		t.Fatalf("PUT:%d %s", rec.Code, rec.Body.String())
	}
	current := e.memoryGet()
	if len(current.Facts) != 1 || current.Facts[0].Value != fact["value"] {
		t.Fatal("feit ontbreekt")
	}
	e.record("MemorySnapshot", http.MethodGet, "/pleya/v1/users/me/memory", rec)
	member := e.tokenFor(e.createUser("member", "memory-member"))
	if len(e.memoryGet(asUser(member)).Facts) != 0 {
		t.Fatal("andermans geheugen zichtbaar")
	}
	if stale := e.do(http.MethodPut, "/pleya/v1/users/me/memory", body); stale.Code != 409 {
		t.Fatal("stale PUT niet geweigerd")
	}
	body["base_revision"] = current.Revision
	body["user_id"] = id.New().String()
	if invalid := e.do(http.MethodPut, "/pleya/v1/users/me/memory", body); invalid.Code != 400 {
		t.Fatal("gesloten body accepteert extra veld")
	}
	delete(body, "user_id")
	fact["unexpected"] = "PRIVATE-MARKER"
	if invalid := e.do(http.MethodPut, "/pleya/v1/users/me/memory", body); invalid.Code != 400 || strings.Contains(invalid.Body.String(), "PRIVATE-MARKER") {
		t.Fatal("genest onbekend veld of lek")
	}
	delete(fact, "unexpected")
	for _, value := range []string{"Onze dochter is 8", "Wil Nederlandse ondertitels", "x\nPRIVATE-MARKER"} {
		fact["value"] = value
		if invalid := e.do(http.MethodPut, "/pleya/v1/users/me/memory", body); invalid.Code != 400 || strings.Contains(invalid.Body.String(), value) {
			t.Fatal("owned/ongeldig feit niet veilig geweigerd")
		}
	}
	if large := e.do(http.MethodPut, "/pleya/v1/users/me/memory", nil, rawBody(strings.Repeat("x", 256*1024+1))); large.Code != 413 {
		t.Fatalf("grootte %d", large.Code)
	}
	// Een geldige 200-feitensnapshot is groter dan de oude globale 8KiB-grens.
	many := []any{}
	for i := range 200 {
		many = append(many, map[string]any{"id": id.New().String(), "category": "habit", "source": "settings_manual", "value": "Feit " + id.New().String() + strings.Repeat("a", 120) + string(rune('a'+i%26))})
	}
	body["facts"] = many
	if valid := e.do(http.MethodPut, "/pleya/v1/users/me/memory", body); valid.Code != 200 {
		t.Fatalf("grote geldige snapshot:%d %s", valid.Code, valid.Body.String())
	}
}
func TestMemoryRestrictedAPITokenAndRoleChangeAreDenied(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	uid := e.createUser("member", "memory-account")
	token := e.tokenFor(uid)
	_ = e.memoryGet(asUser(token))
	if _, err := e.pool.Exec(context.Background(), `UPDATE users SET role='restricted' WHERE id=$1`, uid); err != nil {
		t.Fatal(err)
	}
	for _, method := range []string{http.MethodGet, http.MethodPut, http.MethodPost} {
		path := "/pleya/v1/users/me/memory"
		if method == http.MethodPost {
			path += "/clear"
		}
		rec := e.do(method, path, map[string]any{}, asUser(token))
		if rec.Code != 403 {
			t.Fatalf("restricted %s: %d", method, rec.Code)
		}
	}
	created := e.createToken(map[string]any{"name": "memory-denied", "scope": "admin"}, http.StatusCreated)
	if rec := e.do(http.MethodGet, "/pleya/v1/users/me/memory", nil, asToken(created.Secret)); rec.Code != 403 {
		t.Fatalf("API-token:%d", rec.Code)
	}
}

func TestMemoryCapabilityAndCredentialBoundary(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	uid := e.createUser("member", "memory-revoked")
	access := e.tokenFor(uid)
	var sid id.ID
	if err := e.pool.QueryRow(context.Background(), `SELECT id FROM sessions WHERE user_id=$1`, uid).Scan(&sid); err != nil {
		t.Fatal(err)
	}
	_ = e.memoryGet(asUser(access))
	e.revocations.Revoke(sid, time.Now())
	if rec := e.do(http.MethodGet, "/pleya/v1/users/me/memory", nil, asUser(access)); rec.Code != 401 {
		t.Fatal("ingetrokken sessie leest geheugen")
	}
	gone := e.createUser("member", "memory-deleted")
	goneToken := e.tokenFor(gone)
	if _, err := e.pool.Exec(context.Background(), `DELETE FROM users WHERE id=$1`, gone); err != nil {
		t.Fatal(err)
	}
	if rec := e.do(http.MethodGet, "/pleya/v1/users/me/memory", nil, asUser(goneToken)); rec.Code != 401 && rec.Code != 404 {
		t.Fatalf("verwijderde gebruiker:%d", rec.Code)
	}
	claims, _, err := e.signer.Mint(uid.String(), sid.String(), auth.TokenStream, time.Minute, "")
	if err != nil {
		t.Fatal(err)
	}
	if rec := e.do(http.MethodGet, "/pleya/v1/users/me/memory", nil, asUser(claims)); rec.Code != 401 {
		t.Fatal("streamtoken leest geheugen")
	}
	old := newEnv(t, func(o *api.Options) { o.Memory = nil })
	old.setup(old.putSetupCode())
	var info api.Info
	old.getJSON("/pleya/v1/info", "Info", 200, &info)
	if info.Capabilities.AssistantMemory {
		t.Fatal("capability zonder opslag")
	}
	if rec := old.do(http.MethodGet, "/pleya/v1/users/me/memory", nil); rec.Code != 404 {
		t.Fatal("route zonder opslag beschikbaar")
	}
}
