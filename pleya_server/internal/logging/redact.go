package logging

import (
	"regexp"
	"strings"
)

// Redact haalt bekende credentials uit een regel tekst.
//
// Dit is de derde implementatie van dezelfde denylist. De eerste staat in de
// app (`lib/utils/log_redaction_manager.dart`), de tweede in de Verify-runner
// (`pleya_verify/runner/lib/src/redact.dart`), en ze delen hun testvectoren in
// `pleya_verify/redact/cases.json`. Deze port leest diezelfde vectoren
// (`redact_test.go`), zodat een regel die de app kent en deze server mist rood
// draait aan de kant die achterloopt in plaats van stil door te lopen.
//
// K rij 11 van het securityplan vraagt hem hier: `GET /server/log` en
// `GET /server/environment` tonen tekst die de server zelf heeft geschreven, en
// die tekst mag geen token, DSN of wachtwoord dragen. De redactie zit daarom op
// de weg *naar* de ringbuffer en niet pas op de weg naar buiten: dan is er geen
// pad dat hem kan overslaan, en staat een geheim ook nooit in het geheugen van
// de buffer.
//
// Twee verschillen met de Dart-vorm, en allebei zijn ze noodzaak en geen keuze.
// RE2 kent geen terugverwijzing, dus het IPv4-patroon vergelijkt zijn drie
// scheidingstekens in de vervanger. En RE2 kent geen lookaround, dus de
// negatieve lookbehind is een gevangen voorafgaand teken geworden en de
// negatieve lookahead een controle op de gevangen waarde. De uitkomst is per
// vector gelijk; dat is precies wat de gedeelde vectoren meten.
//
// Wat hier bewust níét in zit is de geregistreerde laag van de app
// (`registerToken`, `registerServerUrl`): die redigeert waarden die de app op
// dat moment in handen heeft. Deze server heeft zijn eigen equivalent in
// [MaskEnvironment] en [RedactDSN].
func Redact(message string) string {
	out := ipv4Pattern.ReplaceAllStringFunc(message, maskIPv4)

	out = plexTokenQueryParam.ReplaceAllString(out, "X-Plex-Token=[REDACTED]")
	out = jellyfinAPIKeyQueryParam.ReplaceAllString(out, "api_key=[REDACTED]")
	out = quickConnectSecretQueryParam.ReplaceAllString(out, "secret=[REDACTED]")
	out = embyTokenHeader.ReplaceAllStringFunc(out, maskEmbyToken)
	out = mediaBrowserTokenHeader.ReplaceAllString(out, `Token="[REDACTED]"`)

	out = replaceValue(secretQueryParam, out, "[REDACTED]")
	out = replaceValue(secretQuotedField, out, `[REDACTED]"`)
	out = replaceValue(schemeCredential, out, "[REDACTED]")
	out = replaceValue(credentialHeader, out, "[REDACTED]")

	return out
}

// alreadyRedacted is de vervanging van de negatieve lookahead uit de
// Dart-vorm: een waarde die al geredigeerd is blijft zoals hij is, zodat een
// tweede ronde over dezelfde tekst niets meer verandert.
const alreadyRedacted = "[REDACTED"

// secretNames zijn de veldnamen waarvan de waarde een credential is, ongeacht
// hoe die waarde eruitziet. Letterlijk overgenomen uit de Dart-vorm.
const secretNames = `api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|auth[_-]?token|` +
	`token|secret|password|passwd|pwd|credential|signature|sig|session[_-]?id|` +
	`client[_-]?secret|device[_-]?token|x-plex-token`

// credentialHeaderNames zijn headers waarvan de hele waarde eraf gaat.
const credentialHeaderNames = `authorization|proxy-authorization|x-api-key|x-auth-token|cookie|set-cookie`

// notWordBefore vangt het teken vóór een naam. De Dart-vorm gebruikt hier een
// negatieve lookbehind; RE2 heeft die niet, dus het teken wordt gevangen en in
// de vervanger weer teruggezet.
const notWordBefore = `(^|[^A-Za-z0-9])`

