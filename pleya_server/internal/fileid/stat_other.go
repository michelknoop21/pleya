//go:build !linux && !darwin

package fileid

import "io/fs"

// Zonder platformkennis blijft alleen wat FileInfo zelf draagt: grootte en
// mtime. De validator wordt daar niet onjuist van, alleen grover, en hij was al
// zwak.
func platformStat(_ fs.FileInfo) (dev, ino, ctimeNs int64) { return 0, 0, 0 }
