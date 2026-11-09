package push

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const bundleID = "nl.michelknoop.pleya"

var appleID = regexp.MustCompile("^[A-Z0-9]{10}$")

type APNs struct {
	key                  *ecdsa.PrivateKey
	teamID, keyID, topic string
	environment, host    string
	client               *http.Client
	token                string
	signedAt             time.Time
	// resignedAt keeps re-signing after a rejected provider token at least
	// 20 minutes apart: Apple answers more frequent new tokens with
	// TooManyProviderTokenUpdates, and a key that stays invalid would otherwise
	// sign a new JWT every queue tick.
	resignedAt time.Time
	// now is the clock; nil means time.Now.
	now func() time.Time
}

// OpenAPNs reads the configuration and key from an operator-owned read-only mount.
// configDir is the server's /config: everything in it goes into each backup,
// and the backup only keeps .key and owner-only files secret.
func OpenAPNs(path, configDir string) (*APNs, error) {
	if path == "" {
		return nil, nil
	}
	var cfg struct {
		TeamID      string `json:"team_id"`
		KeyID       string `json:"key_id"`
		Environment string `json:"environment"`
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, errors.New("cannot read APNs configuration")
	}
	if json.Unmarshal(data, &cfg) != nil || !appleID.MatchString(cfg.TeamID) || !appleID.MatchString(cfg.KeyID) {
		return nil, errors.New("invalid APNs team or key identifier")
	}
	host := "https://api.push.apple.com"
	switch cfg.Environment {
	case "sandbox":
		host = "https://api.sandbox.push.apple.com"
	case "production":
	default:
		return nil, errors.New("invalid APNs environment")
	}
	keyPath := filepath.Join(filepath.Dir(path), "AuthKey.p8")
	if err := checkKeyFile(keyPath, configDir); err != nil {
		return nil, err
	}
	data, err = os.ReadFile(keyPath)
	if err != nil {
		return nil, errors.New("cannot read APNs key")
	}
	block, _ := pem.Decode(data)
	if block == nil || block.Type != "PRIVATE KEY" {
		return nil, errors.New("invalid APNs key")
	}
	privateKey, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	key, ok := privateKey.(*ecdsa.PrivateKey)
	if err != nil || !ok || key.Curve != elliptic.P256() {
		return nil, errors.New("APNs requires a P-256 private key")
	}
	return &APNs{key: key, teamID: cfg.TeamID, keyID: cfg.KeyID, topic: bundleID,
		environment: cfg.Environment, host: host, client: &http.Client{
			Timeout:       8 * time.Second,
			CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
		}}, nil
}

func checkKeyFile(keyPath, configDir string) error {
	info, err := os.Stat(keyPath)
	if err != nil {
		return errors.New("cannot read APNs key")
	}
	if info.Mode().Perm()&0o077 != 0 {
		return fmt.Errorf("APNs key %s is readable by group or others; restrict it to the server user (chmod 600)", keyPath)
	}
	if configDir != "" {
		if rel, err := filepath.Rel(resolvePath(configDir), resolvePath(keyPath)); err == nil && filepath.IsLocal(rel) {
			return fmt.Errorf("APNs key %s is inside the config directory %s and would end up in backups; mount it elsewhere", keyPath, configDir)
		}
	}
	return nil
}

func resolvePath(path string) string {
	if resolved, err := filepath.EvalSymlinks(path); err == nil {
		return resolved
	}
	abs, _ := filepath.Abs(path)
	return abs
}

func (a *APNs) providerToken(now time.Time) (string, error) {
	if a.token != "" && now.Sub(a.signedAt) < 45*time.Minute && !now.Before(a.signedAt) {
		return a.token, nil
	}
	encode := base64.RawURLEncoding.EncodeToString
	header := fmt.Sprintf(`{"alg":"ES256","kid":%q}`, a.keyID)
	claims := fmt.Sprintf(`{"iss":%q,"iat":%d}`, a.teamID, now.Unix())
	unsigned := encode([]byte(header)) + "." + encode([]byte(claims))
	digest := sha256.Sum256([]byte(unsigned))
	r, s, err := ecdsa.Sign(rand.Reader, a.key, digest[:])
	if err != nil {
		return "", err
	}
	var signature [64]byte
	r.FillBytes(signature[:32])
	s.FillBytes(signature[32:])
	a.token = unsigned + "." + encode(signature[:])
	a.signedAt = now
	return a.token, nil
}

type outcome int

const (
	accepted outcome = iota
	retry
	invalidDevice
	rejected
)

// send returns the outcome plus the HTTP status and Apple's reason for the log.
func (a *APNs) send(ctx context.Context, device, locale, notificationID, collapseID string) (outcome, int, string) {
	now := time.Now()
	if a.now != nil {
		now = a.now()
	}
	token, err := a.providerToken(now)
	if err != nil {
		return retry, 0, ""
	}
	body := "There’s something new in your library."
	if locale == "nl" {
		body = "Er staat iets nieuws in je bibliotheek."
	}
	payload := fmt.Sprintf(`{"aps":{"alert":{"title":"Pleya","body":%q}},"notification_id":%q}`, body, notificationID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, a.host+"/3/device/"+device, strings.NewReader(payload))
	if err != nil {
		return rejected, 0, ""
	}
	req.Header.Set("Authorization", "bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("apns-topic", a.topic)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "5")
	req.Header.Set("apns-id", notificationID)
	req.Header.Set("apns-collapse-id", collapseID)
	// Apple must not retain an undelivered alert past a later opt-out.
	req.Header.Set("apns-expiration", "0")
	resp, err := a.client.Do(req)
	if err != nil {
		return retry, 0, ""
	}
	defer resp.Body.Close()
	var failure struct{ Reason string }
	_ = json.NewDecoder(io.LimitReader(resp.Body, 4096)).Decode(&failure)
	switch {
	case resp.StatusCode == http.StatusOK:
		return accepted, resp.StatusCode, failure.Reason
	case failure.Reason == "BadDeviceToken", failure.Reason == "Unregistered", failure.Reason == "DeviceTokenNotForTopic":
		return invalidDevice, resp.StatusCode, failure.Reason
	case failure.Reason == "ExpiredProviderToken", failure.Reason == "InvalidProviderToken":
		// The provider token is at fault, not this delivery: sign a new one and retry.
		if now.Sub(a.resignedAt) >= 20*time.Minute {
			a.token = ""
			a.resignedAt = now
		}
		return retry, resp.StatusCode, failure.Reason
	case resp.StatusCode >= 500, resp.StatusCode == http.StatusTooManyRequests:
		return retry, resp.StatusCode, failure.Reason
	default:
		return rejected, resp.StatusCode, failure.Reason
	}
}
