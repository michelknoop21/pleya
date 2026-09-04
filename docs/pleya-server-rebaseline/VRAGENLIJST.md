# Vragenlijst: alle keuzes vóór de uitvoering

Elke vraag hieronder is een keuze die anders tijdens een slice zou vallen. Per vraag staat een
aanbeveling; "akkoord" neemt die over. Een afwijkend antwoord wordt letterlijk in dit bestand
gezet en daarna in het betreffende deel verwerkt. Zolang een vraag open staat, mag de slice die
ervan afhangt niet starten (poort P0 in de masterlijst).

Antwoordvorm: nummer plus "akkoord" of het afwijkende antwoord. Datum van beantwoording komt in
hoofdstuk 8.

## 1. Scope en volgorde

| # | Vraag | Aanbeveling | Raakt |
| --- | --- | --- | --- |
| 1 | Is de slice-volgorde uit deel I akkoord, met de kritieke lijn S0 → S1 → S14 → S17 → S18 → S23 → S15 en de webslices parallel? | akkoord; web (S7 tot S10) start direct na S0 naast de backend | I |
| 2 | Blijven PS-13 (externe transcode-workers) en PS-16 (offline boeken, bladwijzers) buiten dit plan? | ja | O |
| 3 | Blijft de app-reader (PS-15 aan de appkant) op `feat/ebooks` en buiten dit plan? | ja; de server levert alles wat hij nodig heeft (S3, S6) | H |
| 4 | Komt er een metadata-provider voor boeken (Open Library, Google Books)? | nee in dit plan; de OPF blijft de bron, eigen besluit later (DEC-093) | S22 |
| 5 | Ondertitels zoeken en downloaden via de server (B8)? | niet in dit plan; na S22 als losse uitbreiding op de providerlaag | E, O |
| 6 | Scrubvoorbeelden (B6)? | niet in dit plan | O |
| 7 | Intro en aftiteling overslaan (B7)? | hoofdstukmarkeringen uit het bestand gebruiken waar ze bestaan (S4 leest ze mee), geen eigen detectie | S4, S18 |
| 8 | Live TV en DVR (B9, B10)? | buiten de productscope van Pleya Server, blijft een Plex-functie | O |
| 9 | Plex-kijklijst (B11)? | favorieten per gebruiker dekken het lokale deel; de "nog niet in je bibliotheek"-kant vervalt bij Plex-off | S20 |

## 2. Ontwerp

| # | Vraag | Aanbeveling | Raakt |
| --- | --- | --- | --- |
| 10 | Mockups 17, 18, 19, 28 en 35 worden door mij gereviewd en dan in één keer aan jou voorgelegd? | ja, één ronde | P2 |
| 11 | De zes ontbrekende mockups (metadata-match en artworkkeuze, transcode-sessies, downloads op Mijn Pleya, realtime-status, speler, reader) in één ronde vóór S7? | ja, één ronde, daarna APPROVED met SHA256SUMS | P3 |
| 12 | Standaardthema op web: OLED (`#000`, zoals de app start) of donker (`#141414`, waarop de mockups zijn getekend)? | donker als standaard, OLED en licht als instelling; de mockups zijn de maat | S7 |
| 13 | Blijft het lichte thema bestaan op web, afgeleid uit tokens zonder eigen mockups? | ja | S7 |
| 14 | Talen op web: Nederlands en Engels, standaard uit de browser? | ja, geen derde taal | S7 |
| 15 | Webreader-engine? | `epub.js` (CFI is de kern van de bibliotheek); `foliate-js` als alternatief als epub.js een blokkade oplevert | S12 |
| 16 | Browserspeler: native `<video>` voor direct play, `hls.js` op het transcodepad, Safari native HLS? | ja | S13, S18 |

## 3. Auth, beheer en MCP

