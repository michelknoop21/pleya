package logging

import (
	"bytes"
	"log/slog"
	"strings"
	"testing"
)

func ringLogger(capacity int) (*Ring, *slog.Logger) {
	ring := NewRing(capacity)
	return ring, slog.New(ring.Handler(nil))
}

// Nieuwste eerst, en niet meer dan gevraagd.
func TestRingReturnsNewestFirst(t *testing.T) {
	ring, log := ringLogger(8)
	for _, msg := range []string{"een", "twee", "drie"} {
		log.Info(msg)
	}

	got := ring.Entries(slog.LevelDebug, 10)
	if len(got) != 3 {
		t.Fatalf("%d regels, verwacht 3", len(got))
	}
	if got[0].Message != "drie" || got[2].Message != "een" {
		t.Fatalf("volgorde klopt niet: %q, %q, %q", got[0].Message, got[1].Message, got[2].Message)
	}
	if limited := ring.Entries(slog.LevelDebug, 2); len(limited) != 2 || limited[0].Message != "drie" {
		t.Fatalf("limiet werkt niet: %+v", limited)
	}
}

// De buffer is een ring: regel 1 valt eruit zodra er meer dan capacity in gaan,
// en wat er wél in staat blijft leesbaar. Zonder deze test zou een fout in de
// modulorekenkunde pas zichtbaar worden op een server die lang genoeg draait.
func TestRingOverwritesOldest(t *testing.T) {
	ring, log := ringLogger(3)
	for _, msg := range []string{"een", "twee", "drie", "vier", "vijf"} {
		log.Info(msg)
	}

	got := ring.Entries(slog.LevelDebug, 100)
	if len(got) != 3 {
		t.Fatalf("%d regels, verwacht 3 (de capaciteit)", len(got))
	}
	want := []string{"vijf", "vier", "drie"}
	for i, w := range want {
		if got[i].Message != w {
			t.Fatalf("regel %d is %q, verwacht %q", i, got[i].Message, w)
		}
	}
}

func TestRingFiltersOnLevel(t *testing.T) {
	ring, log := ringLogger(16)
	log.Debug("laag")
	log.Info("midden")
	log.Warn("hoger")
	log.Error("hoogst")

	if got := ring.Entries(slog.LevelWarn, 100); len(got) != 2 {
		t.Fatalf("%d regels vanaf warn, verwacht 2: %+v", len(got), got)
	}
	if got := ring.Entries(slog.LevelDebug, 100); len(got) != 4 {
		t.Fatalf("%d regels vanaf debug, verwacht 4", len(got))
	}
}

// Component() hangt zijn naam met WithAttrs aan de logger, niet aan elke
// Record. Een handler die dat niet onthoudt levert een logscherm zonder
// subsysteem op, en dan is filteren op "wat deed de scanner" onmogelijk.
func TestRingKeepsComponent(t *testing.T) {
	ring, log := ringLogger(8)
	Component(log, "scanner").Info("ronde klaar", "files", 12)

	got := ring.Entries(slog.LevelDebug, 1)
	if len(got) != 1 {
		t.Fatal("geen regel")
	}
	if got[0].Component != "scanner" {
		t.Errorf("component = %q", got[0].Component)
	}
	if got[0].Message != "ronde klaar files=12" {
		t.Errorf("message = %q; de attributen horen erin", got[0].Message)
	}
}

// De regel wordt geredigeerd op de schrijfkant. Dat is K rij 11: er is dan geen
// leespad dat de redactie kan overslaan, en het geheim staat ook niet in het
// geheugen van de buffer te wachten.
func TestRingRedactsOnTheWayIn(t *testing.T) {
	ring, log := ringLogger(8)
	log.Warn("upstream weigerde", "url", "https://host/api?api_key=zeergeheim",
		"auth", "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.x.y")

	got := ring.Entries(slog.LevelDebug, 1)
	if len(got) != 1 {
		t.Fatal("geen regel")
	}
	if strings.Contains(got[0].Message, "zeergeheim") || strings.Contains(got[0].Message, "eyJhbGciOiJIUzI1NiJ9") {
		t.Fatalf("de buffer draagt een credential: %s", got[0].Message)
	}
	if !strings.Contains(got[0].Message, "[REDACTED]") {
		t.Fatalf("er is niets geredigeerd: %s", got[0].Message)
	}
}

// Een lange regel wordt afgekapt, zodat één stacktrace de buffer niet vult.
func TestRingTruncatesLongLines(t *testing.T) {
	ring, log := ringLogger(4)
	log.Error("stuk", "stack", strings.Repeat("a", 5000))

	got := ring.Entries(slog.LevelDebug, 1)
	if len(got) != 1 {
		t.Fatal("geen regel")
	}
	if len([]rune(got[0].Message)) > maxRenderedLength+1 {
		t.Fatalf("regel is %d tekens; de grens is %d", len([]rune(got[0].Message)), maxRenderedLength)
	}
}

// De buffer hangt naast de gewone logger en vervangt hem niet: wat naar stdout
// gaat blijft daar staan, met stack en al.
func TestRingPassesThroughToInner(t *testing.T) {
	var out bytes.Buffer
	ring := NewRing(4)
	log := slog.New(ring.Handler(slog.NewJSONHandler(&out, &slog.HandlerOptions{Level: slog.LevelInfo})))

	log.Info("doorgegeven")

	if !strings.Contains(out.String(), "doorgegeven") {
		t.Fatalf("de onderliggende handler kreeg niets: %q", out.String())
	}
	if len(ring.Entries(slog.LevelDebug, 10)) != 1 {
		t.Fatal("de buffer kreeg niets")
	}
}

func TestParseLevelName(t *testing.T) {
	for name, want := range map[string]slog.Level{
		"debug": slog.LevelDebug, "info": slog.LevelInfo,
		"warn": slog.LevelWarn, "WARNING": slog.LevelWarn, "error": slog.LevelError,
	} {
		got, ok := ParseLevelName(name)
		if !ok || got != want {
			t.Errorf("ParseLevelName(%q) = %v, %v", name, got, ok)
		}
	}
	if _, ok := ParseLevelName("kritiek"); ok {
		t.Error("een onbekend niveau hoort geweigerd te worden")
	}
	for level, want := range map[slog.Level]string{
		slog.LevelDebug: "debug", slog.LevelInfo: "info",
		slog.LevelWarn: "warn", slog.LevelError: "error",
	} {
		if got := LevelName(level); got != want {
			t.Errorf("LevelName(%v) = %q, verwacht %q", level, got, want)
		}
	}
}
