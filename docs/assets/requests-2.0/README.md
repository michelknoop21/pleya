# Requests 2.0, voorstelset A-20

**Status: ONTWERP GOEDGEKEURD, 8 oktober 2026.** Michel Knoop heeft de volledige set met
alle zeven keuzes hieronder goedgekeurd, onder voorwaarde van Impeccable polish. Opus heeft
de polish uitgevoerd; de onafhankelijke review en documentfixreview zijn akkoord. Daarmee
is de ontwerpvoorwaarde vervuld en kan A-21 binnen de bestaande WIP- en reviewgates starten.
Niets in deze map is appimplementatie, simulatoracceptatie of hardwareacceptatie.

Roadmap: A-20. De specificatie waar deze set bij hoort is
[docs/requests-2.0-spec.md](../../requests-2.0-spec.md) (A-19). De beelden openen het
makkelijkst via [index.html](index.html); [manifest.json](manifest.json) bevat dezelfde
koppeling van staat naar bestand in machineleesbare vorm.

## Wat er ligt

72 staten in de acht families uit de spec, elk getekend voor TV, telefoon, tablet en
desktop: 170 beelden. Een scherm krijgt op TV, tablet en desktop een eigen beeld. Overlays
(formulier, menu, bevestiging) staan op borden met twee of drie panelen op ware grootte.
De telefoon staat altijd op een bord van vier. Boven elk paneel staat de code uit de matrix
hieronder, bijvoorbeeld 4C.

| Platform | Map | Los beeld | Bord | Aantal |
|---|---|---|---|---|
| TV (tvOS, Android TV) | `tv/` | 1920x1136 | 1920x1080, twee panelen van 944x1024 | 54 |
| Telefoon (iOS, Android) | `phone/` | geen | 3456x1924 op 2x, vier panelen van 402x874 pt | 20 |
| Tablet (iPadOS, Android liggend) | `tablet/` | 1180x876 | 1720x820, drie panelen van 560x764 | 48 |
| Desktop (macOS, Windows, Linux) | `desktop/` | 1440x956 | 1440x900, drie panelen van 464x844 | 48 |

Boven elk scherm en elk paneel staat een strook van 56 px (telefoon 40) met de code en de naam
van de staat. Die strook hoort bij het beeld en niet bij het scherm: een los beeld is daardoor
56 px hoger dan het scherm dat eronder op ware grootte staat (TV 1920x1080, tablet 1180x820,
desktop 1440x900). In het scherm zelf staat geen voorsteltekst meer.

Een bordpaneel van een overlay is een uitsnede rond de overlay, niet het hele scherm. De
overlay zelf heeft de maat die hij op dat platform zou hebben: 820 breed op TV, 520 op
tablet, 430 op desktop, schermbreed vanaf de onderrand op de telefoon.

## Waar de vormtaal vandaan komt

Er is geen nieuwe shell, kaart of kleur bijgekomen. `src/rq.css` laadt de tokens, de fonts
en de topnav uit `../tvos-unified/src/tv.css` en voegt alleen de Requests-onderdelen toe.

| Onderdeel | Basis |
|---|---|
| Ontdekken in kaarttaal, railregels, raster met statuscapsule, statusrail met aantallen | mockup 35 A, B, **C1** en D, goedgekeurd onder DEC-108 ([manifest](../../tvos-redesign-34-36-approved.md)) |
| Zoekveld, sectiekop als kop, uitweg naar Aanvragen | mockup 36 A tot en met C, DEC-108 |
| Detailhero, informatiegroep, knoppenrij | mockup 37 A, DEC-109 |
| TV-overlay met posterkop en keuzerijen | mockup 12 (contextmenu) |
| Bevestigingsdialoog met de veilige knop in focus | mockup 42 A, zelf nog PROPOSED: een vormverwijzing, geen goedgekeurde basis |
| Telefoonkop, rode gekozen chip, aanvraagrijen, tabbalk | `../ios-unified/northstar/19-aanvragen.png` |
| Desktop en tablet liggend: balk met terugpijl, dichte lijst, menu achter de drie puntjes | mockup 40 |

35 C2 is niet gebruikt. Op TV blijven aanvragen een raster en lopen acties via het
contextmenu, zoals DEC-108 vastlegt. De rijen met knoppen op telefoon, tablet en desktop
zijn het bestaande gedrag van `seerr_request_row.dart`, niet C2 in een andere maat.

## Wat een beeld wel en niet zegt

De kolom "Tegenover de bron" vergelijkt met de code op `bdedec38`:

- **bestaand gedrag**: de app doet dit volgens de bronaudit al; het beeld tekent het in de
  northstartaal. Dat is geen bewijs dat het op elk platform zo werkt.
- **gewijzigd gedrag**: de app doet hier nu iets anders. Voorbeelden: een lege TV-lijst die
  Opnieuw aanbiedt (TVUX-36), een aantal dat nul toont als de telling mislukt.
- **nieuw, niet gebouwd**: er is geen scherm voor. Dat geldt voor de hele familie
  Aanvraagbeheer op TV (8A tot en met 8C), voor Bewerken op elk platform (8E tot en met 8J)
  en voor de twee Beschikbaar-staten in detail (3E en 3F).

Titels, aanvragers, aantallen, servernamen en paden zijn fixture. De posters met foto komen
uit de Blender-openfilms in `../ios-unified/detail-2026/`; de effen covers dragen het woord
FIXTURE. Het toetsenbord in 2A is een aanduiding van het systeemtoetsenbord. Pleya tekent
het niet.

## Goedgekeurde keuzes

