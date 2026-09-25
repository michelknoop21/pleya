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

// Reason is een vaste, gesanitiseerde foutreden: veilig om rechtstreeks in
// stream_loudness.reject_reason te zetten, nooit een pad of ruwe procesfout
// (D1). De ruwe oorzaak hoort alleen in het detail van een MeasureError, voor
// de log.
type Reason string

const (
	ReasonProcessFailed      Reason = "ffmpeg_process_failed"
	ReasonTimeout            Reason = "ffmpeg_timeout"
	ReasonIncompleteProgress Reason = "ffmpeg_progress_incomplete"
	ReasonDurationMismatch   Reason = "measured_duration_mismatch"
	ReasonUnparsableOutput   Reason = "loudnorm_output_unparsable"
)

// MeasureError draagt een Reason die direct als reject_reason opgeslagen mag
// worden, en een Detail dat dat nooit mag: dat kan padinformatie of ruwe
// ffmpeg-stderr bevatten.
type MeasureError struct {
	Reason Reason
	Detail error
}

func (e *MeasureError) Error() string {
	if e.Detail == nil {
		return string(e.Reason)
	}
	return string(e.Reason) + ": " + e.Detail.Error()
}

func (e *MeasureError) Unwrap() error { return e.Detail }

// Measurement is één geslaagde ffmpeg loudnorm-analysepas.
type Measurement struct {
	IntegratedLufs float64
	TruePeakDbtp   float64
	LraLu          float64
	ThresholdLufs  float64
}

// Measurer draait ffmpeg's loudnorm-filter als analysepas en nooit als
// transcoder: de uitvoer gaat naar -f null, er ontstaat geen bestand.
type Measurer struct {
	FFmpegPath string
	Timeout    time.Duration
}

// Measure analyseert stream streamIndex (het absolute ffprobe-indexnummer) van
// path, op de gegeven basis. probeDurationMs is het bewijs uit media_files: een
// pas die zijn duur niet ook echt gelezen heeft is niet ready, wat de reden ook
// is (een kapotte decode, een afgebroken bestand, een timeout die net op tijd
// exit-0 gaf).
func (m *Measurer) Measure(
	ctx context.Context, path string, streamIndex int, codec string, basis Basis, probeDurationMs int64,
) (Measurement, error) {
	ctx, cancel := context.WithTimeout(ctx, m.Timeout)
	defer cancel()

	args := []string{"-n", "19", m.FFmpegPath, "-nostdin", "-threads", "1"}
	args = append(args, basis.DecodeArgs(codec)...)
	args = append(args,
		"-i", path,
		"-map", fmt.Sprintf("0:%d", streamIndex),
		"-vn", "-sn", "-dn",
		"-af", "loudnorm=print_format=json",
		"-f", "null",
		"-progress", "pipe:1",
		"-",
	)

	cmd := exec.CommandContext(ctx, "nice", args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	runErr := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return Measurement{}, &MeasureError{Reason: ReasonTimeout, Detail: ctx.Err()}
	}
	if runErr != nil {
		return Measurement{}, &MeasureError{Reason: ReasonProcessFailed, Detail: runErr}
	}

	measuredMs, sawEnd := parseProgress(stdout.String())
	if !sawEnd {
		return Measurement{}, &MeasureError{
			Reason: ReasonIncompleteProgress,
			Detail: errors.New("progress=end ontbreekt in de ffmpeg-voortgangsstroom"),
		}
	}

	tolerance := int64(2000)
	if onePercent := probeDurationMs / 100; onePercent > tolerance {
		tolerance = onePercent
	}
	if diff := measuredMs - probeDurationMs; diff < -tolerance || diff > tolerance {
		return Measurement{}, &MeasureError{
			Reason: ReasonDurationMismatch,
			Detail: fmt.Errorf("gemeten %d ms, probe %d ms, tolerantie %d ms", measuredMs, probeDurationMs, tolerance),
		}
	}

	meas, err := parseLoudnorm(stderr.String())
	if err != nil {
		return Measurement{}, &MeasureError{Reason: ReasonUnparsableOutput, Detail: err}
	}
	return meas, nil
}

// parseProgress leest ffmpeg's -progress key=value-stroom en geeft de laatst
// geziene out_time_us terug, in milliseconden, plus of er een progress=end-regel
// kwam. out_time_ms draagt in sommige ffmpeg-builds een lang bestaande
// microseconde-bug; out_time_us is de waarde die daadwerkelijk in microseconden
// staat.
func parseProgress(stdout string) (measuredMs int64, sawEnd bool) {
	for _, line := range strings.Split(stdout, "\n") {
		key, value, ok := strings.Cut(strings.TrimSpace(line), "=")
		if !ok {
			continue
		}
		switch key {
		case "out_time_us":
			if us, err := strconv.ParseInt(value, 10, 64); err == nil {
				measuredMs = us / 1000
			}
		case "progress":
			if value == "end" {
				sawEnd = true
			}
		}
	}
	return measuredMs, sawEnd
}

type rawLoudnorm struct {
	InputI      string `json:"input_i"`
	InputTP     string `json:"input_tp"`
	InputLRA    string `json:"input_lra"`
	InputThresh string `json:"input_thresh"`
}

// parseLoudnorm haalt loudnorm's JSON-samenvatting uit ffmpeg's stderr. Het
// filter schrijft die altijd daar, print_format=json of niet: -progress pipe:1
// stuurt alleen de voortgangsstroom om, niet de filteruitvoer. Bij een
// enkelvoudige analysepas (geen tweede pass, geen normalisatie) zijn de
// input_*-velden de meting zelf.
func parseLoudnorm(stderr string) (Measurement, error) {
	start := strings.IndexByte(stderr, '{')
	end := strings.LastIndexByte(stderr, '}')
	if start < 0 || end <= start {
		return Measurement{}, errors.New("geen loudnorm-json gevonden in de ffmpeg-uitvoer")
	}

	var raw rawLoudnorm
	if err := json.Unmarshal([]byte(stderr[start:end+1]), &raw); err != nil {
		return Measurement{}, fmt.Errorf("loudnorm-json onleesbaar: %w", err)
	}

	i, errI := strconv.ParseFloat(raw.InputI, 64)
	tp, errTP := strconv.ParseFloat(raw.InputTP, 64)
	lra, errLRA := strconv.ParseFloat(raw.InputLRA, 64)
	thresh, errThresh := strconv.ParseFloat(raw.InputThresh, 64)
	if err := errors.Join(errI, errTP, errLRA, errThresh); err != nil {
		return Measurement{}, fmt.Errorf("loudnorm-velden onleesbaar: %w", err)
	}

	return Measurement{IntegratedLufs: i, TruePeakDbtp: tp, LraLu: lra, ThresholdLufs: thresh}, nil
}
