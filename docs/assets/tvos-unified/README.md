# tvOS-beeldensets: welke bindt waarvoor

De beeldensets hieronder zijn niet gelijkwaardig. Een beeld zegt zelf niet altijd of het
nog geldt, dus dat staat hier. De volledige kaart, inclusief de andere oppervlakken,
staat in [docs/DESIGN-INDEX.md](../../DESIGN-INDEX.md).

| Map | Beelden | Rol |
|---|---|---|
| `northstar/` | 01 tot en met 08 | de oorspronkelijke acht. **Deels superseded**, zie hieronder |
| `approved-2026-09-03/` | 09 tot en met 25 | goedgekeurd doelbeeld. De PNG's zeggen zelf nog "candidate"; het [approval-manifest](../../tvos-redesign-09-25-approved.md) is de statusautoriteit, niet de tekst in het beeld |
| `mockups-2026-09-04/` | 26 tot en met 31 | goedgekeurd onder DEC-092 tot en met DEC-096 |
| `mockups-2026-09-05/` | 33, het spelerpaneel in negen standen | goedgekeurd, DEC-101; vervangt mockup 19 |
| `mockups-2026-09-07/` | 34 kijklijst, 35 aanvragen, 36 zoeken | goedgekeurd 7 september, DEC-108; manifest met hashes in [tvos-redesign-34-36-approved.md](../../tvos-redesign-34-36-approved.md). `35-aanvragen-c2` is de niet-gekozen kant van één vraag en blijft staan als afweging |
| `mockups-2026-09-07-detail/` | 37 A tot en met D, film- en seriedetail plus volledige synopsis | goedgekeurd 7 september, DEC-109; [tvos-redesign-37-approved.md](../../tvos-redesign-37-approved.md) is de statusautoriteit en corrigeert 09 en 10 waar expliciet beschreven |
| `mockups-2026-09-02/` | Mijn Pleya-secties | goedgekeurd voor die secties |
| de vijf `*-reference.png` hier los | los | **historisch**, de voorloper van de northstar-set. Drie ervan worden nergens meer genoemd |
| `src/` | de HTML-bron | waar de mockups uit gerenderd worden, met `build.mjs` en `tv.css`. Wijzig een beeld hier en render opnieuw, teken er geen tweede versie naast |

## Statusautoriteit

Waar tekst in een PNG of een oude README nog `candidate` of `kandidaat` zegt, wint het
bijbehorende approval-manifest. Dat geldt voor 09 tot en met 25, 34 tot en met 36 en 37.

## Wat er superseded is

| Beeld | Wat vervalt | Waardoor |
|---|---|---|
| `northstar/01-home.jpg` | de hero als afgeronde kaart ín de pagina, "nooit full bleed" | DEC-095 |
| `northstar/02-home-rail-focus.jpg` | de onderste strook met afgeronde hoeken, en het raillabelanker op 372 | DEC-095 |
| `northstar/02-home-rail-focus.jpg` | de drie absolute maten: band 400, gefocust 711, buren 267 | DEC-087 |
| `northstar/03-films-landing.jpg` | de kaarttaal op de landing | DEC-064 |
| `northstar/04-series-landing.jpg` | idem | DEC-064 |
| `approved-2026-09-03/19-speler-infopanel.png` | speler-infopaneel als doelbeeld | DEC-101 / mockup 33 |
| `approved-2026-09-03/09-film-detail.png` en `10-serie-detail.png` | alleen de onderdelen die mockup 37 expliciet corrigeert | DEC-109 / mockup 37 |

Elke afwijking van 01 tot en met 04 staat voluit als blockquote in hoofdstuk 33 van
[tvos-unified-experience.md](../../tvos-unified-experience.md), bij de paragraaf van het
beeld zelf. De beelden zijn bewust niet opnieuw gerenderd: dat zou de pixels en de hashes
wijzigen, terwijl de rest van wat ze vastleggen gewoon geldig blijft.

**Voor Home**: `mockups-2026-09-04/30-home-*` is bindend voor de compositie. Voor alles
wat `01-home.jpg` en `02-home-rail-focus.jpg` daarnaast vastleggen blijven die twee
bindend. Voor detail geldt 37 voor zijn expliciete correcties; 09 en 10 blijven de
autoriteit voor wat 37 niet aanraakt.
