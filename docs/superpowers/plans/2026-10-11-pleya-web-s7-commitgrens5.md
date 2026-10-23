# Pleya Web S7: Nederlandse locale (commitgrens 5)

Werkmap: `pleya_web/`, branch `feat/pleya-web-s7-shell`. Masterlijstrij: S7.5.

Doel: de webclient spreekt Nederlands naast Engels. Elke sleutel heeft een Nederlandse waarde en
een test faalt zodra er een ontbreekt. De taal volgt uit een bewaarde keuze of de browsertaal en
staat op `<html lang>`. Duur, datum, getal en bestandsgrootte volgen de taal ("2u 46m", "nog 1u
12m", "12 augustus 2026", "8,3 GB"). Lange Nederlandse samenstellingen breken met een
afbreekstreepje in plaats van midden in het woord (minor M-1 uit de visuele poort van commitgrens
4). Serverfoutcodes en aria-labels zijn vertaald. Opnamen op 393, 1024 en 1600 in beide talen tonen
dat kop, hero-meta, tabbalk, knoppen en tabelkoppen het langere Nederlands dragen.

Buiten deze grens: routes migreren naar de nieuwe primitieven (commitgrens 6, S7.6). Dit plan
levert wel de locale-API waar S7.6 op bouwt: `t()`, `plural()`, `locale()`, `intlLocale()` en de
formatters lezen allemaal de actieve taal, zodat een gemigreerde route niets meer met taal hoeft te
regelen. De demoteksten in de galerij `/dev/primitives` (al Nederlands, alleen onder `vite dev`)
blijven zoals ze zijn.

Bronnen, in deze volgorde lezen: `pleya_web/src/lib/i18n/` (vier bestanden), `pleya_web/scripts/gen-i18n.ts`,
`pleya_web/src/lib/util/format.ts`, `pleya_web/src/lib/api/errors.ts`, `pleya_web/src/routes/+layout.svelte`
(regel 34 tot 43, waar de taal nu in `onMount` gezet wordt), de northstar-pagina's
`docs/assets/pleya-web-northstar/src/pages/01-home.html`, `06-zoeken.html`, `07-zoeken-leeg.html`,
`08-film-detail.html`, `09-serie-detail.html`, `11-mijn-pleya.html`, `12-inloggen.html`,
`14-server-offline.html` en `40-setup-eigenaar.html` (de terminologiebron), het specimen
`docs/qa/s7-primitives/v3-specimen/README.md`, en minor M-1 in
`.superpowers/sdd/2026-10-10-pleya-web-s7-commitgrens4/task-6-gate.md` (regel 97 tot 102).

## Preflight (uitgevoerd 2026-10-11)

| Controle | Uitkomst |
| --- | --- |
| `git fetch github` | `feat/pleya-web-s7-shell` staat gelijk met `github/feat/pleya-web-s7-shell` op `9780b537`. |
| `git log github/main -- pleya_web/src/lib/i18n` | Leeg: op `main` is `pleya_web/src/lib/i18n` nooit aangeraakt na de fundering. |
| `git grep -i "locale\|\bnl\b" github/main -- pleya_web/src/lib/i18n` | Alleen de bestaande stand: `LOCALES = ['en']` en een test die vastlegt dat `nl-NL` op Engels uitkomt ("nog geen Nederlandse catalogus"). Geen Nederlandse catalogus, geen pariteitstest. |
| `gh pr list --repo michelknoop21/pleya --state open` | Tien open PR's (#227 tot #252), allemaal app, tvOS, assistant, CI of docs. Geen enkele raakt `pleya_web`. |
| `git worktree list` | `pleya-web-s7` is de enige worktree op deze branch; `pleya-web-csp` is de reeds gemergede CSP-fix. Geen andere worktree werkt aan de webclient. |
| Wat de branch al heeft | Elke zichtbare tekst gaat door `t()`: een zoektocht naar letterlijke `aria-label`, `title`, `placeholder` en tekstknopen in `src/**/*.svelte` buiten `/dev/` levert niets op. `plural()` kiest de vorm al met `Intl.PluralRules`. `formatDuration` geeft sinds M-4 "3h" voor een rond uur. De app heeft `lib/i18n/nl.i18n.json` met een Nederlandse waarde voor alle 27 gedeelde sleutels. |
| Wat ontbreekt | `t()` is niet reactief (`let current`) en de taal wordt pas in `onMount` van de layout gezet, na het eerste renderen. `app.html` heeft vast `lang="en"`. `formatDuration` heeft de eenheden `h`, `m`, `s` hard in de code; `formatDate` en `formatCount` hebben `'en'` als standaard; `ERROR_MESSAGES` is een Engelse tabel buiten `t()`; er is geen `formatBytes`. |
| Terminologieverschil app en northstar | Drie gedeelde sleutels hebben in de app een andere Nederlandse term dan de northstar: `common.viewAll` ("Alles weergeven" tegen "Alles bekijken"), `navigation.libraries` ("Media" tegen "Bibliotheken"), `common.settings` ("Opties"). Geen van de drie wordt in `pleya_web/src` gebruikt (gecontroleerd met `grep`). |
| Masterlijst | S7.5 en S7.6 staan op `[ ]`; `scripts/masterlist_counts.sh --check` meldt "155 taken, 27 gereed, 3 bezig, 125 open". |
| E2E | `tests/e2e/*.spec.ts` zoekt op Engelse knopnamen ("Sign in", "Create owner"); `playwright.config.ts` zet geen `locale`, dus de browser blijft `en-US` en de suite blijft Engels draaien. |

Conclusie: niets wordt dubbel gebouwd. De i18n-module wordt uitgebreid, niet vervangen; alle
bestaande sleutels en aanroepen blijven.

## Global Constraints

- Geen vermelding van AI, model of leverancier in code, comments, commits of documenten; geen
  `Co-Authored-By` of sessieregel. Auteur is Michel Knoop.
- Commits met `SKIP_HOOKS=1`. Alleen `pleya_web/` en `docs/` worden aangeraakt. Geen Dart, geen Go,
  geen `docs/pleya-protocol/`, en `lib/i18n/nl.i18n.json` van de app wordt alleen gelezen.
- Geen inline `style=`-attributen (CSP). Geen inline script in `app.html` (CSP `script-src 'self'`).
- Elke zichtbare tekst, ook aria-labels en documenttitels, via `t()` of `plural()`. Nieuwe sleutels
  in het Engels in `web.ts` en tegelijk in het Nederlands in `web.nl.ts`.
- Terminologie: de northstar wint. Waar de app een gedeelde sleutel anders vertaalt dan de
  northstar, gebruikt de webclient een eigen web-sleutel en raakt hij de gedeelde vertaling niet aan.
- Svelte 5 runes. Raadpleeg Context7 (of MDN via Context7) voor elke API die nog niet in de
  codebase staat, met bronvermelding in het taakrapport. In dit plan zijn dat in elk geval
  `Intl.DisplayNames`, CSS `hyphens` en `hyphenate-limit-chars` (browserdekking, Safari-prefix) en
  de `locale`-optie van Playwrights `browser.newContext`.
- Bestanden onder 400 regels; één verantwoordelijkheid per bestand. `format.ts` (151 regels) krijgt
  er formatters bij: wordt hij langer dan 250, dan gaan de taalgebonden formatters naar
  `util/formatLocale.ts`.
- Commentaar in het Nederlands, het waarom, in de stijl van de omliggende bestanden.
- Bewijs per taak: `bun run check`, `bun run test`, `bun run build`, en bij zichtbare taken de
  screenshotpaden. Rapporten en briefs in `.superpowers/sdd/2026-10-11-pleya-web-s7-commitgrens5/`.
- Elke test die een fout moet vangen krijgt een negatieve controle: breek het gedrag tijdelijk,
  laat zien dat de test rood wordt (uitvoer in het rapport), zet het terug.
- Geen `git push`, geen merge. `docs/PLEYA-SERVER-MASTERLIST.md` alleen in taak 7.
- Taken strikt na elkaar, nooit parallel; elke taak eindigt met een eigen commit.

## Niveauverdeling

Vertalen zelf is mechanisch werk: een tabel invullen volgens een vaste terminologie, met een test
die gaten en verkeerde plaatshouders vangt. Taak 2 en 3 zijn daarom licht. Het zwaardere werk zit
in de opstartvolgorde van de taal (taak 1) en in wat het langere Nederlands met de layout doet
(taak 5 en 6).

| Taak | Onderwerp | Niveau |
| --- | --- | --- |
| 1 | Locale-kern: keuze, opslag, `<html lang>`, opstartvolgorde | visueel/protocol |
| 2 | Nederlandse catalogus, pariteitstest, foutcodes via `t()` | mechanisch (licht) |
| 3 | Formatters per taal | mechanisch (licht) |
| 4 | Taalkeuze in Mijn Pleya | mechanisch |
| 5 | Afbreken en lange teksten, opnamen in beide talen | visueel/protocol |
| 6 | Visuele gate, verse reviewer | visueel/protocol |
| 7 | Bookkeeping | mechanisch |

## Task 1: Locale-kern

Vandaag zet de layout de taal in `onMount`. Dat draait na het eerste renderen van de kinderen, en
`t()` leest een gewone variabele, dus wat al getekend is blijft Engels. De oplossing is de taal
één keer vast te stellen vóór er iets rendert, en een wissel af te handelen met een herlaad. Een
reactieve `$state` voor de taal lost het niet op: labels die in een `<script>`-blok berekend worden
(`ThemePicker`, `navItems`) lezen `t()` één keer en zouden toch blijven staan.

Interface in `src/lib/i18n/index.ts` (bestaande exports blijven):

```ts
export const LOCALES = ['en', 'nl'] as const;
export type Locale = (typeof LOCALES)[number];
export const DEFAULT_LOCALE: Locale = 'en';
export const LOCALE_STORAGE_KEY = 'pleya.locale';

/** Bewaarde keuze wint, dan de browsertalen, dan Engels. Een onbekende bewaarde waarde telt niet. */
export function resolveLocale(stored: string | null, preferred: readonly string[]): Locale;
/** Leest opslag en navigator, zet de taal en `document.documentElement.lang`. Idempotent. */
export function initLocale(): Locale;
/** Bewaart de keuze en herlaadt de pagina; doet niets als de taal al actief is. */
export function changeLocale(next: Locale, reload?: () => void): void;
/** De BCP 47-tag voor Intl: 'en' blijft 'en', 'nl' wordt 'nl-NL'. */
export function intlLocale(): string;
```

`pickLocale` blijft bestaan (alleen browsertalen) en `resolveLocale` gebruikt hem. Opslag gaat via
dezelfde try/catch-vorm als `stores/theme.svelte.ts`: geweigerde opslag valt terug op de browser.
`initLocale()` wordt aangeroepen bovenaan het `<script>`-blok van `routes/+layout.svelte`, vóór de
eerste markup, en de regel `setLocale(pickLocale(...))` in `onMount` verdwijnt. `app.html` houdt
`lang="en"` als waarde vóór het opstarten; dat is de juiste terugval voor wie geen JavaScript draait.
`plural()` gebruikt `intlLocale()` voor `Intl.PluralRules`.

Bestanden: `src/lib/i18n/index.ts`, `src/lib/i18n/i18n.test.ts`, `src/routes/+layout.svelte`.

Tests:
- `resolveLocale(null, ['nl-NL'])` is `nl`; `resolveLocale(null, ['en-GB', 'nl'])` is `en`;
  `resolveLocale('nl', ['en-US'])` is `nl`; `resolveLocale('fr', ['nl-BE'])` is `nl`;
  `resolveLocale(null, ['ja'])` en `resolveLocale(null, [])` zijn `en`.
- `initLocale()` zet `document.documentElement.lang` op `nl` als opslag `nl` bevat, en op `en`
  als `localStorage.getItem` gooit en de browser `ja` zegt.
- `changeLocale('nl', spy)` schrijft de opslagsleutel en roept `spy` één keer aan;
  `changeLocale` naar de actieve taal roept hem niet aan.
- De oude test "nog geen Nederlandse catalogus" wordt omgedraaid: `pickLocale(['nl-NL'])` is `nl`.
- Negatieve controle: haal `'nl'` uit `LOCALES` en laat de resolve-tests rood zien.

Acceptatie: drie commando's groen; `grep -n "setLocale(pickLocale" src/routes/+layout.svelte`
levert niets; in `vite dev` met de browsertaal op Nederlands staat er `<html lang="nl">` vóór de
eerste paint (controle met `pw` en `document.documentElement.lang` direct na `domcontentloaded`,
uitvoer in het rapport). Inhoudelijk is nog alles Engels, want er is nog geen catalogus.

Commit: `feat(pleya-web): taal vóór het eerste renderen vastgesteld, met opslag en html-lang (S7.5)`.

## Task 2: Nederlandse catalogus, pariteit en foutcodes

Licht werk: invullen volgens de tabel hieronder, met een test die gaten vangt.

**Gedeelde helft.** `scripts/gen-i18n.ts` leest naast `lib/i18n/en.i18n.json` ook
`lib/i18n/nl.i18n.json` voor dezelfde `KEYS` en schrijft `shared` en `sharedNl` in `shared.ts`.
Een sleutel die in de Nederlandse bron ontbreekt laat het script falen, net als nu bij Engels.

**Web-helft.** Nieuw `src/lib/i18n/web.nl.ts` met `export const webNl = { ... } satisfies
Record<WebKey, string>`. Daarmee is een ontbrekende of overtollige sleutel een compileerfout in
`bun run check`, nog vóór de test draait. `index.ts` krijgt `nl: { ...sharedNl, ...webNl }`.

**Foutcodes.** `ERROR_MESSAGES` in `api/errors.ts` wordt een lijst codes (`ERROR_CODES`) en elke
code krijgt de sleutel `error.<code>` in `web.ts` en `web.nl.ts`. `describeError` vertaalt via
`t()`; de generieke teksten worden `error.generic` ("Er ging iets mis.") en `error.genericCode`
("Er ging iets mis ({code})."). De code blijft het contract; matchen op `message` blijft verboden.

**Terminologie.** Bron is de northstar. Vaste termen, en waar een sleutel niet in de tabel staat
volgt de vertaling dezelfde toon (je-vorm, kort, geen uitroeptekens):

| Sleutel | Nederlands | Bron |
| --- | --- | --- |
| `hero.play`, `hero.moreInfo` | Afspelen, Meer info | 01, specimen v3 |
| `rail.viewAll` | Alles bekijken | 01 |
| `home.recentlyAdded` | Recent toegevoegd | 01 |
| `card.remaining` | nog {duration} | 08, 09 |
| `card.watched`, `card.new` | Gezien, Nieuw | 16 |
| `card.versions.one/other` | {count} versie / {count} versies | 16 |
| `hero.kind.*` | Film, Serie, Seizoen, Aflevering | 01, 09 |
| `item.season`, `item.episode` | Seizoen {index}, Aflevering {index} | 09 |
| `item.seasonsCount`, `item.episodesCount` | {count} seizoen(en), {count} aflevering(en) | 09 |
| `item.subtitles`, `item.added`, `item.duration` | Ondertitels, Toegevoegd, Duur | 08 |
| `item.forced`, `item.external`, `item.default` | geforceerd, extern bestand, standaard | 08 |
| `libraries.itemCount`, `libraries.approximate` | {count} titel(s), ongeveer {count} titels | 11, 12 |
| `nav.libraries`, `libraries.title` | Bibliotheken | 11 |
| `nav.books`, `nav.my`, `nav.search` | Boeken, Mijn Pleya, Zoeken | 01, 06, 11 |
| `login.title`, `login.submit` | Inloggen | 12 |
| `login.username`, `login.password` | Gebruikersnaam, Wachtwoord | 12, 40 |
| `setup.code`, `setup.submit` | Setupcode, Eigenaar aanmaken | 40 |
| `search.noResultsTitle` | Niets gevonden | 07 |
| `unreachable.title` | De server is niet bereikbaar | 14 |
| `theme.*` | OLED, Donker, Licht, Systeem | 11 |
| `common.logout` (gedeeld) | Uitloggen | app en 11 gelijk |

`setup.passwordHint` vertaalt de huidige Engelse regel (8 tekens); de 12 uit beeld 40 is een
toekomstige serverregel en geen vertaling. `login.rateLimited` wordt "Te veel pogingen. Probeer het
over {seconds} s opnieuw." `item.sdh` blijft SDH.

**Aria-labels.** Alle aria-sleutels krijgen een echte vertaling: `nav.primary` "Hoofdnavigatie",
`nav.skipToContent` "Naar de inhoud", `nav.expand` "Navigatie uitklappen", `rail.scrollLeft`
"Naar links schuiven", `rail.scrollRight` "Naar rechts schuiven", `steps.label` "Voortgang".

Bestanden: `scripts/gen-i18n.ts`, `src/lib/i18n/shared.ts` (gegenereerd), `src/lib/i18n/web.ts`,
`src/lib/i18n/web.nl.ts` (nieuw), `src/lib/i18n/index.ts`, `src/lib/i18n/parity.test.ts` (nieuw),
`src/lib/api/errors.ts`, de bestaande errors-test, en een nieuwe `src/lib/i18n/literals.test.ts`.

Tests:
- `parity.test.ts`: dezelfde sleutelset in `en` en `nl`; per sleutel dezelfde verzameling
  `{plaatshouders}`; voor elke meervoudssleutel bestaan `.one` en `.other` in beide talen; geen
  Nederlandse waarde is leeg. Een vergelijking "nl gelijk aan en" met een kleine toegestane lijst
  (`app.name`, `nav.home`, `nav.films`, `nav.series`, `nav.server`, `theme.oled`, `item.video`,
  `item.audio`, `item.sdh`, `dev.*`) vangt een vergeten kopie.
- Elke code uit `ERROR_CODES` heeft een `error.<code>`-sleutel in beide talen; een onbekende code
  geeft `error.genericCode` met de code erin.
- `literals.test.ts` leest `src/**/*.svelte` buiten `routes/dev/` en faalt op een
  `aria-label`, `title`, `placeholder` of `alt` met een letterlijke waarde in plaats van een
  `{...}`-expressie, naar het voorbeeld van `guard.test.ts`.
- Met de taal op `nl`: `t('hero.play')` is "Afspelen", `plural('item.seasonsCount', 1)` is
  "1 seizoen", `describeError` op `auth.invalid_credentials` geeft de Nederlandse tekst.
- Negatieve controles: een sleutel uit `web.nl.ts` weghalen geeft een fout in `bun run check`;
  `{count}` in één vertaling veranderen in `{aantal}` maakt `parity.test.ts` rood; een
  `aria-label="Sluiten"` in een component maakt `literals.test.ts` rood.

Acceptatie: drie commando's groen; `bun run scripts/gen-i18n.ts` gevolgd door `git diff --exit-code
src/lib/i18n/shared.ts` is schoon (het gegenereerde bestand is actueel).

Commit: `feat(pleya-web): Nederlandse catalogus met pariteitstest, foutcodes via t() (S7.5)`.

## Task 3: Formatters per taal

Licht werk, met een vaste uitvoertabel. Alle formatters lezen `intlLocale()` en hebben geen
taalparameter meer met `'en'` als standaard; een expliciete parameter blijft mogelijk voor tests.

| Functie | en | nl | Bron nl |
| --- | --- | --- | --- |
| `formatDuration(166 min)` | 2h 46m | 2u 46m | 01 |
| `formatDuration(180 min)` | 3h | 3u | M-4 |
| `formatDuration(31 min)` | 31m | 31 min | 09 ("nog 31 min") |
| `formatDuration(12 s)` | 12s | 12 s | 14 ("over 12 s") |
| `formatDate(...)` | Aug 12, 2026 | 12 augustus 2026 | 08 (`dateStyle: 'long'` in nl, `'medium'` in en blijft) |
| `formatCount(1200)` | 1,200 | 1.200 | Intl |
| `formatBytes(8.3e9)` | 8.3 GB | 8,3 GB | 08 |
| `formatLanguage('eng')` | English | Engels | 08 |

De eenheden van `formatDuration` komen uit sleutels (`duration.hm`, `duration.h`, `duration.m`,
`duration.s`), zodat een derde taal geen code raakt. `formatBytes` rekent decimaal (1000, zoals de
northstar "42,1 GB" voor een bestand toont), één decimaal boven de 10 kB, en zet de eenheid na een
spatie. `formatLanguage` gebruikt `Intl.DisplayNames` met `type: 'language'` (Context7 voor de
dekking en voor ISO 639-2-codes als `eng`, die `DisplayNames` niet altijd kent: een kleine
vertaaltabel van drie naar twee letters voor de codes die de server levert, en bij een onbekende
code de code zelf). `StorageMeter` krijgt geen nieuwe standaard, de aanroeper geeft
`formatBytes` mee.

De aanroepen in routes die nu `'en'` impliciet meekrijgen (`server/+page.svelte`,
`libraries/+page.svelte`, `libraries/[id]/+page.svelte`, `items/[id]/+page.svelte`) hoeven niet te
veranderen, want de standaard verschuift mee. Alleen `items/[id]/+page.svelte` krijgt
`formatLanguage(stream.language)` in de twee sporenlijsten; dat is een vertaalaanroep en geen
routemigratie.

Bestanden: `src/lib/util/format.ts` (of `formatLocale.ts` boven 250 regels), `format.test.ts`,
`src/lib/i18n/web.ts`, `web.nl.ts`, `src/routes/items/[id]/+page.svelte`.

Tests: de tabel hierboven in beide talen, plus `formatDuration` onder de minuut en `null` bij 0;
`formatBytes(0)` is "0 B"; `formatLanguage('xx')` geeft "xx". Negatieve controle: zet de
standaard van `formatDate` terug op `'en'` en laat de nl-datumtest rood zien.

Acceptatie: drie commando's groen; `grep -n "'en'" src/lib/util/format*.ts` vindt alleen nog
testinvoer of de Intl-tag in `intlLocale`.

Commit: `feat(pleya-web): duur, datum, getal, grootte en taalnaam per locale (S7.5)`.

## Task 4: Taalkeuze in Mijn Pleya

Nieuw `src/lib/components/LanguagePicker.svelte`, dezelfde vorm als `ThemePicker` (een native
`<select>` met een visueel verborgen label `t('settings.language')`). De opties staan in hun eigen
taal en worden niet vertaald: "English" en "Nederlands", zodat iemand die per ongeluk de verkeerde
taal kiest zijn eigen taal terugvindt. Kiezen roept `changeLocale()` aan; de pagina herlaadt.
De picker staat op `/server` direct onder de `ThemePicker`, zoals "Taal en ondertitels" in beeld 11
onder "Uiterlijk" hangt. De volledige indeling van Mijn Pleya is S7.6.

Bestanden: `src/lib/components/LanguagePicker.svelte` (nieuw), `LanguagePicker.test.ts` (nieuw),
`src/routes/server/+page.svelte` (één regel import, één regel gebruik).

Tests: de select toont de actieve taal; een wissel roept `changeLocale` met de gekozen waarde aan
(geïnjecteerde reload-stub, geen echte herlaad in jsdom); de optielabels zijn in beide talen
"English" en "Nederlands"; het label is aan de select gekoppeld (`getByLabelText`). Negatieve
controle: koppel het label los en laat de test rood zien.

Acceptatie: drie commando's groen; in `vite dev` tegen de e2e-stack (`scripts/e2e-stack.sh`)
wisselt de picker de hele schil naar Nederlands en terug, inclusief `<html lang>`, en de keuze
overleeft een herlaad. Twee screenshots in het rapport.

Commit: `feat(pleya-web): taalkeuze in Mijn Pleya (S7.5)`.

## Task 5: Afbreken en lange teksten, opnamen in beide talen

**Afbreken (M-1).** Herotitel, kaarttitel, railkop en paginakoppen krijgen `hyphens: auto` met
`overflow-wrap: break-word` als vangrail. Context7/MDN bepaalt of Safari nog `-webkit-hyphens`
nodig heeft en of `hyphenate-limit-chars` (bijvoorbeeld `10 4 4`, zodat korte woorden heel blijven)
in de doelbrowsers werkt; wat niet gedragen wordt komt er niet in. Afbreken werkt alleen met een
taal op het element of een voorouder, en die levert `<html lang>` uit taak 1.

Een bewuste beperking: mediatitels hebben geen eigen taalveld in het contract, dus een Engelse
filmtitel wordt in een Nederlandse interface met Nederlandse regels afgebroken. Een `lang` per
titel vraagt een veld dat het protocol niet heeft; dat gaat als notitie in het rapport en niet in
code.

**Lange teksten.** Loop deze plekken af met de Nederlandse catalogus en los op wat breekt, met
klassen en tokens:
- kop bij kaart en railkop met "Alles bekijken" ernaast (de link mag niet onder de titel vallen
  op 393);
- hero-meta ("Serie · 2022 · 2 seizoenen · nog 1u 12m") op één regel of netjes afgekapt;
- TabBar-labels op 393 ("Mijn Pleya", "Boeken") zonder afkappen of tweede regel;
- knoppen ("Opnieuw proberen", "Eigenaar aanmaken", "Alles bekijken") houden 44 px raakvlak en
  breken niet midden in een woord;
- tabelkoppen in `DataTable` en de `<dl>` op `/server` ("Functieniveau", "Mogelijkheden").

**Opnamen.** `scripts/primitives-shots.ts` en `scripts/screenshots.ts` krijgen een vlag
`--locale nl|en` die `browser.newContext({ locale })` zet en `pleya.locale` uit de opslag wist
(Context7 voor de Playwright-optie). Opnamen in `docs/qa/s7-locale/`, dark thema:
- galerij: `kaarten`, `hero` (inclusief hero B met "Kinderboekenweekgeschenk",
  "Arbeidsongeschiktheidsverzekering" en "Zandkasteelwedstrijdkampioenschappen"), `rail`,
  `tabel` en `knoppen`, op 393, 1024 en 1600, in `en` en `nl`;
- echte routes tegen de e2e-stack: Home, een bibliotheek, `/server`, `/login` en `/setup`, op 393,
  1024 en 1600, in `en` en `nl` (TopNav vanaf 900, MobileHeader en TabBar eronder);
- `docs/qa/s7-locale/README.md` met per opname wat hij bewijst en welke beperking bewust is.

Bestanden: `src/lib/components/Hero.svelte`, `MediaCard.svelte`, `HubRail.svelte`,
`TabBar.svelte`, `DataTable.svelte` (alleen waar een opname iets laat breken),
`src/styles/base.css`, `scripts/primitives-shots.ts`, `scripts/screenshots.ts`,
`docs/qa/s7-locale/`.

Tests: geen nieuwe unittests voor CSS. Wel een Playwright-meting in het rapport: op hero B in
`nl` is `getComputedStyle(title).hyphens` `auto`, `title.closest('[lang]').lang` is `nl`, en geen
van de drie samenstellingen staat zonder streepje gebroken (de gate kijkt naar het beeld).
Negatieve controle: dezelfde meting met de taal op `en` toont dat de samenstellingen dan wel zonder
streepje breken, wat bewijst dat de meting op `lang` reageert.

Acceptatie: drie commando's groen; `bun run test:e2e` groen (de suite draait in `en-US` en zoekt
op Engelse namen); geen horizontale paginaoverloop op 393, 768, 1024, 1280 en 1600 in beide talen
op de echte routes; alle opnamen bestaan en de README noemt ze; MediaCard, Hero en HubRail blijven
onder 400 regels.

Commit: `feat(pleya-web): afbreken op taal en ruimte voor langer Nederlands, opnamen in beide talen (S7.5)`.

## Task 6: Visuele gate

Verse reviewer die niets bouwde. Vergelijkt de opnamen uit taak 5 in `nl` met dezelfde opnamen in
`en` en met de northstar (`01-home`, `08-film-detail`, `11-mijn-pleya`, `12-inloggen`,
`40-setup-eigenaar`) op 393, 1024 en 1600. Controleert:
- M-1: de drie samenstellingen breken met een streepje, op elke breedte;
- geen afgekapte of over twee regels lopende TabBar-labels, knoppen of tabelkoppen;
- "Alles bekijken" blijft op de regel van de railkop op 393;
- de terminologie in beeld komt overeen met de northstar (steekproef van twintig termen uit de
  tabel in taak 2);
- `<html lang>` is `nl` op elke route in de Nederlandse run en `en` in de Engelse;
- schermlezernamen: in de toegankelijkheidsboom (Playwright `accessibility.snapshot` of axe) zijn
  de navigatie, de railpijlen en de hero-knoppen in het Nederlands;
- `axe` (wcag2a/aa, 21a/aa, 22aa, best-practice) op Home, `/server`, `/login` en de galerijsecties
  `#hero` en `#rail` in `nl` op 393 en 1280: geen serious of critical, en geen `html-has-lang` of
  `valid-lang`.

Verdict PASS of CHANGES met Critical, Important en Minor in `task-6-gate.md` in het ledger. Bij
CHANGES gaat de bevinding terug naar de taak die hem veroorzaakte, daarna een nieuwe gate. Geen
code in deze taak.

## Task 7: Bookkeeping

Alleen na PASS in taak 6.

- `docs/PLEYA-SERVER-MASTERLIST.md`: S7.5 naar `[x]` met bewijs (commits, aantal vitest-tests,
  `svelte-check`-uitvoer, de opnamemap `docs/qa/s7-locale/`, het gateverdict) en datum. Draai
  `scripts/masterlist_counts.sh --check` vóór de wijziging (verwacht "155 taken, 27 gereed, 3
  bezig, 125 open"; staat er iets anders, dan opnieuw tellen) en erna; de teller in de tekst wordt
  "155 taken, 28 gereed, 3 bezig, 124 open" en het script moet hem bevestigen. Regel "Laatst
  bijgewerkt" bijwerken. In de bewijskolom de bewuste beperkingen: taalwissel herlaadt de pagina,
  mediatitels worden met de regels van de interfacetaal afgebroken, de galerij blijft Nederlandse
  demotekst, de drie afwijkende gedeelde app-termen worden niet gebruikt.
- `pleya_web/README.md`: nieuwe sectie "Taal" (twee catalogi, de volgorde opslag, browser, Engels,
  waarom een wissel herlaadt, `web.nl.ts` en de compileercontrole, de pariteitstest, de regel dat de
  northstar de terminologie bepaalt, en `--locale` in de opnamescripts).
- Minor M-1 in het commitgrens-4-ledger krijgt een verwijzing naar de commit die hem sloot.
- Taakteller van dit plan in het ledger (`progress.md`) op 7 van 7.

Commit: `docs(pleya-server): S7.5 gereed met bewijs`.

## Open punten voor de eigenaar

- **Standaardtaal.** Het plan kiest: bewaarde keuze, dan browsertaal, dan Engels. Een browser op
  Duits krijgt dus Engels. Wil je dat de NAS-instantie standaard Nederlands spreekt ongeacht de
  browser, dan is dat een serverinstelling of een bouwvlag en geen clientregel; dat hoort niet in
  deze grens.
- **Taalwissel met herlaad.** Live wisselen zonder herlaad vraagt dat elk script-blok dat `t()`
  leest reactief wordt. Het plan kiest de herlaad, omdat de wissel zelden gebeurt en de sessie het
  herladen overleeft (refreshtoken in `localStorage`).
