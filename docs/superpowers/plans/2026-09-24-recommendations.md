# Aanbevelingen en Tautulli-defecten: implementatieplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** De Home-rijen uit kijkgeschiedenis worden persoonlijk en uitlegbaar (seeds uit het eigen log, een lokaal partieel signaal, Jellyfin-import, een acteurs- of regisseursrij) en de drie bevestigde Tautulli-defecten gaan dicht.

**Architecture:** Alles blijft binnen de bestaande drie lagen: `MediaInteractions` als append-only log, `AffinityEngine` plus `buildPersonalizedRows` als pure scorer, en `DiscoverProvider` als de ene plek waar Home-rijen ontstaan. Nieuwe signalen zijn nieuwe rijen in dezelfde tabel; nieuwe rijen zijn `MediaHub`s door dezelfde renderers. De Tautulli-fix is een binding-check op de plek waar de client wordt uitgedeeld.

**Tech Stack:** Flutter 3.44.0 (pin in `.fvmrc`), drift, slang, `provider`, `flutter_test`, Pleya Verify (`pleya_verify/runner`).

**Spec:** `docs/superpowers/specs/2026-09-24-recommendations-design.md`

Auteur: Michel Knoop. Datum: 24 september 2026. Worktree `feat/recommendations` op `3ad702d3`.

## Global Constraints

- Nederlands in documenten, commit-onderwerpen en rijtitels (nl); Engels als basislocale in `en.i18n.json`. Geen em-dashes, geen vendor- of modelnamen, geen AI-attributie in commits.
- Nieuwe i18n-sleutels alleen in `lib/i18n/nl.i18n.json` en `lib/i18n/en.i18n.json`; daarna `dart run slang`. `slang.yaml` valt voor andere locales terug op Engels.
- Geen ML, geen server-side engine, geen `get_home_stats`, geen negatief signaal uit een afgebroken Tautulli-play, geen nieuw instellingenscherm, geen nieuwe rijwidget, geen wijziging aan de Home-compositie (hero, Verder kijken, Recent toegevoegde series, seeds, gepersonaliseerd, backend-hubs).
- Elke rij leest uitsluitend `MediaInteractions` van het actieve `profileId`. Geen rijtitel noemt een huisgenoot. Geen rij toont een titel die `isWatched` is.
- Drempels zijn de bestaande constanten: `kPartialPercent = 50`, `kCompletedPercent = 85`, `kCrossSourceWindow = 6h`, `kWarmDistinctTitles = 8`, partieel gewicht 0,4, `minRowItems = 4`. Nieuw: `kSeedWindow = 30 dagen`, `kSeedMinWeight = 0.4`, `kMaxAffinityRows = 2`, persoonsdrempel 0,7.
- Voor elke taak: eerst de falende test, dan de minimale implementatie, dan `scripts/ci_checks.sh` vóór de commit. Codegen (`scripts/codegen.sh`) alleen na wijzigingen in drift-tabellen of i18n-bronnen.
- Regelnummers in dit plan gelden voor `3ad702d3`; een uitvoerder controleert ze met `rg` voordat hij een `Modify`-regel toepast.
- Modelkeuze per taak staat in de kop: `mechanisch` (goedkoop model volstaat) of `oordeel` (sterkste model; scoringssemantiek of iets wat de gebruiker op Home ziet).

## Review Focus

1. Een profiel met alleen Pleya Server of een lokale map: Home mag geen rij verliezen en `_loadBecauseYouWatched` mag geen `fetchItem` op die client doen. Test in Taak 3 ("een seed op een client zonder related hubs neemt geen plek in").
2. Een Tautulli-`completed` een uur na een lokale stop op 60 procent van dezelfde film: het volle gewicht moet landen, niet worden weggeslikt. Test in Taak 4 ("een lokale partial slikt een Tautulli-completed niet weg").
3. Twee Plex-servers, Tautulli op één: de detailpagina op de andere server toont géén kijkers van de eerste en valt terug op Plex-geschiedenis. Test in Taak 2 (`clientForServer` geeft `null` voor de andere server).
4. Een serie waarvan de laatste aflevering net is uitgekeken (`watched`-event met `isNowWatched: true` én een eindstop): één `completed`, geen extra `partial`. Test in Taak 4 ("een eindstop met isNowWatched schrijft geen partial").
5. Een Jellyfin-gebruiker die elke dag dezelfde hervatbare film een stukje verder kijkt: één `partial`-rij, geen stapel. Test in Taak 6 ("een hervatbaar item levert één rij, ook na drie syncs").

---

### Task 1: Governance: DEC-132, register en DEC-062-addendum

`mechanisch`

**Files:**
- Modify: `docs/DECISIONS.md` (na DEC-130, einde bestand; addendum onder DEC-062 na regel 553)
- Create: `docs/recommendations-register.md`

**Interfaces:**
- Consumes: de spec.
- Produces: registerrijen `REC-1` tot en met `REC-9` waar elke volgende taak zijn SHA in zet.

- [ ] **Step 1: Controleer dat het nummer vrij is**

Run: `rg -n "DEC-131|DEC-132" docs lib test pleya_verify`
Expected: geen treffers.

- [ ] **Step 2: Schrijf DEC-132 onderaan `docs/DECISIONS.md`**

```markdown
## DEC-132: Home-aanbevelingen seeden uit het eigen interactielog; Tautulli blijft één adapter naast een lokaal partieel signaal en een Jellyfin-import

**Date:** 2026-09-24
**Status:** accepted

**Context:** De audit van 24 september 2026 op de Tautulli-integratie vond drie defecten en vijf
verbeteringen. De seeds voor "Omdat je X gekeken hebt" kwamen uit `fetchRecentlyWatched` van elke
online client, dus een Pleya Server-kijkbeurt nam een van de drie plekken in zonder rij op te
leveren, en een lopende serie seedde nooit omdat `isWatched` voor een serie "alles gezien"
betekent. Op de detailpagina ging de adminclient van Tautulli mee voor elk beheerd Plex-item, ook
op een tweede server die Tautulli niet monitort. Het lokale log kende alleen "afgekeken" en "uit
Verder kijken gehaald", zodat Jellyfin- en Pleya Server-profielen koud bleven tot ze in Pleya
zelf hadden gekeken.

**Decision:**

*Seeds uit het log.* De drie seed-rijen komen uit `MediaInteractions` van het actieve profiel:
de nieuwste onderscheiden evidence-sleutels met gewicht >= 0,4 binnen 30 dagen, alleen voor
servers met de capability `relatedHubs`. Een `partial`-seed heet "Omdat je X kijkt", een
`completed`-seed "Omdat je X gekeken hebt". Een leeg log valt terug op `fetchRecentlyWatched`.
Seeds vier tot en met zes leveren alleen kandidaten voor Top Picks.

*Eén partieel signaal, lokaal en geïmporteerd gelijk.* Een eindstop tussen 50 procent en de
kijkdrempel van de client schrijft `partial` 0,4, hoogstens één per titel per zes uur. De
cross-source-deduplicatie van de importer onderdrukt een geïmporteerd event alleen door een lokale
rij met minstens hetzelfde gewicht.

*Jellyfin als tweede adapter op dezelfde tabel.* `source = 'jellyfin'`, eigen gebruikerstoken,
geen adminbeleid, watermark op `LastPlayedDate`, geen backfill voorbij de retentiecap.

*Eén persoonsrij, gedeelde cap.* Genre-, acteur- en regisseursrijen delen twee plekken; sorteren
op genormaliseerd gewicht, bij gelijkspel genre, dan acteur, dan regisseur. Persoonsdrempel 0,7.

*De Tautulli-client volgt de gemonitorde server.* `TautulliProvider.clientForServer` geeft de
adminclient alleen voor de server die `tautulliMonitoredServer` aanwijst. "Nu aan het kijken" op
detail vergelijkt server én rating key.

**Consequences:** `ServerCapabilities.relatedHubs` (Plex en Jellyfin `true`). `WatchStateEvent`
draagt `durationMs` en `isFinal`. Drie nieuwe i18n-sleutels (`discover.becauseYouAreWatching`,
`discover.moreWithActor`, `discover.moreFromDirector`), andere locales vallen terug op Engels.
`HistorySyncCursors` krijgt rijen met `source = 'jellyfin'`; geen schemawijziging. Buiten scope
blijven: `get_home_stats`, een engine op Pleya Server, een negatief signaal uit een afgebroken
play, een rewatch-rij, een nieuw instellingenscherm. Open: P4 (devicetoken verbruikt bij een
mislukte test), P7 (client per importpagina), P9 (`owned` voor een beheerd Home-profiel) en de
Pleya Server-follow-ups `GET /items/{id}/related` en per-gebruiker watch-state. Register:
`docs/recommendations-register.md`.
```

- [ ] **Step 3: Zet het addendum onder DEC-062**

Direct na de alinea die begint met `*De credentialgrens.*` (regel 553) invoegen:

```markdown
*Addendum 24 september 2026 (DEC-132).* Twee namen in deze tekst zijn ingehaald door de code:
`SettingsExportService._denyPrefixes` is vervangen door de registry in
`lib/services/preferences/preference_sync_policy.dart` (onbekende sleutel is `localOnly`), en
`fetchImportHistory` neemt `profileId`, niet `userId` (`lib/services/tautulli/tautulli_import_access.dart`).
Het gedrag is zoals hier bedoeld; alleen de namen verschoven.
```

- [ ] **Step 4: Maak het register**

`docs/recommendations-register.md`:

```markdown
# Implementatieregister: aanbevelingen en Tautulli-defecten (DEC-132)

Aangelegd op 24 september 2026 door Michel Knoop. Spec:
`docs/superpowers/specs/2026-09-24-recommendations-design.md`. Plan:
`docs/superpowers/plans/2026-09-24-recommendations.md`.

Statussen: `OPEN`, `IN PROGRESS`, `CODE CLOSED`, `SIM CLOSED`, `LIVE ONLY`, `HARDWARE ONLY`,
`DEFERRED`. Bij elke sluiting komen de SHA en de bewijsregel erbij. Een rij verdwijnt alleen door
een eindstatus.

## Taken

| ID | Werkitem | Status | SHA / bewijs |
|----|----------|--------|--------------|
| REC-1 | DEC-132, register, DEC-062-addendum | OPEN | |
| REC-2 | D1: Tautulli-client volgt de gemonitorde server op detail en in "Nu aan het kijken"; P6; P8-kop | OPEN | |
| REC-3 | D2 en D3: seeds uit het interactielog, capability `relatedHubs`, "Omdat je X kijkt" | OPEN | |
| REC-4 | Lokaal partieel signaal bij een eindstop; importer vergelijkt gewichten | OPEN | |
| REC-5 | Related hubs van seeds vier tot zes als kandidatenlaag | OPEN | |
| REC-6 | Jellyfin-geschiedenisimport | OPEN | |
| REC-7 | Acteurs- of regisseursrij met gedeelde cap | OPEN | |
| REC-8 | i18n-controle, layoutblok-test, widgettest op de rijtitel | OPEN | |
| REC-9 | Volledige suite, `ci_checks`, drie Home-scenario's op de fixture, LIVE-ronde | OPEN | |

## Open punten buiten de taken

| ID | Punt | Status | Toelichting |
|----|------|--------|-------------|
| REC-P4 | Devicetoken verbruikt als `serverFriendlyName` of `version` na `register_device` faalt | DEFERRED | niet gemeten tegen `api2.py`; vraagt een clientfactory in `TautulliProvider.test` |
| REC-P7 | Eén `TautulliClient` per importpagina | DEFERRED | 25 clients per forward-pass, niet gevoeld |
| REC-P9 | Ziet een beheerd Plex Home-profiel `owned == true` in `isOwnerOrAdmin`? | LIVE ONLY | alleen op een echte server met een kindprofiel te toetsen |
| REC-PS1 | Pleya Server `GET /items/{id}/related` | OPEN (serverlijn) | zonder dit geen seed-rij voor Pleya Server-profielen |
| REC-PS2 | Pleya Server watch-state per gebruiker | OPEN (serverlijn) | zonder dit geen geschiedenisimport per profiel |
| REC-Q1 | `TvFocusRestoreHost` voor seed-rijen op TV | OPEN (productvraag) | default: nee |
| REC-Q2 | Persoonsrij bij niet-warme smaak | OPEN (productvraag) | default: nee |

## Verify en LIVE

| Platform | Scenario of ronde | Status | Bundel |
|----------|-------------------|--------|--------|
| tvOS-sim | `tvos.home.walk-rails` (regressie D2) | OPEN | |
| iOS-sim | `ios.home.northstar` (regressie D2) | OPEN | |
| macOS | `discover.layout.macos` (regressie D2) | OPEN | |
| iPhone of macOS, echt Plex-profiel met Tautulli en twee servers | seed-rijen, "Omdat je X kijkt", D1 | LIVE ONLY | |
| echt Jellyfin-profiel | import en warme rijen | LIVE ONLY | |
| Apple TV | D-pad over de acteursrij en de seed-rijen | HARDWARE ONLY | |
```

