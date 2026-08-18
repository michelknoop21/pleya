package scanner

import (
	"context"
	"sync"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// progress schrijft de tussenstand periodiek naar de database.
//
// Het risico dat de fase zelf benoemt: een trage NAS laat de scanner hangen
// lijken. Zonder websocket is een teller die oploopt het verschil tussen wachten
// en ingrijpen, dus de stand hoort in de database te staan terwijl de ronde
// loopt en niet pas erna.
type progress struct {
	store *catalog.Store
	runID id.ID
	stats *Stats

	mu      sync.Mutex
	current string

	stopOnce sync.Once
	done     chan struct{}
	finished chan struct{}
}

func newProgress(ctx context.Context, store *catalog.Store, runID id.ID, stats *Stats, every time.Duration) *progress {
	p := &progress{
		store:    store,
		runID:    runID,
		stats:    stats,
		done:     make(chan struct{}),
		finished: make(chan struct{}),
	}

	go func() {
		defer close(p.finished)
		ticker := time.NewTicker(every)
		defer ticker.Stop()
		for {
			select {
			case <-p.done:
				return
			case <-ctx.Done():
				return
			case <-ticker.C:
				p.flush(ctx)
			}
		}
	}()
	return p
}

func (p *progress) note(path string) {
	p.mu.Lock()
	p.current = path
	p.mu.Unlock()
}

func (p *progress) flush(ctx context.Context) {
	p.mu.Lock()
	current := p.current
	p.mu.Unlock()

	counters := p.stats.toCatalog()
	counters.CurrentPath = current
	_ = p.store.UpdateScanProgress(ctx, p.runID, counters)
}

func (p *progress) stop() {
	p.stopOnce.Do(func() {
		close(p.done)
		<-p.finished
	})
}
