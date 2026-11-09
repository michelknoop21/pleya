package api

import (
	"github.com/edde746/plezy/pleya_server/internal/config"
	"log/slog"
	"net/http"
)

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
	req := requester{id: userID, role: role}
	if scope, ok := apiScopeFromContext(r.Context()); ok {
		req.scope, req.viaAPIToken = scope, true
	}
	return req.canAdminister()
}

func (s *Server) fillServerAdminDetail(r *http.Request, detail *ServerDetail) {
	publicURL := s.settings().PublicURL()
	webOrigin := s.settings().WebOrigin()
	listen := s.opts.Listen
	behindProxy := s.behindProxy(r)
	proxies := config.TrustedProxyStrings(s.opts.TrustedProxies)
	if proxies == nil {
		proxies = []string{}
	}
	build := s.opts.Build

	detail.PublicURL = &publicURL
	detail.WebOrigin = &webOrigin
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

	// De status blijft zichtbaar wanneer het transport uit staat.
	detail.MCP = s.mcpStatus()
}
