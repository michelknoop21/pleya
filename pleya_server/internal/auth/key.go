package auth

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// KeyFileName is de plek van de ondertekensleutel binnen de configmap.
const KeyFileName = "token-signing.key"

// KeyLength is 32 bytes: de blokgrootte van SHA-256, waar HMAC precies mee uit
// de voeten kan zonder de sleutel eerst te hashen.
const KeyLength = 32

// LoadOrCreateSigningKey leest de ondertekensleutel uit de persistente configmap
// en maakt hem aan als hij er niet is.
//
// De sleutel leeft alleen op schijf, met restrictieve rechten, en dus niet in
// Postgres en niet in Git (specificatie 6.5, eigenschap 4). Een sleutel die
// naast de data ligt die hij beschermt scheidt niets: een databasedump mag geen
// sessies opleveren, en dat is precies wat deze regel koopt.
func LoadOrCreateSigningKey(configDir string) (key []byte, created bool, err error) {
	path := filepath.Join(configDir, KeyFileName)

	raw, err := os.ReadFile(path)
	switch {
	case err == nil:
		key, err := hex.DecodeString(strings.TrimSpace(string(raw)))
		if err != nil {
			return nil, false, fmt.Errorf("%s is geen hex: %w", path, err)
		}
		if len(key) < KeyLength {
			return nil, false, fmt.Errorf("%s draagt %d bytes; minimaal %d nodig", path, len(key), KeyLength)
		}
		return key, false, nil
	case !os.IsNotExist(err):
		return nil, false, fmt.Errorf("%s lezen: %w", path, err)
	}

	key = make([]byte, KeyLength)
	if _, err := rand.Read(key); err != nil {
		return nil, false, fmt.Errorf("sleutel genereren: %w", err)
	}

	// 0600 en O_EXCL: als twee instanties tegelijk opkomen mag er precies één
	// sleutel ontstaan, en de tweede leest hem in plaats van hem te overschrijven.
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		if os.IsExist(err) {
			return LoadOrCreateSigningKey(configDir)
		}
		return nil, false, fmt.Errorf("%s aanmaken: %w", path, err)
	}
	defer f.Close()

	if _, err := f.WriteString(hex.EncodeToString(key) + "\n"); err != nil {
		return nil, false, fmt.Errorf("%s schrijven: %w", path, err)
	}
	if err := f.Sync(); err != nil {
		return nil, false, fmt.Errorf("%s doorschrijven: %w", path, err)
	}
	return key, true, nil
}
