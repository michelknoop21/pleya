// Package api is de HTTP-laag die het Pleya Protocol v1 implementeert.
//
// De wire-types staan hier en nergens anders. Hoofdstuk 12.1 van de
// architectuur is daar stellig over: wire-types en domeintypes zijn twee dingen,
// met een expliciete mapper ertussen, en de HTTP-laag kent alleen het wire-type.
// De bestaande fout die die regel oplevert staat in pleya_share_protocol.dart,
// waar server en client aan hetzelfde Dart-model vastzitten.
package api

import (
	"encoding/json"
	"log/slog"
	"net/http"
)

// Error is de enige foutvorm die dit protocol kent.
//
// De code is het contract; het bericht is voor logs en niet voor de UI. Een
// client vertaalt codes naar tekst en mag nooit op de tekst matchen.
type Error struct {
	Code      string         `json:"code"`
	Message   string         `json:"message"`
	Retryable bool           `json:"retryable"`
	Details   map[string]any `json:"details,omitempty"`
}

type errorEnvelope struct {
	Error Error `json:"error"`
}

// De codes uit hoofdstuk 7.1 van de specificatie. Uitbreiden mag; de betekenis
// van een bestaande code wijzigen niet.
const (
	CodeInvalidCredentials    = "auth.invalid_credentials"
	CodeTokenExpired          = "auth.token_expired"
	CodeTokenInvalid          = "auth.token_invalid"
	CodeRefreshTokenReused    = "auth.refresh_token_reused"
	CodeSetupRequired         = "auth.setup_required"
	CodeSetupAlreadyCompleted = "auth.setup_already_completed"
	CodeSetupCodeInvalid      = "auth.setup_code_invalid"
	CodeRateLimited           = "auth.rate_limited"

	CodeNotFound         = "library.not_found"
	CodeScanInProgress   = "library.scan_in_progress"
	CodeCursorInvalid    = "library.cursor_invalid"
	CodeSearchQueryEmpty = "library.search_query_empty"
	CodeVersionMultifile = "library.version_multifile"

	CodeVersionUnavailable  = "playback.version_unavailable"
	CodeRangeNotSatisfiable = "playback.range_not_satisfiable"
	CodeNotPlayable         = "playback.not_playable"

	CodeStorageUnavailable = "storage.unavailable"
	CodeStorageFull        = "storage.full"

	CodeSessionInvalid = "session.invalid"

	// CodeStreamSessionLimit is de negende actieve streamsessie (DEC-051). Een
	// stabiele code en geen generieke 429: de client moet het verschil zien met
	// een rate limiter, want hier helpt wachten niet maar een stream sluiten wel.
	CodeStreamSessionLimit = "session.stream_session_limit"
)

// httpStatus koppelt elke code aan zijn status en aan retryable. Het staat in
// één tabel omdat het coderegister in de specificatie dat ook doet, en twee
// plekken die dit apart bijhouden lopen uit elkaar.
var errorTable = map[string]struct {
	status    int
	retryable bool
}{
	CodeInvalidCredentials:    {http.StatusUnauthorized, false},
	CodeTokenExpired:          {http.StatusUnauthorized, false},
	CodeTokenInvalid:          {http.StatusUnauthorized, false},
	CodeRefreshTokenReused:    {http.StatusUnauthorized, false},
	CodeSetupRequired:         {http.StatusConflict, false},
	CodeSetupAlreadyCompleted: {http.StatusConflict, false},
	CodeSetupCodeInvalid:      {http.StatusUnauthorized, false},
	CodeRateLimited:           {http.StatusTooManyRequests, true},

	CodeNotFound:         {http.StatusNotFound, false},
	CodeScanInProgress:   {http.StatusConflict, true},
	CodeCursorInvalid:    {http.StatusBadRequest, false},
	CodeSearchQueryEmpty: {http.StatusBadRequest, false},
	CodeVersionMultifile: {http.StatusConflict, false},

	CodeVersionUnavailable:  {http.StatusConflict, true},
	CodeRangeNotSatisfiable: {http.StatusRequestedRangeNotSatisfiable, false},
	CodeNotPlayable:         {http.StatusUnsupportedMediaType, false},

	CodeStorageUnavailable: {http.StatusServiceUnavailable, true},
	CodeStorageFull:        {http.StatusInsufficientStorage, false},

	CodeSessionInvalid:     {http.StatusBadRequest, false},
	CodeStreamSessionLimit: {http.StatusTooManyRequests, false},
}

// writeError stuurt de foutvorm met de status en retryable die bij de code horen.
func writeError(w http.ResponseWriter, log *slog.Logger, code, message string, details map[string]any) {
	entry, known := errorTable[code]
	if !known {
		// Een code die niet in het register staat is een fout in deze server en
		// niet in het verzoek. Hem als 500 laten gaan is eerlijker dan hem een
		// plausibele status te geven.
		if log != nil {
			log.Error("foutcode staat niet in het register", slog.String("code", code))
		}
		entry.status = http.StatusInternalServerError
	}

	writeJSON(w, entry.status, errorEnvelope{Error: Error{
		Code:      code,
		Message:   message,
		Retryable: entry.retryable,
		Details:   details,
	}})
}

// writeInternal verbergt de oorzaak voor de client en laat hem in het log.
//
// De status komt uit het coderegister en niet uit een eigen keuze. Een 500 met
// storage.unavailable erin zou de tabel in hoofdstuk 7.1 tegenspreken, en dan
// leest een client iets anders uit de status dan uit de code. Het register is
// het contract, dus dat wint.
func writeInternal(w http.ResponseWriter, log *slog.Logger, err error) {
	if log != nil {
		log.Error("interne fout", slog.String("error", err.Error()))
	}
	writeError(w, nil, CodeStorageUnavailable, "internal error", nil)
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	_ = enc.Encode(body)
}

// registeredStatus geeft de status die het coderegister aan deze code toekent.
// Alleen voor tests: het register hoort de enige bron te zijn.
func registeredStatus(code string) (int, bool) {
	entry, ok := errorTable[code]
	return entry.status, ok
}
