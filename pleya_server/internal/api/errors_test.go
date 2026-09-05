package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
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
		"auth.user_not_found":            {404, false},
		"auth.username_taken":            {409, false},
		"auth.owner_immutable":           {409, false},
		"auth.session_not_found":         {404, false},
		"auth.permission_not_allowed":    {409, false},
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
		"settings.invalid_value":         {400, false},
		"session.stream_session_limit":   {429, false},
		"server.internal":                {500, false},
		"server.confirm_mismatch":        {409, false},
	}

	// Deze tabel spiegelt hoofdstuk 7.1 voor zover deze server hem draait.
	// settings.invalid_value kwam erbij met S1.2, server.confirm_mismatch met
	// S1.3 en auth.permission_not_allowed met S1.4, elk samen met het endpoint
	// dat hem stuurt: een code in het register zonder handler zou hier groen
	// staan en in het contract een belofte zijn die niemand nakomt.

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

// TestWriteInternalAnswersServerInternal legt vast welk domein een onvoorziene
// fout in deze server krijgt.
//
// Tot venster 1 was dat storage.unavailable, omdat het register niets beters
// had. Sinds DEC-111 heeft het server.internal, en dan is opslag noemen bij een
// fout die niets met opslag te maken heeft een onwaar antwoord.
func TestWriteInternalAnswersServerInternal(t *testing.T) {
	rec := httptest.NewRecorder()
	writeInternal(rec, nil, errors.New("een fout die de handler niet had voorzien"))

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, wil 500", rec.Code)
	}
	var body errorEnvelope
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("antwoord is geen envelop: %v", err)
	}
	if body.Error.Code != CodeInternal {
		t.Fatalf("code = %q, wil %q", body.Error.Code, CodeInternal)
	}
	if body.Error.Retryable {
		t.Fatal("retryable = true; een deterministische fout opnieuw laten proberen levert dezelfde fout op")
	}
	if body.Error.Message != "internal error" {
		t.Fatalf("message = %q; de oorzaak hoort in het log en niet op de lijn", body.Error.Message)
	}
}

// TestStorageUnavailableKeepsItsOwnMeaning is de andere helft van hetzelfde
// onderscheid: de code blijft bestaan, met zijn eigen status en retryable, voor
// opslag die werkelijk weg is.
//
// Zonder deze helft zou een repareerpoging die storage.unavailable gewoon op
// 500 zet ook groen zijn, en dan was het onderscheid alsnog verdwenen.
func TestStorageUnavailableKeepsItsOwnMeaning(t *testing.T) {
	rec := httptest.NewRecorder()
	writeError(rec, nil, CodeStorageUnavailable, "opslag niet bereikbaar", nil)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, wil 503", rec.Code)
	}
	var body errorEnvelope
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("antwoord is geen envelop: %v", err)
	}
	if body.Error.Code != CodeStorageUnavailable {
		t.Fatalf("code = %q, wil %q", body.Error.Code, CodeStorageUnavailable)
	}
	if !body.Error.Retryable {
		t.Fatal("retryable = false; opslag die weg is kan terugkomen, en dan is opnieuw proberen juist wel zinvol")
	}
}
