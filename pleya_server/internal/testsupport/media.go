package testsupport

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// HasFFmpeg zegt of er een echte ffmpeg en ffprobe op het pad staan.
func HasFFmpeg(t *testing.T) bool {
	t.Helper()
	for _, tool := range []string{"ffmpeg", "ffprobe"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skipf("%s ontbreekt; draai scripts/test-image.sh en zet GO_IMAGE", tool)
			return false
		}
	}
	return true
}

// MakeVideo maakt een klein echt mediabestand.
//
// Een testbestand dat ffprobe werkelijk leest en niet een verzonnen antwoord uit
// een dubbel: hoofdstuk 7.4 gaat er nu juist over dat de analyse zelf de plek is
// waar een mediaserver stil fout gaat.
func MakeVideo(t *testing.T, path string, seconds int, extra ...string) {
	t.Helper()

	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}

	args := []string{
		"-hide_banner", "-loglevel", "error", "-y",
		"-f", "lavfi", "-i", "testsrc=size=320x180:rate=24:duration=" + itoa(seconds),
		"-f", "lavfi", "-i", "sine=frequency=440:duration=" + itoa(seconds),
		"-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
		"-c:a", "aac", "-shortest",
	}
	args = append(args, extra...)
	args = append(args, path)

	out, err := exec.Command("ffmpeg", args...).CombinedOutput()
	if err != nil {
		t.Fatalf("ffmpeg: %v\n%s", err, out)
	}
}

// WriteFile schrijft een sidecar of een willekeurig bestand.
func WriteFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func itoa(v int) string {
	if v <= 0 {
		return "1"
	}
	digits := ""
	for v > 0 {
		digits = string(rune('0'+v%10)) + digits
		v /= 10
	}
	return digits
}
