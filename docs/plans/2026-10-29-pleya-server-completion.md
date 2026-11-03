# Pleya Server en apps — uitvoering van alle resterende pakketten

Roadmap: C-05; fasebesluiten C-03, loudness C-04. Opdracht Michel 29 oktober 2026: alle pakketten uit `2026-10-29-pleya-server-en-apps.md` afronden. Pakket 0 en 1 staan in lokale commit `9ba3b371`. Dit document beschrijft uitvoering; detailstatus blijft in de masterlijst. P5/PS-15 zijn expliciet vrijgegeven (DEC-183). Productie, push/merge/release, PS-12 en nieuwe contractvensters blijven afzonderlijke besluiten. Eén primaire stroom; geen fysieke acceptatie claimen uit simulators.

## Task 2: playback en ondertitels
Bestaande contract: stabiele versie-ID, expliciete eerste versie, sidecars/auth en bron-/bestandsinformatie aansluiten op bestaande speler/cache. RED→GREEN via publieke client en bestaande playback-callers; behoud Plex/Jellyfin/local/Share. Kwaliteitscap en audiokeuze alleen na afgebakende compatibiliteitsvoorstel/vrijgave, inclusief echte planner/transcoderconsumptie. Hoofdstukken/intro/credits blijven onder hun bestaande scope. Verificatie: gerichte playback/mapper/cache-tests, ci_checks, passende native Verify; hardware apart.

## Task 3: metadata en identiteit
S4/S22: bestaande velden/routes en externe IDs inventariseren, NFO/matching/artwork/attributie en correctierondes bewijzen. Ontbrekende identiteit/persoonroutes en velden eerst contractueel voorstellen. Vervolgens wire→mapper→adapter→shared consumer; geen titelmatch als zekere identiteit. Test echte bronkeuze en ambigue matches.

## Task 4: downloads en toestelacceptatie A
Bestaande downloadmanager/sidecar/offline-cache en digest gebruiken; ontbrekend artwork en metadata aansluiten. RED→GREEN op publieke actie, accountrechten, gewijzigde bytes en offline-syncvolgorde. Geen tvOS-downloads. Herstart/offline/native acceptatie per doelplatform; geen hardware-PASS zonder toestelrun.

## Task 5: web en eerste installatie
Bestaande northstars en routes hergebruiken: consument Home/catalogus/detail, persoonlijke functies, browser-state/ondertitels, hervatbare wizard, journey 13/herstel/upgrade op geïsoleerde testinstance. Rol- en fouttoestanden, toetsenbord/axe en native browserbeelden. Geen refreshcredential in URL, geen tweede Flutter-beheersuite.

## Task 6: collecties, playlists, realtime en MCP
S19/S21/S16: eerst scoped contractvrijgave. Bestaande UI/interfaces; canonieke metadatawrites uitsluitend actuele Pleya owner (geen admin/member/borrowed), persoonlijke playlists behouden eigen rechten. Events invalidateren bestaande state met huidige refresh als fallback. MCP vóór volledige journeys, met dezelfde autorisatie/audit en destructieve bevestiging. Gerichte API/contract/authority/UI-tests en onafhankelijke adversariële review.

## Task 7: beveiliging, herstel en vervangingsgate B
S15/S24/S25: bestaande limiter/securitymatrix/faalpaden en off-site herstel sluiten met werkelijk bewijs. Off-site bestemming/sleutel en PS-12-keuze eerst concreet maken; productie alleen na aparte go en verse backup. Review→gates→exacte geïntegreerde SHA→interne builds→hardware→testinstancegate; Plex blijft draaien. Volledige S15.2 vereist alle journeys en boeken/MCP. Geen releaseclaim met open fysieke poort.

## Task 8: volledige productscope C
P5 en PS-15 vrijgegeven; boekenvenster en hardwaremeting blijven vereist. Historische ebooks-werkboom selectief inventariseren, geen blinde merge. Bestaande Unified Library, Readium Locator/digest, reader/leesvoortgang/web en source seam. C-04 loudness in eigen venster. Resterende matrix-gaps volgens bestaande besluiten behandelen; niets stilzwijgend optioneel verklaren.
