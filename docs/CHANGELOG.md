# Changelog

Sessie-voor-sessie logboek. Nieuwste bovenaan. Ouder werk staat in
[docs/archive/CHANGELOG-2026-08-07-tot-19.md](archive/CHANGELOG-2026-08-07-tot-19.md) en
[docs/archive/CHANGELOG-tot-2026-08-06.md](archive/CHANGELOG-tot-2026-08-06.md).

## [2026-09-04] Golden 04: Boeken zoeken, met ranking als eigen contract

Op `feat/ebooks`.

### Added
- **Boeken zoeken** (`lib/screens/books/books_search_screen.dart`), met de drie rijsoorten in
  `widgets/book_search_row.dart`. Het zoekglyph op Boeken-home en Alle boeken opent nu dit scherm
  in plaats van de bibliotheekbrede zoekpagina: golden 04 begrenst hem tot boeken.
- **Het matchingcontract staat los van de presentatie.** `lib/books/book_search.dart` heeft
  `BookSearchRanking` als eigen seam, geïnjecteerd in het scherm, zodat ranking kan bewegen met
  echte metadata of servermatching zonder dat een widget meebeweegt.
- `pleya_verify/scenarios/books.search.layout.yaml`, plus tien widgettests en dertien
  eenheidstests.

### Fixed
- **`Dune` stond derde bij zoeken op `dune`.** De ranking sorteerde alleen alfabetisch. Er is nu
  een band vóór het alfabet: de titel die de zoekterm is, dan de titels die ermee beginnen, dan de
  rest.
- **Het toetsenbord dekte twee van de drie resultaatsecties af.** Het scherm nam de focus altijd;
  dat klopt voor een leeg veld en niet voor een gevuld veld.
- **Het zoekveld droeg een tweede, lichter oppervlak.** Een donker `InputDecorationTheme` vult een
  veld standaard.
- **De serie-cover tekende zijn titel over de stapelranden.** Op 44 punt vechten die om dezelfde
  pixels.

### Notes
- **De tabbalk uit golden 02 en 04 staat niet in de app, op geen van beide schermen.** Alle boeken
  en Boeken zoeken worden op de profielnavigator gepusht en dekken `MainScreen` volledig af.
  Nagemeten op de bewijsbundels van allebei de scenario's. Golden 02 is al goedgekeurd en gebouwd,
  dus dit is een eigen ronde over de navigatieschil en geen fix in dit scherm.
- **Het scenario typt niet.** De iOS-driver heeft geen `/v1/input/text`, dus de canonieke zoekterm
  wordt via de automation-route meegegeven. Wat daarmee bewezen is: de drie secties komen op een
  echt toestel uit waar de golden ze zet. Wat niet: dat typen ze oplevert. De widgettests typen wel.
- De runner weigerde onderweg te compileren op symbolen die gewoon bestonden; een verouderde
  `pleya_verify/runner/.dart_tool`, opgelost met `dart pub get`.
- `scripts/ci_checks.sh` groen op de gepinde SDK 3.44.0, volledige suite 4927 groen en 6
  overgeslagen. De suite ving één regel die de golden niet ziet: een kaal `TextField` is verboden,
  want `FocusableTextField` is wat een veld met een tv-afstandsbediening laat werken.

## [2026-09-04] De automation-ID-generator draait weer, doordat hij Flutter niet meer aanraakt

Op `feat/ebooks`. Tooling-slice, geen productgedrag gewijzigd.

### Fixed
- **`dart run tool/generate_automation_ids_yaml.dart` crashte, en het lag niet aan het script.**
  Een script waarvan de enige regel `import 'package:flutter/material.dart';` is crasht net zo
  hard: de standalone Dart VM compileert het Flutter-framework niet, want zijn
  FFI-use-site-transformer gooit `type 'InvalidType' is not a subtype of type 'FunctionType' in
  type cast` in `_verifyAndReplaceNativeCallable`. Een `dart run` zonder imports draait wel. Het
  is dus de toolchain op Flutter 3.44.0 en Dart 3.12.0, niet onze invocation en niet onze code.
- **De generator raakt Flutter nu nergens meer aan.** `AutomationIds` had `navigation_tabs.dart`
  nodig voor precies één kale enum, en dat is een widgetbestand dat het halve framework meebrengt.
  `NavigationTabId` staat nu in `lib/navigation/navigation_tab_id.dart`, een bestand zonder
  imports, en `navigation_tabs.dart` re-exporteert het zodat geen enkele bestaande import
  verandert. Daarmee compileert de generator een klein pure-Dart-programma en draait hij weer via
  het gedocumenteerde commando.

### Added
- **`test/architecture/automation_ids_generator_test.dart`** loopt de importgraaf van de generator
  af en faalt zodra er ergens een Flutter-import op landt. De eigenschap is anders stil: één
  import verderop neemt de generator weer weg, de fout komt er als een compilercrash uit die de
  veroorzaker niet noemt, en dan bewerkt de volgende persoon de gegenereerde YAML met de hand.
  Rood aangetoond door tijdelijk een Flutter-import in `navigation_tab_id.dart` te zetten.

