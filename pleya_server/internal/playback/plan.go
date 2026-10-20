// Package playback beslist wat er met een versie moet gebeuren voordat een
// toestel hem kan afspelen (PS-6, architectuur hoofdstuk 10).
//
// De planner is een pure functie van (versie-eigenschappen, capabilities,
// beleid) naar een plan. Hij kent geen database, geen HTTP en geen clienttype:
// hij vertakt nooit op wie het vraagt, alleen op wat het toestel zegt te
// kunnen (10.4).
package playback

import (
	"cmp"
	"fmt"
	"slices"
	"strings"
)

// Confidence zegt hoe zeker een waarneming van de client is.
type Confidence string

const (
	Detected Confidence = "detected"
	Inferred Confidence = "inferred"
	Unknown  Confidence = "unknown"
)

// Cap is één capability met de zekerheid van de waarneming. Een Cap zonder
// Known zegt niets, en dan houdt de planner het gedrag van vóór PS-5 aan:
// direct play.
type Cap[T any] struct {
	Known      bool
	Value      T
	Confidence Confidence
	Overridden bool
}

// Known maakt een bekende waarde.
func Known[T any](v T, c Confidence) Cap[T] {
	return Cap[T]{Known: true, Value: v, Confidence: c}
}

// Capabilities is wat het toestel zegt aan te kunnen, in de vier lagen van 9.1.
type Capabilities struct {
	Decoder struct {
		VideoCodecs   Cap[[]string]
		AudioCodecs   Cap[[]string]
		Containers    Cap[[]string]
		VideoProfiles Cap[[]string]
		MaxBitDepth   Cap[int]
	}
	Display struct {
		HDRTransfers Cap[[]string]
	}
	Audio struct {
		MaxChannels       Cap[int]
		PassthroughCodecs Cap[[]string]
	}
	Connection struct {
		IsLocal        Cap[bool]
		MaxBitrateKbps Cap[int]
	}
}

// Source zijn de eigenschappen van één versie die de planner nodig heeft.
type Source struct {
	VersionID   string
	Container   string
	BitrateKbps int64 // 0 is onbekend
	Video       *VideoTrack
	Audio       *AudioTrack
}

// VideoTrack is het videospoor van een versie.
type VideoTrack struct {
	Codec       string
	Profile     string
	BitDepth    int // 0 is onbekend
	Transfer    string
	DoviProfile *int
}

// AudioTrack is het audiospoor dat het plan meeneemt (het standaardspoor).
type AudioTrack struct {
	Codec    string
	Channels int // 0 is onbekend
}

// Policy zegt wat de server mag uitvoeren. Zolang er geen transcoder is
// (S18) staan beide uit en kan een plan alleen direct play zijn.
type Policy struct {
	AllowRemux      bool
	AllowTranscode  bool
	MaxAudioChannel int // doelkanalen bij een downmix; 0 is 2
}

// Mode is de uitkomst op leveringsniveau.
type Mode string

const (
	DirectPlay   Mode = "direct_play"
	Remux        Mode = "remux"
	DirectStream Mode = "direct_stream"
	Transcode    Mode = "transcode"
)

func (m Mode) rank() int {
	switch m {
	case DirectPlay:
		return 0
	case Remux:
		return 1
	case DirectStream:
		return 2
	default:
		return 3
	}
}

// Reason is een domeincode met parameters, geen vertaalsleutel (10.1).
type Reason struct {
	Code   string
	Params map[string]any
}

// Plan is de beslissing voor één versie.
type Plan struct {
	VersionID string
	Mode      Mode
	// Container is original voor direct play en hls voor alles wat de server omzet.
	Container string
	// VideoAction en AudioAction zijn copy of transcode.
	VideoAction string
	AudioAction string
	AudioCodec  string // doelcodec bij AudioAction transcode
	AudioMaxCh  int    // doelkanalen bij AudioAction transcode
	Seekable    bool
	Reasons     []Reason
}

// NotPlayableError betekent dat het harde filter niets overliet. De redenen
// zijn die van de goedkoopste kandidaat, zodat de client kan uitleggen wat er
// ontbrak.
type NotPlayableError struct {
	Reasons []Reason
}

func (e *NotPlayableError) Error() string { return "no playable plan" }

