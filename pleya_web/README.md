# Pleya Web

De meegeleverde webclient van Pleya Server, opgeleverd in **PS-3W**. De fase staat in
[docs/pleya-server-architecture.md](../docs/pleya-server-architecture.md#fase-3w-pleya-web-schil-bladeren-en-zoeken),
het afwijkingsvoorstel in [docs/pleya-server-ps3w-proposal.md](../docs/pleya-server-ps3w-proposal.md).

**Pleya Web is een gewone Pleya Protocol-client** die toevallig samen met de server wordt
uitgeleverd. Alles wat hier op het scherm komt, komt via `/pleya/v1`. Geen tweede API, geen
`/internal/`-route, geen directe database, ook niet nu de bundel in dezelfde binary zit. Dat is
[DEC-046](../docs/DECISIONS.md#dec-046-pleya-web-is-een-protocolclient-en-co-distributie-geeft-geen-extra-rechten),
en het geldt vanaf de eerste regel code.

## Wat er staat

Setup en inloggen, een schil met navigatie die op capabilities draait, Home met
`recently_added`, bibliotheken met cursorpaginering en sortering, zoeken volgens
[DEC-045](../docs/DECISIONS.md#dec-045-zoeken-levert-standaard-films-series-en-afleveringen-geen-seizoenen),
een detailpagina voor film, serie, seizoen en aflevering, en een serveroverzicht uit
`GET /server` en `GET /info`.

Wat er níét staat, en waarom: afspelen en `<video>` horen bij PS-4, en poort 3 en poort 4 uit
[docs/pleya-server-gates.md](../docs/pleya-server-gates.md) staan nog open. Kijkstatus bestaat niet
in dit protocol (`capabilities.watch_state` is `false`), dus `continue_watching` en `next_up`
worden niet eens opgevraagd. Samenvatting, genres, cast en beoordelingen zitten niet in `Item` en
komen in PS-7. Scans, jobs, opslag en bibliotheekbeheer hebben geen endpoint; dat zijn G6 en G7 en
die krijgen eerst een fase. Er staat daarom nergens een knop die niets doet.

## Draaien

```sh
bun install
bun run dev                     # tegen een server op http://127.0.0.1:8832
PLEYA_SERVER_ORIGIN=http://nas:8832 bun run dev
```

De ontwikkelserver proxyt `/pleya` naar de echte server. In de uitrol staan bundel en API op
dezelfde origin, dus de client gebruikt altijd relatieve paden en heeft nooit CORS nodig; die
proxy houdt dat in ontwikkeling waar.

```sh
bun run check                   # svelte-check in TypeScript strict
bun run test                    # unit- en componenttests (vitest)
bun run api:check               # de gegenereerde client tegen het contract
bun run build                   # statische bundel in build/
scripts/build-into-server.sh    # bouwen én in pleya_server/internal/web/dist zetten
```

## De bundel in de binary

`pleya_server/internal/web` embed `dist/` met `//go:embed all:dist` en serveert hem achter de
protocolroutes. `/pleya/v1/*`, `/healthz` en `/readyz` houden altijd voorrang; alleen een pad dat
geen bestand is en niet onder een van die prefixen valt krijgt `index.html`. Dat is een Go-test in
`internal/web` en `internal/api/web_routes_test.go`, geen aanname.

De frontend wordt hier gebouwd en niet in de containerbuild. De uitvoer is architectuurloos, en de
NAS bouwt de Go-binary zelf omdat hij amd64 is; een Bun-toolchain op een Celeron zou hetzelfde
resultaat opleveren voor meer tijd en meer geheugen. `pleya_server/deploy-nas.sh` roept
`scripts/build-into-server.sh` zelf aan.

**Een release bevat nooit stil een lege frontend.** De ontwikkel- en testbuild compileert zonder
bundel, zodat `go test ./...` geen Bun nodig heeft; de releasebuild draagt `-tags release` en
daarmee een `//go:embed dist/index.html`, die zonder bestand op de compiler faalt:

```
internal/web/release.go:18:12: pattern dist/index.html: no matching files found
```

## Het designsysteem

De Flutter-app is de enige designbron. `src/styles/tokens.css` neemt letterlijk over:

| Groep | Bron in de app |
| --- | --- |
| kleur per themamodus, accent, success, error | `lib/theme/mono_theme.dart` |
| radii, ruimte, de drie duren, scrim-gedrag | `lib/theme/mono_tokens.dart` |
| breekpunten, poster- en aflevering-aspecten | `lib/utils/layout_constants.dart` |
| knop-padding en -radius | `monoTheme()`, `buttonStyle` |
| kaartmaten en regelhoogtes | `lib/widgets/media_card_grid_layout.dart` |
| zijbalk 80/220, rode balk op het actieve item | `lib/widgets/side_navigation_rail.dart` |
| bottom bar met indicator van 18×3 | `lib/screens/main_screen.dart` |

OLED is de standaard, net als in de app (`ThemeProvider` start op `ThemeMode.oled`).

Wat web-eigen is: `prefers-reduced-motion`, `:focus-visible`, CSS Grid, `aspect-ratio`,
browser-eigen schuiven, en een hero die met de breedte meebeweegt. Hover staat overal achter
`@media (hover: hover)`. Raakvlakken zijn minstens 44 px. Het TV-focusmodel uit `lib/focus/` en de
1080p-schaalfracties uit `TvLayoutConstants` zijn **niet** overgenomen: een browservenster is geen
televisie.

Twee kleuren uit de app staan bewust niet in de tokens: het teal `#54B9C5` in
`lib/widgets/hub_section.dart:547` en het rood `#F42B1F` in
`lib/widgets/video_controls/tv_info_panel/tv_panel_widgets.dart:15`, dat net naast `kAccent`
`#E5140F` zit. Ze staan als design debt in hoofdstuk 24.3 van de architectuur en worden in app en
web samen rechtgetrokken, niet eenzijdig hier.

### Letters

De app levert Inter in 400, 500 en 700 (`pubspec.yaml`) en gebruikt daarnaast op tientallen
plekken `w600`, `w800` en `w900`, die Flutter naar het dichtstbijzijnde bestand afrondt. De
CSS-fontmatching doet hetzelfde. Er is geen variabele Inter in de repository, en er een toevoegen
zou web juist van de referentie laten afwijken.

De drie bestanden zijn wel omgezet naar woff2: samen 1,8 MB aan OTF is over een LAN de eerste
seconde van elk bezoek, en 548 kB is dat niet. Dat is een hercodering en geen andere letter.
Opnieuw maken uit `assets/fonts/`:

```sh
docker run --rm -v "$PWD/static/fonts:/f" -w /f python:3.12-slim sh -c \
  "pip install --quiet fonttools brotli && python3 -c \"
from fontTools.ttLib import TTFont
for n in ['Inter-Regular','Inter-Medium','Inter-Bold']:
    f = TTFont(f'/f/{n}.otf'); f.flavor = 'woff2'; f.save(f'/f/{n}.woff2')
\""
```

De merkmarkeringen in `static/brand/` komen uit `scripts/gen_brand_assets.py`, net als elk ander
afgeleid merkbeeld:

```sh
python3 scripts/gen_brand_assets.py   # vanuit de repo-root
```

Ze stonden hier eerder als handmatige `sips`-verkleining, en dat is precies misgegaan: toen de P
veranderde bewogen ze niet mee, dus `app.html`, `NavRail.svelte`, `+layout.svelte`, `login/` en
`setup/` tekenden maandenlang nog de oude, handgemaakte P. Een afgeleid merkbeeld hoort geen eigen
handmatig recept te hebben.

De navigatieglyphs staan inline in `src/lib/components/NavIcon.svelte`, met de paden letterlijk uit
`assets/icons/nav/`. Wijzigt daar een glyph, dan hoort hij hier mee te wijzigen.

## Het contract

`src/lib/api/schema.d.ts` wordt gegenereerd uit `docs/pleya-protocol/v1/openapi.yaml` en wordt
nooit met de hand aangeraakt. `scripts/check-api-types.sh` genereert opnieuw en vergelijkt
byte-voor-byte; `src/lib/api/schema.test.ts` doet de goedkope helft door de bron-hash in de kop te
toetsen. Samen is dat wat de codegen-sectie van `scripts/ci_checks.sh` voor Dart doet.

Een pad dat het contract niet kent bestaat in `client.ts` niet, want dan compileert het niet.

## Auth

Het accesstoken staat alleen in het geheugen. Het refreshtoken staat in `localStorage`, en dat is
een **vastgelegde afweging en geen eindmodel**: een strikte CSP maakt XSS moeilijker, niet
onmogelijk, en rotatie met hergebruikdetectie aan de serverkant begrenst de schade zonder hem op te
heffen. Het model dat dit werkelijk oplost is een door de server gezette `HttpOnly`-refreshcookie,
en dat is een wijziging van het authcontract met een CSRF-afweging eraan vast. Zie onderdeel 4.2
van het voorstel.

Vernieuwen gebeurt hoogstens één keer tegelijk. Het refreshtoken roteert bij elk gebruik, dus twee
gelijktijdige verzoeken zijn per definitie hergebruik, en dan trekt de server de hele keten in.

Er wordt niet uitgelogd bij de server: het protocol heeft geen uitlogendpoint. Afmelden gooit het
token weg; `POST /auth/logout` hoort bij PS-9 (voorstel 5.2).

## Artwork

`GET /pleya/v1/artwork/{id}` is klasse `authenticated` en accepteert alleen een
Authorization-header. Een `<img src>` kan die niet zetten, en een service worker die hem injecteert
vraagt een secure context, wat `http://nas:8832` op een LAN niet is. `Artwork.svelte` haalt de
bytes daarom met `fetch` op en hangt ze als object-URL aan het element: luie strategie via
`IntersectionObserver`, annuleren bij verdwijnen, en elke object-URL precies één keer intrekken.

De meting uit acceptatiecriterium 6 draait met `scripts/measure-artwork.ts` tegen een raster van
vijfhonderd posters. De uitkomst: 28 van 104 cellen laden bij binnenkomst, tijdens het
raster staan er 500 object-URL's uit bij 7,3 MB heap, erna 0 en 1,8 MB, en tien keer heen en weer
scheelt 0,2 MB tussen de eerste en de tweede helft. Alle drie de voorwaarden gehaald.

Het script stopt met een fout zodra de grootste bibliotheek kleiner is dan het doelaantal. Een raster
van twee posters ruimt altijd netjes op, dus zonder die grens levert een te kleine bibliotheek een
oordeel op dat er geslaagd uitziet en niets bewijst.

## Content Security Policy

De CSP staat in `svelte.config.js` en komt als meta-tag in de gegenereerde HTML, niet als
Go-header. SvelteKit schrijft één bootstrapscript inline en zet de hash daarvan in die meta-tag;
een browser doorsnijdt alle policies, dus een Go-header met `script-src 'self'` zou datzelfde
script alsnog blokkeren. De Go-laag stuurt `frame-ancestors 'none'`, de enige directive die een
meta-tag niet mag dragen, plus de headers buiten CSP.

`style-src` is `'self'` zonder `'unsafe-inline'`, en dat vraagt dat geen enkele component een
`style`-attribuut zet. SvelteKit's eigen routeaankondiging doet dat wel; die krijgt zijn stijl uit
`src/styles/base.css` en de browser meldt de geblokkeerde regel in de console. Dat is verwacht.

## De NAS bereiken

De server luistert op de NAS alleen op `127.0.0.1`, dus geen enkele machine op het LAN komt erbij;
openstellen hoort bij PS-11. De gewone omweg, `ssh -L`, werkt daar niet: de sshd van DSM weigert
poortdoorgifte met `administratively prohibited: open failed`, ongeacht wat `authorized_keys`
toestaat.

`scripts/nas-tunnel.ts` overbrugt dat zonder iets aan de NAS te veranderen. Per verbinding start hij
over SSH een `python3` op de NAS die stdin en stdout aan `127.0.0.1:8832` koppelt. Geen poort open,
geen bestand, geen configuratie, en niets dat een herstart overleeft.

```sh
bun run nas:tunnel            # daarna http://127.0.0.1:18832 in de browser
PORT=19000 bun run nas:tunnel
```

De end-to-end-suite draait er ook tegen, met de inloggegevens uit de omgeving:

```sh
PLEYA_E2E_BASE_URL=http://127.0.0.1:18832 \
PLEYA_E2E_USER=... PLEYA_E2E_PASS=... \
  bun run test:e2e
```

**Playwright legt bij een fout geen trace en geen schermafbeelding vast.** Elke test die inlogt typt
een wachtwoord in een veld, en dat veld staat in leesbare tekst in de ARIA-boom die Playwright
opslaat. Tegen de wegwerpstack is dat een testwachtwoord, tegen een echte server een credential op
schijf. Aanzetten kan bewust met `PLEYA_E2E_ARTIFACTS=1`, en dan alleen tegen de wegwerpstack.

## Tests

```sh
bun run test                                    # unit en component
eval "$(scripts/e2e-stack.sh up)"               # echte stack: binary, Postgres, ffprobe
bun run test:e2e                                # end-to-end plus axe
bun run scripts/measure-artwork.ts              # de artworkmeting
scripts/e2e-stack.sh down
```

De end-to-end-tests draaien tegen de echte binary met de echte API, niet tegen `vite dev` en niet
tegen mocks. Dat is het punt: ze meten of de bundel geserveerd wordt, of de protocolroutes
voorrang houden, en of de flow tegen het echte contract werkt.
