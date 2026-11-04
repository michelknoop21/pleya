package catalog_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type publicationReadTracer struct {
	publish func()
	fired   bool
	lookup  bool
}
type publicationReadKey struct{}

func (p *publicationReadTracer) TraceQueryStart(ctx context.Context, _ *pgx.Conn, q pgx.TraceQueryStartData) context.Context {
	match := strings.Contains(q.SQL, "i.summary") && strings.Contains(q.SQL, "FROM media_items")
	if p.lookup {
		match = strings.Contains(q.SQL, "mc.applied_external_id") && strings.Contains(q.SQL, "FROM media_items")
	}
	return context.WithValue(ctx, publicationReadKey{}, match)
}
func (p *publicationReadTracer) TraceQueryEnd(ctx context.Context, _ *pgx.Conn, _ pgx.TraceQueryEndData) {
	if match, _ := ctx.Value(publicationReadKey{}).(bool); match && !p.fired {
		p.fired = true
		p.publish()
	}
}

// De tracer publiceert echt B via een andere pool zodra de metadataquery A
// gesloten is, of bij lookup direct na de primaire selectie. Dit is een
// deterministische interleaving, geen timingrace.
func TestAppliedItemReadKeepsPublicationSnapshot(t *testing.T) {
	for _, name := range []string{"detail", "pagina", "lookup"} {
		t.Run(name, func(t *testing.T) {
			store, ctx, ids, pool := metadataFixture(t)
			item := ids["alien"]
			publish := func(ext, label string, art id.ID) {
				t.Helper()
				if err := store.SetManualMatch(ctx, item, "tmdb", ext); err != nil {
					t.Fatal(err)
				}
				target := applicationTarget(t, ctx, store, item)
				d := catalog.MetadataDetails{Summary: label, ContentRating: label, People: []catalog.Person{{Name: label, Role: "director"}}, PosterRef: "/" + label + ".jpg"}
				kind := "poster"
				if label == "B" {
					kind = "backdrop"
					d.BackdropRef = d.PosterRef
					d.PosterRef = ""
				}
				a := catalog.ProviderArtwork{ID: art, ItemID: item, Kind: kind, Provider: "tmdb", SourceRef: "/" + label + ".jpg", FileName: art.String() + ".jpg", SHA256: label}
				if err := store.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: ext, Pass: 3}, &d, nil, []catalog.ProviderArtwork{a}); err != nil {
					t.Fatal(err)
				}
			}
			a, b := id.New(), id.New()
			publish("1", "A", a)
			tracer := &publicationReadTracer{publish: func() { publish("2", "B", b) }, lookup: name == "lookup"}
			cfg := pool.Config()
			cfg.ConnConfig.Tracer = tracer
			readPool, err := pgxpool.NewWithConfig(ctx, cfg)
			if err != nil {
				t.Fatal(err)
			}
			defer readPool.Close()
			reader := catalog.NewStore(readPool)
			var got catalog.Item
			if name != "detail" {
				query := catalog.Query{Limit: 100}
				if name == "lookup" {
					query.Filters.AppliedExternalID = &catalog.ExternalIDFilter{Provider: "tmdb", Value: 1}
				}
				result, err := reader.Items(ctx, query)
				if err != nil {
					t.Fatal(err)
				}
				for _, v := range result.Items {
					if v.ID == item {
						got = v
					}
				}
			} else {
				got, err = reader.Item(ctx, item)
				if err != nil {
					t.Fatal(err)
				}
			}
			if !tracer.fired {
				t.Fatal("publicatie-interleaving niet uitgevoerd")
			}
			if got.Summary == nil || *got.Summary != "A" || got.ContentRating == nil || *got.ContentRating != "A" || len(got.People) != 1 || got.People[0].Name != "A" || got.PosterID == nil || *got.PosterID != a || got.AppliedExternalIDs.TMDB == nil || *got.AppliedExternalIDs.TMDB != 1 {
				t.Fatalf("A/B gemengde snapshot: %+v", got)
			}
			latest, err := store.Item(ctx, item)
			if err != nil {
				t.Fatal(err)
			}
			if latest.Summary == nil || *latest.Summary != "B" || latest.AppliedExternalIDs.TMDB == nil || *latest.AppliedExternalIDs.TMDB != 2 || latest.PosterID != nil || latest.BackdropID == nil || *latest.BackdropID != b {
				t.Fatalf("B niet echt gepubliceerd: %+v", latest)
			}
		})
	}
}

