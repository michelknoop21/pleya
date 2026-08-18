package ffprobe

import (
	"fmt"
	"math"
	"path/filepath"
	"strconv"
	"strings"
)

// containerAliases vertaalt de opsomming die ffprobe teruggeeft naar één naam.
// ffprobe zegt "matroska,webm" omdat de demuxer beide aankan; een client wil
// weten wat er in het bestand zit.
var containerAliases = map[string]string{
	"matroska,webm":           "mkv",
	"mov,mp4,m4a,3gp,3g2,mj2": "mp4",
	"mpegts":                  "ts",
	"mpeg":                    "mpeg",
	"avi":                     "avi",
	"asf":                     "wmv",
	"flv":                     "flv",
	"ogg":                     "ogv",
}

// subtitleFormats vertaalt de ffprobe-codecnaam naar de enum uit het protocol.
// Alleen wat het protocol kent komt erdoor: een onbekende ondertitelcodec levert
// geen spoor op, want een client kan niets met een formaat dat de specificatie
// niet noemt.
var subtitleFormats = map[string]string{
	"subrip":            "srt",
	"srt":               "srt",
	"ass":               "ass",
	"ssa":               "ssa",
	"webvtt":            "vtt",
	"vtt":               "vtt",
	"hdmv_pgs_subtitle": "pgs",
	"pgssub":            "pgs",
	"dvd_subtitle":      "dvdsub",
	"dvdsub":            "dvdsub",
}

// SubtitleFormatForExtension geeft het protocolformaat van een los
// ondertitelbestand naast de media.
func SubtitleFormatForExtension(ext string) (string, bool) {
	switch strings.ToLower(strings.TrimPrefix(ext, ".")) {
	case "srt":
		return "srt", true
	case "ass":
		return "ass", true
	case "ssa":
		return "ssa", true
	case "vtt":
		return "vtt", true
	default:
		return "", false
	}
}

func convert(raw *rawProbe, path string) (*Result, error) {
	res := &Result{Detection: DetectionMap{}}

	// Container. ffprobe draagt hem expliciet, dus confirmed; valt hij weg, dan
	// blijft de extensie over en dat is per definitie inferred.
	if name := strings.TrimSpace(raw.Format.FormatName); name != "" {
		if alias, ok := containerAliases[name]; ok {
			res.Container = alias
		} else {
			res.Container, _, _ = strings.Cut(name, ",")
		}
		res.Detection.Set("container", Confirmed, SourceStream)
	} else {
		res.Container = strings.ToLower(strings.TrimPrefix(filepath.Ext(path), "."))
		res.Detection.Set("container", Inferred, SourceFilename)
	}
	if res.Container == "" {
		return nil, fmt.Errorf("%w: geen container vast te stellen", ErrNotMedia)
	}

	// Duur. Het formaatniveau is het meest betrouwbaar; ontbreekt dat, dan is de
	// langste stream de beste schatting die er is.
	if ms, ok := secondsToMs(raw.Format.Duration); ok {
		res.DurationMs = ms
		res.Detection.Set("duration_ms", Confirmed, SourceStream)
	} else {
		var longest int64
		for _, s := range raw.Streams {
			if ms, ok := secondsToMs(s.Duration); ok && ms > longest {
				longest = ms
			}
		}
		res.DurationMs = longest
		if longest > 0 {
			res.Detection.Set("duration_ms", Inferred, SourceStream)
		} else {
			res.Detection.Set("duration_ms", Unknown, SourceStream)
		}
	}

	if n, err := strconv.ParseInt(strings.TrimSpace(raw.Format.BitRate), 10, 64); err == nil && n > 0 {
		res.BitrateBps = n
		res.Detection.Set("bitrate_bps", Confirmed, SourceStream)
	} else {
		res.Detection.Set("bitrate_bps", Unknown, SourceStream)
	}

	perKind := map[string]int{}
	for _, s := range raw.Streams {
		kind := strings.ToLower(s.CodecType)
		if kind != "video" && kind != "audio" && kind != "subtitle" {
			continue
		}
		// Ingebedde albumhoezen en miniaturen zijn videosporen zonder bewegend
		// beeld. Ze als videospoor aanbieden zet een speler op het verkeerde been.
		if kind == "video" && s.Disposition["attached_pic"] == 1 {
			continue
		}

		out := convertStream(s, kind)
		out.Ordinal = perKind[kind]
		perKind[kind]++
		res.Streams = append(res.Streams, out)
	}

	if len(res.Streams) == 0 {
		return nil, fmt.Errorf("%w: geen bruikbaar spoor", ErrNotMedia)
	}
	return res, nil
}

