<!-- anti-slop: off -->
# Pleya Verify transport contract v1

Autoritatieve spec voor het `/v1/*` control-plane dat de app aanbiedt
(`lib/automation/automation_server.dart`) en de runner-client die ertegen
praat (`pleya_verify/runner/lib/src/transport/verify_client.dart`). Beide
kanten hebben een test die dit bestand parseert en tegen de eigen
implementatie legt — zie `test/automation/transport_contract_test.dart` en
`pleya_verify/runner/test/transport_contract_test.dart`. Een endpoint dat hier
niet staat, bestaat niet op het control-plane; een endpoint dat hier wel
staat maar ontbreekt in een van beide kanten, is een falende test.

## Auth

Elk `/v1/*`-verzoek:

- `Host` moet `127.0.0.1[:port]` of `localhost[:port]` zijn, anders 403.
- `X-Pleya-Verify: PleyaVerify/1` is verplicht — een constante protocolmarker,
  nooit een geheim. Ontbreekt hij of klopt hij niet, dan 403.
- `Authorization: Bearer <token>` is alleen verplicht wanneer de app gebouwd
  is met `PLEYA_VERIFY_TOKEN` gezet. Ontbreekt hij dan of klopt hij niet, dan
  401. `X-Pleya-Verify` wordt nergens als tokenwaarde gelezen.

Elk pad hieronder heeft precies één toegestane HTTP-methode (`GET` of `POST`,
zie de kop per endpoint). Een bestaand pad met de verkeerde methode (bv.
`POST /v1/health`) geeft 405, ná de drie auth-checks hierboven maar vóór de
route zelf draait. Een pad dat niet in deze spec staat geeft 404.

## Endpoints

### `GET /v1/health`

Geen parameters. 200 met JSON:

```json
{
  "protocolVersion": 1,
  "commit": "<git sha, leeg buiten CI>",
  "platform": "<TargetPlatform.name>",
  "port": 47317,
  "booted": true,
  "bootedAt": "<ISO8601>"
}
```

Triggert geen events.

### `GET /v1/ui_tree`

Geen parameters. 200 met JSON:

```json
{
  "declared": [{"id": "nav.discover", "role": "...", "label": "..."}],
  "discovered": [{"label": "...", "focused": false, "canRequestFocus": true, "bounds": {"x": 0, "y": 0, "width": 0, "height": 0}}],
  "duplicates": ["<declared id die dubbel geregistreerd was>"]
}
```

`declared` is leeg totdat widgets een `AutomationDeclaredNode` registreren (zie
A.2/A.8 in het Pleya Verify-plan); `discovered` komt uit een live walk van
`FocusManager.instance.rootScope.traversalDescendants` en is dus altijd
gevuld zodra er een gefocust widget bestaat. `bounds` ontbreekt op een node
zonder gemount `RenderBox` (bv. niet zichtbaar). Labels lopen door
`LogRedactionManager.redact()`. Triggert geen events.

### `GET /v1/focus`

Geen parameters. 200 met JSON in dezelfde vorm als een `discovered`-node uit
`/v1/ui_tree` (`label`, `focused`, `canRequestFocus`, optioneel `bounds`), of
`{"focused": false}` wanneer er niets gefocust is of er nog geen
`WidgetsBinding` bestaat. Triggert geen events.

### `GET /v1/focus/log?since=N`

`since` (optioneel, default `0`): alleen entries met `seq > since`. 200 met
JSON:

```json
{"entries": [{"seq": 1, "at": "<ISO8601>", "from": "...", "to": "...", "cause": "key:Select"}]}
```

`from`/`to` zijn `debugLabel`s van de betrokken `FocusNode`s, `cause` is
best-effort (de laatste early-key-event-beschrijving vóór deze wissel; kan
ontbreken). `seq` is monotoon binnen het app-proces — geen terugblikprobleem.
Triggert geen events (het is zelf al de bron van `focus.changed`).

### `GET /v1/events?since=N`

`since` (optioneel, default `0`): alleen events met `seq > since`. 200 met
JSON:

```json
{"events": [{"seq": 1, "name": "focus.changed", "data": {"from": "...", "to": "..."}, "at": "<ISO8601>"}]}
```

Emitted vandaag, met de bron per naam:

