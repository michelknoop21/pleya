# S26 Delen, stap 2: technische proef, cloud-deel

9 november 2026. Roadmap C-06 / S26.2. Branch `claude/happy-brown-l9so1b`, basis `d63d010`. Proefcode in [`tool/s26_proof`](../../tool/s26_proof/README.md), eigen Go-module, geen productcode. Geen protocolvenster, geen deploy, geen toestel.

## Uitkomst in het kort

- **Certificaatroute werkt zoals ontworpen.** De NAS maakt sleutel en CSR. De centrale dienst krijgt alleen publieke gegevens, doet DNS-01 en geeft een wildcard `*.H.<serverdomein>` terug die de lokale, directe en relaynamen dekt.
- **frp haalt de relay-eisen.** Het type `https` geeft TLS door zonder te termineren. Een serverplugin van de centrale dienst dwingt per server de eigen naam af via een handtekening van de serveridentiteit. Een eigen transport is daarom niet nodig. De eigen dunne relay is wel gebouwd en getest, als terugval.
- **De spelers zijn het zwakke punt, niet de versleuteling.** ffmpeg 6.1 en mpv 0.37 controleren certificaten standaard niet, en sturen een `Authorization`-header mee naar een andere host bij een redirect. Met `tls-verify` aan werken alle routes en wordt een vals certificaat geweigerd.

## Bewijs per proef

