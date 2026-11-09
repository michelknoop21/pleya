# S26 technische proef (cloud-deel)

Proefcode voor stap 2 van [S26 Pleya Server delen](../../docs/plans/2026-11-09-pleya-server-delen/PLAN.md). Geen productcode: niets hier wordt door de app, Pleya Server of de relay-stack geïmporteerd. Rapport: [docs/qa/2026-11-09-s26-stap2-cloudproef.md](../../docs/qa/2026-11-09-s26-stap2-cloudproef.md).

| Pakket | Wat het bewijst |
| --- | --- |
| `proofenv` | Start Pebble (de test-CA van Let's Encrypt) en `pebble-challtestsrv` lokaal. |
| `certflow` | De NAS maakt sleutel en CSR; de centrale dienst ziet alleen publieke gegevens en doet DNS-01. |
| `relay` | Een dunne TLS-passthrough-relay met ondertekende registratie, als terugval naast frp. |
| `frpeval` | frp in de `https`-stand geeft TLS door; een serverplugin dwingt per server de eigen naam af. |
| `players` | ffmpeg en mpv over de directe route, de relay en een CONNECT-proxy; certificaatcontrole en redirects. |

## Draaien

```bash
cd tool/s26_proof
go test ./... -count=1 -v
```

Nodig: Go 1.26 (wordt automatisch opgehaald), en voor `players` ffmpeg met libx264 en mpv. Met `dart` op het PATH draait de redirecttest ook tegen `dart:io`. `frpeval` slaat over zonder `FRP_BIN`, een map met `frps` en `frpc`. frp bouwt niet rechtstreeks uit de modulecache omdat de dashboard-assets ontbreken:

```bash
go mod download github.com/fatedier/frp@v0.72.0
cp -r "$(go env GOMODCACHE)/github.com/fatedier/frp@v0.72.0" /tmp/frpsrc && chmod -R u+w /tmp/frpsrc
for d in frps frpc; do mkdir -p /tmp/frpsrc/web/$d/dist && echo '<html></html>' > /tmp/frpsrc/web/$d/dist/index.html; done
(cd /tmp/frpsrc && go build -o /tmp/frpbin/frps ./cmd/frps && go build -o /tmp/frpbin/frpc ./cmd/frpc)
FRP_BIN=/tmp/frpbin go test ./frpeval/ -v
```

De tests maken alleen verbindingen op 127.0.0.1 en raken geen echte DNS, CA of gebruikersdata.
