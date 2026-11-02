package api

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

func (s *Server) handleMetadataFields(w http.ResponseWriter, r *http.Request) {
	item, ok := s.metadataPreviewTarget(w, r)
	if !ok {
		return
	}
	fields, err := s.opts.Catalog.MetadataFields(r.Context(), item.ID)
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	w.Header().Set("Cache-Control", "private, no-store")
	writeJSON(w, http.StatusOK, mapMetadataFields(fields))
}
func (s *Server) handleMetadataOverrides(w http.ResponseWriter, r *http.Request) {
	item, ok := s.metadataPreviewTarget(w, r)
	if !ok {
		return
	}
	var fields metadataOverridesRequest
	if !s.decodeMetadataOverridesBody(w, r, &fields) {
		return
	}
	if err := s.opts.Catalog.SetMetadataOverrides(r.Context(), item.ID, fields); err != nil {
		s.metadataOverrideError(w, r, err, item.ID.String())
		return
	}
	// Log alleen veldnamen; persoonlijke tekst hoort niet in de audit.
	names := []string{}
	for field := range fields {
		names = append(names, field)
	}
	s.auditEvent(r, "setMetadataOverrides", item.ID.String(), audit.OutcomeOK, map[string]any{"fields": names})
	s.handleMetadataFields(w, r)
}
func (s *Server) handleDeleteMetadataOverride(w http.ResponseWriter, r *http.Request) {
	item, ok := s.metadataPreviewTarget(w, r)
	if !ok {
		return
	}
	if err := s.opts.Catalog.DeleteMetadataOverride(r.Context(), item.ID, r.PathValue("field")); err != nil {
		s.metadataOverrideError(w, r, err, item.ID.String())
		return
	}
	s.auditEvent(r, "deleteMetadataOverride", item.ID.String(), audit.OutcomeOK, map[string]any{"field": r.PathValue("field")})
	s.handleMetadataFields(w, r)
}
func (s *Server) metadataOverrideError(w http.ResponseWriter, r *http.Request, err error, target string) {
	operation := "setMetadataOverrides"
	if r.Method == http.MethodDelete {
		operation = "deleteMetadataOverride"
	}
	switch {
	case errors.Is(err, catalog.ErrInvalidOverride):
		s.auditEvent(r, operation, target, audit.OutcomeDenied, map[string]any{"reason": "invalid_fields"})
		writeError(w, s.log, CodeInvalidOverride, "invalid metadata fields", nil)
	case errors.Is(err, catalog.ErrOverrideFallback):
		s.auditEvent(r, operation, target, audit.OutcomeDenied, map[string]any{"reason": "source_unavailable"})
		writeError(w, s.log, CodeOverrideFallback, "current source unavailable; override retained", nil)
	default:
		s.writeStoreError(w, err)
	}
}

// Dubbele sleutels zijn ambigu; ook een eerdere ongeldige waarde mag niet door
// een tweede exemplaar worden verborgen. De routegebonden decoder hieronder
// controleert EOF voordat een write of audit mogelijk is.
type metadataOverridesRequest map[string]json.RawMessage

func (m *metadataOverridesRequest) UnmarshalJSON(raw []byte) error {
	dec := json.NewDecoder(bytes.NewReader(raw))
	token, err := dec.Token()
	if err != nil || token != json.Delim('{') {
		return catalog.ErrInvalidOverride
	}
	out := metadataOverridesRequest{}
	for dec.More() {
		token, err = dec.Token()
		if err != nil {
			return err
		}
		key, ok := token.(string)
		if !ok {
			return catalog.ErrInvalidOverride
		}
		if _, exists := out[key]; exists {
			return catalog.ErrInvalidOverride
		}
		var value json.RawMessage
		if err = dec.Decode(&value); err != nil {
			return err
		}
		out[key] = value
	}
	if _, err = dec.Token(); err != nil {
		return err
	}
	*m = out
	return nil
}

// Deze gesloten write-route eist precies één volledige JSONwaarde. De bestaande
// bodyLimit-middleware begrenst alle bytes, ook whitespace en trailing rommel.
func (s *Server) decodeMetadataOverridesBody(w http.ResponseWriter, r *http.Request, target *metadataOverridesRequest) bool {
	dec := json.NewDecoder(r.Body)
	if err := dec.Decode(target); err != nil {
		writeError(w, s.log, CodeInvalidOverride, "request body invalid", nil)
		return false
	}
	var trailing any
	if err := dec.Decode(&trailing); err != io.EOF {
		writeError(w, s.log, CodeInvalidOverride, "request body invalid", nil)
		return false
	}
	return true
}
