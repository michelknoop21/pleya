package api

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/memory"
)

type MemoryFactWire struct {
	ID        string    `json:"id"`
	Category  string    `json:"category"`
	Value     string    `json:"value"`
	Source    string    `json:"source"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
type MemorySnapshotWire struct {
	Epoch    string           `json:"epoch"`
	Revision int64            `json:"revision"`
	Facts    []MemoryFactWire `json:"facts"`
}
type MemoryFactInput struct {
	ID       string `json:"id"`
	Category string `json:"category"`
	Value    string `json:"value"`
	Source   string `json:"source"`
}
type MemoryReplace struct {
	Epoch        string             `json:"epoch"`
	BaseRevision *int64             `json:"base_revision"`
	Facts        *[]MemoryFactInput `json:"facts"`
}
type MemoryClear struct {
	Epoch        string `json:"epoch"`
	BaseRevision *int64 `json:"base_revision"`
}

func memoryWire(s memory.Snapshot) MemorySnapshotWire {
	out := MemorySnapshotWire{Epoch: s.Epoch.String(), Revision: s.Revision, Facts: []MemoryFactWire{}}
	for _, f := range s.Facts {
		out.Facts = append(out.Facts, MemoryFactWire{ID: f.ID.String(), Category: f.Category, Value: f.Value, Source: f.Source, CreatedAt: f.CreatedAt, UpdatedAt: f.UpdatedAt})
	}
	return out
}
func (s *Server) memoryRequester(w http.ResponseWriter, r *http.Request) (requester, bool) {
	w.Header().Set("Cache-Control", "no-store")
	if s.opts.Memory == nil {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return requester{}, false
	}
	req, ok := s.resolveRequester(w, r)
	if !ok {
		return req, false
	}
	if req.viaAPIToken || req.role == auth.RoleRestricted {
		writeError(w, s.log, CodeMemoryNotPermitted, "not permitted", nil)
		return req, false
	}
	return req, true
}

// decodeMemory logt geen decoder-/SQL-detail: daarin kan persoonlijke tekst staan.
func (s *Server) decodeMemory(w http.ResponseWriter, r *http.Request, dst any) bool {
	data, err := io.ReadAll(io.LimitReader(r.Body, 256*1024+1))
	if err != nil {
		var sizeError *http.MaxBytesError
		if errors.As(err, &sizeError) {
			writeError(w, s.log, CodeMemoryTooLarge, "request body too large", nil)
		} else {
			writeError(w, s.log, CodeMemoryInvalid, "request body invalid", nil)
		}
		return false
	}
	if len(data) > 256*1024 {
		writeError(w, s.log, CodeMemoryTooLarge, "request body too large", nil)
		return false
	}
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err = dec.Decode(dst); err != nil {
		writeError(w, s.log, CodeMemoryInvalid, "request body invalid", nil)
		return false
	}
	var extra any
	if err = dec.Decode(&extra); err != io.EOF {
		writeError(w, s.log, CodeMemoryInvalid, "request body invalid", nil)
		return false
	}
	return true
}
func (s *Server) memoryError(w http.ResponseWriter, err error) {
	for _, code := range []string{CodeMemoryInvalid, CodeMemoryConflict, CodeMemoryEpoch, CodeMemoryDeleted, CodeMemoryLimit, CodeMemoryDuplicate} {
		if err.Error() == code {
			writeError(w, s.log, code, "memory request refused", nil)
			return
		}
	}
	// De onderliggende databasefout wordt door de store al verwijderd.
	writeError(w, s.log, CodeInternal, "memory storage unavailable", nil)
}
func (s *Server) handleGetMemory(w http.ResponseWriter, r *http.Request) {
	req, ok := s.memoryRequester(w, r)
	if !ok {
		return
	}
	snap, err := s.opts.Memory.Read(r.Context(), req.id)
	if err != nil {
		s.memoryError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, memoryWire(snap))
}
func (s *Server) handlePutMemory(w http.ResponseWriter, r *http.Request) {
	req, ok := s.memoryRequester(w, r)
	if !ok {
		return
	}
	var body MemoryReplace
	if !s.decodeMemory(w, r, &body) {
		return
	}
	epoch, err := id.Parse(body.Epoch)
	if err != nil || body.BaseRevision == nil || body.Facts == nil {
		writeError(w, s.log, CodeMemoryInvalid, "request body invalid", nil)
		return
	}
	facts := make([]memory.Fact, 0, len(*body.Facts))
	for _, f := range *body.Facts {
		fid, err := id.Parse(f.ID)
		if err != nil {
			writeError(w, s.log, CodeMemoryInvalid, "request body invalid", nil)
			return
		}
		facts = append(facts, memory.Fact{ID: fid, Category: f.Category, Value: f.Value, Source: f.Source})
	}
	snap, err := s.opts.Memory.Replace(r.Context(), req.id, epoch, *body.BaseRevision, facts, time.Now())
	if err != nil {
		s.memoryError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, memoryWire(snap))
}
func (s *Server) handleClearMemory(w http.ResponseWriter, r *http.Request) {
	req, ok := s.memoryRequester(w, r)
	if !ok {
		return
	}
	var body MemoryClear
	if !s.decodeMemory(w, r, &body) {
		return
	}
	epoch, err := id.Parse(body.Epoch)
	if err != nil || body.BaseRevision == nil || *body.BaseRevision < 0 || *body.BaseRevision > memory.MaxRevision || epoch == id.Nil {
		writeError(w, s.log, CodeMemoryInvalid, "request body invalid", nil)
		return
	}
	snap, err := s.opts.Memory.Clear(r.Context(), req.id, epoch, *body.BaseRevision)
	if err != nil {
		s.memoryError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, memoryWire(snap))
}
