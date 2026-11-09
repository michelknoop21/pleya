package relay

import (
	"testing"

	"github.com/edde746/plezy/tool/s26_proof/certflow"
)

// mustRegister links n to an account named after its hash, with the
// proof-of-possession handshake.
func mustRegister(t testing.TB, c *certflow.Central, n *certflow.NAS) {
	t.Helper()
	if err := n.RegisterWith(c, "account-"+n.Hash()); err != nil {
		t.Fatalf("register: %v", err)
	}
}
