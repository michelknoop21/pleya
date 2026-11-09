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
}

// OpenAPNs reads the configuration and key from an operator-owned read-only mount.
func OpenAPNs(path string) (*APNs, error) {
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
	data, err = os.ReadFile(filepath.Join(filepath.Dir(path), "AuthKey.p8"))
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

func (a *APNs) send(ctx context.Context, device, locale, notificationID, collapseID string) (outcome, int) {
	token, err := a.providerToken(time.Now())
	if err != nil {
		return retry, 0
	}
	body := "There’s something new in your library."
	if locale == "nl" {
		body = "Er staat iets nieuws in je bibliotheek."
	}
	payload := fmt.Sprintf(`{"aps":{"alert":{"title":"Pleya","body":%q}},"notification_id":%q}`, body, notificationID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, a.host+"/3/device/"+device, strings.NewReader(payload))
	if err != nil {
		return rejected, 0
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
		return retry, 0
	}
	defer resp.Body.Close()
	var failure struct{ Reason string }
	_ = json.NewDecoder(io.LimitReader(resp.Body, 4096)).Decode(&failure)
	switch {
	case resp.StatusCode == http.StatusOK:
		return accepted, resp.StatusCode
	case failure.Reason == "BadDeviceToken", failure.Reason == "Unregistered":
		return invalidDevice, resp.StatusCode
	case resp.StatusCode >= 500, resp.StatusCode == http.StatusTooManyRequests:
		return retry, resp.StatusCode
	default:
		return rejected, resp.StatusCode
	}
}
