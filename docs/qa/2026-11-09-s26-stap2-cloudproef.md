# S26 Delen, stap 2: technische proef, cloud-deel

9 november 2026. Roadmap C-06 / S26.2. Branch `claude/happy-brown-l9so1b`. Proefcode in [`tool/s26_proof`](../../tool/s26_proof/README.md), een eigen Go-module zonder productcode. Geen protocolvenster, geen deploy, geen toestel.

## Uitkomst in het kort

- **De certificaatroute werkt zoals ontworpen.** De NAS maakt sleutel en CSR. De centrale dienst ziet alleen publieke gegevens, doet DNS-01 en geeft een wildcard `*.H.<serverdomein>` terug die de lokale, directe en relaynamen dekt. Registratie vraagt bewijs van bezit van de identiteitssleutel, en één server hoort bij één account.
- **frp haalt de relay-eisen.** Het type `https` geeft TLS door zonder te termineren. Een serverplugin van de centrale dienst dwingt per server de eigen naam af. Zonder die plugin krijgt wie het eerst registreert de route; dat is aangetoond. Een eigen transport is niet nodig. De eigen dunne relay is gebouwd en getest als terugval.
- **De spelers zijn het zwakke punt, niet de versleuteling.** ffmpeg 6.1 en mpv 0.37 controleren certificaten standaard niet, en sturen een `Authorization`-header mee naar een andere host bij een redirect. Met `tls-verify` aan werken alle routes en weigeren ze zowel een vals certificaat als een geldig certificaat van een andere server. `dart:io` stuurt de header bij een redirect niet mee.
- **De centrale dienst is een vertrouwde partij.** Wie hem, zijn DNS-sleutel of zijn ACME-account in handen krijgt, kan servers nabootsen. Het [vertrouwensmodel](../plans/2026-11-09-pleya-server-delen/VERTROUWENSMODEL.md) legt de beperkende maatregelen vast.

## Bewijs per proef