- [ ] **Step 5: Controleer links en anti-slop**

Run: `rg -n "recommendations-register|2026-09-24-recommendations" docs/DECISIONS.md docs/recommendations-register.md docs/superpowers/specs/2026-09-24-recommendations-design.md | wc -l`
Expected: minimaal 4 treffers.
Run: `rg -nP '\x{2014}|\x{2013}' docs/DECISIONS.md docs/recommendations-register.md | rg "DEC-132|REC-" ; echo "exit $?"`
Expected: `exit 1` (geen gedachtestreepjes in de nieuwe tekst; het patroon is de em- en en-dash als Unicode-escape).

- [ ] **Step 6: Commit**

```bash
git add docs/DECISIONS.md docs/recommendations-register.md
git commit -m "docs: DEC-132 en register voor aanbevelingen uit kijkgeschiedenis"
```

---

### Task 2: D1: de Tautulli-client volgt de gemonitorde server

`mechanisch`

**Files:**
- Modify: `lib/providers/tautulli_provider.dart` (na `client` getter, regel 132)
- Modify: `lib/screens/media_detail_screen.dart:2249, 2262`
- Modify: `lib/providers/now_watching_provider.dart:34-46`
- Modify: `lib/screens/media_detail/now_watching_line.dart:18-31`
- Modify: `lib/screens/media_detail_screen.dart:3876, 4609` (de twee `NowWatchingLine(...)`-montages)
- Modify: `lib/navigation/profile_session_screen.dart:214-224`
- Modify: `lib/services/recommendations/tautulli_history_importer.dart:898-900`
- Modify: `lib/screens/settings/tautulli_settings_screen.dart:32-35`
- Test: `test/providers/tautulli_provider_test.dart`, `test/widgets/now_watching_surfaces_test.dart`

**Interfaces:**
- Consumes: `tautulliMonitoredServer` (`lib/services/tautulli/tautulli_server_binding.dart`).
- Produces: `TautulliClient? TautulliProvider.clientForServer(ServerId serverId)`, `ServerId? TautulliProvider.monitoredServerId`, `NowWatchingProvider({ServerId? Function()? monitoredServerId})` met getter `ServerId? get monitoredServerId`, `NowWatchingLine({required String ratingKey, required ServerId? serverId})`.

- [ ] **Step 1: Schrijf de falende providertest**

In `test/providers/tautulli_provider_test.dart`, in de groep `'who sees what'`:

```dart
    test('the admin client is only handed out for the server Tautulli monitors', () async {
      await seedIntegration();
      final p = await provider(servers: const [_machine, 'pms-2']);
      addTearDown(p.dispose);
      expect(p.client, isNotNull, reason: 'the admin surface still has its client');
      expect(p.clientForServer(ServerId(_machine)), isNotNull);
      expect(p.clientForServer(ServerId('pms-2')), isNull, reason: 'rating keys on pms-2 are a different id space');
      expect(p.monitoredServerId, ServerId(_machine));
    });
```

- [ ] **Step 2: Draai de test en zie hem falen**

Run: `flutter test test/providers/tautulli_provider_test.dart --plain-name "only handed out"`
Expected: FAIL, `clientForServer` is niet gedefinieerd.

- [ ] **Step 3: Voeg `clientForServer` en `monitoredServerId` toe**

In `lib/providers/tautulli_provider.dart`, na `TautulliClient? get client => _client;` (regel 132):

```dart
  /// Which registered server the paired Tautulli watches, or null when that is
  /// not decidable. Same rule as the artwork client in the profile session.
  ServerId? get monitoredServerId {
    if (_session == null) return null;
    return tautulliMonitoredServer(
      machineIdentifier: _session?.machineIdentifier,
      serverIds: _serverIds(),
      isOwnerOrAdmin: _isOwnerOrAdmin,
    );
  }

  /// The admin client, but only for the server Tautulli actually monitors.
  ///
  /// Rating keys are per-server integers. Handing this client to a detail page
  /// on a second owned server made it answer with the watchers of whatever
  /// title carries the same key on the monitored one, and an empty answer then
  /// suppressed the Plex fallback too.
  TautulliClient? clientForServer(ServerId serverId) {
    final client = _client;
    if (client == null) return null;
    return monitoredServerId == serverId ? client : null;
  }
```

Import bovenaan: `import '../services/tautulli/tautulli_server_binding.dart';`.

- [ ] **Step 4: Gebruik hem op de detailpagina**

`lib/screens/media_detail_screen.dart` regel 2249: `tautulli: context.read<TautulliProvider?>()?.client,` wordt
`tautulli: context.read<TautulliProvider?>()?.clientForServer(serverId),`.
Regel 2262: `final tautulli = context.read<TautulliProvider?>()?.client;` wordt
`final tautulli = context.read<TautulliProvider?>()?.clientForServer(serverId);`.
(`serverId` is de `ServerId` die op regel 2234 al is opgelost.)

- [ ] **Step 5: Schrijf de falende widgettest voor de regel**

In `test/widgets/now_watching_surfaces_test.dart` de helper `_providerWith` uitbreiden:

```dart
Future<NowWatchingProvider> _providerWith(NowWatching now, {String? monitored}) async {
  final client = TautulliClient(
    TautulliSession(baseUrl: 'https://tautulli.example.test', authMode: TautulliAuthMode.apiKey, token: 'T'),
    httpClient: MockClient((_) async => http.Response('{}', 200)),
  );
  final provider = NowWatchingProvider(
    client: () => client,
    enabled: () => true,
    monitoredServerId: () => monitored == null ? null : ServerId(monitored),
    service: _FakeService(() => now),
  );
  await provider.refresh();
  return provider;
}
```

En in de groep met de `NowWatchingLine`-tests:

```dart
    testWidgets('a title on a server Tautulli does not monitor gets no line', (tester) async {
      final provider = await _providerWith(NowWatching(sessions: [_session(ratingKey: '57752')]), monitored: 'server-a');
      addTearDown(provider.dispose);
      await _pump(tester, provider, NowWatchingLine(ratingKey: '57752', serverId: ServerId('server-b')));
      expect(find.byType(WatcherAvatar), findsNothing);
    });

    testWidgets('the same key on the monitored server does get the line', (tester) async {
      final provider = await _providerWith(NowWatching(sessions: [_session(ratingKey: '57752')]), monitored: 'server-a');
      addTearDown(provider.dispose);
      await _pump(tester, provider, NowWatchingLine(ratingKey: '57752', serverId: ServerId('server-a')));
      expect(find.byType(WatcherAvatar), findsOneWidget);
    });
```

De bestaande `NowWatchingLine(ratingKey: '57752')`-aanroepen in dat bestand krijgen `serverId: null` en de bijbehorende verwachting wordt `findsNothing` waar ze een regel verwachtten; voeg aan die tests `monitored: 'server-a'` en `serverId: ServerId('server-a')` toe zodat ze hun oorspronkelijke bewering houden.

- [ ] **Step 6: Draai en zie falen**

Run: `flutter test test/widgets/now_watching_surfaces_test.dart`
Expected: FAIL op `monitoredServerId` en `serverId`.

- [ ] **Step 7: Provider en regel aanpassen**

`lib/providers/now_watching_provider.dart`, constructor:

```dart
  NowWatchingProvider({
    required TautulliClient? Function() client,
    required bool Function() enabled,
    int? Function()? selfUserId,
    MediaServerClient? Function()? artworkClient,
    ServerId? Function()? monitoredServerId,
    NowWatchingService service = const NowWatchingService(),
  }) : _client = client,
       _enabled = enabled,
       _selfUserId = selfUserId,
       _artworkClient = artworkClient,
       _monitoredServerId = monitoredServerId,
       _service = service {
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
  }

  final ServerId? Function()? _monitoredServerId;

  /// The server whose rating keys the sessions speak of. Null when unknown,
  /// and then no surface may match a session to a title by key alone.
  ServerId? get monitoredServerId => _monitoredServerId?.call();
```

`lib/screens/media_detail/now_watching_line.dart`:

```dart
  const NowWatchingLine({super.key, required this.ratingKey, required this.serverId, this.textStyle});

  final String ratingKey;

  /// The server the item on screen lives on. A session only speaks of the
  /// monitored server, so a key match on any other server is a coincidence.
  final ServerId? serverId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NowWatchingProvider?>();
    final monitored = provider?.monitoredServerId;
    if (provider == null || monitored == null || serverId == null || monitored != serverId) {
      return const SizedBox.shrink();
    }
    final session = provider.sessions.where((s) => s.ratingKey == ratingKey).firstOrNull;
    if (session == null) return const SizedBox.shrink();
```

Import `../../media/ids.dart`. De twee montages in `media_detail_screen.dart` (regels 3876 en 4609) worden `NowWatchingLine(ratingKey: _metadata.id, serverId: serverIdOrNull(_metadata.serverId))`.

`lib/navigation/profile_session_screen.dart`, in de `NowWatchingProvider(...)`-constructie (regel 214): voeg `monitoredServerId: monitoredServerId,` toe (de lokale functie op regel 205 bestaat al).

- [ ] **Step 8: P6 en P8 meenemen**

`tautulli_history_importer.dart` regel 898-900: de eerste regel van `_errorCategory` wordt

```dart
  static String _errorCategory(Object e) {
    if (e is TautulliException && e.isAuth) return 'isAuth';
    final text = e.toString().toLowerCase();
    if (text.contains('unauthorized') || text.contains('forbidden')) return 'isAuth';
```

(de `apikey`-heuristiek verdwijnt; import `../tautulli/tautulli_client.dart` als die er nog niet is).

`tautulli_settings_screen.dart` regel 32-35: vervang de twee zinnen vanaf "One key opens" door:

```dart
/// login. One key opens the whole admin API, so pairing is an admin act. What
/// it feeds is per profile: every profile on this server gets its own history
/// imported, bound to its own Plex account (DEC-062), and none of them sees
/// the key.
```

- [ ] **Step 9: Draai de tests en de gate**

Run: `flutter test test/providers/tautulli_provider_test.dart test/widgets/now_watching_surfaces_test.dart test/services/item_watchers_service_test.dart test/services/recommendations/tautulli_history_importer_test.dart`
Expected: PASS.
Run: `scripts/ci_checks.sh`
Expected: groen.

- [ ] **Step 10: Commit**

```bash
git add lib/providers/tautulli_provider.dart lib/providers/now_watching_provider.dart lib/screens/media_detail_screen.dart lib/screens/media_detail/now_watching_line.dart lib/navigation/profile_session_screen.dart lib/services/recommendations/tautulli_history_importer.dart lib/screens/settings/tautulli_settings_screen.dart test/providers/tautulli_provider_test.dart test/widgets/now_watching_surfaces_test.dart
git commit -m "fix(tautulli): detail en Nu aan het kijken volgen de gemonitorde server (D1)"
```

Zet in `docs/recommendations-register.md` REC-2 op `CODE CLOSED` met de SHA (mag in de commit van Taak 3 mee).

---

### Task 3: Seeds uit het interactielog (D2 en D3)

`oordeel`: bepaalt welke drie rijen bovenaan Home staan en hoe ze heten.

**Files:**
- Modify: `lib/media/server_capabilities.dart:131` (constructor) en de consts `plex` (156), `jellyfin` (188)
- Modify: `lib/database/app_database.dart` (na `getMediaInteractions`, regel 375)
- Modify: `lib/services/recommendations/recommendation_service.dart` (veld `_db`, methode `recentSeeds`)
- Modify: `lib/providers/discover_provider.dart:500-568`
- Modify: `lib/i18n/nl.i18n.json:840`, `lib/i18n/en.i18n.json:840`
- Test: `test/services/recommendations/affinity_engine_db_test.dart`, `test/providers/discover_provider_test.dart`

**Interfaces:**
- Consumes: `AppDatabase._scoringScope`, `MediaServerClient.fetchItem`, `fetchRelatedHubs`, `t.discover.becauseYouWatched`.
- Produces: `bool ServerCapabilities.relatedHubs`; `Future<List<MediaInteractionRow>> AppDatabase.recentPositiveInteractions(String profileId, {required int sinceMs, required double minWeight, required int limit, Set<String> enabledImportServerIds})`; `class RecommendationSeed { String globalKey; bool completed; int occurredAtMs; }`; `Future<List<RecommendationSeed>> RecommendationService.recentSeeds({int limit = 6, int? nowMs})`; `t.discover.becauseYouAreWatching(title:)`. Taak 5 bouwt op `recentSeeds(limit: 6)`.

