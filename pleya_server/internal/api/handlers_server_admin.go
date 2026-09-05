package api

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/config"
	"github.com/edde746/plezy/pleya_server/internal/logging"
)

// De serverdiagnostiek van S1.3: GET /server uitgebreid, /server/environment,
// /server/log, /server/connectivity-check en /server/rotate-signing-key
// (J.2 rijen 3 tot en met 7).
//
// Drie grenzen bepalen de vorm van dit bestand, en ze staan alle drie in het
// securityplan.
//
// K rij 11: er wordt hier geen bestand geopend. Het log komt uit een ringbuffer
// in het geheugen en de omgeving uit os.Environ; er is dus geen pad uit een
// aanvraag dat ergens terechtkomt, en geen manier om deze endpoints als
// bestandsbrowser te gebruiken.
//
// K rij 15: geen antwoord hier draagt de DSN, de ondertekensleutel of een
// token. De databaseversie komt als versienummer binnen en niet als
// verbindingsstring, de omgeving gaat langs logging.MaskEnvironment, en
// rotate-signing-key antwoordt 204 zonder de nieuwe sleutel te tonen.
//
// K rij 13: connectivity-check roept precies één adres aan, namelijk het
// public_url van deze server, met een vaste time-out en zonder redirects te
// volgen. Er is geen aanvraagveld dat het doel kan verzetten.

// probeTimeout is de vaste grens per aanroep in de connectivity-check. Vast en
// niet instelbaar: een beheerder die hem kan verhogen kan van deze knop een
// langzame poortscanner maken, en een controle die langer duurt dan dit zegt
// hetzelfde als een controle die faalt.
const probeTimeout = 5 * time.Second

// probeRangeBytes is het bereik dat de rangecontrole opvraagt. Klein genoeg om
// niets te kosten, groot genoeg dat een antwoord met meer bytes opvalt.
const probeRangeBytes = 16

// maxProbeBody begrenst wat de controle van een antwoord leest.
const maxProbeBody = 64 << 10

// defaultLogLimit en maxLogLimit begrenzen GET /server/log. De bovengrens is
// dezelfde als de capaciteit van de ringbuffer (logging.RingCapacity): een
// hogere zou een belofte zijn die de buffer niet kan waarmaken.
const (
	defaultLogLimit = 100
	maxLogLimit     = logging.RingCapacity
)

// ServerDatabaseWire is Server.database.
type ServerDatabaseWire struct {
	Version string `json:"version"`
	Schema  int    `json:"schema"`
}

// ServerFFprobeWire is Server.ffprobe: gemeten bij het opstarten, niet per
// aanvraag. Een subprocess starten om een beheerscherm te vullen is een prijs
// per verzoek voor een antwoord dat in een container nooit verandert.
type ServerFFprobeWire struct {
	Found   bool   `json:"found"`
	Version string `json:"version,omitempty"`
}

// ServerHealthWire is Server.health.
type ServerHealthWire struct {
	Ready       bool `json:"ready"`
	JobsRunning int  `json:"jobs_running"`
	JobsFailed  int  `json:"jobs_failed"`
}

// EnvironmentEntryWire is één regel van GET /server/environment.
type EnvironmentEntryWire struct {
	Key   string `json:"key"`
	Value string `json:"value"`
	// Redacted zegt dat de waarde hierboven niet de echte is. Zonder dit veld
	// zou een beheerder een gemaskeerde DSN voor de werkelijke instelling
	// aanzien en zich afvragen waarom de server er niet mee verbindt.
	Redacted bool `json:"redacted"`
}

// ServerEnvironmentWire is het antwoord van GET /server/environment.
//
// Een object met een lijst erin en niet een kale array: elk ander lijstantwoord
// in dit protocol heeft een omhulsel, en zonder omhulsel is er later geen plek
// voor een veld erbij zonder het type van het antwoord te wijzigen.
type ServerEnvironmentWire struct {
	Entries []EnvironmentEntryWire `json:"entries"`
}

// LogEntryWire is één regel van GET /server/log.
type LogEntryWire struct {
	At        string `json:"at"`
	Level     string `json:"level"`
	Component string `json:"component,omitempty"`
	Message   string `json:"message"`
}

// ServerLogWire is het antwoord van GET /server/log, nieuwste regel eerst.
type ServerLogWire struct {
	Entries []LogEntryWire `json:"entries"`
}

// ConnectivityCheckWire is het antwoord van POST /server/connectivity-check.
type ConnectivityCheckWire struct {
	PublicURLReachable bool `json:"public_url_reachable"`
	RangeIntact        bool `json:"range_intact"`
	BehindProxy        bool `json:"behind_proxy"`
}

