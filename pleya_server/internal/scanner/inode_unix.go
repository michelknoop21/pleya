//go:build unix

package scanner

import (
	"io/fs"
	"syscall"
)

// inodeOf leest het inodenummer uit de stat-structuur.
//
// Dit is laag 1 uit hoofdstuk 7.3, en tegelijk de reden dat storage_locations
// bijhoudt of het bestandssysteem hier betrouwbaar in is. Sommige mounts
// hergebruiken inodes, en dan is deze waarde een valstrik in plaats van een
// versnelling.
func inodeOf(info fs.FileInfo) int64 {
	st, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return 0
	}
	return int64(st.Ino)
}
