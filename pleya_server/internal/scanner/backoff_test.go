package scanner

import (
	"testing"
	"time"
)

func TestProbeBackoffDoublesAndCapsAtADay(t *testing.T) {
	cases := map[int]time.Duration{0: 0, 1: time.Hour, 2: 2 * time.Hour, 3: 4 * time.Hour, 5: 16 * time.Hour, 6: 24 * time.Hour, 40: 24 * time.Hour}
	for attempts, want := range cases {
		if got := probeBackoff(attempts); got != want {
			t.Errorf("probeBackoff(%d) = %v, verwacht %v", attempts, got, want)
		}
	}
}
