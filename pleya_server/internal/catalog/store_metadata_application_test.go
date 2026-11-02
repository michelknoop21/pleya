package catalog_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/jackc/pgx/v5/pgxpool"
)

type applicationRow struct {
	requested, provider, applied, state, code string
	generation                                time.Time
}

func readApplication(t *testing.T, ctx context.Context, pool *pgxpool.Pool, item id.ID) applicationRow {
	t.Helper()
	var r applicationRow
	if err := pool.QueryRow(ctx, `SELECT coalesce(external_id,''),coalesce(applied_provider,''),coalesce(applied_external_id,''),application_state,coalesce(application_error_code,''),updated_at FROM metadata_candidates WHERE item_id=$1`, item).Scan(&r.requested, &r.provider, &r.applied, &r.state, &r.code, &r.generation); err != nil {
		t.Fatal(err)
	}
	return r
}
func expectApplication(t *testing.T, ctx context.Context, pool *pgxpool.Pool, item id.ID, requested, applied, state, code string) applicationRow {
	t.Helper()
	r := readApplication(t, ctx, pool, item)
	provider := ""
	if applied != "" {
		provider = "tmdb"
	}
	if r.requested != requested || r.provider != provider || r.applied != applied || r.state != state || r.code != code {
		t.Fatalf("application = %+v; verwacht requested=%s applied=%s state=%s code=%s", r, requested, applied, state, code)
	}
	return r
}
func applicationTarget(t *testing.T, ctx context.Context, store *catalog.Store, item id.ID) catalog.MetadataTarget {
	t.Helper()
	targets, err := store.MetadataDue(ctx, "tmdb", 3, nil, 100)
	if err != nil {
		t.Fatal(err)
	}
	for _, target := range targets {
		if target.ID == item {
			return target
		}
	}
	t.Fatal("doel ontbreekt")
	return catalog.MetadataTarget{}
}
func publishApplication(t *testing.T, ctx context.Context, store *catalog.Store, item id.ID, ext string) {
	t.Helper()
	if err := store.SetManualMatch(ctx, item, "tmdb", ext); err != nil {
		t.Fatal(err)
	}
	target := applicationTarget(t, ctx, store, item)
	d := catalog.MetadataDetails{}
	if err := store.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: ext, Pass: 3}, &d, nil, nil); err != nil {
		t.Fatal(err)
	}
}

func TestApplicationSaveCandidateIsNotPublication(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	item := ids["alien"]
	d := catalog.MetadataDetails{Summary: "geen bewijs"}
	if err := store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "1", Details: &d, Pass: 3}); err != nil {
		t.Fatal(err)
	}
	expectApplication(t, ctx, pool, item, "1", "", "unknown", "")
}

func TestApplicationPendingSuccessFailureRejectAndSameID(t *testing.T) {
	for _, same := range []bool{false, true} {
		name := "B"
		if same {
			name = "A"
		}
		t.Run(name, func(t *testing.T) {
			store, ctx, ids, pool := metadataFixture(t)
			item := ids["alien"]
			publishApplication(t, ctx, store, item, "1")
			before := expectApplication(t, ctx, pool, item, "1", "1", "applied", "")
			next := "2"
			if same {
				next = "1"
			}
			if err := store.SetManualMatch(ctx, item, "tmdb", next); err != nil {
				t.Fatal(err)
			}
			pending := expectApplication(t, ctx, pool, item, next, "1", "pending", "")
			if !pending.generation.After(before.generation) {
				t.Fatal("zelfde keuze verloor generatie")
			}
			target := applicationTarget(t, ctx, store, item)
			retry := time.Now().Add(time.Hour)
			if err := store.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateFailed, ExternalID: next, NextAttempt: &retry, Pass: 3}, nil, nil, nil); err != nil {
				t.Fatal(err)
			}
			expectApplication(t, ctx, pool, item, next, "1", "failed", "application_failed")
			// Nieuwe store leest werkelijk de duurzame rij; geen claim van procesherstart.
			fresh := catalog.NewStore(pool)
			if err := fresh.SetManualMatch(ctx, item, "tmdb", next); err != nil {
				t.Fatal(err)
			}
			expectApplication(t, ctx, pool, item, next, "1", "pending", "")
			target = applicationTarget(t, ctx, fresh, item)
			d := catalog.MetadataDetails{}
			if err := fresh.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: next, NextAttempt: &retry, Pass: 3}, &d, nil, nil); err != nil {
				t.Fatal(err)
			}
			expectApplication(t, ctx, pool, item, next, next, "applied", "") // artworkretry verandert coherente publicatie niet in pending.
			if _, err := fresh.RejectMatch(ctx, item, "tmdb"); err != nil {
				t.Fatal(err)
			}
			expectApplication(t, ctx, pool, item, "", "", "unknown", "")
		})
	}
}