| # | Vraag | Aanbeveling | Raakt |
| --- | --- | --- | --- |
| 17 | API-tokens: standaard 90 dagen geldig, bereiken `admin`, `maintenance`, `read`, "nooit" alleen als bewuste keuze? | ja | S1 |
| 18 | Grenzen op token-TTL's (K.14): access 1 tot 60 min, refresh 1 tot 90 dagen, stream 1 tot 15 min, streamsessie 5 tot 120 min, maximaal 32 streamsessies? | ja | S1 |
| 19 | HttpOnly-refreshcookie voor de webclient (PS-3W 4.2): in dit plan of uitgesteld? | uitgesteld; tokens in browseropslag blijven, met de bestaande onderbouwing | K |
| 20 | MCP standaard aan of uit na installatie? | uit; aanzetten in Beveiliging, met de configuratieknop voor Claude Code | S16 |
| 21 | MCP alleen Streamable HTTP, geen stdio? | ja | S16 |
| 22 | Leestools via MCP ook voor `member` en `restricted` (binnen hun zicht)? | ja | S16 |
| 23 | Auditlog: 90 dagen bewaren, alleen mutaties, ook via de webclient? | ja | S1 |
| 24 | Bibliotheek verwijderen vraagt de naam typen; gebruiker verwijderen en sleutel roteren vragen `confirm`? | ja | S2, S1 |
| 25 | Rol `admin` mag gebruikers aanmaken en rechten geven, maar de eigenaar nooit wijzigen of een tweede eigenaar maken? | ja (bestaand PS-9-gedrag) | S1 |

## 4. Data en protocol

| # | Vraag | Aanbeveling | Raakt |
| --- | --- | --- | --- |
| 26 | Locator voor leesvoortgang: EPUB CFI plus spine-index en fractie, bindend voor app en web? | ja (RB-12) | S6, feat/ebooks |
| 27 | Artworkladder 240, 480, 960, 1920 breed; server rondt op naar boven? | ja (RB-7) | S4 |
| 28 | Bibliotheeksoort alleen wijzigbaar zolang de bibliotheek leeg is? | ja | S2 |
| 29 | Genres als vrije tekst uit sidecar en provider, met hoofdlettergelijke facetten; geen vaste lijst? | ja | S4, S5 |
| 30 | Verzamelingen: zichtbaarheid privé, iedereen, of per gebruiker; afspeellijsten alleen de eigenaar? | ja | S19 |
| 31 | Kijkgeschiedenis: onbeperkt bewaren, per gebruiker zelf te wissen, één rij per afspeelsessie? | ja | S20 |
| 32 | Waarderingen: numeriek 1 tot 10 op de server (past bij Plex en Trakt), weergave in de client? | ja | S20 |
| 33 | Drempel voor "uitgekeken": serverinstelling, standaard 90 procent, clients lezen hem uit `/info`? | ja; vervangt de vaste 0,9 in de client | S1, S14 |
| 34 | Zoeken: trigram op titel en sorteertitel, geen semantische of fonetische zoekfunctie? | ja | S5 |
| 35 | `feature_level` blijft 1 gedurende het hele plan; alles via capabilities? | ja (RB-9) | J |
| 36 | Realtime: één websocket per client, bearer in het eerste bericht, volgnummers, `since=`? | ja (RB-25) | S21 |

## 5. Afspelen, transcoderen, downloads

| # | Vraag | Aanbeveling | Raakt |
| --- | --- | --- | --- |
| 37 | Hardwareversnelling: VAAPI en QSV (Intel, de DS920+) eerst, NVENC later, software als terugval? | ja | S18 |
| 38 | Standaardladder voor transcode: 1080p 8 Mbit, 720p 4 Mbit, 480p 1,5 Mbit? | ja, instelbaar in Media | S18 |
| 39 | Gelijktijdige transcodes standaard 2, quotum transcodemap 20 GB, oudste sessie eerst weg? | ja | S18 |
| 40 | Beeldondertitels (PGS, DVD) bij transcoderen inbranden; tekstondertitels als WebVTT ernaast? | ja | S18 |
| 41 | Sessie zonder heartbeat na 60 seconden beëindigen? | ja | S18 |
| 42 | Downloads: origineel of een trede uit de ladder, altijd met digest; recht `download` per bibliotheek beslist? | ja (RB-22) | S23 |
| 43 | Web downloadt zelf alleen boeken; video-downloads zijn voor de apps? | ja | S23 |

## 6. Metadata-providers

