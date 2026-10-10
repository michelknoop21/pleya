# Pleya Web S7: kaart, hero, rail en artworkmaat (commitgrens 4)

Werkmap: `pleya_web/`, branch `feat/pleya-web-s7-shell`. Masterlijstrij: S7.4.

Doel: `MediaCard` krijgt alle staten van northstar-scherm 16, `Hero` en `HubRail` krijgen de
geometrie van beeld 01 (1600 en 393), de hero-titel staat in ArchivoBlack zoals DESIGN.md
hoofdstuk 2 voorschrijft, en een `srcset`-helper rekent per artworkvlak de juiste trede van de
artworkladder uit zonder de server vooruit te bouwen. Alles in de bestaande galerij
`/dev/primitives`, met opnamen op 393, 1024 en 1600 naast de northstar.

Buiten deze grens: routes migreren (commitgrens 6, S7.6), de Nederlandse locale (commitgrens 5,
S7.5), boekkaarten (S9), Home met zes rijen en de hero-rotatie (S8), de serverladder zelf (S4.4).

Bronnen, in deze volgorde lezen: `docs/assets/pleya-web-northstar/DESIGN.md` (hoofdstuk 2, 3, 5
en 8), `docs/assets/pleya-web-northstar/src/web.css` regels 150 tot 247 (de contractklassen
`.card`, `.prog`, `.seen`, `.dot-new`, `.badge-src`, `.over`, `.rail`, `.fade-r`, `.hero`), de
beelden `16-kaartstaten@1600.jpg`, `01-home@1600.jpg`, `01-home@1280.jpg`, `01-home@1024.jpg`,
`01-home@393.jpg`, `15-skeleton@1600.jpg` en `15-skeleton@393.jpg` in dezelfde map, het specimen
`docs/qa/s7-primitives/v2-specimen/`, `pleya_web/README.md` sectie "Het designsysteem" en
"Artwork", en `docs/pleya-server-rebaseline/E-architectuurbesluiten.md` RB-7 (de ladders).

## Preflight (uitgevoerd 2026-10-10)

