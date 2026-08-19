# STATUS · Pleya

_Laatst bijgewerkt: 2026-08-19 11:30 (`main` = `3754ab4`. Build 228 en 229 staan op TestFlight, 230 is aan het bouwen. De werkboom is schoon: het Tautulli-werk van de parallelle sessie is in `6e595f1` vastgelegd. App Store Connect 2.8.0 hangt op iOS, tvOS en macOS aan build 229 en staat op `PREPARE_FOR_SUBMISSION`)_

## Waar was ik

**De aanvragen-schermen gerepareerd, vier losse meldingen erbij, en daarna het taalgeheugen van de ondertiteling.** De aanvraaglijst toonde als kop alleen "Film" of "TV Serie" met een grijze placeholder, omdat `/request` van Overseerr geen titel of poster meestuurt en niets dat aanvulde. Verder een zwart scherm bij sorteren in de kijklijst (een sheet die de app onder zichzelf vandaan popte), een segmented control waarvan de selectie onzichtbaar was, de skip-intro-knop die bij films bleef staan, en het kwaliteitsprofiel bij een aanvraag dat nooit gebouwd bleek. Tien werkstromen, apart te committen, in de builds 228 en 229.

Daarna de melding dat de ondertiteltaal niet wordt onthouden. Die werkt alleen bij direct play: zodra Plex transcodeert wisselt de kiezer een bronstroom in plaats van een mpv-spoor, en dat pad bereikte de opslag nooit. Een onafhankelijke review op die fix vond vervolgens een race die ik er zelf in had gezet. Zie de twee CHANGELOG-entries van 18 en 19 augustus.

## 17 augustus, avond

