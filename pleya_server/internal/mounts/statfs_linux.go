//go:build linux

package mounts

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

// stRDOnly is ST_RDONLY uit sys/statvfs.h.
const stRDOnly = 0x0001

// mountinfoPath is een variabele zodat een test hem kan vervangen.
var mountinfoPath = "/proc/self/mountinfo"

// fsMagic vertaalt de magic uit statfs naar een leesbare naam. Dit is de
// terugval; /proc/self/mountinfo geeft de echte naam en is gezaghebbend.
var fsMagic = map[int64]string{
	0x9123683E: "btrfs",
	0x0000EF53: "ext4",
	0x65735546: "fuse",
	0x01021994: "tmpfs",
	0x794C7630: "overlay",
	0x58465342: "xfs",
	0x2FC12FC1: "zfs",
	0x6969:     "nfs",
	0xFF534D42: "cifs",
	0x73717368: "squashfs",
	0x4D44:     "vfat",
	0x5346544E: "ntfs",
}

// statfs meet het bestandssysteem onder een pad.
//
// De read-only vlag komt uit /proc/self/mountinfo en niet uit de vlaggen van
// statfs. Reden: Docker Desktop hangt bind mounts op via een eigen laag die
// ST_RDONLY niet doorgeeft, en dan meldt statfs een read-only mount als
// beschrijfbaar. mountinfo klopt daar wel, en levert bovendien een echte
// bestandssysteemnaam op in plaats van een magic die vertaald moet worden.
func statfs(path string) (fsType string, readOnly bool, free uint64, err error) {
	var st syscall.Statfs_t
	if err = syscall.Statfs(path, &st); err != nil {
		return "", false, 0, err
	}

	free = st.Bavail * uint64(st.Bsize)
	readOnly = st.Flags&stRDOnly != 0

	magic := int64(st.Type)
	fsType, ok := fsMagic[magic]
	if !ok {
		fsType = formatMagic(magic)
	}

	if entry, found := lookupMount(path); found {
		fsType = entry.fsType
		readOnly = readOnly || entry.readOnly
	}

	return fsType, readOnly, free, nil
}

type mountEntry struct {
	mountPoint string
	fsType     string
	readOnly   bool
}

// lookupMount zoekt de mount waar een pad onder valt: de langste mountpoint die
// een prefix van het pad is.
func lookupMount(path string) (mountEntry, bool) {
	f, err := os.Open(mountinfoPath)
	if err != nil {
		return mountEntry{}, false
	}
	defer f.Close()

	abs, err := filepath.Abs(path)
	if err != nil {
		abs = path
	}
	abs = filepath.Clean(abs)

	var best mountEntry
	var found bool

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		entry, ok := parseMountinfoLine(scanner.Text())
		if !ok || !underMount(abs, entry.mountPoint) {
			continue
		}
		if !found || len(entry.mountPoint) > len(best.mountPoint) {
			best, found = entry, true
		}
	}
	return best, found
}

func underMount(path, mountPoint string) bool {
	if path == mountPoint {
		return true
	}
	if mountPoint == "/" {
		return true
	}
	return strings.HasPrefix(path, mountPoint+"/")
}

// parseMountinfoLine leest één regel uit /proc/self/mountinfo. De vorm is:
//
//	id parent major:minor root mountpoint opties [extra velden] - fstype bron superopties
//
// De optionele velden voor het streepje maken tellen vanaf het einde
// onbetrouwbaar, dus wordt er op het streepje gesplitst.
func parseMountinfoLine(line string) (mountEntry, bool) {
	head, tail, ok := strings.Cut(line, " - ")
	if !ok {
		return mountEntry{}, false
	}

	headFields := strings.Fields(head)
	if len(headFields) < 6 {
		return mountEntry{}, false
	}
	tailFields := strings.Fields(tail)
	if len(tailFields) < 1 {
		return mountEntry{}, false
	}

	entry := mountEntry{
		mountPoint: unescapeOctal(headFields[4]),
		fsType:     tailFields[0],
	}
	for _, opt := range strings.Split(headFields[5], ",") {
		if opt == "ro" {
			entry.readOnly = true
			break
		}
	}
	return entry, true
}

// unescapeOctal draait de \040-achtige codering van mountinfo terug, zodat een
// pad met een spatie erin klopt.
func unescapeOctal(s string) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+3 < len(s) {
			v := 0
			valid := true
			for _, c := range []byte(s[i+1 : i+4]) {
				if c < '0' || c > '7' {
					valid = false
					break
				}
				v = v*8 + int(c-'0')
			}
			if valid {
				b.WriteByte(byte(v))
				i += 3
				continue
			}
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

func formatMagic(magic int64) string {
	const hex = "0123456789abcdef"
	buf := []byte{'0', 'x', 0, 0, 0, 0, 0, 0, 0, 0}
	for i := 0; i < 8; i++ {
		buf[9-i] = hex[(magic>>(4*i))&0xF]
	}
	return string(buf)
}
