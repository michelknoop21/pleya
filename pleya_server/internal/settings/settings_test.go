package settings_test

import (
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/settings"
)

// De grenzen uit K rij 14, elk op zijn twee randen plus net erbuiten.
//
// Een test die alleen "15m mag" en "een jaar mag niet" toetst laat de grens
// zelf ongemeten, en juist daar zit de fout die niemand ziet: een `<` waar een
// `<=` hoort maakt de bovengrens onbruikbaar zonder dat een van beide
// voorbeelden omvalt.
func TestBoundsPerKey(t *testing.T) {
	cases := []struct {
		key   string
		value string
		ok    bool
	}{
		{settings.KeyAccessTokenTTL, `"1m"`, true},
		{settings.KeyAccessTokenTTL, `"60m"`, true},
		{settings.KeyAccessTokenTTL, `"59s"`, false},
		{settings.KeyAccessTokenTTL, `"61m"`, false},

		{settings.KeyRefreshTokenTTL, `"24h"`, true},
		{settings.KeyRefreshTokenTTL, `"2160h"`, true},
		{settings.KeyRefreshTokenTTL, `"23h"`, false},
		{settings.KeyRefreshTokenTTL, `"2161h"`, false},

		{settings.KeyStreamTokenTTL, `"1m"`, true},
		{settings.KeyStreamTokenTTL, `"15m"`, true},
		{settings.KeyStreamTokenTTL, `"30s"`, false},
		{settings.KeyStreamTokenTTL, `"16m"`, false},

		{settings.KeyStreamSessionTTL, `"5m"`, true},
		{settings.KeyStreamSessionTTL, `"120m"`, true},
		{settings.KeyStreamSessionTTL, `"4m"`, false},
		{settings.KeyStreamSessionTTL, `"121m"`, false},

		{settings.KeyMaxStreamSessions, `1`, true},
		{settings.KeyMaxStreamSessions, `32`, true},
		{settings.KeyMaxStreamSessions, `0`, false},
		{settings.KeyMaxStreamSessions, `33`, false},

		{settings.KeyServerName, `"Zolder"`, true},
		{settings.KeyServerName, `""`, false},
	}

	for _, c := range cases {
		_, err := settings.Parse(c.key, json.RawMessage(c.value))
		if c.ok && err != nil {
			t.Errorf("%s = %s werd geweigerd: %v", c.key, c.value, err)
		}
		if !c.ok && err == nil {
			t.Errorf("%s = %s werd geaccepteerd en ligt buiten de grens", c.key, c.value)
		}
	}
}

// Een naam van 65 tekens valt buiten de grens, een van 64 niet. Los van de
// tabel hierboven omdat de lengte uit een lus komt en niet uit een letterlijke
// waarde.
func TestServerNameLength(t *testing.T) {
	name := make([]byte, 64)
	for i := range name {
		name[i] = 'a'
	}
	if _, err := settings.Parse(settings.KeyServerName, mustJSON(t, string(name))); err != nil {
		t.Fatalf("64 tekens werd geweigerd: %v", err)
	}
	if _, err := settings.Parse(settings.KeyServerName, mustJSON(t, string(append(name, 'a')))); err == nil {
		t.Fatal("65 tekens werd geaccepteerd")
	}
}

// De fout draagt het veld en de grens, want daar leest een beheerscherm uit wat
// er mis is. Op de tekst matchen mag een client nooit (hoofdstuk 7.1).
func TestInvalidValueCarriesFieldAndBounds(t *testing.T) {
	_, err := settings.Parse(settings.KeyAccessTokenTTL, json.RawMessage(`"9h"`))
	var invalid *settings.InvalidValueError
	if !errors.As(err, &invalid) {
		t.Fatalf("fout = %v, wil *InvalidValueError", err)
	}
	if invalid.Field != settings.KeyAccessTokenTTL {
		t.Errorf("field = %q", invalid.Field)
	}
	if invalid.Minimum != "1m0s" || invalid.Maximum != "1h0m0s" {
		t.Errorf("grens = %q tot %q", invalid.Minimum, invalid.Maximum)
	}
}

// Een onbekende sleutel is een fout en geen veld dat wegvalt (K rij 14).
func TestUnknownKeyIsRejected(t *testing.T) {
	if _, err := settings.Parse("listen_addr", json.RawMessage(`":9999"`)); err == nil {
		t.Fatal("een onbekende sleutel werd geaccepteerd")
	}
}

// Het bindadres, de proxy's, de paden en de sleutel zijn geen instelling
// (K rij 14). Deze test legt die grens vast op de plek waar hij te breken is:
// de lijst met definities.
func TestDangerousKeysAreNotSettings(t *testing.T) {
	for _, key := range []string{
		"listen_addr", "http_addr", "trusted_proxies", "behind_proxy",
		"config_dir", "cache_dir", "transcode_dir", "media_dirs",
		"database_url", "signing_key",
	} {
		if _, ok := settings.Find(key); ok {
			t.Errorf("%s staat in de definities; die instelling hoort bij de container en niet bij beheer", key)
		}
	}
}

