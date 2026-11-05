package catalog

// Bewaakte publicatie van een voorbereide providerpoging.

import (
	"context"
	"errors"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// ErrMetadataSuperseded betekent dat de gelezen poging door een nieuwere keuze
// of ronde is ingehaald. De aanroeper gooit uitsluitend zijn eigen staged bytes weg.
var ErrMetadataSuperseded = errors.New("metadata-poging ingehaald")

func lockMetadataItem(ctx context.Context, tx pgx.Tx, itemID id.ID) error {
	var found id.ID
	err := tx.QueryRow(ctx, `SELECT id FROM media_items WHERE id = $1 FOR UPDATE`, itemID).Scan(&found)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	return err
}

// CommitMetadata publiceert één voorbereide poging onder dezelfde generatie voor
// velden, kandidaat en artwork. Alleen DB-werk onder de itemlock; alle provider-I/O
// en nieuwe bestanden zijn vooraf voorbereid. updated_at loopt bij iedere
// kandidaatwrite minstens één microseconde op, ook bij dezelfde keuze of klokterugloop.
func (s *Store) CommitMetadata(ctx context.Context, target MetadataTarget, c MetadataCandidate, details, sidecar *MetadataDetails, artwork []ProviderArtwork) error {
	if c.ItemID != target.ID {
		return errors.New("metadata-publicatie hoort niet bij het gelockte item")
	}
	for _, a := range artwork {
		if a.ItemID != target.ID {
			return errors.New("metadata-artwork hoort niet bij het gelockte item")
		}
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := lockMetadataItem(ctx, tx, target.ID); err != nil {
		return err
	}
	var actual time.Time
	err = tx.QueryRow(ctx, `SELECT updated_at FROM metadata_candidates WHERE item_id = $1`, target.ID).Scan(&actual)
	if errors.Is(err, pgx.ErrNoRows) {
		if target.CandidateUpdatedAt != nil {
			return ErrMetadataSuperseded
		}
	} else if err != nil {
		return err
	} else if target.CandidateUpdatedAt == nil || !actual.Equal(*target.CandidateUpdatedAt) {
		return ErrMetadataSuperseded
	}
	if target.SidecarReadError != nil || c.State == CandidateFailed {
		if _, err := tx.Exec(ctx, `UPDATE media_items SET metadata_nfo_safe=false WHERE id=$1`, target.ID); err != nil {
			return err
		}
	} else if sidecar == nil {
		if err := rememberMetadataLayer(ctx, tx, target.ID, SourceNFO, MetadataDetails{}); err != nil {
			return err
		}
	}
	if details != nil {
		if err := clearMissingProviderFields(ctx, tx, target, c.Provider, *details); err != nil {
			return err
		}
		if err := applyMetadata(ctx, tx, target.ID, c.Provider, *details); err != nil {
			return err
		}
	}
	if sidecar != nil {
		if err := applyMetadata(ctx, tx, target.ID, SourceNFO, *sidecar); err != nil {
			return err
		}
	}
	for _, a := range artwork {
		if err := upsertProviderArtwork(ctx, tx, a); err != nil {
			return err
		}
	}
	if details != nil {
		if err := reconcileProviderArtwork(ctx, tx, target.ID, c.Provider, *details); err != nil {
			return err
		}
	}
	if err := saveCandidate(ctx, tx, c); err != nil {
		return err
	}
	if err := publishMetadataApplication(ctx, tx, c, details); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// canonicalMetadataID voorkomt dat beschadigde toegepaste IDs bewijs worden.
func canonicalMetadataID(raw string) bool {
	n, err := strconv.Atoi(raw)
	return err == nil && n > 0 && strconv.Itoa(n) == raw
}
