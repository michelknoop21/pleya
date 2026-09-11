package loudness

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Source is stream_loudness.source: het type bewijs dat een rij vertegenwoordigt.
type Source string

const (
	SourceServerScan Source = "server_scan"
	SourceOpusR128   Source = "opus_r128"
)

// Methodenamen. Twee methodes op dezelfde stream en basis zijn twee rijen, geen
// versies van elkaar (D1).
const (
	MethodFFmpegLoudnorm = "ffmpeg-loudnorm-1"
	MethodTagOpusR128    = "tag-opus-r128-1"
)

// methodVersion hoort bij de methode-implementatie in dit pakket, niet bij een
// individuele meting; er is vandaag van elke methode precies één versie.
const methodVersion = 1

// crossCheckToleranceLu: een tag-rij die meer dan dit van een bestaande
// server_scan-meting afwijkt is geen betrouwbaar bewijs, hoe schoon de tag zelf
// ook parseerde.
const crossCheckToleranceLu = 1.0

// ReasonCrossCheckMismatch is de reject_reason wanneer een tag-rij en een
// bestaande meting het oneens zijn.
const ReasonCrossCheckMismatch Reason = "cross_check_mismatch"

// State is stream_loudness.state.
type State string

const (
	StateReady           State = "ready"
	StateFailedPermanent State = "failed_permanent"
	StateRejected        State = "rejected"
)

// PublishInput is één rij bewijs, geslaagd of niet.
type PublishInput struct {
	FileID      id.ID
	StreamIndex int
	Basis       Basis
	Method      string
	Source      Source
	Generation  int64
	State       State

	IntegratedLufs *float64
	TruePeakDbtp   *float64
	LraLu          *float64
	ThresholdLufs  *float64
	GainDb         *float64
	ReferenceLufs  *float64

	CoverageComplete bool
	Codec            string
	ChannelLayout    *string

	// RejectReason is verplicht buiten State == StateReady (D1's CHECK), en
	// wordt genegeerd wanneer State == StateReady: Publish zet hem dan zelf op
	// NULL, ook als de aanroeper per ongeluk iets meegaf.
	RejectReason *Reason
}

// Store schrijft loudnessbewijs.
type Store struct {
	pool *pgxpool.Pool
}

// NewStore bouwt de opslag rond de pool.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// Publish schrijft één rij, of doet stilzwijgend niets als de generation van
// het bestand intussen is doorgelopen (een herscan maakte deze meting
// ongeldig voordat hij landde) of een rij van een nieuwere generation er al
// staat.
//
// Een server_scan-rij publiceert zoals aangeleverd. Een tag-afgeleide rij
// toetst zichzelf daarnaast, in dezelfde statement, tegen een bestaande ready
// server_scan-rij op dezelfde stream en basis: meer dan crossCheckToleranceLu
// LU uit elkaar en de rij landt rejected, ongeacht wat de aanroeper vroeg. In
// één statement betekent dat een tussentijds gelezen-dan-verouderde stand
// tussen die toets en deze schrijfactie niet kan bestaan; D2 uit
// pleya-server-loudness-measurement-proposal.md noemt dit de
// "verificatie-achteraf en de conditionele publicatie in één statement".
func (s *Store) Publish(ctx context.Context, in PublishInput) error {
	var rejectReason *string
	if in.RejectReason != nil {
		v := string(*in.RejectReason)
		rejectReason = &v
	}
	crossCheckReason := string(ReasonCrossCheckMismatch)

	_, err := s.pool.Exec(ctx, `
WITH candidate AS (
    SELECT
        $1::uuid    AS file_id,
        $2::int     AS stream_index,
        $3::text    AS basis_key,
        $4::text    AS method,
        $5::text    AS source,
        $6::text    AS state,
        $7::bigint  AS generation,
        $8::float8  AS integrated_lufs,
        $9::float8  AS true_peak_dbtp,
        $10::float8 AS lra_lu,
        $11::float8 AS threshold_lufs,
        $12::float8 AS gain_db,
        $13::float8 AS reference_lufs,
        $14::bool   AS coverage_complete,
        $15::text   AS codec,
        $16::text   AS channel_layout,
        $17::text   AS reject_reason
),
sibling AS (
    SELECT sl.integrated_lufs
    FROM stream_loudness sl, candidate c
    WHERE sl.file_id = c.file_id
      AND sl.stream_index = c.stream_index
      AND sl.basis_key = c.basis_key
      AND sl.method = 'ffmpeg-loudnorm-1'
      AND sl.state = 'ready'
      AND sl.generation = c.generation
),
resolved AS (
    SELECT
        c.*,
        (c.method <> 'ffmpeg-loudnorm-1'
            AND c.state = 'ready'
            AND s.integrated_lufs IS NOT NULL
            AND abs(coalesce(c.integrated_lufs, c.reference_lufs - c.gain_db) - s.integrated_lufs)
                > $18::float8
        ) AS cross_check_failed
    FROM candidate c
    LEFT JOIN sibling s ON true
)
INSERT INTO stream_loudness (
    file_id, stream_index, basis_key, method, method_version, source, state, generation,
    integrated_lufs, true_peak_dbtp, lra_lu, threshold_lufs, gain_db, reference_lufs,
    coverage_complete, codec, channel_layout, reject_reason
)
SELECT
    r.file_id, r.stream_index, r.basis_key, r.method, $19::int, r.source,
    CASE WHEN r.cross_check_failed THEN 'rejected' ELSE r.state END,
    r.generation, r.integrated_lufs, r.true_peak_dbtp, r.lra_lu, r.threshold_lufs,
    r.gain_db, r.reference_lufs, r.coverage_complete, r.codec, r.channel_layout,
    CASE
        WHEN r.cross_check_failed THEN $20::text
        WHEN r.state = 'ready' THEN NULL
        ELSE r.reject_reason
    END
FROM resolved r
JOIN media_files f ON f.id = r.file_id
WHERE f.generation = r.generation AND f.missing_since IS NULL
ON CONFLICT (file_id, stream_index, basis_key, method) DO UPDATE SET
    method_version    = EXCLUDED.method_version,
    source            = EXCLUDED.source,
    state             = EXCLUDED.state,
    generation        = EXCLUDED.generation,
    integrated_lufs   = EXCLUDED.integrated_lufs,
    true_peak_dbtp    = EXCLUDED.true_peak_dbtp,
    lra_lu            = EXCLUDED.lra_lu,
    threshold_lufs    = EXCLUDED.threshold_lufs,
    gain_db           = EXCLUDED.gain_db,
    reference_lufs    = EXCLUDED.reference_lufs,
    coverage_complete = EXCLUDED.coverage_complete,
    codec             = EXCLUDED.codec,
    channel_layout    = EXCLUDED.channel_layout,
    reject_reason     = EXCLUDED.reject_reason,
    measured_at       = now()
WHERE stream_loudness.generation <= EXCLUDED.generation`,
		in.FileID, in.StreamIndex, in.Basis.Key, in.Method, string(in.Source), string(in.State), in.Generation,
		in.IntegratedLufs, in.TruePeakDbtp, in.LraLu, in.ThresholdLufs, in.GainDb, in.ReferenceLufs,
		in.CoverageComplete, in.Codec, in.ChannelLayout, rejectReason,
		crossCheckToleranceLu, methodVersion, crossCheckReason,
	)
	return err
}
