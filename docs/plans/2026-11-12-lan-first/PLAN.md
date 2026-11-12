# Plan: LAN first voor Pleya Server, versleuteld op het thuisnetwerk

**Roadmap:** C-07 / S24.7. Roadmap deviation: opdracht Michel van 12 november 2026 ("Pak nu LAN first op voor Pleya Server: maak een plan met roadmap-ID voor binding buiten 127.0.0.1 met TLS op de NAS, nog niets uitrollen"). **Status:** plan, wacht op de besluiten in hoofdstuk 11. Geen code, geen protocolvenster, geen deploy, geen wijziging op de NAS. **Auteur:** Michel Knoop.

Aanleiding: op 11 november 2026 stokte een film op de Apple TV nadat de Cloudflare Tunnel wegviel (`pleya-tunnel` logde `http2: stream closed`). De authenticatiekant daarvan is apart opgelost op branch `fix/mpv-stream-session` (PR #687, mpv speelt op de streamsessie van DEC-051, nog niet op `main`). Dit plan haalt de tunnel uit het thuispad: een toestel thuis praat rechtstreeks met de NAS, versleuteld, en een haperende tunnel stopt het afspelen thuis niet meer.

---

## 1. Hoe het nu bedraad is

Vastgesteld uit de repo op `origin/main` (`08ccff120`). Wat alleen op de NAS te zien is, staat er apart bij.

### 1.1 De feiten

| # | Feit | Bron |
| --- | --- | --- |
| F1 | De server luistert **in de container** op `:8080`, dus op alle interfaces van de netwerknamespace van die container. Dat is ook de standaard in de code. | `pleya_server/compose.yaml:31`, `pleya_server/internal/config/config.go:112` en `:184` |
| F2 | `127.0.0.1` staat alleen in de **poortpublicatie op de host**: `"${PLEYA_SERVER_BIND:-127.0.0.1}:${PLEYA_SERVER_HOST_PORT:-8832}:8080"`. Docker luistert daarmee op de loopback van de NAS, poort 8832, en stuurt door naar 8080 in de container. | `pleya_server/compose.yaml:22-23` |
| F3 | Geen `network_mode` in beide stacks. Pleya Server en Postgres zitten in een eigen bridgenetwerk met vaste naam `pleya-server_default`. | `pleya_server/compose.yaml:192-203` |
| F4 | `cloudflared` (container `pleya-tunnel`) staat in de relay-stack, hangt aan twee netwerken (`default` en het externe `pleya-server_default`) en bereikt de server als `http://pleya-server:8080` via Docker-DNS op dat bridgenetwerk. De ingress zelf staat in het Cloudflare-dashboard. | `server/docker-compose.yml:33-52` en `:84-96` |
| F5 | De relay zelf publiceert ook alleen op loopback (`127.0.0.1:8831:8080`), met dezelfde redenering. | `server/docker-compose.yml:13-18` |
| F6 | `deploy-nas.sh` controleert `readyz` op `http://127.0.0.1:$port` van de NAS en eindigt met de tekst "Alleen bereikbaar op 127.0.0.1 van de NAS zelf, en dat is opzet." Dat laatste is een `echo`, geen controle. | `pleya_server/deploy-nas.sh:100-112` en `:136` |
| F7 | `/metrics` luistert op `127.0.0.1:9464` **binnen** de container en is dus van buiten de container nergens bereikbaar. | `pleya_server/internal/config/config.go:113`, `pleya_server/cmd/pleya-server/main.go:394-404` |
| F8 | Het operatorrecept voor de tunnel zet `PLEYA_SERVER_TRUSTED_PROXIES=172.18.0.0/16`, het hele bridgebereik. | `docs/pleya-server-operator-remote.md:21-30` |
| F9 | De testinstance gebruikt `127.0.0.1:8833` en een eigen netwerk `10.250.0.0/24`, zonder tunnel. | `pleya_server/README.md:312-321` |
| F10 | Het commentaar bij de publicatie noemt openstellen een bewuste stap uit PS-11, achter een proxy of tunnel. PS-11 is in de masterlijst slice S24 (remote hardening); S24.1 tot en met S24.6 staan op `[x]`. | `pleya_server/compose.yaml:18-21`, `docs/PLEYA-SERVER-MASTERLIST.md` sectie S24 |

### 1.2 Werkt 127.0.0.1 binnen het Docker-netwerk?

Er is geen `127.0.0.1`-binding binnen de Pleya-container. De vraag of `cloudflared` een server bereikt die binnen zijn container op `127.0.0.1` luistert, is dus voor de huidige opstelling niet aan de orde, maar het antwoord is nee: loopback hoort bij één netwerknamespace, en `pleya-tunnel` heeft een eigen namespace. Alleen `network_mode: service:pleya-server` of hostnetwerk zou de loopback delen, en geen van beide wordt gebruikt (F3, F4).

De tunnel werkt omdat de server op `:8080` luistert (F1) en `cloudflared` hem over de bridge bereikt (F4). De `127.0.0.1` uit F2 heeft daar nooit invloed op gehad: hij beperkt alleen wie via de **host** bij poort 8832 komt. Dat zijn processen op de NAS zelf, zoals `deploy-nas.sh` en een `ssh -L`.

### 1.3 Kan de server vandaag al op het LAN bereikbaar zijn?

Twee routes, en de repo kan geen van beide uitsluiten.

1. **Via `.env`.** Zet de productie-`.env` `PLEYA_SERVER_BIND` op `0.0.0.0` of op het LAN-adres, dan staat de API onversleuteld op `http://<nas>:8832`. De operatordoc stelt dat zelf voor bij een mesh-VPN (`docs/pleya-server-operator-remote.md:34`). De deploy merkt het verschil niet: `readyz` op loopback slaagt bij elke binding (F6). Alleen op de NAS te bevestigen.
2. **Via directe routering naar het containeradres.** Docker Engine vóór 28.0 blokkeert niet dat een ander toestel op hetzelfde LAN-segment een route naar het bridgebereik via het NAS-adres legt en dan `http://<container-ip>:8080` rechtstreeks aanspreekt; de publicatie op `127.0.0.1` speelt daarbij geen rol. Engine 28.0 voegde daar een blokkade in de `raw`-tabel voor toe. Welke Engine-versie Container Manager op de NAS draait en of de DSM-firewall dat verkeer tegenhoudt, staat niet in de repo. Alleen op de NAS te bevestigen; zie fase 0.

Voor het risico is één ding wel uit de repo vast te stellen: de volledige API, inclusief login, setup en beheerroutes, staat al publiek op internet via `web.pleya.app` (F4). Openstellen op het LAN voegt dus geen nieuw applicatie-oppervlak toe. Wat het wel verandert: het verkeer gaat buiten Cloudflare om (geen WAF of edge-limieten) en het reist over het LAN, vandaag in klare tekst.

### 1.4 Een gevolg voor vertrouwde proxy's

Met het recept uit F8 telt het hele bridgebereik als vertrouwde proxy, inclusief de gateway (`.1`). Verkeer dat via de Docker-proxy op de host binnenkomt, zoals de loopbackpublicatie, komt in de container binnen met dat gateway-adres als afzender. Als LAN-verkeer op een gepubliceerde poort op de NAS ook zo binnenkomt in plaats van met het echte clientadres, dan is een LAN-client een "vertrouwde proxy". Hij bepaalt dan zelf `X-Forwarded-For` (en daarmee zijn emmer in de login- en refreshlimiet) en `X-Forwarded-Proto` (de `Secure`-vlag). De code die dat beslist: `requestIsSecure` (`pleya_server/internal/api/origin.go:29-45`), `clientAddress` (`pleya_server/internal/api/handlers_refresh.go:239-260`) en `RemoteAddrIsTrustedProxy` (`pleya_server/internal/config/publicurl.go:140`). Of de NAS het clientadres behoudt, en welk bereik en welke `TRUSTED_PROXIES` productie werkelijk heeft, is alleen op de NAS te meten. Het ontwerp in hoofdstuk 5 maakt de LAN-listener daar ongevoelig voor, wat de meting ook uitwijst.

### 1.5 Wat hieruit volgt voor de rest van het plan

- De tunnelroute blijft zoals hij is: plat HTTP op `:8080` binnen `pleya-server_default`. Niets in dit plan raakt F3, F4 of de netwerknaam.
- LAN-toegang komt er als een **tweede, versleutelde listener** met een eigen publicatie op het LAN-adres van de NAS, niet door de bestaande publicatie te verbreden. Plat HTTP op het LAN wordt nooit een route.
- Fase 0 meet eerst de punten die de repo niet kan beantwoorden (1.3 en 1.4), voordat er iets openstaat.

---

## 2. Verhouding tot S26 (Pleya Server delen)

Op branch `claude/happy-brown-l9so1b` (9 november 2026, niet gemerged, geen PR) staat werkpakket C-06 / S26: uitnodigingen, een centrale dienst, een automatisch Pleya-adres met publiek certificaat per server, routekeuze en een relay. Daar staan al besluiten van Michel (besluit 12: eigen nieuw domein voor servernamen, Let's Encrypt, aanvraag bij de Public Suffix List) en een cloudproef met twee bevindingen die hier direct gelden:

- ffmpeg en mpv controleren certificaten standaard niet, en de app zet `tls-verify` voor mpv nergens aan (`lib/mpv/player/player_native.dart`, geen `tls`-optie; headers via `http-header-fields` op regel 189);
- een resolver met DNS-rebindingbescherming breekt een publieke naam die naar een privé-adres wijst.

C-07 is het kleine, thuis-alleen deel daarvan, zonder centrale dienst, accounts of relay, en bruikbaar zolang S26 er niet is. Het is zo gesneden dat S26 stap 5 ("lokaal versleuteld") erop voortbouwt in plaats van het te vervangen: TLS eindigt in de server (zoals S26 voor de relay-passthrough vraagt), de server meldt zijn routes in het contract (een deelverzameling van de vensteraanvraag in S26 hoofdstuk 8), en de app krijgt meerdere adressen per server met dezelfde racelogica. Wat S26 later verandert is de bron van het certificaat (de centrale dienst in plaats van een sidecar op de NAS) en de naamgeving. Wordt S26 eerder gemerged, dan houdt S26 het nummer C-06 en blijft dit C-07.

---

## 3. Doel en grenzen

**Doel.** Thuis spelen Apple TV, iPhone, iPad, Mac en Android rechtstreeks vanaf de NAS via HTTPS met een publiek vertrouwd certificaat. Valt de tunnel weg, dan loopt afspelen thuis door. Buitenshuis verandert er niets.

**Toetsbaar.** Tijdens een film op de Apple TV thuis wordt `pleya-tunnel` gestopt; de film speelt door en de serverlog toont het LAN-adres van de Apple TV als client.

**Buiten scope.** Bereikbaarheid buitenshuis via een eigen poort, relay, uitnodigingen en accounts (allemaal S26). Pleya Web via de LAN-route vanaf `web.pleya.app` (een browser kan niet van origin wisselen zonder CORS en Private Network Access; wie thuis de webclient wil, opent het LAN-adres zelf). IPv6 op het LAN. Plex, Jellyfin en lokale bronnen: hun verbindingsmodel blijft (Unified impact: alleen de Pleya Server-bron krijgt meerdere adressen; de unified bibliotheek merkt alleen dat die bron sneller en stabieler antwoordt).

---

## 4. Certificaat en naam

### 4.1 Aanbeveling

Eén vaste naam, bijvoorbeeld `thuis.<domein>`, met een certificaat van Let's Encrypt via DNS-01, aangevraagd en vernieuwd door een sidecar op de NAS, en een DNS-antwoord dat naar het LAN-adres van de NAS wijst.

- **Uitgifte.** Een `acme.sh`-container in daemonstand (digest gepind, zoals de Postgres-image in `compose.yaml:160`) met de Cloudflare-DNS-plugin. Hij vernieuwt zelf en schrijft `fullchain.pem` en `key.pem` naar een map die `pleya-server` alleen-lezen mount. De server leest het certificaat bij elke handshake via `GetCertificate` en laadt het opnieuw zodra het bestand verandert. Geen herstart, geen handwerk. De binary geeft zelf geen certificaten uit, dus de grens uit architectuur hoofdstuk 15 en de out-of-scope-regel van PS-11 (`docs/pleya-server-architecture.md:2822`) blijven staan.
- **Sleutel.** De privésleutel ontstaat en blijft op de NAS. De Cloudflare-token in `.env` mag alleen DNS van één zone wijzigen. Wie de NAS heeft, kan met die token DNS van die zone overschrijven; daarom het advies om een aparte zone te gebruiken en niet `pleya.app` zelf (besluit B1).
- **DNS.** Het liefst een lokale DNS-regel op de router (of Pi-hole) voor `thuis.<domein>` naar het NAS-adres. Dan staat het thuisadres nergens publiek en speelt rebindingbescherming geen rol. Kan de router dat niet, dan een publiek A-record zonder Cloudflare-proxy naar het privé-adres, met een uitzondering voor de naam in de rebindingbescherming van de router (besluit B2). De cloudproef van S26 (review I1) raadt publieke thuisadressen af voor een product met veel servers; voor één eigen NAS is het lek een privé-adres zonder verdere betekenis, maar het blijft een keuze van Michel.
- **Als DNS faalt.** Dan faalt de LAN-kandidaat snel en kiest de app de tunnel, net als vandaag. Er is geen stille terugval naar plat HTTP.

### 4.2 Afgewezen

| Optie | Waarom niet |
| --- | --- |
| Synology-certificaat uit DSM | DSM vraagt Let's Encrypt aan via HTTP-01 (poort 80 open naar internet) of alleen voor `synology.me`; het bestand moet daarna uit een root-pad van DSM naar de container gekopieerd worden. Dat is handwerk of een kwetsbaar script, en poort 80 openzetten is precies wat de tunnel vermijdt. |
| DSM-reverse-proxy op 443 met DSM-certificaat | Zelfde certificaatprobleem, buffering is in de DSM-interface niet uit te zetten (S24 eist dat voor Range en HLS), en de proxy wordt een vertrouwde proxy met het risico uit 1.4. |
| Eigen CA | tvOS laat een gebruiker geen vertrouwensprofiel installeren zonder MDM of Apple Configurator, en mpv en ExoPlayer hebben elk een eigen trust store. |
| Zelfondertekend met pinning per server | Pinning moet in drie spelerstacks apart (mpv, ExoPlayer, Flutter-HTTP) en kan niet in de browser. S26 maakt dit bewust niet de standaard. |
| Plex-stijl wildcard met IP in de naam via een centrale dienst | Dat is de S26-route en vraagt de centrale dienst, het nieuwe domein en de PSL-aanvraag. Te groot om de thuisstoring op te lossen; C-07 sluit erop aan (hoofdstuk 2). |
| Caddy als TLS-proxy-sidecar | Caddy met DNS-01 voor Cloudflare vraagt een eigen build met module; de proxy wordt een vertrouwde proxy (1.4) en voegt een hop toe. TLS in de server is minder code en past bij S26. |
| Plat HTTP op het LAN | Streamtoken, cookiegeheim en accesstoken in klare tekst (DEC-051, `docs/DECISIONS.md:428`: "transportvertrouwelijkheid op het LAN hoort bij de fase die de server buiten het LAN bereikbaar maakt"). Dit plan sluit dat, het erft het niet. |

---

## 5. Server

**Twee listeners in één proces.** De bestaande listener blijft ongewijzigd (`:8080`, plat, bedient de tunnel en de loopbackpublicatie). Een tweede listener, alleen actief met `PLEYA_SERVER_TLS_ADDR` (voorstel `:8443`), `PLEYA_SERVER_TLS_CERT` en `PLEYA_SERVER_TLS_KEY`, termineert TLS met hetzelfde handler-stuk. Minimaal TLS 1.2. Zonder die variabelen verandert er niets; `httpserver.Server` (`pleya_server/internal/httpserver/server.go:41-75`) krijgt een tweede `http.Server` naast de eerste, en `main.go:409` start hem op dezelfde manier.

**Binding.** In `compose.yaml` verandert niets. Een nieuwe laag `compose.lan.yaml`, naar het voorbeeld van `compose.hwaccel.yaml`, publiceert `${PLEYA_SERVER_LAN_BIND}:${PLEYA_SERVER_LAN_PORT:-8443}:8443`, mount de certificaatmap en bevat de `acme.sh`-sidecar. `deploy-nas.sh` voegt de laag toe als `PLEYA_SERVER_LAN_BIND` in `.env` staat, zoals het nu `compose.hwaccel.yaml` toevoegt bij `/dev/dri` (`deploy-nas.sh:89-95`). `PLEYA_SERVER_LAN_BIND` is het IPv4-adres van de NAS op het LAN, nooit `0.0.0.0`: bij `0.0.0.0` kan Docker ook op IPv6 publiceren, en een globaal IPv6-adres van de NAS is van internet bereikbaar als de router inkomend IPv6 doorlaat. Bridge blijft; hostnetwerk zou `:8080` plat op alle interfaces van de NAS zetten en de Docker-DNS-naam voor de tunnel weghalen.

**De LAN-listener gelooft geen forwarded-headers.** Een aanvraag op de TLS-listener komt altijd rechtstreeks van een client. De listener zet dat in de context van de aanvraag, en de drie plekken uit 1.4 lezen het via één helper: op die listener is `RemoteAddrIsTrustedProxy` altijd onwaar. Daarmee maakt het niet uit of Docker het clientadres behoudt (1.4): in het slechtste geval delen LAN-clients één limietemmer, maar niemand kiest zijn eigen adres of `Secure`-vlag. Los daarvan is het advies om `TRUSTED_PROXIES` in productie te versmallen van het hele bereik naar het vaste adres van `pleya-tunnel` (besluit B6).

**Cookies en origin.** Op de TLS-listener is `r.TLS` gezet, dus `requestIsSecure` is waar en zowel het refreshcookie als het streamcookie krijgen `Secure` (`handlers_stream_credentials.go:108`). Cookies zijn host-only, dus de LAN-naam en `web.pleya.app` hebben elk hun eigen cookies. De webclient op `https://thuis.<domein>:8443` is same-origin met zijn API; `WEB_ORIGIN` en `CORS_ORIGINS` hoeven niet te veranderen.

**Streamsessies.** De streamsessie is serverstaat. De native speler stuurt het geheim zelf als `Cookie`-header mee (`lib/services/pleya_server_client/parts/stream_session.dart` op `fix/mpv-stream-session`), dus een sessie die via de tunnel is geopend, geldt ook op de LAN-naam en andersom. Een wissel van route midden in een film vraagt geen nieuwe sessie. Dit leunt op PR #687; die moet eerst op `main` staan.

**Wat op loopback blijft.** `/metrics` (F7). De loopbackpublicatie op 8832 blijft voor `deploy-nas.sh` en beheer via ssh. Beheerroutes blijven op rol afgeschermd (`authorize.go`) en zijn al publiek via de tunnel; ze apart op loopback zetten zou ook de beheerschermen in Pleya Web via `web.pleya.app` breken en is geen onderdeel van dit plan.

**De route melden.** Nieuw veld in `GET /server` (klasse `authenticated`, `docs/pleya-protocol/v1/openapi.yaml:991`), bijvoorbeeld `routes: [{url, kind: "lan"}]`, gevuld uit `PLEYA_SERVER_LAN_URL` (`https://thuis.<domein>:8443`). Niet in `GET /info`: dat is publiek en via de tunnel van internet op te vragen, en een thuisadres hoort daar niet. Alleen `https`-adressen worden gemeld. Dit is een protocolwijziging en vraagt een venster (besluit B5); de vorm sluit aan op S26 hoofdstuk 8 ("aangeboden routes met type"), zodat S26 het veld uitbreidt in plaats van vervangt.

---

## 6. App

**Meer adressen per server.** `PleyaServerConnection` heeft nu één `baseUrl` (`lib/connection/connection.dart:670`) en `normaliseBaseUrl` plakt `http://` voor een adres zonder schema (`lib/services/pleya_server_auth_service.dart:62`). Het krijgt `baseUrls` zoals `JellyfinConnection` (`connection.dart:234`, met backfill bij het inlezen). De gemelde LAN-route komt erbij na elke geslaagde `GET /server`; het door de gebruiker ingevoerde adres blijft staan.

**Keuze.** Hergebruik `raceEndpointCandidates` (`lib/utils/endpoint_race.dart:35`) en `FailoverHttpClient` (`lib/utils/failover_http_client.dart:32`), zoals Plex en Jellyfin al doen. De laatst werkende route krijgt de voorsprong (`preferredEndpointHeadStart` 300 ms, `preferredEndpointProbe` 1,5 s, race 2 s in `lib/utils/media_server_timeouts.dart:30-41`). Buitenshuis kost een dode LAN-route daardoor hooguit 300 ms bij de start, niet de volle probe. Bij gelijke bereikbaarheid wint de LAN-route.

**Eerst identiteit, dan credentials.** Een kandidaat krijgt pas een token nadat `GET /info` daar dezelfde `server.id` geeft als `serverId` van de verbinding (`connection.dart`, veld `serverId`). Met een geldig certificaat voor de naam is nabootsen al lastig; de id-controle vangt het geval dat de naam na een adreswissel bij een andere Pleya Server uitkomt. Een gemelde route met `http://` wordt genegeerd.

**Speler.** mpv krijgt `tls-verify=yes` (met de systeemtrust of een CA-bundel, afhankelijk van de MPVKit-backend) voor elke `https`-stream van Pleya Server. Zonder dat beschermt TLS op het LAN alleen tegen meelezen, niet tegen iemand die zich met ARP-spoofing tussen Apple TV en NAS zet. Dezelfde instelling voor Plex en Jellyfin is de losse hotfix uit de S26-cloudproef en blijft daar een apart besluit (B7). ExoPlayer en `dart:io` controleren standaard; dat wordt per stack in een test vastgelegd.

**Wisselen tijdens het afspelen.** Een lopende stream blijft op zijn route. Valt de LAN-route weg (thuis weggaan met de iPhone), dan opent de speler de film opnieuw via de volgende route op dezelfde positie, met het bestaande heropenpatroon (`reopenAt` in `lib/screens/video_player/parts/episode_navigation.dart:494-880`). Een betere route geldt alleen voor nieuwe aanvragen; de app springt niet midden in een film van tunnel naar LAN. Kijkstatus en voortgang gaan via de API en dus via `FailoverHttpClient`; muterende aanvragen worden niet blind herhaald op een andere route.

**Downloads.** Een download die via de LAN-route start, loopt bij wegvallen op dezelfde manier door via de volgende route; de digestcontrole uit S23.3 blijft gelden.

---

## 7. Beveiliging

**Dreigingsmodel thuis.** Andere toestellen en gasten op hetzelfde netwerk, een besmet IoT-apparaat, iemand op de gast-wifi als die niet gescheiden is. Zij kunnen meelezen, ARP-spoofen en de server rechtstreeks aanspreken.

| Dreiging | Maatregel | Waar bewezen |
| --- | --- | --- |
| Meelezen van token, streamcookie of wachtwoord | Alleen HTTPS op het LAN; geen platte LAN-route in `routes`; app negeert `http://`-routes | Go-test op `routes`, Dart-test op de filter |
| Man-in-the-middle met eigen certificaat | Publiek certificaat; `tls-verify` aan in mpv; ExoPlayer en `dart:io` standaard | Spelertest met vals en met geldig-maar-ander certificaat (zoals S26 `players`) |
| Credentials naar het verkeerde toestel na een adreswissel | `server.id`-controle vóór het eerste token | Dart-test met een tweede fake server op het adres |
| Zelf `X-Forwarded-*` zetten | LAN-listener gelooft geen forwarded-headers | Go-test met negatieve controle (hoofdstuk 9) |
| Brute force op login buiten Cloudflare om | Bestaande limieten per naam en per adres (S24.2); op de LAN-listener het echte adres | Bestaande `limiter_test.go`, plus één test op de LAN-listener |
| DNS-rebinding van een webpagina naar de NAS | De server bedient alleen bekende `Host`-namen op de LAN-listener (de LAN-naam en het eigen adres), anders 421; cookies zijn host-only en `SameSite=Strict` | Go-test met een vreemde `Host` |
| Platte API via direct routeren naar de bridge (1.3) | Meting in fase 0; zo nodig een DSM-firewallregel of een Docker-upgrade | Negatieve controle vanaf een tweede toestel, door Michel |
| Lekken van het thuisadres | Route alleen in `GET /server` achter authenticatie; DNS bij voorkeur alleen lokaal | Contracttest op `/info` zonder `routes` |
| Diefstal van de DNS-token van de NAS | Token alleen DNS-edit op één aparte zone | Instelling, controleerbaar in het Cloudflare-dashboard |

**Authenticatie verandert niet.** Zelfde tokens, sessies, rollen en limieten; alleen de transportlaag en de keuze van het adres zijn nieuw.

**Adversariële review (vereist volgens AGENTS.md voor authenticatie en blootstelling), moet minstens nagaan:**

1. dat de platte listener en zijn publicatie niet zijn verbreed, ook niet via een standaardwaarde in `compose.yaml` of `deploy-nas.sh`;
2. dat de TLS-listener in geen enkel codepad een forwarded-header gelooft, ook niet via een nieuwe aanroep van `RemoteAddrIsTrustedProxy` die de helper omzeilt;
3. dat `Secure` op de LAN-listener op elk cookie staat (refresh en stream) en op de platte listener ongewijzigd is;
4. dat `routes` alleen voor klasse `authenticated` verschijnt en nooit in `/info`;
5. dat de app geen token stuurt voordat de `server.id`-controle slaagde, ook niet in een retry of in de speler;
6. dat mpv `tls-verify` echt aan heeft op het pad dat de Apple TV gebruikt (een test die rood wordt zonder de optie);
7. dat een redirect van de LAN-naam naar een andere host geen `Authorization` of `Cookie` meeneemt (mpv en ffmpeg doen dat wel, volgens de S26-cloudproef);
8. dat de certificaatsleutel alleen-lezen gemount is en niet in een back-up van `/config` belandt zonder versleuteling;
9. dat een onbekende `Host` op de LAN-listener geen antwoord met gegevens krijgt.

---

## 8. Synology

- **Poort.** DSM gebruikt 5000 en 5001 en zijn nginx neemt 80 en 443; die blijven van DSM. Voorstel: 8443 op het LAN-adres, mits vrij (besluit B4, meten met `ss -ltn` in fase 0).
- **DSM-firewall.** Docker zet zijn eigen `iptables`-regels vóór die van DSM; een gepubliceerde poort is daardoor vaak bereikbaar ongeacht de DSM-firewall. Binden op het LAN-adres en geen port-forward op de router zijn daarom de echte grens, niet de firewall. Staat de DSM-firewall aan, dan een regel die 8443 alleen vanaf het LAN-bereik toestaat, en een meting dat hij werkt.
- **Vast adres.** Het NAS-adres moet vast zijn (DHCP-reservering of statisch), want het staat in `PLEYA_SERVER_LAN_BIND` en in DNS.
- **Rechten.** `pleya-server` draait als `1026:100` (`compose.yaml:25-27`) en `read_only`. `acme.sh` draait als root en moet `key.pem` na elke vernieuwing leesbaar maken voor die uid (`--install-cert` met een `reloadcmd` die `chown` en `chmod 0640` doet). De map komt onder `data/` en dus buiten git en de buildcontext.
- **Back-up.** De certificaatmap valt buiten `/config` en hoeft niet mee: hij is in minuten opnieuw aan te vragen.
- **Router.** Geen port-forward voor 8443. Nagaan of de router DNS-rebindingbescherming heeft, en of hij lokale DNS-regels kan zetten (B2).

---

## 9. Fasering

Elke fase is een eigen branch volgens AGENTS.md, met `Roadmap: C-07`. Fasen 1 tot en met 3 zijn security-branches: eigen adversariële review vóór de bundel.

| Fase | Wat | Kan zonder NAS | Vraagt Michel of hardware | Klaar als |
| --- | --- | --- | --- | --- |
| 0 Besluiten en meten | Besluiten B1 tot B8; read-only metingen op de NAS | n.v.t. | Ja: `docker version`, `iptables -t raw -S`, `docker network inspect pleya-server_default`, `grep -E '^PLEYA_SERVER_(BIND\|TRUSTED_PROXIES\|HOST_PORT)=' .env`, `ss -ltn`, of het clientadres behouden blijft (één aanvraag naar een tijdelijke testpoort op de testinstance); vanaf een tweede toestel: `curl http://<nas>:8832/readyz` en een direct-route-proef naar het bridgebereik | De zes vragen uit hoofdstuk 12 hebben een antwoord in de masterlijstregel; staat de API vandaag al op het LAN, dan eerst dat dichtzetten, los van dit plan |
| 1 Server: TLS-listener | Tweede listener, certificaat herladen, geen forwarded-headers, `Host`-controle, `compose.lan.yaml`, deployregel, operatordoc | Ja: Go-tests met een in de test gemaakt certificaat; lokale Docker-stack met `compose.lan.yaml` en een zelfondertekend certificaat; uitgifte en vernieuwing tegen Pebble (de test-CA van Let's Encrypt, zoals in de S26-proef) | Nee | Tests groen met negatieve controles; `docker compose config` toont zonder `PLEYA_SERVER_LAN_BIND` exact de huidige publicatie |
| 2 Protocol: `routes` | Venster (B5), schema, fixture, `check_protocol.sh`, serverkant | Ja | Besluit Michel over het venster | Contracttest groen; `/info` heeft geen `routes` |
| 3 App: LAN eerst | `baseUrls`, race, identiteitscontrole, `tls-verify`, heropenen op positie | Ja: fake server uit `test/pleya_server/pleya_fake_server.dart` met twee adressen, één dood; Pleya Verify-fixture voor een speelstart | Toestelrun op Apple TV voor mpv met `tls-verify` (MPVKit-gedrag is niet buiten een toestel te bewijzen) | Tests groen met negatieve controles; starttijd met dode LAN-route binnen de race-voorsprong |
| 4 Uitrol | DNS, token, `.env`, deploy met de laag; daarna acceptatie | Nee | Ja, alles | Acceptatie hieronder geslaagd |

**Tests per fase, met negatieve controle.**

- Fase 1. `TestLANListenerIgnoresForwardedHeaders`: een aanvraag op de TLS-listener vanaf een adres binnen `TRUSTED_PROXIES` met `X-Forwarded-For` en `X-Forwarded-Proto: http` krijgt zijn eigen adres als limietsleutel en `Secure` op het cookie. Rood als de helper de contextvlag negeert. `TestLANListenerReloadsCertificate`: een nieuw certificaat op schijf wordt bij de volgende handshake gebruikt zonder herstart; rood zonder de mtime-controle. `TestLANListenerRefusesUnknownHost`: 421 bij een vreemde `Host`; rood zonder de controle. `TestPlainListenerUnchanged`: de bestaande `remote_hardening_test.go` blijft groen. Compose-test (`internal/config/compose_test.go` als voorbeeld): zonder de LAN-laag geen extra publicatie.
- Fase 2. Fixture met en zonder `routes`; `/info` zonder `routes` voor elke klasse; een `http://`-waarde in `PLEYA_SERVER_LAN_URL` laat de server weigeren te starten.
- Fase 3. Race met een dood LAN-adres: eerste route binnen 300 ms plus de tunnelprobe; rood als de dode kandidaat de volle probe kost. Identiteit: een fake server met een andere `server.id` op het LAN-adres krijgt geen `Authorization`; rood zonder de controle. Een gemelde `http://`-route wordt niet gebruikt. Heropenen: wegvallen van de LAN-route tijdens een fake stream hervat via de tweede route op de positie. mpv: de opties die naar mpv gaan bevatten `tls-verify=yes` voor een `https`-Pleya-stream; rood zonder.
- Fase 4, acceptatie op de NAS en toestellen (Michel). Apple TV thuis: film start, serverlog toont het LAN-adres; `docker stop pleya-tunnel` tijdens de film, de film speelt door, daarna `docker start pleya-tunnel`. iPhone: thuis starten, wifi uit, de film hervat via `web.pleya.app` op dezelfde positie. Negatief: vanaf een toestel buitenshuis faalt de LAN-route en start via de tunnel binnen de normale tijd. Negatief: met een tijdelijk ander certificaat op de LAN-naam weigert de Apple TV te spelen.

`scripts/ci_checks.sh` groen per branch; UI verandert niet, dus geen screenshots, tenzij besluit B8 een routeweergave toevoegt.

---

## 10. Terugrollen

| Fase | Terugrol |
| --- | --- |
| 0 | Niets uitgerold; metingen zijn alleen-lezen. De testpoort voor de adresmeting gaat op de testinstance en weer dicht. |
| 1 | Zonder `PLEYA_SERVER_TLS_ADDR` start de tweede listener niet en publiceert `compose.yaml` niets extra; terugdraaien is de PR revert. |
| 2 | Het veld is additief; oude clients negeren het. Revert van de serverkant laat `routes` weg; een nieuwe client valt terug op het ene adres. |
| 3 | Een client zonder gemelde routes gedraagt zich als nu. Revert per PR; opgeslagen verbindingen met `baseUrls` lezen in de oude code als één `baseUrl` (backfill zoals bij Jellyfin, te bewijzen met een migratietest in fase 3). |
| 4 | `PLEYA_SERVER_LAN_BIND` en `PLEYA_SERVER_LAN_URL` uit `.env` halen en opnieuw deployen: de laag valt weg, de server meldt geen route meer, apps gaan bij de volgende race via de tunnel. DNS-record en token intrekken. Vooraf een back-up van `.env` en een databaseback-up volgens `deploy-nas.sh`. |

---

## 11. Open besluiten voor Michel

| # | Besluit | Aanbeveling |
| --- | --- | --- |
| B1 | Welk domein voor de LAN-naam | Een aparte zone, het liefst meteen het nieuwe serverdomein uit S26 besluit 12 dat toch geregistreerd moet worden. Dan kan de token op de NAS `pleya.app` niet aanraken. `thuis.pleya.app` werkt technisch ook, met dat risico. |
| B2 | Lokale DNS-regel of publiek A-record | Lokale regel op de router als die dat kan; anders publiek A-record zonder proxy plus een rebinding-uitzondering. |
| B3 | TLS in de server of in een proxy | In de server, met een certificaat uit een sidecar. Minder onderdelen, geen vertrouwde proxy, past bij S26. |
| B4 | Poort | 8443 op het LAN-adres, als die vrij is. |
| B5 | Protocolvenster voor `routes` in `GET /server` | Een smal, additief venster nu, zo gevormd dat S26 het uitbreidt. Het alternatief, per toestel een tweede adres handmatig invoeren, kost op de Apple TV een typronde per toestel en gaat bij elk nieuw toestel opnieuw mis. |
| B6 | `TRUSTED_PROXIES` versmallen | Ja: het vaste adres van `pleya-tunnel` in plaats van het hele bridgebereik; vraagt een vast adres voor die container in de relay-stack. |
| B7 | `tls-verify` voor mpv | In C-07 aan voor Pleya Server. Voor Plex en Jellyfin blijft het de losse hotfix uit de S26-proef, als apart besluit na het toestelbewijs. |
| B8 | Laat de app zien welke route hij gebruikt | Nee in C-07: alleen in de log en in de diagnose. Een zichtbare status hoort bij S26 stap 7. |

---

## 12. Wat de repo niet kan beantwoorden

Allemaal voor fase 0, door Michel op de NAS of in huis:

1. De waarde van `PLEYA_SERVER_BIND`, `PLEYA_SERVER_HOST_PORT` en `PLEYA_SERVER_TRUSTED_PROXIES` in `/volume1/docker/pleya-server/.env`.
2. Het werkelijke subnet van `pleya-server_default` (het recept noemt `172.18.0.0/16` als voorbeeld).
3. De Docker Engine-versie van Container Manager en of directe routering naar het bridgebereik vanaf het LAN werkt.
4. Of een LAN-client in de container met zijn eigen adres binnenkomt of met het gateway-adres.
5. Of poort 8443 vrij is en of de DSM-firewall aan staat.
6. Wat de router kan: lokale DNS-regels, rebindingbescherming en uitzonderingen daarop, en of het NAS-adres vast is.

Verder niet uit de repo vast te stellen: hoe MPVKit op tvOS certificaten controleert met `tls-verify` aan (toestelproef, ook open in S26), en of PR #687 ongewijzigd wordt gemerged.
