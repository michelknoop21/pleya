package id_test

import (
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// TestLayoutFollowsRFC9562 controleert versie- en variantbits.
func TestLayoutFollowsRFC9562(t *testing.T) {
	v := id.New()

	if got := v[6] >> 4; got != 7 {
		t.Fatalf("versienibble is %d, verwacht 7", got)
	}
	if got := v[8] >> 6; got != 0b10 {
		t.Fatalf("variantbits zijn %02b, verwacht 10", got)
	}
	if v.IsZero() {
		t.Fatal("een verse id is niet leeg")
	}
}

// TestSortableAndUnique is de reden voor v7 boven v4: de tijdsprefix maakt ids
// sorteerbaar op aanmaakmoment, en de cursorpaginering leunt daarop.
func TestSortableAndUnique(t *testing.T) {
	const count = 20000

	seen := make(map[id.ID]bool, count)
	previous := id.New()
	seen[previous] = true

	for i := 1; i < count; i++ {
		next := id.New()
		if seen[next] {
			t.Fatalf("dubbele id na %d stuks", i)
		}
		seen[next] = true

		if next.String() <= previous.String() {
			t.Fatalf("id %d sorteert vóór zijn voorganger: %s na %s",
				i, next.String(), previous.String())
		}
		previous = next
	}
}

func TestParseRoundTrip(t *testing.T) {
	original := id.New()
	back, err := id.Parse(original.String())
	if err != nil {
		t.Fatal(err)
	}
	if back != original {
		t.Fatalf("%s werd %s", original.String(), back.String())
	}
}

// TestParseRefusesGarbage: een id is voor de client ondoorzichtig, maar hij komt
// in een pad terug en moet dan kloppen.
func TestParseRefusesGarbage(t *testing.T) {
	for _, raw := range []string{
		"",
		"kort",
		"0198f2b0-1111-7000-8000-00000000000",
		"0198f2b0_1111_7000_8000_000000000001",
		"0198f2b0-1111-7000-8000-00000000000g",
		"../../etc/passwd",
	} {
		if _, err := id.Parse(raw); err == nil {
			t.Errorf("%q werd geaccepteerd", raw)
		}
	}
}
