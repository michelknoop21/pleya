package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

func (e *env) enableMCP() {
	e.t.Helper()
	if got := e.do("PATCH", "/pleya/v1/settings", map[string]any{"mcp_enabled": true}); got.Code != 200 {
		e.t.Fatalf("MCP inschakelen: %d %s", got.Code, got.Body)
	}
}

func (e *env) mcpCall(name string, args map[string]any, opts ...func(*http.Request)) map[string]any {
	e.t.Helper()
	headers := []func(*http.Request){withHeader("Accept", "application/json, text/event-stream"), withHeader("MCP-Protocol-Version", "2025-06-18")}
	headers = append(headers, opts...)
	rec := e.do("POST", "/mcp", map[string]any{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": map[string]any{"name": name, "arguments": args}}, headers...)
	if rec.Code != http.StatusOK {
		e.t.Fatalf("MCP HTTP%d: %s", rec.Code, rec.Body.String())
	}
	var result struct {
		Result map[string]any `json:"result"`
		Error  any            `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &result); err != nil {
		e.t.Fatalf("MCP: %s %v", rec.Body, err)
	}
	if result.Error != nil {
		return map[string]any{"isError": true, "rpcError": result.Error}
	}
	return result.Result
}

func TestMCPReusesRolesAndRejectsSelfConfirmedAdministration(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	e.enableMCP()
	read := e.createToken(map[string]any{"name": "MCP read", "scope": "read"}, 201)
	admin := e.createToken(map[string]any{"name": "MCP admin", "scope": "admin"}, 201)
	if e.mcpCall("listLibraries", map[string]any{}, asToken(read.Secret))["isError"] == true {
		t.Fatal("read failed")
	}
	if e.mcpCall("getSettings", map[string]any{}, asToken(read.Secret))["isError"] != true {
		t.Fatal("read scope gained admin access")
	}
	if e.mcpCall("getSettings", map[string]any{}, asToken(admin.Secret))["isError"] == true {
		t.Fatal("admin read failed")
	}
	user := e.createUserViaAPI("mcp-preserve", "synthetic-long-password", "member", 200)
	for _, name := range []string{"deleteUser", "restoreBackup", "rotateSigningKey", "deleteLibrary", "setUserPermissions", "patchSettings"} {
		args := map[string]any{"confirm": name, "path": map[string]any{"id": user.ID}}
		if name == "patchSettings" {
			args = map[string]any{"confirm": name, "body": map[string]any{"server_name": "unapproved"}}
		}
		result := e.mcpCall(name, args, asToken(admin.Secret))
		if result["isError"] != true {
			t.Fatalf("self-confirmation executed %s", name)
		}
	}
	var exists bool
	if err := e.pool.QueryRow(context.Background(), `SELECT EXISTS(SELECT 1 FROM users WHERE id=$1)`, user.ID).Scan(&exists); err != nil || !exists {
		t.Fatalf("user lost: %v", err)
	}
}

func TestMCPDisabledAndMissingCredentials(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	if got := e.do("POST", "/mcp", nil); got.Code != 404 {
		t.Fatalf("uitgeschakeld: %d", got.Code)
	}
	var info api.Info
	e.getJSON("/pleya/v1/info", "Info", 200, &info)
	if info.Capabilities.MCP {
		t.Fatal("uitgeschakeld transport adverteert capability")
	}
	on := newEnv(t)
	on.setup(on.putSetupCode())
	on.enableMCP()
	if got := on.do("POST", "/mcp", nil, withoutAuth); got.Code != 401 {
		t.Fatalf("zonder credential: %d", got.Code)
	}
}

func TestMCPMemoryMutationIsUnavailable(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	e.enableMCP()
	before := e.memoryGet()
	result := e.mcpCall("replaceMemory", map[string]any{"confirm": "replaceMemory", "body": map[string]any{"facts": []any{}}})
	if result["isError"] != true || e.memoryGet().Revision != before.Revision {
		t.Fatal("MCP changed memory")
	}
}

func TestMCPSettingHotReloadAndNullRejection(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	for _, value := range []any{nil, "true", 1} {
		rec := e.do("PATCH", "/pleya/v1/settings", map[string]any{"mcp_enabled": value, "server_name": "Niet opslaan"})
		if rec.Code != 400 {
			t.Fatalf("ongeldige bool%v: %d", value, rec.Code)
		}
	}
	e.enableMCP()
	if result := e.mcpCall("getInfo", map[string]any{}); result["isError"] == true {
		t.Fatal(result)
	}
	if rec := e.do("PATCH", "/pleya/v1/settings", map[string]any{"mcp_enabled": false}); rec.Code != 200 {
		t.Fatal(rec.Body)
	}
	if rec := e.do("POST", "/mcp", nil); rec.Code != 404 {
		t.Fatalf("niet direct uitgezet: %d", rec.Code)
	}
}

func TestMCPCredentialAndRoleOperationsAreUnavailable(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	e.enableMCP()
	for _, name := range []string{"login", "refresh", "completeSetup", "createUser", "createApiToken", "issueStreamToken", "createStreamSession", "createCompanionTicket"} {
		result := e.mcpCall(name, map[string]any{"body": map[string]any{"username": "backdoor", "password": "synthetic-blocked-password", "role": "admin"}})
		encoded, _ := json.Marshal(result)
		if result["isError"] != true || strings.Contains(string(encoded), "synthetic-blocked-password") {
			t.Fatalf("credential operation exposed: %s", name)
		}
	}
}

func TestMCPDoesNotReflectBinaryURLsOrStreamSecrets(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	e.enableMCP()
	for _, name := range []string{"getArtwork", "getMetadataCandidateArtwork", "getDownloadFile", "getBackup", "getStream", "getSubtitle", "getPlaybackSessionFile"} {
		result := e.mcpCall(name, map[string]any{"query": map[string]any{"stream_token": "synthetic-stream-secret"}}, func(r *http.Request) { r.Host = "untrusted.invalid" })
		encoded, _ := json.Marshal(result)
		if result["isError"] != true || strings.Contains(string(encoded), "synthetic-stream-secret") || strings.Contains(string(encoded), "untrusted.invalid") {
			t.Fatalf("binary link escaped: %s", name)
		}
	}
}

func TestMCPRejectsBatchesBeforeAnyToolDispatch(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	e.enableMCP()
	for _, version := range []string{"", "2025-06-18", "2025-11-25"} {
		body := []any{map[string]any{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": map[string]any{"name": "getInfo"}}, map[string]any{"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": map[string]any{"name": "restoreBackup", "arguments": map[string]any{"confirm": "restoreBackup"}}}}
		rec := e.do("POST", "/mcp", body, withHeader("Accept", "application/json, text/event-stream"), withHeader("MCP-Protocol-Version", version))
		if rec.Code != 400 || !strings.Contains(rec.Body.String(), "batch_not_supported") {
			t.Fatalf("batch accepted: %d %s", rec.Code, rec.Body)
		}
	}
}
