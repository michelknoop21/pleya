# STATUS · Pleya

_Laatst bijgewerkt: 2026-08-17 16:30 (`main` = `8009300`; de dependency-onderhoudsronde is gerebased op `7721859` en geland. Er loopt parallel een tweede sessie met ongecommit werk in de hoofdmap. App Store Connect 2.8.0 hangt op iOS, tvOS én macOS aan build 220 en staat op alle drie `PREPARE_FOR_SUBMISSION`)_

## Waar was ik

**Dependency-onderhoud kreeg een proces, en dat proces ving meteen twee stille regressies.** Alleen MPVKit had een controle; elke andere pin werd pas zichtbaar als iemand er toevallig naar keek. Er staan nu drie dingen: `.fvmrc` als enige bron voor de Flutter-versie met een preflight die drift weigert, `classify_lock_diff.sh` die per gewijzigd pakket een ring afleidt uit de eigenschappen van de wijziging, en `check_updates.sh` dat elke pin in één rapport zet met vier statussen in plaats van twee. Zie [DEC-025](docs/DECISIONS.md#dec-025).

Het beleid bewees zichzelf tijdens de eerste ronde. De analyzer-stack kwam er als ring 1 uit en `flutter analyze` was groen, maar de codegen-controle liet zien dat `drift_dev` de hele relatie tussen `connections` en `profile_connections` uit `app_database.g.dart` weglaat: foreign key, cascade, writepropagatie en reference manager, 298 regels, zonder één waarschuwing. Zie [DEC-026](docs/DECISIONS.md#dec-026); `test/database/drift_relations_test.dart` bewaakt het nu. `rate_limiter` 1.1.1 viel om dezelfde reden af: het leest de tijd sinds 1.1.0 via `package:clock`, waardoor de zoekdebounce onder de fake clock van `flutter_test` anders vuurt. Netto zijn 27 pakketten bijgewerkt met `pubspec.yaml` ongemoeid, plus zes GitHub Actions en vijf third-party actions op een commit-SHA.

Onderweg bleek de committede gegenereerde code al scheef te staan: geformatteerd met homebrew-3.44.4 terwijl CI 3.44.0 pint, 4001 regels verschil. De controle-run op `main` bevestigt dat los van mij, want daar faalt CI op "Generated files are out of date" ([32032784299](https://github.com/michelknoop21/pleya/actions/runs/32032784299)); op de branch is die stap groen. Dit waren de eerste Actions-runs die deze repo ooit heeft gehad; `origin` is een Gitea-instance, dus er was geen historie om tegen af te zetten.

## Eerder vandaag

**De reviewbuild hing niet aan de versie, en dat koppelen doet de lane nu zelf.** De 2.1(a)-afwijzing was allang uitgezocht en gerepareerd, maar de drie App Store-versies stonden nog op build 156: precies de build die Apple afwees. Build 220 met de inlogfix stond sinds 15 augustus in TestFlight, macOS had zelfs helemaal geen build gekoppeld. Alle drie zijn nu op 220 gezet, waarmee iOS uit `REJECTED` kwam. Omdat dit de derde keer is dat de stap tussen "geüpload" en "indienbaar" stil misgaat, koppelen `ios_beta`, `tvos_beta` en `macos_beta` de build voortaan zelf, met `fastlane attach_builds` als vangnet. Zie [DEC-022](docs/DECISIONS.md#dec-022). Reviewnotities, demo-account en demoserver zijn opnieuw nagelopen en kloppen: `demo.pleya.app` antwoordt in 296 ms, het account `applereview` authenticeert en de drie Blender-films staan er.

## Eerder vandaag

**De kijklijst is af en het Live TV-tokenlek is dicht.** De kijklijst kreeg zijn laatste twee stukken: Nederlandse vertalingen plus [DEC-020](docs/DECISIONS.md#dec-020), en alsnog de sorteerkeuze die het plan beloofde maar het scherm niet had (recent toegevoegd, titel, jaar, volledig client-side). Daarna het lek dat sinds fase 0 als losse fix openstond: de favorieten van Live TV gingen via `PlexClient` naar `epg.provider.plex.tv`, en die client draagt de PMS-servertoken in `defaultHeaders` die ook bij een absolute URL meegaat. Eerst gemeten tegen een echt account, daarna in negen commits verhuisd naar `PlexCloudHttpClient`, de gedeelde transportgrens waar de kijklijst nu ook op staat. Zie [DEC-021](docs/DECISIONS.md#dec-021).

Twee dingen kwamen onderweg boven die er los van stonden. De leescall liep door `FailoverHttpClient`, die alleen `get` overridet, dus een 5xx bij plex.tv kon de endpoint-cascade van je eigen server starten. En een mislukte lees gaf `[]`, waarna één ster aantikken die leegte terugschreef als de volledige lijst van het account. Beide dicht.

## Eergisteren en gisteren

Gisteren landde de kijklijst zelf: identiteit en het multi-membership-model, de Plex-cloudclient op een gemeten contract, artwork zonder token in de cachekey, repository, beschikbaarheid met eerlijke dekking, offline-snapshot, provider, Mijn Pleya op mobiel met Watchlist in de sidebar, het kijklijst-scherm en de schrijfacties. Vijftien commits van `310ace8` tot `11ec313`; de details staan in [docs/CHANGELOG.md](docs/CHANGELOG.md).

Eergisteren reageerde het systeemtoetsenbord op Apple TV weer op de Siri Remote, bevestigd op het toestel met build 219. De engine claimt elke press al in `sendEvent:` en slaat de originele implementatie over, dus UIKit begint zijn responder chain nooit; het eigendom ligt nu terug op `PleyaFlutterViewController.tvosHandlePress(fromUIEvent:)`. Zie [DEC-019](docs/DECISIONS.md#dec-019) en de gotcha in `CLAUDE.md`.

## Eerder werk, ongewijzigd

Twee opstartbugs dichtgezet en 2.8.0 klaargemaakt voor herindiening. De Apple-afwijzing van 6 juli (2.1(a), *"Authentication timed out"*) bleek geen app-fout: die string komt uit precies één plek, de Plex PIN-flow, dus de reviewer koos "Sign in with Plex" met het Jellyfin-demoaccount. De uitweg naar Jellyfin bestond al, maar hing in het foutblok: en de poll staat op vijf minuten, dus hij kwam pas ná vijf minuten staren. Hij staat nu ook onder de PIN zelf, en breekt de lopende poging af (anders navigeert een alsnog geclaimde PIN dwars door het Jellyfin-scherm heen). Zie [DEC-015](docs/DECISIONS.md#dec-015). Het lege profielscherm op macOS bleek twee dingen tegelijk: één toestand voor "laadt nog", "leeg" en "stilgevallen", en een toevoeg-knop die structureel ónder de vouw stond omdat macOS in pointer-modus start en niets hem in beeld scrolt. Beide los, plus een logregel die bij de volgende koude start moet verklappen wélke van de vier bronnen stilvalt. Zie [DEC-016](docs/DECISIONS.md#dec-016). Het Atmos-onderzoek staat ongewijzigd stil op de meting hieronder.

Het Atmos-spoor staat er nog precies zo bij als gisteren: een iOS-log van build 211 laat zien dat de bitstream-keten gewoon wérkt: `spdif_eac3` komt op, de avfoundation-sink pakt hem, en de fork logt `JOC=yes`, dus de Atmos-objecten van Ted Lasso S4E1 bereiken de renderer. Daarmee vallen twee van de drie oorspronkelijke verdachten af: `audio-exclusive` heeft in deze libmpv geen enkele consument (geen coreaudio, geen wasapi), en een MPVKit-bisect is zinloos omdat de sink in 1.0.16 aantoonbaar functioneert. Wat er wél uit kwam: de app kan niet zien dát Atmos loopt, want `AVAudioSession.renderingMode` geeft tijdens de werkende bitstream `not-applicable` en de badge hangt volledig aan die property. En loudness-normalisatie sluit passthrough uit zonder dat iets dat coördineert, terwijl Android TV datzelfde conflict al arbitreert maar precies andersom. Zie [DEC-013](docs/DECISIONS.md#dec-013). Verder ontdekt dat `ice.pleya.app` nooit heeft bestaan, waardoor de log-uploadknop altijd stil faalde; de Go-relay stond al klaar in `server/`, alleen op de verkeerde hostnaam. Zie [DEC-014](docs/DECISIONS.md#dec-014).

## Volgende stap

**Een nieuwe TestFlight-upload draaien, want build 221 is er nooit gekomen.** Daarna de kijklijst op een toestel doorlopen. Vier dingen, in deze volgorde. Op de Apple TV via de sidebar naar Watchlist: staat de focusring op de eerste rij, werkt randnavigatie, sluit Menu de sheet, en kloppen de focusvolgorde van de nieuwe detailknop en het contextmenu-item. Daarna wisselen tussen twee Plex Home-gebruikers: de lijst moet meewisselen en geen enkel item van de vorige gebruiker tonen. Dan dezelfde film die zowel Plex-watchlist als Jellyfin-favoriet is verwijderen, en kijken of hij uit beide verdwijnt. En tot slot netwerk uit met een gedownloade titel: die moet speelbaar blijven, sorteren en de typefilters moeten blijven werken, en alleen het filter Beschikbaar hoort te vervallen. De volledige lijst staat in `~/.claude/plans/wat-ik-wel-echt-synchronous-piglet.md` onder Verificatie.

De favorieten van Live TV kun je in dezelfde ronde niet meenemen: dat vraagt een Plex-account met een tuner, en dit account heeft er geen. Zie de blocker daarover.

**Daarna de rest van de tvOS-regressieronde, op de fysieke Apple TV met build 219 of nieuwer.** De vijf fixes van 14 augustus zijn allang gemaakt en zitten in build 219, met unit- en widgetdekking; het toetsenbord is daarnaast op het toestel bevestigd (`6bab0ca`, zie [DEC-019](docs/DECISIONS.md#dec-019)). Wat overblijft is wat alleen een echte Siri Remote kan aantonen: tijdens een intro omhoog naar de skip-knop en er weer uit, tijdens de aftiteling tellen hoeveel volgende-aflevering-knoppen er staan, en een aflevering uitkijken om te zien of hij vanzelf doorgaat, ook ná een eerdere seek in dezelfde sessie, want dat was het no-op-scenario. Scrubben hoort daarbij: pauzeren en met de balk een positie kiezen. En als laatste een log uploaden na een lange kijksessie, plus direct nog eens drukken voor de "te snel"-melding; die is 14 augustus gerepareerd maar nooit op een echte sessielengte gemeten. De volledige volgorde staat in `~/.claude/plans/ik-wil-dat-je-starry-possum.md`.

Neem het typen in zoeken, inloggen, server-URL en Seerr onderweg wel even mee, niet als los testpunt maar als waarschuwingslampje: reageert de remote na het sluiten van het toetsenbord nergens meer op, dan is dat het resterende native risico uit [DEC-017](docs/DECISIONS.md#dec-017) en geen los raadsel.

**Daarna pas de oude sporen hieronder.** Die staan ongewijzigd stil.

**De reviewroute op de iPad naspelen met build 220, en daarna indienen.** Installeer schoon, kies bewust "Sign in with Plex" en voer het demo-account in: de Jellyfin-uitweg hoort meteen zichtbaar te zijn, niet pas na vijf minuten. Daarna dezelfde route via de Jellyfin-knop (`demo.pleya.app`, `applereview`) en afspelen tot beeld. Klopt dat, dan het antwoord uit `docs/app-review-reply-2026-08.md` versturen via Resolution Center en 2.8.0 opnieuw indienen, op alle drie de platforms. Het koppelen is al gedaan: iOS, tvOS en macOS dragen build 220 en staan op `PREPARE_FOR_SUBMISSION`, dus alleen de indien-knop resteert.

Daarna macOS koud starten (verschijnt er nu een spinner, een lege staat mét knop, of een expliciete fout? en wat zegt de nieuwe `profiles_view`-regel in Instellingen → Logs), met als tegenproef een pijltje omlaag in plaats van Esc.

**Tweede spoor, ongewijzigd: de meting op de Apple TV zelf.** Alle audiologs tot nu toe komen van de iPhone.

Correctie van 14 augustus op de aanname hieronder: de uploadknop wérkte niet, ook niet nadat de host live ging. De client las de statuscode nooit en verstuurde tot 5 MB terwijl de relay 1 MB accepteert, dus een lange kijksessie liep gegarandeerd op een 413 die als generieke fout aankwam. Dat is opgelost, maar het vraagt wel **build 216 of nieuwer** op het toestel. Tweede voorbehoud: mpv-regels bereiken `appLogger` alleen op error- en fatal-niveau (`parts/errors.dart`, gevoed door het filter in `parts/playback_services.dart`), dus zelfs een geslaagde upload bevat de `spdif_eac3`- en `JOC=yes`-regels hieronder waarschijnlijk niet. Wil je die meting echt doen, dan moet dat filter eerst info en verbose doorlaten zolang debug-logging aanstaat, of je haalt de log rechtstreeks op met `devicectl` (zie Quick start).

Zet normaliseren uit, audiomodus op Doorvoeren, speel Ted Lasso S4E1, en upload de log via Instellingen, Logs, upload-icoon. Dat geeft een code van vijf tekens; daarmee is de log op te halen met `curl https://ice.pleya.app/logs/<id>`. In die log moet staan: `Selected decoder: spdif_eac3`, `AO: [avfoundation] … spdif-eac3`, `EAC3 config: … JOC=yes`, plus wat `supported output channel layouts` en `audio rendering mode` op tvOS teruggeven. Werkt Atmos daar aantoonbaar, dan gaat het implementatieplan door; blijft het weg terwijl die regels er wél staan, dan ligt het buiten de app.

Het uitgewerkte implementatieplan (arbiter, badge uit de beslissing, `auto` op digitale poorten) staat in `~/.claude/plans/pleya-v2-8-0-211-ios-smooth-frog.md`.

## Blockers

- [ ] **Twee tests falen op de Linux-runner en niet lokaal op macOS**: `side_navigation_rail_test.dart: Apple TV D-pad focus skips hidden downloads item` (verwacht `NavigationTabId.settings`, krijgt `null`) en `pleya_share_pair_any_test.dart: pairAny pairs via a later candidate when the first IP is dead`. Aantoonbaar niet van het dependency-werk: de controle-run op `main` van vóór die branch geeft exact dezelfde twee (branch [32031692723](https://github.com/michelknoop21/pleya/actions/runs/32031692723), controle op main [32032784299](https://github.com/michelknoop21/pleya/actions/runs/32032784299)). Ze zijn nooit eerder gezien omdat GitHub Actions op deze repo nog nooit had gedraaid; `origin` is een Gitea-instance. Bewust niet gerepareerd in de dependency-ronde.
- [ ] **`softprops/action-gh-release@v3` is niet in een echte run bewezen**: `build.yml` leidt `tag_name` af uit een tag-ref, en een `workflow_dispatch` op een branch heeft die niet, dus de stap faalt met `Missing tag_name parameter` voordat de actie iets doet. Dat is een eigenschap van het dispatchen, niet van de versiebump. Alle andere bijgewerkte actions zijn wél groen gedraaid, inclusief de artefact-heenweg `upload-artifact@v7` naar `download-artifact@v8` (Build-run [32031695034](https://github.com/michelknoop21/pleya/actions/runs/32031695034), alleen Linux). Er is daardoor ook geen draft release aangemaakt om op te ruimen.
- [ ] **Kijklijst op een toestel**: alles is unit- en widget-gedekt (3264 tests), maar de TV-focusronde, de profielwissel tussen twee Plex Home-gebruikers, het verwijderen van een gemergde entry en de offline-ronde zijn alleen op een toestel te zien. **Build 221 bestaat niet in App Store Connect**: het hoogste nummer is op alle drie de platforms 220 van 15 augustus, en dat is vóór het kijklijstwerk. Er moet dus eerst een nieuwe upload draaien.
- [ ] **De scope van `favoriteChannels` is niet gemeten**: dit Plex-account heeft geen provider met het `livetv`-protocol, dus er bestaat geen geldige `source` en een synthetische regel wordt geweigerd met 400. Of die lijst per account of per Home-gebruiker is, blijft daarmee open. De proef die het beslist: een account met een echte tuner, favoriet zetten als gebruiker A, teruglezen als B. Het meetscript kan dat al zodra er een tuner is. Geen blocker voor de gedichte credentialgrens, wel voor de vraag of de gekozen profielscope semantisch klopt met wat Plex opslaat.
- [ ] **Live TV-favorieten zijn niet te verifiëren zonder tuner**: dezelfde reden. Bewuste achteruitgang die daarbij hoort: een Home-gebruiker van wie de binding nog loopt ziet geen favorieten, waar de servertoken vandaag wél een antwoord gaf. Zie [DEC-021](docs/DECISIONS.md#dec-021).
- [ ] **Regressieronde op de fysieke Apple TV**: de vijf fixes van 14 augustus zitten inmiddels in tvOS build 219 en zijn unit- en widget-gedekt, maar de Siri Remote is niet te simuleren. Het toetsenbord is los bevestigd (zie hierboven); de skip-knoppen, autoplay en het scrubben nog niet.
- [ ] **Autoplay-vlaggen na een overgenomen herlaadpoging zijn niet door een test gedekt**: de opruiming zit in een `finally` in `_reloadMediaInPlace`, maar die logica leeft in een private extensie op de schermstaat en testen vraagt een volledig spelerharnas. Bewust overgeslagen; de dekking leunt hier op de deviceronde.
- [ ] **Scrubben: hervatten wacht niet op de seek**: bij bevestigen volgt `player.play()` direct op `onSeekEnd`, want die geeft geen future terug. Op mpv landen de commando's in volgorde, maar of er een frame op de oude positie doorschemert is alleen op een toestel te zien.
- [x] ~~**Log-upload werkte niet**~~ opgelost 2026-08-14. Niet de host: de client las de statuscode nooit en verstuurde tot 5 MB terwijl de relay 1 MB accepteert. Zie de CHANGELOG-entry van 14 augustus.
- [x] ~~**macOS-builds bereikten geen tester sinds 196**~~ opgelost 2026-08-14, zie [DEC-018](docs/DECISIONS.md#dec-018).
- [ ] **App Review-antwoord nog niet verstuurd en 2.8.0 nog niet opnieuw ingediend**: de tekst staat klaar in `docs/app-review-reply-2026-08.md`. Alles eromheen is af: build 220 hangt aan alle drie de versies, de reviewnotities waarschuwen tegen "Sign in with Plex", en de demoserver is vandaag nagemeten. Verstuur de reply samen met de herindiening, niet los, anders blijft er niets veranderd voor de reviewer.
- [ ] **Toestelverificatie van de twee fixes van 10 augustus**: iPad (Jellyfin-uitweg tijdens het pollen) en macOS (koude start van het profielscherm). Beide zitten in build 220, de build die nu ook aan de reviewversies hangt; tot die check is de fix alleen door tests gedekt.
- [ ] **Welke van de vier profielbronnen stilvalt op macOS is nog onbewezen**: de nieuwe `profiles_view`-logregel moet het bij de eerstvolgende koude start noemen. Verdachte: `ConnectionRegistry.watchConnections()`.
- [ ] **Apple TV-meting**: geen enkele log komt van het toestel zelf, dus stap 4 van het audioplan (`auto` weer laten bitstreamen) staat geblokkeerd op bewijs.
- [ ] **Pleya Share tegen de productierelay**: de host draait nu, maar het framecontract (arbitraire rooms, >2 peers, object-payloads, ~90KB frames) is alleen tegen de lokale stub getest. Nu wél testbaar.
- [ ] **OAuth redirect-URI's**: `OAUTH_BASE_URL` staat op `ice.pleya.app`, dus MyAnimeList en AniList moeten `https://ice.pleya.app/auth/<service>/callback` geregistreerd hebben voordat tracker-koppelen werkt.
- [x] ~~**ice.pleya.app** bestond niet~~, opgelost 2026-08-10. Draait op de NAS achter een Cloudflare Tunnel; `/health` en de volledige log-upload-route publiek geverifieerd.
- [ ] **Wi-Fi Aware iOS**: alleen compile-bewezen (Xcode 26.3/SDK 26.2); echte verbinding vereist iPhone 12+ op iOS 26.
- [ ] **31 schermafbeeldingen voor de handleiding**: eigen contentronde, niet mengen met nieuwe documentatiefuncties. De techniek eromheen staat klaar: `docs/manual/SCREENSHOTS.md` heeft per schot het bestand, het scherm, het toestel en wat erop moet, de paden liggen vast op `/docs-media/<naam>.png`, en een ontbrekend bestand tekent een plaatshouder in plaats van een kapotte afbeelding. Klaar is: alle 31 in `website/static/docs-media/` en geen plaatshouder meer op `/docs`. Voorgestelde eerste helft: de elf schoten van de acht meestbezochte hoofdstukken. Vraagt een ingelogd toestel per vormfactor en alleen Blender-content in beeld, dezelfde grens als bij de ASC-screenshots.
- [x] ~~**`ScrollReveal` kan content onzichtbaar laten op de landingspage**~~ opgelost 2026-08-17. De observer is eruit; `.scroll-reveal` draait nu dezelfde CSS-only `fade-in-up` als de hoofdstukindex op `/docs`, met `animation-delay` voor de stagger en `animation: none` onder `prefers-reduced-motion`. Twee correcties op de melding hieronder. De blanco pagina in het schot van 1440×3000 was misleidend: de hero vult `100vh`, dus bij die vensterhoogte begint `Screenshots` op y=3120 en valt de rest simpelweg buiten de capture. En met JavaScript aan vuurde de observer wél, 28 van de 37 wrappers kwamen op `opacity: 1` na langzaam doorscrollen. Wat er echt stuk was, blijft twee dingen. Zonder JavaScript bleef 37 van de 37 permanent op `opacity: 0`, met volle hoogte aan lege ruimte, want de gebouwde HTML draagt de inline `opacity: 0`. En de negen telefoons die horizontaal buiten de schermenrail staan werden nooit zichtbaar, ook niet met JavaScript, omdat ze nooit in beeld komen zonder de rail zelf te schuiven. Bewijs: paginahoogte gelijk voor en na (5155 px bij 1440, 5936 px bij 390), en een pixeldiff van de volledige pagina met JavaScript aan verschilt op 0,03% van de pixels, allemaal in de band van de pulserende hero-gloed. `animation-timeline: view()` bewust niet gekozen: dat hangt de voortgang weer aan de scrollpositie en laat een fullpage-capture onder de vouw opnieuw leeg.

## Toolchain-valkuil

Na een Xcode-update faalt **élke** build (ook fastlane) tot Xcode één keer handmatig is gestart, want de systeemcomponenten in `/Library/Developer/PrivateFrameworks/` blijven anders achter bij Xcode.app. `xcodebuild -runFirstLaunch` lost het niet op. Check: `pkgutil --pkg-info com.apple.pkg.XcodeSystemResources` moet dezelfde versie tonen als `xcodebuild -version`. Zie [DEC-010](docs/DECISIONS.md#dec-010).

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

### 2026-08-17
- Dependency-onderhoud kreeg een proces, geland op `main` van `9575b6c` tot `8009300`: `.fvmrc` plus preflight, `classify_lock_diff.sh`, 27 ring-1-pakketten, GitHub Actions bijgewerkt en third-party op SHA, `check_updates.sh` met de `dependency-health`-workflow, en [DEC-025](docs/DECISIONS.md#dec-025) plus [DEC-026](docs/DECISIONS.md#dec-026).
- Het landen zelf vroeg één ingreep. `pubspec.lock` is niet met de hand gemerged maar opnieuw opgebouwd vanaf de lockfile van `main`, met een gerichte `flutter pub upgrade` op de 27 pakketten. De uitkomst is de vereniging van beide kanten: `classify_lock_diff.sh` meldt 27 gewijzigd met ring1=27 en geen UNKNOWN, en `mobile_scanner` blijft op 7.4.0. Op de combinatie is de gegenereerde diff leeg, `ci_checks.sh` groen, `flutter test` 3308 groen en `check_updates.sh --strict-through-ring 1` exit 0.
- De analyzer-stack en `rate_limiter` vielen af doordat de bewijsstap ze ving, niet de classificatie. De drift-regressie is nu vastgelegd in `test/database/drift_relations_test.dart`.
- Eerste GitHub Actions-runs ooit op deze repo. Twee bestaande Linux-only testfouten zichtbaar geworden; de controle-run op `main` bevestigt dat ze er al waren.
- Kijklijst afgemaakt: Nederlandse vertalingen (`195904e`), [DEC-020](docs/DECISIONS.md#dec-020) (`dd75c69`) en alsnog de sorteerkeuze op recent, titel en jaar (`3634fa0`), volledig client-side zodat hij offline blijft werken.
- Het Live TV-tokenlek gedicht in negen commits (`a089264` tot `d867260`), na een meting tegen een echt account. `PlexCloudHttpClient` is nu de transportgrens naar plex.tv en de kijklijst staat er ook op. Onderweg twee losse defecten mee: de cloudcall kon de endpoint-failover van je eigen server triggeren, en een mislukte lees wiste je favorieten bij de eerstvolgende tik. Zie [DEC-021](docs/DECISIONS.md#dec-021).
- 3264 tests groen (was 3202), `scripts/ci_checks.sh` schoon, gepusht naar beide remotes. De upload van build 221 is gestart maar heeft App Store Connect nooit bereikt.
- App Store Connect rechtgezet: build 220 gekoppeld aan de versies 2.8.0 van iOS, tvOS en macOS, die alle drie nog op de afgewezen build 156 stonden (macOS op niets). iOS ging daarmee uit `REJECTED`.
- Het koppelen geautomatiseerd in `fastlane/Fastfile`, met `fastlane attach_builds` als losse lane, plus documentatie in `docs/TESTFLIGHT.md`. Zie [DEC-022](docs/DECISIONS.md#dec-022) en commit `f7b583f`.
- Demoserver en reviewnotities nagelopen en in orde bevonden; het antwoord in `docs/app-review-reply-2026-08.md` is bijgewerkt en klaar om te versturen.

### 2026-08-16
- Mijn Pleya en de kijklijst gebouwd, vijftien commits van `310ace8` tot `11ec313`: datalaag met multi-membership, Plex-cloudclient op een gemeten contract, beschikbaarheid met eerlijke dekking, offline-snapshot, navigatie, scherm en schrijfacties.
- Het API-contract eerst gemeten en gesaniteerd vastgelegd in `test/fixtures/watchlist/`; vier planaannames sneuvelden daarop.

### 2026-08-15
- Het tvOS-systeemtoetsenbord reageert weer op de Siri Remote (`6bab0ca`, build 219, op het toestel bevestigd). Oorzaak uit de engine-binary bewezen, fix via een override van `tvosHandlePressFromUIEvent:`. Zie [DEC-019](docs/DECISIONS.md#dec-019); de gotcha staat in `CLAUDE.md` zodat dit niet opnieuw verloren gaat.
- `main` en `test` weer gelijkgetrokken (`b3dc5b2`), inclusief twee commits die alleen op `test` stonden: de hero die verdween na het zoektoetsenbord, en de watch-state-sync waarbij een tweede apparaat wint van een verouderde lokale positie. 2935 tests groen.

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

Ouder dan dit: zie [docs/CHANGELOG.md](docs/CHANGELOG.md).

Zie [docs/DECISIONS.md](docs/DECISIONS.md) voor keuzes, [docs/CHANGELOG.md](docs/CHANGELOG.md) voor details en [docs/PLEYA_SHARE.md](docs/PLEYA_SHARE.md) voor de share-architectuur.
