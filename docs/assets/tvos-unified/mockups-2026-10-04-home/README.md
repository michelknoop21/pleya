# Mockup 38 tot en met 40 en iPhone 22 tot en met 24: Verder kijken en Home

4 oktober 2026 · beoordeeld door Michel dezelfde dag, zie de statustabel hieronder. Fase 1 (kaartstatus) is vrijgegeven tegen 38 A en 22.

## Status per beeld na de beoordeling

| Beeld | Status | Verwerkt |
|---|---|---|
| 38 A | goedgekeurd | 16:9 blijft, rijkop met teller en Alles-ingang blijft |
| 38 B | referentie, geen akkoord nodig | blijft staan als bewijs voor de oude compositie |
| 38 C | goedgekeurd na correctie | focusregel ingekort tot `S3 E4 · Violet · 18 min over`; laatst gekeken, jaar en genre weg. Dit is het DEC-087-amendement |
| 38 D | goedgekeurd na tekstfix | ondertitel is nu "binnen elke sectie op laatst gekeken" |
| 38 E | goedgekeurd na correctie | "Op alle bronnen" alleen als elke gemergde bron verwijderen kan; de inzet toont de regel voor een puur Plex-item en een Plex+Jellyfin-item |
| 39 | deels goedgekeurd | Kijklijst aan, Nu op tv als opt-in; Beschikbaar gekomen uitgesteld en uit het beeld gehaald |
| 40 | goedgekeurd | neemt de 38 E-correctie over |
| 22 | goedgekeurd | lagere hero blijft |
| 23 | goedgekeurd | afleveringstitel, resterende tijd en laatst gekeken blijven hier |
| 24 | deels goedgekeurd | zelfde als 39 |

Besluiten uit de beoordeling: Eerder begonnen gebruikt een vaste grens van drie maanden, geen
gebruikersinstelling; een recent beschikbaar gekomen vervolgaflevering overrult die ouderdom en een
ontbrekende datum telt nooit als oud. Live TV in de topnav was in beeld 39 een mockupvlag; in de
app is de tab capability-gestuurd (`lib/navigation/navigation_tabs.dart:251`), dus de beelden zijn
gelijkgetrokken. Apart UX-punt voor een latere ronde: iPhone 22 toont bovenin Home/Series/Films
én onderin dezelfde tabs; als de chips functioneel hetzelfde doen als de tabbalk kunnen ze weg.

De vraag was hoe Home meer overzicht geeft, en dan vooral de rij Verder kijken. De
ontwerpopdracht die aan deze set vooraf ging: Home maakt bij openen direct duidelijk wat je
kunt hervatten; Verder kijken onderscheidt begonnen content en volgende afleveringen
herkenbaar; het volledige overzicht ordent alles in precies één sectie per item; extra
Home-rijen ondersteunen, ze zijn niet het middel.

Alle beelden gebruiken één dataset: 23 titels na mergen, ontdubbelen en verbergen, waarvan 14
getekend. Daarin zitten vier begonnen afleveringen, drie begonnen films, vier volgende
afleveringen, drie oude kijkactiviteiten (4 tot 11 maanden), twee kaarten met "2 bronnen", één
Jellyfin-kaart en twee lange titels (Everything Everywhere All at Once, A Stranger Comes to
Town). De iPhone-beelden staan in `../../ios-unified/mockups-2026-10-04-home/`.

## Wat elk beeld is

| Beeld | Scherm | Rol |
|---|---|---|
| `38-verder-kijken-a` | TV Home bij openen | het voorstel: vier 16:9-kaarten met titel en status zichtbaar zonder scrollen |
| `38-verder-kijken-b` | TV Home bij openen | referentie: dezelfde dataset in de goedgekeurde compositie van mockup 30 A1. Toont wat je nu ziet: posters zonder titel, status of teller |
| `38-verder-kijken-c` | TV Home, rij gefocust | bijschrift met afleveringstitel en laatst gekeken, alleen voor de gefocuste kaart |
| `38-verder-kijken-d` | TV Verder kijken, volledig overzicht | vier secties, Verborgen items rechtsboven |
| `38-verder-kijken-e` | TV contextmenu op een Jellyfin-kaart | Verbergen met reikwijdte in de regel; inzet met de Plex-variant |
| `39-home-extra-rijen` | TV Home, verder gescrold | Kijklijst aan; Nu op tv en Beschikbaar gekomen als aangezette optie |
| `40-desktop-overzicht` | desktop en iPad liggend, 1440x900 | hetzelfde overzicht met vijf kaarten per rij en het menu achter de drie puntjes |
| `22-home-verder-kijken` | iPhone Home bij openen | hero plus twee kaarten met status in beeld |
| `23-verder-kijken-alles` | iPhone volledig overzicht | lijstrijen met still, afleveringstitel en statusregel |
| `24-home-extra-rijen` | iPhone Home, gescrold | Recent uitgebracht, Kijklijst, Nu op tv, Beschikbaar gekomen |