func convertStream(s rawStream, kind string) Stream {
	out := Stream{
		Index:     s.Index,
		Kind:      kind,
		Codec:     strings.ToLower(strings.TrimSpace(s.CodecName)),
		Profile:   strings.TrimSpace(s.Profile),
		Detection: DetectionMap{},
	}

	if out.Codec != "" {
		out.Detection.Set("codec", Confirmed, SourceStream)
	} else {
		out.Detection.Set("codec", Unknown, SourceStream)
	}
	if out.Profile != "" {
		out.Detection.Set("profile", Confirmed, SourceStream)
	}

	switch kind {
	case "video":
		out.Width, out.Height = s.Width, s.Height
		if out.Width > 0 && out.Height > 0 {
			out.Detection.Set("resolution", Confirmed, SourceStream)
		} else {
			out.Detection.Set("resolution", Unknown, SourceStream)
		}

		if depth, from := bitDepth(s); depth > 0 {
			out.BitDepth = depth
			out.Detection.Set("bit_depth", Confirmed, from)
		} else {
			out.Detection.Set("bit_depth", Unknown, SourceStream)
		}

		if fps, ok := parseRational(s.AvgFrameRate); ok {
			out.FrameRate = fps
			out.Detection.Set("frame_rate", Confirmed, SourceStream)
		} else if fps, ok := parseRational(s.RFrameRate); ok {
			// r_frame_rate is de kleinste noemer die elk tijdstempel dekt en dus
			// niet de werkelijke beeldsnelheid bij variabele framerate.
			out.FrameRate = fps
			out.Detection.Set("frame_rate", Inferred, SourceStream)
		} else {
			out.Detection.Set("frame_rate", Unknown, SourceStream)
		}

		out.ColorTransfer = strings.TrimSpace(s.ColorTransfer)
		out.ColorPrimaries = strings.TrimSpace(s.ColorPrimaries)
		out.ColorSpace = strings.TrimSpace(s.ColorSpace)
		if out.ColorTransfer != "" {
			out.Detection.Set("color_transfer", Confirmed, SourceStream)
		} else {
			out.Detection.Set("color_transfer", Unknown, SourceStream)
		}

		// Dolby Vision. Het configuratierecord staat in de side data; staat het
		// er niet, dan is er niets over te zeggen en is unknown het eerlijke
		// antwoord. Hoofdstuk 7.4: een verkeerd geraden DV-profiel levert een
		// zwart of paars beeld op, dus hier wordt niet gegokt.
		found := false
		for _, sd := range s.SideData {
			if !strings.Contains(strings.ToLower(sd.Type), "dovi") &&
				!strings.Contains(strings.ToLower(sd.Type), "dolby vision") {
				continue
			}
			out.DoviProfile = sd.DVProfile
			out.DoviBLCompatibleID = sd.DVBLSignalCompatibilityID
			found = true
			break
		}
		if found {
			out.Detection.Set("dovi_profile", Confirmed, SourceSideData)
		} else {
			out.Detection.Set("dovi_profile", Unknown, SourceSideData)
		}

	case "audio":
		out.Channels = s.Channels
		out.ChannelLayout = strings.TrimSpace(s.ChannelLayout)
		if out.Channels > 0 {
			out.Detection.Set("channels", Confirmed, SourceStream)
		} else {
			out.Detection.Set("channels", Unknown, SourceStream)
		}
		switch {
		case out.ChannelLayout == "":
			out.Detection.Set("channel_layout", Unknown, SourceStream)
		case strings.Contains(out.ChannelLayout, "unknown"), strings.Contains(out.ChannelLayout, "?"):
			// ffprobe zet er "5 channels (FL+FR+FC+BL+BR)" of "unknown" neer als
			// de container geen indeling draagt. Dat is een afleiding uit het
			// aantal kanalen, niet een gelezen indeling.
			out.Detection.Set("channel_layout", Inferred, SourceStream)
		default:
			out.Detection.Set("channel_layout", Confirmed, SourceStream)
		}

	case "subtitle":
		if format, ok := subtitleFormats[out.Codec]; ok {
			out.SubtitleFormat = format
			out.Detection.Set("subtitle_format", Confirmed, SourceStream)
		} else {
			out.Detection.Set("subtitle_format", Unknown, SourceStream)
		}
	}

	out.Language = normalizeLanguage(s.Tags["language"])
	if out.Language != "" {
		out.Detection.Set("language", Confirmed, SourceStream)
	} else {
		out.Detection.Set("language", Unknown, SourceStream)
	}
	out.Title = strings.TrimSpace(s.Tags["title"])

	// Expliciete booleans en geen afleiding uit de titel: het protocol vraagt
	// daar in hoofdstuk 12 letterlijk om.
	out.IsDefault = s.Disposition["default"] == 1
	out.IsForced = s.Disposition["forced"] == 1
	out.IsHearingImpaired = s.Disposition["hearing_impaired"] == 1

	return out
}

