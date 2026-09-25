package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"sort"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/settings"
)

// GET en PATCH /settings (S1.2, J.2 rij 2).
//
// Klasse admin. De poort staat in de handler en niet in een middleware, om
// dezelfde reden als bij gebruikersbeheer: requireAdmin schrijft de 404 die een
// niet-beheerder hoort te zien, en dat antwoord is niet te onderscheiden van
// dat van een gebruiker die niet meer bestaat.
//
// Wat een beheerder hier níét kan wijzigen staat in K rij 14 en is even
// belangrijk als wat er wel in staat: bindadres, vertrouwde proxy's, paden en
// de ondertekensleutel. Wie het bindadres over de API kan zetten kan de server
// van het netwerk halen of hem juist openzetten, en dat hoort bij het draaien
// van de container.

// SettingStringWire is één sleutel met een tekstwaarde (schema SettingString en
// SettingDuration). De bron zegt of de waarde uit de omgeving komt of uit de
// database; zonder dat veld zou een beheerder niet kunnen zien of hij naar een
// default kijkt of naar zijn eigen keuze.
type SettingStringWire struct {
	Value  string `json:"value"`
	Source string `json:"source"`
}

// SettingIntWire is één sleutel met een geheel getal (schema SettingInteger).
type SettingIntWire struct {
	Value  int    `json:"value"`
	Source string `json:"source"`
}

// SettingStringListWire is één sleutel met een lijst (schema
// SettingStringList). Voorlopig alleen cors_origins.
//
// Value is nooit nil in het antwoord: de lege lijst is een geldige waarde en
// `null` is dat niet. Een client die `null` naast `[]` zou moeten afhandelen
// doet twee controles waar er één hoort.
type SettingStringListWire struct {
	Value  []string `json:"value"`
	Source string   `json:"source"`
}

// SettingsWire is het antwoord van beide endpoints (schema Settings).
type SettingsWire struct {
	ServerName        SettingStringWire `json:"server_name"`
	AccessTokenTTL    SettingStringWire `json:"access_token_ttl"`
	RefreshTokenTTL   SettingStringWire `json:"refresh_token_ttl"`
	StreamTokenTTL    SettingStringWire `json:"stream_token_ttl"`
	StreamSessionTTL  SettingStringWire `json:"stream_session_ttl"`
	MaxStreamSessions SettingIntWire    `json:"max_stream_sessions"`

	// PublicURL kwam met S1.3, want POST /server/connectivity-check heeft een
	// doel nodig en GET /server toont hem. Leeg betekent "niet ingesteld".
	PublicURL SettingStringWire `json:"public_url"`

	// Het origin-model kwam met S1.8 (RB-29). WebOrigin is de canonieke
	// webclient, CORSOrigins de lijst die er cross-origin bij mag.
	WebOrigin   SettingStringWire     `json:"web_origin"`
	CORSOrigins SettingStringListWire `json:"cors_origins"`
}

// settingsPatch is de gesloten aanvraagbody (schema SettingsPatch).
//
// Per sleutel een pointer naar de ruwe JSON: dat onderscheidt "niet meegestuurd"
// van "meegestuurd met een waarde die niet klopt", en het laat het valideren
// over aan het settings-pakket, dat de grens naast de sleutel bewaart.
type settingsPatch struct {
	ServerName        *json.RawMessage `json:"server_name"`
	AccessTokenTTL    *json.RawMessage `json:"access_token_ttl"`
	RefreshTokenTTL   *json.RawMessage `json:"refresh_token_ttl"`
	StreamTokenTTL    *json.RawMessage `json:"stream_token_ttl"`
	StreamSessionTTL  *json.RawMessage `json:"stream_session_ttl"`
	MaxStreamSessions *json.RawMessage `json:"max_stream_sessions"`
	PublicURL         *json.RawMessage `json:"public_url"`
	WebOrigin         *json.RawMessage `json:"web_origin"`
	CORSOrigins       *json.RawMessage `json:"cors_origins"`
}

func (p settingsPatch) keys() map[string]json.RawMessage {
	out := map[string]json.RawMessage{}
	for key, raw := range map[string]*json.RawMessage{
		settings.KeyServerName:        p.ServerName,
		settings.KeyAccessTokenTTL:    p.AccessTokenTTL,
		settings.KeyRefreshTokenTTL:   p.RefreshTokenTTL,
		settings.KeyStreamTokenTTL:    p.StreamTokenTTL,
		settings.KeyStreamSessionTTL:  p.StreamSessionTTL,
		settings.KeyMaxStreamSessions: p.MaxStreamSessions,
		settings.KeyPublicURL:         p.PublicURL,
		settings.KeyWebOrigin:         p.WebOrigin,
		settings.KeyCORSOrigins:       p.CORSOrigins,
	} {
		if raw != nil {
			out[key] = *raw
		}
	}
	return out
}

