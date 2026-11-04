package catalog

import (
	"context"
	"errors"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/jackc/pgx/v5"
)

const (
	MetadataApplicationUnknown = "unknown"
	MetadataApplicationPending = "pending"
	MetadataApplicationApplied = "applied"
	MetadataApplicationFailed  = "failed"
	// MetadataApplicationErrorFailed is een vaste categorie; nooit providertekst.
	MetadataApplicationErrorFailed = "application_failed"
)

// MetadataApplication leest intentie en publicatiebewijs uit één MVCC-rij.
// UpdatedAt is de bestaande strikt monotone kandidaatgeneratie; nil zonder kandidaat.
// De pointerparen zijn beide nil of beide aanwezig. Dit is geen wire-type.
type MetadataApplication struct {
	RequestedProvider   *string
	RequestedExternalID *string
	AppliedProvider     *string
	AppliedExternalID   *string
	State               string
	ErrorCode           *string
	UpdatedAt           *time.Time
}

// MetadataMatchStatus accepteert alleen bestaande films/series. Zonder kandidaat
// is de toestand unknown; een seizoen/aflevering/ontbrekend item is ErrNotFound.
func (s *Store) MetadataMatchStatus(ctx context.Context, itemID id.ID) (MetadataApplication, error) {
	var status MetadataApplication
	err := s.pool.QueryRow(ctx, `SELECT
    CASE WHEN c.external_id IS NOT NULL THEN c.provider END, c.external_id,
    c.applied_provider, c.applied_external_id,
    coalesce(c.application_state,'unknown'), c.application_error_code, c.updated_at
    FROM media_items i LEFT JOIN metadata_candidates c ON c.item_id=i.id
    WHERE i.id=$1 AND i.kind IN ('movie','show')`, itemID).Scan(
		&status.RequestedProvider, &status.RequestedExternalID, &status.AppliedProvider,
		&status.AppliedExternalID, &status.State, &status.ErrorCode, &status.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return MetadataApplication{}, ErrNotFound
	}
	return status, err
}

// publishMetadataApplication draait uitsluitend ná alle publicatiestappen onder
// de itemlock/generatieguard. saveCandidate op zichzelf levert geen bewijs.
func publishMetadataApplication(ctx context.Context, tx pgx.Tx, c MetadataCandidate, details *MetadataDetails) error {
	if details != nil && c.State == CandidateMatched && c.Provider != "" && c.ExternalID != "" {
		if err := touchAppliedIdentity(ctx, tx, c.ItemID, c.Provider, c.ExternalID); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE metadata_candidates SET applied_provider=$2,
        applied_external_id=$3,application_state='applied',application_error_code=NULL
        WHERE item_id=$1`, c.ItemID, c.Provider, c.ExternalID)
		return err
	}
	if c.State == CandidateFailed {
		_, err := tx.Exec(ctx, `UPDATE metadata_candidates SET application_state='failed',
        application_error_code='application_failed' WHERE item_id=$1`, c.ItemID)
		return err
	}
	return nil
}

// touchAppliedIdentity geeft bestaande caches ook een wijziging bij gelijke
// beschrijvende waarden. De klok mag de itemrepresentatie nooit terugzetten.
func touchAppliedIdentity(ctx context.Context, tx pgx.Tx, itemID id.ID, provider, externalID string) error {
	_, err := tx.Exec(ctx, `UPDATE media_items SET
    updated_at=GREATEST(updated_at + interval '1 microsecond',clock_timestamp())
    WHERE id=$1 AND EXISTS (SELECT 1 FROM metadata_candidates c WHERE c.item_id=$1
      AND (c.applied_provider IS DISTINCT FROM NULLIF($2,'')
        OR c.applied_external_id IS DISTINCT FROM NULLIF($3,'')))`, itemID, provider, externalID)
	return err
}
