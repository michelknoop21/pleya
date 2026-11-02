package api_test

import (
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// Twee tokens met dezelfde kop, tegelijk via de handler. Vóór de vaste vergrendelvolgorde
// liep dat in een deadlock: een 500 na een seconde wachten, in 191 van de 400 antwoorden.
func TestTwoTokensWithOneHeadNeverAnswer500(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	var clock atomic.Pointer[time.Time]
	start := time.Now().Truncate(time.Microsecond)
	clock.Store(&start)
	read := func() time.Time { return *clock.Load() }
	e.server.SetClock(read)
	e.signer.SetClock(read)
	wait := func(d time.Duration) {
		next := clock.Load().Add(d)
		clock.Store(&next)
	}

	offer := func(token string) string {
		t.Helper()
		rec := e.refreshWith(token)
		if rec.Code != http.StatusOK {
			t.Fatalf("aanbieding gaf %d: %s", rec.Code, rec.Body.String())
		}
		return decodePair(t, rec).RefreshToken
	}

	for run := range 25 {
		stolen := e.login("slachtoffer").RefreshToken
		victim := offer(stolen)
		wait(time.Second)
		reserve := offer(stolen)
		wait(time.Second)
		offer(stolen)
		wait(5 * time.Minute)

		recs := make([]*httptest.ResponseRecorder, 2)
		var wg sync.WaitGroup
		for i, token := range []string{victim, reserve} {
			wg.Add(1)
			go func() {
				defer wg.Done()
				recs[i] = e.refreshWith(token)
			}()
		}
		wg.Wait()
		for _, rec := range recs {
			if rec.Code != http.StatusOK && rec.Code != http.StatusUnauthorized {
				t.Fatalf("run %d gaf %d: %s", run, rec.Code, rec.Body.String())
			}
		}
	}
}
