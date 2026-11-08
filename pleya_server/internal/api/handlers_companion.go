package api

import (
	"encoding/base64"
	"errors"
	"net/http"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
)

// CompanionTicketRequest is het lichaam van POST /companion/ticket.
type CompanionTicketRequest struct {
	// DeviceKey is de publieke Ed25519-sleutel van het toestel, base64url
	// zonder opvulling. Het ticket bindt zich eraan.
	DeviceKey string `json:"device_key"`
}

// CompanionTicket is het antwoord: het ticket en de sleutel die het
// ondertekende, zodat een host met dit antwoord ook tickets van anderen kan
// controleren.
type CompanionTicket struct {
	Ticket    string `json:"ticket"`
	ExpiresAt string `json:"expires_at"`
	KeyID     string `json:"key_id"`
	PublicKey string `json:"public_key"`
}

// handleCompanionTicket is POST /companion/ticket (DEC-XXX, matrixregel 107):
// een ticket over de aanvrager zelf, voor Pleya Fly en de Companion Remote.
//
// Elke rol, want het ticket zegt alleen wie de aanvrager is en er staat geen
// doel in de aanvraag: een lid kan geen ticket over een ander vragen. Een
// API-token krijgt er geen. Dat credential is een agent of een script en geen
// toestel van een persoon, en een ticket laat een ander toestel een profiel
// wisselen; dezelfde 403 als op de routes die eigen gegevens wijzigen.
func (s *Server) handleCompanionTicket(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	req, ok := s.resolveRequester(w, r)
	if !ok {
		return
	}
	if req.viaAPIToken {
		writeError(w, s.log, CodeScopeInsufficient, "an API token gets no companion ticket",
			map[string]any{"scope": string(req.scope)})
		return
	}
	var body CompanionTicketRequest
	if !s.decodeBody(w, r, &body, CodeDeviceKeyInvalid) {
		return
	}
	deviceKey, err := base64.RawURLEncoding.Strict().DecodeString(body.DeviceKey)
	if err != nil {
		writeError(w, s.log, CodeDeviceKeyInvalid, "device_key invalid", nil)
		return
	}
	ticket, claims, pub, err := s.opts.Signer.MintCompanionTicket(
		s.opts.ServerID.String(), req.id.String(), deviceKey, auth.CompanionTicketTTL)
	if errors.Is(err, auth.ErrCompanionDeviceKey) {
		writeError(w, s.log, CodeDeviceKeyInvalid, "device_key invalid", nil)
		return
	}
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, CompanionTicket{
		Ticket:    ticket,
		ExpiresAt: formatTime(time.Unix(claims.ExpiresAt, 0)),
		KeyID:     claims.KeyID,
		PublicKey: base64.RawURLEncoding.EncodeToString(pub),
	})
}
