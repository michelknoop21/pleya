# Handoff: de resterende Mijn Pleya-secties op tvOS, 3 september 2026


> **Afgerond sessiedocument.** Het werk hierin is klaar en de bevindingen zijn
> overgenomen in [tvos-redesign-register.md](tvos-redesign-register.md) en
> [tvos-fysieke-correctieronde.md](tvos-fysieke-correctieronde.md). Dit bestand blijft
> staan voor het bewijs en de redenering; zoek de actuele stand niet hier maar in
> [DESIGN-INDEX.md](DESIGN-INDEX.md).

Vervolg op `docs/tvos-my-pleya-handoff-2026-09-03.md`. Die ronde leverde het
topnav-contract, het gedeelde paginaframe, Over en Servers. Deze bouwt de vier
punten die daar open stonden: Samen Kijken, Logs en diagnose, Instellingen, en
de bibliotheekkiezer.

Branch `claude/netflix-redesign-b4x21v`, bovenop `5be7d09`. Flutter 3.44.0 uit
`.fvmrc`. Nog geen commit.

## Wat er af is

**Samen Kijken** (`watch-together-a`). De tak zit waar de vorige handoff hem
aanwees: in `WatchTogetherScreen.build`, boven het sliver-scaffold. De reden
staat er nu als commentaar bij en als test eronder. `SliverFillRemaining` geeft
zijn kind de resterende hoogte van de viewport, en een `TvPageSurface` is een
`SingleChildScrollView`: genest in de scroll van het scaffold krijgt die geen
hoogte. Dat was ook precies het bewijs uit de vorige ronde, een knoop in
`/v1/ui_tree` zonder bounds.

Alleen de helft zonder sessie krijgt de TV-tak. De actieve sessie houdt de
gedeelde presentatie: die viel buiten de audit van 2 september en heeft geen
goedgekeurde TV-indeling, en een pagina die vooral een deelnemerslijst met twee
destructieve knoppen is wordt niet beter van gokwerk.

De recente kamers staan er wel. Dat is geen nieuwe inhoud maar dezelfde lijst
die de mobiele versie al toont, in de tegeltaal, met hetzelfde menu achter een
lang ingedrukte SELECT. Het menu bestaat sindsdien nog maar één keer
(`showRecentRoomActions`), want een van de twee acties verwijdert iets.

**Logs en diagnose** (`logs-a`). De vier acties zijn capsules op de paginamarge
in plaats van ronde desktopknoppen in een vastgezette app bar, met een
niveaufilter ernaast. De regels staan in drie kolommen: tijd, niveau, bericht.

De ruil is bewust en mag Michel afwijzen: minder regels in beeld, elk leesbaar,
in plaats van twintig die dat niet zijn. Wat er niet verandert is wat de acties
doen. Verversen, uploaden, kopiëren en wissen werken nog steeds op de hele
buffer en niet op het gefilterde beeld, want een bugrapport dat stilzwijgend de
debugregels rond de fout weglaat is slechter dan geen filter.

De paginatitel is `t.tvMyPleya.logs`, de naam van de tegel die hem opende. Dat
is de kleine helft van het naamprobleem uit de audit.

**Instellingen** (`settings-a`). Een `part` van `settings_screen.dart`, niet een
tweede scherm: elke bestemming, dialoog en voorkeurschrijfactie is de methode
die de mobiele rij al aanroept. Kopiëren zou het product twee definities van
"instellingen resetten" geven, en een daarvan is destructief.

Dezelfde rijen, dezelfde volgorde, dezelfde condities. De platformpoorten komen
uit dezelfde expressies als de mobiele lijst, dus er kan geen tegel op TV
verschijnen die de telefoon verbergt. Downloads blijft weg op een Apple TV,
Backup krimpt tot de iCloud-schakelaar, Tautulli bestaat alleen voor wie hier
een Plex-server bezit.

Eén verschil is expres. De mobiele pagina hangt `ConnectionsSection` op, die elke
server opsomt. Op TV is die lijst een eigen sectie onder Mijn Pleya ▸ Servers, en
hem hier nog eens tonen zou de derde plek in het product zijn die antwoord geeft
op "welke servers heb ik". De groep houdt de twee acties en laat de inventaris
staan waar hij hoort.

Een schakelaar is een tegel geworden die zijn stand op de waarderegel zet en op
SELECT omklapt. `toggled` is daarvoor een eigen veld en niet `selected`: een
gekozen bibliotheek verdient de opgelichte vulling, maar een instellingenpagina
waar zes ingeschakelde schakelaars zich allemaal zo tekenen heeft zes tegels die
beweren de focus te hebben.