| # | Vraag | Aanbeveling | Raakt |
| --- | --- | --- | --- |
| 44 | TMDB als eerste en enige provider in dit plan; TVDB niet? | ja | S22 |
| 45 | TMDB-sleutel: per server ingevoerd door de beheerder (schrijf-alleen instelling), geen gedeelde Pleya-sleutel? | ja, past bij de TMDB-voorwaarden | S22 |
| 46 | Automatisch matchen: exacte titel plus jaar (of externe id uit een sidecar) koppelt automatisch; alles anders op de ambiguïteitslijst? | ja | S22 |
| 47 | Taal van metadata: `nl-NL` met terugval op `en-US`, instelbaar? | ja | S22 |
| 48 | Artwork automatisch: hoogst gewaardeerde poster en backdrop in de gekozen taal; logo als aanwezig; kiezen uit kandidaten in beheer? | ja | S22 |
| 49 | Sidecar wint per veld van de provider; de provider vult alleen gaten? | ja (RB-27) | S22 |
| 50 | Beoordelingen alleen uit TMDB (geen IMDb-scraping)? | ja | S22 |
| 51 | Extra's (trailers, deleted scenes) uit de bestandsboom herkennen volgens de Plex-naamgeving (`Trailers/`, `-trailer`)? | ja, geen provider-trailers | S22 |
| 52 | Providerronde: automatisch na elke scan voor nieuwe en ongematchte titels, volledige ververs alleen op knop? | ja | S22 |
| 53 | Metadata bewerken beperkt tot bevestigen, afwijzen, fix-match en artwork kiezen; geen vrije editor (B1, B2, B3)? | ja | S22 |

## 7. Bedrijf, back-up, proces

| # | Vraag | Aanbeveling | Raakt |
| --- | --- | --- | --- |
| 54 | Back-ups in een aparte mount `/backups`, dagelijks 03:30, 14 bewaard, wekelijkse hersteltest? | ja | S25 |
| 55 | Onderhoudsmodus: nieuwe streams en scans stoppen, sessies blijven, melding in web en app? | ja | S25 |
| 56 | Metrics alleen Prometheus op loopback; geen externe telemetrie? | ja | S24 |
| 57 | Publiek adres blijft `https://web.pleya.app`; vertrouwde proxy's uit de omgeving? | ja | S1, S24 |
| 58 | Integratiebranch heet `integration/pleya-server-rebaseline`, vanaf `main`, met merge-commits? | ja | N |
| 59 | DEC-nummers: hernummeren vanaf 096 bij de merge in S0; `feat/ebooks` en `feat/netflix-mobile` hernummeren bij hun eigen merge? | ja | M |
| 60 | Commitbeleid: ik commit per commitgrens op de integratiebranch zonder per commit te vragen, en push per slice na jouw go? | ja; niets naar `main` zonder jou | N |
| 61 | De NAS is de stagingomgeving voor de journeys die echte data nodig hebben (1, 3, 4, 8, 9, 13), met een dump vooraf? | ja | L |
| 62 | Eén TestFlight-build aan het eind van S14 voor de hardwareronde en de compatibiliteitstest met build 248? | ja | N |
| 63 | Goedkeuring van mockups: kandidaat, mijn review op de renders, jouw akkoord in de chat, dan APPROVED met SHA256SUMS? | ja | M |
| 64 | Wanneer de masterlijst en een deel van het plan elkaar tegenspreken, wint het plan en wordt de lijst gecorrigeerd? | ja | masterlijst |

## 8. Antwoorden (Michel, 4 september 2026, avond)

Akkoord op 1 t/m 3, 5 t/m 14, 16 t/m 18, 20 t/m 22, 24, 25, 28, 30 t/m 33, 36, 38, 41 t/m 47,
50 t/m 52, 55, 58, 60, 63 en 64, met de toelichtingen hieronder waar hij die gaf. Afwijkend op
15, 19, 23, 26, 27, 29, 34, 35, 37, 39, 40, 48, 49, 53, 54, 56, 57, 59, 61 en 62. De afwijkingen
zijn bindend en gaan vóór de aanbeveling en vóór de delen A tot O tot die zijn bijgewerkt.

