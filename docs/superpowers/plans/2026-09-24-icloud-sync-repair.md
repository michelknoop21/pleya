# iCloud-voorkeurensync herstel: implementatieplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** De iCloud-voorkeurensync doet wat DEC-059 en DEC-096 beloven: de notificatie komt aan, de
revisie-envelop reist mee en beslist, verwijderingen reizen als tombstone, de status liegt niet, en
de taalvoorkeur van het Pleya-profiel bereikt het andere toestel.

**Architecture:** Alles blijft in de bestaande lagen: `ICloudSyncService` (facade),
`PreferenceSyncCoordinator` (engine), `PreferenceSyncPolicyRegistry` (wat mag reizen),
`PreferenceMergeRegistry` (families), `PreferenceRevision` (de regel), `ICloudKvsTransport` en de
drie Swift-plugins. Het draadformaat krijgt twee velden erbij (`t`, `d`) en een tombstonevorm
(`x`), achterwaarts leesbaar voor de uitgebrachte build. De prune verdwijnt onder v2.

**Tech Stack:** Flutter 3.44.0 (`.fvmrc`), Dart records en patterns, `shared_preferences`
(`SharedPreferencesWithCache`), `flutter_test` met `FakeTransport`
(`test/services/preferences/fake_transport.dart`) en `resetSharedPreferencesForTest`
(`test/test_helpers/prefs.dart`), Swift 5 met `swift-format` (`.swift-format`, 120 kolommen).

**Spec:** `docs/superpowers/specs/2026-09-24-icloud-sync-repair-design.md`

## Global Constraints

- Werk uitsluitend in `/Users/michelknoop/.supacode/repos/plezy-main/fix/icloud-sync`, branch
  `fix/icloud-sync`, basis `github/main` = `3ad702d3`.
- `flutter` op PATH is de gepinde 3.44.0; `dart format` (page_width 120 uit `analysis_options.yaml`)
  alleen op de bestanden die je aanraakt, nooit op heel `lib/`.
- Elke taak eindigt met een groene gerichte testrun; taak 8 draait `scripts/ci_checks.sh` en de
  volledige suite. Analyzer-warnings falen de gate.
- Commit-subjects in het Nederlands, zonder gedachtestreepjes, zonder AI-attributie of
  `Co-Authored-By`; auteur is Michel Knoop. Geen `git stash`; geen commits op `main`.
- Het draadformaat onder `__pleya_pref_v2/` blijft leesbaar voor de uitgebrachte build: een live
  record houdt `type` en `value`, een tombstone heeft geen `type`.
- `test/no_raw_preference_write_test.dart` telt raw writes per bestand exact; een nieuwe
  `_prefs.setString`/`remove` in de coordinator vraagt een bijgewerkte telling met reden.
- `test/services/preferences/v2_only_invariant_test.dart` verbiedt `useV2CloudFormat:` in `lib/`;
  de v1-tak blijft bestaan voor `test/services/icloud_rolling_upgrade_test.dart`.
- Geen nieuwe transport, geen server-side sync, geen nieuwe UI-tekst, geen profielmigratie (B12).
- `docs/agents/workflow-evaluation.md` krijgt niets (3 van 3).

## Review Focus

1. Twee ongestempelde kanten (record van de oude build tegenover een lokale waarde zonder revisie):
   de store moet winnen, zoals bij inschakelen altijd gold. Test in taak 3.
2. Een record dat de oude build ná een tombstone terugschrijft (zonder stempel): de tombstone moet
   bij de volgende reconcile opnieuw geschreven worden en de lokale waarde mag niet terugkomen. Test
   in taak 4.
3. Een profielsleutel in de map met lege scope (uitgelogd, `''`) of een `local-`-scope mag nooit
   vertrekken en nooit lokaal overschreven worden door de zender. Test in taak 6.
4. `applyRemoteKeys` met een sleutel die in `changedKeys` staat maar in `readAll` ontbreekt (de oude
   build deed `transport.remove`): de lokale waarde verdwijnt, zoals vandaag; er mag geen exception
   uit `_decodeRecord` komen. Test in taak 3.
5. Een `accountChanged` terwijl `isAvailable()` false is (uitloggen): geen `clearRevisions`, geen
   reconcile, status `unavailable`. Test in taak 5.

Modelkeuze per taak: taak 1, 2, 7 en 8 zijn mechanisch en staan volledig uitgeschreven (goedkoop
model kan). Taak 3, 4, 5 en 6 raken de revisie- en mergesemantiek en vragen een sterker model,
ook al staat de code erbij: de implementer moet begrijpen waarom een assert red of green is.

---

### Task 1: Governance-documenten (DEC-131 en het register)

**Files:**
- Modify: `docs/DECISIONS.md` (append na DEC-130, regel 2900 e.v.)
- Create: `docs/icloud-sync-repair-register.md`

**Interfaces:**
- Consumes: de spec §3 tot §8.
- Produces: het nummer `DEC-131` dat de code-comments in taak 3, 4, 5 en 6 noemen; de registerrijen
  die taak 8 sluit.

- [ ] **Step 1: Controleer dat DEC-131 vrij is**

Run: `rg -n "DEC-131|DEC-12[3-9]" docs/`
Expected: geen treffers. Is er wel een treffer, stop en meld het; hernummer niet zelf.

- [ ] **Step 2: Schrijf DEC-131 onderaan `docs/DECISIONS.md`**

```markdown

## DEC-131: De revisie-envelop reist mee, verwijderingen zijn tombstones en de prune verdwijnt onder v2

**Date:** 2026-09-24
**Status:** accepted

**Context:** De leesaudit van 24 september (`icloud-sync-audit.md`) toonde dat van de vier beloften
van DEC-059 alleen de prune-bescherming bestond. `PreferenceSyncCoordinator.listen()` werd in
productie nergens aangeroepen, dus geen `didChangeExternallyNotification` bereikte Dart en de
engine was poll-on-foreground. De envelop werd lokaal gestempeld maar reisde niet en werd bij
toepassen niet geraadpleegd; `reconcile()` schreef elke sleutel opnieuw, ook gelijke, waardoor een
toestel dat later naar voren kwam een oudere waarde met een verse aankomsttijd over een nieuwere
zette. Een lokale verwijdering werd door het andere toestel teruggezet. `disable()` gooide de
transport weg en `enable()` maakte geen nieuwe. De status meldde "Last sent" terwijl iCloud
uitgelogd was en een geslaagde reconcile wiste een quota-melding. De taalvoorkeur van het
Pleya-profiel (DEC-096) stond als profiel-scoped geregistreerd terwijl haar opslag een global map
met het profiel in de sleutel is, zodat zij inkomend op `user_<uuid>_pleya_profile_language_preferences`
landde, een sleutel die niemand leest. Acht `JsonPref`-sleutels ontsnapten aan de registratieguard
door een regex die geen generiek type met komma verdroeg. Het ontwerp staat in
`docs/superpowers/specs/2026-09-24-icloud-sync-repair-design.md`.

**Decision:** (1) De subscriptie op de transport is onvoorwaardelijk en wordt door `start()` en
`debugCreate()` via één `_wire` gezet; `disable()` schakelt alleen de vlag en gooit niets weg. (2)
Een v2-record draagt zijn stempel: `{"type","value","t","d"}`; een tombstone is `{"x":true,"t","d"}`.
Een record zonder `t`/`d` is van de build vóór dit besluit en telt als `legacyRevisionAt`. De
uitgebrachte build leest het formaat ongewijzigd en slaat tombstones over. (3) Bij toepassen wint
een inkomend record alleen als zijn stempel wint volgens `PreferenceRevision.stampWins`; zijn
beide kanten ongestempeld dan wint de store, zoals bij inschakelen en bij de cutover. Een winnende
remote stempel wordt lokaal overgenomen. Merge-families blijven mergen; voor hen beslist de stempel
niet. (4) `reconcile()` schrijft alleen wat lokaal strikt wint of in de store ontbreekt, en voor
merge-families alleen bij een andere waarde. Een lokale `remove` schrijft een tombstone; reconcile
herhaalt tombstones waar de store nog een ouder levend record heeft. (5) Onder v2 is er geen prune:
`ownsCloudKey` geeft `false`, de prune-lus draait alleen voor het v1-pad dat
`icloud_rolling_upgrade_test` bewaart. Een sleutel die de store heeft en dit toestel niet, is "nog
niet gehad" en wordt overgenomen. (6) De guard die een lokale write tijdens een remote batch liet
vallen gaat weg: de stempel ordent. (7) `_runReconcile` leest eerst `refreshAvailability()` en
stopt buiten `ready`; `apply()` stopt na het lokale stempelen bij `unavailable`; `writeSucceeded`
en `reconcileSucceeded` forceren geen `ready`; `reconcileSucceeded` laat `quota` staan. (8) Bij
`accountChanged` (en beschikbaar) worden de lokale revisies en de v1-bootstrapmarker gewist, daarna
leest de engine de store (die wint alles wat hij heeft) en duwt alleen wat het nieuwe account mist,
met stempel 0. Niets lokaal wordt gewist. Een `initialSync`-notificatie wordt gevolgd door een
reconcile onder de nieuwe trigger `ReconcileTrigger.initialSync`. (9)
`pleya_profile_language_preferences` en `track_language_preferences` zijn `global` met de
merge-familie `profileKeyedMap`: draagbaar is een mapsleutel waarvan de scope een uuid is (de Plex
Home-uuid uit `StorageService.activeUserScope()`); `local-<uuid>` en leeg blijven thuis. Inkomend
behoudt het toestel niet-draagbare entries en entries van scopes die de zender niet kent; voor
gedeelde scopes vervangt de zender de set; bij een entry aan beide kanten met `updatedAt` wint de
hoogste. (10) De registratieguard gebruikt `Pref(?:<[^()]*>)?\(\s*'`. Nieuw geregistreerd:
`keyboard_shortcuts` en `keyboard_hotkeys` als global; `media_version_preferences`,
`unified_source_preferences`, `preferred_unified_server` en `custom_shader_presets` als
device-local; `tv_live_tv_capability` als runtime cache. `live_tv_default_favorites` wordt global.
`default_quality_preset`, `buffer_size`, `mpv_config_text`, `mpv_config_presets`,
`global_shader_preset`, `enable_discord_rpc`, `video_player_navigation_enabled` en
`auto_check_updates_on_startup` synchroniseren niet meer maar blijven exporteerbaar
(`_deviceBoundPref`). (11) De Swift-plugins leveren events via `DispatchQueue.main.async`.

**Consequences:** Wat een gebruiker anders ziet: een wijziging op de Mac verschijnt op de Apple TV
zonder herstart; een teruggezette instelling blijft teruggezet; de statusregel toont geen tijdstip
als iCloud uitgelogd is; uit en weer aan werkt binnen één sessie; de taal van het Pleya-profiel
volgt over toestellen heen. Wat niet is gebouwd: profielscope voor Jellyfin- en Pleya
Server-profielen (`local-<uuid>` is per toestel; `hidden_libraries`, `library_order`, `library_*`
en de taalvoorkeur reizen voor die profielen niet), een per-account-scheiding van lokale
voorkeuren, een serverId-gefilterde familie voor `unified_source_preferences` en
`preferred_unified_server`. Bekende grenzen: verwijdert een toestel de laatste entry van een scope
in een `profileKeyedMap`, dan reist die ene verwijdering niet; het lokale revisieblob groeit tot
één entry per ooit geziene sleutel (op het zware account uit `kvs_footprint_test` 654 sleutels,
circa 40 KB); de uitgebrachte build prunet nog sleutels die hij niet kent en schrijft levende
waarden over tombstones terug, dus tot alle Apple-toestellen deze build hebben wisselen oud en
nieuw op die sleutels om, de releasevoorwaarde uit DEC-060 blijft. Bewijs: unit tegen
`FakeTransport`; geen simulator kan cross-device KVS bewijzen; per punt geldt `CODE CLOSED · UNIT
VERIFIED · HARDWARE OPEN` tot het recept in de spec §7 op twee toestellen is gedraaid. Register:
`docs/icloud-sync-repair-register.md`.
```

- [ ] **Step 3: Maak het register**

Schrijf `docs/icloud-sync-repair-register.md`:

```markdown
# Herstelregister: iCloud-voorkeurensync (DEC-131)

Aangelegd op 24 september 2026 bij DEC-131. Eén rij per punt uit de audit van dezelfde dag. De
statusladder is `OPEN`, `CODE CLOSED`, `UNIT VERIFIED`, `HARDWARE OPEN`, `DEFERRED`. Een rij krijgt
bij `CODE CLOSED` de SHA, bij `UNIT VERIFIED` het testbestand, en houdt `HARDWARE OPEN` tot het
recept uit de spec (§7) op twee ingelogde toestellen is gedraaid met datum, build en toestellen.

Spec: `docs/superpowers/specs/2026-09-24-icloud-sync-repair-design.md`.
Plan: `docs/superpowers/plans/2026-09-24-icloud-sync-repair.md`.

| Punt | Wat | Status | SHA | Bewijs |
|---|---|---|---|---|
| B1 | `listen()` in productie | OPEN | | |
| B2 | reconcile vergelijkt met de store | OPEN | | |
| B3 | envelop op de draad en bij toepassen | OPEN | | |
| B4 | verwijdering reist als tombstone | OPEN | | |
| B5 | oudere build wist nieuwe sleutels (prune) | OPEN | | |
| B6 | uit en weer aan binnen één sessie | OPEN | | |
| B7 | status bij uitgelogd iCloud | OPEN | | |
| B8 | quota-melding overleeft een reconcile | OPEN | | |
| B9 | accountwissel leest eerst | OPEN | | |
| B10 | taalvoorkeur op de juiste sleutel | OPEN | | |
| B11 | acht stille sleutels en de guard | OPEN | | |
| B12 | profielscope Jellyfin en Pleya Server | DEFERRED | | DEC-131, Consequences |
| B13 | lokale write tijdens remote batch | OPEN | | |
| A1 | event-sink op de platformthread | OPEN | | |
| A2 | reconcile na de initiële download | OPEN | | |
| A3 | sleutelaantal gemeten | OPEN | | |
| A4 | revisieblob begrensd | DEFERRED | | DEC-131, Consequences |

## Hardwareronde

Nog niet gedraaid. Recept: spec §7. Vul per rij datum, build en toestellen in; een vinkje zonder
die drie is geen bewijs.
```

- [ ] **Step 4: Controleer links en de anti-slop-hook**

Run: `rg -n "2026-09-24-icloud-sync-repair" docs/DECISIONS.md docs/icloud-sync-repair-register.md`
Expected: beide bestanden verwijzen naar spec en plan die bestaan (`ls docs/superpowers/specs/2026-09-24-icloud-sync-repair-design.md docs/superpowers/plans/2026-09-24-icloud-sync-repair.md`). Meldt de hook treffers, herstel ze eerst.

- [ ] **Step 5: Commit**

```bash
git add docs/DECISIONS.md docs/icloud-sync-repair-register.md
git commit -m "docs(sync): DEC-131 en het herstelregister voor de iCloud-voorkeurensync"
```

---

### Task 2: Luisteren in productie en een status die niet liegt (B1, B6, B7, B8)

**Files:**
- Modify: `lib/services/icloud_sync_service.dart:75-134, 174-203`
- Modify: `lib/services/preferences/preference_sync_coordinator.dart:238-267, 429-442`
- Modify: `lib/services/preferences/preference_sync_status.dart:135-172`
- Test: `test/services/icloud_sync_service_test.dart`
- Test: `test/services/preferences/sync_status_model_test.dart`
- Modify: `test/services/preferences/legacy_store_boundary_test.dart:34-66` (mock op het EventChannel)

**Interfaces:**
- Consumes: `FakeTransport` (`store`, `controller`, `available`), `RemotePreferenceChange`.
- Produces: `ICloudSyncService.start({..., PreferenceTransport? transport})`;
  `ICloudSyncService._wire(SettingsService, PreferenceSyncCoordinator)`; `disable()` zonder
  `dispose()`. Taak 5 hangt `debugHandleEvent` hieraan.

- [ ] **Step 1: Schrijf de falende tests in `test/services/icloud_sync_service_test.dart`**

Eerst het EventChannel. `_wire` abonneert straks in `debugCreate` ook, en een `EventChannel` zonder
mock levert in een test een `MissingPluginException` via `FlutterError.reportError`, wat de test
laat falen. Registreer daarom in de `setUp` van dit bestand én van
`test/services/preferences/legacy_store_boundary_test.dart` (regel 43-58) een tweede mock naast de
bestaande, en ruim hem op in `tearDown`:

```dart
  const eventsChannel = MethodChannel('com.pleya/icloud_kvs/events');
  // in setUp, na de bestaande setMockMethodCallHandler:
  messenger.setMockMethodCallHandler(eventsChannel, (call) async => null); // 'listen' and 'cancel'
  // in tearDown:
  messenger.setMockMethodCallHandler(eventsChannel, null);
```

Voeg bovenaan de imports toe:

```dart
import 'package:pleya/services/preferences/preference_transport.dart';
import 'package:pleya/services/storage_service.dart';

import 'preferences/fake_transport.dart';
```

Voeg onder de bestaande helpers toe:

```dart
/// The value inside a wire record, whatever else the record carries.
Object? valueOf(String? raw) => raw == null ? null : (json.decode(raw) as Map)['value'];
```

Voeg onderaan `main()` toe:

```dart
  test('start() subscribes to the transport, so a remote change lands without a reconcile', () async {
    final settings = await SettingsService.getInstance();
    final storage = await StorageService.getInstance();
    await settings.write(SettingsService.icloudSyncEnabled, true);
    final fake = FakeTransport();
    ICloudSyncService.debugForceSupported = true;
    await ICloudSyncService.start(settings: settings, storage: storage, transport: fake);
    fake.store[g('subtitle_font_size')] = enc('int', 61);

    fake.controller.add(
      RemotePreferenceChange(reason: RemoteChangeReason.serverChange, changedKeys: [g('subtitle_font_size')]),
    );
    await pumpEventQueue();

    expect(settings.read(SettingsService.subtitleFontSize), 61, reason: 'the production wiring must listen');
  });

  test('disable followed by enable keeps syncing in the same session', () async {
    final settings = await SettingsService.getInstance();
    final svc = ICloudSyncService.debugCreate(settings: settings);
    await svc.enable();
    await svc.disable();
    await svc.enable();

    await settings.write(SettingsService.subtitleFontSize, 52);
    await pumpEventQueue();

    expect(svc.status.value.availability, PreferenceSyncAvailability.ready);
    expect(valueOf(kvs[g('subtitle_font_size')]), 52);
  });
```

- [ ] **Step 2: Schrijf de falende statustests in `test/services/preferences/sync_status_model_test.dart`**

In de groep `a success cannot erase a condition` (na de test op regel 55):

```dart
    test('a reconcile does not clear a quota stop: the store never reports that it was lifted', () {
      const start = PreferenceSyncStatus(availability: PreferenceSyncAvailability.ready);

      final after = start
          .raise(PreferenceSyncHealth.quota)
          .reconcileSucceeded(at, pushedCount: 3, skippedCount: 0, oversizeCount: 0);

      expect(after.state, PreferenceSyncState.quota);
    });

    test('a single write cannot promote a signed-out store to ready', () {
      const signedOut = PreferenceSyncStatus(availability: PreferenceSyncAvailability.unavailable);

      final after = signedOut.starting(at).writeSucceeded(at);

      expect(after.availability, PreferenceSyncAvailability.unavailable);
    });
```

In de coordinator-gedreven groep onderaan (na `a signed-out store reports unavailable, not error`):

```dart
    test('a write while iCloud is signed out does not report a send', () async {
      final coordinator = await build();
      transport.available = false;
      await coordinator.refreshAvailability();

      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));

      expect(coordinator.status.value.state, PreferenceSyncState.unavailable);
      expect(coordinator.status.value.lastSuccess, isNull);
      expect(transport.writes, isEmpty);
    });

    test('a reconcile while iCloud is signed out writes nothing and stays unavailable', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      transport.available = false;

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(transport.writes, isEmpty);
      expect(coordinator.status.value.state, PreferenceSyncState.unavailable);
    });