func TestApplicationStaleSuccessAndFailureCannotOverwriteNewerIntent(t *testing.T) {
	for _, action := range []string{"B", "ABA", "reject"} {
		t.Run(action, func(t *testing.T) {
			store, ctx, ids, pool := metadataFixture(t)
			item := ids["alien"]
			publishApplication(t, ctx, store, item, "1")
			if err := store.SetManualMatch(ctx, item, "tmdb", "1"); err != nil {
				t.Fatal(err)
			}
			old := applicationTarget(t, ctx, store, item)
			if action == "reject" {
				if _, err := store.RejectMatch(ctx, item, "tmdb"); err != nil {
					t.Fatal(err)
				}
			} else {
				if err := store.SetManualMatch(ctx, item, "tmdb", "2"); err != nil {
					t.Fatal(err)
				}
				if action == "ABA" {
					if err := store.SetManualMatch(ctx, item, "tmdb", "1"); err != nil {
						t.Fatal(err)
					}
				}
			}
			before := readApplication(t, ctx, pool, item)
			for _, state := range []string{catalog.CandidateMatched, catalog.CandidateFailed} {
				var d *catalog.MetadataDetails
				if state == catalog.CandidateMatched {
					d = &catalog.MetadataDetails{Summary: "stale"}
				}
				err := store.CommitMetadata(ctx, old, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: state, ExternalID: "1", Pass: 3}, d, nil, nil)
				if !errors.Is(err, catalog.ErrMetadataSuperseded) {
					t.Fatalf("stale %s: %v", state, err)
				}
				if got := readApplication(t, ctx, pool, item); got != before {
					t.Fatalf("stale publiceerde status: %+v -> %+v", before, got)
				}
			}
		})
	}
}

func TestApplicationRollbackKeepsProofAndMonotoneItemTime(t *testing.T) {
	for _, changedFields := range []bool{false, true} {
		name := "gelijke_velden"
		if changedFields {
			name = "gewijzigde_velden"
		}
		t.Run(name, func(t *testing.T) {
			store, ctx, ids, pool := metadataFixture(t)
			item := ids["alien"]
			publishApplication(t, ctx, store, item, "1")
			if err := store.SetManualMatch(ctx, item, "tmdb", "2"); err != nil {
				t.Fatal(err)
			}
			target := applicationTarget(t, ctx, store, item)
			before := readApplication(t, ctx, pool, item)
			d := catalog.MetadataDetails{}
			err := store.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: "ongeldig", ExternalID: "2", Pass: 3}, &d, nil, nil)
			if err == nil {
				t.Fatal("ongeldige publicatie slaagde")
			}
			if got := readApplication(t, ctx, pool, item); got != before {
				t.Fatalf("rollback verloor bewijs: %+v", got)
			}
			future := time.Date(2100, 1, 1, 0, 0, 0, 0, time.UTC)
			if _, err := pool.Exec(ctx, `UPDATE media_items SET updated_at=$2 WHERE id=$1`, item, future); err != nil {
				t.Fatal(err)
			}
			if changedFields {
				d.Summary = "B"
			}
			if err := store.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "2", Pass: 3}, &d, nil, nil); err != nil {
				t.Fatal(err)
			}
			var stamp time.Time
			if err := pool.QueryRow(ctx, `SELECT updated_at FROM media_items WHERE id=$1`, item).Scan(&stamp); err != nil {
				t.Fatal(err)
			}
			if !stamp.After(future) {
				t.Fatalf("itemtijd liep niet op: %s", stamp)
			}
			if _, err := store.RejectMatch(ctx, item, "tmdb"); err != nil {
				t.Fatal(err)
			}
			var rejected time.Time
			if err := pool.QueryRow(ctx, `SELECT updated_at FROM media_items WHERE id=$1`, item).Scan(&rejected); err != nil {
				t.Fatal(err)
			}
			if !rejected.After(stamp) {
				t.Fatal("reject trok itemtijd terug")
			}
		})
	}
}

