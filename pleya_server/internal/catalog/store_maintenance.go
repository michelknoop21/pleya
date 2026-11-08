package catalog

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/jackc/pgx/v5"
)

// Bibliotheekonderhoud op verzoek van een beheerder: de prullenbak legen en de
// metadata van een hele bibliotheek opnieuw laten ophalen (DEC-XXX, voorstel
// bibliotheekonderhoud).
//
// De prullenbak is wat een scan als verdwenen aanmerkte en nog niet opruimde.
// PruneEmpty ruimt dat na elke volledige ronde zelf op; blijft een root
// onvolledig (een share die niet gemount is), dan slaat de scanner het
// opruimen voor de hele bibliotheek over, en dan blijven verdwenen titels op
// de andere roots staan. EmptyTrash is dat opruimen op verzoek, met dezelfde
// cascade als PruneEmpty: een verwijderd item neemt zijn kijkstatus,
// geschiedenis, favorieten, waarderingen, downloads en lijstregels mee.

// FileGone zegt of een bestand aantoonbaar weg is: de root staat er als map en
// het pad eronder bestaat niet. Een root die zelf niet te lezen is bewijst
// niets (een niet-gemounte share ziet eruit als een lege map of als niets), en
// een andere fout dan "bestaat niet" ook niet.
func FileGone(root, rel string) bool {
	if info, err := os.Stat(root); err != nil || !info.IsDir() {
		return false
	}
	_, err := os.Lstat(filepath.Join(root, filepath.FromSlash(rel)))
	return errors.Is(err, fs.ErrNotExist)
}

// trashedItemsSQL telt films en afleveringen waarvan elk mediabestand als
// verdwenen gemarkeerd staat: minstens één bestand, en geen enkel aanwezig.
const trashedItemsSQL = `
	SELECT count(*) FROM media_items i
	WHERE i.library_id = $1 AND i.kind IN ('movie', 'episode')
	  AND EXISTS (SELECT 1 FROM media_versions v
	              JOIN media_files f ON f.version_id = v.id AND f.role = 'media'
	              WHERE v.item_id = i.id)
	  AND NOT EXISTS (SELECT 1 FROM media_versions v
	                  JOIN media_files f ON f.version_id = v.id AND f.role = 'media' AND f.missing_since IS NULL
	                  WHERE v.item_id = i.id)`

// TrashedItemCount is het aantal titels in de prullenbak van een bibliotheek.
func (s *Store) TrashedItemCount(ctx context.Context, libraryID id.ID) (int64, error) {
	var n int64
	if err := s.pool.QueryRow(ctx, trashedItemsSQL, libraryID).Scan(&n); err != nil {
		return 0, fmt.Errorf("prullenbak tellen: %w", err)
	}
	return n, nil
}

