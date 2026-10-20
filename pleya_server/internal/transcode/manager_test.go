package transcode_test

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/transcode"
)

// source maakt een kort bronbestand met AC-3 geluid, zodat direct_stream echt
// iets om te zetten heeft. De test slaat over zonder ffmpeg.
func source(t *testing.T) string {
	t.Helper()
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg ontbreekt")
	}
	path := filepath.Join(t.TempDir(), "bron.mkv")
	out, err := exec.Command("ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc=duration=8:size=320x180:rate=25",
		"-f", "lavfi", "-i", "sine=duration=8", "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "ac3", path).CombinedOutput()
	if err != nil {
		t.Fatalf("bron maken: %v: %s", err, out)
	}
	return path
}

func manager(t *testing.T, max int, idle time.Duration) *transcode.Manager {
	t.Helper()
	m, err := transcode.New(transcode.Options{
		Dir: t.TempDir(), Max: max, IdleTimeout: idle, StartTimeout: 40 * time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(m.Close)
	return m
}

func params(src string, mode transcode.Mode) transcode.Params {
	return transcode.Params{
		UserID: id.New(), VersionID: id.New(),
		Job: transcode.Job{InputPath: src, Mode: mode, AudioCodec: "aac", AudioChannels: 2},
	}
}

func TestSessionProducesPlayableHLSAndCleansUp(t *testing.T) {
	src := source(t)
	m := manager(t, 2, time.Minute)

	for _, mode := range []transcode.Mode{transcode.ModeRemux, transcode.ModeDirectStream, transcode.ModeTranscode} {
		s, err := m.Start(context.Background(), params(src, mode))
		if err != nil {
			t.Fatalf("%s: %v", mode, err)
		}
		for _, name := range []string{transcode.PlaylistName, transcode.InitName, "seg_00000.m4s"} {
			if _, err := os.Stat(filepath.Join(s.Dir, name)); err != nil {
				t.Fatalf("%s: %s ontbreekt: %v", mode, name, err)
			}
		}
		if err := m.Stop(s.ID); err != nil {
			t.Fatal(err)
		}
		if _, err := os.Stat(s.Dir); !os.IsNotExist(err) {
			t.Fatalf("%s: de sessiemap staat er nog: %v", mode, err)
		}
		if _, ok := m.Get(s.ID); ok {
			t.Fatalf("%s: de sessie is niet verwijderd", mode)
		}
	}
}

func TestThirdSessionIsBusy(t *testing.T) {
	src := source(t)
	m := manager(t, 2, time.Minute)
	for range 2 {
		if _, err := m.Start(context.Background(), params(src, transcode.ModeRemux)); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := m.Start(context.Background(), params(src, transcode.ModeRemux)); !errors.Is(err, transcode.ErrBusy) {
		t.Fatalf("derde sessie gaf %v", err)
	}
	// Een sessie die stopt maakt ruimte.
	list := m.List()
	_ = m.Stop(list[0].ID)
	if _, err := m.Start(context.Background(), params(src, transcode.ModeRemux)); err != nil {
		t.Fatalf("na stoppen: %v", err)
	}
}

// Een client die verdwijnt (crash, wifi weg) stuurt geen DELETE. De sessie
// verdwijnt dan vanzelf na de inactiviteitstermijn.
func TestSessionWithoutHeartbeatIsReaped(t *testing.T) {
	src := source(t)
	m := manager(t, 1, 2*time.Second)
	s, err := m.Start(context.Background(), params(src, transcode.ModeRemux))
	if err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(15 * time.Second)
	for {
		if _, ok := m.Get(s.ID); !ok {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("sessie werd niet opgeruimd")
		}
		time.Sleep(200 * time.Millisecond)
	}
	if _, err := os.Stat(s.Dir); !os.IsNotExist(err) {
		t.Fatalf("map staat er nog: %v", err)
	}
}

func TestHeartbeatKeepsASessionAlive(t *testing.T) {
	src := source(t)
	m := manager(t, 1, 2*time.Second)
	s, err := m.Start(context.Background(), params(src, transcode.ModeRemux))
	if err != nil {
		t.Fatal(err)
	}
	for range 8 {
		time.Sleep(500 * time.Millisecond)
		if !m.Touch(s.ID) {
			t.Fatal("hartslag geweigerd")
		}
	}
	if _, ok := m.Get(s.ID); !ok {
		t.Fatal("sessie weg ondanks hartslag")
	}
}

func TestBrokenInputFailsWithoutLeavingASession(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg ontbreekt")
	}
	m := manager(t, 1, time.Minute)
	_, err := m.Start(context.Background(), params("/bestaat/niet.mkv", transcode.ModeRemux))
	if !errors.Is(err, transcode.ErrFailed) {
		t.Fatalf("fout %v", err)
	}
	if len(m.List()) != 0 {
		t.Fatal("een mislukte start liet een sessie achter")
	}
}
