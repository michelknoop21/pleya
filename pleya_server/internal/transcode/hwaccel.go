package transcode

import (
	"context"
	"os"
	"os/exec"
	"strings"
	"time"
)

// DefaultRenderNode is het render-device van de DS920+ (Intel UHD 600).
const DefaultRenderNode = "/dev/dri/renderD128"

// HWStatus is wat opstarten vond. Het is zichtbaar voor beheer: wie
// versnelling verwacht en software krijgt moet kunnen zien waarom.
type HWStatus struct {
	Accel  HWAccel
	Node   string
	Reason string
}

// DetectHW kijkt of VAAPI werkt: het device bestaat, ffmpeg kent de methode, en
// een echte testcodering van een paar frames slaagt. Alleen dan telt het.
func DetectHW(ctx context.Context, ffmpegPath, node string) HWStatus {
	if node == "" {
		node = DefaultRenderNode
	}
	if _, err := os.Stat(node); err != nil {
		return HWStatus{Reason: "geen render-device op " + node}
	}
	ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, ffmpegPath, "-hide_banner", "-hwaccels").Output()
	if err != nil || !strings.Contains(string(out), "vaapi") {
		return HWStatus{Node: node, Reason: "deze ffmpeg kent vaapi niet"}
	}
	probe := exec.CommandContext(ctx, ffmpegPath, "-v", "error",
		"-init_hw_device", "vaapi=va:"+node, "-filter_hw_device", "va",
		"-f", "lavfi", "-i", "color=c=black:s=128x128:d=0.2",
		"-vf", "format=nv12,hwupload", "-c:v", "h264_vaapi", "-f", "null", "-")
	if msg, err := probe.CombinedOutput(); err != nil {
		reason := strings.TrimSpace(string(msg))
		if reason == "" {
			reason = err.Error()
		}
		if len(reason) > 200 {
			reason = reason[:200]
		}
		return HWStatus{Node: node, Reason: "testcodering mislukte: " + reason}
	}
	return HWStatus{Accel: HWVAAPI, Node: node}
}
