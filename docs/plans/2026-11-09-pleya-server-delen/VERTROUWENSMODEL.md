# Vertrouwensmodel S26: wie bewijst wat, met welke sleutel

**Roadmap:** C-06 / S26.1. **Besluit:** DEC-XXX (Pleya Server delen), besluit 5 tot en met 12. **Bewijs:** de cloudproef in [`tool/s26_proof`](../../../tool/s26_proof/README.md) en het [rapport](../../qa/2026-11-09-s26-stap2-cloudproef.md). Dit document is de ontwerpbasis voor stap 3 tot en met 6. Het opent geen protocolvenster.

## Uitgangspunten

1. **De NAS beslist over toegang.** De centrale dienst coördineert. Een registratie of uitnodiging bij de centrale dienst geeft nooit zelf rechten op de server.
2. **Geen sleutel verlaat de plek waar hij gemaakt is.** Privésleutels van de NAS blijven op de NAS. Privésleutels van een toestel blijven op dat toestel.
3. **TLS eindigt op de NAS,** ook via de relay. De relay en de centrale dienst kunnen de media niet lezen.
4. **Twee barrières tegen verwisselen van servers:** de naam is afgeleid van de serveridentiteit, en het certificaat hoort bij die naam. Valt de eerste weg, dan houdt de tweede het tegen (proef: `TestServerCannotClaimAnotherServersName`, negatieve controle).

## Sleutels en geheimen

| Sleutel | Waar | Gemaakt door | Bewijst | Rotatie en herstel |
| --- | --- | --- | --- | --- |
| **Serveridentiteit** (Ed25519) | NAS, naast `token-signing.key` | De server bij de eerste koppeling | "Ik ben de server met hash H", met H = base32(SHA-256(publiek)[0:16]) | Roteert niet mee met `token-signing.key`; de companionsleutel in `internal/auth/companion.go` roteert wel mee en is daarom ongeschikt. Zit versleuteld in de S25-back-up. Na verlies volgt een nieuwe identiteit met een nieuwe hash, en de eigenaar koppelt opnieuw via zijn account. |
| **TLS-sleutel** (ECDSA P-256) | NAS | De server, bij elke aanvraag of verlenging | Het certificaat `*.H.<serverdomein>` hoort bij deze server | Kan bij elke verlenging nieuw zijn (proef: `TestRenewalWithSameAndRotatedKey`). Hoeft niet in de back-up: na herstel volgt een nieuwe aanvraag. |
| **ACME-account** | Centrale dienst | De centrale dienst | Niets naar gebruikers toe; alleen nodig bij Let's Encrypt | Kan vervangen worden zonder gevolgen voor servers. |
| **DNS-API-sleutel** | Centrale dienst | De beheerder van het serverdomein | Dat de centrale dienst DNS-01 mag uitvoeren | Een geheim op de NAS van Michel zolang de centrale dienst daar draait; bij de verhuizing naar de VPS een nieuwe sleutel. |
| **Pleya-accountsessie** | Toestel en centrale dienst | De centrale dienst bij aanmelden | Wie de persoon is | Kort access-token en een roterende refresh, naar het patroon van DEC-117. Intrekbaar per toestel. |
| **Servertoegang** | Pleya Server | De server bij acceptatie van een uitnodiging | Welke bibliotheken en rechten een account op deze server heeft | Bestaande rollen en rechtenladder (DEC-119), sessies per toestel (DEC-123), intrekregister (DEC-120). |
| **Relayregistratie** | NAS naar relay | De NAS | "Deze verbinding is van server H, voor deze relay" | frp: handtekening in de metadata, gecontroleerd door de plugin bij Login en NewProxy. Eigen relay: ondertekend bericht met relay-id, tijdstempel en nonce. |

## Wat elke partij weet

| Partij | Weet | Weet niet |
| --- | --- | --- |
| Centrale dienst | Accounts, welke servers aan welk account hangen, publieke serveridentiteiten, uitnodigingen en wie ze accepteerde, de routes van een server, relaygebruik per server | Media, bibliotheekinhoud, kijkgedrag, TLS-sleutels van servers, wachtwoorden van servergebruikers |
| Relay | Welke server-hash hoeveel bytes doorgeeft, IP-adressen van verbindingen, tijdstippen | De inhoud: alleen cijfertekst (proef: `TestRelayForwardsOnlyCiphertext` met een detector die werkt op klare tekst, `TestDetectorSeesPlaintextOnAPlainPipe`) |
| DNS-provider en CA | De servernaam `*.H.<serverdomein>`, dus het bestaan van een server | Wie de eigenaar is, IP-adressen alleen voor de namen die publiek in DNS staan |
| Pleya Server | Alles over zijn eigen gebruikers en media, zoals nu | Andere servers |

**Certificate Transparency:** elke uitgegeven naam komt in de openbare CT-logs. Met de hash in de naam lekt dat alleen dat er een server bestaat, geen eigenaar en geen locatie. Namen met een ingebed IP (`192-168-1-10.H...`) vallen onder het wildcardcertificaat en komen daarom niet apart in de logs.

## De drie stromen

**1. Server koppelen en certificaat krijgen** (stap 3, bewezen in `certflow`)
1. De eigenaar meldt zich in de wizard aan bij zijn Pleya-account. De server maakt zijn identiteitssleutel en toont de koppeling als bevestiging in het account, zodat een vreemde de server niet aan zijn eigen account kan hangen.
2. De centrale dienst registreert de publieke identiteit onder dat account.
3. De server stuurt een CSR voor precies `*.H.<serverdomein>`, ondertekend met de identiteitssleutel. De centrale dienst weigert een andere naam, een andere handtekening en een niet-geregistreerde identiteit (`TestIssueRefusesWhatIsNotTheCallersName`).
4. De centrale dienst doet DNS-01 en geeft de keten terug. De TLS-sleutel blijft op de NAS (`TestCertRequestCarriesNoPrivateKey`, `TestIssueKeepsKeyOnNASAndCoversRouteNames`).

