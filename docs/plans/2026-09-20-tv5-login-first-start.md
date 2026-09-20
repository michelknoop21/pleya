# TV5 Inloggen en Eerste Start Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** MOC-22 sluiten met een echte Apple TV-compositie voor eerste start en inloggen, zonder de bestaande
iOS- of macOS-authflow te veranderen. De oplevering bewijst de initiële Plex- en Jellyfin-keuze, QR-polling,
timeout, retry, Jellyfin-uitweg, succesvolle eerste-profielhandoff, profielpoort, startup bij gedeeltelijk of volledig
offline servers, Siri Remote-focus, systeemtekstinvoer en toegestane terugnavigatie.

**Architecture:** `PlexPinAuthFlow` blijft de enige eigenaar van Plex PIN-creatie, QR-data, polling, annuleren,
timeout en retry. De flow krijgt één optionele, action-aware presentatiepoort die zijn toestand, actieve body,
`startQr` en de altijd annulerende `switchToJellyfin` publiceert. Zonder die poort rendert hij exact zoals nu.
`AuthScreen.build()` splitst vóór de bestaande breedte-layout uitsluitend op `PlatformDetector.isAppleTV()`: Apple TV
bezit een eigen volledig `Scaffold`, focus-root en `TvAuthView`; iOS, macOS en overige routes houden hun huidige boom.
`TvAuthView` bezit zelf precies de Plex- en Jellyfin-rij, hun focuscontract en automation nodes. De Plex-flow publiceert
alleen zijn beperkte visuele state; `AuthScreen` vertaalt die naar de bredere TV-panelstate voor loading en herstel.
Compositiegeometrie komt uit de viewport, terwijl tekst, focusdensity, rijhoogtes, padding en focusring-gap de bestaande
TV-scale gebruiken. Startup, offlinebeslissingen en profielbinding blijven in `SetupScreen`, `ActiveProfileBinder` en
`ProfileSessionScreen`; TV5 voegt daar bewijs toe en geen tweede bootstrap-pad.

**Tech Stack:** Flutter 3.44.0, Dart 3.12, Provider/ChangeNotifier, `flutter_test`, Pleya Verify, Linux-goldens via
`.github/workflows/goldens.yml`.

**Authority:**

- `docs/superpowers/specs/2026-09-18-tvos-redesign-closure-design.md`, TV5.
- `docs/tvos-redesign-implementatiecontract.md`, PB-11.
- `docs/assets/tvos-unified/approved-2026-09-03/22-inloggen.png`.
- `docs/unified-2026-closure.md`, stap 15 en de latere gezamenlijke closuregates.

**Bounded design decision:** De gecorrigeerde mockup 22 wint. Apple TV toont uitsluitend Plex en Jellyfin. Er komt
geen Pleya Share-, lokale-map- of camerakeuze, geen tekstcode, geen aftelklok en geen browseractie. De QR-pagina houdt
retry en de Jellyfin-uitweg zichtbaar. Een geslaagde Verify-login gebruikt de bestaande loopback-only `/v1/signin`
automation-seam; die simuleert geen Plex-claim en omzeilt geen productiebeveiliging.

## Global Constraints

- Geen wijziging aan de productie-autharchitectuur, tokenopslag of backendrechten.
- Geen gedragssplitsing op schermbreedte voor Apple TV. De platformdetectie is de authority.
- Geen handmatige bewerking van `pleya_verify/automation_ids.yaml`; genereer via
  `dart run tool/generate_automation_ids_yaml.dart`.
- Geen lokale golden-regeneratie op macOS. Nieuwe baselines komen uitsluitend uit de Linux-workflow.
- Iedere gedragswijziging volgt rood -> groen -> refactor. Een test die voor de fix niet rood kan worden, bewijst de
  wijziging niet.
- `SKIP_HOOKS=1` alleen voor een documentatie-only commit.
- De bestaande gebruikerswijziging in `lib/screens/home/mobile_catalog_screen.dart` en de ongetrackte plannen en
  sessielogs blijven buiten alle TV5-commits.
- `lib/screens/auth_screen.dart` is al 642 regels. Nieuwe TV-opmaak komt daarom niet in dat bestand maar in
  `lib/screens/tv/tv_auth_view.dart`.

---

## Task 0: Preflight en herleidbare nulmeting

TV5 begint pas nadat de gedeelde basis en het bekende rode landschap zijn vastgelegd. Dit voorkomt dat de lokale
goldens of de losse relay-flake later als TV5-regressie worden opgevoerd.

**Files:**

- Modify: `docs/tvos-fysieke-correctieronde.md` alleen wanneer de preflight aantoonbaar verouderde informatie vindt.
- Read: `.superpowers/sdd/unified-2026-closure/progress.md`.