| # | Antwoord |
| --- | --- |
| 4 | Akkoord. OPF blijft voor boeken de primaire metadatawaarheid; geen externe boekenmetadata-provider in dit plan. |
| 11 | Akkoord. De goedkeuringssemantiek van 63 blijft leidend: één gezamenlijke ronde betekent niet automatisch goedkeuren als de review nog fouten vindt. |
| 13 | Akkoord. Geen aparte light-theme-northstars; wel contrasttests en visuele verificatie van representatieve schermen tijdens implementatie. |
| 14 | Akkoord. Voorkeursvolgorde: expliciete gebruikersinstelling, dan browsertaal, dan productfallback. |
| 15 | **Afwijking.** Readium TypeScript Toolkit als primaire webreader-engine, chromeless `@readium/navigator`-laag zodat Pleya zijn eigen UI houdt. Geen tweede engine als runtimefallback (divergentie in layout, locators, bookmarks, progress). Readium Web is een complementaire Go plus TypeScript-architectuur: de Go-kant biedt publicaties als manifest en resources aan. epub.js hooguit een gedocumenteerde contingency na een spike met aantoonbare blocker; foliate-js geen geplande fallback. |
| 16 | Akkoord. Native `<video>` voor direct play, hls.js waar MSE nodig is, native HLS waar de browser dat beter zelf doet. |
| 17 | Akkoord. 90 dagen absolute TTL, geen sliding expiry. Rotatie met overlap zodat een integratie zonder downtime van token wisselt. |
| 19 | **Afwijking.** HttpOnly-refreshcookie niet uitstellen: hoort in de authfundering vóór beheer via de webapp. Refreshcredential HttpOnly, Secure, passende SameSite, nooit leesbaar door JavaScript, accesstoken kortlevend in geheugen, refreshrotatie, Origin/CSRF-bescherming waar de topologie dat vereist. Samen met 57 oplossen of web en server same-origin zijn; geen ontwerp dat leunt op third-party cookies tussen web.pleya.app en willekeurige Pleya Server-origins. |
| 22 | Akkoord. Iedere MCP-read door exact dezelfde user-, library- en itemautorisatie; restricted is nooit serverbrede read-access. |
| 23 | **Afwijking.** Retentie 90 dagen akkoord, maar niet alleen mutaties. Minimaal: beheer- en datamutaties; login success en failure waar securityrelevant; token aanmaken, intrekken, roteren; permissie- en rolwijzigingen; maintenance-mode; MCP-mutaties; securitygevoelige configuratiewijzigingen. Catalogusreads, playbackticks en readerreads niet. |
| 24 | Akkoord. Bibliotheeknaam typen bij verwijderen; gebruiker verwijderen en sleutelrotatie met expliciete impact-confirmatie. Mediafiles worden bij library-delete nooit stilzwijgend van storage verwijderd. |
| 25 | Akkoord. Admin kan de owner niet wijzigen en niet via de normale admin-API verwijderen. Owner recovery of transfer is een aparte lokale recoveryprocedure met hogere trust dan een adminsessie. |
| 26 | **Afwijking.** Geen CFI plus spine-index plus fractie als bindend contract. Canoniek is een Readium-compatible Locator: href; resource type; progression binnen resource; totalProgression; position waar beschikbaar; optionele partialCfi/CFI; optionele tekstcontext voor bookmarks en highlights; publication- of media-revision of digest naast de locator zodat hij niet blind op een vervangen EPUB wordt toegepast. Spine-index mag afgeleide of fallback-informatie zijn, niet de primaire identiteit. |
| 27 | **Afwijking.** Niet één ladder. Poster en boekcover: 240, 480, 960, 1920. Backdrop en hero: 480, 960, 1920, 3840. Alleen on-demand, nooit boven bronresolutie upscalen; `width` normaliseert naar een ladderwaarde. 3840 is nodig voor 4K en tvOS. |
| 29 | **Afwijking.** Genres vrije tekst, maar facetten niet hoofdlettergevoelig: bewaar originele displaynaam en een genormaliseerde facetkey (Unicode casefold, trim, whitespace-normalisatie). |
| 31 | Akkoord. Onbeperkt, efficiënt geïndexeerd, per gebruiker volledig of selectief wisbaar. |
| 32 | Akkoord. Persoonlijke `user_rating` gescheiden van provider-rating uit TMDB. |
| 34 | **Afwijking.** Geen uitsluitend trigram. PostgreSQL met exacte en prefixmatches, Full Text Search, `pg_trgm` voor fuzzy, één deterministische ranking, over titel, serie, acteur, auteur. Geen embeddings, geen semantisch zoeken. |
| 35 | **Afwijking.** `feature_level` 1 is de verwachte uitkomst, geen onaantastbare regel. Aan het eind van de protocol-diff: volledig additief betekent level 1; één werkelijk brekende wijziging betekent passend verhogen. Geen breaking change verbergen om op level 1 te blijven. |
| 36 | Akkoord. Vóór authenticatie geen eventdata; bij een gedetecteerd gat moet de client state opnieuw kunnen synchroniseren. |
| 37 | **Afwijking.** VAAPI, QSV én NVENC als first-class backends in dit plan; NVENC niet later. Runtime capability detection; geen aanname dat Intel aanwezig is. Voorkeur: passende hardware-encoder voor bron en doelcodec, dan software. AMD op Linux via VAAPI. |
| 38 | Akkoord. Nooit upscalen; 4K bij voorkeur direct play, anders gecontroleerd terugvallen naar 1080p in plaats van een verplichte 4K-transcode. |
| 39 | **Afwijking.** 2 en 20 GB zijn defaults, serverconfigureerbaar binnen veilige grenzen. Cachebeheer beschermt actieve sessies en ruimt oude of inactieve artifacts onder druk op. |
| 40 | **Afwijking.** Bitmap (PGS, VobSub/DVD en andere ondersteunde bitmaptracks): burn-in bij transcode. Gewone tekst: WebVTT. ASS/SSA met styling die niet betrouwbaar naar WebVTT kan: burn-in. |
| 41 | Akkoord. Heartbeatinterval korter dan de time-out; na 60 s zonder geldige heartbeat verlopen. |
| 42 | Akkoord. Digest is een cryptografische contentdigest, bij voorkeur SHA-256, over exact de bytes van het artifact. |
| 43 | Akkoord. Geen half-af offline-video of PWA. |
| 44 | Akkoord. TMDB de enige geïmplementeerde provider, achter een providerinterface; database en domeinmodel niet TMDB-specifiek. |
| 45 | Akkoord. Servergebonden secret, gemaskeerd na opslaan, nooit teruggeleverd via de API. |
| 46 | Akkoord. Exacte externe id koppelt direct; genormaliseerde titel plus jaar alleen automatisch als mediatype klopt en het resultaat ondubbelzinnig is; anders reviewlijst. |
| 48 | **Afwijking.** Artwork-type-aware selectie. Poster en cover: nl, taalneutraal, en, dan kwaliteit, votes, aspect. Backdrop en hero: taalneutraal, nl, en, dan kwaliteit, votes, aspect. Handmatig gekozen artwork wordt gepind en nooit overschreven. |
| 49 | **Afwijking.** Precedence: handmatige of gepinde override, dan sidecar, dan provider, dan technisch uit het bestand afgeleide fallback. Sidecar overschrijft nooit een expliciete beheerdercorrectie. |
| 52 | Akkoord. Providerronde na een scan alleen voor nieuwe, gewijzigde, unmatched of expliciet dirty items; volledig verversen is een expliciete beheeractie. |
| 53 | **Afwijking.** Beheer niet beperken tot match en artwork. Per-field overrides voor titel, sorteertitel, jaar, beschrijving, genres, releasedatum en overige presentatievelden. Iedere override toont bron en provenance, is expliciet handmatig, kan terug naar "gebruik sidecar/provider", en wordt niet door scans overschreven. Bevestigen, afwijzen, fix-match en artwork kiezen blijven daarnaast. |
| 54 | **Afwijking.** Defaults, geen constanten: target configureerbaar (default `/backups`), dagelijks 03:30, 14 bewaard; back-up bevat database plus instance-, config- en cryptografische state; secrets veilig verpakt; waarschuwing als het doel op hetzelfde failure-domain staat; off-host of NAS-mounted target ondersteund; wekelijkse automatische restore in een geïsoleerde tijdelijke database die migraties, schema en kernqueries werkelijk test. |
| 55 | Akkoord. Nieuwe streams en scans geweigerd, bestaande workers gecontroleerd gestopt, authsessies blijven geldig. |
| 56 | **Afwijking.** Prometheus standaard op loopback maar niet hardcoded op 127.0.0.1: configureerbare private bind, nooit publiek standaard, trusted-network en container-network deployment expliciet ondersteund. |
| 57 | **Afwijking.** Canonieke Pleya Web-origin en de externe base-URL van déze server zijn twee concepten. Apart vastleggen: canonical web origin (eventueel web.pleya.app); external/base URL van de server; trusted proxy CIDR's; Forwarded en X-Forwarded-* alleen van trusted proxies; CORS- en originbeleid. Vanwege 19: geen afhankelijkheid van third-party refreshcookies; voorkeur same-origin web en server, of een expliciet ontworpen BFF- of auth-flow. |
| 58 | Akkoord. Vanaf de dan gestabiliseerde actuele `main`; niet vroeg aftakken en drift verzamelen. |
| 59 | **Afwijking.** Geen harde toezegging op 096. Bij integratie: samengestelde boom bepalen, hoogste geldige DEC inventariseren, hernummeren naar de eerstvolgende vrije reeks, alle verwijzingen atomair aanpassen. |
| 61 | **Afwijking.** NAS-data als stagingdataset, niet als mutable testomgeving: geïsoleerde stagingdatabase, dump of snapshot vooraf, media read-only of via snapshot, afzonderlijke config en secrets, geen test die productie-media kan verwijderen of verplaatsen, destructieve journeys alleen tegen disposable stagingstate. |
| 62 | **Afwijking.** Twee TestFlight-gates: einde S14 (eerste geïntegreerde contractvalidatie) en na de definitieve geïntegreerde serverboom, vóór release, tegen exact de releasecandidate. |
| 63 | Akkoord. CANDIDATE, review, expliciet akkoord, APPROVED, dan SHA256SUMS. |
| 64 | Akkoord. Het masterplan staat niet boven een later expliciet besluit van Michel; zo'n besluit wordt eerst als afwijking of DEC vastgelegd, daarna worden plan en masterlijst bijgewerkt. |

