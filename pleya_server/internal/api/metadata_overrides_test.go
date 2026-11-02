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

func TestMetadataOverridesRoutesAndClosedWrites(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	path := "/pleya/v1/items/" + e.findMovie("Grease").ID
	if r := e.do(http.MethodGet, path+"/metadata", nil); r.Code != 200 {
		t.Fatalf("metadata read: %d %s", r.Code, r.Body.String())
	}
	var asMap map[string]any
	e.getJSON(path+"/metadata", "", 200, &asMap)
	if _, ok := asMap["item_id"].(string); !ok {
		t.Fatalf("wire item_id moet string zijn: %+v", asMap)
	}
	var wire api.MetadataFields
	e.getJSON(path+"/metadata", "MetadataFields", 200, &wire)
	for _, body := range []map[string]any{{"title": ""}, {"title": nil}, {"year": 0}, {"year": "2000"}, {"summary": nil}, {"genres": []any{1}}, {"people": []any{map[string]any{"name": "A", "role": "actor", "secret": "x"}}}, {"external_id": "1"}, {}} {
		if r := e.do(http.MethodPut, path+"/overrides", body); r.Code != 400 {
			t.Fatalf("invalid %+v: %d %s", body, r.Code, r.Body.String())
		}
	}
	for _, raw := range []string{`{"title":"First","title":"Second"}`, `{"year":null,"year":2001}`} {
		if r := e.do(http.MethodPut, path+"/overrides", json.RawMessage(raw)); r.Code != 400 {
			t.Fatalf("duplicate fields accepted: %d %s", r.Code, r.Body.String())
		}
	}
	if r := e.do(http.MethodPut, path+"/overrides", map[string]any{"title": "Manual", "year": nil, "summary": "", "genres": []string{}, "content_rating": "", "people": []any{}}); r.Code != 200 {
		t.Fatalf("write: %d %s", r.Code, r.Body.String())
	}
	if r := e.do(http.MethodDelete, path+"/overrides/external_id", nil); r.Code != 400 {
		t.Fatalf("unknown field: %d", r.Code)
	}
}

func TestMetadataOverridesScopeRevocationAndAudit(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	path := "/pleya/v1/items/" + e.findMovie("Grease").ID
	member := e.tokenFor(e.createUser("member", "override-member"))
	limited := e.createToken(map[string]any{"name": "override-read", "scope": "read"}, http.StatusCreated)
	for _, token := range []string{member, limited.Secret} {
		for _, req := range []struct {
			method, path string
			body         any
		}{{http.MethodGet, path + "/metadata", nil}, {http.MethodPut, path + "/overrides", map[string]string{"summary": "must not leak"}}, {http.MethodDelete, path + "/overrides/summary", nil}} {
			if r := e.do(req.method, req.path, req.body, asUser(token)); r.Code != 404 {
				t.Fatalf("scope %s: %d %s", req.method, r.Code, r.Body.String())
			}
		}
	}
	r := e.do(http.MethodPut, path+"/overrides", map[string]any{"summary": "private synthetic text", "people": []map[string]string{{"name": "A", "role": "actor"}}})
	if r.Code != 200 {
		t.Fatalf("valid typed write %d %s", r.Code, r.Body.String())
	}
	e.record("MetadataFields", http.MethodPut, path+"/overrides", r)
	var leaked int
	if err := e.pool.QueryRow(context.Background(), `SELECT count(*) FROM admin_audit WHERE detail::text LIKE '%private synthetic text%'`).Scan(&leaked); err != nil || leaked != 0 {
		t.Fatalf("auditdetail bevat tekst: %d %v", leaked, err)
	}
	page := e.auditPage(auditPath, 200)
	raw, _ := json.Marshal(page)
	if strings.Contains(string(raw), "private synthetic text") {
		t.Fatal("audit leaked manual text")
	}
	found := false
	for _, entry := range page.Items {
		if entry.Operation == "setMetadataOverrides" {
			found = true
		}
	}
	if !found {
		t.Fatal("missing override audit")
	}
	claims, err := e.signer.Verify(e.access, auth.TokenAccess)
	if err != nil {
		t.Fatal(err)
	}
	e.revocations.Revoke(id.MustParse(claims.Sid), time.Now())
	if r := e.do(http.MethodPut, path+"/overrides", map[string]string{"summary": "revoked"}); r.Code != 401 {
		t.Fatalf("revoked write: %d", r.Code)
	}
}

func TestMetadataOverridesRequireWholeJSONBeforeAnyWrite(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	item := e.findMovie("Grease").ID
	path := "/pleya/v1/items/" + item + "/overrides"
	snapshot := func() (string, string) {
		t.Helper()
		var row, audit string
		if err := e.pool.QueryRow(context.Background(), `SELECT to_jsonb(i)::text FROM media_items i WHERE id=$1`, item).Scan(&row); err != nil {
			t.Fatal(err)
		}
		if err := e.pool.QueryRow(context.Background(), `SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY id)::text,'[]') FROM admin_audit a`).Scan(&audit); err != nil {
			t.Fatal(err)
		}
		return row, audit
	}
	before, beforeAudit := snapshot()
	for _, suffix := range []string{` {"unexpected":true}`, ` 7`, ` true`, ` null`, ` garbage`} {
		r := e.do(http.MethodPut, path, nil, rawBody(`{"summary":"must not write"}`+suffix))
		if r.Code != 400 {
			t.Errorf("trailing %q: %d %s", suffix, r.Code, r.Body.String())
		}
		after, afterAudit := snapshot()
		if before != after || beforeAudit != afterAudit {
			t.Fatalf("trailing %q wijzigde data/audit", suffix)
		}
	}
	if r := e.do(http.MethodPut, path, nil, rawBody("  {\"summary\":\"whitespace is valid\"} \n\t ")); r.Code != 200 {
		t.Fatalf("normale whitespace geweigerd: %d %s", r.Code, r.Body.String())
	}
}
