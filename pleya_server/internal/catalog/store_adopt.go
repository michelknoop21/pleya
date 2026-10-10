package catalog

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// De overname van S2.5 (J.3 venster 2): een bibliotheek uit
// PLEYA_SERVER_LIBRARIES gaat over naar beheer via de API, met dezelfde id en
// slug. Er wordt niets gekopieerd of opnieuw aangemaakt: alleen managed
// wisselt, dus items, kijkstatus en scanrondes hangen er na afloop nog precies
// zo aan als ervoor. De keerzijde staat in SyncLibraries: daar laat de
// config-sync een 'db'-rij met dezelfde slug voortaan met rust, anders draaide
// de eerstvolgende herstart de overname stilzwijgend terug.

// ErrNotConfigManaged betekent dat de bibliotheek al via de API beheerd wordt;
// er valt niets over te nemen.
var ErrNotConfigManaged = errors.New("de bibliotheek wordt al via de API beheerd")

// AdoptLibrary zet een config-beheerde bibliotheek om naar managed 'db'.
//
// De voorwaarde staat in de UPDATE zelf en niet in een losse SELECT ervoor:
// twee gelijktijdige overnames kunnen dan niet allebei slagen, de tweede raakt
// nul rijen en krijgt ErrNotConfigManaged.
func (s *Store) AdoptLibrary(ctx context.Context, libraryID id.ID) (Library, error) {
	var lib Library
	err := s.pool.QueryRow(ctx, `
		UPDATE libraries SET managed = 'db', updated_at = now()
		WHERE id = $1 AND managed = 'config'
		RETURNING id, slug, title, kind, managed, scan_interval_seconds, scan_on_start,
		          (SELECT count(*) FROM media_items i
		            WHERE i.library_id = libraries.id AND i.kind IN ('movie', 'show'))`,
		libraryID).
		Scan(&lib.ID, &lib.Slug, &lib.Title, &lib.Kind, &lib.Managed,
			&lib.ScanIntervalSeconds, &lib.ScanOnStart, &lib.ItemCount)
	if err == nil {
		return lib, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return Library{}, fmt.Errorf("bibliotheek overnemen: %w", err)
	}

	// Nul rijen: de bibliotheek bestaat niet, of ze is al 'db'.
	if _, err := s.Library(ctx, libraryID); err != nil {
		return Library{}, err
	}
	return Library{}, ErrNotConfigManaged
}