## 9. Verwerking in de delen (nog te doen, eerste stap van de volgende sessie)

| Afwijking | Raakt | Wat verandert |
| --- | --- | --- |
| 15, 26 | E (RB-4, RB-12), H, I (S6, S12), J (0013, venster 4) | Readium Locator als `reading_states.locator`; Go-kant levert Readium Web Publication Manifest en resources (`GET /ebooks/{id}/manifest`, `/ebooks/{id}/resources/{path}`); webreader op `@readium/navigator`; spike vóór S12 |
| 19, 57 | E (nieuw RB), I (S1), J (venster 1), K (7, 8, 20), F | refreshcookie HttpOnly in S1; `Server.web_origin` en `external_url` apart; CORS-beleid; trusted proxies; same-origin als voorkeur, BFF-flow als de web-origin afwijkt |
| 23 | E (RB-20), J (0008b), K (22) | auditscope uitgebreid met logins, tokens, rollen, maintenance, securityconfig |
| 27 | E (RB-7), F, J | twee ladders; 3840 voor backdrops; nooit upscalen |
| 29 | E (RB-5), J (0011, facetten) | `genres_key` genormaliseerd naast displaynaam |
| 34 | E (RB-5), I (S5), J (0012) | FTS plus trigram plus prefix, één ranking over titel, serie, acteur, auteur |
| 35 | E (RB-9), J.1 | regel: level volgt de diff, niet andersom |
| 37, 39, 40 | E (RB-21), I (S18), J (settings) | drie hwaccel-backends met runtime-detectie; limieten als instellingen met grenzen; ondertitelmatrix |
| 48, 49, 53 | E (RB-27), I (S22), J (0017, venster 8), D (mockup metadata) | artwork-type-aware selectie met pin; precedence met override bovenaan; per-field overrides met provenance en reset |
| 54, 56 | E (RB-26, RB-28), I (S24, S25), J (0019, settings) | back-updoel, schema en retentie als instellingen; failure-domain-waarschuwing; metrics-bind configureerbaar |
| 59 | M.1, N.2 | hernummering tegen de dan geldende boom |
| 61 | L.5, N.5 | geïsoleerde staging: eigen database, media read-only, geen productiemutatie |
| 62 | N.5, O.2, masterlijst S15 | tweede TestFlight-gate vóór release |
