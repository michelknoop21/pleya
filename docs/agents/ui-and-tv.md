# UI, navigation and TV

Read only when the task touches this domain. Inline code paths are relative to the repository root.

`docs/tvos-fysieke-correctieronde.md` is de bindende werklijst voor alles wat op een fysieke
Apple TV is gemeld en nog niet dicht is. Elke bevinding staat er met een status, een root cause
voor zover bekend, en de SHA waarmee hij gesloten is.

**Voordat je aan tvOS-werk begint, lees die lijst.** Werk de items er één voor één af, in de
volgorde van de tabel, en houd je aan de zes stappen die er bovenaan staan: reproduceren, root
cause bij de gedeelde eigenaar, negatieve controle die aantoonbaar rood was, fix, gerichte tests,
en dan pas committen.

**Alles wat erbij komt gaat er ook in.** Een nieuw plan, een werkwijze, een functieverzoek, een
bugfix, een losse melding die werk oplevert: zet hem als regel in de tabel voordat je begint, en
vink hem af met de SHA wanneer hij klaar is. Een item verdwijnt alleen door een eindstatus te
krijgen, nooit doordat er later iets urgenters bijkwam.

Een bevinding die alleen op hardware te toetsen is krijgt `HARDWARE ONLY` en blijft open tot er een
device-run is geweest. De simulator heeft geen aanraakvlak, dus invoer die over de touch-surface van
de Siri Remote loopt is daar principieel niet te reproduceren.

`docs/unified-2026-closure.md` bezit de werkvolgorde en de releasegate voor de Pleya Unified
2026-afronding op iOS en tvOS; `docs/ios-unified-implementation-register.md` is daarbij de
iOS-werklijst, naast het bestaande `docs/tvos-redesign-register.md` voor tvOS.

## Pleya Verify

`pleya_verify/` drijft echte scenario's tegen een echte macOS/iOS-sim/tvOS-sim-build, over een vast
`/v1/*`-transportcontract, met een bewaarde bewijsbundel als resultaat. Zie
`docs/architecture/pleya-verify.md` voor het ontwerp en `docs/testing/pleya-verify-for-agents.md`
voor hoe je een scenario draait of schrijft; `pleya_verify/README.md` is het snelle overzicht.

**Agentregel.** Een relevante UI-/focuswijziging is niet volledig geverifieerd zonder passende
Pleya Verify-assertions en visuele evidence, tenzij de omgeving aantoonbaar geen ondersteund target
kan draaien: rapporteer dan expliciet welk bewijs ontbreekt in plaats van de wijziging als
geverifieerd te melden. Dit is geen zware gate voor pure backendcode: een wijziging die geen focus,
navigatie of layout raakt, hoeft geen scenario te krijgen.

## Known failure modes

