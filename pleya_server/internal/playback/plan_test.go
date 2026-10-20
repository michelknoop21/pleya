package playback_test

import (
	"errors"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/playback"
)

func strs(v ...string) playback.Cap[[]string] { return playback.Known(v, playback.Detected) }

func inferred(v ...string) playback.Cap[[]string] { return playback.Known(v, playback.Inferred) }

func ptr[T any](v T) *T { return &v }

// Een toestel dat alles zegt te kunnen wat een gewone speler kan.
func capable() playback.Capabilities {
	var c playback.Capabilities
	c.Decoder.VideoCodecs = strs("h264", "hevc")
	c.Decoder.AudioCodecs = strs("aac", "ac3", "eac3")
	c.Decoder.Containers = strs("mp4", "mkv")
	return c
}

func movie(container, vcodec, acodec string) playback.Source {
	return playback.Source{
		VersionID: "v1", Container: container, BitrateKbps: 8000,
		Video: &playback.VideoTrack{Codec: vcodec, BitDepth: 8},
		Audio: &playback.AudioTrack{Codec: acodec, Channels: 6},
	}
}

var anything = playback.Policy{AllowRemux: true, AllowTranscode: true}

// De tabel uit hoofdstuk 10.5: elke rij legt de levering én de reden vast,
// want een goed plan om de verkeerde reden is een latente bug.
func TestPlannerTable(t *testing.T) {
	hdrSource := movie("mkv", "hevc", "eac3")
	hdrSource.Video.BitDepth = 10
	hdrSource.Video.Transfer = "smpte2084"
	dv5 := movie("mkv", "hevc", "eac3")
	dv5.Video.DoviProfile = ptr(5)
	dv5.Video.Transfer = "smpte2084"
	truehd := movie("mkv", "h264", "truehd")
	bigRemote := movie("mkv", "hevc", "eac3")
	bigRemote.BitrateKbps = 60000

	tests := []struct {
		name   string
		src    playback.Source
		mutate func(*playback.Capabilities)
		mode   playback.Mode
		reason string
	}{
		{"alles past", movie("mkv", "h264", "eac3"), nil, playback.DirectPlay, playback.ReasonDirect},
		{"HEVC HDR10 naar een SDR-scherm dat dat meldt", hdrSource, func(c *playback.Capabilities) {
			c.Decoder.MaxBitDepth = playback.Known(10, playback.Detected)
			c.Display.HDRTransfers = strs("sdr")
		}, playback.Transcode, playback.ReasonVideoHDR},
		{"HEVC HDR10 naar een SDR-scherm dat dat alleen afleidt", hdrSource, func(c *playback.Capabilities) {
			c.Display.HDRTransfers = inferred("sdr")
		}, playback.DirectPlay, playback.ReasonDirect},
		{"Dolby Vision profiel 5 zonder DV-scherm", dv5, func(c *playback.Capabilities) {
			c.Display.HDRTransfers = strs("sdr", "hdr10")
		}, playback.Transcode, playback.ReasonVideoDovi},
		{"Dolby Vision profiel 5 met DV-scherm", dv5, func(c *playback.Capabilities) {
			c.Display.HDRTransfers = strs("sdr", "hdr10", "dolby_vision")
		}, playback.DirectPlay, playback.ReasonDirect},
		{"TrueHD zonder TrueHD-decoder", truehd, func(c *playback.Capabilities) {
			c.Audio.MaxChannels = playback.Known(2, playback.Detected)
		}, playback.DirectStream, playback.ReasonAudioCodec},
		{"E-AC-3 5.1 met passthrough", movie("mkv", "h264", "eac3"), func(c *playback.Capabilities) {
			c.Decoder.AudioCodecs = strs("aac")
			c.Audio.PassthroughCodecs = strs("eac3")
		}, playback.DirectPlay, playback.ReasonDirect},
		{"AV1 zonder AV1-decoder", movie("mkv", "av1", "aac"), nil, playback.Transcode, playback.ReasonVideoCodec},
		{"onbekende container met een codec die kan", movie("avi", "h264", "aac"), nil, playback.Remux, playback.ReasonContainer},
		{"4K over een remote verbinding met 8 Mbit", bigRemote, func(c *playback.Capabilities) {
			c.Connection.MaxBitrateKbps = playback.Known(8000, playback.Detected)
			c.Connection.IsLocal = playback.Known(false, playback.Detected)
		}, playback.Transcode, playback.ReasonBitrate},
		{"dezelfde bron lokaal negeert de limiet", bigRemote, func(c *playback.Capabilities) {
			c.Connection.MaxBitrateKbps = playback.Known(8000, playback.Detected)
			c.Connection.IsLocal = playback.Known(true, playback.Detected)
		}, playback.DirectPlay, playback.ReasonDirect},
		{"10 bit op een 8-bit decoder", hdrSource, func(c *playback.Capabilities) {
			c.Decoder.MaxBitDepth = playback.Known(8, playback.Detected)
		}, playback.Transcode, playback.ReasonVideoBitDepth},
		{"profiel dat de decoder niet noemt", func() playback.Source {
			s := movie("mkv", "hevc", "aac")
			s.Video.Profile = "Main 10"
			return s
		}(), func(c *playback.Capabilities) { c.Decoder.VideoProfiles = strs("Main") },
			playback.Transcode, playback.ReasonVideoProfile},
		// Onbekend houdt het gedrag van vóór PS-5: direct play.
		{"alles onbekend", movie("avi", "av1", "truehd"), func(c *playback.Capabilities) { *c = playback.Capabilities{} },
			playback.DirectPlay, playback.ReasonDirect},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			caps := capable()
			if tc.mutate != nil {
				tc.mutate(&caps)
			}
			plan, err := playback.Decide([]playback.Source{tc.src}, caps, anything)
			if err != nil {
				t.Fatal(err)
			}
			if plan.Mode != tc.mode {
				t.Fatalf("levering %s, verwacht %s (%v)", plan.Mode, tc.mode, plan.Reasons)
			}
			if plan.Reasons[0].Code != tc.reason {
				t.Fatalf("reden %s, verwacht %s", plan.Reasons[0].Code, tc.reason)
			}
			if (plan.Mode == playback.DirectPlay) != plan.Seekable {
				t.Fatalf("seekbaarheid %v bij %s", plan.Seekable, plan.Mode)
			}
		})
	}
}