## Kaartcontract

Twee kaarttypen, op elk platform dezelfde regel:

| Begonnen | Volgende aflevering |
|---|---|
| **The Bear** | **Andor** |
| `S3 E4 · 18 min over` | `S2 E5 · Volgende aflevering` |
| voortgangsbalk | geen balk, de status staat in de tekst |

Films krijgen `42 min over`. Serienaam op de kaart is geen groepering: Shōgun S1 E9 en een
eventuele S1 E10 blijven twee kaarten (§11.8 van de experience blijft staan). Afleveringstitel
en "2 dagen geleden" verschijnen pas bij focus (TV, beeld C) en in het volledige overzicht.

## Gemeten maatvoering

TV, beeld A: herotekst 452 tot 712, rijkop op 762 (label 27, teller in ink-3, Alles-ingang als
chip van 40 hoog), kaarten 400x225 van 832 tot 1057, gutter 22. Vier kaarten plus 155 van de
vijfde in beeld. De overlay in de kaart: titel 21/700, statusregel 18 in ink-2, balk 6 in het
accent. Beeld B houdt mockup 30 A1 exact: tekst 579 tot 840, label 880, posters piepen 147 van
346.

TV, beeld C: label op 132 zoals mockup 30 B, gefocuste kaart schaalt 1,05 met ring 4 op gap 8,
bijschrift 24 onder de rij: titel 27, metaregel 20, synopsis 19 op één regel. Volgende rij
begint op 586.

TV, beeld D: paginakop op 132, secties met label 26 en teller 22 in ink-3, kaarten 336x189,
sectieafstand 24. Drie secties passen boven de vouw; Eerder begonnen begint op 1058 en is
daarmee bewust nog net zichtbaar als vierde kop.

Desktop, beeld 40: balk 64, inset 32, vijf kaarten van 259x146 per rij, menu 330 breed met
regels van 36.

iPhone: hero 372 hoog in plaats van 540 uit `home-comp.png`; de rij Verder kijken staat met
twee 212x119-kaarten en twee tekstregels volledig boven de tabbalk. In het overzicht (23) zijn
de rijen 64 hoog met een still van 96 breed; de drie puntjes rechts openen hetzelfde menu als
op TV.

## Keuzes die goedkeuring vragen

1. **Verder kijken in rust als 16:9 in plaats van 2:3.** Dit wijkt af van §33.1 (posters piepen
   onder de hero) en van mockup 30 A1. Beeld B laat zien wat de goedgekeurde compositie met
   dezelfde data oplevert: niets van de status is zichtbaar voordat je scrolt. Beeld A koopt die
   zichtbaarheid met een iets hoger geplaatste herotekst (127 omhoog) en een rij van 225 in plaats
   van een strook van 147.
2. **De TV-focusregel wijkt af van DEC-087.** Vastgelegd was `S2 E4 · 18 min resterend · jaar ·
   genre`. Voorgesteld: `S3 E4 · Violet · 18 min over · 2 dagen geleden · 2022 · Drama`. Twee
   feiten erbij (afleveringstitel, laatst gekeken) en "over" in plaats van "resterend", omdat
   dezelfde regel ook in de kaart staat waar "resterend" niet past. Vraagt een amendement op
   DEC-087.
3. **Alles-ingang bij de rijtitel** (`Verder kijken · 23  Alles bekijken`). De teller is de
   werkelijke lijst na mergen, ontdubbelen en verbergen; de Home-cap van 20 geldt daarna. De
   eindtegel "Alle 23" is in beeld A niet getekend omdat hij buiten beeld valt; hij blijft als
   tweede ingang.
