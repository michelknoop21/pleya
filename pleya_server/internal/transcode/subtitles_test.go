package transcode_test

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/transcode"
)

func embeddedTextSource(t *testing.T, text string, target string) string {
	t.Helper()
	video := source(t)
	subtitle := filepath.Join(t.TempDir(), "caption.srt")
	if err := os.WriteFile(subtitle, []byte("1\n00:00:00,000 --> 00:00:07,000\n"+text+"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if target == "" {
		target = filepath.Join(t.TempDir(), "embedded.mkv")
	}
	out, err := exec.Command("ffmpeg", "-v", "error", "-y", "-i", video, "-i", subtitle, "-map", "0", "-map", "1:0", "-c", "copy", target).CombinedOutput()
	if err != nil {
		t.Fatalf("mux: %v %s", err, out)
	}
	return target
}

func TestEmbeddedSubtitleExtractionCachesAndInvalidatesReplacedSource(t *testing.T) {
	input := embeddedTextSource(t, "First caption", "")
	m, err := transcode.New(transcode.Options{FFmpegPath: "ffmpeg", Dir: t.TempDir(), Max: 1})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(m.Close)
	params := transcode.SubtitleParams{InputPath: input, StreamIndex: 2, Format: "srt", Generation: 1}
	path, err := m.ExtractSubtitle(context.Background(), params)
	if err != nil {
		t.Fatal(err)
	}
	bytes, err := os.ReadFile(path)
	if err != nil || !strings.Contains(string(bytes), "First caption") {
		t.Fatalf("subtitle: %v %s", err, bytes)
	}
	again, err := m.ExtractSubtitle(context.Background(), params)
	if err != nil || again != path {
		t.Fatalf("cache: %s %v", again, err)
	}
	embeddedTextSource(t, "Replacement caption", input)
	replaced, err := m.ExtractSubtitle(context.Background(), params)
	if err != nil || replaced == path {
		t.Fatalf("stale cache: %s %v", replaced, err)
	}
	bytes, err = os.ReadFile(replaced)
	if err != nil || !strings.Contains(string(bytes), "Replacement caption") {
		t.Fatalf("replacement: %v %s", err, bytes)
	}
}

func TestEmbeddedSubtitleExtractionRejectsInvalidInputsAndCancellation(t *testing.T) {
	input := embeddedTextSource(t, "Caption", "")
	m, err := transcode.New(transcode.Options{FFmpegPath: "ffmpeg", Dir: t.TempDir(), Max: 1})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(m.Close)
	for _, p := range []transcode.SubtitleParams{
		{InputPath: input, StreamIndex: -1, Format: "srt"},
		{InputPath: input, StreamIndex: 2, Format: "../srt"},
		{InputPath: input, StreamIndex: 999, Format: "srt"},
	} {
		if _, err := m.ExtractSubtitle(context.Background(), p); err == nil {
			t.Fatalf("accepted %+v", p)
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := m.ExtractSubtitle(ctx, transcode.SubtitleParams{InputPath: input, StreamIndex: 2, Format: "srt"}); err == nil {
		t.Fatal("cancelled request extracted a subtitle")
	}
}

func TestEmbeddedSubtitleWorkerRejectsExtraWorkAndStopsOnClose(t *testing.T) {
	dir := t.TempDir()
	input := filepath.Join(dir, "source")
	if err := os.WriteFile(input, []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(dir, "started")
	tool := filepath.Join(dir, "ffmpeg")
	if err := os.WriteFile(tool, []byte("#!/bin/sh\nprintf x > '"+marker+"'\nexec sleep 60\n"), 0700); err != nil {
		t.Fatal(err)
	}
	m, err := transcode.New(transcode.Options{FFmpegPath: tool, Dir: filepath.Join(dir, "work"), Max: 1})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(m.Close)
	done := make(chan error, 1)
	p := transcode.SubtitleParams{InputPath: input, StreamIndex: 2, Format: "srt", Generation: 1}
	go func() { _, err := m.ExtractSubtitle(context.Background(), p); done <- err }()
	deadline := time.Now().Add(3 * time.Second)
	for {
		if _, err := os.Stat(marker); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("worker never started")
		}
		time.Sleep(10 * time.Millisecond)
	}
	p.Generation = 2
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Millisecond)
	defer cancel()
	if _, err := m.ExtractSubtitle(ctx, p); !errors.Is(err, transcode.ErrBusy) {
		t.Fatalf("unbounded waiting worker: %v", err)
	}
	m.Close()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("closed worker succeeded")
		}
	case <-time.After(time.Second):
		t.Fatal("worker survived close")
	}
	files, err := os.ReadDir(filepath.Join(dir, "work", "subtitles"))
	if err != nil || len(files) != 0 {
		t.Fatalf("partial files survived: %v %v", files, err)
	}
}

