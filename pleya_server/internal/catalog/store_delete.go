package catalog

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/jackc/pgx/v5"
)

// Een titel met zijn bestanden verwijderen (DEC-XXX, media verwijderen).
//
// Standaard uit. De beheerder zet het aan met PLEYA_SERVER_ALLOW_MEDIA_DELETE
// en een mount zonder :ro, en de server meet bij het opstarten welke
// mediaroots werkelijk schrijfbaar zijn (WritableRoots). Alleen bestanden onder
// zo'n gemeten root gaan weg.
//
// Wat er gewist wordt is uitsluitend wat de catalogus aan het item en alles
// eronder heeft gehangen: de mediabestanden van elke versie, de losse
// ondertitels van die versies en de artwork van de items. Een bestand dat de
// scanner niet kende (een .nfo, een eigen notitie) blijft staan, en daarmee ook
// de map waarin het staat. De database volgt daarna hetzelfde pad als de
// prullenbak (pruneVersions): eerst de markering missing_since, dan de versies
// zonder aanwezig mediabestand, de titels zonder versie en de lege seizoenen en
// series.

// Redenen waarom een bestand bleef staan. Vaste codes, want ze staan in
// details van library.media_delete_incomplete.
const (
	DeleteReasonOutsideRoot = "outside_root"
	DeleteReasonSymlink     = "symlink"
	DeleteReasonNotAFile    = "not_a_file"
	DeleteReasonFailed      = "remove_failed"
	// DeleteReasonMediaKept: een mediabestand van dit item bleef staan, dus de
	// bijbestanden blijven er ook. Anders staat er een film zonder ondertitel
	// en poster in de bibliotheek.
	DeleteReasonMediaKept = "media_kept"
)

// ErrRootOverlap zegt dat de root van het item, met opgeloste symlinks,
// samenvalt met of overlapt met de root van een andere opslaglocatie. Dan kan
// een bestand van dit item ook bij een andere bibliotheek horen. Er is dan
// niets gewist.
var ErrRootOverlap = errors.New("root overlapt met een andere opslaglocatie; niets gewist")

// ErrRootReadOnly zegt dat een root van het item niet onder een gemeten
// schrijfbare mediaroot valt. Er is dan niets gewist.
var ErrRootReadOnly = errors.New("root valt niet onder een schrijfbare mediaroot; niets gewist")

// DeleteFile is één bestand dat bij een te verwijderen item hoort.
type DeleteFile struct {
	ID   id.ID
	Root string
	Rel  string
	Role string
	// Missing: de scanner had het bestand al als verdwenen gemarkeerd. Alleen
	// dan telt "bestaat niet" als gewist; anders kan het net zo goed een share
	// zijn die tussen de controle en het wissen wegviel.
	Missing bool
}

// ItemDeletion is wat er bij een item weg moet.
type ItemDeletion struct {
	LibraryID id.ID
	Versions  []id.ID
	Files     []DeleteFile
}

// FileFailure is een bestand dat bleef staan.
type FileFailure struct {
	ID     id.ID
	Rel    string
	Reason string
}

// ItemDeletionPlan leest de versies en bestanden van een item en alles eronder:
// bij een serie de seizoenen en afleveringen, bij een seizoen de afleveringen.
func (s *Store) ItemDeletionPlan(ctx context.Context, itemID id.ID) (ItemDeletion, error) {
	var plan ItemDeletion
	libraryID, err := s.ItemLibrary(ctx, itemID)
	if err != nil {
		return plan, err
	}
	plan.LibraryID = libraryID

	const tree = `WITH RECURSIVE tree AS (
		    SELECT id FROM media_items WHERE id = $1
		    UNION ALL
		    SELECT c.id FROM media_items c JOIN tree t ON c.parent_id = t.id)`
	rows, err := s.pool.Query(ctx, tree+`
		SELECT v.id FROM media_versions v WHERE v.item_id IN (SELECT id FROM tree)`, itemID)
	if err != nil {
		return plan, fmt.Errorf("versies lezen: %w", err)
	}
	if plan.Versions, err = pgx.CollectRows(rows, pgx.RowTo[id.ID]); err != nil {
		return plan, fmt.Errorf("versies lezen: %w", err)
	}

	rows, err = s.pool.Query(ctx, tree+`
		SELECT f.id, sl.root_path, f.relative_path, f.role, f.missing_since IS NOT NULL
		FROM media_files f JOIN storage_locations sl ON sl.id = f.storage_location_id
		WHERE f.version_id IN (SELECT v.id FROM media_versions v WHERE v.item_id IN (SELECT id FROM tree))
		   OR f.item_id IN (SELECT id FROM tree)
		ORDER BY f.relative_path`, itemID)
	if err != nil {
		return plan, fmt.Errorf("bestanden lezen: %w", err)
	}
	plan.Files, err = pgx.CollectRows(rows, func(row pgx.CollectableRow) (DeleteFile, error) {
		var f DeleteFile
		err := row.Scan(&f.ID, &f.Root, &f.Rel, &f.Role, &f.Missing)
		return f, err
	})
	if err != nil {
		return plan, fmt.Errorf("bestanden lezen: %w", err)
	}
	return plan, nil
}

