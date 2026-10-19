// Package artwork maakt afgeleide maten van een afbeelding (S4.4, venster 3
// pakket C): een trede van een vaste ladder per rol, gecachet naast de rest van
// de cache, met ffmpeg als beeldbewerker.
//
// Een mislukte bewerking is geen fout voor de aanroeper maar een terugval: de
// client krijgt het origineel. Een poster die te groot is, is beter dan een
// poster die ontbreekt.
package artwork

import (
	"context"
	"errors"
	"fmt"
	"image"
	_ "image/jpeg" // decoders voor DecodeConfig
	_ "image/png"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"time"

	"golang.org/x/sync/singleflight"
)

// De ladders per rol (C2). Een boekcover is geen rol hier maar gebruikt de
// posterladder.
var (
	PosterSteps   = []int{240, 480, 960, 1920}
	BackdropSteps = []int{480, 960, 1920, 3840}
)

// Step rondt een gevraagde breedte naar boven af op een trede van de ladder
// van de rol, en blijft op de bovenste trede hangen.
func Step(kind string, requested int) int {
	steps := PosterSteps
	if kind == "backdrop" {
		steps = BackdropSteps
	}
	for _, s := range steps {
		if requested <= s {
			return s
		}
	}
	return steps[len(steps)-1]
}

// Resizer maakt en bewaart de afgeleide maten.
type Resizer struct {
	ffmpeg   string
	dir      string
	log      *slog.Logger
	sem      chan struct{}
	sf       singleflight.Group
	timeout  time.Duration
	quality  string
	disabled bool
}

// New bouwt een Resizer. Zonder cacheDir of ffmpeg is hij uitgeschakeld en geeft
// Available false: de capability belooft dan niets.
func New(ffmpegPath, cacheDir string, log *slog.Logger) *Resizer {
	r := &Resizer{
		ffmpeg:  ffmpegPath,
		dir:     filepath.Join(cacheDir, "artwork-sizes"),
		log:     log,
		sem:     make(chan struct{}, 2), // een Celeron heeft niet meer dan twee ffmpeg's tegelijk nodig
		timeout: 30 * time.Second,
		quality: "3",
	}
	if cacheDir == "" || ffmpegPath == "" {
		r.disabled = true
		return r
	}
	if _, err := exec.LookPath(ffmpegPath); err != nil {
		r.disabled = true
	}
	return r
}

// Available zegt of er afgeleide maten gemaakt kunnen worden.
func (r *Resizer) Available() bool { return r != nil && !r.disabled }

// Dir is de map met afgeleide maten.
func (r *Resizer) Dir() string { return r.dir }

// sourceWidth leest de breedte uit de kop van de afbeelding. Een formaat dat de
// standaardbibliotheek niet kent (webp) geeft 0 en wordt dus niet verkleind.
func sourceWidth(path string) int {
	f, err := os.Open(path)
	if err != nil {
		return 0
	}
	defer f.Close()
	cfg, _, err := image.DecodeConfig(f)
	if err != nil {
		return 0
	}
	return cfg.Width
}

// Plan zegt welke trede er geleverd moet worden, zonder iets te maken. 0
// betekent: lever het origineel (geen ladder, de bron is al kleiner dan de
// trede, of het formaat is onbekend). Goedkoop genoeg om vóór een
// If-None-Match-controle te draaien, want de trede is deel van de validator.
func (r *Resizer) Plan(src, kind string, requested int) int {
	if !r.Available() || requested <= 0 {
		return 0
	}
	step := Step(kind, requested)
	if w := sourceWidth(src); w <= 0 || step >= w {
		return 0
	}
	return step
}

// Make geeft het pad van de afgeleide maat voor een trede uit Plan, en maakt hem
// zo nodig. false betekent: de bewerking mislukte, lever het origineel.
//
// key hoort bij de bytes van de bron (id en generation), zodat een vervangen
// afbeelding een nieuwe afgeleide krijgt in plaats van de oude te blijven
// leveren.
func (r *Resizer) Make(ctx context.Context, src, key string, step int) (string, bool) {
	out := filepath.Join(r.dir, key+"_"+strconv.Itoa(step)+".jpg")
	if _, err := os.Stat(out); err == nil {
		return out, true
	}

	_, err, _ := r.sf.Do(out, func() (any, error) {
		if _, err := os.Stat(out); err == nil {
			return nil, nil
		}
		select {
		case r.sem <- struct{}{}:
			defer func() { <-r.sem }()
		case <-ctx.Done():
			return nil, ctx.Err()
		}
		return nil, r.run(ctx, src, out, step)
	})
	if err != nil {
		r.log.Warn("afbeelding verkleinen mislukt; origineel geleverd",
			slog.String("error", err.Error()), slog.Int("width", step))
		return "", false
	}
	return out, true
}

func (r *Resizer) run(ctx context.Context, src, out string, step int) error {
	if err := os.MkdirAll(r.dir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(r.dir, ".incoming-*.jpg")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	tmp.Close()
	defer os.Remove(tmpName)

	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), r.timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, r.ffmpeg, "-v", "error", "-y", "-i", src,
		"-vf", fmt.Sprintf("scale=%d:-2:flags=lanczos", step), "-frames:v", "1", "-q:v", r.quality, tmpName)
	if msg, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg: %w: %.200s", err, msg)
	}
	info, err := os.Stat(tmpName)
	if err != nil || info.Size() == 0 {
		return errors.New("ffmpeg leverde niets")
	}
	return os.Rename(tmpName, out)
}

// Stats telt wat er in de cache staat (C4).
func (r *Resizer) Stats() (bytes int64, files int, err error) {
	entries, err := os.ReadDir(r.dir)
	if errors.Is(err, os.ErrNotExist) {
		return 0, 0, nil
	}
	if err != nil {
		return 0, 0, err
	}
	for _, e := range entries {
		if e.IsDir() || e.Name()[0] == '.' {
			continue
		}
		if info, err := e.Info(); err == nil {
			bytes += info.Size()
			files++
		}
	}
	return bytes, files, nil
}

// Purge leegt de cache van afgeleide maten (C4). Ze komen vanzelf terug.
func (r *Resizer) Purge() error {
	entries, err := os.ReadDir(r.dir)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, e := range entries {
		if !e.IsDir() {
			_ = os.Remove(filepath.Join(r.dir, e.Name()))
		}
	}
	return nil
}