Alle tests draaien lokaal tegen Pebble 2.10.1 (de test-CA van Let's Encrypt) en `pebble-challtestsrv`. Het volledige log staat buiten de repo; het resultaat was 18 PASS en 0 FAIL, exit 0.

| Test | Bewijst | Negatieve controle |
| --- | --- | --- |
| `certflow` `TestCertRequestCarriesNoPrivateKey` | Het verzoek aan de centrale dienst kan geen privésleutel bevatten | n.v.t. (typecontrole) |
| `certflow` `TestIssueKeepsKeyOnNASAndCoversRouteNames` | Certificaatsleutel is de NAS-sleutel; `192-168-1-10.H`, `direct.H`, `r1.H` geldig; andere hash, twee labels diep en de kale naam ongeldig | Ingebouwd: de ongeldige namen |
| `certflow` `TestIssueRefusesWhatIsNotTheCallersName` | Andere hash, niet geregistreerd en een verwisselde CSR worden geweigerd | Zonder naamcontrole krijgt de aanvaller een certificaat voor de naam van het slachtoffer |
| `certflow` `TestRenewalWithSameAndRotatedKey` | Verlengen met dezelfde en met een nieuwe sleutel | n.v.t. |
| `relay` `TestPassthroughServesRangeHLSAndSubtitles` | Range (`bytes=10-29`, `bytes=-5`), HLS-playlist en segment, WebVTT via de relay; het TLS-eindpunt is de NAS | n.v.t. |
| `relay` `TestRelayForwardsOnlyCiphertext` | De relay gaf 8,4 MB door zonder de klare-tekstmarker of het HTTP-verzoek | `TestDetectorSeesPlaintextOnAPlainPipe`: dezelfde pipe ziet de marker wel bij klare tekst |
| `relay` `TestServerCannotClaimAnotherServersName` | Andere hash, vreemde handtekening en niet-geautoriseerd worden geweigerd | Zonder hashcontrole lukt de registratie, maar weigert de client het certificaat van de aanvaller |
| `relay` `TestRegistrationReplayAndStaleAreRefused` | Replay, oud tijdstempel en verkeerde relay-id worden geweigerd | Zonder noncecontrole wordt een replay geaccepteerd |
| `relay` `TestConcurrentStreamsAndThroughput` | Acht parallelle Range-streams, 64 MiB, controlesom per deel | n.v.t. |
| `relay` `TestReconnectAfterControlDrop` | Relayroute terug binnen 66 ms na het wegvallen van de controleverbinding | n.v.t. |
| `relay` `TestBandwidthLimitPerServer` | 8 MiB bij 4 MiB/s duurde 2,0 s | Ingebouwd: de minimumduur |
| `relay` `TestUnknownOrForeignSNIIsDropped` | Onbekende hash, vreemd domein en diepe namen worden gesloten | n.v.t. |
| `frpeval` `TestFRPHTTPSPassthroughAndNameEnforcement` | frp 0.72.0: de client ziet het NAS-certificaat; de plugin weigert een dief met eigen login die de naam van een ander claimt, en een dief die zich voordoet als de ander zonder diens sleutel | Geen aparte: de logica is dezelfde als de relaycontrole, die er wel een heeft |
| `players` `TestFFmpegRoutesAndVerification` | Met verificatie aan spelen direct, relay, HLS en seek; een MITM-certificaat wordt geweigerd | Met de standaardinstelling speelt het MITM-certificaat af |
| `players` `TestMPVRoutesAndVerification` | Idem voor mpv, plus een externe ondertitel via de relay | Met de standaardinstelling speelt het MITM-certificaat af |
| `players` `TestAuthorizationHeaderOnCrossHostRedirect` | ffmpeg en mpv sturen `Authorization` mee naar de andere host; de Go-client niet | Ingebouwd: de Go-client als tegenvoorbeeld |
| `players` `TestLocalRouteSurvivesRebindingProtection` | Een resolver die privé-antwoorden weigert, breekt DNS voor de lokale route; via een CONNECT-proxy in de app met de route-adressen speelt ffmpeg met verificatie aan | Ingebouwd: de DNS-lookup faalt |

## Metingen

| Meting | Waarde | Kanttekening |
| --- | --- | --- |
| Doorvoer op loopback, beste van drie, 64 MiB | direct 407 tot 484 MiB/s, via eigen relay 584 tot 697 MiB/s | Alleen loopback. Beide ruim boven elke thuisuplink. Dat de relay hier sneller lijkt, komt waarschijnlijk door buffering in de multiplexer en is geen echte winst. |
| Acht parallelle Range-streams via de relay | 138 tot 172 ms voor 64 MiB | Loopback |
| Herstel na wegvallen van de controleverbinding | 66 ms | Loopback, lopende verzoeken op die verbinding vallen weg |

Echte metingen (starttijd, seek, buffering, NAS-belasting over een echte lijn) horen bij stap 8 op Michels NAS.

## Losse beveiligingsbevinding buiten S26

De app zet voor mpv nergens `tls-verify` aan: niet in `lib/mpv/player/player_native.dart` en niet in de Swift-laag. Op Linux accepteren ffmpeg 6.1 en mpv 0.37 met die standaardinstelling elk certificaat. Als MPVKit zich op iOS, tvOS en macOS net zo gedraagt, kan iemand met een positie in het netwerk vandaag een HTTPS-stream van Plex, Jellyfin of Pleya Server onderscheppen. Daarbij kan hij ook tokens uit de URL (`X-Plex-Token`) of uit de header lezen. De app geeft het Pleya Server-token bovendien als `Authorization`-header aan mpv (`player_native.dart:189`), en die header volgt een redirect naar een andere host.

Dit is niet hersteld in deze ronde: het valt buiten S26 en raakt alle backends. Het vraagt een besluit van Michel over een losse beveiligingshotfix: `tls-verify=yes` voor mpv, met de systeemtrust of een CA-bestand afhankelijk van de MPVKit-backend. Eerst moet het toesteldraaiboek bevestigen hoe MPVKit zich gedraagt.

## Open

- Toestelbewijs op MPVKit, ExoPlayer/Cronet en browser met hls.js: [toesteldraaiboek](../plans/2026-11-09-pleya-server-delen/PROEF-TOESTELLEN.md). Een los startcommando voor de proefopstelling bestaat nog niet.
- frp: het control-kanaal over TLS en replay daarop, frpc als container of als bibliotheek, en een eigen negatieve controle voor de plugin.
- Zelfondertekende TLS voor de zelfstandige modus is niet beproefd. De spelerbevinding maakt pinning per speler duurder, zie het vertrouwensmodel.
- De certificaatroute wordt pas na het toestelbewijs in een DEC vastgelegd; S26.2 blijft `[~]`.
