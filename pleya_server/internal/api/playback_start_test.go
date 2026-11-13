package api_test

import (
	"context"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/transcode"
)

func ms(v int64) *int64 { return &v }

// De grenzen van start_position_ms: negatief en op of voorbij de duur bestaan
// niet, de laatste tien seconden schuiven naar voren, en een onbekende duur
// (nul) begrenst niets.
func TestStartpositieKentZijnGrenzen(t *testing.T) {
	const duur = 7_200_000
	for _, c := range []struct {
		naam   string
		vraag  *int64
		duur   int64
		start  int64
		geldig bool
	}{
		{"afwezig", nil, duur, 0, true},
		{"nul", ms(0), duur, 0, true},
		{"midden", ms(4_200_000), duur, 4_200_000, true},
		{"negatief", ms(-1), duur, 0, false},
		{"op de duur", ms(duur), duur, 0, false},
		{"voorbij de duur", ms(duur + 1), duur, 0, false},
		{"vlak voor het einde", ms(duur - 500), duur, duur - 10_000, true},
		{"precies op de marge", ms(duur - 10_000), duur, duur - 10_000, true},
		{"korter dan de marge", ms(400), 1000, 0, true},
		{"onbekende duur", ms(9_000_000), 0, 9_000_000, true},
	} {
		start, geldig := api.StartPosition(c.vraag, c.duur)
		if start != c.start || geldig != c.geldig {
			t.Errorf("%s: start %d geldig %v, verwacht %d %v", c.naam, start, geldig, c.start, c.geldig)
		}
	}
}

// stubFFprobe meldt een vaste starttijd: het keyframe dat de stub-omzetting
// zogenaamd koos, anderhalve seconde vóór de gevraagde minuut.
const stubFFprobe = "#!/bin/sh\necho 58.500000\n"

// startEnv is transcodeEnv met een ffprobe-stub erbij en een film van twee uur.
func startEnv(t *testing.T) (*env, *transcode.Manager, api.Item) {
	t.Helper()
	return startEnvWith(t, stubFFprobe, true)
}

