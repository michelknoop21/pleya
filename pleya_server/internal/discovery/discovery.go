// Package discovery beantwoordt de oproep waarmee een Pleya-client op het
// thuisnetwerk naar servers zoekt (S26.9). Het is bewust het kleinst mogelijke
// antwoord: wie de server is en op welke poort hij te bereiken is. Geen
// gebruikersgegevens, geen toegang. Wie het antwoord krijgt, moet daarna nog
// gewoon inloggen.
//
// De client bouwt het adres uit het afzenderadres van het antwoord plus Scheme
// en Port: in Docker kent de server zijn eigen LAN-adres niet.
package discovery

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"sync"
	"time"
)

const (
	// Probe is de exacte tekst van de oproep. Al het andere blijft
	// onbeantwoord, zodat de poort niet als echo te gebruiken is.
	Probe = "who is PleyaServer?"

	// DefaultPort is de UDP-poort van de oproep. 48632 tot en met 48634 zijn
	// van Companion Remote en Pleya Share, 7359 is van Jellyfin.
	DefaultPort = 48635

	// MaxReply houdt het antwoord klein: een oproep van 19 bytes mag geen
	// groot pakket naar een vervalst afzenderadres sturen.
	MaxReply = 512

	replyApp     = "pleya-server"
	replyVersion = 1
)

// maxSenders begrenst het register van afzenders.
const maxSenders = 4096

// Reply is het antwoord op de draad.
type Reply struct {
	App     string `json:"app"`
	Version int    `json:"v"`
	ID      string `json:"id"`
	Name    string `json:"name"`
	Port    int    `json:"port"`
	Scheme  string `json:"scheme"`
}

// Options beschrijft wat de luisteraar antwoordt.
type Options struct {
	// Addr is het UDP-adres, bijvoorbeeld ":48635".
	Addr string
	// ServerID is de vaste id van deze server, dezelfde als in GET /info.
	ServerID string
	// Name geeft de actuele servernaam; hij kan tijdens het draaien wijzigen.
	Name func() string
	// Port is de HTTP-poort waarop clients de server bereiken: de poort op de
	// host, niet die in de container.
	Port int
	// Scheme is "http" of "https".
	Scheme string
	Log    *slog.Logger

	// Limiet per afzender: Burst antwoorden per Window. Nul kiest 5 per 10 s.
	Burst  int
	Window time.Duration

	// AnswerAnything bestaat alleen voor de negatieve controle in de test.
	AnswerAnything bool
	now            func() time.Time
}

// Listener is een draaiende luisteraar.
type Listener struct {
	conn net.PacketConn
	opts Options

	mu   sync.Mutex
	seen map[string][]time.Time
	// pruned is wanneer het register voor het laatst is opgeschoond.
	pruned time.Time
}

// Listen opent de UDP-poort. Het antwoorden begint met Serve.
func Listen(opts Options) (*Listener, error) {
	if opts.ServerID == "" {
		return nil, errors.New("discovery: geen server-id")
	}
	if opts.Port < 1 || opts.Port > 65535 {
		return nil, errors.New("discovery: geen geldige poort om te adverteren")
	}
	if opts.Scheme == "" {
		opts.Scheme = "http"
	}
	if opts.Burst == 0 {
		opts.Burst = 5
	}
	if opts.Window == 0 {
		opts.Window = 10 * time.Second
	}
	if opts.now == nil {
		opts.now = time.Now
	}
	conn, err := net.ListenPacket("udp4", opts.Addr)
	if err != nil {
		return nil, err
	}
	return &Listener{conn: conn, opts: opts, seen: map[string][]time.Time{}}, nil
}

// Addr is het adres waarop geluisterd wordt.
func (l *Listener) Addr() net.Addr { return l.conn.LocalAddr() }

// Close stopt de luisteraar; Serve keert dan terug.
func (l *Listener) Close() error { return l.conn.Close() }

// readRetry is de pauze na een leesfout die de socket niet sloot.
const readRetry = 100 * time.Millisecond

// Serve beantwoordt oproepen tot ctx eindigt of Close wordt aangeroepen.
//
// Een andere leesfout stopt de luisteraar niet: op een niet-verbonden
// UDP-socket kan een ICMP-melding of een vol buffer één lezing laten mislukken,
// en daarna zou elke oproep tot een herstart onbeantwoord blijven. De fout
// wordt hoogstens één keer per minuut gelogd.
func (l *Listener) Serve(ctx context.Context) error {
	go func() {
		<-ctx.Done()
		_ = l.conn.Close()
	}()
	buf := make([]byte, 256)
	var warned time.Time
	for {
		n, from, err := l.conn.ReadFrom(buf)
		if err != nil {
			if ctx.Err() != nil || errors.Is(err, net.ErrClosed) {
				return nil
			}
			if l.opts.Log != nil && time.Since(warned) >= time.Minute {
				warned = time.Now()
				l.opts.Log.Warn("ontdekking: lezen mislukt, ga door", "error", err)
			}
			select {
			case <-ctx.Done():
				return nil
			case <-time.After(readRetry):
			}
			continue
		}
		if !l.opts.AnswerAnything && string(buf[:n]) != Probe {
			continue
		}
		if !l.allow(from) {
			continue
		}
		reply, err := l.reply()
		if err != nil {
			if l.opts.Log != nil {
				l.opts.Log.Warn("ontdekkingsantwoord niet gebouwd", "error", err)
			}
			continue
		}
		_, _ = l.conn.WriteTo(reply, from)
	}
}

// reply bouwt het antwoord. De naam wordt ingekort tot het geheel past.
func (l *Listener) reply() ([]byte, error) {
	name := ""
	if l.opts.Name != nil {
		name = l.opts.Name()
	}
	for {
		b, err := json.Marshal(Reply{
			App:     replyApp,
			Version: replyVersion,
			ID:      l.opts.ServerID,
			Name:    name,
			Port:    l.opts.Port,
			Scheme:  l.opts.Scheme,
		})
		if err != nil {
			return nil, err
		}
		if len(b) <= MaxReply {
			return b, nil
		}
		r := []rune(name)
		if len(r) == 0 {
			return nil, errors.New("discovery: antwoord past niet")
		}
		name = string(r[:len(r)/2])
	}
}

// allow telt de antwoorden per afzenderadres (zonder poort).
func (l *Listener) allow(from net.Addr) bool {
	host, _, err := net.SplitHostPort(from.String())
	if err != nil {
		host = from.String()
	}
	now := l.opts.now()
	l.mu.Lock()
	defer l.mu.Unlock()
	// Het register groeit niet mee met vervalste afzenders: vol is vol. Een
	// nieuwe afzender krijgt dan geen antwoord, en opschonen gebeurt hoogstens
	// één keer per venster, zodat een stortvloed niet elk pakket het hele
	// register laat doorlopen.
	if _, known := l.seen[host]; !known && len(l.seen) >= maxSenders {
		if now.Sub(l.pruned) < l.opts.Window {
			return false
		}
		l.pruned = now
		for k, v := range l.seen {
			if len(v) == 0 || now.Sub(v[len(v)-1]) >= l.opts.Window {
				delete(l.seen, k)
			}
		}
		if len(l.seen) >= maxSenders {
			return false
		}
	}
	kept := l.seen[host][:0]
	for _, t := range l.seen[host] {
		if now.Sub(t) < l.opts.Window {
			kept = append(kept, t)
		}
	}
	if len(kept) >= l.opts.Burst {
		l.seen[host] = kept
		return false
	}
	l.seen[host] = append(kept, now)
	return true
}
