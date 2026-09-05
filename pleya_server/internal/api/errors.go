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

	// De vier codes van PS-9 (DEC-101, protocolwijziging 7). user_not_found en
	// session_not_found volgen de 404-regel van hoofdstuk 7.1: een gebruiker of
	// sessie die de aanvrager niet mag zien bestaat voor hem niet.
	CodeUserNotFound    = "auth.user_not_found"
	CodeUsernameTaken   = "auth.username_taken"
	CodeOwnerImmutable  = "auth.owner_immutable"
	CodeSessionNotFound = "auth.session_not_found"

	// CodePermissionNotAllowed is de code die venster 1 toevoegt voor een
	// rechtencombinatie die de rol van het doel verbiedt (J.2 rij 11): manage
	// voor een restricted (DEC-098 paragraaf 3). Tot nu toe droeg dat geval
	// auth.user_not_found, en dat was de minst onjuiste van wat er stond.
	//
	// Hij hoort bij de 409's en niet bij de 404's, en dat is de uitzondering
	// die de regel bevestigt: de 404-regel verbergt het bestaan van iets dat de
	// aanvrager niet mag zien, maar de aanvrager is hier per definitie een
	// beheerder die de gebruiker en de bibliotheek allebei al mag zien. Er valt
	// niets te verbergen, alleen iets uit te leggen, en een 404 zou dan een
	// beheerder laten zoeken naar een gebruiker die er gewoon is.
	CodePermissionNotAllowed = "auth.permission_not_allowed"

	// CodeScopeExceedsRole is het antwoord van POST /auth/api-tokens op een
	// bereik dat boven de rol van de eigenaar uitkomt (J.2 rij 12, K rij 22).
	//
	// 400 en geen 409: er is geen toestand die dit verzoek in de weg zit en die
	// later anders zou kunnen zijn, het verzoek zelf klopt niet. details draagt
	// het gevraagde bereik en de rol, zodat een beheerscherm kan zeggen wat er
	// mis is zonder de tekst te lezen.
	//
	// De rol in het antwoord is die van de toekomstige eigenaar en niet die van
	// de aanvrager. Dat lekt niets: wie hier komt is de eigenaar zelf, of een
	// beheerder die de rol van zijn gebruikers sowieso ziet in GET /users.
	CodeScopeExceedsRole = "auth.scope_exceeds_role"

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

	// CodeSettingsInvalidValue is het antwoord van PATCH /settings op een waarde
	// buiten zijn grens en op een sleutel die niet bestaat (J.2 rij 2, K rij
	// 14). details draagt het veld en de grens, zodat een beheerscherm kan
	// zeggen wat er mis is zonder de tekst te lezen.
	CodeSettingsInvalidValue = "settings.invalid_value"

	// CodeStreamSessionLimit is de negende actieve streamsessie (DEC-051). Een
	// stabiele code en geen generieke 429: de client moet het verschil zien met
	// een rate limiter, want hier helpt wachten niet maar een stream sluiten wel.
	CodeStreamSessionLimit = "session.stream_session_limit"

	// CodeInternal is het antwoord op een fout die de handler zelf niet had
	// voorzien: de recovery-laag vangt een panic af en maakt er een envelop van
	// in plaats van een verbroken verbinding (J.2 rij 17, DEC-110 en DEC-111).
	// `details.request_id` verwijst naar de logregel met de stack; de stack
	// zelf verlaat de server niet.
	//
	// retryable is false en niet true. Het contract dwingt een boolean af waar
	// "onbekend" het eerlijke antwoord zou zijn, en van de twee is false de
	// veilige: een deterministische panic die als retryable binnenkomt levert
	// een client op die de server blijft raken op precies het verzoek dat hem
	// omver duwde.
	CodeInternal = "server.internal"

	// CodeConfirmMismatch is het antwoord op een destructieve handeling waarvan
	// de bevestiging ontbreekt of niet klopt (K rij 16). Voor S1.3 is dat
	// POST /server/rotate-signing-key met confirm: "rotate".
	//
	// Een eigen code en geen settings.invalid_value: dit is geen waarde buiten
	// een grens maar een handeling die niet is bevestigd, en 409 zegt dat ook
	// in de status. Hij staat in het domein server, dat DEC-111 met venster 1
	// heeft toegevoegd; het foutpatroon in het contract draagt hem daarmee al,
	// dus er is geen schemawijziging voor nodig.
	//
	// De aanleiding voor het bestaan is een gat tussen twee plannen: J.2 laat
	// de foutkolom van rotate-signing-key leeg, terwijl K rij 16 een 409 op een
	// ontbrekende of foute confirm eist. Van die twee is K de specifiekere en
	// de veiligste, en die is hier gevolgd.
	CodeConfirmMismatch = "server.confirm_mismatch"
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

	CodeUserNotFound:         {http.StatusNotFound, false},
	CodeUsernameTaken:        {http.StatusConflict, false},
	CodeOwnerImmutable:       {http.StatusConflict, false},
	CodeSessionNotFound:      {http.StatusNotFound, false},
	CodePermissionNotAllowed: {http.StatusConflict, false},
	CodeScopeExceedsRole:     {http.StatusBadRequest, false},

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

	CodeSessionInvalid:       {http.StatusBadRequest, false},
	CodeSettingsInvalidValue: {http.StatusBadRequest, false},
	CodeStreamSessionLimit:   {http.StatusTooManyRequests, false},

	CodeInternal:        {http.StatusInternalServerError, false},
	CodeConfirmMismatch: {http.StatusConflict, false},
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
// De code is server.internal en niet storage.unavailable. Het register is het
// contract en de status komt daaruit, niet uit een eigen keuze; tot venster 1
// had het register geen code voor een fout die de server zichzelf aandoet, en
// toen was storage.unavailable de minst onjuiste van wat er stond. Sinds
// DEC-111 staat server.internal erin en is die reden weg.
//
// Het verschil is niet cosmetisch. storage.unavailable is een 503 met
// retryable=true en zegt tegen een client: de opslag is even weg, probeer het
// zo nog eens. Een nil-pointer in een handler gaat bij elke poging opnieuw
// stuk, en dan blijft een client de server raken op precies het verzoek dat
// hem omver duwde. storage.unavailable blijft voor het geval waar de opslag
// werkelijk niet bereikbaar is.
func writeInternal(w http.ResponseWriter, log *slog.Logger, err error) {
	if log != nil {
		log.Error("interne fout", slog.String("error", err.Error()))
	}
	writeError(w, nil, CodeInternal, "internal error", nil)
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
