package api

import (
	"errors"
	"net/http"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// De vijf gebruikersbeheer-endpoints uit DEC-067, stap 4 van de
// PS-9-implementatievolgorde. Zonder deze set is het enige pad naar een tweede
// gebruiker handmatige SQL, en dat is geen ondersteund productpad; AC1 en het
// stopcriterium van PS-9 vragen om twee echte gebruikers.
//
// Er komt hier geen scherm bij. Dat is PS-11A (DEC-067) en wordt niet
// vooruitgebouwd; het ondersteunde pad in deze fase is de API plus het
// curl-recept in README.md.

// minPasswordLength is de minLength uit het contract (schema Password en
// CreateUserRequest). Ook hier afdwingen scheelt een wachtwoord dat het schema
// afkeurt maar de server al heeft opgeslagen.
const minPasswordLength = 8

// pathUserID leest {id} uit het pad met auth.user_not_found als foutcode: een
// onleesbaar gebruikers-id is voor de aanvrager niet te onderscheiden van een
// gebruiker die niet bestaat, en library.not_found zou hier het verkeerde
// domein noemen.
func (s *Server) pathUserID(w http.ResponseWriter, r *http.Request, code string) (id.ID, bool) {
	parsed, err := id.Parse(r.PathValue("id"))
	if err != nil {
		writeError(w, s.log, code, "not found", nil)
		return id.Nil, false
	}
	return parsed, true
}

// requester is de aanvrager van deze aanvraag: zijn id en zijn rol.
//
// De rol staat niet in de claims en wordt per aanvraag gelezen. Dat is opzet:
// een rol die in een token zit blijft geldig tot dat token verloopt, en een
// degradatie die pas over vijftien minuten ingaat is precies het soort
// stille vertraging dat AC3 elders juist wegneemt.
type requester struct {
	id   id.ID
	role auth.Role
}

// isAdmin zegt of deze aanvrager de admin-klasse haalt. owner telt mee: hij
// heeft alles van admin (specificatie 16.1).
func (r requester) isAdmin() bool { return r.role == auth.RoleOwner || r.role == auth.RoleAdmin }

// resolveRequester leest id en rol van de aanvrager.
//
// Een gebruiker die niet meer bestaat krijgt 404 en geen 500: dat is een
// accesstoken van een net verwijderde gebruiker, een normale uitkomst en geen
// opslagstoring. Dezelfde redenering als in authorizeLibraryFor.
func (s *Server) resolveRequester(w http.ResponseWriter, r *http.Request) (requester, bool) {
	userID, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return requester{}, false
	}
	role, err := s.opts.Auth.UserRole(r.Context(), userID)
	if err != nil {
		if errors.Is(err, auth.ErrUserNotFound) {
			writeError(w, s.log, CodeUserNotFound, "not found", nil)
			return requester{}, false
		}
		writeInternal(w, s.log, err)
		return requester{}, false
	}
	return requester{id: userID, role: role}, true
}

// requireAdmin is de admin-klasse als poort.
//
// Een member die een admin-endpoint aanroept krijgt 404 en geen 403, dezelfde
// regel als overal (hoofdstuk 7.1): het bestaan van het beheeroppervlak lekt
// niet naar wie er niet bij mag.
func (s *Server) requireAdmin(w http.ResponseWriter, r *http.Request) (requester, bool) {
	req, ok := s.resolveRequester(w, r)
	if !ok {
		return requester{}, false
	}
	if !req.isAdmin() {
		writeError(w, s.log, CodeUserNotFound, "not found", nil)
		return requester{}, false
	}
	return req, true
}

// UserWire is het wire-type van een gebruiker (schema User).
type UserWire struct {
	ID       string `json:"id"`
	Username string `json:"username"`
	Role     string `json:"role"`
}

// UserListWire is het antwoord van GET /users.
type UserListWire struct {
	Items []UserWire `json:"items"`
}

// LibraryPermissionWire is één rij van de rechtenladder.
type LibraryPermissionWire struct {
	LibraryID  string `json:"library_id"`
	Permission string `json:"permission"`
}

