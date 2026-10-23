package backup

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"fmt"

	"golang.org/x/crypto/argon2"
)

// sealParams staat in het manifest: alles wat nodig is om de geheimen weer te
// openen, behalve de wachtzin zelf.
//
// De parameters staan per back-up vast en niet in de code. Een latere versie
// die zwaardere waarden kiest, kan een oude back-up dan nog steeds openen.
type sealParams struct {
	KDF     string `json:"kdf"`
	Salt    []byte `json:"salt"`
	Time    uint32 `json:"time"`
	Memory  uint32 `json:"memory_kib"`
	Threads uint8  `json:"threads"`
	Cipher  string `json:"cipher"`
}

// sealAAD bindt het versleutelde blok aan zijn doel: hetzelfde blok in een
// ander bestandsformaat gaat niet open.
var sealAAD = []byte("pleya-backup-secrets-v1")

// Argon2id met 64 MiB en drie rondes. Dat is een fractie van een seconde op de
// Celeron in de NAS, en het gebeurt eenmaal per back-up.
const (
	sealTime    = 3
	sealMemory  = 64 * 1024
	sealThreads = 1
)

// seal versleutelt plaintext met een sleutel afgeleid van de wachtzin.
func seal(passphrase string, plaintext []byte) ([]byte, sealParams, error) {
	p := sealParams{KDF: "argon2id", Time: sealTime, Memory: sealMemory, Threads: sealThreads, Cipher: "aes-256-gcm"}
	p.Salt = make([]byte, 16)
	if _, err := rand.Read(p.Salt); err != nil {
		return nil, p, err
	}
	gcm, err := newGCM(passphrase, p)
	if err != nil {
		return nil, p, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, p, err
	}
	return gcm.Seal(nonce, nonce, plaintext, sealAAD), p, nil
}

// unseal opent wat seal maakte. Een verkeerde wachtzin en een beschadigd blok
// zijn voor GCM hetzelfde, en allebei ErrWrongKey: geen van beide valt terug te
// zetten.
func unseal(passphrase string, sealed []byte, p sealParams) ([]byte, error) {
	if p.KDF != "argon2id" || p.Cipher != "aes-256-gcm" {
		return nil, fmt.Errorf("%w: onbekende versleuteling %s/%s", ErrNotRestorable, p.KDF, p.Cipher)
	}
	// Een manifest met een gigabytes zware afleiding legt de server stil
	// voordat de sleutel ook maar getoetst is.
	if p.Memory > 1<<20 || p.Time == 0 || p.Time > 16 || p.Threads == 0 {
		return nil, fmt.Errorf("%w: afleidingsparameters buiten de grens", ErrNotRestorable)
	}
	gcm, err := newGCM(passphrase, p)
	if err != nil {
		return nil, err
	}
	if len(sealed) < gcm.NonceSize() {
		return nil, ErrWrongKey
	}
	plain, err := gcm.Open(nil, sealed[:gcm.NonceSize()], sealed[gcm.NonceSize():], sealAAD)
	if err != nil {
		return nil, ErrWrongKey
	}
	return plain, nil
}

func newGCM(passphrase string, p sealParams) (cipher.AEAD, error) {
	key := argon2.IDKey([]byte(passphrase), p.Salt, p.Time, p.Memory, p.Threads, 32)
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}
