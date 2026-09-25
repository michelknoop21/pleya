package config

import (
	"errors"
	"fmt"
	"net/url"
	"strings"
)

// MaxCORSOrigins is de bovengrens op de lijst in cors_origins (K rij 14, en
// hoofdstuk 17a.2 van de specificatie).
//
// Zestien is ruim voor wat een thuisopstelling nodig heeft (de bundel zelf, een
// devserver, misschien een tweede hostnaam) en klein genoeg dat de lijst per
// aanvraag lineair doorlopen kan worden zonder dat dat iets kost. Een
// ongelimiteerde lijst is bovendien een manier om via één PATCH een
// instellingenrij te laten groeien die bij elke aanvraag gelezen wordt.
const MaxCORSOrigins = 16

// ErrOriginWildcard is `*` als origin. Hij is geen origin maar de afwezigheid
// van een grens, en `Access-Control-Allow-Origin: *` samen met een credential
// is precies de combinatie die browsers zelf al weigeren.
var ErrOriginWildcard = errors.New("is een jokerteken en geen origin")

// NormalizeOrigin toetst de vorm van een origin en geeft hem terug zoals een
// browser hem in de Origin-header zet.
//
// Een origin is schema, host en poort, en verder niets. Dat is smaller dan
// ParsePublicURL, die een pad toestaat: een pad in een origin bestaat niet, en
// hem accepteren zou een vergelijking opleveren die nooit klopt met wat de
// browser stuurt. `https://web.pleya.app/` komt er daarom uit als
// `https://web.pleya.app`, want dat is wat er in de header staat.
//
// Anders dan bij public_url wordt een privé-adres hier niet geweigerd. Deze
// waarde is geen doel dat de server aanroept maar een verwachting over wie hém
// aanroept, dus de aanval uit K rij 13 bestaat er niet; `http://nas:8832` is op
// een thuisnetwerk juist het goede antwoord.
func NormalizeOrigin(raw string) (string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", errors.New("is leeg")
	}
	if raw == "*" {
		return "", ErrOriginWildcard
	}

	u, err := url.Parse(raw)
	if err != nil {
		return "", fmt.Errorf("is geen origin: %w", err)
	}
	switch u.Scheme {
	case "http", "https":
	default:
		return "", fmt.Errorf("schema %q is niet http of https", u.Scheme)
	}
	if u.Host == "" {
		return "", errors.New("heeft geen host")
	}
	if u.User != nil {
		return "", errors.New("draagt inloggegevens")
	}
	if u.RawQuery != "" || u.Fragment != "" {
		return "", errors.New("draagt een querystring of fragment")
	}
	if u.Path != "" && u.Path != "/" {
		return "", errors.New("draagt een pad; een origin is alleen schema, host en poort")
	}

	// De host gaat in kleine letters mee omdat een browser hem zo stuurt; de
	// poort blijft staan zoals hij is, want :8832 en de default zijn twee
	// verschillende origins.
	return u.Scheme + "://" + strings.ToLower(u.Host), nil
}

// ParseCORSOrigins leest de komma-gescheiden lijst uit
// PLEYA_SERVER_CORS_ORIGINS en normaliseert elk stuk.
func ParseCORSOrigins(raw string) ([]string, error) {
	return NormalizeOrigins(splitList(raw))
}

// NormalizeOrigins toetst een hele lijst: elk stuk apart, ten hoogste
// MaxCORSOrigins stukken, en geen dubbele. Een dubbele is geen fout in de
// werking maar wel in de bedoeling, en stil ontdubbelen geeft een beheerder een
// lijst terug die hij niet heeft ingevuld.
func NormalizeOrigins(raw []string) ([]string, error) {
	if len(raw) > MaxCORSOrigins {
		return nil, fmt.Errorf("bevat %d origins; ten hoogste %d", len(raw), MaxCORSOrigins)
	}
	out := make([]string, 0, len(raw))
	seen := make(map[string]struct{}, len(raw))
	for _, part := range raw {
		origin, err := NormalizeOrigin(part)
		if err != nil {
			return nil, fmt.Errorf("%q: %w", part, err)
		}
		if _, dup := seen[origin]; dup {
			return nil, fmt.Errorf("%q staat er twee keer in", origin)
		}
		seen[origin] = struct{}{}
		out = append(out, origin)
	}
	return out, nil
}
