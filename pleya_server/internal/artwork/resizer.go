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
	"image"
	_ "image/jpeg" // decoders voor DecodeConfig
	_ "image/png"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
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
	ffmpeg           string
	dir              string
	log              *slog.Logger
	sem              chan struct{}
	sf               singleflight.Group
	timeout          time.Duration
	quality          string
	disabled         bool
	boundaryErr      error
	purgeBoundaryErr error
	gate             cacheGate
}

// New bouwt een Resizer. Zonder cacheDir of ffmpeg is hij uitgeschakeld en geeft
// Available false: de capability belooft dan niets.
func New(ffmpegPath, cacheDir string, log *slog.Logger, protectedDirs ...string) *Resizer {
	r := &Resizer{
		ffmpeg:  ffmpegPath,
		dir:     filepath.Join(cacheDir, "artwork-sizes"),
		log:     log,
		sem:     make(chan struct{}, 2), // een Celeron heeft niet meer dan twee ffmpeg's tegelijk nodig
		timeout: 30 * time.Second,
		quality: "3",
	}
	// De grens betreft uitsluitend de afgeleide map, zodat standaard siblings
	// /cache/artwork, /cache/artwork-pins en /config gewoon kunnen blijven bestaan.
	for _, protected := range protectedDirs {
		if protected == "" {
			continue
		}
		cachePath, err := filepath.Abs(r.dir)
		rootPath, rootErr := filepath.Abs(protected)
		if err != nil || rootErr != nil || pathWithin(cachePath, rootPath) || pathWithin(rootPath, cachePath) {
			r.boundaryErr = errors.New("artworkcache overlapt een beschermd opslagpad")
			r.disabled = true
			return r
		}
		resolvedRoot, resolveErr := resolvedProtectedRoot(rootPath)
		if resolveErr != nil {
			// Een offline gewone suffix mag blijven bestaan, maar een
			// onoplosbare alias is geen veilige destructieve grens. Alleen
			// nieuw cachebeheer valt uit; bestaande resizing blijft werken.
			r.purgeBoundaryErr = resolveErr
			continue
		}
		if pathWithin(cachePath, resolvedRoot) || pathWithin(resolvedRoot, cachePath) {
			r.boundaryErr = errors.New("artworkcache overlapt een beschermd opslagpad")
			r.disabled = true
			return r
		}
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

// resolvedProtectedRoot neemt bestaande symlink-aliasen mee, ook in de
// ancestors. Gewone ontbrekende old-root-suffixen worden achter de opgeloste
// bestaande ancestor gevoegd. Een bestaande maar onoplosbare symlink (of een
// andere leesfout) mag niet als een gewone ontbrekende map worden behandeld.
// Dit is uitsluitend de startupgrens; runtime-retarget/bind-aliasbeleid blijft
// buiten dit beperkte cachebeheeroppervlak.
func resolvedProtectedRoot(path string) (string, error) {
	probe := path
	var missing []string
	for {
		resolved, err := filepath.EvalSymlinks(probe)
		if err == nil {
			for i := len(missing) - 1; i >= 0; i-- {
				resolved = filepath.Join(resolved, missing[i])
			}
			return resolved, nil
		}
		if !errors.Is(err, os.ErrNotExist) {
			return "", err
		}
		// Lstat onderscheidt een echt ontbrekende component van een
		// bestaande dangling symlink. Ook een veranderende lookup faalt dicht.
		if _, statErr := os.Lstat(probe); statErr == nil {
			return "", err
		} else if !errors.Is(statErr, os.ErrNotExist) {
			return "", statErr
		}
		parent := filepath.Dir(probe)
		if parent == probe {
			return "", err
		}
		missing = append(missing, filepath.Base(probe))
		probe = parent
	}
}

// pathWithin vergelijkt gedeclareerde containerpaden op directorygrenzen.
// Verborgen bindmount-aliasen zijn hiermee niet vast te stellen; symlinks in
// het cachepad worden daarnaast door openCache bij elke operatie geweigerd.
func pathWithin(path, root string) bool {
	return path == root || strings.HasPrefix(path, root+string(os.PathSeparator)) || root == string(os.PathSeparator)
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

// Open maakt de trede en opent haar onder dezelfde purgegrens. De aanroeper
// bezit de descriptor; de HTTP-kopie houdt geen cachelock vast.
func (r *Resizer) Open(ctx context.Context, src, key string, step int) (*os.File, error) {
	name := key + "_" + strconv.Itoa(step) + ".jpg"
	if r.boundaryErr != nil {
		return nil, r.boundaryErr
	}
	if !artifactName(name) {
		return nil, errors.New("ongeldige laddersleutel")
	}
	if err := r.gate.acquire(ctx, false); err != nil {
		return nil, err
	}
	release := true
	defer func() {
		if release {
			r.gate.release(false)
		}
	}()
	dir, err := r.openCache(true)
	if err != nil {
		return nil, err
	}
	defer dir.Close()
	if f, err := openArtifact(dir, name); err == nil {
		return f, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	// De eerste aanvrager houdt zijn readgrens tot de single-flight klaar is,
	// ook als zijn HTTP-context intussen annuleert. De gedeelde render behoudt
	// de bestaande eigen timeout; wachten op deze render is wel annuleerbaar.
	workDir, err := duplicateCacheDir(dir)
	if err != nil {
		return nil, err
	}
	closeWork := true
	defer func() {
		if closeWork {
			workDir.Close()
		}
	}()
	result := r.sf.DoChan(name, func() (any, error) {
		work, cancel := context.WithTimeout(context.WithoutCancel(ctx), r.timeout)
		defer cancel()
		if f, err := openArtifact(workDir, name); err == nil {
			f.Close()
			return nil, nil
		} else if !errors.Is(err, os.ErrNotExist) {
			return nil, err
		}
		select {
		case r.sem <- struct{}{}:
			defer func() { <-r.sem }()
		case <-work.Done():
			return nil, work.Err()
		}
		return nil, r.run(work, src, workDir, name, step)
	})
	select {
	case <-ctx.Done():
		release = false
		closeWork = false
		go func() { <-result; workDir.Close(); r.gate.release(false) }()
		return nil, ctx.Err()
	case done := <-result:
		if done.Err != nil {
			return nil, done.Err
		}
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return openArtifact(dir, name)
}

// Make blijft de interne padinterface voor bestaande callers/tests. HTTP
// gebruikt Open, omdat een pad zonder descriptor geen I/O-grens kan dragen.
func (r *Resizer) Make(ctx context.Context, src, key string, step int) (string, bool) {
	f, err := r.Open(ctx, src, key, step)
	if err != nil {
		r.log.Warn("afbeelding verkleinen mislukt; origineel geleverd", slog.String("error", err.Error()), slog.Int("width", step))
		return "", false
	}
	f.Close()
	return filepath.Join(r.dir, key+"_"+strconv.Itoa(step)+".jpg"), true
}