- [ ] **Step 1: Falende databasetest**

In `test/services/recommendations/affinity_engine_db_test.dart`, `_row` uitbreiden met `String? seriesKey, String eventType = 'completed'` en `seriesKey: Value(seriesKey), eventType: eventType` in de companion. Dan:

```dart
  group('recentPositiveInteractions', () {
    const now = 1700000000000;
    const day = Duration.millisecondsPerDay;

    test('one row per evidence key, newest first, positives only, inside the window', () async {
      await db.insertMediaInteraction(_row('p1', 's:ep1', seriesKey: 's:show', occurredAt: now - 1 * day), profileId: 'p1');
      await db.insertMediaInteraction(_row('p1', 's:ep2', seriesKey: 's:show', occurredAt: now - 2 * day, weight: 0.4, eventType: 'partial'), profileId: 'p1');
      await db.insertMediaInteraction(_row('p1', 's:film', occurredAt: now - 3 * day), profileId: 'p1');
      await db.insertMediaInteraction(_row('p1', 's:dismissed', occurredAt: now - 1 * day, weight: -0.3, eventType: 'skipped'), profileId: 'p1');
      await db.insertMediaInteraction(_row('p1', 's:old', occurredAt: now - 40 * day), profileId: 'p1');

      final rows = await db.recentPositiveInteractions('p1', sinceMs: now - 30 * day, minWeight: 0.4, limit: 6);

      expect(rows.map((r) => r.globalKey), ['s:ep1', 's:film'], reason: 'the show once, the dismissal and the old row never');
    });

    test('an imported row on a disabled server is not a seed', () async {
      await db.insertMediaInteraction(
        MediaInteractionsCompanion.insert(
          profileId: 'p1', globalKey: 'pms:9', mediaKind: 'movie', eventType: 'completed', eventWeight: 1.0,
          occurredAt: now, source: const Value('tautulli'), sourceServerId: const Value('pms'),
          sourceEventId: const Value('tautulli:pms:9'),
        ),
        profileId: 'p1',
      );
      expect(await db.recentPositiveInteractions('p1', sinceMs: now - 30 * day, minWeight: 0.4, limit: 6), isEmpty);
      expect(await db.recentPositiveInteractions('p1', sinceMs: now - 30 * day, minWeight: 0.4, limit: 6, enabledImportServerIds: const {'pms'}), hasLength(1));
    });
  });
```

De retentie-prune in `insertMediaInteraction` gebruikt de wandklok; gebruik voor `now` in deze test `DateTime.now().millisecondsSinceEpoch` in plaats van de constante als de rij van 40 dagen anders wordt gepruned, dat is prima: de test wil hem juist niet zien.

- [ ] **Step 2: Draai en zie falen**

Run: `flutter test test/services/recommendations/affinity_engine_db_test.dart --plain-name "recentPositiveInteractions"`
Expected: FAIL, methode ontbreekt.

- [ ] **Step 3: Databasemethode**

In `lib/database/app_database.dart` na `getMediaInteractions`:

```dart
  /// Newest positive interactions of one profile, one row per evidence key
  /// (the series for an episode, the item for a movie), newest first. Same
  /// scoring scope as the vector, so a disabled import server never seeds.
  Future<List<MediaInteractionRow>> recentPositiveInteractions(
    String profileId, {
    required int sinceMs,
    required double minWeight,
    required int limit,
    Set<String> enabledImportServerIds = const {},
  }) async {
    final rows =
        await (select(mediaInteractions)
              ..where(
                (t) =>
                    t.profileId.equals(profileId) &
                    t.eventWeight.isBiggerOrEqualValue(minWeight) &
                    t.occurredAt.isBiggerOrEqualValue(sinceMs) &
                    _scoringScope(enabledImportServerIds),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
            .get();
    final seen = <String>{};
    final out = <MediaInteractionRow>[];
    for (final row in rows) {
      if (!seen.add(row.seriesKey ?? row.globalKey)) continue;
      out.add(row);
      if (out.length >= limit) break;
    }
    return out;
  }
```

Run: `flutter test test/services/recommendations/affinity_engine_db_test.dart`
Expected: PASS.

- [ ] **Step 4: Capability en service**

`lib/media/server_capabilities.dart`: veld en constructorparameter toevoegen naast `richHubs`:

```dart
  /// The backend answers `fetchRelatedHubs` with something (Plex `/related`,
  /// Jellyfin `/Similar`). A source without this never becomes a seed for
  /// "Because you watched", because the row would be empty.
  final bool relatedHubs;
```

Constructor: `this.relatedHubs = false,`. In `plex` en `jellyfin`: `relatedHubs: true,`. `local` en de Pleya Server-resolver blijven op de default.

`lib/services/recommendations/recommendation_service.dart`:

```dart
/// How far back a title may lie to still headline a "Because you watched" row.
const Duration kSeedWindow = Duration(days: 30);

/// A partial view counts; a dismissal never does.
const double kSeedMinWeight = 0.4;

/// One title the feed may build a related row on.
class RecommendationSeed {
  /// The series key for an episode, the item's own global key otherwise.
  final String globalKey;

  /// False when the strongest recent evidence is a partial view: the title is
  /// still being watched and the row says so.
  final bool completed;
  final int occurredAtMs;
  const RecommendationSeed({required this.globalKey, required this.completed, required this.occurredAtMs});
}
```

Veld `final AppDatabase _db;` toevoegen en in de constructor-initializer `_db = database,`. Methode:

```dart
  /// Newest distinct titles with positive evidence, for the seed rows. Empty
  /// when personalization is off or nothing qualifies; the caller then falls
  /// back to the servers' own recently-watched lists.
  Future<List<RecommendationSeed>> recentSeeds({int limit = 6, int? nowMs}) async {
    if (!_enabled) return const [];
    try {
      final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      final rows = await _db.recentPositiveInteractions(
        profileId,
        sinceMs: now - kSeedWindow.inMilliseconds,
        minWeight: kSeedMinWeight,
        limit: limit,
        enabledImportServerIds: _enabledImportServerIds(),
      );
      return [
        for (final row in rows)
          RecommendationSeed(globalKey: row.seriesKey ?? row.globalKey, completed: row.eventWeight >= 1.0, occurredAtMs: row.occurredAt),
      ];
    } catch (e, s) {
      appLogger.w('RecommendationService: recentSeeds failed (no seeds)', error: e, stackTrace: s);
      return const [];
    }
  }
```

- [ ] **Step 5: i18n-sleutel**

`lib/i18n/en.i18n.json` na regel 840: `"becauseYouAreWatching": "Because you're watching ${title}",`.
`lib/i18n/nl.i18n.json` na regel 840: `"becauseYouAreWatching": "Omdat je ${title} kijkt",`.
Run: `dart run slang`
Expected: `strings.g.dart` en `strings_nl.g.dart` bevatten `becauseYouAreWatching`.

- [ ] **Step 6: Falende providertests**

In `test/providers/discover_provider_test.dart`. `_FakeRecommendationService` krijgt:

```dart
  List<RecommendationSeed> seeds = const [];
  List<MediaItem> lastHubItems = const [];

  @override
  Future<List<RecommendationSeed>> recentSeeds({int limit = 6, int? nowMs}) async => seeds.take(limit).toList();
```

en in `buildRows`: `lastHubItems = hubItems;`. `_FakeClient` krijgt:

```dart
  List<MediaItem> recentlyWatched = const [];
  Map<String, List<MediaHub>> relatedByItem = const {};
  ServerCapabilities caps = ServerCapabilities.plex;

  @override
  ServerCapabilities get capabilities => caps;

  @override
  Future<List<MediaItem>> fetchRecentlyWatched({int limit = 5}) async => recentlyWatched.take(limit).toList();

  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async => relatedByItem[id] ?? const [];
```

en `fetchItem` blijft `itemResult` teruggeven; maak er een map van: `Map<String, MediaItem> itemsById = {};` met `return itemsById[id] ?? itemResult;`. Nieuwe groep:

```dart
  group('seed rows from the interaction log', () {
    MediaItem movie(String id, {String server = 'server_1', int viewCount = 0}) =>
        MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: id, serverId: server, serverName: 'Server', viewCount: viewCount);

    Future<DiscoverProvider> loadWith(_FakeRecommendationService service, List<_FakeClient> clients) async {
      final manager = MultiServerManager();
      for (final c in clients) {
        manager.debugRegisterClientForTesting(c);
      }
      aggregation = _FakeAggregationService(manager);
      multiServer = MultiServerProvider(manager, aggregation);
      final p = DiscoverProvider(multiServer, hiddenLibraries, libraries, isProfileBinding: () => isBinding, recommendations: service);
      aggregation.onDeckResult = () => const [];
      aggregation.hubsResult = () => const [];
      await p.load();
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return p;
    }

    test('a partial seed becomes "because you are watching", a completed one keeps the old title', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      client.itemsById = {'sev': movie('sev'), 'heat': movie('heat')};
      client.relatedByItem = {
        'sev': [_hub('rel-sev', items: [movie('a'), movie('b'), movie('c')])],
        'heat': [_hub('rel-heat', items: [movie('d'), movie('e'), movie('f')])],
      };
      final service = _FakeRecommendationService()
        ..seeds = [
          RecommendationSeed(globalKey: 'server_1:sev', completed: false, occurredAtMs: now),
          RecommendationSeed(globalKey: 'server_1:heat', completed: true, occurredAtMs: now - 1000),
        ];
      final p = await loadWith(service, [client]);
      addTearDown(p.dispose);

      final titles = p.hubs.where((h) => h.identifier == 'home.becauseyouwatched').map((h) => h.title).toList();
      expect(titles, [t.discover.becauseYouAreWatching(title: 'sev'), t.discover.becauseYouWatched(title: 'heat')]);
    });

    test('a seed on a server without related hubs takes no slot and costs no fetch', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final pleya = _FakeClient(id: 'pleya_1')..caps = ServerCapabilities.local;
      client.itemsById = {'heat': movie('heat')};
      client.relatedByItem = {'heat': [_hub('rel', items: [movie('d'), movie('e'), movie('f')])]};
      final service = _FakeRecommendationService()
        ..seeds = [
          RecommendationSeed(globalKey: 'pleya_1:42', completed: true, occurredAtMs: now),
          RecommendationSeed(globalKey: 'server_1:heat', completed: true, occurredAtMs: now - 1000),
        ];
      final p = await loadWith(service, [client, pleya]);
      addTearDown(p.dispose);

      expect(p.hubs.where((h) => h.identifier == 'home.becauseyouwatched'), hasLength(1));
      expect(pleya.fetchedIds, isEmpty);
    });

    test('finished titles are dropped from a seed row', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      client.itemsById = {'heat': movie('heat')};
      client.relatedByItem = {
        'heat': [_hub('rel', items: [movie('seen', viewCount: 1), movie('d'), movie('e'), movie('f')])],
      };
      final service = _FakeRecommendationService()..seeds = [RecommendationSeed(globalKey: 'server_1:heat', completed: true, occurredAtMs: now)];
      final p = await loadWith(service, [client]);
      addTearDown(p.dispose);

      final row = p.hubs.singleWhere((h) => h.identifier == 'home.becauseyouwatched');
      expect(row.items.map((i) => i.id), isNot(contains('seen')));
    });

    test('an empty log falls back to the servers own recently watched list', () async {
      client.recentlyWatched = [movie('old', viewCount: 1)];
      client.relatedByItem = {'old': [_hub('rel', items: [movie('d'), movie('e'), movie('f')])]};
      final p = await loadWith(_FakeRecommendationService(), [client]);
      addTearDown(p.dispose);

      expect(p.hubs.where((h) => h.identifier == 'home.becauseyouwatched'), hasLength(1));
    });
  });
```

Import bovenaan: `import 'package:pleya/i18n/strings.g.dart';`. `MediaItem` heeft `viewCount` als named parameter in de gewone constructor; controleer met `rg -n "int\? viewCount" lib/media/media_item.dart`.

- [ ] **Step 7: Draai en zie falen**

Run: `flutter test test/providers/discover_provider_test.dart --plain-name "seed rows"`
Expected: FAIL (`recentSeeds`, `caps`, titels).

- [ ] **Step 8: `_loadBecauseYouWatched` herschrijven**

In `lib/providers/discover_provider.dart`, regels 500-568 worden:

