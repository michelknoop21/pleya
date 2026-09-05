package logging

import "strings"

// EnvPrefix is de enige naamruimte die de server van zichzelf toont, naast
// DATABASE_URL. Alles daarbuiten is de omgeving van de container en niet van
// deze server: daar staan gerust credentials van heel andere diensten in, en
// die horen niet in een beheerscherm van een mediaserver.
const EnvPrefix = "PLEYA_SERVER_"

// EnvDatabaseURL krijgt zijn eigen behandeling: hij hoort er wel bij, want
// zonder hem is "waarom start hij niet" niet te beantwoorden, maar hij draagt
// een wachtwoord en gaat er dus als schema, host en databasenaam uit.
const EnvDatabaseURL = "DATABASE_URL"

// secretWords zijn de woorden die van een sleutelnaam een geheim maken. De
// vergelijking gaat per woord en niet per deelstring: PLEYA_SERVER_TOKEN_SIGNING
// is een geheim, PLEYA_SERVER_TRANSCODE_DIR niet, ook al staat er "cod" in.
var secretWords = map[string]bool{
	"PASSWORD": true, "PASSWD": true, "PASS": true, "SECRET": true,
	"KEY": true, "TOKEN": true, "CREDENTIAL": true, "CREDENTIALS": true,
	"SIGNATURE": true, "DSN": true,
}

// MaskEnvironment geeft de waarde zoals hij getoond mag worden, plus of er iets
// van af is gehaald.
//
// De regel is grof met opzet: een sleutelnaam met "token" erin gaat er in zijn
// geheel af, ook wanneer de waarde een duur is (PLEYA_SERVER_ACCESS_TOKEN_TTL).
// Dat kost niets, want de TTL's staan met hun bron en hun grens in
// GET /settings, en het houdt de regel hier op één vraag die niet per
// variabele opnieuw beoordeeld hoeft te worden. Een uitzonderingslijst zou bij
// de eerstvolgende variabele met een geheim in de naam stil te kort schieten.
func MaskEnvironment(key, value string) (string, bool) {
	if key == EnvDatabaseURL {
		return RedactDSN(value), true
	}
	if isSecretEnvKey(key) {
		return "[REDACTED]", true
	}
	// Ook een variabele met een onschuldige naam gaat langs de denylist: een
	// pad of een URL kan een token in een querystring dragen.
	masked := Redact(value)
	return masked, masked != value
}

func isSecretEnvKey(key string) bool {
	for _, word := range strings.Split(strings.ToUpper(key), "_") {
		if secretWords[word] {
			return true
		}
	}
	return false
}
