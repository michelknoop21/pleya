package database

import (
	"errors"
	"net"
	"strings"

	"github.com/jackc/pgx/v5/pgconn"
)

// ErrUnavailable markeert een fout van een hulpprogramma (pg_dump, psql) dat de
// database niet kon bereiken. Die tools geven een exitcode en een tekst, geen
// Go-fout, dus de aanroeper wikkelt hem hierin zodat Unavailable hem herkent.
var ErrUnavailable = errors.New("de database is niet bereikbaar")

// Unavailable zegt of een fout betekent dat de database weg is, en niet dat een
// query fout was (faalpad "database weg", S25.5).
//
// Het onderscheid is wat een client nodig heeft: een weggevallen database gaat
// vanzelf over en is herhaalbaar (server.database_unavailable, 503), een fout in
// een query niet (server.internal, 500). Een verbindingsfout van pgx, een
// netwerkfout eronder en de foutklassen 08 (connection exception) en 57P0x
// (de server stopt of start nog) tellen; een PgError met een andere code is een
// antwoord van een database die er juist wél is.
func Unavailable(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, ErrUnavailable) {
		return true
	}
	var connectErr *pgconn.ConnectError
	if errors.As(err, &connectErr) {
		return true
	}
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return strings.HasPrefix(pgErr.Code, "08") || pgErr.Code == "57P01" || pgErr.Code == "57P02" || pgErr.Code == "57P03"
	}
	var netErr net.Error
	if errors.As(err, &netErr) {
		return true
	}
	// Een verbinding die eerder wegviel geeft pgconn terug als "conn closed",
	// zonder eigen type. Een kale onverwachte EOF telt bewust niet: die komt ook
	// uit een JSON-decoder of een afgekapt bestand, en dan is de database er wel.
	return strings.Contains(err.Error(), "conn closed")
}
