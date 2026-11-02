package artwork

import (
	"context"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"strconv"
	"strings"
	"sync"
)

// cacheGate beschermt uitsluitend de laddercache, tot de bestandsdescriptor
// geopend is. Wachtende purges laten bestaande lezers aflopen; nieuwe lezers
// wachten annuleerbaar. De aparte cold-sem begrenst alleen ffmpeg.
type cacheGate struct {
	mu               sync.Mutex
	changed          chan struct{}
	readers, waiting int
	writing          bool
}

func (g *cacheGate) wake() {
	if g.changed != nil {
		close(g.changed)
	}
	g.changed = make(chan struct{})
}
func (g *cacheGate) acquire(ctx context.Context, write bool) error {
	g.mu.Lock()
	if g.changed == nil {
		g.changed = make(chan struct{})
	}
	if write {
		g.waiting++
	}
	for {
		if err := ctx.Err(); err != nil {
			if write {
				g.waiting--
				g.wake()
			}
			g.mu.Unlock()
			return err
		}
		if !g.writing && ((write && g.readers == 0) || (!write && g.waiting == 0)) {
			if write {
				g.waiting--
				g.writing = true
			} else {
				g.readers++
			}
			g.mu.Unlock()
			return nil
		}
		changed := g.changed
		g.mu.Unlock()
		select {
		case <-ctx.Done():
		case <-changed:
		}
		g.mu.Lock()
	}
}
func (g *cacheGate) release(write bool) {
	g.mu.Lock()
	if write {
		g.writing = false
	} else {
		g.readers--
	}
	g.wake()
	g.mu.Unlock()
}

// artifactName accepteert alleen de canonieke UUID_generation_ladder.jpg-vorm.
func artifactName(name string) bool {
	parts := strings.Split(strings.TrimSuffix(name, ".jpg"), "_")
	if !strings.HasSuffix(name, ".jpg") || len(parts) != 3 {
		return false
	}
	uuid, err := id.Parse(parts[0])
	if err != nil || uuid.String() != parts[0] {
		return false
	}
	generation, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil || generation < 1 || strconv.FormatInt(generation, 10) != parts[1] {
		return false
	}
	switch parts[2] {
	case "240", "480", "960", "1920", "3840":
		return true
	}
	return false
}

func (r *Resizer) Stats() (int64, int, error) { return r.StatsContext(context.Background()) }
func (r *Resizer) Purge() error               { return r.PurgeContext(context.Background()) }

// CacheAdminAvailable belooft beheer alleen op de bewezen veilige IO-keten.
func (r *Resizer) CacheAdminAvailable() bool {
	return r.Available() && cacheAdminSupported && r.purgeBoundaryErr == nil
}