func TestAppliedFilterFingerprintKeepsLegacyCursors(t *testing.T) {
	for _, c := range []struct {
		f    catalog.Filters
		want string
	}{
		{catalog.Filters{}, ""},
		{catalog.Filters{ExternalID: &catalog.ExternalIDFilter{Provider: "tmdb", Value: 621}}, "58f3f77dd1c7"},
		{catalog.Filters{Genres: []string{"drama"}}, "f558f29f8e5e"},
	} {
		if got := c.f.Fingerprint(); got != c.want {
			t.Fatalf("legacyfingerprint %v = %q; verwacht %q", c.f, got, c.want)
		}
	}
	legacy := catalog.Filters{ExternalID: &catalog.ExternalIDFilter{Provider: "tmdb", Value: 621}}
	applied := catalog.Filters{AppliedExternalID: &catalog.ExternalIDFilter{Provider: "tmdb", Value: 621}}
	other := catalog.Filters{AppliedExternalID: &catalog.ExternalIDFilter{Provider: "tmdb", Value: 622}}
	if applied.Empty() || applied.Fingerprint() == legacy.Fingerprint() || applied.Fingerprint() == other.Fingerprint() {
		t.Fatal("nieuwe filter niet gebonden")
	}
	cursor := catalog.Cursor{Sort: catalog.SortTitle, Key: "a", ID: id.New().String(), Filter: legacy.Fingerprint()}
	if _, err := catalog.DecodeCursorFor(cursor.Encode(), catalog.SortTitle, applied.Fingerprint()); !errors.Is(err, catalog.ErrCursorInvalid) {
		t.Fatalf("filterwissel: %v", err)
	}
}

// De oude aparte IDquery sloeg seizoenen/afleveringen over. De gecombineerde
// metadataread is voor hun eigen velden nodig, maar mag ook met vervuilde
// kandidaatdata geen titelidentiteit aan ze toekennen.
func TestAppliedReadDoesNotGiveSeasonsOrEpisodesAnIdentity(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	episode := id.New()
	ids["episode"] = episode
	if _, err := pool.Exec(ctx, `INSERT INTO media_items(id,library_id,parent_id,kind,title,grouping_key) SELECT $1,library_id,id,'episode','Aflevering 1','episode-test' FROM media_items WHERE id=$2`, episode, ids["season"]); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"season", "episode"} {
		item := ids[key]
		if item == (id.ID{}) {
			t.Fatalf("fixture mist %s", key)
		}
		if _, err := pool.Exec(ctx, `INSERT INTO metadata_candidates(item_id,provider,state,external_id,applied_provider,applied_external_id,application_state) VALUES($1,'tmdb','matched','1','tmdb','1','applied')`, item); err != nil {
			t.Fatal(err)
		}
		got, err := store.Item(ctx, item)
		if err != nil {
			t.Fatal(err)
		}
		if !got.ExternalIDs.IsZero() || !got.AppliedExternalIDs.IsZero() {
			t.Fatalf("%s kreeg identiteit: %+v", key, got)
		}
	}
}

func TestAppliedReadDoesNotInventProofFromLegacyOrMalformedIDs(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	item := ids["alien"]
	if err := store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "621"}); err != nil {
		t.Fatal(err)
	}
	it, err := store.Item(ctx, item)
	if err != nil {
		t.Fatal(err)
	}
	if it.ExternalIDs.TMDB == nil || *it.ExternalIDs.TMDB != 621 || !it.AppliedExternalIDs.IsZero() {
		t.Fatalf("legacy werd applied: %+v", it)
	}
	for _, raw := range []string{"0", "-1", "+1", "01", "abc", "999999999999999999999999"} {
		if _, err := pool.Exec(ctx, `UPDATE metadata_candidates SET applied_provider='tmdb',applied_external_id=$2 WHERE item_id=$1`, item, raw); err != nil {
			t.Fatal(err)
		}
		it, err = store.Item(ctx, item)
		if err != nil {
			t.Fatal(err)
		}
		if !it.AppliedExternalIDs.IsZero() {
			t.Fatalf("ongeldig %q werd bewijs: %+v", raw, it.AppliedExternalIDs)
		}
	}
}

func TestAppliedLookupUsesOnlyItsSnapshotConnection(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	publishApplication(t, ctx, store, ids["alien"], "1")
	openGenreGate(t, ctx, pool)
	cfg := pool.Config()
	cfg.MaxConns = 1
	readerPool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer readerPool.Close()
	readCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	reader := catalog.NewStore(readerPool)
	result, err := reader.Items(readCtx, catalog.Query{Limit: 100, Filters: catalog.Filters{AppliedExternalID: &catalog.ExternalIDFilter{Provider: "tmdb", Value: 1}}})
	if err != nil {
		t.Fatalf("snapshot probe leent een tweede verbinding of faalt: %v", err)
	}
	if len(result.Items) != 1 || len(result.Items[0].Genres) == 0 {
		t.Fatalf("snapshot/genrepoort niet compleet: %+v", result)
	}
	if readerPool.Stat().AcquiredConns() != 0 {
		t.Fatal("readtransactie lekt verbinding")
	}
}
