// Package scanner leest de bestandsboom in en houdt de catalogus bij.
//
// De verandersdetectie volgt hoofdstuk 7.3 in drie lagen, en hoofdstuk 7.2 is
// daarbij onvoorwaardelijk: een scan-signature mag op zichzelf nooit betekenen
// "dit is gegarandeerd hetzelfde bestand". Een hash over de eerste en de laatste
// megabyte zegt niets over het middenstuk, en juist bij grote mediabestanden kan
// een remux of een gerepareerde container het midden veranderen terwijl kop en
// staart intact blijven. De signature beslist alleen of er verder gekeken wordt.
package scanner

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"io"
	"os"
)

// ChunkSize is de kop en de staart die de goedkope hash meeneemt.
const ChunkSize = 1 << 20

// Signature berekent laag 2: een hash over de eerste en de laatste megabyte plus
// de grootte.
//
// De grootte gaat er expliciet in. Zonder dat zou een bestand dat aan het einde
// is afgekapt tot precies de kop plus de staart dezelfde signature houden.
func Signature(path string, size int64) (string, int64, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", 0, err
	}
	defer f.Close()

	h := sha256.New()

	var sizeBuf [8]byte
	binary.BigEndian.PutUint64(sizeBuf[:], uint64(size))
	h.Write(sizeBuf[:])

	head := int64(ChunkSize)
	if size < head {
		head = size
	}
	read, err := io.CopyN(h, f, head)
	if err != nil && err != io.EOF {
		return "", read, err
	}

	if size > 2*ChunkSize {
		if _, err := f.Seek(size-ChunkSize, io.SeekStart); err != nil {
			return "", read, err
		}
		n, err := io.CopyN(h, f, ChunkSize)
		read += n
		if err != nil && err != io.EOF {
			return "", read, err
		}
	}

	return hex.EncodeToString(h.Sum(nil)), read, nil
}

// FingerprintUnavailable is de melding die hoort bij de derde laag bewijs.
//
// De content fingerprint uit hoofdstuk 7.2 staat in het schema vanaf v1 als
// nullable kolom en wordt in deze fase alleen berekend waar hij gevraagd wordt.
// Er vraagt in PS-2 niets om, dus hij blijft leeg. Wanneer hij verplicht wordt
// is een aparte afweging, en hij hangt samen met poort 4 uit
// docs/pleya-server-gates.md.
var FingerprintUnavailable = fmt.Errorf("content fingerprint wordt in PS-2 niet berekend")
