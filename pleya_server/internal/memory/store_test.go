package memory

import (
	"context"
	"errors"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	"sync"
	"testing"
	"time"
)

func TestMemoryCASDeletionEpochAndIsolation(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatal(err)
	}
	user, other := id.New(), id.New()
	if _, err := pool.Exec(ctx, `INSERT INTO users(id,username,password_hash,role) VALUES($1,'a','x','owner'),($2,'b','x','member')`, user, other); err != nil {
		t.Fatal(err)
	}
	s := NewStore(pool)
	base, err := s.Read(ctx, user)
	if err != nil {
		t.Fatal(err)
	}
	again, err := s.Read(ctx, user)
	if err != nil || again.Epoch != base.Epoch {
		t.Fatal("GET verandert de epoch")
	}
	f := Fact{ID: id.New(), Category: "preference", Value: "Houdt van horror", Source: "user_explicit"}
	current, err := s.Replace(ctx, user, base.Epoch, base.Revision, []Fact{f}, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	otherSnap, err := s.Read(ctx, other)
	if err != nil || len(otherSnap.Facts) != 0 {
		t.Fatal("gebruiker ziet andermans feit")
	}
	if _, err = s.Replace(ctx, user, base.Epoch, base.Revision, []Fact{}, time.Now()); !errors.Is(err, ErrConflict) {
		t.Fatal("verouderde writer geaccepteerd")
	}
	current, err = s.Replace(ctx, user, current.Epoch, current.Revision, []Fact{}, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.Replace(ctx, user, current.Epoch, current.Revision, []Fact{f}, time.Now()); !errors.Is(err, ErrDeleted) {
		t.Fatal("gewist id herleeft")
	}
	before := current
	current, err = s.Clear(ctx, user, current.Epoch, current.Revision)
	if err != nil || current.Epoch == before.Epoch {
		t.Fatal("clear mist nieuwe epoch")
	}
	f.ID = id.New()
	if _, err = s.Replace(ctx, user, before.Epoch, before.Revision, []Fact{f}, time.Now()); !errors.Is(err, ErrEpoch) {
		t.Fatal("offline nieuw feit passeert wisgrens")
	}
	if _, err = s.Clear(ctx, user, before.Epoch, before.Revision); !errors.Is(err, ErrEpoch) {
		t.Fatal("verouderde clear geaccepteerd")
	}
	// Twee writers met dezelfde basis: precies één commit.
	var wg sync.WaitGroup
	errs := make(chan error, 2)
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, e := s.Replace(ctx, user, current.Epoch, current.Revision, []Fact{f}, time.Now())
			errs <- e
		}()
	}
	wg.Wait()
	close(errs)
	successes, conflicts := 0, 0
	for e := range errs {
		if e == nil {
			successes++
		} else if errors.Is(e, ErrConflict) {
			conflicts++
		} else {
			t.Fatal(e)
		}
	}
	if successes != 1 || conflicts != 1 {
		t.Fatal("CAS serialiseert niet")
	}
}
