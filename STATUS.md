# STATUS — Pleya

_Laatst bijgewerkt: 2026-08-14 16:00 (branch `main`, gepusht t/m `9c896d7`; TestFlight 2.8.0: tvOS 216, macOS 216, iOS 215)_

## Waar was ik

Vijf gemelde Apple TV-problemen opgelost en naar TestFlight gebracht. Het toetsenbord was de belangrijkste: de D-pad bediende de UI achter het geopende systeemtoetsenbord, en de fix uit DEC-011 bleek op een codepad te zitten dat daar nooit draait. De engine swizzlet `sendEvent:` en levert elke press rechtstreeks aan Dart, buiten de responder chain om, dus de gate hoort op `FocusManager.addEarlyKeyEventHandler`. Die geldt nu centraal voor elk invoerveld. Zie [DEC-017](docs/DECISIONS.md#dec-017). Verder: de skip- en volgende-aflevering-knop zijn bereikbaar met de remote en tonen er niet langer twee tegelijk tijdens de aftiteling, autoplay had drie onafhankelijke breekpunten waarvan er één autoplay voor de rest van de sessie stil kon leggen, de tijdlijn kent nu scrubben op pauze plus een spoelsnelheid die met het klikritme oploopt, en de log-upload hield zich niet aan het 1 MB-contract van de eigen relay.

Bij het uitrollen bleek dat **geen enkele macOS-build sinds 196 ooit installeerbaar is geweest**: `ITSAppUsesNonExemptEncryption` ontbrak in de macOS-plist, waardoor Apple elke upload op `MISSING_EXPORT_COMPLIANCE` zette terwijl de lane succes meldde. Sleutel toegevoegd en de builds 214 en 216 via de ASC-API losgetrokken. Zie [DEC-018](docs/DECISIONS.md#dec-018).

## Eerder werk, ongewijzigd

Twee opstartbugs dichtgezet en 2.8.0 klaargemaakt voor herindiening. De Apple-afwijzing van 6 juli (2.1(a), *"Authentication timed out"*) bleek geen app-fout: die string komt uit precies één plek, de Plex PIN-flow, dus de reviewer koos "Sign in with Plex" met het Jellyfin-demoaccount. De uitweg naar Jellyfin bestond al, maar hing in het foutblok — en de poll staat op vijf minuten, dus hij kwam pas ná vijf minuten staren. Hij staat nu ook onder de PIN zelf, en breekt de lopende poging af (anders navigeert een alsnog geclaimde PIN dwars door het Jellyfin-scherm heen). Zie [DEC-015](docs/DECISIONS.md#dec-015). Het lege profielscherm op macOS bleek twee dingen tegelijk: één toestand voor "laadt nog", "leeg" en "stilgevallen", en een toevoeg-knop die structureel ónder de vouw stond omdat macOS in pointer-modus start en niets hem in beeld scrolt. Beide los, plus een logregel die bij de volgende koude start moet verklappen wélke van de vier bronnen stilvalt. Zie [DEC-016](docs/DECISIONS.md#dec-016). Het Atmos-onderzoek staat ongewijzigd stil op de meting hieronder.

Het Atmos-spoor staat er nog precies zo bij als gisteren: een iOS-log van build 211 laat zien dat de bitstream-keten gewoon wérkt — `spdif_eac3` komt op, de avfoundation-sink pakt hem, en de fork logt `JOC=yes`, dus de Atmos-objecten van Ted Lasso S4E1 bereiken de renderer. Daarmee vallen twee van de drie oorspronkelijke verdachten af: `audio-exclusive` heeft in deze libmpv geen enkele consument (geen coreaudio, geen wasapi), en een MPVKit-bisect is zinloos omdat de sink in 1.0.16 aantoonbaar functioneert. Wat er wél uit kwam: de app kan niet zien dát Atmos loopt, want `AVAudioSession.renderingMode` geeft tijdens de werkende bitstream `not-applicable` en de badge hangt volledig aan die property. En loudness-normalisatie sluit passthrough uit zonder dat iets dat coördineert, terwijl Android TV datzelfde conflict al arbitreert maar precies andersom. Zie [DEC-013](docs/DECISIONS.md#dec-013). Verder ontdekt dat `ice.pleya.app` nooit heeft bestaan, waardoor de log-uploadknop altijd stil faalde; de Go-relay stond al klaar in `server/`, alleen op de verkeerde hostnaam. Zie [DEC-014](docs/DECISIONS.md#dec-014).

## Volgende stap

**Eén regressieronde op de fysieke Apple TV met tvOS build 216.** Alle vijf de fixes raken de remote, de focus of de spelerstaat, dus ze worden in één sessie doorlopen in plaats van los. Volgorde en wat je per punt controleert staat in `~/.claude/plans/ik-wil-dat-je-starry-possum.md`. Kort: zoeken openen en letters typen (achtergrond moet stilstaan, Menu sluit in één druk, daarna normaal navigeren, en hetzelfde bij inloggen, server-URL en Seerr), tijdens een intro omhoog naar de skip-knop en er weer uit, tijdens de aftiteling tellen hoeveel volgende-aflevering-knoppen er staan, een aflevering uitkijken en zien of hij vanzelf doorgaat (ook ná een eerdere seek in dezelfde sessie, dat was het no-op-scenario), pauzeren en met de balk een positie kiezen, en tot slot een log uploaden na een lange kijksessie plus direct nog eens drukken voor de "te snel"-melding.

Let bij het eerste punt op één ding in het bijzonder: reageert de remote na het sluiten van het toetsenbord nergens meer op, dan is dat het resterende native risico uit [DEC-017](docs/DECISIONS.md#dec-017) en geen los raadsel.

**Daarna pas de oude sporen hieronder.** Die staan ongewijzigd stil.

**De reviewroute op de iPad naspelen met build 213.** Installeer schoon, kies bewust "Sign in with Plex" en voer het demo-account in: de Jellyfin-uitweg hoort meteen zichtbaar te zijn, niet pas na vijf minuten. Daarna dezelfde route via de Jellyfin-knop — `demo.pleya.app`, `applereview` — en afspelen tot beeld. Klopt dat, dan het antwoord uit `docs/app-review-reply-2026-08.md` versturen via Resolution Center en 2.8.0 opnieuw indienen; de versie-records staan nu op alle drie de platforms op 2.8.0, dus build 213/214 is koppelbaar.

Daarna macOS koud starten (verschijnt er nu een spinner, een lege staat mét knop, of een expliciete fout? en wat zegt de nieuwe `profiles_view`-regel in Instellingen → Logs), met als tegenproef een pijltje omlaag in plaats van Esc.

**Tweede spoor, ongewijzigd: de meting op de Apple TV zelf.** Alle audiologs tot nu toe komen van de iPhone.

Correctie van 14 augustus op de aanname hieronder: de uploadknop wérkte niet, ook niet nadat de host live ging. De client las de statuscode nooit en verstuurde tot 5 MB terwijl de relay 1 MB accepteert, dus een lange kijksessie liep gegarandeerd op een 413 die als generieke fout aankwam. Dat is opgelost, maar het vraagt wel **build 216 of nieuwer** op het toestel. Tweede voorbehoud: mpv-regels bereiken `appLogger` alleen op error- en fatal-niveau (`parts/errors.dart`, gevoed door het filter in `parts/playback_services.dart`), dus zelfs een geslaagde upload bevat de `spdif_eac3`- en `JOC=yes`-regels hieronder waarschijnlijk niet. Wil je die meting echt doen, dan moet dat filter eerst info en verbose doorlaten zolang debug-logging aanstaat, of je haalt de log rechtstreeks op met `devicectl` (zie Quick start).

Zet normaliseren uit, audiomodus op Doorvoeren, speel Ted Lasso S4E1, en upload de log via Instellingen, Logs, upload-icoon. Dat geeft een code van vijf tekens; daarmee is de log op te halen met `curl https://ice.pleya.app/logs/<id>`. In die log moet staan: `Selected decoder: spdif_eac3`, `AO: [avfoundation] … spdif-eac3`, `EAC3 config: … JOC=yes`, plus wat `supported output channel layouts` en `audio rendering mode` op tvOS teruggeven. Werkt Atmos daar aantoonbaar, dan gaat het implementatieplan door; blijft het weg terwijl die regels er wél staan, dan ligt het buiten de app.

Het uitgewerkte implementatieplan (arbiter, badge uit de beslissing, `auto` op digitale poorten) staat in `~/.claude/plans/pleya-v2-8-0-211-ios-smooth-frog.md`.

## Blockers

- [ ] **Regressieronde op de fysieke Apple TV**: de vijf fixes van 14 augustus zitten in tvOS build 216 en zijn unit- en widget-gedekt, maar de Siri Remote is niet te simuleren. Zie de volgende stap hierboven.
- [ ] **Autoplay-vlaggen na een overgenomen herlaadpoging zijn niet door een test gedekt**: de opruiming zit in een `finally` in `_reloadMediaInPlace`, maar die logica leeft in een private extensie op de schermstaat en testen vraagt een volledig spelerharnas. Bewust overgeslagen; de dekking leunt hier op de deviceronde.
- [ ] **Scrubben: hervatten wacht niet op de seek**: bij bevestigen volgt `player.play()` direct op `onSeekEnd`, want die geeft geen future terug. Op mpv landen de commando's in volgorde, maar of er een frame op de oude positie doorschemert is alleen op een toestel te zien.
- [x] ~~**Log-upload werkte niet**~~ opgelost 2026-08-14. Niet de host: de client las de statuscode nooit en verstuurde tot 5 MB terwijl de relay 1 MB accepteert. Zie de CHANGELOG-entry van 14 augustus.
- [x] ~~**macOS-builds bereikten geen tester sinds 196**~~ opgelost 2026-08-14, zie [DEC-018](docs/DECISIONS.md#dec-018).
- [ ] **App Review-antwoord nog niet verstuurd**: concept staat klaar in `docs/app-review-reply-2026-08.md`. iOS 2.8.0 staat op REJECTED tot er opnieuw is ingediend.
- [ ] **Toestelverificatie van de twee fixes van vandaag**: iPad (Jellyfin-uitweg tijdens het pollen) en macOS (koude start van het profielscherm). Beide zitten in build 213/214; tot die check is de fix alleen door tests gedekt.
- [ ] **Welke van de vier profielbronnen stilvalt op macOS is nog onbewezen**: de nieuwe `profiles_view`-logregel moet het bij de eerstvolgende koude start noemen. Verdachte: `ConnectionRegistry.watchConnections()`.
- [ ] **Apple TV-meting**: geen enkele log komt van het toestel zelf, dus stap 4 van het audioplan (`auto` weer laten bitstreamen) staat geblokkeerd op bewijs.
- [ ] **Pleya Share tegen de productierelay**: de host draait nu, maar het framecontract (arbitraire rooms, >2 peers, object-payloads, ~90KB frames) is alleen tegen de lokale stub getest. Nu wél testbaar.
- [ ] **OAuth redirect-URI's**: `OAUTH_BASE_URL` staat op `ice.pleya.app`, dus MyAnimeList en AniList moeten `https://ice.pleya.app/auth/<service>/callback` geregistreerd hebben voordat tracker-koppelen werkt.
- [x] ~~**ice.pleya.app** bestond niet~~ — opgelost 2026-08-10. Draait op de NAS achter een Cloudflare Tunnel; `/health` en de volledige log-upload-route publiek geverifieerd.
- [ ] **Wi-Fi Aware iOS**: alleen compile-bewezen (Xcode 26.3/SDK 26.2); echte verbinding vereist iPhone 12+ op iOS 26.

## Toolchain-valkuil

Na een Xcode-update faalt **élke** build (ook fastlane) tot Xcode één keer handmatig is gestart — de systeemcomponenten in `/Library/Developer/PrivateFrameworks/` blijven anders achter bij Xcode.app. `xcodebuild -runFirstLaunch` lost het niet op. Check: `pkgutil --pkg-info com.apple.pkg.XcodeSystemResources` moet dezelfde versie tonen als `xcodebuild -version`. Zie [DEC-010](docs/DECISIONS.md#dec-010).

## Openstaand plan

Near-realtime sync van kijkvoortgang tussen apparaten: WebSocket-push van Plex/Jellyfin naar de bestaande `WatchStateNotifier` plus directe voortgangsrapportage bij seek. Richting goedgekeurd, nog niet gestart. Plan: `~/.claude/plans/is-er-een-manier-snoopy-snowglobe.md`.

## Quick start

```bash
cd /Volumes/SSD/Projects/PlexFlixNetwork/plezy-main
flutter test test/services/audio_output_decision_test.dart test/services/audio_output_coordinator_test.dart
scripts/ci_checks.sh                                           # volledige CI-gate
scripts/testflight_release.sh tvos_beta                        # TestFlight-upload (~10 min)
server/deploy-nas.sh                                           # relay naar de NAS
```

Log van de Apple TV rechtstreeks binnenhalen zonder de relay (het toestel is al gekoppeld):

```bash
xcrun devicectl device process launch --console --terminate-existing \
  --device AppleTV nl.michelknoop.pleya 2>&1 | tee /tmp/atv.log
```

## Recente sessies

### 2026-08-14
- Vijf gemelde Apple TV-problemen opgelost: de D-pad-lek door het systeemtoetsenbord (`5dba184`, `c8ae4b7`), de bereikbaarheid en vorm van de skip- en volgende-aflevering-knop plus de dubbele knop tijdens de aftiteling (`2dfbcd4`), autoplay naar de volgende aflevering (`ee96f6c`), scrubben op pauze met oplopende spoelsnelheid (`d9706ad`) en de log-upload (`73ba2b8`). 2925 tests groen. Zie [DEC-017](docs/DECISIONS.md#dec-017).
- Ontdekt dat geen enkele macOS-build sinds 196 installeerbaar was in TestFlight: `ITSAppUsesNonExemptEncryption` ontbrak (`9c896d7`). Builds 214 en 216 via de ASC-API losgetrokken. Zie [DEC-018](docs/DECISIONS.md#dec-018).
- TestFlight 2.8.0: tvOS 216, macOS 216, iOS 215. De iOS-lane hing eerst 32 minuten op de bekende `xattr`-valkuil met een `build/`-map van 13 GB; opgelost met een reaper die alleen een `xattr`-proces boven de 45 seconden afbreekt.

### 2026-08-10
- App Review 2.1(a) dichtgezet: de Jellyfin-uitweg staat nu óók tijdens het wachten op de PIN, en breekt de lopende poging af (`6f4d6d9`). Reviewnotities herschreven met de Plex-waarschuwing bovenaan; ASC-versierecords voor macOS en tvOS van 1.0 naar 2.8.0 gezet zodat er een build aan te koppelen is. Zie [DEC-015](docs/DECISIONS.md#dec-015).
- Leeg profielscherm op macOS: laden, leeg en stuk zijn nu drie toestanden, de toevoeg-knop staat in de lege staat zelf, en `_combineLatest4` noemt na drie seconden welke bron stilvalt (`fd87cad`). Zie [DEC-016](docs/DECISIONS.md#dec-016).
- Builds 213 (iOS) en 214 (tvOS, macOS) naar TestFlight; 2883 tests groen, `scripts/ci_checks.sh` schoon.
- `ice.pleya.app` live: Cloudflare Tunnel op de Synology, relay en tunnel als containers. `/health` en de volledige log-upload-route publiek geverifieerd (`POST /logs` geeft een code van vijf tekens, `GET /logs/<id>` geeft de tekst terug).
- Code-review-fixes op het serverwerk: LAN-poort naar `127.0.0.1` (de relay is onauthenticated en de OAuth-proxy zit op dezelfde poort), `--remove-orphans` in het deploy-script, en de OAuth-redirect-URI-stap gedocumenteerd omdat `OAUTH_BASE_URL` van hostnaam wisselde.

### 2026-08-09
- Atmos-diagnose: bitstream werkt aantoonbaar op iOS (`JOC=yes`), `audio-exclusive` en MPVKit-bisect afgevoerd als spoor. Twee echte defecten gevonden: de badge hangt aan een property die `not-applicable` teruggeeft, en loudnorm vecht met passthrough. Zie [DEC-013](docs/DECISIONS.md#dec-013).
- Builds 210 t/m 212: `auto` bitstreamt niet meer (`a0a2018`), daarna een vangnet dat binnen een seconde terugvalt op PCM en de route onthoudt (`87844bb`).
- `current-ao` en `audio-out-params/format` toegevoegd aan de performance-HUD, plus de Android-pariteit. Nog niet gecommit.
- `ice.pleya.app` bleek nooit te hebben bestaan; `server/` omgezet van `ice.plezy.app`, tunnel-compose, deploy-script en README erbij, lokaal end-to-end getest. Zie [DEC-014](docs/DECISIONS.md#dec-014).

### 2026-08-07/08
- Dolby Atmos en spatial audio op iOS en tvOS (`87c5e04`, build 207): de ontbrekende schakel was `setSupportsMultichannelContent(true)`, niet mpv. Introduceerde ook de auto-passthrough die in build 211 weer terugging.
- Blu-ray ISO's en uitgepakte BDMV-mappen afspelen (`de48dbb`): libbluray zat al in de bundle, alleen de Dart-kant ontbrak.
- Seerr Ontdekken zegt nu wát er misging in plaats van altijd "probeer opnieuw" (`24f9054`).

### 2026-08-05
- Zoeken op elk apparaat: Siri Remote-dictatie via het systeem-toetsenbord op Apple TV, plus zeven focus/selectie/popup-fixes waaronder twee globale (`SelectKeyUpSuppressor`, verweesde key-ups). Commit `3b193f8`, build 202 op iOS/tvOS/macOS.
- Repo gesynchroniseerd: `main` 64 commits bijgewerkt naar `origin/main` en de lokale `test`-branch gemerged.
- Xcode-toolchain hersteld (componenten stonden op 26.3 tegen Xcode 26.6) — zie [DEC-010](docs/DECISIONS.md#dec-010).

Ouder dan dit: zie [docs/CHANGELOG.md](docs/CHANGELOG.md).

Zie [docs/DECISIONS.md](docs/DECISIONS.md) voor keuzes, [docs/CHANGELOG.md](docs/CHANGELOG.md) voor details en [docs/PLEYA_SHARE.md](docs/PLEYA_SHARE.md) voor de share-architectuur.
