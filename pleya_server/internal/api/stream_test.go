package api_test

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// withHeader zet één header op de aanvraag.
func withHeader(name, value string) func(*http.Request) {
	return func(r *http.Request) { r.Header.Set(name, value) }
}

// streamPath geeft het streampad van de eerste versie van een film.
func (e *env) streamPath(title string) string {
	e.t.Helper()
	movie := e.findMovie(title)
	if len(movie.Versions) == 0 {
		e.t.Fatalf("%s heeft geen versie", title)
	}
	return "/pleya/v1/stream/" + movie.Versions[0].ID
}

// TestStreamFullGet is het gewone geval: geen Range, het hele bestand.
func TestStreamFullGet(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodGet, e.streamPath("Grease"), nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("stream gaf %d: %s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Accept-Ranges"); got != "bytes" {
		t.Fatalf("Accept-Ranges is %q", got)
	}
	if got := rec.Header().Get("Content-Type"); got != "video/x-matroska" {
		t.Fatalf("content-type is %q", got)
	}
	size := rec.Body.Len()
	if size == 0 {
		t.Fatal("er kwamen geen bytes")
	}
	if got := rec.Header().Get("Content-Length"); got != strconv.Itoa(size) {
		t.Fatalf("Content-Length is %q terwijl er %d bytes kwamen", got, size)
	}
}

// TestStreamETagIsWeak is poort 4 in testvorm.
//
// De header draagt W/ en niets anders. Deze test bewijst NIET dat gelijke bytes
// een gelijke validator opleveren, en dat is met opzet: die bewering is precies
// wat DEC-050 uit het contract haalt.
func TestStreamETagIsWeak(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodGet, e.streamPath("Grease"), nil)
	etag := rec.Header().Get("ETag")
	if !strings.HasPrefix(etag, `W/"`) || !strings.HasSuffix(etag, `"`) {
		t.Fatalf("ETag is %q, wil de vorm W/\"...\"", etag)
	}
	if strings.Contains(rec.Header().Get("Cache-Control"), "immutable") {
		t.Fatal("immutable op media: het pad is stabiel, de bytes erachter niet")
	}
}

// TestStreamFirstRange is de eerste seek van elke speler.
func TestStreamFirstRange(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	path := e.streamPath("Grease")

	full := e.do(http.MethodGet, path, nil)
	size := int64(full.Body.Len())

	rec := e.do(http.MethodGet, path, nil, withHeader("Range", "bytes=0-1023"))
	if rec.Code != http.StatusPartialContent {
		t.Fatalf("range gaf %d, wil 206", rec.Code)
	}
	if got := rec.Header().Get("Content-Range"); got != "bytes 0-1023/"+strconv.FormatInt(size, 10) {
		t.Fatalf("Content-Range is %q", got)
	}
	if rec.Body.Len() != 1024 {
		t.Fatalf("er kwamen %d bytes, wil 1024", rec.Body.Len())
	}
	if got := full.Body.String()[:1024]; got != rec.Body.String() {
		t.Fatal("de eerste kilobyte komt niet overeen met het hele bestand")
	}
}

// TestStreamOpenEndedRange is wat een speler stuurt bij het openen: alles vanaf
// hier.
func TestStreamOpenEndedRange(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	path := e.streamPath("Grease")

	full := e.do(http.MethodGet, path, nil)
	size := int64(full.Body.Len())

	rec := e.do(http.MethodGet, path, nil, withHeader("Range", "bytes=100-"))
	if rec.Code != http.StatusPartialContent {
		t.Fatalf("open bereik gaf %d", rec.Code)
	}
	if int64(rec.Body.Len()) != size-100 {
		t.Fatalf("er kwamen %d bytes, wil %d", rec.Body.Len(), size-100)
	}
	if got := rec.Header().Get("Content-Range"); got != "bytes 100-"+strconv.FormatInt(size-1, 10)+"/"+strconv.FormatInt(size, 10) {
		t.Fatalf("Content-Range is %q", got)
	}
}

// TestStreamSuffixRange dekt "de laatste n bytes", waar een speler de index van
// een container mee ophaalt.
func TestStreamSuffixRange(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	path := e.streamPath("Grease")

	full := e.do(http.MethodGet, path, nil)
	size := int64(full.Body.Len())

	rec := e.do(http.MethodGet, path, nil, withHeader("Range", "bytes=-512"))
	if rec.Code != http.StatusPartialContent {
		t.Fatalf("suffix gaf %d", rec.Code)
	}
	if rec.Body.Len() != 512 {
		t.Fatalf("er kwamen %d bytes, wil 512", rec.Body.Len())
	}
	if got := rec.Header().Get("Content-Range"); got != "bytes "+strconv.FormatInt(size-512, 10)+"-"+strconv.FormatInt(size-1, 10)+"/"+strconv.FormatInt(size, 10) {
		t.Fatalf("Content-Range is %q", got)
	}
	if full.Body.String()[size-512:] != rec.Body.String() {
		t.Fatal("de staart komt niet overeen met het hele bestand")
	}
}

