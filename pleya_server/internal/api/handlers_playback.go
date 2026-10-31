package api

import (
	"errors"
	"net/http"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/playback"
	"github.com/edde746/plezy/pleya_server/internal/transcode"
)

// CapabilityWire is één capability van het toestel (architectuur 9.1). Een
// ontbrekende value, of confidence unknown, zegt dat het toestel het niet weet.
type CapabilityWire[T any] struct {
	Value      *T     `json:"value"`
	Confidence string `json:"confidence"`
	Overridden bool   `json:"overridden,omitempty"`
}

// DeviceCapabilitiesWire is de vorm die de client uit PS-5 stuurt.
type DeviceCapabilitiesWire struct {
	Decoder struct {
		VideoCodecs   CapabilityWire[[]string] `json:"video_codecs"`
		AudioCodecs   CapabilityWire[[]string] `json:"audio_codecs"`
		Containers    CapabilityWire[[]string] `json:"containers"`
		VideoProfiles CapabilityWire[[]string] `json:"video_profiles"`
		MaxBitDepth   CapabilityWire[int]      `json:"max_bit_depth"`
	} `json:"decoder"`
	Display struct {
		HDRTransfers CapabilityWire[[]string] `json:"hdr_transfers"`
	} `json:"display"`
	Audio struct {
		MaxChannels       CapabilityWire[int]      `json:"max_channels"`
		PassthroughCodecs CapabilityWire[[]string] `json:"passthrough_codecs"`
	} `json:"audio"`
	Connection struct {
		IsLocal        CapabilityWire[bool] `json:"is_local"`
		MaxBitrateKbps CapabilityWire[int]  `json:"max_bitrate_kbps"`
	} `json:"connection"`
}

// PlaybackPlanRequest is de body van POST /playback/plan.
type PlaybackSubtitleSelection struct {
	Mode     string  `json:"mode"`
	StreamID *string `json:"stream_id,omitempty"`
}

type PlaybackSubtitlePlan struct {
	Action   string  `json:"action"`
	StreamID *string `json:"stream_id,omitempty"`
	URL      *string `json:"url,omitempty"`
	Format   *string `json:"format,omitempty"`
}

type PlaybackPlanRequest struct {
	Subtitle      *PlaybackSubtitleSelection `json:"subtitle,omitempty"`
	Quality       *playback.Quality          `json:"quality,omitempty"`
	AudioStreamID *string                    `json:"audio_stream_id,omitempty"`
	ItemID        string                     `json:"item_id"`
	VersionID     *string                    `json:"version_id,omitempty"`
	Capabilities  *DeviceCapabilitiesWire    `json:"capabilities,omitempty"`
}

// PlaybackReason is een domeincode met parameters.
type PlaybackReason struct {
	Code   string         `json:"code"`
	Params map[string]any `json:"params"`
}

// PlaybackTrackPlan zegt wat er met één spoor gebeurt.
type PlaybackTrackPlan struct {
	Action   string  `json:"action"`
	Codec    *string `json:"codec,omitempty"`
	Channels *int    `json:"channels,omitempty"`
}

// PlaybackPlan is het antwoord van POST /playback/plan.
type PlaybackPlan struct {
	Subtitle              *PlaybackSubtitlePlan `json:"subtitle,omitempty"`
	EffectiveQuality      *playback.Quality     `json:"effective_quality,omitempty"`
	SelectedAudioStreamID *string               `json:"selected_audio_stream_id,omitempty"`
	ItemID                string                `json:"item_id"`
	VersionID             string                `json:"version_id"`
	DeliveryMode          string                `json:"delivery_mode"`
	StreamURL             string                `json:"stream_url"`
	Container             string                `json:"container"`
	Video                 PlaybackTrackPlan     `json:"video"`
	Audio                 PlaybackTrackPlan     `json:"audio"`
	Seekable              bool                  `json:"seekable"`
	SessionID             *string               `json:"session_id"`
	Reason                PlaybackReason        `json:"reason"`
	Reasons               []PlaybackReason      `json:"reasons"`
}