// Bij twee versies wint de goedkoopste die past, niet de beste.
func TestPlannerPicksTheCheapestFittingVersion(t *testing.T) {
	big := movie("mkv", "h264", "aac")
	big.VersionID, big.BitrateKbps = "groot", 40000
	small := movie("mkv", "h264", "aac")
	small.VersionID, small.BitrateKbps = "klein", 4000
	incompatible := movie("mkv", "av1", "aac")
	incompatible.VersionID, incompatible.BitrateKbps = "av1", 1000

	plan, err := playback.Decide([]playback.Source{big, incompatible, small}, capable(), anything)
	if err != nil || plan.VersionID != "klein" {
		t.Fatalf("plan %+v, %v", plan, err)
	}
	// Past alleen de grote, dan wint die.
	plan, err = playback.Decide([]playback.Source{incompatible, big}, capable(), anything)
	if err != nil || plan.VersionID != "groot" {
		t.Fatalf("plan %+v, %v", plan, err)
	}
}

// Laat het harde filter niets over, dan is dat een fout met reden en geen
// willekeurig laatste plan.
func TestPlannerErrorsWhenNothingIsAllowed(t *testing.T) {
	_, err := playback.Decide([]playback.Source{movie("mkv", "av1", "aac")}, capable(), playback.Policy{})
	var np *playback.NotPlayableError
	if !errors.As(err, &np) {
		t.Fatalf("fout %v", err)
	}
	if np.Reasons[0].Code != playback.ReasonVideoCodec || np.Reasons[len(np.Reasons)-1].Code != playback.ReasonTranscodeDisallowd {
		t.Fatalf("redenen %v", np.Reasons)
	}
	if _, err := playback.Decide(nil, capable(), anything); !errors.As(err, &np) {
		t.Fatalf("geen versies gaf %v", err)
	}
}

// Wat direct speelde, blijft direct spelen, ook als de server niets mag omzetten.
func TestDirectPlayStaysDirectPlayWithoutTranscoder(t *testing.T) {
	plan, err := playback.Decide([]playback.Source{movie("mkv", "h264", "aac")}, capable(), playback.Policy{})
	if err != nil || plan.Mode != playback.DirectPlay {
		t.Fatalf("plan %+v, %v", plan, err)
	}
}
