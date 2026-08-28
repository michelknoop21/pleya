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

Zie de event-vocabulaire in het Pleya Verify-plan voor de volledige lijst van
event-namen; op dit moment emit alleen `focus.changed` (uit
`AutomationFocusLog`). Triggert geen events (het is zelf de bron).

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
