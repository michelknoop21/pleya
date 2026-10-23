# Pleya Web S7: bestaande routes gemigreerd, axe groen op vijf breedtes (commitgrens 6)

Werkmap: `pleya_web/`, branch `feat/pleya-web-s7-shell`. Masterlijstrij: S7.6.

Doel: elke route die de webclient vóór S7 had, draait op de primitieven uit S7.3 en S7.4 en op de
paginabouw van de northstar, zonder functieverlies. De staten inloggen (beeld 12), server
onbereikbaar (14) en laden (15) zijn niet langer de oude schermen. Een e2e-spec draait axe op elke
route en elke staat, op 393, 768, 1024, 1280 en 1600, in Engels en Nederlands, en eist nul
overtredingen. De opnamen van Home, 12, 14 en 15 liggen naast de northstar zonder afwijking in
compositie of maat (acceptatie S7 in deel I). Daarmee sluit S7.6, en met een besluit over S7.2 ook
S7 als geheel.

Buiten deze grens: alles wat S8 herschrijft. Home met zes rijen, de keuze van het heroitem (M-6),
Films- en Series-landing, filters en facetten, zoeken in secties, de detailpagina volgens 08 en 09
(`DetailHero`, `EpisodeList`, `TrackList`), Mijn Pleya volgens 11 en een onbereikbare server midden
in een sessie. Deze grens migreert de bestaande inhoud naar de nieuwe bouwstenen; hij voegt geen
inhoud toe die een endpoint nodig heeft dat de route vandaag niet aanroept.

Bronnen, in deze volgorde lezen: `pleya_web/src/routes/` (alle `+page.svelte` en `+layout.svelte`),
`pleya_web/src/lib/components/` (`StateView`, `SkeletonPage`, `Skeleton`, `Field`, `Select`,
`Chips`, `Panel`, `Alert`, `DataTable`, `StatusPill`, `HubRail`), `pleya_web/src/lib/stores/session.svelte.ts`,
`pleya_web/tests/e2e/helpers.ts` en `flow.spec.ts`, `pleya_web/scripts/screenshots.ts`,
`primitives-shots.ts` en `shot-locale.ts`, `docs/assets/pleya-web-northstar/DESIGN.md` (hoofdstuk 3
en 5), de northstar-pagina's `01-home.html`, `12-inloggen.html`, `14-server-offline.html`,
`15-skeleton.html`, `13-lege-bibliotheek.html` (vorm van de lege staat), `40-setup-eigenaar.html` en
`src/web.css` (`.page`, `.page-title`, `.section-h`, `.state`, `.btn-row`), deel I en G van
`docs/pleya-server-rebaseline/`, het specimen `docs/qa/s7-primitives/v3-specimen/README.md`, en de
minors in `.superpowers/sdd/2026-10-10-pleya-web-s7-commitgrens4/task-6-gate.md` en
`.superpowers/sdd/2026-10-11-pleya-web-s7-commitgrens5/progress.md`.

## Preflight (uitgevoerd 2026-10-11)

