// Package transcode voert een afspeelplan uit dat meer is dan direct play
// (PS-8, architectuur hoofdstuk 11): remux, alleen het geluid omzetten, of
// beeld en geluid omzetten, als HLS met fMP4-segmenten.
//
// De ffmpeg-argumenten zijn een vaste lijst. Het enige dat erin komt van wat
// een aanvraag kan beïnvloeden is een waarde uit een toegestane verzameling
// (codec, kanalen); een pad of vrije tekst van de client komt er nooit in.
package transcode

import (
	"fmt"
	"strconv"
)

// Mode is hoe zwaar de omzetting is.
type Mode string

const (
	ModeRemux        Mode = "remux"
	ModeDirectStream Mode = "direct_stream"
	ModeTranscode    Mode = "transcode"
)

// HWAccel is de hardwareversnelling waarmee ffmpeg het beeld codeert.
type HWAccel string

const (
	HWNone  HWAccel = ""
	HWVAAPI HWAccel = "vaapi"
)

// Job is één omzetting. Alles hierin komt van de server zelf: het pad uit de
// catalogus, de modus uit de planner.
type Job struct {
	// InputPath is het absolute pad van het mediabestand.
	InputPath string
	// OutDir is de map van deze sessie onder de transcodemap.
	OutDir string

	Mode Mode
	// AudioCodec is aac of eac3; AudioChannels 1 tot en met 8. Bij een transcode
	// betekent een lege AudioCodec dat het geluid gekopieerd wordt.
	AudioCodec    string
	AudioChannels int
	// HDR zegt dat de bron HDR is en het beeld naar SDR moet.
	HDR bool
	// HEVCSource zegt dat een gekopieerd beeld HEVC is en een hvc1-tag nodig heeft.
	HEVCSource bool

	HW         HWAccel
	RenderNode string // bijvoorbeeld /dev/dri/renderD128

	SegmentSeconds int
}

// PlaylistName en InitName zijn de vaste bestandsnamen in een sessiemap.
const (
	PlaylistName   = "index.m3u8"
	InitName       = "init.mp4"
	SegmentPattern = "seg_%05d.m4s"
)

var allowedAudioCodecs = map[string]string{"aac": "aac", "eac3": "eac3"}

// BuildArgs maakt de argumentenlijst voor ffmpeg. Een ongeldige job geeft een
// fout in plaats van een lijst met iets onverwachts erin.
func BuildArgs(j Job) ([]string, error) {
	if j.InputPath == "" || j.OutDir == "" {
		return nil, fmt.Errorf("pad ontbreekt")
	}
	seg := j.SegmentSeconds
	if seg <= 0 {
		seg = 4
	}
	a := []string{"-nostdin", "-hide_banner", "-loglevel", "error"}

	hw := j.Mode == ModeTranscode && j.HW == HWVAAPI && !j.HDR
	if hw {
		if j.RenderNode == "" {
			return nil, fmt.Errorf("render node ontbreekt")
		}
		// Alleen het coderen gaat naar de GPU. Het decoderen blijft software: de
		// hardwaredecoder van een Celeron kent niet elk profiel (10 bit, sommige
		// HEVC-niveaus), en een bron die daar op stukloopt is precies de bron die
		// omgezet moet worden.
		a = append(a, "-init_hw_device", "vaapi=va:"+j.RenderNode, "-filter_hw_device", "va")
	}
	a = append(a, "-i", j.InputPath, "-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn")

	switch j.Mode {
	case ModeRemux:
		a = append(a, "-c", "copy")
		a = appendHEVCTag(a, j)
	case ModeDirectStream:
		a = append(a, "-c:v", "copy")
		a = appendHEVCTag(a, j)
		var err error
		if a, err = appendAudio(a, j); err != nil {
			return nil, err
		}
	case ModeTranscode:
		switch {
		case hw:
			a = append(a, "-vf", "format=nv12,hwupload", "-c:v", "h264_vaapi", "-qp", "23")
		case j.HDR:
			a = append(a, "-vf", hdrToSDRFilter, "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-pix_fmt", "yuv420p")
		default:
			a = append(a, "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-pix_fmt", "yuv420p")
		}
		if j.AudioCodec == "" {
			// Het geluid past al; alleen het beeld wordt omgezet.
			a = append(a, "-c:a", "copy")
		} else {
			var err error
			if a, err = appendAudio(a, j); err != nil {
				return nil, err
			}
		}
	default:
		return nil, fmt.Errorf("onbekende modus %q", j.Mode)
	}

	a = append(a,
		"-f", "hls",
		"-hls_time", strconv.Itoa(seg),
		"-hls_playlist_type", "event",
		"-hls_segment_type", "fmp4",
		"-hls_flags", "independent_segments+temp_file",
		"-hls_fmp4_init_filename", InitName,
		"-hls_segment_filename", j.OutDir+"/"+SegmentPattern,
		j.OutDir+"/"+PlaylistName,
	)
	return a, nil
}

// hdrToSDRFilter zet HDR10 naar SDR met een tone-mapping in software.
const hdrToSDRFilter = "zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p"

func appendHEVCTag(a []string, j Job) []string {
	if j.HEVCSource {
		return append(a, "-tag:v", "hvc1")
	}
	return a
}

func appendAudio(a []string, j Job) ([]string, error) {
	codec, ok := allowedAudioCodecs[j.AudioCodec]
	if !ok {
		return nil, fmt.Errorf("audiocodec %q is niet toegestaan", j.AudioCodec)
	}
	ch := j.AudioChannels
	if ch < 1 || ch > 8 {
		return nil, fmt.Errorf("kanalen %d buiten bereik", ch)
	}
	a = append(a, "-c:a", codec, "-ac", strconv.Itoa(ch))
	if codec == "aac" {
		a = append(a, "-b:a", strconv.Itoa(64*ch)+"k")
	} else {
		a = append(a, "-b:a", strconv.Itoa(96*ch)+"k")
	}
	return a, nil
}