func TestEmbeddedSubtitleOutputBudgetLeavesNoTruncatedCacheEntry(t *testing.T) {
	dir := t.TempDir()
	input := filepath.Join(dir, "source")
	tool := filepath.Join(dir, "ffmpeg")
	if err := os.WriteFile(input, []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(tool, []byte("#!/bin/sh\nexec head -c 5000000 /dev/zero\n"), 0700); err != nil {
		t.Fatal(err)
	}
	m, err := transcode.New(transcode.Options{FFmpegPath: tool, Dir: filepath.Join(dir, "work"), Max: 1})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(m.Close)
	if _, err := m.ExtractSubtitle(context.Background(), transcode.SubtitleParams{InputPath: input, StreamIndex: 2, Format: "srt"}); err == nil {
		t.Fatal("oversized subtitle was accepted")
	}
	files, err := os.ReadDir(filepath.Join(dir, "work", "subtitles"))
	if err != nil || len(files) != 0 {
		t.Fatalf("truncated cache survived: %v %v", files, err)
	}
}

func TestBitmapSubtitleBudgetUsesTheCacheBudgetRatherThanTheTextBudget(t *testing.T) {
	for _, tc := range []struct {
		name     string
		bytes    int
		accepted bool
	}{
		{"above_text_limit", 5_000_000, true}, {"above_cache_limit", 67_108_865, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			input, tool := filepath.Join(dir, "source"), filepath.Join(dir, "ffmpeg")
			if err := os.WriteFile(input, []byte("fixture"), 0600); err != nil {
				t.Fatal(err)
			}
			script := fmt.Sprintf("#!/bin/sh\nexec head -c %d /dev/zero\n", tc.bytes)
			if err := os.WriteFile(tool, []byte(script), 0700); err != nil {
				t.Fatal(err)
			}
			m, err := transcode.New(transcode.Options{FFmpegPath: tool, Dir: filepath.Join(dir, "work"), Max: 1})
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(m.Close)
			path, err := m.ExtractSubtitle(context.Background(), transcode.SubtitleParams{InputPath: input, StreamIndex: 0, Format: "pgs"})
			if !tc.accepted {
				if err == nil {
					t.Fatal("oversized bitmap accepted")
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			info, err := os.Stat(path)
			if err != nil || info.Size() != int64(tc.bytes) {
				t.Fatalf("truncated bitmap: %v %v", info, err)
			}
		})
	}
}

// Own synthetic white rectangle; packet layout follows FFmpeg's supdec/pgssubdec, no third-party media.
func pgsFixture(t *testing.T, startSeconds, endSeconds uint32) string {
	t.Helper()
	var data []byte
	packet := func(pts uint32, kind byte, payload []byte) {
		data = append(data, 'P', 'G')
		data = binary.BigEndian.AppendUint32(data, pts)
		data = binary.BigEndian.AppendUint32(data, 0)
		data = append(data, kind)
		data = binary.BigEndian.AppendUint16(data, uint16(len(payload)))
		data = append(data, payload...)
	}
	presentation := []byte{2, 128, 1, 104, 0x10, 0, 0, 0x80, 0, 0, 1, 0, 0, 0, 0, 0, 80, 0, 80}
	packet(startSeconds*90000, 0x16, presentation)
	packet(startSeconds*90000, 0x14, []byte{0, 0, 1, 235, 128, 128, 255})
	var rle []byte
	for range 10 {
		for range 80 {
			rle = append(rle, 1)
		}
		rle = append(rle, 0, 0)
	}
	n := len(rle) + 4
	object := []byte{0, 0, 0, 0xc0, byte(n >> 16), byte(n >> 8), byte(n), 0, 80, 0, 10}
	packet(startSeconds*90000, 0x15, append(object, rle...))
	packet(startSeconds*90000, 0x80, nil)
	clear := append([]byte(nil), presentation[:11]...)
	clear[7], clear[10] = 0, 0
	packet(endSeconds*90000, 0x16, clear)
	packet(endSeconds*90000, 0x80, nil)
	path := filepath.Join(t.TempDir(), "rectangle.sup")
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestBitmapSubtitleExtractionAndBurnRendersAndClearsPixels(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg ontbreekt")
	}
	// A first cue at 4 s: a burn that shifts the subtitle track to zero shows it at the start instead.
	// -itsoffset because the muxing below would otherwise apply that same shift to the fixture.
	input := filepath.Join(t.TempDir(), "black.mkv")
	if out, err := exec.Command("ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=black:size=640x360:rate=25:duration=8", "-itsoffset", "4", "-i", pgsFixture(t, 4, 6), "-map", "0:v", "-map", "1:s", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:s", "copy", input).CombinedOutput(); err != nil {
		t.Fatalf("fixture: %v %s", err, out)
	}
	m, err := transcode.New(transcode.Options{FFmpegPath: "ffmpeg", Dir: t.TempDir(), Max: 1})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(m.Close)
	session, err := m.Start(context.Background(), transcode.Params{UserID: id.New(), VersionID: id.New(), Job: transcode.Job{InputPath: input, Mode: transcode.ModeTranscode, SubtitleBitmap: true, SubtitleStreamIndex: 1, MaxVideoBitrateKbps: 500, MaxHeight: 180}})
	if err != nil {
		t.Fatal(err)
	}
	for _, at := range []string{"1", "5", "7"} {
		frame, err := exec.Command("ffmpeg", "-v", "error", "-i", filepath.Join(session.Dir, transcode.PlaylistName), "-ss", at, "-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", "pipe:1").Output()
		if err != nil {
			t.Fatal(err)
		}
		if len(frame) != 320*180 {
			t.Fatalf("at %s: missing frame (%d bytes)", at, len(frame))
		}
		bright := 0
		for _, pixel := range frame {
			if pixel > 150 {
				bright++
			}
		}
		if at == "5" && bright < 100 || at != "5" && bright > 0 {
			t.Fatalf("at %s: incorrect subtitle pixels: %d", at, bright)
		}
	}
}
