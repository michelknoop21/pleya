package transcode_test

import (
	"slices"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/transcode"
)

func job(mode transcode.Mode) transcode.Job {
	return transcode.Job{
		InputPath: "/media/Film (2020)/Film.mkv", OutDir: "/transcode/s1", Mode: mode,
		AudioCodec: "aac", AudioChannels: 2,
	}
}

func TestRemuxCopiesBothTracks(t *testing.T) {
	args, err := transcode.BuildArgs(job(transcode.ModeRemux))
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Contains(args, "copy") || slices.Contains(args, "libx264") || slices.Contains(args, "-c:a") {
		t.Fatalf("remux hoort alles te kopieren: %v", args)
	}
}

func TestDirectStreamKeepsVideoAndConvertsAudio(t *testing.T) {
	j := job(transcode.ModeDirectStream)
	j.HEVCSource = true
	args, err := transcode.BuildArgs(j)
	if err != nil {
		t.Fatal(err)
	}
	s := strings.Join(args, " ")
	for _, want := range []string{"-c:v copy", "-tag:v hvc1", "-c:a aac", "-ac 2", "-hls_segment_type fmp4"} {
		if !strings.Contains(s, want) {
			t.Fatalf("%q ontbreekt in %s", want, s)
		}
	}
	if strings.Contains(s, "libx264") {
		t.Fatalf("direct stream mag het beeld niet coderen: %s", s)
	}
}

func TestTranscodeUsesSoftwareUnlessVAAPIAndSDR(t *testing.T) {
	soft, _ := transcode.BuildArgs(job(transcode.ModeTranscode))
	if !slices.Contains(soft, "libx264") {
		t.Fatalf("software: %v", soft)
	}

	hw := job(transcode.ModeTranscode)
	hw.HW, hw.RenderNode = transcode.HWVAAPI, "/dev/dri/renderD128"
	args, err := transcode.BuildArgs(hw)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Contains(args, "h264_vaapi") || !slices.Contains(args, "/dev/dri/renderD128") {
		t.Fatalf("vaapi: %v", args)
	}

	// HDR gaat door de software-tonemap, ook met hardware beschikbaar.
	hw.HDR = true
	args, _ = transcode.BuildArgs(hw)
	if slices.Contains(args, "h264_vaapi") || !strings.Contains(strings.Join(args, " "), "tonemap=hable") {
		t.Fatalf("hdr: %v", args)
	}
}

func TestArgsRejectAnythingOutsideTheAllowedSet(t *testing.T) {
	for name, mut := range map[string]func(*transcode.Job){
		"audiocodec met optie erin": func(j *transcode.Job) { j.AudioCodec = "aac -f lavfi" },
		"onbekende audiocodec":      func(j *transcode.Job) { j.AudioCodec = "mp3" },
		"nul kanalen":               func(j *transcode.Job) { j.AudioChannels = 0 },
		"te veel kanalen":           func(j *transcode.Job) { j.AudioChannels = 9 },
		"onbekende modus":           func(j *transcode.Job) { j.Mode = "x" },
		"geen pad":                  func(j *transcode.Job) { j.InputPath = "" },
	} {
		j := job(transcode.ModeTranscode)
		mut(&j)
		if _, err := transcode.BuildArgs(j); err == nil {
			t.Errorf("%s werd niet geweigerd", name)
		}
	}
}

// Het invoerpad staat precies één keer in de lijst, direct na -i, en geen enkel
// ander element bevat client-invoer.
func TestInputPathAppearsOnlyAfterDashI(t *testing.T) {
	args, _ := transcode.BuildArgs(job(transcode.ModeTranscode))
	n := 0
	for i, a := range args {
		if strings.Contains(a, "Film.mkv") {
			n++
			if i == 0 || args[i-1] != "-i" {
				t.Fatalf("pad op een andere plek: %v", args)
			}
		}
	}
	if n != 1 {
		t.Fatalf("pad komt %d keer voor", n)
	}
}

// Past het geluid al, dan wordt alleen het beeld omgezet.
func TestTranscodeWithoutAudioCodecCopiesTheAudio(t *testing.T) {
	j := job(transcode.ModeTranscode)
	j.AudioCodec, j.AudioChannels = "", 0
	args, err := transcode.BuildArgs(j)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(strings.Join(args, " "), "-c:a copy") {
		t.Fatalf("geluid niet gekopieerd: %v", args)
	}
	// Direct stream zonder doelcodec blijft een fout: daar is het geluid het werk.
	if _, err := transcode.BuildArgs(func() transcode.Job { j.Mode = transcode.ModeDirectStream; return j }()); err == nil {
		t.Fatal("direct stream zonder audiocodec werd niet geweigerd")
	}
}