Michel Knoop heeft deze zeven keuzes op 8 oktober 2026 goedgekeurd. De technische toets bij
A-21 blijft nodig; een niet ondersteunde serverbewerking krijgt de getekende herstelroute.

1. **Beschikbaar opent nooit zelf de speler.** 3E gaat naar het bestaande Pleya-detail als
   de titel bewezen in de bibliotheek staat. 3F zoekt in de bibliotheek met de titel als
   zoekopdracht. Geen van beide noemt een bron. Dit vervangt "Beschikbaar · 4K op NAS" uit
   iOS-northstar 19, dat een bron belooft die Seerr niet kent.
2. **In afwachting krijgt een werkende hoofdknop.** 3B opent "Mijn aanvraag" waar nu een
   uitgeschakelde knop staat.
3. **Films zonder 4K-recht zien een uitlegregel met een slotje** (4B) in plaats van niets.
   Het alternatief is de regel weglaten, zoals de app nu doet.
4. **Mislukt het laden van de serveropties, dan kan een beheerder toch indienen met de
   standaard van de aanvraagserver** (6G). Het alternatief is indienen blokkeren tot de
   opties er zijn. De spec dwingt geen van beide af.
5. **Aantallen verdwijnen bij Mijn aanvragen** (7A, 7D). `/request/count` kent geen
   `requestedBy`, dus een eigen telling is niet te bewijzen. De statusrail blijft, zonder
   getallen en met één regel uitleg.
6. **Bewerken is beperkt tot aanvragen in afwachting** (8E tot en met 8H): seizoenen voor de
   aanvrager, 4K en doel voor de beheerder. Of Seerr elke wijziging toestaat is in A-21 te
   toetsen; 8G en 8H tekenen wat er gebeurt als dat niet zo is.
7. **Goedkeuren en afwijzen vragen geen bevestiging, annuleren wel** (8A, 8D). Dat is het
   huidige gedrag op touch en is hier naar TV doorgetrokken.

## Wat er niet in zit

- **Licht thema.** Alle beelden zijn donker, zoals de sets waarop ze leunen.
- **Tablet staand en smalle desktopvensters.** De tablet is alleen liggend getekend
  (1180x820), de desktop alleen op 1440x900.
- **Android-eigen vormen.** Telefoon en tablet tonen de iOS-statusbalk en tabbalk. Het
  gedrag is hetzelfde bedoeld; systeembalk, terugknop en toetsenbord van Android staan er
  niet in.
- **Het instelscherm voor de aanvraagserver.** 1C verwijst ernaar, het scherm zelf valt
  buiten de acht families.
- **Pleya Web.** De spec noemt Web uitdrukkelijk geen Requests-oppervlak.
- **Bekende fout versus onbekende uitkomst bij Bewerken.** 8G is de weigering waarop de server
  antwoordde. 8J is de wijziging die verstuurd is zonder dat er antwoord kwam: de keuze blijft
  staan en Status controleren leest de aanvraag opnieuw voordat opnieuw opslaan mogelijk is.
  Een aparte staat voor "niet verstuurd, verbinding ontbrak al" is voor Bewerken niet getekend.
- **TV-focus tijdens laden en verzenden.** In 1D, 7F, 4G, 5G, 8I en 8K is geen focusring
  getekend. Deze set bepaalt geen focusbestemming tijdens laden of verzenden; A-21 moet
  veilige focus behouden en de bestemming expliciet verifiëren.
- **Beweging.** Focusherstel, de overgang van 6E naar 6F en het verdwijnen van een melding
  zijn elk als stilstaand moment getekend.

## Dekkingsmatrix

Elke regel is een staat uit de spec. De vier laatste kolommen wijzen naar het bestand; bij
een bord staat erbij welk paneel.

<!-- MATRIX:BEGIN -->
### 1. Ontdekken

| Code | Staat | Rol | Tegenover de bron | TV | Telefoon | Tablet | Desktop |
|---|---|---|---|---|---|---|---|
| 1A | Geladen | aanvrager | bestaand gedrag | [beeld](tv/rq-tv-1A-geladen.jpg) | [paneel 1A](phone/rq-ph-1A-1D-ontdekken.jpg) | [beeld](tablet/rq-tb-1A-geladen.jpg) | [beeld](desktop/rq-dk-1A-geladen.jpg) |
| 1B | Filters open | aanvrager | bestaand gedrag | [beeld](tv/rq-tv-1B-filters-open.jpg) | [paneel 1B](phone/rq-ph-1A-1D-ontdekken.jpg) | [beeld](tablet/rq-tb-1B-filters-open.jpg) | [beeld](desktop/rq-dk-1B-filters-open.jpg) |
| 1C | Niet ingesteld | geen koppeling | bestaand gedrag | [beeld](tv/rq-tv-1C-niet-ingesteld.jpg) | [paneel 1C](phone/rq-ph-1A-1D-ontdekken.jpg) | [beeld](tablet/rq-tb-1C-niet-ingesteld.jpg) | [beeld](desktop/rq-dk-1C-niet-ingesteld.jpg) |
| 1D | Laden | aanvrager | bestaand gedrag | [beeld](tv/rq-tv-1D-laden.jpg) | [paneel 1D](phone/rq-ph-1A-1D-ontdekken.jpg) | [beeld](tablet/rq-tb-1D-laden.jpg) | [beeld](desktop/rq-dk-1D-laden.jpg) |
| 1E | Leeg na filter | aanvrager | gewijzigd gedrag | [beeld](tv/rq-tv-1E-leeg-na-filter.jpg) | [paneel 1E](phone/rq-ph-1E-1H-ontdekken.jpg) | [beeld](tablet/rq-tb-1E-leeg-na-filter.jpg) | [beeld](desktop/rq-dk-1E-leeg-na-filter.jpg) |
| 1F | Fout met opnieuw proberen | aanvrager | bestaand gedrag | [beeld](tv/rq-tv-1F-fout-met-opnieuw-proberen.jpg) | [paneel 1F](phone/rq-ph-1E-1H-ontdekken.jpg) | [beeld](tablet/rq-tb-1F-fout-met-opnieuw-proberen.jpg) | [beeld](desktop/rq-dk-1F-fout-met-opnieuw-proberen.jpg) |
| 1G | Meer laden mislukt | aanvrager | gewijzigd gedrag | [beeld](tv/rq-tv-1G-meer-laden-mislukt.jpg) | [paneel 1G](phone/rq-ph-1E-1H-ontdekken.jpg) | [beeld](tablet/rq-tb-1G-meer-laden-mislukt.jpg) | [beeld](desktop/rq-dk-1G-meer-laden-mislukt.jpg) |
| 1H | Terugkeer naar gekozen kaart | aanvrager | gewijzigd gedrag | [beeld](tv/rq-tv-1H-terugkeer-naar-gekozen-kaart.jpg) | [paneel 1H](phone/rq-ph-1E-1H-ontdekken.jpg) | [beeld](tablet/rq-tb-1H-terugkeer-naar-gekozen-kaart.jpg) | [beeld](desktop/rq-dk-1H-terugkeer-naar-gekozen-kaart.jpg) |

