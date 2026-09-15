# tvOS remote input: autoriteitsgrenzen

**Status: CODE CLOSED** (15 september 2026, `834a8012` op `remote-controller`). Het autoriteitsmodel
in §1 en de levenscyclus in §2-4 staan vast; SEL1 is dicht (`docs/tvos-fysieke-correctieronde.md`).
RAIL2: de meting in §6 is gedraaid (build 281, log `8x94u`, 15 september 2026) en levert
**ENGINE_DUPLICATE bevestigd**, zijdeur 4 (§3): drie onafhankelijke fantoompaar-instanties, elk
`same-uipress`. Een engine-lifecyclepatch is daarmee gerechtvaardigd volgens de beslisregel in §6,
maar nog niet gebouwd. Zie `docs/tvos-fysieke-correctieronde.md`, rij RAIL2, voor de volledige
classificatie.

Dit document legt vast welke laag welke staat mag bezitten in het pad van een Siri Remote-druk
naar een Pleya-navigatie, en waarom. Het volgt uit het lezen van de gepinde engine-fork
(`scripts/tvos_engine_source.sh`, `tvos/engine.version` = `3.44.0+3`) en de bestaande Dart-kant
(`lib/services/apple_tv_remote_touch_service.dart`), niet uit een nieuw ontwerp. Zie
`docs/tvos-remote-press-pipeline.md` voor de tien stations en de drie eerder gevonden zijdeuren;
dit document voegt er een vierde aan toe (§3) en legt de autoriteitstabel vast (§1).

## 1. De tabel

| # | Station | Waar | Eigenaar van state | Mag dedupliceren |
|---|---|---|---|---|
| 1 | `UIPress` `.began`/`.changed`/`.ended`/`.cancelled` | tvOS | n.v.t. | nee |
| 2 | `flutterTvos_sendEvent:` swizzle op `UIApplication` én `UIWindow` | engine-fork | nee | nee |
| 3 | `tvosHandlePress(fromUIEvent:)` | `tvos/Runner/AppDelegate.swift` | **nee** (kan twee keer per drukcyclus lopen: één keer bij `.began`, één keer bij `.ended`) | **nee** |
| 4-6 | `synthesizeRemotePressType:`, `synthesizedPressedKeys`, de herhaaltimer | engine-fork | **ja, exclusief** | ja, op fysieke key-identiteit |
| 7 | `sendKeyEvent:` → `flutter/keydata` | engine-fork | nee | nee |
| 8 | `HardwareKeyboard.handleKeyEvent` | Flutter SDK | `physicalKeysPressed` | nee |
| 9 | `FocusManager` early key handler | `AppleTvRemoteTouchService` | **ja, enige Dart-eigenaar** | **ja, enige Dart-plek** |
| 10 | focus-tree (`FocusableWrapper`) | widgets | alleen eigen focus/long-press | **nee** |

Drie regels die hieruit volgen:

1. **Station 3 blijft een stateloze boolean.** Additieve diagnostiek (een NSLog- of
   kanaalregel) mag; gedragslogica (tellen, filteren, een fase inslikken of doorgeven) niet. Twee
   builds hebben dat op hardware bewezen: swallowen liet de herhaaltimer van station 6 eeuwig
   doorlopen (build 257), doorgeven crashte UIKit op `_verifyTrackingPresses:` (build 256).
2. **Een synthesefout van station 4-6 hoort in de patchreeks**, niet in een filterlaag erboven.
   Elke poging om engine-gedrag vanuit de app te maskeren is al gemeten en afgekeurd (station 3,
   station 9 met een tijdvenster: build 254, log `ld1t1`, 65 echte drukken gegeten).
3. **Schermen dedupliceren niet.** Duplicaatcorrectie die in een widget terechtkomt is schuld en
   hoort naar station 9, of moet weg, en alleen na bewijs dat de schermlaag daadwerkelijk bij SEL1
   of RAIL2 hoort.

Station 9 is al de enige Dart-plek die een druk kan stoppen
(`FocusManager.instance.addEarlyKeyEventHandler`, DEC-017;
`HardwareKeyboard.instance.addHandler` alleen registreert, stopt niets: bewezen door
`blockConsumedKeyEvent` in `apple_tv_remote_touch_service.dart:217-222` en de bijbehorende
testgroep "een consume moet de focustree ook echt bereiken"). `AppleTvRemoteTouchService` zit daar
al: er komt geen nieuwe coordinator naast, die service *is* de coordinator.

## 2. `synthesizedPressedKeys`: de volledige levenscyclus

