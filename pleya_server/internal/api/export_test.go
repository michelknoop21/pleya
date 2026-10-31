package api

import (
	"net/http"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

// SetPasswordVerifier vervangt de Argon2-stap, zodat een test kan zien hoeveel er
// tegelijk lopen zonder 64 MiB per stuk.
func (s *Server) SetPasswordVerifier(verify func(string, string, auth.Argon2Params) (bool, bool, error)) {
	s.loginGuard.verify = verify
}

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