```

`ReconcileTrigger` komt mee via de export van `preference_sync_coordinator.dart`; `build()` in die
groep bestaat al en levert `transport` en `settings`.

- [ ] **Step 3: Draai de tests en zie ze falen**

Run: `flutter test test/services/icloud_sync_service_test.dart test/services/preferences/sync_status_model_test.dart`
Expected: de zes nieuwe tests rood. `start()` kent geen `transport` (compilefout op dat bestand);
los dat eerst op door stap 4 alleen voor de signatuur te doen als je de rode run wilt zien.

- [ ] **Step 4: Implementeer de facade**

Vervang in `lib/services/icloud_sync_service.dart` de methode `start` (regel 75-104) door:

```dart
  /// Wire the mutation pipeline, subscribe to the transport and, if the toggle
  /// is on, reconcile. Safe to call on any platform; no-ops off Apple platforms.
  ///
  /// [transport] exists so a test can drive this exact path with a fake. It
  /// was the missing piece of DEC-131's B1: the listener was only ever attached
  /// by tests calling `coordinator.listen()` themselves.
  static Future<void> start({
    required SettingsService settings,
    required StorageService storage,
    VoidCallback? onRemoteChangesApplied,
    @visibleForTesting PreferenceTransport? transport,
  }) async {
    if (!_supported || _instance != null) return;
    // A dedicated id, not the Plex client identifier: that one is sent to
    // plex.tv and identifies the device to a third party.
    final deviceId = await PreferenceDeviceId.getOrCreate(settings.prefs);
    final coordinator = PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: storage.getActiveProfileId,
      enabled: () => settings.read(SettingsService.icloudSyncEnabled),
      deviceId: deviceId,
      transport: transport ?? ICloudKvsTransport(),
      onRemoteChangesApplied: onRemoteChangesApplied,
      onLocalStateChanged: settings.refreshListenables,
    )..onRuntimeRefresh = PreferenceRefreshBus.instance.invalidate;
    final svc = _wire(settings, coordinator);
    // A key-value store can change while the process is suspended, and the
    // notification for that change can be delivered to nobody. Coming back to
    // the foreground is therefore a reconcile trigger, not a hope.
    svc._lifecycle = AppLifecycleListener(
      onResume: () => unawaited(coordinator.requestReconcile(ReconcileTrigger.foreground)),
    );
    await coordinator.refreshAvailability();
    if (svc._enabled) await coordinator.requestReconcile(ReconcileTrigger.boot);
  }

  /// Everything a live instance needs, shared by [start] and [debugCreate] so
  /// a test of the fake path proves the production one.
  ///
  /// The subscription is unconditional. The coordinator drops events while the
  /// toggle is off, and a subscription that only exists after `enable()` is
  /// how it came to exist nowhere at all.
  static ICloudSyncService _wire(SettingsService settings, PreferenceSyncCoordinator coordinator) {
    final svc = ICloudSyncService._(settings, coordinator);
    _instance = svc;
    BaseSharedPreferencesService.onMutation = coordinator.apply;
    coordinator.listen();
    return svc;
  }
```

Vervang `enable` en `disable` (regel 121-134) door:

```dart
  /// Turn sync on: persist the toggle, then pull remote and upload local keys.
  Future<void> enable() async {
    await _settings.write(SettingsService.icloudSyncEnabled, true);
    await _coordinator.refreshAvailability();
    _coordinator.listen();
    await _coordinator.requestReconcile(ReconcileTrigger.enabled);
  }

  /// Turn sync off: persist the toggle. The transport and the subscription
  /// stay; the coordinator ignores events and writes while the toggle is off,
  /// and tearing them down here left `enable()` with nothing to re-enable.
  Future<void> disable() async {
    await _settings.write(SettingsService.icloudSyncEnabled, false);
    await _coordinator.refreshAvailability();
  }
```

Vervang in `debugCreate` (regel 199-202) de vier regels vanaf `final svc = ICloudSyncService._(...)`
tot en met `return svc;` door:

```dart
    return _wire(settings, coordinator);
```

- [ ] **Step 5: Implementeer de gates in de coordinator**

In `apply()` direct na `if (transport == null) return;` (regel 262):

```dart
    if (status.value.availability == PreferenceSyncAvailability.unavailable) {
      // Signed out. The change is stamped above, so the first reconcile after
      // signing back in carries it; writing now would only produce a "last
      // sent" time for a value that went nowhere.
      return;
    }
```

In `_runReconcile` na de ambient-gate (regel 435), vóór `needsBootstrap`:

```dart
    // The store may have gone away while we were suspended; the status has to
    // say so before this pass pretends to have sent anything.
    await refreshAvailability();
    if (status.value.availability != PreferenceSyncAvailability.ready) return;
