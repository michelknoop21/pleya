package api

import (
	"context"
	"math"
	"net"
	"net/http"
	"net/netip"
	"strconv"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/config"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

type refreshRequest struct {
	RefreshToken   string `json:"refresh_token"`
	CredentialMode string `json:"credential_mode"`
}

func (s *Server) handleRefresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if !s.decodeBody(w, r, &req, CodeTokenInvalid) {
		return
	}

	mode, ok := s.credentialMode(w, r, req.CredentialMode, CodeTokenInvalid, "")
	if !ok {
		return
	}

	presented := strings.TrimSpace(req.RefreshToken)
	if mode == credentialModeCookie {
		// Twee bronnen is geen bron. Wie een token in het lichaam zet én om de
		// cookie vraagt heeft twee credentials en geen manier om te zeggen welk
		// van de twee hij bedoelt, en stilzwijgend kiezen is precies hoe een
		// client per ongeluk het verkeerde blijft roteren.
		if presented != "" {
			writeError(w, s.log, CodeTokenInvalid, "refresh token in both body and cookie", nil)
			return
		}
		cookie, err := r.Cookie(auth.RefreshCookieName)
		if err != nil || strings.TrimSpace(cookie.Value) == "" {
			writeError(w, s.log, CodeTokenInvalid, "refresh cookie missing", nil)
			return
		}
		presented = strings.TrimSpace(cookie.Value)
	} else if presented == "" {
		writeError(w, s.log, CodeTokenInvalid, "refresh token missing", nil)
		return
	}

	presentedHash := auth.HashOpaque(presented)
	if !s.allowRefresh(w, r, presentedHash) {
		return
	}

	newToken, newHash, err := auth.NewRefreshToken()
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	now := s.now().UTC()
	outcome, sid, subjectID, err := s.opts.Auth.RotateRefreshToken(r.Context(),
		presentedHash, newHash, now.Add(s.settings().RefreshTokenTTL()), now,
		s.opts.RefreshGraceWindow)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	// Een afgewezen refresh in cookiemodus laat geen dode cookie achter. Zonder
	// deze regel blijft de browser bij elke volgende poging een credential
	// meesturen dat nooit meer werkt, en dan lijkt "opnieuw inloggen" niet te
	// helpen.
	if mode == credentialModeCookie && outcome != auth.RefreshOK && outcome != auth.RefreshReplayed {
		s.clearRefreshCookie(w)
	}

	switch outcome {
	case auth.RefreshReplayed:
		// Meetbaar apart van een gewone rotatie: elke regel hier is een
		// antwoord dat de lijn eerder kwijtraakte, en dat hoort zeldzaam te
		// zijn.
		s.log.Info("rotatie-antwoord verloren; herhaling binnen het respijt bediend")
	case auth.RefreshReused:
		// De hele keten van DEZE sessie is nu ongeldig (DEC-123, sessie-scoped
		// sinds PS-9). Een van de twee partijen die dit token droeg is de
		// aanvaller, en welke dat is valt niet vast te stellen.
		if sid != id.Nil {
			s.opts.Revocations.Revoke(sid, now)
		}
		s.log.Warn("refreshtoken hergebruikt; de tokens van deze sessie zijn ingetrokken")
		writeError(w, s.log, CodeRefreshTokenReused, "refresh token reused", nil)
		return
	case auth.RefreshSessionRevoked:
		writeError(w, s.log, CodeTokenInvalid, "session revoked", nil)
		return
	case auth.RefreshExpired, auth.RefreshUnknown:
		writeError(w, s.log, CodeTokenInvalid, "refresh token invalid", nil)
		return
	}

	// last_seen_at bijwerken hoort hier en niet bij elke aanvraag: een refresh
	// is per toestel de natuurlijke hartslag, en een schrijfronde per GET zou
	// een leesserver in een schrijfserver veranderen voor een veld dat alleen in
	// GET /sessions staat.
	if err := s.opts.Auth.TouchSession(r.Context(), sid, now); err != nil {
		s.log.Warn("last_seen_at bijwerken mislukt", "error", err.Error())
	}

	access, claims, err := s.opts.Signer.Mint(subjectID.String(), sid.String(), auth.TokenAccess, s.settings().AccessTokenTTL(), "")
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	s.writeTokenPair(w, r, mode, access, newToken, (claims.ExpiresAt-claims.IssuedAt)*1000)
}