// CheckDeleteRoots toetst vóór er iets gewist wordt elke root van het plan:
// niet te lezen of leeg is ErrTrashRootUnavailable (een share die niet gemount
// is), buiten de gemeten schrijfbare roots is ErrRootReadOnly, en een root die
// na het oplossen van symlinks samenvalt met of overlapt met een andere
// opslaglocatie is ErrRootOverlap. De tekstvergelijking bij het aanmaken van een
// bibliotheek ziet een symlink-root niet; deze controle wel. Daarnaast vergelijkt
// hij per bestand de mappen zelf (overlapOnDisk), zodat ook een andere root die
// via een tweede bind-mount van dezelfde NAS-map binnen deze root ligt opvalt.
func (s *Store) CheckDeleteRoots(ctx context.Context, files []DeleteFile, writable []string) error {
	seen := map[string]bool{}
	var roots []string
	for _, f := range files {
		if seen[f.Root] {
			continue
		}
		seen[f.Root] = true
		roots = append(roots, f.Root)
		if rootUnavailable(f.Root) {
			return fmt.Errorf("%w: %s", ErrTrashRootUnavailable, f.Root)
		}
		if !underWritable(f.Root, writable) {
			return fmt.Errorf("%w: %s", ErrRootReadOnly, f.Root)
		}
	}
	if len(roots) == 0 {
		return nil
	}
	rows, err := s.pool.Query(ctx, `SELECT DISTINCT root_path FROM storage_locations WHERE NOT (root_path = ANY($1))`, roots)
	if err != nil {
		return fmt.Errorf("andere roots lezen: %w", err)
	}
	others, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return fmt.Errorf("andere roots lezen: %w", err)
	}
	for _, root := range roots {
		mine, err := filepath.EvalSymlinks(root)
		if err != nil {
			return fmt.Errorf("%w: %s", ErrTrashRootUnavailable, root)
		}
		for _, other := range others {
			theirs, err := filepath.EvalSymlinks(other)
			if err != nil {
				// Een root die er nu niet is, kan ook niet overlappen.
				continue
			}
			if within(mine, theirs) || within(theirs, mine) {
				return fmt.Errorf("%w: %s en %s", ErrRootOverlap, root, other)
			}
		}
	}
	var otherDirs []fs.FileInfo
	for _, other := range others {
		if info, err := os.Stat(other); err == nil {
			otherDirs = append(otherDirs, info)
		}
	}
	checked := map[string]bool{}
	for _, f := range files {
		if overlapOnDisk(f.Root, f.Rel, otherDirs, checked) {
			return fmt.Errorf("%w: %s", ErrRootOverlap, f.Root)
		}
	}
	return nil
}

// overlapOnDisk zegt of de map van dit bestand, of een map erboven tot en met de
// root, dezelfde map is als een andere root: gemeten op apparaat en inode
// (os.SameFile), niet op het pad. Zo valt /films op als die een tweede
// bind-mount is van /media/films. Wat dit niet ziet: een root die zelf binnen
// een andere ligt terwijl de paden dat niet tonen (het item staat in /films en
// /media toont dezelfde NAS-map een niveau hoger), en dezelfde share die twee
// keer los over het netwerk gekoppeld is (andere apparaatnummers).
//
// checked onthoudt de mappen die al vergeleken zijn: de klim stopt daar, zodat
// een seizoen met twintig afleveringen één stat per unieke map kost.
func overlapOnDisk(root, rel string, others []fs.FileInfo, checked map[string]bool) bool {
	if len(others) == 0 || !filepath.IsLocal(filepath.FromSlash(rel)) {
		return false
	}
	root = filepath.Clean(root)
	for dir := filepath.Join(root, filepath.Dir(filepath.FromSlash(rel))); ; dir = filepath.Dir(dir) {
		if checked[dir] {
			return false
		}
		checked[dir] = true
		if info, err := os.Stat(dir); err == nil {
			for _, other := range others {
				if os.SameFile(info, other) {
					return true
				}
			}
		}
		if dir == root || filepath.Dir(dir) == dir {
			return false
		}
	}
}

