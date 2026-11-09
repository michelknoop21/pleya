module github.com/edde746/plezy/tool/s26_proof

go 1.26.0

require (
	github.com/hashicorp/yamux v0.1.2
	github.com/miekg/dns v1.1.62
	golang.org/x/crypto v0.58.0
	golang.org/x/time v0.16.0
)

require (
	github.com/go-jose/go-jose/v4 v4.1.4 // indirect
	github.com/letsencrypt/challtestsrv v1.4.2 // indirect
	github.com/letsencrypt/pebble/v2 v2.10.1 // indirect
	golang.org/x/mod v0.24.0 // indirect
	golang.org/x/net v0.60.0 // indirect
	golang.org/x/sync v0.14.0 // indirect
	golang.org/x/sys v0.49.0 // indirect
	golang.org/x/tools v0.33.0 // indirect
)

tool (
	github.com/letsencrypt/pebble/v2/cmd/pebble
	github.com/letsencrypt/pebble/v2/cmd/pebble-challtestsrv
)
