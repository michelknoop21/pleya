# DESIGN.md: hoe je de Pleya Web-mockups nabouwt, uitbreidt en implementeert

Dit bestand bestaat zodat een volgende sessie niets opnieuw hoeft uit te zoeken. Het bevat de
authority-keten, elke tokenwaarde met zijn bron, het layoutcontract per breedte, de macrotaal
van `src/build.mjs`, de componentmapping naar `pleya_web`, de artwork- en fixturebronnen, en
een stappenplan voor een nieuw scherm. Wie een scherm wil toevoegen leest hoofdstuk 6 en is
klaar; wie een scherm wil implementeren leest hoofdstuk 5.

## 1. Authority-keten (waar iets vandaan komt)

| Laag | Bron | Locatie | Status |
| --- | --- | --- | --- |
| Tokens | `lib/theme/mono_theme.dart`, `lib/theme/mono_tokens.dart` | elke branch | bron van waarheid |
| Webtranscriptie | `pleya_web/src/styles/tokens.css` | `feat/pleyaserver` | per regel naar Flutter verwezen |
| Breekpunten en verhoudingen | `lib/utils/layout_constants.dart` (`ScreenBreakpoints`, `GridLayoutConstants`) | elke branch | 600 / 900 / 1200 / 1600; poster 2:3; aflevering 16:9 |
| TV-familie (≥ 900) | `docs/assets/tvos-unified/src/tv.css`, mockups 09 tot 26 | `main` `2433f74` | goedgekeurd 3 sep (`docs/tvos-redesign-09-25-approved.md`) |
| iOS-familie (< 900) | `~/Downloads/mockups/_src/ios.css`, PNG's in `docs/assets/ios-unified/northstar/` | `feat/netflix-mobile` `cf256fb`, DEC-090 | goedgekeurd 3 sep; HTML-bron alleen lokaal |
| E-books | `docs/assets/ebooks/northstar/` met `src/` en `README.md` | `feat/ebooks` `5d6ab71`, DEC-094 | goldens 00 tot 05 goedgekeurd |
| Web | deze map, `src/web.css`, `src/pages/` | `feat/pleyaserver` | kandidaat |

Regel bij twijfel: onder 900 wint de iOS-set, erboven de TV-set, en voor boekinhoud de
e-bookscomp. Waar de webset van beide afwijkt staat dat in `src/web.css` met een comment
"web:".

## 2. Tokens

Alle kleuren zijn identiek aan de app; "web" markeert een afleiding.

| Token | Waarde | Bron | Gebruik |
| --- | --- | --- | --- |
| `--accent` | `#E5140F` | `kAccent` | progreslijn, actieve tab, actieve filterchip (tint), foutrand |
| `--amber` | `#FFB020` | `kAccentAlt` | nieuw-punt, waarschuwing, Beheer-pil |
| `--ok` | `#3DD68C` | `kSuccess` | online-punt, toggle aan |
| `--bg` | `#141414` | dark; OLED `#000` blijft instelling | paginagrond |
| `--surface` | `#1F1F1F` | `surface` | kaarten, panelen, rijen, velden |
| `--elevated` | `#2F2F2F` | `surfaceElevated` | toggles, secundaire knop op detail |
| `--ink-2` / `-3` / `-4` | wit 70 / 50 / 30 % | `textMuted` en afleidingen | meta, hints, hairlines |
| `--fill` / `--fill-2` | wit 8 / 14 % | web | zoekveld, ghost-knop, secundaire knop |
| `--r-sm` / `--r-md` / `--r-card` / `--r-hero` | 8 / 12 / 14 / 18 px (16 op smal) | `radiusSm`, `radiusMd`, `cardTheme`, TV-billboard | posters / velden / panelen / hero |
| `--ring` | 3 px wit (TV: 4) | web | focusring op een gap van 3 px |
| `--inset` | 48 / 32 / 16 px | web (TV 75, iOS 16) | pagina-inset ≥1200 / ≥900 / smal |
| `--poster-w` | 190 / 170 / 150 / 110 px | web (iOS 110) | railposter ≥1600 / ≥1200 / ≥900 / smal |
| `--rail-gap` | 20 / 16 / 12 px | web (`MonoTokens.space` 12 op smal) | ruimte tussen kaarten |
| `--nav-h` / `--tab-h` | 64 / 56 px | web | topnav / tabbalk |
| Lettertype | Inter 400 / 500 / 700; ArchivoBlack 900 | app | ArchivoBlack alleen voor de hero-titel en detailtitel op breed |
| Basismaat | 15 px, regelhoogte 1,35 | web | iOS 15, TV 22 |