var (
	// Vier getallen met drie gelijke scheidingstekens. De gelijkheid wordt in
	// maskIPv4 getoetst, want RE2 kent geen terugverwijzing.
	ipv4Pattern = regexp.MustCompile(`\b(\d{1,3})([.-])(\d{1,3})([.-])(\d{1,3})([.-])(\d{1,3})\b`)

	plexTokenQueryParam          = regexp.MustCompile(`(?i)X-Plex-Token=[^&#\s]+`)
	jellyfinAPIKeyQueryParam     = regexp.MustCompile(`(?i)api_key=[^&#\s]+`)
	quickConnectSecretQueryParam = regexp.MustCompile(`(?i)secret=[^&#\s]+`)
	embyTokenHeader              = regexp.MustCompile(`(?i)X-Emby-Token[:=]\s*[^,;&#\s"]+`)
	mediaBrowserTokenHeader      = regexp.MustCompile(`(?i)Token="[^"]+"`)

	secretQueryParam  = regexp.MustCompile(`(?i)` + notWordBefore + `((?:` + secretNames + `)\s*=\s*)([^&#\s"\\]+)`)
	secretQuotedField = regexp.MustCompile(`(?i)` + notWordBefore + `((?:` + secretNames + `)\s*=\s*")([^"]*)"`)

	schemeCredential = regexp.MustCompile(`(?i)` + notWordBefore +
		`((?:authorization|proxy-authorization)\s*[:=]\s*(?:bearer|basic|digest|token|apikey)\s+)([^\s,;]+)`)

	credentialHeader = regexp.MustCompile(`(?i)` + notWordBefore +
		`((?:` + credentialHeaderNames + `)\s*[:=]\s*)([^\n\r]+)`)
)

// maskIPv4 houdt het eerste en het laatste octet en maakt de middelste twee x.
// Genoeg om twee hosts uit elkaar te houden in een log, te weinig om een
// netwerk mee in kaart te brengen.
func maskIPv4(match string) string {
	parts := ipv4Pattern.FindStringSubmatch(match)
	if parts == nil {
		return match
	}
	// De drie scheidingstekens moeten gelijk zijn; 1.2-3.4 is geen adres.
	if parts[2] != parts[4] || parts[4] != parts[6] {
		return match
	}
	sep := parts[2]
	return parts[1] + sep + "x" + sep + "x" + sep + parts[7]
}

// maskEmbyToken houdt het scheidingsteken dat er stond. De dubbele punt is een
// header, het isgelijkteken een queryparameter, en een logregel leest verkeerd
// als de vorm verandert.
func maskEmbyToken(match string) string {
	separator := "="
	if strings.Contains(match, ":") {
		separator = ":"
	}
	return "X-Emby-Token" + separator + " [REDACTED]"
}

// replaceValue vervangt de derde vanggroep van elk treffer door replacement en
// laat de eerste twee staan.
//
// Handmatig over de indexen en niet met ReplaceAllStringFunc: die geeft alleen
// de treffer als tekst, en dan zou het patroon opnieuw op die tekst gedraaid
// moeten worden om bij de groepen te komen. Dat werkt hier toevallig, maar het
// is een tweede meting die met de eerste uit de pas kan lopen zodra een patroon
// een anker krijgt.
func replaceValue(re *regexp.Regexp, s, replacement string) string {
	matches := re.FindAllStringSubmatchIndex(s, -1)
	if matches == nil {
		return s
	}

	var b strings.Builder
	last := 0
	for _, m := range matches {
		if strings.Contains(s[m[6]:m[7]], alreadyRedacted) {
			continue
		}
		b.WriteString(s[last:m[6]])
		b.WriteString(replacement)
		last = m[1]
	}
	b.WriteString(s[last:])
	return b.String()
}