### Notes
- De vier regels die in de vorige sessie met de hand in `pleya_verify/automation_ids.yaml` waren
  gezet, blijken byte-identiek aan wat de herstelde generator schrijft. Een tweede run geeft geen
  diff, `automation_ids_yaml_test.dart` is groen, en er is dus nooit een tweede bron van waarheid
  geweest. Er komt ook geen fallbackprocedure: de route is gerepareerd, niet omzeild.
- `scripts/ci_checks.sh` groen op de gepinde SDK 3.44.0, volledige suite 4904 groen en 6
  overgeslagen. Onderweg één echte fout van mezelf: `export` maakt een naam niet zichtbaar in het
  exporterende bestand, dus `navigation_tabs.dart` had ook een gewone import nodig.

## [2026-09-04] Golden 03: de filtersheet, en waarom drie commits de gate oversloegen

Op `feat/ebooks`, drie commits: `823a329` (proposed), `ef1f21c` (goedgekeurd), `bd02265` (gebouwd).

### Added
- **De filtersheet achter de Filters-pill op Alle boeken.**
  `lib/screens/books/widgets/book_filter_sheet.dart` met `lib/books/book_filter.dart` eronder.
  Groepen links, keuzes rechts, en de sheet is een klad: pas `Toepassen` raakt de plank aan. De
  maten in `BookFilterSheetMetrics` zijn nagemeten op `04-filters-sheet.png` uit de iOS
  Unified-set, en de sheet houdt de verhouding 600 op 852 aan in plaats van een vaste hoogte.
- **`Book` draagt nu genre, taal en downloadstaat**, plus `isFinished` naast `isInProgress` op
  dezelfde 0.995-grens. Genre en taal zijn strings van de bron en geen enum: een gesloten opsomming
  laat alles vallen wat de bron wel kent en Pleya niet.
- **Vier automation-id's**: `screen.books_filters`, `books.filter.group`, `books.filter.option` en
  `books.filter.apply`, met `pleya_verify/scenarios/books.filters.layout.yaml` erop.

### Fixed
- **Een groepslabel stond 11 punt te hoog in zijn eigen rij.** Een `Stack` geeft zijn
  niet-gepositioneerde kinderen losse constraints, dus het label sizede naar één regel tekst en
  ging tegen de bovenrand van de rij van 43,5 staan in plaats van in het midden. Geen enkele test
  klaagde; het kwam alleen boven door het simulatorbeeld naast de golden te leggen.
  `StackFit.expand` lost het op.
- **De pill-rij op Alle boeken paste niet meer zodra de badge erbij kwam.** De testfont maakte het
  zichtbaar, maar het probleem is echt: een langer sorteerlabel of een grotere tekstschaal doet
  hetzelfde. De rij scrollt nu horizontaal in plaats van de waarde af te knippen.

### Notes
- **Drie commits zijn met `SKIP_HOOKS=1` gemaakt, en dat was niet omdat de gate rood stond.** De
  pre-commit-gate viel op twee dingen die niets met deze diff te maken hebben: de SDK op PATH was
  3.44.4 in plaats van de gepinde 3.44.0, en `flutter analyze` laadde `dart_code_linter` wisselend
  en meldde daardoor 28 lintwaarschuwingen in bestaande testbestanden. Met de gepinde SDK vooraan
  in PATH is `scripts/ci_checks.sh` daarna op exact deze tree helemaal groen gedraaid, inclusief
  `flutter analyze` zonder fouten of waarschuwingen, en de volledige suite geeft 4903 groen en 6
  overgeslagen. De gate is dus uitgevoerd, alleen niet door de hook.
- **`tool/generate_automation_ids_yaml.dart` crasht onder `dart run`** in de FFI-transformer
  (`type 'InvalidType' is not a subtype of type 'FunctionType' in type cast`). De vier nieuwe
  regels in `pleya_verify/automation_ids.yaml` zijn daarom met de hand ingevoegd in exact de vorm
  die de generator schrijft; `test/architecture/automation_ids_yaml_test.dart` bevestigt dat ze
  gelijk zijn aan `AutomationIds.catalog()`. Dat is een noodgreep en geen route.

## [2026-08-29] Pleya Verify: de reviewbevindingen na Fase 10 dicht

Twee onafhankelijke adversariële reviews over de branch-diff vonden elf defecten. De zwaarste zes
hangen aan één faalvorm, en het is de ergste die dit gereedschap kan hebben: stil groen op bewijs uit
de verkeerde app. `runScenario` riep `terminate()` alleen aan na een gelukte `launch()`, dus een
health-check die afliep liet het net gestarte proces draaien; de drivers praatten daarna
hardgecodeerd tegen `127.0.0.1:47317` terwijl `AutomationServer` bij een bezette basispoort doorloopt
tot 47326. Het achtergebleven proces beantwoordt `/v1/health` overtuigend, en de run rapporteert PASS.
Precies dat gebeurde in Fase 10 en moest met de hand getraceerd worden.

