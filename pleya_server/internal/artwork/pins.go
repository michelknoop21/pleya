package artwork

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"time"

	_ "golang.org/x/image/webp"
	"golang.org/x/sync/singleflight"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/metadata"
)

const MaxPinBytes = 12 << 20

var ErrPinUnavailable = errors.New("gekozen artworkbron niet beschikbaar")
var ErrPinSourceChanged = errors.New("gekozen artworkbron heeft andere bytes")
var ErrPinImage = errors.New("ongeldige artworkafbeelding")

type imageProvider interface {
	Image(context.Context, string, string) ([]byte, string, error)
}
type imageLister interface {
	Images(context.Context, string, int) ([]metadata.ImageChoice, error)
}
type PinCandidate struct {
	ID        string
	Kind      string
	Source    string
	ArtworkID *id.ID
	FileID    *id.ID
	Ref       string
	SHA256    string
	Language  *string
	Available bool
}
type PinStatus struct {
	Pin       catalog.ArtworkPin
	State     string
	ErrorCode string
}
type PinChoices struct {
	State         catalog.ArtworkState
	Candidates    []PinCandidate
	Pins          []PinStatus
	ProviderState string
}

// Pins bewaart uitsluitend afgeleide cachebytes. De catalogus bewaart intentie,
// bronlocator en verwachte byte-identiteit; /config en de backup blijven vrij van beelden.
type Pins struct {
	store    *catalog.Store
	provider imageProvider
	cache    string
	sf       singleflight.Group
}

func NewPins(store *catalog.Store, provider imageProvider, cache string) *Pins {
	return &Pins{store: store, provider: provider, cache: cache}
}
func (p *Pins) Available() bool    { return p != nil && p.store != nil && p.cache != "" }
func pinDigest(data []byte) string { sum := sha256.Sum256(data); return hex.EncodeToString(sum[:]) }
func candidateID(token string, c PinCandidate) string {
	raw := token + "\x00" + c.Kind + "\x00" + c.Source + "\x00" + c.Ref + "\x00" + c.SHA256
	if c.FileID != nil {
		raw += "\x00" + c.FileID.String()
	}
	return pinDigest([]byte(raw))
}

// validatePinHeader begrenst de bron vóór enige volledige pixeldecode.
// Bestaande jpeg/png/webp-,12MiB-grens plus begrensde dimensies voor lokale bronbestanden.
func validatePinHeader(data []byte, ext string) error {
	expected := map[string]string{".jpg": "image/jpeg", ".png": "image/png", ".webp": "image/webp"}[ext]
	if len(data) == 0 || len(data) > MaxPinBytes || expected == "" || http.DetectContentType(data) != expected {
		return ErrPinImage
	}
	config, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil || config.Width < 1 || config.Height < 1 || config.Width > 20000 || config.Height > 20000 || int64(config.Width)*int64(config.Height) > 16000000 {
		return ErrPinImage
	}
	return nil
}

// Maximaal twee volledige decodes/herbouwen tegelijk in dit proces. De gate
// omvat alle volle buffers: ophalen, warme cache, kandidaten en status.
// Wachtende grids stapelen geen bronbuffers of pixelrasters op.
// Maximaal 16 MP per beeld: samen maximaal 256 MiB voor twee 16-bit-RGBA-
// rasters, plus decoderwerkruimte en maximaal 24 MiB bronbuffers. Wachten is
// context-cancellable; een al lopende decode blijft door de pixelgrens begrensd.
var pinDecodeSlots = make(chan struct{}, 2)

