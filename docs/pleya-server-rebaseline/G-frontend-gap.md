# G. Frontend gap analysis (`pleya_web`)

Gemeten op `5eebb83`: SvelteKit 2.70 met Svelte 5 runes, Vite 8, Bun, adapter-static in
SPA-modus, TypeScript strict, één runtime-dependency (`openapi-fetch`). Zeven routes, elf
componenten, drie stores, 16 unit-bestanden (112 asserties), 28 e2e-tests met axe op vijf
breedtes, geen CI.

## G.1 Architectuur: wat blijft en wat verandert

| Laag | Vandaag | Verandert | Reden |
| --- | --- | --- | --- |
| Routing | 7 bestandsroutes, één `+layout.svelte` met fasebewaking | 24 routes in drie groepen: consumer, `/admin/*`, `/setup`; twee layouts (`(app)` en `(admin)`) onder één root | de beheersectie heeft een eigen zijbalk en een eigen gate op rol |
| State | `session`, `theme`, `viewport` als klassestores | `session` krijgt `role`, `libraries` met soort, `capabilities`; nieuw `settings` (client-local voorkeuren) en `admin` (server, roots, jobs met polling) | RB-9, RB-16 |
| API-client | `PleyaClient` met single-flight refresh, `PUBLIC_PATHS` | uitbreiden per venster; `schema.d.ts` opnieuw genereren per slice; `api/admin.ts`, `api/ebooks.ts`, `api/reading.ts` als dunne lagen op dezelfde client | bestaand patroon, geen tweede client |
| Auth | tokens in `sessionStorage` en `localStorage`, geen cookie | ongewijzigd in dit traject; de HttpOnly-cookie uit PS-3W 4.2 blijft uitgesteld | geen contractwijziging nodig; noteren in K |
| Componenten | 11 | ongeveer 30 (DESIGN.md hoofdstuk 5) | northstar |
| Tokens | `tokens.css`, OLED standaard | ongewijzigd, plus `--poster-w`, `--inset`, `--rail-gap` per breekpunt en de capsuleknop | DESIGN.md hoofdstuk 2 |
| Responsief | `viewport.wide` op 900, CSS op 600/900/1200/1600 | zelfde breekpunten; `wide` blijft de schakel tussen topnav en tabbalk | ongewijzigd |
| Data fetching | per pagina `$effect` met `AbortController`, geen cache | per pagina blijft; Home doet zes aanvragen parallel; beheer pollt `scans` elke 5 s met backoff bij fout | RB-6, geen realtime |
| Fouten | `ApiError` met 18 codes op code, `StateView` | codes erbij uit deel J; `ConfirmDialog` voor destructieve acties | |
| i18n | infrastructuur, één locale | Nederlands erbij als tweede bronbestand; de mockups zijn Nederlands, de code blijft sleutelgedreven | PS-3W 5.7 |
| Tests | vitest, Playwright tegen echte stack, axe | uitbreiden per slice; screenshotvergelijking tegen de northstar als reviewbewijs, niet als gate | RB-14 |
| CI | geen | job `pleya-web` | RB-15 |

## G.2 Per surface