```

- [ ] **Step 6: Implementeer de status**

In `lib/services/preferences/preference_sync_status.dart` vervang `starting`, `writeSucceeded` en
`reconcileSucceeded` (regel 135-172) door:

```dart
  /// A pass started. `disabled` is promoted to `ready` because a pass only
  /// starts while the toggle is on, so that value is stale; `unavailable` is
  /// not, because a write to a signed-out store succeeds locally and proves
  /// nothing.
  PreferenceSyncStatus starting(DateTime at) => copyWith(
    activity: PreferenceSyncActivity.syncing,
    lastAttempt: at,
    availability: availability == PreferenceSyncAvailability.unavailable
        ? PreferenceSyncAvailability.unavailable
        : PreferenceSyncAvailability.ready,
  );

  /// One value left the device. Says nothing about health or availability: a
  /// single write succeeding does not mean the quota stop or the failed
  /// reconcile before it went away, and it does not mean anyone is signed in.
  PreferenceSyncStatus writeSucceeded(DateTime at) =>
      copyWith(activity: PreferenceSyncActivity.idle, lastSuccess: at, pushed: pushed + 1);

  /// A full pass finished. This is the only thing entitled to clear health: it
  /// looked at everything, so what it did not find is genuinely gone. Quota is
  /// the exception: the store reports a violation and never reports that it
  /// was lifted, so only a restart or the toggle clears it.
  PreferenceSyncStatus reconcileSucceeded(
    DateTime at, {
    required int pushedCount,
    required int skippedCount,
    required int oversizeCount,
  }) => PreferenceSyncStatus(
    availability: availability,
    activity: PreferenceSyncActivity.idle,
    health: oversizeCount > 0
        ? PreferenceSyncHealth.warning
        : (health == PreferenceSyncHealth.quota ? PreferenceSyncHealth.quota : PreferenceSyncHealth.healthy),
    legacyPeerDetected: legacyPeerDetected,
    lastAttempt: lastAttempt,
    lastSuccess: at,
    lastRemoteChange: lastRemoteChange,
    pushed: pushed + pushedCount,
    applied: applied,
    skipped: skipped + skippedCount,
    oversize: oversize + oversizeCount,
    errorCategory: oversizeCount > 0 ? errorCategory : null,
  );
```

- [ ] **Step 7: Draai de tests**

Run: `dart format lib/services/icloud_sync_service.dart lib/services/preferences/preference_sync_coordinator.dart lib/services/preferences/preference_sync_status.dart test/services/icloud_sync_service_test.dart test/services/preferences/sync_status_model_test.dart`
Run: `flutter test test/services/icloud_sync_service_test.dart test/services/preferences test/screens/settings/icloud_sync_status_test.dart`
Expected: alles groen. Wordt `the quota stop is shown, and a later successful write does not hide it`
in de widgettest rood, dan is `starting()` verkeerd gegaan; de basis daar is `ready`.

- [ ] **Step 8: Commit**

```bash
git add lib/services/icloud_sync_service.dart lib/services/preferences/preference_sync_coordinator.dart lib/services/preferences/preference_sync_status.dart test/services/icloud_sync_service_test.dart test/services/preferences/sync_status_model_test.dart test/services/preferences/legacy_store_boundary_test.dart
git commit -m "fix(sync): luister echt naar de KVS-notificaties en laat de status niet liegen (B1, B6, B7, B8)"
```

---

### Task 3: De envelop op de draad en beslissend bij toepassen (B3)

Sterker model. Lees eerst de spec §3 onder B3 en `lib/services/preferences/preference_revision.dart`.

**Files:**
- Modify: `lib/services/preferences/preference_revision.dart:37-88`
- Modify: `lib/services/preferences/preference_sync_coordinator.dart:38-42, 260-322, 326-406, 508-637`
- Create: `test/services/preferences/revision_on_the_wire_test.dart`
- Modify: `test/services/preferences/preference_revision_test.dart:64-90`
- Modify: `test/services/preferences/kvs_footprint_test.dart:33, 57-59`
- Modify: `test/services/icloud_sync_service_test.dart:73, 154-155, 193, 214`
- Modify: `test/no_raw_preference_write_test.dart:58-62`

**Interfaces:**
- Consumes: `PreferenceRevision.winsOver`, `_revisions()`, `legacyRevisionAt`, `_decodeTyped`.
- Produces: `PreferenceRevision.stampWins({at, device, deleted, overAt, overDevice, overDeleted})`;
  in de coordinator `typedef _Stamp = ({int at, String device, bool deleted})`, `_localStamp(baseKey)`,
  `_adoptStamp(baseKey, stamp)`, `_remoteWins(remote, local)`, `_encodeRecord(entry, stamp)`,
  `_encodeTombstone(stamp)`, `_decodeRecord(raw)`, `clearRevisions()`. Taak 4 en 5 gebruiken al deze
  namen.

- [ ] **Step 1: Schrijf `test/services/preferences/revision_on_the_wire_test.dart`**

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// DEC-131 (2) and (3). The envelope leaves the device with every record and
/// decides on arrival. A record without a stamp is one the previous build
/// wrote and counts as the oldest possible.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: homeUuid);

  late SettingsService settings;
  late FakeTransport transport;

  Future<PreferenceSyncCoordinator> build({String deviceId = 'macbook'}) async {
    settings = await SettingsService.getInstance();
    transport = FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => profile,
      enabled: () => true,
      deviceId: deviceId,
      transport: transport,
    );
  }

  String bare(String type, Object? value) => json.encode({'type': type, 'value': value});
  String stamped(String type, Object? value, int at, String device) =>
      json.encode({'type': type, 'value': value, 't': at, 'd': device});
  String tombstone(int at, String device) => json.encode({'x': true, 't': at, 'd': device});
  Map<String, dynamic> record(PreferenceSyncCoordinator c, String baseKey) =>
      json.decode(transport.store[c.cloudKeyFor(baseKey)!]!) as Map<String, dynamic>;
  int future() => DateTime.now().toUtc().millisecondsSinceEpoch + 60 * 60 * 1000;

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  group('outbound', () {
    test('a write carries its stamp next to the typed value', () async {
      final coordinator = await build();

      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));

      final r = record(coordinator, 'subtitle_font_size');
      expect(r['type'], 'int');
      expect(r['value'], 44);
      expect(r['t'], isA<int>());
      expect(r['t'], greaterThan(0));
      expect(r['d'], 'macbook');
    });

    test('the meta record stays a bare typed value', () async {
      final coordinator = await build();

      await coordinator.reconcile();

      final meta = json.decode(transport.store[PreferenceSyncCoordinator.v2MetaVersionKey]!) as Map;
      expect(meta.containsKey('t'), isFalse);
    });
  });

  group('inbound', () {
    test('an older remote record does not overwrite a newer local change', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = stamped('int', 99, 1000, 'appletv');

      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), 44);
    });

    test('a newer remote record wins and its stamp is adopted', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      final at = future();
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = stamped('int', 99, at, 'appletv');

      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), 99);
      final adopted = coordinator.localRevision('subtitle_font_size')!;
      expect(adopted.updatedAt, at);
      expect(adopted.deviceId, 'appletv');
    });

    test('a later local change stamps past an adopted remote stamp', () async {
      final coordinator = await build();
      final at = future();
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = stamped('int', 99, at, 'appletv');
      await coordinator.applyAllRemote();

      await settings.prefs.setInt('subtitle_font_size', 50);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 50));

      expect(coordinator.localRevision('subtitle_font_size')!.updatedAt, greaterThan(at));
      expect(record(coordinator, 'subtitle_font_size')['value'], 50);
    });

    test('a record from the previous build beats an unstamped local value: the store wins', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 30);
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = bare('int', 99);

      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), 99, reason: 'two unstamped sides: the store wins');
    });

    test('a stamped local value beats a record from the previous build', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = bare('int', 99);

      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), 44);
    });

    test('an identical stamp on both sides applies nothing', () async {
      final coordinator = await build();
      final at = future();
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = stamped('int', 99, at, 'appletv');
      await coordinator.applyAllRemote();
      final applied = coordinator.status.value.applied;

      await coordinator.applyAllRemote();

      expect(coordinator.status.value.applied, applied);
    });

    test('a newer tombstone removes the local value and is remembered', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = tombstone(future(), 'appletv');

      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), isNull);
      expect(coordinator.localRevision('subtitle_font_size')!.deleted, isTrue);
    });

    test('an older tombstone does not remove a newer local value', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = tombstone(1000, 'appletv');

      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), 44);
    });

    test('a key named in the event but absent from the store is still removed, as the previous build did', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);

      await coordinator.applyRemoteKeys([coordinator.cloudKeyFor('subtitle_font_size')!]);

      expect(settings.prefs.getInt('subtitle_font_size'), isNull);
    });

    test('a merge family merges regardless of the stamp', () async {
      final coordinator = await build();
      coordinator.serverIdPortability = (id) => id == 'plex';
      final key = 'user_${homeUuid}_hidden_libraries';
      await settings.prefs.setString(key, json.encode(['plex:1', 'folder:9']));
      await coordinator.apply(PreferenceMutation.set(key, json.encode(['plex:1', 'folder:9'])));
      transport.store[coordinator.cloudKeyFor(key)!] = stamped('string', json.encode(['plex:2']), 1000, 'appletv');

      await coordinator.applyAllRemote();

      expect(json.decode(settings.prefs.getString(key)!), unorderedEquals(['plex:2', 'folder:9']));
    });
  });
}
```

- [ ] **Step 2: Draai en zie rood**

Run: `flutter test test/services/preferences/revision_on_the_wire_test.dart`
Expected: `a write carries its stamp` rood (geen `t`), `an older remote record does not overwrite`
rood (99 gewonnen), tombstone-tests rood (record wordt overgeslagen, waarde blijft), de rest mag al
groen zijn.

- [ ] **Step 3: `PreferenceRevision.stampWins`**

Vervang in `lib/services/preferences/preference_revision.dart` `winsOver` (regel 40-52) door:

```dart
  /// Deterministic last-writer-wins.
  ///
  /// Newer [updatedAt] wins. On an exact tie the higher [deviceId] wins, which
  /// is arbitrary but identical on both devices, so they converge instead of
  /// ping-ponging. A tombstone does not get special treatment beyond its
  /// timestamp: deleting at 10:00 and re-adding at 10:05 keeps the value.
  bool winsOver(PreferenceRevision other) => stampWins(
    at: updatedAt,
    device: deviceId,
    deleted: deleted,
    overAt: other.updatedAt,
    overDevice: other.deviceId,
    overDeleted: other.deleted,
  );

  /// The rule behind [winsOver], on bare stamps. The coordinator compares a
  /// wire record against a stored stamp without having a value for either side
  /// at hand, and a live [PreferenceRevision] insists on one.
  static bool stampWins({
    required int at,
    required String device,
    required bool deleted,
    required int overAt,
    required String overDevice,
    required bool overDeleted,
  }) {
    if (at != overAt) return at > overAt;
    if (device != overDevice) return device.compareTo(overDevice) > 0;
    // Same instant, same device: prefer the tombstone, so a remove that
    // arrives alongside its own set does not leave the value behind.
    return deleted && !overDeleted;
  }
```

Verwijder `toJson()`, `encode()`, `decode()` en `_normalize` (regel 58-88): de coordinator schrijft
het draadformaat zelf en niets in `lib/` riep ze aan. Verwijder in
`test/services/preferences/preference_revision_test.dart` de test `a delete survives a round trip
through the wire format` en de hele groep `encoding`. Pas de klasse-doc aan: de zin over "the
Pleya Server transport" blijft, voeg toe dat het draadformaat in `PreferenceSyncCoordinator` staat
(DEC-131).

- [ ] **Step 4: Draadformaat-helpers in de coordinator**

Vervang de klasse-doc regel 38-42 door:

```dart
/// Since DEC-131 the wire format carries the envelope: a record is
/// `{"type","value","t","d"}` and a removal is a tombstone `{"x":true,"t","d"}`.
/// Both live in the `__pleya_pref_v2/` namespace the previous build already
/// reads; that build ignores `t` and `d` and skips a tombstone, so the formats
/// coexist. A record without a stamp is one the previous build wrote and
/// counts as [legacyRevisionAt].
```

Zet op bestandsniveau, direct boven `class PreferenceSyncCoordinator` (een `typedef` kan niet in
een klasse):

```dart
/// A stamp as stored locally or read from a record.
typedef _Stamp = ({int at, String device, bool deleted});
```

Voeg direct onder `static const int legacyRevisionAt = 0;` (regel 349) toe:

```dart
  /// The device a stamp-less record is attributed to. Any real id compares
  /// above the empty string, which is exactly the tie we want unstamped local
  /// values to lose (see [_remoteWins]).
  static const String _noDevice = '';

  _Stamp _localStamp(String baseKey) {
    final entry = _revisions()[baseKey];
    if (entry is Map && entry['t'] is int && entry['d'] is String) {
      return (at: entry['t'] as int, device: entry['d'] as String, deleted: entry['x'] == true);
    }
    return (at: legacyRevisionAt, device: _noDevice, deleted: false);
  }

  /// Remember the stamp of a remote record this device just adopted, so the
  /// next comparison is against it and the next local change stamps past it.
  Future<void> _adoptStamp(String baseKey, _Stamp stamp) async {
    final revisions = _revisions();
    revisions[baseKey] = {'t': stamp.at, 'd': stamp.device, if (stamp.deleted) 'x': true};
    await _prefs.setString(revisionStoreKey, json.encode(revisions));
  }

  /// Whether a remote record replaces what this device holds.
  ///
  /// Two unstamped sides (a record from the previous build against a local
  /// value nobody stamped) cannot be ordered, and the store wins: that is what
  /// enabling sync always did and what the cutover chose.
  static bool _remoteWins(_Stamp remote, _Stamp local) {
    if (remote.at == legacyRevisionAt && local.at == legacyRevisionAt) return true;
    return PreferenceRevision.stampWins(
      at: remote.at,
      device: remote.device,
      deleted: remote.deleted,
      overAt: local.at,
      overDevice: local.device,
      overDeleted: local.deleted,
    );
  }

  static bool _sameStamp(_Stamp a, _Stamp b) => a.at == b.at && a.device == b.device && a.deleted == b.deleted;

  String _encodeRecord(Map<String, dynamic> typed, _Stamp stamp) =>
      json.encode({...typed, 't': stamp.at, 'd': stamp.device});

  String _encodeTombstone(_Stamp stamp) => json.encode({'x': true, 't': stamp.at, 'd': stamp.device});

  /// A wire record, or null when [raw] is not one. `type` is empty for a
  /// tombstone. A missing stamp is the previous build's record.
  ({String type, Object? value, _Stamp stamp})? _decodeRecord(String raw) {
    try {
      final m = json.decode(raw);
      if (m is! Map) return null;
      final deleted = m['x'] == true;
      final type = m['type'];
      if (!deleted && type is! String) return null;
      final at = m['t'];
      final device = m['d'];
      return (
        type: type is String ? type : '',
        value: m['value'],
        stamp: (
          at: at is int ? at : legacyRevisionAt,
          device: device is String ? device : _noDevice,
          deleted: deleted,
        ),
      );
    } catch (_) {
      return null;
    }
  }
```

