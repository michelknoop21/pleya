// Package mounts inspecteert de mediamounts en de schrijfbare mappen.
//
// Dit levert de metingen waar PS-0 om draait. Of een mount werkelijk read-only
// is blijkt uit het bestandssysteem zelf en niet uit wat er in compose.yaml
// staat, en het type bestandssysteem is de enige aanwijzing vooraf of de
// aanname van de scanner over stabiele inodes daar straks houdt.
package mounts

import (
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
)

// Info beschrijft één pad.
type Info struct {
	Path      string
	Exists    bool
	IsDir     bool
	Readable  bool
	Writable  bool
	ReadOnly  bool   // het bestandssysteem is read-only gemount
	FSType    string // btrfs, ext4, fuseblk, overlay, ...
	FreeBytes uint64
	Err       string
}

// LogValue laat slog het geheel als één gestructureerd veld opnemen.
func (i Info) LogValue() slog.Value {
	attrs := []slog.Attr{
		slog.String("path", i.Path),
		slog.Bool("exists", i.Exists),
	}
	if i.Exists {
		attrs = append(attrs,
			slog.Bool("readable", i.Readable),
			slog.Bool("writable", i.Writable),
			slog.Bool("mounted_read_only", i.ReadOnly),
			slog.String("fstype", i.FSType),
			slog.Uint64("free_bytes", i.FreeBytes),
		)
	}
	if i.Err != "" {
		attrs = append(attrs, slog.String("error", i.Err))
	}
	return slog.GroupValue(attrs...)
}

// Inspect meet één pad. Het geeft nooit een fout terug: een onbereikbare
// mediamount is een bevinding om te loggen, niet een reden om niet te starten.
func Inspect(path string) Info {
	info := Info{Path: path}

	st, err := os.Stat(path)
	if err != nil {
		info.Err = err.Error()
		return info
	}
	info.Exists = true
	info.IsDir = st.IsDir()

	info.Readable = canRead(path, info.IsDir)
	info.Writable = canWrite(path)

	if fsType, readOnly, free, err := statfs(path); err != nil {
		info.Err = err.Error()
	} else {
		info.FSType = fsType
		info.ReadOnly = readOnly
		info.FreeBytes = free
	}

	return info
}

func canRead(path string, isDir bool) bool {
	if isDir {
		f, err := os.Open(path)
		if err != nil {
			return false
		}
		defer f.Close()
		_, err = f.ReadDir(1)
		return err == nil || errors.Is(err, fs.ErrNotExist) || err.Error() == "EOF"
	}
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	_ = f.Close()
	return true
}

// canWrite probeert werkelijk te schrijven. Rechten uitrekenen uit de modus
// klopt niet op een read-only mount en niet op een FUSE-bestandssysteem dat
// zijn eigen rechten verzint.
func canWrite(dir string) bool {
	f, err := os.CreateTemp(dir, ".pleya-write-probe-*")
	if err != nil {
		return false
	}
	name := f.Name()
	_ = f.Close()
	_ = os.Remove(name)
	return true
}

// EnsureDir maakt een schrijfbare map aan als hij ontbreekt.
func EnsureDir(path string) error {
	if err := os.MkdirAll(path, 0o755); err != nil {
		return fmt.Errorf("map %s aanmaken mislukt: %w", filepath.Clean(path), err)
	}
	return nil
}