func settingsWire(v settings.Values) SettingsWire {
	text := func(key string) SettingStringWire {
		return SettingStringWire{Value: settingText(v, key), Source: string(v.Source(key))}
	}
	return SettingsWire{
		ServerName:       text(settings.KeyServerName),
		AccessTokenTTL:   text(settings.KeyAccessTokenTTL),
		RefreshTokenTTL:  text(settings.KeyRefreshTokenTTL),
		StreamTokenTTL:   text(settings.KeyStreamTokenTTL),
		StreamSessionTTL: text(settings.KeyStreamSessionTTL),
		PublicURL:        text(settings.KeyPublicURL),
		WebOrigin:        text(settings.KeyWebOrigin),
		MaxStreamSessions: SettingIntWire{
			Value:  v.MaxStreamSessions(),
			Source: string(v.Source(settings.KeyMaxStreamSessions)),
		},
		CORSOrigins: SettingStringListWire{
			// Nooit nil de lijn op: zie SettingStringListWire.
			Value:  append([]string{}, v.CORSOrigins()...),
			Source: string(v.Source(settings.KeyCORSOrigins)),
		},
	}
}

// settingText geeft de waarde van een tekstsleutel in dezelfde vorm als de
// PATCH hem accepteert. Een duur gaat er dus als "15m" uit en niet als
// nanoseconden: wat je terugkrijgt kun je zo weer insturen.
func settingText(v settings.Values, key string) string {
	raw, err := settings.Encode(v.Get(key))
	if err != nil {
		return ""
	}
	var text string
	if err := json.Unmarshal(raw, &text); err != nil {
		return ""
	}
	return text
}

func (s *Server) handleGetSettings(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	writeJSON(w, http.StatusOK, settingsWire(s.settings()))
}

func (s *Server) handlePatchSettings(w http.ResponseWriter, r *http.Request) {
	req, ok := s.requireAdmin(w, r)
	if !ok {
		return
	}

	var patch settingsPatch
	if !s.decodeBody(w, r, &patch, CodeSettingsInvalidValue) {
		// Een onbekende sleutel komt hier uit: de body is gesloten, dus de
		// decoder wijst hem af (K rij 14, regel 5 van hoofdstuk 3).
		return
	}

	keys := patch.keys()
	if len(keys) == 0 {
		writeError(w, s.log, CodeSettingsInvalidValue, "empty patch", nil)
		return
	}

	if !s.opts.Settings.HasStore() {
		// Zonder database is er niets om te bewaren. Doen alsof het gelukt is
		// zou een beheerder een waarde tonen die de volgende aanvraag alweer
		// kwijt is.
		writeInternal(w, s.log, errors.New("instellingen wijzigen zonder opslag"))
		return
	}

	if err := s.opts.Settings.Apply(r.Context(), keys, req.id); err != nil {
		var invalid *settings.InvalidValueError
		if errors.As(err, &invalid) {
			details := map[string]any{"field": invalid.Field}
			if invalid.Minimum != "" {
				details["minimum"] = invalid.Minimum
			}
			if invalid.Maximum != "" {
				details["maximum"] = invalid.Maximum
			}
			s.auditEvent(r, auditPatchSettings, "", audit.OutcomeDenied,
				map[string]any{"field": invalid.Field, "reason": "invalid_value"})
			writeError(w, s.log, CodeSettingsInvalidValue, invalid.Error(), details)
			return
		}
		writeInternal(w, s.log, err)
		return
	}

	// De namen van de gewijzigde sleutels, niet hun waarden. Vier van de negen
	// raken de beveiliging (twee TTL's en sinds S1.8 het origin-model), en dát
	// een beheerder eraan draaide is
	// wat het log moet vastleggen; wat de nieuwe waarde is staat in
	// GET /settings, dat de bron per sleutel toch al toont.
	changed := make([]string, 0, len(keys))
	for k := range keys {
		changed = append(changed, k)
	}
	// Gesorteerd, want een map-iteratie in Go is willekeurig en twee identieke
	// patches horen niet twee verschillende logregels op te leveren.
	sort.Strings(changed)
	s.auditEvent(r, auditPatchSettings, "", audit.OutcomeOK, map[string]any{"keys": changed})

	writeJSON(w, http.StatusOK, settingsWire(s.settings()))
}
