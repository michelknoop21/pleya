package catalog

import (
	"context"
	"fmt"
)

// StorageLocationWithLibrary is één geclaimde root plus de bibliotheek die hem
// bezit, voor GET /storage/roots (S2.3, J.3 venster 2).
//
// root_path is server-breed uniek (0002_catalog.sql), dus dit is vandaag
// altijd een 1:1-relatie; het wire-antwoord draagt libraries als lijst omdat
// het schema dat zo vastlegt en niet omdat er meer dan één kan zijn.
type StorageLocationWithLibrary struct {
	StorageLocation
	LibraryTitle string
}

// AllStorageLocations geeft elke geclaimde root, over alle bibliotheken heen.
//
// Dit is de tegenhanger van StorageLocations (die filtert op één bibliotheek):
// GET /storage/roots en de rechecktaak hebben de volledige lijst nodig, niet
// de lijst van één bibliotheek.
func (s *Store) AllStorageLocations(ctx context.Context) ([]StorageLocationWithLibrary, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT l.id, l.library_id, l.root_path, coalesce(l.fs_type, ''), l.inode_trusted, l.inode_trust_source,
		       lib.title
		FROM storage_locations l
		JOIN libraries lib ON lib.id = l.library_id
		ORDER BY l.root_path`)
	if err != nil {
		return nil, fmt.Errorf("geclaimde roots lezen: %w", err)
	}
	defer rows.Close()

	var out []StorageLocationWithLibrary
	for rows.Next() {
		var loc StorageLocationWithLibrary
		if err := rows.Scan(&loc.ID, &loc.LibraryID, &loc.RootPath, &loc.FSType,
			&loc.InodeTrusted, &loc.TrustSource, &loc.LibraryTitle); err != nil {
			return nil, err
		}
		out = append(out, loc)
	}
	return out, rows.Err()
}

// UpdateStorageLocationMeasurement schrijft een verse meting van een geclaimde
// root weg (S2.3, POST /storage/roots/recheck).
//
// Een root_path die intussen niet meer bestaat (de bibliotheek is in de
// tussentijd verwijderd) raakt 0 rijen en is geen fout: de rechecktaak loopt
// over een momentopname en een race met een DELETE is geen storingsgeval.
func (s *Store) UpdateStorageLocationMeasurement(ctx context.Context, rootPath, fsType string, inodeTrusted bool, trustSource string) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE storage_locations
		SET fs_type = $2, inode_trusted = $3, inode_trust_source = $4, last_seen_at = now()
		WHERE root_path = $1`, rootPath, nullString(fsType), inodeTrusted, trustSource)
	if err != nil {
		return fmt.Errorf("meting van root %s vastleggen: %w", rootPath, err)
	}
	return nil
}
