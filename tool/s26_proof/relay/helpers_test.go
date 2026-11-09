package relay

import (
	"crypto/ed25519"
	"crypto/tls"
	"net"
	"reflect"
	"testing"
	"unsafe"

	"github.com/edde746/plezy/tool/s26_proof/certflow"
)

// identityOf reads the NAS identity key for the agent. In the product the
// agent and the key live in the same process; certflow keeps the field private
// so no other proof package can hand it around by accident.
func identityOf(n *certflow.NAS) ed25519.PrivateKey {
	v := reflect.ValueOf(n).Elem().FieldByName("identity")
	return *(*ed25519.PrivateKey)(unsafe.Pointer(v.UnsafeAddr()))
}

func tlsListener(l net.Listener, s *server) net.Listener { return tls.NewListener(l, s.tls) }

var _ = testing.Short