### 2. Zoeken

| Code | Staat | Rol | Tegenover de bron | TV | Telefoon | Tablet | Desktop |
|---|---|---|---|---|---|---|---|
| 2A | Invoer met systeemtoetsenbord | aanvrager | bestaand gedrag | [beeld](tv/rq-tv-2A-invoer-met-systeemtoetsenbord.jpg) | [paneel 2A](phone/rq-ph-2A-2D-zoeken.jpg) | [beeld](tablet/rq-tb-2A-invoer-met-systeemtoetsenbord.jpg) | [beeld](desktop/rq-dk-2A-invoer-met-systeemtoetsenbord.jpg) |
| 2B | Resultaten gemengd | aanvrager | gewijzigd gedrag | [beeld](tv/rq-tv-2B-resultaten-gemengd.jpg) | [paneel 2B](phone/rq-ph-2A-2D-zoeken.jpg) | [beeld](tablet/rq-tb-2B-resultaten-gemengd.jpg) | [beeld](desktop/rq-dk-2B-resultaten-gemengd.jpg) |
| 2C | Geen match in bibliotheek, door naar Aanvragen | aanvrager | bestaand gedrag | [beeld](tv/rq-tv-2C-geen-match-in-bibliotheek-door-naar-aanvrage.jpg) | [paneel 2C](phone/rq-ph-2A-2D-zoeken.jpg) | [beeld](tablet/rq-tb-2C-geen-match-in-bibliotheek-door-naar-aanvrage.jpg) | [beeld](desktop/rq-dk-2C-geen-match-in-bibliotheek-door-naar-aanvrage.jpg) |
| 2D | Nergens een match | aanvrager | bestaand gedrag | [beeld](tv/rq-tv-2D-nergens-een-match.jpg) | [paneel 2D](phone/rq-ph-2A-2D-zoeken.jpg) | [beeld](tablet/rq-tb-2D-nergens-een-match.jpg) | [beeld](desktop/rq-dk-2D-nergens-een-match.jpg) |
| 2E | Onvolledig: Aanvragen antwoordde niet | aanvrager | gewijzigd gedrag | [beeld](tv/rq-tv-2E-onvolledig-aanvragen-antwoordde-niet.jpg) | [paneel 2E](phone/rq-ph-2E-2E-zoeken.jpg) | [beeld](tablet/rq-tb-2E-onvolledig-aanvragen-antwoordde-niet.jpg) | [beeld](desktop/rq-dk-2E-onvolledig-aanvragen-antwoordde-niet.jpg) |

### 3. Detail film/serie

