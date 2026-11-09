package api_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"
)

type mcpCredentialTransport struct{ token string }

func (t mcpCredentialTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	copy := r.Clone(r.Context())
	copy.Header.Set("Authorization", "Bearer "+t.token)
	return http.DefaultTransport.RoundTrip(copy)
}

func TestMCPClientInitializeListAndExistingOperations(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	e.enableMCP()
	token := e.createToken(map[string]any{"name": "MCP interoperability", "scope": "admin"}, http.StatusCreated)
	server := httptest.NewServer(e.server.Handler())
	defer server.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	client := sdk.NewClient(&sdk.Implementation{Name: "acceptance fixture", Version: "1"}, nil)
	session, err := client.Connect(ctx, &sdk.StreamableClientTransport{Endpoint: server.URL + "/mcp", HTTPClient: &http.Client{Transport: mcpCredentialTransport{token: token.Secret}}}, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer session.Close()
	listed, err := session.ListTools(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(listed.Tools) != 49 {
		t.Fatalf("tools%d", len(listed.Tools))
	}
	for _, call := range []struct {
		name string
		args map[string]any
	}{
		{"listLibraries", map[string]any{}},
		{"getCurrentUser", map[string]any{}},
		{"getSettings", map[string]any{}},
	} {
		result, err := session.CallTool(ctx, &sdk.CallToolParams{Name: call.name, Arguments: call.args})
		if err != nil {
			t.Fatal(err)
		}
		if result.IsError {
			t.Fatalf("%s: %+v", call.name, result)
		}
	}
}