func acquirePinDecode(ctx context.Context) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	select {
	case pinDecodeSlots <- struct{}{}:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
func releasePinDecode() { <-pinDecodeSlots }
func validatePinImage(data []byte, ext string) error {
	if err := validatePinHeader(data, ext); err != nil {
		return err
	}
	if _, _, err := image.Decode(bytes.NewReader(data)); err != nil {
		return ErrPinImage
	}
	return nil
}

func readPinFile(ctx context.Context, path string) ([]byte, string, error) {
	if err := ctx.Err(); err != nil {
		return nil, "", err
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, "", ErrPinUnavailable
	}
	defer file.Close()
	stat, err := file.Stat()
	if err != nil || !stat.Mode().IsRegular() || stat.Size() > MaxPinBytes {
		return nil, "", ErrPinImage
	}
	body, err := io.ReadAll(io.LimitReader(pinReadContext{ctx: ctx, Reader: file}, MaxPinBytes+1))
	if ctx.Err() != nil {
		return nil, "", ctx.Err()
	}
	if err != nil {
		return nil, "", ErrPinUnavailable
	}
	ext := map[string]string{"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}[http.DetectContentType(body)]
	if err := validatePinHeader(body, ext); err != nil {
		return nil, "", err
	}
	return body, ext, nil
}

// De body blijft binnen deze scope tot na de hash; pas daarna gaat het slot vrij.
// Aanroepers krijgen uitsluitend een digest, geen volle buffer buiten de gate.
func pinFileDigest(ctx context.Context, path string) (string, string, error) {
	if err := acquirePinDecode(ctx); err != nil {
		return "", "", err
	}
	defer releasePinDecode()
	body, ext, err := readPinFile(ctx, path)
	if err != nil {
		return "", "", err
	}
	if err := ctx.Err(); err != nil {
		return "", "", err
	}
	return pinDigest(body), ext, nil
}

type pinReadContext struct {
	io.Reader
	ctx context.Context
}

func (r pinReadContext) Read(body []byte) (int, error) {
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	return r.Reader.Read(body)
}
func (p *Pins) local(ctx context.Context, fileID id.ID, itemID id.ID, kind string) ([]byte, string, error) {
	file, err := p.store.ArtworkSourceFile(ctx, fileID, itemID, kind)
	if err != nil {
		return nil, "", ErrPinUnavailable
	}
	return readPinFile(ctx, file.AbsPath)
}
func (p *Pins) Choices(ctx context.Context, state catalog.ArtworkState) (PinChoices, error) {
	return p.choices(ctx, state, true)
}
func (p *Pins) choices(ctx context.Context, state catalog.ArtworkState, recoverPins bool) (PinChoices, error) {
	out := PinChoices{State: state, Candidates: []PinCandidate{}, Pins: []PinStatus{}, ProviderState: "not_configured"}
	seen := map[string]bool{}
	counts := map[string]int{}
	locals := map[string]int{}
	appendChoice := func(c PinCandidate) {
		key := c.Kind + "\x00" + c.Source + "\x00" + c.Ref
		if c.FileID != nil {
			key += c.FileID.String()
		}
		if seen[key] || counts[c.Kind] >= 20 {
			return
		}
		seen[key] = true
		counts[c.Kind]++
		c.ID = candidateID(state.Token, c)
		out.Candidates = append(out.Candidates, c)
	}
	for _, source := range state.Sources {
		if source.Source == "local" {
			if source.FileID == nil || locals[source.Kind] >= 8 {
				continue
			}
			locals[source.Kind]++
			c := PinCandidate{Kind: source.Kind, Source: "local", ArtworkID: source.ArtworkID, FileID: source.FileID}
			file, err := p.store.ArtworkSourceFile(ctx, *source.FileID, state.ItemID, source.Kind)
			if err == nil {
				c.SHA256, _, err = pinFileDigest(ctx, file.AbsPath)
			}
			if ctx.Err() != nil {
				return out, ctx.Err()
			}
			c.Available = err == nil
			appendChoice(c)

		}
	}
	if lister, ok := p.provider.(imageLister); ok {
		if state.AppliedProvider == nil || *state.AppliedProvider != "tmdb" || state.AppliedExternalID == nil {
			out.ProviderState = "identity_unknown"
		} else {
			number, err := strconv.Atoi(*state.AppliedExternalID)
			if err != nil || number <= 0 || strconv.Itoa(number) != *state.AppliedExternalID {
				out.ProviderState = "identity_unknown"
			} else {
				alternatives, err := lister.Images(ctx, state.Kind, number)
				if err != nil {
					out.ProviderState = "unavailable"
				} else {
					out.ProviderState = "available"
					for _, choice := range alternatives {
						if (choice.Kind == "poster" || choice.Kind == "backdrop") && metadata.ValidImageRef(choice.Ref) {
							appendChoice(PinCandidate{Kind: choice.Kind, Source: "tmdb", Ref: choice.Ref, Language: choice.Language, Available: true})
						}
					}
				}
			}
		}
	}
	for _, pin := range state.Pins {
		if !recoverPins {
			continue
		}
		status := PinStatus{Pin: pin, State: "ready"}
		if _, err := p.Resolve(ctx, pin); err != nil {
			status.State = "unavailable"
			status.ErrorCode = pinErrorCode(err)
		}
		out.Pins = append(out.Pins, status)
	}
	return out, nil
}
func pinErrorCode(err error) string {
	if errors.Is(err, ErrPinSourceChanged) {
		return "source_changed"
	}
	if errors.Is(err, ErrPinImage) {
		return "invalid_image"
	}
	return "source_unavailable"
}

// Prepare kiest uitsluitend een opnieuw gevonden item-/rolgebonden kandidaat.
// De gebruiker stuurt geen providerref of bestandspad. Falen publiceert niets.
func (p *Pins) Prepare(ctx context.Context, state catalog.ArtworkState, selection map[string]*string) (map[string]*catalog.ArtworkPin, error) {
	if !p.Available() {
		return nil, ErrPinUnavailable
	}
	changes := map[string]*catalog.ArtworkPin{}
	needsChoices := false
	for kind, choice := range selection {
		if kind != "poster" && kind != "backdrop" {
			return nil, catalog.ErrArtworkInvalid
		}
		if choice != nil {
			needsChoices = true
		}
		changes[kind] = nil
	}
	if len(changes) == 0 {
		return nil, catalog.ErrArtworkInvalid
	}
	if !needsChoices {
		return changes, nil
	}
	choices, err := p.choices(ctx, state, false)
	if err != nil {
		return nil, err
	}
	for kind, wanted := range selection {
		if wanted == nil {
			continue
		}
		var chosen *PinCandidate
		for i := range choices.Candidates {
			c := &choices.Candidates[i]
			if c.Kind == kind && c.ID == *wanted {
				chosen = c
				break
			}
		}
		if chosen == nil {
			return nil, catalog.ErrArtworkStale
		}
		if !chosen.Available {
			return nil, ErrPinUnavailable
		}
		if err := acquirePinDecode(ctx); err != nil {
			return nil, err
		}
		pin, prepareErr := func() (*catalog.ArtworkPin, error) {
			defer releasePinDecode()
			var body []byte
			var ext string
			if chosen.Source == "local" {
				body, ext, err = p.local(ctx, *chosen.FileID, state.ItemID, kind)
			} else {
				if chosen.ArtworkID != nil {
					if file, _, getErr := p.store.ProviderArtworkFile(ctx, *chosen.ArtworkID, p.cache); getErr == nil {
						body, ext, err = readPinFile(ctx, file.AbsPath)
					}
				}
				if len(body) == 0 || err != nil {
					if p.provider == nil {
						return nil, ErrPinUnavailable
					}
					body, ext, err = p.provider.Image(ctx, kind, chosen.Ref)
				}
			}
			if err != nil {
				return nil, ErrPinUnavailable
			}
			if err := ctx.Err(); err != nil {
				return nil, err
			}
			if err := validatePinImage(body, ext); err != nil {
				return nil, err
			}
			sum := pinDigest(body)
			if chosen.SHA256 != "" && sum != chosen.SHA256 {
				return nil, ErrPinSourceChanged
			}
			pin := catalog.ArtworkPin{ID: id.New(), ItemID: state.ItemID, Kind: kind, Source: chosen.Source, FileID: chosen.FileID, SHA256: sum, Extension: ext}
			if chosen.Source == "tmdb" {
				ref := chosen.Ref
				pin.Ref = &ref
			}
			if err := p.writeCache(ctx, pin, body); err != nil {
				return nil, err
			}
			if err := ctx.Err(); err != nil {
				return nil, err
			}
			return &pin, nil
		}()
		if prepareErr != nil {
			return nil, prepareErr
		}
		changes[kind] = pin
	}
	return changes, nil
}
func (p *Pins) cachePath(pin catalog.ArtworkPin) string {
	return filepath.Join(p.cache, "artwork-pins", pin.ID.String()+"_"+pin.SHA256+pin.Extension)
}
func (p *Pins) writeCache(ctx context.Context, pin catalog.ArtworkPin, body []byte) error {
	return retryPinCacheWrite(ctx, func() error { return p.writeCacheAttempt(pin, body) })
}

// De afgeleide cachemap kan tijdens een write verdwijnen. Herhaal alleen die
// ENOENT-grens, met dezelfde gevalideerde bytes en een vaste bovengrens; andere
// opslagfouten en annulering blijven zichtbaar voor de aanroeper.
func retryPinCacheWrite(ctx context.Context, attempt func() error) error {
	for n := 0; ; n++ {
		if err := ctx.Err(); err != nil {
			return err
		}
		err := attempt()
		if !errors.Is(err, os.ErrNotExist) || n == 2 {
			return err
		}
		timer := time.NewTimer(10 * time.Millisecond)
		select {
		case <-ctx.Done():
			timer.Stop()
			return ctx.Err()
		case <-timer.C:
		}
	}
}

func (p *Pins) writeCacheAttempt(pin catalog.ArtworkPin, body []byte) error {
	dir := filepath.Join(p.cache, "artwork-pins")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	file, err := os.CreateTemp(dir, ".incoming-*")
	if err != nil {
		return err
	}
	name := file.Name()
	defer os.Remove(name)
	if _, err := file.Write(body); err != nil {
		file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(name, p.cachePath(pin))
}

// Resolve houdt de gekozen SHA ook na cacheverlies vast. Ander bronmateriaal
// wordt nooit onder dezelfde keuze-ID gepubliceerd; bronverlies trekt de pin niet in.
func (p *Pins) Resolve(ctx context.Context, pin catalog.ArtworkPin) (catalog.FileOnDisk, error) {
	if !p.Available() {
		return catalog.FileOnDisk{}, ErrPinUnavailable
	}
	file := catalog.FileOnDisk{ID: pin.ID, AbsPath: p.cachePath(pin), Role: catalog.RoleArtwork, Generation: 1, Kind: pin.Kind}
	result := p.sf.DoChan(pin.ID.String(), func() (any, error) {
		if err := acquirePinDecode(ctx); err != nil {
			return nil, err
		}
		defer releasePinDecode()
		if body, ext, err := readPinFile(ctx, file.AbsPath); err == nil && ext == pin.Extension && pinDigest(body) == pin.SHA256 {
			return nil, nil
		}
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		var body []byte
		var ext string
		var err error
		if pin.Source == "local" && pin.FileID != nil {
			body, ext, err = p.local(ctx, *pin.FileID, pin.ItemID, pin.Kind)
		} else if pin.Source == "tmdb" && pin.Ref != nil && metadata.ValidImageRef(*pin.Ref) && p.provider != nil {
			body, ext, err = p.provider.Image(ctx, pin.Kind, *pin.Ref)
		} else {
			return nil, ErrPinUnavailable
		}
		if err != nil {
			return nil, ErrPinUnavailable
		}
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		if err := validatePinImage(body, ext); err != nil {
			return nil, err
		}
		if ext != pin.Extension || pinDigest(body) != pin.SHA256 {
			return nil, ErrPinSourceChanged
		}
		if _, _, err := p.store.ArtworkPin(ctx, pin.ID); err != nil {
			return nil, err
		}
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		return nil, p.writeCache(ctx, pin, body)
	})
	select {
	case <-ctx.Done():
		return file, ctx.Err()
	case done := <-result:
		return file, done.Err
	}
}

// Trim ruimt uitsluitend verweesde afgeleide pinbytes na dezelfde uurrespijt als
// de provider-GC op. Actieve intentie wordt nooit gewist, ook niet bij bronfouten.
func (p *Pins) Trim(ctx context.Context) error {
	if !p.Available() {
		return nil
	}
	pins, err := p.store.ListArtworkPins(ctx)
	if err != nil {
		return err
	}
	known := map[string]bool{}
	for _, pin := range pins {
		known[filepath.Base(p.cachePath(pin))] = true
	}
	entries, err := os.ReadDir(filepath.Join(p.cache, "artwork-pins"))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, entry := range entries {
		stat, err := entry.Info()
		if err != nil || !stat.Mode().IsRegular() || known[entry.Name()] || time.Since(stat.ModTime()) < time.Hour {
			continue
		}
		_ = os.Remove(filepath.Join(p.cache, "artwork-pins", entry.Name()))
	}
	return nil
}

// CachedStatus belooft na een write alleen bytes die al gevalideerd beschikbaar
// zijn. Een andere rol lokt hier geen nieuwe provider-I/O uit; GET kan herstellen.
func (p *Pins) CachedStatus(ctx context.Context, pins []catalog.ArtworkPin) ([]PinStatus, error) {
	out := make([]PinStatus, 0, len(pins))
	for _, pin := range pins {
		sum, ext, err := pinFileDigest(ctx, p.cachePath(pin))
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		status := PinStatus{Pin: pin, State: "unavailable", ErrorCode: "source_unavailable"}
		if err == nil && ext == pin.Extension && sum == pin.SHA256 {
			status.State = "ready"
			status.ErrorCode = ""
		}
		out = append(out, status)
	}
	return out, nil
}
