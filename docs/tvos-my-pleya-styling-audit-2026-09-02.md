# Mijn Pleya op tvOS: de visuele audit, 2 september 2026


> **Afgerond sessiedocument.** Het werk hierin is klaar en de bevindingen zijn
> overgenomen in [tvos-redesign-register.md](tvos-redesign-register.md) en
> [tvos-fysieke-correctieronde.md](tvos-fysieke-correctieronde.md). Dit bestand blijft
> staan voor het bewijs en de redenering; zoek de actuele stand niet hier maar in
> [DESIGN-INDEX.md](DESIGN-INDEX.md).

De vorige ronde maakte de secties bedienbaar. Deze meet hoe ze eruitzien, want dat
is een andere vraag met ander bewijs. Alles hieronder komt uit één Pleya
Verify-run op de tvOS-simulator met echte HID-invoer, `tvos.my-pleya.styling-audit`,
bundel `.build/pleya-verify/tvos-my-pleya-styling-audit-1788376435255`: 24
compositor-opnames van 3840x2160 en 24 `ui_tree`-dumps, één paar per pagina-toestand.

Baseline `5be7d09`, branch `claude/netflix-redesign-b4x21v`, Flutter 3.44.0 uit
`.fvmrc`. Er is in deze ronde geen presentatiecode aangeraakt.

## Wat er eerst gebouwd moest worden

Een `snapshot` bewaarde alleen een PNG. Zes van de tien secties dragen bijna geen
automation-id, dus "waar begint de inhoud" was uit de boom niet te beantwoorden en
uit een plaatje alleen te schatten. De `snapshot`-verb dumpt nu onder dezelfde naam
ook de `ui_tree` en de viewport van datzelfde moment
(`pleya_verify/runner/lib/src/engine/run_scenario.dart`). Additief: elk bestaand
scenario krijgt de meting erbij zonder dat er iets anders van vindt.

## De coördinaten kloppen niet, en dat raakt het plan