`synthesizedPressedKeys` (`NSMutableSet<NSNumber*>`, sleutel = de HID physical usage-code) leeft
exclusief in de engine-laag (`FlutterViewController+TvosRemote`,
`build/tvos-engine-source/src/.../FlutterViewController.mm:1043-1092, 1288-1347` na reconstructie).

**Wie voegt toe.** Alleen `sendSynthesizedKeyEventOfType:` op `type == kFlutterKeyEventTypeDown`,
en alleen als de key er nog niet in zit (`:1059-1063`); zit hij er al, dan wordt de Down
genegeerd (`return NO`) en er gaat geen tweede keydata-pakket naar Flutter.

**Wie verwijdert.** Twee paden:
- `sendSynthesizedKeyEventOfType:` op `type == kFlutterKeyEventTypeUp`, alleen als de key erin
  zit (`:1064-1068`); zit hij er niet in, dan wordt de Up genegeerd.
- `releaseAllSynthesizedPresses` (`:1166-1179`), die **elke** key in de set een synthetische Up
  geeft en de set leegt. Wordt alleen aangeroepen vanuit `setMenuPressPassthroughEnabled:` op een
  overgang naar `enabled == YES` (`:1181-1189`), de al bekende NAV1-trigger, sinds `7786a952`
  geparkeerd tot `physicalKeysPressed` leeg is (`lib/services/tvos_system_navigation_service.dart`).

**Wie leest zonder te muteren.** `synthesizeRemotePressType:eventType:physical:logical:tapIfMissingKeyDown:`
(`:1288-1314`) leest `hasKeyDown` aan het begin en beslist daarop:

```objc
NSNumber* key = @(physical);
BOOL hasKeyDown = [self.synthesizedPressedKeys containsObject:key];
if (type == kFlutterKeyEventTypeUp) {
  if (self.synthesizedRepeatPhysicalKey.unsignedLongLongValue == physical) {
    [self stopSynthesizedRepeat];
  }
  if (!hasKeyDown && tapIfMissingKeyDown) {
    [self sendSynthesizedKeyEventOfType:kFlutterKeyEventTypeDown physical:physical logical:logical];
  }
}
BOOL sent = [self sendSynthesizedKeyEventOfType:type physical:physical logical:logical];
if (sent && type == kFlutterKeyEventTypeDown && [self isRepeatablePressType:pressType]) {
  [self startSynthesizedRepeatWithPhysical:physical logical:logical];
}
return YES;  // onvoorwaardelijk, ongeacht of `sent` waar was
```

`tapIfMissingKeyDown` staat op `YES` voor precies één aanroeppad:
`tvosHandlePressFromUIEvent:` op `UIPressPhaseEnded`/`UIPressPhaseCancelled` (`:1337-1343`). Voor
`UIPressPhaseBegan`/`Changed`/`Stationary` staat hij op `NO` (`:1332-1336`), en voor het losse
`maybeSynthesizeForPress:eventType:`-pad (ongebruikt door de huidige `.began`/`.ended`-route,
gereserveerd voor toekomstige aanroepers) ook op `NO` (`:1279-1283`).

**De invariant die hierdoor moet gelden**, en die met de huidige code klopt zolang de set alleen
op de hierboven genoemde twee paden verandert:

> Een `.ended`/`.cancelled` mag alleen een ontbrekende keydown synthetiseren (`tapIfMissingKeyDown`)
> wanneer er voor die fysieke key nog geen equivalente Down aan Flutter geleverd is sinds de
> laatste Up: dus wanneer de `.began` van deze druk zelf nooit als Down aankwam.

**Waar de invariant breekt: het bewezen pad (NAV1, gesloten).** `setMenuPressPassthroughEnabled:YES`
verwijdert een gehouden key uit de set terwijl de fysieke druk nog loopt. Komt de bijbehorende
`.ended` daarna binnen, dan vindt hij de key niet meer, en `tapIfMissingKeyDown` synthetiseert een
vers Down/Up-paar: de tweede stap uit NAV1. Gefixed door de enable te parkeren tot geen enkele key
meer vastzit (`7786a952`).

**Waar de invariant kan breken zonder een channel-bericht: de kandidaat voor RAIL2.** De set kan
ook leeglopen doordat **dezelfde `UIPress`-fase tweemaal bij `tvosHandlePressFromUIEvent:`
aankomt**: de engine hookt zowel `-[UIApplication sendEvent:]` als `-[UIWindow sendEvent:]` met
dezelfde afhandelfunctie (`FlutterTvosHandlePressesEvent`,
`build/.../FlutterViewController.mm:312-338`, opgeroepen vanuit beide swizzels op `:359-395`).
Voor `.began` is een dubbele aanroep onschadelijk: de tweede Down vindt de key al in de set en
wordt genegeerd (`sendSynthesizedKeyEventOfType:` retourneert `NO`, geen tweede keydata, geen
herstart van de herhaaltimer). Voor `.ended`/`.cancelled` is dat **niet** symmetrisch:

