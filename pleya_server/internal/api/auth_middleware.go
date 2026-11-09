package api

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// claimsContextKey draagt de geverifieerde Claims van de huidige aanvraag.
type claimsContextKey struct{}

// withClaims zet de claims van een geverifieerd accesstoken in de context.
func withClaims(ctx context.Context, claims auth.Claims) context.Context {
	return context.WithValue(ctx, claimsContextKey{}, claims)
}

// claimsFromContext leest ze terug. Elke handler achter authenticated() kan
// hiervan uitgaan: de middleware zet ze altijd voordat next wordt aangeroepen.
func claimsFromContext(ctx context.Context) (auth.Claims, bool) {
	claims, ok := ctx.Value(claimsContextKey{}).(auth.Claims)
	return claims, ok
}

// sessionContextKey draagt de auth-sessie (sid) van de huidige aanvraag.
//
// Los van claimsContextKey, want het streampad kent drie credentials en maar
// twee daarvan dragen Claims: de browserstreamsessie heeft geen token en leest
// zijn sid uit stream_sessions.session_id.
type sessionContextKey struct{}

func withSessionID(ctx context.Context, sessionID id.ID) context.Context {
	return context.WithValue(ctx, sessionContextKey{}, sessionID)
}

// streamSubjectKey draagt de gebruiker achter een streamtoken of -sessie. Beide
// lopen buiten de bearer-Claims om, dus zonder dit is alleen hun versie bekend.
type streamSubjectKey struct{}

func withStreamSubject(ctx context.Context, subject id.ID) context.Context {
	return context.WithValue(ctx, streamSubjectKey{}, subject)
}

func streamSubjectFromContext(ctx context.Context) (id.ID, bool) {
	subject, ok := ctx.Value(streamSubjectKey{}).(id.ID)
	return subject, ok
}

// streamRequester is de gebruiker achter een aanvraag op het streampad, met welk
// van de drie credentials hij ook binnenkwam.
func streamRequester(r *http.Request) (id.ID, bool) {
	if subject, ok := streamSubjectFromContext(r.Context()); ok {
		return subject, true
	}
	claims, ok := claimsFromContext(r.Context())
	if !ok {
		return id.Nil, false
	}
	subject, err := id.Parse(claims.Subject)
	return subject, err == nil
}

// withClaimsAndSession zet ook de sid in de context, zodat copyRange op een
// `authenticated`-route (zoals een download) stopt bij een ingetrokken sessie.
func withClaimsAndSession(ctx context.Context, claims auth.Claims) context.Context {
	ctx = withClaims(ctx, claims)
	if sessionID, err := id.Parse(claims.Sid); err == nil {
		ctx = withSessionID(ctx, sessionID)
	}
	return ctx
}

// sessionIDFromContext geeft de sid van deze aanvraag, of id.Nil. Gebruikt door
// copyRange om per blok het intrekkingsregister te raadplegen (DEC-120).
func sessionIDFromContext(ctx context.Context) id.ID {
	sessionID, ok := ctx.Value(sessionContextKey{}).(id.ID)
	if !ok {
		return id.Nil
	}
	return sessionID
}

// scopeContextKey draagt het bereik van het API-token van deze aanvraag.
type scopeContextKey struct{}

// withAPIScope zet het bereik in de context. Een aanvraag met een gewoon
// accesstoken krijgt hem niet, en dat is het onderscheid waar requireAdmin op
// leest: "geen bereik" is een mens achter een toestel en niet een agent.
func withAPIScope(ctx context.Context, scope auth.APITokenScope) context.Context {
	return context.WithValue(ctx, scopeContextKey{}, scope)
}

// apiScopeFromContext geeft het bereik, en of deze aanvraag er een had.
func apiScopeFromContext(ctx context.Context) (auth.APITokenScope, bool) {
	scope, ok := ctx.Value(scopeContextKey{}).(auth.APITokenScope)
	return scope, ok
}

