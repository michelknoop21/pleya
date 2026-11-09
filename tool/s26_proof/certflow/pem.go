package certflow

import (
	"crypto/x509"
	"encoding/pem"
	"testing"
)

func pemChain(chain [][]byte) []byte {
	var out []byte
	for _, d := range chain {
		out = append(out, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: d})...)
	}
	return out
}

func pemKey(t testing.TB, n *NAS) []byte {
	der, err := x509.MarshalECPrivateKey(n.tlsKey)
	if err != nil {
		t.Fatal(err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: der})
}

// PEMChain and PEMKey are used by other proof packages that need a NAS TLS
// certificate on disk or in memory.
func PEMChain(chain [][]byte) []byte     { return pemChain(chain) }
func PEMKey(t testing.TB, n *NAS) []byte { return pemKey(t, n) }
