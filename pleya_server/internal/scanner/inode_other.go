//go:build !unix

package scanner

import "io/fs"

// inodeOf geeft niets op platforms zonder inodes. De scanner valt dan terug op
// de hash uit laag 2, wat precies het pad is dat een onbetrouwbare inode ook
// neemt.
func inodeOf(fs.FileInfo) int64 { return 0 }