| Controle | Uitkomst |
| --- | --- |
| `git fetch --all` | `feat/pleya-web-s7-shell` staat gelijk met `github/feat/pleya-web-s7-shell` op `88c5075b`. `github/main` (`faab73ab`) zit volledig in de branch. |
| `gh pr list` | Drie open PR's: #257 (assistant), #218 (docs unified-first), #130 (dependency-baan). Geen raakt `pleya_web`. |
| `git worktree list` | `pleya-web-s7` is de enige worktree op deze branch. `pleya-web-csp` draagt `ad9b5cae`; dezelfde wijziging staat als `5ed41f0c` (#219) op `main` en dus in deze branch (`'unsafe-hashes'` in `pleya_web/svelte.config.js`). De opmerking in de gate van commitgrens 4 dat de announcer-fix ontbreekt, is daarmee achterhaald. Geen andere worktree werkt aan de webclient. |
| Masterlijst | S7.6 staat op `[ ]` zonder bewijs; `scripts/masterlist_counts.sh --check` meldt "155 taken, 29 gereed, 4 bezig, 122 open". |
| Wat al gemigreerd is | De schil (`TopNav`, `MobileHeader`, `TabBar`), `Hero` en `HubRail` op Home, `SkeletonPage` op Home, raster en detail, `MediaGrid` op `MediaCard`, `LanguagePicker` en `ThemePicker` op `/server`, alle tekst via `t()`. |
| Wat nog op de oude opmaak draait | Zie de routetabel. Kort: `StateView` met de oude opmaak (`--text-muted`, `min-height: 40vh`, knop `btn--secondary`) op zes routes en in de layout, `t-headline` (24 px) als paginatitel, `.field` uit `base.css` op login, setup en zoeken, een eigen `.chip` op zoeken, een native `<select>` met eigen CSS op het raster, `.card-surface` met `--outline` op `/server`, eigen tegels op `--surface` op `/libraries`, en `--page-inset` (de oude naam uit `tokens.css`) op vijf routes. |
| Axe vandaag | `expectNoAxeViolations` in `tests/e2e/helpers.ts` gebruikt `@axe-core/playwright` 4.13.0 met de tags `wcag2a`, `wcag2aa`, `wcag21a`, `wcag21aa`, alleen op de standaardbreedte van het project, alleen in `en-US`. `WIDTHS` in de helpers is `[390, ...]`, niet 393. |

**Zeven of acht routes.** Deel I zegt "de bestaande zeven routes"; deel G telde ze op `5eebb83`. Op
die commit, en sinds `ad6f28d7`, zijn het er acht met een `+page.svelte`: `/`, `/libraries`,
`/libraries/[id]`, `/items/[id]`, `/search`, `/server`, `/login`, `/setup`. Dit plan migreert ze alle
acht. De bewijskolom van S7.6 noemt het verschil, zodat niemand een route mist omdat de titel zeven
zegt.

## Routetabel

"Primitieven" noemt wat de route na deze grens gebruikt. Een route zonder eigen northstar-beeld
volgt `.page` en `.page-title` uit `web.css` en de lege staat uit beeld 13.

| Route | Huidige staat (gecontroleerd in de code) | Doelstaat | Primitieven |
| --- | --- | --- | --- |
| `/` Home | `Hero` op `items[0]` plus één `HubRail` "Recent toegevoegd"; laden is `SkeletonPage home`; fout en leeg via oude `StateView` | beeld 01 met de data die er is (hero en één rij), afstanden uit `.section`; laden is beeld 15 in de schil; leeg en fout in de vorm van 13 | `Hero`, `HubRail`, `SkeletonPage`, `StateView` (nieuw) |
| `/libraries` | eigen `.tile` op `--surface`/`--outline`, `NavIcon`, titel `t-headline`, `--page-inset` | paginatitel uit `.page-title`, tegels op `--panel` met `--hairline` en `--r-card`, lege staat met uitweg | `PageHeader` (nieuw), `StateView` |
| `/libraries/[id]` | native `<select>` met eigen CSS, `MediaGrid`, `SkeletonPage grid`, oude `StateView`, knoppen "Load more" en "Retry" als `btn--secondary` | kop uit `.page-title` met aantal als `.sub` en sortering rechts, `Select` met verborgen label | `PageHeader`, `Select`, `MediaGrid`, `SkeletonPage`, `StateView` |
| `/items/[id]` | `Artwork`-poster, eigen `dl`, versieblok op `--surface`/`--outline`, `MediaGrid` voor kinderen, `StateView compact` | dezelfde inhoud, versie en sporen in een `Panel`, kinderen onder een `.section-h`-kop; geen herschikking naar 08 of 09 (dat is S8.5) | `Panel`, `MediaGrid`, `SkeletonPage`, `StateView` |
| `/search` | `.field` uit `base.css`, eigen `.chip`, aria-label van de filtergroep is `search.filters.all` ("Alles") | `Field type="search"` met verborgen label, `Chips` enkelvoudig, groepslabel met een eigen sleutel, lege staten met uitweg | `PageHeader`, `Field`, `Chips`, `MediaGrid`, `StateView` |
| `/server` (slot Mijn Pleya) | vijf `.card-surface`-secties, eigen `dl`, eigen statuspunten, "Taal" dubbel als `h2` en als verborgen label | elke sectie een `Panel`, sleutel-waarderijen in de vorm van `.kv`, capabilities als `StatusPill variant="dot"`, bibliotheken in een `DataTable` (gestapeld onder 900); geen indeling volgens 11 (S8.6) | `PageHeader`, `Panel`, `StatusPill`, `DataTable`, `ThemePicker`, `LanguagePicker` |
| `/login` | gecentreerde kolom van 400 met het merkteken, `.field`, eigen foutvak | beeld 12: twee panelen vanaf 900, beeldvlak boven op smal (260 hoog), wordmark, kop 28, ondertitel, fout onder het wachtwoordveld, primaire knop vol breed, hulptekst | `Field`, eigen layout in de route |
| `/setup` | gecentreerde kolom van 400, `.field`, eigen foutvak | het formulier van stap 1 uit 40 in een kolom van 620 (DESIGN.md hoofdstuk 3); de vier stappen zijn S11 | `Field`, `Alert` |
| layout, fase `unreachable` | oude `StateView kind="error"` buiten de schil, knop "Retry" | beeld 14: binnen de schil, icoon, servernaam, uitleg, laatste contact, aftellen tot de volgende poging, knop "Nu opnieuw proberen" | `UnreachableState` (nieuw, op `StateView`) |
| layout, fase `starting` | `SkeletonPage compact` zonder schil | blijft zo (zie uitspraak in taak 4); beeld 15 is de laadstaat van Home in de schil | `SkeletonPage` |

## Afhandeling van de open minors

| Punt | Herkomst | In deze grens |
| --- | --- | --- |
| M-5, 3 px overloop op 1024 in de galerij, `DataTable` | cg4 | **Oplossen in taak 7**: `/server` krijgt een `DataTable`, dus de oorzaak gaat een echte route raken. |
| M-6, Home kiest een aflevering als hero | cg4 | **Buiten scope, naar S8.1.** Heroselectie is routelogica van de nieuwe Home. |
| M-7, ring van de railpijl in light tegen een donkere poster 1,66:1 | cg4 | **Oplossen in taak 3**: een gap in `--bg` zoals bij de kaartfocus. |
| M-8, ArchivoBlack laadt op elke route | cg4 | **Open vraag 5.** Standaard blijft de preload staan. |
| M-2, metaregel op helder artwork | cg4 | Buiten scope; meten zodra er echte backdrops in de testset zitten. |
| M-3, FOUT van de herotitel | cg4 | Geaccepteerd (CLS 0); geen werk. |
| Synopsis 3,79:1 op egaal zwart artwork | cg4, gatepunt PS-7N | Buiten scope. Geen route geeft `summary`; blijft gatepunt voor PS-7N met de geometrische oplossing uit de S7.4-rij. |
| Filtergroep op zoeken heet "Alles" | cg5 | **Oplossen in taak 6** met een eigen sleutel. |
| "ongeveer 1 titel" op het raster | cg5 | **Oplossen in taak 6**: de schatting alleen tonen als hij groter is dan het aantal geladen items. |
| "Eigenaar aanmaken" krap op 361 px | cg5 | **Controleren in taak 5** op de echte setuproute. |
| Dubbel "Taal" (label en kop) | cg5 | **Oplossen in taak 7**: de kop is de naam, het verborgen label verwijst ernaar met `aria-labelledby`, zelfde vorm voor thema. |
| Login en setup op de oude `.field` | S7.3 | **Oplossen in taak 5.** |
| `SkeletonPage` volgt de oude raster- en detailkop | S7.3 | **Oplossen in taak 6 en 7** zodra die koppen veranderen. |
| Thema-flits vóór hydratie | S7.3 | Buiten scope; dezelfde CSP-grens als `lang` in de eerste HTML (cg5 taak 1). |

## Global Constraints

- Geen vermelding van AI, model of leverancier in code, comments, commits of documenten; geen
  `Co-Authored-By` of sessieregel. Auteur is Michel Knoop.
- Commits met `SKIP_HOOKS=1`. Alleen `pleya_web/` en `docs/` worden aangeraakt. Geen Dart, geen Go,
  geen `docs/pleya-protocol/`. Het protocol is bevroren: wat `GET /info` vóór het inloggen niet
  draagt (servernaam, aantallen), staat niet op het inlogscherm.
- Geen inline `style=`-attributen en geen inline script (CSP `style-src 'self'`, `script-src 'self'`).
  `style:`-directives op componenten zijn toegestaan waar ze al gebruikt worden (`Choice`).
- Elke zichtbare tekst, ook aria-labels en documenttitels, via `t()` of `plural()`. Nieuwe sleutels
  tegelijk in `web.ts` en `web.nl.ts`; `parity.test.ts` en `literals.test.ts` blijven groen.
  Nederlandse termen uit de northstar (12, 13, 14, 40).
- Kleuren alleen uit `tokens.css`. Nieuwe CSS gebruikt de v2-namen (`--panel`, `--hairline`,
  `--ink-*`, `--fill*`, `--inset`); `--page-inset`, `--surface`, `--outline` en `--text-muted`
  komen in geen enkel gewijzigd bestand terug.
- Svelte 5 runes. Raadpleeg Context7 (of MDN via Context7) voor elke API die nog niet in de codebase
  staat, met bronvermelding in het taakrapport. In dit plan in elk geval `Intl.RelativeTimeFormat`
  (laatste contact), de `locale`-optie van Playwright via `test.use`, en de `withTags`/`include`/
  `exclude`-API van `@axe-core/playwright` 4.13. Voor de tagnamen is al nagekeken in de axe-core
  API-documentatie (Context7 `/dequelabs/axe-core`, `doc/API.md`): `wcag22aa` en `best-practice` zijn
  geldige tags naast `wcag2a`, `wcag2aa`, `wcag21a` en `wcag21aa`.
- Bestanden onder 400 regels, één verantwoordelijkheid per bestand. `items/[id]/+page.svelte` (297)
  krijgt een versiepaneel: komt hij boven 350, dan gaat dat paneel naar
  `src/lib/components/VersionPanel.svelte`. `primitives-shots.ts` (391) krijgt niets meer; de
  vergelijkfunctie gaat eruit naar een gedeeld bestand (taak 8).
- Commentaar in het Nederlands, het waarom, in de stijl van de omliggende bestanden.
- Bewijs per taak: `bun run check`, `bun run test`, `bun run build`; bij zichtbare taken ook
  `bun run test:e2e` op een verse stack (`eval "$(scripts/e2e-stack.sh up)"`) en de screenshotpaden.
  Rapporten en briefs in `.superpowers/sdd/2026-10-11-pleya-web-s7-commitgrens6/`.
- Elke test die een fout moet vangen krijgt een negatieve controle: breek het gedrag tijdelijk, laat
  de rode uitvoer zien in het rapport, zet het terug.
- Een route verliest geen functie: wat de route vóór deze grens kon (sorteren met URL-parameter,
  doorbladeren met waarnemer en knop, filter op soort, debounce en annulering bij zoeken, kinderen
  van serie en seizoen, uitloggen, thema- en taalkeuze, de foutcodes bij inloggen en setup) staat na
  afloop in een e2e-test of een componenttest.
- Geen `git push`, geen merge. `docs/PLEYA-SERVER-MASTERLIST.md` alleen in taak 10.
- Taken strikt na elkaar, nooit parallel; elke taak eindigt met een eigen commit.

## Niveauverdeling

Het zware werk zit in de staten die nu nog niet bestaan (onbereikbaar met aftellen, het
inlogscherm in twee panelen), in de axe-spec die de hele matrix moet dragen, en in het oordeel
naast de northstar. Het omzetten van de bladerroutes en de detail- en serverpagina is
vervangwerk met vaste doelen.

| Taak | Onderwerp | Niveau |
| --- | --- | --- |
| 1 | Axe-matrix als e2e-spec, vijf breedtes, twee talen | visueel/protocol |
| 2 | Gedeelde paginabouw: `PageHeader`, `StateView` naar de northstar | visueel/protocol |
| 3 | Home en laadstaat (beeld 01 en 15), M-7 | visueel/protocol |
| 4 | Server onbereikbaar (beeld 14) met aftellen | visueel/protocol |
| 5 | Inloggen en setup (beeld 12, `Field`) | visueel/protocol |
| 6 | Bladeren: `/libraries`, `/libraries/[id]`, `/search` | mechanisch |
| 7 | Detail en Mijn Pleya: `/items/[id]`, `/server`, M-5, opruimen | mechanisch |
| 8 | Opnamen naast de northstar in `docs/qa/s7-routes/` | visueel/protocol |
| 9 | Visuele gate, verse reviewer | visueel/protocol |
| 10 | Bookkeeping | mechanisch |

## Task 1: Axe-matrix als e2e-spec

Eerst de meetlat, dan de migratie: elke volgende taak draait deze spec en levert hem groen op voor
de routes die hij raakte. De nulmeting in deze taak mag rood zijn; het rapport legt per route,
breedte en taal vast wat er rood is, zodat later zichtbaar is wat een migratie oploste en wat ze
brak.

**Aanpak.** Wat in de repo staat blijft de basis: `@axe-core/playwright` 4.13.0 met `AxeBuilder`,
tegen de echte stack van `scripts/e2e-stack.sh`. Geen tweede axe-integratie.

**Helpers** (`tests/e2e/helpers.ts`):
- `WIDTHS` wordt `[393, 768, 1024, 1280, 1600]`, de breedtes van de northstar. De responsieve test
  in `flow.spec.ts` gebruikt dezelfde constante en loopt daarmee mee.
- `expectNoAxeViolations` krijgt de tags van de eerdere gates: `wcag2a`, `wcag2aa`, `wcag21a`,
  `wcag21aa`, `wcag22aa`, `best-practice`. Dat verscherpt de bestaande zes aanroepen ook; wat daar
  rood wordt is werk voor deze grens. De foutmelding noemt route, breedte en taal.
- `signIn(page, locale?)` en `expectShell(page, locale?)` zoeken op labels uit de catalogus (`t()`
  na `setLocale`), zoals `scripts/screenshots.ts` al doet, in plaats van op vaste Engelse tekst.
  Zonder argument blijft alles Engels, zodat de bestaande specs niet veranderen.
- `openLibraryOfKind` leest nu `.rows__row` en `.t-body` op `/server`. Die klassen verdwijnen in
  taak 7; de helper gaat over op een rol- of `data-`-selector die taak 7 behoudt
  (`data-library-kind` op de bibliotheekrij), en dat staat in deze taak al klaar.

**Nieuwe spec** `tests/e2e/a11y-routes.spec.ts`, alleen in het project `chromium` (de breedtes
worden per meting gezet; het project `mobile` slaat hem over met `test.skip` en een reden):
- Per taal een `test.describe` met `test.use({ locale: 'en-US' })` of `'nl-NL'`, een init-script dat
  `pleya.locale` wist (zelfde vorm als `forgetStoredLocale` in `scripts/shot-locale.ts`) en het thema
  op `dark` zet.
- Eén ingelogde test per taal, met `expect.soft` zodat één run de hele matrix rapporteert en er
  geen dertig keer ingelogd wordt. Doelen, tijdens de run opgezocht en niet uit de testdata
  geraden: `/`, `/libraries`, een films- en een seriebibliotheek, een film, een serie, een seizoen,
  `/search` leeg, `/search?q=` met treffers, `/search?q=` zonder treffers, `/server`.
- Per doel één `goto`, daarna per breedte `setViewportSize`, wachten tot er geen `[aria-busy=true]`
  meer staat, en dan drie metingen: axe nul overtredingen, horizontale paginaoverloop ≤ 1 px, en
  `document.documentElement.lang` gelijk aan de taal.
- Losse tests zonder sessie per taal: `/login` op vijf breedtes, en `/setup` op vijf breedtes zolang
  `GET /info` `setup_required` zegt. Op een stack met eigenaar slaat de setuptest over met een reden;
  de gate draait daarom op een verse stack, en de spec staat alfabetisch vóór `auth.spec.ts`, zodat
  hij `/setup` ziet voordat er een eigenaar is.
- Staten: Home laden (`page.route` op de hub-aanvraag die pas antwoordt nadat de meting klaar is) en
  vanaf taak 4 de onbereikbare server (`page.route` die `/pleya/v1/info` laat mislukken). De
  onbereikbaar-meting staat in deze taak als `test.fixme` met een verwijzing naar taak 4.
- `incomplete`-resultaten van `color-contrast` over artwork falen niet. De spec schrijft ze naar
  `test.info().annotations`, en de gate meet die plekken met pixels.

Tijdslimiet per test ruim (`test.setTimeout(300_000)`); de stack staat lokaal.

Bestanden: `tests/e2e/helpers.ts`, `tests/e2e/a11y-routes.spec.ts` (nieuw), `tests/e2e/flow.spec.ts`
(alleen als de nieuwe `WIDTHS` iets breekt).

Negatieve controle: haal tijdelijk de `aria-label` van de navigatie in `TabBar.svelte` weg en laat de
spec op 393 en 768 rood zien in beide talen; zet de taal van een Nederlandse run op `en-US` terug en
laat de `lang`-meting rood zien.

Acceptatie: drie commando's groen; `bun run test:e2e` draait de nieuwe spec; het rapport bevat de
nulmeting als tabel (doel × breedte × taal, aantal overtredingen per regel-id).

Commit: `test(pleya-web): axe op elke route op vijf breedtes en in twee talen (S7.6)`.

## Task 2: Gedeelde paginabouw

Twee bouwstenen die elke volgende taak gebruikt.

**`PageHeader.svelte`** (nieuw): de `.page-title` uit `web.css`. Een `h1` met optioneel een `sub`
(aantal, in `--ink-3`) en een `actions`-snippet rechts; onder 900 valt de actie onder de titel. De
maat volgt `--text-page-title-size` uit designsysteem v2 boven 900 en 26 px eronder, gewicht 700 (de
bundel heeft geen 800, zie het specimen). Marges 12 boven en 18 onder, 6 en 12 op smal.

**`StateView.svelte`** naar `.state` uit de northstar: gecentreerd, maximaal 460 breed, padding 64 en
24, icoon 44 in `--ink-3`, titel 20/700 in `--ink`, tekst 14 met regelhoogte 1,45 in `--ink-2`, een
`actions`-snippet als `.btn-row` met 18 erboven. De `onRetry`-knop blijft bestaan als snelkoppeling
en wordt een primaire kleine capsule. Er komt een `icon`-snippet bij, zodat 13 en 14 hun eigen
pictogram krijgen (de huidige twee paden blijven de standaard). De rol `alert` bij een fout blijft.
`compact` blijft voor binnen een sectie. Een paginatitel is geen onderdeel van de staat: de route
zet `PageHeader` erboven, zoals in 13.

Bestanden: `src/lib/components/PageHeader.svelte` en `PageHeader.test.ts` (nieuw),
`StateView.svelte`, `StateView.test.ts`, de galerij `routes/dev/primitives/` (één sectie voor beide,
zodat de gate ze los kan zien), `src/lib/i18n/web.ts` en `web.nl.ts` alleen als er een sleutel
bijkomt.

Tests: `PageHeader` rendert één `h1`, `sub` en acties alleen als ze gegeven zijn; `StateView` toont
acties, gebruikt het meegegeven icoon, houdt `role="alert"` alleen bij `kind="error"`. Negatieve
controle: zet de rol op elke staat en laat de test op de lege staat rood zien.

Acceptatie: drie commando's groen; galerijopname van beide op 393 en 1600 naast `13-lege-bibliotheek`
in het rapport.

Commit: `feat(pleya-web): paginakop en lege staat naar de northstar (S7.6)`.

## Task 3: Home en laadstaat (beeld 01 en 15), M-7

Home verandert inhoudelijk niet: hero op het eerste item, één rij "Recent toegevoegd". Wat wel
verandert:
- de ruimte tussen hero en rij volgt `.section` (26, op smal 18) in plaats van `--space-2`;
- fout en leeg gebruiken de nieuwe `StateView`, leeg met een uitweg naar Mijn Pleya (de bibliotheken
  staan daar), fout met opnieuw proberen;
- `SkeletonPage variant="home"` wordt naast beeld 15 gelegd en waar nodig bijgesteld: skelethero in
  de hero-geometrie (21:9, 16:9, 520 portret), kop van de rij 220 en 160 breed, kaarten op
  `--poster-w`. Het skelet en de echte Home moeten op elke breedte dezelfde bovenkant van de eerste
  rij hebben; meet dat met `getBoundingClientRect` vóór en na het binnenkomen van de data.

**M-7.** De ring van de railpijl krijgt een gap in `--bg`, dezelfde vorm als de kaartfocus, zodat
hij in light ook boven een donkere poster 3:1 haalt. Meten in light, dark en OLED met de pixelmeting
uit de gate van commitgrens 4; uitvoer in het rapport.

Bestanden: `src/routes/+page.svelte`, `src/lib/components/SkeletonPage.svelte`,
`src/lib/components/HubRail.svelte` (alleen de pijlfocus), eventueel `Skeleton.svelte`.

Tests: bestaande `HubRail`- en `SkeletonPage`-tests blijven groen; een nieuwe e2e-meting in
`flow.spec.ts` dat de eerste rij op 393 en 1280 niet meer dan 2 px verspringt tussen skelet en data
(skelet vasthouden met `page.route`). Negatieve controle: zet de ruimte boven de skeletrij tijdelijk
op 0 en laat de meting rood zien.

Acceptatie: drie commando's en `bun run test:e2e` groen; de axe-spec groen op Home en de Home-
laadstaat in beide talen op vijf breedtes; opnamen van Home en van de laadstaat op 393 en 1600 naast
01 en 15 in het rapport.

Commit: `feat(pleya-web): Home en laadstaat op de maten van beeld 01 en 15, focusring railpijl (S7.6)`.

## Task 4: Server onbereikbaar (beeld 14)

Vandaag tekent de layout bij een mislukte `GET /info` een kale foutstaat buiten de schil, met de
Engelse foutcode als tekst. Beeld 14 tekent hem in de schil, met de servernaam, een uitleg dat de
sessie blijft, het laatste contact, een aftelling tot de volgende poging en een knop om het nu te
proberen.

**Laatste contact.** De sessie bewaart na elke geslaagde `load()` een klein record in
`localStorage` onder `pleya.lastContact`: servernaam, tijdstip, en de bibliotheekverwijzingen
(`id`, `kind`) met de `browse`-capability die `navItems` nodig heeft. Opslag via dezelfde
try/catch-vorm als `theme.svelte.ts`; geweigerde opslag betekent: geen record. Het record is een
gemak voor deze kijker en geen bron van waarheid; het wordt overschreven zodra de server weer
antwoordt.

**`UnreachableState.svelte`** (nieuw, op `StateView`):
- titel "{naam} is niet bereikbaar" met de naam uit het record, anders de host uit `location.host`;
- uitleg met de host in `--font-mono`; de zin "Je bent nog ingelogd" alleen als de tokenopslag van
  de client een refreshtoken heeft (de uitvoerder controleert welke methode `PleyaClient` daarvoor
  biedt en voegt er alleen een leesmethode bij als die ontbreekt);
- "Laatste contact {relatief}" met `Intl.RelativeTimeFormat` in de actieve taal (Context7/MDN), alleen
  als er een record is;
- aftellen "opnieuw proberen over {n} s"; de reeks is 2, 4, 8, 16 en daarna elke 30 s (open vraag 3).
  Het getal staat in een element zonder live-regio, zodat een schermlezer niet elke seconde praat;
  alleen de overgang naar "Verbinding maken…" wordt aangekondigd;
- knop "Nu opnieuw proberen" (primair, klein, met het verversicoon) die de timer stopt en
  `session.start()` aanroept. De tweede knop uit 14 komt er niet (open vraag 4).

**Layout.** De fase `unreachable` rendert de schil (`TopNav` of `MobileHeader` en `TabBar`) met de
items uit het record, en `UnreachableState` als inhoud. Zonder record staan alleen het merk en Mijn
Pleya in de schil. Een navigatieklik verandert de URL; de layout blijft de staat tonen tot de server
antwoordt, en dan landt de gebruiker op die route.

**Uitspraak `starting`.** Tijdens `starting` is nog onbekend of de gebruiker op inloggen of setup
uitkomt. Een schil tonen en die dan weghalen is een sprong die erger is dan de huidige compacte
laadstaat. `starting` blijft daarom zonder schil; beeld 15 wordt vergeleken met de laadstaat van
Home in de schil. Kosten als fout: één tak in de layout.

Bestanden: `src/lib/stores/session.svelte.ts` (record schrijven en lezen),
`src/lib/components/UnreachableState.svelte` en `UnreachableState.test.ts` (nieuw),
`src/lib/util/format.ts` of `formatLocale.ts` (`formatRelative`), `src/routes/+layout.svelte`,
`src/lib/i18n/web.ts`, `web.nl.ts`, het icoon "cloudoff" in `NavIcon.svelte` of als eigen pad in de
staat, `tests/e2e/a11y-routes.spec.ts` (de `fixme` wordt een echte meting).

Tests:
- met nep-timers: na 2 s een tweede poging, daarna 4, 8, 16, 30, 30; de knop reset de reeks; bij
  ontkoppelen staat er geen timer meer;
- titel met naam uit het record, en met de host zonder record; "Laatste contact" ontbreekt zonder
  record; de ingelogd-zin alleen met refreshtoken;
- `session.load()` schrijft het record; `localStorage` die gooit breekt `load()` niet;
- e2e: `/pleya/v1/info` laten mislukken toont de staat in de schil met de juiste taal; daarna de
  route weer vrijgeven en op "Nu opnieuw proberen" drukken brengt de gebruiker in de app.
Negatieve controle: laat de knop de timer niet stoppen en laat de reset-test rood zien.

Acceptatie: drie commando's en `bun run test:e2e` groen; axe groen op de staat in beide talen op vijf
breedtes; opnamen op 393 en 1600 naast 14 in het rapport.

Commit: `feat(pleya-web): onbereikbare server in de schil met aftellen en laatste contact (S7.6)`.

## Task 5: Inloggen en setup (beeld 12, `Field`)

**Inloggen** volgt 12. Vanaf 900 twee kolommen van gelijke breedte: links het beeldvlak met scrim en
onderschrift, rechts een kolom van maximaal 380 met de wordmark (36 hoog), kop 28/700, ondertitel 14
in `--ink-2`, de velden als `Field`, de primaire knop vol breed met 22 erboven en de hulptekst over
een vergeten wachtwoord. Onder 900 staat het beeldvlak bovenaan op 260 hoog en de kolom eronder met
16 inzet. De fout staat onder het wachtwoordveld via de `error`-prop van `Field`
(`aria-invalid` en `aria-describedby` op het veld), niet meer in een los vak; de rate-limit-tekst
blijft uit `retry_after_ms` komen.

Het beeldvlak kan geen serverartwork tonen: artwork komt met een Authorization-header binnen en vóór
het inloggen is er geen token. Het onderschrift kan geen servernaam of aantallen tonen: `GET /info`
draagt ze niet en het contract is dicht. Standaard in dit plan (open vraag 1): het vlak op `--panel`
met de haarlijn en het grote merkteken, het onderschrift met alleen de host. De afwijking gaat in de
README van de opnamemap.

**Setup** krijgt dezelfde velden als `Field` en een fout als `Alert tone="err"`, in een kolom van 620
gecentreerd (DESIGN.md hoofdstuk 3, "Setup"). De stappen en het opslag- en bibliotheekwerk zijn S11;
de route blijft één formulier. Controleer "Eigenaar aanmaken" op 361 en 393 in het Nederlands.

Nieuwe sleutels: `login.subtitle`, `login.forgotHelp`, en waar nodig `login.invalid` voor de fout
onder het veld (de bestaande foutcode-tekst blijft de bron). Termen uit 12 en 40.

Bestanden: `src/routes/login/+page.svelte`, `src/routes/setup/+page.svelte`, `src/lib/i18n/web.ts`,
`web.nl.ts`, `tests/e2e/auth.spec.ts` alleen als een selector verandert.

Tests: `auth.spec.ts` blijft groen (setup of inloggen, verkeerd wachtwoord met vertaalde foutcode,
sessie over een herlaad). Nieuw in `auth.spec.ts`: na een verkeerd wachtwoord heeft het
wachtwoordveld `aria-invalid="true"` en verwijst `aria-describedby` naar de fouttekst. Negatieve
controle: haal `error` van het veld en laat die test rood zien.

Acceptatie: drie commando's en `bun run test:e2e` groen; axe groen op `/login` (ook in de foutstaat)
en `/setup` in beide talen op vijf breedtes; opnamen van 12 in de foutstaat op 393 en 1600 naast de
northstar in het rapport; `grep -n 'class="field"' src/routes` levert niets meer.

Commit: `feat(pleya-web): inloggen naar beeld 12 en setup op Field (S7.6)`.

## Task 6: Bladeren: `/libraries`, `/libraries/[id]`, `/search`

Vervangwerk met vaste doelen uit de routetabel.

- `/libraries`: `PageHeader`, tegels op `--panel` met `--hairline`, `--r-card` en hover achter
  `@media (hover: hover)`; lege staat met de nieuwe `StateView`.
- `/libraries/[id]`: `PageHeader` met de titel, het aantal als `sub` en `Select` (verborgen label)
  als actie. Het aantal staat er alleen als de schatting groter is dan het aantal geladen items, en
  anders het werkelijke aantal; "ongeveer 1 titel" verdwijnt. Sorteren, URL-parameter, waarnemer en
  de knoppen blijven zoals ze zijn. `SkeletonPage variant="grid"` krijgt dezelfde kophoogte als de
  nieuwe kop.
- `/search`: `PageHeader`, `Field type="search"` met verborgen label en dezelfde debounce,
  `Chips` enkelvoudig met een eigen groepslabel (`search.filters.label`, "Soort" en "Type"), lege
  staten met de nieuwe `StateView`; de opmerking over seizoenen blijft. De eigen `.chip`-CSS gaat weg.

Bestanden: de drie `+page.svelte`, `SkeletonPage.svelte`, `web.ts`, `web.nl.ts`.

Tests: `flow.spec.ts` (bibliotheeklijst naar raster, sorteren, zoeken zonder seizoenen) blijft groen;
nieuw: de filtergroep op zoeken heeft de naam uit `search.filters.label` en een filterklik zet
`aria-pressed` of `aria-checked` zoals `Chips` dat doet. Negatieve controle: zet het oude label terug
en laat die test rood zien.

Acceptatie: drie commando's en `bun run test:e2e` groen; axe groen op de drie routes en hun lege
staten in beide talen op vijf breedtes; `grep -n "page-inset\|text-muted\|--surface\|--outline"` in
de drie bestanden levert niets.

Commit: `feat(pleya-web): bibliotheken, raster en zoeken op de primitieven (S7.6)`.

## Task 7: Detail en Mijn Pleya, M-5, opruimen

- `/items/[id]`: zelfde inhoud en volgorde. Versie, video, audio en ondertitels in een `Panel`;
  kinderen onder een kop in de vorm van `.section-h`; de lege kinderstaat wordt `StateView compact`.
  `SkeletonPage variant="detail"` volgt de kop. Komt het bestand boven 350 regels, dan gaat het
  versiepaneel naar `VersionPanel.svelte`.
- `/server`: `PageHeader` met "Mijn Pleya" als slotnaam (open vraag 6), elke sectie een `Panel`,
  server en protocol als sleutel-waarderijen, capabilities als `StatusPill variant="dot"` met
  "beschikbaar" en "niet beschikbaar", bibliotheken in een `DataTable` (titel, soort, aantal) die
  onder 900 stapelt, elke rij met `data-library-kind` voor de helper uit taak 1. Thema en taal
  krijgen hun kop als naam (`aria-labelledby`) in plaats van een tweede verborgen label. Uitloggen
  blijft een stille knop onderaan.
- **M-5.** Zoek in de galerij op 1024 welk element 3 px buiten het venster steekt, los het in
  `DataTable` op, en meet daarna 0 px in de galerij en op `/server` op alle vijf breedtes.
- **Opruimen.** `--page-inset` gaat uit `tokens.css`; `.card-surface` en `.field` gaan uit `base.css`
  als `grep` geen gebruiker meer vindt buiten de galerij (die wordt meegenomen). De
  basistokens `--surface`, `--outline` en `--text-muted` blijven bestaan, want `Artwork`, `Hero` en
  `TabBar` lezen ze nog; dat is geen routemigratie.

Bestanden: `src/routes/items/[id]/+page.svelte`, `src/routes/server/+page.svelte`,
`src/lib/components/DataTable.svelte`, `SkeletonPage.svelte`, `ThemePicker.svelte` en
`LanguagePicker.svelte` (alleen de labelkoppeling), `src/styles/tokens.css`, `src/styles/base.css`,
`web.ts`, `web.nl.ts`, eventueel `VersionPanel.svelte`.

Tests: `flow.spec.ts` (detail toont alleen wat `Item` draagt, serie via seizoen naar aflevering,
serveroverzicht) blijft groen, net als de picker-tests; nieuw: de capabilitylijst op `/server` toont
per capability een status met tekst, niet alleen een kleur. Negatieve controle: verwijder de tekst
uit de pil en laat de test rood zien.

Acceptatie: drie commando's en `bun run test:e2e` groen; de hele axe-spec groen; `grep -rn
"page-inset\|card-surface" src` levert niets; overloop 0 px op `/server` en in de galerij op 1024.

Commit: `feat(pleya-web): detail en Mijn Pleya op panelen, tabel zonder overloop (S7.6)`.

## Task 8: Opnamen naast de northstar

**Script.** De functie `compare` uit `scripts/primitives-shots.ts` gaat naar
`scripts/shot-compare.ts`; `primitives-shots.ts` importeert hem en levert byte-gelijke uitvoer
(controle: één galerijvergelijking vóór en na, `cmp` in het rapport). Nieuw
`scripts/routes-shots.ts` met `--locale nl|en`, op de bestaande `shot-locale.ts`, tegen de e2e-stack:
- elke route uit de routetabel op 393, 1024 en 1600, in beide talen, dark;
- de staten 12 (foutstaat), 14 en 15 op alle vijf breedtes in het Nederlands (de northstar is
  Nederlands) en op 393 en 1600 in het Engels; 14 met een mislukte `/info`, 15 met een vastgehouden
  hub-aanvraag;
- vergelijkingsbeelden `*-vs-northstar@{w}.png`: Home naast 01 op 393, 1024, 1280 en 1600; 12, 14 en
  15 op 393 en 1600 (de breedtes waarop de northstar ze heeft).

**Map** `docs/qa/s7-routes/` met `README.md`: per opname wat hij bewijst, welke breedte bij welk
northstar-beeld hoort (768 bij 393, 1024 en 1280 bij 1600 voor de beelden die alleen 393 en 1600
hebben, volgens het layoutcontract), en de bewuste afwijkingen: het beeldvlak van 12, de ontbrekende
tweede knop van 14, de laadstaat `starting` zonder schil, één rij op Home tot S8.1, het heroitem
(M-6, S8.1), titels en artwork uit de e2e-testdata.

Bestanden: `scripts/shot-compare.ts`, `scripts/routes-shots.ts` (nieuw),
`scripts/primitives-shots.ts`, `docs/qa/s7-routes/`.

Acceptatie: drie commando's groen; alle opnamen bestaan en de README noemt ze; het script meldt op
elke route en staat, elke breedte en beide talen 0 px overloop.

Commit: `docs(pleya-web): routes en staten naast de northstar (S7.6)`.

## Task 9: Visuele gate

Verse reviewer die niets in deze grens bouwde. Geen code in deze taak. Controleert:
- 01, 12, 14 en 15 naast de northstar: geen afwijking in compositie of maat buiten de afwijkingen die
  de README benoemt. Maat betekent gemeten, niet geschat: hero-hoogte, inzet, posterbreedte,
  kop-tot-rij, kolombreedtes van 12, positie en maat van de staat in 14 (`getBoundingClientRect`,
  uitvoer in het gaterapport);
- de reviewlijst uit DESIGN.md hoofdstuk 6 (acht punten) op elke gemigreerde route;
- de axe-spec zelf gedraaid op een verse stack: groen, niets overgeslagen behalve wat de spec met
  reden overslaat in het project `mobile`; de `incomplete`-plekken van `color-contrast` met een
  pixelmeting op 393 en 1280;
- toetsenbord: elke route met Tab doorlopen op 393 en 1280, zichtbare ring op elk bediend element,
  ook de railpijl in light (M-7);
- functiebehoud: de lijst uit de Global Constraints, punt voor punt met de test die het bewijst;
- terminologie: twintig termen uit 12, 13, 14 en 40 naast het Nederlandse beeld;
- de onbereikbare staat: aftellen loopt, de knop werkt, de schermlezer krijgt geen aankondiging per
  seconde (accessibility-snapshot of axe-boom).

Verdict PASS of CHANGES met Critical, Important en Minor in `task-9-gate.md` in het ledger. Bij
CHANGES gaat de bevinding terug naar de taak die hem veroorzaakte, daarna een nieuwe gate.

## Task 10: Bookkeeping

Alleen na PASS in taak 9.

- `docs/PLEYA-SERVER-MASTERLIST.md`:
  - S7.6 naar `[x]` met bewijs (commits, aantallen vitest en e2e, `svelte-check`-uitvoer, de
    axe-matrix met aantal metingen, `docs/qa/s7-routes/`, het gateverdict) en datum. In de bewijskolom
    het verschil zeven tegen acht routes, de bewuste afwijkingen uit de README, en de minors die naar
    een andere slice gaan (M-6 naar S8.1, M-2 en de synopsis naar PS-7N, M-8 volgens open vraag 5).
  - S7.1 naar `[x]`: het enige open punt was de visuele controle op vijf breedtes, en die levert
    deze grens (opnamen en overloopmeting). Bewijs verwijst naar `docs/qa/s7-routes/`.
  - S7.2 volgens open vraag 2. Zonder besluit blijft hij `[~]`, met de staten 12, 14 en 15 uit zijn
    open-lijst gestreept en naar S7.6 verwezen.
  - Tellingen. Draai `scripts/masterlist_counts.sh --check` vóór de wijziging (verwacht "155 taken,
    29 gereed, 4 bezig, 122 open"; staat er iets anders, opnieuw tellen) en erna. Met S7.1, S7.2 en
    S7.6 op `[x]`: "155 taken, 32 gereed, 2 bezig, 121 open", in de bloktabel Web "1 gereed, 0 bezig,
    6 open", totaal "4 gereed, 0 bezig, 22 open", golf 4 van 29 naar 26 taken, en de zin "S7 is
    bezig" wordt "S7 is gereed". Blijft S7.2 op `[~]`: "155 taken, 31 gereed, 3 bezig, 121 open", S7
    blijft bezig in de bloktabel, golf 4 naar 27. Het script moet de telling in de tekst bevestigen.
  - Regel "Laatst bijgewerkt" bijwerken.
- `pleya_web/README.md`: sectie "Routes en staten" (welke primitieven elke route gebruikt, het record
  `pleya.lastContact` en waarom het geen bron van waarheid is, de axe-spec en hoe hij op een verse
  stack draait, `scripts/routes-shots.ts`).
- In het ledger van commitgrens 4: M-5 en M-7 krijgen een verwijzing naar de commit die ze sloot, M-6
  een verwijzing naar S8.1. In het ledger van commitgrens 5: de filtergroep, "ongeveer 1 titel" en
  het dubbele "Taal" idem.
- Taakteller van dit plan in `progress.md` op 10 van 10.

Commit: `docs(pleya-server): S7.6 gereed met bewijs`.

## Open vragen voor Michel

1. **Het beeldvlak van het inlogscherm (12).** Vóór het inloggen is er geen token, dus geen
   serverartwork, en `GET /info` draagt geen servernaam of aantallen. Keuze: (a) vlak op `--panel`
   met het merkteken en alleen de host als onderschrift (standaard in dit plan); (b) een eigen
   meegeleverd beeld zonder TMDb-materiaal, dat jij aanlevert; (c) één kolom zonder beeldvlak. (a) en
   (c) wijken in compositie van 12 af, (b) alleen in inhoud.
2. **S7.2 en het sluiten van S7.** Na deze grens staan bij S7.2 nog de Beheer-pil (wacht op `/admin`)
   en de avatar (geen bron in het contract) open. S7 sluit volgens de legenda pas als S7.2 op `[x]`
   staat. Voorstel: S7.2 naar `[x]` met de Beheer-pil als expliciet onderdeel van S10.1 en de avatar
   bij S8.6 (Mijn Pleya), beide als regel in die slices erbij. Zonder akkoord blijft S7 bezig.
3. **Aftelreeks van de onbereikbare staat.** Voorstel 2, 4, 8, 16 en daarna elke 30 s, zonder
   bovengrens in aantal pogingen. Beeld 14 toont "over 12 s" en zegt niets over de reeks.
4. **De tweede knop in 14, "Wat kan er aan de hand zijn?".** Er is geen hulppagina om naar te
   verwijzen, en DESIGN.md eist bij elke knop een bestaande bestemming. Voorstel: weglaten en als
   afwijking noteren. Alternatief: een uitklapbare uitleg in de staat zelf, met tekst die jij levert.
5. **M-8, ArchivoBlack op elke route.** De preload staat in `app.html` omdat een preload vanuit een
   component pas na het laden van JavaScript start en dan M-3 terugbrengt. Voorstel: laten zoals het
   is (31 KB, één keer, lange cachetijd). Per route preloaden kan pas als de eerste HTML per route
   verschilt, en dat kan de statische bundel niet.
6. **Paginatitel van `/server`.** Het slot heet "Mijn Pleya", de route toont "Server". Voorstel:
   "Mijn Pleya" als titel nu al, met de serverinformatie als paneel eronder; de indeling volgens 11
   blijft S8.6. Alternatief: "Server" laten staan tot S8.6.
7. **Een onbereikbare server midden in een sessie.** Dit plan behandelt alleen het mislukken van
   `GET /info` bij het starten. Midden in een sessie toont een route bij een netwerkfout zijn eigen
   foutstaat, zoals nu. Voorstel: dat gedrag hoort bij S8 commitgrens 6 ("staten"). Wil je het hier,
   dan kost het een fasewissel in de sessie bij een `TransportError` en een extra taak.
