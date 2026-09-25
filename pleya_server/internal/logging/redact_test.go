package logging

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// De gedeelde vectoren uit pleya_verify/redact/cases.json.
//
// Dezelfde vectoren draaien aan de appkant (test/utils/log_redaction_manager_parity_test.dart)
// en in de Verify-runner (pleya_verify/runner/test/redact_test.go-equivalent). Een
// eigen kopie hier zou de vraag die deze test stelt onbeantwoordbaar maken: niet
// "redigeert deze functie iets", maar "redigeert hij hetzelfde als de andere twee".
type redactCase struct {
	Description string `json:"description"`
	Input       string `json:"input"`
	Expected    string `json:"expected"`
}

func casesPath(t *testing.T) string {
	t.Helper()
	// In de container koppelt scripts/go-tool.sh de wortel op /repo; daarbuiten
	// ligt hij twee mappen omhoog vanaf internal/logging plus één voor
	// pleya_server zelf.
	candidates := []string{}
	if root := strings.TrimSpace(os.Getenv("PLEYA_REPO_ROOT")); root != "" {
		candidates = append(candidates, filepath.Join(root, "pleya_verify", "redact", "cases.json"))
	}
	candidates = append(candidates, filepath.Join("..", "..", "..", "pleya_verify", "redact", "cases.json"))

	for _, path := range candidates {
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}
	// Geen t.Skip. Een overgeslagen pariteitstest is precies de vorm die de rest
	// van dit project bestrijdt: hij oogt groen en meet niets.
	t.Fatalf("de gedeelde redactievectoren zijn niet te vinden; gezocht op %v", candidates)
	return ""
}

func loadCases(t *testing.T) []redactCase {
	t.Helper()
	raw, err := os.ReadFile(casesPath(t))
	if err != nil {
		t.Fatalf("vectoren lezen: %v", err)
	}
	var file struct {
		Cases []redactCase `json:"cases"`
	}
	if err := json.Unmarshal(raw, &file); err != nil {
		t.Fatalf("vectoren ontleden: %v", err)
	}
	if len(file.Cases) == 0 {
		t.Fatal("het vectorbestand is leeg")
	}
	return file.Cases
}

func TestRedactMatchesSharedVectors(t *testing.T) {
	for _, c := range loadCases(t) {
		t.Run(c.Description, func(t *testing.T) {
			if got := Redact(c.Input); got != c.Expected {
				t.Errorf("Redact(%q)\n  gaf      %q\n  verwacht %q", c.Input, got, c.Expected)
			}
		})
	}
}

// Negatieve controle op de vectorronde hierboven. Zonder deze test bewijst een
// groene ronde niet dat de vergelijking iets doet: een Redact die zijn invoer
// ongewijzigd teruggeeft zou op de eerste, de vijftiende en de zeventiende
// vector nog steeds slagen, en die drie zijn de enige waar invoer en uitkomst
// gelijk zijn. Deze test eist dat de rest wél verandert.
func TestSharedVectorsWouldCatchAnIdentityRedact(t *testing.T) {
	changed := 0
	for _, c := range loadCases(t) {
		if c.Input != c.Expected {
			changed++
		}
	}
	if changed < 10 {
		t.Fatalf("slechts %d van de vectoren verandert iets; de ronde toetst dan te weinig", changed)
	}
}

// Redigeren is stabiel: een tweede ronde over dezelfde tekst verandert niets
// meer. De ringbuffer redigeert op de schrijfkant en een handler kan geketend
// zijn, dus een patroon dat zijn eigen uitkomst opnieuw pakt zou een regel bij
// elke doorgang verder verminken.
func TestRedactIsIdempotent(t *testing.T) {
	for _, c := range loadCases(t) {
		once := Redact(c.Input)
		if twice := Redact(once); twice != once {
			t.Errorf("tweede ronde over %q\n  gaf      %q\n  verwacht %q", c.Input, twice, once)
		}
	}
}

// De DSN is de vector die niet in het gedeelde bestand staat, want de app kent
// hem niet. K rij 11 en rij 15 vragen hem hier wel: een logregel met een
// verbindingsstring mag geen wachtwoord dragen.
func TestRedactRemovesDatabaseCredentials(t *testing.T) {
	line := "database=" + RedactDSN("postgres://pleya:geheim@db:5432/pleya?sslmode=disable")
	if strings.Contains(line, "geheim") {
		t.Fatalf("het wachtwoord staat er nog in: %s", line)
	}
	if !strings.Contains(line, "db:5432/pleya") {
		t.Fatalf("host en databasenaam horen leesbaar te blijven: %s", line)
	}
}

func TestMaskEnvironment(t *testing.T) {
	for _, tc := range []struct {
		key, value   string
		want         string
		wantRedacted bool
	}{
		{"DATABASE_URL", "postgres://pleya:geheim@db:5432/pleya", "postgres://db:5432/pleya", true},
		{"PLEYA_SERVER_HTTP_ADDR", ":8080", ":8080", false},
		{"PLEYA_SERVER_ACCESS_TOKEN_TTL", "15m", "[REDACTED]", true},
		{"PLEYA_SERVER_TRANSCODE_DIR", "/transcode", "/transcode", false},
		{"PLEYA_SERVER_PUBLIC_URL", "https://web.pleya.app", "https://web.pleya.app", false},
		{"PLEYA_SERVER_PUBLIC_URL", "https://web.pleya.app/?api_key=abc", "https://web.pleya.app/?api_key=[REDACTED]", true},
	} {
		got, redacted := MaskEnvironment(tc.key, tc.value)
		if got != tc.want || redacted != tc.wantRedacted {
			t.Errorf("MaskEnvironment(%q, %q) = %q, %v; verwacht %q, %v",
				tc.key, tc.value, got, redacted, tc.want, tc.wantRedacted)
		}
	}
}
