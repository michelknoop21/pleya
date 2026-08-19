// Package web serveert de meegeleverde Pleya Web-bundel uit de binary.
//
// Dit is de enige serverwijziging die PS-3W meebrengt. Er komt geen endpoint
// bij, geen capability en geen protocolregel: de bundel is een verzameling
// statische bestanden en de webclient praat verder net zo tegen /pleya/v1 als
// de Flutter-client dat straks doet. DEC-046 legt vast dat samen uitgeleverd
// worden daar geen uitzondering op geeft.
package web

import (
	"embed"
	"errors"
	"io"
	"io/fs"
	"net/http"
	"path"
	"strings"
	"time"
)

// De bundel. `all:` is nodig omdat SvelteKit zijn uitvoer in `_app/` zet en
// go:embed mappen met een liggend streepje anders overslaat.
//
//go:embed all:dist
var bundle embed.FS

// IndexFile is het bestand dat elke frontendroute krijgt die geen bestand is.
const IndexFile = "index.html"

// immutablePrefix is het pad waar de bouwer bestanden met een inhoudshash in
// de naam neerzet. Alleen daar mag een client een antwoord een jaar geloven.
const immutablePrefix = "_app/immutable/"

// Options bepaalt hoe de handler zich gedraagt. De nulwaarde is bruikbaar.
type Options struct {
	// FS is de bestandsboom die geserveerd wordt. Blijft hij leeg, dan is dat
	// de ingebedde bundel.
	FS fs.FS
}

// Bundle geeft de ingebedde bundel als bestandsboom.
func Bundle() fs.FS {
	sub, err := fs.Sub(bundle, "dist")
	if err != nil {
		// Kan alleen bij een kapotte embed-regel, en dat is een bouwfout.
		panic(err)
	}
	return sub
}

// HasIndex zegt of er werkelijk een gebouwde frontend in zit.
//
// Zonder bundel compileert en draait de server gewoon door, zodat `go test`
// en een ontwikkelbuild geen Bun nodig hebben. Wat er niet gebeurt is stil een
// lege pagina leveren: de handler zegt dan met zoveel woorden wat er ontbreekt,
// en een releasebuild komt niet eens zover (zie release.go).
func HasIndex(fsys fs.FS) bool {
	f, err := fsys.Open(IndexFile)
	if err != nil {
		return false
	}
	_ = f.Close()
	return true
}

type handler struct {
	fsys     fs.FS
	index    []byte
	modTime  time.Time
	hasIndex bool
}

// Handler bouwt de statische handler voor de ingebedde bundel.
func Handler() http.Handler { return HandlerFor(Options{}) }

// HandlerFor bouwt de handler voor een opgegeven bestandsboom. Alleen tests
// geven hier iets anders mee dan de ingebedde bundel.
func HandlerFor(opts Options) http.Handler {
	fsys := opts.FS
	if fsys == nil {
		fsys = Bundle()
	}

	h := &handler{fsys: fsys, modTime: time.Now()}
	if data, err := fs.ReadFile(fsys, IndexFile); err == nil {
		h.index = data
		h.hasIndex = true
	}
	return h
}

func (h *handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	securityHeaders(w)

	if !h.hasIndex {
		// Geen bundel: luid en leesbaar, geen witte pagina. Een releasebuild
		// komt hier nooit, want die compileert niet zonder index.html.
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = io.WriteString(w, "Pleya Web is niet in deze build meegenomen.\n")
		return
	}

	name := strings.TrimPrefix(path.Clean("/"+r.URL.Path), "/")
	if name == "" {
		h.serveIndex(w, r)
		return
	}

	file, err := h.fsys.Open(name)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			// De SPA-terugval. Elk pad dat geen bestand is hoort bij de
			// clientrouter; welke paden dat níét zijn wordt een niveau hoger
			// beslist, want /pleya/v1, /healthz en /readyz komen hier nooit.
			h.serveIndex(w, r)
			return
		}
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil || info.IsDir() {
		h.serveIndex(w, r)
		return
	}

	seeker, ok := file.(io.ReadSeeker)
	if !ok {
		h.serveIndex(w, r)
		return
	}

	setCacheHeaders(w, name)
	http.ServeContent(w, r, info.Name(), h.modTime, seeker)
}

func (h *handler) serveIndex(w http.ResponseWriter, r *http.Request) {
	// HTML krijgt nooit een lange levensduur, en zeker geen immutable: de
	// verwijzingen naar de gehashte bundels staan erin, dus een gecachete
	// index.html houdt een oude app in de lucht na een upgrade.
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	http.ServeContent(w, r, IndexFile, h.modTime, strings.NewReader(string(h.index)))
}

// setCacheHeaders geeft elk bestand de levensduur die bij zijn naam hoort.
func setCacheHeaders(w http.ResponseWriter, name string) {
	switch {
	case strings.HasPrefix(name, immutablePrefix):
		// De naam draagt een hash over de inhoud, dus deze bytes veranderen
		// nooit meer. Revalideren zou elke keer een 304 opleveren en niets
		// anders.
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	case strings.HasSuffix(name, ".html"):
		w.Header().Set("Cache-Control", "no-cache")
	default:
		// Fonts, iconen en merkassets: wel cachen, maar herzien blijft
		// mogelijk, want hun naam draagt geen hash.
		w.Header().Set("Cache-Control", "public, max-age=86400, must-revalidate")
	}
}

// securityHeaders zet wat niet in de bundel zelf kan staan.
//
// De Content-Security-Policy staat bewust niet volledig hier. SvelteKit
// schrijft één bootstrapscript inline in index.html en zet de hash daarvan in
// een meta-tag; een browser doorsnijdt alle policies, dus een header met
// script-src 'self' zou datzelfde script alsnog blokkeren. Wat hier staat is
// de enige directive die een meta-tag niet mag dragen, plus de headers die
// buiten CSP vallen.
func securityHeaders(w http.ResponseWriter) {
	w.Header().Set("Content-Security-Policy", "frame-ancestors 'none'")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("X-Frame-Options", "DENY")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=()")
	w.Header().Set("Cross-Origin-Opener-Policy", "same-origin")
	w.Header().Set("Cross-Origin-Resource-Policy", "same-origin")
	// Geen Access-Control-Allow-Origin. De bundel en de API staan op dezelfde
	// origin, dus CORS is er niet nodig, en hem "voor de zekerheid" toevoegen
	// zou de API openzetten voor elke pagina die erom vraagt.
}
