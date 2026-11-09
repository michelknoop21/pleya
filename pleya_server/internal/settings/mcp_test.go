package settings

import (
	"encoding/json"
	"testing"
)

func TestMCPBooleanIsStrictAndDefaultsOff(t *testing.T) {
	if newValues(Base{}, nil).MCPEnabled() {
		t.Fatal("MCP standaard aan")
	}
	for _, value := range []bool{false, true} {
		raw, err := Encode(value)
		if err != nil {
			t.Fatal(err)
		}
		got, err := Parse(KeyMCPEnabled, raw)
		if err != nil || got != value {
			t.Fatalf("bool%v = %v %v", value, got, err)
		}
	}
	for _, raw := range []string{`null`, `"true"`, `1`, `[]`, `{}`} {
		if _, err := Parse(KeyMCPEnabled, json.RawMessage(raw)); err == nil {
			t.Fatalf("ongeldige boolean %s geaccepteerd", raw)
		}
	}
}
