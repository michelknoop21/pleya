package api

import (
	"encoding/json"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

// MetadataField en MetadataFields zijn uitsluitend de expliciete wirevormen van
// de zes geopende editorvelden, onafhankelijk van het interne catalogusmodel.
type MetadataField struct {
	Value  json.RawMessage `json:"value"`
	Source string          `json:"source"`
	Locked bool            `json:"locked"`
}
type MetadataFields struct {
	ItemID string                   `json:"item_id"`
	Fields map[string]MetadataField `json:"fields"`
}

func mapMetadataFields(in catalog.MetadataFields) MetadataFields {
	out := MetadataFields{ItemID: in.ItemID.String(), Fields: make(map[string]MetadataField, 6)}
	for _, name := range []string{"title", "year", "summary", "genres", "content_rating", "people"} {
		field := in.Fields[name]
		out.Fields[name] = MetadataField{Value: field.Value, Source: field.Source, Locked: field.Locked}
	}
	return out
}
