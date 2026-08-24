package auth_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
)

var testParams = auth.Argon2Params{Memory: 8 * 1024, Iterations: 1, Parallelism: 1, SaltLength: 16, KeyLength: 32}

func TestPasswordRoundTrip(t *testing.T) {
	hash, err := auth.HashPassword("een-lang-genoeg-wachtwoord", testParams)
	if err != nil {
		t.Fatal(err)
	}

	// De parameters staan in de hash zelf, in PHC-vorm. Dat is de reden dat
	// verifiëren nergens op de configuratie leunt.
	if !strings.HasPrefix(hash, "$argon2id$v=19$m=8192,t=1,p=1$") {
		t.Fatalf("hash draagt zijn parameters niet: %q", hash)
	}

	ok, rehash, err := auth.VerifyPassword("een-lang-genoeg-wachtwoord", hash, testParams)
	if err != nil || !ok {
		t.Fatalf("het juiste wachtwoord werd afgekeurd: %v %v", ok, err)
	}
	if rehash {
		t.Fatal("een hash met de huidige parameters hoeft niet opnieuw")
	}

	wrong, _, err := auth.VerifyPassword("iets anders", hash, testParams)
	if err != nil || wrong {
		t.Fatalf("een fout wachtwoord werd goedgekeurd: %v %v", wrong, err)
	}
}

// TestRehashWhenParametersRise dekt eigenschap 3 uit specificatie 6.5: zwaarder
// hashen vraagt geen schemawijziging.
func TestRehashWhenParametersRise(t *testing.T) {
	light, err := auth.HashPassword("wachtwoord-van-toen", testParams)
	if err != nil {
		t.Fatal(err)
	}

	heavier := testParams
	heavier.Memory *= 4

	ok, rehash, err := auth.VerifyPassword("wachtwoord-van-toen", light, heavier)
	if err != nil || !ok {
		t.Fatalf("een oudere hash werd afgekeurd: %v %v", ok, err)
	}
	if !rehash {
		t.Fatal("een lichtere hash hoort opnieuw gehasht te worden bij de eerstvolgende login")
	}
}

func TestVerifyRefusesGarbage(t *testing.T) {
	for _, hash := range []string{
		"",
		"gewoon-tekst",
		"$argon2i$v=19$m=8192,t=1,p=1$c2FsdA$aGFzaA",
		"$argon2id$v=13$m=8192,t=1,p=1$c2FsdA$aGFzaA",
	} {
		if _, _, err := auth.VerifyPassword("x", hash, testParams); err == nil {
			t.Errorf("%q werd geaccepteerd als hash", hash)
		}
	}
}

func TestTokenRoundTrip(t *testing.T) {
	signer := mustSigner(t)

	token, claims, err := signer.Mint("owner", "sessie-1", auth.TokenAccess, time.Minute, "")
	if err != nil {
		t.Fatal(err)
	}
	if claims.Subject != "owner" || claims.Sid != "sessie-1" || claims.Type != auth.TokenAccess {
		t.Fatalf("claims zijn %+v", claims)
	}

	back, err := signer.Verify(token, auth.TokenAccess)
	if err != nil {
		t.Fatalf("het eigen token werd afgekeurd: %v", err)
	}
	if back.Subject != "owner" || back.Sid != "sessie-1" {
		t.Fatalf("subject/sid zijn %q/%q", back.Subject, back.Sid)
	}
}

// TestTokenTypesDoNotCross dekt de smalheid van het streamtoken: het heeft geen
// enkel recht op de rest van de API.
func TestTokenTypesDoNotCross(t *testing.T) {
	signer := mustSigner(t)

	stream, _, err := signer.Mint("owner", "sessie-1", auth.TokenStream, time.Minute, "een-versie")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := signer.Verify(stream, auth.TokenAccess); err == nil {
		t.Fatal("een streamtoken werd als accesstoken geaccepteerd")
	}

	access, _, err := signer.Mint("owner", "sessie-1", auth.TokenAccess, time.Minute, "")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := signer.Verify(access, auth.TokenStream); err == nil {
		t.Fatal("een accesstoken werd als streamtoken geaccepteerd")
	}
}