// authenticated eist een geldig accesstoken of API-token in de
// Authorization-header.
//
// De twee zijn aan hun vorm te onderscheiden en niet aan een mislukte poging:
// een API-token begint met auth.APITokenPrefix, een accesstoken met `ply1.`.
// Dat scheelt niet alleen een databaseronde per onzin-token, het houdt ook de
// foutmelding eerlijk. Zou de middleware eerst de handtekening proberen en bij
// elke mislukking de database bevragen, dan zou een verlopen accesstoken via
// het tokenpad alsnog als "bestaat niet" terugkomen.
func (s *Server) authenticated(next http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, ok := bearerToken(r)
		if !ok {
			writeError(w, s.log, CodeTokenInvalid, "no bearer token", nil)
			return
		}
		if auth.LooksLikeAPIToken(token) {
			s.authenticatedByAPIToken(w, r, token, next)
			return
		}
		claims, err := s.opts.Signer.Verify(token, auth.TokenAccess)
		if err != nil {
			s.writeTokenError(w, err)
			return
		}
		if !s.sessionLives(w, claims) {
			return
		}
		next(w, r.WithContext(withClaimsAndSession(r.Context(), claims)))
	})
}

// authenticatedByAPIToken is het tweede pad van authenticated (S1.5, RB-20).
//
// Het bouwt dezelfde Claims als een accesstoken zou dragen, zodat elke handler
// erachter niet hoeft te weten waar zijn aanvrager vandaan komt: subjectID en
// currentSessionID lezen hetzelfde veld, en de rol wordt zoals altijd per
// aanvraag uit de database gelezen. Wat er bij komt is het bereik in de
// context.
//
// Hier staat wél een databaseronde per aanvraag, en dat is een bewuste keuze.
// Het alternatief is een cache, en die zou de intrekkingsgarantie van twee
// seconden precies zo lang breken als de cache leeft. De frequentie past bij de
// drager: een agent doet aanvragen op menselijk tempo, niet per streamblok.
func (s *Server) authenticatedByAPIToken(w http.ResponseWriter, r *http.Request, token string, next http.HandlerFunc) {
	identity, err := s.opts.Auth.VerifyAPIToken(r.Context(), token, s.now().UTC())
	switch {
	case errors.Is(err, auth.ErrAPITokenExpired):
		// Dezelfde code als een verlopen accesstoken. De drager kan er niets
		// anders mee dan een nieuw token vragen, en het protocol heeft er al
		// een naam voor.
		writeError(w, s.log, CodeTokenExpired, "token expired", nil)
		return
	case errors.Is(err, auth.ErrAPITokenInvalid):
		writeError(w, s.log, CodeTokenInvalid, "token invalid", nil)
		return
	case err != nil:
		writeInternal(w, s.log, err)
		return
	}

	claims := auth.Claims{
		Subject:   identity.UserID.String(),
		Sid:       identity.SessionID.String(),
		Type:      auth.TokenAccess,
		ExpiresAt: identity.ExpiresAt.Unix(),
	}
	// Ook het register nog, ook al keek de query net naar revoked_at. De query
	// dekt een herstart, het register dekt het moment tussen twee
	// databaserondes; ze overlappen met opzet.
	if !s.sessionLives(w, claims) {
		return
	}

	ctx := withAPIScope(withClaimsAndSession(r.Context(), claims), identity.Scope)
	next(w, r.WithContext(ctx))
}

// ownDataWrite is authenticated plus de grens uit 17c.2: een API-token onder
// bereik admin wist of herschrijft geen eigen gegevens. Een gelekt leestoken
// hoort geen geschiedenis te kunnen wissen of een lijst leeg te kunnen maken.
//
// De weigering hangt niet af van het doel, dus een lijst buiten zicht verraadt
// hier niets. Een gewone sessie heeft geen bereik en loopt er ongemoeid door.
func (s *Server) ownDataWrite(next http.HandlerFunc) http.Handler {
	return s.authenticated(func(w http.ResponseWriter, r *http.Request) {
		if scope, ok := apiScopeFromContext(r.Context()); ok && scope != auth.APIScopeAdmin {
			writeError(w, s.log, CodeScopeInsufficient, "this token cannot change personal data",
				map[string]any{"scope": string(scope)})
			return
		}
		next(w, r)
	})
}