Vervang `debugClearRevisions` (regel 405-406) door:

```dart
  /// Forget every stamp. Used when the account under the store changes (the
  /// stamps describe edits against another account's history) and by tests.
  Future<void> clearRevisions() => _prefs.remove(revisionStoreKey);
```

Run daarna `rg -n "debugClearRevisions" test/` en hernoem eventuele aanroepen naar `await coordinator.clearRevisions()`.

- [ ] **Step 5: Uitgaand in `apply()`**

Vervang regel 301-317 (`final entry = ...` tot en met `_setStatus(status.value.writeSucceeded(...))`) door:

```dart
      final entry = SettingsExportService.encodeValue(portableValue);
      if (entry == null) {
        _setStatus(status.value.countingSkipped(1));
        return;
      }
      final encoded = _encodeRecord(entry, _localStamp(baseKey));
      final cap = transport.maxValueBytes;
      if (cap != null && encoded.length > cap) {
        // Oversize is reported, not swallowed. It also must not become a
        // removal: leaving the older cloud value in place is strictly better
        // than deleting it because the newer one did not fit.
        appLogger.w('preference sync: value for ${_category(baseKey)} exceeds the transport cap');
        _setStatus(status.value.copyWith(oversize: status.value.oversize + 1).raise(PreferenceSyncHealth.warning));
        return;
      }
      await transport.write(cloudKey, encoded);
      _setStatus(status.value.writeSucceeded(DateTime.now()));
```

- [ ] **Step 6: Inkomend in `applyEntries`**

Vervang regel 569-598 (`final family = ...` tot en met de `else { skipped++; }` van `writeTyped`) door:

```dart
        final refresh = PreferenceSyncPolicyRegistry.policyFor(baseKey).refresh;

        final raw = entry.value;
        if (raw == null) {
          // Named in the event, gone from the store: the previous build's
          // `transport.remove`. It carries no stamp, so it is honoured as it
          // always was. This build never removes; it writes a tombstone.
          await _prefs.remove(targetKey);
          changed++;
          if (refresh != null) stale.add(refresh);
          continue;
        }
        final record = _decodeRecord(raw);
        if (record == null) {
          skipped++;
          continue;
        }
        final family = _merges.familyFor(baseKey);
        if (family == null && !_remoteWins(record.stamp, _localStamp(baseKey))) {
          skipped++;
          continue; // this device's change is newer, or the same
        }
        if (record.stamp.deleted) {
          if (_prefs.containsKey(targetKey)) {
            await _prefs.remove(targetKey);
            changed++;
            if (refresh != null) stale.add(refresh);
          }
          await _adoptStamp(baseKey, record.stamp);
          continue;
        }
        var value = record.value;
        final inbound = family?.inbound;
        if (inbound != null) {
          // Not a replacement. What the family does with the two sides is the
          // family's business; for the server-scoped lists it keeps what the
          // sender never saw, because treating that absence as a removal would
          // wipe this device's local-folder libraries on every remote change.
          value = inbound(_prefs.get(targetKey), value);
        }
        final ok = await SettingsExportService.writeTyped(_prefs, targetKey, record.type, value);
        if (ok) {
          changed++;
          if (refresh != null) stale.add(refresh);
          if (family == null) await _adoptStamp(baseKey, record.stamp);
        } else {
          skipped++;
        }
```

`_prefs.remove(targetKey)` komt nu twee keer voor; `no_raw_preference_write_test` telt de coordinator
daarmee op 6 (twee `remove(targetKey)`, `_stampRevision`, `bootstrapLegacyRevision`, `_adoptStamp`,
`clearRevisions`). Zet in `test/no_raw_preference_write_test.dart:58-62` de telling op `6` met reden
`'applies remote entries, removes on a tombstone or an absent key, and persists its own revision metadata; re-reporting those would echo'`.

- [ ] **Step 7: De overige tests op het nieuwe formaat**

In `test/services/icloud_sync_service_test.dart` vervang de vier gelijkheden op door de coordinator
geschreven records door `valueOf(...)`: regel 73 `expect(valueOf(kvs[g('subtitle_font_size')]), 44);`,
regel 154 `expect(valueOf(kvs[g('seek_time_small')]), 5, reason: 'local-unique uploaded');`, regel
193 en 214 `expect(valueOf(kvs[g('seek_time_small')]), 8);`. De metasleutel-vergelijking op 155
blijft.

In `test/services/preferences/kvs_footprint_test.dart` vervang de helper op regel 33 en de opmerking
op 57-59:

```dart
  String typed(String type, Object? value) => json.encode({'type': type, 'value': value});

  /// What a record costs since DEC-131: the typed value plus a stamp of the
  /// shape the coordinator writes (a millisecond timestamp and a v4 uuid).
  String enveloped(String type, Object? value) =>
      json.encode({'type': type, 'value': value, 't': 1758700000000, 'd': '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e'});
```

Laat `v2Footprint()` `typed` blijven gebruiken (het meet de prefix) en voeg een test toe:

```dart
  test('the envelope on every record still leaves half the store free', () {
    var v2 = 0;
    const prefix = PreferenceSyncScope.cloudNamespacePrefix;
    for (var i = 0; i < globalPrefs; i++) {
      v2 += bytesOf('${prefix}global/a_reasonably_long_preference_name_$i', enveloped('int', 42));
    }
    final libs = libraryKeys();
    final profilePrefix = '${prefix}profile/$homeUuid/';
    v2 += bytesOf('${profilePrefix}hidden_libraries', enveloped('string', json.encode(libs)));
    v2 += bytesOf('${profilePrefix}library_order', enveloped('string', json.encode(libs)));
    for (final lib in libs) {
      v2 += bytesOf('${profilePrefix}library_sort_$lib', enveloped('string', '{"key":"titleSort","descending":false}'));
      v2 += bytesOf('${profilePrefix}library_grouping_$lib', enveloped('string', 'movies'));
      v2 += bytesOf('${profilePrefix}library_tab_$lib', enveloped('string', 'Recommended'));
    }
    // ignore: avoid_print
    print('KVS footprint with envelope: v2 ${v2 ~/ 1024} KB, plus frozen v1 ${v1Footprint() ~/ 1024} KB');
    expect(v1Footprint() + v2, lessThan(kvsTotalBytes ~/ 2));
  });
```

Vervang de zin "The envelope is not on the wire yet for scalars, so this measures the key growth"
door "Measures the key growth alone; the envelope's cost has its own test below."

- [ ] **Step 8: Draai alles wat de sync raakt**

Run: `dart format lib/services/preferences/preference_revision.dart lib/services/preferences/preference_sync_coordinator.dart test/services/preferences/revision_on_the_wire_test.dart test/services/preferences/preference_revision_test.dart test/services/preferences/kvs_footprint_test.dart test/services/icloud_sync_service_test.dart test/no_raw_preference_write_test.dart`
Run: `flutter test test/services/preferences test/services/icloud_sync_service_test.dart test/services/icloud_rolling_upgrade_test.dart test/no_raw_preference_write_test.dart`
Expected: groen. Rood in `v2_cutover_test` `a later real v2 mutation beats a bootstrapped value` wijst op een kapotte `winsOver`; rood in `local_only_bookkeeping_test` `a revision stamp never leaves the device` mag niet gebeuren (de stempel zit in het record, niet als eigen sleutel: `k.contains('revision')` matcht geen recordinhoud).

- [ ] **Step 9: Commit**

```bash
git add lib/services/preferences/preference_revision.dart lib/services/preferences/preference_sync_coordinator.dart test/services/preferences/revision_on_the_wire_test.dart test/services/preferences/preference_revision_test.dart test/services/preferences/kvs_footprint_test.dart test/services/icloud_sync_service_test.dart test/no_raw_preference_write_test.dart
git commit -m "feat(sync): de revisie-envelop reist mee en beslist bij het toepassen (B3)"
```

---

### Task 4: Reconcile vergelijkt, verwijderingen zijn tombstones, geen prune onder v2 (B2, B4, B5, B13)

Sterker model. Lees de spec §3 onder B2/B4, B5 en B13 voordat je begint.

**Files:**
- Modify: `lib/services/preferences/preference_sync_coordinator.dart:98-102, 238-275, 650-669, 743-844`
- Create: `test/services/preferences/reconcile_and_tombstones_test.dart`
- Modify: `test/services/preferences/preference_sync_coordinator_test.dart:50-58, 67-73, 236-244`
- Modify: `test/services/preferences/merge_strategy_test.dart:205-213`
- Modify: `test/services/preferences/namespace_ownership_test.dart:110-126`
- Modify: `test/services/preferences/v2_cutover_test.dart:90-96`
- Modify: `test/services/preferences/local_first_failure_test.dart:54-65`
- Modify: `test/services/icloud_sync_service_test.dart:194-215`

**Interfaces:**
- Consumes: `_localStamp`, `_remoteWins`, `_sameStamp`, `_encodeRecord`, `_encodeTombstone`,
  `_decodeRecord`, `_revisions()` uit taak 3.
- Produces: `reconcile()` zonder prune onder v2; `ownsCloudKey` geeft `false` onder v2; `apply()`
  schrijft een tombstone bij `remove`. Taak 5 bouwt op `reconcile()` zoals hier gedefinieerd.

