package catalog_test

import (
	"errors"
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

// TestCursorKeyMatchesItsSort: de sleutel gaat als parameter met een cast de SQL
// in, dus een sleutel die niet bij de sortering past klapt daar op een
// typefout. Dat hoort een 400 met library.cursor_invalid te zijn en geen 500.
func TestCursorKeyMatchesItsSort(t *testing.T) {
	itemID := id.New().String()

	bad := catalog.Cursor{Sort: catalog.SortYear, Key: "x", ID: itemID}.Encode()
	if _, err := catalog.DecodeCursor(bad, catalog.SortYear); !errors.Is(err, catalog.ErrCursorInvalid) {
		t.Fatalf("een year-cursor met sleutel \"x\" gaf %v, verwacht ErrCursorInvalid", err)
	}

	good := catalog.Cursor{Sort: catalog.SortYear, Key: "1999", ID: itemID}.Encode()
	if _, err := catalog.DecodeCursor(good, catalog.SortYear); err != nil {
		t.Fatalf("een year-cursor met sleutel \"1999\" werd geweigerd: %v", err)
	}

	// Op titel is elke tekst een geldige sleutel; daar valt niets te typeren.
	text := catalog.Cursor{Sort: catalog.SortTitle, Key: "x", ID: itemID}.Encode()
	if _, err := catalog.DecodeCursor(text, catalog.SortTitle); err != nil {
		t.Fatalf("een title-cursor met sleutel \"x\" werd geweigerd: %v", err)
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

// TestIndexCursorCarriesItsTitle: bij SortIndex hebben alle ongenummerde
// afleveringen dezelfde sleutel, dus de titel hoort in de cursor.
func TestIndexCursorCarriesItsTitle(t *testing.T) {
	itemID := id.New().String()
	title := "Bumba op reis"

	encoded := catalog.Cursor{Sort: catalog.SortIndex, Key: "2147483647", ID: itemID, Tie: &title}.Encode()
	back, err := catalog.DecodeCursor(encoded, catalog.SortIndex)
	if err != nil {
		t.Fatal(err)
	}
	if back.Tie == nil || *back.Tie != title {
		t.Fatalf("de titel kwam terug als %v", back.Tie)
	}
}

// TestIndexCursorWithoutTitleIsRefused: een cursor van vóór de tweede sleutel
// hervatten zou het laatste item van de vorige pagina opnieuw tonen. Weigeren
// geeft library.cursor_invalid en de client begint opnieuw.
func TestIndexCursorWithoutTitleIsRefused(t *testing.T) {
	old := catalog.Cursor{Sort: catalog.SortIndex, Key: "3", ID: id.New().String()}.Encode()
	if _, err := catalog.DecodeCursor(old, catalog.SortIndex); !errors.Is(err, catalog.ErrCursorInvalid) {
		t.Fatalf("een index-cursor zonder titel gaf %v, verwacht ErrCursorInvalid", err)
	}
}

// TestTitleCursorWithATieIsRefused: een sortering zonder tweede sleutel
// accepteert er ook geen, anders mengt een client twee ordeningen.
func TestTitleCursorWithATieIsRefused(t *testing.T) {
	tie := "x"
	c := catalog.Cursor{Sort: catalog.SortTitle, Key: "x", ID: id.New().String(), Tie: &tie}.Encode()
	if _, err := catalog.DecodeCursor(c, catalog.SortTitle); !errors.Is(err, catalog.ErrCursorInvalid) {
		t.Fatalf("een title-cursor met een tweede sleutel gaf %v, verwacht ErrCursorInvalid", err)
	}
}