// sessionLives is de O(1)-controle uit DEC-120: draagt dit credential een sid
// die is ingetrokken, dan is het credential dood, ongeacht zijn eigen
// vervalmoment.
//
// Zonder databaseronde, en dat is het hele punt: een controle die per aanvraag
// een query doet zou op het streampad per blok een query worden. Symmetrisch
// voor het accesstoken, het streamtoken en de browserstreamsessie; alle drie
// dragen sid.
func (s *Server) sessionLives(w http.ResponseWriter, claims auth.Claims) bool {
	sessionID, err := id.Parse(claims.Sid)
	if err != nil {
		// Een token zonder leesbare sid is van vóór PS-9 of vervalst. Beide
		// horen te falen, en met dezelfde code als een ingetrokken sessie.
		writeError(w, s.log, CodeTokenInvalid, "token carries no session", nil)
		return false
	}
	if s.opts.Revocations.IsRevoked(sessionID) {
		writeError(w, s.log, CodeTokenInvalid, "session revoked", nil)
		return false
	}
	return true
}

// streamAuthorized accepteert daarnaast een streamtoken in de querystring.
//
// Dat is de enige uitzondering op "nooit een token in een URL", en hij staat er
// omdat een externe speler geen header kan zetten. Het token is smal: het opent
// één mediaresource en heeft geen enkel recht op de rest van de API.
func (s *Server) streamAuthorized(next func(w http.ResponseWriter, r *http.Request, versionScope *id.ID)) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if token, ok := bearerToken(r); ok {
			claims, err := s.opts.Signer.Verify(token, auth.TokenAccess)
			if err != nil {
				s.writeTokenError(w, err)
				return
			}
			if !s.sessionLives(w, claims) {
				return
			}
			// De claims moeten de context in: bij een gewoon accesstoken (geen
			// versionScope) leest handleStream/handleSubtitle ze voor de
			// bibliotheekcontrole van AC2 (PS-9). De sid gaat er los naast voor
			// copyRange, die per blok het intrekkingsregister raadpleegt.
			ctx := withClaims(r.Context(), claims)
			if sessionID, err := id.Parse(claims.Sid); err == nil {
				ctx = withSessionID(ctx, sessionID)
			}
			next(w, r.WithContext(ctx), nil)
			return
		}

		if sessionID := strings.TrimSpace(r.URL.Query().Get("ss")); sessionID != "" {
			scope, authSid, subject, ok := s.streamSessionScope(w, r, sessionID)
			if !ok {
				return
			}
			next(w, r.WithContext(withStreamSubject(withSessionID(r.Context(), authSid), subject)), scope)
			return
		}

		raw := strings.TrimSpace(r.URL.Query().Get("stream_token"))
		if raw == "" {
			writeError(w, s.log, CodeTokenInvalid, "no bearer token and no stream token", nil)
			return
		}
		claims, err := s.opts.Signer.Verify(raw, auth.TokenStream)
		if err != nil {
			s.writeTokenError(w, err)
			return
		}
		if !s.sessionLives(w, claims) {
			return
		}
		scope, err := id.Parse(claims.Resource)
		if err != nil {
			writeError(w, s.log, CodeTokenInvalid, "stream token carries no resource", nil)
			return
		}
		subject, err := id.Parse(claims.Subject)
		if err != nil {
			writeInternal(w, s.log, fmt.Errorf("subject in streamtoken is geen geldig id: %w", err))
			return
		}
		// Aanvraagpad, niet alleen mint-moment (DEC-126, hoofdstuk 16.4 regel 8
		// en 9): een streamtoken leeft tot vijf minuten zelfstandig na het
		// minten, dus een ingetrokken bibliotheekrecht moet hier meteen gelden
		// en niet pas wanneer het token vanzelf verloopt.
		if !s.authorizeVersionFor(w, r, subject, scope) {
			return
		}
		ctx := withStreamSubject(r.Context(), subject)
		if sessionID, err := id.Parse(claims.Sid); err == nil {
			ctx = withSessionID(ctx, sessionID)
		}
		next(w, r.WithContext(ctx), &scope)
	})
}

