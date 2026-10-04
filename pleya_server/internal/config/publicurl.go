package config

import (
	"errors"
	"fmt"
	"net"
	"net/netip"
	"net/url"
	"strings"
)

// ErrPublicURLPrivate is het adres dat wel een geldige URL is maar geen doel
// mag zijn: loopback, een privé-bereik, link-local of het niet-gespecificeerde
// adres.
var ErrPublicURLPrivate = errors.New("wijst naar een privé- of link-local-adres")

// ParsePublicURL toetst de vorm van een publieke server-URL.
//
// Wat er wel in mag: http of https, een host, en hooguit een pad. Wat er niet
// in mag: gebruikersnaam en wachtwoord (die zouden in GET /server belanden),
// een querystring en een fragment (die horen bij een pagina en niet bij een
// serveradres). De vorm is opzettelijk smal, want deze waarde is het enige doel
// dat POST /server/connectivity-check ooit aanroept.
func ParsePublicURL(raw string) (*url.URL, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, errors.New("is leeg")
	}
	u, err := url.Parse(raw)
	if err != nil {
		return nil, fmt.Errorf("is geen URL: %w", err)
	}
	switch u.Scheme {
	case "http", "https":
	default:
		return nil, fmt.Errorf("schema %q is niet http of https", u.Scheme)
	}
	if u.Host == "" {
		return nil, errors.New("heeft geen host")
	}
	if u.User != nil {
		return nil, errors.New("draagt inloggegevens")
	}
	if u.RawQuery != "" || u.Fragment != "" {
		return nil, errors.New("draagt een querystring of fragment")
	}
	return u, nil
}

// ValidatePublicURL is ParsePublicURL zonder de uitkomst, voor het pad dat
// alleen wil weten of de waarde deugt.
func ValidatePublicURL(raw string) error {
	_, err := ParsePublicURL(raw)
	return err
}

// PublicURLIsPrivate zegt of de host een letterlijk adres in een bereik is dat
// nooit een publiek serveradres kan zijn.
//
// Alleen letterlijke adressen, geen DNS. Een naam opzoeken tijdens het
// valideren geeft schijnzekerheid: de aanvrager beheert de zone, dus hij kan de
// naam na de controle naar 169.254.169.254 laten wijzen en het antwoord is
// hetzelfde. Wat deze controle wél koopt is dat een beheerder de server niet
// met één PATCH op een metadata-endpoint of een buurserver kan richten (K rij
// 13), en dat is de aanval waar hij voor staat.
//
// De omgeving valt hier bewust buiten: PLEYA_SERVER_PUBLIC_URL komt van wie de
// container draait, en op een thuisnetwerk is 192.168.x.y het juiste antwoord.
// De grens ligt bij wat over de API binnenkomt.
func PublicURLIsPrivate(u *url.URL) bool {
	host := u.Hostname()
	if host == "" {
		return true
	}
	if lower := strings.ToLower(host); lower == "localhost" || strings.HasSuffix(lower, ".localhost") {
		return true
	}
	addr, err := netip.ParseAddr(host)
	if err != nil {
		// Een naam is geen letterlijk adres; zie de reden hierboven.
		return false
	}
	addr = addr.Unmap()
	return addr.IsLoopback() || addr.IsPrivate() || addr.IsLinkLocalUnicast() ||
		addr.IsLinkLocalMulticast() || addr.IsUnspecified() || addr.IsInterfaceLocalMulticast()
}

// TrustedProxy is één vertrouwd adres of bereik, met de tekst zoals hij
// geconfigureerd is. De tekst gaat mee omdat GET /server hem toont: een
// beheerder wil zien wat hij heeft ingevuld en niet een genormaliseerde vorm
// die hij niet herkent.
type TrustedProxy struct {
	Raw    string
	Prefix netip.Prefix
}

// ParseTrustedProxies leest de komma-gescheiden lijst uit
// PLEYA_SERVER_TRUSTED_PROXIES. Elk stuk is een adres (10.0.0.1) of een bereik
// (10.0.0.0/8).
func ParseTrustedProxies(raw string) ([]TrustedProxy, error) {
	parts := splitList(raw)
	out := make([]TrustedProxy, 0, len(parts))
	for _, part := range parts {
		prefix, err := parsePrefix(part)
		if err != nil {
			return nil, fmt.Errorf("%q: %w", part, err)
		}
		out = append(out, TrustedProxy{Raw: part, Prefix: prefix})
	}
	return out, nil
}

func parsePrefix(raw string) (netip.Prefix, error) {
	if strings.Contains(raw, "/") {
		prefix, err := netip.ParsePrefix(raw)
		if err != nil {
			return netip.Prefix{}, errors.New("is geen adres of bereik")
		}
		return prefix.Masked(), nil
	}
	addr, err := netip.ParseAddr(raw)
	if err != nil {
		return netip.Prefix{}, errors.New("is geen adres of bereik")
	}
	addr = addr.Unmap()
	return netip.PrefixFrom(addr, addr.BitLen()), nil
}

// TrustedProxyStrings geeft de lijst zoals hij geconfigureerd is.
func TrustedProxyStrings(proxies []TrustedProxy) []string {
	out := make([]string, 0, len(proxies))
	for _, p := range proxies {
		out = append(out, p.Raw)
	}
	return out
}

// RemoteAddrIsTrustedProxy zegt of remoteAddr (de vorm uit
// http.Request.RemoteAddr, dus host:poort) in de lijst valt.
func RemoteAddrIsTrustedProxy(proxies []TrustedProxy, remoteAddr string) bool {
	if len(proxies) == 0 {
		return false
	}
	host := remoteAddr
	if h, _, err := net.SplitHostPort(remoteAddr); err == nil {
		host = h
	}
	addr, err := netip.ParseAddr(strings.Trim(host, "[]"))
	if err != nil {
		return false
	}
	addr = addr.Unmap()
	for _, p := range proxies {
		if p.Prefix.Contains(addr) {
			return true
		}
	}
	return false
}
