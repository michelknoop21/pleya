# Handoff: stand van 4 september 2026, avond

Dit bestand is het overdrachtspunt van de sessie die het re-baseline-pakket schreef. Het zegt
wat er ligt, wat Michel heeft besloten, wat daardoor in de andere delen achterhaald is, en
waar de volgende sessie begint. Alles in deze map en in `docs/assets/pleya-web-northstar/` is
op dit moment **ongecommit** op `feat/pleyaserver` `5eebb83`.

## 1. Wat er ligt

| Onderdeel | Locatie | Stand |
| --- | --- | --- |
| Pakket A tot O plus C-review | `docs/pleya-server-rebaseline/` | compleet voor de scope van vóór de avondbesluiten |
| Northstar-set | `docs/assets/pleya-web-northstar/` | 40 schermen, 80 beelden; bron in `src/pages/`, tokens in `src/web.css`, renderer `src/build.mjs`, handleiding `DESIGN.md` |
| Mockups voor de uitgebreide scope | pagina's 17, 18, 19, 35 en de bijgewerkte 28 | gebouwd, nog niet gereviewd en nog niet in manifest, deel D en deel C opgenomen |
| Geheugen | `~/.claude/projects/.../memory/pleya-server-rebaseline-pakket.md` | bijgewerkt met de avondbesluiten |
| Ongecommit werk van eerdere sessies vandaag | `docs/qa/ps5-hardware-round.md`, `docs/sessions/2026-09-04.md`, `docs/sessions/2026-09-03.md` | niet van deze sessie; laten staan |

## 2. Besluiten van Michel op 4 september, avond

1. **Northstar-set akkoord**, inclusief `Meer info` als tweede hero-knop en de tijdelijke
   segmentindicator (RB-2). De set mag naar APPROVED zodra de mockups voor de uitgebreide
   scope (punt 3) ook gereviewd zijn; tot dan blijft de map CANDIDATE.
2. **Boeken zichtbaar op web** akkoord (RB-3).
3. **De scope wordt het totaalplan.** Erbij: transcoderen (PS-6 PlaybackPlan en PS-8),
   downloads naar apps (PS-10), verzamelingen en afspeellijsten (PS-9C), persoonlijke laag met
   geschiedenis, favorieten en waarderingen (PS-9P), spoorvoorkeuren (PS-9T), realtime
   websocket-hub (PS-11R), remote hardening en observability (PS-11), back-up, restore, upgrade
   en faalpaden (PS-11B), en **metadata-providers (PS-7) met automatisch matchen en automatisch
   inladen van metadata en artwork**. De Plex-off gate uit architectuur hoofdstuk 25 hoort
   daarmee bij "af".
4. **Plex-migratie (PS-12) is een losse keuzefase aan het eind** en loopt nooit automatisch mee.
   PS-13 (externe transcode-workers) en PS-16 (offline boeken, bladwijzers) blijven buiten scope.
5. **De branch moet weer zonder problemen met `main` kunnen mergen.** Dat is een eigen
   deliverable naast slice S0.
6. Eerder die dag al: **alles beheerbaar via MCP** (RB-19, RB-20, slice S16, scherm 34).

## 3. Wat daardoor achterhaald was, per deel (bijgewerkt op 4 september, laat; de tabel blijft als verslag)

| Deel | Achterhaald | Vervangen door |
| --- | --- | --- |
| README | "Eén productbesluit" en de zin dat transcode, downloads, verzamelingen, realtime, back-up en Plex-migratie buiten dit traject blijven | besluit 3 en 4 hierboven |
| B.3 | de rij "PS-6, PS-8, PS-10, PS-9C, PS-9P, PS-9T, PS-12, PS-13: buiten dit traject" | alle behalve PS-12 en PS-13 krijgen een slice |
| E | RB-18 (scope-grens) | herschrijven naar de totale scope; nieuwe RB's voor PlaybackPlan en transcode (architectuur h10 en h11), downloads met digest, verzamelingen, persoonlijke laag, realtime met volgnummers (h14), back-up en restore (h17.3, h22), providerladder (h8, TMDB eerst, productbesluiten B1 t/m B4 en B8 uit de replacement matrix als aanbeveling ingevuld) |
| F, G, H | ontbrekende domeinen: transcode, downloads, verzamelingen, geschiedenis, realtime, back-up, providers | rijen per domein erbij |
| I | S15 als sluitstuk na S16 | nieuwe slices S17 en verder in de DAG; kritieke lijn opnieuw bepalen |
| J | vier vensters, migraties tot 0013 | extra vensters en migraties 0014 en verder |
| K | dreigingen 1 tot 23 | erbij: transcoderproces en ffmpeg-argumenten, websocket-auth en per-gebruiker events, back-upbestanden en hun rechten, providerantwoorden valideren, SSRF naar providers |
| L | journeys 1 tot 8 | erbij: transcode op een toestel dat het bestand niet aankan, download en sync-back, verzameling delen, realtime scanvoortgang, back-up en restore, metadata-match met correctie die drie rondes overleeft |
| M | DEC-lijst | nieuwe DEC's voor elk nieuw domein |
| N | mergebaarheid alleen in S0 | eigen hoofdstuk met de proefmerge en de conflictlijst |
| O | matrix en O.3 | totale scope; Plex-migratie als keuze; PS-13 en PS-16 buiten |
| D en C | schermen 17, 18, 19, 28, 35 ontbreken | opnemen na review |

