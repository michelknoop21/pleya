# Implementatieregister: tvOS-redesign 09 tot en met 25

Aangelegd op 3 september 2026 bij de approval. Dit is de blijvende voortgangsadministratie voor
de heringerichte TV-oppervlakken. De approval staat in `docs/tvos-redesign-09-25-approved.md`,
de vijftien productbesluiten in `docs/tvos-redesign-implementatiecontract.md`, en de
hardwarebevindingen blijven in `docs/tvos-fysieke-correctieronde.md`.

Statussen: `OPEN`, `IN PROGRESS`, `DONE`, `DEFERRED`, `BLOCKED`. Een item krijgt bij `DONE` de
SHA en de bewijsregel erbij. Een item verdwijnt alleen door een eindstatus, nooit doordat er
later iets urgenters bijkwam.

## Volgorde

Eerst de systemische eigenaren die meerdere mockups blokkeren, in deze volgorde: het blijvende
TV-shell- en topnav-routecontract, BACK1, de TV-overlay- en sheet-presentatie, de gedeelde
staat- en lege-presentatie, en de i18n- en tokencorrectheid. Daarna 09 tot en met 12, dan 13 tot
en met 16, dan 17 tot en met 19, dan 20 tot en met 25, tenzij een afhankelijkheid aantoonbaar
een andere volgorde afdwingt.

## SYSTEMIC

| ID | Werkitem | Besluit | Status | SHA / bewijs |
|----|----------|---------|--------|--------------|
| SYS-1a | Routecontract: een TV-contentroute opent in de shell in plaats van erboven | PB-1 | DONE | `5cafc10`, DEC-091 |
| SYS-1b | Detail, collectie en persoon over dat contract | PB-1 | OPEN | |
| SYS-1c | Geneste routes krijgen de contentbox als `MediaQuery`, nodig voor de detailgeometrie | PB-1 | OPEN | |
| SYS-2 | BACK1, geen zichtbare onbereikbare terugknop op TV | PB-2 | OPEN | |
| SYS-3 | TV-overlay- en sheetgeometrie, OVR1-diagnose vóór elke breedte | PB-5 | OPEN | |
| SYS-4 | Gedeelde staat- en lege-presentatie schaalt op TV | audit | OPEN | |
| SYS-5 | i18n-gaten en hardcoded strings | audit | OPEN | |
| SYS-6 | Tokenafwijkingen per stuk beoordeeld, met regressiebeelden | tokenaudit | OPEN | |
| SYS-7 | Automation-ids en Pleya Verify-journeys per heringericht oppervlak | werkwijze | OPEN | |

## DETAIL

| ID | Werkitem | Besluit | Status | SHA / bewijs |
|----|----------|---------|--------|--------------|
| MOC-09 | Filmdetail | PB-1, PB-2, PB-3 | OPEN | |
| MOC-10 | Seriedetail, seizoenchips met één actieve afleveringenrail | PB-4 | OPEN | |
| MOC-11 | Bronkeuze met backend-icoonwel | PB-15 | OPEN | |
| MOC-12 | Unified contextmenu | PB-5 | OPEN | |

## DISCOVERY EN PERSOONLIJK

| ID | Werkitem | Besluit | Status | SHA / bewijs |
|----|----------|---------|--------|--------------|
| MOC-13 | Zoeken, permanente resultaattitel, SEARCH1 sluiten | PB-6 | OPEN | |
| MOC-14 | Kijklijst | PB-3 | OPEN | |
| MOC-15 | Aanvragen, Seerr-status blijft Seerr-state | PB-3 | OPEN | |
| MOC-16 | Activiteit, scope en capability-predicaat | PB-7 | OPEN | |

## PLAYBACK EN LIVE

| ID | Werkitem | Besluit | Status | SHA / bewijs |
|----|----------|---------|--------|--------------|
| MOC-17 | Live TV, één navigatiebalk, volledige functionaliteit | PB-8 | OPEN | |
| MOC-18 | Speler-OSD | approval | OPEN | |
| MOC-19 | Spelerinfopaneel | PB-9 | OPEN | |

## SYSTEEM EN META

