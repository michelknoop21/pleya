package backup

import (
	"archive/tar"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"
)

// De namen in de tar. Een back-up is een gewone tar, zodat een beheerder hem
// zonder Pleya kan openen: tar -xf, dan zcat database.sql.gz | psql.
const (
	entryManifest = "manifest.json"
	entryDump     = "database.sql.gz"
	entrySecrets  = "secrets.tar.enc"
	configPrefix  = "config/"

	// archiveFormat stijgt als de indeling verandert op een manier die een
	// oudere server niet kan lezen.
	archiveFormat = 1
)

// Counts zijn de kerngetallen die de hersteltest natelt.
type Counts struct {
	Titles      int64 `json:"titles"`
	Users       int64 `json:"users"`
	Libraries   int64 `json:"libraries"`
	WatchStates int64 `json:"watch_states"`
}

// Manifest beschrijft een back-up. Het staat als eerste in de tar.
type Manifest struct {
	Format        int       `json:"format"`
	ID            string    `json:"id"`
	CreatedAt     time.Time `json:"created_at"`
	Trigger       Trigger   `json:"trigger"`
	ServerVersion string    `json:"server_version"`
	SchemaVersion int       `json:"schema_version"`
	// Schema is het Postgres-schema waaruit gedumpt is (public in productie). De
	// dump maakt het zelf aan, dus terugzetten heeft de naam nodig.
	Schema string `json:"schema"`
	Counts Counts `json:"counts"`
	// Secrets staat er alleen als de geheimen versleuteld meegingen.
	Secrets *sealParams `json:"secrets,omitempty"`
	// SecretsOmitted telt de geheime bestanden die zonder sleutel wegbleven.
	SecretsOmitted int `json:"secrets_omitted"`
}

// configFile is één bestand uit /config.
type configFile struct {
	name string // relatief, met schuine strepen
	mode fs.FileMode
	data []byte
}

// isSecret zegt of een bestand uit /config geheim is: een sleutelbestand, of
// een bestand dat alleen de eigenaar mag lezen. De tweede regel is de ruime: een
// bestand dat iemand bewust op 0600 zette, hoort niet leesbaar in een back-up.
func isSecret(name string, mode fs.FileMode) bool {
	return strings.HasSuffix(name, ".key") || mode.Perm()&0o077 == 0
}