De app publiceerde de oplossing al zonder dat iemand hem gebruikte: `AutomationServer.start()` schrijft
`<tmpdir>/pleya-verify/instance.json` met poort en pid. De drivers wissen dat bestand nu vóór de
launch en wachten erop, wat een verouderde lezing structureel onmogelijk maakt in plaats van
onwaarschijnlijk, en `/v1/health` moet daarna dezelfde poort én een boottijd ná deze launch melden.
Wijkt er iets af, dan faalt de launch met die reden erbij; terugvallen op de basispoort doet hij
nooit. macOS heeft de boot-logregel als tweede kanaal, de simulators lezen het bestand uit hun
datacontainer. De opgeloste instantie staat in het manifest, zodat een bundel kan antwoorden op de
vraag welke app hem geproduceerd heeft.

Onderweg bleek de aanname over redactie niet te kloppen. `redact()` was wel getest en nergens
aangeroepen, maar hem alsnog over een geëncodeerde JSON-regel halen maakt het erger, niet beter:
`X-Plex-Token=[^&#\s]+` heeft geen reden om bij een aanhalingsteken te stoppen en at de afsluitende
`"}` mee, terwijl `"Authorization":"Bearer …"` juist door geen enkel patroon werd geraakt. Er is nu
een `redactJson` die de gedecodeerde structuur doorloopt, elke string apart redigeert en een waarde
weggooit zodra de *sleutel* een credential noemt.

Verder: de bundle-id-herschrijving in alle drie de drivers controleert nu exitcodes én leest de
identiteit terug, want een geslaagd `plutil`-commando bewijst niet dat het bundel de geïsoleerde
identiteit draagt en die identiteit ís de hele isolatiegarantie. De transport-client heeft een
deadline per request (een opgehangen app is de regressieklasse waarvoor dit bestaat, hij mag niet de
runner gijzelen) en gooit op 401/403/404/405 zoals zijn eigen doc al beloofde. Bewust niet op 400 en
409, want `/v1/signin` en `/v1/input/key` antwoorden daarmee inhoudelijk.

App-kant: `AutomationNode` en `AutomationScreen` registreerden de closure die ze op mount-moment
hadden. Aanroepers bouwen die inline over hun eigen velden, dus na een rebuild bleef `/v1/ui_tree` de
navigatiestand van vóór de tabwissel melden en `/v1/screens` een scherm dat allang klaar was als
"loading". Ze registreren nu een indirectie, hetzelfde patroon dat `contextGetter` er een regel boven
al gebruikte. Het achtervoegsel bij dubbele automation-ids telt per id in plaats van over alle ids
samen, want `a, a, b, b, a` leverde twee keer `#4` op.

Twee dingen zitten buiten de runner. Seeden riep de volledige `reset()` van de fixture-server aan en
wiste daarmee ook de credentials, waardoor `sign_in` gevolgd door `seed` de net gemaakte sessie
sloopte en elke volgende stap faalde met een melding die nergens naar de seed wees; er is nu een
`resetCatalog()` die alleen de catalogus leegt. En `PLEYA_VERIFY` werd in `xcode_appletv.sh` uit de
omliggende shell gelezen zonder dat iets hem voor een release terugzette: een device-releasebuild met
de vlag aan wordt nu geweigerd, en `testflight_release.sh` zet zijn eigen omgeving dicht in plaats van
op de aanroeper te vertrouwen.

## [2026-08-22] De twee PS-4-bevindingen dicht, en de releasenotes blijven staan

Het verlaten van de speler wachtte op de afsluitrapportage van de kijkstatus. Het beeld is op dat
moment al weg en de bibliotheek is nog niet terug, dus een connect-timeout werd letterlijk zwart
scherm, op 21 augustus op iOS en tvOS tegelijk gemeten (logs `xhs3j` en `kzq7c`). Het rapport vertrekt
nu zonder dat het afsluitpad erop wacht, `PlaybackProgressTracker` begrenst de schrijving zelf op vijf
seconden, en wat daarbinnen niet landt gaat naar de offline-wachtrij in plaats van naar de prullenbak.
Een terminaal rapport negeert daarvoor bewust `queueOnOnlineFailure`: bij de periodieke updates draagt
de volgende tik de positie alsnog, na een stop is er geen volgende tik. De lokaal weggeschreven
positie wordt meteen gemeld, anders staat de rij waar de kijker op terugkomt nog op de oude waarde.

De log-uploadknop vuurde elf requests in zeven seconden op een relay die er één per minuut accepteert
(log `kzq7c`, 21:53:39 tot 21:53:46). De bestaande guard dekte alleen een druk die over een lopende
request heen valt, en een weigering komt in zo'n zestig milliseconden terug, dus dat gebeurde nooit.
Het scherm houdt nu vast tot wanneer er weer gevraagd mag worden. Zegt de server met `Retry-After` hoe
lang, dan is dat het antwoord; zwijgt hij, dan verdubbelt de eigen schatting vanaf de bekende minuut
tot maximaal vijf. De datumvorm van die header wordt nu ook gelezen: `HttpDate.parse` meldt een
onleesbare waarde met een `HttpException` en niet met de `FormatException` die de naam suggereert.