// rotateSigningKeyRequest is de gesloten body van POST /server/rotate-signing-key.
type rotateSigningKeyRequest struct {
	Confirm string `json:"confirm"`
}

// rotateConfirmWord is wat er in confirm moet staan. Een vast woord en niet een
// boolean: een `true` is met één ontbrekende regel in een client te sturen, dit
// is een handeling die iemand met opzet uitschrijft (K rij 16).
const rotateConfirmWord = "rotate"

// handleServer is GET /server.
//
// Klasse authenticated, met een uitbreiding voor klasse admin (J.2 rij 3). De
// basisvelden blijven wat ze waren, dus een lid ziet precies wat het altijd
// zag; de acht velden erbij bestaan voor hem niet.
func (s *Server) handleServer(w http.ResponseWriter, r *http.Request) {
	detail := ServerDetail{
		ID:        s.opts.ServerID.String(),
		Name:      s.settings().ServerName(),
		Version:   s.opts.Version,
		StartedAt: formatTime(s.opts.StartedAt),
	}
	if s.requesterIsAdmin(r) {
		s.fillServerAdminDetail(r, &detail)
	}
	writeJSON(w, http.StatusOK, detail)
}

// requesterIsAdmin beantwoordt de klassevraag voor een endpoint dat ook zonder
// die klasse antwoord geeft.
//
// Verdraagzaam met opzet, anders dan requireAdmin: kan de rol niet gelezen
// worden, dan is het antwoord "geen beheerder" en geen 500. GET /server is het
// endpoint waarmee een client zijn kop tekent, en dat mag niet omvallen omdat
// de rollenquery hapert. Wat er dan gebeurt is dat de beheervelden wegblijven,
// en dat is de veilige kant van de vergissing.
func (s *Server) requesterIsAdmin(r *http.Request) bool {
	userID, err := s.subjectID(r)
	if err != nil {
		return false
	}
	role, err := s.opts.Auth.UserRole(r.Context(), userID)
	if err != nil {
		s.log.Warn("rol van de aanvrager niet te lezen; GET /server toont de beheervelden niet",
			slog.String("error", err.Error()))
		return false
	}
	return requester{id: userID, role: role}.isAdmin()
}

func (s *Server) fillServerAdminDetail(r *http.Request, detail *ServerDetail) {
	publicURL := s.settings().PublicURL()
	listen := s.opts.Listen
	behindProxy := s.behindProxy(r)
	proxies := config.TrustedProxyStrings(s.opts.TrustedProxies)
	if proxies == nil {
		proxies = []string{}
	}
	build := s.opts.Build

	detail.PublicURL = &publicURL
	detail.Listen = &listen
	detail.BehindProxy = &behindProxy
	detail.TrustedProxies = &proxies
	detail.Build = &build
	detail.FFprobe = &ServerFFprobeWire{Found: s.opts.FFprobe.Found, Version: s.opts.FFprobe.Version}

	ready := s.opts.Ready == nil || s.opts.Ready()
	health := ServerHealthWire{Ready: ready}

	if s.opts.Diag != nil {
		if snapshot, err := s.opts.Diag.Read(r.Context()); err == nil {
			detail.Database = &ServerDatabaseWire{Version: snapshot.DatabaseVersion, Schema: snapshot.SchemaVersion}
			health.JobsRunning = snapshot.JobsRunning
			health.JobsFailed = snapshot.JobsFailed
		} else {
			// Eén onbereikbare meting maakt het hele antwoord niet stuk: de
			// beheerder die dit scherm opent doet dat vaak juist omdat de
			// database hapert, en dan is "ready: false" het nuttigste dat hij
			// kan zien.
			s.log.Warn("diagnostiek niet te lezen", slog.String("error", err.Error()))
			health.Ready = false
		}
	}
	detail.Health = &health
}

// behindProxy zegt of déze aanvraag via een vertrouwde proxy binnenkwam.
//
// Twee voorwaarden, en allebei zijn ze nodig. De tegenpartij moet in
// PLEYA_SERVER_TRUSTED_PROXIES staan, want anders zet elke client zelf een
// X-Forwarded-For en is het antwoord wat hij beweert. En er moet werkelijk een
// forwarding-header staan, want een vertrouwde proxy die niets doorstuurt is
// voor deze vraag geen proxy.
func (s *Server) behindProxy(r *http.Request) bool {
	if !config.RemoteAddrIsTrustedProxy(s.opts.TrustedProxies, r.RemoteAddr) {
		return false
	}
	return r.Header.Get("X-Forwarded-For") != "" ||
		r.Header.Get("X-Forwarded-Proto") != "" ||
		r.Header.Get("Forwarded") != ""
}

