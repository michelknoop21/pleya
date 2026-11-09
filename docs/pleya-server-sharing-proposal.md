# Roadmap deviation proposal: Pleya Server delen via uitnodigingen, met automatisch versleutelde verbindingen en een relay

**Status:** richting besloten door Michel op 9 november 2026, vastgelegd als [DEC-XXX](DECISIONS.md#dec-xxx-pleya-server-delen-via-uitnodigingen-met-automatisch-versleutelde-verbindingen-en-een-relay); het nummer volgt bij de merge. Dit voorstel voegt werkpakket C-06 / slice S26 toe en opent **geen** protocolvenster: dat is een apart besluit (hoofdstuk 8).
**Auteur:** uitgewerkt met Michel Knoop, 9 november 2026
**Betreft:** [docs/pleya-server-architecture.md](pleya-server-architecture.md) hoofdstuk 15 en 23, [DEC-037](DECISIONS.md#dec-037-pleya-server-bouwt-geen-eigen-nat-traversal-en-geen-relay), [docs/pleya-server-operator-remote.md](pleya-server-operator-remote.md), [docs/PLEYA-SERVER-MASTERLIST.md](PLEYA-SERVER-MASTERLIST.md) S24, [docs/ROADMAP.md](ROADMAP.md) C-05 en E-01
**Uitvoeringsplan:** [plans/2026-11-09-pleya-server-delen/PLAN.md](plans/2026-11-09-pleya-server-delen/PLAN.md)

Dit voorstel volgt de zes onderdelen uit [hoofdstuk 23.1](pleya-server-architecture.md#231-de-roadmap-is-een-contract). Het is geschreven voordat er een regel code, een migratie of een protocolwijziging voor dit werk bestaat.

---

## 1. De oorspronkelijke aanname

DEC-037 (18 augustus 2026) en architectuur hoofdstuk 15 stelden: de binary bevat geen NAT-traversal, geen relay en geen certificaatuitgifte. Bereikbaarheid buitenshuis is een deploymentrecept (tunnel, mesh-VPN of eigen omgekeerde proxy) en geen architectuurbeslissing. Een huishouden achter CGNAT dat geen tunnel kan opzetten viel buiten wat de binary oplost. S24 (remote hardening) heeft dat recept gebouwd en bewezen: vertrouwde proxy's, publieke URL, rate limits, metrics en de range-testset.

Die aanname paste bij één server op één NAS, beheerd door iemand die zelf een tunnel of proxy neerzet.

## 2. De nieuwe bevinding

Pleya Server wordt een product voor andere self-hosters en partijen. De inventarisatie van 9 november 2026 (hoofdstuk 7) laat zien wat dat met de huidige stand betekent:

- Een nieuwe kijker krijgt nu gebruikersnaam en wachtwoord van de beheerder en typt zelf een serveradres in. Er is geen uitnodiging, geen account, geen serveroverzicht en geen TV-aanmelding voor Pleya Server.
- De server praat zelf alleen HTTP. Versleuteling tot de NAS hangt af van wat de beheerder zelf neerzet. De productieroute `web.pleya.app` termineert TLS bij Cloudflare, dat daarmee de stream in klare tekst kan zien.
- De app kent één adres per server en begint met `http://`; er is geen lokaal/extern onderscheid en geen certificaatafhandeling in de drie spelerstacks.
- De bestaande relaytechniek (`server/main.go`, `ice.pleya.app`) kan geen video dragen (DEC-176).

Michels eisen: zo makkelijk mogelijk, zo privé mogelijk, nooit ten koste van performance of kwaliteit, en bruikbaar voor wie Pleya Server zelf host.

## 3. Waarom de roadmap daardoor niet meer klopt

Met DEC-037 blijft delen buitenshuis handwerk voor de beheerder en onmogelijk achter CGNAT. Dat is verenigbaar met één huishouden, niet met een product dat anderen hosten. De roadmap heeft geen werkpakket voor uitnodigingen, accounts, serverregistratie, TLS in de binary of een relay; S24 is gesloten en gaat over proxy-instellingen. E-01 (Free/Pro) is een voorstel zonder besluit en kent de relay niet als kostenpost.

## 4. De concrete voorgestelde wijziging

Eén samenhangend werkpakket, **C-06 / S26 "Pleya Server delen: uitnodigingen, veilige verbindingen en automatische toegang buitenshuis"**, met deze kern:

1. **Uitnodigen is de basis.** De beheerder maakt een tijdelijke, eenmalige uitnodigingslink met bibliotheken en rechten. De ontvanger opent hem, logt in of maakt een Pleya-account, accepteert, en de server verschijnt met de toegestane bibliotheken. Op elk volgend apparaat verschijnt de server na aanmelden bij hetzelfde account. Een TV meldt aan via bevestiging op de telefoon of een korte inlogcode. Geen serverpairing per apparaat; QR is hoogstens een gemak.
2. **Twee modi.** Pleya-accountmodus (standaard, aanbevolen) met een kleine centrale coördinatiedienst voor accounts, serverregistratie, uitnodigingen, serveroverzicht, verbindingsmogelijkheden en relayautorisatie. Zelfstandige modus zonder centrale dienst, met eigen adres, certificaat, VPN of eigen relay en meer handmatige instellingen. Vóór die keuze start geen centrale registratie.
3. **Versleuteling tot de NAS, automatisch.** Voorkeursrichting: een automatisch Pleya-adres en publiek vertrouwd certificaat per server, privésleutel op de NAS. Dat wordt pas definitief na een technische proef met de echte spelerstacks (mpv/MPVKit, ExoPlayer/Cronet, Flutter-HTTP, browser). Zelfondertekende certificaten met maatwerkpinning worden niet vooraf de standaard. Eigen domeinen, proxies en VPN's blijven ondersteund.
4. **Automatische routekeuze** uit toegestane, geverifieerde routes: lokaal versleuteld, rechtstreeks buitenshuis, VPN, Pleya-relay, en Cloudflare alleen als expliciet toegestane route met afwijkende vertrouwensgrens. Nooit stil terug naar onversleuteld HTTP.
5. **Relay zonder routerwerk.** Als rechtstreeks verbinden niet lukt, werkt de standaardmodus via een relay die de versleutelde verbinding doorgeeft en de privésleutel van de media-TLS niet heeft. Eerst een bestaande tunnelcomponent met TLS-passthrough beoordelen; eigen transport alleen bij aantoonbaar tekort. Pleya draait een relay; dezelfde component is zelf te hosten zonder account.
6. **Kwaliteit** blijft bij de kijker: originele kwaliteit als fabrieksinstelling, databesparing met plafond, of automatisch; het PlaybackPlan noemt de reden en onderscheidt kwaliteit van compatibiliteit.
7. **Uitval en herstel** krijgen expliciet gedrag: welke toegang bij uitval van de centrale dienst blijft werken, hoe lang, en hoe intrekking daartegen weegt.

De acht uitvoeringsstappen, de acceptatiescenario's en de inventarisatie staan in het [uitvoeringsplan](plans/2026-11-09-pleya-server-delen/PLAN.md).

## 5. De gevolgen voor latere fasen

- **DEC-037 en hoofdstuk 15** worden gedeeltelijk vervangen: de binary krijgt een registratieclient, een relayclient en TLS. Wat blijft: correct gedrag achter een eigen proxy en de S24-recepten.
- **C-05** blijft de dekking van S0 tot en met S25; S26 komt erbij als eigen slice met eigen poorten en telt in de masterlijst als open werk. De bestaande vrijgave-, hardware- en releasepoorten blijven gelden.
- **E-01/E-03** krijgen een afhankelijkheid: de Pleya-relay hangt aan het nog te nemen abonnements- en limietbesluit. Directe verbindingen werken onafhankelijk daarvan.
- **S17/S18** leveren de kwaliteitsstanden; **S10/S11** het hoofdscherm en de wizardstap; **S14** de client op het uitgebreide contract.
- **Protocol:** het contract blijft bevroren tot het venster van hoofdstuk 8 expliciet opent.
- **S15 (Plex-off gate)** verandert niet van inhoud; S26 is geen voorwaarde voor die gate.

## 6. Welke scope hierdoor vervalt

- "Een huishouden achter CGNAT valt buiten wat de binary oplost" vervalt als productgrens.
- De operatorrecepten uit S24 blijven bestaan, maar zijn niet langer de enige route en komen voor de gewone gebruiker onder Geavanceerd.
- Niet in scope van S26: losse installers voor Windows, macOS of kale Linux (dag één is Docker op NAS), e-mailverzending als eigen dienst (alleen aansluiten op bestaande mail als die er is), en een prijsbesluit (dat blijft E-01).

## 7. Inventarisatie van 9 november 2026

Wat er al is en hergebruikt wordt, met bewijsplek:

| Onderdeel | Stand | Plek |
| --- | --- | --- |
| Rollen en rechten | `owner`, `admin`, `member`, `restricted`; ladder `view < download < manage` per bibliotheek | `pleya_server/internal/auth/store.go`, `internal/catalog/permissions.go`, DEC-119 |
| Gebruikersbeheer | API compleet (DEC-121), geen beheerscherm | `internal/api/handlers_users.go` |
| Sessies en intrekken | per toestel, `sid` door de keten, intrekregister per 64 KiB-blok, binnen 2 s | DEC-120, DEC-123, DEC-124, DEC-164 |
| Sleutels | `token-signing.key`; Ed25519-companionsleutel afgeleid en roterend; `ServerID` is een id, geen sleutel | `internal/auth/key.go`, `internal/auth/companion.go` |
| Uitgaande aanroepen | geen naar pleya.app; alleen TMDB, eigen connectivity-check, healthcheck | `internal/metadata/tmdb.go`, `handlers_server_admin.go` |
| Web-login | gebruikersnaam en wachtwoord, refresh-cookie; geen device-code | `pleya_web/src/routes/login` |
| Pleya-account in de app | bestaat niet; alleen de entitlement-stub achter een buildvlag | `lib/assistant/assistant_entitlement.dart` |
| Verbindingen tussen toestellen | lokaal in Drift, niet gesynchroniseerd; iCloud-sync blokkeert credentials; `PleyaKeychain` heeft een gesynchroniseerde variant voor Apple | `lib/connection/connection_registry.dart`, `preference_sync_policy.dart`, `lib/services/pleya_keychain.dart` |
| Profielen | `PleyaServerProfile` is één serveraccount; geleende verbindingen alleen op hetzelfde toestel en niet voor Pleya Server | `lib/profiles/profile.dart`, `borrow_connection_screen.dart` |
| TV-aanmelding | alleen Plex en Jellyfin; herbruikbaar: `device_code_dialog.dart` (RFC 8628) en de QR/poll-schil van `PlexPinAuthFlow` | `lib/screens/tv/tv_auth_view.dart`, `lib/screens/auth/plex_pin_auth_flow.dart` |
| Deep links | geen universal links of App Links; alleen `pleya://play` en `pleya-share://pair` als QR-inhoud | `tvos/Runner/Info.plist`, `lib/services/pleya_share/pleya_share_uri.dart` |
| Centrale backend | pleya.app is een statische SvelteKit-site met een downloadteller; `ice.pleya.app` is een Go-relay voor logs, Watch Together, posters en OAuth-proxy | `website/`, `server/` |

Drie gevolgen voor het ontwerp: de server krijgt een eigen, niet-roterend identiteitssleutelpaar; "server verschijnt op alle apparaten" komt uit het serveroverzicht van de centrale dienst en niet uit toestelsync; een uitnodigingslink vraagt universal links en App Links op een pleya.app-domein met een webfallback. De centrale dienst is nieuw; de Go-relaystack is de dichtstbijzijnde plek om hem te hosten, en dat is een keuze voor stap 3.

## 8. Protocolvensteraanvraag (niet geopend)

S26 raakt het bevroren contract. Dit hoofdstuk vraagt een venster aan en opent het niet; openen is een apart besluit van Michel, na stap 1 en de technische proef van stap 2. Verwachte, additieve scope binnen protocolmajor 1:

- `ServerInfo`/`GET /info`: modus (account of zelfstandig), serveridentiteit (publieke sleutel en sleutel-id), aangeboden routes met type en verificatiebeleid.
- Uitnodigingen: resource met aanmaken, lijst, intrekken en accepteren; bibliotheken, rechten en vervaldatum; foutcodes voor verlopen, gebruikt en ingetrokken.
- Toegang: koppeling van een account aan een servergebruiker; intrekking met korte geldigheid van bestaande sessies.
- TV-aanmelding: device-code-operaties voor de zelfstandige modus.
- Relay- en registratiestatus in `GET /server`; instellingen voor buitenshuis in `Settings`/`SettingsPatch`.
- Kwaliteitsstand in `POST /playback/plan` met reden "kwaliteit" of "compatibiliteit".

De precieze schema's, fixtures en matrixregels volgen uit stap 1 en 2 en komen in een eigen venstervoorstel, zoals bij S19/S23. Tot dat venster opent blijft `scripts/check_protocol.sh` de poortwachter.

## 9. Bij de merge: het nummer van DEC-XXX

Het nummer wordt bij de merge toegekend (AGENTS.md). Dezelfde commit die de kop in `docs/DECISIONS.md` hernummert, vervangt ook de tekst "DEC-XXX (Pleya Server delen)" en de anchor `#dec-xxx-pleya-server-delen-...` in: dit voorstel (kop en hoofdstuk 1), `docs/plans/2026-11-09-pleya-server-delen/PLAN.md`, `docs/ROADMAP.md` (rij C-06, Server/Web-volgorde, sectie C-06), `docs/PLEYA-SERVER-MASTERLIST.md` (kopregel, scopezin, S26), `docs/pleya-server-architecture.md` (noot bij hoofdstuk 15) en de statusnoot bij DEC-037. Een `rg "DEC-XXX (Pleya Server delen)"` moet daarna leeg zijn.
