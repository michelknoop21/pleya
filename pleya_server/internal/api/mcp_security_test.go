package api_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestMCPDiscoveryFollowsCurrentRoleAndTokenScope(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	e.enableMCP()
	read := e.createToken(map[string]any{"name": "limited discovery", "scope": "read"}, http.StatusCreated)
	adminID, admin := e.member("admin", "discovery-admin", "movies")
	_, member := e.member("member", "discovery-member", "movies")
	list := func(token string) map[string]bool {
		t.Helper()
		rec := e.do("POST", "/mcp", map[string]any{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}, asToken(token), withHeader("Accept", "application/json, text/event-stream"))
		if rec.Code != 200 {
			t.Fatalf("list HTTP%d: %s", rec.Code, rec.Body)
		}
		var result struct {
			Result struct {
				CacheScope string `json:"cacheScope"`
				TTLMs      int    `json:"ttlMs"`
				Tools      []struct {
					Name        string
					Description string
				}
			}
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &result); err != nil {
			t.Fatal(err)
		}
		if result.Result.CacheScope != "private" || result.Result.TTLMs != 0 {
			t.Fatalf("identiteitsafhankelijk register mag niet gedeeld worden gecachet: scope=%q ttl=%d HTTP=%q", result.Result.CacheScope, result.Result.TTLMs, rec.Header().Get("Cache-Control"))
		}
		names := map[string]bool{}
		for _, tool := range result.Result.Tools {
			names[tool.Name] = true
			if !strings.Contains(tool.Description, "onvertrouwde gegevens") {
				t.Fatalf("tool %s mist datagrens", tool.Name)
			}
		}
		if !names["listLibraries"] {
			t.Fatal("catalogus ontbreekt")
		}
		return names
	}
	for _, token := range []string{read.Secret, member} {
		names := list(token)
		for _, name := range []string{"patchSettings", "getSettings", "listUsers", "listAudit", "listJobs", "getServerLog", "getArtworkCandidates", "getMetadataMatchStatus"} {
			if names[name] {
				t.Fatalf("beperkt register bevat beheertool %s", name)
			}
		}
		if result := e.mcpCall("getSettings", map[string]any{}, asToken(token)); result["isError"] != true {
			t.Fatal("verborgen beheertool omzeilt API-rechten")
		}
	}
	if !list(admin)["getSettings"] {
		t.Fatal("beheerder mist beheertools")
	}
	if got := e.do("PATCH", "/pleya/v1/users/"+adminID.String(), map[string]any{"role": "member"}); got.Code != 200 {
		t.Fatalf("rol wijzigen HTTP%d %s", got.Code, got.Body)
	}
	if list(admin)["getSettings"] {
		t.Fatal("register bewaart oude beheerdersrol")
	}
}

func TestMCPRateLimitSharesPrincipalAndLeavesRESTAvailable(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	e.enableMCP()
	first := e.createToken(map[string]any{"name": "busy client", "scope": "read"}, http.StatusCreated)
	second := e.createToken(map[string]any{"name": "other client", "scope": "read"}, http.StatusCreated)
	body := map[string]any{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": map[string]any{"protocolVersion": "2025-06-18", "capabilities": map[string]any{}, "clientInfo": map[string]any{"name": "synthetic", "version": "1"}}}
	request := func(token string) int {
		t.Helper()
		rec := e.do("POST", "/mcp", body, asToken(token), withHeader("Accept", "application/json, text/event-stream"))
		if rec.Code == 429 && rec.Header().Get("Retry-After") == "" {
			t.Fatal("begrenzing mist Retry-After")
		}
		return rec.Code
	}
	limited := false
	for n := 0; n < 100; n++ {
		status := request(first.Secret)
		if status == 429 {
			limited = true
			break
		}
		if status != 200 {
			t.Fatalf("onverwachte status %d", status)
		}
	}
	if !limited {
		t.Fatal("MCP initialize blijft onbegrensd")
	}
	listed := e.do("POST", "/mcp", map[string]any{"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, asToken(first.Secret), withHeader("Accept", "application/json, text/event-stream"))
	if listed.Code != 429 {
		t.Fatalf("tools/list omzeilt de lege MCP-emmer: %d", listed.Code)
	}
	if status := request(second.Secret); status != 429 {
		t.Fatalf("ander token omzeilt gedeelde emmer: %d", status)
	}
	if rec := e.do("GET", "/pleya/v1/libraries", nil, asToken(first.Secret)); rec.Code != 200 {
		t.Fatalf("MCP begrenst REST: %d", rec.Code)
	}
}