// Reason codes. Ze zijn protocol: een client mapt ze naar eigen tekst.
const (
	ReasonDirect             = "direct.supported"
	ReasonContainer          = "container.unsupported"
	ReasonVideoCodec         = "video.codec_unsupported"
	ReasonVideoProfile       = "video.profile_unsupported"
	ReasonVideoBitDepth      = "video.bit_depth_unsupported"
	ReasonVideoHDR           = "video.hdr_unsupported"
	ReasonVideoDovi          = "video.dovi_unsupported"
	ReasonAudioCodec         = "audio.codec_unsupported"
	ReasonBitrate            = "connection.bitrate_exceeded"
	ReasonTranscodeDisallowd = "server.transcode_unavailable"
)

// Decide kiest het goedkoopste passende plan over de versies. Goedkoopst is
// eerst de lichtste leveringswijze (direct play, dan remux, dan alleen audio
// omzetten, dan transcode), daarna de laagste bitrate. Hoogste kwaliteit is
// dus geen criterium: wie meer wil, kiest zelf een versie.
func Decide(sources []Source, caps Capabilities, policy Policy) (Plan, error) {
	if len(sources) == 0 {
		return Plan{}, &NotPlayableError{}
	}
	type cand struct {
		plan    Plan
		bitrate int64
		allowed bool
	}
	cands := make([]cand, 0, len(sources))
	for _, s := range sources {
		p := evaluate(s, caps, policy)
		cands = append(cands, cand{plan: p, bitrate: s.BitrateKbps, allowed: allowed(p.Mode, policy)})
	}
	less := func(a, b cand) int {
		if c := cmp.Compare(a.plan.Mode.rank(), b.plan.Mode.rank()); c != 0 {
			return c
		}
		// Een onbekende bitrate telt als de duurste: een versie waarvan we
		// de kosten niet kennen wint niet van een bekende.
		ab, bb := a.bitrate, b.bitrate
		if ab == 0 {
			ab = 1 << 40
		}
		if bb == 0 {
			bb = 1 << 40
		}
		if c := cmp.Compare(ab, bb); c != 0 {
			return c
		}
		return strings.Compare(a.plan.VersionID, b.plan.VersionID)
	}
	slices.SortFunc(cands, less)
	for _, c := range cands {
		if c.allowed {
			return c.plan, nil
		}
	}
	reasons := slices.Clone(cands[0].plan.Reasons)
	reasons = append(reasons, Reason{Code: ReasonTranscodeDisallowd, Params: map[string]any{"mode": string(cands[0].plan.Mode)}})
	return Plan{}, &NotPlayableError{Reasons: reasons}
}

func allowed(m Mode, p Policy) bool {
	switch m {
	case DirectPlay:
		return true
	case Remux:
		return p.AllowRemux
	default:
		return p.AllowTranscode
	}
}

