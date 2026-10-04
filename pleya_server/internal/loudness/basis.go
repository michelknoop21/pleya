// Package loudness meet de geïntegreerde luidheid per audiostroom voor de
// Pleya Unified Loudness Engine.
//
// D2 uit ../../docs/pleya-server-loudness-measurement-proposal.md (D0,
// goedgekeurd): basis.go (deze file), measure.go (de ffmpeg-analysepas),
// metadata.go (de Opus-tagvertaling) en store.go (de conditionele publicatie).
// Het canonieke bewijsmodel is gedeeld met de client
// (lib/media/loudness_evidence.dart): dezelfde velden, dezelfde regel dat een
// ontbrekende metric null blijft en nooit 0, en dezelfde eis dat een meting op
// de ene basis niets zegt over een andere.
package loudness

// Basis is de decodeconfiguratie waaronder gemeten wordt: het wire-veld
// "basis" op LoudnessEvidence, en het eerste deel van de sleutel van
// stream_loudness.
type Basis struct {
	// Key moet letterlijk overeenkomen met LoudnessPolicy.clientBasis
	// (lib/services/loudness/loudness_planner.dart): de planner vergelijkt op
	// gelijkheid, en een rij op een andere basis is voor de client onzichtbaar
	// bewijs.
	Key string
}

// Native is de enige basis van vandaag. DEC-111 (afwijking 1) legt drc_scale 0
// vast en niet 1: mpv decodeert AC-3 met zijn eigen default (ac3drc 0), en de
// servermeting moet dezelfde bytes horen als de client, niet ffmpeg-cli's
// eigen default van drc_scale 1.
var Native = Basis{Key: "pcm-native-tl31-drc0"}

// DecodeArgs geeft de ffmpeg-decoderflags die vóór -i horen voor deze codec, op
// deze basis. Geen -ac: de kanaallayout blijft native, downmixbeleid is
// plannerterrein (PS-6) en geen serverzaak.
func (b Basis) DecodeArgs(codec string) []string {
	switch codec {
	case "ac3", "eac3":
		return []string{"-target_level", "-31", "-drc_scale", "0"}
	default:
		return nil
	}
}
