package scanner

import (
	"context"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/nameparse"
)

// Entry is één bestand zoals de wandeling het aantrof.
type Entry struct {
	RelPath string
	Dir     string
	Base    string // bestandsnaam zonder extensie
	Kind    nameparse.Kind
	Size    int64
	Mtime   int64
	Inode   int64 // 0 betekent: het bestandssysteem gaf er geen
}

// skipDirs zijn mappen die geen bibliotheek-inhoud dragen. Een scanner die hier
// wel doorheen loopt vindt de miniaturen en de prullenbak van een NAS terug als
// bibliotheekitems.
var skipDirs = map[string]bool{
	"@eadir":                    true,
	"#recycle":                  true,
	"#snapshot":                 true,
	".@__thumb":                 true,
	"lost+found":                true,
	".ds_store":                 true,
	"$recycle.bin":              true,
	"system volume information": true,
}

// Walk loopt één root af en geeft elk bruikbaar bestand terug.
//
// Fouten op losse mappen zijn geen scanfout: een map waar deze uid niet in mag
// hoort gemeld te worden, niet de hele ronde af te breken. Een fout op de root
// zelf is dat wel, want dan is er niets gescand en zou alles verdwenen lijken.
func Walk(ctx context.Context, root string, onEntry func(Entry) error, onProblem func(path string, err error)) error {
	if _, err := os.Stat(root); err != nil {
		return err
	}

	return filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if err != nil {
			if onProblem != nil {
				onProblem(path, err)
			}
			if d != nil && d.IsDir() {
				return fs.SkipDir
			}
			return nil
		}

		name := d.Name()
		if d.IsDir() {
			if path != root && (skipDirs[strings.ToLower(name)] || strings.HasPrefix(name, ".")) {
				return fs.SkipDir
			}
			return nil
		}
		if strings.HasPrefix(name, ".") || strings.HasPrefix(name, "._") {
			return nil
		}

		kind := nameparse.Classify(name)
		if kind == nameparse.KindOther {
			return nil
		}

		info, statErr := d.Info()
		if statErr != nil {
			if onProblem != nil {
				onProblem(path, statErr)
			}
			return nil
		}

		rel, relErr := filepath.Rel(root, path)
		if relErr != nil {
			return nil
		}
		rel = filepath.ToSlash(rel)

		entry := Entry{
			RelPath: rel,
			Dir:     filepath.ToSlash(filepath.Dir(rel)),
			Base:    strings.TrimSuffix(name, filepath.Ext(name)),
			Kind:    kind,
			Size:    info.Size(),
			Mtime:   info.ModTime().Unix(),
			Inode:   inodeOf(info),
		}
		if entry.Dir == "." {
			entry.Dir = ""
		}
		return onEntry(entry)
	})
}
