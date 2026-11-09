package mcp

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"net/url"
	"strings"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"
)

const maxResultBytes = 1 << 20

type invocationKey struct{}

// Invocation hoort bij de gevalideerde toolaanroep, nooit bij een HTTP-header.
type Invocation struct {
	Operation Operation
}

func FromRequest(r *http.Request) Invocation {
	value, _ := r.Context().Value(invocationKey{}).(Invocation)
	return value
}

func execute(ctx context.Context, parent *http.Request, dispatch http.Handler, operation Operation, args map[string]any) (*sdk.CallToolResult, error) {
	if operation.Method != http.MethodGet {
		return nil, errors.New("approval_required: G1 ontbreekt")
	}
	path := "/pleya/v1" + operation.Path
	if values, ok := args["path"].(map[string]any); ok {
		for name, value := range values {
			segment, ok := value.(string)
			if !ok || segment == "" || segment == "." || segment == ".." || strings.ContainsAny(segment, "/\\") {
				return nil, errors.New("ongeldig padargument")
			}
			path = strings.ReplaceAll(path, "{"+name+"}", url.PathEscape(segment))
		}
	}
	if strings.ContainsAny(path, "{}") {
		return nil, errors.New("padargument ontbreekt")
	}
	query := url.Values{}
	if values, ok := args["query"].(map[string]any); ok {
		for name, value := range values {
			if list, ok := value.([]any); ok {
				for _, v := range list {
					query.Add(name, fmt.Sprint(v))
				}
			} else {
				query.Set(name, fmt.Sprint(value))
			}
		}
	}
	var body []byte
	if value, ok := args["body"]; ok {
		var err error
		body, err = json.Marshal(value)
		if err != nil {
			return nil, err
		}
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	ctx = context.WithValue(ctx, invocationKey{}, Invocation{Operation: operation})
	request, err := http.NewRequestWithContext(ctx, operation.Method, path+"?"+query.Encode(), bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	request.RemoteAddr = parent.RemoteAddr
	request.Host = parent.Host
	request.Header.Set("Authorization", parent.Header.Get("Authorization"))
	request.Header.Set("Content-Type", "application/json")
	if values, ok := args["header"].(map[string]any); ok {
		for name, value := range values {
			if strings.EqualFold(name, "Authorization") || strings.EqualFold(name, "Cookie") {
				return nil, errors.New("credentialheader niet toegestaan")
			}
			request.Header.Set(name, fmt.Sprint(value))
		}
	}
	response := &resultWriter{headers: make(http.Header), status: http.StatusOK, cancel: cancel}
	dispatch.ServeHTTP(response, request)
	if response.overflow {
		return nil, errors.New("antwoord groter dan 1 MiB; gebruik paginering")
	}
	result := &sdk.CallToolResult{IsError: response.status >= 400, Content: []sdk.Content{}}
	if response.binary && response.status < 400 {
		return nil, errors.New("binaire resultaten zijn niet beschikbaar via MCP")
	}
	result.Content = append(result.Content, &sdk.TextContent{Text: response.body.String()})
	return result, nil
}

type resultWriter struct {
	headers          http.Header
	status           int
	wrote            bool
	body             bytes.Buffer
	overflow, binary bool
	cancel           context.CancelFunc
}

func (w *resultWriter) Header() http.Header { return w.headers }
func (w *resultWriter) WriteHeader(status int) {
	if w.wrote {
		return
	}
	w.wrote = true
	w.status = status
	kind, _, _ := mime.ParseMediaType(w.headers.Get("Content-Type"))
	w.binary = kind != "" && kind != "application/json" && !strings.HasPrefix(kind, "text/") && kind != "application/vnd.apple.mpegurl"
}
func (w *resultWriter) Write(data []byte) (int, error) {
	if !w.wrote {
		w.WriteHeader(http.StatusOK)
	}
	if w.binary {
		w.cancel()
		return 0, io.ErrClosedPipe
	}
	if w.body.Len()+len(data) > maxResultBytes {
		w.overflow = true
		w.cancel()
		return 0, io.ErrShortBuffer
	}
	return w.body.Write(data)
}