// EmptyTrash verwijdert de versies van deze bibliotheek waarvan elk
// mediabestand als verdwenen gemarkeerd staat én volgens gone werkelijk weg
// is, daarna de films en afleveringen die zo zonder versie raakten, en de
// seizoenen en series die daardoor leeg werden. Een item met nog één aanwezig
// bestand blijft, en een versie waarvan één verdwenen bestand toch op schijf
// staat ook: dan loopt de markering achter en hoort de volgende scan haar weg
// te halen, niet deze opruiming. Het antwoord is het aantal verwijderde films
// en afleveringen.
//
// De aanroeper sluit een gelijktijdige scan van dezelfde bibliotheek uit (de
// job deelt de dedupe key van de scan): een scan maakt een item en zijn versie
// in twee stappen.
func (s *Store) EmptyTrash(ctx context.Context, libraryID id.ID, gone func(root, rel string) bool) (int64, error) {
	type missingFile struct {
		version   id.ID
		root, rel string
	}
	rows, err := s.pool.Query(ctx, `
		SELECT v.id, sl.root_path, f.relative_path
		FROM media_versions v
		JOIN media_items i ON i.id = v.item_id AND i.library_id = $1
		JOIN media_files f ON f.version_id = v.id AND f.role = 'media'
		JOIN storage_locations sl ON sl.id = f.storage_location_id
		WHERE NOT EXISTS (SELECT 1 FROM media_files p
		                  WHERE p.version_id = v.id AND p.role = 'media' AND p.missing_since IS NULL)`, libraryID)
	if err != nil {
		return 0, fmt.Errorf("prullenbak lezen: %w", err)
	}
	var files []missingFile
	for rows.Next() {
		var f missingFile
		if err := rows.Scan(&f.version, &f.root, &f.rel); err != nil {
			rows.Close()
			return 0, err
		}
		files = append(files, f)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}

	// Pas na het lezen naar de schijf: geen databaseverbinding vasthouden
	// tijdens bestandssysteemaanroepen op een trage share.
	allGone := map[id.ID]bool{}
	for _, f := range files {
		ok, seen := allGone[f.version]
		allGone[f.version] = (ok || !seen) && gone(f.root, f.rel)
	}
	var versions []id.ID
	for v, ok := range allGone {
		if ok {
			versions = append(versions, v)
		}
	}
	if len(versions) == 0 {
		return 0, nil
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// De voorwaarde opnieuw in de DELETE zelf: wat sinds het lezen terugkwam
	// blijft staan.
	items, err := collectIDs(ctx, tx, `
		DELETE FROM media_versions v USING media_items i
		WHERE v.id = ANY($2) AND i.id = v.item_id AND i.library_id = $1
		  AND NOT EXISTS (SELECT 1 FROM media_files p
		                  WHERE p.version_id = v.id AND p.role = 'media' AND p.missing_since IS NULL)
		RETURNING v.item_id`, libraryID, versions)
	if err != nil {
		return 0, fmt.Errorf("versies uit de prullenbak verwijderen: %w", err)
	}
	// coalesce: een film heeft geen ouder en geeft zijn eigen id terug, dat
	// hieronder nergens meer op past. Zo blijft de lijst zonder NULL.
	parents, err := collectIDs(ctx, tx, `
		DELETE FROM media_items i
		WHERE i.id = ANY($2) AND i.library_id = $1 AND i.kind IN ('movie', 'episode')
		  AND NOT EXISTS (SELECT 1 FROM media_versions v WHERE v.item_id = i.id)
		RETURNING coalesce(i.parent_id, i.id)`, libraryID, items)
	if err != nil {
		return 0, fmt.Errorf("titels uit de prullenbak verwijderen: %w", err)
	}
	// Een aflevering hangt onder een seizoen en dat onder een serie. Alleen
	// ouders van wat hier verdween komen in aanmerking, en alleen als ze leeg
	// zijn geworden.
	shows, err := collectIDs(ctx, tx, `
		DELETE FROM media_items s
		WHERE s.id = ANY($2) AND s.library_id = $1 AND s.kind = 'season'
		  AND NOT EXISTS (SELECT 1 FROM media_items c WHERE c.parent_id = s.id)
		RETURNING s.parent_id`, libraryID, parents)
	if err != nil {
		return 0, fmt.Errorf("lege seizoenen verwijderen: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		DELETE FROM media_items s
		WHERE s.id = ANY($2) AND s.library_id = $1 AND s.kind = 'show'
		  AND NOT EXISTS (SELECT 1 FROM media_items c WHERE c.parent_id = s.id)`,
		libraryID, append(shows, parents...)); err != nil {
		return 0, fmt.Errorf("lege series verwijderen: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return int64(len(parents)), nil
}

// collectIDs voert een statement uit dat één uuid-kolom teruggeeft.
func collectIDs(ctx context.Context, tx pgx.Tx, sql string, args ...any) ([]id.ID, error) {
	rows, err := tx.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowTo[id.ID])
}

// RequeueLibraryMetadata zet elke film en serie van deze bibliotheek meteen
// weer aan de beurt voor de metadataronde, zoals DropProviderArtwork dat voor
// één item doet. Een titel die een beheerder afwees (rejected) of die op een
// keuze wacht (ambiguous) blijft buiten: dat is een besluit, en de ronde zou
// het niet anders beslissen. Handmatige velden, locks en pins houdt de ronde
// zelf in stand. Het antwoord is het aantal titels dat aan de beurt is.
//
// updated_at loopt op zoals bij DropProviderArtwork, zodat een poging die al
// onderweg was als achterhaald geldt en de nieuwe ronde wint.
func (s *Store) RequeueLibraryMetadata(ctx context.Context, libraryID id.ID) (int64, error) {
	var n int64
	err := s.pool.QueryRow(ctx, `
		WITH due AS (
		    UPDATE media_items i SET sidecar_checked_at = NULL
		    WHERE i.library_id = $1 AND i.kind IN ('movie', 'show')
		      AND NOT EXISTS (SELECT 1 FROM metadata_candidates c
		                      WHERE c.item_id = i.id AND c.state IN ('rejected', 'ambiguous'))
		    RETURNING i.id
		), requeued AS (
		    UPDATE metadata_candidates c
		    SET next_attempt_at = now(),
		        updated_at = GREATEST(c.updated_at + interval '1 microsecond', clock_timestamp())
		    WHERE c.item_id IN (SELECT id FROM due) AND c.state IN ('matched', 'unmatched', 'failed')
		)
		SELECT count(*) FROM due`, libraryID).Scan(&n)
	if err != nil {
		return 0, fmt.Errorf("metadata opnieuw inplannen: %w", err)
	}
	return n, nil
}