- [ ] **Step 1: Bevestig branch, HEAD en user-owned werk**

```bash
git status --short
git branch --show-current
git log --oneline -5
git show --stat --oneline cb81ea20
git show --stat --oneline c1dd2552
```

Verwacht: `cb81ea20` sluit CTA1/HTTP1, `c1dd2552` werkt het register bij. De wijziging in
`mobile_catalog_screen.dart`, `.serena/`, de bestaande TV2/TV3-plannen en sessielogs zijn niet van TV5 en worden niet
gestaged. Als de branch nog `fix/audio-boost-gain-stage` heet, maak vóór de eerste codewijziging een expliciete
TV5-branch vanaf deze HEAD; herschrijf of reset geen geschiedenis.

- [ ] **Step 2: Bevestig toolchain en statische gate**

```bash
flutter --version | head -1
scripts/check_flutter_version.sh
scripts/ci_checks.sh
```

Verwacht: Flutter 3.44.0 en een groene `ci_checks.sh`.

- [ ] **Step 3: Leg de functionele nulmeting vast**

```bash
flutter test test/screens/auth_screen_test.dart test/screens/auth/plex_pin_auth_flow_test.dart test/screens/settings/add_jellyfin_screen_test.dart test/screens/startup_bind_recovery_test.dart test/navigation/profile_session_screen_test.dart test/automation/automation_signin_test.dart
flutter test test/services/pleya_share_relay_test.dart --plain-name "tunnel self-heals after the relay drops both sockets" --reporter expanded
```

Verwacht: beide commando's groen. De relaytest liep na de full-suite-flake op 20 september gericht groen in 18
seconden; een nieuwe rode run wordt eerst als flake onderzocht en niet aan TV5 gekoppeld.

- [ ] **Step 4: Bevestig de bestaande verantwoordelijkheden**

```bash
rg -n "class AuthScreen|_buildAuthBody|_buildInitialButtons" lib/screens/auth_screen.dart
rg -n "class PlexPinAuthFlow|_start\(|_retry\(|_switchToJellyfin" lib/screens/auth/plex_pin_auth_flow.dart
rg -n "allConnections.isEmpty|shouldEnterOfflineModeAfterStartupBind|ProfileSwitchScreen" lib/main.dart
rg -n "Apple TV|system.*keyboard|tvKeyboardAutoOpenBehavior" lib/screens/settings/add_jellyfin_screen.dart test/screens/settings/add_jellyfin_screen_test.dart
```

Exit: de implementer kan aanwijzen dat `AuthScreen` de compositie bezit, `PlexPinAuthFlow` de Plex-state-machine,
`AddJellyfinScreen` tekstinvoer en `SetupScreen` startup/offline/profielkeuze.

- [ ] **Step 5: Commit alleen als de preflight documentatie corrigeerde**

```bash
git add docs/tvos-fysieke-correctieronde.md
SKIP_HOOKS=1 git commit -m "docs: toets TV5-aanvang tegen de huidige basis"
```

---

## Task 1: Een action-aware shellpoort rond de bestaande Plex-flow

De mockup vraagt blijvende keuzes links terwijl rechts QR, wachten of herstel wisselt. De state-machine dupliceren in
`AuthScreen` zou twee PIN-flows opleveren. Daarom krijgt de bestaande flow een optionele shell-builder die niet alleen
widgets maar ook de echte flowacties publiceert. De blijvende Jellyfin-keuze moet altijd `_switchToJellyfin()` gebruiken,
zodat een lopende Plex-poll wordt geïnvalideerd voordat de route opent. De standaard blijft de huidige widgetboom.

**Files:**

- Modify: `lib/screens/auth/plex_pin_auth_flow.dart:37-98,327-348`.
- Test: `test/screens/auth/plex_pin_auth_flow_test.dart`.

**Interface:**

```dart
enum PlexPinAuthVisualState { initial, waiting, qr, error, timedOut }

class PlexPinAuthShellScope {
  const PlexPinAuthShellScope({
    required this.state,
    required this.busy,
    required this.activeBody,
    required this.startQr,
    required this.switchToJellyfin,
  });

  final PlexPinAuthVisualState state;
  final bool busy;
  final Widget? activeBody;
  final VoidCallback startQr;
  final VoidCallback? switchToJellyfin;
}

typedef PlexPinAuthShellBuilder = Widget Function(BuildContext context, PlexPinAuthShellScope scope);
```

