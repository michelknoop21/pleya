# Pleya Verify: architectuur

Pleya Verify is de automation-/verificatielaag onder `pleya_verify/`: een control-plane in de app
zelf (`lib/automation/`), een losstaande runner die scenario's uitvoert en beoordeelt
(`pleya_verify/runner/`), een fixture-server die een deterministische Plex-achtige backend
simuleert (`pleya_verify/fixture_server/`), en een dunne MCP-adapter erbovenop
(`pleya_verify/mcp/`). Het bestaat om één vraag herhaalbaar te kunnen beantwoorden: draait deze
build op dit platform echt zoals bedoeld, met bewijs dat een reviewer zonder het apparaat erbij te
pakken kan nalezen. `kPleyaVerify` (`lib/automation/pleya_verify.dart`) is de compile-time schakel:
een normale build zet hem `const false`, waardoor de Dart-treeshaker elke `if (kPleyaVerify)`-tak,
en alles wat die tak bevat, uit een releasebinary verwijdert.

## Grens met de rest van de teststrategie

Vier lagen dekken vier verschillende dingen, en geen ervan vervangt een andere:

- **`flutter test`** toetst logica en widgets in isolatie, zonder platform-invoer, zonder echte
  simulator. Snel, en de eerste plek waar een regressie hoort te breken.
- **`scripts/tvos_sim.sh`** is een handmatig/scriptbaar bedieningspaneel voor de tvOS-simulator:
  boot, invoer sturen, screenshotten. Het heeft geen scenariogrammatica en geen PASS/FAIL-oordeel,
  het voert uit wat je vraagt.
- **`pleya_web`-e2e** toetst de losse webclient tegen zijn eigen backend-contract, een ander
  product met een ander oppervlak dan de Flutter-app.
- **Pleya Verify** is de enige laag die een complete, echte end-to-end flow op een echt platform
  (macOS, iOS-simulator, tvOS-simulator) drijft via een scenario, en die flow beoordeelt tegen
  assertions op focus, UI-boom, geometrie en events, met een bewaarde bewijsbundel als resultaat.
  Waar `tvos_sim.sh` het stuur is, is Pleya Verify de chauffeur die een vaste route rijdt en
  rapporteert of hij is aangekomen.

## Eén transportcontract

Alle observatie en (niet-tvOS) invoer loopt via `/v1/*`, aangeboden door
`lib/automation/automation_server.dart` en aangesproken door de runner-client
(`pleya_verify/runner/lib/src/transport/verify_client.dart`). De spec staat in
`pleya_verify/contract/verify_api_v1.md` en is autoritatief: een endpoint dat daar niet in staat,
bestaat niet op het control-plane. Beide kanten hebben een eigen test die de spec parseert en tegen
de eigen implementatie legt (`test/automation/transport_contract_test.dart` en
`pleya_verify/runner/test/transport_contract_test.dart`), dus een endpoint dat in de spec staat maar
in één kant ontbreekt, is een falende test in plaats van een stille drift.

Kernendpoints: `GET /v1/ui_tree` (declared + discovered nodes), `GET /v1/focus`,
`GET /v1/events?since=N` (`focus.changed`, `screen.changed`, `screen.ready`,
`navigation.tab_changed`, `library.items_loaded`, `media_detail.ready`, `input.received`),
`GET /v1/screens`, `GET /v1/viewport`, `POST /v1/wait` (event/node/stableFrames), `POST /v1/input/*`
(alleen niet-tvOS, zie hieronder), `POST /v1/overlay` + de bijbehorende screenshot-flow, en
`POST /v1/signin` / `POST /v1/connections/seed` / `POST /v1/open` om een profiel of scherm te
bereiken zonder de UI handmatig te bedienen.

## Fixture-server