**2. Uitnodiging accepteren** (stap 4, ontwerp)
1. De beheerder maakt op de server een uitnodiging met bibliotheken en rechten. De server meldt hem aan bij de centrale dienst met een eenmalige code.
2. De link wijst naar pleya.app en bevat alleen die code. De code geeft geen toegang tot de server; hij is eenmalig en verloopt.
3. De ontvanger meldt zich aan of maakt een account aan. De centrale dienst koppelt het account aan de uitnodiging en vertelt de server dat dit account accepteerde.
4. De server maakt of koppelt een servergebruiker met precies de rechten uit de uitnodiging. Pas daarna geeft de server sessies uit aan toestellen van dat account.
5. Vertrouwen in de server loopt via de centrale dienst over gewone TLS met publiek vertrouwde certificaten. De app krijgt de routes en de hash; het certificaat van de server bewijst bij elke verbinding dat het de juiste server is.

**3. Verbinden en kijken** (stap 5 en 6, bewezen in `relay`, `frpeval` en `players`)
1. De app kiest uit routes van de centrale dienst: lokaal (`a-b-c-d.H...`), rechtstreeks (`direct.H...`), relay (`r1.H...`). Alle namen vallen onder hetzelfde certificaat.
2. **Elke speler moet het certificaat controleren.** ffmpeg en mpv doen dat standaard niet (proef: MITM speelt af met de standaardinstelling, wordt geweigerd met `tls-verify=yes`). De app moet dit expliciet aanzetten voor mpv en voor elke ffmpeg-route.
3. **Geen bearer-header naar de speler waar een redirect naar een andere host kan volgen.** ffmpeg en mpv sturen `Authorization` mee naar de nieuwe host; de Go-client niet (`TestAuthorizationHeaderOnCrossHostRedirect`). Voor de speler gebruikt S26 daarom een kortlevend, versiegebonden streamtoken of een app-side proxy die de header alleen naar de geverifieerde host stuurt.
4. **De lokale route hangt niet aan DNS.** Routers met DNS-rebindingbescherming beantwoorden een naam met een privé-IP niet. De app gebruikt de adressen uit de routegegevens via een CONNECT-proxy op het toestel; de speler houdt de hostnaam voor TLS (`TestLocalRouteSurvivesRebindingProtection`).

## Dreigingen en antwoord

| Dreiging | Antwoord | Bewijs |
| --- | --- | --- |
| Iemand vraagt een certificaat aan voor de naam van een ander | Naam moet afgeleid zijn van de ondertekenende identiteit, en die moet geregistreerd zijn | `certflow`, met negatieve controle |
| Een server neemt bij de relay de naam van een ander over | Hash afgeleid van de sleutel, handtekening, autorisatie door de centrale dienst; daarachter het certificaat | `relay` en `frpeval`, met negatieve controle |
| Replay van een relayregistratie | Eigen relay: nonce, tijdstempel en relay-id. frp: control-kanaal over TLS; de handtekening in de metadata is een statisch geheim op de NAS | `relay` met negatieve controle; frp-replay buiten de proef, zie open punten |
| Relay of netwerk leest mee | TLS eindigt op de NAS | `relay` met detectorcontrole; `frpeval` ziet het NAS-certificaat |
| Man-in-the-middle op een route | Verificatie in elke speler, geen stille terugval naar HTTP | `players`: geweigerd met verificatie, geaccepteerd zonder |
| Token lekt via redirect | Geen bearer-header naar spelers bij mogelijke redirect; versiegebonden token | `players` |
| Uitval van de centrale dienst | Bestaande sessies op de server blijven werken tot hun refresh verloopt; nieuwe accounts en uitnodigingen wachten | Ontwerp, besluit 10; nog te bewijzen in stap 8 |
| Uitval thuis in de NAS-fase | Aanmelden en relay vallen weg voor alle gebruikers; directe en lokale routes van andere servers blijven werken met gecachte routes | Ontwerp; reden voor de latere verhuizing naar de VPS |

## Hosting in fases (besluit 12)

- **NAS-fase:** de centrale dienst draait als eigen container met eigen database achter de bestaande Cloudflare Tunnel; dat mag, want daar gaat alleen coördinatieverkeer over. De relay kan niet achter de tunnel, want die termineert TLS. De relay (frps) krijgt een eigen doorgezette poort op de router van Michel.
- **VPS-fase:** dezelfde containers met dezelfde DNS-namen op een VPS. De verhuizing is een DNS- en deploywijziging. De DNS-API-sleutel en het ACME-account worden daarbij vervangen.

## Open voor stap 3 en later

- frp-control-kanaal over TLS (`transport.tls.enable`) en de replay-eigenschappen daarvan aantonen. De statische handtekening in de frpc-metadata is gelijkwaardig aan een API-sleutel op de NAS; rotatie gaat via de identiteit.
- Of frpc als aparte container naast Pleya Server draait of als bibliotheek in de binary. De proef gebruikte de losse binaries.
- De precieze termijn voor intrekken van bestaande sessies, en het cachen van routes bij uitval van de centrale dienst.
- Spelergedrag op echte toestellen: MPVKit (iOS, tvOS, macOS), ExoPlayer met Cronet (Android en Android TV), Safari en Chrome met hls.js. Zie het [toesteldraaiboek](PROEF-TOESTELLEN.md).
