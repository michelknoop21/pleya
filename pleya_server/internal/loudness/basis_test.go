package loudness_test

import (
	"reflect"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/loudness"
)

// TestNativeBasisKeyMatchesTheClient dekt de enige regel die er echt toe doet:
// een andere sleutel dan LoudnessPolicy.clientBasis
// (lib/services/loudness/loudness_planner.dart) maakt elke servermeting voor
// de planner onzichtbaar bewijs, zonder dat er ooit een foutmelding komt.
func TestNativeBasisKeyMatchesTheClient(t *testing.T) {
	const clientBasis = "pcm-native-tl31-drc0"
	if loudness.Native.Key != clientBasis {
		t.Fatalf("Native.Key = %q, verwacht %q (LoudnessPolicy.clientBasis)", loudness.Native.Key, clientBasis)
	}
}

func TestDecodeArgsOnlyTouchesAc3Family(t *testing.T) {
	cases := []struct {
		codec string
		want  []string
	}{
		{"ac3", []string{"-target_level", "-31", "-drc_scale", "0"}},
		{"eac3", []string{"-target_level", "-31", "-drc_scale", "0"}},
		{"aac", nil},
		{"opus", nil},
		{"flac", nil},
	}
	for _, c := range cases {
		got := loudness.Native.DecodeArgs(c.codec)
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("DecodeArgs(%q) = %v, verwacht %v", c.codec, got, c.want)
		}
	}
}
