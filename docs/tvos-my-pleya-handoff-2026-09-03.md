# Handoff: Mijn Pleya en het topnav-contract op tvOS, 3 september 2026

Vervolg op `docs/tvos-my-pleya-styling-audit-2026-09-02.md`. Die ronde mat en
ontwierp; deze bouwt. Wat af is staat hieronder met zijn bewijs, wat open staat
staat er met de reden en het eerstvolgende commando.

Branch `claude/netflix-redesign-b4x21v`, bovenop `5be7d09`. Flutter 3.44.0 uit
`.fvmrc`. Nog geen commit, geen build naar hardware.

## Het topnav-contract is af

Focus op een item in de bovenbalk is voortaan de navigatie. Select is er niet
meer voor nodig en betekent nu hetzelfde als DOWN: naar binnen.

De naad lag er al. `TvTopNavigation` had `onFocusDestination` naast `onSelect`
staan, met in het commentaar erbij dat de ring bewegen de pagina niet mocht
wijzigen. De shell hing die callback aan `TvNavigationCoordinator.focusDestination`,
dat alleen de ring verplaatst. Nu gaat hij naar `MainScreen._focusTvDestination`,
dat activeert, de tab selecteert en via `TvContentFocusAuthority.onDestinationFocused`
niets wapent. De ring blijft dus staan terwijl de pagina eronder wisselt.

Er zit geen debounce in en dat is opzet. `activate` geeft false terug als er
niets verandert en `_selectTab` draait alleen op een echte wisseling, dus sneller
drukken dan pagina's laden kost werk en geen verkeerde eindtoestand.

Eén ding moest apart afgevangen worden. Zoeken staat links van Home, dus wie naar
links loopt kwam er langs, en het tekstveld greep de afstandsbediening. De
post-frame focus op dat veld staat nu achter dezelfde regel als de rest: alleen
bij een gewapende intentie, of buiten de TV-shell.

Bewijs: `tvos.nav.focus-switches-destination` draaide groen op de simulator met
echte HID-invoer, bundel
`.build/pleya-verify/tvos-nav-focus-switches-destination-1788386130771`. De
routetrace loopt `home → series → movies → myPleya` op drie keer RIGHT, en terug
`myPleya → movies → series → home → search` op vier keer LEFT, zonder één Select.

De negatieve controle is gedraaid, niet beweerd: met de oude bedrading terug
melden beide nieuwe tests `Expected: series / Actual: home`.

## Twee meetdefecten die hieronder vandaan kwamen

**`AutomationRegistry._boundsOf` mengde twee stelsels.** `localToGlobal` lost op
door de 1,85-vergroting van DEC-028 heen, `size` niet, dus elke gerapporteerde
rechthoek had een positie en een maat die een factor 1,85 uit elkaar lagen.
`MatrixUtils.transformRect(getTransformTo(null), ...)` transformeert de hele
rechthoek. `/v1/viewport` rapporteert nu hetzelfde stelsel, met `space`, `scale`
en de logische maten erbij zodat een lezer niet hoeft te raden.

**Automation-state bevroor bij de eerste build.** `FocusableWrapper` registreert
in `initState` en registreert niet opnieuw, dus het gaf de registry de closure
die op dat moment bestond. Voor een navigatiepil was dat `active: false`, voor
altijd. Het topnav-scenario haalde het eruit: `/v1/route` meldde dat de
bestemming naar Series was gegaan terwijl `nav.series.active` in hetzelfde frame
nog false stond. Nu gaat het door een thunk op `widget`, wat per constructie
actueel is.

Allebei met een regressietest en een negatieve controle.

## De canonieke inhoudsrand is een controle

`leftInset` bestaat als geometriepredicaat en neemt de marge als getal in de
eenheid van de viewport, niet als percentage. 75,48 is `pageInset` 48 maal de
0,85-clamp maal DEC-028's 1,85.

Gemeten in `tvos.my-pleya.alignment`, dat echt draaide:

| Knoop | Gemeten | Verwacht | Verschil |
|---|---|---|---|
| `discover.hero` | 75,48 | 75,48 | 0,00 |
| `my_pleya.section.content[servers]` | 75,48 | 75,48 | 0,00 |
| `my_pleya.section.content[about]` | 75,48 | 75,48 | 0,00 |

Dit kon pas nadat de bounds één stelsel gebruikten. Een linkerrandassertie op de
oude bounds vergeleek een positie in het ene stelsel met een viewport in het
andere.

## Het gedeelde frame