Typografische maten: paginatitel 34 (26 smal), sectiekop 20 (18), kaarttitel 14 (13),
kaartonderregel 12 (11), knop 15, chip 14, tabellabel 12 uppercase met 0,04 em spatiëring.

## 3. Layoutcontract per breedte

| | ≥ 1600 | 1200 tot 1599 | 900 tot 1199 | < 900 |
| --- | --- | --- | --- | --- |
| Navigatie | topnav | topnav | topnav, smaller zoekveld | kop + tabbalk (vast onder) |
| Hero | 21:9, tekst linksonder, scrim links | 21:9 | 16:9 | portret 520 px, tekst gecentreerd onder, scrim onder |
| Rails | bleed tot de rand, fade rechts | idem | idem | idem, posters 110 |
| Raster | `auto-fill` op `--poster-w` | idem | idem | 3 kolommen |
| Detail | backdrop-hero met kolom links, panelen in 2 kolommen | idem | idem | 16:9-voorvertoning, titel in Inter, knoppen vol breed, iconknoppen op één rij |
| Beheer | zijbalk 232 + inhoud, panelen in 2 kolommen | zijbalk 232 | zijbalk 200, panelen 1 kolom | geen zijbalk (lijstpagina 33), tabellen scrollen in hun paneel |
| Setup | gecentreerde kolom van 620 | idem | idem | vol breed |
| Screenshot | hele pagina | hele pagina | hele pagina | één scherm, 2× |

Focus en hover: hover alleen achter `@media (hover: hover)`, kaart krijgt ring plus lift van
3 px plus acties onderin; toetsenbordfocus krijgt de ring op een gap zonder lift.

## 4. De renderer en zijn macrotaal

`src/build.mjs` leest `src/pages/*.html` (fragmenten, geen complete documenten), vervangt
tokens, schrijft `src/out/<naam>.html` en schiet elke breedte uit de kopregel van de pagina.

```
<!-- widths: 1600, 1280, 1024, 393 -->      kopregel; zonder regel: 1600 en 393
{{shell:home}}                              topnav + mobiele kop + tabbalk; actief: home|series|films|books|my|admin
{{shell:films|nav=Alle films|navAction=search}}   mobiele terugkop met titel en actie-icoon (leeg = geen actie)
{{shell:home|q=dune}}                       zoekveld met term
{{shell:home|noadmin}}                      gebruiker zonder Beheer-pil
{{admin:libraries|badges=activity:1,storage:!}}   beheerzijbalk met actieve sectie en badges
{{icon:play}}                               icoon uit de set in build.mjs (zelfde tekening als de TV-set)
{{art:dune2-backdrop}}                      pad naar artwork buiten git (slug-poster / slug-backdrop)
{{card:dune2|Dune: Part Two|2024 · Sciencefiction|prog=40,seen,new,src=2 versies,wide,hover,focus,over,badge=NIEUW}}
{{bookcard:dune|48|hover,new,sub=Dune · 6 boeken}}   CSS-cover met voortgang op de cover
{{readcard:dune|48|Hoofdstuk 12}}           liggende Verder-lezen-kaart met ambience
{{cover:dune:48}} / {{amb:dune}}            losse cover / ambience-achtergrond
{{ep:severance|S2 · A3|Titel|49 min · datum|synopsis|prog=42,seen}}   afleveringsrij
```

