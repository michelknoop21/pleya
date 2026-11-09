package api

import (
	"context"
	"net/http"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	tools "github.com/edde746/plezy/pleya_server/internal/mcp"
)

type mcpAuditKey struct{}
type mcpAdminKey struct{}
type mcpAuditState struct {
	written   bool
	operation string
}

func (s *Server) mcpEnabled() bool {
	return s.mcpHandler != nil && s.settings().MCPEnabled()
}

func (s *Server) mcpStatus() *ServerMCPWire {
	status := &ServerMCPWire{Enabled: s.mcpEnabled()}
	if status.Enabled {
		endpoint := "/mcp"
		status.URL = &endpoint
		status.ToolCount = len(tools.Operations())
	}
	return status
}

func (s *Server) configureMCP() {
	s.mcpLimiter = newLimiter()
	s.mcpLimiter.preserveBuckets = true
	s.mcpLimiter.burst, s.mcpLimiter.refill = 60, 1
	s.mcpHandler = tools.New(http.HandlerFunc(s.dispatchMCP), mcpToolVisible)
}

func (s *Server) handleMCP(w http.ResponseWriter, r *http.Request) {
	if !s.mcpEnabled() {
		http.NotFound(w, r)
		return
	}
	principal, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	if ok, wait := s.mcpLimiter.allow(principal.String()); !ok {
		w.Header().Set("Retry-After", retryAfterSeconds(wait))
		writeError(w, s.log, CodeRateLimited, "too many attempts", map[string]any{"retry_after_ms": wait.Milliseconds()})
		return
	}
	request := r.Clone(context.WithValue(r.Context(), mcpAdminKey{}, s.requesterIsAdmin(r)))
	s.mcpHandler.ServeHTTP(w, request)
}

// dispatchMCP houdt de bestaande router en alle controles op het aanvraagpad.
func (s *Server) dispatchMCP(w http.ResponseWriter, r *http.Request) {
	invocation := tools.FromRequest(r)
	state := &mcpAuditState{operation: invocation.Operation.Name}
	r = r.WithContext(context.WithValue(r.Context(), mcpAuditKey{}, state))
	if invocation.Operation.Method != http.MethodGet || r.Method != http.MethodGet {
		s.auditEvent(r, invocation.Operation.Name, r.URL.Path, audit.OutcomeDenied, map[string]any{"reason": "approval_required"})
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "approval_required"})
		return
	}
	rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
	s.maintenanceGate(s.bodyLimit(s.mux)).ServeHTTP(rec, r)
	if r.Method != http.MethodGet && !state.written {
		outcome := audit.OutcomeOK
		if rec.status >= 400 {
			outcome = audit.OutcomeFailed
		}
		if rec.status == 401 || rec.status == 403 || rec.status == 404 {
			outcome = audit.OutcomeDenied
		}
		s.auditEvent(r, invocation.Operation.Name, r.URL.Path, outcome, nil)
	}
}

// Ontdekking is beperkter dan aanroepen; de API autoriseert ook verborgen tools opnieuw.
func mcpToolVisible(r *http.Request, name string) bool {
	if admin, _ := r.Context().Value(mcpAdminKey{}).(bool); admin {
		return true
	}
	// Nieuwe tools blijven buiten het beperkte register totdat hun leesklasse is gecontroleerd.
	switch name {
	case "getInfo", "getServer", "listLibraries", "listLibraryItems", "getLibraryFacets",
		"getItem", "listItemChildren", "getHub", "search", "getArtwork", "getStream", "getSubtitle",
		"getCurrentUser", "getActivitySharing", "getMemory", "getHistory", "listWatchState",
		"getTrackPreference", "listFavorites", "listRatings", "getItemActivity",
		"listCollections", "getCollection", "listCollectionItems", "listPlaylists", "getPlaylist", "listPlaylistItems",
		"listDownloads", "getDownload", "getDownloadFile", "getPlaybackSessionFile", "listSessions", "listApiTokens":
		return true
	}
	return false
}