| ID | Werkitem | Besluit | Status | SHA / bewijs |
|----|----------|---------|--------|--------------|
| MOC-20 | Instellingen, Uiterlijk, vier echte voorkeuren | PB-10 | OPEN | |
| MOC-21 | Profiel kiezen | approval | OPEN | |
| MOC-22 | Inloggen, eerste start | PB-11 | OPEN | |
| MOC-23 | Offline | PB-12 | OPEN | |
| MOC-24 | Collectie | PB-13 | OPEN | |
| MOC-25 | Persoon, `CanonicalPersonIdentity` | PB-14 | OPEN | |

## SYS-1a, wat er staat

`lib/navigation/tv/tv_content_route_registry.dart` is de ene plek waar een aanroeper diep in de
boom om een schermwissel vraagt zonder de shell te verliezen. `MainScreen` publiceert daar zijn
push zolang de TV-shell staat; buiten TV is er niets aangehaakt en houdt elke aanroeper de
profielnavigator die hij altijd had. Dat is bewust geen tweede `Navigator`: de reden die DEC-069
gaf om er geen te plaatsen geldt nog steeds, want `Navigator.pop` zou dan stap 2 en stap 3 van
de terugketen uit hoofdstuk 7.5 niet meer uit elkaar houden. Wat wel verviel is de tweede helft
van dat besluit, die zei dat een detailpagina hier niet hoort; PB-1 besliste het tegendeel.

`TvNestedRoute` heeft nu een resultaat, zodat een aanroeper die eerst een `Navigator.push`
afwachtte dezelfde vorm houdt. `pushNested` geeft terug welke route bovenop komt te liggen, want
bij een genegeerde dubbele push is dat niet het object dat de aanroeper meegaf, en wachten op de
verliezer duurt eeuwig. `clearNestedRoutes` sluit bij een profielwissel elk openstaand resultaat
af, anders blijft die `await` hangen.

Eerste overgenomen route: de twaalf Instellingen-subpagina's. Die zaten al in een geneste route,
want `SettingsScreen` is er zelf een, en pushten hun eigen subpagina's toch op de
profielnavigator. Het kind ontsnapte dus aan een shell waar de ouder in bleef staan.

Bewijs: `5cafc10`, met `test/screens/tv/tv_content_route_test.dart`, negen tests. De eerste is de negatieve
controle en legt het oude gedrag vast: een volledig-venster push dekt de balk af, en na die push
is niets in de balk nog bereikbaar. De tweede en derde tonen dezelfde subpagina via het nieuwe
contract, met de balk bereikbaar en de bestemmingsroot eronder blijvend gemonteerd.

## Auditbevindingen die werkitem zijn geworden

Deze staan ook als regel in `docs/tvos-fysieke-correctieronde.md`, want dat is de masterlijst.
Hier staan ze bij de werkstroom die ze bezit.