## 4. Wat de volgende sessie doet, in volgorde

0. **P0b uit de masterlijst**: de afwijkingen zijn in E, I, J, K, L, M en N verwerkt; trek ze nog
   door in D (mockup voor metadata-overrides), F, H en O. De zwaarste: Readium als reader-architectuur met een
   Go-manifestlaag (15, 26), HttpOnly-refreshcookie en origin-model in S1 (19, 57), per-field
   metadata-overrides (53), drie hwaccel-backends (37).

1. **Mergebaarheid meten.** `git rev-list --left-right --count main...HEAD` en een proefmerge in
   een wegwerp-worktree (nooit in deze), tegen `main` `2433f74` of nieuwer. Bekende conflicten:
   `lib/media/server_capabilities.dart` (`userRating`), `lib/models/pleya_server/pleya_wire.dart`
   (`sessions`), `lib/profiles/profile.dart` plus `.freezed.dart`, `lib/database/app_database.dart`
   plus `.g.dart` en de replay-tak voor `removedFromContinueWatching` in
   `offline_watch_sync_service.dart`, `docs/DECISIONS.md` (063 tot 073 en 093 tegen main, eerste
   vrije nummer 096). Uitschrijven in deel N als stappenplan en uitvoeren als eerste commits van
   S0 op een integratiebranch vanaf `main` (N.2). Bewijs: `scripts/codegen.sh` met lege diff,
   `scripts/ci_checks.sh`, `flutter test` op de SDK uit `.fvmrc`.
2. **Review van mockups 17, 18, 19, 28, 35** op de renders volgens `DESIGN.md` hoofdstuk 6, en
   opnemen in het manifest, deel C en deel D.
3. **Extra mockups** voor de uitgebreide scope: metadata-match en artworkkeuze in beheer
   (kandidaten bevestigen of afwijzen, matchpercentage per bibliotheek, providerattributie),
   transcode-sessies in het overzicht, downloads op Mijn Pleya, realtime-status in Diagnostiek.
4. **Documenten nalezen**: B, D tot O zijn op het totaalplan bijgewerkt; controleer de nieuwe
   slices S17 tot S25 in I tegen de fasetabellen in architectuur hoofdstuk 23 en vul aan waar een
   acceptatiecriterium ontbreekt.
5. **Masterlijst bijhouden**: `docs/PLEYA-SERVER-MASTERLIST.md` is de afvinklijst; elke
   afgeronde taak krijgt daar status, bewijs en datum in dezelfde commit.
6. **Geheugen bijwerken** zodra de docs op de nieuwe scope staan.

## 5. Wat de volgende sessie niet doet

Productiecode wijzigen buiten de mergevoorbereiding van S0; `feat/ebooks` of
`feat/netflix-mobile` aanraken; DEC-nummers claimen buiten de hernummering tegen `main`;
artwork uit `~/Downloads` in git zetten; committen zonder Michels go en zonder `ListAgents` en
de index-mtime te controleren.

## 6. Hoe deze sessie te werk ging (voor wie het wil naspelen)

Drie parallelle audits (Go-backend, `pleya_web`, clientstromen en branches) leverden de
inventaris in A, B, F en G; de designauthority is uit git gehaald (`git show main:...`,
`feat/netflix-mobile:...`, `feat/ebooks:...`) en bekeken als beeld; de mockups zijn gebouwd met
dezelfde werkwijze als de TV-set (HTML-fragmenten, tokens, Playwright) en in twee ronden op de
renders gereviewd (C.2). De anti-slop-hook blokkeerde twee keer op gedachtestreepjes in
tabellen; "onbekend" en "n.v.t." zijn de vervangers.