`pleya_verify/fixture_server/` simuleert een Plex-server die deterministisch is: elke seed
(`catalog.mixed.v1`, `catalog.shows.v1`, …) levert dezelfde library-inhoud, ongeacht wanneer of
hoevaak een scenario hem aanroept. Dat is de voorwaarde voor een reproduceerbaar scenario: een
assertion op `child_count: 10` mag niet afhangen van wat er toevallig op een echte Plex-server staat.
`fixture_mutate` (zowel in `setup:` als in `steps:`) laat een scenario de fixture tijdens de run
gericht muteren (bijvoorbeeld een aflevering toevoegen), zodat een refetch-pad ook echt getoetst
wordt in plaats van aangenomen. `fixture/requests.jsonl` in de evidencebundel legt vast welke
requests de fixture kreeg en wanneer, wat een scenario in staat stelt te bewijzen dat een refetch
ná een gebeurtenis plaatsvond, niet toevallig ervoor.

## Scenariogrammatica

Eén `.yaml` per testgeval in `pleya_verify/scenarios/`, geparsed en gevalideerd door
`pleya_verify/runner/lib/src/scenario/`. `setup:` en `steps:` gebruiken bewust disjuncte
werkwoordenlijsten (`pleya_verify/runner/lib/src/scenario/model.dart`): `setup:` bereidt staat voor
(`reset_app`, `seed`, `sign_in`, `open`, `install`, `launch`, `fixture_mutate`) en drukt nooit een
toets in of asserteert nooit iets; `steps:` doet het omgekeerde (`press`, `tap`, `type`,
`wait_until`, `assert`, `snapshot`, `settle`, `fixture_mutate`, `overlay`). Een verb dat in de
verkeerde sectie staat, is een validatiefout met bestandsnaam en regelnummer, niet een stille
no-op. Elk geadverteerd verb heeft een echte case in `run_scenario.dart`: de vocabulaire hier en de
engine-implementatie mogen nooit uit elkaar lopen, dus een verb komt hier pas bij zodra het ook
werkt. Automation-ids die een scenario aanspreekt (`nav.discover`,
`library.grid.item[3]`, …) worden getoetst tegen de statische catalogus
(`pleya_verify/automation_ids.yaml`, gegenereerd uit `AutomationIds.catalog()`), zodat een
scenario met een niet-bestaand id al bij `validate` breekt, zonder simulator nodig te hebben.
`assert:` combineert state-assertions (een boolean/veld dat de widget zelf rendert, geen proxy
ervoor) met geometrie-assertions (`insideViewport`, `notOverlapping`, `minimumTapTarget`, …, zie
`pleya_verify/geometry/SPEC.md` voor de volledige functietabel).

## Drivers en de tvOS-invoerinvariant

Eén `VerificationDriver`-implementatie per target (`pleya_verify/runner/lib/src/driver/`):
`MacosDriver`, `IosSimulatorDriver`, `TvosSimulatorDriver`. Observatie (`uiTree`, `focus`,
`eventsSince`, `logs`, `viewport`) loopt voor alle drie via dezelfde `VerifyClient` tegen `/v1/*`.

Invoer niet. Op tvOS claimt de gepinde engine-fork elke druk vóórdat UIKit's responder chain ooit
begint (zie CLAUDE.md, sectie Gotchas, voor de swizzle-details), dus een druk die via
`/v1/input/key` synthetisch bij Flutter binnenkomt, bewijst niets over wat een echte Siri Remote
zou doen: die twee paden zijn aantoonbaar niet hetzelfde gedrag. `TvosSimulatorDriver.press()` /
`.typeText()` / `.tap()` bevatten daarom géén verwijzing naar `VerifyClient` of `package:http`, en
gaan uitsluitend via `scripts/tvos_sim.sh` (idb HID) naar UIKit. `pleya_verify/runner/test/
driver_routing_test.dart` bewaakt dit structureel door de bronbestanden van de driver te scannen, en
elk tvOS-scenariomanifest draagt `input_route: "idb"` als expliciete markering. Een scenario-stap
roept `/v1/input/*` op tvOS dan ook nooit aan, ook al bestaat het endpoint technisch.

## Bewijsstructuur