// underWritable zegt of root, met opgeloste symlinks, binnen een van de
// gemeten schrijfbare roots ligt.
func underWritable(root string, writable []string) bool {
	resolved, err := filepath.EvalSymlinks(root)
	if err != nil {
		return false
	}
	for _, w := range writable {
		if within(resolved, w) {
			return true
		}
	}
	return false
}

// writableFor geeft de gemeten schrijfbare root waaronder resolved ligt.
func writableFor(resolved string, writable []string) (string, bool) {
	for _, w := range writable {
		if within(resolved, w) {
			return w, true
		}
	}
	return "", false
}

// within zegt of child gelijk is aan parent of eronder ligt. Beide zijn
// absolute, opgeloste paden.
func within(child, parent string) bool {
	rel, err := filepath.Rel(parent, child)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) && !filepath.IsAbs(rel)
}

// RemoveItemFiles wist de bestanden van het plan van schijf en geeft de ids
// van wat weg is en wat bleef staan. Een bestand dat er niet (meer) is telt
// alleen als gewist als de scanner het al als verdwenen had gemarkeerd.
//
// Elke bewerking loopt via os.Root: eerst de bij het opstarten gemeten
// schrijfbare root, daarbinnen de bibliotheekroot met Root.OpenRoot. Wordt de
// bibliotheekroot tussen de controle en het openen door een symlink naar buiten
// vervangen, dan weigert OpenRoot. Een symlink in een tussenliggende map komt
// evenmin buiten de root. Daarnaast eerst een expliciete controle op het
// opgeloste pad, zodat het antwoord outside_root zegt in plaats van een
// algemene fout. Een bestand dat zelf een symlink is wordt niet gewist, en het
// doel ervan ook niet.
//
// Mediabestanden eerst. Blijft er één staan, dan blijven alle ondertitels en
// artwork van het plan ook staan. Een map die door het wissen leeg raakt gaat
// mee, tot aan de bibliotheekroot; een map met nog iets erin blijft, en een
// symlink naar een map ook.
// afterPathCheck is een haak voor tests: hij loopt tussen de expliciete
// padcontrole en de bewerkingen via os.Root, precies het venster waarin een map
// door een symlink vervangen kan worden. Nil doet niets.
var afterPathCheck func(DeleteFile)