// streamSessionScope valideert een browser-streamsessie en geeft de versie waar
// hij aan gebonden is.
//
// De sessie-id in de URL is niet geheim en op zichzelf niets waard. Het geheim
// zit in de cookie waarvan de naam die id draagt, en pas de twee samen openen
// iets. Een aanvraag zonder die cookie is daarmee net zo kansloos als een
// aanvraag zonder token, en dat is precies de bedoeling: de id mag in
// browsergeschiedenis en in logs staan.
func (s *Server) streamSessionScope(w http.ResponseWriter, r *http.Request, rawSessionID string) (*id.ID, id.ID, id.ID, bool) {
	sessionID, err := id.Parse(rawSessionID)
	if err != nil {
		writeError(w, s.log, CodeTokenInvalid, "stream session is invalid", nil)
		return nil, id.Nil, id.Nil, false
	}

	cookie, err := r.Cookie(auth.StreamCookiePrefix + sessionID.String())
	if err != nil || cookie.Value == "" {
		writeError(w, s.log, CodeTokenInvalid, "stream session is invalid", nil)
		return nil, id.Nil, id.Nil, false
	}

	versionID, err := id.Parse(r.PathValue("version_id"))
	if err != nil && s.opts.Transcode != nil {
		// HLS routes carry a conversion id, not a version id (same ss scope).
		if conversionID, parseErr := id.Parse(r.PathValue("session_id")); parseErr == nil {
			if conversion, found := s.opts.Transcode.Get(conversionID); found {
				versionID, err = conversion.VersionID, nil
			}
		}
	}
	if err != nil {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return nil, id.Nil, id.Nil, false
	}

	now := s.now().UTC()
	subject, authSid, err := s.opts.Auth.VerifyStreamSession(r.Context(), sessionID, cookie.Value, versionID, now)
	if err != nil {
		if errors.Is(err, auth.ErrStreamSessionInvalid) {
			writeError(w, s.log, CodeTokenInvalid, "stream session is invalid", nil)
			return nil, id.Nil, id.Nil, false
		}
		writeInternal(w, s.log, err)
		return nil, id.Nil, id.Nil, false
	}

	// De databasecontrole hierboven leest sessions.revoked_at, maar het register
	// is de snellere en de enige die tijdens een lopende stream nog meekijkt.
	if s.opts.Revocations.IsRevoked(authSid) {
		writeError(w, s.log, CodeTokenInvalid, "session revoked", nil)
		return nil, id.Nil, id.Nil, false
	}

	// Aanvraagpad, niet alleen mint-moment (DEC-126, hoofdstuk 16.4 regel 9):
	// het geheim en de versie kloppen, maar dat bewijst niet dat subject nog
	// recht heeft op de bibliotheek erachter. Een streamsessie leeft tot 30
	// minuten zelfstandig na het minten, dus een ingetrokken recht moet hier
	// meteen gelden.
	if !s.authorizeVersionFor(w, r, subject, versionID) {
		return nil, id.Nil, id.Nil, false
	}

	// Verlengen raakt uitsluitend deze sessie. Dat is de reden dat het model
	// werkt: twee gelijktijdige streams roteren onafhankelijk.
	if _, err := s.opts.Auth.TouchStreamSession(r.Context(), sessionID, s.settings().StreamSessionTTL(), now); err != nil {
		s.log.Warn("streamsessie verlengen mislukt", "error", err.Error())
	}
	return &versionID, authSid, subject, true
}

func (s *Server) writeTokenError(w http.ResponseWriter, err error) {
	switch {
	case err == auth.ErrTokenExpired:
		writeError(w, s.log, CodeTokenExpired, "token expired", nil)
	default:
		writeError(w, s.log, CodeTokenInvalid, "token invalid", nil)
	}
}

func bearerToken(r *http.Request) (string, bool) {
	header := r.Header.Get("Authorization")
	if header == "" {
		return "", false
	}
	scheme, token, ok := strings.Cut(header, " ")
	if !ok || !strings.EqualFold(scheme, "bearer") {
		return "", false
	}
	token = strings.TrimSpace(token)
	return token, token != ""
}