Elke run schrijft een evidencebundel naar `.build/pleya-verify/<run-id>/`
(`pleya_verify/runner/lib/src/engine/evidence_bundle.dart`): `manifest.json`, `report.md`,
`scenario.resolved.yaml` (de scenario-tekst zoals daadwerkelijk uitgevoerd, na
placeholder-resolutie), `focus-trace.json`, `app.log`, `driver.log`, `fixture/requests.jsonl`,
plus `screenshots/*.png` en `ui-tree/*.json` per `snapshot:`-stap. Alles wat naar de bundel
geschreven wordt loopt door dezelfde redactie als de app zelf (`LogRedactionManager.redact()` aan
de appkant, een geport equivalent aan de runnerkant, gedeelde testvectoren in
`pleya_verify/redact/SPEC.md`), zodat een bundel die ooit gedeeld wordt geen sessietoken of
serveradres lekt.

**Screenshot-source-of-truth [C5]:** de platform-/simulatorscreenshot (`xcrun simctl io … screenshot`
op tvOS/iOS, native capture op macOS) is de enige geldige bron voor een visuele PASS. `GET
/v1/screenshot` is een Flutter-`RepaintBoundary`-capture die platformcompositing, mpv-lagen en
systeem-chrome overslaat; hij dient uitsluitend diagnose (bijvoorbeeld: bevestigt de overlay tekende
wat `/v1/ui_tree` rapporteerde) en draagt in een vergelijking altijd expliciet
`"source": "flutter_repaint_boundary"`, nooit stilzwijgend als vervanger van de echte screenshot.

De `run`-uitkomst is altijd één van drie, nooit een verkapte vierde: `PASS`, `FAILED` (het scenario
liep, een assertion of wachttijd faalde), of `ERROR` (het scenario liep niet eens: ontbrekend
bestand, parse-/validatiefout, geen driver voor het target). Fase 12 heeft met een bewuste, nooit
gecommitte sabotage bewezen dat een echte regressie ook echt `FAILED` oplevert, met non-zero exit
en een volledige bundel, niet een groen scenario dat toevallig niets toetst.

## Security-grens (Core 1.0)

Het control-plane is fail-closed, niet fail-open-met-een-vlag: er bestaat geen bouwtijd- of
omgevingsschakelaar die `/v1/*` zonder auth laat draaien.

- `AutomationServer.start()` genereert per launch een eigen, cryptografisch willekeurige
  bearer-token (`Random.secure()`, hetzelfde patroon als
  `FixtureHttpServer.generateControlToken`). Elk `/v1/*`-verzoek zonder de exacte
  `Authorization: Bearer <token>` krijgt `401`, zonder uitzondering en zonder een vroegere
  build-tijd-token als impliciete bypass.
- Het token verlaat het proces op precies één manier: geschreven naast `port`/`pid` in
  `instance.json`, het discovery-bestand dat alleen een lokale driver op dezelfde machine leest.
  Het staat nooit in een response-body, `manifest.json`, `report.md`, een logregel of enige andere
  evidence. `stop()` verwijdert `instance.json` zelf, zodat een gestopte instance geen geldig-ogend
  token achterlaat.
- `POST /v1/signin` en `POST /v1/connections/seed` accepteren als `base_url` uitsluitend een
  letterlijk `http://127.0.0.1`- of `http://[::1]`-adres (`rejectNonLoopbackBaseUrl`,
  `lib/automation/automation_signin.dart`), gecontroleerd vóór enige netwerkcall of persistence.
  Zonder die grens was een loopback-only automationendpoint een open SSRF-proxy naar elke
  door de caller opgegeven host.
- Evidence-redactie is structureel, geen exacte-naam-match: `_isSecretKey`
  (`pleya_verify/runner/lib/src/redact.dart`) herkent een woordgrens-match op de canonieke vorm van
  een sleutel, zodat een samengestelde variant (`oldPassword`, `userAccessToken`, `serverApiKey`)
  hetzelfde redacteert als zijn kale vorm. `pleya_verify/redact/cases.json` houdt de app-kant
  (`LogRedactionManager`) en de runner-kant in parity.
- Een `fixture_mutate`-resultaat en een teardown-exceptionstring gaan altijd eerst door
  `redactJson`/`redact` voordat ze het manifest-record in gaan: dezelfde regel die elk ander
  stepresultaat al volgde, nu ook op deze twee paden.
