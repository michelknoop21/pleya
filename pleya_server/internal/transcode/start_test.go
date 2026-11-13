package transcode_test

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/transcode"
)

// firstVideoPTS meet zelf, los van de manager, op welke filmtijd het eerste
// beeld van het eerste segment staat.
func firstVideoPTS(t *testing.T, dir string) float64 {
	t.Helper()
	out, err := exec.Command("ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=start_time", "-of", "csv=p=0",
		"concat:"+filepath.Join(dir, transcode.InitName)+"|"+filepath.Join(dir, "seg_00000.m4s")).Output()
	if err != nil {
		t.Fatal(err)
	}
	sec, err := strconv.ParseFloat(strings.TrimSpace(string(out)), 64)
	if err != nil {
		t.Fatalf("starttijd %q: %v", out, err)
	}
	return sec
}

// Een echt bestand met een keyframe op 0, 3, 6 en 9 seconden, omgezet vanaf
// 7,3 seconden. Een gekopieerd beeld begint op het keyframe van 6 seconden,
// een volledige omzetting op 7,3. In beide gevallen staan de filmtijden in het
// segment en meldt de sessie waar de stream begint.
func TestOmzettingBegintOpDeStartpositie(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg ontbreekt")
	}
	if _, err := exec.LookPath("ffprobe"); err != nil {
		t.Skip("ffprobe ontbreekt")
	}
	src := filepath.Join(t.TempDir(), "bron.mkv")
	out, err := exec.Command("ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc=duration=12:size=320x180:rate=25",
		"-f", "lavfi", "-i", "sine=duration=12", "-c:v", "libx264", "-preset", "ultrafast", "-bf", "2", "-g", "75",
		"-keyint_min", "75", "-sc_threshold", "0", "-c:a", "ac3", src).CombinedOutput()
	if err != nil {
		t.Fatalf("bron maken: %v: %s", err, out)
	}
	m := manager(t, 2, time.Minute)
	for _, c := range []struct {
		mode       transcode.Mode
		vanaf, tot float64
	}{
		{transcode.ModeRemux, 5.9, 6.2},
		{transcode.ModeDirectStream, 5.9, 6.2},
		{transcode.ModeTranscode, 7.25, 7.4},
	} {
		p := params(src, c.mode)
		p.Job.StartMs = 7300
		s, err := m.Start(context.Background(), p)
		if err != nil {
			t.Fatalf("%s: %v", c.mode, err)
		}
		beeld := firstVideoPTS(t, s.Dir)
		if beeld < c.vanaf || beeld > c.tot {
			t.Errorf("%s: het eerste beeld staat op %.3f s, verwacht tussen %.2f en %.2f", c.mode, beeld, c.vanaf, c.tot)
		}
		// De sessie meldt het begin van de stream: nooit na het eerste beeld en
		// er hooguit een fractie voor (het geluid begint op een eigen framegrens).
		gemeld := float64(s.StartMs) / 1000
		if gemeld > beeld+0.001 || gemeld < beeld-0.2 || gemeld > 7.3 {
			t.Errorf("%s: de sessie meldt %.3f s bij een eerste beeld op %.3f s", c.mode, gemeld, beeld)
		}
		raw, err := os.ReadFile(filepath.Join(s.Dir, transcode.PlaylistName))
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(string(raw), "EXTINF:0.000000") || strings.Contains(string(raw), "TARGETDURATION:0") {
			t.Errorf("%s: de afspeellijst heeft duur 0:\n%s", c.mode, raw)
		}
		if err := m.Stop(s.ID); err != nil {
			t.Fatal(err)
		}
	}
}

// Een ingebrande tekstondertitel volgt de filmtijd, ook als de omzetting later
// begint. Na een start op 7 seconden staat de regel van 8 tot 11 seconden op
// filmtijd 8,5 in beeld en op 7,2 nog niet. Zonder -copyts telt het filter
// vanaf nul en verschijnt de regel pas acht seconden na de start.
func TestIngebrandeOndertitelVolgtDeFilmtijdNaEenStartpositie(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg ontbreekt")
	}
	if _, err := exec.LookPath("ffprobe"); err != nil {
		t.Skip("ffprobe ontbreekt")
	}
	root := t.TempDir()
	input, caption := filepath.Join(root, "zwart.mp4"), filepath.Join(root, "regel.srt")
	if err := os.WriteFile(caption, []byte("1\n00:00:08,000 --> 00:00:11,000\nPleya zichtbare regel\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	out, err := exec.Command("ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=black:size=640x360:rate=25:duration=12", "-c:v", "libx264", "-pix_fmt", "yuv420p", input).CombinedOutput()
	if err != nil {
		t.Fatalf("bron maken: %v %s", err, out)
	}
	m := manager(t, 1, time.Minute)
	s, err := m.Start(context.Background(), transcode.Params{UserID: id.New(), VersionID: id.New(), Job: transcode.Job{
		InputPath: input, Mode: transcode.ModeTranscode, SubtitlePath: caption, MaxVideoBitrateKbps: 500, MaxHeight: 180, StartMs: 7000,
	}})
	if err != nil {
		t.Fatal(err)
	}
	// Een lijst zonder einde leest ffmpeg als live, vanaf het laatste segment.
	playlist := filepath.Join(s.Dir, transcode.PlaylistName)
	for deadline := time.Now().Add(30 * time.Second); ; time.Sleep(100 * time.Millisecond) {
		raw, _ := os.ReadFile(playlist)
		if strings.Contains(string(raw), "#EXT-X-ENDLIST") {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("de omzetting kwam niet af:\n%s", raw)
		}
	}
	// -copyts bij het lezen: -ss is dan een filmtijd, geen tijd sinds de start.
	helder := func(offset string) int {
		frame, err := exec.Command("ffmpeg", "-v", "error", "-copyts", "-i", playlist, "-ss", offset, "-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", "pipe:1").Output()
		if err != nil || len(frame) != 320*180 {
			t.Fatalf("beeld op %s s: %v, %d bytes", offset, err, len(frame))
		}
		n := 0
		for _, pixel := range frame {
			if pixel > 150 {
				n++
			}
		}
		return n
	}
	if n := helder("8.5"); n < 20 {
		t.Errorf("de regel staat niet in beeld op filmtijd 8,5 s: %d heldere pixels", n)
	}
	if n := helder("7.2"); n >= 20 {
		t.Errorf("de regel staat al in beeld op filmtijd 7,2 s: %d heldere pixels", n)
	}
}
