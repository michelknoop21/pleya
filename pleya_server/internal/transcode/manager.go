package transcode

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Fouten die een aanroeper op code afhandelt.
var (
	// ErrBusy: het maximum aantal gelijktijdige sessies is bereikt.
	ErrBusy = errors.New("transcode: alle sessies zijn bezet")
	// ErrFailed: ffmpeg haalde geen speelbare uitvoer. De tekst draagt het eind
	// van zijn foutuitvoer voor het log, niet voor de client.
	ErrFailed = errors.New("transcode: ffmpeg leverde geen uitvoer")
	// ErrNotFound: de sessie bestaat niet (meer).
	ErrNotFound = errors.New("transcode: sessie niet gevonden")
)

// State is waar een sessie staat.
type State string

const (
	StateRunning  State = "running"
	StateFinished State = "finished"
	StateFailed   State = "failed"
	StateStopped  State = "stopped"
)

// Session is één lopende of afgelopen omzetting.
type Session struct {
	ID        id.ID
	UserID    id.ID
	VersionID id.ID
	Mode      Mode
	HW        HWAccel
	Dir       string
	StartedAt time.Time
	LastBeat  time.Time
	State     State
}

// Params is wat Start nodig heeft. De uitvoermap kiest de manager zelf.
type Params struct {
	UserID    id.ID
	VersionID id.ID
	Job       Job
}

// Recorder bewaart het verloop van sessies, voor beheer en na een herstart.
type Recorder interface {
	Started(ctx context.Context, s Session) error
	Ended(ctx context.Context, id id.ID, state State, errText string) error
	// ResetRunning zet sessies die een herstart overleefden op stopped.
	ResetRunning(ctx context.Context) error
}

// Options zijn de instellingen van een Manager.
type Options struct {
	FFmpegPath string
	// Dir is de transcodemap; elke sessie krijgt een eigen submap.
	Dir string
	// Max is het aantal gelijktijdige sessies; 0 betekent geen enkele.
	Max int
	// IdleTimeout is hoe lang een sessie zonder hartslag of aanvraag leeft.
	IdleTimeout time.Duration
	// StartTimeout is hoe lang Start op het eerste segment wacht.
	StartTimeout time.Duration
	HW           HWAccel
	RenderNode   string
	// HWReason zegt waarom er geen hardwareversnelling is, voor beheer.
	HWReason string
	Recorder Recorder
	Log      *slog.Logger
}

// Manager houdt de sessies bij en bewaakt de ffmpeg-processen.
type Manager struct {
	o Options

	mu       sync.Mutex
	sessions map[id.ID]*running
	closed   bool
	stop     chan struct{}
	wg       sync.WaitGroup
}

type running struct {
	s      Session
	cancel context.CancelFunc
	done   chan struct{}
	reason State // gezet door Stop, voor wat de wachter erna meldt
}

// New maakt een Manager en ruimt wat een vorige run achterliet op.
func New(o Options) (*Manager, error) {
	if o.Log == nil {
		o.Log = slog.Default()
	}
	if o.IdleTimeout <= 0 {
		o.IdleTimeout = 60 * time.Second
	}
	if o.StartTimeout <= 0 {
		o.StartTimeout = 30 * time.Second
	}
	if o.FFmpegPath == "" {
		o.FFmpegPath = "ffmpeg"
	}
	if err := os.MkdirAll(o.Dir, 0o750); err != nil {
		return nil, fmt.Errorf("transcodemap: %w", err)
	}
	// Een herstart laat geen proces achter dat we nog kunnen bereiken, dus wat
	// er in de map staat is afval.
	entries, _ := os.ReadDir(o.Dir)
	for _, e := range entries {
		_ = os.RemoveAll(filepath.Join(o.Dir, e.Name()))
	}
	if o.Recorder != nil {
		if err := o.Recorder.ResetRunning(context.Background()); err != nil {
			return nil, fmt.Errorf("sessies terugzetten: %w", err)
		}
	}
	m := &Manager{o: o, sessions: map[id.ID]*running{}, stop: make(chan struct{})}
	m.wg.Add(1)
	go m.janitor()
	return m, nil
}

// Enabled zegt of deze manager sessies mag starten.
func (m *Manager) Enabled() bool { return m != nil && m.o.Max > 0 }

