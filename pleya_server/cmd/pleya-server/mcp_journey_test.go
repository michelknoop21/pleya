package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/scanner"
	"github.com/edde746/plezy/pleya_server/internal/settings"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	sdk "github.com/modelcontextprotocol/go-sdk/mcp"
)

type journeyBearer string

func (token journeyBearer) RoundTrip(r *http.Request) (*http.Response, error) {
	request := r.Clone(r.Context())
	request.Header.Set("Authorization", "Bearer "+string(token))
	return http.DefaultTransport.RoundTrip(request)
}

func TestMCPGoldenJourneyUsesProductionScanHandler(t *testing.T) {
	testsupport.HasFFmpeg(t)
	pool := testsupport.Pool(t)
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatal(err)
	}
	store, credentials := catalog.NewStore(pool), auth.NewStore(pool)
	root, privateRoot := t.TempDir(), t.TempDir()
	testsupport.MakeVideo(t, filepath.Join(root, "Fixture (2026).mkv"), 1)
	logger := testLogger()
	runner := jobs.New(jobs.Options{Pool: pool, Logger: logger, Instance: "mcp-journey"})
	sc := scanner.New(scanner.Options{Store: store, Prober: ffprobe.New("ffprobe", time.Minute), Logger: logger, Concurrency: 1})
	runner.Register(api.JobScanLibrary, scanHandler(store, sc, runner, logger, nil))
	running := make(chan struct{})
	go func() { runner.Run(ctx); close(running) }()
	defer func() { cancel(); <-running }()
	signer, err := auth.NewSigner(make([]byte, 32))
	if err != nil {
		t.Fatal(err)
	}
	serverID, err := credentials.ServerID(ctx)
	if err != nil {
		t.Fatal(err)
	}
	cache := settings.NewCache(settings.Base{ServerName: "MCP journey", AccessTokenTTL: 15 * time.Minute, RefreshTokenTTL: 24 * time.Hour, StreamTokenTTL: 5 * time.Minute, StreamSessionTTL: 30 * time.Minute, MaxStreamSessions: 8}, settings.NewStore(pool), logger)
	service := api.New(api.Options{Catalog: store, Auth: credentials, Signer: signer, Logger: logger, ServerID: serverID, Settings: cache, Audit: audit.NewStore(pool), Jobs: runner, MediaRoots: []string{root, privateRoot}, SetupCodeTTL: 30 * time.Minute, Argon2: auth.Argon2Params{Memory: 8 * 1024, Iterations: 1, Parallelism: 1, SaltLength: 16, KeyLength: 32}})
	server := httptest.NewServer(service.Handler())
	defer server.Close()
	if err := credentials.PutSetupCode(ctx, auth.HashOpaque("synthetic-mcp-setup"), time.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	rest := func(method, path string, body any, token string) map[string]any {
		t.Helper()
		encoded, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		request, err := http.NewRequestWithContext(ctx, method, server.URL+"/pleya/v1"+path, bytes.NewReader(encoded))
		if err != nil {
			t.Fatal(err)
		}
		request.Header.Set("Content-Type", "application/json")
		if token != "" {
			request.Header.Set("Authorization", "Bearer "+token)
		}
		response, err := server.Client().Do(request)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		if response.StatusCode >= 300 {
			t.Fatalf("REST %s HTTP%d", path, response.StatusCode)
		}
		var result map[string]any
		if err := json.NewDecoder(response.Body).Decode(&result); err != nil {
			t.Fatal(err)
		}
		return result
	}
	pair := rest("POST", "/auth/setup", map[string]any{"setup_code": "synthetic-mcp-setup", "username": "owner", "password": "synthetic-only-password"}, "")
	access := pair["access_token"].(string)
	rest("PATCH", "/settings", map[string]any{"mcp_enabled": true}, access)
	admin := rest("POST", "/auth/api-tokens", map[string]any{"name": "MCP journey", "scope": "admin"}, access)["secret"].(string)
	connect := func(token string) *sdk.ClientSession {
		t.Helper()
		client := sdk.NewClient(&sdk.Implementation{Name: "journey fixture", Version: "1"}, nil)
		session, err := client.Connect(ctx, &sdk.StreamableClientTransport{Endpoint: server.URL + "/mcp", HTTPClient: &http.Client{Transport: journeyBearer(token)}}, nil)
		if err != nil {
			t.Fatal(err)
		}
		return session
	}
	adminSession := connect(admin)
	defer adminSession.Close()
	call := func(session *sdk.ClientSession, name string, args map[string]any) map[string]any {
		t.Helper()
		result, err := session.CallTool(ctx, &sdk.CallToolParams{Name: name, Arguments: args})
		if err != nil {
			t.Fatal(err)
		}
		if result.IsError {
			t.Fatalf("MCP operatie %s geweigerd: %+v", name, result.Content)
		}
		if len(result.Content) == 0 {
			return nil
		}
		text, ok := result.Content[0].(*sdk.TextContent)
		if !ok {
			t.Fatalf("geen JSON-antwoord op %s", name)
		}
		if text.Text == "" {
			return nil
		}
		var out map[string]any
		if err := json.Unmarshal([]byte(text.Text), &out); err != nil {
			t.Fatal(err)
		}
		return out
	}
	library := rest("POST", "/libraries", map[string]any{"title": "MCP films", "kind": "movies", "root_paths": []string{root}, "scan_on_start": false}, access)
	libraryID := library["id"].(string)
	rest("POST", "/libraries", map[string]any{"title": "Private films", "kind": "movies", "root_paths": []string{privateRoot}, "scan_on_start": false}, access)
	scan := rest("POST", "/libraries/"+libraryID+"/scan", nil, access)
	for {
		state := call(adminSession, "getScan", map[string]any{"path": map[string]any{"scan_id": scan["id"]}})
		if state["state"] == "done" {
			if state["files_seen"].(float64) < 1 {
				t.Fatal("scan heeft geen bestand gelezen")
			}
			break
		}
		if state["state"] == "failed" {
			t.Fatal("productiescan mislukt")
		}
		select {
		case <-ctx.Done():
			t.Fatal(ctx.Err())
		case <-time.After(100 * time.Millisecond):
		}
	}
	user := rest("POST", "/users", map[string]any{"username": "reader", "password": "synthetic-only-reader", "role": "member"}, access)
	rest("PUT", "/users/"+user["id"].(string)+"/permissions", map[string]any{"permissions": []any{map[string]any{"library_id": libraryID, "permission": "view"}}}, access)
	reader := rest("POST", "/auth/api-tokens", map[string]any{"user_id": user["id"], "name": "MCP reader", "scope": "read"}, access)["secret"].(string)
	rest("PATCH", "/settings", map[string]any{"server_name": "MCP journey accepted"}, access)
	readerSession := connect(reader)
	defer readerSession.Close()
	visible := call(readerSession, "listLibraries", map[string]any{})["items"].([]any)
	if len(visible) != 1 || visible[0].(map[string]any)["id"] != libraryID {
		t.Fatal("leestoken ziet meer dan de toegewezen bibliotheek")
	}
	denied, err := readerSession.CallTool(ctx, &sdk.CallToolParams{Name: "patchSettings", Arguments: map[string]any{"confirm": "patchSettings", "body": map[string]any{"server_name": "Forbidden"}}})
	if err == nil && (denied == nil || !denied.IsError) {
		t.Fatal("leestoken kon beheer uitvoeren")
	}
	for _, operation := range []string{"createLibrary", "startScan", "createUser", "setPermissions", "createApiToken", "patchSettings"} {
		var count int
		if err := pool.QueryRow(ctx, `SELECT count(*) FROM admin_audit WHERE source<>'mcp' AND operation=$1 AND outcome='ok'`, operation).Scan(&count); err != nil || count == 0 {
			t.Fatalf("audit ontbreekt voor %s: %v", operation, err)
		}
	}
}
