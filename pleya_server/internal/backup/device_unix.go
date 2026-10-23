//go:build unix

package backup

import (
	"os"
	"syscall"
)

// sameDevice vergelijkt het apparaatnummer van twee paden. Twee bind mounts uit
// hetzelfde bestandssysteem op de host delen dat nummer, ook in de container.
// Is een van beide niet te lezen, dan is het antwoord nee: een waarschuwing op
// grond van een meting die niet lukte zou niets bewijzen.
func sameDevice(a, b string) bool {
	sa, errA := os.Stat(a)
	sb, errB := os.Stat(b)
	if errA != nil || errB != nil {
		return false
	}
	da, okA := sa.Sys().(*syscall.Stat_t)
	db, okB := sb.Sys().(*syscall.Stat_t)
	return okA && okB && uint64(da.Dev) == uint64(db.Dev)
}
