package api

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// POST en GET /auth/api-tokens (S1.5, J.2 rij 12 en 13, RB-20).
//
// **Waarom dit geen beheerroute is.** RB-20 schrijft "een gebruiker (zelf, of
// een beheerder namens iemand)", en dat is een ander model dan admin-only. J.2
// zegt er niets over, dus de keuze staat hier expliciet: de autorisatie is die
// van GET /sessions (matrixregel 15). Zonder `user_id` gaan beide endpoints
// over de aanvrager zelf en antwoorden ze elke rol; met `user_id` van een ander
// gaan ze over die ander en antwoorden ze alleen owner en admin, met een 404
// voor de rest.
//
// De reden om admin-only af te wijzen is dat het bereik dan zijn nut verliest.
// Een lid dat een leestoken voor zijn eigen bibliotheek wil, zou dan een
// beheerder moeten vragen, en een beheerder die zo'n token maakt kan alleen een
// token maken dat de rol van het lid heeft. Het resultaat is hetzelfde token,
// met een extra mens ertussen. En andersom: was elk API-token een beheerding,
// dan zou `scope: read` voor een lid nooit voorkomen en zou `auth.scope_exceeds_role`
// een dode foutcode zijn.

// APITokenWire is één token in het overzicht (schema ApiToken). Zonder geheim:
// dat bestaat na het aanmaken alleen nog bij de aanvrager.
type APITokenWire struct {
	ID         string `json:"id"`
	UserID     string `json:"user_id"`
	Name       string `json:"name"`
	Scope      string `json:"scope"`
	CreatedAt  string `json:"created_at"`
	LastSeenAt string `json:"last_seen_at"`
	ExpiresAt  string `json:"expires_at"`
}

// APITokenListWire is het antwoord van GET /auth/api-tokens.
type APITokenListWire struct {
	Items []APITokenWire `json:"items"`
}

// APITokenCreatedWire is het antwoord van POST /auth/api-tokens.
//
// `secret` staat hier en in geen enkel ander antwoord. Dat is de reden dat dit
// een eigen schema is en niet ApiToken met een extra veld: een optioneel
// geheimveld op het lijsttype zou een lezer laten denken dat het er soms in kan
// staan, en dan is de vraag "kan dit antwoord een geheim dragen" niet meer aan
// het type te zien.
type APITokenCreatedWire struct {
	Token  APITokenWire `json:"token"`
	Secret string       `json:"secret"`
}

// createAPITokenRequest is de gesloten aanvraagbody (schema ApiTokenRequest).
type createAPITokenRequest struct {
	Name          string  `json:"name"`
	Scope         string  `json:"scope"`
	ExpiresInDays *int    `json:"expires_in_days"`
	UserID        *string `json:"user_id"`
}

// maxAPITokenNameLength is dezelfde grens als die van de servernaam (K rij 14).
// Een naam is een label in een overzicht, geen document.
const maxAPITokenNameLength = 64