// allowRefresh past de limiter toe, vóór de rotatie (S15.1). Een 429 raakt dus
// niets: het aangeboden token blijft geldig, de cookie blijft staan en de keten
// merkt er niets van. Een client die wacht en het opnieuw probeert, gaat verder
// waar hij was; dat is het verschil met een afgewezen refresh.
//
// Geen auditregel, anders dan bij login: een client in een lus zou dan per
// geweigerde aanvraag alsnog een schrijfronde kosten, en dat is wat de limiter
// tegenhoudt.
func (s *Server) allowRefresh(w http.ResponseWriter, r *http.Request, presentedHash []byte) bool {
	key, err := s.refreshLimiterKey(r.Context(), r, presentedHash)
	if err != nil {
		writeInternal(w, s.log, err)
		return false
	}
	ok, wait := s.refreshLimiter.allow(key)
	if ok {
		return true
	}
	s.log.Warn("refresh begrensd", "limiter", strings.SplitN(key, ":", 2)[0])
	w.Header().Set("Retry-After", retryAfterSeconds(wait))
	writeError(w, s.log, CodeRateLimited, "too many attempts", map[string]any{
		"retry_after_ms": wait.Milliseconds(),
	})
	return false
}

// refreshLimiterKey kiest de emmer van een refresh.
//
// Een token dat bij een sessie hoort telt op die sessie, want één sessie is één
// toestel of één browserprofiel: twee tabbladen delen hun emmer, en een lus in
// één client raakt niemand anders. Een huishouden achter één NAT of tunnel heeft
// dus geen last van elkaar, en dat blijft zo als PLEYA_SERVER_TRUSTED_PROXIES
// niet klopt, want het adres speelt hier geen rol.
//
// De sleutel is niet het token zelf: dat roteert bij elk gebruik, dus juist een
// client in een lus zou dan steeds een volle emmer krijgen.
//
// Een token zonder sessie is verzonnen of opgeruimd, en dat kan geen rechtmatige
// client helpen. Die aanvragen tellen op het adres, zodat ze de database niet
// onbeperkt raken en toch geen enkele sessie kunnen blokkeren.
func (s *Server) refreshLimiterKey(ctx context.Context, r *http.Request, presentedHash []byte) (string, error) {
	sessionID, known, err := s.opts.Auth.RefreshTokenSession(ctx, presentedHash)
	if err != nil {
		return "", err
	}
	if known {
		return "session:" + sessionID.String(), nil
	}
	return "address:" + s.clientAddress(r), nil
}

// clientAddress geeft het adres van de client.
//
// X-Forwarded-For telt alleen als de tegenpartij in
// PLEYA_SERVER_TRUSTED_PROXIES staat, anders kiest elke client zijn eigen adres
// en daarmee zijn eigen emmer. Dan wordt de lijst van rechts naar links gelezen:
// rechts staat wat onze eigen proxy's erin zetten, links wat de client zelf
// meestuurde. De eerste hop die geen vertrouwde proxy is, is de client.
func (s *Server) clientAddress(r *http.Request) string {
	address := r.RemoteAddr
	if host, _, err := net.SplitHostPort(address); err == nil {
		address = host
	}
	if !config.RemoteAddrIsTrustedProxy(s.opts.TrustedProxies, r.RemoteAddr) {
		return address
	}
	hops := strings.Split(strings.Join(r.Header.Values("X-Forwarded-For"), ","), ",")
	for i := len(hops) - 1; i >= 0; i-- {
		hop, err := netip.ParseAddr(strings.TrimSpace(hops[i]))
		if err != nil {
			break
		}
		address = hop.Unmap().String()
		if !config.RemoteAddrIsTrustedProxy(s.opts.TrustedProxies, address) {
			break
		}
	}
	return address
}

// retryAfterSeconds rondt naar boven af op hele seconden, minstens één: een
// client die afgerond korter wacht komt nog voor zijn token terug.
func retryAfterSeconds(wait time.Duration) string {
	return strconv.FormatInt(max(1, int64(math.Ceil(wait.Seconds()))), 10)
}