| Code | Staat | Rol | Tegenover de bron | TV | Telefoon | Tablet | Desktop |
|---|---|---|---|---|---|---|---|
| 3A | Nog niet aangevraagd (unknown) | aanvrager | bestaand gedrag | [beeld](tv/rq-tv-3A-nog-niet-aangevraagd-unknown.jpg) | [paneel 3A](phone/rq-ph-3A-3D-detail-film-serie.jpg) | [beeld](tablet/rq-tb-3A-nog-niet-aangevraagd-unknown.jpg) | [beeld](desktop/rq-dk-3A-nog-niet-aangevraagd-unknown.jpg) |
| 3B | In afwachting (pending) | aanvrager, eigen aanvraag | gewijzigd gedrag | [beeld](tv/rq-tv-3B-in-afwachting-pending.jpg) | [paneel 3B](phone/rq-ph-3A-3D-detail-film-serie.jpg) | [beeld](tablet/rq-tb-3B-in-afwachting-pending.jpg) | [beeld](desktop/rq-dk-3B-in-afwachting-pending.jpg) |
| 3C | Bezig (processing) | aanvrager | gewijzigd gedrag | [beeld](tv/rq-tv-3C-bezig-processing.jpg) | [paneel 3C](phone/rq-ph-3A-3D-detail-film-serie.jpg) | [beeld](tablet/rq-tb-3C-bezig-processing.jpg) | [beeld](desktop/rq-dk-3C-bezig-processing.jpg) |
| 3D | Deels beschikbaar (partial), serie | aanvrager | bestaand gedrag | [beeld](tv/rq-tv-3D-deels-beschikbaar-partial-serie.jpg) | [paneel 3D](phone/rq-ph-3A-3D-detail-film-serie.jpg) | [beeld](tablet/rq-tb-3D-deels-beschikbaar-partial-serie.jpg) | [beeld](desktop/rq-dk-3D-deels-beschikbaar-partial-serie.jpg) |
| 3E | Beschikbaar, identiteit bewezen | aanvrager | nieuw, niet gebouwd | [beeld](tv/rq-tv-3E-beschikbaar-identiteit-bewezen.jpg) | [paneel 3E](phone/rq-ph-3E-3H-detail-film-serie.jpg) | [beeld](tablet/rq-tb-3E-beschikbaar-identiteit-bewezen.jpg) | [beeld](desktop/rq-dk-3E-beschikbaar-identiteit-bewezen.jpg) |
| 3F | Beschikbaar, bron onbekend | aanvrager | nieuw, niet gebouwd | [beeld](tv/rq-tv-3F-beschikbaar-bron-onbekend.jpg) | [paneel 3F](phone/rq-ph-3E-3H-detail-film-serie.jpg) | [beeld](tablet/rq-tb-3F-beschikbaar-bron-onbekend.jpg) | [beeld](desktop/rq-dk-3F-beschikbaar-bron-onbekend.jpg) |
| 3G | Afgewezen | aanvrager | gewijzigd gedrag | [beeld](tv/rq-tv-3G-afgewezen.jpg) | [paneel 3G](phone/rq-ph-3E-3H-detail-film-serie.jpg) | [beeld](tablet/rq-tb-3G-afgewezen.jpg) | [beeld](desktop/rq-dk-3G-afgewezen.jpg) |
| 3H | Status niet ververst | aanvrager | gewijzigd gedrag | [beeld](tv/rq-tv-3H-status-niet-ververst.jpg) | [paneel 3H](phone/rq-ph-3E-3H-detail-film-serie.jpg) | [beeld](tablet/rq-tb-3H-status-niet-ververst.jpg) | [beeld](desktop/rq-dk-3H-status-niet-ververst.jpg) |

### 4. Aanvraag film

| Code | Staat | Rol | Tegenover de bron | TV | Telefoon | Tablet | Desktop |
|---|---|---|---|---|---|---|---|
| 4A | Standaard: 4K toegestaan, limiet bekend | aanvrager met 4K-film | bestaand gedrag | [paneel 4A](tv/rq-tv-4A-4B-aanvraag-film.jpg) | [paneel 4A](phone/rq-ph-4A-4D-aanvraag-film.jpg) | [paneel 4A](tablet/rq-tb-4A-4C-aanvraag-film.jpg) | [paneel 4A](desktop/rq-dk-4A-4C-aanvraag-film.jpg) |
| 4B | 4K niet toegestaan voor films, onbeperkt | aanvrager zonder 4K-film | gewijzigd gedrag | [paneel 4B](tv/rq-tv-4A-4B-aanvraag-film.jpg) | [paneel 4B](phone/rq-ph-4A-4D-aanvraag-film.jpg) | [paneel 4B](tablet/rq-tb-4A-4C-aanvraag-film.jpg) | [paneel 4B](desktop/rq-dk-4A-4C-aanvraag-film.jpg) |
| 4C | Limiet onbekend | aanvrager | gewijzigd gedrag | [paneel 4C](tv/rq-tv-4C-4D-aanvraag-film.jpg) | [paneel 4C](phone/rq-ph-4A-4D-aanvraag-film.jpg) | [paneel 4C](tablet/rq-tb-4A-4C-aanvraag-film.jpg) | [paneel 4C](desktop/rq-dk-4A-4C-aanvraag-film.jpg) |
| 4D | Limiet bereikt | aanvrager | bestaand gedrag | [paneel 4D](tv/rq-tv-4C-4D-aanvraag-film.jpg) | [paneel 4D](phone/rq-ph-4A-4D-aanvraag-film.jpg) | [paneel 4D](tablet/rq-tb-4D-4F-aanvraag-film.jpg) | [paneel 4D](desktop/rq-dk-4D-4F-aanvraag-film.jpg) |
| 4E | Al aangevraagd (duplicaat) | aanvrager | bestaand gedrag | [paneel 4E](tv/rq-tv-4E-4F-aanvraag-film.jpg) | [paneel 4E](phone/rq-ph-4E-4H-aanvraag-film.jpg) | [paneel 4E](tablet/rq-tb-4D-4F-aanvraag-film.jpg) | [paneel 4E](desktop/rq-dk-4D-4F-aanvraag-film.jpg) |
| 4F | Geen aanvraagrecht | profiel zonder recht | bestaand gedrag | [paneel 4F](tv/rq-tv-4E-4F-aanvraag-film.jpg) | [paneel 4F](phone/rq-ph-4E-4H-aanvraag-film.jpg) | [paneel 4F](tablet/rq-tb-4D-4F-aanvraag-film.jpg) | [paneel 4F](desktop/rq-dk-4D-4F-aanvraag-film.jpg) |
| 4G | Bezig met indienen | aanvrager | bestaand gedrag | [paneel 4G](tv/rq-tv-4G-4H-aanvraag-film.jpg) | [paneel 4G](phone/rq-ph-4E-4H-aanvraag-film.jpg) | [paneel 4G](tablet/rq-tb-4G-4I-aanvraag-film.jpg) | [paneel 4G](desktop/rq-dk-4G-4I-aanvraag-film.jpg) |
| 4H | Fout, keuzes behouden | aanvrager | bestaand gedrag | [paneel 4H](tv/rq-tv-4G-4H-aanvraag-film.jpg) | [paneel 4H](phone/rq-ph-4E-4H-aanvraag-film.jpg) | [paneel 4H](tablet/rq-tb-4G-4I-aanvraag-film.jpg) | [paneel 4H](desktop/rq-dk-4G-4I-aanvraag-film.jpg) |
| 4I | Onzeker of het aankwam | aanvrager | gewijzigd gedrag | [paneel 4I](tv/rq-tv-4I-4J-aanvraag-film.jpg) | [paneel 4I](phone/rq-ph-4I-4K-aanvraag-film.jpg) | [paneel 4I](tablet/rq-tb-4G-4I-aanvraag-film.jpg) | [paneel 4I](desktop/rq-dk-4G-4I-aanvraag-film.jpg) |
| 4J | Door de server geweigerd (403/409) | aanvrager | gewijzigd gedrag | [paneel 4J](tv/rq-tv-4I-4J-aanvraag-film.jpg) | [paneel 4J](phone/rq-ph-4I-4K-aanvraag-film.jpg) | [paneel 4J](tablet/rq-tb-4J-4K-aanvraag-film.jpg) | [paneel 4J](desktop/rq-dk-4J-4K-aanvraag-film.jpg) |
| 4K | Bevestigd resultaat | aanvrager | bestaand gedrag | [paneel 4K](tv/rq-tv-4K-4K-aanvraag-film.jpg) | [paneel 4K](phone/rq-ph-4I-4K-aanvraag-film.jpg) | [paneel 4K](tablet/rq-tb-4J-4K-aanvraag-film.jpg) | [paneel 4K](desktop/rq-dk-4J-4K-aanvraag-film.jpg) |