- Elke subprocess- en fixture-controlcall heeft een echte deadline. `RealProcessRunner`
  (`pleya_verify/mcp/lib/src/process_runner.dart`) start het kindproces zelf, race't de uitvoer
  tegen een deadline, en stuurt bij een timeout eerst `SIGTERM` dan `SIGKILL`, vóórdat de aanroep
  teruggeeft; een timeout is altijd een `ProcessRunTimeoutException`, nooit een scenario-uitkomst.
  `FixtureServerHandle._controlGet`/`_controlPost` hebben dezelfde deadline als `VerifyClient`'s
  `/v1/*`-calls. Een startupfout in `FixtureServerHandle.start()` (boot-timeout, vroegtijdig
  gesloten stdout, kapotte JSON-regel, ontbrekend port/token-veld) ruimt het kindproces altijd op
  voordat de exception naar boven gaat.
- `run --json` en `validate --json` geven altijd precies één JSON-envelope terug, ook bij een
  onverwachte crash boven de al afgehandelde paden (kapotte YAML-syntax die niet als
  `ScenarioParseException` binnenkomt, een kapotte `automation_ids.yaml`). `_runScenarioCommand` en
  `_runValidate` (`pleya_verify/runner/bin/verify.dart`) vangen dat af met een top-level catch die
  in exact dezelfde envelope resulteert (`result: ERROR`, non-zero exitcode), stacktrace alleen
  geredacteerd op stderr. Een caller, de MCP-laag incluis, hoeft dus nooit met een ongeparste
  stdout om te gaan.
- De DSL-vocabulaire (`setupVerbs`/`stepVerbs`, zie Scenariogrammatica hierboven) bevat alleen
  verbs met een echte case in `run_scenario.dart`. `set_pref`, `focus` en `back` stonden er ooit in
  zonder implementatie of gedefinieerde semantiek: een scenario die ze gebruikte haalde `validate`
  probleemloos en liep pas na een volledige build/install/launch tegen `UnsupportedError`. Verwijderd
  in plaats van alsnog geïmplementeerd. `pleya_verify/runner/test/validator_test.dart` scant nu
  structureel of `setupVerbs`/`stepVerbs` en de switch in `run_scenario.dart` in beide richtingen in
  sync blijven, zodat deze drift niet terugkomt.

## Bekende grenzen

- **`tvos.library.filters`** is `DEFERRED: blocked by Pleya Server catalog/filter contract G13`
  ([DEC-080](../DECISIONS.md#dec-080-tvoslibraryfilters-is-deferred-geblokkeerd-door-het-pleya-server-cataloguscontract-g13)).
  De scenariogrammatica kan het dragen zodra het productcontract bestaat; tot die tijd bewijst
  `tvos.library.sort.yaml` de wél bestaande Sort-control.
- **`macos.smoke.boot` in CI** faalt op een GitHub-hosted runner door een signing-beperking, niet
  door een fout in Verify zelf ([DEC-083](../DECISIONS.md#dec-083-pleya-verify-ci-drie-gescheiden-gates-geen-tweede-execution-path)).
  `discover.hero.layout` op hetzelfde target heeft wél een reproduceerbaar bewezen PASS.
- **De MCP-laag** (`pleya_verify/mcp/`) is Dart, geen tweede scenario-engine: elke tool spawnt
  `pleya_verify/runner/bin/verify.dart --json <subcommand>` als los proces en geeft de JSON-envelope
  die de CLI al besliste ongewijzigd door. Zie `pleya_verify/mcp/README.md` voor de tool-lijst en de
  securityeigenschappen.
- **tvOS-D-pad-navigatie binnen het systeemtoetsenbord** is niet simuleerbaar (zie CONTRIBUTING.md,
  sectie tvOS-simulator): `idb` stuurt toetsenbordcodes, geen Siri-Remote-D-pad, dus een scenario
  dat dat specifieke gedrag zou moeten bewijzen heeft geen betrouwbaar pad in de simulator.