// LibraryPermissionListWire is het antwoord van PUT /users/{id}/permissions.
type LibraryPermissionListWire struct {
	Items []LibraryPermissionWire `json:"items"`
}

func userWire(u auth.User) UserWire {
	return UserWire{ID: u.ID.String(), Username: u.Username, Role: string(u.Role)}
}

type createUserRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
	Role     string `json:"role"`
}

func (s *Server) handleCreateUser(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}

	var req createUserRequest
	if !s.decodeBody(w, r, &req, CodeUserNotFound) {
		return
	}

	req.Username = strings.TrimSpace(req.Username)
	if req.Username == "" || !auth.ValidRole(req.Role) {
		writeError(w, s.log, CodeUserNotFound, "username or role missing", nil)
		return
	}
	// owner ontstaat uitsluitend via /auth/setup (specificatie 16.3). De
	// partiële unieke index zou een tweede owner ook weigeren, maar dan met een
	// unieke-schending die als "gebruikersnaam bezet" zou lezen.
	if auth.Role(req.Role) == auth.RoleOwner {
		writeError(w, s.log, CodeOwnerImmutable, "owner is created by setup only", nil)
		return
	}
	if len(req.Password) < minPasswordLength {
		writeError(w, s.log, CodeUserNotFound, "password too short", nil)
		return
	}

	hash, err := auth.HashPassword(req.Password, s.opts.Argon2)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	user, err := s.opts.Auth.CreateUser(r.Context(), req.Username, hash, auth.Role(req.Role), s.now().UTC())
	if errors.Is(err, auth.ErrUsernameTaken) {
		writeError(w, s.log, CodeUsernameTaken, "username taken", nil)
		return
	}
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, userWire(user))
}

// handleListUsers is matrixregel 14: member en restricted zien alleen zichzelf.
func (s *Server) handleListUsers(w http.ResponseWriter, r *http.Request) {
	req, ok := s.resolveRequester(w, r)
	if !ok {
		return
	}

	if !req.isAdmin() {
		self, err := s.opts.Auth.GetUser(r.Context(), req.id)
		if err != nil {
			writeInternal(w, s.log, err)
			return
		}
		writeJSON(w, http.StatusOK, UserListWire{Items: []UserWire{userWire(self)}})
		return
	}

	users, err := s.opts.Auth.ListUsers(r.Context())
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	items := make([]UserWire, 0, len(users))
	for _, u := range users {
		items = append(items, userWire(u))
	}
	writeJSON(w, http.StatusOK, UserListWire{Items: items})
}

type updateUserRequest struct {
	Role     *string `json:"role"`
	Password *string `json:"password"`
}

