// Package settings houdt de serverinstellingen die een beheerder mag wijzigen.
//
// Drie regels bepalen wat hier wel en niet in staat, en ze komen alle drie uit
// K rij 14 van het securityplan.
//
// Een instelling heeft grenzen. Een TTL van een jaar is geen configuratie maar
// een gat, en een TTL van een seconde maakt de server onbruikbaar zonder dat
// iemand ziet waarom. De grens staat daarom bij de definitie en niet in de
// handler: dan geldt hij ook voor een pad dat later langs een andere kant
// binnenkomt.
//
// Bindadres, proxy's, paden en de ondertekensleutel zijn geen instelling. Wie
// het bindadres over de API kan wijzigen kan de server van het netwerk halen of
// hem juist openzetten, en dat hoort bij het draaien van de container en niet
// bij beheer in de app.
//
// Een ontbrekende rij betekent "neem de omgeving" (J.6). De omgeving is
// daarmee de onderste laag en de database de bovenste; `source` in het antwoord
// zegt welke van de twee een sleutel op dit moment levert.
package settings

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// De sleutels. Ze staan in het contract (schema Settings en SettingsPatch), dus
// hernoemen is een protocolwijziging en niet een refactor.
const (
	KeyServerName        = "server_name"
	KeyAccessTokenTTL    = "access_token_ttl"
	KeyRefreshTokenTTL   = "refresh_token_ttl"
	KeyStreamTokenTTL    = "stream_token_ttl"
	KeyStreamSessionTTL  = "stream_session_ttl"
	KeyMaxStreamSessions = "max_stream_sessions"
)

// Source zegt welke laag deze waarde levert.
type Source string

const (
	// SourceEnv is de omgeving plus de default in de binary. Die twee zijn hier
	// bewust één laag: config.Load lost ze op voordat de server start, en een
	// client die het verschil zou zien kan er niets mee.
	SourceEnv Source = "env"
	SourceDB  Source = "db"
)

// Kind is het type van een sleutel op de lijn.
type Kind int

const (
	// KindDuration is een Go-duurstring ("15m", "720h"). Dezelfde vorm als de
	// omgevingsvariabele ernaast, zodat een beheerder niet twee notaties hoeft
	// te kennen voor dezelfde instelling.
	KindDuration Kind = iota
	KindInt
	KindString
)

// Definition is één sleutel met zijn grenzen.
type Definition struct {
	Key  string
	Kind Kind

	MinDuration, MaxDuration time.Duration
	MinInt, MaxInt           int
	MinLen, MaxLen           int
}

// Definitions is de volledige lijst, in de volgorde waarin het contract ze
// noemt. Elke sleutel die hier niet in staat bestaat niet: PATCH weigert hem
// met een gesloten body, en GET toont hem niet.
var Definitions = []Definition{
	{Key: KeyServerName, Kind: KindString, MinLen: 1, MaxLen: 64},

	// De vijf grenzen uit K rij 14. Ze zijn geen smaak: een accesstoken dat een
	// dag geldig is maakt de intrekkingslatentie uit DEC-099 waardeloos, en een
	// refreshtoken van tien jaar maakt uitloggen op afstand een illusie.
	{Key: KeyAccessTokenTTL, Kind: KindDuration, MinDuration: time.Minute, MaxDuration: 60 * time.Minute},
	{Key: KeyRefreshTokenTTL, Kind: KindDuration, MinDuration: 24 * time.Hour, MaxDuration: 90 * 24 * time.Hour},
	{Key: KeyStreamTokenTTL, Kind: KindDuration, MinDuration: time.Minute, MaxDuration: 15 * time.Minute},
	{Key: KeyStreamSessionTTL, Kind: KindDuration, MinDuration: 5 * time.Minute, MaxDuration: 120 * time.Minute},
	{Key: KeyMaxStreamSessions, Kind: KindInt, MinInt: 1, MaxInt: 32},
}

// Find geeft de definitie van een sleutel.
func Find(key string) (Definition, bool) {
	for _, d := range Definitions {
		if d.Key == key {
			return d, true
		}
	}
	return Definition{}, false
}

// Minimum en Maximum geven de grens zoals hij in details van de foutvorm komt.
// Als tekst, ook voor een getal: een client toont ze naast elkaar en een
// gemengd type in hetzelfde veld levert daar alleen werk op.
func (d Definition) Minimum() string {
	switch d.Kind {
	case KindDuration:
		return d.MinDuration.String()
	case KindInt:
		return strconv.Itoa(d.MinInt)
	default:
		return strconv.Itoa(d.MinLen)
	}
}

