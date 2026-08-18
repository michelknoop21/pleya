package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/config"
	"github.com/edde746/plezy/pleya_server/internal/mounts"
)

// ensureSetupCode drukt een verse setupcode af zolang er geen eigenaar is.
//
// Er is geen standaardwachtwoord en geen ingebouwd account. De code is
// kortlevend en eenmalig: hij vervalt bij de eerste geslaagde inwisseling en
// daarnaast vanzelf, en persistent staat hij er alleen als hash in.
func ensureSetupCode(ctx context.Context, store *auth.Store, ttl time.Duration, log *slog.Logger) error {
	required, err := store.SetupRequired(ctx)
	if err != nil {
		return err
	}
	if !required {
		return nil
	}

	code, hash, err := auth.NewSetupCode()
	if err != nil {
		return err
	}
	expires := time.Now().UTC().Add(ttl)
	if err := store.PutSetupCode(ctx, hash, expires); err != nil {
		return err
	}

	// Naar stderr en niet door de JSON-logger, zodat hij leesbaar op de console
	// staat en niet in een logaggregator belandt die iedereen mag lezen.
	fmt.Fprintf(os.Stderr,
		"\n  Pleya Server is nog niet ingericht.\n"+
			"  Setupcode: %s\n"+
			"  Geldig tot %s. Wissel hem in met POST /pleya/v1/auth/setup.\n\n",
		code, expires.Format(time.RFC3339))

	log.Info("setupcode afgedrukt", slog.Time("expires_at", expires))
	return nil
}

// syncLibraries brengt de configuratie en de database bij elkaar, en meet
// meteen het bestandssysteem onder elke root.
func syncLibraries(ctx context.Context, store *catalog.Store, cfg *config.Config, log *slog.Logger) ([]catalog.Library, error) {
	if len(cfg.Libraries) == 0 {
		log.Warn("geen bibliotheken geconfigureerd; PLEYA_SERVER_LIBRARIES is leeg")
		return nil, nil
	}

	specs := make([]catalog.LibrarySpec, 0, len(cfg.Libraries))
	for _, spec := range cfg.Libraries {
		out := catalog.LibrarySpec{Slug: spec.Slug, Title: spec.Title, Kind: spec.Kind}

		for _, root := range spec.Roots {
			info := mounts.Inspect(root)
			trusted := mounts.InodeTrustDefault(info.FSType)
			source := "fstype_default"

			switch cfg.InodeTrust[root] {
			case config.InodeTrustAlways:
				trusted, source = true, "config_override"
			case config.InodeTrustNever:
				trusted, source = false, "config_override"
			}

			out.Roots = append(out.Roots, catalog.RootSpec{
				Path:         root,
				FSType:       info.FSType,
				InodeTrusted: trusted,
				TrustSource:  source,
			})

			log.Info("bibliotheekroot",
				slog.String("library", spec.Slug),
				slog.String("root", root),
				slog.String("fstype", info.FSType),
				slog.Bool("exists", info.Exists),
				slog.Bool("readable", info.Readable),
				slog.Bool("mounted_read_only", info.ReadOnly),
				slog.Bool("inode_trusted", trusted),
				slog.String("inode_trust_source", source))
		}
		specs = append(specs, out)
	}

	libs, err := store.SyncLibraries(ctx, specs)
	if err != nil {
		return nil, err
	}
	for _, l := range libs {
		log.Info("bibliotheek gereed",
			slog.String("slug", l.Slug),
			slog.String("id", l.ID.String()),
			slog.String("kind", l.Kind))
	}
	return libs, nil
}

// openStores bundelt de twee opslaglagen rond dezelfde pool.
func openStores(pool *pgxpool.Pool) (*catalog.Store, *auth.Store) {
	return catalog.NewStore(pool), auth.NewStore(pool)
}
