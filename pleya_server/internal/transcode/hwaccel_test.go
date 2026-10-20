package transcode_test

import (
	"context"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/transcode"
)

// Zonder render-device is software het antwoord, met een reden.
func TestDetectHWWithoutDeviceFallsBackToSoftwareWithAReason(t *testing.T) {
	st := transcode.DetectHW(context.Background(), "ffmpeg", "/dev/dri/bestaat-niet")
	if st.Accel != transcode.HWNone || st.Reason == "" {
		t.Fatalf("status %+v", st)
	}
}
