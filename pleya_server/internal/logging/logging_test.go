package logging

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"strings"
	"testing"
)

// De belangrijkste test van dit pakket: er mag onder geen enkele voorwaarde een
// wachtwoord uit een verbindingsreeks in een logregel komen.
func TestRedactDSNRemovesCredentials(t *testing.T) {
	cases := []struct {
		name string
		dsn  string
		want string
	}{
		{"met gebruiker en wachtwoord", "postgres://pleya:zeergeheim@postgres:5432/pleya", "postgres://postgres:5432/pleya"},
		{"met querystring", "postgres://pleya:zeergeheim@postgres:5432/pleya?sslmode=disable", "postgres://postgres:5432/pleya"},
		{"zonder wachtwoord", "postgres://pleya@db:5432/pleya", "postgres://db:5432/pleya"},
		{"zonder database", "postgres://pleya:zeergeheim@db:5432", "postgres://db:5432"},
		{"postgresql-schema", "postgresql://u:p@host:5432/naam", "postgresql://host:5432/naam"},
		{"leeg", "", "(leeg)"},
		{"onleesbaar", "dit is geen verbindingsreeks", "(onleesbaar)"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := RedactDSN(c.dsn)
			if got != c.want {
				t.Errorf("RedactDSN(%q) = %q, verwacht %q", c.dsn, got, c.want)
			}
			for _, secret := range []string{"zeergeheim", ":p@"} {
				if strings.Contains(got, secret) {
					t.Fatalf("RedactDSN lekte %q in %q", secret, got)
				}
			}
		})
	}
}

// Een sleutelvorm die pgx accepteert maar die geen URL is, mag niet gedeeltelijk
// worden teruggegeven.
func TestRedactDSNKeyValueFormLeaksNothing(t *testing.T) {
	got := RedactDSN("host=postgres user=pleya password=zeergeheim dbname=pleya")
	if strings.Contains(got, "zeergeheim") {
		t.Fatalf("RedactDSN lekte het wachtwoord: %q", got)
	}
}

func TestNewWritesJSONWithLevel(t *testing.T) {
	var buf bytes.Buffer
	log := New(slog.LevelInfo, &buf)
	log.Debug("dit hoort te verdwijnen")
	if buf.Len() != 0 {
		t.Fatalf("debug kwam door bij niveau info: %s", buf.String())
	}

	Component(log, "startup").Info("gestart", slog.String("listen", ":8080"))

	var entry map[string]any
	if err := json.Unmarshal(buf.Bytes(), &entry); err != nil {
		t.Fatalf("logregel is geen JSON: %v (%s)", err, buf.String())
	}
	for _, key := range []string{"time", "level", "msg", "component"} {
		if _, ok := entry[key]; !ok {
			t.Errorf("veld %q ontbreekt in %v", key, entry)
		}
	}
	if entry["component"] != "startup" {
		t.Errorf("component = %v, verwacht startup", entry["component"])
	}
}
