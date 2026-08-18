// Package database opent de Postgres-pool.
//
// De pool verbindt lui. Dat is opzet: de server hoeft bij het opstarten niet te
// wachten op een Postgres die tien seconden later opkomt, en er is dus ook geen
// retrylus nodig. Bereikbaarheid is wat /readyz bewijst.
package database

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// PingTimeout begrenst de interne gezondheidscontrole van de pool.
const PingTimeout = 5 * time.Second

// MaxConns houdt de pool klein. De doelhardware is een NAS met vier trage
// cores, niet een applicatieserver.
const MaxConns = 10

// Open bouwt de pool op. Er wordt hier niet verbonden en niet gepingd.
func Open(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("databaseverbinding is onleesbaar: %w", err)
	}
	cfg.MaxConns = MaxConns
	cfg.PingTimeout = PingTimeout

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("pool aanmaken mislukt: %w", err)
	}
	return pool, nil
}
