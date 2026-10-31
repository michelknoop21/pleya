package api

import (
	"net/http"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

// ListSharingProbe raakt allowListSharing zonder ownDataWrite ervoor. Op de echte
// routes weigert die laatste een beperkt token al eerder, en dan zou een test niet
// zien of de regel zelf nog klopt.
func (s *Server) ListSharingProbe() http.Handler {
	visibility := catalog.VisibilityEveryone
	return s.authenticated(func(w http.ResponseWriter, r *http.Request) {
		if s.allowListSharing(w, r, catalog.ListInput{Visibility: &visibility}) {
			w.WriteHeader(http.StatusNoContent)
		}
	})
}
