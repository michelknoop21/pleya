package catalog

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Permission is één trede van de ladder uit DEC-098 §4: view < download <
// manage, opgeslagen als tekst en niet als drie booleans. download impliceert
// view, manage impliceert beide, per constructie via permissionsAtLeast en
// niet als afspraak die elders afgedwongen moet worden.
type Permission string

const (
	PermissionView     Permission = "view"
	PermissionDownload Permission = "download"
	PermissionManage   Permission = "manage"
)

// permissionsAtLeast geeft de databasewaarden die minimaal need dekken.
func permissionsAtLeast(need Permission) []string {
	switch need {
	case PermissionManage:
		return []string{"manage"}
	case PermissionDownload:
		return []string{"download", "manage"}
	default:
		return []string{"view", "download", "manage"}
	}
}

// roleBypassesPermissions zegt of een rol nooit een library_permissions-rij
// nodig heeft (DEC-098 §2): owner en admin volgen uit de rol zelf, want
// bibliotheken ontstaan tot PS-11A uit configuratie plus een herstart, zonder
// beheerscherm om ze expliciet toe te kennen.
func roleBypassesPermissions(role string) bool {
	return role == "owner" || role == "admin"
}

// userRole leest users.role rechtstreeks, zonder via internal/auth te gaan:
// dit is autorisatiebeleid over catalogusresources (DEC-098 §2), niet
// identiteitsbeheer, en de enige vraag die het hier nodig heeft is "omzeilt
// deze rol de bibliotheekrechten".
func (s *Store) userRole(ctx context.Context, userID id.ID) (string, error) {
	var role string
	err := s.pool.QueryRow(ctx, `SELECT role FROM users WHERE id = $1`, userID).Scan(&role)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	if err != nil {
		return "", fmt.Errorf("rol lezen: %w", err)
	}
	return role, nil
}

// MayAccess zegt of userID libraryID minimaal met need mag benaderen (DEC-098,
// DEC-105). Dit is DE controle uit AC2: een bibliotheek die de aanvrager niet
// mag zien bestaat voor hem niet, dus de aanroeper zet false om in 404 en
// nooit in 403.
func (s *Store) MayAccess(ctx context.Context, userID, libraryID id.ID, need Permission) (bool, error) {
	role, err := s.userRole(ctx, userID)
	if err != nil {
		return false, err
	}
	if roleBypassesPermissions(role) {
		return true, nil
	}

	var exists bool
	err = s.pool.QueryRow(ctx, `
		SELECT true FROM library_permissions
		WHERE user_id = $1 AND library_id = $2 AND permission = ANY($3)`,
		userID, libraryID, permissionsAtLeast(need)).Scan(&exists)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("bibliotheekrecht lezen: %w", err)
	}
	return exists, nil
}

// VisibleLibraries geeft de bibliotheken die userID mag zien (minimaal view),
// voor endpoints die over meerdere bibliotheken filteren (search, een hub
// zonder library_id, en GET /watch-state). nil betekent "geen beperking":
// owner en admin filteren niet. Een lege, niet-nil slice betekent dat
// member/restricted nul rechten heeft.
func (s *Store) VisibleLibraries(ctx context.Context, userID id.ID) ([]id.ID, error) {
	role, err := s.userRole(ctx, userID)
	if err != nil {
		return nil, err
	}
	if roleBypassesPermissions(role) {
		return nil, nil
	}

	rows, err := s.pool.Query(ctx,
		`SELECT library_id FROM library_permissions WHERE user_id = $1`, userID)
	if err != nil {
		return nil, fmt.Errorf("bibliotheekrechten lezen: %w", err)
	}
	defer rows.Close()

	ids := []id.ID{}
	for rows.Next() {
		var libraryID id.ID
		if err := rows.Scan(&libraryID); err != nil {
			return nil, err
		}
		ids = append(ids, libraryID)
	}
	return ids, rows.Err()
}

// ItemLibrary geeft de bibliotheek waar een item toe hoort, voor autorisatie
// vóór een kijkstatusevent wordt toegepast (AC2, PS-9, DEC-105 regel 12) —
// lichter dan Item(), die ook versies, artwork en aantallen ophaalt.
func (s *Store) ItemLibrary(ctx context.Context, itemID id.ID) (id.ID, error) {
	var libraryID id.ID
	err := s.pool.QueryRow(ctx,
		`SELECT library_id FROM media_items WHERE id = $1`, itemID).Scan(&libraryID)
	if errors.Is(err, pgx.ErrNoRows) {
		return id.Nil, ErrNotFound
	}
	if err != nil {
		return id.Nil, fmt.Errorf("item-bibliotheek lezen: %w", err)
	}
	return libraryID, nil
}
