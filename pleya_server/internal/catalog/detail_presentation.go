package catalog

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"math"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/jackc/pgx/v5"
)

// ExternalRating is source-attributed evidence, never the user's own rating.
// Source is unknown-safe. Only bounded numeric scales are published.
type ExternalRating struct {
	Source    string  `json:"source"`
	Value     float64 `json:"value"`
	MaxValue  float64 `json:"max_value"`
	VoteCount int     `json:"vote_count,omitempty"`
}

type CreditPortrait struct {
	Name      string `json:"name"`
	Role      string `json:"role"`
	Character string `json:"character,omitempty"`
	Ref       string `json:"ref"`
	ID        *id.ID `json:"id,omitempty"`
}

// DetailPresentation is internal publication data, not a wire response.
// References are fetched only through the existing fixed-host provider client.
type DetailPresentation struct {
	Provider   string           `json:"provider"`
	ExternalID string           `json:"external_id"`
	LogoRef    string           `json:"logo_ref,omitempty"`
	LogoID     *id.ID           `json:"logo_id,omitempty"`
	Portraits  []CreditPortrait `json:"portraits,omitempty"`
	Ratings    []ExternalRating `json:"ratings,omitempty"`
}

func LogoKind(ref string) string {
	sum := sha256.Sum256([]byte(ref))
	return "logo:" + hex.EncodeToString(sum[:])
}

func PortraitKind(ref string) string {
	sum := sha256.Sum256([]byte(ref))
	return "portrait:" + hex.EncodeToString(sum[:])
}

func validExternalRating(r ExternalRating) bool {
	return r.Source != "" && len(r.Source) <= 32 && !math.IsNaN(r.Value) && !math.IsInf(r.Value, 0) &&
		!math.IsNaN(r.MaxValue) && !math.IsInf(r.MaxValue, 0) && r.MaxValue > 0 && r.MaxValue <= 100 &&
		r.Value >= 0 && r.Value <= r.MaxValue && r.VoteCount >= 0
}

func publishDetailPresentation(ctx context.Context, tx pgx.Tx, itemID id.ID, candidate MetadataCandidate, presentation *DetailPresentation) error {
	var raw []byte
	if presentation != nil && candidate.Provider != "" && canonicalMetadataID(candidate.ExternalID) {
		copy := *presentation
		copy.Provider, copy.ExternalID = candidate.Provider, candidate.ExternalID
		copy.Ratings = nil
		for _, r := range presentation.Ratings {
			if validExternalRating(r) && len(copy.Ratings) < 8 {
				copy.Ratings = append(copy.Ratings, r)
			}
		}
		var err error
		raw, err = json.Marshal(copy)
		if err != nil {
			return err
		}
	}
	_, err := tx.Exec(ctx, `UPDATE media_items SET detail_presentation=$2, updated_at=GREATEST(updated_at + interval '1 microsecond', clock_timestamp()) WHERE id=$1 AND detail_presentation IS DISTINCT FROM $2`, itemID, raw)
	return err
}

func attachDetailPresentation(item *Item, raw, rawAssets []byte, provider, externalID, peopleSource *string) {
	item.LogoID = nil
	item.ExternalRatings = nil
	// Never trust a portrait copied through an older/manual people JSON layer.
	for i := range item.People {
		item.People[i].PortraitID = nil
	}
	if provider == nil || externalID == nil || !canonicalMetadataID(*externalID) {
		return
	}
	var p DetailPresentation
	if json.Unmarshal(raw, &p) != nil || p.Provider != *provider || p.ExternalID != *externalID {
		return
	}
	var assets map[string]struct {
		Kind     string `json:"kind"`
		Provider string `json:"provider"`
		Ref      string `json:"ref"`
	}
	if json.Unmarshal(rawAssets, &assets) != nil {
		assets = nil
	}
	if p.LogoID != nil {
		a := assets[p.LogoID.String()]
		if a.Kind == LogoKind(p.LogoRef) && a.Provider == p.Provider && a.Ref == p.LogoRef {
			item.LogoID = p.LogoID
		}
	}
	for _, r := range p.Ratings {
		if validExternalRating(r) && len(item.ExternalRatings) < 8 {
			item.ExternalRatings = append(item.ExternalRatings, r)
		}
	}
	if peopleSource == nil || *peopleSource != p.Provider {
		return
	}
	for i := range item.People {
		person := &item.People[i]
		for _, portrait := range p.Portraits {
			if portrait.ID != nil && person.Name == portrait.Name && person.Role == portrait.Role && person.Character == portrait.Character && assets[portrait.ID.String()].Kind == PortraitKind(portrait.Ref) && assets[portrait.ID.String()].Provider == p.Provider && assets[portrait.ID.String()].Ref == portrait.Ref {
				person.PortraitID = portrait.ID
				break
			}
		}
	}
}