func TestApplicationUnknownReprocessIsBoundedAndRespectsRetry(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	item := ids["alien"]
	if err := store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "7", Pass: 3}); err != nil {
		t.Fatal(err)
	}
	target := applicationTarget(t, ctx, store, item)
	d := catalog.MetadataDetails{}
	if err := store.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "7", Pass: 3}, &d, nil, nil); err != nil {
		t.Fatal(err)
	}
	dueHas := func(pass int) bool {
		t.Helper()
		targets, err := store.MetadataDue(ctx, "tmdb", pass, nil, 100)
		if err != nil {
			t.Fatal(err)
		}
		for _, target := range targets {
			if target.ID == item {
				return true
			}
		}
		return false
	}
	if dueHas(3) {
		t.Fatal("bewezen publicatie bleef opnieuw lopen")
	}
	if _, err := pool.Exec(ctx, `UPDATE metadata_candidates SET applied_provider=NULL,applied_external_id=NULL,application_state='unknown',next_attempt_at=now()+interval '1 day',pass=1 WHERE item_id=$1`, item); err != nil {
		t.Fatal(err)
	}
	if dueHas(3) {
		t.Fatal("reprocess omzeilt toekomstige retry")
	}
	if _, err := pool.Exec(ctx, `UPDATE metadata_candidates SET state='ambiguous',next_attempt_at=NULL WHERE item_id=$1`, item); err != nil {
		t.Fatal(err)
	}
	if dueHas(3) {
		t.Fatal("ambigue rij werd automatisch gekozen")
	}
	if _, err := store.RejectMatch(ctx, item, "tmdb"); err != nil {
		t.Fatal(err)
	}
	if dueHas(3) {
		t.Fatal("reject kwam terug")
	}
}

func TestApplicationStatusReadsOneCoherentDurableRow(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	for _, item := range []id.ID{ids["alien"], ids["show"]} {
		status, err := store.MetadataMatchStatus(ctx, item)
		if err != nil || status.State != "unknown" || status.UpdatedAt != nil || status.RequestedProvider != nil || status.AppliedProvider != nil {
			t.Fatalf("zonder kandidaat: %+v %v", status, err)
		}
	}
	for _, item := range []id.ID{ids["season"], id.New()} {
		if _, err := store.MetadataMatchStatus(ctx, item); !errors.Is(err, catalog.ErrNotFound) {
			t.Fatalf("ongeldig item: %v", err)
		}
	}
	item := ids["alien"]
	publishApplication(t, ctx, store, item, "1")
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `UPDATE metadata_candidates SET external_id='2',application_state='pending',updated_at=updated_at+interval '1 microsecond' WHERE item_id=$1`, item); err != nil {
		t.Fatal(err)
	}
	check := func(requested, applied, state string) {
		t.Helper()
		s, err := catalog.NewStore(pool).MetadataMatchStatus(ctx, item)
		if err != nil || s.RequestedProvider == nil || *s.RequestedProvider != "tmdb" || s.RequestedExternalID == nil || *s.RequestedExternalID != requested || s.AppliedProvider == nil || *s.AppliedProvider != "tmdb" || s.AppliedExternalID == nil || *s.AppliedExternalID != applied || s.State != state || s.UpdatedAt == nil {
			t.Fatalf("incoherente rij: %+v %v", s, err)
		}
	}
	check("1", "1", "applied")
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	check("2", "1", "pending")
}