```dart
  /// A seed and how it was earned. [completed] picks the title: a finished
  /// title reads "Because you watched X", one still in progress "Because
  /// you're watching X".
  typedef _Seed = ({MediaItem item, bool completed});

  Future<void> _loadBecauseYouWatched() async {
    try {
      // Only sources that can answer with related titles may seed; a seed on
      // any other source would take one of the three slots and yield nothing.
      final clients = _multiServer.serverManager.onlineClients.values
          .where((client) => client.capabilities.relatedHubs)
          .toList();
      if (clients.isEmpty) return;
      final generation = _loadGeneration;
      final alreadyShown = <String>{
        for (final item in _onDeck) item.globalKey,
        for (final hub in _hubs)
          for (final item in hub.items) item.globalKey,
      };

      var seeds = await _seedsFromLog(clients);
      if (seeds.isEmpty) seeds = await _seedsFromServers(clients);
      final rows = seeds.isEmpty
          ? const <MediaHub?>[]
          : await Future.wait([
              for (final seed in seeds.take(3)) _relatedRowForSeed(seed, alreadyShown).catchError((Object _) => null),
            ]);
      if (isDisposed || generation != _loadGeneration) return;

      final newSeedHubs = [for (final row in rows) ?row];
      if (_seedHubs.isEmpty && newSeedHubs.isEmpty) return;
      _seedHubs = newSeedHubs;
      safeNotifyListeners();
    } catch (e) {
      appLogger.w('DiscoverProvider: because-you-watched rows failed (keeping previous)', error: e);
    }
  }

  /// Seeds from this profile's own interaction log, newest first. A key that
  /// belongs to no eligible client is skipped without a fetch.
  Future<List<_Seed>> _seedsFromLog(List<MediaServerClient> clients) async {
    final service = recommendations;
    if (service == null) return const [];
    final seeds = await service.recentSeeds(limit: 6);
    final out = <_Seed>[];
    for (final seed in seeds) {
      final client = clients.where((c) => seed.globalKey.startsWith('${c.serverId}:')).firstOrNull;
      if (client == null) continue;
      final itemId = seed.globalKey.substring('${client.serverId}:'.length);
      final item = await client.fetchItem(itemId).catchError((Object _) => null);
      if (item == null || item.title == null) continue;
      out.add((item: item, completed: seed.completed));
    }
    return out;
  }

  /// The pre-log path: what each server itself says was watched last. Kept as
  /// the cold-start fallback so a fresh profile on an old server still gets
  /// its rows.
  Future<List<_Seed>> _seedsFromServers(List<MediaServerClient> clients) async {
    final recents = await Future.wait([
      for (final client in clients) client.fetchRecentlyWatched(limit: 5).catchError((Object _) => const <MediaItem>[]),
    ]);
    final merged = recents.expand((items) => items).toList()
      ..sort((a, b) => b.recencySortKey.compareTo(a.recencySortKey));
    final seeds = <_Seed>[];
    final usedIdentities = <String>{};
    for (final item in merged) {
      if (item.serverId == null || item.title == null) continue;
      final identity = (item.grandparentTitle ?? item.title ?? item.id).toLowerCase();
      if (!usedIdentities.add(identity)) continue;
      seeds.add((item: item, completed: true));
      if (seeds.length >= 3) break;
    }
    return seeds;
  }

  Future<MediaHub?> _relatedRowForSeed(_Seed seed, Set<String> alreadyShown) async {
    final serverId = seed.item.serverId;
    final seedTitle = seed.item.title;
    if (serverId == null || seedTitle == null) return null;
    final client = _multiServer.getClientForServer(ServerId(serverId));
    if (client == null) return null;
    final relatedHubs = await client.fetchRelatedHubs(seed.item.id);
    for (final hub in relatedHubs) {
      final items = hub.items
          .where((item) => item.globalKey != seed.item.globalKey && !item.isWatched && !alreadyShown.contains(item.globalKey))
          .toList();
      if (items.isEmpty) continue;
      return hub.copyWith(
        identifier: 'home.becauseyouwatched',
        title: seed.completed
            ? t.discover.becauseYouWatched(title: seedTitle)
            : t.discover.becauseYouAreWatching(title: seedTitle),
        items: items,
      );
    }
    return null;
  }
```

De `typedef` staat op bestandsniveau (buiten de klasse), boven `class DiscoverProvider`.

- [ ] **Step 9: Draai alles wat het raakt**

Run: `flutter test test/providers/discover_provider_test.dart test/services/recommendations/ test/screens/discover_screen_test.dart`
Expected: PASS. Let op de bestaande fetch-cost-tests in `discover_provider_test.dart`: de seedselectie loopt buiten de getelde paden, dus de tellingen moeten ongewijzigd groen zijn.
Run: `scripts/ci_checks.sh`
Expected: groen (de i18n-codegen is vers).

- [ ] **Step 10: Commit**

```bash
git add lib/media/server_capabilities.dart lib/database/app_database.dart lib/services/recommendations/recommendation_service.dart lib/providers/discover_provider.dart lib/i18n/nl.i18n.json lib/i18n/en.i18n.json lib/i18n/strings.g.dart lib/i18n/strings_nl.g.dart lib/i18n/strings_en.g.dart test/services/recommendations/affinity_engine_db_test.dart test/providers/discover_provider_test.dart docs/recommendations-register.md
git commit -m "feat(home): seeds voor Omdat je X keek uit het eigen kijklog (D2, D3)"
```

---

### Task 4: Lokaal partieel signaal bij een eindstop

`oordeel`: scoringssemantiek, raakt elke gepersonaliseerde rij.

**Files:**
- Modify: `lib/utils/watch_state_notifier.dart:33-77, 123-148`
- Modify: `lib/services/playback_progress_tracker.dart:455-472`
- Modify: `lib/services/recommendations/interaction_recorder.dart:56-90`
- Modify: `lib/services/recommendations/tautulli_history_importer.dart:44-46, 659-690, 777-782`
- Modify: `lib/database/app_database.dart:425-450` (`localPositiveInteractionsIn`) plus nieuwe `hasPositiveInteractionSince`
- Create: `test/services/recommendations/interaction_recorder_test.dart`
- Test: `test/services/recommendations/tautulli_history_importer_test.dart`

**Interfaces:**
- Consumes: `WatchStateNotifier.notifyProgress`, `kPartialPercent`, `kCrossSourceWindow`.
- Produces: `WatchStateEvent({int? durationMs, bool isFinal = false})`; `notifyProgress({..., bool isFinal = false})`; `const double kPartialWeight = 0.4` in `tautulli_history_importer.dart`; `Future<bool> AppDatabase.hasPositiveInteractionSince(String profileId, String globalKey, int sinceMs)`; `localPositiveInteractionsIn` geeft `Map<String, List<({int at, double weight})>>`. Taak 6 hergebruikt `kPartialWeight` en de gewichtsvergelijking.

- [ ] **Step 1: Falende recordertest**

`test/services/recommendations/interaction_recorder_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/services/recommendations/interaction_recorder.dart';
import 'package:pleya/utils/watch_state_notifier.dart';

class _FakeClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('s1');
  @override
  MediaBackend get backend => MediaBackend.plex;
  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;
  @override
  Future<MediaItem?> fetchItem(String id, {bool useCache = true}) async =>
      MediaItem.plex(id: id, kind: MediaKind.movie, serverId: 's1', title: id, genres: const ['Drama'], year: 2019);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late InteractionRecorder recorder;
  final item = MediaItem.plex(id: 'm1', kind: MediaKind.movie, serverId: 's1', title: 'm1');
  const hour = 60 * 60 * 1000;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    recorder = InteractionRecorder(database: db, profileId: 'p1', clientResolver: (_) => _FakeClient())..start();
  });
  tearDown(() async {
    await recorder.dispose();
    await db.close();
  });

  Future<List<MediaInteractionRow>> rows() async {
    await pumpEventQueue();
    return db.getMediaInteractions('p1');
  }

  test('a final stop at 60 percent records one partial row', () async {
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 60 * 60000, duration: 100 * 60000, isFinal: true);
    final saved = await rows();
    expect(saved.single.eventType, 'partial');
    expect(saved.single.eventWeight, 0.4);
    expect(saved.single.genresJson, '["Drama"]');
  });

  test('below 50 percent nothing is recorded', () async {
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 20 * 60000, duration: 100 * 60000, isFinal: true);
    expect(await rows(), isEmpty);
  });

  test('a progress tick that is not final records nothing', () async {
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 60 * 60000, duration: 100 * 60000);
    expect(await rows(), isEmpty);
  });

  test('a final stop that already counts as watched leaves the row to the watched event', () async {
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 95 * 60000, duration: 100 * 60000, isFinal: true);
    expect(await rows(), isEmpty, reason: 'isNowWatched is true at 95 percent; the watched event carries this one');
  });

  test('a second final stop within six hours does not stack', () async {
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 55 * 60000, duration: 100 * 60000, isFinal: true);
    await rows();
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 70 * 60000, duration: 100 * 60000, isFinal: true);
    expect(await rows(), hasLength(1));
  });

  test('the six hour window is measured against the stored row', () async {
    await db.insertMediaInteraction(
      MediaInteractionsCompanion.insert(
        profileId: 'p1', globalKey: 's1:m1', mediaKind: 'movie', eventType: 'partial', eventWeight: 0.4,
        occurredAt: DateTime.now().millisecondsSinceEpoch - 7 * hour,
      ),
      profileId: 'p1',
    );
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 55 * 60000, duration: 100 * 60000, isFinal: true);
    expect(await rows(), hasLength(2));
  });
}
```

- [ ] **Step 2: Draai en zie falen**

Run: `flutter test test/services/recommendations/interaction_recorder_test.dart`
Expected: FAIL, `isFinal` is geen parameter van `notifyProgress`.

- [ ] **Step 3: Event en notifier**

`lib/utils/watch_state_notifier.dart`, `WatchStateEvent`: twee velden en constructorparameters:

```dart
  /// Media duration in milliseconds, when the emitter knows it. Together with
  /// [viewOffset] this is the completion percentage of a stop.
  final int? durationMs;

  /// The terminal notification of a playback session. Fires at most once per
  /// session (see PlaybackProgressTracker); a progress tick is never final.
  final bool isFinal;
```

Constructor: `this.durationMs, this.isFinal = false,`. `notifyProgress` krijgt `bool isFinal = false` en zet `durationMs: duration, isFinal: isFinal` in het event.

`lib/services/playback_progress_tracker.dart` regel 467-472: `isFinal: isFinal,` toevoegen aan de `notifyProgress`-aanroep.

- [ ] **Step 4: Recorder**

`lib/services/recommendations/tautulli_history_importer.dart` regel 44-46: constante erbij en gebruiken:

```dart
/// Weight of a partial view, local or imported.
const double kPartialWeight = 0.4;
```

en regel 781: `return (type: 'partial', weight: kPartialWeight);`.

`lib/services/recommendations/interaction_recorder.dart`, `_onEvent`:

```dart
  Future<void> _onEvent(WatchStateEvent event) async {
    try {
      final (String type, double weight)? mapped = switch (event.changeType) {
        WatchStateChangeType.watched => ('completed', 1.0),
        WatchStateChangeType.removedFromContinueWatching => ('skipped', -0.3),
        WatchStateChangeType.progressUpdate => await _partialSignal(event),
        WatchStateChangeType.unwatched => null,
      };
      if (mapped == null) return;
```

en de nieuwe methode:

```dart
  /// A final stop between [kPartialPercent] and the client's watched threshold
  /// is evidence the title held attention. Below it nothing is recorded, as
  /// with the imported history (DEC-062). At or above the threshold the
  /// `watched` event carries the row, so nothing is written here either. One
  /// row per title per [kCrossSourceWindow], so pausing and resuming over an
  /// evening does not stack.
  Future<(String, double)?> _partialSignal(WatchStateEvent event) async {
    final duration = event.durationMs;
    final offset = event.viewOffset;
    if (!event.isFinal || duration == null || duration <= 0 || offset == null) return null;
    if (event.isNowWatched == true) return null;
    if (offset * 100 ~/ duration < kPartialPercent) return null;
    final since = DateTime.now().millisecondsSinceEpoch - kCrossSourceWindow.inMilliseconds;
    if (await _db.hasPositiveInteractionSince(_profileId, event.globalKey, since)) return null;
    return ('partial', kPartialWeight);
  }
```

Import `tautulli_history_importer.dart` voor de constanten. Werk de klassedocumentatie bij: de zin "Partial/abandoned tracking can be layered on later" klopt niet meer; vervang door een zin die het partiële signaal en zijn grenzen noemt.

`lib/database/app_database.dart`, naast `localPositiveInteractionsIn`:

```dart
  /// Whether a positive row for [globalKey] exists at or after [sinceMs].
  /// Any source counts: a Tautulli row imported an hour ago is as much proof
  /// of the view as a local one.
  Future<bool> hasPositiveInteractionSince(String profileId, String globalKey, int sinceMs) async {
    final row =
        await (select(mediaInteractions)
              ..where(
                (t) =>
                    t.profileId.equals(profileId) &
                    t.globalKey.equals(globalKey) &
                    t.eventWeight.isBiggerThanValue(0) &
                    t.occurredAt.isBiggerOrEqualValue(sinceMs),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }
```