func (s *Server) handlePlaybackPlan(w http.ResponseWriter, r *http.Request) {
	var req PlaybackPlanRequest
	if !s.decodeBody(w, r, &req, CodeNotFound) {
		return
	}
	itemID, err := id.Parse(strings.TrimSpace(req.ItemID))
	if err != nil {
		writeError(w, s.log, CodeNotFound, "item not found", nil)
		return
	}
	var wantVersion *id.ID
	if req.VersionID != nil {
		v, err := id.Parse(strings.TrimSpace(*req.VersionID))
		if err != nil {
			writeError(w, s.log, CodeNotFound, "version not found", nil)
			return
		}
		wantVersion = &v
	}

	item, err := s.opts.Catalog.Item(r.Context(), itemID)
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	if !s.authorizeLibrary(w, r, item.LibraryID) {
		return
	}

	if req.Quality != nil && (req.Quality.MaxVideoBitrateKbps < 1 || req.Quality.MaxVideoBitrateKbps > 100000 || req.Quality.MaxHeight < 1 || req.Quality.MaxHeight > 4320) || req.AudioStreamID != nil && req.VersionID == nil {
		writeError(w, s.log, CodePlaybackSelectionInvalid, "invalid playback selection", nil)
		return
	}
	if sub := req.Subtitle; sub != nil {
		if (sub.Mode != "off" && sub.Mode != "external" && sub.Mode != "burn") ||
			(sub.Mode == "off" && sub.StreamID != nil) ||
			(sub.Mode != "off" && (sub.StreamID == nil || req.VersionID == nil)) {
			writeError(w, s.log, CodePlaybackSelectionInvalid, "invalid subtitle selection", nil)
			return
		}
	}
	var subtitleStream *catalog.Stream
	var sources []playback.Source
	for _, v := range item.Versions {
		if wantVersion != nil && v.ID != *wantVersion {
			continue
		}
		if sub := req.Subtitle; sub != nil && sub.Mode != "off" {
			for _, stream := range v.Streams {
				if stream.Kind == "subtitle" && stream.ID.String() == *sub.StreamID && stream.SubtitleFormat != "" {
					copy := stream
					subtitleStream = &copy
					break
				}
			}
		}
		src := planSource(v)
		if req.AudioStreamID != nil {
			src.Audio = nil
			for _, stream := range v.Streams {
				if stream.ID.String() == *req.AudioStreamID && stream.Kind == "audio" && !stream.IsExternal && stream.Index != nil {
					src.Audio = &playback.AudioTrack{ID: stream.ID.String(), Index: stream.Index, Codec: stream.Codec}
					if stream.Channels != nil {
						src.Audio.Channels = *stream.Channels
					}
					break
				}
			}
			if src.Audio == nil {
				writeError(w, s.log, CodeNotFound, "audio stream not found", nil)
				return
			}
		}
		sources = append(sources, src)
	}
	if len(sources) == 0 {
		if wantVersion != nil {
			writeError(w, s.log, CodeNotFound, "version not found", nil)
			return
		}
		writeError(w, s.log, CodeVersionUnavailable, "item has no playable version", nil)
		return
	}

	if req.Subtitle != nil && req.Subtitle.Mode != "off" && subtitleStream == nil {
		writeError(w, s.log, CodeNotFound, "subtitle not found", nil)
		return
	}
	var caps playback.Capabilities
	if req.Capabilities != nil {
		caps = req.Capabilities.model()
	}
	policy := s.playbackPolicy()
	policy.Quality, policy.SelectAudio = req.Quality, req.AudioStreamID != nil
	policy.BurnSubtitles = req.Subtitle != nil && req.Subtitle.Mode == "burn"
	plan, err := playback.Decide(sources, caps, policy)
	var np *playback.NotPlayableError
	if errors.As(err, &np) {
		writeError(w, s.log, CodeNotPlayable, "no version can be played on this device",
			map[string]any{"reasons": reasonsWire(np.Reasons)})
		return
	}
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	var subtitlePlan *PlaybackSubtitlePlan
	if req.Subtitle != nil {
		subtitlePlan = &PlaybackSubtitlePlan{Action: req.Subtitle.Mode, StreamID: req.Subtitle.StreamID}
		if subtitleStream != nil {
			format := subtitleStream.SubtitleFormat
			subtitlePlan.Format = &format
			if req.Subtitle.Mode == "external" {
				url := "/pleya/v1/subtitles/" + subtitleStream.ID.String()
				subtitlePlan.URL = &url
			} else if req.Subtitle.Mode == "burn" {
				file, _, _, fileErr := s.opts.Catalog.SubtitleFile(r.Context(), subtitleStream.ID)
				index := 0
				if errors.Is(fileErr, catalog.ErrNotFound) {
					file, _, _, index, fileErr = s.opts.Catalog.EmbeddedSubtitleFile(r.Context(), subtitleStream.ID)
				}
				if fileErr != nil {
					s.writeStoreError(w, fileErr)
					return
				}
				if format == "pgs" || format == "dvdsub" {
					// Burned straight from the source: an extraction reads the whole file for what ffmpeg
					// demuxes anyway, and a separate input would lose the cue times.
					plan.SubtitleBitmap, plan.SubtitleStream = true, index
				} else {
					user, subjectErr := s.subjectID(r)
					if subjectErr != nil {
						writeInternal(w, s.log, subjectErr)
						return
					}
					path, extractErr := s.opts.Transcode.ExtractSubtitle(r.Context(), transcode.SubtitleParams{
						User: user, InputPath: file.AbsPath, StreamIndex: index, Format: file.Format, Generation: file.Generation,
					})
					if extractErr != nil {
						s.writeSubtitlePreparationError(w, r, subtitleStream.ID, extractErr)
						return
					}
					plan.SubtitlePath = path
				}
			}
		}
	}
	// Preparation may outlive credentials or a library grant.
	s.authenticated(func(w http.ResponseWriter, fresh *http.Request) {
		if !s.authorizeLibrary(w, fresh, item.LibraryID) {
			return
		}
		var sess *transcode.Session
		if plan.Mode != playback.DirectPlay {
			var ok bool
			if sess, ok = s.startTranscode(w, fresh, plan, chosenSource(sources, plan.VersionID)); !ok {
				return
			}
		}
		s.opts.Metrics.Inc("pleya_playback_plans_total", "Afspeelplannen per leveringswijze.", "mode", string(plan.Mode))
		response := mapPlan(itemID, plan, sess)
		response.EffectiveQuality = plan.Quality
		response.SelectedAudioStreamID = req.AudioStreamID
		response.Subtitle = subtitlePlan
		writeJSON(w, http.StatusOK, response)
	}).ServeHTTP(w, r)
}