`lib/widgets/tv/tv_page_surface.dart` bezit de paginamarge, de kop en zijn type,
de ruimte onder de bovenbalk, de overscanmarge onderaan en de scroll.
`lib/widgets/tv/tv_menu_grid.dart` bezit de tegeltaal en de richtingswandeling.

De kop scrollt mee. Dat is de structurele helft van de reparatie voor inhoud die
door paginachrome werd doorgesneden: een vastgezette doorzichtige titel kan niets
doorsnijden waar hij niet bovenop ligt. Geen extra bovenmarge per pagina.

Focus is er bewust niet opnieuw in gebouwd. `TvNestedSurface` houdt die rol; de
twee delen alleen tokens.

## Wat er geïmplementeerd is

**Over** (`about-a`), als eigen TV-scherm, want het heeft geen gedeelde state.
De mobiele `AboutScreen` blijft wat iOS en macOS tonen en deelt nu de URL's en de
GPL-tekst met de TV-versie in plaats van ze te kopiëren.

**Servers** (`servers-a`). Dezelfde registry-stream, dezelfde schermen achter de
acties, dezelfde bevestigingen; die laatste zijn naar `ConnectionsRemoval`
verhuisd zodat een destructief pad niet in twee versies bestaat. De servertegel
draagt nu wat de audit miste: `Zolder`, met eronder `Pleya Servers · Online · 2 bibliotheken ·
verify-owner`. `TvServersScreen`, dat de desktopkaart in een TV-pagina hing, is
weg.

## Wat open staat, en waarom

**Samen Kijken** is begonnen en teruggedraaid. De TV-tak hoort in
`_NotInSessionViewState`, en die wordt door `WatchTogetherScreen` in een sliver
gezet. Een `SingleChildScrollView` daarbinnen krijgt geen hoogte, en het bewijs
daarvan was precies leesbaar: de knoop stond geregistreerd in `/v1/ui_tree` en
had geen bounds. De tak hoort dus in `WatchTogetherScreen.build` (regel 42), vóór
het sliver-scaffold, niet in de binnenste view. De i18n-sleutels
(`createSessionHint`, `joinSessionHint`, `noRecentRooms`, `noRecentRoomsHint`)
staan er al in en zijn ongebruikt tot die tak er is.

**Instellingen, Logs en Bibliotheken** zijn niet begonnen. Voor die drie geldt
dezelfde keuze als voor Samen Kijken: een TV-presentatietak binnen het bestaande
scherm, niet een kopie, omdat hun logica (dialogen, substacks, serverlijsten) niet
gedupliceerd moet worden. Over en Servers konden eigen schermen worden omdat ze
geen gedeelde state dragen.

Bibliotheken draagt daarnaast het productcontract uit hoofdstuk 16 van de
opdracht: concrete bibliotheken zichtbaar en kiesbaar, gescheiden van acties en
aggregaties, en `Movies → Shows → Movies` bewezen via Verify.

**Watchlist en Requests** hebben een geldige smalle naad (de spike staat in de
audit van 2 september) maar die is niet gebouwd. **Activity** blijft een
acceptance-gap: het predicaat is getypeerd op de concrete `PlexClient`.

## Bewijs op dit moment

`flutter analyze`: 0 errors, 0 warnings. `flutter test`: 6032 geslaagd, 6
overgeslagen, 78 gefaald, alle 78 in goldenbestanden en gelijk aan de bekende
baseline. Geen nieuwe onverwachte failures, geen `--update-goldens`.

Drie Verify-scenario's draaiden echt op de simulator, niet alleen `validate`:
`tvos.nav.focus-switches-destination`, `tvos.my-pleya.alignment` en
`tvos.home.hero-artwork`.

## Eerstvolgende commando's

```bash
export PATH="/Volumes/SSD/flutter-sdks/3.44.0/flutter/bin:$PATH"
cd pleya_verify/runner
dart run bin/verify.dart run ../scenarios/tvos.my-pleya.alignment.yaml
```

Breid dat scenario uit met elke sectie die erbij komt: het is de plek waar de
canonieke rand een controle wordt in plaats van een mening.

## Wat je niet moet doen

De 78 goldens niet met `--update-goldens` groen maken. De uitlijning van de hero
niet van `topCenter` naar `center` zetten; die is voorgelegd en afgewezen. En de
bovenbalk niet terugbedraden aan `TvNavigationCoordinator.focusDestination`, want
dat is sinds deze ronde een regressie met een test eronder.