`PlexPinAuthFlow` krijgt `final PlexPinAuthShellBuilder? shellBuilder`. Deze presentatie-enum bevat geen token, PIN,
URL, timer of service. `busy` is rechtstreeks `_authService == null`. `activeBody` is de al bestaande `_buildQr`,
`_buildBrowserWaiting` of `_buildErrorBlock`, maar bevat in de TV-shell geen tweede Jellyfin-link. `startQr` start de
bestaande QR-poging; `switchToJellyfin` loopt intern altijd via `_switchToJellyfin()` en is null wanneer Jellyfin niet
beschikbaar is. Wanneer `shellBuilder == null`, retourneert `build()` exact de huidige boom met de bestaande
`initialButtonsBuilder` en de bestaande rechter Jellyfin-uitweg.

- [ ] **Step 1: Schrijf de rode regressietests**

Voeg twee tests toe:

```dart
testWidgets('default rendering is unchanged when no shell builder is supplied', (tester) async {
  // Pump the current default flow and assert the existing Plex and QR actions.
});

testWidgets('shell builder exposes the QR body and cancelling Jellyfin action', (tester) async {
  // Inject the existing never-claimed client, call scope.startQr, then invoke
  // scope.switchToJellyfin and prove the stale poll cannot deliver a token.
});
```

De tweede test moet rood zijn omdat de huidige flow geen action-aware shellscope publiceert.

- [ ] **Step 2: Draai alleen de rode test**

```bash
flutter test test/screens/auth/plex_pin_auth_flow_test.dart --plain-name "shell builder exposes the QR body and cancelling Jellyfin action"
```

Verwacht: FAIL doordat de action-aware shellscope nog niet bestaat.

- [ ] **Step 3: Implementeer de minimale presentatiepoort**

Bereken eerst `activeBody` en `state`. Roep daarna de shell-builder aan wanneer die bestaat en geef callbacks door naar
de bestaande `_start(showQr: true)` en `_switchToJellyfin()`. Verplaats geen servicecode. Let erop dat een fout zonder
timeout `error` is, en de huidige timeoutweergave `timedOut`.

- [ ] **Step 4: Bewijs QR, gewone fout, timeout, retry en Jellyfin-annulering**

Breid de geïnjecteerde fake zo uit dat `createPin` kan slagen of falen en `pollPinUntilClaimed` null kan opleveren.
Assert per toestand de enum en dat `retry` een nieuwe attempt start. Voeg een gecontroleerde late claim toe en bewijs
dat `switchToJellyfin` eerst `_attemptId` invalideert: na de keuze mag `onTokenReceived` niet meer lopen. De bestaande
test "tapping the Jellyfin way out" blijft groen voor het standaardrenderpad.

- [ ] **Step 5: Gerichte suite en commit**

```bash
dart format --line-length 120 lib/screens/auth/plex_pin_auth_flow.dart test/screens/auth/plex_pin_auth_flow_test.dart
flutter test test/screens/auth/plex_pin_auth_flow_test.dart
git add lib/screens/auth/plex_pin_auth_flow.dart test/screens/auth/plex_pin_auth_flow_test.dart
git commit -m "refactor(auth): maak de Plex-flow TV-shellbaar"
```

---

## Task 2: Bouw `TvAuthView` als zuivere 10-foot-compositie

Deze taak bouwt alleen presentatie. Netwerk, navigatie en opslag blijven buiten de widget. De nieuwe view moet op de
canonieke 1920x1080-output leesbaar zijn via `kTvGoldenSurfaceSize` en de title-safe insets respecteren.

**Files:**

- Create: `lib/screens/tv/tv_auth_view.dart`.
- Modify: `lib/widgets/tv/tv_unified_layout.dart` alleen wanneer bestaande densitytokens ontbreken.
- Create: `test/screens/tv/tv_auth_view_test.dart`.

**Interface:**

```dart
class TvAuthView extends StatelessWidget {
  const TvAuthView({
    super.key,
    required this.brand,
    required this.content,
    required this.state,
    required this.plexEnabled,
    required this.jellyfinEnabled,
    required this.onPlexSelected,
    required this.onJellyfinSelected,
  });

  final Widget brand;
  final Widget content;
  final TvAuthPanelState state;
  final bool plexEnabled;
  final bool jellyfinEnabled;
  final VoidCallback onPlexSelected;
  final VoidCallback onJellyfinSelected;
}

enum TvAuthPanelState {
  initial,
  waiting,
  qr,
  plexError,
  timedOut,
  authenticating,
  noServersFound,
  networkError,
}

class TvAuthGeometry {
  factory TvAuthGeometry.forViewport(Size viewport) { ... }
}
```

`TvAuthGeometry.forViewport` bepaalt safe insets, kolombreedtes, kolomafstand en paneelmaat uit de werkelijke viewport.
Alleen type, rijhoogtes, padding, radius en focusring-gap lopen via `TvLayoutConstants.scaleOf`. Gebruik
`tvPanelDecoration(tokens(context), radius)` voor het rechterpaneel. `TvAuthView` bouwt zelf precies twee backendrijen
via een kleine private rijwidget op `FocusableWrapper` of `TvPanelButton`; geen aangeleverde `choices`-widget en geen
lokale `FilledButton.styleFrom(shape: ...)`.

