package artwork

import (
	"image"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

func TestLogoPlanNeverRoutesTransparentMarksThroughJPEG(t *testing.T) {
	// Plan only needs a decoder and an available executable; no image conversion
	// is invoked here. The ordinary poster control proves the precondition.
	r := New("true", t.TempDir(), quiet())
	src := filepath.Join(t.TempDir(), "logo.png")
	f, err := os.Create(src)
	if err != nil {
		t.Fatal(err)
	}
	if err := png.Encode(f, image.NewNRGBA(image.Rect(0, 0, 1000, 400))); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	if r.Plan(src, "poster", 300) != 480 {
		t.Fatal("ordinary conversion precondition failed")
	}
	if r.Plan(src, "logo:fixture", 300) != 0 {
		t.Fatal("transparent title mark would be converted to opaque JPEG")
	}
}
