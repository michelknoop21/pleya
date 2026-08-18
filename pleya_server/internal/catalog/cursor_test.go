package catalog_test

import (
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

func TestCursorRoundTrip(t *testing.T) {
	itemID := id.New()
	encoded := catalog.Cursor{Sort: catalog.SortTitle, Key: "Matrix, The", ID: itemID.String()}.Encode()

	back, err := catalog.DecodeCursor(encoded, catalog.SortTitle)
	if err != nil {
		t.Fatal(err)
	}
	if back.Key != "Matrix, The" || back.ID != itemID.String() {
		t.Fatalf("cursor kwam terug als %+v", back)
	}
}

// TestCursorBelongsToItsSort: een cursor die bij een andere sortering hoort geeft
// library.cursor_invalid, en opnieuw beginnen is dan de juiste reactie.
func TestCursorBelongsToItsSort(t *testing.T) {
	encoded := catalog.Cursor{Sort: catalog.SortTitle, Key: "x", ID: id.New().String()}.Encode()

	if _, err := catalog.DecodeCursor(encoded, catalog.SortYear); err == nil {
		t.Fatal("een cursor van een andere sortering werd geaccepteerd")
	}
	for _, raw := range []string{"niet base64!", "", "eyJzIjoidGl0bGUifQ"} {
		if raw == "" {
			c, err := catalog.DecodeCursor(raw, catalog.SortTitle)
			if err != nil || c != nil {
				t.Fatalf("een lege cursor hoort nil te geven zonder fout: %v %v", c, err)
			}
			continue
		}
		if _, err := catalog.DecodeCursor(raw, catalog.SortTitle); err == nil {
			t.Errorf("%q werd geaccepteerd als cursor", raw)
		}
	}
}

func TestParseSortAndLimits(t *testing.T) {
	if got, ok := catalog.ParseSort("", catalog.SortTitle); !ok || got != catalog.SortTitle {
		t.Fatalf("lege sort gaf %q", got)
	}
	if _, ok := catalog.ParseSort("verzonnen", catalog.SortTitle); ok {
		t.Fatal("een onbekende sortering werd geaccepteerd")
	}
	if !catalog.SortTitleDesc.Descending() || catalog.SortTitle.Descending() {
		t.Fatal("de richting wordt verkeerd gelezen")
	}

	// Een hogere waarde wordt naar het maximum teruggebracht en is geen fout.
	if got := catalog.ClampLimit(10000); got != catalog.MaxLimit {
		t.Fatalf("limit werd %d, verwacht %d", got, catalog.MaxLimit)
	}
	if got := catalog.ClampLimit(0); got != catalog.DefaultLimit {
		t.Fatalf("limit zonder waarde werd %d", got)
	}
}
