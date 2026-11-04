package metadata

import (
	"context"
	"errors"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

// acknowledgedLostStore simuleert uitsluitend de onzekere retourwaarde, met
// een echte databasecommit of een gesimuleerde niet-gepubliceerde uitkomst.
// Dit is geen echte rollback of fysieke netwerkstoring.
type acknowledgedLostStore struct {
	*catalog.Store
	committed bool
}

func (s *acknowledgedLostStore) CommitMetadata(ctx context.Context, target catalog.MetadataTarget, c catalog.MetadataCandidate, details, sidecar *catalog.MetadataDetails, art []catalog.ProviderArtwork) error {
	if details == nil {
		return s.Store.CommitMetadata(ctx, target, c, details, sidecar, art)
	}
	if s.committed {
		if err := s.Store.CommitMetadata(ctx, target, c, details, sidecar, art); err != nil {
			return err
		}
	}
	return errors.New("synthetisch verloren COMMIT-antwoord")
}
func TestApplicationUncertainCommitUsesOnlyDurableOutcome(t *testing.T) {
	for _, committed := range []bool{false, true} {
		name := "rollback"
		if committed {
			name = "commit"
		}
		t.Run(name, func(t *testing.T) {
			store, ctx, pool, item, dir, before := publicationFixture(t)
			publishA(t, store, ctx, item, dir)
			if err := store.SetManualMatch(ctx, item, ProviderTMDB, "2"); err != nil {
				t.Fatal(err)
			}
			wrapped := &acknowledgedLostStore{Store: store, committed: committed}
			p := &publicationProvider{details: catalog.MetadataDetails{Summary: "B"}}
			st, err := testRunner(wrapped, p, dir).Round(ctx)
			if err != nil || st.Matched != 0 || st.Failed != 1 {
				t.Fatalf("onzekere retour is geen succes: %+v %v", st, err)
			}
			status, err := catalog.NewStore(pool).MetadataMatchStatus(ctx, item)
			if err != nil {
				t.Fatal(err)
			}
			wantState, wantApplied := "failed", "1"
			if committed {
				wantState, wantApplied = "applied", "2"
			}
			if status.State != wantState || status.AppliedExternalID == nil || *status.AppliedExternalID != wantApplied || status.RequestedExternalID == nil || *status.RequestedExternalID != "2" {
				t.Fatalf("onzekere poging verzon uitkomst: %+v", status)
			}
			if metadataReferenceSnapshot(t, ctx, pool, item) != before {
				t.Fatal("onzekere commit wijzigde identiteit/persoonlijke data")
			}
		})
	}
}

func TestApplicationOldMatchedReprocessThenStopsWithoutKeylessLoop(t *testing.T) {
	_, ctx, pool, item, dir, before := publicationFixture(t)
	// Oude manual/details blijven onbewezen, maar de exacte manual-ID blijft gelden.
	if _, err := pool.Exec(ctx, `INSERT INTO metadata_candidates(item_id,provider,state,external_id,manual,details,pass) VALUES($1,'tmdb','matched','7',true,'{"summary":"historisch"}',3)`, item); err != nil {
		t.Fatal(err)
	}
	p := &publicationProvider{}
	for round := 0; round < 3; round++ {
		fresh := catalog.NewStore(pool)
		st, err := testRunner(fresh, p, dir).Round(ctx)
		want := 0
		if round == 0 {
			want = 1
		}
		if err != nil || st.Matched != want {
			t.Fatalf("ronde %d: %+v %v", round, st, err)
		}
	}
	if len(p.ids) != 1 || p.ids[0] != 7 || p.searches != 0 {
		t.Fatalf("reprocess veranderde manual of liep door: %+v", p)
	}
	if _, err := pool.Exec(ctx, `UPDATE metadata_candidates SET applied_provider=NULL,applied_external_id=NULL,application_state='unknown' WHERE item_id=$1`, item); err != nil {
		t.Fatal(err)
	}
	for round := 0; round < 3; round++ {
		r := testRunner(catalog.NewStore(pool), nil, dir)
		r.name = catalog.SourceNFO
		if _, err := r.Round(ctx); err != nil {
			t.Fatal(err)
		}
	}
	status, err := catalog.NewStore(pool).MetadataMatchStatus(ctx, item)
	if err != nil || status.State != "unknown" || status.AppliedExternalID != nil {
		t.Fatalf("keyless verzon bewijs: %+v %v", status, err)
	}
	if metadataReferenceSnapshot(t, ctx, pool, item) != before {
		t.Fatal("reprocess wijzigde identiteit/persoonlijke data")
	}
}
