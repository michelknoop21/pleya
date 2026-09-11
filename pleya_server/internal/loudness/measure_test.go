package loudness_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/loudness"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func newMeasurer() *loudness.Measurer {
	return &loudness.Measurer{FFmpegPath: "ffmpeg", Timeout: 30 * time.Second}
}

// TestMeasureTracksARealLevelDifference bewijst dat de analysepas een echt
// niveauverschil ziet en geen verzonnen antwoord geeft: twee verder identieke
// clips, 6 dB uit elkaar via -af volume, horen ~6 dB uit elkaar te meten. Een
// exacte referentiewaarde pinnen zou de ebur128-fixtures uit
// scripts/loudness/ op de clientbranch dupliceren; dit bewijst alleen dat de
// pas zelf echt meet.
func TestMeasureTracksARealLevelDifference(t *testing.T) {
	testsupport.HasFFmpeg(t)

	loud := t.TempDir() + "/loud.mkv"
	quiet := t.TempDir() + "/quiet.mkv"
	testsupport.MakeVideo(t, loud, 3, "-af", "volume=0dB")
	testsupport.MakeVideo(t, quiet, 3, "-af", "volume=-6dB")

	m := newMeasurer()
	loudMeas, err := m.Measure(context.Background(), loud, 1, "aac", loudness.Native, 3000)
	if err != nil {
		t.Fatalf("Measure(loud): %v", err)
	}
	quietMeas, err := m.Measure(context.Background(), quiet, 1, "aac", loudness.Native, 3000)
	if err != nil {
		t.Fatalf("Measure(quiet): %v", err)
	}

	diff := loudMeas.IntegratedLufs - quietMeas.IntegratedLufs
	if diff < 5 || diff > 7 {
		t.Fatalf("niveauverschil gemeten als %.2f dB, verwacht ~6 dB (loud=%.2f, quiet=%.2f)",
			diff, loudMeas.IntegratedLufs, quietMeas.IntegratedLufs)
	}
}

func TestMeasureRejectsAWrongProbeDuration(t *testing.T) {
	testsupport.HasFFmpeg(t)
	path := t.TempDir() + "/clip.mkv"
	testsupport.MakeVideo(t, path, 2)

	m := newMeasurer()
	_, err := m.Measure(context.Background(), path, 1, "aac", loudness.Native, 60_000)

	var measureErr *loudness.MeasureError
	if !errors.As(err, &measureErr) || measureErr.Reason != loudness.ReasonDurationMismatch {
		t.Fatalf("Measure met een probeDurationMs die niets met het bestand te maken heeft gaf %v, verwacht ReasonDurationMismatch", err)
	}
}

func TestMeasureNonexistentFileFailsWithProcessFailed(t *testing.T) {
	testsupport.HasFFmpeg(t)

	m := newMeasurer()
	_, err := m.Measure(context.Background(), "/does/not/exist/clip.mkv", 0, "aac", loudness.Native, 1000)

	var measureErr *loudness.MeasureError
	if !errors.As(err, &measureErr) || measureErr.Reason != loudness.ReasonProcessFailed {
		t.Fatalf("Measure op een niet-bestaand pad gaf %v, verwacht ReasonProcessFailed", err)
	}
}

// TestMeasureAppliesAc3DecodeArgs bewijst niet de klank (dat doet de
// clientfixture al), maar wel dat een ac3-decode niet crasht en een geldige
// meting oplevert met DEC-111's decoderflags erop.
func TestMeasureAppliesAc3DecodeArgs(t *testing.T) {
	testsupport.HasFFmpeg(t)
	path := t.TempDir() + "/ac3.mkv"
	testsupport.MakeVideo(t, path, 2, "-c:a", "ac3", "-b:a", "192k")

	m := newMeasurer()
	meas, err := m.Measure(context.Background(), path, 1, "ac3", loudness.Native, 2000)
	if err != nil {
		t.Fatalf("Measure(ac3): %v", err)
	}
	if meas.IntegratedLufs == 0 {
		t.Fatal("IntegratedLufs = 0, dat betekent bijna zeker een verzonnen antwoord")
	}
}