// Max is het aantal gelijktijdige sessies dat deze manager toelaat.
func (m *Manager) Max() int { return m.o.Max }

// HWReason is waarom er geen hardwareversnelling is; leeg als die er wel is.
func (m *Manager) HWReason() string { return m.o.HWReason }

// HW is de hardwareversnelling die deze manager gebruikt.
func (m *Manager) HW() HWAccel { return m.o.HW }

// Start zet een sessie op en wacht tot het eerste segment er ligt. Faalt een
// omzetting met hardwareversnelling, dan probeert hij het één keer in software:
// een bron die de GPU niet aankan hoort geen gebroken afspeelpoging op te leveren.
func (m *Manager) Start(ctx context.Context, p Params) (Session, error) {
	sess, err := m.startWith(ctx, p, m.o.HW)
	if err != nil && errors.Is(err, ErrFailed) && m.o.HW != HWNone && p.Job.Mode == ModeTranscode {
		m.o.Log.Warn("omzetten met hardware mislukte, nieuwe poging in software", slog.String("error", err.Error()))
		return m.startWith(ctx, p, HWNone)
	}
	return sess, err
}

func (m *Manager) startWith(ctx context.Context, p Params, hw HWAccel) (Session, error) {
	m.mu.Lock()
	if m.closed {
		m.mu.Unlock()
		return Session{}, ErrBusy
	}
	if m.o.Max <= 0 || len(m.sessions) >= m.o.Max {
		m.mu.Unlock()
		return Session{}, ErrBusy
	}
	sid := id.New()
	dir := filepath.Join(m.o.Dir, sid.String())
	job := p.Job
	job.OutDir = dir
	job.HW, job.RenderNode = hw, m.o.RenderNode
	args, err := BuildArgs(job)
	if err != nil {
		m.mu.Unlock()
		return Session{}, err
	}
	if err := os.MkdirAll(dir, 0o750); err != nil {
		m.mu.Unlock()
		return Session{}, fmt.Errorf("sessiemap: %w", err)
	}

	runCtx, cancel := context.WithCancel(context.Background())
	cmd := exec.CommandContext(runCtx, m.o.FFmpegPath, args...)
	cmd.Cancel = func() error { return cmd.Process.Signal(syscall.SIGTERM) }
	cmd.WaitDelay = 5 * time.Second
	var stderr tailBuffer
	cmd.Stderr = &stderr

	now := time.Now()
	used := HWNone
	if job.Mode == ModeTranscode && !job.HDR {
		used = hw
	}
	r := &running{
		s: Session{ID: sid, UserID: p.UserID, VersionID: p.VersionID, Mode: job.Mode, HW: used,
			Dir: dir, StartedAt: now, LastBeat: now, State: StateRunning},
		cancel: cancel, done: make(chan struct{}),
	}
	if err := cmd.Start(); err != nil {
		m.mu.Unlock()
		cancel()
		_ = os.RemoveAll(dir)
		return Session{}, fmt.Errorf("%w: %v", ErrFailed, err)
	}
	m.sessions[sid] = r
	m.mu.Unlock()

	if m.o.Recorder != nil {
		if err := m.o.Recorder.Started(ctx, r.s); err != nil {
			m.o.Log.Warn("transcodesessie niet vastgelegd", slog.String("error", err.Error()))
		}
	}
	m.wg.Add(1)
	go m.wait(r, cmd, &stderr)

	if err := m.waitReady(ctx, r, &stderr); err != nil {
		_ = m.Stop(sid)
		return Session{}, err
	}
	return m.snapshot(r), nil
}

func (m *Manager) wait(r *running, cmd *exec.Cmd, stderr *tailBuffer) {
	defer m.wg.Done()
	err := cmd.Wait()
	m.mu.Lock()
	state := StateFinished
	text := ""
	switch {
	case r.reason != "":
		state = r.reason
	case err != nil:
		state = StateFailed
		text = strings.TrimSpace(stderr.String())
		if text == "" {
			text = err.Error()
		}
	}
	r.s.State = state
	m.mu.Unlock()
	close(r.done)
	if m.o.Recorder != nil {
		if rerr := m.o.Recorder.Ended(context.Background(), r.s.ID, state, text); rerr != nil {
			m.o.Log.Warn("einde transcodesessie niet vastgelegd", slog.String("error", rerr.Error()))
		}
	}
	if state == StateFailed {
		m.o.Log.Warn("ffmpeg faalde", slog.String("session", r.s.ID.String()), slog.String("stderr", text))
	}
}