Kaartopties staan in het laatste segment, gescheiden door komma's. Slugs voor `card` zonder
`-backdrop` krijgen automatisch `-poster`. Onbekende iconen en covers breken de build hard,
zodat een typfout niet stil een leeg vak oplevert.

Breedtes en viewports staan in `VIEWPORTS`; 834 (iPad-portret) is beschikbaar maar niet in de
kandidaatset gebruikt. Een telefoonbeeld is `fullPage: false` (één scherm met de vaste
tabbalk), een breed beeld `fullPage: true`.

## 5. Componentmapping naar `pleya_web`

De CSS-klassen in `web.css` zijn geen implementatie, wel de contractnamen. Zo horen ze te landen:

| Klasse in de mockup | Svelte-component | Bestaat | Slice |
| --- | --- | --- | --- |
| `.topnav`, `.mhead`, `.tabbar` | `TopNav`, `MobileHeader`, `TabBar` in `+layout.svelte` | `NavRail`, `BottomBar` (vervangen) | S7 |
| `.hero` | `Hero` | ja, herschrijven | S7 |
| `.rail`, `.fade-r` | `HubRail` | ja, bleed en fade erbij | S7 |
| `.card` en staten | `MediaCard` | ja, staten erbij | S7 |
| `.cover`, `.card .cover` | `BookCover`, `BookCard` | nee | S9 |
| `.read-card` | `ContinueReadingCard` | nee | S9 |
| `.ep` | `EpisodeRow` | nee | S8 |
| `.chips`, `.chip` | `Chips`, `FilterChip` | deels in `search` | S7 |
| `.grid` | `MediaGrid` | ja | S7 |
| `.btn` varianten | `base.css` `.btn` | ja, capsule in plaats van radius 4 | S7 |
| `.field`, `.select`, `.label`, `.help` | `Field`, `Select` | `base.css` `.field` | S7 |
| `.state`, `.skel` | `StateView`, `Skeleton` | `StateView` ja | S7 |
| `.admin`, `.admin-nav` | `AdminLayout`, `AdminNav` | nee | S10 |
| `.stats`, `.stat` | `StatTile` | nee | S10 |
| `.panel`, `.kv` | `Panel`, `KeyValue` | nee | S10 |
| `.table` | `DataTable` | nee | S10 |
| `.alert` | `Alert` | nee | S10 |
| `.modal`, `.scrim-full` | `ConfirmDialog` | nee | S10 |
| `.steps`, `.choice`, `.checkbox`, `.toggle` | `Steps`, `Choice`, `Checkbox`, `Toggle` | nee | S10, S11 |
| `.log` | `LogView` | nee | S10 |
| `.pill`, `.status`, `.dot` | `StatusPill`, `StatusDot` | nee | S10 |

De knop uit `base.css` heeft nu radius 4 (`buttonStyle` uit `monoTheme()`); de hele Unified
2026-familie gebruikt capsules (`StadiumBorder`, DEC-090-audit hoofdstuk 2). Dat is een bewuste
wijziging in S7, niet een afwijking van de mockup.

## 6. Een scherm toevoegen of nabouwen

1. Kopieer het dichtstbijzijnde fragment uit `src/pages/` en geef het een vrij nummer:
   01 tot 19 consumer, 20 tot 39 beheer, 40 tot 49 setup, 50 en verder voor speler en reader.
2. Zet de kopregel met breedtes. Neem 393 altijd mee bij een consumerscherm; bij een
   beheerscherm alleen als de mobiele variant iets nieuws laat zien.
3. Gebruik de macro's; schrijf geen losse `<img>` naar artwork en geen inline kleuren buiten
   de tokens. Nieuwe CSS hoort in `web.css` onder het juiste kopje, met een "web:"-comment als
   hij van TV of iOS afwijkt.
