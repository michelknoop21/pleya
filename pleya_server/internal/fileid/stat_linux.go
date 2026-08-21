//go:build linux

package fileid

import (
	"io/fs"
	"syscall"
)

func platformStat(info fs.FileInfo) (dev, ino, ctimeNs int64) {
	st, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return 0, 0, 0
	}
	return int64(st.Dev), int64(st.Ino), st.Ctim.Sec*1e9 + st.Ctim.Nsec
}