- [ ] **Step 1: Schrijf `test/services/preferences/reconcile_and_tombstones_test.dart`**

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// DEC-131 (4), (5) and (6). A reconcile writes what is newer here and nothing
/// else; a removal is a tombstone the other device honours; nothing is pruned
/// under v2; a local write during a remote batch is ordered by its stamp.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: homeUuid);

  late SettingsService settings;
  late FakeTransport transport;

  Future<PreferenceSyncCoordinator> build({String deviceId = 'macbook', FakeTransport? shared}) async {
    settings = await SettingsService.getInstance();
    transport = shared ?? FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => profile,
      enabled: () => true,
      deviceId: deviceId,
      transport: transport,
    );
  }

  String bare(String type, Object? value) => json.encode({'type': type, 'value': value});
  String stamped(String type, Object? value, int at, String device) =>
      json.encode({'type': type, 'value': value, 't': at, 'd': device});
  Map<String, dynamic> decode(String raw) => json.decode(raw) as Map<String, dynamic>;
  int future() => DateTime.now().toUtc().millisecondsSinceEpoch + 60 * 60 * 1000;

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  group('a reconcile compares before it writes', () {
    test('a second reconcile over an unchanged store writes nothing at all', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      await coordinator.reconcile();
      transport.writes.clear();

      await coordinator.reconcile();

      expect(transport.writes, isEmpty, reason: 'the meta record and every value were already there');
    });

    test('an older local value is not pushed over a newer remote one', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      await settings.prefs.setInt('subtitle_font_size', 30);
      transport.store[cloudKey] = stamped('int', 99, future(), 'appletv');

      await coordinator.reconcile();

      expect(transport.writes, isNot(contains(cloudKey)));
      expect(decode(transport.store[cloudKey]!)['value'], 99);
    });

    test('a newer local value is pushed over an older remote one', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      transport.store[cloudKey] = stamped('int', 99, 1000, 'appletv');

      await coordinator.reconcile();

      expect(decode(transport.store[cloudKey]!)['value'], 44);
    });

    test('a merge family is rewritten only when the merged value differs', () async {
      final coordinator = await build();
      coordinator.serverIdPortability = (id) => id == 'plex';
      final key = 'user_${homeUuid}_hidden_libraries';
      final cloudKey = coordinator.cloudKeyFor(key)!;
      await settings.prefs.setString(key, json.encode(['plex:1']));
      transport.store[cloudKey] = stamped('string', json.encode(['plex:1']), 1000, 'appletv');

      await coordinator.reconcile();

      expect(transport.writes, isNot(contains(cloudKey)));
    });
  });

  group('a removal is a tombstone', () {
    test('a local removal writes a tombstone instead of removing the record', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));

      await coordinator.apply(const PreferenceMutation.remove('subtitle_font_size'));

      expect(transport.removes, isEmpty);
      final r = decode(transport.store[cloudKey]!);
      expect(r['x'], isTrue);
      expect(r.containsKey('value'), isFalse);
      expect(r['d'], 'macbook');
    });

    test('the other device honours the tombstone and does not push its value back', () async {
      // Device A sets and removes.
      final a = await build(deviceId: 'macbook');
      await settings.prefs.setInt('subtitle_font_size', 44);
      await a.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      await a.apply(const PreferenceMutation.remove('subtitle_font_size'));
      final shared = transport;

      // Device B still holds the value it received earlier, unstamped.
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      final b = await build(deviceId: 'appletv', shared: shared);
      await settings.prefs.setInt('subtitle_font_size', 44);

      await b.requestReconcile(ReconcileTrigger.foreground);

      expect(settings.prefs.getInt('subtitle_font_size'), isNull, reason: 'B applies the tombstone');
      final r = decode(shared.store[b.cloudKeyFor('subtitle_font_size')!]!);
      expect(r['x'], isTrue, reason: 'B did not resurrect the value');
      expect(b.localRevision('subtitle_font_size')!.deleted, isTrue);
    });

    test('a live record the previous build wrote back over a tombstone is tombstoned again', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      await coordinator.apply(const PreferenceMutation.remove('subtitle_font_size'));
      transport.store[cloudKey] = bare('int', 44); // the old build's reconcile

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(decode(transport.store[cloudKey]!)['x'], isTrue);
      expect(settings.prefs.getInt('subtitle_font_size'), isNull, reason: 'and it did not come back locally');
    });

    test('a reset removal is a tombstone too', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('theme_mode')!;

      await coordinator.apply(const PreferenceMutation.remove('theme_mode', source: PreferenceSource.reset));

      expect(decode(transport.store[cloudKey]!)['x'], isTrue);
    });
  });

  group('nothing is pruned under v2', () {
    test('a record this device never had is adopted, not deleted', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('theme_mode')!;
      transport.store[cloudKey] = bare('string', 'dark');

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(transport.removes, isEmpty);
      expect(settings.prefs.getString('theme_mode'), 'dark');
    });

    test('a record for a key this build does not know survives a reconcile', () async {
      final coordinator = await build();
      const futureKey = '${PreferenceSyncScope.cloudNamespacePrefix}global/a_pref_from_a_newer_build';
      transport.store[futureKey] = stamped('int', 1, 5, 'iphone');

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(transport.removes, isEmpty);
      expect(transport.store.containsKey(futureKey), isTrue);
    });

    test('ownsCloudKey claims nothing under v2', () async {
      final coordinator = await build();

      expect(coordinator.ownsCloudKey('${PreferenceSyncScope.cloudNamespacePrefix}global/theme_mode'), isFalse);
    });
  });

  group('a local write during a remote batch', () {
    test('still reaches the store', () async {
      final coordinator = await build();
      final applying = coordinator.applyEntries({
        coordinator.cloudKeyFor('theme_mode')!: stamped('string', 'dark', 1000, 'appletv'),
      });
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      await applying;

      expect(transport.store.containsKey(coordinator.cloudKeyFor('subtitle_font_size')!), isTrue);
    });
  });
}
```

- [ ] **Step 2: Draai en zie rood**

Run: `flutter test test/services/preferences/reconcile_and_tombstones_test.dart`
Expected: rood op `writes nothing at all`, alle tombstone-tests, `is adopted, not deleted`
(`removes` bevat de sleutel), `ownsCloudKey claims nothing`, `still reaches the store`.

- [ ] **Step 3: Tombstone bij `remove` in `apply()`**

Vervang in `apply()` regel 269-275 door:

```dart
      if (mutation.operation == PreferenceOperation.remove) {
        // A removal is a first-class change. v1 lost it here: the hook only had
        // a key, read `null` back, and stopped. Since DEC-131 it travels as a
        // tombstone rather than as an absent key, so the other device can tell
        // "deleted" from "never had it".
        await transport.write(cloudKey, _encodeTombstone(_localStamp(baseKey)));
        _setStatus(status.value.writeSucceeded(DateTime.now()));
        return;
      }
```

Verwijder de guard regel 247-252 en het veld `_applyingRemote` (regel 100-102) met zijn twee
toewijzingen in `applyEntries` (`_applyingRemote = true;` en het `finally`-blok; de `try` blijft
niet nodig, haal hem weg). Vervang de veld-doc door niets; de reden staat in DEC-131 (6).

- [ ] **Step 4: `reconcile()` zonder prune, met vergelijking en tombstones**

Vervang `ownsCloudKey` (regel 650-669) door:

```dart
  /// Whether a transport key is a record this coordinator, in its current
  /// format, is entitled to delete.
  ///
  /// Under v2 the answer is always no. A removal travels as a tombstone since
  /// DEC-131, so a record this device does not hold is one it has not seen
  /// yet, never one it deleted. The v1 path keeps its prune for the
  /// rolling-upgrade test, which runs the released algorithm.
  bool ownsCloudKey(String cloudKey) {
    if (_useV2CloudFormat) return false;
    if (cloudKey.startsWith('__')) return false;
    return PreferenceSyncPolicyRegistry.maySync(cloudKey);
  }
```

Vervang `reconcile()` (regel 743-844) door:

```dart
  /// Push every syncable local key whose stamp is newer than the store's, or
  /// which the store lacks; re-send tombstones the store has been written over.
  Future<void> reconcile() async {
    final transport = _transport;
    if (transport == null) return;
    _setStatus(status.value.starting(DateTime.now()));

    try {
      // The store is read before anything is written. A failed read is not an
      // empty store: everything that can decide on its own is still pushed, and
      // nothing is compared against a blank.
      final remote = await transport.readAll();

      var pushed = 0;
      var skipped = 0;
      var oversize = 0;
      final known = <String>{};
      for (final fullKey in _prefs.keys) {
        final baseKey = baseKeyOf(fullKey);
        if (baseKey != null) known.add(baseKey);
        final cloudKey = cloudKeyFor(fullKey);
        if (cloudKey == null || baseKey == null) continue;
        final family = _merges.familyFor(baseKey);
        if ((family?.mergesOutgoing ?? false) && remote == null) {
          // Merging blind would push over entries this device cannot account for.
          skipped++;
          continue;
        }
        final raw = remote?[cloudKey];
        final record = raw == null ? null : _decodeRecord(raw);
        final portableValue = portableValueFor(baseKey, _prefs.get(fullKey), remote: record?.value);
        if (portableValue == null) {
          skipped++;
          continue;
        }
        final entry = SettingsExportService.encodeValue(portableValue);
        if (entry == null) {
          skipped++;
          continue;
        }
        final local = _localStamp(baseKey);
        final encoded = _encodeRecord(entry, local);
        final cap = transport.maxValueBytes;
        if (cap != null && encoded.length > cap) {
          oversize++;
          continue;
        }
        if (record != null) {
          if (family == null) {
            // Last-writer-wins: only a strictly newer local change travels. An
            // equal stamp means the same value; an older one lost already.
            if (_remoteWins(record.stamp, local) || _sameStamp(record.stamp, local)) continue;
          } else if (json.encode(record.value) == json.encode(entry['value'])) {
            continue; // the merged value is already what the store holds
          }
        }
        await transport.write(cloudKey, encoded);
        pushed++;
      }

      // Tombstones this device holds, re-sent where the store still carries an
      // older live record: the previous build writes its values back over them.
      for (final e in _revisions().entries) {
        final meta = e.value;
        if (meta is! Map || meta['x'] != true) continue;
        final localKey = localKeyFor(e.key);
        if (localKey == null) continue;
        final cloudKey = cloudKeyFor(localKey);
        if (cloudKey == null) continue;
        final raw = remote?[cloudKey];
        if (raw == null) continue;
        final record = _decodeRecord(raw);
        if (record == null || record.stamp.deleted) continue;
        final local = _localStamp(e.key);
        if (_remoteWins(record.stamp, local)) continue;
        await transport.write(cloudKey, _encodeTombstone(local));
        pushed++;
      }

      final metaRecord = json.encode({'type': 'int', 'value': _activeFormatVersion});
      if (remote == null || remote[_activeMetaKey] != metaRecord) {
        await transport.write(_activeMetaKey, metaRecord);
      }

      if (!_useV2CloudFormat && remote != null) {
        // The v1 prune, kept for the rolling-upgrade test only. It deletes what
        // is genuinely gone locally and leaves what is present but no longer
        // eligible, so an older client that still syncs the key keeps it.
        final scope = PreferenceSyncScope.forProfile(_activeProfileId());
        for (final k in remote.keys) {
          if (!ownsCloudKey(k)) continue;
          if (known.contains(k)) continue;
          if (scope.id == null && PreferenceSyncPolicyRegistry.isProfileScoped(k)) continue;
          await transport.remove(k);
        }
      }
      await transport.flush();
      _setStatus(
        status.value.reconcileSucceeded(
          DateTime.now(),
          pushedCount: pushed,
          skippedCount: skipped,
          oversizeCount: oversize,
        ),
      );
    } catch (e) {
      _setStatus(status.value.raise(PreferenceSyncHealth.error, errorCategory: _errorCategory(e)));
      appLogger.w('preference sync: reconcile failed (${_errorCategory(e)})');
    }
  }
```

Let op: onder v1 waren `eligible` en `oversize` sets van cloudsleutels die de prune oversloeg. In
de v1-tak hierboven staat die uitsluiting niet meer; `known` dekt de eerste (een eligible sleutel
staat lokaal) en een oversize sleutel staat ook lokaal. `icloud_rolling_upgrade_test` en de
v1-tests in `namespace_ownership_test` bewijzen dat de tak nog doet wat hij deed.

- [ ] **Step 5: Bestaande tests naar het nieuwe contract**

`test/services/preferences/preference_sync_coordinator_test.dart`: in `a local removal reaches the
transport` (regel 50-58) vervang de twee laatste `expect`s door
`expect(json.decode(transport.store[cloudKey]!)['x'], isTrue);`. In `a reset removal travels`
(67-73) vervang de `expect` door `expect(json.decode(transport.store[coordinator.cloudKeyFor('theme_mode')!]!)['x'], isTrue);`.
Hernoem `a key that is genuinely gone locally is still pruned` (236-244) naar `a record this device
never had is adopted on the next pull, not deleted` met body:

```dart
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('theme_mode')!;
      transport.store[cloudKey] = enc('string', 'dark');

      await coordinator.reconcile();

      expect(transport.removes, isEmpty, reason: 'absent locally means not seen yet, since DEC-131');
      expect(transport.store.containsKey(cloudKey), isTrue);
```

`test/services/preferences/merge_strategy_test.dart` (205-213): dezelfde hernoeming en dezelfde
twee `expect`s, met `subtitle_font_size` en `json.encode({'type': 'int', 'value': 44})`.

`test/services/preferences/namespace_ownership_test.dart` (110-126): hernoem `v2: only records inside
the owned namespace are pruned` naar `v2: nothing is pruned, whatever the namespace` en vervang
`expect(transport.removes, ['__pleya_pref_v2/global/theme_mode']);` door `expect(transport.removes, isEmpty);`;
de resterende `expect`s op het voortbestaan van `theme_mode` en `__pleya_pref_v3/...` blijven.

`test/services/preferences/v2_cutover_test.dart` (90-96): `a removal is a v2 removal` wordt
`a removal is a v2 tombstone`; body:

```dart
      final coordinator = await build();
      await coordinator.apply(const PreferenceMutation.remove('theme_mode'));

      final key = '${PreferenceSyncScope.cloudNamespacePrefix}global/theme_mode';
      expect(transport.writes, contains(key));
      expect(json.decode(transport.store[key]!)['x'], isTrue);
      expect(transport.removes, isEmpty);
```

`test/services/preferences/local_first_failure_test.dart` (54-65): `transport.throwOnRemove =` wordt
`transport.throwOnWrite =`; de rest blijft.

`test/services/icloud_sync_service_test.dart` (194-215): hernoem `pushAll removes KVS keys that no
longer exist locally, keeps meta and foreign keys` naar `pushAll leaves keys this device lacks in the
store, and keeps meta and foreign keys`; vervang `expect(kvs.containsKey(g('theme_mode')), isFalse);`
door `expect(kvs.containsKey(g('theme_mode')), isTrue, reason: 'an import is local-first, and nothing is pruned since DEC-131');`.
Pas het commentaar erboven aan.

- [ ] **Step 6: Draai**

Run: `dart format lib/services/preferences/preference_sync_coordinator.dart test/services/preferences/reconcile_and_tombstones_test.dart test/services/preferences/preference_sync_coordinator_test.dart test/services/preferences/merge_strategy_test.dart test/services/preferences/namespace_ownership_test.dart test/services/preferences/v2_cutover_test.dart test/services/preferences/local_first_failure_test.dart test/services/icloud_sync_service_test.dart`
Run: `flutter test test/services/preferences test/services/icloud_sync_service_test.dart test/services/icloud_rolling_upgrade_test.dart test/no_raw_preference_write_test.dart`
Expected: groen. `quota_and_oversize_test` `a reconcile holds it back from the push and from the
prune alike` blijft groen (er is niets meer om van de prune te vrijwaren).
`reconcile_lifecycle_test` `hydrates the new profile and leaves the old profile's records alone`
blijft groen.

