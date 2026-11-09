package push

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/pem"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestOpenAPNsRefusesAKeyThatWouldLeakIntoBackups(t *testing.T) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	pemKey := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
	root := t.TempDir()
	configDir := filepath.Join(root, "config")
	write := func(dir string, mode os.FileMode) string {
		t.Helper()
		if err := os.MkdirAll(dir, 0o700); err != nil {
			t.Fatal(err)
		}
		cfg := filepath.Join(dir, "apns.json")
		if err := os.WriteFile(cfg, []byte(`{"team_id":"AAAAAAAAAA","key_id":"BBBBBBBBBB","environment":"sandbox"}`), 0o644); err != nil {
			t.Fatal(err)
		}
		keyPath := filepath.Join(dir, "AuthKey.p8")
		if err := os.WriteFile(keyPath, pemKey, mode); err != nil {
			t.Fatal(err)
		}
		if err := os.Chmod(keyPath, mode); err != nil {
			t.Fatal(err)
		}
		return cfg
	}

	secrets := write(filepath.Join(root, "secrets"), 0o600)
	if a, err := OpenAPNs(secrets, configDir); err != nil || a == nil {
		t.Fatalf("owner-only key outside /config refused: %v", err)
	}
	if _, err := OpenAPNs(write(filepath.Join(root, "secrets"), 0o644), configDir); err == nil || !strings.Contains(err.Error(), "chmod 600") {
		t.Fatalf("world-readable key accepted: %v", err)
	}
	if _, err := OpenAPNs(write(filepath.Join(configDir, "apns"), 0o600), configDir); err == nil || !strings.Contains(err.Error(), "config directory") {
		t.Fatalf("key inside /config accepted: %v", err)
	}
}

func TestProviderTokenRejectionRetriesWithAFreshToken(t *testing.T) {
	var auths []string
	reasons := []string{"ExpiredProviderToken", "InvalidProviderToken", ""}
	apns := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auths = append(auths, r.Header.Get("Authorization"))
		reason := reasons[len(auths)-1]
		if reason == "" {
			w.WriteHeader(http.StatusOK)
			return
		}
		w.WriteHeader(http.StatusForbidden)
		_, _ = io.WriteString(w, `{"reason":"`+reason+`"}`)
	}))
	apns.EnableHTTP2 = true
	apns.StartTLS()
	defer apns.Close()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	a := &APNs{key: key, topic: bundleID, environment: "sandbox", host: apns.URL, client: apns.Client()}
	ctx := context.Background()
	for i, want := range []outcome{retry, retry, accepted} {
		if got, _ := a.send(ctx, "aabb", "en", "n", "c"); got != want {
			t.Fatalf("send %d: outcome %d, want %d", i, got, want)
		}
	}
	if auths[0] == auths[1] || auths[1] == auths[2] {
		t.Fatal("rejected provider token was reused")
	}
}

func TestDeviceTokenNotForTopicDropsTheInstallation(t *testing.T) {
	apns := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = io.WriteString(w, `{"reason":"DeviceTokenNotForTopic"}`)
	}))
	apns.EnableHTTP2 = true
	apns.StartTLS()
	defer apns.Close()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	a := &APNs{key: key, topic: bundleID, environment: "sandbox", host: apns.URL, client: apns.Client()}
	if got, _ := a.send(context.Background(), "aabb", "en", "n", "c"); got != invalidDevice {
		t.Fatalf("outcome %d, want invalidDevice", got)
	}
}
