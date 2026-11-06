package metadata

import (
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

func (f *episodeFixture) state(t *testing.T) string {
	t.Helper()
	var state string
	if err := f.pool.QueryRow(f.ctx, `SELECT state FROM metadata_candidates WHERE item_id = $1`, f.show).Scan(&state); err != nil {
		t.Fatal(err)
	}
	return state
}

// Een herhaling gebruikt de toegepaste id en zoekt niet opnieuw op titel.
// Komt er bij de provider een tweede serie met dezelfde naam bij, dan blijft
// de serie gematcht in plaats van op de aandachtslijst te belanden.
func TestRetriedShowReusesItsAppliedMatch(t *testing.T) {
	f := newEpisodeFixtureMatched(t, false)
	p := &episodeTestProvider{seasons: seasonOne(), searches: [][]SearchResult{
		{{ID: 10, Title: "Moon News"}},
		{{ID: 10, Title: "Moon News"}, {ID: 77, Title: "Moon News"}},
	}}
	if st, err := testRunner(f.store, p, f.dir).Round(f.ctx); err != nil || st.Matched != 1 {
		t.Fatalf("eerste ronde: %+v %v", st, err)
	}
	if _, err := f.pool.Exec(f.ctx, `UPDATE metadata_candidates SET next_attempt_at = now() - interval '1 second' WHERE item_id = $1`, f.show); err != nil {
		t.Fatal(err)
	}
	if st, err := testRunner(f.store, p, f.dir).Round(f.ctx); err != nil || st.Matched != 1 {
		t.Fatalf("herhaling: %+v %v", st, err)
	}
	if state := f.state(t); state != catalog.CandidateMatched || p.searched != 1 {
		t.Fatalf("herhaling zocht opnieuw (%d keer) en werd %q", p.searched, state)
	}
}

// Een aflevering die tijdens de ronde verdwijnt, maakt de serie niet "failed".
func TestEpisodeRemovedMidRoundDoesNotFailTheShow(t *testing.T) {
	f := newEpisodeFixture(t)
	p := &episodeTestProvider{seasons: seasonOne()}
	p.onSeason = func() {
		if _, err := f.pool.Exec(f.ctx, `DELETE FROM media_items WHERE id = $1`, f.eps["Mijn eigen titel"]); err != nil {
			t.Fatal(err)
		}
	}
	st, err := testRunner(f.store, p, f.dir).Round(f.ctx)
	if err != nil || st.Failed != 0 {
		t.Fatalf("ronde: %+v %v", st, err)
	}
	if state := f.state(t); state == catalog.CandidateFailed {
		t.Fatal("serie staat op failed door een verdwenen aflevering")
	}
}