Run: `flutter test test/services/recommendations/interaction_recorder_test.dart`
Expected: PASS.

- [ ] **Step 5: Falende importertest voor de gewichtsvergelijking**

In `test/services/recommendations/tautulli_history_importer_test.dart`, nieuwe groep onderaan `main`:

```dart
  group('cross-source window and weights', () {
    Future<void> local(String globalKey, double weight, {String type = 'completed'}) => db.insertMediaInteraction(
      MediaInteractionsCompanion.insert(
        profileId: _profile, globalKey: globalKey, mediaKind: 'movie', eventType: type, eventWeight: weight,
        occurredAt: _now - Duration.millisecondsPerHour,
      ),
      profileId: _profile,
    );

    test('a local partial does not swallow a completed Tautulli view', () async {
      await local('$_machine:1', 0.4, type: 'partial');
      final access = _FakeAccess(rows: [_entry(rowId: 1, daysAgo: 0)]);
      final outcome = await importer(access, _FakeClient({'1': _item('1')})).sync();
      expect(outcome!.imported, 1);
      expect(outcome.deduplicated, 0);
    });

    test('a local completed does swallow it', () async {
      await local('$_machine:1', 1.0);
      final access = _FakeAccess(rows: [_entry(rowId: 1, daysAgo: 0)]);
      final outcome = await importer(access, _FakeClient({'1': _item('1')})).sync();
      expect(outcome!.imported, 0);
      expect(outcome.deduplicated, 1);
    });

    test('a local partial does swallow a partial Tautulli view', () async {
      await local('$_machine:1', 0.4, type: 'partial');
      final access = _FakeAccess(rows: [_entry(rowId: 1, daysAgo: 0, watchedStatus: 0, percentComplete: 60)]);
      final outcome = await importer(access, _FakeClient({'1': _item('1')})).sync();
      expect(outcome!.deduplicated, 1);
    });
  });
```

`_entry(daysAgo: 0)` geeft `date = _now` in seconden; de lokale rij ligt een uur eerder, binnen het venster.

Run: `flutter test test/services/recommendations/tautulli_history_importer_test.dart --plain-name "cross-source window"`
Expected: de eerste test FAIL (imported 0), de andere twee PASS.

- [ ] **Step 6: Importer vergelijkt gewichten**

`lib/database/app_database.dart`, `localPositiveInteractionsIn` geeft voortaan gewicht mee:

```dart
  Future<Map<String, List<({int at, double weight})>>> localPositiveInteractionsIn(
    String profileId,
    Set<String> globalKeys,
    int fromMs,
    int toMs,
  ) async {
    if (globalKeys.isEmpty) return const {};
    final rows = await (select(mediaInteractions)..where(
          (t) =>
              t.profileId.equals(profileId) &
              t.source.equals(kInteractionSourceLocal) &
              t.eventWeight.isBiggerThanValue(0) &
              t.globalKey.isIn(globalKeys.toList()) &
              t.occurredAt.isBetweenValues(fromMs, toMs),
        ))
        .get();
    final out = <String, List<({int at, double weight})>>{};
    for (final row in rows) {
      out.putIfAbsent(row.globalKey, () => []).add((at: row.occurredAt, weight: row.eventWeight));
    }
    return out;
  }
```

`tautulli_history_importer.dart` regel 659-690: de lokale lookup heet nu `localPlays` met records; de check wordt

```dart
      final signal = _signalFor(e);
      final nearbyLocal = matchKey == null ? null : localPlays[matchKey];
      if (nearbyLocal != null &&
          nearbyLocal.any((l) => (l.at - atMs).abs() <= windowMs && l.weight >= signal.weight)) {
        // Pleya already recorded this view with at least this much weight. A
        // local partial is not proof of a completed view elsewhere, so it does
        // not count here; a rewatch days later falls outside the window.
        deduplicated++;
        continue;
      }
```

waarbij `_signalFor(e)` de bestaande functie is die `(type, weight)` teruggeeft (regel 777); haal hem hier één keer aan en geef het resultaat door aan `_companionFor` als die hem nu zelf aanroept.

Run: `flutter test test/services/recommendations/tautulli_history_importer_test.dart test/services/recommendations/interaction_recorder_test.dart test/services/recommendations/import_scoping_test.dart`
Expected: PASS.

- [ ] **Step 7: Gate en commit**

Run: `scripts/ci_checks.sh`
Expected: groen.

```bash
git add lib/utils/watch_state_notifier.dart lib/services/playback_progress_tracker.dart lib/services/recommendations/interaction_recorder.dart lib/services/recommendations/tautulli_history_importer.dart lib/database/app_database.dart test/services/recommendations/interaction_recorder_test.dart test/services/recommendations/tautulli_history_importer_test.dart docs/recommendations-register.md
git commit -m "feat(smaak): partieel signaal bij een eindstop, importer vergelijkt gewichten"
```

---

### Task 5: Related hubs van seeds vier tot zes als kandidatenlaag

`mechanisch`

**Files:**
- Modify: `lib/providers/discover_provider.dart` (`_loadBecauseYouWatched`, `_loadPersonalizedRows`, nieuw veld `_seedCandidates`)
- Test: `test/providers/discover_provider_test.dart`

**Interfaces:**
- Consumes: `_seedsFromLog` (Taak 3, levert tot zes seeds), `RecommendationService.buildRows(hubItems:)`.
- Produces: `List<MediaItem> _seedCandidates` in `DiscoverProvider`, meegegeven als `hubItems` en niet als `excludeKeys`.

- [ ] **Step 1: Falende test**

In de groep `'seed rows from the interaction log'`:

```dart
    test('seeds four to six feed the candidate pool, not the rows', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final ids = ['s1', 's2', 's3', 's4', 's5', 's6'];
      client.itemsById = {for (final id in ids) id: movie(id)};
      client.relatedByItem = {
        for (final id in ids) id: [_hub('rel-$id', items: [movie('$id-a'), movie('$id-b'), movie('$id-c')])],
      };
      final service = _FakeRecommendationService()
        ..seeds = [
          for (var i = 0; i < ids.length; i++)
            RecommendationSeed(globalKey: 'server_1:${ids[i]}', completed: true, occurredAtMs: now - i * 1000),
        ];
      final p = await loadWith(service, [client]);
      addTearDown(p.dispose);

      expect(p.hubs.where((h) => h.identifier == 'home.becauseyouwatched'), hasLength(3));
      final candidateIds = service.lastHubItems.map((i) => i.id).toSet();
      expect(candidateIds, containsAll(['s4-a', 's5-a', 's6-a']));
      expect(candidateIds, isNot(contains('s1-a')), reason: 'a shown seed row is excluded, not a candidate');
    });
```

Run: `flutter test test/providers/discover_provider_test.dart --plain-name "seeds four to six"`
Expected: FAIL.

- [ ] **Step 2: Implementatie**

`lib/providers/discover_provider.dart`: veld naast `_seedHubs`:

```dart
  /// Related titles of the seeds that did not get a row (positions four to
  /// six). Free candidates for the personalized rows, never shown as a row.
  List<MediaItem> _seedCandidates = [];
```

In `_loadBecauseYouWatched`, na het bouwen van `rows`:

```dart
      final extraRelated = await Future.wait([
        for (final seed in seeds.skip(3).take(3))
          _multiServer
                  .getClientForServer(ServerId(seed.item.serverId!))
                  ?.fetchRelatedHubs(seed.item.id)
                  .catchError((Object _) => const <MediaHub>[]) ??
              Future.value(const <MediaHub>[]),
      ]);
      if (isDisposed || generation != _loadGeneration) return;
      _seedCandidates = [
        for (final hubs in extraRelated)
          for (final hub in hubs)
            for (final item in hub.items)
              if (!item.isWatched) item,
      ];
```

(`seed.item.serverId` is niet null: `_seedsFromLog` en `_seedsFromServers` filteren daarop.) In `_loadPersonalizedRows` wordt de aanroep:

```dart
      final rows = clients.isEmpty
          ? const <MediaHub>[]
          : await service.buildRows(clients, hubItems: [...onScreen, ..._seedCandidates], excludeKeys: excludeKeys);
```

`excludeKeys` blijft alleen `onScreen`.

- [ ] **Step 3: Draai, gate, commit**

Run: `flutter test test/providers/discover_provider_test.dart`
Expected: PASS.
Run: `scripts/ci_checks.sh`
Expected: groen.

```bash
git add lib/providers/discover_provider.dart test/providers/discover_provider_test.dart docs/recommendations-register.md
git commit -m "feat(smaak): related hubs van seeds vier tot zes voeden de kandidatenpool"
```

---

### Task 6: Jellyfin-geschiedenisimport

`mechanisch` (groot, maar backend en volledig door tests gedekt; geen zichtbare rijwijziging).

**Files:**
- Modify: `lib/database/app_database.dart:62-63` (constante `kInteractionSourceJellyfin`)
- Modify: `lib/services/jellyfin_client/parts/browse.dart` (na `fetchRecentlyWatched`, regel 1650)
- Modify: `lib/services/jellyfin_client.dart:80` (implements `JellyfinHistorySource`)
- Create: `lib/services/recommendations/history_importer.dart`
- Create: `lib/services/recommendations/jellyfin_history_importer.dart`
- Modify: `lib/services/recommendations/tautulli_history_importer.dart:207` (`implements HistoryImporter`)
- Modify: `lib/services/recommendations/recommendation_service.dart` (`historyImporters`, loop in `_syncImportedHistory`)
- Modify: `lib/navigation/profile_session_screen.dart:292-345`
- Create: `test/services/recommendations/jellyfin_history_importer_test.dart`

**Interfaces:**
- Consumes: `kPartialWeight`, `kPartialPercent`, `kCrossSourceWindow`, `AppDatabase.localPositiveInteractionsIn`, `insertImportedInteractions`, `getHistorySyncCursor`, `upsertHistorySyncCursor`, `TautulliImportOutcome`.
- Produces:

```dart
abstract interface class HistoryImporter { Future<TautulliImportOutcome?> sync(); }

abstract interface class JellyfinHistorySource {
  ServerId get serverId;
  Future<List<MediaItem>> fetchPlayedHistoryPage({required int startIndex, int limit});
  Future<List<MediaItem>> fetchResumableItems({int limit});
  Future<MediaItem?> fetchItem(String id, {bool useCache});
}

class JellyfinHistoryImporter implements HistoryImporter {
  JellyfinHistoryImporter({required AppDatabase database, required String profileId, required JellyfinHistorySource source, required bool Function() isCurrentProfile, int Function()? clock, int maxPagesFirstRun = 5});
}
```

`RecommendationService({List<HistoryImporter> Function()? historyImporters})`.

- [ ] **Step 1: Falende importertest**

