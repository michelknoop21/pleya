package api

import (
	"encoding/json"
	"errors"
	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/settings"
	"net/http"
)

type setupRequest struct {
	SetupCode  string `json:"setup_code"`
	Username   string `json:"username"`
	Password   string `json:"password"`
	DeviceID   string `json:"device_id"`
	DeviceName string `json:"device_name"`

	// ServerName (J.2 rij 10) is de instelling server_name, gezet op het moment
	// dat er nog geen beheerder is om PATCH /settings te doen. Optioneel, en
	// alleen te sturen wanneer info.server.setup_accepts_name waar is.
	ServerName string `json:"server_name"`
}

func (s *Server) handleSetup(w http.ResponseWriter, r *http.Request) {
	if !s.rateLimit(w, "setup") {
		return
	}

	var req setupRequest
	if !s.decodeBody(w, r, &req, CodeSetupCodeInvalid) {
		return
	}
	if req.SetupCode == "" || req.Username == "" {
		writeError(w, s.log, CodeSetupCodeInvalid, "setup code or username missing", nil)
		return
	}
	// minLength 8 staat in het contract; hem hier ook afdwingen scheelt een
	// wachtwoord dat het schema wel afkeurt maar de server al heeft opgeslagen.
	if len(req.Password) < 8 {
		writeError(w, s.log, CodeSetupCodeInvalid, "password too short", nil)
		return
	}

	// De servernaam wordt hier al getoetst en pas na CompleteSetup weggeschreven.
	// Andersom zou een naam van vijfenzestig tekens de setupcode opbranden: die
	// is eenmalig, dus de tweede poging met een kortere naam zou stuiten op
	// auth.setup_already_completed en de eigenaar zou een server zonder naam
	// overhouden.
	serverName, ok := s.validateSetupServerName(w, req.ServerName)
	if !ok {
		return
	}

	hash, err := auth.HashPassword(req.Password, s.opts.Argon2)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	err = s.opts.Auth.CompleteSetup(r.Context(), req.SetupCode, req.Username, hash, s.now().UTC())
	switch {
	case errors.Is(err, auth.ErrSetupCompleted):
		s.auditAnonymous(r, auditSetup, audit.OutcomeDenied, map[string]any{"reason": "already_completed"})
		writeError(w, s.log, CodeSetupAlreadyCompleted, "setup already completed", nil)
		return
	case errors.Is(err, auth.ErrSetupCodeInvalid):
		// De code zelf gaat niet mee in detail. Hij is een geheim zolang setup
		// openstaat, en een auditlog dat mislukte pogingen letterlijk bewaart
		// zou het raden ervan makkelijker maken in plaats van zichtbaar.
		s.auditAnonymous(r, auditSetup, audit.OutcomeDenied, map[string]any{"reason": "code_invalid"})
		writeError(w, s.log, CodeSetupCodeInvalid, "setup code invalid or expired", nil)
		return
	case err != nil:
		writeInternal(w, s.log, err)
		return
	}

	ownerID, err := s.opts.Auth.OwnerUserID(r.Context())
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	if serverName != nil {
		// Op naam van de zojuist aangemaakte eigenaar, want server_settings
		// houdt bij wie een sleutel heeft gezet en er is geen andere gebruiker.
		if err := s.opts.Settings.Apply(r.Context(),
			map[string]json.RawMessage{settings.KeyServerName: *serverName}, ownerID); err != nil {
			// De eigenaar bestaat op dit punt al en de setupcode is verbruikt;
			// terugdraaien kan niet meer. Een 500 is dan het eerlijke antwoord:
			// de handeling is half gelukt, en een 200 met de oude naam zou dat
			// verbergen.
			writeInternal(w, s.log, err)
			return
		}
	}

	s.limiter.reset("setup")
	s.issueTokens(w, r, ownerID, deviceID(req.DeviceID), deviceName(req.DeviceName), auditSetup,
		credentialModeToken)
}

// validateSetupServerName toetst server_name tegen dezelfde grenzen als
// PATCH /settings, en geeft nil wanneer het veld niet is meegestuurd.
//
// Dezelfde grenzen omdat het dezelfde instelling is: settings.Parse is de enige
// plek waar ze staan, en een tweede controle hier zou meteen uit elkaar kunnen
// lopen met de eerste.
func (s *Server) validateSetupServerName(w http.ResponseWriter, raw string) (*json.RawMessage, bool) {
	if raw == "" {
		return nil, true
	}
	if s.opts.Settings == nil || !s.opts.Settings.HasStore() {
		// info.server.setup_accepts_name stond op false; deze client heeft de
		// onderhandeling overgeslagen. Doen alsof de naam is aangenomen zou een
		// server opleveren die anders heet dan het setupscherm zei.
		writeInternal(w, s.log, errors.New("server_name bij setup zonder opslag voor instellingen"))
		return nil, false
	}

	encoded, err := json.Marshal(raw)
	if err != nil {
		writeInternal(w, s.log, err)
		return nil, false
	}
	value := json.RawMessage(encoded)
	if _, err := settings.Parse(settings.KeyServerName, value); err != nil {
		var invalid *settings.InvalidValueError
		if errors.As(err, &invalid) {
			details := map[string]any{"field": invalid.Field}
			if invalid.Minimum != "" {
				details["minimum"] = invalid.Minimum
			}
			if invalid.Maximum != "" {
				details["maximum"] = invalid.Maximum
			}
			writeError(w, s.log, CodeSettingsInvalidValue, invalid.Error(), details)
			return nil, false
		}
		writeInternal(w, s.log, err)
		return nil, false
	}
	return &value, true
}
