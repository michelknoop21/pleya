package certflow

import (
	"testing"
)

// mustRegister links n to an account named after its hash, with the
// proof-of-possession handshake.
func mustRegister(t testing.TB, c *Central, n *NAS) {
	t.Helper()
	if err := n.RegisterWith(c, "account-"+n.Hash()); err != nil {
		t.Fatalf("register: %v", err)
	}
}