`test/services/recommendations/jellyfin_history_importer_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/recommendations/jellyfin_history_importer.dart';

const _profile = 'profile-a';
const _server = 'jf-1';
final _now = DateTime.now().millisecondsSinceEpoch;
int _secondsAgo(int days) => (_now - days * Duration.millisecondsPerDay) ~/ 1000;

class _FakeSource implements JellyfinHistorySource {
  List<MediaItem> played;
  List<MediaItem> resumable;
  final Map<String, MediaItem> items;
  int pageCalls = 0;
  _FakeSource({this.played = const [], this.resumable = const [], this.items = const {}});

  @override
  ServerId get serverId => ServerId(_server);

  @override
  Future<List<MediaItem>> fetchPlayedHistoryPage({required int startIndex, int limit = 200}) async {
    pageCalls++;
    return played.skip(startIndex).take(limit).toList();
  }

  @override
  Future<List<MediaItem>> fetchResumableItems({int limit = 100}) async => resumable.take(limit).toList();

  @override
  Future<MediaItem?> fetchItem(String id, {bool useCache = true}) async => items[id];
}

MediaItem _movie(String id, {required int lastViewedDaysAgo, int? viewOffsetMs, int? durationMs, int viewCount = 1}) =>
    MediaItem.jellyfin(
      id: id,
      kind: MediaKind.movie,
      serverId: _server,
      title: id,
      genres: const ['Drama'],
      year: 2019,
      viewCount: viewCount,
      lastViewedAt: _secondsAgo(lastViewedDaysAgo),
      viewOffsetMs: viewOffsetMs,
      durationMs: durationMs,
    );

MediaItem _episode(String id, {required String showId, required int lastViewedDaysAgo}) => MediaItem.jellyfin(
  id: id, kind: MediaKind.episode, serverId: _server, title: id, grandparentId: showId,
  viewCount: 1, lastViewedAt: _secondsAgo(lastViewedDaysAgo),
);

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  JellyfinHistoryImporter importer(_FakeSource source, {int maxPagesFirstRun = 5}) => JellyfinHistoryImporter(
    database: db,
    profileId: _profile,
    source: source,
    isCurrentProfile: () => true,
    clock: () => _now,
    maxPagesFirstRun: maxPagesFirstRun,
  );

  test('played films become completed rows with a stable event id', () async {
    final source = _FakeSource(played: [_movie('m1', lastViewedDaysAgo: 1), _movie('m2', lastViewedDaysAgo: 2)]);
    final outcome = await importer(source).sync();
    expect(outcome!.imported, 2);
    final rows = await db.getMediaInteractions(_profile);
    expect(rows.map((r) => r.source).toSet(), {'jellyfin'});
    expect(rows.map((r) => r.eventWeight).toSet(), {1.0});
    expect(rows.map((r) => r.sourceEventId), everyElement(startsWith('jellyfin:$_server:')));
    expect(rows.map((r) => r.sourceServerId).toSet(), {_server});
  });

  test('a second sync imports nothing new and stops at the watermark', () async {
    final source = _FakeSource(played: [_movie('m1', lastViewedDaysAgo: 1)]);
    await importer(source).sync();
    source.pageCalls = 0;
    final outcome = await importer(source).sync();
    expect(outcome!.imported, 0);
    expect(source.pageCalls, 1, reason: 'the first page already reaches the watermark');
  });

  test('an episode rolls up to its series for features and the series key', () async {
    final show = MediaItem.jellyfin(id: 'show', kind: MediaKind.show, serverId: _server, title: 'Show', genres: const ['Sci-Fi']);
    final source = _FakeSource(played: [_episode('e1', showId: 'show', lastViewedDaysAgo: 1)], items: {'show': show});
    await importer(source).sync();
    final row = (await db.getMediaInteractions(_profile)).single;
    expect(row.seriesKey, '$_server:show');
    expect(row.genresJson, '["Sci-Fi"]');
  });

  test('a resumable item between 50 and 90 percent is one partial row, also after three syncs', () async {
    final source = _FakeSource(resumable: [_movie('r1', lastViewedDaysAgo: 0, viewCount: 0, viewOffsetMs: 60 * 60000, durationMs: 100 * 60000)]);
    await importer(source).sync();
    source.resumable = [_movie('r1', lastViewedDaysAgo: 0, viewCount: 0, viewOffsetMs: 70 * 60000, durationMs: 100 * 60000)];
    await importer(source).sync();
    await importer(source).sync();
    final rows = await db.getMediaInteractions(_profile);
    expect(rows, hasLength(1));
    expect(rows.single.eventType, 'partial');
    expect(rows.single.eventWeight, 0.4);
  });

  test('a resumable item under 50 percent is ignored', () async {
    final source = _FakeSource(resumable: [_movie('r1', lastViewedDaysAgo: 0, viewCount: 0, viewOffsetMs: 10 * 60000, durationMs: 100 * 60000)]);
    await importer(source).sync();
    expect(await db.getMediaInteractions(_profile), isEmpty);
  });

  test('a local completed view an hour earlier suppresses the import of the same title', () async {
    await db.insertMediaInteraction(
      MediaInteractionsCompanion.insert(
        profileId: _profile, globalKey: '$_server:m1', mediaKind: 'movie', eventType: 'completed', eventWeight: 1.0,
        occurredAt: _now - Duration.millisecondsPerHour,
      ),
      profileId: _profile,
    );
    final source = _FakeSource(played: [_movie('m1', lastViewedDaysAgo: 0)]);
    final outcome = await importer(source).sync();
    expect(outcome!.deduplicated, 1);
    expect(outcome.imported, 0);
  });

  test('the first run reads at most maxPagesFirstRun pages', () async {
    final source = _FakeSource(played: [for (var i = 0; i < 700; i++) _movie('m$i', lastViewedDaysAgo: i % 300)]);
    await importer(source, maxPagesFirstRun: 2).sync();
    expect(source.pageCalls, 2);
  });
}
```

`MediaItem.jellyfin(...)`: controleer met `rg -n "factory MediaItem.jellyfin" lib/media/media_item.dart` dat die factory bestaat en dezelfde named parameters neemt als `MediaItem.plex`; anders `MediaItem(id:, backend: MediaBackend.jellyfin, kind:, serverId:, …)`.

Run: `flutter test test/services/recommendations/jellyfin_history_importer_test.dart`
Expected: FAIL, bestand ontbreekt.

- [ ] **Step 2: Interfaces en constante**

`lib/services/recommendations/history_importer.dart`:

```dart
import 'tautulli_history_importer.dart' show TautulliImportOutcome;

/// One external history source feeding [MediaInteractions]. The outcome type
/// is shared with the Tautulli importer so the service treats both the same.
abstract interface class HistoryImporter {
  Future<TautulliImportOutcome?> sync();
}
```

`TautulliHistoryImporter` krijgt `implements HistoryImporter`. `lib/database/app_database.dart` regel 63: `const String kInteractionSourceJellyfin = 'jellyfin';`.

- [ ] **Step 3: Jellyfin-bron**

`lib/services/recommendations/jellyfin_history_importer.dart` begint met:

```dart
/// What the importer needs from a Jellyfin connection. The client implements
/// it; tests hand in a fake.
abstract interface class JellyfinHistorySource {
  ServerId get serverId;

  /// This user's played films and episodes, newest play first.
  Future<List<MediaItem>> fetchPlayedHistoryPage({required int startIndex, int limit});

  /// Titles this user stopped partway, with position and duration.
  Future<List<MediaItem>> fetchResumableItems({int limit});

  Future<MediaItem?> fetchItem(String id, {bool useCache});
}
```

`lib/services/jellyfin_client/parts/browse.dart`, na `fetchRecentlyWatched`:

```dart
  @override
  Future<List<MediaItem>> fetchPlayedHistoryPage({required int startIndex, int limit = 200}) async {
    final items = await _safeFetchItemsArray('/Items', {
      'userId': connection.userId,
      'Recursive': 'true',
      'IncludeItemTypes': 'Movie,Episode',
      'Filters': 'IsPlayed',
      'SortBy': 'DatePlayed',
      'SortOrder': 'Descending',
      'StartIndex': startIndex.toString(),
      'Limit': limit.toString(),
      'Fields': _browseFields,
      ...jellyfinImageQueryParameters,
    });
    return _mapItems(items);
  }

  @override
  Future<List<MediaItem>> fetchResumableItems({int limit = 100}) async {
    final items = await _safeFetchItemsArray('/Items', {
      'userId': connection.userId,
      'Recursive': 'true',
      'IncludeItemTypes': 'Movie,Episode',
      'Filters': 'IsResumable',
      'Limit': limit.toString(),
      'Fields': _browseFields,
      ...jellyfinImageQueryParameters,
    });
    return _mapItems(items);
  }
```

`lib/services/jellyfin_client.dart` regel 80: `class JellyfinClient ... implements JellyfinHistorySource` erbij (naast wat er al staat). `fetchItem` en `serverId` bestaan al.

- [ ] **Step 4: De importer**

Rest van `jellyfin_history_importer.dart`:

```dart
const String _kSource = kInteractionSourceJellyfin;
const int kJellyfinPageLength = 200;
const int kJellyfinResumeLimit = 100;

/// Imports one Jellyfin user's own history into [MediaInteractions].
///
/// No admin credential and no binding: the connection is the profile's own,
/// so every row is the profile's. A played item becomes `completed`, a
/// resumable one between [kPartialPercent] and 90 percent becomes `partial`
/// once (its event id has no position in it, so a title that keeps being
/// resumed stays one row until it is finished).
///
/// ponytail: forward-only. The watermark is the newest `LastPlayedDate` seen;
/// the first run reads at most [maxPagesFirstRun] pages. Anything older than
/// that is left out on purpose: the profile cap of 5000 rows would prune it
/// anyway. Add a backfill cursor like the Tautulli importer's if a real
/// profile turns out to need history beyond the first thousand plays.
class JellyfinHistoryImporter implements HistoryImporter {
  final AppDatabase _db;
  final String _profileId;
  final JellyfinHistorySource _source;
  final bool Function() _isCurrentProfile;
  final int Function() _nowMs;
  final int _maxPagesFirstRun;

  JellyfinHistoryImporter({
    required AppDatabase database,
    required String profileId,
    required JellyfinHistorySource source,
    required bool Function() isCurrentProfile,
    int Function()? clock,
    int maxPagesFirstRun = 5,
  }) : _db = database,
       _profileId = profileId,
       _source = source,
       _isCurrentProfile = isCurrentProfile,
       _nowMs = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       _maxPagesFirstRun = maxPagesFirstRun;

  String get _serverId => _source.serverId.toString();

  @override
  Future<TautulliImportOutcome?> sync() async {
    if (_profileId.isEmpty || !_isCurrentProfile()) return null;
    try {
      final cursor = await _db.getHistorySyncCursor(_profileId, _serverId, _kSource);
      final watermarkMs = cursor?.forwardCursorAt ?? 0;
      final firstRun = cursor == null;

      final played = <MediaItem>[];
      var start = 0;
      var pages = 0;
      var reachedWatermark = false;
      while (!reachedWatermark && (firstRun ? pages < _maxPagesFirstRun : true)) {
        final page = await _source.fetchPlayedHistoryPage(startIndex: start, limit: kJellyfinPageLength);
        pages++;
        for (final item in page) {
          final at = (item.lastViewedAt ?? 0) * 1000;
          if (at <= watermarkMs) {
            reachedWatermark = true;
            break;
          }
          played.add(item);
        }
        if (page.length < kJellyfinPageLength) break;
        start += kJellyfinPageLength;
        if (!firstRun && pages >= _maxPagesFirstRun) break; // a bounded catch-up, never a full crawl
      }
      final resumable = await _source.fetchResumableItems(limit: kJellyfinResumeLimit);

      final candidates = <_Candidate>[
        for (final item in played)
          if (item.lastViewedAt != null)
            _Candidate(item: item, type: 'completed', weight: 1.0, atMs: item.lastViewedAt! * 1000,
                eventId: '$_kSource:$_serverId:${item.id}:${item.lastViewedAt}'),
        for (final item in resumable)
          if (_partialPercent(item) case final percent? when percent >= kPartialPercent && percent < 90)
            _Candidate(item: item, type: 'partial', weight: kPartialWeight, atMs: _nowMs(),
                eventId: '$_kSource:$_serverId:${item.id}:resume', completionPercent: percent),
      ];
      if (candidates.isEmpty) {
        await _saveCursor(watermarkMs);
        return const TautulliImportOutcome();
      }

      final existing = await _db.existingImportedEventIds(_profileId, {for (final c in candidates) c.eventId});
      final fresh = candidates.where((c) => !existing.contains(c.eventId)).toList();

      final features = <String, MediaItem>{};
      for (final c in fresh) {
        final key = c.featureItemId;
        if (features.containsKey(key)) continue;
        features[key] = key == c.item.id ? c.item : (await _source.fetchItem(key) ?? c.item);
      }

      final windowMs = kCrossSourceWindow.inMilliseconds;
      final atValues = fresh.map((c) => c.atMs);
      final localPlays = fresh.isEmpty
          ? const <String, List<({int at, double weight})>>{}
          : await _db.localPositiveInteractionsIn(
              _profileId,
              {for (final c in fresh) c.globalKey(_source.serverId)},
              atValues.reduce(math.min) - windowMs,
              atValues.reduce(math.max) + windowMs,
            );

      var deduplicated = 0;
      final rows = <MediaInteractionsCompanion>[];
      var newest = watermarkMs;
      for (final c in fresh) {
        final globalKey = c.globalKey(_source.serverId);
        final nearby = localPlays[globalKey];
        if (nearby != null && nearby.any((l) => (l.at - c.atMs).abs() <= windowMs && l.weight >= c.weight)) {
          deduplicated++;
          continue;
        }
        final f = features[c.featureItemId]!;
        rows.add(
          MediaInteractionsCompanion.insert(
            profileId: _profileId,
            globalKey: globalKey,
            mediaKind: c.item.kind.id,
            eventType: c.type,
            eventWeight: c.weight,
            occurredAt: c.atMs,
            genresJson: Value(jsonEncode(f.genres ?? const [])),
            actorsJson: Value(jsonEncode([for (final r in f.roles?.take(5) ?? const <MediaRole>[]) r.tag])),
            directorsJson: Value(jsonEncode(f.directors ?? const [])),
            moodsJson: Value(jsonEncode(f.moods ?? const [])),
            studio: Value(f.studio),
            year: Value(f.year),
            communityRating: Value(f.rating),
            seriesKey: Value(c.item.kind == MediaKind.episode ? globalKey : null),
            source: const Value(_kSource),
            sourceEventId: Value(c.eventId),
            sourceServerId: Value(_serverId),
            completionPercent: Value(c.completionPercent),
          ),
        );
        if (c.type == 'completed' && c.atMs > newest) newest = c.atMs;
      }

      if (!_isCurrentProfile()) return null;
      if (rows.isNotEmpty) await _db.insertImportedInteractions(rows, profileId: _profileId);
      await _saveCursor(newest);
      return TautulliImportOutcome(imported: rows.length, deduplicated: deduplicated);
    } catch (e, s) {
      appLogger.w('JellyfinHistoryImporter: sync failed', error: e, stackTrace: s);
      return const TautulliImportOutcome(partial: true);
    }
  }

  Future<void> _saveCursor(int watermarkMs) => _db.upsertHistorySyncCursor(
    HistorySyncCursorsCompanion.insert(
      profileId: _profileId,
      serverId: _serverId,
      source: _kSource,
      forwardCursorAt: Value(watermarkMs),
      lastSyncAt: Value(_nowMs()),
    ),
  );

  static int? _partialPercent(MediaItem item) {
    final offset = item.viewOffsetMs;
    final duration = item.durationMs;
    if (offset == null || duration == null || duration <= 0) return null;
    return offset * 100 ~/ duration;
  }
}

class _Candidate {
  final MediaItem item;
  final String type;
  final double weight;
  final int atMs;
  final String eventId;
  final int? completionPercent;
  const _Candidate({required this.item, required this.type, required this.weight, required this.atMs, required this.eventId, this.completionPercent});

  /// An episode is evidence about its series, like the Tautulli importer and
  /// the recorder: the series is what the scorer groups on.
  String get featureItemId => item.kind == MediaKind.episode ? (item.grandparentId ?? item.id) : item.id;

  String globalKey(ServerId serverId) => buildGlobalKey(serverId, featureItemId);
}
```

