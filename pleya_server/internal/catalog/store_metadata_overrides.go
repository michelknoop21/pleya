package catalog

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/jackc/pgx/v5"
)

var ErrInvalidOverride = errors.New("ongeldige metadatacorrectie")
var ErrOverrideFallback = errors.New("actuele bron niet bewezen; lock behouden")

var editableMetadataFields = []string{"title", "year", "summary", "genres", "content_rating", "people"}

// MetadataField toont effectieve waarde en aantoonbare herkomst; manual is de lock.
type MetadataField struct {
	Value  json.RawMessage
	Source string
	Locked bool
}
type MetadataFields struct {
	ItemID id.ID
	Fields map[string]MetadataField
}

func metadataField(field string) bool {
	for _, f := range editableMetadataFields {
		if f == field {
			return true
		}
	}
	return false
}

// ValidateMetadataOverrides controleert dezelfde gesloten types op wire en store.
// null wist alleen het optionele jaar. Lege arrays/strings zijn expliciete locks.
func ValidateMetadataOverrides(fields map[string]json.RawMessage) error {
	if len(fields) == 0 {
		return ErrInvalidOverride
	}
	for field, raw := range fields {
		if !metadataField(field) {
			return ErrInvalidOverride
		}
		switch field {
		case "year":
			if string(raw) == "null" {
				continue
			}
			var year int
			if json.Unmarshal(raw, &year) != nil || year < 1 || year > 9999 {
				return ErrInvalidOverride
			}
		case "genres":
			var values []string
			if string(raw) == "null" || json.Unmarshal(raw, &values) != nil || len(values) > 50 {
				return ErrInvalidOverride
			}
			for _, v := range values {
				if strings.TrimSpace(v) == "" || utf8.RuneCountInString(v) > 100 {
					return ErrInvalidOverride
				}
			}
		case "people":
			var values []map[string]json.RawMessage
			if string(raw) == "null" || json.Unmarshal(raw, &values) != nil || len(values) > 100 {
				return ErrInvalidOverride
			}
			for _, v := range values {
				for k := range v {
					if k != "name" && k != "role" && k != "character" {
						return ErrInvalidOverride
					}
				}
				for _, k := range []string{"name", "role", "character"} {
					r, ok := v[k]
					if !ok && k == "character" {
						continue
					}
					var text string
					if k == "role" {
						var role string
						if json.Unmarshal(r, &role) != nil || (role != "actor" && role != "director" && role != "writer") {
							return ErrInvalidOverride
						}
					}
					if !ok || string(r) == "null" || json.Unmarshal(r, &text) != nil || (k != "character" && strings.TrimSpace(text) == "") || utf8.RuneCountInString(text) > 200 {
						return ErrInvalidOverride
					}
				}
			}
		default:
			var text string
			max := 20000
			if field == "title" {
				max = 500
			}
			if field == "content_rating" {
				max = 100
			}
			if string(raw) == "null" || json.Unmarshal(raw, &text) != nil || utf8.RuneCountInString(text) > max || (field == "title" && strings.TrimSpace(text) == "") {
				return ErrInvalidOverride
			}
		}
	}
	return nil
}

func readMetadataFields(ctx context.Context, reader itemReader, itemID id.ID) (MetadataFields, map[string]string, error) {
	var valuesRaw, sourcesRaw []byte
	err := reader.QueryRow(ctx, `SELECT jsonb_build_object('title',title,'year',year,'summary',summary,'genres',genres,'content_rating',content_rating,'people',people),metadata_sources FROM media_items WHERE id=$1 AND kind IN ('movie','show')`, itemID).Scan(&valuesRaw, &sourcesRaw)
	if errors.Is(err, pgx.ErrNoRows) {
		return MetadataFields{}, nil, ErrNotFound
	}
	if err != nil {
		return MetadataFields{}, nil, err
	}
	values := map[string]json.RawMessage{}
	sources := map[string]string{}
	if err = json.Unmarshal(valuesRaw, &values); err != nil {
		return MetadataFields{}, nil, err
	}
	if err = json.Unmarshal(sourcesRaw, &sources); err != nil {
		return MetadataFields{}, nil, err
	}
	if sources == nil {
		sources = map[string]string{}
	}
	out := MetadataFields{ItemID: itemID, Fields: map[string]MetadataField{}}
	for _, field := range editableMetadataFields {
		source := sources[field]
		if source == "" {
			source = "unknown"
			if field == "title" || field == "year" {
				source = "scanner"
			}
		}
		out.Fields[field] = MetadataField{Value: values[field], Source: source, Locked: source == SourceManual}
	}
	return out, sources, nil
}
func (s *Store) MetadataFields(ctx context.Context, itemID id.ID) (MetadataFields, error) {
	out, _, err := readMetadataFields(ctx, s.pool, itemID)
	return out, err
}