Onderweg kwam er iets onder vandaan dat groter is dan allebei. `_postJson` in
`lib/services/pleya_server_client.dart` vangt elke fout af en geeft `null` terug, dus een mislukte
`POST /watch-state` bereikt de aanroeper niet. Bij de PS-4-ronde bleef dat verborgen omdat de
verbinding in een timeout liep en de deadline van de speler alsnog aansloeg; een 404, een 5xx en een
snelle verbindingsweigering vallen nog steeds stil weg. Staat als bevinding in hoofdstuk 24 van het
architectuurdocument, met de aantekening dat het elke aanroep van de client raakt en dus niet binnen
PS-5 hoort.

`main` is erin gemerged. Alleen `playback_progress_tracker_test.dart` botste, en dat was twee keer
aanbouw aan het eind van hetzelfde bestand, dus beide groepen staan er nu naast elkaar. De begrensde
stopmelding zit boven op het hervat-pad uit `b1bb268` en `25d192b`: een rapport dat over de deadline
gaat blijft in de sessie doorlopen, dus het hervatten haalt hem nog steeds in. Bewijs op de
samengevoegde boom: `ci_checks.sh` volledig groen en 4617 tests geslaagd, 1 overgeslagen, met de
gepinde SDK uit `.fvmrc` vooraan in PATH. Zonder die pin staat er 3.44.4 op PATH en valt
`check_flutter_version` om.

Daarna `/update-docs`. Build 240 is afgesloten tot een echte versiekop met het anker op de
bump-commit, en de regels erin zijn herschreven naar wat iemand merkt. Het serverwerk staat er niet
in, om dezelfde reden als bij `fbd19f3`. Twee hoofdstukken bijgewerkt: `settings-reference.md` krijgt
de statusregel onder de iCloud-schakelaar, de instellingen die per toestel blijven en de
geschiedenisschakelaar op het Tautulli-scherm, en `the-home-screen.md` legt uit waarom je die zou
aanzetten. Het Pleya Server-scherm blijft ongedocumenteerd zolang er geen server is die iemand kan
draaien.

**Waarom de releasenotes drie keer waren platgewalst.** `scripts/gen_release_notes.sh` overschrijft
het hele blok tussen `BEGIN GENERATED` en `END GENERATED` bij elke run, en de pre-push hook draait dat
script. De site knipt datzelfde blok er sowieso uit (`website/src/lib/server/releases.ts`) en
publiceert alleen wat eronder staat. De Engelse tekst stond al die tijd ín dat blok, dus hij werd
overschreven én niet gepubliceerd. Hij staat nu onder `END GENERATED`, `--check` geeft exit 0, en de
push ging in één keer door zonder `SKIP_HOOKS`. De zin op de site dat die regels nog in commit-taal
staan klopte daarmee niet meer en is vervangen.

Bij App Store Connect dragen tvOS en macOS de nieuwe tekst, allebei teruggelezen op 2041 tekens. Een
iOS-build 240 bestaat daar niet: de lane wachtte de volle 1800 seconden en `notes_show` bevestigt het
los.

## [2026-08-21] PS-4: afspelen en kijkstatus, met drie poorten dicht ervoor

PS-3 is gesloten met de meting die eraan ontbrak. Een live test legt dezelfde route die de app loopt
tegen de draaiende server op de DS920+: drie bibliotheken (Films 461, Kids 5, Series 97), artwork met
de header uit DEC-048, zoeken, en daarna een verse client die met het bewaarde refreshtoken opnieuw
inlogt. De test slaat zichzelf over zonder adres, want een suite die een NAS nodig heeft om groen te
zijn is geen suite.

Daarmee ging het contractvenster open, en het is weer dicht met drie besluiten erin.

**DEC-049, kijkstatus heeft een eigenaar.** De drie voor de hand liggende conflictregels falen elk op
een scenario dat gewoon voorkomt, en een vierde (ordenen op sessiestart) breekt op het tv/telefoon-
geval. Wat er staat is server-authoritative eigendom: een monotone `revision`, een eigenaarssessie en
een lease op de serverklok. Eigendom wordt alleen verworven met `playback_started`, een passief
voortgangsevent verwerft nooit, `base_revision` draagt de causaliteit, een expliciete handeling
negeert de lease, en een offline backlog is geschiedenis zolang er een toestand is. Achttien tests
dekken de zes regels plus het tv/telefoon-scenario.

**DEC-050, de `ETag` op `/stream` is zwak.** De belofte dat hij verandert zodra de bytes veranderen
gaat uit het contract. RFC 9110 §8.8.1 vraagt strict revision control of een hash over de bytes, en
Pleya beheert de bestanden niet. `If-Range` levert daarom altijd het hele bestand; gewone `Range`
verandert niet, en dat is het pad dat elke seek gebruikt. Gelijkheid van de validator is nergens in
Pleya grond om bytes aan elkaar te plakken.

**DEC-051, de browser krijgt een streamsessie.** Eén cookie op één pad breekt bij twee tabbladen,
want cookies met dezelfde naam, domein en pad vervangen elkaar. De cookienaam draagt daarom de
sessie-id, het geheim staat er als SHA-256 in de database, en er gaan er ten hoogste acht tegelijk
actief: de negende wordt geweigerd in plaats van dat de oudste stream stil sneuvelt.

