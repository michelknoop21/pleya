package api

import (
	"net/http"
	"testing"
)

// TestErrorRegisterMatchesTheSpecification houdt de tabel gelijk aan hoofdstuk
// 7.1 van de specificatie.
//
// De code is het contract en de status draagt de grofmazige categorie; lopen die
// twee uiteen, dan leest een client iets anders uit het een dan uit het ander.
func TestErrorRegisterMatchesTheSpecification(t *testing.T) {
	want := map[string]struct {
		status    int
		retryable bool
	}{
		"auth.invalid_credentials":       {401, false},
		"auth.token_expired":             {401, false},
		"auth.token_invalid":             {401, false},
		"auth.refresh_token_reused":      {401, false},
		"auth.setup_required":            {409, false},
		"auth.setup_already_completed":   {409, false},
		"auth.setup_code_invalid":        {401, false},
		"auth.rate_limited":              {429, true},
		"library.not_found":              {404, false},
		"library.scan_in_progress":       {409, true},
		"library.cursor_invalid":         {400, false},
		"library.search_query_empty":     {400, false},
		"library.version_multifile":      {409, false},
		"playback.version_unavailable":   {409, true},
		"playback.range_not_satisfiable": {416, false},
		"playback.not_playable":          {415, false},
		"storage.unavailable":            {503, true},
		"storage.full":                   {507, false},
		"session.invalid":                {400, false},
		"session.stream_session_limit":   {429, false},
	}

	for code, expect := range want {
		entry, ok := errorTable[code]
		if !ok {
			t.Errorf("%s staat niet in het register", code)
			continue
		}
		if entry.status != expect.status {
			t.Errorf("%s geeft %d, de specificatie zegt %d", code, entry.status, expect.status)
		}
		if entry.retryable != expect.retryable {
			t.Errorf("%s heeft retryable=%v, de specificatie zegt %v", code, entry.retryable, expect.retryable)
		}
	}
	for code := range errorTable {
		if _, ok := want[code]; !ok {
			t.Errorf("%s staat in het register maar niet in de specificatie", code)
		}
	}
}

// TestWriteInternalUsesTheRegister vangt een status die de code tegenspreekt.
func TestWriteInternalUsesTheRegister(t *testing.T) {
	status, ok := registeredStatus(CodeStorageUnavailable)
	if !ok {
		t.Fatal("storage.unavailable staat niet in het register")
	}
	if status == http.StatusInternalServerError {
		t.Fatal("het register geeft storage.unavailable een 500; dat spreekt de specificatie tegen")
	}
}
