package api

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestActivityInitials(t *testing.T) {
	for username, want := range map[string]string{
		"sanne":        "S",
		"anna.de.boer": "AB",
		"jan-piet":     "JP",
		"Émile Zola":   "ÉZ",
		"ömer":         "Ö",
		"7of9":         "7",
		"...":          "?",
		"":             "?",
	} {
		if got := activityInitials(username); got != want {
			t.Errorf("activityInitials(%q) = %q, verwacht %q", username, got, want)
		}
	}
}

// activityRoutes staat twee keer vast: in de routetabel en in het contract.
// scripts/check_protocol.sh kijkt alleen naar het contract, en een route die er
// maar aan één kant staat is daar niet zichtbaar.
var activityRoutes = []struct{ method, pattern, contractPath string }{
	{"GET", "/pleya/v1/items/{item_id}/activity", "/items/{item_id}/activity"},
	{"GET", "/pleya/v1/users/me/activity-sharing", "/users/me/activity-sharing"},
	{"PUT", "/pleya/v1/users/me/activity-sharing", "/users/me/activity-sharing"},
}

func TestActivityRoutesAreRegisteredAndInTheContract(t *testing.T) {
	registered := map[string]bool{}
	for _, rt := range bareRouter(t).routeTable() {
		registered[rt.pattern] = true
	}
	contract := readContract(t)
	for _, rt := range activityRoutes {
		if !registered[rt.method+" "+rt.pattern] {
			t.Errorf("%s %s staat niet in de routetabel", rt.method, rt.pattern)
		}
		if !contractHas(contract, rt.contractPath, rt.method) {
			t.Errorf("%s %s staat niet in openapi.yaml", rt.method, rt.contractPath)
		}
	}
}

func readContract(t *testing.T) []string {
	t.Helper()
	candidates := []string{filepath.Join("..", "..", "..", "docs", "pleya-protocol", "v1", "openapi.yaml")}
	if root := strings.TrimSpace(os.Getenv("PLEYA_REPO_ROOT")); root != "" {
		candidates = append([]string{filepath.Join(root, "docs", "pleya-protocol", "v1", "openapi.yaml")}, candidates...)
	}
	for _, path := range candidates {
		if raw, err := os.ReadFile(path); err == nil {
			return strings.Split(string(raw), "\n")
		}
	}
	// Geen t.Skip: een overgeslagen dekkingstest oogt groen en meet niets.
	t.Fatalf("openapi.yaml is niet te vinden; gezocht op %v", candidates)
	return nil
}

// contractHas zoekt het pad op twee spaties inspringing en de methode op vier,
// voordat het volgende pad begint. Dat is de vaste opmaak van openapi.yaml en
// spaart een yaml-afhankelijkheid uit voor deze ene test.
func contractHas(lines []string, path, method string) bool {
	head := fmt.Sprintf("  %s:", path)
	operation := fmt.Sprintf("    %s:", strings.ToLower(method))
	for i, line := range lines {
		if line != head {
			continue
		}
		for _, next := range lines[i+1:] {
			if next == operation {
				return true
			}
			if strings.HasPrefix(next, "  /") || (next != "" && !strings.HasPrefix(next, " ")) {
				return false
			}
		}
	}
	return false
}
