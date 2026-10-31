package api

import (
	"context"
	"net/http"
	"unicode/utf8"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/auth"
)

// maxLoginNameRunes knipt wat een client als gebruikersnaam stuurt voordat het een
// limitersleutel of een auditregel wordt. Een aanvraag mag 8 KiB zijn, en die zouden
// anders 90 dagen in admin_audit blijven staan.
const maxLoginNameRunes = 64

// passwordSlots is hoeveel Argon2-berekeningen van inlogpogingen tegelijk lopen. Eén kost
// 64 MiB, en elke verzonnen gebruikersnaam krijgt er vijf.
const passwordSlots = 2

// Hoeveel geweigerde logins per proces een auditregel krijgen: twaalf achter elkaar en
// daarna één per vijf seconden. De aanvraag kost de aanvrager geen wachtwoord, dus zonder
// grens kiest hij zelf hoe snel de tabel groeit. Het patroon over een nacht blijft
// zichtbaar; wat erboven valt staat in het log. De verhouding is 60 s, zoals
// limiterIdleTTL van een emmer vraagt.
const (
	loginDenialBurst  = 12.0
	loginDenialRefill = 1.0 / 5.0
)

// loginGuard begrenst wat een inlogpoging kost die niets bewijst.
type loginGuard struct {
	denials *limiter
	slots   chan struct{}
	verify  func(password, encoded string, current auth.Argon2Params) (bool, bool, error)
}

func newLoginGuard() *loginGuard {
	denials := newLimiter()
	denials.burst, denials.refill = loginDenialBurst, loginDenialRefill
	return &loginGuard{denials: denials, slots: make(chan struct{}, passwordSlots), verify: auth.VerifyPassword}
}

// loginName knipt op tekens, zodat er geen half teken in de auditregel belandt.
func loginName(username string) string {
	if utf8.RuneCountInString(username) <= maxLoginNameRunes {
		return username
	}
	return string([]rune(username)[:maxLoginNameRunes])
}

// verifyPassword wacht op een plek en controleert dan het wachtwoord. Wie wegloopt
// voordat er plek is, kost niets meer.
func (s *Server) verifyPassword(ctx context.Context, password, encoded string) (bool, bool, error) {
	guard := s.loginGuard
	select {
	case guard.slots <- struct{}{}:
		defer func() { <-guard.slots }()
	case <-ctx.Done():
		return false, false, ctx.Err()
	}
	return guard.verify(password, encoded, s.opts.Argon2)
}

// auditLoginDenied schrijft de auditregel van een geweigerde login, tot de grens. Het log
// noemt de naam niet: dat is geen plek om te lezen wie een aanvaller probeerde.
func (s *Server) auditLoginDenied(r *http.Request, username, reason string) {
	if ok, _ := s.loginGuard.denials.allow("denied"); !ok {
		s.log.Warn("geweigerde login zonder auditregel: de grens is bereikt", "reason", reason)
		return
	}
	s.auditAnonymous(r, auditLogin, audit.OutcomeDenied,
		map[string]any{"username": loginName(username), "reason": reason})
}
