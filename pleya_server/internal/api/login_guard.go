package api

import (
	"bytes"
	"context"
	"errors"
	"net/http"
	"strconv"
	"time"
	"unicode/utf8"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/auth"
)

// maxLoginTextRunes knipt wat een client als naam of Origin stuurt voordat het een
// limitersleutel, een logregel of een auditregel wordt. Een aanvraag mag 8 KiB zijn en
// een header 1 MiB, en die zouden anders 90 dagen in admin_audit blijven staan.
const maxLoginTextRunes = 64

// passwordSlots is hoeveel Argon2-berekeningen van inlogpogingen tegelijk lopen. Eén kost
// 64 MiB, en elke verzonnen gebruikersnaam krijgt er vijf.
const passwordSlots = 2

// loginSlotWait is hoe lang een poging op een plek wacht. Zonder grens staat elke echte
// login achter elke verzonnen naam in de rij, en login is de uitweg voor wie zijn sessie
// kwijt is. Een 429 met Retry-After laat hem het zelf nog eens proberen.
const loginSlotWait = 3 * time.Second

// Hoeveel pogingen per clientadres bij de Argon2-stap komen: 60 achter elkaar en daarna
// één per seconde. Het adres is altijd clientAddress: een doorgestuurd adres telt alleen
// achter een vertrouwde proxy, want anders kiest een client zelf zijn emmer. Staat
// PLEYA_SERVER_TRUSTED_PROXIES leeg op een server achter een tunnel, dan delen alle
// clients één emmer en kan één client de logins van anderen op 429 zetten. Dat is een
// verkeerde opstelling, zie docs/pleya-server-operator-remote.md.
const (
	loginAddressBurst  = 60.0
	loginAddressRefill = 1.0
)

// Hoeveel weigeringen per proces een auditregel krijgen: twaalf achter elkaar en daarna
// één per vijf seconden. Het gaat om verzonnen namen, volle emmers en afgewezen origins:
// dat kost de aanvrager geen wachtwoord, dus zonder grens kiest hij zelf hoe snel de tabel
// groeit. Een fout wachtwoord op een bestaande naam telt niet mee, anders maakt hij de
// beheerder blind met een naam die niet bestaat; dat is al per naam begrensd. Wat erboven
// valt staat in het log. De verhouding is 60 s, zoals limiterIdleTTL van een emmer vraagt.
const (
	loginDenialBurst  = 12.0
	loginDenialRefill = 1.0 / 5.0
)

// errLoginBusy: er kwam geen plek vrij, of de client liep weg.
var errLoginBusy = errors.New("geen plek voor een wachtwoordcontrole")

// loginGuard begrenst wat een inlogpoging kost die niets bewijst.
type loginGuard struct {
	denials   *limiter
	addresses *limiter
	slots     chan struct{}
	slotWait  time.Duration
	verify    func(password, encoded string, current auth.Argon2Params) (bool, bool, error)
}

func newLoginGuard() *loginGuard {
	denials, addresses := newLimiter(), newLimiter()
	denials.burst, denials.refill = loginDenialBurst, loginDenialRefill
	addresses.burst, addresses.refill = loginAddressBurst, loginAddressRefill
	return &loginGuard{
		denials: denials, addresses: addresses, slots: make(chan struct{}, passwordSlots),
		slotWait: loginSlotWait, verify: auth.VerifyPassword,
	}
}

// cutLoginText knipt op tekens, zodat er geen half teken in de auditregel belandt.
func cutLoginText(text string) string {
	if utf8.RuneCountInString(text) <= maxLoginTextRunes {
		return text
	}
	return string([]rune(text)[:maxLoginTextRunes])
}

// verifyPassword wacht op een plek en controleert dan het wachtwoord. Wie wegloopt of te
// lang wacht, kost niets meer.
func (s *Server) verifyPassword(ctx context.Context, password, encoded string) (bool, bool, error) {
	guard := s.loginGuard
	timer := time.NewTimer(guard.slotWait)
	defer timer.Stop()
	select {
	case guard.slots <- struct{}{}:
		defer func() { <-guard.slots }()
	case <-ctx.Done():
		return false, false, errLoginBusy
	case <-timer.C:
		return false, false, errLoginBusy
	}
	return guard.verify(password, encoded, s.opts.Argon2)
}

// allowLoginAttempt telt een poging die naar de Argon2-stap wil op het clientadres.
func (s *Server) allowLoginAttempt(w http.ResponseWriter, r *http.Request, username string) bool {
	ok, wait := s.loginGuard.addresses.allow(s.clientAddress(r))
	if ok {
		return true
	}
	s.auditLoginDenied(r, map[string]any{"username": cutLoginText(username), "reason": "rate_limited"})
	s.writeRefreshLimited(w, "login", wait)
	return false
}

// auditLoginDenied schrijft de auditregel van een weigering, tot de grens. Het log noemt
// de naam niet: dat is geen plek om te lezen wie een aanvaller probeerde.
func (s *Server) auditLoginDenied(r *http.Request, detail map[string]any) {
	if ok, _ := s.loginGuard.denials.allow("denied"); !ok {
		s.log.Warn("geweigerde login zonder auditregel: de grens is bereikt", "reason", detail["reason"])
		return
	}
	s.auditAnonymous(r, auditLogin, audit.OutcomeDenied, detail)
}

// writeInvalidCredentials geeft het hele antwoord vóór er nog iets gebeurt. Een bestaande
// naam schrijft daarna altijd een auditregel en een verzonnen naam niet altijd, en dat
// verschil mag de client niet kunnen klokken: hij heeft dit antwoord dan al compleet, met
// Content-Length, dus ook het einde ervan wacht niet op de database.
func (s *Server) writeInvalidCredentials(w http.ResponseWriter) {
	answer := bufferedResponse{header: w.Header()}
	writeError(&answer, s.log, CodeInvalidCredentials, "invalid credentials", nil)
	w.Header().Set("Content-Length", strconv.Itoa(answer.body.Len()))
	w.WriteHeader(answer.status)
	_, _ = w.Write(answer.body.Bytes())
	_ = http.NewResponseController(w).Flush()
}

// bufferedResponse vangt een antwoord op om zijn lengte te kennen.
type bufferedResponse struct {
	header http.Header
	status int
	body   bytes.Buffer
}

func (b *bufferedResponse) Header() http.Header         { return b.header }
func (b *bufferedResponse) WriteHeader(status int)      { b.status = status }
func (b *bufferedResponse) Write(p []byte) (int, error) { return b.body.Write(p) }

// auditWrongPassword is de regel van een mislukte controle. Op een bestaande naam gaat
// hij buiten de grens om: die naam heeft al zijn eigen emmer, en dit is de regel waar een
// beheerder naar zoekt.
func (s *Server) auditWrongPassword(r *http.Request, username string, known bool) {
	detail := map[string]any{"username": cutLoginText(username), "reason": "invalid_credentials"}
	if known {
		s.auditAnonymous(r, auditLogin, audit.OutcomeDenied, detail)
		return
	}
	s.auditLoginDenied(r, detail)
}