### 5. Aanvraag serie

| Code | Staat | Rol | Tegenover de bron | TV | Telefoon | Tablet | Desktop |
|---|---|---|---|---|---|---|---|
| 5A | Alle aanvraagbare seizoenen vooraf gekozen | aanvrager | bestaand gedrag | [paneel 5A](tv/rq-tv-5A-5B-aanvraag-serie.jpg) | [paneel 5A](phone/rq-ph-5A-5D-aanvraag-serie.jpg) | [paneel 5A](tablet/rq-tb-5A-5C-aanvraag-serie.jpg) | [paneel 5A](desktop/rq-dk-5A-5C-aanvraag-serie.jpg) |
| 5B | Eén seizoen | aanvrager | bestaand gedrag | [paneel 5B](tv/rq-tv-5A-5B-aanvraag-serie.jpg) | [paneel 5B](phone/rq-ph-5A-5D-aanvraag-serie.jpg) | [paneel 5B](tablet/rq-tb-5A-5C-aanvraag-serie.jpg) | [paneel 5B](desktop/rq-dk-5A-5C-aanvraag-serie.jpg) |
| 5C | Meerdere seizoenen, selecteer alles gemengd | aanvrager | bestaand gedrag | [paneel 5C](tv/rq-tv-5C-5D-aanvraag-serie.jpg) | [paneel 5C](phone/rq-ph-5A-5D-aanvraag-serie.jpg) | [paneel 5C](tablet/rq-tb-5A-5C-aanvraag-serie.jpg) | [paneel 5C](desktop/rq-dk-5A-5C-aanvraag-serie.jpg) |
| 5D | Lange scrolllijst (14 seizoenen) | aanvrager | gewijzigd gedrag | [paneel 5D](tv/rq-tv-5C-5D-aanvraag-serie.jpg) | [paneel 5D](phone/rq-ph-5A-5D-aanvraag-serie.jpg) | [paneel 5D](tablet/rq-tb-5D-5F-aanvraag-serie.jpg) | [paneel 5D](desktop/rq-dk-5D-5F-aanvraag-serie.jpg) |
| 5E | Geen aanvraagbaar seizoen | aanvrager | bestaand gedrag | [paneel 5E](tv/rq-tv-5E-5F-aanvraag-serie.jpg) | [paneel 5E](phone/rq-ph-5E-5H-aanvraag-serie.jpg) | [paneel 5E](tablet/rq-tb-5D-5F-aanvraag-serie.jpg) | [paneel 5E](desktop/rq-dk-5D-5F-aanvraag-serie.jpg) |
| 5F | 4K voor series, limiet krap | aanvrager met 4K-serie | gewijzigd gedrag | [paneel 5F](tv/rq-tv-5E-5F-aanvraag-serie.jpg) | [paneel 5F](phone/rq-ph-5E-5H-aanvraag-serie.jpg) | [paneel 5F](tablet/rq-tb-5D-5F-aanvraag-serie.jpg) | [paneel 5F](desktop/rq-dk-5D-5F-aanvraag-serie.jpg) |
| 5G | Bezig met indienen | aanvrager | bestaand gedrag | [paneel 5G](tv/rq-tv-5G-5H-aanvraag-serie.jpg) | [paneel 5G](phone/rq-ph-5E-5H-aanvraag-serie.jpg) | [paneel 5G](tablet/rq-tb-5G-5I-aanvraag-serie.jpg) | [paneel 5G](desktop/rq-dk-5G-5I-aanvraag-serie.jpg) |
| 5H | Fout, selectie behouden | aanvrager | bestaand gedrag | [paneel 5H](tv/rq-tv-5G-5H-aanvraag-serie.jpg) | [paneel 5H](phone/rq-ph-5E-5H-aanvraag-serie.jpg) | [paneel 5H](tablet/rq-tb-5G-5I-aanvraag-serie.jpg) | [paneel 5H](desktop/rq-dk-5G-5I-aanvraag-serie.jpg) |
| 5I | Bevestigd resultaat | aanvrager | bestaand gedrag | [paneel 5I](tv/rq-tv-5I-5I-aanvraag-serie.jpg) | [paneel 5I](phone/rq-ph-5I-5I-aanvraag-serie.jpg) | [paneel 5I](tablet/rq-tb-5G-5I-aanvraag-serie.jpg) | [paneel 5I](desktop/rq-dk-5G-5I-aanvraag-serie.jpg) |

