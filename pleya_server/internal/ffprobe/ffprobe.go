// Package ffprobe leest de technische eigenschappen van een mediabestand.
//
// Hoofdstuk 7.4 van de architectuur is het uitgangspunt: dit is het punt waar
// een mediaserver stil fout gaat, dus elk veld draagt naast zijn waarde een
// detectionStatus en een source. Er is bewust geen enkele confidence-score van
// hoog tot laag, want dan moet de planner zelf verzinnen wat "middel" betekent
// voor Dolby Vision tegenover wat het betekent voor een kanaalindeling, en juist
// dat verschil doet ertoe.
//
// Wat dit pakket niet doet is interpreteren. Er komt geen hdr_format uit en geen
// Atmos-oordeel: die afweging is planner-beleid en dus PS-6. Hier gaat erin wat
// ffprobe zegt, met de herkomst erbij.
package ffprobe

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// Status is de detectionStatus uit hoofdstuk 7.4.
type Status string

const (
	// Confirmed betekent dat de bron het veld expliciet draagt.
	Confirmed Status = "confirmed"
	// Inferred betekent dat het is afgeleid uit iets anders.
	Inferred Status = "inferred"
	// Unknown betekent dat er niets over te zeggen valt. Unknown telt nooit als
	// toestemming.
	Unknown Status = "unknown"
)

// Source is de herkomst van een veld.
type Source string

const (
	SourceStream    Source = "ffprobe_stream"
	SourceSideData  Source = "ffprobe_side_data"
	SourceBitstream Source = "bitstream_probe"
	SourceFilename  Source = "filename"
	SourceManual    Source = "manual"
)

// Detection is de herkomst van één veld.
type Detection struct {
	Status Status `json:"status"`
	Source Source `json:"source"`
}

// DetectionMap is wat er in de jsonb-kolom belandt: veldnaam naar herkomst.
type DetectionMap map[string]Detection

// Set legt de herkomst van één veld vast.
func (m DetectionMap) Set(field string, status Status, source Source) {
	m[field] = Detection{Status: status, Source: source}
}

// Result is wat één analyse oplevert.
type Result struct {
	Container  string
	DurationMs int64
	BitrateBps int64
	Streams    []Stream
	Detection  DetectionMap
}

// Stream is één spoor uit de container.
type Stream struct {
	Index   int
	Kind    string // video, audio, subtitle
	Codec   string
	Profile string
	Ordinal int

	Width     int
	Height    int
	BitDepth  int
	FrameRate float64

	Channels      int
	ChannelLayout string

	Language string
	Title    string

	IsDefault         bool
	IsForced          bool
	IsHearingImpaired bool

	SubtitleFormat string

	ColorTransfer  string
	ColorPrimaries string
	ColorSpace     string

	DoviProfile        *int
	DoviBLCompatibleID *int

	Detection DetectionMap
}

// ErrNotMedia betekent dat ffprobe het bestand niet als media herkende. Dat is
// geen storing: een bibliotheek staat vol met bestanden die er alleen op lijken.
var ErrNotMedia = errors.New("geen bruikbaar mediabestand")

// Prober draait ffprobe.
type Prober struct {
	Path    string
	Timeout time.Duration
}

// New bouwt een prober.
func New(path string, timeout time.Duration) *Prober {
	return &Prober{Path: path, Timeout: timeout}
}

// Available zegt of het gepinde ffprobe uit de image bereikbaar is, en welke
// versie het is. Zonder dat draait de scanner niet en is dat beter meteen
// zichtbaar dan pas bij het eerste bestand.
func (p *Prober) Available(ctx context.Context) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	out, err := exec.CommandContext(ctx, p.Path, "-hide_banner", "-version").Output()
	if err != nil {
		return "", fmt.Errorf("%s draaien: %w", p.Path, err)
	}
	line, _, _ := strings.Cut(string(out), "\n")
	return strings.TrimSpace(line), nil
}

// Probe analyseert één bestand.
func (p *Prober) Probe(ctx context.Context, path string) (*Result, error) {
	ctx, cancel := context.WithTimeout(ctx, p.Timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, p.Path,
		"-hide_banner",
		"-loglevel", "error",
		"-print_format", "json",
		"-show_format",
		"-show_streams",
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
		return nil, fmt.Errorf("%w: %s", ErrNotMedia, msg)
	}

	var raw rawProbe
	if err := json.Unmarshal(stdout.Bytes(), &raw); err != nil {
		return nil, fmt.Errorf("ffprobe-uitvoer is onleesbaar: %w", err)
	}
	return convert(&raw, path)
}

type rawProbe struct {
	Format  rawFormat   `json:"format"`
	Streams []rawStream `json:"streams"`
}

type rawFormat struct {
	FormatName string `json:"format_name"`
	Duration   string `json:"duration"`
	BitRate    string `json:"bit_rate"`
}

type rawStream struct {
	Index            int               `json:"index"`
	CodecName        string            `json:"codec_name"`
	CodecType        string            `json:"codec_type"`
	Profile          string            `json:"profile"`
	Width            int               `json:"width"`
	Height           int               `json:"height"`
	PixFmt           string            `json:"pix_fmt"`
	BitsPerRawSample string            `json:"bits_per_raw_sample"`
	AvgFrameRate     string            `json:"avg_frame_rate"`
	RFrameRate       string            `json:"r_frame_rate"`
	Channels         int               `json:"channels"`
	ChannelLayout    string            `json:"channel_layout"`
	ColorTransfer    string            `json:"color_transfer"`
	ColorPrimaries   string            `json:"color_primaries"`
	ColorSpace       string            `json:"color_space"`
	Duration         string            `json:"duration"`
	Disposition      map[string]int    `json:"disposition"`
	Tags             map[string]string `json:"tags"`
	SideData         []rawSideData     `json:"side_data_list"`
}

type rawSideData struct {
	Type                      string `json:"side_data_type"`
	DVProfile                 *int   `json:"dv_profile"`
	DVBLSignalCompatibilityID *int   `json:"dv_bl_signal_compatibility_id"`
}
