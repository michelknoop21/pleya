package loudness

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// OpusR128ReferenceLufs is het niveau waar Opus' eigen gain-tag tegen is
// uitgedrukt (RFC 7845 §5.2), niet hetzelfde als de planner's -22 LUFS-doel.
const OpusR128ReferenceLufs = -23.0

const (
	ReasonCodecNotAllowlisted Reason = "codec_not_allowlisted"
	ReasonTagProbeFailed      Reason = "ffprobe_tag_read_failed"
	ReasonTagMissing          Reason = "tag_missing"
	ReasonTagUnparsable       Reason = "tag_unparsable"
)

// TagResult is één vertrouwde tag, vertaald naar het canonieke gain/referentie-
// paar (LoudnessEvidence.gain_db / reference_lufs).
type TagResult struct {
	GainDb        float64
	ReferenceLufs float64
}

// TagReader leest de tags van één stream met één gerichte ffprobe-aanroep.
// internal/ffprobe blijft onaangeraakt: zijn Probe doet de volledige
// containeranalyse uit hoofdstuk 7.4, dit is één opzoeking per job en geen
// tweede volledige probe.
type TagReader struct {
	FFprobePath string
	Timeout     time.Duration
}

// ReadOpusR128 leest R128_TRACK_GAIN voor één Opus-stream. Alles buiten de
// allowlist, een andere codec, een ontbrekende tag, een tag die niet als
// Q7.8 signed 16-bit parseert, komt terug als een MeasureError wiens Reason
// veilig is om als stream_loudness.reject_reason op te slaan.
func (r *TagReader) ReadOpusR128(ctx context.Context, path string, streamIndex int, codec string) (TagResult, error) {
	if codec != "opus" {
		return TagResult{}, &MeasureError{Reason: ReasonCodecNotAllowlisted, Detail: fmt.Errorf("codec %q staat niet op de allowlist", codec)}
	}

	tags, err := r.readTags(ctx, path, streamIndex)
	if err != nil {
		return TagResult{}, &MeasureError{Reason: ReasonTagProbeFailed, Detail: err}
	}

	raw, ok := tags["R128_TRACK_GAIN"]
	if !ok {
		return TagResult{}, &MeasureError{Reason: ReasonTagMissing, Detail: errors.New("R128_TRACK_GAIN ontbreekt")}
	}

	q78, err := strconv.ParseInt(strings.TrimSpace(raw), 10, 32)
	if err != nil || q78 < -32768 || q78 > 32767 {
		return TagResult{}, &MeasureError{
			Reason: ReasonTagUnparsable,
			Detail: fmt.Errorf("R128_TRACK_GAIN %q is geen signed 16-bit Q7.8-waarde", raw),
		}
	}

	return TagResult{GainDb: float64(q78) / 256.0, ReferenceLufs: OpusR128ReferenceLufs}, nil
}

func (r *TagReader) readTags(ctx context.Context, path string, streamIndex int) (map[string]string, error) {
	ctx, cancel := context.WithTimeout(ctx, r.Timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, r.FFprobePath,
		"-v", "error",
		// Kaal streamnummer, geen "0:<idx>": dat input:stream-voorvoegsel hoort
		// bij ffmpeg's -map (meerdere inputs), niet bij ffprobe's
		// -select_streams (altijd precies één input).
		"-select_streams", strconv.Itoa(streamIndex),
		"-show_entries", "stream_tags",
		"-of", "json",
		path,
	)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = err.Error()
		}
		return nil, errors.New(msg)
	}

	var raw struct {
		Streams []struct {
			Tags map[string]string `json:"tags"`
		} `json:"streams"`
	}
	if err := json.Unmarshal(stdout.Bytes(), &raw); err != nil {
		return nil, fmt.Errorf("ffprobe-uitvoer onleesbaar: %w", err)
	}
	if len(raw.Streams) == 0 {
		return map[string]string{}, nil
	}
	return raw.Streams[0].Tags, nil
}