4. Sluit af met `<div class="note">NORTHSTAR · nn Naam · wat het beeld vastlegt</div>`.
5. `node build.mjs nn` en bekijk het beeld op elke breedte. Controleer de acht punten uit de
   reviewlijst hieronder.
6. Voeg de regel toe aan het manifest in `README.md` en aan deel D van
   `docs/pleya-server-rebaseline/` (route, data, slice).

Reviewlijst per beeld: (1) shell klopt met de breedte, (2) geen horizontale overloop van de
pagina, (3) elke knop heeft een werkwoord en een bestaand of gepland endpoint, (4) lege en
foutstaten hebben een uitweg, (5) tekst op artwork staat op een scrim, (6) hover en focus zijn
onderscheidbaar, (7) geen kleur buiten de tokens, (8) de note onderaan zegt welke slice het
scherm draagt.

## 7. Artwork en fixturedata

Films en series: `~/Downloads/mockups/_src/art` (85 bestanden, `slug-poster.jpg` en
`slug-backdrop.jpg`), terugval `~/Downloads/mockups-tvos/_src/art`. Nieuwe titels haal je
zoals de iOS-set dat doet met `~/Downloads/mockups/_src/fetch_art.sh <slug> <movie|tv>
<tmdbId>`. Deze bestanden zijn TMDb-materiaal en komen nooit in git; `art/` staat in geen
enkele mockupmap in de repository.

Boeken: elf CSS-covers in `COVERS` in `build.mjs`, dezelfde titels als `DemoBooksSource` op
`feat/ebooks` (Dune 48 % en hoofdstuk 12, Project Hail Mary, Sapiens, 1984, De Alchemist,
Atomic Habits, Dune Messiah, Children of Dune, De Zeven Zussen, De Hobbit, Brave New World)
plus Het Zoutpad. Vorm, kleur en informatiedichtheid zijn aangehouden; een echte cover vervangt
de hele tekening zodra de server hem levert.

Vaste beheerfixture: server "Pleya-server" op `web.pleya.app`, versie 0.9.0, bibliotheken
Films 461, Series 97, Kids 5 (`.env`), Boeken 38 (root niet gemount), gebruikers Michel
(eigenaar), Sanne (lid), Kids (beperkt), vijf toestellen, één lopende scan op 62 %. Dezelfde
getallen op elk scherm, zodat een reviewer een inconsistentie ziet als ze afwijken.

## 8. Wat vastligt en wat niet

Vastgelegd door goedkeuring van de set: shellkeuze per breedte, compositie en hiërarchie per
scherm, de kaartstaten uit 16, de grens consumer versus beheer, de beheerindeling in tien
secties, de vier setupstappen. Niet vastgelegd: titels, artwork, aantallen, exacte teksten,
de volgorde van rijen die van data afhangt, en de twee schermen die nog geen mockup hebben
(speler, webreader).

Open designdetails die bij goedkeuring een ja vragen: "Meer info" als tweede hero-knop en de
tijdelijke segmentindicator (beide uit DEC-090 paragraaf 10 overgenomen voor web).

## 9. Vergelijken met de andere sets

Leg een webbeeld op 393 naast het iOS-beeld met hetzelfde nummer-onderwerp
(`docs/assets/ios-unified/northstar/` op `feat/netflix-mobile`) en een webbeeld op 1600 naast
het TV-beeld (`docs/assets/tvos-unified/` op `main`). Wat gelijk hoort te zijn: tokens,
kaartverhoudingen, chipgedrag, de witte primaire knop, rood en amber alleen als signaal. Wat
bewust verschilt: inset, posterbreedte, ringdikte, de plaats van het wordmark (links op web en
iOS, rechts op TV) en de zijbalk in beheer, die geen van beide andere sets kent.

```
git show feat/netflix-mobile:docs/assets/ios-unified/northstar/06-film-detail.png > /tmp/ios-06.png
git show main:docs/assets/tvos-unified/approved-2026-09-03/09-film-detail.png > /tmp/tv-09.png
```