1. Eerste aanroep: `hasKeyDown == true`, dus de `tapIfMissingKeyDown`-tak wordt overgeslagen; de
   Up wordt verzonden en de key verwijderd.
2. Tweede aanroep voor **dezelfde fase van hetzelfde `UIPress`-object**: `hasKeyDown == false`
   (de eerste aanroep heeft de key net verwijderd), dus `!hasKeyDown && tapIfMissingKeyDown` is nu
   waar en er gaat een fantoom-Down uit, gevolgd door de eigen Up: een volledig extra
   Down/Up-paar, zonder dat er een tweede fysieke druk plaatsvond en zonder dat er een
   kanaalbericht (`flutter/tvos_system_navigation`) aan te pas kwam.

Dit verklaart precies waarom twee van de vier RAIL2-waarnemingen in log `ijqxp` geen
kanaalbericht laten zien (de rij zelf noteert dit als "dus dit is niet de NAV1-trigger"): het is
een tweede route naar dezelfde synthesefout, niet dezelfde trigger. Of dit pad in de praktijk
wordt geraakt hangt af van of beide swizzel-hops voor dezelfde fase daadwerkelijk dezelfde
`FlutterViewController` resolven (`FlutterTvosFlutterViewControllerForPress`, eerst via
`press.responder`, anders via `press.window` of het scheme-venster), en dat is precies het
`same-uipress`-bewijs dat de trace in fase 2 moet leveren, geen aanname vanuit deze lezing.

**Wat dit niet is.** Dit is geen tijdvenster en geen heuristiek: het is een structurele eigenschap
van de asymmetrie tussen `tapIfMissingKeyDown:NO` op begin-achtige fasen en
`tapIfMissingKeyDown:YES` op eindfasen, gecombineerd met een dubbele dispatch-route die de app
niet kan uitschakelen (beide swizzels horen bij de engine, niet bij `tvos/Runner/`). Een fix hoort
dus, als het bewijs dit bevestigt, in de patchreeks: de asymmetrie wegnemen, of de tweede dispatch
voor eenzelfde fase van hetzelfde `UIPress`-object herkennen vóór `synthesizeRemotePressType:`
wordt aangeroepen.

## 3. De vierde zijdeur

`docs/tvos-remote-press-pipeline.md` noemt er drie: de passthrough-enable die alles loslaat, de
`tapIfMissingKeyDown` re-tap op een lege set, en de herhaaltimer die doorloopt zonder een
aankomende `.ended`. Uit §2 volgt een vierde, die niet via een kanaalbericht loopt:

> **Zijdeur 4.** Dezelfde fase van hetzelfde `UIPress`-object bereikt `tvosHandlePressFromUIEvent:`
> twee keer (via de twee swizzels op `UIApplication` en `UIWindow`), en op `.ended`/`.cancelled`
> synthetiseert de tweede aanroep, via `tapIfMissingKeyDown`, een fantoom Down/Up-paar omdat de
> eerste aanroep de key al verwijderd had.

Bevestigd op 15 september 2026 (build 281, log `8x94u`): drie fantoompaar-instanties, alle drie
`same-uipress`. Opgenomen als vierde zijdeur in `docs/tvos-remote-press-pipeline.md`; het
`RE-TAP(same-uipress)`-verdict in `scripts/tvos_press_trace.sh` verwijst er sindsdien expliciet
naar. Zie de correctieronde-rij (`docs/tvos-fysieke-correctieronde.md`, RAIL2) voor de volledige
classificatie per log.

## 4. `new-uipress` is geen bewijs van twee fysieke drukken

Twee verschillende `UIPress`-identiteiten (het 16-bit `ObjectIdentifier`-hash-veld dat
`tvos_press_diag` meestuurt) betekenen alleen dat de twee waargenomen deliveries niet hetzelfde
object zijn. Het bewijst niet dat de gebruiker twee keer drukte en niet dat de remote defect is:
UIKit kan onder omstandigheden méér dan één `UIPress`-object voor wat fysiek één druk was
aanmaken (bijvoorbeeld bij een focus-overgang tijdens de druk). Classificatie als
`PLATFORM_MULTIPLE_PRESS_OBJECTS` vereist eigen bewijs: de `.began`/`.ended`-levenscyclus van
beide objecten, hun `systemUptimeMs`, richting, volgorde, overlap, kanaal-delivery, keydata-
delivery, `HardwareKeyboard`-events en focusmoves moeten samen twee volledige, aparte
platform-press-levenscycli laten zien. Zonder dat bewijs is de juiste uitkomst
`UNKNOWN_HARDWARE_EVIDENCE_REQUIRED`, niet een aanname over de gebruiker of de hardware.

