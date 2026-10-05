<!-- Directieve documentatie: vereist een onafhankelijke review (AGENTS.md) voor het merget. Beslissingsrecord: DEC-XXX, nummer bij merge. -->
# Big P masterroadmap

Status: voorstel, alleen documentatie. Geen code in deze ronde. De harde regel hieronder wordt pas bindend na acceptatie (DEC-XXX). Breidt de bevoegdheid van de assistent uit, dus lees DEC-142 mee: zichtbaarheid geeft geen rechten, beheer blijft per aanroep afgeschermd.

## Uitgangspunt

Big P antwoordt nu met een vaste set losse tools (`assistantTools`, ruim dertig). Elke nieuwe vraag over een gekoppelde bron betekent een nieuwe tool. Dat schaalt niet, en het levert het verkeerde falen op: een bron die Big P kan bereiken blijft onbeantwoord omdat niemand er een tool voor schreef. Het voorbeeld dat dit aan het licht bracht (IMG_8805, 4 okt 2026): "wat is er deze week toegevoegd?" werd beantwoord met "ik zie alleen wat bekeken is", terwijl Plex en Jellyfin een recent-toegevoegd-lijst kennen.

## Harde regel

Geen gekoppelde, relevante bron blijft voor Big P onbereikbaar alleen omdat er nog geen losse LLM-tool voor bestaat. De grenzen blijven: de rechten van de gebruiker, wat de bron zelf aanbiedt, en privacy en beveiliging van die verbinding.

Een tijdelijke connectivity-wisseling (server offline, daarna weer online) maakt een antwoord niet ongeldig. Een echte identiteits- of rechtenwijziging wel: ander clientobject, ander profiel, andere zichtbaarheid. Dit is dezelfde scheiding als in `assistant_run_named_titles.dart` (commit 88a2b325).

## Fase A: capability-inventaris

Per koppeling vastleggen, in een tabel in dit document of een los bestand ernaast:

| Koppeling | Wat de bron levert | Onder welke rechten | Wat Pleya nu ontsluit |
|---|---|---|---|
| Plex | bibliotheken, items, recent toegevoegd, historie, gebruikers, wijzigingstijden | token van de gebruiker, admin voor beheer | in te vullen |
| Jellyfin / Emby | idem, per gebruiker | gebruikerstoken | in te vullen |
| Trakt | historie, watchlist, kalender (de API; `trakt_client.dart` leest nu alleen aanbevelingen, trending en populair en schrijft scrobbles, historie en beoordelingen) | OAuth van de gebruiker | in te vullen |
| TMDB | metadata, releasedata (nog geen eigen client in `lib/services`, te verifiëren) | API-sleutel via proxy | in te vullen |
| Pleya Server | catalogus, historie, tokens, audit | sessie plus scope | in te vullen |
| Seerr | aanvragen, status, beschikbaarheid | Seerr-gebruiker | in te vullen |
| Tautulli | afspeelhistorie, gebruikers | API-sleutel | in te vullen |

De kolom "wat de bron levert" beschrijft de API van de bron, niet per se wat de Pleya-client al aanroept. De kolom "wat Pleya nu ontsluit" wordt gevuld door de tools in `lib/assistant/assistant_tools_*.dart` na te lopen. Het verschil tussen "bron kan" en "Pleya biedt" is de werklijst.

## Fase B: één CatalogQuery

Eén querymodel in plaats van een toolnaam per vraag: `scope` (servers, bibliotheken), `mediaKind`, `audience` (gebruiker, profiel, iedereen), `changeType` (`added|modified|watched|released|available`), `since`, `sort`. Pleya kiest per bron het juiste endpoint en voegt de uitkomsten samen. Het model krijgt dus één tool met dit schema, niet twintig. Beginpunten: het argumentschema van `search_catalog` in `assistant_tools_catalog.dart` en `UnifiedCatalogSort` plus `buildUnifiedCatalogQuery` in `unified_catalog_filters.dart`. `_CatalogQuery` in `assistant_tools_catalog_query.dart` is alleen de bewaarde uitkomst van een zoekopdracht, geen querymodel.

## Fase C: lokale wijzigingsindex, alleen waar nodig

Bronnen die alleen de huidige toestand kennen (geen "toegevoegd op") krijgen een kleine index: identiteit, bron, `firstSeenAt`, `lastSeenAt`, `sourceUpdatedAt`, metadata-hash en beschikbaarheidswijzigingen. Het is geen kopie van de bibliotheek en wordt alleen gevuld voor bronnen waar fase A laat zien dat historie ontbreekt. Gesleuteld op verbinding en eigen/geleend (owned/borrowed, zie `docs/agents/architecture.md`) en per profiel, nooit gedeeld tussen profielen met verschillende rechten. De index reikt nooit verder dan de zichtbare bibliotheken en wat `canAdministerServer` toestaat, en wordt gewist bij een rechtenwijziging (bibliotheek verborgen, profielwissel, verbinding losgekoppeld).

## Eerste end-to-end acceptatiescenario

Vraag: "Wat is er recent toegevoegd of veranderd?" over alle gekoppelde bronnen.

- Bron met eigen toegevoegd-datum: antwoord rechtstreeks uit de bron.
- Bron die alleen de huidige toestand vertelt: antwoord uit de wijzigingsindex, met de vermelding sinds wanneer Pleya die bron volgt.
- Per onderdeel van het antwoord staat de bron erbij.
- Kan een bron het niet, dan zegt Big P dat en waarom, in plaats van de vraag te herinterpreteren naar kijkcijfers.
- Test: een server gaat offline tijdens de vraag, het antwoord blijft staan maar wordt niet ververst en de wijzigingsindex vult zich voor die bron niet bij. Een profielwissel, een vervangen client of een verborgen bibliotheek tijdens de vraag, het antwoord verdwijnt.

## Volgorde en review

A voor B voor C; B kan beginnen zodra de eerste drie bronnen in A staan. Elke fase is een eigen branch met focus-tests en een negatieve controle. Dit bestand stuurt toekomstig werk aan, dus het krijgt een inhoudelijke review van een zitting die het niet schreef, voor het merget.