func bitDepth(s rawStream) (int, Source) {
	if n, err := strconv.Atoi(strings.TrimSpace(s.BitsPerRawSample)); err == nil && n > 0 {
		return n, SourceStream
	}
	// pix_fmt draagt de diepte in zijn naam: yuv420p10le is tien bits.
	pix := strings.ToLower(s.PixFmt)
	for _, depth := range []int{16, 14, 12, 10, 9} {
		if strings.Contains(pix, "p"+strconv.Itoa(depth)) {
			return depth, SourceStream
		}
	}
	if pix != "" {
		return 8, SourceStream
	}
	return 0, SourceStream
}

func parseRational(v string) (float64, bool) {
	num, den, ok := strings.Cut(strings.TrimSpace(v), "/")
	if !ok {
		f, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
		return f, err == nil && f > 0
	}
	n, err1 := strconv.ParseFloat(num, 64)
	d, err2 := strconv.ParseFloat(den, 64)
	if err1 != nil || err2 != nil || d == 0 || n <= 0 {
		return 0, false
	}
	f := n / d
	if math.IsInf(f, 0) || math.IsNaN(f) {
		return 0, false
	}
	// Drie decimalen is genoeg voor 23.976 en 29.970 en houdt de waarde stabiel
	// tussen twee analyses van hetzelfde bestand.
	return math.Round(f*1000) / 1000, true
}

func secondsToMs(v string) (int64, bool) {
	f, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
	if err != nil || f <= 0 || math.IsInf(f, 0) || math.IsNaN(f) {
		return 0, false
	}
	return int64(math.Round(f * 1000)), true
}

// normalizeLanguage houdt alleen wat het protocol belooft: ISO 639-2/B in drie
// letters, of niets. Een tag als "eng-US" of "English" levert liever geen taal
// op dan een taal die een client verkeerd interpreteert.
func normalizeLanguage(raw string) string {
	v := strings.ToLower(strings.TrimSpace(raw))
	v, _, _ = strings.Cut(v, "-")
	if len(v) != 3 {
		return ""
	}
	for _, r := range v {
		if r < 'a' || r > 'z' {
			return ""
		}
	}
	if v == "und" || v == "zxx" {
		return ""
	}
	return v
}