## 5. Wat hier expliciet niet verandert

- Station 3 (`tvos/Runner/AppDelegate.swift`) krijgt geen nieuwe state, geen teller, geen
  duplicate-detectie. Alleen de reeds geporte diagnostiek (`nl.michelknoop.pleya/tvos_press_diag`).
- Er komt geen nieuwe `TvRemoteInputCoordinator`. `AppleTvRemoteTouchService` blijft de enige
  Dart-autoriteit op station 9.
- Bestaande, op toestel getunede swipe-parameters (`nativeSwipeClassifyDistance`, de
  as-hysterese, de afstand-naar-stappenlogica, de 190 ms-cooldown) worden benoemd, niet
  herkalibreerd.

## 6. RAIL2 closure-run: protocol, beslisregels, en uitkomst

**Gedraaid op 15 september 2026, build 281 (`a7d5d3c7`), log `8x94u`.** Stap 2 bevestigd: de
diagnostiek verstuurt daadwerkelijk berichten (524 `native press=`/`native key*`-regels in de log).
Stap 3-5: snelle en normale LEFT/RIGHT-drukken op een Home-rail reproduceerden drie onafhankelijke
fantoompaar-instanties (arrowRight bij 20:29:51.971→52.026 en 20:29:57.345→57.406, arrowLeft bij
20:30:23.345→23.425; hold ≤40 ms, gat ≤80 ms), plus twee bijvangst-`RE-TAP`s binnen hetzelfde
400 ms-venster (zie de kanttekening bij het meetinstrument in `docs/tvos-fysieke-correctieronde.md`).
Alle zes `RE-TAP`s zijn `same-uipress`: `8705` voor beide arrowRight-instanties, `62021` voor de
arrowLeft-instantie. Stap 6, beslisregel toegepast: **ENGINE_DUPLICATE bevestigd**. Een
engine-lifecyclepatch is gerechtvaardigd; nog niet gebouwd.

`scripts/tvos_press_trace.sh` had tot deze run een regex-bug die de `uipress`-waarde nooit las
zodra het richtingstoken een ordinal droeg (`right(3)` in plaats van `right`), waardoor elke
`RE-TAP` als `unknown` terugkwam. Gefixt in dezelfde sessie (optioneel `(?:\(\d+\))?` na de
richtingsnaam); de classificatie hierboven staat op de gefixte versie.

Protocol en beslisregels hieronder blijven van kracht voor een volgende RAIL2-achtige meting.
Referentiebuild voor déze run was **281 (`a7d5d3c7`)**; een volgende meting kiest zijn eigen
referentiebuild.

**Stappen.**

1. Installeer exact build 281 op het toestel.
2. Bewijs eerst dat `nl.michelknoop.pleya/tvos_press_diag` daadwerkelijk in de relaylog verschijnt,
   vóór er iets over RAIL2 geconcludeerd wordt.
3. Reproduceer zowel snelle als normale LEFT/RIGHT-drukken op een Home-rail.
4. Analyseer het log met `scripts/tvos_press_trace.sh`.
5. Classificeer iedere relevante `RE-TAP` op basis van de `uipress`-identiteit en de
   `.began`/`.ended`-levenscyclus van de betrokken `UIPress`-objecten (§4: `new-uipress` alleen is
   geen bewijs van twee fysieke drukken).
6. Beslis pas dáárna of een softwarefix gerechtvaardigd is.

**Beslisregels.**

- `same-uipress` op een fantoom Down/Up-paar → **ENGINE_DUPLICATE** bevestigd; een
  engine-lifecyclepatch (de asymmetrie in `tapIfMissingKeyDown` wegnemen, of de tweede dispatch voor
  dezelfde fase van hetzelfde `UIPress`-object herkennen) is dan gerechtvaardigd.
- `new-uipress` → betekent niet automatisch een defecte remote of een tweede fysieke druk (§4); eerst
  de volledige press-levenscycli van beide objecten vergelijken (`systemUptimeMs`, richting,
  volgorde, overlap, kanaal- en keydata-delivery, focusmoves) voordat `PLATFORM_MULTIPLE_PRESS_OBJECTS`
  geclaimd wordt.
- Eén inputevent maar meerdere focusmoves in de widget-laag → **FOCUS_TRAVERSAL**, een andere laag
  en een andere fix dan ENGINE_DUPLICATE.
- Onvoldoende bewijs, ook na deze meting → open laten als `UNKNOWN_HARDWARE_EVIDENCE_REQUIRED`, niet
  gokken en geen fix bouwen op de werkhypothese alleen.
