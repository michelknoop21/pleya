// Package id levert UUIDv7 volgens RFC 9562, sectie 5.7.
//
// v7 en niet v4: de tijdsprefix maakt ids sorteerbaar op aanmaakmoment, wat de
// index-locality op grote tabellen aanzienlijk beter maakt dan een willekeurige
// v4. Een UUID en geen serial: ids moeten uitdeelbaar zijn zonder rondgang naar
// de database, en een migratiegereedschap moet ze kunnen genereren voordat het
// schrijft.
//
// Eigen implementatie en geen dependency: het is vijftig regels met een
// vastgelegd bitpatroon, en dat is goedkoper te lezen dan te vertrouwen.
package id

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"sync"
	"time"
)

// ID is een UUID in binaire vorm. pgx codeert [16]byte rechtstreeks naar het
// Postgres-type uuid.
type ID [16]byte

// Nil is de lege UUID.
var Nil ID

var (
	mu       sync.Mutex
	lastMs   int64
	lastSeq  uint16
	maxSeq   = uint16(0x0FFF)
	errShort = errors.New("uuid: te weinig tekens")
)

// New geeft een nieuwe UUIDv7.
//
// Binnen dezelfde milliseconde loopt een teller van twaalf bits op in plaats van
// dat de willekeur het moet oplossen. Dat is de monotone variant uit RFC 9562
// 6.2 methode 1, en hij is hier nodig omdat een scanner er duizenden per seconde
// uitdeelt: zonder teller staan ids uit dezelfde milliseconde in willekeurige
// volgorde, en dan is "sorteerbaar op aanmaakmoment" niet waar.
func New() ID {
	return newAt(time.Now())
}

func newAt(t time.Time) ID {
	ms := t.UnixMilli()

	mu.Lock()
	switch {
	case ms > lastMs:
		lastMs = ms
		lastSeq = 0
	case ms == lastMs && lastSeq < maxSeq:
		lastSeq++
	case ms == lastMs:
		// De teller is vol; schuif naar de volgende milliseconde in plaats van
		// een id uit te geven dat vóór zijn voorganger sorteert.
		lastMs++
		ms = lastMs
		lastSeq = 0
	default:
		// De klok liep terug. De reeks blijft leidend, want een id dat
		// achteruit springt breekt elke cursor die erop sorteert.
		ms = lastMs
		if lastSeq < maxSeq {
			lastSeq++
		} else {
			lastMs++
			ms = lastMs
			lastSeq = 0
		}
	}
	seq := lastSeq
	mu.Unlock()

	var out ID
	out[0] = byte(ms >> 40)
	out[1] = byte(ms >> 32)
	out[2] = byte(ms >> 24)
	out[3] = byte(ms >> 16)
	out[4] = byte(ms >> 8)
	out[5] = byte(ms)

	// rand_a draagt de teller, met het versienummer 7 in de hoge nibble.
	out[6] = 0x70 | byte(seq>>8)
	out[7] = byte(seq)

	if _, err := rand.Read(out[8:]); err != nil {
		panic("uuid: geen entropie beschikbaar: " + err.Error())
	}
	// Variant 10xx volgens RFC 9562 4.1.
	out[8] = (out[8] & 0x3F) | 0x80

	return out
}

// String geeft de canonieke 8-4-4-4-12-vorm in kleine letters.
func (i ID) String() string {
	var buf [36]byte
	hex.Encode(buf[0:8], i[0:4])
	buf[8] = '-'
	hex.Encode(buf[9:13], i[4:6])
	buf[13] = '-'
	hex.Encode(buf[14:18], i[6:8])
	buf[18] = '-'
	hex.Encode(buf[19:23], i[8:10])
	buf[23] = '-'
	hex.Encode(buf[24:36], i[10:16])
	return string(buf[:])
}

// IsZero zegt of dit de lege UUID is.
func (i ID) IsZero() bool { return i == Nil }

// Parse leest de canonieke vorm. Een id is voor de client ondoorzichtig, maar de
// server krijgt hem in een pad terug en moet hem dan afwijzen als hij niet klopt.
func Parse(s string) (ID, error) {
	if len(s) != 36 {
		return Nil, fmt.Errorf("%w: %d in plaats van 36", errShort, len(s))
	}
	if s[8] != '-' || s[13] != '-' || s[18] != '-' || s[23] != '-' {
		return Nil, errors.New("uuid: streepjes staan verkeerd")
	}
	var out ID
	for _, part := range [5][3]int{{0, 8, 0}, {9, 13, 4}, {14, 18, 6}, {19, 23, 8}, {24, 36, 10}} {
		if _, err := hex.Decode(out[part[2]:], []byte(s[part[0]:part[1]])); err != nil {
			return Nil, fmt.Errorf("uuid: %w", err)
		}
	}
	return out, nil
}

// MustParse is Parse voor vaste waarden in tests en fixtures.
func MustParse(s string) ID {
	v, err := Parse(s)
	if err != nil {
		panic(err)
	}
	return v
}
