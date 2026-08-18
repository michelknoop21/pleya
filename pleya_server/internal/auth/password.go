// Package auth draagt de bootstrap-identiteit uit specificatie 6.5.
//
// Er is precies één identiteit, de server-owner. Geen gebruikers, geen
// profielen, geen rollen en geen bibliotheekrechten: dat is PS-9.
package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
)

// Argon2Params zijn de instellingen waarmee een nieuwe hash gemaakt wordt.
//
// Ze staan ook in de hash zelf, in PHC-vorm. Dat is de hele reden dat
// verifiëren nergens op de configuratie leunt: die noemt alleen wat er vandaag
// voor een nieuwe hash geldt, en zwaarder hashen vraagt geen schemawijziging
// (specificatie 6.5, eigenschap 3).
type Argon2Params struct {
	Memory      uint32 // KiB
	Iterations  uint32
	Parallelism uint8
	SaltLength  uint32
	KeyLength   uint32
}

// DefaultArgon2Params volgen de RFC 9106-aanbeveling voor de tweede optie,
// bijgesteld op de doelhardware: een DS920+ met een Celeron J4125. 64 MiB en
// drie rondes kost daar ongeveer een kwart seconde per login, wat aanvaardbaar
// is voor iets dat één keer per sessie gebeurt.
var DefaultArgon2Params = Argon2Params{
	Memory:      64 * 1024,
	Iterations:  3,
	Parallelism: 2,
	SaltLength:  16,
	KeyLength:   32,
}

// ErrInvalidHash betekent dat de opgeslagen hash niet te lezen is.
var ErrInvalidHash = errors.New("wachtwoordhash is onleesbaar")

// HashPassword maakt een Argon2id-hash in PHC-vorm.
func HashPassword(password string, p Argon2Params) (string, error) {
	salt := make([]byte, p.SaltLength)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("salt genereren: %w", err)
	}
	key := argon2.IDKey([]byte(password), salt, p.Iterations, p.Memory, p.Parallelism, p.KeyLength)

	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, p.Memory, p.Iterations, p.Parallelism,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(key),
	), nil
}

// VerifyPassword controleert een wachtwoord tegen een PHC-hash.
//
// De tweede uitkomst zegt of de opgeslagen hash lichter is dan wat er vandaag
// geldt. Is dat zo, dan hasht de server bij deze geslaagde login opnieuw.
func VerifyPassword(password, encoded string, current Argon2Params) (ok bool, needsRehash bool, err error) {
	stored, salt, key, err := decodeHash(encoded)
	if err != nil {
		return false, false, err
	}

	candidate := argon2.IDKey([]byte(password), salt,
		stored.Iterations, stored.Memory, stored.Parallelism, uint32(len(key)))

	if subtle.ConstantTimeCompare(candidate, key) != 1 {
		return false, false, nil
	}

	lighter := stored.Memory < current.Memory ||
		stored.Iterations < current.Iterations ||
		uint32(len(key)) < current.KeyLength ||
		uint32(len(salt)) < current.SaltLength

	return true, lighter, nil
}

func decodeHash(encoded string) (Argon2Params, []byte, []byte, error) {
	var p Argon2Params

	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[0] != "" {
		return p, nil, nil, fmt.Errorf("%w: verwachtte zes velden", ErrInvalidHash)
	}
	if parts[1] != "argon2id" {
		return p, nil, nil, fmt.Errorf("%w: algoritme %q is geen argon2id", ErrInvalidHash, parts[1])
	}

	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil {
		return p, nil, nil, fmt.Errorf("%w: versie: %v", ErrInvalidHash, err)
	}
	if version != argon2.Version {
		return p, nil, nil, fmt.Errorf("%w: versie %d, deze build kent %d", ErrInvalidHash, version, argon2.Version)
	}

	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &p.Memory, &p.Iterations, &p.Parallelism); err != nil {
		return p, nil, nil, fmt.Errorf("%w: parameters: %v", ErrInvalidHash, err)
	}

	salt, err := base64.RawStdEncoding.Strict().DecodeString(parts[4])
	if err != nil {
		return p, nil, nil, fmt.Errorf("%w: salt: %v", ErrInvalidHash, err)
	}
	key, err := base64.RawStdEncoding.Strict().DecodeString(parts[5])
	if err != nil {
		return p, nil, nil, fmt.Errorf("%w: hash: %v", ErrInvalidHash, err)
	}

	p.SaltLength = uint32(len(salt))
	p.KeyLength = uint32(len(key))
	return p, salt, key, nil
}