- [ ] **Step 7: Commit**

```bash
git add lib/services/preferences/preference_sync_coordinator.dart test/services/preferences/reconcile_and_tombstones_test.dart test/services/preferences/preference_sync_coordinator_test.dart test/services/preferences/merge_strategy_test.dart test/services/preferences/namespace_ownership_test.dart test/services/preferences/v2_cutover_test.dart test/services/preferences/local_first_failure_test.dart test/services/icloud_sync_service_test.dart
git commit -m "fix(sync): reconcile vergelijkt met de store, verwijderingen reizen als tombstone en de prune verdwijnt onder v2 (B2, B4, B5, B13)"
```

---

### Task 5: Accountwissel leest eerst; de initiële download krijgt een reconcile (B9, A2)

Sterker model.

**Files:**
- Modify: `lib/services/preferences/preference_reconcile_scheduler.dart:8-30`
- Modify: `lib/services/preferences/preference_sync_coordinator.dart:429-442, 472-492`
- Modify: `lib/services/icloud_sync_service.dart:205-221`
- Test: `test/services/preferences/reconcile_lifecycle_test.dart:149-174`

**Interfaces:**
- Consumes: `clearRevisions()`, `PreferenceLegacyBootstrap.reset`, `_onRemoteChange`.
- Produces: `ReconcileTrigger.initialSync`; `PreferenceSyncCoordinator.handleRemoteChange(change)`
  (`@visibleForTesting`), waarop `ICloudSyncService.debugHandleEvent` delegeert.

- [ ] **Step 1: Schrijf de falende tests in `reconcile_lifecycle_test.dart`, groep `an iCloud account change`**

Voeg de imports `package:pleya/services/preferences/preference_legacy_bootstrap.dart` toe en, in de
groep, na `a switch to another signed-in account reconciles once`:

```dart
    test('the new account\'s values win, even over a fresher local stamp', () async {
      final coordinator = await build();
      coordinator.listen();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      // Account B's store: an older stamp from another device.
      transport.store.clear();
      transport.store[cloudKey] = json.encode({'type': 'int', 'value': 99, 't': 1000, 'd': 'other-device'});

      transport.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(settings.prefs.getInt('subtitle_font_size'), 99, reason: 'the old account\'s stamps mean nothing here');
      expect(coordinator.localRevision('subtitle_font_size')!.deviceId, 'other-device');
    });

    test('what the new account lacks is pushed with the oldest stamp, so its first real change wins', () async {
      final coordinator = await build();
      coordinator.listen();
      await settings.prefs.setInt('seek_time_small', 5);
      await coordinator.apply(const PreferenceMutation.set('seek_time_small', 5));
      transport.store.clear();

      transport.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final record = json.decode(transport.store[coordinator.cloudKeyFor('seek_time_small')!]!) as Map;
      expect(record['value'], 5);
      expect(record['t'], PreferenceSyncCoordinator.legacyRevisionAt);
      expect(settings.prefs.getInt('seek_time_small'), 5, reason: 'nothing local is wiped');
    });

    test('a switch runs the v1 bootstrap again for the new account', () async {
      final coordinator = await build();
      coordinator.listen();
      await settings.prefs.setBool(PreferenceLegacyBootstrap.completedKey, true);
      transport.store['theme_mode'] = enc('string', 'dark'); // account B still has a v1 device

      transport.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(settings.prefs.getString('theme_mode'), 'dark');
    });

    test('a sign-out clears no stamps', () async {
      final coordinator = await build();
      coordinator.listen();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      transport.available = false;

      transport.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged));
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.localRevision('subtitle_font_size'), isNotNull);
    });
```

Voeg een nieuwe groep toe:

```dart
  group('the initial download', () {
    test('is followed by a reconcile, so a write the system discarded before it is sent again', () async {
      final coordinator = await build();
      coordinator.listen();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      transport.store.remove(cloudKey); // what InitialSyncChange means: that write never landed

      transport.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.initialSync));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(transport.store.containsKey(cloudKey), isTrue);
    });
  });
```

- [ ] **Step 2: Draai en zie rood**

Run: `flutter test test/services/preferences/reconcile_lifecycle_test.dart`
Expected: de eerste drie accountwissel-tests en de initial-download-test rood; `a sign-out clears no stamps` groen.

- [ ] **Step 3: Implementeer**

`lib/services/preferences/preference_reconcile_scheduler.dart`, in de enum na `accountChanged`:

```dart
  /// The store finished its first download. Writes made before that moment
  /// were discarded by the system (`InitialSyncChange`), so they go again.
  initialSync,
```

`lib/services/preferences/preference_sync_coordinator.dart`, `_runReconcile`: voeg `ReconcileTrigger.initialSync`
toe aan de `ambient`-set, en vervang de regels vanaf `final needsBootstrap` tot en met `await reconcile();` door:

```dart
    if (triggers.contains(ReconcileTrigger.accountChanged)) {
      // The stamps describe this device's edits against the previous account's
      // history. Against another account they mean nothing, and keeping them
      // would push the old account's values into the new one as "newer".
      // Local values stay; the store is read first and wins what it holds.
      await clearRevisions();
      await PreferenceLegacyBootstrap.reset(_prefs);
    }
    final needsBootstrap =
        triggers.contains(ReconcileTrigger.boot) ||
        triggers.contains(ReconcileTrigger.enabled) ||
        triggers.contains(ReconcileTrigger.accountChanged);
    final localIsTheSource = triggers.every((t) => t == ReconcileTrigger.imported || t == ReconcileTrigger.reset);

    if (needsBootstrap) await bootstrapFromLegacyV1();
    if (!localIsTheSource) await applyAllRemote();
    await reconcile();
```

In `_onRemoteChange` vervang de laatste `case`:

```dart
      case RemoteChangeReason.serverChange:
        if (change.changedKeys.isNotEmpty) await applyRemoteKeys(change.changedKeys);
      case RemoteChangeReason.initialSync:
        if (change.changedKeys.isNotEmpty) await applyRemoteKeys(change.changedKeys);
        await requestReconcile(ReconcileTrigger.initialSync);
```

Voeg onder `_onRemoteChange` toe:

```dart
  /// Drive the remote-event path without a stream. Test-only.
  @visibleForTesting
  Future<void> handleRemoteChange(RemotePreferenceChange change) => _onRemoteChange(change);
```

`lib/services/icloud_sync_service.dart`, vervang `debugHandleEvent` (regel 205-221) door:

```dart
  /// Drive the remote-event path directly (fakes an EventChannel emission).
  @visibleForTesting
  Future<void> debugHandleEvent(Map<String, dynamic> event) async {
    final change = ICloudKvsTransport.translateEvent(event);
    if (change != null) await _coordinator.handleRemoteChange(change);
  }
```

- [ ] **Step 4: Draai**

Run: `dart format lib/services/preferences/preference_reconcile_scheduler.dart lib/services/preferences/preference_sync_coordinator.dart lib/services/icloud_sync_service.dart test/services/preferences/reconcile_lifecycle_test.dart`
Run: `flutter test test/services/preferences test/services/icloud_sync_service_test.dart`
Expected: groen. `reconcile_scheduler_test` kent de enum door `values`-iteratie mogelijk niet; is
daar een `switch` zonder default, dan voegt de analyzer een fout toe: behandel `initialSync` daar
als ambient.

- [ ] **Step 5: Commit**

```bash
git add lib/services/preferences/preference_reconcile_scheduler.dart lib/services/preferences/preference_sync_coordinator.dart lib/services/icloud_sync_service.dart test/services/preferences/reconcile_lifecycle_test.dart
git commit -m "fix(sync): accountwissel leest eerst en duwt niet terug, en de eerste download krijgt een reconcile (B9, A2)"
```

---

### Task 6: Taalvoorkeur als profiel-gesleutelde map, acht sleutels geregistreerd, scopetabel (B10, B11)

Sterker model voor de merge-familie; de registraties zijn mechanisch.

**Files:**
- Modify: `lib/services/preferences/preference_sync_scope.dart:98-101`
- Modify: `lib/services/preferences/preference_merge_strategies.dart:30-48, 66-95`
- Modify: `lib/services/preferences/preference_sync_policy.dart:188-260, 300-433, 495-500`
- Modify: `lib/services/preferences/preference_sync_coordinator.dart:188-194`
- Modify: `lib/services/track_preference_store.dart:17-19`
- Modify: `test/services/preferences/preference_sync_policy_test.dart:175`
- Create: `test/services/preferences/profile_keyed_map_test.dart`

**Interfaces:**
- Consumes: `PreferenceMergeFamily`, `PreferenceMergeRegistry.register`, `PreferenceValuePortability` (niet nodig), `decodeStringList` als voorbeeld.
- Produces: `PreferenceMergeFamilies.profileKeyedMap`, `buildProfileKeyedMapFamily()`,
  `profileScopeOfMapKey(String)`, `decodeStringMap(Object?)`, `PreferenceSyncScope.isPortableProfileScope(String)`,
  `PreferenceSyncPolicyRegistry._profileKeyedMapPref`, `_deviceBoundPref`.

