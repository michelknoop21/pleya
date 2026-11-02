package api

import (
	"encoding/json"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

func TestMetadataOverridesWireMapperKeepsTheClosedContract(t *testing.T) {
	item := id.New()
	in := catalog.MetadataFields{ItemID: item, Fields: map[string]catalog.MetadataField{
		"summary":         {Value: json.RawMessage(`""`), Source: catalog.SourceManual, Locked: true},
		"future_internal": {Value: json.RawMessage(`"internal"`), Source: "internal"},
	}}
	out := mapMetadataFields(in)
	if out.ItemID != item.String() || len(out.Fields) != 6 {
		t.Fatalf("wiregrens: %+v", out)
	}
	if _, ok := out.Fields["future_internal"]; ok {
		t.Fatal("intern toekomstveld naar protocol gelekt")
	}
	if got := out.Fields["summary"]; string(got.Value) != `""` || got.Source != "manual" || !got.Locked {
		t.Fatalf("expliciet leeg/bron/lock verloren: %+v", got)
	}
	raw, err := json.Marshal(out)
	if err != nil {
		t.Fatal(err)
	}
	var wire map[string]any
	if err = json.Unmarshal(raw, &wire); err != nil {
		t.Fatal(err)
	}
	if got, ok := wire["item_id"].(string); !ok || got != item.String() {
		t.Fatalf("wire-ID is geen string: %s", raw)
	}
	if len(wire) != 2 {
		t.Fatalf("onverwachte wirevelden: %s", raw)
	}
}