- [ ] **Step 1: Schrijf rode compositie- en geometrietests**

De tests pompen `TvAuthView` op `kTvGoldenSurfaceSize` en bewijzen:

- brand, Plex en Jellyfin staan in de linkerkolom en de view bouwt zelf exact die twee keuzes;
- het statepaneel staat rechts en overlapt de keuzes niet;
- beide kolommen en hun focusringen vallen binnen de viewport;
- Plex heeft initieel focus, DOWN landt op Jellyfin en UP keert terug;
- SELECT roept de juiste callback eenmaal aan en disabled keuzes zijn niet activeerbaar;
- de keuzes publiceren `auth.choice[plex]` en `auth.choice[jellyfin]` op hun echte renderowner;
- er bestaan geen labels voor Pleya Share, lokale map, camera, tekstcode of aftelklok;
- een lang Nederlands of Duits label veroorzaakt geen overflow.

De eerste test moet rood zijn omdat `TvAuthView` nog niet bestaat.

- [ ] **Step 2: Implementeer de frame-opmaak**

Volg mockup 22: donker vlak, royale linker marge, logo en kop boven de twee backendrijen, rechts een afgerond paneel.
Toon in de initiële toestand een rustige uitleg in het rechterpaneel; laat QR/wachten/herstel exact die plek innemen.
Geen topnav: eerste start heeft nog geen profielsession en dus geen hoofd-shell.

- [ ] **Step 3: Gerichte suite en commit**

```bash
dart format --line-length 120 lib/screens/tv/tv_auth_view.dart lib/widgets/tv/tv_unified_layout.dart test/screens/tv/tv_auth_view_test.dart
flutter test test/screens/tv/tv_auth_view_test.dart
git add lib/screens/tv/tv_auth_view.dart lib/widgets/tv/tv_unified_layout.dart test/screens/tv/tv_auth_view_test.dart
git commit -m "feat(tvos): bouw de eerste-startcompositie"
```

---

## Task 3: Koppel Apple TV aan de nieuwe view, zonder handheld-regressie

**Files:**

- Modify: `lib/screens/auth_screen.dart:225-327,387-469`.
- Modify: `lib/screens/auth/plex_pin_auth_flow.dart` alleen wanneer een klein test-injectiepunt nodig blijkt.
- Test: `test/screens/auth_screen_test.dart`.

**Test seams:** `AuthScreen` mag `@visibleForTesting` twee afzonderlijke servicefactories krijgen: één die per
`PlexPinAuthFlow`-aanroep een verse service levert voor PIN/polling, en één die per connectpoging een verse service
levert voor tokenuitwisseling, gebruikersinformatie en servers. Alleen compacte unit/widgettests mogen een
Jellyfin-routecallback injecteren; de integratieproef in Task 5 gebruikt de echte Navigator en `AddJellyfinScreen`.
Productie-defaults blijven de huidige constructors. Injecteer geen Provider-stack in `TvAuthView`; houd die widget
zuiver.

- [ ] **Step 1: Schrijf de rode platformgrens**

Voeg een widgettest toe die `TvDetectionService.debugSetAppleTVOverride(true)` zet, `AuthScreen` met de minimale
bestaande providers pompt en een volledige `TvAuthView` buiten de bestaande `maxWidth: 800`-container verwacht. Dezelfde
test met override `false` verwacht de oude desktop/mobile boom en geen `TvAuthView`.

- [ ] **Step 2: Splits Apple TV bovenaan `AuthScreen.build()` af**

Maak de platformgrens vóór iedere breedtekeuze:

```dart
@override
Widget build(BuildContext context) {
  if (PlatformDetector.isAppleTV()) {
    return _buildAppleTvAuthScreen();
  }

  return _buildExistingAuthScreen();
}
```

De niet-Apple-TV-boom blijft letterlijk of structureel ongewijzigd. `_buildAppleTvAuthScreen()` bezit het volledige
`Scaffold`, de focus-root en één `PlexPinAuthFlow` met shell-builder. Die builder levert `TvAuthView` met:

- de bestaande logo/tagline-authority;
- door `TvAuthView` zelf gebouwde Plex- en Jellyfin-rijen;
- het actieve body-widget van `PlexPinAuthFlow` rechts;
- een initiële uitleg rechts wanneer `activeBody == null`.

De Plex-callback gebruikt `scope.startQr`; de enige Jellyfin-rij gebruikt `scope.switchToJellyfin`, zodat QR-polling
wordt geannuleerd. Tijdens `_isAuthenticating` en `_recoveryState` vertaalt `AuthScreen` naar `TvAuthPanelState` en
rendert hetzelfde frame met uitgeschakelde keuzes links en loading of recovery rechts. Op niet-Apple-TV blijft de
bestaande authboom ongewijzigd.

