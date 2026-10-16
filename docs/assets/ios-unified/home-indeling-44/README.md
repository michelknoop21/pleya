# Mockupset 44: Home aanpassen op iPhone, iPad en Mac

Status: PROPOSED (16 oktober 2026). Nog niet bouwen: eerst een akkoord van Michel per beeld.
Roadmap: HOME-R1 stap 2. Het voorstel met de inventaris, de keuzes en de open vragen staat in
[docs/plans/2026-10-16-home-r1-home-indeling.md](../../../plans/2026-10-16-home-r1-home-indeling.md).

De tvOS-weergave verandert niet. De lijstregel en de wizard nemen de vorm over van mockup 32 B
en C (tvOS, goedgekeurd bij DEC-100), maar met een sleepgreep in plaats van pijlknoppen en met de
wizard als sheet. Kleuren komen uit `lib/theme/mono_theme.dart` (donker `#141414/#1F1F1F/#2F2F2F`,
licht `#F7F7F8/#FFFFFF/#EDEDED`, accent `#E5140F`), de bouwstenen uit set 43. Alle teksten die de
app al heeft (Home aanpassen, Nieuwe rij, de wizardstappen, Rij toevoegen, Filters aanpassen,
Verborgen items) staan er letterlijk zoals in `lib/i18n/nl.i18n.json`.

## De beelden

Elk iPhone-beeld bestaat in vier varianten: klein (375x667, iPhone SE) en groot (430x932), licht
en donker. Bestandsnaam: `<beeld>-<s|l>-<dark|light>.png`. iPad en Mac hebben `-dark` en `-light`.
Alle PNG's zijn 2x.

| Beeld | Scherm | Formaten |
| --- | --- | --- |
| 44 A `44-a-home-ingang` | Home onderaan: de regel "Home aanpassen" onder de laatste rij | iPhone |
| 44 B `44-b-rijkop-lang-drukken` | lang drukken op een rijkop: Omhoog, Omlaag, Verbergen op Home, Home aanpassen | iPhone |
| 44 C `44-c-aanpassen-lijst` | Home aanpassen: vaste rijen, sleepgrepen, oog per rij, Nieuwe rij | iPhone |
| 44 D `44-d-slepen` | Kijklijst wordt naar plek 2 gesleept, de lege plek schuift mee | iPhone |
| 44 E `44-e-eigen-rij-menu` | menu van een eigen rij: Bewerken, Verbergen op Home, Alle 42 in Films, Verwijderen | iPhone |
| 44 F `44-f-verwijderen` | bevestiging bij Verwijderen | iPhone |
| 44 G `44-g-nieuwe-rij-naam` | wizard stap 1, Naam en soort | iPhone |
| 44 H `44-h-nieuwe-rij-filters` | wizard stap 2, Filters: Status, Genre, Jaar, Bronnen, Sortering | iPhone |
| 44 I `44-i-nieuwe-rij-voorbeeld` | wizard stap 3, Voorbeeld met teller en eerste posters | iPhone |
| 44 J `44-j-leeg-voorbeeld` | wizard stap 3 bij een filter zonder resultaat (C4 van mockup 32) | iPhone |
| 44 K `44-k-randgevallen` | samengevoegde rij, rij van een offline server, lege eigen rij, Nu op tv uit, Verborgen items | iPhone |
| 44 L `44-l-ipad` | iPad liggend 1180x820: lijst links met slepen, wizard rechts voor de gekozen eigen rij | iPad |
| 44 M `44-m-mac-paneel` | Mac 1440x900: paneel over de gedimde Home, rij slepen met de muis | Mac |
| 44 N `44-n-mac-rechtsklik` | Mac: rechtsklik op een rijkop, plus de knop met drie puntjes bij hover | Mac |

Bij de beelden:

- 44 C tot en met K tonen de lijst zoals de iPhone-Home hem tekent: unified rijen, dus een
  samengevoegde rij is één regel en Recent uitgebracht en Nu op tv staan erin.
- 44 L, M en N tonen de lijst zoals de iPad- en Mac-Home hem vandaag tekenen: één regel per
  server-hub (twee keer "Recent toegevoegde series", één per server) en zonder Recent uitgebracht
  of Nu op tv. Zie open vraag 1 in het voorstel.
- De ronde vlek in 44 D en 44 L is de vinger; het handje in 44 M de muiscursor. Ze horen niet bij
  de app.
- In 44 J is de metaregel amber, de enige kleurwissel uit C4.

## Opnieuw renderen

```
python3 gen44.py              # HTML en PNG's
python3 gen44.py --html       # alleen HTML
python3 gen44.py 44-c         # alleen beelden waarvan de naam zo begint
```

`gen44.py` schrijft per beeld één HTML-bestand dat `hl44.css` en `hl44.js` laadt, en maakt de
PNG's met de Playwright CLI (`pw screenshot`). Thema en formaat staan in de URL
(`?t=dark&s=l&x=2`); `x=2` zet een CSS-zoom van 2, zodat `pw` zonder schaalfactor-optie toch 2x
levert. Posters komen uit `../detail-2026/` (Blender-films), avatar en woordmerk uit
`../../tvos-unified/src/assets/`.