Controleer de bestaande hulpfuncties voor je schrijft: `rg -n "existingImportedEventIds|Future<Set<String>>" lib/database/app_database.dart` (de Tautulli-importer vraagt vooraf welke event-ids bestaan; hergebruik die methode, en als hij anders heet, gebruik die naam). `MediaItem.viewOffsetMs`, `durationMs`, `lastViewedAt`, `grandparentId`, `roles`, `directors`, `moods`, `studio`, `year`, `rating`, `kind.id` bestaan (`media_item.dart:40-130`). Imports: `dart:convert`, `dart:math as math`, `package:drift/drift.dart show Value`, `../../database/app_database.dart`, `../../media/ids.dart`, `../../media/media_item.dart`, `../../media/media_kind.dart`, `../../media/media_role.dart`, `../../utils/app_logger.dart`, `../../utils/global_key_utils.dart`, `history_importer.dart`, `tautulli_history_importer.dart`.

Run: `flutter test test/services/recommendations/jellyfin_history_importer_test.dart`
Expected: PASS.

- [ ] **Step 5: Bedrading in de service en de sessie**

`recommendation_service.dart`: constructorparameter `List<HistoryImporter> Function()? historyImporters` en veld `_historyImporters`. In `_syncImportedHistory`, na de Tautulli-lus:

```dart
    for (final importer in _historyImporters?.call() ?? const <HistoryImporter>[]) {
      try {
        final outcome = await importer.sync();
        changed = changed || (outcome?.changedAnything ?? false);
      } catch (e, s) {
        appLogger.w('RecommendationService: own-history sync failed', error: e, stackTrace: s);
      }
    }
```

en de guard `if (factory == null) return false;` wordt `if (factory == null && _historyImporters == null) return false;` met de Tautulli-lus achter `if (factory != null)`. De typedef `TautulliImporterFactory` mag `HistoryImporter?` teruggeven; `_FakeImporter implements TautulliHistoryImporter` in de servicetest blijft geldig.

`profile_session_screen.dart`, in de `RecommendationService(...)`-constructie:

```dart
                    historyImporters: () => [
                      for (final client in multiServer.serverManager.onlineClients.values)
                        if (client is JellyfinClient)
                          JellyfinHistoryImporter(
                            database: database,
                            profileId: profileId,
                            source: client,
                            isCurrentProfile: () => activeProfile.activeId == profileId,
                          ),
                    ],
```

- [ ] **Step 6: Volledige recommendations-map, gate, commit**

Run: `flutter test test/services/recommendations/ test/providers/discover_provider_test.dart`
Expected: PASS.
Run: `scripts/ci_checks.sh`
Expected: groen (let op `check-unused-code`: `kJellyfinResumeLimit` en `kJellyfinPageLength` worden gebruikt).

```bash
git add lib/database/app_database.dart lib/services/jellyfin_client.dart lib/services/jellyfin_client/parts/browse.dart lib/services/recommendations/history_importer.dart lib/services/recommendations/jellyfin_history_importer.dart lib/services/recommendations/tautulli_history_importer.dart lib/services/recommendations/recommendation_service.dart lib/navigation/profile_session_screen.dart test/services/recommendations/jellyfin_history_importer_test.dart docs/recommendations-register.md
git commit -m "feat(smaak): Jellyfin-kijkgeschiedenis als tweede adapter op het interactielog"
```

---

### Task 7: Acteurs- of regisseursrij met gedeelde cap

`oordeel`: bepaalt welke twee affiniteitsrijen een warm profiel ziet.

**Files:**
- Modify: `lib/services/recommendations/personalized_rows_builder.dart:7-13, 61-77`
- Modify: `lib/navigation/profile_session_screen.dart:307-311`
- Modify: `lib/i18n/nl.i18n.json:845`, `lib/i18n/en.i18n.json:845`
- Test: `test/services/recommendations/personalized_rows_builder_test.dart`, `test/services/recommendations/recommendation_service_test.dart` (alleen de `_titles`-constante)

**Interfaces:**
- Consumes: `AffinityVector.topFeatures`, `AffinityVector.of`.
- Produces: `PersonalizedRowTitles({..., required String Function(String name) moreWithActor, required String Function(String name) moreFromDirector})`; `const int kMaxAffinityRows = 2; const double kPersonFeatureThreshold = 0.7;`; rij-ids `home.becauselike.actor.<slug>` en `home.becauselike.director.<slug>`; `t.discover.moreWithActor(name:)`, `t.discover.moreFromDirector(name:)`.

- [ ] **Step 1: Falende builder-tests**

In `test/services/recommendations/personalized_rows_builder_test.dart`, `_titles` wordt:

```dart
final _titles = PersonalizedRowTitles(
  topPicks: 'Top Picks',
  becauseYouLike: (g) => 'Because you like $g',
  hiddenGems: 'Hidden Gems',
  moreWithActor: (n) => 'More with $n',
  moreFromDirector: (n) => 'More from $n',
);
```

`_movie` krijgt `List<String> actors = const []` en `roles: [for (final a in actors) MediaRole(tag: a)]` (import `package:pleya/media/media_role.dart`). Nieuwe tests:

```dart
  AffinityVector _warmTaste({List<String> genres = const ['Sci-Fi'], List<String> actors = const [], List<String> directors = const []}) =>
      AffinityVector.build([
        for (var i = 0; i < 12; i++) TasteEvent(weight: 1.0, occurredAtMs: _nowMs, evidenceKey: 't$i', genres: genres, actors: actors, directors: directors),
      ], nowMs: _nowMs);

  test('a strong actor gets a row named after the server spelling of the name', () {
    final pool = [for (var i = 0; i < 6; i++) _movie(id: 'h$i', actors: const ['Tom Hanks'], rating: 7)];
    final rows = buildPersonalizedRows(_warmTaste(genres: const [], actors: const ['Tom Hanks']), pool, titles: _titles, nowMs: _nowMs);
    final row = rows.singleWhere((r) => r.id.startsWith('home.becauselike.actor.'));
    expect(row.id, 'home.becauselike.actor.tom-hanks');
    expect(row.title, 'More with Tom Hanks');
  });

  test('genre, actor and director share two slots; genre wins a tie', () {
    final pool = [
      for (var i = 0; i < 6; i++) _movie(id: 'a$i', genres: const ['Sci-Fi', 'Drama'], actors: const ['Tom Hanks'], rating: 7),
    ];
    // Every event carries both genres, one actor and one director: all four
    // features normalize to 1.0, so the tie-break decides.
    final taste = AffinityVector.build([
      for (var i = 0; i < 12; i++)
        TasteEvent(weight: 1.0, occurredAtMs: _nowMs, evidenceKey: 't$i', genres: const ['Sci-Fi', 'Drama'], actors: const ['Tom Hanks'], directors: const ['Ridley Scott']),
    ], nowMs: _nowMs);
    final rows = buildPersonalizedRows(taste, pool, titles: _titles, nowMs: _nowMs);
    final affinity = rows.where((r) => r.id.startsWith('home.becauselike.')).map((r) => r.id).toList();
    expect(affinity, hasLength(2));
    expect(affinity, everyElement(isNot(contains('.actor.'))), reason: 'two genres at 1.0 beat the actor at 1.0');
  });

  test('a strong actor beats a weak second genre', () {
    final pool = [
      for (var i = 0; i < 6; i++) _movie(id: 'a$i', genres: const ['Sci-Fi'], actors: const ['Tom Hanks'], rating: 7),
      for (var i = 0; i < 6; i++) _movie(id: 'd$i', genres: const ['Drama'], rating: 7),
    ];
    final taste = AffinityVector.build([
      for (var i = 0; i < 10; i++) TasteEvent(weight: 1.0, occurredAtMs: _nowMs, evidenceKey: 's$i', genres: const ['Sci-Fi'], actors: const ['Tom Hanks']),
      for (var i = 0; i < 6; i++) TasteEvent(weight: 1.0, occurredAtMs: _nowMs, evidenceKey: 'd$i', genres: const ['Drama']),
    ], nowMs: _nowMs);
    final rows = buildPersonalizedRows(taste, pool, titles: _titles, nowMs: _nowMs);
    final affinity = rows.where((r) => r.id.startsWith('home.becauselike.')).map((r) => r.id).toList();
    expect(affinity, ['home.becauselike.sci-fi', 'home.becauselike.actor.tom-hanks']);
  });

  test('a cold taste gets no person row', () {
    final pool = [for (var i = 0; i < 6; i++) _movie(id: 'h$i', actors: const ['Tom Hanks'], rating: 8)];
    final rows = buildPersonalizedRows(AffinityVector.empty, pool, titles: _titles, nowMs: _nowMs);
    expect(rows.any((r) => r.id.contains('.actor.')), isFalse);
  });
```

In de derde test is Drama 6/10 = 0,6 na normalisatie op Sci-Fi (1,0); Tom Hanks is 1,0 binnen de acteursdimensie. Verwacht: genre Sci-Fi, dan acteur. Controleer dat het bestaande genre-rij-id `home.becauselike.sci-fi` is (genre lowercased door `_norm`); de bestaande test `'warm taste emits a Because-you-like genre row'` verwacht de titel `'Because you like Sci-fi'`, dat blijft.

Run: `flutter test test/services/recommendations/personalized_rows_builder_test.dart`
Expected: FAIL op `moreWithActor`.

- [ ] **Step 2: Builder**

`personalized_rows_builder.dart`:

```dart
class PersonalizedRowTitles {
  final String topPicks;
  final String Function(String genre) becauseYouLike;
  final String hiddenGems;
  final String Function(String name) moreWithActor;
  final String Function(String name) moreFromDirector;

  const PersonalizedRowTitles({
    required this.topPicks,
    required this.becauseYouLike,
    required this.hiddenGems,
    required this.moreWithActor,
    required this.moreFromDirector,
  });
}

/// Genre, actor and director rows share these slots, so a warm profile never
/// gets more personalized rows than before this row existed.
const int kMaxAffinityRows = 2;

/// Persons need more than genres. The vector normalizes each dimension to its
/// strongest feature, so the top actor and the top genre both read 1.0 no
/// matter how much evidence sits under them; the higher bar and the tie-break
/// towards genre are the compensation.
const double kPersonFeatureThreshold = 0.7;
```

Het blok `if (taste.isWarm) { ... }` wordt:

