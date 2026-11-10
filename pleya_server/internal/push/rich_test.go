package push

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

// The vector the Swift side opens too (ios/NotificationService tests): one
// layout, nonce|ciphertext|tag, checked from both ends.
type richVector struct {
	Key       string `json:"key"`
	Nonce     string `json:"nonce"`
	Plaintext string `json:"plaintext"`
	Sealed    string `json:"sealed"`
}

func loadVector(t *testing.T) richVector {
	t.Helper()
	raw, err := os.ReadFile("testdata/rich_vector.json")
	if err != nil {
		t.Fatal(err)
	}
	var v richVector
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	return v
}

func TestSealMatchesTheSharedVectorAndOnlyItsKeyOpensIt(t *testing.T) {
	v := loadVector(t)
	key, _ := base64.StdEncoding.DecodeString(v.Key)
	nonce, _ := hex.DecodeString(v.Nonce)
	sealed, err := seal(key, []byte(v.Plaintext), bytes.NewReader(nonce))
	if err != nil {
		t.Fatal(err)
	}
	if got := base64.StdEncoding.EncodeToString(sealed); got != v.Sealed {
		t.Fatalf("sealed %s, vector says %s", got, v.Sealed)
	}
	open := func(key []byte) error {
		block, _ := aes.NewCipher(key)
		gcm, _ := cipher.NewGCM(block)
		_, err := gcm.Open(nil, sealed[:12], sealed[12:], nil)
		return err
	}
	if err := open(key); err != nil {
		t.Fatalf("own key does not open: %v", err)
	}
	other := bytes.Clone(key)
	other[0] ^= 1
	if open(other) == nil {
		t.Fatal("another key opened the content")
	}
	if bytes.Contains(sealed, []byte("Dune")) {
		t.Fatal("plaintext visible in the sealed bytes")
	}
}

func TestPayloadShowsAppleOnlyTheGenericAlert(t *testing.T) {
	var msg struct {
		APS struct {
			Alert          struct{ Title, Body string }
			MutableContent int `json:"mutable-content"`
		}
		Pleya *struct{ I, C string }
	}
	generic := payload("nl", "n1", "inst", "")
	if err := json.Unmarshal(generic, &msg); err != nil {
		t.Fatal(err)
	}
	if msg.APS.MutableContent != 0 || msg.Pleya != nil || msg.APS.Alert.Body != "Er staat iets nieuws in je bibliotheek." {
		t.Fatalf("generic payload carries rich parts: %s", generic)
	}
	rich := payload("nl", "n1", "inst", "c2VhbGVk")
	msg.Pleya = nil
	if err := json.Unmarshal(rich, &msg); err != nil {
		t.Fatal(err)
	}
	if msg.APS.MutableContent != 1 || msg.Pleya == nil || msg.Pleya.I != "inst" || msg.Pleya.C != "c2VhbGVk" ||
		msg.APS.Alert.Title != "Pleya" || msg.APS.Alert.Body != "Er staat iets nieuws in je bibliotheek." {
		t.Fatalf("rich payload wrong: %s", rich)
	}
}

func TestOversizedContentFallsBackToTheGenericAlert(t *testing.T) {
	huge := strings.Repeat("A", maxPayload)
	out := payload("en", "n1", "inst", huge)
	if len(out) > maxPayload {
		t.Fatalf("payload of %d bytes exceeds Apple's limit", len(out))
	}
	if !bytes.Equal(out, payload("en", "n1", "inst", "")) {
		t.Fatalf("oversized content did not fall back to the generic alert: %.120s", out)
	}
}

func TestDescribeNamesTheTitleAndTheBatch(t *testing.T) {
	one, three := 1, 3
	movie := catalog.Item{Kind: "movie", Title: "Dune"}
	season := &catalog.Item{Kind: "season", Index: &one}
	show := &catalog.Item{Kind: "show", Title: "The Bear"}
	episode := catalog.Item{Kind: "episode", Title: "System", Index: &three}
	for _, c := range []struct {
		got, title, body string
	}{
		{describeText(describe("nl", movie, nil, nil, 0)), "Nieuw: Dune", "Nieuwe film in je bibliotheek."},
		{describeText(describe("en", movie, nil, nil, 3)), "New: Dune and 3 more", "New movie in your library."},
		{describeText(describe("nl", episode, season, show, 9)), "Nieuw: The Bear en 9 meer", "Seizoen 1, aflevering 3: System"},
		{describeText(describe("en", episode, nil, show, 0)), "New: The Bear", "Episode 3: System"},
	} {
		if c.got != c.title+"|"+c.body {
			t.Errorf("got %q, want %q", c.got, c.title+"|"+c.body)
		}
	}
	long := describe("en", catalog.Item{Kind: "movie", Title: strings.Repeat("é", 500)}, nil, nil, 0)
	if n := len([]rune(long.Title)); n > maxTitleRunes+len("New: ") {
		t.Fatalf("title of %d runes not clipped", n)
	}
}

func describeText(c richContent) string { return c.Title + "|" + c.Body }