- [ ] **Step 3: Bewijs gedrag van beide backendkeuzes**

Tests:

- SELECT op Plex start QR en opent nooit `url_launcher` op Apple TV;
- DOWN en SELECT op Jellyfin roept exact eenmaal de geïnjecteerde Jellyfin-route aan;
- dezelfde Jellyfin-rij blijft tijdens QR-polling bereikbaar, annuleert die poging en een late Plex-claim navigeert niet;
- Menu/back houdt root-auth gemount, popt geen route, herstelt of behoudt geldige focus en veroorzaakt geen exception;
- na terugkeer uit Jellyfin staat focus weer op een geldige backendrij.

- [ ] **Step 4: Bewijs handheld/desktop-ongewijzigd**

Voeg assertions toe voor de bestaande brede layout en smalle layout: browser is de primaire Plex-actie buiten TV,
QR blijft secundair en er wordt geen `TvAuthView` gebouwd. Draai de bestaande `PlexPinAuthFlow`-tests mee.

- [ ] **Step 5: Gerichte suite en commit**

```bash
dart format --line-length 120 lib/screens/auth_screen.dart test/screens/auth_screen_test.dart
flutter test test/screens/auth_screen_test.dart test/screens/auth/plex_pin_auth_flow_test.dart
git add lib/screens/auth_screen.dart test/screens/auth_screen_test.dart
git commit -m "feat(tvos): verbind authstatussen met de TV-compositie"
```

---

## Task 4: Sluit loading, herstel, profielpoort en offline-startup met tests

MOC-22 noemt meer dan de eerste QR-frame. Deze taak bouwt alleen ontbrekend gedrag wanneer een rode test een echt gat
vindt. Bestaand groen gedrag wordt niet herschreven.

**Files:**

- Test/modify: `test/screens/auth_screen_test.dart`.
- Test/modify: `test/screens/startup_bind_recovery_test.dart`.
- Test/modify: `test/navigation/profile_session_screen_test.dart`.
- Test/modify: `test/automation/automation_signin_test.dart`.
- Possible modify after a red proof: `lib/screens/auth_screen.dart`, `lib/main.dart`,
  `lib/navigation/profile_session_screen.dart`.

- [ ] **Step 1: Auth loading en herstel**

Met de twee afzonderlijke, per aanroep verse Plex-servicefactories bewijs je op Apple TV:

- token ontvangen -> loading rechts en geen tweede authpoging;
- servers leeg -> `noServersFound` met retry en Jellyfin;
- netwerkfout -> `networkError` met retry;
- retry -> terug naar de initiële, gefocuste Plex/Jellyfin-keuze;
- timeout -> echte `authenticationTimeout`, retry en Jellyfin-uitweg, zonder code of klok.

- [ ] **Step 2: Succes en profielpoort**

Breid de bestaande pure tests uit voor drie gevallen:

- precies één Plex Home-profiel wordt automatisch actief;
- meerdere profielen openen verplicht `ProfileSwitchScreen` voordat `ProfileSessionScreen`;
- cancel of geen geldige selectie laat de authscreen staan en stopt loading.

De end-to-end automationtest blijft de authority voor "eerste profiel wordt via `/v1/signin` aangemaakt en daarna
bestaat de profile-session seam".

- [ ] **Step 3: Gedeeltelijk en volledig offline**

Voeg tabeltests toe rond de bestaande startupbeslissing:

```dart
test('partial startup remains online when at least one visible server binds', () { ... });
test('failed startup enters offline only when no server is online', () { ... });
test('successful bind with zero manager servers is not reclassified as failure', () { ... });
```

Als de bestaande helpers deze matrix al volledig dekken, voeg dan geen productiecode toe en leg in het register de
testnamen als bewijs vast. Een wijziging in `main.dart` is alleen toegestaan na een rode test op de echte beslissing.

- [ ] **Step 4: Gerichte suite en commit**

```bash
flutter test test/screens/auth_screen_test.dart test/screens/startup_bind_recovery_test.dart test/navigation/profile_session_screen_test.dart test/automation/automation_signin_test.dart
git add test/screens/auth_screen_test.dart test/screens/startup_bind_recovery_test.dart test/navigation/profile_session_screen_test.dart test/automation/automation_signin_test.dart lib/screens/auth_screen.dart lib/main.dart lib/navigation/profile_session_screen.dart
git diff --cached --check
git commit -m "test(auth): dek eerste sessie en startupherstel"
```

Stage alleen bestanden die daadwerkelijk wijzigden.

---

## Task 5: Bewijs Siri Remote, systeemtoetsenbord en terugnavigatie voor Jellyfin

