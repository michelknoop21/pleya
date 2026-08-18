package main

import "testing"

// De healthcheck draait in dezelfde container en hoort nooit over het netwerk
// te gaan, ook niet wanneer de server op alle adressen luistert.
func TestHealthURLStaysLocal(t *testing.T) {
	cases := map[string]string{
		":8080":          "http://127.0.0.1:8080/healthz",
		"0.0.0.0:8080":   "http://127.0.0.1:8080/healthz",
		"[::]:8080":      "http://127.0.0.1:8080/healthz",
		"127.0.0.1:8832": "http://127.0.0.1:8832/healthz",
	}
	for addr, want := range cases {
		t.Run(addr, func(t *testing.T) {
			got, err := healthURL(addr)
			if err != nil {
				t.Fatalf("healthURL(%q) gaf een fout: %v", addr, err)
			}
			if got != want {
				t.Errorf("healthURL(%q) = %q, verwacht %q", addr, got, want)
			}
		})
	}
}

func TestHealthURLRejectsGarbage(t *testing.T) {
	if _, err := healthURL("8080"); err == nil {
		t.Fatal("healthURL accepteerde een adres zonder poort")
	}
}