### 6. Advanced target

| Code | Staat | Rol | Tegenover de bron | TV | Telefoon | Tablet | Desktop |
|---|---|---|---|---|---|---|---|
| 6A | Beheerder: server, profiel, hoofdmap (film) | beheerder | bestaand gedrag | [paneel 6A](tv/rq-tv-6A-6B-advanced-target.jpg) | [paneel 6A](phone/rq-ph-6A-6D-advanced-target.jpg) | [paneel 6A](tablet/rq-tb-6A-6C-advanced-target.jpg) | [paneel 6A](desktop/rq-dk-6A-6C-advanced-target.jpg) |
| 6B | Geen beheerder: sectie afwezig | aanvrager | bestaand gedrag | [paneel 6B](tv/rq-tv-6A-6B-advanced-target.jpg) | [paneel 6B](phone/rq-ph-6A-6D-advanced-target.jpg) | [paneel 6B](tablet/rq-tb-6A-6C-advanced-target.jpg) | [paneel 6B](desktop/rq-dk-6A-6C-advanced-target.jpg) |
| 6C | Beheerder: Sonarr-doel bij een serie | beheerder | bestaand gedrag | [paneel 6C](tv/rq-tv-6C-6D-advanced-target.jpg) | [paneel 6C](phone/rq-ph-6A-6D-advanced-target.jpg) | [paneel 6C](tablet/rq-tb-6A-6C-advanced-target.jpg) | [paneel 6C](desktop/rq-dk-6A-6C-advanced-target.jpg) |
| 6D | Serverkeuze bij 4K: alleen 4K-servers | beheerder | bestaand gedrag | [paneel 6D](tv/rq-tv-6C-6D-advanced-target.jpg) | [paneel 6D](phone/rq-ph-6A-6D-advanced-target.jpg) | [paneel 6D](tablet/rq-tb-6D-6F-advanced-target.jpg) | [paneel 6D](desktop/rq-dk-6D-6F-advanced-target.jpg) |
| 6E | Na serverwissel: afhankelijke keuzes gewist en aan het laden | beheerder | bestaand gedrag | [paneel 6E](tv/rq-tv-6E-6F-advanced-target.jpg) | [paneel 6E](phone/rq-ph-6E-6H-advanced-target.jpg) | [paneel 6E](tablet/rq-tb-6D-6F-advanced-target.jpg) | [paneel 6E](desktop/rq-dk-6D-6F-advanced-target.jpg) |
| 6F | Herladen: standaard van de nieuwe server | beheerder | bestaand gedrag | [paneel 6F](tv/rq-tv-6E-6F-advanced-target.jpg) | [paneel 6F](phone/rq-ph-6E-6H-advanced-target.jpg) | [paneel 6F](tablet/rq-tb-6D-6F-advanced-target.jpg) | [paneel 6F](desktop/rq-dk-6D-6F-advanced-target.jpg) |
| 6G | Opties niet geladen | beheerder | gewijzigd gedrag | [paneel 6G](tv/rq-tv-6G-6H-advanced-target.jpg) | [paneel 6G](phone/rq-ph-6E-6H-advanced-target.jpg) | [paneel 6G](tablet/rq-tb-6G-6H-advanced-target.jpg) | [paneel 6G](desktop/rq-dk-6G-6H-advanced-target.jpg) |
| 6H | Geen 4K-server ingesteld | beheerder | gewijzigd gedrag | [paneel 6H](tv/rq-tv-6G-6H-advanced-target.jpg) | [paneel 6H](phone/rq-ph-6E-6H-advanced-target.jpg) | [paneel 6H](tablet/rq-tb-6G-6H-advanced-target.jpg) | [paneel 6H](desktop/rq-dk-6G-6H-advanced-target.jpg) |

### 7. Aanvragenlijst

