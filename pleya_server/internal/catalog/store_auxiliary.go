package catalog

import (
	"context"
	"errors"
	"fmt"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/jackc/pgx/v5"
)

// ReconcileAuxiliary changes a catalog classification, never presence, byte
// identity, media role or an existing item/version/part binding.
func (s *Store) ReconcileAuxiliary(ctx context.Context, file id.ID, kind string) error {
	var library id.ID
	err := s.pool.QueryRow(ctx, `UPDATE media_files f SET auxiliary_kind=$2
		FROM storage_locations l WHERE f.storage_location_id=l.id
		AND f.id=$1 AND f.auxiliary_kind IS DISTINCT FROM $2
		RETURNING l.library_id`, file, nullString(kind)).Scan(&library)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	s.invalidateGenreGate(library)
	return nil
}

// ObserveAuxiliary refreshes a deliberately unprobed, unbound auxiliary file.
// Bound legacy files follow normal change detection and keep their bindings.
func (s *Store) ObserveAuxiliary(ctx context.Context, file id.ID, size, mtime int64, inode *int64, signature string) error {
	_, err := s.pool.Exec(ctx, `UPDATE media_files
		SET size_bytes=$2,mtime_unix=$3,inode=$4,scan_signature=$5
		WHERE id=$1 AND version_id IS NULL AND item_id IS NULL`,
		file, size, mtime, inode, nullString(signature))
	return err
}

// ordinaryItemSQL is only for discovery/navigation. Do not use it for explicit
// personal lists, history, by-ID access, downloads or physical retention.
// A mixed item/season/show remains ordinary when any live media is ordinary.
// Rows with no media retain the existing behavior (metadata-only test/imports).
// Reduce leaf/season/show owners once, so the outer query can hash the excluded
// set instead of rescanning all media per item. NULL owners cannot enter NOT IN.
// alias is a constant internal SQL alias, never request input.
func ordinaryItemSQL(alias string) string {
	return fmt.Sprintf(`%s.id NOT IN (
		SELECT scope.owner FROM media_files af
		JOIN media_versions av ON av.id=af.version_id
		JOIN media_items ae ON ae.id=av.item_id
		LEFT JOIN media_items ap ON ap.id=ae.parent_id
		CROSS JOIN LATERAL (VALUES (ae.id),(ae.parent_id),
			(CASE WHEN ae.kind='episode' THEN ap.parent_id END)) scope(owner)
		WHERE af.role='media' AND af.missing_since IS NULL AND scope.owner IS NOT NULL
		GROUP BY scope.owner HAVING bool_and(af.auxiliary_kind IS NOT NULL))`, alias)
}

// Keep complete stacked versions: dropping an auxiliary-looking part would
// change the playback sequence and duration. Only an entirely auxiliary version
// is omitted from ordinary catalog projections; explicit version routes stay.
const ordinaryVersionSQL = `NOT EXISTS (SELECT 1 FROM media_files af
	WHERE af.version_id=v.id AND af.role='media' AND af.missing_since IS NULL)
	OR EXISTS (SELECT 1 FROM media_files af WHERE af.version_id=v.id
	AND af.role='media' AND af.missing_since IS NULL AND af.auxiliary_kind IS NULL)`
