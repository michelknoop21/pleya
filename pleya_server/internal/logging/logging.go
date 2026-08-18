// Package logging levert de gestructureerde logger en de redactie van
// credentials.
//
// Hoofdstuk 18 van de architectuur schrijft JSON voor, met een niveau per
// subsysteem. Het subsysteem zit hier in het veld "component".
package logging

import (
	"io"
	"log/slog"
	"net/url"
	"strings"
)

// New bouwt een JSON-logger op stdout.
func New(level slog.Level, w io.Writer) *slog.Logger {
	return slog.New(slog.NewJSONHandler(w, &slog.HandlerOptions{Level: level}))
}

// Component geeft een afgeleide logger die elk bericht aan een subsysteem hangt.
func Component(l *slog.Logger, name string) *slog.Logger {
	return l.With(slog.String("component", name))
}

// RedactDSN houdt van een databaseverbinding alleen over wat bruikbaar is bij
// het lezen van een log: het schema, de host, de poort en de databasenaam.
//
// Gebruiker, wachtwoord en querystring gaan er onvoorwaardelijk af. De
// querystring ook, want daar staan sslmode en soms een wachtwoord in. Bij een
// onleesbare invoer komt er niets van de invoer terug: liever een nutteloze
// logregel dan een gelekte credential.
func RedactDSN(dsn string) string {
	dsn = strings.TrimSpace(dsn)
	if dsn == "" {
		return "(leeg)"
	}

	u, err := url.Parse(dsn)
	if err != nil || u.Host == "" {
		return "(onleesbaar)"
	}

	out := u.Host
	if u.Scheme != "" {
		out = u.Scheme + "://" + out
	}
	if db := strings.TrimPrefix(u.Path, "/"); db != "" {
		out += "/" + db
	}
	return out
}