// evaluate legt de eigenschappen van één versie langs de capabilities.
func evaluate(s Source, caps Capabilities, policy Policy) Plan {
	var containerReasons, videoReasons, audioReasons, netReasons []Reason

	// Container.
	if c := caps.Decoder.Containers; c.Known && s.Container != "" && !contains(c.Value, normContainer(s.Container)) {
		containerReasons = append(containerReasons, Reason{ReasonContainer, map[string]any{
			"container": s.Container, "supported": sortedCopy(c.Value),
		}})
	}

	// Video. Elke eigenschap heeft zijn eigen drempel (acceptatie 1): een
	// ontbrekende lijst keurt niets af, een afgeleide (inferred) lijst telt
	// mee voor codec en container maar niet voor HDR en Dolby Vision, want
	// die lees je alleen uit het scherm zelf.
	if v := s.Video; v != nil {
		if c := caps.Decoder.VideoCodecs; c.Known && v.Codec != "" && !contains(c.Value, normCodec(v.Codec)) {
			videoReasons = append(videoReasons, Reason{ReasonVideoCodec, map[string]any{"source_codec": v.Codec}})
		}
		if c := caps.Decoder.VideoProfiles; c.Known && len(c.Value) > 0 && v.Profile != "" && !containsFold(c.Value, v.Profile) {
			videoReasons = append(videoReasons, Reason{ReasonVideoProfile, map[string]any{"source_codec": v.Codec, "profile": v.Profile}})
		}
		if c := caps.Decoder.MaxBitDepth; c.Known && v.BitDepth > 0 && v.BitDepth > c.Value {
			videoReasons = append(videoReasons, Reason{ReasonVideoBitDepth, map[string]any{"bit_depth": v.BitDepth, "max_bit_depth": c.Value}})
		}
		if c := caps.Display.HDRTransfers; c.Known && c.Confidence == Detected {
			if kind := hdrKind(v.Transfer); kind != "" && !containsFold(c.Value, kind) {
				videoReasons = append(videoReasons, Reason{ReasonVideoHDR, map[string]any{"transfer": kind}})
			}
			if v.DoviProfile != nil && *v.DoviProfile == 5 && !containsFold(c.Value, "dolby_vision") {
				videoReasons = append(videoReasons, Reason{ReasonVideoDovi, map[string]any{"dovi_profile": 5}})
			}
		}
	}

	// Audio.
	var audioTarget string
	targetCh := 0
	if a := s.Audio; a != nil && a.Codec != "" {
		decodable := true
		if c := caps.Decoder.AudioCodecs; c.Known && !contains(c.Value, normCodec(a.Codec)) {
			decodable = false
		}
		if c := caps.Audio.PassthroughCodecs; c.Known && contains(c.Value, normCodec(a.Codec)) {
			decodable = true
		}
		if !decodable {
			targetCh = a.Channels
			if m := caps.Audio.MaxChannels; m.Known && (targetCh == 0 || targetCh > m.Value) {
				targetCh = m.Value
			}
			if targetCh == 0 || targetCh > 6 {
				targetCh = 2
			}
			audioTarget = "aac"
			if targetCh > 2 && contains(caps.Decoder.AudioCodecs.Value, "eac3") {
				audioTarget = "eac3"
			}
			audioReasons = append(audioReasons, Reason{ReasonAudioCodec, map[string]any{
				"source_codec": a.Codec, "channels": a.Channels, "target_codec": audioTarget, "target_channels": targetCh,
			}})
		}
	}

	// Verbinding: de limiet geldt alleen buiten het lokale netwerk (9.1).
	if c := caps.Connection.MaxBitrateKbps; c.Known && s.BitrateKbps > 0 && s.BitrateKbps > int64(c.Value) &&
		!(caps.Connection.IsLocal.Known && caps.Connection.IsLocal.Value) {
		netReasons = append(netReasons, Reason{ReasonBitrate, map[string]any{"bitrate_kbps": s.BitrateKbps, "max_kbps": c.Value}})
	}

	p := Plan{VersionID: s.VersionID, Container: "original", VideoAction: "copy", AudioAction: "copy", Seekable: true}
	switch {
	case len(videoReasons) > 0 || len(netReasons) > 0:
		p.Mode, p.Container, p.VideoAction = Transcode, "hls", "transcode"
		if len(audioReasons) > 0 {
			p.AudioAction, p.AudioCodec, p.AudioMaxCh = "transcode", audioTarget, targetCh
		}
	case len(audioReasons) > 0:
		p.Mode, p.Container, p.AudioAction, p.AudioCodec, p.AudioMaxCh = DirectStream, "hls", "transcode", audioTarget, targetCh
	case len(containerReasons) > 0:
		p.Mode, p.Container = Remux, "hls"
	default:
		p.Mode = DirectPlay
	}
	for _, rs := range [][]Reason{containerReasons, videoReasons, audioReasons, netReasons} {
		p.Reasons = append(p.Reasons, rs...)
	}
	if len(p.Reasons) == 0 {
		p.Reasons = []Reason{{Code: ReasonDirect, Params: map[string]any{"container": s.Container}}}
	}
	// Seekbaarheid: direct play seekt met HTTP-range. De uitvoerende modi
	// (S18) bepalen hun eigen grens; tot dan zijn ze niet seekbaar gemeld.
	p.Seekable = p.Mode == DirectPlay
	return p
}

// IsHDRTransfer zegt of een kleuroverdracht HDR is (PQ of HLG).
func IsHDRTransfer(transfer string) bool { return hdrKind(transfer) != "" }

func hdrKind(transfer string) string {
	switch strings.ToLower(transfer) {
	case "smpte2084":
		return "hdr10"
	case "arib-std-b67":
		return "hlg"
	}
	return ""
}

func normCodec(c string) string {
	c = strings.ToLower(c)
	if c == "h265" {
		return "hevc"
	}
	return c
}

func normContainer(c string) string {
	c = strings.ToLower(c)
	switch c {
	case "matroska":
		return "mkv"
	case "m4v", "mov":
		return c
	}
	return c
}

func contains(list []string, v string) bool {
	for _, x := range list {
		if normCodec(x) == v || strings.EqualFold(x, v) {
			return true
		}
	}
	return false
}

func containsFold(list []string, v string) bool {
	for _, x := range list {
		if strings.EqualFold(x, v) {
			return true
		}
	}
	return false
}

func sortedCopy(in []string) []string {
	out := slices.Clone(in)
	slices.Sort(out)
	return out
}

// String maakt Reason leesbaar in testmeldingen.
func (r Reason) String() string { return fmt.Sprintf("%s%v", r.Code, r.Params) }