- [ ] **Step 1: Schrijf `test/services/preferences/profile_keyed_map_test.dart`**

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_merge_strategies.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// DEC-131 (9). The two language maps are global preferences whose map keys
/// carry the profile scope. A Plex Home uuid means the same profile everywhere;
/// `local-<uuid>` and the empty scope belong to one device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const home = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  const otherHome = '11111111-2222-3333-4444-555555555555';
  const local = 'local-9a8b7c6d-1111-2222-3333-444455556666';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: home);
  final family = buildProfileKeyedMapFamily();

  Map<String, dynamic> m(Object? raw) => Map<String, dynamic>.from(json.decode(raw as String) as Map);

  group('scope portability', () {
    test('a Plex Home uuid travels, local and empty scopes stay', () {
      expect(PreferenceSyncScope.isPortableProfileScope(home), isTrue);
      expect(PreferenceSyncScope.isPortableProfileScope(local), isFalse);
      expect(PreferenceSyncScope.isPortableProfileScope(''), isFalse);
    });

    test('the scope is the part before the first pipe', () {
      expect(profileScopeOfMapKey('$home|series:42'), home);
      expect(profileScopeOfMapKey(home), home);
      expect(profileScopeOfMapKey('|x'), '');
    });
  });

  group('inbound', () {
    test('keeps local-only entries and adopts the portable ones', () {
      final mine = json.encode({'$local|s1': {'a': 'nl'}, '$home|s1': {'a': 'nl'}});
      final theirs = json.encode({'$home|s1': {'a': 'en'}, '$home|s2': {'a': 'de'}});

      final merged = m(family.inbound(mine, theirs));

      expect(merged['$local|s1'], {'a': 'nl'});
      expect(merged['$home|s1'], {'a': 'en'});
      expect(merged['$home|s2'], {'a': 'de'});
    });

    test('a series entry the sender removed for a shared scope is removed here too', () {
      final mine = json.encode({'$home|s1': {'a': 'nl'}, '$home|s2': {'a': 'de'}});
      final theirs = json.encode({'$home|s1': {'a': 'nl'}});

      final merged = m(family.inbound(mine, theirs));

      expect(merged.containsKey('$home|s2'), isFalse);
    });

    test('a scope the sender does not know is kept whole', () {
      final mine = json.encode({'$otherHome|s1': {'a': 'nl'}});
      final theirs = json.encode({'$home|s1': {'a': 'en'}});

      final merged = m(family.inbound(mine, theirs));

      expect(merged['$otherHome|s1'], {'a': 'nl'});
      expect(merged['$home|s1'], {'a': 'en'});
    });

    test('a local entry with a newer updatedAt survives an older remote one', () {
      final mine = json.encode({home: {'audio': 'nl', 'updatedAt': 200}});
      final theirs = json.encode({home: {'audio': 'en', 'updatedAt': 100}});

      final merged = m(family.inbound(mine, theirs));

      expect(merged[home], {'audio': 'nl', 'updatedAt': 200});
    });

    test('an undecodable remote value leaves the local one alone', () {
      expect(family.inbound('{"a":1}', 'not json'), '{"a":1}');
    });
  });

  group('outbound', () {
    test('drops local-only entries and keeps store entries for scopes this device lacks', () {
      final mine = json.encode({'$local|s1': {'a': 'nl'}, '$home|s1': {'a': 'nl'}});
      final theirs = json.encode({'$otherHome|s1': {'a': 'fr'}, '$home|s9': {'a': 'it'}});

      final out = m(family.outbound!(mine, theirs));

      expect(out.containsKey('$local|s1'), isFalse);
      expect(out['$home|s1'], {'a': 'nl'});
      expect(out['$otherHome|s1'], {'a': 'fr'}, reason: 'not mine to drop');
      expect(out.containsKey('$home|s9'), isFalse, reason: 'my scope, and I no longer have it');
    });

    test('sends nothing when nothing portable is held', () {
      final mine = json.encode({'$local|s1': {'a': 'nl'}});

      expect(family.outbound!(mine, null), isNull);
    });

    test('a newer remote entry for a shared key is carried rather than overwritten', () {
      final mine = json.encode({home: {'audio': 'nl', 'updatedAt': 100}});
      final theirs = json.encode({home: {'audio': 'en', 'updatedAt': 200}});

      final out = m(family.outbound!(mine, theirs));

      expect(out[home], {'audio': 'en', 'updatedAt': 200});
    });
  });

  group('the two language preferences', () {
    late SettingsService settings;
    late FakeTransport transport;

    Future<PreferenceSyncCoordinator> build() async {
      settings = await SettingsService.getInstance();
      transport = FakeTransport();
      return PreferenceSyncCoordinator(
        prefs: settings.prefs,
        activeProfileId: () => profile,
        enabled: () => true,
        deviceId: 'macbook',
        transport: transport,
      );
    }

    setUp(() {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
    });

    tearDown(() => BaseSharedPreferencesService.onMutation = null);

    test('are global maps with the profile-keyed merge', () {
      for (final key in ['pleya_profile_language_preferences', 'track_language_preferences']) {
        final policy = PreferenceSyncPolicyRegistry.policyFor(key);
        expect(policy.scope, PreferenceScopeKind.global, reason: key);
        expect(policy.maySync, isTrue, reason: key);
        expect(policy.mergeFamily, PreferenceMergeFamilies.profileKeyedMap, reason: key);
        expect(PreferenceSyncPolicyRegistry.isProfileScoped(key), isFalse, reason: key);
      }
    });

    test('an incoming profile preference lands on the key the store reads', () async {
      final coordinator = await build();
      const key = 'pleya_profile_language_preferences';
      transport.store[coordinator.cloudKeyFor(key)!] = json.encode({
        'type': 'string',
        'value': json.encode({home: {'audioLanguage': 'nl', 'updatedAt': 5}}),
        't': 5,
        'd': 'appletv',
      });

      await coordinator.applyAllRemote();

      expect(settings.prefs.getString(key), contains('"nl"'));
      expect(settings.prefs.getString('user_${home}_$key'), isNull, reason: 'the dead key of B10');
    });

    test('an outgoing map leaves the local profile\'s entry at home', () async {
      final coordinator = await build();
      const key = 'track_language_preferences';
      final value = json.encode({'$local|s1': {'a': 'nl'}, '$home|s1': {'a': 'en'}});
      await settings.prefs.setString(key, value);

      await coordinator.apply(PreferenceMutation.set(key, value));

      final record = json.decode(transport.store[coordinator.cloudKeyFor(key)!]!) as Map;
      final sent = m(record['value']);
      expect(sent.containsKey('$local|s1'), isFalse);
      expect(sent['$home|s1'], {'a': 'en'});
    });
  });
}
```

- [ ] **Step 2: Voeg de policy-tests toe in `preference_sync_policy_test.dart`**

Vervang op regel 175 de eerste regex door `RegExp(r"Pref(?:<[^()]*>)?\(\s*'([a-z0-9_.]+)'"),` en
voeg onder de guard-test toe:

```dart
  test('the eight JsonPref maps that hid from the guard are registered', () {
    for (final key in [
      'keyboard_shortcuts',
      'keyboard_hotkeys',
      'media_version_preferences',
      'track_language_preferences',
      'unified_source_preferences',
      'tv_live_tv_capability',
      'preferred_unified_server',
      'custom_shader_presets',
    ]) {
      expect(PreferenceSyncPolicyRegistry.isRegistered(key), isTrue, reason: key);
    }
    expect(PreferenceSyncPolicyRegistry.maySync('keyboard_shortcuts'), isTrue);
    expect(PreferenceSyncPolicyRegistry.maySync('keyboard_hotkeys'), isTrue);
    expect(PreferenceSyncPolicyRegistry.maySync('tv_live_tv_capability'), isFalse);
    expect(PreferenceSyncPolicyRegistry.isExportable('tv_live_tv_capability'), isFalse);
    for (final key in ['media_version_preferences', 'unified_source_preferences', 'preferred_unified_server', 'custom_shader_presets']) {
      expect(PreferenceSyncPolicyRegistry.maySync(key), isFalse, reason: key);
      expect(PreferenceSyncPolicyRegistry.isExportable(key), isFalse, reason: key);
    }
  });

  test('device-bound playback configuration stops syncing but stays exportable', () {
    for (final key in [
      'default_quality_preset',
      'buffer_size',
      'mpv_config_text',
      'mpv_config_presets',
      'global_shader_preset',
      'enable_discord_rpc',
      'video_player_navigation_enabled',
      'auto_check_updates_on_startup',
    ]) {
      expect(PreferenceSyncPolicyRegistry.maySync(key), isFalse, reason: key);
      expect(PreferenceSyncPolicyRegistry.isExportable(key), isTrue, reason: key);
    }
    expect(PreferenceSyncPolicyRegistry.maySync('live_tv_default_favorites'), isTrue);
  });
```

- [ ] **Step 3: Draai en zie rood**

Run: `flutter test test/services/preferences/profile_keyed_map_test.dart test/services/preferences/preference_sync_policy_test.dart`
Expected: compilefouten op de nieuwe namen; na een lege stub rood op de guard (acht onbekende
sleutels), op de scope van de taalvoorkeur en op de scopetabel.

- [ ] **Step 4: Implementeer de scope-hulp**

In `lib/services/preferences/preference_sync_scope.dart`, direct onder `ownsCloudKey` (regel 101):

```dart
  /// Whether a `{profileScope}` inside a map key names the same profile on
  /// another device.
  ///
  /// `StorageService.activeUserScope()` is the Plex Home uuid for a Plex Home
  /// profile and the full profile id otherwise, and every other profile kind
  /// is minted as `local-<uuid>` on the device that created it
  /// (`add_jellyfin_screen.dart`, `add_pleya_server_screen.dart`,
  /// `add_local_profile_screen.dart`). Empty is signed out. So "looks like a
  /// uuid" is the whole test, and it fails closed.
  static bool isPortableProfileScope(String scope) => _uuid.hasMatch(scope);

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
```

- [ ] **Step 5: Implementeer de familie**

In `lib/services/preferences/preference_merge_strategies.dart`, in `PreferenceMergeFamilies` na `watchedMap`:

```dart
  /// A JSON map whose keys are `{profileScope}` or `{profileScope}|{rest}`:
  /// the two language preferences (DEC-096, DEC-131).
  static const String profileKeyedMap = 'profileKeyedMap';
```

Voeg toe (import `preference_sync_scope.dart` bovenaan), na `buildServerScopedListFamily`:

```dart
/// Maps keyed by profile scope, where a device speaks for the profiles it has.
///
/// Inbound keeps this device's non-portable entries and the entries of scopes
/// the sender does not know; for a scope both know, the sender's set replaces
/// this device's, so a removed series override travels. Outbound sends the
/// portable entries and carries the store's entries for scopes this device
/// lacks. An entry present on both sides is settled by `updatedAt` when both
/// carry one, otherwise the side doing the merge keeps its own.
///
/// Known limit (DEC-131): a device that removes the last entry of a scope no
/// longer "knows" that scope, so that final removal does not travel.
PreferenceMergeFamily buildProfileKeyedMapFamily() => PreferenceMergeFamily(
  name: PreferenceMergeFamilies.profileKeyedMap,
  inbound: (local, remote) {
    final theirs = decodeStringMap(remote);
    if (theirs == null) return local;
    final mine = decodeStringMap(local) ?? const <String, dynamic>{};
    final theirScopes = theirs.keys.map(profileScopeOfMapKey).toSet();
    final merged = <String, dynamic>{
      for (final e in mine.entries)
        if (!PreferenceSyncScope.isPortableProfileScope(profileScopeOfMapKey(e.key)) ||
            !theirScopes.contains(profileScopeOfMapKey(e.key)))
          e.key: e.value,
      for (final e in theirs.entries)
        if (PreferenceSyncScope.isPortableProfileScope(profileScopeOfMapKey(e.key)))
          e.key: _newerEntry(e.value, mine[e.key]),
    };
    return json.encode(merged);
  },
  outbound: (local, remote) {
    final mine = decodeStringMap(local);
    if (mine == null) return local;
    final myScopes = mine.keys.map(profileScopeOfMapKey).toSet();
    final theirs = decodeStringMap(remote) ?? const <String, dynamic>{};
    final out = <String, dynamic>{
      for (final e in mine.entries)
        if (PreferenceSyncScope.isPortableProfileScope(profileScopeOfMapKey(e.key)))
          e.key: _newerEntry(e.value, theirs[e.key]),
      for (final e in theirs.entries)
        if (PreferenceSyncScope.isPortableProfileScope(profileScopeOfMapKey(e.key)) &&
            !myScopes.contains(profileScopeOfMapKey(e.key)))
          e.key: e.value,
    };
    if (out.isEmpty) return null;
    return json.encode(out);
  },
);

/// The `{profileScope}` half of a map key: everything before the first `|`,
/// or the whole key when there is none.
String profileScopeOfMapKey(String key) {
  final pipe = key.indexOf('|');
  return pipe < 0 ? key : key.substring(0, pipe);
}

/// Prefer [preferred] unless both are maps with an int `updatedAt` and
/// [other]'s is higher.
Object? _newerEntry(Object? preferred, Object? other) {
  if (preferred is Map && other is Map) {
    final a = preferred['updatedAt'];
    final b = other['updatedAt'];
    if (a is int && b is int && b > a) return other;
  }
  return preferred;
}