func TestTamperedTokenIsRefused(t *testing.T) {
	signer := mustSigner(t)

	token, _, err := signer.Mint("owner", "sessie-1", auth.TokenAccess, time.Minute, "")
	if err != nil {
		t.Fatal(err)
	}

	parts := strings.Split(token, ".")
	// De payload wijzigen zonder de handtekening bij te werken.
	tampered := parts[0] + "." + parts[1][:len(parts[1])-2] + "AA." + parts[2]
	if _, err := signer.Verify(tampered, auth.TokenAccess); err == nil {
		t.Fatal("een gewijzigde payload werd geaccepteerd")
	}

	// En met een andere sleutel klopt niets meer.
	other, err := auth.NewSigner([]byte(strings.Repeat("z", 32)))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := other.Verify(token, auth.TokenAccess); err == nil {
		t.Fatal("een token van een andere sleutel werd geaccepteerd")
	}
}

func TestExpiredTokenIsRefused(t *testing.T) {
	signer := mustSigner(t)

	now := time.Date(2026, 8, 18, 12, 0, 0, 0, time.UTC)
	signer.SetClock(func() time.Time { return now })

	token, _, err := signer.Mint("owner", "sessie-1", auth.TokenAccess, time.Minute, "")
	if err != nil {
		t.Fatal(err)
	}

	signer.SetClock(func() time.Time { return now.Add(2 * time.Minute) })
	if _, err := signer.Verify(token, auth.TokenAccess); err != auth.ErrTokenExpired {
		t.Fatalf("een verlopen token gaf %v, verwacht ErrTokenExpired", err)
	}
}

// TestSigningKeyLivesOnDiskOnly dekt eigenschap 4 uit specificatie 6.5.
func TestSigningKeyLivesOnDiskOnly(t *testing.T) {
	dir := t.TempDir()

	key, created, err := auth.LoadOrCreateSigningKey(dir)
	if err != nil {
		t.Fatal(err)
	}
	if !created {
		t.Fatal("de eerste aanroep hoort de sleutel aan te maken")
	}
	if len(key) != auth.KeyLength {
		t.Fatalf("sleutel is %d bytes", len(key))
	}

	path := filepath.Join(dir, auth.KeyFileName)
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if mode := info.Mode().Perm(); mode != 0o600 {
		t.Fatalf("rechten zijn %o, verwacht 600", mode)
	}

	again, created, err := auth.LoadOrCreateSigningKey(dir)
	if err != nil {
		t.Fatal(err)
	}
	if created {
		t.Fatal("de tweede aanroep hoort de bestaande sleutel te lezen")
	}
	if string(again) != string(key) {
		t.Fatal("de sleutel veranderde tussen twee starts; elke uitstaande sessie zou daarmee omvallen")
	}
}

func TestSetupCodeIsReadableAndOpaqueOnDisk(t *testing.T) {
	code, hash, err := auth.NewSetupCode()
	if err != nil {
		t.Fatal(err)
	}

	// Overtypen van een terminal: geen 0/O en geen 1/I/L.
	if len(code) != 11 || strings.Count(code, "-") != 2 {
		t.Fatalf("setupcode heeft vorm %q", code)
	}
	for _, r := range strings.ReplaceAll(code, "-", "") {
		if strings.ContainsRune("01OIL", r) {
			t.Fatalf("setupcode bevat een teken dat op een ander lijkt: %q", code)
		}
	}

	if !auth.EqualHash(hash, auth.HashOpaque(code)) {
		t.Fatal("de hash hoort bij de code")
	}
	if strings.Contains(string(hash), code) {
		t.Fatal("de code is uit de opslagvorm terug te lezen")
	}
}

func TestRefreshTokenIsNotStored(t *testing.T) {
	token, hash, err := auth.NewRefreshToken()
	if err != nil {
		t.Fatal(err)
	}
	if len(token) < 40 {
		t.Fatalf("refreshtoken is %d tekens", len(token))
	}
	// Wat er in de database staat is een identificatie die niet naar het token
	// terug te rekenen is. Een databasedump mag geen bruikbaar token opleveren.
	if strings.Contains(string(hash), token) {
		t.Fatal("het token is uit de opslagvorm terug te lezen")
	}
	if !auth.EqualHash(hash, auth.HashOpaque(token)) {
		t.Fatal("de opslagvorm hoort bij het token")
	}
}

func mustSigner(t *testing.T) *auth.Signer {
	t.Helper()
	signer, err := auth.NewSigner([]byte(strings.Repeat("k", 32)))
	if err != nil {
		t.Fatal(err)
	}
	return signer
}
