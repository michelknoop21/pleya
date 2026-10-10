# Pleya Web S7: primitieven (commitgrens 3)

Werkmap: `pleya_web/`. Bron van waarheid voor maat, kleur en gedrag: `docs/assets/pleya-web-northstar/DESIGN.md` (hoofdstuk 2, 3 en 5) en de beelden in dezelfde map. Bestaande componenten in `pleya_web/src/lib/components/` zijn de stijlreferentie (Svelte 5 runes, `t()` uit `../i18n`, tokens uit `src/styles/tokens.css`).

## Global Constraints

- Geen vermelding van AI, model of leverancier in code, comments, commits of documenten; geen `Co-Authored-By`. Auteur is Michel Knoop.
- Commits met `SKIP_HOOKS=1`. Alleen `pleya_web/` en `docs/` worden aangeraakt, geen Dart.
- Geen inline `style=`-attributen (CSP). Variatie via klassen en tokens; `style:`-directives van Svelte zijn toegestaan.
- Kleuren, maten en radii uit `tokens.css` (`--ink-*`, `--fill`, `--amber`, `--ok`, `--danger-ink`, `--radius-*`, `--inset`). Geen losse hexwaarden behalve waar de northstar er een noemt.
- Elke zichtbare tekst via `t()`; sleutels in `src/lib/i18n/web.ts`.
- Svelte 5 runes (`$props`, `$derived`, `$state`). Raadpleeg Context7 voor elke Svelte-, testing-library- of vitest-API die nog niet in de codebase staat, met bronvermelding in het rapport.
- Toegankelijkheid: toetsenbord, `aria-*`, zichtbare focus, 44 px raakvlak.
- Bestanden onder 400 regels; één verantwoordelijkheid per bestand.
- Commentaar in dezelfde stijl en taal als de omliggende bestanden (Nederlands, het waarom).
- Bewijs: toon testuitvoer, `bun run check`-uitvoer en bij visuele taken de screenshotpaden.
- Geen `git push`, geen merge, geen wijziging aan `docs/PLEYA-SERVER-MASTERLIST.md` buiten taak 7.

## Task 1: Formulierprimitieven
`Field` (label, hulptekst, fout, `aria-describedby`), `Select`, `Toggle` (`role="switch"`), `Choice` (radiogroep als kaarten). Nieuw in `pleya_web/src/lib/components/`: `Field.svelte`, `Select.svelte`, `Toggle.svelte`, `Choice.svelte` plus een vitest per component. Commit.

## Task 2: Weergaveprimitieven
`Panel` (titel en actieslot), `StatTile`, `StatusPill` (ok, warn, err, run, idle met stip), `Alert` (warn, err, info, actieslot), `Chips` (aria-pressed, quiet en outline). Vijf componenten, vijf tests. Alert, StatusPill en Chips delen de toonkleuren (`--amber`, `--ok`, `--danger-ink`). Commit.

## Task 3: Structuurprimitieven
`DataTable` (kolommen, cel-snippet, `stack` onder 900, scroll in paneel; gebruikt `StatusPill` in cellen en `Panel` als omhulsel), `Steps` (`aria-current="step"`, done/on), `ConfirmDialog` (`role="dialog"`, `aria-modal`, Escape, focus naar eerste veld en terug, optionele `requirePhrase` via `Field`, sheet onder 900). Drie componenten, drie tests. Commit.

## Task 4: Skeleton
`Skeleton` (blok, regel, titel, kaart, hero) en `SkeletonPage` (hero plus twee rails met de maten van de echte kaarten), met tests. Vervang `StateView kind="loading"` op de zes plekken: `routes/+layout.svelte` (3x), `routes/+page.svelte`, `routes/libraries/[id]/+page.svelte`, `routes/items/[id]/+page.svelte`. `StateView` houdt `empty` en `error`; pas `StateView.test.ts` aan. Beeld 15 (skeleton) is het doel. Commit.

## Task 5: Galerij en screenshots
Dev-only route `src/routes/dev/primitives/+page.svelte` die elke primitief in elke staat toont en met `dev` uit `$app/environment` een 404 geeft buiten ontwikkeling (productiebuild bevat geen bereikbare pagina). Screenshots op 393, 1024 en 1600 in `docs/qa/s7-primitives/`; skeleton op vijf breedtes. Commit.

## Task 6: Visuele gate
Verse reviewer, bouwde niets. Vergelijkt de screenshots met de northstar (15, 16, 20 t/m 35). Verslag in het ledger, geen code.

## Task 7: Bookkeeping
Masterlijst S7.3 met bewijs, `pleya_web/README.md` sectie designsysteem, i18n-sleutels (`common.confirm`, `common.dismiss`, enz.) in `web.ts`. Commit.

## Task 8: Scriptfix
`pleya_web/scripts/e2e-stack.sh` roept `build-into-server.sh` aan vóór de media-stap (nu faalt een schone checkout). Eén script. Commit.
