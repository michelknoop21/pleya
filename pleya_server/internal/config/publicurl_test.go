package config_test

import (
	"net/url"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/config"
)

// De vorm van PLEYA_SERVER_PUBLIC_URL en de vertrouwde proxy's (S1.3).

func TestParsePublicURLShape(t *testing.T) {
	for _, ok := range []string{
		"https://web.pleya.app",
		"http://192.168.1.10:8080", // uit de omgeving mag een privé-adres wel
		"https://web.pleya.app/pleya",
	} {
		if _, err := config.ParsePublicURL(ok); err != nil {
			t.Errorf("%s werd geweigerd: %v", ok, err)
		}
	}
	for _, bad := range []string{
		"", "geen-url", "ftp://pleya.example", "https://", "//pleya.example",
		"https://user:pass@pleya.example", "https://pleya.example/?token=x", "https://pleya.example/#top",
	} {
		if _, err := config.ParsePublicURL(bad); err == nil {
			t.Errorf("%q werd geaccepteerd", bad)
		}
	}
}

// PublicURLIsPrivate kijkt naar letterlijke adressen en zoekt geen naam op. Dat
// is een keuze met een reden (K rij 13): wie de zone beheert kan een naam na de
// controle toch verzetten, dus een lookup koopt schijnzekerheid.
func TestPublicURLIsPrivate(t *testing.T) {
	for raw, want := range map[string]bool{
		"http://169.254.169.254/": true,
		"http://192.168.1.10":     true,
		"http://10.0.0.5":         true,
		"http://172.16.0.1":       true,
		"https://127.0.0.1":       true,
		"https://[::1]":           true,
		"https://localhost":       true,
		"https://api.localhost":   true,
		"http://0.0.0.0":          true,
		"https://web.pleya.app":   false,
		"http://203.0.113.10":     false,
		"http://8.8.8.8":          false,
	} {
		u, err := url.Parse(raw)
		if err != nil {
			t.Fatal(err)
		}
		if got := config.PublicURLIsPrivate(u); got != want {
			t.Errorf("PublicURLIsPrivate(%q) = %v, verwacht %v", raw, got, want)
		}
	}
}

func TestParseTrustedProxies(t *testing.T) {
	proxies, err := config.ParseTrustedProxies(" 172.18.0.0/16 , 10.0.0.7 ")
	if err != nil {
		t.Fatal(err)
	}
	if got := config.TrustedProxyStrings(proxies); len(got) != 2 || got[0] != "172.18.0.0/16" || got[1] != "10.0.0.7" {
		t.Fatalf("de lijst komt terug als %v; de ingevulde tekst hoort behouden te blijven", got)
	}

	for addr, want := range map[string]bool{
		"172.18.0.4:51234":  true,
		"10.0.0.7:1":        true,
		"10.0.0.8:1":        false,
		"192.168.1.1:80":    false,
		"[fd00::1]:443":     false,
		"geen-adres":        false,
		"172.18.255.255:99": true,
	} {
		if got := config.RemoteAddrIsTrustedProxy(proxies, addr); got != want {
			t.Errorf("RemoteAddrIsTrustedProxy(%q) = %v, verwacht %v", addr, got, want)
		}
	}

	// Zonder lijst is niemand vertrouwd, ook niet een adres dat er als een
	// proxy uitziet.
	if config.RemoteAddrIsTrustedProxy(nil, "172.18.0.4:1") {
		t.Error("zonder geconfigureerde proxy's hoort niets vertrouwd te zijn")
	}

	if _, err := config.ParseTrustedProxies("niet-een-adres"); err == nil {
		t.Error("een onzinwaarde werd geaccepteerd")
	}
}

// Load weigert te starten op een onbruikbaar publiek adres of een onzinnige
// proxylijst. Luid falen bij het opstarten is hier beter dan een beheerscherm
// dat later een veld toont dat nergens op slaat.
func TestLoadValidatesTheNewVariables(t *testing.T) {
	base := map[string]string{"DATABASE_URL": "postgres://p@db:5432/p"}
	load := func(extra map[string]string) error {
		values := map[string]string{}
		for k, v := range base {
			values[k] = v
		}
		for k, v := range extra {
			values[k] = v
		}
		_, err := config.Load(func(key string) string { return values[key] })
		return err
	}

	if err := load(nil); err != nil {
		t.Fatalf("zonder de nieuwe variabelen hoort Load gewoon te slagen: %v", err)
	}
	if err := load(map[string]string{"PLEYA_SERVER_PUBLIC_URL": "ftp://x"}); err == nil {
		t.Error("een onbruikbaar publiek adres liet de server starten")
	}
	if err := load(map[string]string{"PLEYA_SERVER_TRUSTED_PROXIES": "niet-een-adres"}); err == nil {
		t.Error("een onzinnige proxylijst liet de server starten")
	}

	cfg, err := config.Load(func(key string) string {
		return map[string]string{
			"DATABASE_URL":                 "postgres://p@db:5432/p",
			"PLEYA_SERVER_PUBLIC_URL":      "https://web.pleya.app",
			"PLEYA_SERVER_TRUSTED_PROXIES": "172.18.0.0/16",
		}[key]
	})
	if err != nil {
		t.Fatal(err)
	}
	if cfg.PublicURL != "https://web.pleya.app" || len(cfg.TrustedProxies) != 1 {
		t.Fatalf("public_url = %q, proxies = %v", cfg.PublicURL, cfg.TrustedProxies)
	}
}