`AddJellyfinScreen` heeft al Apple TV-tests voor initiële focus, het niet automatisch openen van een keyboard en de
Quick Connect-panelwissel. TV5 vult alleen de ontbrekende route vanaf `AuthScreen` en terug aan.

**Files:**

- Modify: `test/screens/settings/add_jellyfin_screen_test.dart`.
- Modify: `test/screens/auth_screen_test.dart`.
- Possible modify after red proof: `lib/screens/settings/add_jellyfin_screen.dart`.

- [ ] **Step 1: Inventariseer en draai het bestaande bewijs**

```bash
flutter test test/screens/settings/add_jellyfin_screen_test.dart --reporter expanded
```

De reeds groene tests voor URL-focus, systeemkeyboard-suppressie en Quick Connect worden niet gedupliceerd.

- [ ] **Step 2: Voeg de ontbrekende routeproef toe**

Pump `AuthScreen` met de echte Navigator-route (geen geïnjecteerde Jellyfin-routecallback), navigeer met DOWN naar
Jellyfin, SELECT, verwacht de echte `AddJellyfinScreen`, druk Menu/back voordat data is gewijzigd en verwacht terugkeer
naar `AuthScreen` met geldige focus. Navigeer opnieuw naar de echte route, activeer het URL-veld met SELECT en bewijs
via de bestaande native-text-entry seam dat Apple TV het systeemtoetsenbord gebruikt en nooit
`tv_virtual_keyboard_panel` bouwt.

- [ ] **Step 3: Repareer alleen een aangetoond focus- of backgat**

Gebruik de bestaande `handleBackKeyNavigation`, `FocusedScrollScaffold` en `TvKeyboardAutoOpenBehavior`. Voeg geen
tweede key-handler of virtueel Apple TV-toetsenbord toe.

- [ ] **Step 4: Gerichte suite en commit**

```bash
dart format --line-length 120 test/screens/settings/add_jellyfin_screen_test.dart test/screens/auth_screen_test.dart lib/screens/settings/add_jellyfin_screen.dart
flutter test test/screens/settings/add_jellyfin_screen_test.dart test/screens/auth_screen_test.dart
git add test/screens/settings/add_jellyfin_screen_test.dart test/screens/auth_screen_test.dart lib/screens/settings/add_jellyfin_screen.dart
git commit -m "test(tvos): sluit Jellyfin-invoer en terugkeer"
```

Stage opnieuw alleen gewijzigde bestanden.

---

## Task 6: Maak auth agent-addressable

De eerste-startjourney mag niet op tekst of coördinaten vertrouwen. Voeg een klein, gesloten ID-domein toe.

**Files:**

- Modify: `lib/automation/automation_ids.dart`.
- Modify: `lib/screens/auth_screen.dart`.
- Modify: `lib/screens/tv/tv_auth_view.dart`.
- Modify: `lib/screens/auth/plex_pin_auth_flow.dart`.
- Regenerate: `pleya_verify/automation_ids.yaml`.
- Test: `test/architecture/automation_ids_test.dart` indien de catalogusasserties aanpassing vragen.

**IDs:**

```text
screen.auth                 screen
auth.choice                 button, instanceable: plex | jellyfin
auth.panel                  region
auth.retry                  button
```

`screen.auth` is ready zodra de compositie gemount is. De Plex-keuze publiceert daarnaast zijn echte `enabled`-staat;
de journey wacht op focus voordat hij SELECT stuurt en kan daardoor niet tegen de asynchrone service-initialisatie
racen. Tijdens QR blijft `auth.choice[jellyfin]` dezelfde zichtbare, annulerende uitweg; er bestaat geen tweede
`auth.jellyfin_escape`. `auth.panel.state` publiceert exact de gerenderde `TvAuthPanelState`: `initial`, `waiting`,
`qr`, `plexError`, `timedOut`, `authenticating`, `noServersFound` of `networkError`. Publiceer nooit QR-URL, PIN,
token, gebruikersnaam of serveradres.

- [ ] **Step 1: Schrijf de rode catalogus- en widgettests**

Assert dat alle vier basis-IDs in `AutomationIds.catalog()` staan, dat alleen `auth.choice` instanceable is en dat de
live node-state rechtstreeks dezelfde `TvAuthPanelState` draagt waaruit het paneel wordt gerenderd.

- [ ] **Step 2: Voeg `AutomationScreen` en nodes toe**

Wrap de root van `AuthScreen` in `AutomationScreen`. Wrap de twee keuzes, het rechterpaneel, retry en Jellyfin-uitweg
op hun echte renderowner. Maak geen onzichtbare proxy-nodes.

- [ ] **Step 3: Regenereer en valideer**

