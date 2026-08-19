package catalog

import (
	"errors"
	"fmt"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
)

// TestCursorOrWrapMasksNothingElse bewaakt de smalle rand van het vangnet.
//
// Het vertaalt een typefout op de cursorwaarde naar ErrCursorInvalid, en dat is
// invoer van de client. Alles daarbuiten hoort een interne fout te blijven: een
// ontbrekende tabel als cursorfout melden zou een echt defect als een
// gebruikersfout laten lijken, en dan verdwijnt het uit beeld.
func TestCursorOrWrapMasksNothingElse(t *testing.T) {
	cursor := &Cursor{Sort: SortAddedAt, Key: "geen tijdstip", ID: "x"}
	typeFout := &pgconn.PgError{Code: "22P02", Message: "invalid input syntax"}

	if err := cursorOrWrap(cursor, typeFout, "items lezen"); !errors.Is(err, ErrCursorInvalid) {
		t.Errorf("een typefout mét cursor gaf %v, verwacht ErrCursorInvalid", err)
	}

	// Zonder cursor is diezelfde SQLSTATE niet aan de client toe te schrijven:
	// dan komt de waarde ergens anders vandaan en is er iets echt mis.
	if err := cursorOrWrap(nil, typeFout, "items lezen"); errors.Is(err, ErrCursorInvalid) {
		t.Error("een typefout zonder cursor werd als cursorfout gemeld")
	}

	// Een andere SQLSTATE is nooit een cursorfout, ook niet met een cursor erbij.
	andere := &pgconn.PgError{Code: "42P01", Message: "relation does not exist"}
	if err := cursorOrWrap(cursor, andere, "items lezen"); errors.Is(err, ErrCursorInvalid) {
		t.Error("een ontbrekende tabel werd als cursorfout gemeld")
	}

	// En een fout die helemaal niet uit Postgres komt evenmin.
	if err := cursorOrWrap(cursor, fmt.Errorf("verbinding weg"), "items lezen"); errors.Is(err, ErrCursorInvalid) {
		t.Error("een niet-Postgres-fout werd als cursorfout gemeld")
	}
}