func TestApplicationDueSeparatesNewProofReasonFromOldPassAndNFO(t *testing.T) {
	for _, tc := range []struct {
		name, state, application string
		pass                     int
		future, want             bool
	}{
		{"nieuw_unknown_matched", "matched", "unknown", 3, false, true},
		{"nieuw_applied_matched", "matched", "applied", 3, false, false},
		{"oud_applied_matched", "matched", "applied", 1, false, true},
		{"oud_unmatched", "unmatched", "unknown", 1, false, true},
		{"oud_failed", "failed", "unknown", 1, false, true},
		{"oud_ambiguous", "ambiguous", "unknown", 1, false, false},
		{"oud_rejected", "rejected", "unknown", 1, false, false},
		{"oud_matched_retry", "matched", "unknown", 1, true, false},
		{"oud_applied_retry", "matched", "applied", 1, true, false},
		{"oud_unmatched_retry", "unmatched", "unknown", 1, true, false},
		{"oud_failed_retry", "failed", "failed", 1, true, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store, ctx, ids, pool := metadataFixture(t)
			item := ids["alien"]
			var next *time.Time
			if tc.future {
				n := time.Now().Add(time.Hour)
				next = &n
			}
			if err := store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: tc.state, ExternalID: "7", Pass: tc.pass, NextAttempt: next}); err != nil {
				t.Fatal(err)
			}
			if tc.application == "applied" {
				if _, err := pool.Exec(ctx, `UPDATE metadata_candidates SET application_state='applied',applied_provider='tmdb',applied_external_id='7' WHERE item_id=$1`, item); err != nil {
					t.Fatal(err)
				}
			}
			if tc.application == "failed" {
				if _, err := pool.Exec(ctx, `UPDATE metadata_candidates SET application_state='failed',application_error_code='application_failed' WHERE item_id=$1`, item); err != nil {
					t.Fatal(err)
				}
			}
			has := func(provider string) bool {
				t.Helper()
				targets, err := store.MetadataDue(ctx, provider, 3, nil, 100)
				if err != nil {
					t.Fatal(err)
				}
				for _, target := range targets {
					if target.ID == item {
						return true
					}
				}
				return false
			}
			if got := has("tmdb"); got != tc.want {
				t.Fatalf("providerdue=%v, verwacht %v", got, tc.want)
			}
			// Een lokale NFO-ronde houdt haar eigen klok, ongeacht candidate-state/pass.
			if !has(catalog.SourceNFO) {
				t.Fatal("candidateguard blokkeerde lokale NFO")
			}
			if err := store.MarkSidecarChecked(ctx, item); err != nil {
				t.Fatal(err)
			}
			if has(catalog.SourceNFO) {
				t.Fatal("lokale NFO bleef terugkomen")
			}
			if _, err := pool.Exec(ctx, `UPDATE media_items SET sidecar_checked_at=now()-interval '8 days' WHERE id=$1`, item); err != nil {
				t.Fatal(err)
			}
			if !has(catalog.SourceNFO) {
				t.Fatal("bestaande NFO-hercheck verdwenen")
			}
		})
	}
}

func TestApplicationPublicationRequiresGuardedItem(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	item := ids["alien"]
	other := ids["heat"]
	publishApplication(t, ctx, store, item, "1")
	publishApplication(t, ctx, store, other, "2")
	if err := store.SetManualMatch(ctx, item, "tmdb", "3"); err != nil {
		t.Fatal(err)
	}
	target := applicationTarget(t, ctx, store, item)
	before := readApplication(t, ctx, pool, other)
	d := catalog.MetadataDetails{}
	if err := store.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: other, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "3", Pass: 3}, &d, nil, nil); err == nil {
		t.Fatal("publicatie buiten het gelockte item geaccepteerd")
	}
	if got := readApplication(t, ctx, pool, other); got != before {
		t.Fatal("ongelockte publicatie wijzigde ander bewijs")
	}
}

func TestApplicationArtworkRequiresGuardedItem(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	item, other := ids["alien"], ids["heat"]
	publishApplication(t, ctx, store, item, "1")
	publishApplication(t, ctx, store, other, "2")
	if err := store.SetManualMatch(ctx, item, "tmdb", "3"); err != nil {
		t.Fatal(err)
	}
	target := applicationTarget(t, ctx, store, item)
	before, otherBefore := readApplication(t, ctx, pool, item), readApplication(t, ctx, pool, other)
	d := catalog.MetadataDetails{PosterRef: "/fixture.jpg"}
	art := []catalog.ProviderArtwork{{ID: id.New(), ItemID: other, Provider: "tmdb", Kind: "poster", SourceRef: "/fixture.jpg", FileName: "fixture.jpg", SHA256: "fixture"}}
	if err := store.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "3", Pass: 3}, &d, nil, art); err == nil {
		t.Fatal("artwork buiten het gelockte item geaccepteerd")
	}
	if got := readApplication(t, ctx, pool, item); got != before {
		t.Fatal("geweigerde artwork publiceerde deelstatus")
	}
	if got := readApplication(t, ctx, pool, other); got != otherBefore {
		t.Fatal("geweigerde artwork wijzigde ander bewijs")
	}
	var count int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM provider_artwork WHERE item_id=$1`, other).Scan(&count); err != nil || count != 0 {
		t.Fatalf("artwork buiten guard geschreven: %d %v", count, err)
	}
}
