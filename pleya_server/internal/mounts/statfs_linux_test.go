//go:build linux

package mounts

import (
	"os"
	"path/filepath"
	"testing"
)

// Echte regels: de eerste twee komen van Docker Desktop, de derde en vierde van
// de Synology DS920+. De NTFS-regel is de reden dat dit pakket bestaat.
const fixture = `485 484 0:96 / /config rw,nosuid,nodev,relatime - fakeowner /run/host_mark/Users rw,fakeowner
486 484 0:96 / /media/library ro,nosuid,nodev,relatime - fakeowner /run/host_mark/Users ro,fakeowner
501 484 0:99 /Intern_PlexMedia /media/intern ro,relatime - btrfs /dev/mapper/cachedev_0 ro,synoacl
502 484 0:11 / /media/usb5 ro,relatime - fuseblk /dev/usb4p2 ro,allow_other
503 484 0:12 / /pad\040met\040spatie rw,relatime - ext4 /dev/sda1 rw
`

func withFixture(t *testing.T) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "mountinfo")
	if err := os.WriteFile(path, []byte(fixture), 0o644); err != nil {
		t.Fatalf("fixture schrijven mislukt: %v", err)
	}
	original := mountinfoPath
	mountinfoPath = path
	t.Cleanup(func() { mountinfoPath = original })
}

func TestLookupMountReadsOptions(t *testing.T) {
	withFixture(t)

	cases := []struct {
		path     string
		fsType   string
		readOnly bool
	}{
		{"/config", "fakeowner", false},
		{"/media/library", "fakeowner", true},
		{"/media/library/film.mkv", "fakeowner", true},
		{"/media/intern", "btrfs", true},
		{"/media/usb5", "fuseblk", true},
		{"/pad met spatie", "ext4", false},
	}

	for _, c := range cases {
		t.Run(c.path, func(t *testing.T) {
			entry, ok := lookupMount(c.path)
			if !ok {
				t.Fatalf("geen mount gevonden voor %s", c.path)
			}
			if entry.fsType != c.fsType {
				t.Errorf("fsType = %q, verwacht %q", entry.fsType, c.fsType)
			}
			if entry.readOnly != c.readOnly {
				t.Errorf("readOnly = %v, verwacht %v", entry.readOnly, c.readOnly)
			}
		})
	}
}

// De langste mountpoint moet winnen, anders erft een submount de vlaggen van
// zijn ouder.
func TestLookupMountPrefersLongestMatch(t *testing.T) {
	withFixture(t)

	entry, ok := lookupMount("/media/intern/Films/film.mkv")
	if !ok {
		t.Fatal("geen mount gevonden")
	}
	if entry.mountPoint != "/media/intern" {
		t.Errorf("mountPoint = %q, verwacht /media/intern", entry.mountPoint)
	}
}

func TestParseMountinfoLineRejectsGarbage(t *testing.T) {
	for _, line := range []string{"", "te weinig velden", "1 2 3:4 / /pad rw geen-streepje ext4"} {
		if _, ok := parseMountinfoLine(line); ok {
			t.Errorf("parseMountinfoLine accepteerde %q", line)
		}
	}
}

func TestUnescapeOctal(t *testing.T) {
	cases := map[string]string{
		`/pad`:                  `/pad`,
		`/pad\040met\040spatie`: `/pad met spatie`,
		`/pad\`:                 `/pad\`,
	}
	for in, want := range cases {
		if got := unescapeOctal(in); got != want {
			t.Errorf("unescapeOctal(%q) = %q, verwacht %q", in, got, want)
		}
	}
}