| Code | Staat | Rol | Tegenover de bron | TV | Telefoon | Tablet | Desktop |
|---|---|---|---|---|---|---|---|
| 7A | Mijn aanvragen | aanvrager | bestaand gedrag | [beeld](tv/rq-tv-7A-mijn-aanvragen.jpg) | [paneel 7A](phone/rq-ph-7A-7D-aanvragenlijst.jpg) | [beeld](tablet/rq-tb-7A-mijn-aanvragen.jpg) | [beeld](desktop/rq-dk-7A-mijn-aanvragen.jpg) |
| 7B | Alle aanvragen | beheerder | bestaand gedrag | [beeld](tv/rq-tv-7B-alle-aanvragen.jpg) | [paneel 7B](phone/rq-ph-7A-7D-aanvragenlijst.jpg) | [beeld](tablet/rq-tb-7B-alle-aanvragen.jpg) | [beeld](desktop/rq-dk-7B-alle-aanvragen.jpg) |
| 7C | Statusfilter met aantallen | beheerder, bereik alle | bestaand gedrag | [beeld](tv/rq-tv-7C-statusfilter-met-aantallen.jpg) | [paneel 7C](phone/rq-ph-7A-7D-aanvragenlijst.jpg) | [beeld](tablet/rq-tb-7C-statusfilter-met-aantallen.jpg) | [beeld](desktop/rq-dk-7C-statusfilter-met-aantallen.jpg) |
| 7D | Aantallen onbekend bij eigen bereik | beheerder, bereik mijn | gewijzigd gedrag | [beeld](tv/rq-tv-7D-aantallen-onbekend-bij-eigen-bereik.jpg) | [paneel 7D](phone/rq-ph-7A-7D-aanvragenlijst.jpg) | [beeld](tablet/rq-tb-7D-aantallen-onbekend-bij-eigen-bereik.jpg) | [beeld](desktop/rq-dk-7D-aantallen-onbekend-bij-eigen-bereik.jpg) |
| 7E | Aantallen niet geladen | beheerder, bereik alle | gewijzigd gedrag | [beeld](tv/rq-tv-7E-aantallen-niet-geladen.jpg) | [paneel 7E](phone/rq-ph-7E-7H-aanvragenlijst.jpg) | [beeld](tablet/rq-tb-7E-aantallen-niet-geladen.jpg) | [beeld](desktop/rq-dk-7E-aantallen-niet-geladen.jpg) |
| 7F | Laden | aanvrager | bestaand gedrag | [beeld](tv/rq-tv-7F-laden.jpg) | [paneel 7F](phone/rq-ph-7E-7H-aanvragenlijst.jpg) | [beeld](tablet/rq-tb-7F-laden.jpg) | [beeld](desktop/rq-dk-7F-laden.jpg) |
| 7G | Leeg | aanvrager | gewijzigd gedrag | [beeld](tv/rq-tv-7G-leeg.jpg) | [paneel 7G](phone/rq-ph-7E-7H-aanvragenlijst.jpg) | [beeld](tablet/rq-tb-7G-leeg.jpg) | [beeld](desktop/rq-dk-7G-leeg.jpg) |
| 7H | Gefilterd leeg | beheerder | bestaand gedrag | [beeld](tv/rq-tv-7H-gefilterd-leeg.jpg) | [paneel 7H](phone/rq-ph-7E-7H-aanvragenlijst.jpg) | [beeld](tablet/rq-tb-7H-gefilterd-leeg.jpg) | [beeld](desktop/rq-dk-7H-gefilterd-leeg.jpg) |
| 7I | Fout | aanvrager | bestaand gedrag | [beeld](tv/rq-tv-7I-fout.jpg) | [paneel 7I](phone/rq-ph-7I-7K-aanvragenlijst.jpg) | [beeld](tablet/rq-tb-7I-fout.jpg) | [beeld](desktop/rq-dk-7I-fout.jpg) |
| 7J | Meer laden mislukt | beheerder | gewijzigd gedrag | [beeld](tv/rq-tv-7J-meer-laden-mislukt.jpg) | [paneel 7J](phone/rq-ph-7I-7K-aanvragenlijst.jpg) | [beeld](tablet/rq-tb-7J-meer-laden-mislukt.jpg) | [beeld](desktop/rq-dk-7J-meer-laden-mislukt.jpg) |
| 7K | Statusverandering en terugkeer naar kaart | beheerder | gewijzigd gedrag | [beeld](tv/rq-tv-7K-statusverandering-en-terugkeer-naar-kaart.jpg) | [paneel 7K](phone/rq-ph-7I-7K-aanvragenlijst.jpg) | [beeld](tablet/rq-tb-7K-statusverandering-en-terugkeer-naar-kaart.jpg) | [beeld](desktop/rq-dk-7K-statusverandering-en-terugkeer-naar-kaart.jpg) |

### 8. Aanvraagbeheer