**De bibliotheekkiezer.** Dit was het enige defect uit de audit dat niet over
styling ging, en de enige waar het productcontract van hoofdstuk 16 aan hangt.
De keten was sluitend en is nagemeten: `LibrariesProvider: Loaded 2 libraries` in
de `app.log` van de bundel, één bibliotheek in beeld, geen weg naar de tweede.
`shouldUseSideNavigation` is `isDesktop || isTV`, dus op tvOS neemt
`_buildAppBarTitle` de statische tak en bouwt de dropdown die de enige kiezer van
het scherm is nooit. Welke bibliotheek je kreeg volgde uit de bewaarde sleutel of
uit `visibleLibraries.first`, en de zijbalk die desktop zijn tweede route geeft
bestaat in de TV-shell niet.

Er staat nu een rij capsules boven de tabs, in de chiptaal die de catalogusheader
sinds hoofdstuk 10.6 al gebruikt, met de open bibliotheek als enige met een
omlijning. De selectielogica is niet aangeraakt: de capsule roept dezelfde
`_loadLibraryContent` aan als de mobiele dropdown, dus de bewaarde sleutel, het
tabherstel per bibliotheek en iOS en macOS gedragen zich exact zoals eerst.

UP vanaf de tabrij komt op de kiezer uit. UP vanaf de kiezer doet niets, met
opzet: hij is de bovenste rij van de pagina, en de app bar-iconen erboven worden
bereikt zoals de headerregel ze altijd al bereikte, met RIGHT langs de tabs. Een
tweede route erheen zou "druk UP tot je bovenaan bent" onwaar maken.

De tegel heet voortaan `t.libraries.title` en niet `t.navigation.libraries`. In
het Nederlands verschillen die twee, "Bibliotheken" tegen "Media", en dat was de
tweede helft van de drie namen op één plek.

## Drie meetdefecten die hieronder vandaan kwamen

**Tegels binnen een sectie deelden de naamruimte van de hub.** `TvMenuTile`
registreerde op `my_pleya.tile`, net als de tegels van de hub zelf. De registry
houdt elke gemounte knoop vast, ook de schermen die de shell offstage in leven
laat, en `SettingsScreen` is er zo een: hij is een `MainScreen`-bestemming én een
Mijn Pleya-sectie. Zijn tegel met sleutel `about` registreerde dus als
`my_pleya.tile[about]` naast de About-tegel van de hub, en
`tvos.my-pleya.alignment` viel om met "`my_pleya.tile[about]`.focused is false"
terwijl de bedoelde tegel er gefocust naast stond als `my_pleya.tile[about]#2`.
Sectietegels heten nu `my_pleya.section.tile`, met de paginanaam als voorvoegsel,
zodat twee secties ook onderling niet kunnen botsen.

**De registry gaf de kale id aan de verkeerde kopie.** Welke van twee
gelijknamige knopen de kale id kreeg volgde uit registratievolgorde, en de
offstage kopie registreert eerst. Twee scenario's zijn daardoor tegen het
verkeerde scherm gemeten: de kiezer wachtte zijn timeout uit op een capsule die
helemaal geen focus kan krijgen, en las daarna `library.header` als "Movies" van
de kopie die niemand had aangeraakt terwijl de pagina in beeld al op Shows stond.
`snapshot()` sorteert nu op twee signalen, in die volgorde: wordt de knoop
getekend (een wandeling door de renderboom langs `RenderOffstage` en
`RenderIndexedStack`), en kan de afstandsbediening hem bereiken
(`ExcludeFocus`, hetzelfde signaal waar `TvNestedSurface` op leunt). Bewust
zonder inherited lookup, want dit draait vanuit een HTTP-handler en niet vanuit
een build.

**Een conditioneel `selected`-veld is niet te asserteren.** De capsules en tegels
zetten `selected` alleen in de state als het waar was, dus een scenario dat
controleert dat een filter *uit* staat kreeg null en viel om op de assertie die
het had moeten halen. Het veld staat er nu altijd.

Alle drie met een regressietest en een negatieve controle. De negatieve controles
zijn gedraaid, niet beweerd: met de oude bedrading terug melden ze respectievelijk
`canRequestFocus is false`, `Expected: 'Shows' Actual: 'Movies'` en het
oorspronkelijke timeout-bericht.

## Twee dingen die de screenshots eruit haalden

De eerste run tekende de tijdkolom van de logregels te smal, waardoor het laatste
cijfer van `08:47:30.929` op een tweede regel viel en één entry twee rijen werd,
en zonder tussenruimte liep het niveau tegen de tijd aan als `08:47:31.229INFO`.
Kolombreedtes bijgesteld, `softWrap: false` erbij zodat een kolom die ooit toch
te smal is knipt in plaats van de pagina te herindelen.