// handleUpdateUser is admin, of owner op zichzelf (specificatie 16.3).
//
// "owner op zichzelf" is smaller dan het lijkt: de owner is al admin, dus die
// clausule voegt niets toe zolang de owner de enige niet-admin zou zijn die
// hem nodig heeft. Hij staat in het contract en wordt daarom letterlijk
// gevolgd, niet weggeredeneerd.
func (s *Server) handleUpdateUser(w http.ResponseWriter, r *http.Request) {
	req, ok := s.resolveRequester(w, r)
	if !ok {
		return
	}
	targetID, ok := s.pathUserID(w, r, CodeUserNotFound)
	if !ok {
		return
	}
	if !req.isAdmin() && req.id != targetID {
		writeError(w, s.log, CodeUserNotFound, "not found", nil)
		return
	}

	var body updateUserRequest
	if !s.decodeBody(w, r, &body, CodeUserNotFound) {
		return
	}
	if body.Role == nil && body.Password == nil {
		writeError(w, s.log, CodeUserNotFound, "role or password required", nil)
		return
	}

	var role *auth.Role
	if body.Role != nil {
		if !auth.ValidRole(*body.Role) {
			writeError(w, s.log, CodeUserNotFound, "unknown role", nil)
			return
		}
		parsed := auth.Role(*body.Role)
		role = &parsed
	}

	var hash *string
	if body.Password != nil {
		if len(*body.Password) < minPasswordLength {
			writeError(w, s.log, CodeUserNotFound, "password too short", nil)
			return
		}
		// restricted beheert zijn eigen wachtwoord niet (DEC-065 §3): alleen
		// owner en admin zetten het. De rolcontrole hierboven laat een gebruiker
		// zijn eigen id passeren, dus deze regel is de enige die het verschil
		// tussen member en restricted maakt.
		if !req.isAdmin() && req.role == auth.RoleRestricted {
			writeError(w, s.log, CodeUserNotFound, "not found", nil)
			return
		}
		h, err := auth.HashPassword(*body.Password, s.opts.Argon2)
		if err != nil {
			writeInternal(w, s.log, err)
			return
		}
		hash = &h
	}

	user, err := s.opts.Auth.UpdateUser(r.Context(), targetID, role, hash, s.now().UTC())
	switch {
	case errors.Is(err, auth.ErrUserNotFound):
		writeError(w, s.log, CodeUserNotFound, "not found", nil)
		return
	case errors.Is(err, auth.ErrOwnerImmutable):
		writeError(w, s.log, CodeOwnerImmutable, "owner cannot be demoted", nil)
		return
	case err != nil:
		writeInternal(w, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, userWire(user))
}

func (s *Server) handleDeleteUser(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	targetID, ok := s.pathUserID(w, r, CodeUserNotFound)
	if !ok {
		return
	}

	err := s.opts.Auth.DeleteUser(r.Context(), targetID)
	switch {
	case errors.Is(err, auth.ErrUserNotFound):
		writeError(w, s.log, CodeUserNotFound, "not found", nil)
		return
	case errors.Is(err, auth.ErrOwnerImmutable):
		writeError(w, s.log, CodeOwnerImmutable, "owner cannot be deleted", nil)
		return
	case err != nil:
		writeInternal(w, s.log, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type permissionsRequest struct {
	Permissions []LibraryPermissionWire `json:"permissions"`
}

func (s *Server) handleSetPermissions(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	targetID, ok := s.pathUserID(w, r, CodeUserNotFound)
	if !ok {
		return
	}

	var body permissionsRequest
	if !s.decodeBody(w, r, &body, CodeUserNotFound) {
		return
	}

	perms := make([]auth.LibraryPermission, 0, len(body.Permissions))
	for _, p := range body.Permissions {
		libraryID, err := id.Parse(p.LibraryID)
		if err != nil {
			writeError(w, s.log, CodeNotFound, "not found", nil)
			return
		}
		if !auth.ValidPermission(p.Permission) {
			writeError(w, s.log, CodeUserNotFound, "unknown permission", nil)
			return
		}
		perms = append(perms, auth.LibraryPermission{LibraryID: libraryID, Permission: p.Permission})
	}

	err := s.opts.Auth.SetPermissions(r.Context(), targetID, perms)
	switch {
	case errors.Is(err, auth.ErrUserNotFound):
		writeError(w, s.log, CodeUserNotFound, "not found", nil)
		return
	case errors.Is(err, auth.ErrLibraryNotFound):
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return
	case errors.Is(err, auth.ErrRestrictedCannotManage):
		// DEC-065 §3 verbiedt manage voor restricted, maar het coderegister
		// (hoofdstuk 7.1) heeft er geen eigen code voor en het contractvenster
		// is dicht: een achtste protocolwijziging mag niet. auth.user_not_found
		// is de eerlijkste van de codes die er wel zijn en staat al als 404 op
		// dit endpoint: het gevraagde doel, deze gebruiker met manage, bestaat
		// niet. Zie de openstaande punten in het PS-9-verslag; een eigen code
		// hoort in het eerstvolgende protocolvenster.
		writeError(w, s.log, CodeUserNotFound, "restricted cannot hold manage", nil)
		return
	case err != nil:
		writeInternal(w, s.log, err)
		return
	}

	stored, err := s.opts.Auth.ListPermissions(r.Context(), targetID)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	items := make([]LibraryPermissionWire, 0, len(stored))
	for _, p := range stored {
		items = append(items, LibraryPermissionWire{LibraryID: p.LibraryID.String(), Permission: p.Permission})
	}
	writeJSON(w, http.StatusOK, LibraryPermissionListWire{Items: items})
}