```bash
dart run tool/generate_automation_ids_yaml.dart
flutter test test/architecture/automation_ids_test.dart test/architecture/automation_ids_yaml_test.dart
cd pleya_verify/runner && dart test && cd ../..
```

- [ ] **Step 4: Commit**

```bash
git add lib/automation/automation_ids.dart lib/screens/auth_screen.dart lib/screens/tv/tv_auth_view.dart lib/screens/auth/plex_pin_auth_flow.dart pleya_verify/automation_ids.yaml test/architecture/automation_ids_test.dart
git commit -m "test(verify): maak de eerste-startflow adresseerbaar"
```

---

## Task 7: Twee eerlijke Pleya Verify-journeys en visueel bewijs

Eén scenario kan niet tegelijk de handmatige QR-route doorlopen en daarna buiten de DSL alsnog `sign_in` uitvoeren:
`sign_in` is bewust een setup-verb. Daarom worden het twee smalle journeys, elk met én waarheid.

**Files:**

- Create: `pleya_verify/scenarios/tvos.auth.first-start.yaml`.
- Create: `pleya_verify/scenarios/tvos.auth.first-profile-handoff.yaml`.
- Modify: `pleya_verify/impact-map.yaml` wanneer scenarioselectie daar per bestand wordt bijgehouden.
- Generated evidence only: `.build/pleya-verify/`.

- [ ] **Step 1: Schrijf de deterministische eerste-profielhandoff**

```yaml
name: tvos.auth.first-profile-handoff
target: tvos-sim
setup:
  - reset_app
  - seed: catalog.mixed.v1
  - launch
  - sign_in: {base_url: "{{fixture}}", username: verify-owner, password: verify-password, setup_code: "{{fixture_setup_code}}"}
steps:
  - wait_until: {id: screen.discover, timeout: 30000}
  - assert: {id: screen.discover}
  - snapshot: 00-first-profile-ready
```

Dit bewijst succesvolle setup, opslag, eerste-profielcreatie, binder-handoff en de uiteindelijke sessie. Het beweert
niet dat de fixture een Plex QR-claim deed. Deze journey is hermetisch en verplicht groen voor TV5-closure.

- [ ] **Step 2: Schrijf de externe echte Plex-QR-journey**

```yaml
name: tvos.auth.first-start
target: tvos-sim
setup:
  - reset_app
  - launch
steps:
  - wait_until: {id: screen.auth, timeout: 30000}
  - wait_until: {focused: "auth.choice[plex]", timeout: 15000}
  - assert: {id: "auth.choice[plex]", focused: true, insideViewport: true}
  - assert: {id: "auth.choice[jellyfin]", insideViewport: true}
  - snapshot: 00-first-start
  - press: select
  - wait_until: {id: auth.panel, timeout: 15000}
  - assert: {id: auth.panel, insideViewport: true, state: {state: qr}}
  - assert: {id: auth.retry, insideViewport: true}
  - assert: {id: "auth.choice[jellyfin]", insideViewport: true}
  - snapshot: 01-plex-qr
```

Dit scenario doet geen `seed` en geen `sign_in`: het bewijst de echte lege eerste start en start een echte Plex-PIN.
Wanneer plex.tv vanuit de simulatoromgeving onbereikbaar is, moet de scenario-state `error` aantoonbaar maken en mag
de run niet als QR-PASS worden bestempeld. In dat geval wordt QR met de geïnjecteerde widgettest bewezen en blijft het
simulatorbewijs als `VERIFY/SIM OPEN` expliciet open. Deze externe smoke-test is dus conditioneel groen en blokkeert
geen eerlijke rapportage van de deterministische handoff.

- [ ] **Step 3: Valideer portable**

```bash
cd pleya_verify/runner
dart run bin/verify.dart validate ../scenarios/tvos.auth.first-start.yaml
dart run bin/verify.dart validate ../scenarios/tvos.auth.first-profile-handoff.yaml
dart test
cd ../..
```

- [ ] **Step 4: Valideer de simulatorinvoer en draai beide journeys op dezelfde build**

```bash
scripts/tvos_sim.sh doctor --json
cd pleya_verify/runner
dart run bin/verify.dart run ../scenarios/tvos.auth.first-profile-handoff.yaml --json
dart run bin/verify.dart run ../scenarios/tvos.auth.first-start.yaml --json
cd ../..
```

Een groene doctor is verplicht voordat tvOS-input als simulatorbewijs telt. Bewaar de beschikbare `bundle_dir`-paden,
manifests, compositor-screenshots en ui-trees in het voortgangsregister. Vergelijk `00-first-start` en, wanneer externe
Plex-toegang beschikbaar is, `01-plex-qr` met `22-inloggen.png` op compositie, veilige marges, leesafstand,
focuszichtbaarheid en afwezigheid van verboden opties.

- [ ] **Step 5: Voeg golden-test en Linux-baselines als één reviewbare wijziging toe**