- **tvOS remote-input: de engine claimt élke press, niet de responder chain.** De gepinde fork-engine (`tvos/engine.version`) swizzlet `-[UIApplication sendEvent:]` én `-[UIWindow sendEvent:]` en vraagt per press aan `-[FlutterViewController tvosHandlePressFromUIEvent:]` of hij hem mag claimen. De engine-implementatie eindigt in `synthesizeRemotePressType:`, die **onvoorwaardelijk YES** geeft, en bij YES wordt de originele `sendEvent:` overgeslagen: UIKit begint zijn responder chain dan nooit. Gevolgen die je uren kosten als je dit niet weet:
  - `pressesBegan/Ended`-overrides, `canBecomeFirstResponder` en `resignFirstResponder` draaien op een pad dat bij een geclaimde press **nooit** wordt uitgevoerd. Daar iets repareren doet niets.
  - Een Dart-antwoord (`KeyEventResult.handled`, of `true` uit een `HardwareKeyboard`-handler) komt te laat: `sendEvent:` is dan al teruggekeerd. Dart kan een press niet aan UIKit teruggeven.
  - Vegen over het aanraakvlak is `UIEventTypeTouches` en wordt door de swizzle genegeerd, dus die werkt altijd. Werkt navigeren wel maar klikken niet, dan is dit vrijwel zeker de oorzaak.
  - De enige plek die werkt is `PleyaFlutterViewController.tvosHandlePress(fromUIEvent:)` (`tvos/Runner/AppDelegate.swift`), die tijdens een native tekstinvoersessie `false` geeft **zonder `super` aan te roepen**. Super synthetiseert de press; meelopen brengt het achtergrondlek terug. De selector staat in geen publieke header en wordt gedeclareerd in `Runner-Bridging-Header.h`. Zie [DEC-019](../DECISIONS.md#dec-019) en DEC-017 voor de volledige redenering, inclusief disassembly-adressen.
  - **De fork is een patchreeks, geen bron. Lees hem vóór je bouwt.** `scripts/tvos_engine_source.sh` reconstrueert `FlutterViewController.mm` in een minuut; `docs/tvos-remote-press-pipeline.md` heeft het pad per station en een symptoomtabel. De engine houdt staat bij die je vanuit Swift of Dart niet ziet: `synthesizedPressedKeys`, een herhaaltimer (0,4 s, dan 80 ms) en `releaseAllSynthesizedPresses` bij het aanzetten van de Menu-passthrough. Dat laatste was NAV1 (DEC-099): acht builds in de fasen gezocht, oorzaak stond in twintig regels ObjC. Een fase inslikken laat de timer eeuwig lopen (build 257), een fase doorgeven crasht UIKit (build 256).
  - Na een bump van `tvos/engine.version` opnieuw valideren: `AppDelegate` logt bij het opstarten `engine press hook available=…`. Staat daar `false`, dan is het toetsenbord stil kapot.

- **Een kaal Material-widget met een selectiestaat is in dit thema onzichtbaar.** `monoTheme` mapt `secondaryContainer`, `primaryContainer`, `surfaceContainerHighest` en `surfaceBright` allemaal op `c.surface`, dezelfde kleur als de kaart eronder, en zet daarbij `NoSplash` met een doorzichtige highlight. Een `SegmentedButton` met `showSelectedIcon: false` had daardoor nul zichtbaar verschil tussen gekozen en niet-gekozen; de instelling werkte, je zag het alleen niet. Gebruik de eigen widgets (`FocusableFilterChip`, `FocusableTabChip`, `SegmentedTabGroup`) of controleer de staat expliciet tegen het oppervlak erachter. Zie [DEC-053](../DECISIONS.md#dec-053).

- **De browse-UI hangt onder een geneste Navigator, een `OverlayEntry` in de root-overlay niet.** `ProfileSessionScreen` zet `ProfileNavigationScope` om een eigen `Navigator`, en alles wat de app daarna pusht (detailpagina, speler, menu's) hoort dáárin. Een met de hand ingevoegde `OverlayEntry` (`Overlay.of(context, rootOverlay: true)`) zit juist boven die scope. Navigeer je met de `BuildContext` van zo'n entry, dan pusht `Navigator.of` op de root-navigator en gooit het geopende scherm meteen `StateError: ProfileNavigationScope is required for profile routes.`; in release is dat een foutwidget over het hele venster, oftewel een zwart scherm. Gebruik in overlay-inhoud dus altijd de context van de widget die de overlay opzette, niet die van de builder. Tweede adder onder hetzelfde gras: `Navigator` draait bij elke push `Overlay.rearrange`, en die zet entries die hij niet zelf beheert expliciet terug bovenop álle route-entries. Een preview die blijft staan, zweeft daardoor boven een net geopend menu en slikt de kliks erop, dus sluit hem vóór je iets opent. `test/widgets/hover_boxart_overlay_test.dart` bewaakt allebei.

- **Een animerende zijbalk moet zijn eigen band bezitten, en dat volgt uit de breedte, niet uit een boolean.** `isCollapsed` klapt synchroon om, de breedte animeert er 200 ms achteraan, en in dat gat kan een klik die voor het menu bedoeld was op de content eronder landen. De hover-zone was daarbij een proxy over de animerende container, dus nooit breder dan de balk op dat moment: wie naar een label toe beweegt haalt de easeOutCubic in en start de collapse-timer. Andersom legde `IgnorePointer(ignoring: isCollapsed)` alle rijen dood terwijl de balk nog op volle breedte stond te tekenen. `side_navigation_rail.dart` lost dat op met drie lagen op één mirror-tween: een `AbsorbPointer` over `max(getekend, doel)`, de balk zelf, en bovenop een translucent `MouseRegion` die de hele band ziet maar niets pakt (die komt wél in het hit-pad en geeft toch `false`, dus de `Stack` loopt door naar de content). Alles wat met interactiviteit te maken heeft leest de getekende breedte. **Repareer dit nooit met een debounce of een `AppLifecycleState`-venster.** Het is layout en hit-test-eigendom, en de vijf pointer-tests in `test/widgets/side_navigation_rail_test.dart` waren vóór de fix rood.

- **De tvOS-variant hiervan is onderzocht en niet aangetoond.** `NavigationRailItem` activeert Select op `KeyDownEvent`, waarna `onDestinationSelected` de focus meteen naar de content verplaatst, en op tvOS levert de engine KeyDown en KeyUp in één callback. Het is de enige plek in de codebase die op Select activeert, focus verplaatst en `SelectKeyUpSuppressor.suppressSelectUntilKeyUp()` niet wapent (elf andere plekken wel). Toch lekt het niet: `handleOneShotSelect` negeert een KeyUp en `FocusableWrapper` weigert een release waarvan hij de druk niet zag. In de simulator was het ook niet te reproduceren. Drie contracttests in `side_navigation_rail_test.dart` leggen dat vast. Komt er een nieuwe tvOS-melding, begin dan bij het focus- en key-eventpad, niet bij timing.