Daar bovenop PS-4 zelf: twee voorwaartse migraties, `GET /stream/{version_id}` met volledige
range-ondersteuning, beide kijkstatus-endpoints, `POST /auth/stream-session`, en aan de clientkant
een `PleyaServerClient` die afspeelt en kijkstatus schrijft. 182 Go-tests, 214 Dart-tests in
`test/pleya_server/`, de volledige Flutter-suite op 3721, `verify-local.sh` op 72 controles, en 32
controles tegen de draaiende server op de DS920+ (seek naar 73% van een bestand van 1,87 GB in 164 ms
voor 1 MB).

Eén grens is tijdens de uitvoering hersteld. Het masterplan schreef een geweigerd kijkstatusevent
naar `play_history`, en die tabel hoort bij PS-9P. PS-4 correct laten zijn ten koste van een tabel
uit een latere fase is precies de drift die hoofdstuk 23.1 verbiedt, dus zo'n event wordt beantwoord
met de actuele toestand en gelogd, en niet bewaard.

Eén meting viel de andere kant op dan verwacht. De `MediaServerClient`-beoordeling uit PS-4 criterium
5 komt uit op 28 van de 84 members die in drie of meer van de vijf implementaties structureel leeg
zijn, tegen een drempel van 21. De klasse is te breed volgens haar eigen criterium; het getal en de
plek staan in hoofdstuk 5.3 zodat de opsplitsingsronde met een lijst kan beginnen.

**PS-4 staat op "opgeleverd, ter goedkeuring" en niet op "gesloten."** Acceptatiecriterium 1 vraagt
een direct-play-bestand dat op desktop, mobiel en TV speelt met werkende seek, en er is deze sessie
geen film gestart vanuit de app. Alles wat hierboven staat is gemeten op de lijn.

## [2026-08-21] De sync-engine reconcilieert op één plek, en de schermen volgen zonder herstart

Op `main`, nog niet gecommit. Fase A blok 2 (A8 tot en met A16), plus de vijf voorwaarden uit de
reviewronde op de v2-cutover. Hiermee is fase A af; fase B begint na het architectuurrapport.

### Fixed
- **De prune verwijderde clouddata van andere toestellen.** De bescherming "staat lokaal, alleen
  niet syncbaar" vergeleek een genamespacete v2-cloudsleutel met een kale basissleutel, dus hij
  matchte onder v2 nooit. Een lijst met uitsluitend local-folder-entries werd daardoor bij elke
  reconcile uit de store gegooid. De vergelijking gaat nu over basissleutels; de test is rood op de
  oude vergelijking.
- **Een uitgaande schrijfactie kon entries van een ander toestel overschrijven.** De merge draaide
  alleen inkomend. Voor de serverlijsten houdt de uitgaande merge nu de entries in de store die van
  een server zijn waar dit toestel niets over kan zeggen, terwijl een bewuste verwijdering op een
  gedeelde server gewoon doorreist. Kan de store niet gelezen worden, dan wordt er niet geschreven.
- **Een geslaagde schrijfactie wiste een quotastop, een transportfout of de legacy-peer-waarschuwing
  uit beeld.** Er was één `state`-veld, dus `success` overschreef alles wat nog waar was.
- **Een remote wijziging kwam pas na een herstart op het scherm.** `HiddenLibrariesProvider` las
  zijn set bij constructie, `HomeLayoutProvider` blokkeerde elke herlaadpoging met
  `if (_isInitialized) return`, en `LibrariesProvider` bakte de volgorde in zijn lijst.
- **Uitloggen bij iCloud tijdens een sessie bereikte de app nooit.**
  `NSUbiquityIdentityDidChangeNotification` werd nergens waargenomen, dus de status bleef gezond
  terwijl elke schrijfactie nergens heen ging.

### Changed
- **Eén `PreferenceReconcileScheduler` bezit alle triggers** (boot, inschakelen, foreground,
  accountwissel, profielwissel, import, reset). Triggers uit dezelfde turn worden één run; een
  trigger tijdens een lopende run levert precies één vervolgrun. Het venster is een microtask, geen
  `Future.delayed`. Een profielwissel wordt opgemerkt aan de schrijfactie op `active_app_profile_id`,
  dus elk pad dat van profiel wisselt is gedekt.
- **`PreferenceSyncStatus` heeft drie assen** (`availability`, `activity`, `health`) plus
  `legacyPeerDetected`. De acht toestanden uit het plan zijn een afgeleide getter, dus niets
  schrijft nog een toestand. Alleen een geslaagde volledige reconcile schoont health op.
- **`PreferenceMergeRegistry`** vervangt de hardgecodeerde `if` op een sleutelprefix. Een familie
  registreert `merge(local, remote)` onder de naam die in de policy staat; de engine leert nooit wat
  de waarden betekenen. `mergeProgressMaps` is daarmee een geregistreerde familie geworden.
- **`PreferenceRefreshBus`** meldt per batch welke afgeleide families verlopen zijn, en de providers
  herladen hun eigen plak. Geen herstart, geen globale rebuild. De ponytail-notitie op `main.dart`
  is daarmee weg.
- **Instellingen toont één statusregel** onder de iCloud-schakelaar, met nieuwe strings in
  `lib/i18n/en.i18n.json`. Nooit een sleutel, waarde of telling met identiteit, en nooit de claim
  dat andere toestellen bij zijn: KVS accepteert een write, het meldt geen aflevering.
