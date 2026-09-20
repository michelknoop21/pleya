package logging

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"sync"
	"time"
)

// RingCapacity is het aantal regels dat de buffer vasthoudt.
//
// Gelijk aan de bovengrens van `?limit=` op GET /server/log: een grotere buffer
// zou regels bewaren die geen enkel verzoek kan opvragen, een kleinere zou de
// bovengrens tot een belofte maken die de server niet kan waarmaken.
const RingCapacity = 500

// maxRenderedLength kapt één regel af. Een stacktrace of een lange lijst paden
// hoort de buffer niet vol te zetten; 500 regels van 2 KiB is een megabyte, en
// dat is de bovengrens die dit onderdeel mag kosten.
const maxRenderedLength = 2000

// Entry is één regel zoals GET /server/log hem teruggeeft.
type Entry struct {
	At        time.Time
	Level     slog.Level
	Component string
	Message   string
}

// Ring is de logbuffer in het geheugen.
//
// K rij 11 van het securityplan is de reden dat hij bestaat: het beheerscherm
// wil de laatste regels zien, en de enige veilige manier om dat te doen is
// zonder ooit een pad uit een aanvraag te openen. Een endpoint dat een
// logbestand leest is een bestandsbrowser met een filter ervoor; deze buffer
// kan niets anders teruggeven dan wat deze server zelf geschreven heeft.
//
// De inhoud is al geredigeerd. Dat is een bewuste keuze voor de schrijfkant:
// zo bestaat er geen leespad dat de redactie kan overslaan, en staat een token
// dat per ongeluk in een logregel belandt ook niet in het geheugen van dit
// proces te wachten op een lezer.
type Ring struct {
	mu      sync.Mutex
	entries []Entry
	next    int
	filled  bool
}

// NewRing bouwt een buffer. capacity <= 0 neemt RingCapacity.
func NewRing(capacity int) *Ring {
	if capacity <= 0 {
		capacity = RingCapacity
	}
	return &Ring{entries: make([]Entry, capacity)}
}

func (r *Ring) add(e Entry) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.entries[r.next] = e
	r.next = (r.next + 1) % len(r.entries)
	if r.next == 0 {
		r.filled = true
	}
}

// Entries geeft de regels van minLevel en hoger, nieuwste eerst, hoogstens
// limit stuks.
func (r *Ring) Entries(minLevel slog.Level, limit int) []Entry {
	if limit <= 0 {
		return nil
	}

	r.mu.Lock()
	defer r.mu.Unlock()

	size := len(r.entries)
	count := r.next
	if r.filled {
		count = size
	}

	out := make([]Entry, 0, min(limit, count))
	for i := 1; i <= count && len(out) < limit; i++ {
		e := r.entries[((r.next-i)%size+size)%size]
		if e.Level < minLevel {
			continue
		}
		out = append(out, e)
	}
	return out
}

// Handler geeft een slog.Handler die elke regel doorgeeft aan inner en
// daarnaast in de buffer legt. inner mag nil zijn.
func (r *Ring) Handler(inner slog.Handler) slog.Handler {
	return &ringHandler{ring: r, inner: inner}
}

// ringHandler is de handler-kant. Hij houdt zijn eigen attributen bij, want
// slog geeft die bij WithAttrs mee aan een nieuwe handler en niet bij elke
// Record: zonder deze kopie zou "component" uit Component() nergens meer
// terugkomen.
type ringHandler struct {
	ring      *Ring
	inner     slog.Handler
	component string
	attrs     []slog.Attr
	groups    []string
}

func (h *ringHandler) Enabled(ctx context.Context, level slog.Level) bool {
	if h.inner == nil {
		return true
	}
	return h.inner.Enabled(ctx, level)
}

func (h *ringHandler) Handle(ctx context.Context, record slog.Record) error {
	h.ring.add(Entry{
		At:        record.Time,
		Level:     record.Level,
		Component: h.component,
		Message:   Redact(h.render(record)),
	})
	if h.inner == nil {
		return nil
	}
	return h.inner.Handle(ctx, record)
}

// render zet het bericht en zijn attributen in één regel.
//
// De vorm op de lijn heeft vier velden (at, level, component, message), en
// zonder de attributen zou message de helft van elke regel missen: een fout
// staat in slog niet in het bericht maar in het attribuut ernaast, dus
// "interne fout" zonder error= is geen logregel maar een aankondiging.
func (h *ringHandler) render(record slog.Record) string {
	var b strings.Builder
	b.WriteString(record.Message)

	write := func(a slog.Attr) {
		if a.Key == "component" || a.Equal(slog.Attr{}) {
			return
		}
		b.WriteString(" ")
		b.WriteString(strings.Join(append(append([]string{}, h.groups...), a.Key), "."))
		b.WriteString("=")
		b.WriteString(fmt.Sprint(a.Value.Any()))
	}

	for _, a := range h.attrs {
		write(a)
	}
	record.Attrs(func(a slog.Attr) bool {
		write(a)
		return true
	})

	out := b.String()
	if len(out) > maxRenderedLength {
		out = out[:maxRenderedLength] + "…"
	}
	return out
}

func (h *ringHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	next := h.clone()
	for _, a := range attrs {
		if a.Key == "component" {
			next.component = a.Value.String()
			continue
		}
		next.attrs = append(next.attrs, a)
	}
	if h.inner != nil {
		next.inner = h.inner.WithAttrs(attrs)
	}
	return next
}

func (h *ringHandler) WithGroup(name string) slog.Handler {
	next := h.clone()
	if name != "" {
		next.groups = append(next.groups, name)
	}
	if h.inner != nil {
		next.inner = h.inner.WithGroup(name)
	}
	return next
}

func (h *ringHandler) clone() *ringHandler {
	return &ringHandler{
		ring:      h.ring,
		inner:     h.inner,
		component: h.component,
		attrs:     append([]slog.Attr{}, h.attrs...),
		groups:    append([]string{}, h.groups...),
	}
}

// LevelName geeft de naam die op de lijn staat.
func LevelName(level slog.Level) string {
	switch {
	case level < slog.LevelInfo:
		return "debug"
	case level < slog.LevelWarn:
		return "info"
	case level < slog.LevelError:
		return "warn"
	default:
		return "error"
	}
}

// ParseLevelName is de omgekeerde weg, voor ?level= op GET /server/log.
func ParseLevelName(name string) (slog.Level, bool) {
	switch strings.ToLower(strings.TrimSpace(name)) {
	case "debug":
		return slog.LevelDebug, true
	case "info":
		return slog.LevelInfo, true
	case "warn", "warning":
		return slog.LevelWarn, true
	case "error":
		return slog.LevelError, true
	default:
		return 0, false
	}
}