- `focus.changed` (`{"from": "...", "to": "..."}`) — `AutomationFocusLog`, elke
  focuswissel.
- `screen.changed` (`AutomationRouteObserver`) — een routetransitie.
- `screen.ready` (`{"id": "..."}`, `AutomationScreen`) — het moment dat een
  gemount scherm z'n readiness-transitie naar `ready` maakt.
- `navigation.tab_changed` (`{"from": "...", "to": "..."}`, `main_screen.dart`)
  — de navigatietab wisselt.

Zie de event-vocabulaire in het Pleya Verify-plan voor de volledige, nog
groeiende lijst (`library.items_loaded`, `media_detail.ready`,
`input.received` volgen in Fase 5). Triggert geen events zelf (het is zelf de
bron).

### `GET /v1/screens`

Geen parameters. 200 met JSON:

```json
{"screens": [{"id": "screen.discover", "state": "ready", "ready": true}]}
```

Eén entry per gemount `AutomationScreen`. `state` is `loading`/`ready`/`error`,
`reason` (optioneel) staat erbij zolang `state != "ready"`. Readiness wordt
lui berekend — pas geëvalueerd op het moment van deze call, geen achtergrond-
polling. Elke transitie naar `ready` heeft al een `screen.ready`-event in
`/v1/events` achtergelaten op het moment dat hij daadwerkelijk plaatsvond.

### `GET /v1/automation_ids`

Geen parameters. 200 met JSON:

```json
{"ids": [{"id": "screen.discover", "role": "screen"}, {"id": "nav.discover", "role": "nav"}]}
```

