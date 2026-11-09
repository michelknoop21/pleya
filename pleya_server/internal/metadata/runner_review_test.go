package metadata

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

func TestChildSuccessDoesNotResetProviderCircuitBreaker(t *testing.T) {
	targets := []catalog.MetadataTarget{}
	provider := &fakeProvider{fail: map[string]error{}}
	for n := 0; n < 7; n++ {
		name := fmt.Sprintf("failure-%d", n)
		provider.fail[name] = errors.New("provider unavailable")
		for _, kind := range []string{"show", "season", "episode"} {
			targets = append(targets, catalog.MetadataTarget{ID: id.New(), Kind: kind, Title: name})
		}
	}
	store := newFakeStore(targets...)
	_, err := testRunner(store, provider, t.TempDir()).Round(context.Background())
	if err == nil || provider.calls != 5 {
		t.Fatalf("breaker bypassed: calls %d error %v", provider.calls, err)
	}
	for _, target := range targets {
		if target.Kind != "show" {
			if _, ok := store.candidates[target.ID]; ok {
				t.Fatal("child received provider candidate")
			}
		}
	}
}

type reviewStore struct {
	*fakeStore
	maxExcluded int
	childError  error
}

func (s *reviewStore) MetadataDue(ctx context.Context, provider string, pass int, exclude []id.ID, limit int) ([]catalog.MetadataTarget, error) {
	if len(exclude) > s.maxExcluded {
		s.maxExcluded = len(exclude)
	}
	return s.fakeStore.MetadataDue(ctx, provider, pass, exclude, limit)
}
func (s *reviewStore) CommitSidecar(ctx context.Context, target catalog.MetadataTarget, details *catalog.MetadataDetails) error {
	if s.childError != nil {
		return s.childError
	}
	return s.fakeStore.CommitSidecar(ctx, target, details)
}

func TestSuccessfulChildRoundDoesNotGrowSQLExclusions(t *testing.T) {
	targets := make([]catalog.MetadataTarget, 21000)
	for i := range targets {
		targets[i] = catalog.MetadataTarget{ID: id.New(), Kind: "episode", Title: "local child"}
	}
	store := &reviewStore{fakeStore: newFakeStore(targets...)}
	provider := &fakeProvider{}
	_, err := testRunner(store, provider, t.TempDir()).Round(context.Background())
	if err != nil || store.maxExcluded != 0 || len(store.checked) != len(targets) || provider.calls != 0 {
		t.Fatalf("round error %v excluded %d checked %d provider %d", err, store.maxExcluded, len(store.checked), provider.calls)
	}
}

func TestDirectChildGuardNeverCallsProvider(t *testing.T) {
	for _, kind := range []string{"season", "episode"} {
		target := catalog.MetadataTarget{ID: id.New(), Kind: kind, Title: "child"}
		store := newFakeStore(target)
		provider := &fakeProvider{}
		err := testRunner(store, provider, t.TempDir()).one(context.Background(), target, &RoundStats{})
		if err != nil || provider.calls != 0 || len(store.candidates) != 0 || !store.checked[target.ID] {
			t.Fatalf("child guard failed: %s %v", kind, err)
		}
	}
}

func TestFailedChildCommitDoesNotCreateProviderCandidateOrLoop(t *testing.T) {
	target := catalog.MetadataTarget{ID: id.New(), Kind: "episode", Title: "child"}
	store := &reviewStore{fakeStore: newFakeStore(target), childError: errors.New("local database write failure")}
	provider := &fakeProvider{}
	stats, err := testRunner(store, provider, t.TempDir()).Round(context.Background())
	if err != nil || stats.Failed != 1 || provider.calls != 0 || len(store.candidates) != 0 || store.maxExcluded != 1 {
		t.Fatalf("child failure leaked or looped: %+v %v excluded %d", stats, err, store.maxExcluded)
	}
}