// handleServerEnvironment is GET /server/environment.
//
// Alleen PLEYA_SERVER_* plus een gemaskeerde DATABASE_URL (K rij 11). De rest
// van de procesomgeving is de omgeving van de container en kan credentials van
// heel andere diensten dragen; die horen niet in het beheerscherm van een
// mediaserver, ook niet gemaskeerd.
func (s *Server) handleServerEnvironment(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}

	entries := []EnvironmentEntryWire{}
	for _, raw := range s.environ() {
		key, value, ok := strings.Cut(raw, "=")
		if !ok {
			continue
		}
		if key != logging.EnvDatabaseURL && !strings.HasPrefix(key, logging.EnvPrefix) {
			continue
		}
		masked, redacted := logging.MaskEnvironment(key, value)
		entries = append(entries, EnvironmentEntryWire{Key: key, Value: masked, Redacted: redacted})
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Key < entries[j].Key })

	writeJSON(w, http.StatusOK, ServerEnvironmentWire{Entries: entries})
}

func (s *Server) environ() []string {
	if s.opts.Environ != nil {
		return s.opts.Environ()
	}
	return os.Environ()
}

// handleServerLog is GET /server/log?level=&limit=.
//
// De regels komen uit de ringbuffer in het geheugen, nooit uit een bestand
// (K rij 11), en ze zijn al geredigeerd op de weg erin.
//
// Een onbekend niveau is geen fout maar geen filter. Het veld is unknown-safe
// in het contract, en dan hoort een waarde die deze server niet kent hem niet
// te laten weigeren; een client van een latere versie mag een niveau sturen dat
// hier nog niet bestaat.
func (s *Server) handleServerLog(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}

	minLevel := slog.LevelDebug
	if raw := strings.TrimSpace(r.URL.Query().Get("level")); raw != "" {
		if parsed, ok := logging.ParseLevelName(raw); ok {
			minLevel = parsed
		}
	}

	limit := defaultLogLimit
	if v, ok := queryInt(r, "limit"); ok {
		limit = v
	}
	if limit < 1 {
		limit = 1
	}
	if limit > maxLogLimit {
		limit = maxLogLimit
	}

	entries := []LogEntryWire{}
	if s.opts.Log != nil {
		for _, e := range s.opts.Log.Entries(minLevel, limit) {
			entries = append(entries, LogEntryWire{
				At:        formatTime(e.At),
				Level:     logging.LevelName(e.Level),
				Component: e.Component,
				Message:   e.Message,
			})
		}
	}
	writeJSON(w, http.StatusOK, ServerLogWire{Entries: entries})
}

// handleConnectivityCheck is POST /server/connectivity-check.
//
// Het doel is altijd het eigen public_url en niets anders (K rij 13): er is
// geen aanvraagveld, dus er is niets aan de aanvrager om het ergens anders
// heen te richten. De grens tegen een adres in het interne netwerk staat op
// PATCH /settings, waar een waarde binnenkomt die van buiten komt; de omgeving
// valt daar bewust buiten, want op een thuisnetwerk ís 192.168.x.y het juiste
// publieke adres en dat is de keuze van wie de container draait.
//
// Twee metingen. De eerste vraagt /info op en zegt of het adres van hieruit
// terugkomt bij deze server. De tweede vraagt zestien bytes van de bundel met
// een Range-header: een tussenliggende proxy die ranges wegbuffert breekt
// precies het direct play uit PS-4, en dat is aan de clientkant een
// onverklaarbaar haperende speler.
func (s *Server) handleConnectivityCheck(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}

	out := ConnectivityCheckWire{BehindProxy: s.behindProxy(r)}

	raw := strings.TrimSpace(s.settings().PublicURL())
	if raw == "" {
		// Geen publiek adres ingesteld is een geldige opstelling, en dan is
		// "niet bereikbaar" het eerlijke antwoord op een vraag die nergens
		// heen kan.
		writeJSON(w, http.StatusOK, out)
		return
	}
	base, err := config.ParsePublicURL(raw)
	if err != nil {
		s.log.Warn("public_url is onbruikbaar voor de connectivity-check",
			slog.String("error", err.Error()))
		writeJSON(w, http.StatusOK, out)
		return
	}

	out.PublicURLReachable = s.probeInfo(r.Context(), base)
	if out.PublicURLReachable {
		out.RangeIntact = s.probeRange(r.Context(), base)
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) probeInfo(ctx context.Context, base *url.URL) bool {
	answer, ok := s.probe(ctx, base.JoinPath("pleya", "v1", "info").String(), nil)
	return ok && answer.status == http.StatusOK
}