// startEnvWith kiest de ffprobe-stub en wat de server bij het opstarten van
// ffprobe vond.
func startEnvWith(t *testing.T, ffprobe string, found bool) (*env, *transcode.Manager, api.Item) {
	t.Helper()
	dir := t.TempDir()
	for name, body := range map[string]string{"ffmpeg": stubFFmpeg, "ffprobe": ffprobe} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	m, err := transcode.New(transcode.Options{
		FFmpegPath: filepath.Join(dir, "ffmpeg"), FFprobePath: filepath.Join(dir, "ffprobe"), Dir: filepath.Join(dir, "work"),
		Max: 2, IdleTimeout: time.Minute, StartTimeout: 10 * time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(m.Close)
	e := newEnv(t, func(o *api.Options) {
		o.Transcode = m
		o.FFprobe.Found = found
	})
	e.setup(e.putSetupCode())
	e.hasTranscoder = true
	movie := e.findMovie("Grease")
	if _, err := e.pool.Exec(context.Background(), `UPDATE media_versions SET duration_ms = 7200000 WHERE id = $1`, movie.Versions[0].ID); err != nil {
		t.Fatal(err)
	}
	return e, m, movie
}

func sessionArgs(t *testing.T, m *transcode.Manager, plan api.PlaybackPlan) string {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(sessionDir(t, m, *plan.SessionID), "args.txt"))
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

// De omzetting begint op de gevraagde positie, en het antwoord meldt wat er
// gemeten is in plaats van wat er gevraagd werd.
func TestStartpositieBereiktFFmpegEnHetAntwoordMeldtDeGemetenStart(t *testing.T) {
	e, m, movie := startEnv(t)
	plan, _ := e.planFor(map[string]any{"item_id": movie.ID, "capabilities": vp9Only(), "start_position_ms": 60_000}, http.StatusOK)
	if plan.StartPositionMs == nil || *plan.StartPositionMs != 58_500 {
		t.Fatalf("start_position_ms = %v, verwacht de gemeten 58500", plan.StartPositionMs)
	}
	args := sessionArgs(t, m, plan)
	// Het geluid van de testfilm past al en wordt gekopieerd, dus begint alles
	// op het keyframe ervoor (-noaccurate_seek).
	if !strings.Contains(args, "-ss\n60.000\n-noaccurate_seek\n-copyts\n-start_at_zero\n-i\n") {
		t.Fatalf("startpositie ontbreekt vóór -i: %q", args)
	}

	// Vlak voor het einde schuift de start naar tien seconden voor het einde.
	plan, _ = e.planFor(map[string]any{"item_id": movie.ID, "capabilities": vp9Only(), "start_position_ms": 7_199_500}, http.StatusOK)
	if args := sessionArgs(t, m, plan); !strings.Contains(args, "-ss\n7190.000\n") {
		t.Fatalf("start vlak voor het einde is niet begrensd: %q", args)
	}
}

// Een client die het veld niet stuurt krijgt het antwoord en de omzetting van
// vóór dit veld: geen start_position_ms in de JSON, geen zoekoptie bij ffmpeg.
func TestZonderStartpositieBlijftHetPlanZoalsHetWas(t *testing.T) {
	e, m, movie := startEnv(t)
	plan, rec := e.planFor(map[string]any{"item_id": movie.ID, "capabilities": vp9Only()}, http.StatusOK)
	if strings.Contains(rec.Body.String(), "start_position_ms") {
		t.Fatalf("antwoord draagt start_position_ms zonder dat erom gevraagd is: %s", rec.Body.String())
	}
	args := sessionArgs(t, m, plan)
	for _, verboden := range []string{"-ss", "-copyts", "-start_at_zero", "-noaccurate_seek"} {
		if strings.Contains(args, verboden+"\n") {
			t.Fatalf("%s in de argumenten zonder startpositie: %q", verboden, args)
		}
	}
}

func TestStartpositieBuitenDeVersieIsEenOngeldigeKeuze(t *testing.T) {
	e, m, movie := startEnv(t)
	for _, start := range []int64{-1, 7_200_000, 9_000_000} {
		rec := e.do(http.MethodPost, "/pleya/v1/playback/plan", map[string]any{"item_id": movie.ID, "capabilities": vp9Only(), "start_position_ms": start})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("start %d gaf %d: %s", start, rec.Code, rec.Body.String())
		}
		e.expectCode(rec, api.CodePlaybackSelectionInvalid)
	}
	if n := len(m.List()); n != 0 {
		t.Fatalf("een geweigerde startpositie liet %d sessie(s) achter", n)
	}
}

// Bij direct play is de stream het bestand: geen sessie, en tijd nul is het
// begin van de film. Het veld dwingt geen omzetting af.
func TestStartpositieBijDirectPlayStartGeenOmzetting(t *testing.T) {
	e, _, movie := startEnv(t)
	plan, _ := e.planFor(map[string]any{"item_id": movie.ID, "start_position_ms": 60_000}, http.StatusOK)
	if plan.DeliveryMode != "direct_play" || plan.SessionID != nil || plan.StartPositionMs == nil || *plan.StartPositionMs != 0 {
		t.Fatalf("direct play met startpositie: %+v", plan)
	}
}

// Een andere startpositie is een nieuwe sessie en telt mee voor de limiet: de
// client stopt de oude eerst.
func TestNieuweStartpositieIsEenNieuweSessieBinnenDeLimiet(t *testing.T) {
	e, _, movie := startEnv(t)
	body := func(start int64) map[string]any {
		return map[string]any{"item_id": movie.ID, "capabilities": vp9Only(), "start_position_ms": start}
	}
	first, _ := e.planFor(body(60_000), http.StatusOK)
	second, _ := e.planFor(body(120_000), http.StatusOK)
	if *first.SessionID == *second.SessionID {
		t.Fatal("een andere startpositie hergebruikte de sessie")
	}
	rec := e.do(http.MethodPost, "/pleya/v1/playback/plan", body(180_000))
	e.expectCode(rec, api.CodeTranscodeBusy)
	e.do(http.MethodDelete, "/pleya/v1/playback/sessions/"+*first.SessionID, nil)
	e.planFor(body(180_000), http.StatusOK)
}

func TestInfoMeldtStartpositieAlleenMetOmzetter(t *testing.T) {
	e, _, _ := startEnv(t)
	var info api.Info
	e.getJSON("/pleya/v1/info", "", http.StatusOK, &info)
	if !info.Capabilities.PlaybackStartPosition {
		t.Fatal("playback_start_position hoort aan te staan met een omzetter en ffprobe")
	}
	zonder := newEnv(t)
	zonder.setup(zonder.putSetupCode())
	zonder.getJSON("/pleya/v1/info", "", http.StatusOK, &info)
	if info.Capabilities.PlaybackStartPosition {
		t.Fatal("playback_start_position staat aan zonder omzetter")
	}
}

// Bij direct play is een positie voorbij de duur geen fout: het veld dwingt
// daar niets af en de client zoekt zelf in het bestand.
func TestStartpositieVoorbijDeDuurBijDirectPlayIsGeenFout(t *testing.T) {
	e, _, movie := startEnv(t)
	plan, _ := e.planFor(map[string]any{"item_id": movie.ID, "start_position_ms": 9_000_000}, http.StatusOK)
	if plan.DeliveryMode != "direct_play" || plan.StartPositionMs == nil || *plan.StartPositionMs != 0 {
		t.Fatalf("direct play met een positie voorbij de duur: %+v", plan)
	}
}

// Zonder ffprobe staat playback_start_position uit en negeert de server het
// veld, in plaats van per aanvraag een omzetting te starten die 502 geeft.
func TestZonderFFprobeNegeertDeServerDeStartpositie(t *testing.T) {
	e, m, movie := startEnvWith(t, stubFFprobe, false)
	plan, rec := e.planFor(map[string]any{"item_id": movie.ID, "capabilities": vp9Only(), "start_position_ms": 60_000}, http.StatusOK)
	if strings.Contains(rec.Body.String(), "start_position_ms") {
		t.Fatalf("antwoord draagt start_position_ms terwijl de vlag uit staat: %s", rec.Body.String())
	}
	if args := sessionArgs(t, m, plan); strings.Contains(args, "-ss\n") {
		t.Fatalf("-ss in de argumenten terwijl de vlag uit staat: %q", args)
	}
}

// Een meting die mislukt is 502: zonder gemeten start weet geen client welke
// positie hij meldt. Er blijft geen sessie achter.
func TestMislukteMetingVanDeStartIs502(t *testing.T) {
	e, m, movie := startEnvWith(t, "#!/bin/sh\nexit 1\n", true)
	rec := e.do(http.MethodPost, "/pleya/v1/playback/plan", map[string]any{"item_id": movie.ID, "capabilities": vp9Only(), "start_position_ms": 60_000})
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("mislukte meting gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.expectCode(rec, api.CodeTranscodeFailed)
	if n := len(m.List()); n != 0 {
		t.Fatalf("een mislukte meting liet %d sessie(s) achter", n)
	}
}