// handleCreateAPIToken maakt een token en toont het geheim precies één keer.
func (s *Server) handleCreateAPIToken(w http.ResponseWriter, r *http.Request) {
	req, ok := s.resolveRequester(w, r)
	if !ok {
		return
	}

	// Een API-token maakt geen API-tokens, tenzij het er zelf een met bereik
	// `admin` is.
	//
	// Dit staat in geen enkel plan en is hier gevonden. K rij 22 toetst het
	// bereik tegen de rol van de eigenaar, en die controle alleen laat een gat
	// open: een `read`-token van een beheerder heeft rol `admin`, dus
	// ScopeWithinRole(admin, admin) zegt ja, en dan mint een leestoken een
	// beheertoken. Dat is rechtenverhoging via het endpoint dat er juist een
	// grens op moest zetten.
	//
	// De weigering gebruikt precies het mechanisme dat de adminklasse gebruikt,
	// inclusief de byte-gelijke 404: het aanmaken van een credential is een
	// beheerhandeling, ook wanneer iemand hem voor zichzelf doet. Een token met
	// bereik `admin` mag het wel, en dat is zijwaarts en geen verhoging: dat
	// token kan alles al wat het nieuwe token zou kunnen.
	if req.viaAPIToken && !req.scopeReachesAdmin() {
		writeError(w, s.log, CodeUserNotFound, "not found", nil)
		return
	}

	var body createAPITokenRequest
	if !s.decodeBody(w, r, &body, CodeSessionInvalid) {
		return
	}

	target, ok := s.apiTokenSubject(w, req, body.UserID)
	if !ok {
		return
	}

	name := strings.TrimSpace(body.Name)
	if name == "" || len(name) > maxAPITokenNameLength {
		writeError(w, s.log, CodeSessionInvalid, "name is required and at most 64 characters", nil)
		return
	}

	scope, known := auth.ParseAPITokenScope(body.Scope)
	if !known {
		writeError(w, s.log, CodeSessionInvalid, "scope is unknown", nil)
		return
	}

	// K rij 22, en de reden dat de rol van het dóél geldt en niet die van de
	// aanvrager: een beheerder die een token voor een lid maakt, maakt een
	// token met de rechten van dat lid. Het bereik mag dus nooit boven de rol
	// van de eigenaar, ook niet wanneer degene die op de knop drukt meer mag.
	targetRole, err := s.opts.Auth.UserRole(r.Context(), target)
	if err != nil {
		if errors.Is(err, auth.ErrUserNotFound) {
			writeError(w, s.log, CodeUserNotFound, "not found", nil)
			return
		}
		writeInternal(w, s.log, err)
		return
	}
	if !auth.ScopeWithinRole(scope, targetRole) {
		s.auditEvent(r, auditCreateAPIToken, target.String(), audit.OutcomeDenied,
			map[string]any{"scope": string(scope), "role": string(targetRole)})
		writeError(w, s.log, CodeScopeExceedsRole, "scope exceeds the role of the token owner",
			map[string]any{"scope": string(scope), "role": string(targetRole)})
		return
	}

	days := auth.DefaultAPITokenDays
	if body.ExpiresInDays != nil {
		days = *body.ExpiresInDays
		if days < 1 || days > auth.MaxAPITokenDays {
			writeError(w, s.log, CodeSessionInvalid, "expires_in_days is out of range", nil)
			return
		}
	}

	now := s.now().UTC()
	token, secret, err := s.opts.Auth.CreateAPIToken(r.Context(), target, name, scope,
		now.Add(time.Duration(days)*24*time.Hour), now)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	s.auditEvent(r, auditCreateAPIToken, token.ID.String(), audit.OutcomeOK,
		map[string]any{"scope": string(scope), "owner": target.String(), "expires_in_days": days})

	writeJSON(w, http.StatusCreated, APITokenCreatedWire{
		Token:  apiTokenWire(token),
		Secret: secret,
	})
}

// handleListAPITokens geeft de levende tokens, zonder geheimen (K rij 15).
func (s *Server) handleListAPITokens(w http.ResponseWriter, r *http.Request) {
	req, ok := s.resolveRequester(w, r)
	if !ok {
		return
	}

	var raw *string
	if q := strings.TrimSpace(r.URL.Query().Get("user_id")); q != "" {
		raw = &q
	}
	target, ok := s.apiTokenSubject(w, req, raw)
	if !ok {
		return
	}

	tokens, err := s.opts.Auth.ListAPITokens(r.Context(), target, s.now().UTC())
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	items := make([]APITokenWire, 0, len(tokens))
	for _, t := range tokens {
		items = append(items, apiTokenWire(t))
	}
	writeJSON(w, http.StatusOK, APITokenListWire{Items: items})
}

// apiTokenSubject bepaalt over wiens tokens deze aanvraag gaat.
//
// Dezelfde regel als GET /sessions: zonder user_id de aanvrager zelf, met
// user_id van een ander alleen voor owner en admin, en anders een 404 die niet
// verraadt of die gebruiker bestaat.
func (s *Server) apiTokenSubject(w http.ResponseWriter, req requester, raw *string) (id.ID, bool) {
	if raw == nil {
		return req.id, true
	}
	parsed, err := id.Parse(strings.TrimSpace(*raw))
	if err != nil {
		writeError(w, s.log, CodeUserNotFound, "not found", nil)
		return id.Nil, false
	}
	if parsed != req.id && !req.isAdmin() {
		writeError(w, s.log, CodeUserNotFound, "not found", nil)
		return id.Nil, false
	}
	return parsed, true
}

func apiTokenWire(t auth.APIToken) APITokenWire {
	return APITokenWire{
		ID:         t.ID.String(),
		UserID:     t.UserID.String(),
		Name:       t.Name,
		Scope:      string(t.Scope),
		CreatedAt:  formatTime(t.CreatedAt),
		LastSeenAt: formatTime(t.LastSeenAt),
		ExpiresAt:  formatTime(t.ExpiresAt),
	}
}
