// Package fileid leest de bestandsmetadata waaruit de zwakke validator volgt.
//
// DEC-050 legt de tupel vast: (dev, ino, size, mtime_ns, ctime_ns) van het
// bestand plus de generation van de versie. Groter dan (size, mtime) omdat een
// kopieeractie die beide bewaart wél een andere inode en een andere ctime
// oplevert, en kleiner dan een hash over het hele bestand omdat die op een NAS
// niet te betalen is.
//
// Wat deze tupel NIET is, is bewijs van gelijkheid. Een in-place overschrijving
// van gelijke lengte met teruggezette mtime blijft eronder de radar. Daarom
// draagt de header W/ en gebruikt Pleya hem nergens om bytes aan elkaar te
// plakken.
package fileid

import (
	"crypto/sha256"
	"encoding/hex"
	"io/fs"
	"strconv"
)

// Stat is de tupel uit DEC-050, met nullen waar het platform niets levert.
type Stat struct {
	Dev     int64
	Ino     int64
	Size    int64
	MtimeNs int64
	CtimeNs int64
}

// Of leest de tupel uit een FileInfo.
func Of(info fs.FileInfo) Stat {
	st := Stat{Size: info.Size(), MtimeNs: info.ModTime().UnixNano()}
	dev, ino, ctime := platformStat(info)
	st.Dev, st.Ino, st.CtimeNs = dev, ino, ctime
	return st
}

// WeakETag maakt de headerwaarde, inclusief het W/-voorvoegsel.
//
// Ondoorzichtig: een client ontleedt hem niet. De hash zit erin zodat de header
// geen inodenummers en geen padinformatie lekt, en niet omdat hij iets over de
// bytes zou bewijzen.
func (s Stat) WeakETag(generation int64) string {
	parts := strconv.FormatInt(s.Dev, 10) + ":" +
		strconv.FormatInt(s.Ino, 10) + ":" +
		strconv.FormatInt(s.Size, 10) + ":" +
		strconv.FormatInt(s.MtimeNs, 10) + ":" +
		strconv.FormatInt(s.CtimeNs, 10) + ":" +
		strconv.FormatInt(generation, 10)
	sum := sha256.Sum256([]byte(parts))
	return `W/"` + hex.EncodeToString(sum[:16]) + `"`
}