// readConfig leest de gewone bestanden uit dir, gesplitst in gewoon en geheim.
// Symlinks en andere niet-gewone bestanden gaan niet mee.
func readConfig(dir string) (plain, secret []configFile, err error) {
	err = filepath.WalkDir(dir, func(p string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if !d.Type().IsRegular() {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(dir, p)
		if err != nil {
			return err
		}
		data, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		f := configFile{name: filepath.ToSlash(rel), mode: info.Mode().Perm(), data: data}
		if isSecret(f.name, f.mode) {
			secret = append(secret, f)
		} else {
			plain = append(plain, f)
		}
		return nil
	})
	return plain, secret, err
}

// tarFiles zet bestanden in een tar in het geheugen. Voor de geheimen: die
// worden als één blok versleuteld, zodat ook hun namen en aantal niet leesbaar
// in de back-up staan.
func tarFiles(files []configFile) ([]byte, error) {
	var buf bytes.Buffer
	tw := tar.NewWriter(&buf)
	for _, f := range files {
		if err := writeEntry(tw, f.name, int64(f.mode), bytes.NewReader(f.data), int64(len(f.data))); err != nil {
			return nil, err
		}
	}
	if err := tw.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// untarFiles leest wat tarFiles maakte.
func untarFiles(raw []byte) ([]configFile, error) {
	var out []configFile
	tr := tar.NewReader(bytes.NewReader(raw))
	for {
		h, err := tr.Next()
		if errors.Is(err, io.EOF) {
			return out, nil
		}
		if err != nil {
			return nil, err
		}
		data, err := io.ReadAll(tr)
		if err != nil {
			return nil, err
		}
		out = append(out, configFile{name: h.Name, mode: fs.FileMode(h.Mode).Perm(), data: data})
	}
}

func writeEntry(tw *tar.Writer, name string, mode int64, r io.Reader, size int64) error {
	if err := tw.WriteHeader(&tar.Header{
		Name: name, Mode: mode, Size: size, ModTime: time.Now().UTC(), Typeflag: tar.TypeReg, Format: tar.FormatPAX,
	}); err != nil {
		return err
	}
	_, err := io.Copy(tw, r)
	return err
}

// writeArchive schrijft de tar naar w. De dump komt uit een tijdelijk bestand,
// want de tar wil de grootte van een onderdeel vóór de inhoud weten.
func writeArchive(w io.Writer, m Manifest, dumpPath string, plain []configFile, sealed []byte) error {
	tw := tar.NewWriter(w)
	raw, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	if err := writeEntry(tw, entryManifest, 0o600, bytes.NewReader(raw), int64(len(raw))); err != nil {
		return err
	}
	dump, err := os.Open(dumpPath)
	if err != nil {
		return err
	}
	defer dump.Close()
	info, err := dump.Stat()
	if err != nil {
		return err
	}
	if err := writeEntry(tw, entryDump, 0o600, dump, info.Size()); err != nil {
		return err
	}
	for _, f := range plain {
		if err := writeEntry(tw, configPrefix+f.name, int64(f.mode), bytes.NewReader(f.data), int64(len(f.data))); err != nil {
			return err
		}
	}
	if sealed != nil {
		if err := writeEntry(tw, entrySecrets, 0o600, bytes.NewReader(sealed), int64(len(sealed))); err != nil {
			return err
		}
	}
	return tw.Close()
}

// walkArchive loopt de tar langs en geeft elk onderdeel aan fn. Stopt fn met
// errStop, dan stopt het lezen zonder fout.
func walkArchive(file string, fn func(name string, h *tar.Header, r io.Reader) error) error {
	f, err := os.Open(file)
	if err != nil {
		return err
	}
	defer f.Close()
	tr := tar.NewReader(f)
	for {
		h, err := tr.Next()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("%w: de tar is onleesbaar: %v", ErrNotRestorable, err)
		}
		if err := fn(path.Clean(h.Name), h, tr); err != nil {
			if errors.Is(err, errStop) {
				return nil
			}
			return err
		}
	}
}

var errStop = errors.New("stop")

// readManifest leest het manifest, dat altijd het eerste onderdeel is.
func readManifest(file string) (Manifest, error) {
	var m Manifest
	found := false
	err := walkArchive(file, func(name string, _ *tar.Header, r io.Reader) error {
		if name != entryManifest {
			return fmt.Errorf("%w: het eerste onderdeel is %q en niet het manifest", ErrNotRestorable, name)
		}
		if err := json.NewDecoder(io.LimitReader(r, 1<<20)).Decode(&m); err != nil {
			return fmt.Errorf("%w: het manifest is onleesbaar: %v", ErrNotRestorable, err)
		}
		found = true
		return errStop
	})
	if err != nil {
		return m, err
	}
	if !found {
		return m, fmt.Errorf("%w: geen manifest", ErrNotRestorable)
	}
	if m.Format != archiveFormat {
		return m, fmt.Errorf("%w: indeling %d, deze server kent %d", ErrNotRestorable, m.Format, archiveFormat)
	}
	return m, nil
}

// archiveContents leest de config-bestanden en het versleutelde blok; de dump
// laat hij liggen, die wordt rechtstreeks uit de tar gestroomd.
func archiveContents(file string) (plain []configFile, sealed []byte, err error) {
	err = walkArchive(file, func(name string, h *tar.Header, r io.Reader) error {
		switch {
		case name == entrySecrets:
			sealed, err = io.ReadAll(io.LimitReader(r, 16<<20))
			return err
		case strings.HasPrefix(name, configPrefix):
			rel := strings.TrimPrefix(name, configPrefix)
			// Geen pad dat buiten /config uitkomt, ook niet uit een tar die iemand
			// met de hand in de map legde.
			if rel == "" || strings.HasPrefix(rel, "../") || path.IsAbs(rel) {
				return fmt.Errorf("%w: ongeldig pad %q", ErrNotRestorable, name)
			}
			data, err := io.ReadAll(io.LimitReader(r, 16<<20))
			if err != nil {
				return err
			}
			plain = append(plain, configFile{name: rel, mode: fs.FileMode(h.Mode).Perm(), data: data})
		}
		return nil
	})
	return plain, sealed, err
}

// withDump geeft fn de gzip-stroom van de dump.
func withDump(file string, fn func(r io.Reader) error) error {
	found := false
	err := walkArchive(file, func(name string, _ *tar.Header, r io.Reader) error {
		if name != entryDump {
			return nil
		}
		found = true
		if err := fn(r); err != nil {
			return err
		}
		return errStop
	})
	if err == nil && !found {
		return fmt.Errorf("%w: geen databasedump in de back-up", ErrNotRestorable)
	}
	return err
}
