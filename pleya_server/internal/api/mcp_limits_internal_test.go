package api

import (
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestMCPEnvelopeRetainsOrdinaryOperationBodyLimits(t *testing.T) {
	for _, tc := range []struct {
		path    string
		size    int
		blocked bool
	}{
		{"/mcp", 16 << 10, false},
		{"/mcp", (264 << 10) + 1, true},
		{"/pleya/v1/users/me/memory", 16 << 10, false},
		{"/pleya/v1/users/me/memory", (256 << 10) + 1, true},
		{"/pleya/v1/auth/login", 16 << 10, true},
	} {
		t.Run(tc.path, func(t *testing.T) {
			r := httptest.NewRequest("POST", tc.path, bytes.NewReader(make([]byte, tc.size)))
			(&Server{}).bodyLimit(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				_, err := io.ReadAll(r.Body)
				if (err != nil) != tc.blocked {
					t.Fatalf("bodylimiet size%d blocked%v err%v", tc.size, tc.blocked, err)
				}
			})).ServeHTTP(httptest.NewRecorder(), r)
		})
	}
}
