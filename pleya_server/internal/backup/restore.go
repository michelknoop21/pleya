package backup

import (
	"compress/gzip"
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
)

// Confirmation is de tekst die een beheerder letterlijk moet terugsturen om een
// back-up terug te zetten (S25.3, RB-26).
//
// De tekst noemt wat er verloren gaat, en dat is de reden dat hij geen los
// woord is zoals "rotate": een restore gooit alles weg wat na het tijdstip van
// de back-up gebeurde, en wie dat tijdstip heeft moeten overtypen weet welke
// back-up hij koos.
func Confirmation(rec Record) string {
	return fmt.Sprintf("herstel %s: kijkstatus, gebruikers, sessies, instellingen en scans van daarna gaan verloren",
		rec.StartedAt.UTC().Format(time.RFC3339))
}

// Plan is een gecontroleerde restore: alles wat vóór de onderhoudsmodus te
// toetsen valt, is getoetst.
type Plan struct {
	Record   Record
	file     string
	manifest Manifest
	plain    []configFile
	secrets  []configFile
}

// PrepareRestore toetst een back-up zonder iets te wijzigen: hij bestaat, is
// geslaagd, het bestand is leesbaar, het schema is niet nieuwer dan deze binary,
// en de geheimen gaan open. Een restore die pas halverwege ontdekt dat de
// sleutel niet past, heeft de server dan al in onderhoud gezet voor niets.
func (s *Service) PrepareRestore(ctx context.Context, backupID id.ID) (Plan, error) {
	rec, err := s.Get(ctx, backupID)
	if err != nil {
		return Plan{}, err
	}
	if rec.Status != StatusOK || rec.FileName == "" {
		return Plan{}, fmt.Errorf("%w: %w: de back-up staat op %s", ErrNotRestorable, ErrNotOK, rec.Status)
	}
	p := Plan{Record: rec, file: filepath.Join(s.o.Dir, filepath.Base(rec.FileName))}
	if p.manifest, err = readManifest(p.file); err != nil {
		return Plan{}, err
	}
	target, err := migrate.Target()
	if err != nil {
		return Plan{}, err
	}
	if p.manifest.SchemaVersion > target {
		return Plan{}, fmt.Errorf("%w: %w: de back-up heeft schema %d, deze binary %d", ErrNotRestorable, ErrSchemaNewer, p.manifest.SchemaVersion, target)
	}
	var sealed []byte
	if p.plain, sealed, err = archiveContents(p.file); err != nil {
		return Plan{}, err
	}
	if p.manifest.Secrets != nil {
		if s.o.Key == "" {
			return Plan{}, fmt.Errorf("%w: de geheimen zijn versleuteld en PLEYA_SERVER_BACKUP_KEY is leeg", ErrWrongKey)
		}
		inner, err := unseal(s.o.Key, sealed, *p.manifest.Secrets)
		if err != nil {
			return Plan{}, err
		}
		if p.secrets, err = untarFiles(inner); err != nil {
			return Plan{}, err
		}
	}
	return p, nil
}

// Restore zet een voorbereide back-up terug in de echte database en in /config.
// De aanroeper zet de server vooraf in onderhoud en herstart hem daarna; de
// database is na de laatste regel van een andere tijd dan het proces dat hem
// nog in het geheugen heeft.
func (s *Service) Restore(ctx context.Context, p Plan) error {
	s.log.Warn("restore begint", "backup", p.Record.ID.String(), "file", filepath.Base(p.file))
	if err := withDump(p.file, func(r io.Reader) error {
		zr, err := gzip.NewReader(r)
		if err != nil {
			return fmt.Errorf("%w: de dump is geen gzip: %v", ErrNotRestorable, err)
		}
		return s.load(ctx, s.liveDatabase(), p.manifest.Schema, zr)
	}); err != nil {
		return err
	}
	// Daarna pas de bestanden. Faalt de database, dan blijft /config zoals hij
	// was; andersom zou een oude sleutel naast een nieuwe database staan.
	for _, f := range append(append([]configFile{}, p.plain...), p.secrets...) {
		if err := writeConfigFile(s.o.ConfigDir, f); err != nil {
			return fmt.Errorf("database teruggezet, /config niet: %w", err)
		}
	}
	s.log.Warn("restore klaar", "backup", p.Record.ID.String())
	return nil
}

// writeConfigFile schrijft één bestand atomair terug: eerst naast het doel,
// dan hernoemen. Een geheim krijgt 0600, ongeacht wat er in de tar stond.
func writeConfigFile(dir string, f configFile) error {
	rel := filepath.FromSlash(f.name)
	if strings.HasPrefix(filepath.Clean(rel), "..") || filepath.IsAbs(rel) {
		return fmt.Errorf("ongeldig pad %q", f.name)
	}
	target := filepath.Join(dir, rel)
	if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
		return err
	}
	mode := f.mode
	if isSecret(f.name, f.mode) {
		mode = 0o600
	}
	tmp := target + ".restore"
	if err := os.WriteFile(tmp, f.data, mode); err != nil {
		return err
	}
	if err := os.Chmod(tmp, mode); err != nil {
		return err
	}
	return os.Rename(tmp, target)
}
