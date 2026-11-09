package players

import (
	"crypto/ed25519"
	"net"
	"net/url"
	"reflect"
	"strings"
	"testing"
	"unsafe"

	"github.com/miekg/dns"

	"github.com/edde746/plezy/tool/s26_proof/certflow"
)

type neturl = url.URL

func parseURL(s string) (*url.URL, error) { return url.Parse(s) }

func identityOf(n *certflow.NAS) ed25519.PrivateKey {
	v := reflect.ValueOf(n).Elem().FieldByName("identity")
	return *(*ed25519.PrivateKey)(unsafe.Pointer(v.UnsafeAddr()))
}

// startRebindingDNS answers <a-b-c-d>.<hash>.<domain> with the embedded IP,
// except private and loopback addresses, which it drops like a router with
// DNS rebinding protection.
func startRebindingDNS(t *testing.T) string {
	pc, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	srv := &dns.Server{PacketConn: pc, Handler: dns.HandlerFunc(func(w dns.ResponseWriter, q *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(q)
		name := q.Question[0].Name
		ip := net.ParseIP(strings.ReplaceAll(strings.SplitN(name, ".", 2)[0], "-", "."))
		if ip != nil && !(ip.IsPrivate() || ip.IsLoopback()) && q.Question[0].Qtype == dns.TypeA {
			m.Answer = append(m.Answer, &dns.A{Hdr: dns.RR_Header{Name: name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 60}, A: ip})
		} else {
			m.Rcode = dns.RcodeNameError
		}
		w.WriteMsg(m)
	})}
	go srv.ActivateAndServe()
	t.Cleanup(func() { srv.Shutdown() })
	return pc.LocalAddr().String()
}
