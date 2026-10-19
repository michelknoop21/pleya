package artwork

import (
	"context"
	"image"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func quiet() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

func widthOf(t *testing.T, path string) int {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	cfg, _, err := image.DecodeConfig(f)
	if err != nil {
		t.Fatal(err)
	}
	return cfg.Width
}

func TestStepRoundsUpPerRoleAndStopsAtTheTop(t *testing.T) {
	cases := []struct {
		kind string
		in   int
		want int
	}{
		{"poster", 1, 240}, {"poster", 240, 240}, {"poster", 241, 480}, {"poster", 700, 960},
		{"poster", 1920, 1920}, {"poster", 4096, 1920},
		{"backdrop", 100, 480}, {"backdrop", 481, 960}, {"backdrop", 2000, 3840}, {"backdrop", 4096, 3840},
		{"", 300, 480}, // onbekende rol rekent met de posterladder
	}
	for _, c := range cases {
		if got := Step(c.kind, c.in); got != c.want {
			t.Errorf("Step(%q, %d) = %d, verwacht %d", c.kind, c.in, got, c.want)
		}
	}
}

func newResizer(t *testing.T) *Resizer {
	t.Helper()
	testsupport.HasFFmpeg(t)
	r := New("ffmpeg", t.TempDir(), quiet())
	if !r.Available() {
		t.Fatal("resizer niet beschikbaar met ffmpeg op het pad")
	}
	return r
}

func TestPlanNeverUpscalesAndIgnoresUnknownSources(t *testing.T) {
	r := newResizer(t)
	dir := t.TempDir()
	src := filepath.Join(dir, "poster.jpg")
	testsupport.MakeImage(t, src, 1000, 1500)

	if got := r.Plan(src, "poster", 300); got != 480 {
		t.Errorf("Plan(300) = %d, verwacht 480", got)
	}
	if got := r.Plan(src, "poster", 1000); got != 0 { // trede 1920 > bron 1000: het origineel
		t.Errorf("Plan(1000) = %d, verwacht 0 (nooit opschalen)", got)
	}
	if got := r.Plan(src, "poster", 960); got != 960 {
		t.Errorf("Plan(960) = %d, verwacht 960 (bron is breder dan de trede)", got)
	}
	if got := r.Plan(src, "poster", 0); got != 0 {
		t.Errorf("Plan(0) = %d", got)
	}
	if got := r.Plan(filepath.Join(dir, "weg.jpg"), "poster", 300); got != 0 {
		t.Errorf("Plan op een ontbrekend bestand = %d, verwacht 0", got)
	}
	junk := filepath.Join(dir, "x.webp")
	testsupport.WriteFile(t, junk, "geen beeld")
	if got := r.Plan(junk, "poster", 300); got != 0 {
		t.Errorf("Plan op een onleesbaar formaat = %d, verwacht 0", got)
	}
}

func TestMakeResizesCachesAndSingleFlights(t *testing.T) {
	r := newResizer(t)
	src := filepath.Join(t.TempDir(), "p.jpg")
	testsupport.MakeImage(t, src, 1200, 1800)

	var wg sync.WaitGroup
	paths := make([]string, 6)
	for i := range paths {
		wg.Add(1)
		go func() {
			defer wg.Done()
			p, ok := r.Make(context.Background(), src, "abc_1", 480)
			if !ok {
				t.Error("Make mislukte")
			}
			paths[i] = p
		}()
	}
	wg.Wait()
	for _, p := range paths {
		if p != paths[0] {
			t.Fatalf("gelijktijdige aanvragen gaven verschillende paden: %v", paths)
		}
	}
	if w := widthOf(t, paths[0]); w != 480 {
		t.Fatalf("afgeleide breedte %d, verwacht 480", w)
	}

	before, _ := os.Stat(paths[0])
	again, ok := r.Make(context.Background(), src, "abc_1", 480)
	after, _ := os.Stat(again)
	if !ok || !after.ModTime().Equal(before.ModTime()) {
		t.Fatal("een tweede aanvraag maakte het bestand opnieuw")
	}

	// Een andere generation is een andere bron en krijgt een eigen bestand.
	other, _ := r.Make(context.Background(), src, "abc_2", 480)
	if other == paths[0] {
		t.Fatal("een andere generation hergebruikte de oude afgeleide")
	}

	bytes, files, err := r.Stats()
	if err != nil || files != 2 || bytes <= 0 {
		t.Fatalf("Stats = %d bytes, %d bestanden, %v", bytes, files, err)
	}
	if err := r.Purge(); err != nil {
		t.Fatal(err)
	}
	if _, files, _ := r.Stats(); files != 0 {
		t.Fatalf("na Purge staan er nog %d bestanden", files)
	}
}

func TestMakeFailureFallsBackInsteadOfLeavingFiles(t *testing.T) {
	r := newResizer(t)
	bad := filepath.Join(t.TempDir(), "kapot.jpg")
	testsupport.WriteFile(t, bad, "geen jpeg")
	if _, ok := r.Make(context.Background(), bad, "k_1", 480); ok {
		t.Fatal("een kapot bestand gaf toch een afgeleide")
	}
	if _, files, _ := r.Stats(); files != 0 {
		t.Fatalf("een mislukte bewerking liet %d bestanden achter", files)
	}
}

func TestDisabledResizerPromisesNothing(t *testing.T) {
	for _, r := range []*Resizer{nil, New("", t.TempDir(), quiet()), New("ffmpeg", "", quiet()), New("bestaat-niet-xyz", t.TempDir(), quiet())} {
		if r.Available() {
			t.Fatal("een uitgeschakelde resizer meldt zich beschikbaar")
		}
		if got := r.Plan("/x.jpg", "poster", 300); got != 0 {
			t.Fatalf("Plan = %d", got)
		}
	}
}