func RemoveItemFiles(files []DeleteFile, writable []string) (removed []id.ID, failed []FileFailure) {
	var opened []*os.Root
	defer func() {
		for _, r := range opened {
			_ = r.Close()
		}
	}()
	writableRoots := map[string]*os.Root{}
	libraryRoots := map[string]*os.Root{}
	// libraryRoot opent de bibliotheekroot binnen zijn gemeten schrijfbare root.
	libraryRoot := func(resolved string) (*os.Root, error) {
		if r := libraryRoots[resolved]; r != nil {
			return r, nil
		}
		w, ok := writableFor(resolved, writable)
		if !ok {
			return nil, ErrRootReadOnly
		}
		wr := writableRoots[w]
		if wr == nil {
			var err error
			if wr, err = os.OpenRoot(w); err != nil {
				return nil, err
			}
			opened = append(opened, wr)
			writableRoots[w] = wr
		}
		rel, err := filepath.Rel(w, resolved)
		if err != nil {
			return nil, err
		}
		r := wr
		if rel != "." {
			if r, err = wr.OpenRoot(rel); err != nil {
				return nil, err
			}
			opened = append(opened, r)
		}
		libraryRoots[resolved] = r
		return r, nil
	}
	emptied := map[*os.Root]map[string]bool{}

	remove := func(f DeleteFile) {
		fail := func(reason string) { failed = append(failed, FileFailure{ID: f.ID, Rel: f.Rel, Reason: reason}) }
		// Er niet (meer) is telt als gewist als de scanner het al gemarkeerd had,
		// of als de map van het bestand er is en gevuld is: dan wiste iets anders
		// het net. Een map die weg is of leeg (een share die binnen de root
		// gemount was en wegviel) bewijst niets, ook als de root zelf gevuld is.
		gone := func(dir string) {
			if f.Missing || (dir != "" && !rootUnavailable(dir)) {
				removed = append(removed, f.ID)
			} else {
				fail(DeleteReasonFailed)
			}
		}
		rel := filepath.FromSlash(f.Rel)
		if !filepath.IsLocal(rel) {
			fail(DeleteReasonOutsideRoot)
			return
		}
		rootPath, err := filepath.EvalSymlinks(f.Root)
		if err != nil {
			fail(DeleteReasonFailed)
			return
		}
		if _, ok := writableFor(rootPath, writable); !ok {
			fail(DeleteReasonOutsideRoot)
			return
		}
		dir, err := filepath.EvalSymlinks(filepath.Join(rootPath, filepath.Dir(rel)))
		if errors.Is(err, fs.ErrNotExist) {
			gone("")
			return
		}
		if err != nil {
			fail(DeleteReasonFailed)
			return
		}
		if !within(dir, rootPath) {
			fail(DeleteReasonOutsideRoot)
			return
		}
		if afterPathCheck != nil {
			afterPathCheck(f)
		}
		r, err := libraryRoot(rootPath)
		if err != nil {
			fail(DeleteReasonFailed)
			return
		}
		info, err := r.Lstat(rel)
		switch {
		case errors.Is(err, fs.ErrNotExist):
			gone(dir)
			return
		case err != nil:
			// os.Root weigert ook een pad dat sinds de controle naar buiten wijst.
			// Opnieuw meten zegt welke van de twee het is.
			if now, evalErr := filepath.EvalSymlinks(filepath.Join(rootPath, filepath.Dir(rel))); evalErr == nil && !within(now, rootPath) {
				fail(DeleteReasonOutsideRoot)
			} else {
				fail(DeleteReasonFailed)
			}
			return
		case info.Mode()&fs.ModeSymlink != 0:
			fail(DeleteReasonSymlink)
			return
		case !info.Mode().IsRegular():
			fail(DeleteReasonNotAFile)
			return
		}
		if err := r.Remove(rel); err != nil {
			fail(DeleteReasonFailed)
			return
		}
		removed = append(removed, f.ID)
		if emptied[r] == nil {
			emptied[r] = map[string]bool{}
		}
		emptied[r][path.Dir(filepath.ToSlash(rel))] = true
	}

	var sidecars []DeleteFile
	for _, f := range files {
		if f.Role == "media" {
			remove(f)
		} else {
			sidecars = append(sidecars, f)
		}
	}
	if len(failed) > 0 {
		for _, f := range sidecars {
			failed = append(failed, FileFailure{ID: f.ID, Rel: f.Rel, Reason: DeleteReasonMediaKept})
		}
	} else {
		for _, f := range sidecars {
			remove(f)
		}
	}

	// Lege mappen opruimen, diepste eerst. Alleen een echte map: een symlink
	// naar een map zou Remove anders zelf weghalen. Remove op een map die niet
	// leeg is faalt, en dan stopt de klim.
	for r, names := range emptied {
		list := make([]string, 0, len(names))
		for d := range names {
			list = append(list, d)
		}
		sort.Slice(list, func(i, j int) bool { return len(list[i]) > len(list[j]) })
		for _, d := range list {
			for ; d != "." && d != "/" && d != ""; d = path.Dir(d) {
				name := filepath.FromSlash(d)
				info, err := r.Lstat(name)
				if err != nil || !info.IsDir() {
					break
				}
				if r.Remove(name) != nil {
					break
				}
			}
		}
	}
	return removed, failed
}

// FinishItemDeletion zet de markering missing_since op de gewiste bestanden en
// ruimt daarna via pruneVersions de versies van het plan op waarvan geen
// mediabestand meer aanwezig is. Het antwoord is het aantal verwijderde films
// en afleveringen.
func (s *Store) FinishItemDeletion(ctx context.Context, libraryID id.ID, versions, removed []id.ID) (int64, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := tx.Exec(ctx,
		`UPDATE media_files SET missing_since = coalesce(missing_since, now()) WHERE id = ANY($1)`, removed); err != nil {
		return 0, fmt.Errorf("gewiste bestanden markeren: %w", err)
	}
	n, err := pruneVersions(ctx, tx, libraryID, versions)
	if err != nil {
		return 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return n, nil
}

// WritableRoots meet welke mediaroots werkelijk schrijfbaar zijn: een leeg
// tijdelijk bestand aanmaken en meteen weer wissen. Een :ro-mount faalt hier
// met EROFS. Het antwoord bevat de opgeloste paden.
func WritableRoots(dirs []string) (writable, readOnly []string) {
	for _, dir := range dirs {
		resolved, err := filepath.EvalSymlinks(dir)
		if err != nil {
			readOnly = append(readOnly, dir)
			continue
		}
		f, err := os.CreateTemp(resolved, ".pleya-schrijftoets-*")
		if err != nil {
			readOnly = append(readOnly, dir)
			continue
		}
		name := f.Name()
		_ = f.Close()
		if err := os.Remove(name); err != nil {
			readOnly = append(readOnly, dir)
			continue
		}
		writable = append(writable, resolved)
	}
	return writable, readOnly
}