Alle tests draaien lokaal tegen Pebble 2.10.1 (de test-CA van Let's Encrypt), `pebble-challtestsrv`, frp 0.72.0, ffmpeg 6.1, mpv 0.37 en Dart 3.12. Het volledige log staat buiten de repo. Resultaat van de laatste run: 21 PASS, 0 FAIL, 0 SKIP, exit 0. `go vet` en `gofmt` zijn schoon.

| Test | Bewijst | Negatieve controle |
| --- | --- | --- |
| `certflow` `TestCertRequestCarriesNoPrivateKey` | Geen veld van het verzoek heeft een sleuteltype. Dit is een typecontrole: een `[]byte`-veld kan nog alles dragen | n.v.t. |
| `certflow` `TestIssueKeepsKeyOnNASAndCoversRouteNames` | De certificaatsleutel is de NAS-sleutel; `192-168-1-10.H`, `direct.H` en `r1.H` zijn geldig; een andere hash, twee labels diep en de kale naam zijn ongeldig | Ingebouwd: de ongeldige namen |
| `certflow` `TestIssueRefusesWhatIsNotTheCallersName` | Een andere hash, een niet-geregistreerde server en een verwisselde CSR worden geweigerd | Zonder naamcontrole krijgt de aanvaller een certificaat voor de naam van het slachtoffer |
| `certflow` `TestRegistrationNeedsPossessionAndOneOwner` | Alleen de publieke sleutel kennen is niet genoeg; een uitdaging werkt één keer; een handtekening voor het ene account werkt niet voor een ander; één server, één account | Ingebouwd per subtest |
| `certflow` `TestRenewalWithSameAndRotatedKey` | Verlengen met dezelfde en met een nieuwe sleutel | n.v.t. |
| `relay` `TestPassthroughServesRangeHLSAndSubtitles` | Range (`bytes=10-29`, `bytes=-5`), HLS-playlist en segment, WebVTT via de relay; het TLS-eindpunt is de NAS | n.v.t. |
| `relay` `TestRelayForwardsOnlyCiphertext` | De relay gaf 8,4 MB door zonder de klare-tekstmarker of het HTTP-verzoek | `TestDetectorSeesPlaintextOnAPlainPipe`: dezelfde pipe ziet de marker wel bij klare tekst |
| `relay` `TestServerCannotClaimAnotherServersName` | Een andere hash, een vreemde handtekening en een niet-geautoriseerde server worden geweigerd | Zonder hashcontrole lukt de registratie, maar weigert de client het certificaat van de aanvaller |
| `relay` `TestRegistrationReplayAndStaleAreRefused` | Replay, een oud tijdstempel en een verkeerde relay-id worden geweigerd. Kanttekening: het control-kanaal is in de proef gewone TCP | Zonder noncecontrole wordt een replay geaccepteerd |
| `relay` `TestConcurrentStreamsAndThroughput` | Acht parallelle Range-streams, 64 MiB, controlesom per deel | n.v.t. |
| `relay` `TestReconnectAfterControlDrop` | Relayroute terug binnen 66 ms na het wegvallen van de controleverbinding | n.v.t. |
| `relay` `TestBandwidthLimitPerServer` | 8 MiB bij 4 MiB/s duurde 2,0 s | Ingebouwd: de minimumduur |
| `relay` `TestUnknownOrForeignSNIIsDropped` | Een onbekende hash, een vreemd domein en diepe namen worden gesloten vóór TLS; een certificaatfout zou betekenen dat de relay toch doorstuurde | Ingebouwd: de test faalt op een certificaatfout |
| `frpeval` `TestFRPHTTPSPassthroughAndNameEnforcement` | Met de plugin houdt de NAS de route, ook als de dief eerst registreert; de client ziet het NAS-certificaat; beide dieven worden geweigerd | `TestFRPWithoutPluginGivesTheRouteToTheFirstClaimant` |
| `frpeval` `TestFRPWithoutPluginGivesTheRouteToTheFirstClaimant` | Zonder plugin krijgt de dief de route; alleen de certificaatcontrole van de client weigert hem | Dit is de negatieve controle |
| `frpeval` `TestPluginRefusesOtherProxyTypes` | De plugin staat alleen `https` toe, niet `http` of `tcpmux` voor dezelfde naam | Ingebouwd |
| `players` `TestFFmpegRoutesAndVerification` | Met verificatie aan spelen direct, relay, HLS en seek; een zelfondertekend en een geldig maar ander serverscertificaat worden geweigerd | Zonder verificatie spelen beide valse certificaten af, dus de route zelf werkt |
| `players` `TestMPVRoutesAndVerification` | Idem voor mpv, plus een externe ondertitel via de relay | Zonder verificatie spelen beide valse certificaten af |
| `players` `TestAuthorizationHeaderOnCrossHostRedirect` | ffmpeg en mpv sturen `Authorization` mee naar de andere host; `dart:io` en de Go-client niet. Alle vier worden geasserteerd, dus een verandering maakt de test rood | Ingebouwd: vier clients naast elkaar |
| `players` `TestLocalRouteSurvivesRebindingProtection` | Een resolver die privé-antwoorden weigert, breekt DNS voor de lokale route; via een CONNECT-proxy met de routeadressen speelt ffmpeg met verificatie aan | Positieve controle: dezelfde resolver beantwoordt een publiek adres wel |

## Metingen

| Meting | Waarde | Kanttekening |
| --- | --- | --- |
| Doorvoer op loopback, beste van drie, 64 MiB | direct en via de eigen relay beide tussen 280 en 750 MiB/s, de verhouding wisselt per run | Alleen loopback, ruim boven elke thuisuplink. Een vergelijking tussen de routes is hier niet zinvol. |
| Acht parallelle Range-streams via de relay | 108 tot 172 ms voor 64 MiB | Loopback |
| Herstel na wegvallen van de controleverbinding | 66 ms | Loopback; lopende verzoeken op die verbinding vallen weg |

Echte metingen (starttijd, seek, buffering, NAS-belasting over een echte lijn) horen bij stap 8 op Michels NAS.

## Review

Een onafhankelijke reviewer las de documenten en de proefcode en draaide de tests. Hij vond één Critical, zeven Important en elf Minors. Elke bevinding is eerst tegen de code en de documenten gecontroleerd.

- **Critical, verwerkt:** de centrale dienst kan onderscheppen, niet alleen "niet lezen". Het vertrouwensmodel zegt dat nu expliciet, met een dreigingsregel en beperkende maatregelen: CAA, identiteitspinning in de app, CT-bewaking, bevestiging van nieuwe toestellen.
- **Important, verwerkt:** thuisadressen niet in publieke DNS (I1); de proef met een geldig certificaat van een andere server (I2); frp met eigen backends, controle op `proxy_type` en een negatieve controle zonder plugin (I3); besluit 12 scheidt Michels besluiten van de gevolgen en voorstellen (I4); registratie met bewijs van bezit en één eigenaar (I6); `dart:io` in de redirecttest en de app-HTTP-kolom in het toesteldraaiboek (I7).
- **Important, voorgelegd aan Michel:** de Public Suffix List weigert aanvragen die alleen limieten omzeilen, en kleine projecten worden waarschijnlijk afgewezen (I5). De richtlijnen zijn gecontroleerd. Het risico staat in besluit 12; het besluit zelf is niet gewijzigd.
- **Minors, verwerkt:** een strengere SNI-droptest, een positieve DNS-controle, de formulering van de typecontrole, een kanttekening over het control-kanaal, geen claim over doorvoerverhouding, het voorbehoud over de back-upsleutel, de woordkeus in de roadmap, uitgelekte uitnodigingslinks, `go mod download` voor frp, `go mod tidy`, en de dubbele DEC-117 en DEC-120 bij naam genoemd.

Een verse reviewer controleerde daarna alle fixes in één keer. Uitkomst: de Critical en zes Important zijn hersteld en I7 was half. Hij vond één nieuwe Important: de browser kan de proxy op het toestel niet gebruiken, en valt daardoor buiten de lokale en directe route. Daarnaast vond hij vijf Minors. Alles is verwerkt: de browserroute staat in het vertrouwensmodel en het toesteldraaiboek; de redirectbevinding en `dart:io` worden nu geasserteerd; het geval met een ander serverscertificaat heeft een controle zonder verificatie; overdracht van een server staat als nog niet gebouwd; de hostingindeling heet een voorstel; en de afweging vóór stap 3 ligt bij Michel.

## Losse beveiligingsbevinding buiten S26

De app zet voor mpv nergens `tls-verify` aan: niet in `lib/mpv/player/player_native.dart` en niet in de Swift-laag. Op Linux accepteren ffmpeg 6.1 en mpv 0.37 met die standaardinstelling elk certificaat. Als MPVKit zich op iOS, tvOS en macOS net zo gedraagt, kan iemand met een positie in het netwerk vandaag een HTTPS-stream van Plex, Jellyfin of Pleya Server onderscheppen, inclusief tokens in de URL (`X-Plex-Token`) of in de header. De app geeft het Pleya Server-token bovendien als `Authorization`-header aan mpv (`player_native.dart:189`), en die header volgt een redirect naar een andere host.

Dit is niet hersteld: het valt buiten S26 en raakt alle backends. Het vraagt een besluit van Michel over een losse beveiligingshotfix: `tls-verify=yes` voor mpv, met de systeemtrust of een CA-bestand afhankelijk van de MPVKit-backend. Eerst moet het toesteldraaiboek bevestigen hoe MPVKit zich gedraagt.

## Open

- Toestelbewijs op MPVKit, ExoPlayer/Cronet, de app-HTTP-laag en de browser met hls.js: [toesteldraaiboek](../plans/2026-11-09-pleya-server-delen/PROEF-TOESTELLEN.md). Een los startcommando voor de proefopstelling bestaat nog niet.
- frp: het control-kanaal over TLS en replay daarop, en frpc als container of als bibliotheek.
- Identiteitspinning in de app, gebonden aan de TLS-sessie.
- Zelfondertekende TLS voor de zelfstandige modus is niet beproefd.
- De certificaatroute wordt pas na het toestelbewijs in een DEC vastgelegd; S26.2 blijft `[~]`.