func (s *Server) probeRange(ctx context.Context, base *url.URL) bool {
	answer, ok := s.probe(ctx, base.String(), map[string]string{
		"Range": fmt.Sprintf("bytes=0-%d", probeRangeBytes-1),
	})
	if !ok {
		return false
	}
	// 206 met een Content-Range en niet meer bytes dan gevraagd. Een 200 met de
	// hele pagina is in HTTP-termen geen fout, maar het is precies het gedrag
	// dat een speler laat haperen bij elke seek, dus hier telt het als niet
	// intact.
	return answer.status == http.StatusPartialContent &&
		answer.header.Get("Content-Range") != "" &&
		answer.bodyLength <= probeRangeBytes
}

// probeAnswer is wat de controle van een antwoord overhoudt: de status, de
// headers en hoeveel bytes eruit kwamen. Het lichaam zelf niet: er is geen
// vraag die de inhoud van dat antwoord stelt, en het niet bewaren is de
// kortste weg om te garanderen dat er niets van in een logregel belandt.
type probeAnswer struct {
	status     int
	header     http.Header
	bodyLength int
}

// probe doet één aanvraag met een vaste time-out en zonder een redirect te
// volgen. Redirects volgen zou het enige doel dat dit endpoint kent alsnog
// verplaatsbaar maken door wie het antwoord schrijft.
func (s *Server) probe(ctx context.Context, target string, headers map[string]string) (probeAnswer, bool) {
	ctx, cancel := context.WithTimeout(ctx, probeTimeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return probeAnswer{}, false
	}
	for name, value := range headers {
		req.Header.Set(name, value)
	}

	resp, err := s.probeClient().Do(req)
	if err != nil {
		s.log.Info("connectivity-check kreeg geen antwoord",
			slog.String("target", target), slog.String("error", logging.Redact(err.Error())))
		return probeAnswer{}, false
	}
	defer resp.Body.Close()

	// Begrensd lezen: het doel is een adres dat een beheerder heeft ingevuld,
	// en een antwoord van een gigabyte hoort deze controle niet op te eten.
	n, _ := io.Copy(io.Discard, io.LimitReader(resp.Body, maxProbeBody))
	return probeAnswer{status: resp.StatusCode, header: resp.Header, bodyLength: int(n)}, true
}

func (s *Server) probeClient() *http.Client {
	if s.opts.ProbeClient != nil {
		return s.opts.ProbeClient
	}
	return defaultProbeClient
}

// NewProbeClient bouwt de client van de connectivity-check: vaste time-out,
// geen omleidingen.
//
// Exported omdat de testomgeving hem ook gebruikt, met een eigen transport
// eronder om te tellen wat er uitgaat. Zou de test zijn eigen client
// samenstellen, dan zou "volgt geen omleidingen" een eigenschap van de test
// bewijzen en niet van de server.
func NewProbeClient(transport http.RoundTripper) *http.Client {
	return &http.Client{
		Timeout:       probeTimeout,
		Transport:     transport,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
}

var defaultProbeClient = NewProbeClient(nil)

// handleRotateSigningKey is POST /server/rotate-signing-key.
//
// De volgorde ligt vast: eerst elke sessie intrekken, dan pas de sleutel
// vervangen. Andersom zou een mislukte schrijfactie een server achterlaten
// waarvan de accesstokens dood zijn en de refreshtokens leven, en dan logt elke
// client zichzelf meteen weer in met precies de keten die de beheerder wilde
// verbreken. Deze volgorde faalt de veilige kant op: iedereen uitgelogd, de
// sleutel ongewijzigd.
//
// Het antwoord is 204 en draagt de nieuwe sleutel niet (K rij 15). Ook het
// token van de aanvrager zelf is hierna dood; opnieuw inloggen hoort erbij en
// is het bewijs dat de rotatie gewerkt heeft.
func (s *Server) handleRotateSigningKey(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}

	var req rotateSigningKeyRequest
	if !s.decodeBody(w, r, &req, CodeConfirmMismatch) {
		return
	}
	if req.Confirm != rotateConfirmWord {
		writeError(w, s.log, CodeConfirmMismatch,
			"confirm must be "+rotateConfirmWord, map[string]any{"expected": rotateConfirmWord})
		return
	}
	if strings.TrimSpace(s.opts.ConfigDir) == "" {
		writeInternal(w, s.log, errors.New("geen configmap; de ondertekensleutel heeft geen plek"))
		return
	}

	now := s.now().UTC()
	revoked, err := s.opts.Auth.RevokeAllSessions(r.Context(), now)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	for _, sessionID := range revoked {
		s.opts.Revocations.Revoke(sessionID, now)
	}

	key, err := auth.RotateSigningKey(s.opts.ConfigDir)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	if err := s.opts.Signer.Rotate(key); err != nil {
		writeInternal(w, s.log, err)
		return
	}

	s.log.Warn("ondertekensleutel geroteerd; alle sessies zijn ingetrokken",
		slog.Int("sessies", len(revoked)))
	w.WriteHeader(http.StatusNoContent)
}
