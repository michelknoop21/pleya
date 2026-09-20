package api

import (
	"net/http"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/config"
)

// Het origin-model van S1.8 (RB-29, hoofdstuk 17d van de specificatie).
//
// Twee dingen die uit elkaar gehouden moeten worden. De **origin-controle**
// beslist of een aanvraag in cookiemodus bediend wordt; hij staat in
// handlers_auth.go en gebruikt originAllowed hieronder. De **CORS-laag**
// beslist of een browser het antwoord mag lézen; die staat hier als middleware.
//
// Ze delen dezelfde lijst en beantwoorden een andere vraag, en dat verschil is
// de reden dat de eerste een 403 kan geven en de tweede nooit een fout schrijft:
// een blokkade door CORS is het werk van de browser, en een server die er een
// eigen status van maakt geeft zijn origin-lijst prijs aan wie hem afloopt.

// requestIsSecure zegt of de client deze aanvraag over TLS deed.
//
// Twee bronnen, en de tweede alleen achter een vertrouwde proxy (K rij 8).
// Zonder die voorwaarde zet elke client zelf X-Forwarded-Proto: https, en dan
// zou hij de Secure-vlag op zijn eigen cookie kunnen bepalen. Op http://nas:8832
// blijft het antwoord false, en dan gaat Secure er niet op: een Secure-cookie
// over http wordt door de browser weggegooid, en dan werkt inloggen niet meer.
func (s *Server) requestIsSecure(r *http.Request) bool {
	if r.TLS != nil {
		return true
	}
	if !config.RemoteAddrIsTrustedProxy(s.opts.TrustedProxies, r.RemoteAddr) {
		return false
	}
	return strings.EqualFold(strings.TrimSpace(r.Header.Get("X-Forwarded-Proto")), "https")
}

// requestOrigin geeft de origin waarop deze aanvraag bij de server binnenkwam.
//
// Uit Host en het schema, want dat is wat de browser als Origin stuurt wanneer
// de pagina op deze server zelf draait. Host komt van de client en is dus niet
// te vertrouwen als identiteit, maar dat hoeft ook niet: hij wordt hier alleen
// met de Origin van diezelfde aanvraag vergeleken, en een aanvaller die beide
// kan zetten kan net zo goed rechtstreeks praten. Wat de vergelijking koopt is
// dat de pagina van de bezoeker niet die van een ander is.
func (s *Server) requestOrigin(r *http.Request) string {
	host := strings.TrimSpace(r.Host)
	if host == "" {
		return ""
	}
	scheme := "http"
	if s.requestIsSecure(r) {
		scheme = "https"
	}
	return scheme + "://" + strings.ToLower(host)
}

// originAllowed zegt of deze origin de cookiemodus mag gebruiken.
//
// Drie bronnen: de aanvraag zelf (same-origin), de canonieke webclient uit
// web_origin, en de lijst uit cors_origins. Een lege origin komt er nooit door;
// zie de reden bij requireAllowedOrigin.
func (s *Server) originAllowed(r *http.Request, origin string) bool {
	if origin == "" {
		return false
	}
	normalized, err := config.NormalizeOrigin(origin)
	if err != nil {
		return false
	}
	if normalized == s.requestOrigin(r) {
		return true
	}

	current := s.settings()
	if web := current.WebOrigin(); web != "" && normalized == web {
		return true
	}
	for _, allowed := range current.CORSOrigins() {
		if normalized == allowed {
			return true
		}
	}
	return false
}

// corsMethods is wat een preflight terugkrijgt: de methoden die dit protocol
// kent, en niet een sterretje. Een sterretje is bij een preflight geldig maar
// zegt niets, en het maakt een antwoord dat een browser cachet minder
// informatief dan het kan zijn.
const corsMethods = "GET, HEAD, POST, PATCH, PUT, DELETE"

// corsHeaders zijn de aanvraagheaders die een browser mag meesturen.
// Authorization omdat de API bearer-only is, Content-Type omdat elke body JSON
// is.
const corsHeaders = "Authorization, Content-Type"

// corsMaxAge is hoe lang een browser een preflight mag onthouden. Tien minuten:
// lang genoeg om een preflight per aanvraag te vermijden, kort genoeg dat een
// gewijzigde origin-lijst binnen een zitting doorwerkt.
const corsMaxAge = "600"

// cors zet de CORS-headers en beantwoordt de preflight.
//
// Access-Control-Allow-Credentials staat er bewust NIET bij. Zonder die header
// is cross-origin toegang bearer-only, precies zoals K rij 7 het beschrijft, en
// samen met SameSite=Strict op de refreshcookie betekent het dat cookiemodus
// per constructie same-site is. Dat is de uitvoering van RB-29's "geen ontwerp
// dat leunt op third-party cookies": het is niet verboden op papier, het kan
// niet.
//
// Een preflight wordt hier afgehandeld en niet in de mux. De routes dragen geen
// OPTIONS, dus een preflight zou anders bij de SPA-terugval belanden en een
// browser een pagina HTML geven waar hij headers verwacht.
func (s *Server) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := strings.TrimSpace(r.Header.Get("Origin"))
		if origin == "" {
			next.ServeHTTP(w, r)
			return
		}

		// Vary staat er ook wanneer de origin niet is toegestaan. Het antwoord
		// hángt van de Origin-header af, en een cache die dat niet weet zou het
		// antwoord voor de ene origin aan de andere kunnen geven.
		w.Header().Add("Vary", "Origin")

		if s.originAllowed(r, origin) && origin != s.requestOrigin(r) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
		}

		if r.Method == http.MethodOptions && r.Header.Get("Access-Control-Request-Method") != "" {
			// Een preflight is nooit een protocoloperatie en draagt geen
			// lichaam. 204 en klaar, ook wanneer de origin niet is toegestaan:
			// zonder Allow-Origin-header blokkeert de browser het echte verzoek
			// zelf, en dat is het antwoord dat het minst prijsgeeft.
			w.Header().Set("Access-Control-Allow-Methods", corsMethods)
			w.Header().Set("Access-Control-Allow-Headers", corsHeaders)
			w.Header().Set("Access-Control-Max-Age", corsMaxAge)
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}
