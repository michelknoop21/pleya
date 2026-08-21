# STATUS · Pleya

_Laatst bijgewerkt: 2026-08-21 (`main`, build 234 met de hero-crop fix staat op TestFlight voor iOS; tvOS en macOS nog niet bevestigd op 234. App Store Connect 2.8.0 hangt op iOS, tvOS en macOS aan build 229 en staat op `PREPARE_FOR_SUBMISSION`)_

## Waar was ik

**Fase A is af.** Blok 2 (A8 tot en met A16) sloot de vier gaten die de engine wel correct maar niet
merkbaar hielden. Reconciliatie heeft nu één scheduler die alle triggers bezit (boot, inschakelen,
foreground, accountwissel, profielwissel, import, reset), waarbij triggers uit dezelfde turn één run
worden en een trigger tijdens een lopende run precies één vervolgrun oplevert; het venster is een
microtask, geen `Future.delayed`. De status bestaat uit drie assen, zodat een geslaagde schrijfactie
geen quotastop, transportfout of legacy-peer-waarschuwing meer uit beeld wist. Afgeleide schermstaat
wordt gericht ongeldig verklaard via `PreferenceRefreshBus`, dus een remote wijziging in verborgen
bibliotheken of bibliotheekvolgorde is meteen zichtbaar in plaats van na een herstart. En de merge
is een registry geworden waar een familie zich onder een naam inschrijft, inkomend én uitgaand, wat
fase B nodig heeft. Onderweg kwam er een echte bug uit: de prune vergeleek een genamespacete
v2-cloudsleutel met een kale basissleutel, waardoor de bescherming "staat lokaal, alleen niet
syncbaar" onder v2 niets deed en een lijst met uitsluitend local-folder-entries bij elke reconcile
uit de store verdween. Zie [DEC-038](docs/DECISIONS.md#dec-038) en
[DEC-039](docs/DECISIONS.md#dec-039).

Native is er op precies twee van de negen auditpunten gewijzigd: een `deinit` met `removeObserver`,
en waarneming van `NSUbiquityIdentityDidChange`, want uitloggen bij iCloud tijdens een sessie
bereikte Dart nooit en de status bleef gezond terwijl elke schrijfactie nergens heen ging. De
volledige audit, inclusief waarom er géén buffer voor vroege notificaties is gebouwd, staat in
[docs/qa/icloud-kvs-native-audit.md](docs/qa/icloud-kvs-native-audit.md).

Volledige suite 4068 groen / 15 rood, byte-identiek aan de 15 op `8fea407`. `ci_checks.sh` groen op
SDK 3.44.0. Nog niet gedaan: committen, het architectuurrapport vóór fase B, en de verificatie op
twee echte Apple-toestellen.

**Voorkeuren gingen naar iCloud zonder dat iemand had besloten dat ze daar hoorden.** Fase A blok 1
legt dat vast in één pijplijn. Het oude hookcontract was `void Function(String key)`, en die vorm
kon het werk niet dragen: hij kon `set` niet van `remove` onderscheiden, dus een lokaal gewiste
voorkeur haalde de cloud alleen via een volledige `pushAll`, en zijn `void`-terugtype dwong de
consument tot `unawaited(...)`, waarmee elke transportfout verdween. Het contract is vervangen door
een volledige `PreferenceMutation` met operatie en bron. `PreferenceSyncCoordinator` bezit voortaan
mutatie, policy, scope, merge, reconcile en status; `ICloudKvsTransport` doet alleen kanaalwerk, en
`ICloudSyncService` is een dunne facade zonder eigen syncgedrag. De allow-by-default denylist is
omgekeerd: een niet-geregistreerde voorkeur is local-only, waarmee een LAN-adres en per-tracker
bibliotheekfilters stoppen met meereizen. Wat een gebruiker merkt: uitzetten synchroniseert nu net
zo goed als aanzetten, en `volume`, downloadmappen, hardware-decoding en HDR blijven op het toestel
waar ze gezet zijn. Zie [DEC-037](docs/DECISIONS.md#dec-037).

Blok 1 mat toen 3981 groen / 15 rood, met `flutter analyze` zonder fouten of waarschuwingen en
`ci_checks.sh` groen op SDK 3.44.0. De verificatie op twee echte Apple-toestellen staat nog open
(`docs/qa/preference-sync-and-playback-matrix.md`).

**Drie dingen staan hier bewust open, en ze mogen niet stilzwijgend afgevinkt raken:**

1. **De v2-cutover is gedaan, en hij is scherp.** `v2CloudFormatEnabled` staat op `true`: Pleya
   schrijft alleen nog onder `__pleya_pref_v2/`. v1 is read-only geworden. Globale v1-waarden komen
   er één keer in met revisie 0, profiel-scoped v1-waarden blijven in quarantaine omdat het formaat
   hun eigenaar had weggestript, en de bevroren v1-records worden niet verwijderd. Dual-write is
   bewust afgewezen: v1 heeft geen revisie, dus een v1-schrijf na een v2-schrijf is niet te ordenen.
   **Gevolg:** een toestel op een oudere Pleya blijft werken maar wisselt geen instellingen meer uit
   met een bijgewerkt toestel. De app zegt dat ook, onder de iCloud-schakelaar. iOS, iPadOS, macOS en
   tvOS moeten daarom rond dezelfde release mee.
2. **Alleen de home-rijen wachten nog, en niet om de reden die het plan noemde.** De aanname dat
   `serverId` apparaatgebonden is, klopt niet: voor Plex is het de `clientIdentifier` die plex.tv
   voor die server uitgeeft, voor Jellyfin de `machineId` van de server zelf. De
   bibliotheekfamilies reizen dus wél, met een filter dat entries van een local-folder- of
   Pleya Share-backend eruit haalt. `home_row_order` en `hidden_home_rows` staan local-only omdat
   `hub.identifier` niet is aangetoond als stabiele server-side identiteit over toestellen: de
   fallback naar `hub.id` en de meting op twee toestellen ontbreken. Groen krijgen van die meting
   is de hele ingreep; het opgeslagen formaat gebruikt al portable ids.
3. **Legacy store consolidation.** Vijf services (`local_folder_client`,
   `favorite_channels_repository`, `local_server_match_service` en de twee `pleya_share`-services)
   schrijven nog in de legacy-`SharedPreferences`-store, die na de eenmalige migratie los staat van
   de cache-store. Ze vallen bewust buiten de engine en hun sleutels bereiken iCloud niet. Elke
   service heeft een eigen datamigratieplan met terugrolstrategie nodig voordat dit opgelost is.

**De hervatpositie kwam uit twee plekken die elkaar tegenspraken, en de gepauzeerde speler won.**
De melding: *Mutiny* stond tegelijk open op de MacBook (gepauzeerd, 1:03 resterend) en de Apple TV
(actief, 0:57 resterend), en de MacBook-positie kwam terug. De schuldige was de heartbeat in
`playback_progress_tracker.dart`, die elke zes tikken een `paused`-rapport met steeds dezelfde
positie stuurde. Die is weg, samen met elk rapport dat staat én positie van het vorige herhaalt.
Verder rapporteert een seek nu binnen 500 ms in plaats van bij de volgende tik, bepaalt
`PlaybackResumeResolver` als enige waar een open begint (vijf lagen op intentie, herkomst en tijd,
nooit op "welke positie is groter"), en weigert `PlaybackReportSession` alle drie de rapportsignalen
zodra `ObservedPlaybackAuthority` is ingetrokken. Dat laatste is uitdrukkelijk een waarneming en
geen lease: wat de autoriteit intrekt komt in fase D, een echt toegekende lease pas op PS-4. Dit is
fase C van vijf; A (generieke preference-sync), B (trackvoorkeuren), D (realtime waarneming) en E
(serverdocumenten) volgen. Zie [docs/CHANGELOG.md](docs/CHANGELOG.md).

89 gerichte tests groen, `flutter analyze` zonder fouten of waarschuwingen, `scripts/ci_checks.sh`
groen op de gepinde SDK 3.44.0. De volledige suite geeft 3826 groen en 15 rood; diezelfde 15 falen
op een schone worktree van `8fea407` en raken geen van alle het afspelen. Nog niet gedaan:
committen, en de verificatie op twee echte Apple-toestellen.

**De home-hero croppte op een smalle telefoon de zijkanten van zijn eigen artwork weg, en dat zat al in de serveraanvraag.** `billboardArt()` koos daar terecht het vierkante `backgroundSquarePath` in plaats van een 16:9-backdrop, maar `discover_screen.dart` vroeg nog altijd de volle 16:9-hoogte op (`max(screenWidth*9/16, heroHeight)`), en Plex' `minSize=1&upscale=1` vulde die portret-box door van het midden te croppen vóórdat Flutter iets tekende. `homeHeroArtGeometry()` (`lib/utils/home_hero_layout.dart`) laat de aanvraag voortaan altijd de ratio van de gekozen bron volgen in plaats van de containerratio, en de artworklaag verhuisde naar een eigen `HomeHeroArtwork`-widget zodat de geometrie los van het hele scherm te toetsen is. Onderweg ook het vaste 400×120-logo responsive gemaakt voor telefoon. Een onafhankelijke `/code-review` op de diff ving daarna een echte bug in die nieuwe widget: de fade-gradient onder het (kortere) frame stond gepositioneerd op de onderkant van de hele hero in plaats van op de onderkant van het frame zelf, dus hij rendersde in lege ruimte. Gefixt en met een regressietest vastgelegd. Zie [DEC-035](docs/DECISIONS.md#dec-035).

`flutter test`, `flutter analyze` en `scripts/ci_checks.sh` zijn schoon voor de geraakte bestanden (73 gerichte tests groen). Nog niet gedaan: committen, en de verplichte visuele verificatie met een screenshot op een echt smal scherm dat de crop nu klopt.

**Eerdere twee UI-meldingen lagen allebei op dezelfde as: een control die te veel gewicht opeist, en een klik die bij het verkeerde terechtkomt.** Eerst openden Filters, Sorteren en Groepering op een desktopvenster rechtsonder. Dat zat niet in de bibliotheekpagina maar in de gedeelde overlay-sheet: die geeft op desktop de laatste muis-x als anker, wat klopt voor een contextmenu en voor niets anders, plus een vaste hoogte van 400. De host heeft nu een presentatiestand en de plaatsing staat in een pure functie. In dezelfde ronde kreeg Ontdekken via Aanvragen de bibliotheekheader zelf in plaats van omlijnde pillen: van 92px naar 42px chroom. Zie [DEC-032](docs/DECISIONS.md#dec-032).

**De fix van die tweede melding sloeg door en is dezelfde avond hersteld.** Zie de alinea eronder: de balk claimde de hele strook tot 220 zodra de pointer erin kwam, ook stil ingeklapt, en daarmee de contentknoppen die daar staan. Op macOS was Aanbevolen op een bibliotheekpagina niet meer aan te klikken.

Daarna de melding dat een klik in het zijmenu op de achtergrond een film startte. Het log bewees dat de zijbalk die klik nooit zag. De balk tekent niet buiten zijn hitbox, dus het verschil zit in de tijd: `isCollapsed` klapt synchroon om en de breedte animeert er 200 ms achteraan, waardoor de cursor de animatie kan inhalen en bij het inklappen zichtbare rijen al dood zijn. De balk bezit zijn band nu via de getekende breedte, en het billboard is geen verborgen afspeelknop meer. Zie [DEC-033](docs/DECISIONS.md#dec-033).

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

**Eerst de hero-crop fix afronden: screenshot op een smal scherm (simulator volstaat, 353 of 402pt breed) dat het vierkante of 16:9-frame nu ongecropt staat.** De code is gecommit en getest; alleen de verplichte visuele check ontbreekt nog. `docs/CHANGELOG.md` krijgt zijn entry zodra die check gedaan is.

**Daarna de deviceronde op de nieuwe build, in deze volgorde.** Eerst de twee dingen die al sinds build 230 wachten en de echte server vragen: de aanvraaglijst op de iPhone (staan er echte titels en posters, klopt de status per regel, met debuglogging gefilterd op `seerr: could not resolve`), en de ondertiteltaal op de Apple TV terwijl Plex transcodeert. Daarna één wegwerpaanvraag met bewust gekozen server, kwaliteitsprofiel en rootmap, in Radarr of Sonarr controleren dat exact die waarden zijn opgeslagen, en de aanvraag verwijderen.

Nieuw erbij op deze build: op een echt toestel met trackpad of muis de zijbalk naderen en meteen een menu-item aanklikken. Dat is de ene helft van de fix die niet met de hand te automatiseren was, want `cliclick` levert geen synthetische hover aan deze app. Kijk daarbij ook of de content in de strook tussen 80 en 220 pixels prettig blijft: die schuift nu weg zodra je hem nadert, en dat is bewust.

## Blockers

- [ ] **De terugzetter is niet op hardware gecontroleerd**: de Mutiny-regressie is met `fakeAsync`
  vastgelegd en aantoonbaar rood op de oude code, maar twee Apple-toestellen die hetzelfde item
  openen is de enige manier om te zien dat het gedrag in het echt weg is. Vraagt een build met
  fase C erin.
- [ ] **De ingetrokken schrijfautoriteit is nog dood hout**: `ObservedPlaybackAuthority` wordt
  aangemaakt en gerespecteerd, maar niets trekt hem in tot fase D de serverevents levert. Tot dan
  leunt de bescherming volledig op het wegvallen van de heartbeat en op het onderdrukken van
  herhaalde rapporten.
- [ ] **Een lokale voortgangsactie is niet als bewuste handeling vast te leggen**: de wachtrij in
  `offline_watch_progress` heeft geen veld dat een gebruikersseek van een trackertik onderscheidt,
  dus `getLocalResumeProgress` meldt elk record als passief. Laag 2 van `PlaybackResumeResolver`
  ondersteunt het geval wel, er is alleen nog geen bron die het levert.
- [ ] **De hero-crop fix is niet visueel geverifieerd**: `homeHeroArtGeometry()` en `HomeHeroArtwork` zijn compleet getest (73 tests, inclusief de frame/fade-rects), maar niemand heeft nog een screenshot bekeken op een echt smal scherm om te zien dat de gezichten/compositie nu wél in beeld staan in plaats van gecropt. Build 234 staat sinds 20 augustus op TestFlight voor iOS, dus dat kan nu op een toestel. Zie [DEC-035](docs/DECISIONS.md#dec-035).
- [ ] **De hover-band van de zijbalk is niet met de hand geverifieerd**: `cliclick` levert geen synthetische hover- of scrollevents aan deze app, dus dat de balk uitklapt zodra de cursor binnen 220 pixels komt leunt volledig op de widgettest met een echte pointer-gesture. Wat wél met de hand is gezien: een klik op x=150 in het hero-gebied levert de detailpagina op in plaats van een film, en de Afspelen-pil speelt. Vraagt de nieuwe build op een toestel met muis of trackpad.
- [ ] **`RIGHT OVERFLOWED BY 16 PIXELS` op de tvOS-hero**: de knoppenrij met Resume en View details loopt over. Gezien in de simulator, bestond al vóór het zijbalkwerk en bewust niet in die commit meegenomen. Eigen UI-fix.
- [ ] **De tvOS-select-asymmetrie blijft open als onderzoeksnotitie**: `NavigationRailItem` is de enige plek die op Select activeert, daarna focus verplaatst en `SelectKeyUpSuppressor.suppressSelectUntilKeyUp()` niet wapent, terwijl elf andere plekken dat wel doen. Niet gerepareerd omdat het aantoonbaar niet lekt (beide ontvangers in de content weigeren een losse key-up) en het in de simulator niet te reproduceren was. Drie contracttests leggen het gedrag vast; komt er een nieuwe melding, begin dan bij het focus- en key-eventpad.
- [ ] **De aanvragen-flow is niet tegen de echte server gezien**: titel- en posterverrijking, en of een gekozen kwaliteitsprofiel echt zo in Radarr of Sonarr landt. Alles eromheen is gedekt (aanvraagregel, seizoenen, statuschips, badge, filterbalk, i18n, plus vier tests die de kosten van de verrijking meten), maar de verrijking zelf praat met Overseerr en dat is alleen op een toestel te zien. Build 229 of nieuwer.
- [ ] **Het taalgeheugen bij transcoding is alleen door tests gedekt**: het opzoeken van de taal bij een stream-id en de Plex-mapping zijn getest, de echte wissel op een Apple TV niet. Vraagt build 231, die sinds 19 augustus op TestFlight staat. Let op: met **Ook de taal naar Plex schrijven** uit kan de volgende aflevering niet goed openen zodra Plex de ondertitels inbrandt, want dan is er lokaal geen spoor meer om te kiezen.
- [ ] **`SeerrProvider` heeft geen injecteerbare http-client**: `SeerrClient` accepteert er wel een (de client-tests gebruiken `MockClient`), maar de provider bouwt zijn eigen. Daardoor is de aanvraag-sheet met de server-, profiel- en rootmapkeuze niet met gestubde HTTP te testen. Afgesproken: niet nu refactoren, wel eerst dependency injection bij de volgende substantiële Seerr-uitbreiding.
- [ ] **Twee gaten in het taalgeheugen die los staan van de gemelde bug**: een ondertitelspoor zonder taalcode wordt niet onthouden (`track_manager.dart:450`, raakt losse SRT-bestanden; de audio-tegenhanger op :439 verdedigt hetzelfde gedrag met een reden die voor ondertitels niet opgaat, dus een titel-gebaseerde sleutel is de fix), en de iCloud-synchronisatie vervangt de hele voorkeurenkaart in één keer in plaats van per titel samen te voegen, dus een verouderde snapshot op een tweede Apple-toestel kan nieuwere keuzes overschrijven.
- [ ] **De lange App Store-productbeschrijving en keywords blijven handwerk**: alleen de App Store "What's New"-tekst is nu geautomatiseerd (DEC-036), de vaste marketingcopy op de App Store-pagina bewust niet, want die verandert zelden en per ongeluk overschrijven van bestaande ASO-copy is duurder te herstellen dan handmatig zetten.
- [ ] **Build 234 heeft nog geen "What's New" op de App Store-versie**: `fastlane whats_new build:234` moet nog draaien; `whats_new_show platform:ios` bevestigde dat het veld voor de bewerkbare 2.8.0-versie leeg staat. Zie [DEC-036](docs/DECISIONS.md#dec-036).
- [ ] **229 en 230 staan op TestFlight zonder "What to Test"**: de releasenotes zijn pas na de lane gepubliceerd en het gat liep door tot 231. Beide zijn vervangen door 231, dus bewust niet los nagelopen; hun inhoud staat samengevoegd in de 231-sectie van `docs/RELEASES.md`. De stap zelf zit niet vanzelf in de lane: na een build eerst de sectie publiceren, dan `fastlane notes build:<n>`.
- [ ] **De schaal van 1,85 is niet op een televisie beoordeeld**: de vergelijking tussen 2,00, 1,90 en 1,85 komt van schermafdrukken uit de simulator. Op rijniveau is 1,90 nauwelijks van 1,85 te onderscheiden, dus als 1,85 te ver blijkt is 1,90 de eerstvolgende kandidaat. Vraagt een TestFlight-build.
- [ ] **`MediaQuery.size` en `devicePixelRatio` zijn nooit op echte hardware gelogd**: de 960x540 volgt uit `_AppleTvScale` en is in de simulator gemeten, met dpr 4 op een 4K-toestel. Elk getal in de densityaudit hangt aan die aanname.
- [ ] **De schermsweep voor de schaalwijziging is niet af**: Home, Libraries Aanbevolen en Instellingen hebben een volledige vergelijking over de drie varianten, de rest niet. Het aansturen van de TV-UI met blinde toetsaanslagen liep uit de rails, opende het filterpaneel en dook daarna telkens dieper in detailschermen. Bladeren, media detail, kijklijst, zoeken, de spelerbediening en de sheets moeten op het toestel.
- [ ] **`textTheme.copyWith` vervangt vier stijlen volledig**: `mono_theme.dart:149-156` zet `displayLarge`, `titleMedium`, `bodyMedium` en `bodySmall` met een kale `TextStyle` in `copyWith`, wat de stijl vervángt in plaats van aanvult. Alle vier verliezen `fontSize` en `height` uit `Typography.englishLike2021`; `displayLarge` en `titleMedium` verliezen daarbij ook de kleur uit `.apply()`. Oplossing per stijl: `Typography.englishLike2021.<stijl>.copyWith(...)`. Losse opruiming, bewust niet tijdens de densityronde gedaan omdat typografie dan tegelijk met de schaal verandert.
- [x] ~~**Twee tests falen op de Linux-runner en niet lokaal op macOS**~~ opgelost 2026-08-18 in `c00ab9d`. De railtest drukte drie keer omlaag terwijl er met Downloads verborgen op Apple TV maar drie items staan; op Windows en Linux zet `_showFullscreenToggle` er een vierde achter Settings, dus de focus schoof daarheen en Enter bereikte `onDestinationSelected` nooit. Twee stappen is het juiste aantal en bewijst pas echt dat Downloads is overgeslagen. De dode host in de share-test was `127.0.0.2`, wat Linux gewoon beantwoordt; nu `192.0.2.1` uit TEST-NET-1. Blijft staan als voetnoot: `_showFullscreenToggle` leest `dart:io Platform` rechtstreeks (`side_navigation_rail.dart`) en is voor een test niet te overrulen, dus een volgende test die stappen telt voorbij Instellingen loopt opnieuw per platform uiteen.
- [ ] **`softprops/action-gh-release@v3` is nog niet in een echte run bewezen**: de oorzaak is weg. De stap kreeg helemaal geen `tag_name` mee en leunde op een tag-ref, die een `workflow_dispatch` op een branch niet heeft, dus hij faalde met `Missing tag_name parameter` voordat de actie iets deed. Sinds 19 augustus staat er een expliciete `tag_name` uit de pubspec-versie die dezelfde stap al leest, dezelfde waarde waar de appcast-enclosures naar wijzen. Een groene run heeft dat nog niet bevestigd. Dat is een eigenschap van het dispatchen, niet van de versiebump. Alle andere bijgewerkte actions zijn wél groen gedraaid, inclusief de artefact-heenweg `upload-artifact@v7` naar `download-artifact@v8` (Build-run [32031695034](https://github.com/michelknoop21/pleya/actions/runs/32031695034), alleen Linux). Er is daardoor ook geen draft release aangemaakt om op te ruimen.
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
- [ ] **32 schermafbeeldingen voor de handleiding**: eigen contentronde, niet mengen met nieuwe documentatiefuncties. De techniek eromheen staat klaar: `docs/manual/SCREENSHOTS.md` heeft per schot het bestand, het scherm, het toestel en wat erop moet, de paden liggen vast op `/docs-media/<naam>.png`, en een ontbrekend bestand tekent een plaatshouder in plaats van een kapotte afbeelding. Klaar is: alle 32 in `website/static/docs-media/` en geen plaatshouder meer op `/docs`. Voorgestelde eerste helft: de vijftien schoten van de acht meestbezochte hoofdstukken. Vraagt een ingelogd toestel per vormfactor en alleen Blender-content in beeld, dezelfde grens als bij de ASC-screenshots.
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

### 2026-08-20
- De home-hero croppte op een smalle telefoon de zijkanten van het gekozen artwork weg, want de server-aanvraag volgde de containerratio in plaats van de bronratio. `homeHeroArtGeometry()` (`lib/utils/home_hero_layout.dart`) koppelt de framehoogte nu los van `heroHeight` en laat de aanvraag altijd de ratio van de bron (vierkant of 16:9) volgen; de artworklaag verhuisde naar `HomeHeroArtwork` (`lib/widgets/home_hero_artwork.dart`). Zie [DEC-035](docs/DECISIONS.md#dec-035).
- Onderweg ook het vaste 400×120-herologo responsive gemaakt op telefoon (`homeHeroLogoConstraints()`).
- Een onafhankelijke `/code-review` op de diff ving een echte bug: de fade-gradient onder het frame stond op de onderkant van de hele hero in plaats van op de onderkant van het (kortere) frame. Gefixt, met een regressietest die de fade-rect tegen de frame-rect toetst.
- 73 gerichte tests groen, `flutter analyze` en `scripts/ci_checks.sh` schoon voor de geraakte bestanden. Gecommit als `40d9608` op `main`. Nog open: visuele verificatie op een echt smal scherm.

### 2026-08-18 en 2026-08-19
- De aanvragen-schermen in zeven commits van `02d5b71` tot `da1bbab`: echte titel en poster per regel via `SeerrClient.hydrateRequests`, de kaart herschikt met samengevatte seizoenen, filterbalk en zoekveld rechtgezet, kwaliteitsprofiel en rootmap toegevoegd, en de posterbadge binnen zijn kaart.
- Vier losse meldingen erbij: het zwarte scherm bij sorteren in de kijklijst (`02d5b71`, een sheet die `MainScreen` onder zichzelf vandaan popte), de onzichtbare selectie in elke segmented instelling (`1717a44`), de skip-intro-knop bij films (`5e6d5e0`) en de filterbalk van de kijklijst (`d0678c7`).
- Het taalgeheugen van de ondertiteling op 19 augustus, drie commits: alleen direct play schreef naar de opslag, transcoding niet (`cb2f486`), de keuze moest ook op de serie (`0b25734`), en een onafhankelijke review vond een race die in de fix zelf zat (`05a9179`).
- Builds 228 en 229 naar TestFlight op alle drie de platforms; 230 draait. 3583 tests groen, `scripts/ci_checks.sh` schoon.
- Het Tautulli-werk van een parallelle sessie vastgelegd in `6e595f1`, zodat de builds naar een commit verwijzen in plaats van naar een werkboom.
- Op 19 augustus daarna twee UI-rondes. `6247253`: Filters, Sorteren en Groepering openen viewportbewust in plaats van bij de muis, via een presentatiestand op `OverlaySheetHost` en een pure `resolveOverlaySheetGeometry`; in dezelfde commit kreeg de Seerr-filterbalk de echte `LibraryHeaderBar`, van 92px naar 42px. Zie [DEC-032](docs/DECISIONS.md#dec-032).
- `29431f9`: een klik op de zijbalk kon de hero eronder starten. Twee races tussen een boolean die direct omslaat en een breedte die 200 ms animeert. De balk bezit zijn band nu via de getekende breedte, en het billboard opent details in plaats van af te spelen. Acht nieuwe tests, drie ervan vóór de fix aantoonbaar rood. Zie [DEC-033](docs/DECISIONS.md#dec-033) en de twee gotchas in `CLAUDE.md` (`7aae62b`).
- `40658ed`: de band uit `29431f9` lag te breed. Eigendom hoort verdiend te worden door over de ingeklapte balk binnen te komen, niet vooraf gereserveerd omdat content binnen de toekomstige uitgeklapte breedte valt. `owned` (max van getekend en doel) drukte die regel al uit, maar alleen laag 1 las hem; de hover-MouseRegion stond op `Positioned.fill` over de vaste 220. Die volgt nu `owned`. Nieuwe test was vóór de fix rood.
- 3631 tests groen, `scripts/ci_checks.sh` schoon. De tvOS-variant van de zijbalkbug is onderzocht in de simulator en niet aangetoond.
- Releasenotes van 229 tot en met 231 samengevoegd tot één sectie voor build 231, met de drie deviceronde-checks erin als *Worth checking*. Vier handleidinghoofdstukken bij: Aanvragen (geavanceerde opties, de aanvraaglijst, de nieuwe header), Ondertitels en audio (wat er bij inbranden nodig is), het beginscherm (het billboard opent details) en de kijklijst (sorteren en filteren).

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

Ouder dan dit: zie [docs/CHANGELOG.md](docs/CHANGELOG.md).

Zie [docs/DECISIONS.md](docs/DECISIONS.md) voor keuzes, [docs/CHANGELOG.md](docs/CHANGELOG.md) voor details en [docs/PLEYA_SHARE.md](docs/PLEYA_SHARE.md) voor de share-architectuur.