| ID | Bevinding | Werkstroom | Status |
|----|-----------|-----------|--------|
| I18N-1 | `nl.i18n.json` mist `videoControls.skipIntro`, `skipCredits`, `nextEpisode` | SYS-5 | OPEN |
| I18N-2 | `nl.i18n.json` mist `search.voiceSearch` | SYS-5 | OPEN |
| I18N-3 | `nl.i18n.json` mist `settings.visualEffects*` | SYS-5 | OPEN |
| I18N-4 | `nl.i18n.json` mist `addServer.connectToPleyaServerCard*` en `addLocalFolder.*` | SYS-5 | OPEN |
| STR-1 | Hardcoded "Video" in `tv_info_panel.dart:265` | SYS-5, MOC-19 | OPEN |
| STR-2 | Hardcoded "(Forced)" in `track_label_builder.dart:203-205` | SYS-5, MOC-19 | OPEN |
| STR-3 | Hardcoded "titles" in `actor_media_screen.dart:174` | SYS-5, MOC-25 | OPEN |
| STR-4 | Hardcoded tagline in `auth_screen.dart:341` | SYS-5, MOC-22 | OPEN |
| STR-5 | Hardcoded "Incorrect PIN" in `profile_activation.dart:57` | SYS-5, MOC-21 | OPEN |
| TOK-1 | `TvPanelTheme.accent #F42B1F` naast `kAccent` | SYS-6 | OPEN |
| TOK-2 | Serverstip `#3FBF5F` hardcoded in `tv_my_pleya_screen.dart:829` | SYS-6 | OPEN |
| PNL-1 | Infopaneel gooit secundaire spoorlabels weg, `tv_audio_subtitle_tabs.dart:103, 375, 407` | MOC-19 | OPEN |
| LIVE-1 | `PlatformDetector.shouldUseSideNavigation` waar op TV: twee navigatiebalken in Live TV | MOC-17 | OPEN |
| ACT-2 | `now_watching_screen.dart:63-70` popt via `Navigator` binnen een `TvNestedRoute` | MOC-16, SYS-1 | OPEN |
| OFF-1 | Geen reconnect-affordance op TV | MOC-23 | OPEN |
| OFF-2 | Offline topnav toont dode pills | MOC-23, SYS-1 | OPEN |
| OVR-2 | Legacy `MediaContextMenu`, rating-sheet, kijklijst-item-sheet en Live TV-sheets vallen op tvOS in een 400x400 bottom sheet | SYS-3 | OPEN |
| STA-1 | `StateView` en `EmptyStateWidget` schalen niet op TV | SYS-4 | OPEN |
| SRCH-2 | `people` wordt nooit aan `searchProjection` meegegeven | MOC-13 | OPEN |
| ACT-3 | `tvMyPleya.activitySubtitle` belooft samen kijken en remote die de tegel niet levert | MOC-16 | OPEN |

## Tokenafwijkingen uit de audit

Dertien punten, elk eerst beoordeeld op de vraag of de code een nieuwere goedgekeurde beslissing
is dan de mockup. Geen globale omkleuring, en geen wijziging zonder regressiebeeld van Home,
Films en Series.

| ID | Afwijking | Vermoedelijke winnaar | Status |
|----|-----------|----------------------|--------|
| TA-1 | Nav-itemafstand 40 tegenover ongeveer 102 in code | te beoordelen | OPEN |
| TA-2 | Kaartradius 12 tegenover 15,7 | te beoordelen | OPEN |
| TA-3 | Groepslabel 26/w500/0,72 tegenover 22/w600/0,50 in hoofdletters | code, afgeleid van september-mockup | OPEN |
| TA-4 | Vinkje wit met donkere tick tegenover donkere capsule | mockup, 33.5 zegt wit | OPEN |
| TA-5 | Nieuw-markering amber punt tegenover "NEW"-pil met gradient | mockup, hoofdstuk 34 en 33.6 | OPEN |
| TA-6 | Raillabel 31,5 tegenover 27 en de 8.3-band 25 tot 28 | te beoordelen | OPEN |
| TA-7 | Scrim `#141414` op 0,72 tegenover zwart op 0,50 of 0,34 | te beoordelen | OPEN |
| TA-8 | Progress-track wit 0,25 tegenover zwart 0,45 | te beoordelen | OPEN |
| TA-9 | Ring-gap op chips en knoppen 8 tegenover 4,7 | te beoordelen | OPEN |
| TA-10 | Standaardthema OLED, alle alpha-fills landen donkerder dan gemeten | code | OPEN |
| TA-11 | Eén inktladder in de mockup, vijf in de code | te beoordelen | OPEN |
| TA-12 | Drie groenen voor één statuskleur | mockup, één token | OPEN |
| TA-13 | Topnav-dim bij een overlay heeft geen implementatie | mockup | OPEN |

De HTML-bron loopt zelf achter op DEC-087: `_src/tv.css` presenteert 267x400 en 400x225 nog als
bindend terwijl DEC-087 de railband 346, de 16:9-kaart 615 en de buren 231 autoriseert. Daar
wint de code.

## Fysieke controlepunten

Drie momenten waarop een Release-build rechtstreeks via Xcode op de gepairde Apple TV gaat.
Geen TestFlight nodig zolang die route werkt.

| Punt | Wanneer | Status |
|------|---------|--------|
| A | Na de systemische shell- en detailronde | OPEN |
| B | Na playback en Live TV | OPEN |
| C | Finale kandidaat | OPEN |