// SetMetadataOverrides verandert geen kandidaat of applied-identiteit. De itemlock
// serialiseert edits en guarded publicaties; een late runner respecteert de lock.
func (s *Store) SetMetadataOverrides(ctx context.Context, itemID id.ID, fields map[string]json.RawMessage) error {
	if err := ValidateMetadataOverrides(fields); err != nil {
		return err
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err = lockMetadataItem(ctx, tx, itemID); err != nil {
		return err
	}
	effective, sources, err := readMetadataFields(ctx, tx, itemID)
	if err != nil {
		return err
	}
	for field, value := range fields {
		old := effective.Fields[field]
		if field == "title" && !old.Locked {
			if _, err = tx.Exec(ctx, `UPDATE media_items SET metadata_field_layers=jsonb_set(metadata_field_layers,'{scanner}',coalesce(metadata_field_layers->'scanner','{}'::jsonb)||jsonb_build_object('sort_title',sort_title),true) WHERE id=$1`, itemID); err != nil {
				return err
			}
		}
		if !old.Locked && old.Source != "unknown" {
			// Vul uitsluitend ontbrekend legacy-bronbewijs aan. Een bestaande
			// waarde, ook expliciet null, is de nieuwere werkelijke bronobservatie.
			if _, err = tx.Exec(ctx, `UPDATE media_items SET metadata_field_layers=jsonb_set(metadata_field_layers,ARRAY[$2],coalesce(metadata_field_layers->$2,'{}'::jsonb)||jsonb_build_object($3::text,$4::jsonb),true) WHERE id=$1 AND NOT coalesce((metadata_field_layers->$2) ? $3,false)`, itemID, old.Source, field, old.Value); err != nil {
				return err
			}
		}
		if err = writeMetadataValue(ctx, tx, itemID, field, value); err != nil {
			return err
		}
		sources[field] = SourceManual
	}
	raw, _ := json.Marshal(sources)
	if _, err = tx.Exec(ctx, `UPDATE media_items SET metadata_sources=$2,updated_at=GREATEST(updated_at+interval '1 microsecond',clock_timestamp()) WHERE id=$1`, itemID, raw); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func writeMetadataValue(ctx context.Context, tx pgx.Tx, itemID id.ID, field string, value json.RawMessage) error {
	if !metadataField(field) {
		return ErrInvalidOverride
	}
	expression := `$2::jsonb #>> '{}'`
	switch field {
	case "year":
		expression = `($2::jsonb #>> '{}')::integer`
	case "genres":
		expression = `CASE WHEN $2::jsonb='null'::jsonb THEN NULL ELSE ARRAY(SELECT jsonb_array_elements_text($2::jsonb)) END`
	case "people":
		expression = `NULLIF($2::jsonb,'null'::jsonb)`
	}
	extra := ""
	if field == "title" {
		extra = `,sort_title=NULL`
	}
	_, err := tx.Exec(ctx, `UPDATE media_items SET `+field+`=`+expression+extra+`,updated_at=GREATEST(updated_at+interval '1 microsecond',clock_timestamp()) WHERE id=$1`, itemID, value)
	return err
}

func (s *Store) DeleteMetadataOverride(ctx context.Context, itemID id.ID, field string) error {
	if !metadataField(field) {
		return ErrInvalidOverride
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err = lockMetadataItem(ctx, tx, itemID); err != nil {
		return err
	}
	effective, sources, err := readMetadataFields(ctx, tx, itemID)
	if err != nil {
		return err
	}
	if !effective.Fields[field].Locked {
		return tx.Commit(ctx)
	}
	var raw []byte
	var nfoSafe bool
	if err = tx.QueryRow(ctx, `SELECT metadata_field_layers,metadata_nfo_safe FROM media_items WHERE id=$1`, itemID).Scan(&raw, &nfoSafe); err != nil {
		return err
	}
	layers := map[string]map[string]json.RawMessage{}
	if err = json.Unmarshal(raw, &layers); err != nil {
		return err
	}
	source := ""
	var value json.RawMessage
	for _, src := range []string{ProviderTMDB, SourceNFO, "scanner"} {
		v, known := layers[src][field]
		if !known {
			continue
		}
		if src == SourceNFO && !nfoSafe {
			return ErrOverrideFallback
		}
		if string(v) == "null" && field != "year" {
			continue
		}
		source, value = src, v
		break
	}
	if source == "" {
		// Een geslaagde volledige bronronde bewijst ook expliciet afwezig. Zonder
		// die ronde blijft een oude onbekende/manual waarde veilig gelockt.
		_, providerKnown := layers[ProviderTMDB][field]
		_, nfoKnown := layers[SourceNFO][field]
		if field != "title" && field != "year" && providerKnown && nfoKnown && nfoSafe {
			source = SourceNone
			value = json.RawMessage("null")
		} else {
			return ErrOverrideFallback
		}
	}
	if err = writeMetadataValue(ctx, tx, itemID, field, value); err != nil {
		return err
	}
	if field == "title" && source == "scanner" {
		if _, err = tx.Exec(ctx, `UPDATE media_items SET sort_title=metadata_field_layers->'scanner'->>'sort_title' WHERE id=$1`, itemID); err != nil {
			return err
		}
	}
	sources[field] = source
	raw, _ = json.Marshal(sources)
	if _, err = tx.Exec(ctx, `UPDATE media_items SET metadata_sources=$2 WHERE id=$1`, itemID, raw); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// rememberMetadataLayer bewaart alleen werkelijk gelezen bronwaarden. Het draait
// binnen dezelfde itemlock/generatieguard als de effectieve publicatie.
func rememberMetadataLayer(ctx context.Context, tx pgx.Tx, itemID id.ID, source string, d MetadataDetails) error {
	if source == SourceManual {
		return nil
	}
	fields := map[string]any{"summary": nil, "genres": nil, "content_rating": nil, "people": nil}
	if d.Summary != "" {
		fields["summary"] = d.Summary
	}
	if len(d.Genres) > 0 {
		fields["genres"] = d.Genres
	}
	if d.ContentRating != "" {
		fields["content_rating"] = d.ContentRating
	}
	if len(d.People) > 0 {
		fields["people"] = d.People
	}
	raw, _ := json.Marshal(fields)
	_, err := tx.Exec(ctx, `UPDATE media_items SET metadata_field_layers=jsonb_set(metadata_field_layers,ARRAY[$2],$3::jsonb,true),metadata_nfo_safe=CASE WHEN $2='nfo' THEN true ELSE metadata_nfo_safe END WHERE id=$1`, itemID, source, raw)
	return err
}

// CommitSidecar heeft dezelfde item/generatiegrens zonder een providerkandidaat
// te verzinnen. Een afwezige of onleesbare NFO mag geen oude unlockbron blijven.
func (s *Store) CommitSidecar(ctx context.Context, target MetadataTarget, details *MetadataDetails) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err = lockMetadataItem(ctx, tx, target.ID); err != nil {
		return err
	}
	var actual *time.Time
	if err = tx.QueryRow(ctx, `SELECT (SELECT updated_at FROM metadata_candidates WHERE item_id=$1)`, target.ID).Scan(&actual); err != nil {
		return err
	}
	if (actual == nil) != (target.CandidateUpdatedAt == nil) || (actual != nil && !actual.Equal(*target.CandidateUpdatedAt)) {
		return ErrMetadataSuperseded
	}
	if target.SidecarReadError != nil {
		if _, err = tx.Exec(ctx, `UPDATE media_items SET metadata_nfo_safe=false WHERE id=$1`, target.ID); err != nil {
			return err
		}
	} else if details != nil {
		if err = applyMetadata(ctx, tx, target.ID, SourceNFO, *details); err != nil {
			return err
		}
	} else {
		if err = rememberMetadataLayer(ctx, tx, target.ID, SourceNFO, MetadataDetails{}); err != nil {
			return err
		}
	}
	if _, err = tx.Exec(ctx, `UPDATE media_items SET sidecar_checked_at=now() WHERE id=$1`, target.ID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