De kiezer stond gecentreerd boven tabs die op de linkermarge beginnen. Een
`Column` centreert wat hij niet uitrekt. Nu links uitgelijnd op dezelfde marge
als de tabrij.

## Bewijs

`flutter analyze`: 0 errors, 0 warnings. `flutter test`: 6052 geslaagd, 6
overgeslagen, 78 gefaald, alle 78 in goldenbestanden en gelijk aan de bekende
baseline uit de vorige handoff. Geen nieuwe onverwachte failures, geen
`--update-goldens`.

Twee Verify-scenario's draaiden echt op de tvOS-simulator met HID-invoer:

- `tvos.my-pleya.alignment` meet de canonieke inhoudsrand van 75,48 op Home,
  Servers, Samen Kijken, Over, Logs en Instellingen in één run, plus dat het
  niveaufilter van Logs echt omschakelt en dat de schakelaartegels hun stand
  melden.
- `tvos.my-pleya.library-chooser` doet `Movies → Shows → Movies` en leest de
  uitkomst van `library.header`, niet van de capsule die zichzelf markeert.

Nieuwe testbestanden: `test/screens/tv/tv_watch_together_test.dart`,
`test/screens/tv/tv_logs_test.dart`,
`test/screens/libraries/tv_library_chooser_test.dart`,
`test/widgets/tv/tv_page_primitives_test.dart`, plus drie tests in
`test/automation/automation_registry_test.dart`.

## Wat open staat, en waarom

**De TV-instellingenpagina heeft geen widgettest.** `SettingsScreen` mounten in
een widgettest vraagt negen providers plus drie platformkanalen; een poging liep
vast in plaats van te falen. De pagina is in plaats daarvan end-to-end gedekt via
`tvos.my-pleya.alignment`, dat hem opent, zijn rand meet en de stand van twee
schakelaartegels leest. Wie dit wil sluiten, begint bij een providerharnas voor
`SettingsScreen`, niet bij de TV-tak.

**Instellingen en Bibliotheken zijn twee keer gemount.** Ze zijn allebei een
`MainScreen`-bestemming én een Mijn Pleya-sectie, en de shell houdt zijn
bestemmingen in een `IndexedStack` in leven. De registry wijst de kale id nu naar
de kopie in beeld, dus een assertie klopt, maar de dubbele mount zelf is er nog.
Dat is werk aan de shell, niet aan deze pagina's.

**De tabs onder de kiezer houden hun rode onderstreping.** Het voorstel voor
Bibliotheken had ze in de chiptaal willen zetten; deze ronde is expliciet
beperkt tot de kiezer, dus dat staat nog open.

**Watchlist, Aanvragen en Activiteit** zijn onveranderd. De eerste twee hebben
een geldige smalle naad (de spike staat in de audit van 2 september) die niet
gebouwd is; Activiteit blijft een acceptance-gap, want het predicaat is
getypeerd op de concrete `PlexClient`.

**`dart run tool/generate_automation_ids_yaml.dart` werkt niet meer in deze
omgeving.** De standalone VM crasht bij het compileren van de FFI-laag die het
pakket meesleept ("type 'InvalidType' is not a subtype of type 'FunctionType'").
De flutter-testtoolchain compileert hetzelfde pakket wel. Tot dat verholpen is,
is dit de weg eromheen: zet een tijdelijk testbestand neer dat `gen.main()`
aanroept, draai `flutter test` erop, gooi het weg.
`test/architecture/automation_ids_yaml_test.dart` bewaakt of de yaml klopt.

## Eerstvolgende commando's

```bash
export PATH="/Volumes/SSD/flutter-sdks/3.44.0/flutter/bin:$PATH"
cd pleya_verify/runner
dart run bin/verify.dart run ../scenarios/tvos.my-pleya.alignment.yaml
dart run bin/verify.dart run ../scenarios/tvos.my-pleya.library-chooser.yaml
```

Breid het eerste scenario uit met elke sectie die erbij komt. Het is de plek
waar de canonieke rand een controle wordt in plaats van een mening.

## Wat je niet moet doen

De 78 goldens niet met `--update-goldens` groen maken. De uitlijning van de hero
niet van `topCenter` naar `center` zetten, die is voorgelegd en afgewezen. De
bovenbalk niet terugbedraden aan `TvNavigationCoordinator.focusDestination`. En
de kiezer niet omzetten naar een index-eerst landing van Bibliotheken zonder dat
opnieuw voor te leggen: die keuze is deze ronde expliciet gemaakt en beperkt tot
de kiezer.