// Een getal met een komma komt niet stilzwijgend als afgekapt geheel getal
// binnen: wie 8.5 stuurt krijgt een fout en niet 8.
func TestFractionalIntegerIsRejected(t *testing.T) {
	if _, err := settings.Parse(settings.KeyMaxStreamSessions, json.RawMessage(`8.5`)); err == nil {
		t.Fatal("8.5 werd geaccepteerd als aantal streamsessies")
	}
}

// Wat eruit komt kun je zo weer insturen. Zonder die eigenschap zou een
// beheerscherm dat de set toont en terugstuurt zijn eigen waarde afkeuren.
func TestEncodeRoundTrips(t *testing.T) {
	parsed, err := settings.Parse(settings.KeyAccessTokenTTL, json.RawMessage(`"20m"`))
	if err != nil {
		t.Fatal(err)
	}
	raw, err := settings.Encode(parsed)
	if err != nil {
		t.Fatal(err)
	}
	again, err := settings.Parse(settings.KeyAccessTokenTTL, raw)
	if err != nil {
		t.Fatalf("de eigen uitvoer werd geweigerd: %v", err)
	}
	if again != 20*time.Minute {
		t.Fatalf("waarde = %v", again)
	}
}

// Zonder opslag is er alleen de omgeving, en dan geldt precies wat de server
// meekreeg. Dat is het gedrag van een server die migratie 0008 nog niet heeft
// gedraaid, niet een testgemak.
func TestCacheWithoutStoreServesTheEnvironment(t *testing.T) {
	cache := settings.NewCache(settings.Base{
		ServerName:        "Zolder",
		AccessTokenTTL:    15 * time.Minute,
		RefreshTokenTTL:   24 * time.Hour,
		StreamTokenTTL:    5 * time.Minute,
		StreamSessionTTL:  30 * time.Minute,
		MaxStreamSessions: 8,
	}, nil, nil)

	if cache.HasStore() {
		t.Fatal("een cache zonder store meldt dat hij er een heeft")
	}
	v := cache.Current()
	if v.ServerName() != "Zolder" || v.AccessTokenTTL() != 15*time.Minute || v.MaxStreamSessions() != 8 {
		t.Fatalf("waarden = %q, %v, %d", v.ServerName(), v.AccessTokenTTL(), v.MaxStreamSessions())
	}
	for _, d := range settings.Definitions {
		if v.Source(d.Key) != settings.SourceEnv {
			t.Errorf("%s heeft bron %q, wil env", d.Key, v.Source(d.Key))
		}
	}
}

func mustJSON(t *testing.T, v string) json.RawMessage {
	t.Helper()
	raw, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

// public_url is de zevende sleutel (S1.3). Zijn grens is geen lengte maar een
// vorm: K rij 13 wil dat een beheerder de connectivity-check niet op het
// interne netwerk kan richten.
func TestPublicURLRejectsPrivateAndMalformedTargets(t *testing.T) {
	for _, raw := range []string{
		`"http://169.254.169.254/latest/meta-data/"`,
		`"http://192.168.1.10:8080"`,
		`"http://10.0.0.5"`,
		`"https://127.0.0.1"`,
		`"https://localhost:8080"`,
		`"https://[::1]"`,
		`"ftp://pleya.example"`,
		`"https://user:pass@pleya.example"`,
		`"https://pleya.example/?token=x"`,
		`"geen-url"`,
		`42`,
	} {
		if _, err := settings.Parse(settings.KeyPublicURL, json.RawMessage(raw)); err == nil {
			t.Errorf("%s werd geaccepteerd als publiek adres", raw)
		}
	}
}

func TestPublicURLAcceptsAPublicAddress(t *testing.T) {
	for _, raw := range []string{
		`"https://web.pleya.app"`,
		`"https://web.pleya.app/pleya"`,
		`"http://203.0.113.10:8080"`,
	} {
		if _, err := settings.Parse(settings.KeyPublicURL, json.RawMessage(raw)); err != nil {
			t.Errorf("%s werd geweigerd: %v", raw, err)
		}
	}
}

// Leegmaken mag: dan valt de sleutel terug op de omgeving, net als elke andere
// sleutel zonder rij in de tabel.
func TestPublicURLCanBeCleared(t *testing.T) {
	value, err := settings.Parse(settings.KeyPublicURL, json.RawMessage(`""`))
	if err != nil {
		t.Fatalf("leegmaken werd geweigerd: %v", err)
	}
	if value != "" {
		t.Fatalf("leegmaken gaf %q", value)
	}
}