Voeg nu pas `test/goldens/tv_auth_view_golden_test.dart` toe met `tv_auth_initial.png` en `tv_auth_qr.png`. Push pas na
expliciete toestemming en start `.github/workflows/goldens.yml`. Download alleen de twee nieuwe TV5-baselines,
inspecteer ze en commit de test plus goedgekeurde PNG's samen. Een lokale macOS-output wordt niet als baseline gebruikt.
Als de workflow een vooraf gecommitte test vereist, maak dan expliciet een tijdelijke rode, niet-reviewbare en
niet-mergeable generatiecommit op de branch; amend/squash die na artifactreview zodat de definitieve commit de test en
PNG's samen bevat.

- [ ] **Step 6: Commit scenario's en daarna de complete goldenwijziging**

```bash
git add pleya_verify/scenarios/tvos.auth.first-start.yaml pleya_verify/scenarios/tvos.auth.first-profile-handoff.yaml pleya_verify/impact-map.yaml
git commit -m "test(verify): bewijs eerste start en eerste profiel"
```

Goldencommit na Linux-artifact:

```bash
git add test/goldens/tv_auth_view_golden_test.dart test/goldens/tv_auth_initial.png test/goldens/tv_auth_qr.png
git commit -m "test(golden): leg de TV-authcompositie vast"
```

---

## Task 8: TV5 closuregate, review en registers

**Files:**

- Modify: `docs/tvos-redesign-register.md`.
- Modify: `docs/tvos-fysieke-correctieronde.md` wanneer de visuele of simulatorronde een bevinding oplevert.

Het gitignored uitvoeringsledger onder `.superpowers/sdd/` wordt wel actueel gehouden maar is geen repository-artifact
en hoort daarom niet in deze documentatiecommit.

- [ ] **Step 1: Volledige gerichte suite**

```bash
flutter test test/screens/auth_screen_test.dart test/screens/auth/plex_pin_auth_flow_test.dart test/screens/settings/add_jellyfin_screen_test.dart test/screens/startup_bind_recovery_test.dart test/navigation/profile_session_screen_test.dart test/automation/automation_signin_test.dart test/screens/tv/tv_auth_view_test.dart
```

- [ ] **Step 2: Repo-gates**

```bash
scripts/ci_checks.sh
flutter test
```

Een full-suite-failure door de bekende lokale Linux-goldenverschillen wordt apart gerapporteerd met exacte testnamen.
Niet-golden-falers zijn blokkerend totdat ze gereproduceerd en geclassificeerd zijn.

- [ ] **Step 3: Fresh-context review**

Laat een reviewer uitsluitend de TV5-commitreeks beoordelen tegen PB-11 en de TV5-sectie van de closure-spec. Vereiste
vragen:

- is niet-Apple-TV gedrag werkelijk ongewijzigd;
- bestaat er nog maar én Plex state-machine;
- zijn verboden opties/code/klok afwezig;
- zijn focus, back en Jellyfin-systeemtekstinvoer bewezen;
- bewijzen de scenario's wat hun naam claimt;
- bevatten logs of automation state geen geheimen.

Verwerk bevindingen TDD-first en herhaal de relevante gates.

- [ ] **Step 4: Werk MOC-22 bij**

Zet `MOC-22` pas op `CODE/SIM CLOSED · HARDWARE OPEN` wanneer aanwezig zijn:

- gerichte groene tests;
- groene `ci_checks.sh`;
- de deterministische eerste-profielhandoff groen op de kandidaat-SHA;
- de echte Plex-QR-journey groen wanneer externe toegang beschikbaar is, anders expliciet `VERIFY/SIM OPEN`;
- twee compositor-screenshots vergeleken met mockup 22;
- Linux-goldens beoordeeld;
- review zonder open code- of simbevinding.

Ontbreekt een externe Plex-verbinding of de Linux-workflow, noteer precies welk bewijs ontbreekt en houd
`VERIFY/SIM OPEN`; sluit de rij niet op widgettests alleen.

- [ ] **Step 5: Documentatiecommit**

```bash
git add docs/tvos-redesign-register.md docs/tvos-fysieke-correctieronde.md
SKIP_HOOKS=1 git commit -m "docs: sluit TV5 op code en simulator"
```

- [ ] **Step 6: Stop voor de externe integratiepoort**

Rapporteer commitreeks, testtotalen, bundle-paden, screenshots, golden-workflow-run en resterende `HARDWARE OPEN`.
Push, PR, merge en een build/TestFlight-upload gebeuren pas na expliciete toestemming. Na merge wordt TV6 gestart;
TV8 blijft door de nu gesloten GATE0 niet langer geblokkeerd, maar komt volgens de vastgelegde volgorde pas na TV7.