func chosenSource(sources []playback.Source, versionID string) playback.Source {
	for _, src := range sources {
		if src.VersionID == versionID {
			return src
		}
	}
	return playback.Source{}
}

func planSource(v catalog.Version) playback.Source {
	src := playback.Source{VersionID: v.ID.String(), Container: v.Container}
	if v.BitrateBps != nil {
		src.BitrateKbps = *v.BitrateBps / 1000
	}
	var firstAudio *catalog.Stream
	for i := range v.Streams {
		st := &v.Streams[i]
		switch {
		case st.Kind == "video" && src.Video == nil:
			vt := &playback.VideoTrack{Codec: st.Codec, Profile: st.Profile, Transfer: st.ColorTransfer, DoviProfile: st.DoviProfile}
			if st.BitDepth != nil {
				vt.BitDepth = *st.BitDepth
			}
			src.Video = vt
		case st.Kind == "audio" && !st.IsExternal:
			if firstAudio == nil || (st.IsDefault && !firstAudio.IsDefault) {
				firstAudio = st
			}
		}
	}
	if firstAudio != nil {
		at := &playback.AudioTrack{ID: firstAudio.ID.String(), Index: firstAudio.Index, Codec: firstAudio.Codec}
		if firstAudio.Channels != nil {
			at.Channels = *firstAudio.Channels
		}
		src.Audio = at
	}
	return src
}

func capOf[T any](c CapabilityWire[T]) playback.Cap[T] {
	if c.Value == nil || c.Confidence == string(playback.Unknown) {
		return playback.Cap[T]{}
	}
	conf := playback.Confidence(c.Confidence)
	if conf != playback.Detected && conf != playback.Inferred {
		// Een zekerheid die de server niet kent telt als de zwakste bekende:
		// de waarde wordt gebruikt, maar nooit zwaarder dan een afleiding.
		conf = playback.Inferred
	}
	return playback.Cap[T]{Known: true, Value: *c.Value, Confidence: conf, Overridden: c.Overridden}
}

func (c *DeviceCapabilitiesWire) model() playback.Capabilities {
	var m playback.Capabilities
	m.Decoder.VideoCodecs = capOf(c.Decoder.VideoCodecs)
	m.Decoder.AudioCodecs = capOf(c.Decoder.AudioCodecs)
	m.Decoder.Containers = capOf(c.Decoder.Containers)
	m.Decoder.VideoProfiles = capOf(c.Decoder.VideoProfiles)
	m.Decoder.MaxBitDepth = capOf(c.Decoder.MaxBitDepth)
	m.Display.HDRTransfers = capOf(c.Display.HDRTransfers)
	m.Audio.MaxChannels = capOf(c.Audio.MaxChannels)
	m.Audio.PassthroughCodecs = capOf(c.Audio.PassthroughCodecs)
	m.Connection.IsLocal = capOf(c.Connection.IsLocal)
	m.Connection.MaxBitrateKbps = capOf(c.Connection.MaxBitrateKbps)
	return m
}

func reasonsWire(in []playback.Reason) []PlaybackReason {
	out := make([]PlaybackReason, 0, len(in))
	for _, r := range in {
		params := r.Params
		if params == nil {
			params = map[string]any{}
		}
		out = append(out, PlaybackReason{Code: r.Code, Params: params})
	}
	return out
}

func mapPlan(itemID id.ID, p playback.Plan, sess *transcode.Session) PlaybackPlan {
	reasons := reasonsWire(p.Reasons)
	audio := PlaybackTrackPlan{Action: p.AudioAction}
	if p.AudioAction == "transcode" {
		codec, ch := p.AudioCodec, p.AudioMaxCh
		audio.Codec, audio.Channels = &codec, &ch
	}
	streamURL := "/pleya/v1/stream/" + p.VersionID
	var sessionID *string
	if sess != nil {
		sid := sess.ID.String()
		sessionID = &sid
		streamURL = "/pleya/v1/playback/sessions/" + sid + "/" + transcode.PlaylistName
	}
	return PlaybackPlan{
		ItemID:       itemID.String(),
		VersionID:    p.VersionID,
		DeliveryMode: string(p.Mode),
		StreamURL:    streamURL,
		SessionID:    sessionID,
		Container:    p.Container,
		Video:        PlaybackTrackPlan{Action: p.VideoAction},
		Audio:        audio,
		Seekable:     p.Seekable,
		Reason:       reasons[0],
		Reasons:      reasons,
	}
}