// waitReady wacht op een afspeelbare uitvoer: de afspeellijst met een init- en
// minstens één segmentbestand.
func (m *Manager) waitReady(ctx context.Context, r *running, stderr *tailBuffer) error {
	deadline := time.NewTimer(m.o.StartTimeout)
	defer deadline.Stop()
	tick := time.NewTicker(100 * time.Millisecond)
	defer tick.Stop()
	for {
		if ready(r.s.Dir) {
			return nil
		}
		select {
		case <-r.done:
			if ready(r.s.Dir) {
				return nil
			}
			return fmt.Errorf("%w: %s", ErrFailed, strings.TrimSpace(stderr.String()))
		case <-deadline.C:
			return fmt.Errorf("%w: geen segment binnen %s", ErrFailed, m.o.StartTimeout)
		case <-ctx.Done():
			return ctx.Err()
		case <-tick.C:
		}
	}
}

func ready(dir string) bool {
	pl, err := os.ReadFile(filepath.Join(dir, PlaylistName))
	if err != nil || !bytes.Contains(pl, []byte("#EXTINF")) {
		return false
	}
	_, err = os.Stat(filepath.Join(dir, InitName))
	return err == nil
}

func (m *Manager) snapshot(r *running) Session {
	m.mu.Lock()
	defer m.mu.Unlock()
	return r.s
}

// Get geeft een sessie.
func (m *Manager) Get(sid id.ID) (Session, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	r, ok := m.sessions[sid]
	if !ok {
		return Session{}, false
	}
	return r.s, true
}

// Touch telt als hartslag.
func (m *Manager) Touch(sid id.ID) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	r, ok := m.sessions[sid]
	if !ok || r.s.State != StateRunning && r.s.State != StateFinished {
		return false
	}
	r.s.LastBeat = time.Now()
	return true
}

// Stop beëindigt een sessie en ruimt zijn map op. Een onbekende sessie is
// ErrNotFound; stoppen is dus niet idempotent op id, wel op effect.
func (m *Manager) Stop(sid id.ID) error { return m.end(sid, StateStopped) }

func (m *Manager) end(sid id.ID, reason State) error {
	m.mu.Lock()
	r, ok := m.sessions[sid]
	if !ok {
		m.mu.Unlock()
		return ErrNotFound
	}
	delete(m.sessions, sid)
	if r.reason == "" {
		r.reason = reason
	}
	m.mu.Unlock()
	r.cancel()
	<-r.done
	return os.RemoveAll(r.s.Dir)
}

// List geeft de sessies, oudste eerst.
func (m *Manager) List() []Session {
	m.mu.Lock()
	out := make([]Session, 0, len(m.sessions))
	for _, r := range m.sessions {
		out = append(out, r.s)
	}
	m.mu.Unlock()
	slices.SortFunc(out, func(a, b Session) int { return a.StartedAt.Compare(b.StartedAt) })
	return out
}

func (m *Manager) janitor() {
	defer m.wg.Done()
	t := time.NewTicker(time.Second)
	defer t.Stop()
	for {
		select {
		case <-m.stop:
			return
		case now := <-t.C:
			for _, s := range m.List() {
				if now.Sub(s.LastBeat) > m.o.IdleTimeout {
					m.o.Log.Info("transcodesessie verlopen", slog.String("session", s.ID.String()))
					_ = m.end(s.ID, StateStopped)
				}
			}
		}
	}
}

// Close stopt alle sessies. Daarna weigert Start.
func (m *Manager) Close() {
	m.mu.Lock()
	if m.closed {
		m.mu.Unlock()
		return
	}
	m.closed = true
	m.mu.Unlock()
	close(m.stop)
	for _, s := range m.List() {
		_ = m.end(s.ID, StateStopped)
	}
	m.wg.Wait()
}

// tailBuffer houdt de laatste 4 KiB vast: ffmpeg meldt de oorzaak aan het eind.
type tailBuffer struct {
	mu  sync.Mutex
	buf []byte
}

func (b *tailBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.buf = append(b.buf, p...)
	if len(b.buf) > 4096 {
		b.buf = b.buf[len(b.buf)-4096:]
	}
	return len(p), nil
}

func (b *tailBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return string(b.buf)
}