/// Decode a JSON object, or null when the value is not one.
Map<String, dynamic>? decodeStringMap(Object? raw) {
  if (raw is! String) return null;
  try {
    final decoded = json.decode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}
```

In `preference_sync_coordinator.dart` `_registerBuiltInMergeFamilies` (regel 188-194) voeg toe:
`_merges.register(buildProfileKeyedMapFamily());`.

- [ ] **Step 6: Implementeer de policy**

In `lib/services/preferences/preference_sync_policy.dart`: vervang `_profileLanguagePref` (de const
plus zijn doc, regel 236-251) door:

```dart
  /// The two language maps (DEC-096, DEC-131 (9)): one global preference each,
  /// with the profile scope inside the map keys, exactly as
  /// `PleyaProfileLanguagePreferenceStore` and `TrackPreferenceStore` write
  /// them. Registering them as profile-scoped put the incoming value under a
  /// `user_<uuid>_` key nothing reads. The family decides per profile which
  /// entries travel and which stay.
  static const PreferencePolicy _profileKeyedMapPref = PreferencePolicy(
    scope: PreferenceScopeKind.global,
    merge: PreferenceMergeStrategy.custom,
    mergeFamily: PreferenceMergeFamilies.profileKeyedMap,
  );

  /// Bound to this device's hardware or installation, so it does not sync,
  /// but a file export is a deliberate act towards a device the user chose,
  /// so it still exports (DEC-131 (10)).
  static const PreferencePolicy _deviceBoundPref = PreferencePolicy(
    scope: PreferenceScopeKind.deviceLocal,
    icloudSyncable: false,
  );
```

In `_exact`: zet deze acht van `_globalPref` op `_deviceBoundPref`, elk met een korte reden in
commentaar: `'global_shader_preset'` (GPU), `'default_quality_preset'` (netwerk van het toestel),
`'buffer_size'` (geheugen), `'mpv_config_text'` en `'mpv_config_presets'` (kunnen `hwdec` en paden
bevatten), `'video_player_navigation_enabled'` en `'enable_discord_rpc'` (desktopgedrag),
`'auto_check_updates_on_startup'` (App Store versus sideload, per installatie).
`'default_playback_speed'` blijft `_globalPref`. Zet `'live_tv_default_favorites'` van
`_deviceLocalPref` op `_globalPref`. Vervang `'pleya_profile_language_preferences': _profileLanguagePref,`
door:

```dart
    // -- The two language maps (DEC-096, DEC-131).
    'pleya_profile_language_preferences': _profileKeyedMapPref,
    'track_language_preferences': _profileKeyedMapPref,

    // -- JsonPref maps the guard could not see until DEC-131 (10).
    'keyboard_shortcuts': _globalPref,
    'keyboard_hotkeys': _globalPref,
    // The chosen version index depends on what the server offers this device.
    'media_version_preferences': _deviceLocalPref,
    // Both name a server id; a portable-server filter is a follow-up, not a fix.
    'unified_source_preferences': _deviceLocalPref,
    'preferred_unified_server': _deviceLocalPref,
    // GPU-bound, like global_shader_preset.
    'custom_shader_presets': _deviceLocalPref,
    'tv_live_tv_capability': _runtimeCache,
```

In `lib/services/track_preference_store.dart` regel 17-19 vervang door:

```dart
/// Sits on [SettingsService.trackLanguagePreferences], a global map registered
/// with the `profileKeyedMap` merge family (DEC-131): the Plex Home profile's
/// entries reach the user's other Apple devices, a local profile's stay here.
```

- [ ] **Step 7: Draai**

Run: `dart format lib/services/preferences/preference_sync_scope.dart lib/services/preferences/preference_merge_strategies.dart lib/services/preferences/preference_sync_policy.dart lib/services/preferences/preference_sync_coordinator.dart lib/services/track_preference_store.dart test/services/preferences/profile_keyed_map_test.dart test/services/preferences/preference_sync_policy_test.dart`
Run: `flutter test test/services/preferences test/services/settings_export_service_test.dart test/services/lang1_controls_page_test.dart test/services/track_manager_test.dart`
Expected: groen. Wordt een exporttest rood op `mpv_config_presets`, dan is `_deviceBoundPref` per
ongeluk `_deviceLocalPref` geworden.

- [ ] **Step 8: Commit**

```bash
git add lib/services/preferences/preference_sync_scope.dart lib/services/preferences/preference_merge_strategies.dart lib/services/preferences/preference_sync_policy.dart lib/services/preferences/preference_sync_coordinator.dart lib/services/track_preference_store.dart test/services/preferences/profile_keyed_map_test.dart test/services/preferences/preference_sync_policy_test.dart
git commit -m "fix(sync): taalvoorkeuren reizen als profiel-gesleutelde map, acht stille sleutels geregistreerd en de scopetabel bijgewerkt (B10, B11)"
```

---

### Task 7: KVS-notificaties via de platformthread (A1)

Goedkoop model. Geen unittest mogelijk; het bewijs is de Flutter-regel, de native format-check en
een diff die de drie bestanden gelijk houdt.

**Files:**
- Modify: `ios/Runner/ICloudKvsPlugin.swift:88-101`
- Modify: `tvos/Runner/ICloudKvsPlugin.swift:88-101`
- Modify: `macos/Runner/ICloudKvsPlugin.swift:88-101`

- [ ] **Step 1: Leg de huidige gelijkheid vast**

Run: `diff ios/Runner/ICloudKvsPlugin.swift tvos/Runner/ICloudKvsPlugin.swift; diff ios/Runner/ICloudKvsPlugin.swift macos/Runner/ICloudKvsPlugin.swift`
Expected: alleen de twee `messenger`-regels verschillen in macOS; ios en tvos zijn gelijk.

- [ ] **Step 2: Vervang in alle drie de bestanden de twee handlers (regel 88-101)**

```swift
  /// The iCloud account itself changed. Reported under the store's own
  /// account-change reason, so the Dart side needs no second vocabulary for it.
  @objc private func ubiquityIdentityDidChange(_ notification: Notification) {
    emit(["reason": NSUbiquitousKeyValueStoreAccountChange, "changedKeys": [String]()])
  }

  @objc private func storeDidChangeExternally(_ notification: Notification) {
    let info = notification.userInfo ?? [:]
    let reason = (info[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int) ?? -1
    let changedKeys = (info[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
    emit(["reason": reason, "changedKeys": changedKeys])
  }

  /// Channel traffic has to happen on the platform thread; NotificationCenter
  /// delivers on the posting thread, and Apple documents none for these two
  /// notifications. The sink is read inside the hop so a cancel that raced the
  /// notification is honoured.
  private func emit(_ payload: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      guard let sink = self?.eventSink else { return }
      sink(payload)
    }
  }
```

- [ ] **Step 3: Controleer**

Run: `scripts/format_native.sh --check`
Expected: groen. Zo niet, `scripts/format_native.sh` (zonder `--check`) en opnieuw.
Run: `diff ios/Runner/ICloudKvsPlugin.swift tvos/Runner/ICloudKvsPlugin.swift; diff ios/Runner/ICloudKvsPlugin.swift macos/Runner/ICloudKvsPlugin.swift`
Expected: dezelfde twee `messenger`-regels als in stap 1, verder niets.

- [ ] **Step 4: Commit**

```bash
git add ios/Runner/ICloudKvsPlugin.swift tvos/Runner/ICloudKvsPlugin.swift macos/Runner/ICloudKvsPlugin.swift
git commit -m "fix(sync): KVS-notificaties bereiken Dart via de platformthread (A1)"
```

---

### Task 8: Volledige suite, sleutelaantal gemeten, matrix en register bijgewerkt

Goedkoop model.

**Files:**
- Modify: `test/services/preferences/kvs_footprint_test.dart` (nieuwe test)
- Modify: `docs/qa/preference-sync-and-playback-matrix.md`
- Modify: `docs/qa/icloud-kvs-native-audit.md:98-110`
- Modify: `docs/icloud-sync-repair-register.md`
- Modify: `docs/CHANGELOG.md` (één blok bovenaan)

- [ ] **Step 1: Meet het sleutelaantal (A3)**

Voeg toe aan `kvs_footprint_test.dart`:

```dart
  test('the key count on a heavy account with four profiles stays under the 1024-key limit', () {
    const profiles = 4;
    const kvsMaxKeys = 1024;
    final perProfile = 2 + libraryKeys().length * 3; // hidden, order, plus sort/grouping/tab per library
    final total = globalPrefs + 1 + profiles * perProfile; // +1 for the meta record
    // ignore: avoid_print
    print('KVS key count: $total of $kvsMaxKeys (tombstones reuse a key\'s slot, so they add none)');
    expect(total, lessThan(kvsMaxKeys));
  });
```

Run: `flutter test test/services/preferences/kvs_footprint_test.dart`
Expected: groen, met `KVS key count: 655 of 1024` in de uitvoer.

- [ ] **Step 2: De gate en de volledige suite**

Run: `scripts/ci_checks.sh`
Expected: groen. Rood op `dart format`: formatteer alleen de genoemde bestanden. Rood op de
analyzer: los op, geen `// ignore`.
Run: `flutter test`
Expected: groen. Bewaar de laatste regel (`All tests passed!` met het aantal) voor het register.

- [ ] **Step 3: Matrix**

In `docs/qa/preference-sync-and-playback-matrix.md`: zet bovenaan `Bijgewerkt: 2026-09-24, na
DEC-131 (herstelronde iCloud-sync). Alle rijen blijven open tot de hardwareronde.` Wijzig bij S6 de
kolom Verwacht in `De verwijdering bereikt het andere toestel als tombstone; een volgende foreground
zet hem niet terug`. Voeg na blok 4 toe:

```markdown
## Blok 5: herstelronde DEC-131 (hardware)

Recept in `docs/superpowers/specs/2026-09-24-icloud-sync-repair-design.md` §7. Twee toestellen,
één iCloud-account, dezelfde TestFlight-build, schakelaar aan op beide.

| # | Scenario | Verwacht | Status |
|---|---|---|---|
| H1 | Ondertitelgrootte op de Mac, Apple TV open in Instellingen | Volgt binnen een minuut zonder herstart (S1, S9) | open |
| H2 | Instelling terugzetten en daarna resetten op de Mac | Apple TV volgt; de Mac krijgt na een eigen foreground niets terug; log toont één tombstone-write per sleutel (S6, R8) | open |
| H3 | Dezelfde instelling binnen vijf seconden op beide anders | Beide op de laatst gezette waarde; een derde foreground wisselt niets (S8) | open |
| H4 | Uitloggen bij iCloud met de app open, wijziging, weer inloggen | Ondertitel "Sign in to iCloud", geen "Last sent"; na inloggen komt de volgende wijziging aan zonder herstart (R5, R6) | open |
| H5 | Schakelaar uit, wijziging, schakelaar aan, wijziging | Beide wijzigingen komen aan (B6) | open |
| H6 | Wisselen naar een tweede testaccount en terug | Waarden van dat account verschijnen; wat het miste staat met stempel 0 in zijn store; lokaal niets gewist (S10, B9) | open |
| H7 | KVS-quota vol | Niet praktisch uitvoerbaar; blijft open met die reden (L4) | open |
```

Voeg in "Wat de geautomatiseerde tests wél bewijzen" een regel toe: `de envelop op de draad, de
tombstones, de accountwissel en de profiel-gesleutelde map zijn getest tegen FakeTransport
(revision_on_the_wire_test, reconcile_and_tombstones_test, reconcile_lifecycle_test,
profile_keyed_map_test); de productiebedrading van de listener tegen dezelfde fake via
ICloudSyncService.start(transport:). Geen simulator heeft een iCloud-account.`

- [ ] **Step 4: Native audit**

In `docs/qa/icloud-kvs-native-audit.md` vervang de alinea die begint met "That looks like a hole and
is not one. Every path that subscribes also reconciles: `listen()` runs inside the boot and enable
triggers" door:

```markdown
That looks like a hole and is not one, provided the subscription exists. Until DEC-131 it did not:
`listen()` was defined and never called outside tests, so every notification was dropped and the
engine was poll-on-foreground. Since DEC-131 `ICloudSyncService._wire` subscribes unconditionally
at start, and `enable()` re-arms it. Every path that subscribes also reconciles, so a change missed
during startup is read from the store moments later by a pass that does not depend on having seen
the event. Adding a buffer would add a queue, a flush and an ordering question, to re-deliver
information the next read already carries.
```

Voeg onder "Also deliberately not changed" een korte sectie toe dat de sink sinds DEC-131 via
`DispatchQueue.main.async` loopt, met de reden uit taak 7.

- [ ] **Step 5: Register en changelog**

In `docs/icloud-sync-repair-register.md` zet elke rij behalve B12 en A4 op
`CODE CLOSED · UNIT VERIFIED · HARDWARE OPEN` met de SHA van de taak die hem sloot (`git log
--oneline -8`) en het testbestand: B1/B6/B7/B8 taak 2 (`icloud_sync_service_test`,
`sync_status_model_test`); B3 taak 3 (`revision_on_the_wire_test`); B2/B4/B5/B13 taak 4
(`reconcile_and_tombstones_test`); B9/A2 taak 5 (`reconcile_lifecycle_test`); B10/B11 taak 6
(`profile_keyed_map_test`, `preference_sync_policy_test`); A1 taak 7 (`CODE CLOSED · HARDWARE
OPEN`, bewijs `format_native.sh --check` en de diff); A3 taak 8 (`kvs_footprint_test`, 655 van 1024,
status `UNIT VERIFIED`). Noteer onder "Hardwareronde" het aantal tests uit stap 2.

In `docs/CHANGELOG.md` voeg bovenaan onder de inleiding toe:

```markdown
## [2026-09-24] iCloud-voorkeurensync: herstelronde DEC-131

Acht taken in `fix/icloud-sync`. De KVS-listener is in productie aangesloten, de revisie-envelop
reist mee en beslist bij het toepassen, verwijderingen reizen als tombstone en de prune verdwijnt
onder v2, de status meldt geen verzending bij een uitgelogd iCloud en laat een quota-melding staan,
een accountwissel leest eerst, de taalvoorkeuren van het Pleya-profiel reizen als
profiel-gesleutelde map, acht `JsonPref`-sleutels zijn geregistreerd en acht toestelgebonden
instellingen synchroniseren niet meer. Bewijs: unit tegen `FakeTransport`; hardware open, recept in
de spec. Zie DEC-131 en `docs/icloud-sync-repair-register.md`.
```

- [ ] **Step 6: Controleer de documenten en commit**

Run: `rg -n "DEC-131" docs/qa/preference-sync-and-playback-matrix.md docs/qa/icloud-kvs-native-audit.md docs/icloud-sync-repair-register.md docs/CHANGELOG.md`
Expected: elk bestand minstens één treffer. Meldt de anti-slop-hook treffers, herstel ze.

```bash
git add test/services/preferences/kvs_footprint_test.dart docs/qa/preference-sync-and-playback-matrix.md docs/qa/icloud-kvs-native-audit.md docs/icloud-sync-repair-register.md docs/CHANGELOG.md
git commit -m "docs(sync): matrix, native audit, register en changelog na de herstelronde DEC-131"
```

---

## Zelfcontrole

Spec-dekking: B1/B6/B7/B8 taak 2; B3 taak 3; B2/B4/B5/B13 taak 4; B9/A2 taak 5; B10/B11 en de
scopetabel taak 6; A1 taak 7; A3 en de documentatie taak 8; B12 en A4 als `DEFERRED` in taak 1.
Namen: `_Stamp`, `_localStamp`, `_adoptStamp`, `_remoteWins`, `_sameStamp`, `_encodeRecord`,
`_encodeTombstone`, `_decodeRecord`, `clearRevisions`, `stampWins`, `handleRemoteChange`,
`ReconcileTrigger.initialSync`, `profileKeyedMap`, `buildProfileKeyedMapFamily`,
`profileScopeOfMapKey`, `decodeStringMap`, `isPortableProfileScope`, `_profileKeyedMapPref`,
`_deviceBoundPref`, `_wire`, `start(transport:)` zijn in elke taak gelijk gespeld. De vijf punten
uit Review Focus hebben een test in taak 3 (1 en 4), 4 (2), 6 (3) en 5 (5).