func (d Definition) Maximum() string {
	switch d.Kind {
	case KindDuration:
		return d.MaxDuration.String()
	case KindInt:
		return strconv.Itoa(d.MaxInt)
	default:
		return strconv.Itoa(d.MaxLen)
	}
}

// InvalidValueError is de fout achter settings.invalid_value: het veld en de
// grens, zodat de client kan zeggen wat er mis is zonder de tekst te lezen.
type InvalidValueError struct {
	Field   string
	Minimum string
	Maximum string
	Reason  string
}

func (e *InvalidValueError) Error() string {
	if e.Reason != "" {
		return fmt.Sprintf("%s: %s", e.Field, e.Reason)
	}
	return fmt.Sprintf("%s ligt buiten %s tot %s", e.Field, e.Minimum, e.Maximum)
}

// Parse leest de waarde van één sleutel uit zijn JSON-vorm en toetst hem aan
// de grenzen.
//
// De uitkomst is time.Duration, int of string, afhankelijk van de soort. Een
// waarde van het verkeerde JSON-type is dezelfde fout als een waarde buiten de
// grens: beide zijn settings.invalid_value met het veld erbij, want voor de
// client is het verschil tussen "geen getal" en "te groot" niet bruikbaar
// anders dan in de tekst.
func Parse(key string, raw json.RawMessage) (any, error) {
	def, ok := Find(key)
	if !ok {
		return nil, &InvalidValueError{Field: key, Reason: "onbekende sleutel"}
	}

	switch def.Kind {
	case KindDuration:
		var text string
		if err := json.Unmarshal(raw, &text); err != nil {
			return nil, &InvalidValueError{Field: key, Reason: "verwacht een duur als tekst, bijvoorbeeld \"15m\"",
				Minimum: def.Minimum(), Maximum: def.Maximum()}
		}
		d, err := time.ParseDuration(strings.TrimSpace(text))
		if err != nil {
			return nil, &InvalidValueError{Field: key, Reason: "geen geldige duur",
				Minimum: def.Minimum(), Maximum: def.Maximum()}
		}
		if d < def.MinDuration || d > def.MaxDuration {
			return nil, &InvalidValueError{Field: key, Minimum: def.Minimum(), Maximum: def.Maximum()}
		}
		return d, nil

	case KindInt:
		// json.Number en niet int: 8.5 komt anders als 8 binnen, en een
		// stilzwijgend afgekapte waarde is precies het soort verschil tussen
		// gevraagd en opgeslagen dat later niemand meer kan verklaren.
		var number json.Number
		if err := json.Unmarshal(raw, &number); err != nil {
			return nil, &InvalidValueError{Field: key, Reason: "verwacht een geheel getal",
				Minimum: def.Minimum(), Maximum: def.Maximum()}
		}
		value, err := strconv.Atoi(number.String())
		if err != nil {
			return nil, &InvalidValueError{Field: key, Reason: "verwacht een geheel getal",
				Minimum: def.Minimum(), Maximum: def.Maximum()}
		}
		if value < def.MinInt || value > def.MaxInt {
			return nil, &InvalidValueError{Field: key, Minimum: def.Minimum(), Maximum: def.Maximum()}
		}
		return value, nil

	default:
		var text string
		if err := json.Unmarshal(raw, &text); err != nil {
			return nil, &InvalidValueError{Field: key, Reason: "verwacht tekst"}
		}
		trimmed := strings.TrimSpace(text)
		if len(trimmed) < def.MinLen || len(trimmed) > def.MaxLen {
			return nil, &InvalidValueError{Field: key, Minimum: def.Minimum(), Maximum: def.Maximum(),
				Reason: "lengte buiten de grens"}
		}
		return trimmed, nil
	}
}

// Encode zet een geparseerde waarde terug in zijn JSON-vorm, voor de kolom en
// voor het antwoord. Eén functie voor beide, zodat wat de database bewaart en
// wat de client ziet niet uit elkaar kunnen lopen.
func Encode(value any) (json.RawMessage, error) {
	switch v := value.(type) {
	case time.Duration:
		return json.Marshal(v.String())
	case int:
		return json.Marshal(v)
	case string:
		return json.Marshal(v)
	default:
		return nil, fmt.Errorf("waarde van onbekend type %T", value)
	}
}
