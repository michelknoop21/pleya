# Liquid Glass-mockups, september 2026

**Status: goedgekeurd op 24 september 2026 ([DEC-122](DECISIONS.md#dec-122)).** Deze set laat
zien hoe Pleya eruitziet als de oppervlakken Liquid Glass worden, op iPhone en Apple TV. Michel
keurde de richting goed met één eis: goed contrast, zie de sectie Contrast hieronder. Layout, typografie, kleuren en maten komen uit de iOS-northstar
(`docs/assets/ios-unified/northstar/`) en de goedgekeurde tvOS-mockups 30, 33 en 36. Alleen
tabbalk, knoppen, zoekveld en spelerbediening zijn veranderd.

Beelden: `docs/assets/liquid-glass/mockups-2026-09-24/`. Alle content is Blender-materiaal van de
demoserver, geknipt uit de App Store-screenshots van 24 september 2026.

## De acht beelden

| Bestand | Maat | Wat het toont |
|---|---|---|
| `LG-01-home.png` | 1206×2622 | iPhone Home. De tabbalk (Home, Series, Movies, My Pleya) zweeft als glazen capsule los van de rand; de posters van Recently Added lopen eronder door. De zoekknop rechtsboven is een glazen cirkel. |
| `LG-02-film-detail.png` | 1206×2622 | iPhone filmpagina van Big Buck Bunny. Resume (wit, "prominent glass"), Download en de kijklijstknop liggen als glas over het heroartwork; terug en meer zijn glazen cirkels. |
| `LG-03-speler.png` | 2622×1206 | iPhone speler liggend. Terugspoelen, pauze en vooruitspoelen zijn glazen cirkels, tijdlijn en werkbalk zitten in één glazen plaat, rechtsboven een glazen capsule met cast, AirPlay en het menu. Lichte scène onder het glas. |
| `LG-04-home.png` | 1920×1080 | Apple TV Home. De topbalk is een capsule van nepglas over de hero, focus op Home (witte pil, licht vergroot). |
| `LG-05-spelerpaneel.png` | 1920×1080 | Apple TV spelerbalk, stand I van mockup 33 (bediening zichtbaar). Tijdlijn en knoppen staan op één nepglasplaat boven een lichte scène. |
| `LG-06-zoeken.png` | 1920×1080 | Apple TV zoeken, mockup 36 B. De zoekpil is nepglas, in ruststand: onder de topbalk, met de resultaten eronder en de focus op de eerste kaart. Pas bij scrollen schuiven posters onder pil en topbalk door. |
| `LG-07-iphone-vergelijking.png` | 2593×2826 | Links Home van vandaag, rechts LG-01. |
| `LG-08-appletv-vergelijking.png` | 3960×1210 | Links Home van vandaag, rechts LG-04. |

Het linkerbeeld in LG-07 is de app zoals hij nu in de App Store staat, zonder hero en met een
vaste tabbalk. Het rechterbeeld volgt de northstar-compositie. Wie alleen het glas wil beoordelen,
kijkt naar de tabbalk en de zoekknop; de rest van het verschil is de northstar die nog niet
helemaal gebouwd is.

## Echt glas tegenover nepglas

Op de iPhone breekt het glas. Langs de rand zit een band van 10 px waarin de achtergrond 1,10 keer
vergroot en daardoor verschoven is; in het midden is de achtergrond vervaagd. Zo ziet een poster die
onder de tabbalk doorloopt er aan de rand anders uit dan in het midden. Dat is wat
`liquid_glass_renderer` met een Impeller-shader doet.

Op Apple TV bestaat dat pakket niet, dus daar is het glas een `BackdropFilter`: vervagen, iets meer
verzadiging, iets dimmen, een witte tint en een lichtlijn bovenlangs. Geen rand die breekt. In
LG-04 en LG-06 is het verschil met een donkere balk goed te zien, in LG-05 minder, omdat de plaat
daar groot is en de scène achter de knoppen al rustig is.

## Contrast

Glas mag de leesbaarheid niet kosten. Dit is een eis bij de goedkeuring, geen wens.

- Tekst en iconen op glas halen minstens 4,5:1 tegen wat eronder ligt, gemeten op de lichtste
  scène die daar kan staan (Big Buck Bunny, Coffee Run). Wit op glas krijgt daarom altijd de
  tekstschaduw uit de recepten hierboven; zonder schaduw zakt wit op de lichte Bunny-scène onder 3:1.
- Het glas dempt wat erdoor schemert (`--lg-dim`) en zet een lichte donkere tint in de plaat zodra
  de achtergrond licht is. In Flutter is dat een luminantiemeting van het beeld onder de plaat, of
  een vaste tint van 22 tot 28 procent zwart als meten te duur is.
- De focusring op Apple TV blijft wit met de bestaande ring-gap; op een witte pil (Home in LG-04)
  vervalt de ring en telt de schaal plus schaduw als focus. Dat is de enige plek waar dat mag.
- Het rode accent (voortgang, actieve tab) blijft dekkend; het gaat nooit door het glas heen.
- Controle: elk scherm met glas krijgt in Pleya Verify een contrastmeting op de lichtste fixture.

## De CSS-recepten

Het iPhone-glas bestaat uit vier lagen per vlak. CSS kan niet breken, dus `src/ios/shoot.mjs`
schiet eerst de pagina zonder glas en gebruikt dat beeld als achtergrond voor de lagen:

```css
/* tokens, src/ios/ios.css */
--lg-blur: 12px;   /* sigma */
--lg-tint: .14;    /* wit */
--lg-sat: 1.5;
--lg-dim: .78;     /* dempt wat erdoor schemert, voor contrast met witte tekst */
--lg-band: 10px;   /* brekingsrand */
--lg-zoom: 1.10;   /* vergroting in die rand, rond het midden van het vlak */

/* 1. breking: hele vlak, achtergrond vergroot rond het middelpunt */
background-size: calc(W * 1.10) calc(H * 1.10);
filter: blur(4px) saturate(1.5) brightness(.78);
/* 2. blur: zelfde achtergrond op ware grootte, gemaskeerd tot 10 px binnen de rand
      (afgeronde rechthoek, 3 px zachte overgang) */
filter: blur(12px) saturate(1.5) brightness(.78);
/* 3. tint */
background: linear-gradient(180deg, rgba(255,255,255,.10), transparent 45%), rgba(255,255,255,.14);
/* 4. lichtrand */
box-shadow: inset 0 1px 0 rgba(255,255,255,.55), inset 0 0 0 .5px rgba(255,255,255,.30),
            inset 0 -1px 0 rgba(255,255,255,.10);
/* op het vlak zelf */
box-shadow: 0 8px 24px rgba(0,0,0,.28), 0 1px 3px rgba(0,0,0,.18);
/* tekst en iconen op glas */
text-shadow: 0 0 1px rgba(0,0,0,.45), 0 1px 8px rgba(0,0,0,.45);
```

Resume in LG-02 gebruikt dezelfde lagen met tint .92 en zonder demping, zodat de knop wit blijft
zoals de CTA-regel voorschrijft.

Het tvOS-nepglas staat in `src/tv-glass.css`:

```css
backdrop-filter: blur(30px) saturate(1.2) brightness(.80);
background: linear-gradient(180deg, rgba(255,255,255,.08), transparent 50%), rgba(255,255,255,.12);
box-shadow: inset 0 1.5px 0 rgba(255,255,255,.40), inset 0 0 0 1px rgba(255,255,255,.12),
            0 12px 32px rgba(0,0,0,.30);
```

De blur is in beide gevallen een sigma in logische pixels; CSS `blur(12px)` is
`ImageFilter.blur(sigmaX: 12, sigmaY: 12)`.

## Wat in de beelden afwijkt van de bestaande mockups

- LG-02 zet de hero over de volle breedte en achter de statusbalk, omdat de knoppen anders niet
  over het artwork liggen. De kijklijstknop verhuist van de actierij naar een ronde knop naast
  Download. Beide zijn met DEC-122 goedgekeurd.
- LG-06 toont de ruststand. Een eerdere versie had de resultaten omhoog gescrold zodat posters
  onder de pil lagen; dat oogde als een verkeerd geplaatste zoekbalk en is teruggedraaid. Scrollt
  de pil in de app mee, dan ligt het glas altijd op `#141414` en is het nauwelijks van een donkere
  pil te onderscheiden; blijft hij staan, dan komt het glas pas bij scrollen tot zijn recht.
- In de glazen topbalk van LG-04 is de focus een witte pil die 1,08 keer vergroot met een schaduw.
  De witte ring uit `tv.css` valt direct om een witte pil weg.
- Drie posters (Sintel, Coffee Run, The Daily Dweebs) hadden in de bron een bekeken-vinkje. Dat is
  in `make_art.py` overgeschilderd met het stuk poster ernaast, zodat ze in een verder-kijkenrij
  passen.

## Naar Flutter

1. iPhone: `liquid_glass_renderer` (whynotmake-it), met één `LiquidGlassLayer` per groep vlakken en
   `LiquidGlass(shape: LiquidRoundedSuperellipse(...))` voor tabbalk, knoppen en spelerplaat.
2. De tokens hierboven gaan naar `LiquidGlassSettings`: `blur: 12`, `glassColor: Color(0x24FFFFFF)`,
   `saturation: 1.5`, `thickness` en `refractiveIndex` op het oog tot de rand zoveel breekt als LG-01.
3. Het pakket heeft Impeller nodig; op Skia valt het terug op `FakeGlass`, en dat is dezelfde
   gradatie als het tvOS-nepglas.
4. Apple TV: `ClipRRect` plus `BackdropFilter(filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30))`,
   een `DecoratedBox` voor tint en lichtrand, en een `ColorFilter.matrix` voor verzadiging en
   demping. Het spelerpaneel heeft die opbouw al (`kTvPanelBlurSigma`, DEC-101).
5. Breking kan op tvOS niet: er is geen `liquid_glass_renderer` voor tvOS, en een eigen
   fragment-shader op de engine-fork is werk dat buiten deze ronde valt.

## Herschieten

```
cd docs/assets/liquid-glass/src
python3 make_art.py          # knipt art/ uit ~/Pictures/pleya-asc/2026-09-24
node ios/shoot.mjs           # LG-01 tot en met LG-03
cd ../../tvos-unified/src
PLEYA_MOCKUP_ART=$PWD/../../liquid-glass/src/art \
PLEYA_MOCKUP_DEST=$PWD/../../liquid-glass/mockups-2026-09-24 node build.mjs LG-
cd ../../liquid-glass/src && python3 compare.py   # LG-07 en LG-08
```

`art/` en `out/` staan niet in git. De tvOS-pagina's staan in
`docs/assets/tvos-unified/src/pages/LG-0*.html` en halen hun glas uit `src/tv-glass.css`.