| Surface | Vandaag | Werk | Slice |
| --- | --- | --- | --- |
| Shell | `NavRail` 80/220, `BottomBar` 4 items, `ThemePicker` in de kop | `TopNav`, `MobileHeader`, `TabBar` met capability-slot, Beheer-pil, zoekveld inline; thema verhuist naar Mijn Pleya | S7 |
| Home | hero plus `recently_added`, limit 24 | zes rijen, lege rij verdwijnt, hero met `Meer info` en segmentindicator | S8, S9 |
| Films, Series | bestaan niet (`/libraries` is de ingang) | landings met rijen; `/libraries` blijft als secundaire route bereikbaar via Mijn Pleya | S8 |
| Boeken | niets | landing, alle boeken, detail | S9 |
| Alle films | `/libraries/[id]` raster met 6 sorteringen | filters, facetten, verwijderbare chips, extra sorteringen | S8 |
| Zoeken | `/search` met soortchips | secties per soort, vijf chips altijd, boeken en auteurs erbij, lege staat met uitweg | S8, S9 |
| Detail | `/items/[id]` 296 regels, film/show/season/episode | herschrijven naar `DetailHero`, `EpisodeRow`, panelen; `summary`, `genres`, cast; versiekiezer; toestelnaam | S8 |
| Boekdetail | niets | `BookHero` met ambience, feiten, reeks, download | S9 |
| Mijn Pleya | niets (alleen thema) | persoonlijke laag, toestellen, uitloggen, wachtwoord, voorkeuren client-local, ingang beheer | S8 |
| Inloggen, setup | bestaan | inloggen herschikken (foutstaat), setup wordt vier stappen | S7, S11 |
| Staten | `StateView` | skelet, lege bibliotheek met rolafhankelijke knoppen, onbereikbaar met backoff-tekst | S7 |
| Beheer | `/server` alleen-lezen | tien secties plus mobiele index | S10 |
| Speler | niets | `/items/[id]/play` met eigen schil, na een mockup | S13 |
| Webreader | niets | `/books/[id]/read` met eigen schil, na een mockup en RB-12 | S12 |

Uitgebreide scope: verzamelingen en afspeellijsten (17, 18, S19), geschiedenis en favorieten
(19, S20), downloads zichtbaar op Mijn Pleya (S23), speler met hls.js op het transcodepad
(S18), realtime-abonnement voor scanvoortgang en kijkstatus met terugval op polling (S21),
metadata-match en artworkkeuze in beheer (S22), onderhoud met back-up en restore (35, S25).

## G.3 Bestandsgrenzen (wat waar komt)

```
src/routes/
  +layout.svelte                 root: sessie, thema, locale (bestaand, ontdaan van nav)
  (app)/+layout.svelte           TopNav / MobileHeader / TabBar
  (app)/+page.svelte             Home
  (app)/films/+page.svelte       landing      (app)/films/all/+page.svelte   catalogus
  (app)/series/...               idem
  (app)/books/+page.svelte       landing      (app)/books/all/   (app)/books/[id]/
  (app)/items/[id]/+page.svelte  detail film, serie, seizoen, aflevering
  (app)/items/[id]/play/         speler (S13, eigen schil)
  (app)/books/[id]/read/         reader (S12, eigen schil)
  (app)/search/+page.svelte
  (app)/my/+page.svelte
  (app)/libraries/...            bestaand, secundair
  (admin)/+layout.svelte         AdminLayout met AdminNav en rolgate
  (admin)/admin/+page.svelte     overzicht
  (admin)/admin/libraries/  storage/  activity/  users/  users/[id]/  media/  metadata/  network/  security/  diagnostics/
  setup/+page.svelte             wizard met vier stappen (één route, stap in de state)
  login/+page.svelte
src/lib/components/              zie DESIGN.md hoofdstuk 5; één component per bestand, geen bestand boven 300 regels
src/lib/api/                     client.ts (bestaand), admin.ts, ebooks.ts, reading.ts, schema.d.ts (gegenereerd)
src/lib/stores/                  session, theme, viewport (bestaand), prefs, admin
src/lib/util/                    format, paging (bestaand), ambience.ts (dominante kleur uit een cover), srcset.ts (artworkladder)
src/styles/                      tokens.css, base.css (capsuleknop, nieuwe primitieven)
```

De detailpagina van 296 regels wordt gesplitst voordat ze groeit: `DetailHero.svelte`,
`SeasonPicker.svelte`, `EpisodeList.svelte`, `TrackList.svelte`, `FileFacts.svelte`.

## G.4 Wat er niet komt

Geen client-side cache-laag (elke navigatie haalt opnieuw; de Go-laag cachet artwork en
immutables), geen service worker of PWA (secure-context op LAN, bestaand besluit), geen tweede
API-client, geen adminframework of componentbibliotheek van buiten, geen bestandsbrowser.