**De reviewbuild hing niet aan de versie, en dat koppelen doet de lane nu zelf.** De 2.1(a)-afwijzing was allang uitgezocht en gerepareerd, maar de drie App Store-versies stonden nog op build 156: precies de build die Apple afwees. Build 220 met de inlogfix stond sinds 15 augustus in TestFlight, macOS had zelfs helemaal geen build gekoppeld. Alle drie zijn nu op 220 gezet, waarmee iOS uit `REJECTED` kwam. Omdat dit de derde keer is dat de stap tussen "geüpload" en "indienbaar" stil misgaat, koppelen `ios_beta`, `tvos_beta` en `macos_beta` de build voortaan zelf, met `fastlane attach_builds` als vangnet. Zie [DEC-022](docs/DECISIONS.md#dec-022). Reviewnotities, demo-account en demoserver zijn opnieuw nagelopen en kloppen: `demo.pleya.app` antwoordt in 296 ms, het account `applereview` authenticeert en de drie Blender-films staan er.

## 17 augustus

**De kijklijst is af en het Live TV-tokenlek is dicht.** De kijklijst kreeg zijn laatste twee stukken: Nederlandse vertalingen plus [DEC-020](docs/DECISIONS.md#dec-020), en alsnog de sorteerkeuze die het plan beloofde maar het scherm niet had (recent toegevoegd, titel, jaar, volledig client-side). Daarna het lek dat sinds fase 0 als losse fix openstond: de favorieten van Live TV gingen via `PlexClient` naar `epg.provider.plex.tv`, en die client draagt de PMS-servertoken in `defaultHeaders` die ook bij een absolute URL meegaat. Eerst gemeten tegen een echt account, daarna in negen commits verhuisd naar `PlexCloudHttpClient`, de gedeelde transportgrens waar de kijklijst nu ook op staat. Zie [DEC-021](docs/DECISIONS.md#dec-021).

Twee dingen kwamen onderweg boven die er los van stonden. De leescall liep door `FailoverHttpClient`, die alleen `get` overridet, dus een 5xx bij plex.tv kon de endpoint-cascade van je eigen server starten. En een mislukte lees gaf `[]`, waarna één ster aantikken die leegte terugschreef als de volledige lijst van het account. Beide dicht.

## 15 en 16 augustus

Gisteren landde de kijklijst zelf: identiteit en het multi-membership-model, de Plex-cloudclient op een gemeten contract, artwork zonder token in de cachekey, repository, beschikbaarheid met eerlijke dekking, offline-snapshot, provider, Mijn Pleya op mobiel met Watchlist in de sidebar, het kijklijst-scherm en de schrijfacties. Vijftien commits van `310ace8` tot `11ec313`; de details staan in [docs/CHANGELOG.md](docs/CHANGELOG.md).

Eergisteren reageerde het systeemtoetsenbord op Apple TV weer op de Siri Remote, bevestigd op het toestel met build 219. De engine claimt elke press al in `sendEvent:` en slaat de originele implementatie over, dus UIKit begint zijn responder chain nooit; het eigendom ligt nu terug op `PleyaFlutterViewController.tvosHandlePress(fromUIEvent:)`. Zie [DEC-019](docs/DECISIONS.md#dec-019) en de gotcha in `CLAUDE.md`.

## Eerder werk, ongewijzigd

Twee opstartbugs dichtgezet en 2.8.0 klaargemaakt voor herindiening. De Apple-afwijzing van 6 juli (2.1(a), *"Authentication timed out"*) bleek geen app-fout: die string komt uit precies één plek, de Plex PIN-flow, dus de reviewer koos "Sign in with Plex" met het Jellyfin-demoaccount. De uitweg naar Jellyfin bestond al, maar hing in het foutblok: en de poll staat op vijf minuten, dus hij kwam pas ná vijf minuten staren. Hij staat nu ook onder de PIN zelf, en breekt de lopende poging af (anders navigeert een alsnog geclaimde PIN dwars door het Jellyfin-scherm heen). Zie [DEC-015](docs/DECISIONS.md#dec-015). Het lege profielscherm op macOS bleek twee dingen tegelijk: één toestand voor "laadt nog", "leeg" en "stilgevallen", en een toevoeg-knop die structureel ónder de vouw stond omdat macOS in pointer-modus start en niets hem in beeld scrolt. Beide los, plus een logregel die bij de volgende koude start moet verklappen wélke van de vier bronnen stilvalt. Zie [DEC-016](docs/DECISIONS.md#dec-016). Het Atmos-onderzoek staat ongewijzigd stil op de meting hieronder.

Het Atmos-spoor staat er nog precies zo bij als gisteren: een iOS-log van build 211 laat zien dat de bitstream-keten gewoon wérkt: `spdif_eac3` komt op, de avfoundation-sink pakt hem, en de fork logt `JOC=yes`, dus de Atmos-objecten van Ted Lasso S4E1 bereiken de renderer. Daarmee vallen twee van de drie oorspronkelijke verdachten af: `audio-exclusive` heeft in deze libmpv geen enkele consument (geen coreaudio, geen wasapi), en een MPVKit-bisect is zinloos omdat de sink in 1.0.16 aantoonbaar functioneert. Wat er wél uit kwam: de app kan niet zien dát Atmos loopt, want `AVAudioSession.renderingMode` geeft tijdens de werkende bitstream `not-applicable` en de badge hangt volledig aan die property. En loudness-normalisatie sluit passthrough uit zonder dat iets dat coördineert, terwijl Android TV datzelfde conflict al arbitreert maar precies andersom. Zie [DEC-013](docs/DECISIONS.md#dec-013). Verder ontdekt dat `ice.pleya.app` nooit heeft bestaan, waardoor de log-uploadknop altijd stil faalde; de Go-relay stond al klaar in `server/`, alleen op de verkeerde hostnaam. Zie [DEC-014](docs/DECISIONS.md#dec-014).

## Volgende stap

**De drie live tests op een toestel, met build 230.** Ze vragen alle drie de echte server en zijn niet met tests te dekken. Eerst de aanvraaglijst op de iPhone: staan er echte titels en posters, en klopt de status per regel? Zet daarbij debuglogging aan en filter op `seerr: could not resolve`; die regel onderscheidt een lege titel door ontbrekende data van een mislukte verrijking. Daarna één wegwerpaanvraag met bewust gekozen server, kwaliteitsprofiel en rootmap, en in Radarr of Sonarr controleren dat exact die waarden zijn opgeslagen, niet alleen dat Overseerr 200 teruggaf. Dezelfde ronde voor een serie via Sonarr. Verwijder de testaanvraag daarna.

Dan de ondertiteltaal op de Apple TV: kies bij een aflevering een taal terwijl Plex transcodeert, en kijk of de volgende aflevering ermee start. Werkt dat niet, dan zegt de log welke prioriteit won.

## Blockers

- [ ] **De aanvragen-flow is niet tegen de echte server gezien**: titel- en posterverrijking, en of een gekozen kwaliteitsprofiel echt zo in Radarr of Sonarr landt. Alles eromheen is gedekt (aanvraagregel, seizoenen, statuschips, badge, filterbalk, i18n, plus vier tests die de kosten van de verrijking meten), maar de verrijking zelf praat met Overseerr en dat is alleen op een toestel te zien. Build 229 of nieuwer.
- [ ] **Het taalgeheugen bij transcoding is alleen door tests gedekt**: het opzoeken van de taal bij een stream-id en de Plex-mapping zijn getest, de echte wissel op een Apple TV niet. Vraagt build 230.
- [ ] **`SeerrProvider` heeft geen injecteerbare http-client**: `SeerrClient` accepteert er wel een (de client-tests gebruiken `MockClient`), maar de provider bouwt zijn eigen. Daardoor is de aanvraag-sheet met de server-, profiel- en rootmapkeuze niet met gestubde HTTP te testen. Afgesproken: niet nu refactoren, wel eerst dependency injection bij de volgende substantiële Seerr-uitbreiding.
- [ ] **Twee gaten in het taalgeheugen die los staan van de gemelde bug**: een ondertitelspoor zonder taalcode wordt niet onthouden (`track_manager.dart:449`, raakt losse SRT-bestanden), en de iCloud-synchronisatie vervangt de hele voorkeurenkaart in één keer in plaats van per titel samen te voegen, dus een verouderde snapshot op een tweede Apple-toestel kan nieuwere keuzes overschrijven.
- [ ] **Build 229 staat op TestFlight zonder "What to Test"**: de releasenotes zijn pas na de lane gepubliceerd. Wordt vervangen door 230, dus bewust niet nagelopen. De stap zelf zit niet vanzelf in de lane: na een build eerst de sectie publiceren, dan `fastlane notes build:<n>`.
- [ ] **De schaal van 1,85 is niet op een televisie beoordeeld**: de vergelijking tussen 2,00, 1,90 en 1,85 komt van schermafdrukken uit de simulator. Op rijniveau is 1,90 nauwelijks van 1,85 te onderscheiden, dus als 1,85 te ver blijkt is 1,90 de eerstvolgende kandidaat. Vraagt een TestFlight-build.
- [ ] **`MediaQuery.size` en `devicePixelRatio` zijn nooit op echte hardware gelogd**: de 960x540 volgt uit `_AppleTvScale` en is in de simulator gemeten, met dpr 4 op een 4K-toestel. Elk getal in de densityaudit hangt aan die aanname.
- [ ] **De schermsweep voor de schaalwijziging is niet af**: Home, Libraries Aanbevolen en Instellingen hebben een volledige vergelijking over de drie varianten, de rest niet. Het aansturen van de TV-UI met blinde toetsaanslagen liep uit de rails, opende het filterpaneel en dook daarna telkens dieper in detailschermen. Bladeren, media detail, kijklijst, zoeken, de spelerbediening en de sheets moeten op het toestel.
- [ ] **`textTheme.copyWith` vervangt twee stijlen volledig**: `mono_theme.dart:129-136` zet `displayLarge` en `titleMedium` met `copyWith`, wat de stijl vervángt in plaats van aanvult, dus die twee verliezen hun `fontSize` en `height` uit `Typography.englishLike2021` en vallen terug op de omringende `DefaultTextStyle`. Losse opruiming, bewust niet tijdens de densityronde gedaan omdat typografie dan tegelijk met de schaal verandert.
- [ ] **Twee tests falen op de Linux-runner en niet lokaal op macOS**: `side_navigation_rail_test.dart: Apple TV D-pad focus skips hidden downloads item` (verwacht `NavigationTabId.settings`, krijgt `null`) en `pleya_share_pair_any_test.dart: pairAny pairs via a later candidate when the first IP is dead`. Aantoonbaar niet van het dependency-werk: de controle-run op `main` van vóór die branch geeft exact dezelfde twee (branch [32031692723](https://github.com/michelknoop21/pleya/actions/runs/32031692723), controle op main [32032784299](https://github.com/michelknoop21/pleya/actions/runs/32032784299)). Ze zijn nooit eerder gezien omdat GitHub Actions op deze repo nog nooit had gedraaid; `origin` is een Gitea-instance. Bewust niet gerepareerd in de dependency-ronde.
- [ ] **`softprops/action-gh-release@v3` is niet in een echte run bewezen**: `build.yml` leidt `tag_name` af uit een tag-ref, en een `workflow_dispatch` op een branch heeft die niet, dus de stap faalt met `Missing tag_name parameter` voordat de actie iets doet. Dat is een eigenschap van het dispatchen, niet van de versiebump. Alle andere bijgewerkte actions zijn wél groen gedraaid, inclusief de artefact-heenweg `upload-artifact@v7` naar `download-artifact@v8` (Build-run [32031695034](https://github.com/michelknoop21/pleya/actions/runs/32031695034), alleen Linux). Er is daardoor ook geen draft release aangemaakt om op te ruimen.
- [ ] **Kijklijst op een toestel**: alles is unit- en widget-gedekt, maar de TV-focusronde, de profielwissel tussen twee Plex Home-gebruikers, het verwijderen van een gemergde entry en de offline-ronde zijn alleen op een toestel te zien. De blokkade dat er geen build was is weg: 226 tot en met 229 staan in App Store Connect.
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

### 2026-08-18 en 2026-08-19
- De aanvragen-schermen in zeven commits van `02d5b71` tot `da1bbab`: echte titel en poster per regel via `SeerrClient.hydrateRequests`, de kaart herschikt met samengevatte seizoenen, filterbalk en zoekveld rechtgezet, kwaliteitsprofiel en rootmap toegevoegd, en de posterbadge binnen zijn kaart.
- Vier losse meldingen erbij: het zwarte scherm bij sorteren in de kijklijst (`02d5b71`, een sheet die `MainScreen` onder zichzelf vandaan popte), de onzichtbare selectie in elke segmented instelling (`1717a44`), de skip-intro-knop bij films (`5e6d5e0`) en de filterbalk van de kijklijst (`d0678c7`).
- Het taalgeheugen van de ondertiteling op 19 augustus, drie commits: alleen direct play schreef naar de opslag, transcoding niet (`cb2f486`), de keuze moest ook op de serie (`0b25734`), en een onafhankelijke review vond een race die in de fix zelf zat (`05a9179`).
- Builds 228 en 229 naar TestFlight op alle drie de platforms; 230 draait. 3583 tests groen, `scripts/ci_checks.sh` schoon.
- Het Tautulli-werk van een parallelle sessie vastgelegd in `6e595f1`, zodat de builds naar een commit verwijzen in plaats van naar een werkboom.

### 2026-08-17 (avond)
- Drie tvOS-ingrepen op `main`: de hero-clearance boven een gedokte rail (`d16fa4f`), de focusmarkering in Instellingen (`e2c123f`) en de Apple TV-vergroting van 2,00 naar 1,85 (`0f780f9`). Zie [DEC-027](docs/DECISIONS.md#dec-027) en [DEC-028](docs/DECISIONS.md#dec-028).
- De densitymeting legde de oorzaak bloot: het canvas is 960x540 en niet 1920x1080, waarna `scaleForHeight` op zijn clamp van 0,85 blijft steken. Samen 1,7 keer het ontwerpdoel. Gemeten met een tijdelijke logregel, bevestigd op de schermafdruk via de icoonbadge van 36 punten die 138 fysieke pixels meet, en daarna weer verwijderd.
- Vijf van de acht richtwaarden uit de opdracht bleken niet te kloppen. De tekst is op tv niet groot, de chrome eromheen wel: een settings-rij is 81 punten hoog met een titel van 13 punten en heeft geen enkele tv-tak.
- 3465 tests groen, `scripts/ci_checks.sh` schoon. Twee nieuwe regressietests: de hero-bounds tegen een echte rail, en het focusvlak per settings-rij in donker en licht.
- Bewust niet gedaan: de componentronde over rijhoogtes, bibliotheekkop, railmaten en focusschaal, plus de clamp in `scaleForHeight`. Eerst één dimensie tegelijk.

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

Ouder dan dit: zie [docs/CHANGELOG.md](docs/CHANGELOG.md).

Zie [docs/DECISIONS.md](docs/DECISIONS.md) voor keuzes, [docs/CHANGELOG.md](docs/CHANGELOG.md) voor details en [docs/PLEYA_SHARE.md](docs/PLEYA_SHARE.md) voor de share-architectuur.
