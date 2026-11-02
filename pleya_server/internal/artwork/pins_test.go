package artwork

import (
	"bytes"
	"encoding/binary"
	"hash/crc32"
	"image"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func TestPinAfbeeldingenFormaatDimensiesEnBytegrens(t *testing.T) {
	small := image.NewRGBA(image.Rect(0, 0, 3, 4))
	var pngBytes, jpegBytes bytes.Buffer
	if err := png.Encode(&pngBytes, small); err != nil {
		t.Fatal(err)
	}
	if err := jpeg.Encode(&jpegBytes, small, nil); err != nil {
		t.Fatal(err)
	}
	for _, entry := range []struct {
		body []byte
		ext  string
	}{{pngBytes.Bytes(), ".png"}, {jpegBytes.Bytes(), ".jpg"}} {
		if err := validatePinImage(entry.body, entry.ext); err != nil {
			t.Fatalf("geldig %s: %v", entry.ext, err)
		}
	}
	// Synthetische WebP door dezelfde gepinde ffmpeg als de normale artworkladder.
	testsupport.HasFFmpeg(t)
	path := filepath.Join(t.TempDir(), "tiny.webp")
	testsupport.MakeImage(t, path, 4, 6)
	webp, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := validatePinImage(webp, ".webp"); err != nil {
		t.Fatalf("WebP-header: %v", err)
	}
	huge := append([]byte{}, pngBytes.Bytes()...)
	binary.BigEndian.PutUint32(huge[16:20], 20000)
	binary.BigEndian.PutUint32(huge[20:24], 20000)
	binary.BigEndian.PutUint32(huge[29:33], crc32.ChecksumIEEE(huge[12:29]))
	for n, entry := range []struct {
		body []byte
		ext  string
	}{{nil, ".png"}, {[]byte("<svg>geen raster</svg>"), ".png"}, {pngBytes.Bytes(), ".jpg"}, {jpegBytes.Bytes(), ".webp"}, {pngBytes.Bytes(), ".gif"}, {pngBytes.Bytes()[:20], ".png"}, {webp[:15], ".webp"}, {huge, ".png"}, {make([]byte, MaxPinBytes+1), ".jpg"}} {
		if err := validatePinImage(entry.body, entry.ext); err == nil {
			t.Fatalf("ongeldige afbeelding %d geaccepteerd", n)
		}
	}
}

func TestPinAfgekaptPixelpayloadMetGeldigeHeaderWordtGeweigerd(t *testing.T) {
	testsupport.HasFFmpeg(t)
	for _, ext := range []string{".png", ".jpg", ".webp"} {
		t.Run(ext, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "valid"+ext)
			testsupport.MakeImage(t, path, 40, 60)
			valid, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			var broken []byte
			for cut := len(valid) - 1; cut > 0; cut-- {
				candidate := valid[:cut]
				if _, _, err := image.DecodeConfig(bytes.NewReader(candidate)); err != nil {
					continue
				}
				if _, _, err := image.Decode(bytes.NewReader(candidate)); err != nil {
					broken = candidate
					break
				}
			}
			if broken == nil {
				t.Fatal("fixture heeft geen valide header met afgekapt pixelpayload")
			}
			if err := validatePinImage(broken, ext); err == nil {
				t.Fatal("geldig headerblok maar kapot pixelpayload als pin geaccepteerd")
			}
		})
	}
}
