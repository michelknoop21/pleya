package loudness_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/loudness"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func newTagReader() *loudness.TagReader {
	return &loudness.TagReader{FFprobePath: "ffprobe", Timeout: 15 * time.Second}
}

// TestReadOpusR128RejectsNonOpusWithoutTouchingDisk dekt de allowlist: de
// codec-check gebeurt vóór er ook maar één proces start, dus een pad dat niet
// bestaat is hier geen probleem.
func TestReadOpusR128RejectsNonOpusWithoutTouchingDisk(t *testing.T) {
	r := newTagReader()
	_, err := r.ReadOpusR128(context.Background(), "/does/not/exist.mkv", 0, "aac")

	var measureErr *loudness.MeasureError
	if !errors.As(err, &measureErr) || measureErr.Reason != loudness.ReasonCodecNotAllowlisted {
		t.Fatalf("ReadOpusR128 met codec aac gaf %v, verwacht ReasonCodecNotAllowlisted", err)
	}
}

func TestReadOpusR128ParsesTheGainTag(t *testing.T) {
	testsupport.HasFFmpeg(t)
	path := t.TempDir() + "/tagged.mkv"
	testsupport.MakeVideo(t, path, 1, "-c:a", "libopus", "-metadata:s:a:0", "R128_TRACK_GAIN=-512")

	r := newTagReader()
	res, err := r.ReadOpusR128(context.Background(), path, 1, "opus")
	if err != nil {
		t.Fatalf("ReadOpusR128: %v", err)
	}
	if res.GainDb != -2.0 {
		t.Fatalf("GainDb = %v, verwacht -2.0 (Q7.8 van -512)", res.GainDb)
	}
	if res.ReferenceLufs != loudness.OpusR128ReferenceLufs {
		t.Fatalf("ReferenceLufs = %v, verwacht %v", res.ReferenceLufs, loudness.OpusR128ReferenceLufs)
	}
}

func TestReadOpusR128MissingTagIsRejected(t *testing.T) {
	testsupport.HasFFmpeg(t)
	path := t.TempDir() + "/untagged.mkv"
	testsupport.MakeVideo(t, path, 1, "-c:a", "libopus")

	r := newTagReader()
	_, err := r.ReadOpusR128(context.Background(), path, 1, "opus")

	var measureErr *loudness.MeasureError
	if !errors.As(err, &measureErr) || measureErr.Reason != loudness.ReasonTagMissing {
		t.Fatalf("ReadOpusR128 zonder tag gaf %v, verwacht ReasonTagMissing", err)
	}
}

func TestReadOpusR128UnparsableTagIsRejected(t *testing.T) {
	testsupport.HasFFmpeg(t)
	path := t.TempDir() + "/garbage-tag.mkv"
	testsupport.MakeVideo(t, path, 1, "-c:a", "libopus", "-metadata:s:a:0", "R128_TRACK_GAIN=niet-een-getal")

	r := newTagReader()
	_, err := r.ReadOpusR128(context.Background(), path, 1, "opus")

	var measureErr *loudness.MeasureError
	if !errors.As(err, &measureErr) || measureErr.Reason != loudness.ReasonTagUnparsable {
		t.Fatalf("ReadOpusR128 met een onleesbare tag gaf %v, verwacht ReasonTagUnparsable", err)
	}
}