// TestStreamExactFinalByte is het randgeval waar een off-by-one zich verstopt.
func TestStreamExactFinalByte(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	path := e.streamPath("Grease")

	full := e.do(http.MethodGet, path, nil)
	size := int64(full.Body.Len())
	last := strconv.FormatInt(size-1, 10)

	rec := e.do(http.MethodGet, path, nil, withHeader("Range", "bytes="+last+"-"+last))
	if rec.Code != http.StatusPartialContent {
		t.Fatalf("laatste byte gaf %d", rec.Code)
	}
	if rec.Body.Len() != 1 {
		t.Fatalf("er kwamen %d bytes, wil 1", rec.Body.Len())
	}
	if rec.Body.String() != full.Body.String()[size-1:] {
		t.Fatal("de laatste byte klopt niet")
	}
}

// TestStreamRangeBeyondEOF geeft 416 met de werkelijke lengte erbij.
func TestStreamRangeBeyondEOF(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	path := e.streamPath("Grease")

	size := int64(e.do(http.MethodGet, path, nil).Body.Len())
	start := strconv.FormatInt(size+10, 10)

	rec := e.do(http.MethodGet, path, nil, withHeader("Range", "bytes="+start+"-"))
	if rec.Code != http.StatusRequestedRangeNotSatisfiable {
		t.Fatalf("voorbij het einde gaf %d, wil 416", rec.Code)
	}
	if code := errorCode(t, rec); code != "playback.range_not_satisfiable" {
		t.Fatalf("code is %q", code)
	}
	if got := rec.Header().Get("Content-Range"); got != "bytes */"+strconv.FormatInt(size, 10) {
		t.Fatalf("Content-Range bij een 416 is %q", got)
	}
}

// TestStreamMalformedRangeFallsBackToFull dekt de terugval uit RFC 9110 §14.2:
// een bereik dat de server niet begrijpt wordt genegeerd, niet afgekeurd.
func TestStreamMalformedRangeFallsBackToFull(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	path := e.streamPath("Grease")
	size := e.do(http.MethodGet, path, nil).Body.Len()

	for _, header := range []string{"kilobytes=0-10", "bytes=abc-def", "bytes=", "nonsense"} {
		rec := e.do(http.MethodGet, path, nil, withHeader("Range", header))
		if header == "bytes=abc-def" || header == "bytes=" {
			// Wél de eenheid bytes, maar geen leesbaar bereik: dat is een bereik
			// dat niet te bedienen valt en geen onbekende eenheid.
			if rec.Code != http.StatusRequestedRangeNotSatisfiable {
				t.Fatalf("Range %q gaf %d, wil 416", header, rec.Code)
			}
			continue
		}
		if rec.Code != http.StatusOK {
			t.Fatalf("Range %q gaf %d, wil 200", header, rec.Code)
		}
		if rec.Body.Len() != size {
			t.Fatalf("Range %q leverde %d bytes, wil het hele bestand", header, rec.Body.Len())
		}
	}
}

// TestStreamMultipleRangesGiveTheWholeFile is de toegestane terugval uit het
// contract: multipart/byteranges wordt niet gebouwd, en een 416 zou een speler
// breken die het toch probeert.
func TestStreamMultipleRangesGiveTheWholeFile(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	path := e.streamPath("Grease")
	size := e.do(http.MethodGet, path, nil).Body.Len()

	rec := e.do(http.MethodGet, path, nil, withHeader("Range", "bytes=0-99,200-299"))
	if rec.Code != http.StatusOK {
		t.Fatalf("twee bereiken gaven %d, wil 200", rec.Code)
	}
	if rec.Body.Len() != size {
		t.Fatalf("twee bereiken leverden %d bytes, wil %d", rec.Body.Len(), size)
	}
	if rec.Header().Get("Content-Range") != "" {
		t.Fatal("een 200 draagt geen Content-Range")
	}
}

// TestStreamIfRangeAlwaysGivesTheWholeFile is de kern van DEC-050.
//
// De validator is zwak, dus RFC 9110 §13.1.5 staat geen deelantwoord toe. Dat
// geldt ook wanneer de client precies de ETag terugstuurt die hij net kreeg:
// gelijkheid van een zwakke validator zegt niets over de bytes, en een 206 zou
// een half oude, half nieuwe stream opleveren.
func TestStreamIfRangeAlwaysGivesTheWholeFile(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	path := e.streamPath("Grease")

	first := e.do(http.MethodGet, path, nil)
	etag := first.Header().Get("ETag")
	size := first.Body.Len()

	for _, ifRange := range []string{etag, `W/"iets-anders"`, time.Now().UTC().Format(http.TimeFormat)} {
		rec := e.do(http.MethodGet, path, nil,
			withHeader("Range", "bytes=0-99"), withHeader("If-Range", ifRange))
		if rec.Code != http.StatusOK {
			t.Fatalf("If-Range %q gaf %d, wil 200", ifRange, rec.Code)
		}
		if rec.Body.Len() != size {
			t.Fatalf("If-Range %q leverde %d bytes, wil het hele bestand", ifRange, rec.Body.Len())
		}
		if rec.Header().Get("Content-Range") != "" {
			t.Fatalf("If-Range %q leverde een Content-Range", ifRange)
		}
	}
}

