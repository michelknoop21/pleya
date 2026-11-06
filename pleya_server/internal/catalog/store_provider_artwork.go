package catalog

// Opslag van providerartwork in CacheDir en de lokale-artworkcheck van de ronde.

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// ProviderArtwork is een afbeelding in CacheDir.
type ProviderArtwork struct {
	ID         id.ID
	ItemID     id.ID
	Kind       string
	Provider   string
	SourceRef  string
	FileName   string
	SHA256     string
	Generation int64
}

// GetProviderArtwork leest de bestaande cacherij voor een item, soort en provider.
func (s *Store) GetProviderArtwork(ctx context.Context, itemID id.ID, kind, provider string) (ProviderArtwork, bool, error) {
	var a ProviderArtwork
	err := s.pool.QueryRow(ctx, `
		SELECT id, item_id, kind, provider, source_ref, file_name, sha256, generation
		FROM provider_artwork WHERE item_id = $1 AND kind = $2 AND provider = $3`,
		itemID, kind, provider).
		Scan(&a.ID, &a.ItemID, &a.Kind, &a.Provider, &a.SourceRef, &a.FileName, &a.SHA256, &a.Generation)
	if errors.Is(err, pgx.ErrNoRows) {
		return a, false, nil
	}
	return a, err == nil, err
}

// UpsertProviderArtwork legt een gecachede afbeelding vast. De aanroeper schreef
// het bestand al; het id blijft gelijk bij een vervanging en generation loopt op
// zodra de bytes anders zijn.
func (s *Store) UpsertProviderArtwork(ctx context.Context, a ProviderArtwork) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := lockMetadataItem(ctx, tx, a.ItemID); err != nil {
		return err
	}
	if err := upsertProviderArtwork(ctx, tx, a); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func upsertProviderArtwork(ctx context.Context, tx pgx.Tx, a ProviderArtwork) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO provider_artwork (id, item_id, kind, provider, source_ref, file_name, sha256)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (item_id, kind, provider) DO UPDATE SET
		    source_ref = EXCLUDED.source_ref,
		    file_name = EXCLUDED.file_name,
		    generation = CASE WHEN provider_artwork.sha256 = EXCLUDED.sha256
		                      THEN provider_artwork.generation
		                      ELSE provider_artwork.generation + 1 END,
		    sha256 = EXCLUDED.sha256,
		    updated_at = now()`,
		a.ID, a.ItemID, a.Kind, a.Provider, a.SourceRef, a.FileName, a.SHA256)
	if err != nil {
		return fmt.Errorf("providerartwork opslaan: %w", err)
	}
	return nil
}

// LocalArtwork zegt of er naast de media al een poster of backdrop staat. Dan
// haalt een provider er geen op: de sidecar wint (RB-27).
func (s *Store) LocalArtwork(ctx context.Context, itemID id.ID) (poster, backdrop bool, err error) {
	err = s.pool.QueryRow(ctx, `
		SELECT coalesce(bool_or(artwork_kind = 'poster'), false),
		       coalesce(bool_or(artwork_kind = 'backdrop'), false)
		FROM media_files WHERE item_id = $1 AND role = 'artwork' AND missing_since IS NULL`, itemID).
		Scan(&poster, &backdrop)
	return poster, backdrop, err
}

// ProviderArtworkFile zoekt een gecachede afbeelding op id. cacheDir komt van de
// aanroeper, want de store kent de configuratie niet.
func (s *Store) ProviderArtworkFile(ctx context.Context, artworkID id.ID, cacheDir string) (FileOnDisk, id.ID, error) {
	var f FileOnDisk
	var libraryID id.ID
	var name string
	err := s.pool.QueryRow(ctx, `
		SELECT a.id, a.file_name, a.generation, i.library_id, a.kind
		FROM provider_artwork a JOIN media_items i ON i.id = a.item_id
		WHERE a.id = $1`, artworkID).Scan(&f.ID, &name, &f.Generation, &libraryID, &f.Kind)
	if errors.Is(err, pgx.ErrNoRows) {
		return f, id.Nil, ErrNotFound
	}
	if err != nil {
		return f, id.Nil, err
	}
	f.AbsPath = cacheDir + "/artwork/" + name
	f.Role = RoleArtwork
	return f, libraryID, nil
}

// ListProviderArtwork geeft alle gecachede afbeeldingen, voor het opruimen.
func (s *Store) ListProviderArtwork(ctx context.Context) ([]ProviderArtwork, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, item_id, kind, provider, source_ref, file_name, sha256, generation FROM provider_artwork`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ProviderArtwork
	for rows.Next() {
		var a ProviderArtwork
		if err := rows.Scan(&a.ID, &a.ItemID, &a.Kind, &a.Provider, &a.SourceRef, &a.FileName, &a.SHA256, &a.Generation); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// DropProviderArtwork verwijdert de cacherij van een afbeelding waarvan het
// bestand weg is en zet het item meteen weer aan de beurt, zodat de volgende
// ronde hem opnieuw ophaalt.
func (s *Store) DropProviderArtwork(ctx context.Context, artworkID id.ID) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var itemID id.ID
	if err := tx.QueryRow(ctx, `SELECT item_id FROM provider_artwork WHERE id = $1`, artworkID).Scan(&itemID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		return err
	}
	if err := lockMetadataItem(ctx, tx, itemID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `DELETE FROM provider_artwork WHERE id = $1`, artworkID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `
		UPDATE metadata_candidates SET next_attempt_at = now(), updated_at = GREATEST(updated_at + interval '1 microsecond', clock_timestamp())
		WHERE state = 'matched' AND item_id IN (
		    SELECT $1::uuid
		    -- Een afleveringsstill hoort bij de match van haar serie.
		    UNION SELECT se.parent_id FROM media_items e JOIN media_items se ON se.id = e.parent_id
		    WHERE e.id = $1 AND e.kind = 'episode')`, itemID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// localArtworkRankSQL ordent de lokale afbeeldingen van één rol: poster.jpg (ook
// "<naam>-poster.jpg") gaat voor cover.jpg, en die voor folder.jpg en de rest.
// Zonder rang won alleen de padvolgorde, en dan sorteert een "banner.jpg" of een
// kleine "folder.jpg" vóór de echte "poster.jpg". Een seizoensposter in de
// seriemap ("season01-poster.jpg") gaat achteraan: hij is niet de serie.
func localArtworkRankSQL(alias string) string {
	return fmt.Sprintf(`CASE WHEN lower(%[1]s.relative_path) ~ '(^|/)season[^/]*$' THEN 3
	    WHEN lower(%[1]s.relative_path) ~ '(^|[/.-])poster\.[a-z0-9]+$' THEN 0
	    WHEN lower(%[1]s.relative_path) ~ '(^|[/.-])cover\.[a-z0-9]+$' THEN 1 ELSE 2 END`, alias)
}

// CandidateAttempts geeft het aantal pogingen dat voor een item is vastgelegd.
func (s *Store) CandidateAttempts(ctx context.Context, itemID id.ID) (int, error) {
	var n int
	err := s.pool.QueryRow(ctx, `SELECT attempts FROM metadata_candidates WHERE item_id = $1`, itemID).Scan(&n)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil
	}
	return n, err
}