| Code | Staat | Rol | Tegenover de bron | TV | Telefoon | Tablet | Desktop |
|---|---|---|---|---|---|---|---|
| 8A | Acties voor beheerder op een aanvraag in afwachting | beheerder | nieuw, niet gebouwd | [paneel 8A](tv/rq-tv-8A-8B-aanvraagbeheer.jpg) | [paneel 8A](phone/rq-ph-8A-8D-aanvraagbeheer.jpg) | [paneel 8A](tablet/rq-tb-8A-8C-aanvraagbeheer.jpg) | [paneel 8A](desktop/rq-dk-8A-8C-aanvraagbeheer.jpg) |
| 8B | Acties op een eigen aanvraag in afwachting | aanvrager | nieuw, niet gebouwd | [paneel 8B](tv/rq-tv-8A-8B-aanvraagbeheer.jpg) | [paneel 8B](phone/rq-ph-8A-8D-aanvraagbeheer.jpg) | [paneel 8B](tablet/rq-tb-8A-8C-aanvraagbeheer.jpg) | [paneel 8B](desktop/rq-dk-8A-8C-aanvraagbeheer.jpg) |
| 8C | Geen acties: niet meer in afwachting of geen recht | aanvrager | nieuw, niet gebouwd | [paneel 8C](tv/rq-tv-8C-8D-aanvraagbeheer.jpg) | [paneel 8C](phone/rq-ph-8A-8D-aanvraagbeheer.jpg) | [paneel 8C](tablet/rq-tb-8A-8C-aanvraagbeheer.jpg) | [paneel 8C](desktop/rq-dk-8A-8C-aanvraagbeheer.jpg) |
| 8D | Annuleren bevestigen | aanvrager, eigen aanvraag | bestaand gedrag | [paneel 8D](tv/rq-tv-8C-8D-aanvraagbeheer.jpg) | [paneel 8D](phone/rq-ph-8A-8D-aanvraagbeheer.jpg) | [paneel 8D](tablet/rq-tb-8D-8F-aanvraagbeheer.jpg) | [paneel 8D](desktop/rq-dk-8D-8F-aanvraagbeheer.jpg) |
| 8E | Bewerken: seizoenen | aanvrager, eigen aanvraag | nieuw, niet gebouwd | [paneel 8E](tv/rq-tv-8E-8F-aanvraagbeheer.jpg) | [paneel 8E](phone/rq-ph-8E-8H-aanvraagbeheer.jpg) | [paneel 8E](tablet/rq-tb-8D-8F-aanvraagbeheer.jpg) | [paneel 8E](desktop/rq-dk-8D-8F-aanvraagbeheer.jpg) |
| 8F | Bewerken: 4K en doel | beheerder | nieuw, niet gebouwd | [paneel 8F](tv/rq-tv-8E-8F-aanvraagbeheer.jpg) | [paneel 8F](phone/rq-ph-8E-8H-aanvraagbeheer.jpg) | [paneel 8F](tablet/rq-tb-8D-8F-aanvraagbeheer.jpg) | [paneel 8F](desktop/rq-dk-8D-8F-aanvraagbeheer.jpg) |
| 8G | Bewerken geweigerd (403) | aanvrager | nieuw, niet gebouwd | [paneel 8G](tv/rq-tv-8G-8H-aanvraagbeheer.jpg) | [paneel 8G](phone/rq-ph-8E-8H-aanvraagbeheer.jpg) | [paneel 8G](tablet/rq-tb-8G-8I-aanvraagbeheer.jpg) | [paneel 8G](desktop/rq-dk-8G-8I-aanvraagbeheer.jpg) |
| 8H | Bewerken niet mogelijk | aanvrager | nieuw, niet gebouwd | [paneel 8H](tv/rq-tv-8G-8H-aanvraagbeheer.jpg) | [paneel 8H](phone/rq-ph-8E-8H-aanvraagbeheer.jpg) | [paneel 8H](tablet/rq-tb-8G-8I-aanvraagbeheer.jpg) | [paneel 8H](desktop/rq-dk-8G-8I-aanvraagbeheer.jpg) |
| 8I | Bewerken: bezig met opslaan | aanvrager | nieuw, niet gebouwd | [paneel 8I](tv/rq-tv-8I-8J-aanvraagbeheer.jpg) | [paneel 8I](phone/rq-ph-8I-8L-aanvraagbeheer.jpg) | [paneel 8I](tablet/rq-tb-8G-8I-aanvraagbeheer.jpg) | [paneel 8I](desktop/rq-dk-8G-8I-aanvraagbeheer.jpg) |
| 8J | Bewerken: onzeker of het is opgeslagen | aanvrager | nieuw, niet gebouwd | [paneel 8J](tv/rq-tv-8I-8J-aanvraagbeheer.jpg) | [paneel 8J](phone/rq-ph-8I-8L-aanvraagbeheer.jpg) | [paneel 8J](tablet/rq-tb-8J-8J-aanvraagbeheer.jpg) | [paneel 8J](desktop/rq-dk-8J-8J-aanvraagbeheer.jpg) |
| 8K | Actie bezig op de kaart | beheerder | gewijzigd gedrag | [beeld](tv/rq-tv-8K-actie-bezig-op-de-kaart.jpg) | [paneel 8K](phone/rq-ph-8I-8L-aanvraagbeheer.jpg) | [beeld](tablet/rq-tb-8K-actie-bezig-op-de-kaart.jpg) | [beeld](desktop/rq-dk-8K-actie-bezig-op-de-kaart.jpg) |
| 8L | Actie mislukt, focus terug op de kaart | beheerder | gewijzigd gedrag | [beeld](tv/rq-tv-8L-actie-mislukt-focus-terug-op-de-kaart.jpg) | [paneel 8L](phone/rq-ph-8I-8L-aanvraagbeheer.jpg) | [beeld](tablet/rq-tb-8L-actie-mislukt-focus-terug-op-de-kaart.jpg) | [beeld](desktop/rq-dk-8L-actie-mislukt-focus-terug-op-de-kaart.jpg) |
<!-- MATRIX:END -->

## Opnieuw renderen

```
cd docs/assets/requests-2.0/src
node gen.mjs                # alles: HTML, beelden, manifest, index, matrix
node gen.mjs rq-tv-7        # alleen bestanden met die tekst in de naam
node gen.mjs --no-render    # alleen manifest, index en matrix
```

`gen.mjs` bevat de fixture, de staten en de vier platformframes. `out/` is tussenresultaat
en staat in `.gitignore`. Playwright komt uit dezelfde globale installatie als bij
`../tvos-unified/src/build.mjs`; `PLEYA_MOCKUP_PLAYWRIGHT` wijst een andere aan. Het script
sluit af met een zelfcontrole: elk beeld bestaat, elke staat heeft op elk platform een
bestand, en geen pagina had een afbeelding die niet laadde. Sinds de herstelronde van
8 oktober toetst het ook inhoud en maat. 8J mag niet beweren dat de server onveranderd is en
biedt Status controleren als hoofdknop. In 7H is het aantal op het gekozen filter 0, terwijl
7D geen getal toont en 7E een streepje. Bij het renderen meet het script of de profiel- en
servercontext en het gekozen filter binnen de schermrand staan, niet afgekapt en niet bedekt.

De polishronde van 8 oktober voegde zes metingen toe, elk rood op de set van daarvoor. Er staat
geen voorsteltekst in een scherm. De voetregel van een overlay is één regel en blijft binnen de
overlay, ook naast een lange knop als "Aanvragen met serverstandaard". Een herstelknop (Opnieuw,
Opnieuw proberen) staat volledig in beeld en boven de tabbalk. Focus staat met zijn ring en de
ondertitel van de kaart in beeld; op TV schuift het raster daarvoor naar de tweede rij (1G, 7J,
2B). Aanvrager, datum en "speelbaar" of "aan te vragen" worden niet afgekapt. Op de telefoon
vervaagt een filterchip die de schermrand raakt, in plaats van midden in een getal te eindigen.