// TestStreamValidatorFollowsTheBytes toont wat de zwakke validator wél kan.
//
// Een vervangen bestand levert een andere validator op. De omgekeerde bewering
// staat hier bewust niet: dat een gelijke validator gelijke bytes betekent is
// precies wat DEC-050 niet belooft.
func TestStreamValidatorFollowsTheBytes(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	path := e.streamPath("Grease")

	before := e.do(http.MethodGet, path, nil).Header().Get("ETag")

	// Andere bytes op hetzelfde pad, met een andere lengte. De mtime gaat
	// expliciet vooruit, want anders hangt de test aan de tijdsresolutie van het
	// bestandssysteem.
	target := filepath.Join(e.root, "films", "Grease (1978)", "Grease (1978).mkv")
	testsupport.MakeVideo(t, target, 3)
	stamp := time.Now().Add(2 * time.Second)
	if err := os.Chtimes(target, stamp, stamp); err != nil {
		t.Fatal(err)
	}
	e.rescan()

	after := e.do(http.MethodGet, path, nil).Header().Get("ETag")
	if after == before {
		t.Fatal("de validator veranderde niet terwijl de bytes dat wel deden")
	}
	if !strings.HasPrefix(after, `W/"`) {
		t.Fatalf("de nieuwe validator is %q", after)
	}
}

// TestStreamHeadCarriesTheHeadersWithoutBytes: een speler doet routinematig een
// HEAD voordat hij begint.
func TestStreamHeadCarriesTheHeadersWithoutBytes(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	path := e.streamPath("Grease")

	size := e.do(http.MethodGet, path, nil).Body.Len()
	rec := e.do(http.MethodHead, path, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("HEAD gaf %d", rec.Code)
	}
	if rec.Body.Len() != 0 {
		t.Fatalf("HEAD leverde %d bytes", rec.Body.Len())
	}
	if got := rec.Header().Get("Content-Length"); got != strconv.Itoa(size) {
		t.Fatalf("HEAD zegt Content-Length %q, wil %d", got, size)
	}
	if rec.Header().Get("ETag") == "" {
		t.Fatal("HEAD draagt geen validator")
	}
}

// TestStreamUnknownVersionIsNotFound: een id dat niets opent is een 404 en geen
// storing.
func TestStreamUnknownVersionIsNotFound(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodGet, "/pleya/v1/stream/0198f2a1-7c3e-7b21-9f44-1c2d3e4f5a6b", nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("onbekende versie gaf %d", rec.Code)
	}
	if code := errorCode(t, rec); code != "library.not_found" {
		t.Fatalf("code is %q", code)
	}
}

// TestStreamNeedsAuthorization: bytes gaan nooit de deur uit zonder identiteit.
func TestStreamNeedsAuthorization(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	path := e.streamPath("Grease")

	rec := e.do(http.MethodGet, path, nil, withoutAuth)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("zonder token gaf %d, wil 401", rec.Code)
	}
}

// TestStreamWithStreamToken dekt de externe speler die geen header kan zetten,
// inclusief de grens van het token: het opent één versie en verder niets.
func TestStreamWithStreamToken(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	grease := e.findMovie("Grease")
	matrix := e.findMovie("The Matrix")

	tokenRec := e.do(http.MethodPost, "/pleya/v1/auth/stream-token",
		map[string]string{"version_id": grease.Versions[0].ID})
	if tokenRec.Code != http.StatusOK {
		t.Fatalf("stream-token gaf %d: %s", tokenRec.Code, tokenRec.Body.String())
	}
	var token api.StreamToken
	if err := json.Unmarshal(tokenRec.Body.Bytes(), &token); err != nil {
		t.Fatal(err)
	}

	path := "/pleya/v1/stream/" + grease.Versions[0].ID
	ok := e.do(http.MethodGet, path+"?stream_token="+token.StreamToken, nil, withoutAuth)
	if ok.Code != http.StatusOK {
		t.Fatalf("met streamtoken gaf %d: %s", ok.Code, ok.Body.String())
	}

	other := "/pleya/v1/stream/" + matrix.Versions[0].ID
	wrong := e.do(http.MethodGet, other+"?stream_token="+token.StreamToken, nil, withoutAuth)
	if wrong.Code != http.StatusUnauthorized {
		t.Fatalf("een token voor een andere versie gaf %d, wil 401", wrong.Code)
	}
}