```dart
  if (taste.isWarm) {
    final candidates = <({String dim, String feature, double weight})>[
      for (final g in taste.topFeatures('genre', threshold: 0.5, limit: 2)) (dim: 'genre', feature: g, weight: taste.of('genre', g)),
      for (final a in taste.topFeatures('actor', threshold: kPersonFeatureThreshold, limit: 1)) (dim: 'actor', feature: a, weight: taste.of('actor', a)),
      for (final d in taste.topFeatures('director', threshold: kPersonFeatureThreshold, limit: 1)) (dim: 'director', feature: d, weight: taste.of('director', d)),
    ]..sort((a, b) {
      final byWeight = b.weight.compareTo(a.weight);
      return byWeight != 0 ? byWeight : _dimRank(a.dim).compareTo(_dimRank(b.dim));
    });

    final usedInAffinityRows = <String>{};
    var emitted = 0;
    for (final c in candidates) {
      if (emitted >= kMaxAffinityRows) break;
      final matches = byScore.where((i) => _matches(i, c.dim, c.feature) && usedInAffinityRows.add(i.globalKey)).toList();
      if (matches.length < minRowItems) continue;
      rows.add(switch (c.dim) {
        'genre' => row('home.becauselike.${c.feature}', titles.becauseYouLike(_titleCase(c.feature)), matches),
        'actor' => row('home.becauselike.actor.${_slug(c.feature)}', titles.moreWithActor(_displayName(matches, c.feature)), matches),
        _ => row('home.becauselike.director.${_slug(c.feature)}', titles.moreFromDirector(_displayName(matches, c.feature)), matches),
      });
      emitted++;
    }
  }
```

met onderaan:

```dart
int _dimRank(String dim) => switch (dim) { 'genre' => 0, 'actor' => 1, _ => 2 };

String _n(String s) => s.trim().toLowerCase();

bool _matches(MediaItem item, String dim, String feature) => switch (dim) {
  'genre' => (item.genres ?? const []).any((g) => _n(g) == feature),
  'actor' => (item.roles?.take(5) ?? const <MediaRole>[]).any((r) => _n(r.tag) == feature),
  _ => (item.directors ?? const []).any((d) => _n(d) == feature),
};

String _slug(String feature) => feature.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

/// The name as the server spells it, from the first item that carries it.
/// The vector only knows the lowercased key.
String _displayName(List<MediaItem> matches, String feature) {
  for (final item in matches) {
    for (final r in item.roles ?? const <MediaRole>[]) {
      if (_n(r.tag) == feature) return r.tag;
    }
    for (final d in item.directors ?? const []) {
      if (_n(d) == feature) return d;
    }
  }
  return feature;
}
```

Import `../../media/media_role.dart`. Het bestaande `usedInGenreRows` verdwijnt in `usedInAffinityRows`.

- [ ] **Step 3: Titels en i18n**

`en.i18n.json` na regel 845: `"moreWithActor": "More with ${name}",` en `"moreFromDirector": "More from ${name}",`. `nl.i18n.json`: `"moreWithActor": "Meer met ${name}",` en `"moreFromDirector": "Meer van ${name}",`. Run: `dart run slang`.

`profile_session_screen.dart:307-311`:

```dart
                    titles: PersonalizedRowTitles(
                      topPicks: t.discover.topPicksForYou,
                      becauseYouLike: (genre) => t.discover.becauseYouLike(genre: genre),
                      hiddenGems: t.discover.hiddenGems,
                      moreWithActor: (name) => t.discover.moreWithActor(name: name),
                      moreFromDirector: (name) => t.discover.moreFromDirector(name: name),
                    ),
```

`recommendation_service_test.dart` regel 18-22: dezelfde twee velden toevoegen aan `_titles`.

- [ ] **Step 4: Draai, gate, commit**

Run: `flutter test test/services/recommendations/`
Expected: PASS.
Run: `scripts/ci_checks.sh`
Expected: groen.

```bash
git add lib/services/recommendations/personalized_rows_builder.dart lib/navigation/profile_session_screen.dart lib/i18n/nl.i18n.json lib/i18n/en.i18n.json lib/i18n/strings.g.dart lib/i18n/strings_nl.g.dart lib/i18n/strings_en.g.dart test/services/recommendations/personalized_rows_builder_test.dart test/services/recommendations/recommendation_service_test.dart docs/recommendations-register.md
git commit -m "feat(home): rij Meer met acteur of Meer van regisseur bij warme smaak"
```

---

### Task 8: i18n-controle, layoutblok en de rijtitel op het scherm

`oordeel`: dit is wat de gebruiker leest op Home en in Home aanpassen.

**Files:**
- Test: `test/providers/home_layout_provider_test.dart`
- Test: `test/screens/discover_screen_test.dart` (`_FakeMediaServerClient`, `_pumpTvDiscoverScreen`)
- Verify: `lib/i18n/*.i18n.json` (geen wijziging, alleen controle)

**Interfaces:**
- Consumes: `homeRowId`, `HomeLayoutProvider.apply`, `t.discover.becauseYouWatched`, `t.discover.becauseYouAreWatching`.
- Produces: niets nieuws in `lib/`; bewijs.

- [ ] **Step 1: i18n-controle**

Run: `for f in lib/i18n/*.i18n.json; do printf '%s %s\n' "$f" "$(rg -c 'becauseYouAreWatching|moreWithActor|moreFromDirector' "$f")"; done`
Expected: `nl` en `en` melden 3, alle andere 0 (fallback op Engels via `slang.yaml`).
Run: `rg -n "becauseYouAreWatching|moreWithActor|moreFromDirector" lib/i18n/strings_de.g.dart | head -3`
Expected: de gegenereerde Duitse klasse bevat de sleutels met de Engelse tekst.

- [ ] **Step 2: Falende layoutblok-test**

In `test/providers/home_layout_provider_test.dart`:

```dart
  test('one hidden because-you-watched id hides every seed row of that server', () async {
    final p = HomeLayoutProvider();
    final seedA = MediaHub(id: 'a', identifier: 'home.becauseyouwatched', title: 'Because you watched A', type: 'mixed', items: const [], size: 0, serverId: 's1');
    final seedB = MediaHub(id: 'b', identifier: 'home.becauseyouwatched', title: "Because you're watching B", type: 'mixed', items: const [], size: 0, serverId: 's1');
    final other = MediaHub(id: 'c', identifier: 'home.toppicks', title: 'Top Picks', type: 'mixed', items: const [], size: 0, serverId: 's1');
    await p.setRowHidden(homeRowId(seedA), true);

    final shown = p.apply([seedA, seedB, other], homeRowId);

    expect(shown.map((h) => h.id), ['c']);
  });
```

Controleer de signatuur van `apply` met `rg -n "apply\(" lib/providers/home_layout_provider.dart`; de bestaande tests in dit bestand tonen de aanroepvorm (regel 25-33). Als `apply` een `dropHidden`-parameter heeft, gebruik de default.

Run: `flutter test test/providers/home_layout_provider_test.dart --plain-name "hides every seed row"`
Expected: PASS meteen als het blokgedrag al klopt (dit is een pin, geen fix). Faalt hij, dan is `homeRowId` gewijzigd en is dat een bevinding voor het register.

- [ ] **Step 3: Falende widgettest op de rijtitel**

In `test/screens/discover_screen_test.dart`, `_FakeMediaServerClient` uitbreiden:

```dart
  _FakeMediaServerClient({this.hubs = const [], this.recentlyWatched = const [], this.related = const []});

  final List<MediaHub> hubs;
  final List<MediaItem> recentlyWatched;
  final List<MediaHub> related;

  @override
  Future<List<MediaItem>> fetchRecentlyWatched({int limit = 5}) async => recentlyWatched.take(limit).toList();

  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async => related;
```

(controleer hoe de constructor nu heet op regel 19-24 en behoud bestaande parameters.) `_pumpTvDiscoverScreen` krijgt een optionele parameter `List<MediaItem> recentlyWatched = const [], List<MediaHub> related = const []` die aan de fake wordt doorgegeven. Nieuwe test in de groep `'Home-focus baseline (TV)'` of een eigen groep:

```dart
  testWidgets('a seed row shows its reason as the rail label', (tester) async {
    MediaItem m(String id, {int viewCount = 0}) => MediaItem(
      id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: id, serverId: 'server_1', serverName: 'Server', viewCount: viewCount,
    );
    final seed = m('Severance', viewCount: 1);
    final related = MediaHub(id: 'rel', title: 'Related', type: 'movie', items: [m('a'), m('b'), m('c'), m('d')], size: 4, serverId: 'server_1');
    final harness = await _pumpTvDiscoverScreen(tester, recentlyWatched: [seed], related: [related]);
    await tester.pumpAndSettle();

    expect(find.text(t.discover.becauseYouWatched(title: 'Severance')), findsOneWidget);
    expect(find.text('Severance'), findsNothing, reason: 'the seed itself is not in its own row');
    harness.toString(); // keep the harness alive until the asserts ran
  });
```

Zonder `RecommendationService` in het harnas loopt de fallback (`_seedsFromServers`), wat precies het koude-startpad is. `t` komt uit `package:pleya/i18n/strings.g.dart` en staat al in de imports van dit bestand (het gebruikt `t.discover.continueWatching`).

Run: `flutter test test/screens/discover_screen_test.dart --plain-name "seed row shows its reason"`
Expected: FAIL tot de fake de twee methoden heeft; daarna PASS. Blijft hij rood omdat de TV-projectie de rijtitel anders rendert (bijvoorbeeld met een suffix), pas de matcher aan naar `find.textContaining('Severance')` op het raillabel en noteer waarom.

- [ ] **Step 4: Draai, gate, commit**

Run: `flutter test test/providers/home_layout_provider_test.dart test/screens/discover_screen_test.dart`
Expected: PASS.
Run: `scripts/ci_checks.sh`
Expected: groen.

```bash
git add test/providers/home_layout_provider_test.dart test/screens/discover_screen_test.dart docs/recommendations-register.md
git commit -m "test(home): rijtitel van een seed-rij en het verbergblok van Omdat je X keek"
```

---

### Task 9: Volledige suite, gate, Verify-regressie en register

`mechanisch`

**Files:**
- Modify: `docs/recommendations-register.md`
- Evidence buiten de boom: `/tmp/pleya-verify/<datum>/` (bundels)

**Interfaces:**
- Consumes: alles hiervoor.
- Produces: het register met SHA's en bewijsregels; de LIVE- en HARDWARE-rijen blijven open met de exacte ontbrekende meting.

- [ ] **Step 1: Volledige suite**

Run: `flutter test 2>&1 | tail -20`
Expected: `All tests passed!`. Bij een rode golden die niets met deze branch te maken heeft: noteer bestand en reden in het register, fix hem niet hier (CAT5 en GOLD4 zijn bekende stale goldens).

- [ ] **Step 2: Gate**

Run: `scripts/ci_checks.sh`
Expected: groen, inclusief `check-unused-code` (de dode `TautulliClient.users` en `ping` waren al aanwezig en blijven buiten dit werk).

- [ ] **Step 3: Verify-regressie op de fixture**

De fixture is een Pleya Server-fake zonder related-endpoint; deze runs bewijzen alleen dat een Pleya Server-only profiel geen rijen verliest (D2). Vanuit `pleya_verify/runner`:

Run: `dart run bin/verify.dart run ../scenarios/tvos.home.walk-rails.yaml --json | tee /tmp/pleya-verify/rec-tvos.json | tail -5`
Expected: `"status":"PASS"`.
Run: `dart run bin/verify.dart run ../scenarios/ios.home.northstar.yaml --json | tee /tmp/pleya-verify/rec-ios.json | tail -5`
Expected: `"status":"PASS"`.
Run: `dart run bin/verify.dart run ../scenarios/discover.layout.macos.yaml --json | tee /tmp/pleya-verify/rec-macos.json | tail -5`
Expected: `"status":"PASS"`. Kan macOS niet draaien (signing zonder profiel is een bekende oorzaak), schrijf dan exact die reden in het register en claim geen SIM CLOSED voor macOS.

Lees per bundel de snapshot van de tweede rail (bijvoorbeeld `01-second-rail`) en noteer welke rijtitel erop staat; verschijnt "Aanbevolen voor jou", dan is dat een meetpunt voor de Pleya Server-pool en komt het in het register.

- [ ] **Step 4: Register bijwerken**

In `docs/recommendations-register.md`: REC-1 tot en met REC-8 op `CODE CLOSED` met SHA (`git log --oneline -9`), REC-9 op `SIM CLOSED` per platform dat PASS gaf, de drie Verify-rijen met het bundelpad, en de LIVE- en HARDWARE-rijen met de zin wat er precies nog gemeten moet worden: "echt Plex-profiel met Tautulli en twee servers: detail op server B toont Plex-geschiedenis, geen Tautulli-kijkers; Home toont 'Omdat je X kijkt' voor de lopende serie" en "Apple TV: D-pad van de eerste rail naar de acteursrij en terug, focusherstel op de tegel".

- [ ] **Step 5: Commit**

```bash
git add docs/recommendations-register.md
git commit -m "docs: register aanbevelingen bijgewerkt na suite, gate en Verify-regressie"
```

Daarna: niets pushen zonder opdracht. Eén review van de hele branch met het sterkste model vóór een PR, conform de eenmansteam-regel.