De **statische, autoritatieve** `AutomationIds`-catalogus
(`AutomationIds.catalog()`) — niet een dump van de op dat moment gemounte
`AutomationRegistry` (dat is `/v1/ui_tree`'s `declared`). Het verschil is
bewust: de runtime-registry bevat alleen wat toevallig gemount is (nooit alle
schermen tegelijk), terwijl scenariovalidatie zonder simulator (Fase 6) een
volledige, schermonafhankelijke bron nodig heeft. Groeit mee met de
id-uitbreidingen in Fase 5, inclusief `instanceable`-metadata voor
instance-suffixed ids (`library.grid.item[n]` en vergelijkbaar). Triggert
geen events.

### `GET /v1/viewport`

Geen parameters. 200 met JSON:

```json
{"available": true, "width": 1920.0, "height": 1080.0, "devicePixelRatio": 2.0, "safeArea": {"top": 0.0, "right": 0.0, "bottom": 0.0, "left": 0.0}}
```

`{"available": false}` wanneer er nog geen gemounte `Navigator` is (vroege
boot, of een test zonder widget-tree) — nooit een crash. Waarden komen uit
`MediaQuery` op `rootNavigatorKey`'s huidige context, dezelfde
"overleeft-profielsessie-remounts"-seam die `main.dart`'s `_rootPinPrompt`
gebruikt. Nodig voor `insideViewport`-geometrie (Fase 7). Triggert geen
events.

### `GET /v1/logs?since=N`

`since` (optioneel, default `0`): alleen entries met `seq > since`. 200 met
JSON:

```json
{"entries": [{"seq": 1, "at": "<ISO8601>", "level": "debug", "message": "...", "error": "..."}]}
```

`error` ontbreekt wanneer de entry er geen had. Bron is `MemoryLogOutput`
(dezelfde ringbuffer als het instellingenscherm `LogsScreen` toont); `seq` is
monotoon binnen het app-proces en blijft geldig als oude entries uit de
ringbuffer vallen (in tegenstelling tot lijstpositie). `message`/`error` zijn
al ge-redact bij het schrijven (`MemoryAwareLogPrinter`) en worden hier nog
een keer door `LogRedactionManager.redact()` gehaald — verdediging in
diepte tegen een waarde die pas ná het bufferen geregistreerd werd. Triggert
geen events.

### `POST /v1/wait`

Body (alle velden optioneel, precies één van `event`/`node` gebruiken, anders
valt de call terug op `stableFrames`):

```json
{"event": {"name": "focus.changed", "since": 0}, "timeoutMs": 5000}
{"node": {"id": "nav.discover", "visible": true, "focused": true}, "timeoutMs": 5000}
{"stableFrames": 2, "timeoutMs": 5000}
```

200 altijd (nooit een HTTP-timeoutstatus) met `{"ok": true, ...}` zodra het
predicaat voldaan is, of `{"ok": false, "reason": "timeout"}` na `timeoutMs`
(default 5000). `event` matcht op naam (weggelaten = elk event) sinds
`since` (default 0) en pollt `/v1/events`'s bron elke 100ms. `node` matcht op
`id`/`visible` (afgeleid van `bounds != null`)/`focused` tegen `/v1/ui_tree`'s
`declared`+`discovered` nodes. `stableFrames` wacht dat aantal frames via
`SchedulerBinding.endOfFrame` (no-op zonder `WidgetsBinding`). Triggert geen
events zelf.

### `POST /v1/input/key`

Body: `{"key": "select"}`. Sleutelwoorden: `up`, `down`, `left`, `right`,
`select`, `menu`, `delete` — dezelfde vocabulaire als `scripts/tvos_sim.sh
key`. Loopt via `lib/utils/key_event_simulator.dart` (hetzelfde pad als
gamepad/companion-remote), en respecteert `NativeInputSession.isActive`.

200 `{"result": "dispatched"}`; 409 `{"result": "blockedByNativeSession"}`
wanneer een native invoersessie (bv. het tvOS-systeemtoetsenbord) de remote
bezit; 400 `{"result": "unknownKey"}` op een onbekend sleutelwoord.

**Verboden als uitvoeringsroute voor een tvOS-scenariostap** — zie de
tvOS-invoerroute-invariant hierboven. `TvosSimulatorDriver.press()` roept dit
endpoint nooit aan.

### `POST /v1/input/pointer`

Body: `{"x": 100.0, "y": 200.0}` (logische pixels). Synthetiseert een tap
(down + up) via `GestureBinding.handlePointerEvent`, door de echte hit-test-
pipeline — geen directe callback-aanroep. Forceert eerst pointer-mode via
`AutomationInput.onPointerModeRequested` (`InputModeTracker`'s hook, naar het
model van `GamepadService.onGamepadInput`), anders zou de app-brede
`IgnorePointer` tijdens D-pad-navigatie de tap slikken.

200 `{"result": "dispatched"}`; 409 bij een actieve native invoersessie; 400
wanneer `x`/`y` ontbreken. Geen pointer-equivalent op tvOS (geen aanraakvlak
in de zin van deze API) — het endpoint bestaat er wel, maar een scenario-stap
roept het net als `/v1/input/key` nooit aan op een tvOS-target.

### `POST /v1/overlay`

Body (alle velden optioneel, ontbrekend = ongewijzigd):
`{"enabled": true, "showIds": true, "showBounds": true}`. 200 met
`{"enabled": <huidige staat>}`.

Zet/toggelt de diagnostic-overlay — een `IgnorePointer`+`CustomPaint`-laag die
exact dezelfde `AutomationRegistry.snapshot()` tekent als `/v1/ui_tree`
teruggeeft (declared node-ids altijd, discovered-labels alleen bij
`showIds`). De **flow** voor autoritatieve diagnostic evidence:

1. `POST /v1/overlay {"enabled": true}`
2. platform-/simulatorscreenshot (buiten deze API — `xcrun simctl io …
   screenshot` op tvOS/iOS, macOS-capture op desktop)
3. `POST /v1/overlay {"enabled": false}`

De screenshot zelf komt **altijd** van de driver/simulator, nooit van
`/v1/screenshot` — zie [C5] in het Pleya Verify-plan.

### `GET /v1/screenshot`

Geen parameters. 200 met `image/png`, of 404 wanneer de
`RepaintBoundary` nog niet gemount is. Een Flutter-`RepaintBoundary`-capture
van de hele app — slaat platformcompositing, mpv/native player-lagen en
systeem-chrome over. **Nooit de bron voor een visual-PASS.** Uitsluitend
diagnostisch: bevestigt Flutter's eigen renderstate (bv. dat de overlay
tekende wat `/v1/ui_tree` rapporteerde), of als terugvaloptie op een target
zonder simulator-equivalent. Een vergelijking die hierop leunt draagt
expliciet `"source": "flutter_repaint_boundary"`.