`AutomationRegistry._boundsOf` (`lib/automation/automation_registry.dart:133-138`)
bouwt elke `Rect` als `renderObject.localToGlobal(Offset.zero) & renderObject.size`.
Die twee helften leven niet in dezelfde ruimte. `localToGlobal` lost op door de
1,85-vergroting van [DEC-028](DECISIONS.md#dec-028) heen en levert referentiepixels
op een 1920x1080-vlak; `size` blijft in de logische ruimte van 1038x584. Elke
gerapporteerde rechthoek heeft dus een positie en een maat die een factor 1,85 uit
elkaar liggen.

Drie onafhankelijke controles wijzen dezelfde kant op. De knoop `View Scope` meldt
onder één schaalaanname een breedte van 185%. De steek tussen twee hubtegels klopt
op `x * 2`, terwijl de gemeten vulling van diezelfde tegel op `w * 3,7` klopt. En
`discover.rail` meldt precies de viewportbreedte in de logische ruimte terwijl
`my_pleya.tile[logout]` tot 1652 loopt op een canvas van 1038.

Dit blokkeert hoofdstuk 22 van de opdracht. Een `leftInset`-assertie op deze bounds
zou een positie in referentiepixels tegen een viewport in logische pixels afzetten.
`insideViewport` en `notOverlapping` staan nu al op dezelfde scheve basis. De
reparatie hoort vóór de assertie, niet erna.

Voor deze audit is daarom van de opnames gemeten en niet uit de boom. Het model is
gecontroleerd tegen de tokens: de kaart in Instellingen komt uit
`(1037,84 - 880) / 2 + 16 = 94,92` logisch, oftewel 9,146%, en de meting zegt 9,14%.
De kaart in Servers komt uit `48 * 0,85 + 16 = 56,8`, oftewel 5,473%, en de meting
zegt 5,47%.

## Twaalf inhoudsranden op negen pagina's

Gemeten als percentage van de schermbreedte, op de 3840-opnames van dezelfde run.
Home is de referentie: `TvTopNavLayout.pageInset` is 48, en `48 * 0,85 * 1,85 / 1920`
is 3,93%.

| Pagina | Kop | Groeplabel | Kaart of eerste inhoud |
|---|---|---|---|
| Home (referentie) | 7,19% (heldtitel) | 3,98% | 3,93% |
| Mijn Pleya hub | 4,06% | 4,04% | 3,93% kaart, 4,17% tegelvulling |
| Servers | 4,01% | 5,96% | 5,47% |
| Bibliotheken | 2,11% | 2,06% | 0,44% tabstrip |
| Samen Kijken | 1,61% | n.v.t. | 33,02% knop |
| Instellingen | 1,67% | 9,64% | 9,14% |
| Logs en diagnose | 1,67% | n.v.t. | 1,22% |
| Over | 1,61% | n.v.t. | 1,54% en 3,07% |

Alleen Home en de hub staan op de token. Instellingen heeft drie randen op één
pagina, Over twee. De koppen van Samen Kijken, Instellingen, Logs en Over staan
alle vier rond 1,6%, want die worden door de shell getekend en niet door de
paginamarge.

Wat daaronder zit is één gedeeld bestand. `lib/widgets/settings_section.dart`
gebruikt vaste logische waarden die niet door `TvLayoutConstants.scaleOf` gaan:
`kSettingsMaxWidth = 880` (regel 14), rijpadding 16 bij 6 (regel 18), groepskop
`fromLTRB(20, 24, 20, 10)` (regel 76), kaartmarge `fromLTRB(16, 0, 16, 8)`
(regel 120), een badge van 36 met een glyph van 20 (regel 225 tot 234). Die vaste
880 is op een canvas van 1038 breed de reden dat de kaart op 81,69% van het scherm
eindigt en de rest leeg blijft. DEC-028 noteerde het al in één zin: de hele
instellingen-stack heeft geen tv-tak voor maatvoering.

Instellingen, Servers en Over gebruiken alle drie die primitieven. Dat is de reden
dat één reparatie drie pagina's raakt.

## Vier defecten die geen kwestie van smaak zijn

**De shell tekent een kop over de inhoud heen.** Op Over is de tagline "Een mooie
Plex- en Jellyfin-client voor Flutter" halverwege de letters afgesneden. Op
Instellingen schuift "Library Visibility" bij het scrollen onder dezelfde kopregel
door en wordt daar doormidden gesneden. Er is geen scrim en geen gereserveerde
bovenruimte. Bewijs: `60-about-opened.png` en `42-settings-scrolled.png`.

**Twee koppen op één pagina.** Samen Kijken en Over tekenen naast de kop van de
shell hun eigen gecentreerde titel. Logs tekent er één die anders heet dan de tegel
waar hij vandaan komt.

**Inhoud in de overscanband.** `TvCatalogLayout.topSafeInset` legt vast dat er geen
tekst en geen focusring binnen de buitenste 56 referentiepixels hoort te staan, dat
is 2,92%. De tabstrip van Bibliotheken staat op 0,44%, de logtekst op 1,22%, de
eerste kaart van Over op 1,54%. Alle drie binnen de band.

**Drie focusaffordances.** De witte ring op Home, de hub en Samen Kijken. Een
verticale balk van 3 pixels links op Instellingen, Servers en Over
(`kSettingsFocusBarWidth`). Een rode onderstreping op de tabs van Bibliotheken.

## Bibliotheken is meer dan styling

De app laadde tijdens de run twee bibliotheken. Uit `app.log` van de bundel:
`LibrariesProvider: Loaded 2 libraries`. Het scherm toont er één, heet "Movies", en
er is geen weg naar de tweede.

De keten is sluitend. `PlatformDetector.shouldUseSideNavigation` is
`isDesktop || isTV` (`lib/utils/platform_detector.dart:169-171`) en dus waar op
tvOS. `_buildAppBarTitle` neemt daarom de statische tak
(`lib/screens/libraries/libraries_screen.dart:910-925`) en bereikt
`_buildLibraryDropdownTitle` op regel 928 nooit. Die dropdown is de enige kiezer die
het scherm heeft. Welke bibliotheek je krijgt volgt uit de bewaarde sleutel
(regel 198 tot 208) of anders uit `visibleLibraries.first` (regel 211 tot 213). De
zijbalk die op desktop de tweede route levert bestaat in de TV-shell niet, en de
`ui_tree` van de geopende pagina bevat geen enkele kiezer-, dropdown- of
menuknoop.

Staat er een serie-bibliotheek vooraan, dan is dat wat de tegel "Media" laat zien.
Dat is de hardwaremelding, letterlijk.

Er zitten drie namen op één plek: de tegel heet Media, het scherm heet Movies, en
het concept heet Bibliotheken. Logs heeft dezelfde kwaal in het klein, met een tegel
"Logs en diagnose" boven een scherm "Logbestanden".

## Wat er niet geauditeerd kon worden

Kijklijst, Aanvragen en Activiteit hebben geen tegel, en dat komt niet door de
inhoud van de fixture maar door de backends erachter.

Watchlist-bronnen komen alleen uit `PlexAccountWatchlistSource` of uit een
`JellyfinClient` met `capabilities.serverFavorites`
(`lib/services/watchlist/watchlist_source_factory.dart:53-87`). Activiteit vraagt
`getPlexClient(id) != null` (`lib/providers/multi_server_provider.dart:270`).
Aanvragen vraagt een bewaarde `SeerrSession` (`lib/providers/seerr_provider.dart:41`).

De harnas kan geen van drieën leveren. `pleya_fake_server.dart:305` strookt
`/pleya/v1` van het pad en bedient tien routes van het eigen protocol.
`/v1/connections/seed` bouwt een `PleyaServerConnection` en verder niets
(`lib/automation/automation_signin.dart:169`). Een zoektocht door heel
`pleya_verify/` naar `jellyfinclient`, `plexclient`, `seerrclient` of `overseerr`
levert nul bestanden op.

Dit sluiten vraagt een nagemaakte plex.tv met Plex-server, een nagemaakte
Jellyfin-server en een nagemaakte Overseerr, plus een automation-naad per backend.
Drie subsystemen, tegen een opdracht die zegt de fixture minimaal uit te breiden.
Het staat als beslissing bij Michel en is niet eenzijdig gebouwd.

Downloads is een ander geval. Die hoort op Apple TV niet zichtbaar te zijn:
`showDownloads: !PlatformDetector.isAppleTV()`
(`lib/screens/tv/tv_my_pleya_screen.dart:274`), dezelfde predicaat als
`NavigationTab.getVisibleTabs`, zodat tegel en tab het niet oneens kunnen worden.
Geen gat, maar het productcontract.

## Classificatie

| Pagina | Klasse | Kern |
|---|---|---|
| Mijn Pleya hub | A | Staat op de tokens, witte ring, 4-op-een-rij raster |
| Servers | B | Kop op de marge, label en kaart niet, desktopkaart met scheidingslijnen |
| Instellingen | C | Drie randen, 880-cap actief, ongeschaalde desktopmaten, 5,3 rijen zichtbaar |
| Over | C | Twee kaartranden, tagline afgesneden, dezelfde desktopstapel |
| Logs en diagnose | C | Desktop-iconenbalk, tekst in de overscanband, onleesbaar op kijkafstand |
| Samen Kijken | C | Gecentreerde mobiele lege staat, tweede kop, knoppen op 33% breedte |
| Bibliotheken | E | Legacy presentatie plus één bereikbare bibliotheek van twee |

Home, Films, Series en Search zijn de referentiefamilie en blijven buiten deze ronde.

## De mockups

Acht beelden op 1920x1080, in `docs/assets/tvos-unified/mockups-2026-09-02/`, met de
opnames waar ze vandaan komen in `before/`. Ze zijn gebouwd op de echte tokens uit
`lib/widgets/tv/tv_unified_layout.dart`, omgerekend zoals de kop van dat bestand het
beschrijft: referentiepixel is basiswaarde maal `scaleOf` maal 1,85, en `scaleOf`
staat op Apple TV vast op 0,85. De controle daarop is `48 * 1,5725 = 75,5`, oftewel
3,93%, precies waar Home zijn heldkaart zet.

Wat in alle acht hetzelfde is: de topnav blijft staan, de paginamarge is 3,93%, de
kop staat op die marge, de focus is de witte ring met de ringmarge eromheen, de
oppervlakken zijn `tileFillAlpha` op zwart, en de radius is de tegelradius van de
hub. Er is geen zijbalk, geen AppBar en geen desktopwerkbalk.

Wat per pagina verandert staat in het reviewpakket hieronder.

## Reviewpakket

### Instellingen

Klasse C. `settings-a.png` (geopend) en `settings-b.png` (eerste tegel gefocust).

Gemeten nu: kop 1,67%, groeplabel 9,64%, kaart 9,14% met een breedte van 81,69%,
rijsteek 281 pixels oftewel 13,0% van de hoogte, 5,3 rijen zichtbaar en de zesde
afgesneden, badge 36 en glyph 20 zonder schaal, focus als balk van 3 pixels links.

Functioneel gelijk: dezelfde groepen, dezelfde rijen, dezelfde bestemmingen. Het
scherm is een index van instellingsecties en blijft dat.

Voorgesteld: de gedeelde paginamarge, de 880-cap eruit, en de rijen in de
tegeltaal van de hub in twee kolommen. Waarde-instellingen tonen hun huidige stand
op de tegel, zoals "OLED · Bibliotheek dichtheid 3". Acht items in beeld waar er nu
5,3 passen, met ruimte over.

Waarom dit past: het scherm is functioneel hetzelfde als de Mijn Pleya-hub, een
menu van secties, dus het krijgt de tegeltaal van de hub in plaats van een tweede,
eigen idioom.

Risico: `settings_section.dart` bedient ook iOS en macOS. De tv-tak moet aantoonbaar
niets aan die twee veranderen, en de bestaande goldens van die platforms zijn de
controle.

### Bibliotheken

Klasse E. `libraries-a.png` (index van bronnen) en `libraries-d.png` (bibliotheek
geopend, kiezer blijft in beeld).

Gemeten nu: kop 2,11%, tabstrip 0,44%, rasterinhoud eindigt rond 40% van de breedte,
desktoptitelbalk met potlood en verversknop, rode onderstreping onder de actieve tab.
Inhoudelijk: twee bibliotheken geladen, één bereikbaar, drie namen.

Functioneel gelijk: `LibrariesScreen` houdt zijn bedrijfslogica. Tabs, collecties,
afspeellijsten, metadata verversen en verbergen blijven wat ze zijn.

Voorgesteld: de pagina opent als index van bronnen. Elke zichtbare bibliotheek is
een tegel met naam, soort, aantal en server. Wie er een kiest krijgt die bibliotheek,
met een chiprij bovenaan die elke andere op één druk houdt. De tabs blijven, zonder
rode onderstreping, in de chiptaal van de rest van de TV-UI.

Waarom dit past: Home, Films en Series zijn de samengevoegde catalogus, en Mijn
Pleya ▸ Bibliotheken is de concrete bronweergave. Een index van bronnen zegt dat
met de eerste schermvulling, en er is geen toestand meer waarin de pagina stil één
bibliotheek als "Media" presenteert.

Risico: dit raakt de selectielogica, niet alleen de presentatie. De bewaarde sleutel
moet blijven werken en iOS en macOS mogen niet veranderen. Dit is de enige mockup
waar het productcontract zelf in het geding is, en de enige die ik expliciet apart
goedgekeurd wil hebben.

### Servers

Klasse B. `servers-a.png`.

Gemeten nu: kop 4,01%, label 5,96%, kaart 5,47%, drie rijen, onderste 23% van het
scherm leeg, focus als balk van 3 pixels.

Functioneel gelijk: verbinding toevoegen, media delen, de serverlijst met status en
verwijderknop.

Voorgesteld: de 20 en de 16 uit de desktopprimitieven vervallen, alles staat op
3,93%, en de rijen worden tegels in twee kolommen. De server houdt zijn statusregel.

Waarom dit past: dit is de kleinste correctie in de set. De structuur klopt al, de
randen niet.

Risico: laag. Servers is de pagina die het dichtst bij het doel staat.

### Over

Klasse C. `about-a.png`.

Gemeten nu: kop 1,61%, kaarten op 1,54% en 3,07%, tagline afgesneden onder de kop.

Functioneel gelijk: broncode, upstream, privacybeleid, licenties, en de licentietekst.

Voorgesteld: versie en toestel worden het groeplabel onder de kop, de vier links
worden tegels, en de licentietekst krijgt één tegel over de volle breedte. De
afgesneden tagline verdwijnt omdat de pagina zijn eigen gecentreerde kop niet meer
tekent.

Waarom dit past: Over is een korte lijst links plus één blok tekst. In de tegeltaal
is dat één scherm zonder scrollen.

Risico: laag.

### Logs en diagnose

Klasse C. `logs-a.png`.

Gemeten nu: kop 1,67%, logtekst op 1,22% en doorlopend tot bijna de rechterrand,
desktop-iconenbalk rechtsboven, regels te klein voor kijkafstand.

Functioneel gelijk: verversen, delen, kopiëren, wissen, en dezelfde regels.

Voorgesteld: de acties worden chips op de paginamarge in plaats van ronde
desktopknoppen, met een filter op niveau ernaast. De regels krijgen tijd, niveau en
bericht in drie kolommen op tegelgrootte, binnen één oppervlak. Negen regels
leesbaar in plaats van twintig onleesbare.

Waarom dit past: op tien voet is een logregel iets dat je scant, niet iets dat je
leest. Minder regels die je kunt lezen is meer waard dan meer regels die je niet
kunt lezen.

Risico: laag. Wel een keuze die Michel expliciet mag afwijzen als hij het volledige
logvolume in beeld wil houden.

### Samen Kijken

Klasse C. `watch-together-a.png`.

Gemeten nu: kop van de shell op 1,61% plus een eigen gecentreerde titel, knoppen van
33% breedte gecentreerd, "Sessie Deelnemen" in rood op zwart.

Functioneel gelijk: sessie maken en sessie deelnemen.

Voorgesteld: de tweede kop vervalt, de ondertitel wordt het groeplabel, en de twee
acties worden tegels naast elkaar op de paginamarge. Eronder ruimte voor recente
sessies, nu nog als lege staat die zegt wat er komt te staan.

Waarom dit past: de gecentreerde compositie is een telefoonscherm dat is
uitvergroot. Op TV begint de blik linksboven, en de rest van de app doet dat ook.

Risico: laag. Wel de kanttekening dat de rij recente sessies nieuwe inhoud is en
niet alleen een herschikking. Zonder goedkeuring daarvan blijft de pagina twee
tegels.

## Waar de simulator ophoudt

Deze audit toont bereikbaarheid, focus, backherstel, geometrie en presentatie. Echte
4K-uitvoer, echte overscan op een consumentenset, VoiceOver op kijkafstand en het
gevoel van Reduce Motion op hardware kan hij niet tonen. J2, J4, J8 en J9 blijven
open, en I17 blijft echte Android TV-hardware.

## Home hero: de artwork-audit

Aparte opdracht, later toegevoegd, met een eigen run:
`tvos.home.hero-artwork` op de nieuwe fixture `catalog.hero-artwork.v1`, bundel
`.build/pleya-verify/tvos-home-hero-artwork-1788378852939`.

### Wat er eerst gebouwd moest worden

Op `catalog.mixed.v1` is elke afbeelding een egaal vierkant van 32 bij 32. Zo'n
plaatje ziet er hetzelfde uit hoe hard je het ook bijsnijdt, dus er viel niets aan
te meten. De eerste run legde daarnaast bloot dat geen enkel fixture-item een
backdrop had: `addItem` zette `backdrop_id` hard op null, dus de hero viel terug op
zijn poster-fill en de audit zou de verkeerde codepad hebben gemeten.

Daarom twee toevoegingen aan het harnas. `calibrationPng` tekent een tiendenraster,
een eigen kleur per schermrand en een witte onderwerpsschijf op een opgegeven
positie, zodat een ontbrekende rand de bijgesneden kant benoemt en het raster telt
hoeveel er meeging. En `addItem` kreeg een `backdropId`, want poster en backdrop
zijn twee verschillende afbeeldingen en de hero tekent alleen de tweede scherp.

### De geometrie is stabiel

`discover.hero` meet in alle acht bomen van de run exact hetzelfde:
x 75,48, y 179,36, breedte 956,24, hoogte 368,88, verhouding 2,5923. Ook na een
stap terug en na een hercontrole 300 ms later. Geen hoogtewijziging, geen
layoutsprong, geen verschuivende CTA.

De verhouding zelf is niet de gedocumenteerde 2,465. `heroAspectRatio` is
`1770 / 718`, maar de hoogte wordt geklemd op `contentHeight * heroMaxHeightFraction`,
en die klem is hier actief: 956,24 / 2,465 zou 387,9 geven, en het is 368,88. De
hero is dus in de praktijk 2,592 breed tegen hoog. Dat is geen fout, wel het getal
waar de rest van deze paragraaf mee rekent.

### Wat er van elk backdrop overblijft

| Bron | Verhouding | Bijgesneden | Onderwerp op | Opschaling |
|---|---|---|---|---|
| 3840x1600 | 2,400 | 7,4% | 0,540 | 0,92x |
| 1920x1080 | 1,778 | 31,4% | 0,729 | 1,84x |
| 1600x1080 | 1,481 | 42,8% | 0,875 | 2,21x |
| 1920x1080, onderwerp laag links | 1,778 | 31,4% | **1,050** | 1,84x |
| 1920x1080, onderwerp hoog rechts | 1,778 | 31,4% | 0,408 | 1,84x |

"Onderwerp op" is de verticale positie van het onderwerp binnen de hero, waarbij 1,0
de onderrand is. Bij het vierde geval is dat 1,050: het onderwerp staat volledig
onder de onderrand en is weg. Wat er nog van te zien is, is een randje boven de
knop "Details bekijken". Dat staat op `04-slide-d.png` van die bundel.

Bij alle vijf zijn de boven-, linker- en rechterrand aanwezig en de onderrand
verdwenen. De volledige snee zit dus onderaan, wat klopt met `Alignment.topCenter`.

Een 16:9-backdrop in een 2,592-doos verliest 31,4% van zijn hoogte. Dat volgt uit de
twee verhoudingen en is met `cover` niet te vermijden. Wat wel een keuze is, is aan
welke kant je die 31,4% weghaalt, en op dit moment gaat hij er in zijn geheel
onderaan af.

### De aangevraagde afmeting

De hero heeft 3538 bij 1365 fysieke pixels nodig. Aangevraagd wordt 2560 bij 1440,
en dat komt uit `roundDimensions`: breedte en hoogte worden onafhankelijk van elkaar
geklemd op `_maxTranscodedWidth` 2560 en `_maxTranscodedHeight` 1440. Zonder die
klem zou de aanvraag 3920 bij 1560 zijn geweest, verhouding 2,513, vlak bij de doos.
Mét de klem is de aanvraag 1,778.

Dat is precies de invariant die `tv_hero_artwork.dart` in zijn eigen kop beschrijft
en die DEC-057 vastlegt: aanvraagdoos en scherpe laag hebben één vorm, zodat de
serverkant niet nog een keer snijdt. De klem breekt hem, en niet de aanroeper.

Op Plex telt dat dubbel. `thumbnailUrl` stuurt `width`, `height`, `minSize=1` en
`upscale=1` naar `/photo/:/transcode`, dus de server levert een naar 16:9 gesneden
2560x1440 en Flutter snijdt daar zijn eigen 31,4% nog eens af. Op een Pleya-server
gaat alleen `width` mee en blijft de bronverhouding staan; op Jellyfin passen
`maxWidth`/`maxHeight` binnen zonder te snijden.

De opschaling is het tweede gevolg. 2560 aangevraagd voor een vlak van 3538 fysieke
pixels is 1,38 keer opschalen, en waar de bron zelf niet groter is dan 1920 wordt
het 1,84 keer.

### Twee aanvragen per backdrop

In de aanvraaglog van de run staat elke backdrop twee keer, op `width=1360` en op
`width=2560`, en die van de eerste slide staat er drie keer. Vijf keer 1360, zes keer
2560, voor vijf afbeeldingen.

De 2560 komt van `TvHeroArtwork`. Waar de 1360 vandaan komt is niet vastgesteld: de
knoop die hem aanvraagt zit niet in de automation-boom, en `ImageType.art` heeft op
de Home-landing verder geen enkele andere afnemer. Dit staat hier als open punt met
het bewijs erbij, niet als een gok. Aanvraagidentiteit hoort stabiel te zijn, en dat
is hij niet.

### Wat het niet is

Er is geen tweede schaalgezag. Een zoektocht naar `Transform.scale`, `AnimatedScale`,
`FittedBox` en `ScaleTransition` door alle vijf de bestanden van het heropad levert
niets op. De maat wordt één keer berekend in `tv_content_feed.dart` en doorgegeven;
`TvHeroArtwork` leest zelf geen `MediaQuery`. De ingezoomde indruk komt van snijden
plus opschalen, niet van een tweede transform.

Er is ook geen aparte ambient-laag meer die zijn snijeisen aan de scherpe hero kan
opdringen. De schermvullende `TvSpotlightBackground` is vervangen door de kaart in de
pagina. De enige tweelaagse situatie die overblijft is de poster-fill, en die geldt
alleen als er helemaal geen backdrop is.

### De oorzaken

| | |
|---|---|
| TOO ZOOMED | ja |
| WRONG SOURCE SIZE | ja |
| WRONG BOXFIT | nee |
| DOUBLE SCALING | nee |
| POSITIONING ISSUE | ja |
| REQUEST SIZE ISSUE | ja |
| CAROUSEL LOAD SHIFT | nee voor geometrie, ja voor aanvraagidentiteit |
| TECHNICAL FIX ONLY | nee |
| VISIBLE COMPOSITION CHANGE REQUIRED | ja, alleen de uitsnede |

Hoofdoorzaak: de onafhankelijke klem in `roundDimensions` herschrijft de gevraagde
verhouding, waardoor de aanvraag te klein én de verkeerde vorm is.

Nevenoorzaken: `Alignment.topCenter` legt de hele snee onderaan; de `* 1,1`
overshoot in de art-tak duwt de breedte eerder tegen de klem aan; en er zijn twee
aanvraagidentiteiten per backdrop.

### Wat er zonder goedkeuring kan

De aanvraag repareren verandert niets aan wat er te zien is behalve de scherpte.
Dat is de klem verhogen of ratiobewust maken, zodat de gevraagde doos dezelfde vorm
en genoeg pixels heeft. Datzelfde geldt voor de dubbele aanvraag zodra de tweede
afnemer gevonden is. Beide zijn technische defecten en vragen geen ontwerpbesluit.

### Wat wel goedkeuring vraagt

De uitsnede. `docs/assets/tvos-unified/mockups-2026-09-02/hero-alignment-before-after.png`
zet twee titels twee keer naast elkaar, op dezelfde afbeelding, met alleen de
uitlijning anders. De hero-doos, de verhouding en `BoxFit.cover` staan in alle vier
de panelen vast.

Voorgesteld: `Alignment.center` in plaats van `Alignment.topCenter`. Het verlies
wordt dan gelijk over boven en onder verdeeld, 15,7% elk. Het onderwerp dat nu
helemaal wegvalt komt volledig in beeld, en het middengeval schuift van 0,729 terug
naar het midden.

Wat je ervoor inlevert staat in de code beschreven: `topCenter` is gekozen omdat een
te hoge backdrop dan "de lucht verliest en niet de gezichten". Met `center` gaat er
15,7% lucht af. Voor een onderwerp dat hoog in het kader staat is dat iets minder
gunstig, en dat vierde geval in de tabel schuift van 0,408 naar 0,179.

Er is geen focal-point-metadata in het protocol en die wordt hier ook niet verzonnen.
`center` is het deterministische contract; als er ooit expliciete metadata komt mag
die ervan afwijken. Geen uitlijning per titel.