4. **Sectie-indeling van het overzicht**: Series hervatten, Films hervatten, Volgende afleveringen,
   Eerder begonnen. Indeling op herkomst uit de bron (resume versus next_up), niet alleen op
   voortgang. Eerder begonnen is in de beelden alles ouder dan drie maanden; de drempel is open,
   zie hieronder.
5. **Verbergen versus Verwijderen.** Eén regel per capability, met de reikwijdte in de regel:
   "Verwijderen uit Verder kijken · Op alle bronnen" op Plex en Pleya Server, "Verbergen uit
   Verder kijken · Alleen op dit apparaat" op Jellyfin, Emby en lokale mappen. Lokaal verbergen
   onderdrukt alle samengevoegde bronvarianten maar synchroniseert niet naar andere apparaten.
   Herstel via Verborgen items in het overzicht.
6. **Defaults van de extra rijen.** Kijklijst standaard aan zodra hij gevuld is. Nu op tv en
   Beschikbaar gekomen bestaan als rij maar staan standaard uit; de ondertitel in beeld 39 en 24
   is uitleg voor de reviewer, niet iets dat de app toont. Aanvragen op Home toont alleen
   aanvragen die nu afspeelbaar zijn; het statusoverzicht met aangevraagd en afgewezen blijft op
   het tabblad.

## Wat de set openlaat

- De drempel voor Eerder begonnen. Drie maanden in de beelden, maar een serie waarvan gisteren
  een nieuwe aflevering binnenkwam hoort daar niet, ook al is de laatste kijkactiviteit oud.
  De regel wordt "laatste relevante kijkactiviteit", en een ontbrekende datum betekent niet oud.
- Focus- en scrollherstel bij terugkeer uit detail of overzicht. Niet te tekenen, wel een
  acceptatiecriterium voor de bouw.
- Of Beschikbaar gekomen op Home überhaupt moet. De planner adviseerde uitstel omdat een
  aanvraag geen `MediaItem` is; de rij is hier getekend met alleen items die naar een
  server-item resolven.
- Jellyfin Live TV: Nu op tv is Plex-only getekend omdat alleen Plex een "nu op"-feed levert.
- De desktopchrome. Beeld 40 toont een balk met terugknop omdat de huidige desktop-Home geen
  vaste kop heeft; de werkelijke navigatie van de app blijft leidend.

## Bewuste verschillen met northstar en eerdere mockups

- 16:9 in rust (keuze 1) en de uitgebreide focusregel (keuze 2), zie boven.
- Beeld C laat de gefocuste kaart alleen schalen; §33.2 schrijft een verbreding naar 711 voor
  wanneer de rustkaart 2:3 is. Met 16:9-rustkaarten is die verbreding niet meer nodig.
- Geen filterchips boven de rails (DEC-100 blijft staan). Het overzicht ordent met vaste secties,
  niet met filters.
- Eerder begonnen dimt de still 30 procent, niet de tekst.
- De iPhone-hero is lager dan in `home-comp.png`, zodat de rij Verder kijken bij openen in beeld
  staat. DEC-102 en DEC-103 (eigen iPhone-scherm, iPad op desktopindeling) blijven staan.

## Reproduceerbaarheid

TV en desktop: `node build.mjs 38- 39- 40-` in `../src/` met `PLEYA_MOCKUP_ART` op de art-map
in `~/Downloads/Design-en-mockups/mockups-tvos/_src/art`. `build.mjs` leest sinds deze set een
`<!-- viewport:1440x900 -->`-regel in een pagina; zonder die regel blijft alles 1920x1080.
iPhone: `node build.mjs 22- 23- 24-` in `~/Downloads/Design-en-mockups/mockups/_src/`; die bron
staat buiten de repo, zoals de rest van de iOS-set.

Twee runs direct na elkaar: zes van de tien beelden byte-identiek. Beeld 38 A, 38 C, 40 en 24
verschillen in 32 tot 57 pixels, allemaal binnen één foto (JPEG-decodering in Chromium), nooit
in tekst of layout. Een derde run van 38 A en 38 C was identiek aan de tweede. Dat bewijst dat
de bron de beelden reproduceert. Het bewijst niet dat een kijker sneller de juiste aflevering
vindt; daarvoor is de bouw plus een Verify-run met echte data nodig.