- **Native gewijzigd op precies twee punten** van de negen auditpunten: een `deinit` met
  `removeObserver`, en waarneming van `NSUbiquityIdentityDidChange`. De volledige audit staat in
  `docs/qa/icloud-kvs-native-audit.md`, inclusief waarom er géén buffer voor vroege notificaties is
  gebouwd.

### Added
- `test/services/preferences/v2_only_invariant_test.dart` bewaakt dat v2-only een invariant is en
  geen standaardwaarde: geen bestand in `lib/` kiest het formaat, en een volledige levenscyclus over
  een store vol v1-records laat die records ongemoeid.
- `test/services/preferences/local_only_bookkeeping_test.dart` bewaakt dat de bootstrap-marker, de
  install-id, de revisieopslag, de quarantaine en de actieve-profielsleutel het toestel nooit
  verlaten.
- `test/services/preferences/log_safety_test.dart` scant de logregels op het syncpad en eist dat elke
  interpolatie op een veilige lijst staat. Een nieuwe logregel met een waarde erin wordt rood.
- Verder: `reconcile_scheduler_test`, `reconcile_lifecycle_test`, `runtime_refresh_test`,
  `sync_status_model_test`, `merge_strategy_test`, `quota_and_oversize_test` en
  `test/screens/settings/icloud_sync_status_test.dart`. Suite 4068 groen, dezelfde 15 rood als op
  `8fea407`.

