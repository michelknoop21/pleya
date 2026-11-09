# Uitvoeringsplan: Pleya Server delen via uitnodigingen, automatisch versleutelde verbindingen en relay

**Roadmap:** C-06 / S26, toegevoegd op 9 november 2026 als roadmapafwijking (besluit Michel). **Voorstel:** [docs/pleya-server-sharing-proposal.md](../../pleya-server-sharing-proposal.md). **Besluit:** DEC-XXX in [docs/DECISIONS.md](../../DECISIONS.md), nummer bij de merge. **Status:** stap 1 (inventarisatie en besluit) in uitvoering; geen protocolvenster geopend, geen code.

Dit bestand is de repo-kopie van het goedgekeurde plan en de bron voor de acht stappen. De stand per taak staat in [de masterlijst, S26](../../PLEYA-SERVER-MASTERLIST.md#s26-delen-ps-17); dit plan houdt geen tweede status bij.

## Context

Michel wil dat iedereen die Pleya Server zelf host, de server eenvoudig kan delen: de ontvanger accepteert een uitnodiging, logt in en kijkt, ook buitenshuis, met versleuteling tot aan de NAS en zonder verlies van performance of kwaliteit. De techniek (TLS, certificaten, routes, relay) gebeurt achter de schermen. Dit is een product voor andere self-hosters en partijen, niet alleen voor Michels NAS.

Wat de repo nu heeft, en waarom dat niet volstaat:

- **Server zonder TLS, alleen op loopback.** `pleya_server/internal/httpserver/server.go:69-70` doet `ListenAndServe`; `compose.yaml:18-22` publiceert `127.0.0.1:8832`. DEC-037 (`docs/DECISIONS.md:310-316`) en architectuur §15 (`docs/pleya-server-architecture.md:1270-1297`) sluiten NAT-traversal, relay en certificaatuitgifte in de binary uit. S24.1 t/m S24.6 (`docs/PLEYA-SERVER-MASTERLIST.md`, sectie "S24 Remote hardening") zijn instellingen en operatorrecepten (`docs/pleya-server-operator-remote.md`): tunnel, mesh-VPN, eigen proxy.
- **Huidige productieroute termineert TLS bij Cloudflare.** `web.pleya.app` loopt via `cloudflared` in `server/docker-compose.yml` naar `http://pleya-server:8080`. Op het LAN reizen `stream_token` en het `ss`-cookiegeheim in klare tekst (DEC-051).
- **Client: één adres, standaard http, geen pairing of serverlijst.** `PleyaServerConnection.baseUrl` (`lib/connection/connection.dart:654-700`), `normaliseBaseUrl` plakt `http://` (`lib/services/pleya_server_auth_service.dart:62`), `PleyaServerClient.create` gebruikt één `MediaServerHttpClient` (`pleya_server_client.dart:191-205`) terwijl Jellyfin `baseUrls` en `FailoverHttpClient` heeft. Geen certificaatafhandeling in `lib/` (`lib/utils/platform_http_client_io.dart`). Cleartext toegestaan in Info.plists en AndroidManifest.
- **Drie spelerstacks met elk een eigen TLS-stack.** mpv via MPVKit (`ios/Runner/MpvPlayer/MpvPlayerCore.swift`, headers via `http-header-fields` in `lib/mpv/player/player_native.dart:189`), ExoPlayer via Cronet of `DefaultHttpDataSource` (`android/.../exoplayer/ExoPlayerCore.kt:38-41, 125-137`), en de Flutter-HTTP-client. Eén Flutter-callback beveiligt mpv en ExoPlayer niet. Dit is de reden dat publiek vertrouwde certificaten de voorkeursrichting zijn en maatwerkpinning niet vooraf de standaard wordt.
- **Authenticatie bestaat, delen niet.** Tokens `ply1.` met HMAC-SHA256 (`internal/auth/token.go`), access 15 minuten, refresh 30 dagen met rotatie (DEC-117), sessies per toestel en intrekbaar (DEC-120/DEC-123, `internal/auth/revocation.go`), stream-token 5 minuten, stream-sessie 30 minuten (DEC-051), Ed25519-companiontickets (`internal/auth/companion.go`). Gebruikers worden door de beheerder aangemaakt met wachtwoord; de eerste eigenaar via een setup-code op de console. Geen uitnodiging, geen centraal account, geen serverlijst per account.
- **Relaytechniek in de repo is ongeschikt voor video.** De WebSocket/JSON-relay in `server/main.go` is gemeten op 64 KiB per bericht en 10 berichten per seconde (DEC-176). Wel herbruikbaar als ontwerpreferentie: E2E-verzegeling en pairingcode uit Pleya Share (`lib/services/pleya_share/pleya_share_pairing.dart`), maar niet als transport.

## 1. De gebruikerservaring staat vast

**Servereigenaar**
1. Pleya Server installeren (dag één: Docker op NAS, bestaand `compose.yaml`) en eenmalig aan het eigen Pleya-account koppelen, of zelfstandige modus kiezen. Vóór die keuze start geen centrale registratie.
2. "Buitenshuis kijken" inschakelen.
3. Pleya onderzoekt de beschikbare verbindingen en stelt ze automatisch in.
4. Gebruikers uitnodigen en per uitnodiging bibliotheken en rechten kiezen.

**Ontvanger**
1. Uitnodigingslink openen.
2. Inloggen of Pleya-account aanmaken.
3. Uitnodiging accepteren.
4. De server verschijnt automatisch met de toegestane bibliotheken.

Op elk volgend apparaat verschijnt de server na aanmelden bij hetzelfde account. Een TV meldt aan via bevestiging op de telefoon of een korte inlogcode. Geen serverpairing per apparaat. QR-codes zijn hoogstens een gemak om een link te openen, nooit een verplichte stap.

**Twee modi**

| Modus | Ervaring | Centrale afhankelijkheid |
| --- | --- | --- |
| Pleya-accountmodus (standaard, aanbevolen) | Uitnodiging accepteren; server verschijnt op alle aangemelde apparaten | Pleya verzorgt accounts, serverregistratie en toegangscoördinatie |
| Zelfstandige modus | Uitnodiging van de server zelf accepteren; aanmelden bij die server | Geen Pleya-accountdienst; bereikbaarheid via eigen adres, VPN of eigen relay; meer handmatige instellingen toegestaan |

In accountmodus spreekt de server pleya.app aan voor registratie, toegangscoördinatie en relay. In zelfstandige modus maakt de server geen centrale verbindingen; een test bewaakt dat.

## 2. Stap 1: inventarisatie en besluit

Drie begrippen blijven uit elkaar:

| Begrip | Betekenis | Waar het nu leeft |
| --- | --- | --- |
| Pleya-account | De persoon die zich aanmeldt | Bestaat nog niet als dienst (E-01 voorstel, E-03 gepland); inventariseren wat de Pleya-backend achter pleya.app en `ice.pleya.app` al kan dragen |
| Servertoegang | Tot welke server en bibliotheken iemand toegang heeft | Pleya Server-gebruikers, rollen (owner, admin, member, restricted), rechten per bibliotheek zoals `download`; afdwinging in `internal/api/authorize.go` |
| Kijkprofiel | Geschiedenis, voorkeuren, profielbeperkingen | Profielen en PIN in de app (A-09), `CurrentUserContext`, kijkstatus op de server |

Wat de inventarisatie van 9 november al heeft opgeleverd (te bevestigen in stap 1, niet opnieuw te ontdekken):

**Server (`pleya_server/`)**
- Rollen `owner`, `admin`, `member`, `restricted` (`internal/auth/store.go:43-54`, DEC-119), één owner afgedwongen. Rechtenladder `view < download < manage` per bibliotheek in `library_permissions` (`internal/catalog/permissions.go:21-33, 65, 93`); owner en admin via rol. Herbruikbaar als rechtenmodel voor uitnodigingen.
- Gebruikersbeheer bestaat als API (DEC-121: `POST/GET/PATCH/DELETE /users`, `PUT /users/{id}/permissions`, `internal/api/handlers_users.go`), maar zonder beheerscherm (uitgesteld naar PS-11A). Nieuwe leden krijgen nu gebruikersnaam en wachtwoord van de beheerder. Geen uitnodiging, join, registratie of device-code; e-mailuitnodigingen staan expliciet buiten scope in architectuur §13.3.
- Sessies per toestel met `device_id` en `device_name` (DEC-123), `sid` door de hele keten, `GET/DELETE /sessions` (DEC-124), sweep van dode ketens (DEC-164). Intrekregister in geheugen, gecontroleerd per 64 KiB-blok van een stream: een ingetrokken sessie stopt binnen 2 s (DEC-120). Register leeft in één proces, dus niet over meerdere instanties.
- Sleutels: `token-signing.key` (32 bytes, 0600, `internal/auth/key.go`), rotatie trekt alle sessies in. De Ed25519-companionsleutel is afgeleid van de signing key en roteert mee (`internal/auth/companion.go:27-35`): niet bruikbaar als blijvende serveridentiteit. `ServerID` is een willekeurige id in `server_instance`, geen sleutel. **Gevolg:** stap 3 introduceert een eigen, niet-roterend identiteitssleutelpaar voor registratie en relay.
- Geen enkele uitgaande aanroep naar pleya.app; alleen TMDB, de eigen connectivity-check en de healthcheck. Dat is de nulmeting voor de zelfstandige modus.
- Web-login: gebruikersnaam en wachtwoord, refresh-token in HttpOnly-cookie op `/pleya/v1/auth/refresh`, geen "onthoud toestel", geen device-code.

**Client (`lib/`)**
- Geen Pleya-account, geen aankoop, geen entitlement: alleen de stub `lib/assistant/assistant_entitlement.dart:16-20` achter een buildvlag. E-01 is "voorstel, niet besloten", E-03 "gepland"; de roadmap (`docs/ROADMAP.md`, sectie "Commercial/site order") zegt al dat een betaalentitlement nooit mediaserver-beheerrechten vervangt.
- Verbindingen staan lokaal in Drift (`lib/connection/connection_registry.dart`) en syncen niet tussen toestellen; de iCloud-voorkeurensync (A-14) blokkeert credentials expliciet (`preference_sync_policy.dart:579-592`) en draait niet op Android, Linux en Windows. `CredentialVault` versleutelt met een sleutel in SharedPreferences, dus alleen obfuscatie. `PleyaKeychain` (`lib/services/pleya_keychain.dart`) heeft wel een iCloud-gesynchroniseerde variant: bestaande plumbing voor Apple, geen oplossing voor Android of TV van een ander merk. **Gevolg:** "server verschijnt op alle apparaten" komt uit het serveroverzicht van de centrale dienst, niet uit toestelsync.
- Profielen: `PleyaServerProfile` koppelt één serveraccount per profiel (`lib/profiles/profile.dart:66-83`); geen PIN voor Pleya Server-profielen; `CurrentUserContext` identificeert "ik" per server op opgeslagen user-id (BP-02/BP-03c). Geleende verbindingen (A-02) zijn kopieën tussen profielen op hetzelfde toestel, nooit beheerrechten, en Pleya Server-verbindingen zijn niet leenbaar. Dat model blijft.
- TV: de tvOS-aanmeldkeuze biedt alleen Plex en Jellyfin (`lib/screens/tv/tv_auth_view.dart:129-143`). Plex gebruikt QR van de plex.tv-auth-URL met polling (`lib/screens/auth/plex_pin_auth_flow.dart`). Herbruikbaar voor Pleya Server-TV-aanmelding: `lib/widgets/device_code_dialog.dart` (RFC 8628, nu voor Trakt en Simkl) en de QR/poll/retry-schil van `PlexPinAuthFlow`. Server-side bestaat nog geen device-code-endpoint.
- Deep links: geen `app_links` of universal links; alleen het schema `pleya://play` voor Top Shelf (tvOS en Android) en `pleya-share://pair` als QR-inhoud zonder OS-registratie. **Gevolg:** een uitnodigingslink vraagt universal links (Associated Domains) en Android App Links op een pleya.app-domein, plus een webfallback voor wie de app nog niet heeft.

Nog te inventariseren en vast te leggen in één docs-PR (roadmapafwijking, `DEC-XXX`, protocolvensteraanvraag):
- Wat de bestaande Pleya-backend achter pleya.app en `ice.pleya.app` (Go, `server/`) kan dragen voor accounts, registratie en uitnodigingen, versus een eigen klein onderdeel ernaast.
- Vertrouwensmodel: wie bewijst wat, welke sleutels waar leven (NAS, toestel, centrale dienst), wat de centrale dienst wel en niet weet, hoe eigenaarschap van een server wordt bewezen.
- Roadmapwijzigingen: S26 toevoegen, DEC-037 en §15 gedeeltelijk vervangen, relatie met E-01/E-03 (relay en pricing), S17/S18 (kwaliteit), S10/S11 (beheer en wizard), S14 (client op contract).
- Controle bij uitvoering of DEC-nummers, PS-11-afbakening en vrije roadmap-ID's nog kloppen met de actuele repo.

Een uitnodiging omzeilt nooit profielrechten of serverregels: de NAS beslist bij elk verzoek wat iemand mag zien of wijzigen. Centrale registratie geeft nooit automatisch beheerdersrechten.

## 3. Stap 2: technische proef voor TLS en passthrough

Voorkeursrichting: een automatisch Pleya-adres en publiek vertrouwd certificaat per server, met de privésleutel gegenereerd en bewaard op de NAS (patroon `internal/auth/key.go`). De gebruiker regelt geen domein of certificaat.

Te bewijzen vóór het definitieve besluit, op een beperkte proefopstelling tegen de NAS-testinstance:
- Afspelen op alle gebruikte spelerstacks: mpv/MPVKit (iOS, macOS, tvOS), ExoPlayer/Cronet (Android, Android TV), Flutter-HTTP en de browser (hls.js).
- Direct play, transcode/HLS, seek en ondertitels, inclusief segmenten en afbeeldingen over dezelfde geverifieerde verbinding.
- Automatische certificaatvernieuwing en sleutelrotatie zonder onderbreking van toegang; correcte hostnaamverificatie; bescherming tegen ongemerkte vervanging van de serveridentiteit; serverherstel en herinstallatie.
- TLS-passthrough via een bestaande tunnelcomponent (kandidaten beoordelen op SNI-passthrough, reconnects, limieten, logging; pas een eigen transport als die aantoonbaar tekortschieten).
- Haalbaarheid van zelfondertekende TLS voor de zelfstandige modus, met betrouwbare overdracht van vertrouwen via de uitnodiging zelf. Een fingerprint uit onbeveiligd `/info` of een `server_id` in een link bewijst niets.

Uitkomst: één `DEC-XXX` met de gekozen certificaatroute per modus. Zelfondertekende certificaten met maatwerkpinning worden niet vooraf de standaard. Eigen domeinen, reverse proxies en VPN's blijven ondersteund maar verschijnen niet in de uitnodigingsflow.

## 4. Stap 3: accounts, serverregistratie en centrale coördinatiedienst

Een kleine centrale dienst, waar mogelijk op de bestaande Pleya-backend, geen nieuwe microservices. Zij beheert:
- registratie van servers en hun eigenaar (serveridentiteit met sleutel op de NAS, eigenaarschap bewezen via account, nooit via een bestaand adres);
- uitnodigingen en geaccepteerde toegang;
- het serveroverzicht voor een aangemelde gebruiker;
- actuele verbindingsmogelijkheden per server;
- autorisatie voor gebruik van de Pleya-relay.

Zij bewaart geen media en geen privésleutels van servercertificaten. Zij is wel onderdeel van het vertrouwensmodel voor accounts en registratie. Logging beperkt tot operationeel noodzakelijke gegevens.

Server: koppelen aan account in de wizard (S11) en scherm 30; status in `GET /server`. Client: serverlijst uit het account naast de bestaande handmatige verbinding; `PleyaServerConnection` krijgt een serveridentiteit plus routes (stap 5) in plaats van één `baseUrl`.

## 5. Stap 4: uitnodigingen en toegangsbeheer

- Beheerder maakt een uitnodigingslink (optioneel e-mail via bestaande mailfunctionaliteit als die er is) en kiest per uitnodiging: bibliotheken, bestaande rechten (zoals downloaden of beheren), optionele vervaldatum van de toegang.
- Uitnodiging is tijdelijk geldig en eenmalig te accepteren. Na acceptatie hangt toegang aan het account; de link is geen toegangssleutel meer.
- Beheerscherm toont openstaande uitnodigingen en gebruikers met toegang; wijzigen en intrekken werkt ook voor bestaande sessies binnen een expliciet vastgelegde korte termijn. Bouwt op de bestaande korte access-tokens (15 min), refresh-rotatie en het intrekregister (DEC-117/120/123) plus een mechanisme voor actuele intrekkingen; een langdurig token alleen is onvoldoende.
- Server dwingt alles zelf af in `authorize.go`; de centrale dienst coördineert alleen.
- Protocol: nieuwe resources voor uitnodigingen en toegang, fixtures en `check_protocol.sh`, zoals bij S19/S23.

## 6. Stap 5: veilige directe routes

De client krijgt per vertrouwde server een lijst routes. Per route: adres en routetype, verificatiebeleid, waar TLS eindigt, of de beheerder de route toestaat, bereikbaarheid en laatste fout.

| Route | Gebruik |
| --- | --- |
| Lokaal versleuteld | Voorkeur als de server thuis bereikbaar is |
| Rechtstreeks buitenshuis | Als een veilige directe verbinding mogelijk is |
| VPN | Als geconfigureerd en beschikbaar |
| Pleya-relay | Terugval als geschikte directe routes niet werken |
| Cloudflare | Alleen als expliciet toegestane route met afwijkende vertrouwensgrens; nooit een stille terugval voor wie versleuteling tot de NAS eist |

Regels voor alle paden: geen automatische HTTPS-naar-HTTP-terugval; credentials pas naar een geverifieerde bestemming; geen credentialdoorgifte naar ongeautoriseerde redirects; segmenten, ondertitels en afbeeldingen vallen onder dezelfde controle; muterende verzoeken niet blind herhalen via een andere route. Binnen toegestane routes kiest de app op bereikbaarheid, prestaties en kosten. Een werkende stream blijft staan; bij verlies hervat Pleya via een andere veilige route op dezelfde positie; een betere route geldt voor nieuwe verzoeken.

Hergebruik `FailoverHttpClient` waar passend; onderzoek per spelerstack afzonderlijk hoe dezelfde regels gelden (mpv-opties, ExoPlayer-datasource, hls.js).

Router: directe bereikbaarheid wordt automatisch van buiten het thuisnetwerk gecontroleerd (via de centrale dienst of relay, niet alleen de bestaande lokale `connectivity-check`). Automatische poortmapping (UPnP/NAT-PMP) alleen als de gekozen componenten het betrouwbaar dragen en de beheerder het toestaat: opt-in, standaard uit, vernieuwing van een tijdelijke mapping automatisch zolang de instelling aanstaat en de status zichtbaar is, mapping verwijderen bij uitschakelen. Handmatig portforwarden blijft geavanceerd en is nooit een voorwaarde om uit te nodigen.

## 7. Stap 6: relay en automatische routekeuze

Harde eis voor de standaardmodus: als rechtstreeks verbinden niet lukt, werkt Pleya automatisch via de relay, zonder portforwarding of VPN-installatie bij de ontvanger.

De relay:
- geeft de versleutelde verbinding door tot de NAS en beschikt niet over de privésleutel van de media-TLS;
- registreert en authenticeert servers betrouwbaar (vastgelegd welke sleutel bij welke server hoort; weerstand tegen hergebruik van authenticatieberichten en verwisseling van servers);
- draagt meerdere gelijktijdige streams, gecontroleerde reconnects en time-outs, bandbreedte- en verbindingslimieten;
- logt alleen operationele gegevens;
- levert gewone HTTPS-adressen die de bestaande spelers begrijpen; geen eigen voorhandshake tenzij op alle stacks bewezen.

Eerst een bestaande tunnelcomponent met TLS-passthrough beoordelen (stap 2); eigen transport alleen bij aantoonbaar tekort. Niet bouwen op de WebSocket/JSON-relay in `server/main.go`.

Pleya-relay en eigen relay blijven beide: de Pleya-relay hangt aan het nog te nemen abonnements- en limietbesluit (E-01); een eigen relay vraagt geen account of Pro, maar wel veilige registratie van de servers die hem mogen gebruiken. Duurzame configuratie voor sleutels, registraties en limieten is waarschijnlijk nodig; "geen database" is geen harde eis. Pricing is een apart productbesluit vóór lancering; geen onbeperkte belofte zonder kostenberekening. Directe verbindingen werken onafhankelijk van een relayabonnement.

## 8. Kwaliteit buitenshuis (hangt aan S17 PlaybackPlan en S18 Transcode)

| Stand | Gedrag |
| --- | --- |
| Originele kwaliteit (fabrieksinstelling) | Geen verlaging voor bandbreedte; een compatibiliteitsconversie (audio, container, ondertitels, niet alleen videocodec) wordt afzonderlijk uitgelegd |
| Databesparing | Instelbaar bitrateplafond, bijvoorbeeld 4 Mbit/s |
| Automatisch | Kiest op capaciteit, buffer en apparaatmogelijkheden; niet alleen op de eerste segmenten; voorkomt voortdurend wisselen |

De beheerder zet de standaard, de kijker wijkt per toestel af. Het plan uit `POST /playback/plan` onderscheidt "kwaliteit aanpassen" van "compatibiliteit oplossen" en noemt de reden, zodat de speler het label toont. Kwaliteit daalt nooit stil.

## 9. Stap 7: interface, TV-aanmelding en migratie

Hoofdscherm eenvoudig: Buitenshuis kijken aan/uit; status (rechtstreeks, via relay, niet bereikbaar); gebruikers en uitnodigingen; kwaliteitsstandaard; eventuele relaylimieten. Onder Geavanceerd: routermapping, eigen adressen, VPN, certificaten, eigen relay, Cloudflare. De wizard (S11) krijgt accountkoppeling of zelfstandige keuze als overslaanbare stap.

TV: aanmelden via bevestiging op de telefoon of korte inlogcode (RFC 8628-achtig, via de centrale dienst in accountmodus en via de server zelf in zelfstandige modus). Hergebruik `device_code_dialog.dart` en de QR/poll-schil van `PlexPinAuthFlow`; Pleya Server toevoegen aan `tv_auth_view.dart`. D-pad en focus volgens `docs/agents/ui-and-tv.md`.

Migratie: bestaande Pleya Server-verbindingen zorgvuldig omzetten naar serveridentiteit plus routes; een bestaand adres is geen bewijs van eigenaarschap. Plex en Jellyfin behouden hun verbindingsmodel (Unified impact: alleen Pleya Server; `MediaBackend`-check voor de nieuwe connectievelden). De bestaande webroute blijft tijdens de overgang, met onderscheid tussen laden van de webinterface en transport van media; videotransport via Cloudflare hangt af van de toepasselijke dienst en afspraken.

## 10. Uitval en herstel

Expliciet vast te leggen in de `DEC-XXX` en de operatordoc:
- welke eerder geautoriseerde toegang tijdelijk blijft werken bij uitval van de centrale dienst;
- hoe lang gecachte toegangsrechten geldig blijven en wanneer opnieuw aanmelden nodig is;
- hoe intrekking en tijdelijke offline werking tegen elkaar wegen;
- serververvanging, herstel (S25-back-up bevat de identiteit en sleutels versleuteld) en sleutelrotatie.

Lokale toegang mag niet onnodig uitvallen door een storing bij Pleya.

## 11. Uitvoering

| Stap | Resultaat | Review |
| --- | --- | --- |
| 1 Inventarisatie en besluit | Bestaande functionaliteit, vertrouwensmodel, roadmapafwijking, `DEC-XXX`, protocolvensteraanvraag | docs-only review, onafhankelijke seat |
| 2 Technische proef | TLS en passthrough bewezen met echte spelers; certificaatroute per modus besloten | adversariële review van het vertrouwensmodel |
| 3 Accounts en serverregistratie | Eigenaar koppelt server; server verschijnt bij het juiste account | security-branch: adversarieel vóór bundel |
| 4 Uitnodigingen en rechten | Uitnodigen, accepteren, automatisch verschijnen, intrekken | security-branch |
| 5 Veilige directe routes | Lokaal, extern en VPN met correcte verificatie op alle stacks | security-branch, Pleya Verify |
| 6 Relay en automatische selectie | Kijken achter CGNAT zonder routerwerk | security-branch, belastingmeting |
| 7 Interface en migratie | Eenvoudige installatie, TV-aanmelding, migratie bestaande verbindingen | volledige UI-review met beelden |
| 8 Integrale verificatie | Securityreview, praktijktests, prestatiemetingen | aparte reviewer |

Elke stap een eigen branch volgens de bundelregels in AGENTS.md; security-gevoelige stappen krijgen hun eigen adversariële review vóór de bundel.

## 12. Acceptatie

Het werkpakket is af als deze scenario's aantoonbaar werken, met echte apparaten en Michels NAS:
- Michel nodigt iemand uit die buitenshuis via mobiel internet kijkt.
- Die persoon logt op een tweede apparaat in en ziet de server zonder opnieuw te koppelen.
- Een TV meldt eenvoudig aan en gebruikt dezelfde toegang.
- Een server achter CGNAT werkt zonder routeraanpassingen.
- Intrekken beëindigt ook bestaande toegang binnen de afgesproken termijn.
- Een verkeerde serveridentiteit of ongeldig certificaat wordt geblokkeerd, ook door de videospeler.
- Tokens komen niet bij een onbevoegde route of redirect terecht.
- De relay beëindigt de media-TLS niet en beschikt niet over de privésleutel.
- Direct play, transcoderen, ondertitels en hervatten werken op de ondersteunde platforms.
- Zelfstandige modus maakt geen onverwachte centrale verbindingen.
- Uitval van de centrale dienst volgt het vastgelegde gedrag voor bestaande toegang.
- Metingen op de NAS tonen acceptabele starttijd, seekgedrag, buffering en belasting.

Testaanpak: het daadwerkelijke verificatiegedrag per spelerstack, sleutelgrenzen (welke sleutel waar leeft) en weerstand tegen manipulatie. Geen testclaims die niet kunnen: de server kan bij gewone TLS niet zien of een client pint, en één test bewijst niet algemeen dat ontsleutelen onmogelijk is. Elke fix met negatieve controle; `scripts/ci_checks.sh` groen; UI-stappen met Pleya Verify en screenshotmanifest.