| Controle | Uitkomst |
| --- | --- |
| `git fetch --all` | `feat/pleya-web-s7-shell` staat gelijk met `github/feat/pleya-web-s7-shell` op `bef71ec9`, 42 commits boven `github/main`. |
| `git log github/main -- pleya_web` | Laatste webcommit `5ed41f0c` (CSP voor de route-announcer, #219); de branch draagt dezelfde fix. Geen kaart-, hero- of railwerk na PS-4E. |
| `git grep` op `github/main` en `origin/main` | `MediaCard`, `Hero`, `HubRail` en `MediaGrid` bestaan sinds PS-4E, in de oude vorm: geen kaartstaten, hero van rand tot rand, rail zonder bleed en fade. Geen `srcset`, geen ArchivoBlack in `pleya_web`. |
| Andere remote branches | `archive/worktree-pleya-web-ps4e` heeft dezelfde componentbestanden als `main`. De `feat/website-*`-branches raken `pleya_web` niet (alleen achterstand op `main`). Geen branch bevat S7.4-werk. |
| Wat de branch al heeft | Taak 4 van commitgrens 3 (`5bbf2837`) haalde de maten van `Hero` en `HubRail` naar tokens (`--hero-min-h`, `--rail-cell-w`) zodat `SkeletonPage` ze deelt. `MediaCard` zelf is op de branch niet gewijzigd. S7.3 noteert als bewuste afwijking dat het skeletheld van rand tot rand loopt "tot de Hero/HubRail-herschrijving": die afwijking sluit in deze grens. |
| Masterlijst | S7.4, S7.5 en S7.6 staan op `[ ]`; teller "149 taken, 23 gereed, 3 bezig, 123 open". |
| Worktrees | Geen andere worktree op deze branch; `pleya-web-csp` is de reeds gemergede CSP-fix. |
| Font | `assets/fonts/ArchivoBlack-Regular.ttf` staat in de repo (app en mockups); `pleya_web/static/fonts/` heeft alleen Inter in woff2. |
| Protocol | `/artwork/{id}` kent `?width=` al (zonder parameter het origineel); de capability `artwork_sizes` bestaat nog niet en komt met S4. Het protocolvenster is dicht. |

Conclusie: niets wordt dubbel gebouwd. De drie componenten bestaan en worden herschreven met
behoud van hun props, zodat de routes van commitgrens 6 ongewijzigd blijven werken.

## Global Constraints

- Geen vermelding van AI, model of leverancier in code, comments, commits of documenten; geen
  `Co-Authored-By` of sessieregel. Auteur is Michel Knoop.
- Commits met `SKIP_HOOKS=1`. Alleen `pleya_web/` en `docs/` worden aangeraakt, geen Dart, geen
  Go, geen `docs/pleya-protocol/`.
- Geen inline `style=`-attributen (CSP). Variatie via klassen en tokens; `style:`-directives van
  Svelte zijn toegestaan (zie README "Geen inline stijl").
- Kleuren, maten en radii uit `tokens.css`. Waar de northstar een maat noemt die nog geen token
  is (posterbreedte, rail-gap, hero-radius bestaan al), gebruik je het bestaande token; een nieuw
  token krijgt een waarde voor alle drie de thema's en een comment met de bron.
- Elke zichtbare tekst via `t()`, sleutels in `src/lib/i18n/web.ts` in het Engels. Nederlands is
  commitgrens 5.
- Svelte 5 runes. Raadpleeg Context7 voor elke Svelte-, SvelteKit-, testing-library- of
  vitest-API die nog niet in de codebase staat (bijvoorbeeld `createContext`/`setContext`,
  `ResizeObserver` in jsdom), met bronvermelding in het taakrapport.
- Toegankelijkheid: toetsenbord, `aria-*`, zichtbare focus, 44 px raakvlak, geen interactief
  element binnen een `<a>`.
- Bestanden onder 400 regels; één verantwoordelijkheid per bestand. `MediaCard.svelte` dreigt
  daarboven te komen: badges en overlay gaan dan naar een eigen component.
- Props van `MediaCard`, `Hero` en `HubRail` blijven achterwaarts verenigbaar: elke nieuwe prop is
  optioneel. `MediaGrid`, `routes/+page.svelte`, `routes/libraries/[id]` en `routes/search`
  compileren en werken zonder wijziging.
- Geen knop die naar niets leidt (DESIGN.md reviewlijst punt 3). Afspelen in de browser is PS-4W
  en niet vrijgegeven: een afspeelknop verschijnt alleen als de aanroeper een bestemming meegeeft.
- Commentaar in het Nederlands, het waarom, in de stijl van de omliggende bestanden.
- Bewijs per taak: `bun run check`, `bun run test`, `bun run build`, en bij zichtbare taken de
  screenshotpaden. Rapport en briefs in `.superpowers/sdd/2026-10-10-pleya-web-s7-commitgrens4/`.
- Geen `git push`, geen merge. `docs/PLEYA-SERVER-MASTERLIST.md` alleen in taak 7.
- Taken strikt na elkaar, nooit parallel; elke taak eindigt met een eigen commit.

## Niveauverdeling

| Taak | Onderwerp | Niveau |
| --- | --- | --- |
| 1 | Fundament: ArchivoBlack, artworkladder, loader-context | mechanisch |
| 2 | `MediaCard` met de staten van scherm 16 | visueel/protocol |
| 3 | `Hero` en het skeletheld | visueel/protocol |
| 4 | `HubRail` en de skeletrail | visueel/protocol |
| 5 | Opnamen naast de northstar | mechanisch |
| 6 | Visuele gate, verse reviewer | visueel/protocol |
| 7 | Bookkeeping | mechanisch |

## Task 1: Fundament (ArchivoBlack, artworkladder, loader-context)

Niets zichtbaars; drie stukken die taak 2 tot 4 nodig hebben.

**Lettertype.** DESIGN.md hoofdstuk 2: "ArchivoBlack 900, alleen voor de hero-titel en
detailtitel op breed". Zet `assets/fonts/ArchivoBlack-Regular.ttf` om naar
`pleya_web/static/fonts/ArchivoBlack-Regular.woff2` met het bestaande fonttools-recept uit de
README (zelfde docker-aanroep, bestandsnaam erbij). `@font-face` in `src/styles/base.css` naast
Inter, `font-weight: 900`, `font-display: swap`. Nieuw token `--font-display: 'ArchivoBlack',
var(--font-sans)` in `tokens.css`. Geen preload: het font hoort bij één element per pagina.
Controleer dat de CSP (`font-src`) het bestand toelaat in `bun run build` plus de bestaande
CSP-test.

**Artworkladder.** Nieuw `src/lib/util/srcset.ts` met:

```ts
export const POSTER_LADDER = [240, 480, 960, 1920] as const;   // RB-7, poster en boekcover
export const BACKDROP_LADDER = [480, 960, 1920, 3840] as const; // RB-7, backdrop en hero
export type ArtworkRole = 'poster' | 'backdrop';
/** Kleinste trede die cssWidth * dpr dekt; boven de top de top. */
export function ladderStep(cssWidth: number, dpr: number, role: ArtworkRole): number;
/** Of de server afgeleide formaten levert. Vandaag altijd false: S4.4 zet hem aan. */
export const ARTWORK_SIZES_AVAILABLE = false;
/** De breedte om te vragen, of undefined: dan het origineel. */
export function requestWidth(cssWidth: number, dpr: number, role: ArtworkRole,
  available?: boolean): number | undefined;
```

Een echt `srcset`-attribuut is hier onmogelijk en dat staat bovenaan het bestand: artwork komt
binnen via `fetch` met een Authorization-header en hangt als object-URL aan het element (README
"Artwork"), dus de browser kan zelf geen bron kiezen. De helper doet het werk van `srcset` en
`sizes` aan de clientkant: één trede per vlak, gemeten aan de getekende breedte. Zolang
`ARTWORK_SIZES_AVAILABLE` false is gaat er geen `?width=` over de lijn; de terugval is het
origineel, precies wat het contract belooft. Geen capability-veld lezen dat het protocol niet kent.

`Artwork.svelte` krijgt een optionele prop `role?: ArtworkRole` (standaard afgeleid van `shape`:
`wide` en `free` zijn backdrop) en meet bij het laden `host.clientWidth` en
`window.devicePixelRatio`. `client.artworkBlob(id, signal, width?)` zet `?width=` alleen als
`width` gedefinieerd is. De bestaande clienttest "zet het artwork-id in het pad en niet in de
querystring" blijft ongewijzigd groen.

**Loader-context.** De galerij en de tests hebben artwork nodig zonder server en zonder
TMDb-beelden in git. `Artwork.svelte` leest een optionele loader uit een Svelte-context
(`src/lib/components/artworkLoader.ts`, `setArtworkLoader(fn)` en `getArtworkLoader()`), met
`session.client.artworkBlob` als standaard. Productie zet de context nergens; gedrag daar is
ongewijzigd.

Bestanden: `static/fonts/ArchivoBlack-Regular.woff2` (nieuw), `src/styles/base.css`,
`src/styles/tokens.css`, `src/lib/util/srcset.ts` (nieuw), `src/lib/util/srcset.test.ts` (nieuw),
`src/lib/components/artworkLoader.ts` (nieuw), `src/lib/components/Artwork.svelte`,
`src/lib/components/Artwork.test.ts`, `src/lib/api/client.ts`, `src/lib/api/client.test.ts`.

Tests: `ladderStep` op 110 px bij DPR 2 geeft 240, 190 px bij DPR 2 geeft 480, 3000 px backdrop
geeft 3840, 9000 px geeft de top; `requestWidth` geeft `undefined` bij `available` false en een
trede bij true; `artworkBlob` met `width` 480 zet `?width=480`, zonder `width` geen querystring;
`Artwork` gebruikt een loader uit de context en valt zonder context terug op de client.

Acceptatie: drie commando's groen, de woff2 kleiner dan het TTF-bestand (grootte in het rapport),
`grep -r "width=" src/lib/api/client.ts` alleen achter de `width !== undefined`-tak.

Commit: `feat(pleya-web): ArchivoBlack, artworkladder en loader-context voor S7.4`.

## Task 2: `MediaCard` met de staten van scherm 16

Beeld 16 is het doel, `web.css` regels 154 tot 180 de maatvoering. Staten:

| Staat | Bron in `Item` of prop | Teken |
| --- | --- | --- |
| rust | | poster 2:3, radius `--radius-sm`, titel 14/500 (13 onder 900), onderregel 12 in `--ink-3` (11 onder 900) |
| hover | `@media (hover: hover)` | ring `--ring` in `--ink`, lift 3 px, schaduw, titel 700, acties onderin als de aanroeper ze geeft |
| toetsenbordfocus | `:focus-visible` | ring op een gap van 3 px, geen lift |
| voortgang | `user_state.position_ms` en `duration_ms`, niet bekeken | balk van 4 px onderaan het beeld in `--accent` op 22 % wit; onderregel "1h 12m left" |
| gezien | `user_state.watched`, of bij een serie `watched_episode_count === episode_count` | witte schijf van 22 px rechtsboven met vinkje |
| nieuw | prop `isNew` | amber punt van 9 px rechtsboven; nooit samen met gezien (gezien wint) |
| versies | `versions.length > 1` | pil linksboven, "2 versions" |
| aflevering in Verder kijken | props `artworkId` en `subtitle` | posterbeeld van de serie, regel "S2 · E3 · 31m left" |
| volgende aflevering | `shape="wide"` | 16:9, breedte `--poster-w * 1.78` |
| geen artwork | id ontbreekt of laden faalt | titel en jaar gecentreerd op `--panel`, nooit een grijs blok zonder tekst |

De boekstaten uit 16 horen bij S9 en worden niet gebouwd.

Interface, alle nieuwe props optioneel:

```ts
interface Props {
  item: Item;
  eager?: boolean;
  shape?: 'poster' | 'wide';
  isNew?: boolean;                 // de aanroeper bepaalt "nieuw sinds je laatste bezoek" (S8)
  artworkId?: string | null;       // overschrijft de afleiding, voor een serieposter bij een aflevering
  subtitle?: string;               // overschrijft itemSubtitle
  actions?: Snippet;               // knoppen in de hover-overlay; zonder snippet geen overlay
}
```

Structuur: de kaart is een `div` met positie, de link (`<a href="/items/{id}">`) dekt beeld en
bijschrift, en de actie-overlay staat als zuster boven het beeld, zodat er geen knop in een `<a>`
staat. De overlay verschijnt bij hover en bij `:focus-within`, zodat een toetsenbordgebruiker de
acties bereikt. `Artwork` krijgt een `fallback`-snippet voor de geen-artworkstaat (het
pictogram blijft de standaard elders). Voortgang en gezien in een eigen helper in
`src/lib/util/format.ts` (`itemProgress(item)`, `isWatched(item)`), zodat `MediaGrid` en de latere
detailpagina dezelfde regel lezen. Badges en overlay in `MediaCardBadges.svelte` als
`MediaCard.svelte` boven 250 regels komt. Hover-schaal `1.04` uit de huidige versie verdwijnt:
de northstar tilt, hij vergroot niet. `prefers-reduced-motion` schakelt de lift uit.

Galerijsectie `kaarten` in `src/routes/dev/primitives/` (`CardSection.svelte`, id in
`sections.ts`), twee rijen zoals beeld 16, met demo-artwork via de loader uit taak 1: posters en
backdrops als gegenereerde verlopen met de titel erin (canvas naar Blob, in
`src/routes/dev/primitives/demoArtwork.ts`), geen TMDb-materiaal. De hover-kaart krijgt drie
demoknoppen (afspelen, mijn lijst, meer) met `t()`-labels; die bestaan alleen in de galerij.

Tests (`MediaCard.test.ts` uitbreiden): voortgangsbalk met de juiste breedte en tekst, gezien
wint van nieuw, versiepil alleen boven één versie, geen-artworkstaat toont titel en jaar,
`actions`-snippet buiten de link (`closest('a')` is null), geen overlay zonder snippet,
`artworkId`- en `subtitle`-overschrijving. Bestaande tests blijven groen.

i18n-sleutels: `card.remaining` (met `{duration}`), `card.watched`, `card.new`,
`card.versions` (meervoud), en de drie demolabels onder `dev.`.

Acceptatie: drie commando's groen; screenshot van `#kaarten` op 1600 naast
`16-kaartstaten@1600.jpg` in het rapport; `MediaGrid` en `HubRail` tonen ongewijzigd.

Commit: `feat(pleya-web): MediaCard met de staten van scherm 16 (S7.4)`.

## Task 3: `Hero` en het skeletheld

Beeld 01 is het doel, `web.css` regels 226 tot 247 de maatvoering:

| Breedte | Vorm | Tekst |
| --- | --- | --- |
| ≥ 1200 | 21:9, ingesprongen op `--inset`, radius `--radius-hero` | linksonder (44 links, 40 onder), scrim van links en van onder |
| 900 tot 1199 | 16:9 | titel 38, inzet 32 en 28 |
| < 900 | portret van 520 px | gecentreerd onderaan, scrim van onder, knoppen elk de halve breedte |

Titel in `--font-display`, hoofdletters, spatiëring 0,12 em, 48 px (38 onder 1200, 32 met 0,2 em
onder 900). Metaregel 15 in `--ink-2` met punten ertussen (soort, jaar, duur). Synopsis en
leeftijdsbadge staan in de northstar maar `Item` draagt ze nog niet (PS-7N, S4): de hero toont ze
als een optionele prop `summary` gevuld is en anders niet, zonder plaatshouder.

Knoppen: "Meer info" (secundaire capsule met i-pictogram) naar `/items/{id}`, altijd. "Play"
(witte capsule met driehoek) alleen met een prop `playHref`; geen route geeft hem in deze grens
mee, omdat de browserspeler PS-4W is. Het comment bovenaan het bestand dat zegt dat er geen
afspeelknop staat, wordt hierop bijgewerkt.

Niet in deze taak: de segmentindicator en de rotatie over meerdere titels. DESIGN.md hoofdstuk 8
noemt de indicator een open designdetail dat een ja vraagt, en rotatie hoort bij Home (S8).

Interface: `item: Item` blijft verplicht; nieuw en optioneel zijn `summary?: string`,
`playHref?: string`, `label?: string` (de `aria-label`, standaard de huidige). `max-height: 62dvh`
en de rand-tot-randvorm verdwijnen. Artwork via `role="backdrop"` uit taak 1, `object-position`
50 % 25 % (50 % 20 % onder 900).

Skelet: `Skeleton kind="hero"` en `SkeletonPage` volgen dezelfde vorm (ingesprongen, radius,
21:9, 16:9, 520 px), via gedeelde tokens in `tokens.css` (`--hero-aspect`, `--hero-h-narrow`) in
plaats van `--hero-min-h`. Daarmee sluit de bewuste afwijking uit S7.3. Pas de skeletopnamen niet
aan in deze taak, dat doet taak 5.

Galerijsectie `hero` met vier varianten: met afspeelknop en synopsis, zonder afspeelknop, zonder
artwork, en een lange titel die over twee regels breekt (393 in beeld 01 breekt "DUNE: PART TWO").

Tests (`Hero.test.ts` uitbreiden): geen afspeelknop zonder `playHref`, wel met; "Meer info" wijst
naar het item; synopsis alleen met `summary`; titel heeft de display-klasse.
`Skeleton.test.ts` en `SkeletonPage.test.ts` blijven groen of krijgen een assertie op de nieuwe
vorm.

i18n: `hero.play`, `hero.moreInfo` (vervangt `home.heroAction` niet; die blijft tot commitgrens
6 in gebruik).

Acceptatie: drie commando's groen; screenshots van `#hero` en `#skelet` op 393, 1024 en 1600 in
het rapport naast `01-home` en `15-skeleton` op dezelfde breedtes; `routes/+page.svelte` toont de
nieuwe hero zonder codewijziging.

Commit: `feat(pleya-web): Hero op de geometrie van beeld 01, skeletheld volgt (S7.4)`.

## Task 4: `HubRail` en de skeletrail

Beeld 01, `web.css` regels 150 tot 157:

- Kop: titel als sectiekop 20/700 (18 onder 900) links, "View all ›" rechts als `href` gegeven
  is, altijd zichtbaar (de huidige versie verbergt hem tot hover). Titel en link zijn twee
  elementen, beide met een raakvlak van 44 px.
- Spoor: bleed tot de rand van het venster, de eerste kaart lijnt uit op `--inset`, ruimte
  `--rail-gap`, celbreedte `--poster-w` (wide: `--poster-w * 1.78`). `--rail-cell-w` vervalt, en
  `SkeletonPage` leest dezelfde tokens zodat skelet en rail even breed blijven.
- Fade rechts: 90 px verloop naar `--bg`, alleen zolang er rechts nog iets te schuiven valt (een
  scroll-luisteraar met `requestAnimationFrame`, of `scroll-timeline` als Context7 bevestigt dat
  de doelbrowsers het dragen), `pointer-events: none`.
- Pijlknoppen: blijven achter `(hover: hover) and (min-width: 900px)`, verschijnen alleen bij
  hover of `:focus-within` van de rail, labels via `t('rail.scrollLeft')` en
  `t('rail.scrollRight')` in plaats van de huidige Engelse letterlijke tekst. De linker is
  uitgeschakeld aan het begin, de rechter aan het eind.
- Een lege rij tekent zichzelf nog steeds niet.

Interface: `title`, `items`, `href`, `viewAllLabel` blijven; nieuw en optioneel is
`card?: Snippet<[Item, number]>`, zodat een aanroeper zijn eigen `MediaCard`-props (bijvoorbeeld
`isNew`) meegeeft. Zonder snippet tekent de rail de standaardkaart.

Galerijsectie `rail` met een posterrail van twaalf demotitels (meer dan op 1600 past, zodat de
fade zichtbaar is), een wide-rail met vijf afleveringen, en een rail zonder `href`.

Tests (`HubRail.test.ts` uitbreiden): "View all" zichtbaar en een eigen link, pijllabels via
`t()`, linkerpijl uitgeschakeld bij scrollpositie 0, snippet vervangt de standaardkaart, lege rij
rendert niets.

i18n: `rail.scrollLeft`, `rail.scrollRight`, `rail.viewAll`.

Acceptatie: drie commando's groen; geen horizontale overloop van de pagina op 393, 768, 1024,
1280 en 1600 (de rail schuift binnen zichzelf); screenshots van `#rail` en `#skelet` op 393 en
1600 naast `01-home`.

Commit: `feat(pleya-web): HubRail met bleed, fade en kop uit beeld 01 (S7.4)`.

## Task 5: Opnamen naast de northstar

`scripts/primitives-shots.ts` neemt de nieuwe secties vanzelf mee via `sections.ts`. Voeg twee
gerichte opnamen toe: `kaarten-hover` (muis boven de tweede kaart) en `kaarten-focus`
(tabtoets naar de derde kaart), naar het voorbeeld van `focus-knop`. Maak opnieuw:
`kaarten`, `kaarten-hover`, `kaarten-focus`, `hero`, `rail` op 393, 1024 en 1600 in dark, en
`kaarten` en `hero` in light en OLED op 393 en 1600; `skeleton-home` op de vijf breedtes, omdat
het skeletheld veranderde. Naast elke breedte een samengesteld vergelijkingsbeeld met de
northstar ernaast (`<naam>-vs-northstar@<breedte>.png`), gemaakt met hetzelfde script of met
`pw screenshot` op een kleine vergelijkingspagina in de galerij; geen TMDb-beelden in git, de
northstar-JPG's staan er al.

`docs/qa/s7-primitives/README.md` krijgt een sectie "Commitgrens 4" met wat elke opname laat zien
en welke afwijking bewust is (synopsis en leeftijdsbadge ontbreken zonder data, geen
segmentindicator, demo-artwork in plaats van posters).

Acceptatie: alle bestanden bestaan, README noemt ze, `git status` toont alleen `docs/qa/` en
eventueel het script.

Commit: `docs(pleya-web): opnamen van kaart, hero en rail naast de northstar`.

## Task 6: Visuele gate

Verse reviewer die niets bouwde. Vergelijkt de opnamen uit taak 5 met `16-kaartstaten`,
`01-home` (1600, 1280, 1024, 393) en `15-skeleton`, en loopt de acht punten van de reviewlijst
uit DESIGN.md hoofdstuk 6 af plus: kaartmaten per breedte gemeten in DevTools tegen
`--poster-w`, hover en focus onderscheidbaar, ArchivoBlack daadwerkelijk geladen (Network-tab of
`document.fonts.check`), geen knop zonder bestemming, `axe` op `/dev/primitives#kaarten`, `#hero`
en `#rail` zonder serious of critical. Verdict PASS of CHANGES met Critical, Important en Minor in
`task-6-gate.md` in het ledger. Bij CHANGES gaat de bevinding terug naar de taak die hem
veroorzaakte (zelfde model), daarna een nieuwe gate. Geen code in deze taak.

## Task 7: Bookkeeping

Alleen na PASS in taak 6.

- `docs/PLEYA-SERVER-MASTERLIST.md`: S7.4 naar `[x]` met bewijs (commits, vitest-aantal,
  `svelte-check`-uitvoer, opnamemap, gate-verdict) en datum. Teller "149 taken, 23 gereed, 3
  bezig, 123 open" wordt "149 taken, 24 gereed, 3 bezig, 122 open"; controleer vooraf dat de
  teller op de branch nog die waarde heeft en tel anders opnieuw. De blokkentabel verandert niet,
  S7 is nog niet dicht. Regel "Laatst bijgewerkt" bijwerken. Bewuste afwijkingen in de bewijskolom:
  geen echt `srcset`-attribuut (auth-header), ladder uit tot S4.4, synopsis en leeftijdsbadge
  wachten op S4, segmentindicator open.
- S7.2 noemt de staten 12, 14 en 15 als open; werk de verwijzing naar 15 bij als het skeletheld nu
  overeenkomt, en laat de rest staan.
- `pleya_web/README.md`: sectie "Letters" (ArchivoBlack, waar en waarom alleen daar, het recept),
  "Primitieven" (`MediaCard`, `Hero`, `HubRail` met één regel elk), "Artwork" (de ladder, waarom
  geen `srcset`-attribuut, wat S4.4 omzet).
- Taakteller van dit plan in het ledger (`progress.md`) op 7 van 7.

Commit: `docs(pleya-server): S7.4 gereed met bewijs`.

## Open punten voor de eigenaar

- De segmentindicator en "Meer info" als tweede hero-knop staan in DESIGN.md hoofdstuk 8 als
  open designdetails die een ja vragen. Dit plan bouwt "Meer info" (het vervangt de bestaande
  knop met dezelfde bestemming) en laat de indicator weg tot dat ja er is.