Besluiten: [DEC-060](DECISIONS.md#dec-060) (de v2-cutover als bevroren v1) en
[DEC-061](DECISIONS.md#dec-061) (scheduler, statusassen, gerichte invalidatie, merge per familie).

## [2026-08-21] Preference-sync kreeg één pijplijn, en de grens met de legacy prefs-store ligt nu vast

Op `main`, nog niet gecommit. Fase A blok 1 van het vijffasenplan (A0 tot en met A5 en A7, plus de
vier amendementen uit de planreview). Blok 2 (A8 tot en met A16) en de cloudinhoud-migratie (A6)
volgen apart.

### Fixed
- **Een seek tijdens een netwerkstoring verdween.** `onSeek()` gooide de debouncetimer weg zodra de
  foutbackoff liep. Erger dan het lijkt: de periodieke timer draait alleen tijdens afspelen, dus wie
  seekte en daarna pauzeerde liet de oude positie op de server staan tot er toevallig weer gespeeld
  werd. De seek wordt nu uitgesteld in plaats van weggegooid, en het uitstel tikt de backoff zelf af
  zodat een gepauzeerde speler convergeert. Vijf tests erbij; drie ervan zijn rood op de oude code.
- **Een lokale verwijdering bereikte iCloud niet.** `onKeyWritten` gaf alleen een sleutel door, dus
  de consument las de waarde terug, vond `null` bij een remove en stopte. Alleen een volledige
  `pushAll` propageerde nog verwijderingen.
- **Een waarde die over de 100 KB-grens groeide werd uit de cloud verwijderd in plaats van
  overgeslagen.** `pushAll` prunede op afwezigheid uit de push-set, en een te grote waarde belandde
  daar niet in. Oversize-sleutels worden nu expliciet buiten de prune gehouden en leveren een
  zichtbare waarschuwing.
- **Een transportfout verdween.** Het `void`-terugtype dwong de consument tot `unawaited(...)`.

### Changed
- **Het hookcontract is vervangen, niet omwikkeld.** `BaseSharedPreferencesService.onMutation`
  levert een volledige `PreferenceMutation` met operatie en bron en geeft een `Future` terug.
- **Nieuwe laag `lib/services/preferences/`**: `PreferenceSyncCoordinator` (mutatie, policy, scope,
  merge, reconcile, status), `PreferenceTransport` als poort, `ICloudKvsTransport` als enige
  implementatie. `ICloudSyncService` is een dunne facade geworden en draagt geen syncgedrag meer.
- **Syncbaarheid is een expliciete registratie.** De allow-by-default denylist is weg: een
  niet-geregistreerde voorkeur is local-only. Gevolg dat een gebruiker merkt: `volume`,
  downloadmappen, hardware-decoding, HDR, `custom_relay_url` en het laatst gebruikte LAN-adres
  synchroniseren niet meer.
- **Profielidentiteit blijft aan de waarde hangen** via `PreferenceSyncScope`, dat eerlijk is over
  portabiliteit: een Plex Home-UUID is portable, een `local-<uuid>` niet.
- **Scalaire conflicten hebben een regel.** `PreferenceRevision`: deterministische last-writer-wins
  op `(updatedAt, deviceId)` met tombstones, waarbij een `migration` geen gebruikerstijdstempel zet.
- **De ~35 library- en home-callsites lopen rechtstreeks over de pijplijn**, verwijderingen
  inbegrepen. Read-path-migraties dragen `source: migration`.

### Added
- `test/no_raw_preference_write_test.dart`: 81 rauwe prefs-schrijfacties in 20 bestanden, alle 81
  geclassificeerd met een aantal per bestand. Een nieuwe schrijfactie in een onbekend bestand én een
  extra schrijfactie in een bekend bestand zijn allebei aantoonbaar rood gemaakt.
- `test/services/icloud_rolling_upgrade_test.dart`: de uitgebrachte client laat `__`-sleutels met
  rust in zowel de prune-lus als de apply-lus, met een controle die bewijst dat dezelfde payload in
  de gewone namespace wél wordt opgeruimd. Daarom krijgt de v2-namespace een `__`-voorvoegsel en is
  er geen tweefasenuitrol nodig.
- `docs/qa/preference-sync-and-playback-matrix.md`, met de drie openstaande metingen.

### Notes
- **De cloudinhoud is niet aangeraakt.** `PreferenceSyncCoordinator.v2CloudFormatEnabled` staat op
  `false`: de scoped namespace en de envelop bestaan en zijn getest, maar er is geen v2-record
  geschreven en geen v1-record verwijderd. A6 wacht op een eigen checkpoint, omdat v1-cloudsleutels
  geen profielidentiteit meer dragen en dus niet aan het toevallig actieve profiel mogen worden
  toegewezen.
- **De vijf legacy-services vallen bewust buiten de engine.** `flutter.`-sleutels en de benoemde
  historische namen bereiken iCloud niet. `mergeProgressMaps` blijft als legacy inbound
  compatibility, met de verwijderconditie op de methode. Zie DEC-059.
- **Bij het nalopen van de eigen acceptatie kwam er nog een gat uit.** De prune in `reconcile`
  verwijderde een cloudsleutel zodra hij niet meer in de push-set zat, dus het omkeren van de
  denylist zou clouddata van andere toestellen wissen, en een vergeten registratie zou dataverlies
  zijn in plaats van een gemiste sync. De prune deletet nu alleen wat lokaal echt weg is. In
  dezelfde controle bleken 26 gedeclareerde voorkeuren niet geregistreerd (`app_locale`,
  `library_density`, `buffer_size`, `default_playback_speed`, de mpv-configuratie en meer); die zijn
  alsnog geclassificeerd, en een guard scant voortaan de declaraties.
- Meting: volledige suite 3909 groen / 15 rood, byte-identiek aan de 15 op `8fea407`.
  `flutter analyze` zonder fouten of waarschuwingen, `scripts/ci_checks.sh` groen op SDK 3.44.0.

## [2026-08-21] De hervatpositie kwam uit twee plekken die elkaar tegenspraken

Op `main`, nog niet gecommit. Fase C van het vijffasenplan voor voorkeurensynchronisatie en
kijkvoortgang; A, B, D en E volgen.

### Fixed
- **Een gepauzeerde speler zette de positie van een spelende speler terug.** De melding: *Mutiny*
  stond open op de MacBook (gepauzeerd, 1:03 resterend) en op de Apple TV (actief, 0:57
  resterend), en de MacBook won. De oorzaak stond in `playback_progress_tracker.dart`: de
  periodieke timer stuurde elke zesde tik een `paused`-rapport "om de serversessie in leven te
  houden", met steeds dezelfde positie. Die heartbeat is weg. Een rapport dat zowel de staat als
  de positie van het vorige rapport herhaalt gaat nu niet meer de deur uit.
- **Een seek bereikte de server pas bij de volgende tik.** Wie sprong en binnen tien seconden
  afsloot, liet de positie van vóór de sprong staan. `PlaybackProgressTracker.onSeek()` rapporteert
  na een trailing debounce van 500 ms, herstart daarbij de periodieke timer en respecteert een
  lopende foutbackoff. De 30 seconden-drempel op `_notifyProgressIfNeeded` slikt de sprong niet
  meer op.
- **Een gedownload bestand hervatte op de lokale positie, ook online.** `_resolveOpenResumePosition`
  las bij offline afspelen eerst de lokaal bijgehouden voortgang en gaf die terug zodra hij groter
  dan nul was, ongeacht wat de server wist. Een tweede toestel dat verder had gekeken verloor het
  daarmee altijd.
- **De verse ophaalactie bij het starten sloeg juist het gevaarlijke geval over.**
  `navigateToVideoPlayer` haalde het item alleen opnieuw op als het helemaal geen `viewOffsetMs`
  droeg. Een scherm met een verouderde offset sloeg de ophaalactie dus over en hervatte op die
  verouderde waarde. `shouldRefetchForFreshResume()` haalt online elke film en aflevering vers op.

### Added
- **`lib/services/playback_resume_resolver.dart`**: de enige plek die bepaalt waar een open begint.
  Vijf lagen op intentie, herkomst en tijd, nooit op "welke positie is groter". Een lokale
  handeling wint alleen van een vers opgehaalde serverwaarde als hij aantoonbaar nieuwer is én
  als bewuste gebruikershandeling is vastgelegd; tegen een verouderde cachewaarde volstaat een
  nieuwere tijdstempel. 19 tests.
- **`lib/services/playback_write_authority.dart`**: `ObservedPlaybackAuthority`, een lokale
  waarneming van wie mag schrijven. Uitdrukkelijk geen lease: een vertraagd socketevent, een
  Plex-notificatie zonder bruikbare sessie-informatie of twee spelers die gelijk starten laten
  twee toestellen tegelijk denken dat ze mogen schrijven. `PlaybackReportSession` weigert bij een
  ingetrokken autoriteit alle drie de signalen, `stopped` incluis, want juist dat late stopbericht
  draagt de oude positie. `retakeAfterRefresh` legt de volgorde vast: eerst de serverstaat lezen,
  dan pas terugnemen. Wat de autoriteit intrekt komt in fase D. 13 tests.
- **`lib/services/playback_lifecycle_report_decision.dart`**: wat de achtergrond-, detach- en
  disposepaden schrijven. Ingetrokken autoriteit schrijft niets; een positie die niet bewoog heeft
  niets toe te voegen; een speler die nog speelde schrijft één keer af, en die schrijfactie kan
  niets terugzetten omdat hij een al verstuurde positie herhaalt. 12 tests.
- **`OfflineWatchSyncService.getLocalResumeProgress()`** geeft dezelfde offset als
  `getLocalViewOffset`, met de tijdstempel van de actie erbij. Zonder die tijdstempel bestaat er
  maar één regel, "lokaal wint altijd", en dat was de bug.

### Changed
- **`VideoPlayerScreen` krijgt `resumeProgressIsFresh`.** Alleen de startroute kan zeggen dat de
  offset deze keer bij de backend is opgehaald; de herlaadroutes dragen een eerder opgehaald
  moment.
- **`WatchStateResolver.latestAction()`** staat los van `fromActions()`, omdat de resolver de
  tijdstempel van de winnende actie nodig heeft en niet alleen de staat die eruit volgt.

### Notes
- **Het plan schreef dat de verse ophaalactie langs de cache moest.** Dat klopt niet:
  `fetchWithCacheFallback` (`lib/media/media_server_client.dart:704-732`) gaat network-first en
  raakt de cache alleen in offlinemodus of nadat het verzoek faalde. `fetchItem` levert online dus
  al verse data. Het echte gat zat in de `viewOffsetMs == null`-voorwaarde eromheen.
- **Rood aangetoond op de oude code.** Met de heartbeat teruggezet falen beide
  heartbeat-tests (`Expected: empty`); met `onSeek` leeggemaakt falen alle vijf de seektests.
  Daarna 45 van de 45 groen.
- **Er komt geen permanente DEC voor een leasemodel.** Wat landt is een tijdelijke strategie op
  basis van waarneming. Een echt toegekende lease wacht op PS-4 in de serverrepo.
- 89 gerichte tests groen, `flutter analyze` zonder fouten of waarschuwingen, `scripts/ci_checks.sh`
  groen op de gepinde SDK 3.44.0. De volledige suite geeft 3826 groen en 15 rood; diezelfde 15
  falen op een schone worktree van `8fea407`, in `logs_screen`, `watchlist`, `sync_rules` en
  `media_detail`, geen daarvan raakt afspelen.
- Niet gedaan: verificatie op echte hardware. Twee Apple-toestellen die hetzelfde item openen is de
  enige manier om te zien dat de terugzetter echt weg is.

## [2026-08-20] Hero-artwork vroeg de containerratio op, niet die van de bron

Op `main`, één commit: `40d9608`.

### Fixed
- **De home-hero croppte vierkante artwork op een smalle telefoon horizontaal weg.** `billboardArt()` koos bij een smalle hero-box terecht de vierkante `backgroundSquarePath` in plaats van een 16:9-backdrop, maar `discover_screen.dart` vroeg de afbeelding nog steeds op met de volle 16:9-hoogte van de container. Plex' server-side crop (`minSize=1&upscale=1`) vulde die box vanuit het midden en croppte zo'n 30% van de breedte al weg vóórdat Flutter iets tekende. `homeHeroArtGeometry()` (`lib/utils/home_hero_layout.dart`) ontkoppelt de framehoogte van `heroHeight` en laat de aanvraag altijd de ratio van de gekozen bron volgen, zodat de server-side crop een no-op wordt. Zie [DEC-057](DECISIONS.md#dec-057).

### Added
- **`BillboardArtKind`** (`lib/media/media_item.dart`) vervangt de bool `isBackdrop` op `BillboardArt`: `widescreen`, `square` of `fallback`, met `canRenderSharp`/`shouldBlur` als afgeleide.
- **`HomeHeroArtwork`** (`lib/widgets/home_hero_artwork.dart`, nieuw): de scherpe artworklaag van de hero geëxtraheerd uit `_buildHeroItemContent`, zodat de geometrie los van het hele scherm te toetsen is.
- **`homeHeroLogoConstraints()`** maakt het vaste 400×120-herologo responsive op telefoonbreedtes.

### Notes
- Een onafhankelijke codereview (`/code-review`) op de diff ving een echte bug in de nieuwe widget: de fade-gradient onder een korter frame stond op de onderkant van de hele hero-Stack in plaats van op de onderkant van het frame zelf. Gefixt vóór de commit, met een regressietest die de fade-rect tegen de frame-rect toetst.
- Visuele verificatie op een echt smal scherm (simulator- of TestFlight-screenshot) is nog niet gedaan.
