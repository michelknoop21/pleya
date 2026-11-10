package api

import (
	"strings"
	"testing"
)

// Rijke push (DEC-XXX) voegt alleen content_key toe aan de gesloten body: de
// A-21-body blijft geldig, een sleutel moet precies 32 bytes zijn.
func TestPushInstallationBodyTakesAnOptionalContentKey(t *testing.T) {
	const old = `{"device_token":"aabb","environment":"production","locale":"nl","movies":true}`
	key32 := strings.Repeat("A", 43) + "="
	for _, c := range []struct {
		name, body string
		ok         bool
		keyLen     int
	}{
		{"A-21-body zonder sleutel", old, true, 0},
		{"met sleutel", `{"device_token":"aabb","environment":"production","movies":true,"content_key":"` + key32 + `"}`, true, 32},
		{"te korte sleutel", `{"device_token":"aabb","environment":"production","movies":true,"content_key":"AAAA"}`, false, 0},
		{"geen base64", `{"device_token":"aabb","environment":"production","movies":true,"content_key":"` + strings.Repeat("!", 44) + `"}`, false, 0},
		{"onbekend veld blijft geweigerd", `{"device_token":"aabb","environment":"production","movies":true,"title":"x"}`, false, 0},
	} {
		body, key, ok := decodePushInstallation(strings.NewReader(c.body))
		if ok != c.ok || len(key) != c.keyLen {
			t.Errorf("%s: ok=%v sleutel=%d bytes, verwacht ok=%v en %d", c.name, ok, len(key), c.ok, c.keyLen)
		}
		if ok && body.Locale == "" {
			t.Errorf("%s: locale bleef leeg", c.name)
		}
	}
}
