# Pleya Server: replacement matrix

**Status:** levend document, hoort bij de goedgekeurde architectuurbaseline in
[docs/pleya-server-architecture.md](pleya-server-architecture.md).
**Datum:** 19 augustus 2026, bijgewerkt bij het sluiten van PS-2 en PS-3W
**Auteur:** Michel Knoop

Dit document beantwoordt één vraag:

> **Wat moet er aanwezig zijn voordat een Pleya-gebruiker Plex Media Server werkelijk kan
> uitschakelen?**

Het is geen tweede architectuurdocument. Waar een capability ontwerpuitleg vraagt, staat hier een
verwijzing naar het hoofdstuk dat hem beschrijft en niet een herhaling ervan. Wat hier wél staat is
de volledige lijst serververantwoordelijkheden die Pleya vandaag bij Plex afneemt, met per stuk een
bestemming, een fase, een status en een oordeel of hij de Plex-off gate blokkeert.

---

## Inhoud

1. [North star](#1-north-star)
2. [Wat een Plex-off blocker is](#2-wat-een-plex-off-blocker-is)
3. [Drie bestemmingen, en geen vierde](#3-drie-bestemmingen-en-geen-vierde)
4. [Statussen](#4-statussen)
5. [De matrix](#5-de-matrix)
6. [Roadmapmapping per fase](#6-roadmapmapping-per-fase)
7. [Roadmap gaps](#7-roadmap-gaps)
8. [Open productbesluiten](#8-open-productbesluiten)
9. [De Plex-off acceptance gate](#9-de-plex-off-acceptance-gate)
10. [Hoe dit document wordt bijgehouden](#10-hoe-dit-document-wordt-bijgehouden)

---

## 1. North star

Pleya Server is geen aanvullende backend, geen beperkte homeserver en geen technisch experiment
naast Plex. Het einddoel is een zelfstandig mediaserverproduct waarmee een Pleya-gebruiker Plex
Media Server kan uitschakelen zonder voor de afgesproken Pleya-productscope afhankelijk te blijven
van Plex voor bibliotheekbeheer, metadata, afspelen, transcoding, gebruikers, kijkstatus, gebruik
buiten huis, downloads of dagelijks serverbeheer.

De roadmap is incrementeel. Daaruit volgt de regel die dit hele document draagt:

> **"Niet in deze fase" is iets anders dan "niet nodig voor het eindproduct".**

Een functie verdwijnt niet uit het eindproduct omdat hij nog geen Phase ID heeft. Een capability die
hier op `Roadmap gap` staat is geen geschrapte functie maar een functie zonder plek, en dat is een
bevinding die om een besluit vraagt.

Plex en Jellyfin blijven optionele adapters. "Plex vervangen" betekent dat Pleya Plex niet meer
nodig heeft, niet dat Plex-ondersteuning verdwijnt. Pleya Share blijft een apart product met een
eigen levensduur en vertrouwensmodel; zie
[hoofdstuk 2 van de architectuur](pleya-server-architecture.md#2-de-grens-tussen-pleya-share-en-pleya-server).

---

## 2. Wat een Plex-off blocker is

Een capability is een blocker wanneer een normaal huishouden hem bij dagelijks gebruik mist zodra de
Plex-container stopt. Dat is de enige toets.

Wat een capability **niet** tot blocker maakt: dat hij technisch lastig is, dat hij in geen enkele
fase staat, of dat hij bij Plex een betaalde functie was. Wat hem **niet uitsluit**: dat hij zelden
gebruikt wordt, zolang het ontbreken ervan dagelijks gebruik onmogelijk of pijnlijk maakt.

Twee capabilities kunnen dezelfde functionaliteit dekken op verschillend niveau, en dat verschil
telt. Een scanner die media indexeert is een technische capability. Een beheerder die een
bibliotheek toevoegt, een scan start, de voortgang ziet en een fout begrijpt zonder de database of
een SSH-sessie aan te raken, is dezelfde capability op productniveau. **Voor de gate telt een
capability pas als productgereed wanneer dagelijks gebruik dat niveau vraagt.**

---

## 3. Drie bestemmingen, en geen vierde

Voor iedere Plex-verantwoordelijkheid bestaat uiteindelijk precies één van drie besluiten.

| Code | Bestemming | Betekenis |
| --- | --- | --- |
| **A** | Eigen Pleya-equivalent | Pleya Server levert zelfstandig dezelfde productwaarde. |
| **B** | Bewust anders opgelost | Het gebruikersprobleem blijft opgelost, maar Pleya kiest een andere architectuur of UX. |
| **C** | Bewust buiten productscope | De functie hoort aantoonbaar niet bij Pleya's mediaserverproduct, en dat besluit staat hier vastgelegd. |

Een capability belandt nooit in **C** omdat hij moeilijk is of omdat hij niet in de eerste roadmap
stond. **C** vraagt een expliciet besluit met een reden. Zolang dat besluit er niet is, staat er
`Productbesluit nodig` en telt de capability mee in
[hoofdstuk 8](#8-open-productbesluiten).

---

## 4. Statussen

| Status | Betekenis |
| --- | --- |
| `Niet ontworpen` | Niemand heeft er een ontwerp voor. |
| `Ontworpen` | De architectuur beschrijft hem, maar geen fase levert hem op. |
| `In roadmap` | Een fase draagt hem met scope en acceptatiecriteria. |
| `In uitvoering` | De fase loopt. |
| `Technisch gereed` | Het endpoint of mechanisme werkt en is getest. |
| `Productgereed` | Een gebruiker of beheerder kan hem bedienen zonder database, logbestand of SSH. |
| `Bewust buiten scope` | Besluit **C**, met reden. |

`Technisch gereed` en `Productgereed` zijn met opzet twee statussen. Een scanner die werkt maar
alleen via `docker exec` te starten is technisch gereed en productoneigenlijk, en het verschil
verdwijnt zodra beide "af" heten.

---

## 5. De matrix

Kolommen: wat Pleya vandaag bij Plex haalt, wat Pleya Server ervoor in de plaats zet met de
bestemming ertussen haakjes, de fase die hem levert, de status, of hij de Plex-off gate blokkeert, en
waaraan je ziet dat hij klaar is.

### 5.1 Bibliotheek, identiteit en scanner

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Bibliotheken ontdekken en tonen | `GET /media/providers`, oude servers `GET /library/sections` | (A) eigen bibliotheeklijst in het protocol | PS-1, PS-2, PS-3 | In roadmap | ja | PS-3 criterium 1: verbinding toevoegen toont bibliotheken |
| Bibliotheekinhoud pagineren | `/library/sections/{id}/all` met `X-Plex-Container-Start/Size` | (A) cursorpaginatie, [12.7](pleya-server-architecture.md#127-pagination) | PS-1, PS-2, PS-3 | In roadmap | ja | schemavalidatie plus een bibliotheek van 1000 items |
| Item, versie en bestand als drie dingen | `Media[]` en `Part[]` op de metadata | (A) [7.1](pleya-server-architecture.md#71-identiteit-los-van-locatie) | PS-2 | Technisch gereed | nee | twee versies van één film leveren één item |
| Edities onderscheiden | `editionTitle`, Plex-only veld | (A) veld op de versie | PS-2 | Technisch gereed | nee | een Director's Cut naast de bioscoopversie blijft herkenbaar |
| Technische eigenschappen per bestand | Plex-analyse plus `includeStreams=1` | (A) ffprobe met `detectionStatus` en `source`, [7.4](pleya-server-architecture.md#74-wat-ffprobe-wel-en-niet-betrouwbaar-zegt) | PS-2 | Technisch gereed | nee | PS-2 criterium 1 |
| Verandersdetectie bij herscan | Plex-scanner | (A) drie lagen, [7.3](pleya-server-architecture.md#73-wat-de-scanner-elke-ronde-doet) | PS-2 | Technisch gereed | nee | PS-2 criterium 2: tweede scan draait ffprobe nul keer |
| Hernoemen en verplaatsen zonder identiteitsverlies | Plex maakt hier een dubbele entry | (A) inode, plus scan-signature tussen mounts | PS-2 | Technisch gereed | ja | PS-2 criterium 3; poort 4 is dicht en de signature draagt geen `ETag`-belofte meer (DEC-050) |
| Bibliotheek toevoegen en verwijderen | Plex Web, niet vanuit Pleya | (A) beheerscherm in de client | geen | **Roadmap gap** | ja | een nieuwe bibliotheek is zonder SSH aan te maken |
| Scan starten vanuit de client | `GET /library/sections/{id}/refresh` | (A) beheer-endpoint plus knop | PS-11 deels | **Roadmap gap** | ja | scan start en de voortgang is zichtbaar |
| Metadata forceren te verversen | `GET /library/sections/{id}/refresh?force=1` | (A) job opnieuw inplannen | PS-7, PS-11 | **Roadmap gap** | ja | een verkeerd gematchte titel is opnieuw te laten ophalen |
| Lopende serverklussen zien | `GET /activities`, `DELETE /activities/{uuid}` | (A) jobstatus plus scanvoortgang | PS-11 deels | **Roadmap gap** | ja | beheerder ziet wat er draait en kan het afbreken |
| Media analyseren als losse actie | `GET /library/sections/{id}/analyze` | (B) valt samen met de scanner: analyse gebeurt bij binnenkomst en bij wijziging | PS-2 | Technisch gereed | nee | geen aparte knop nodig |
| Prullenbak legen | `PUT /library/sections/{id}/emptyTrash` | (B) een verdwenen bestand verdwijnt bij de volgende scan, want mounts zijn read-only | PS-2 | Technisch gereed | nee | een verwijderd bestand valt binnen één scanronde uit de catalogus |
| Item plus bestanden verwijderen | `DELETE /library/metadata/{id}` | (C) read-only mounts vanaf v1, [16.2](pleya-server-architecture.md#162-dreigingen-en-antwoorden) | n.v.t. | Bewust buiten scope | nee | opruimen gebeurt op het bestandssysteem |
| Mappenhiërarchie bladeren | `GET /library/sections/{id}/folder` | (A) mapweergave uit `storage_locations` | geen | **Roadmap gap** | nee | `folderGrouping` werkt ook op Pleya Server |

### 5.2 Metadata en artwork

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Titel, samenvatting, jaar, genres, studio, kijkwijzer | Plex-agents | (A) TMDB via de kandidatenlaag, [8.2](pleya-server-architecture.md#82-providers-schrijven-nooit-op-het-canonieke-record) | PS-7 | In roadmap | ja | PS-7 criterium 1 |
| Cast en crew, plus doorklikken naar een persoon | `Role[]`, `GET /library/people/{id}/media` | (A) `people` en `item_people` | PS-7 | In roadmap | ja | een acteurpagina toont titels uit de eigen catalogus |
| Beoordelingen (critici, publiek, bronlogo) | `rating`, `audienceRating`, `ratingImage` | (A) providerveld op het canonieke record | PS-7 | **Roadmap gap** | ja | de beoordelingschip op het detailscherm blijft gevuld |
| Externe ids (imdb, tmdb, tvdb) | `includeGuids=1` | (A) `external_ids`, [DEC-032](pleya-server-architecture.md#24-voorgestelde-dec-besluiten-en-open-vragen) | PS-7 | In roadmap | ja | Trakt-synchronisatie en dubbeldetectie blijven werken |
| Posters, achtergronden, clearLogo, vierkante art | Plex `Image[]` | (A) artwork met content-hash, [8.4](pleya-server-architecture.md#84-artwork) | PS-7 | In roadmap | ja | PS-7 stopcriterium |
| Artwork schalen en cachen | `GET /photo/:/transcode?width=&height=` | (A) afgeleide formaten op aanvraag met sterke `ETag` | PS-7 | In roadmap | ja | een posterraster laadt zonder de originelen te trekken |
| Matchen met ambiguïteitsregel | Plex-agents | (A) driestapsmatch, [19.1](pleya-server-architecture.md#191-het-matchpatroon-bestaat-al) | PS-7 | In roadmap | ja | PS-7 criterium 1: ambigue titels op een lijst |
| Handmatige correctie die blijft staan | Plex field locks | (A) correctie wint van elke providerronde | PS-7 | In roadmap | ja | PS-7 criterium 2: overleeft drie rondes |
| Metadatavelden bewerken in de client | `PUT /library/sections/{id}/all` met `{veld}.value` en `.locked` | Productbesluit nodig; PS-7 zet dit expliciet buiten scope | geen | **Productbesluit nodig** | ja | zie [8](#8-open-productbesluiten) |
| Match corrigeren en losmaken | `/matches`, `PUT /match`, `PUT /unmatch` | Productbesluit nodig | geen | **Productbesluit nodig** | ja | zie [8](#8-open-productbesluiten) |
| Artwork kiezen of uploaden | `/posters`, `/arts`, `PUT` met binaire body | Productbesluit nodig; uploads bestaan niet in v1 | geen | **Productbesluit nodig** | nee | zie [8](#8-open-productbesluiten) |
| Bronvermelding tonen | Plex regelt dit zelf | (A) TMDB-attributie zichtbaar, [8.3](pleya-server-architecture.md#83-attributie-is-een-productvereiste) | PS-7 | In roadmap | ja | PS-7 criterium 4 |

### 5.3 Bladeren en ontdekken

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Home-rijen | `GET /hubs/promoted`, `GET /hubs` | (B) de bestaande client-side aanbevelingsmotor (`lib/services/recommendations/`) bouwt de rijen; de server levert de bouwstenen | PS-3, PS-7 | In roadmap | ja | het homescherm is gevuld zonder Plex-hubs |
| Recent toegevoegd | `GET /library/recentlyAdded` | (A) sorteren op `added_at` | PS-3 | In roadmap | ja | de rij vult zich na een scan |
| Recent toegevoegde series op serieniveau | `GET /library/all?type=2&sort=addedAt:desc` | (A) zelfde query op itemtype | PS-3 | In roadmap | nee | de serie staat er, niet de losse aflevering |
| Verder kijken | provider-key of `GET /hubs?identifier=home.continue` | (A) afgeleid uit kijkstatus | PS-4 | Technisch gereed | ja | PS-4 criterium 3; de hub leest de kijkstatus die PS-4 schrijft |
| Recent bekeken | `GET /library/all?sort=lastViewedAt:desc` | (A) afgeleid uit kijkstatus | PS-4 | Technisch gereed | nee | `fetchRecentlyWatched` leest `GET /watch-state` en houdt de uitgekeken titels over |
| Volgende aflevering bij een serie | `includeOnDeck=1` op de metadata | (A) uit kijkstatus plus afleveringsvolgorde | PS-4 | In roadmap | ja | detailscherm toont de juiste volgende aflevering |
| Nieuwe afleveringen (hub) | `GET /hubs?identifier=home.nextup` | (A) uit kijkstatus plus afleveringsvolgorde, normatief in specificatie 15 | PS-4 | Technisch gereed | ja | de `next_up`-hub levert per begonnen serie precies de volgende aflevering |
| Verwante titels | `GET /hubs/metadata/{id}/related` | (A) uit genres, mensen en verzamelingen | PS-7 | **Roadmap gap** | nee | de "meer zoals dit"-rij is gevuld |
| Sorteeropties per bibliotheek | `GET /library/sections/{id}/sorts` | (A) vaste lijst per bibliotheektype in het protocol | PS-1, PS-3 | In roadmap | ja | de sorteersheet is niet leeg |
| Filtercategorieën en filterwaarden | `GET /library/sections/{id}/filters` | (A) categorieën uit de catalogus | geen | **Roadmap gap** | ja | filteren op genre en jaar werkt |
| Alfabetische sprongbalk met echte offsets | `GET /library/sections/{id}/firstCharacter` | (A) telling per beginletter | geen | **Roadmap gap** | nee | de balk springt naar de juiste positie in plaats van te filteren |
| Extra's en trailers | `GET /library/metadata/{id}/extras` | Productbesluit nodig | geen | **Productbesluit nodig** | nee | zie [8](#8-open-productbesluiten) |

### 5.4 Zoeken en identiteit

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Vrije tekst zoeken op een server | `GET /library/search?query=` | (A) zoekendpoint in het protocol | PS-1, PS-3 | In roadmap | ja | PS-3 criterium 2 |
| Zoeken over meerdere servers tegelijk | client-side fan-out in `data_aggregation_service` | (A) blijft client-side, backend-blind | PS-3 | In roadmap | ja | PS-3 criterium 2 zonder backendcheck |
| Titel opzoeken op externe id | `GET /library/all?guid=plex://…` | (A) opzoeken in `external_ids` | PS-7 | In roadmap | ja | kijklijstbeschikbaarheid en dubbeldetectie blijven werken |
| Zoekresultaten volgen rechten | Plex sharing | (A) onzichtbaar bestaat niet, [13.1](pleya-server-architecture.md#131-het-model) | PS-9 | In roadmap | ja | PS-9 criterium 2 |

### 5.5 Verzamelingen en afspeellijsten

Dit hele domein komt in geen enkele fase voor, terwijl de client er vandaag volledige lees- en
schrijfondersteuning voor heeft.

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Verzamelingen lezen en doorbladeren | `GET /library/sections/{id}/collections`, `/library/collections/{id}/children` | (A) eigen resource | geen | **Roadmap gap** | ja | het tabblad Verzamelingen is gevuld |
| Verzameling maken, vullen, opschonen, verwijderen | `POST`, `PUT`, `DELETE /library/collections` | (A) eigen schrijfoppervlak | geen | **Roadmap gap** | ja | een verzameling overleeft een herstart |
| Afspeellijsten lezen | `GET /playlists`, `/playlists/{id}/items` | (A) eigen resource | geen | **Roadmap gap** | ja | het tabblad Afspeellijsten is gevuld |
| Afspeellijst maken, vullen, verwijderen | `POST /playlists`, `PUT /playlists/{id}/items` | (A) eigen schrijfoppervlak | geen | **Roadmap gap** | ja | een afspeellijst overleeft een herstart |
| Afspeellijst herordenen | `PUT /playlists/{id}/items/{itemId}/move?after=` | (A) stabiele positie per item | geen | **Roadmap gap** | nee | slepen bewaart de volgorde |
| Slimme afspeellijsten en slimme verzamelingen | Plex `smart=1`, alleen lezen in de client | Productbesluit nodig | geen | **Productbesluit nodig** | nee | zie [8](#8-open-productbesluiten) |
| Serverzijdige afspeelwachtrij | `POST /playQueues` | (B) client-side wachtrij zoals bij Jellyfin, want de wachtrij hoort bij een kijksessie en niet bij de catalogus | PS-4 | Ontworpen | nee | volgende aflevering en wachtrijsheet werken zonder serverresource |

### 5.6 Afspeellevering

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Direct play met HTTP-range | directe part-URL met `X-Plex-Token` | (A) `GET /stream/{versionId}`, [11.1](pleya-server-architecture.md#111-direct-play-is-de-standaard-en-het-meeste-verkeer) | PS-4 | Technisch gereed | ja | PS-4 criterium 1; op de DS920+ gemeten, de app-ronde op drie vormfactoren staat nog open |
| Zwakke validator, en `If-Range` levert het hele bestand | Plex-`ETag` | (A) `W/"..."` uit bestandsmetadata plus `generation`, [DEC-050](DECISIONS.md) | PS-4 | Technisch gereed | nee | de belofte van byte-identiteit is bewust vervallen; een client plakt nergens bytes aan elkaar |
| Seeken in een direct-play-stream | range-request | (A) hele bestand seekbaar | PS-4 | Technisch gereed | ja | PS-4 criterium 2: 1 MB vanaf byte 1.469.339.787 in 164 ms op de DS920+ |
| Remux naar een speelbare container | `/video/:/transcode/universal/start` met `protocol=http&container=mkv` | (A) fMP4, HLS waar segmentatie nodig is | PS-8 | In roadmap | ja | PS-8 criterium 1 |
| Videotranscode | `universal/decision` plus `start` met `maxVideoBitrate` | (A) planner plus ffmpeg-supervisor | PS-6, PS-8 | In roadmap | ja | PS-8 test per `deliveryMode` |
| Audiotranscode en downmix | `directStreamAudio=0` op de transcode-URL | (A) gescheiden audiobesluit, [10.1](pleya-server-architecture.md#101-de-uitkomst-is-rijker-dan-een-enkel-woord) | PS-6, PS-8 | In roadmap | ja | tabelrij TrueHD Atmos naar stereo |
| Hardwareversnelling | Plex Pass-functie | (A) detectie bij opstarten, [11.5](pleya-server-architecture.md#115-hardwareversnelling) | PS-8 | In roadmap | ja | zichtbare servercapability plus metric |
| Sessie openen, levend houden en sluiten | bestaat niet in de client: `universal/stop` komt nul keer voor in `lib/` | (A) sessiecontract plus watchdog, [11.2](pleya-server-architecture.md#112-wanneer-er-wel-een-sessie-is) | PS-8 | In roadmap | ja | PS-8 criterium 2: geen verweesd ffmpeg-proces |
| Seekgrenzen als eigenschap van de stream | `backend == plex` in `seeking.dart:17-23` | (A) veld in het plan, [11.4](pleya-server-architecture.md#114-seek-is-een-eigenschap-van-de-stream) | PS-6 | In roadmap | ja | PS-8 criterium 3 |
| Gelijktijdige sessies begrenzen | Plex-transcoderinstelling | (A) configuratiewaarde met een duidelijke foutcode | PS-8 | In roadmap | ja | PS-8 criterium 4 |
| Externe speler starten (VLC, MX Player) | directe URL met token in de querystring | (A) kortlevend streamtoken, [12.5](pleya-server-architecture.md#125-de-auth-grens) | PS-4 | Technisch gereed | nee | `resolveExternalPlaybackUrl` levert de URL met streamtoken; met VLC zelf niet nagelopen |

### 5.7 Afspeelintelligentie

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Vaststellen wat het toestel aankan | hardgecodeerde constante op `plex_client.dart:3072-3110` | (A) `DeviceCapabilities`, [9](pleya-server-architecture.md#9-device-capabilities-in-de-client) | PS-5 | In roadmap | ja | PS-5 criterium 1 |
| Versiekeuze bij meerdere versies | de client kiest via `mediaIndex` | (A) de server kiest op capability-fit, [10.3](pleya-server-architecture.md#103-het-besluitpad) | PS-6 | In roadmap | ja | PS-6 criterium 2 |
| Uitleg waarom er getranscodeerd wordt | bestaat niet | (A) domeincode met parameters | PS-6 | In roadmap | ja | PS-6 criterium 3 |
| Bandbreedtebeleid, lokaal tegenover remote | `TranscodeQualityPreset`, handmatig | (A) verbindingslaag in het capabilitymodel | PS-5, PS-6 | In roadmap | ja | tabelrij 4K over 8 Mbit |
| HDR-, Dolby Vision- en Atmos-beleid | volledig client-side, bereikt de server nooit | (A) detectiestatus plus planner | PS-5, PS-6 | In roadmap | ja | tabelrijen HDR10 en DV-profiel 5 |
| Serverbelasting meewegen | Plex weegt dit intern mee | (A) aantal actieve sessies in de beslissing | PS-6, PS-8 | Ontworpen | nee | een volle server kiest een goedkoper plan of weigert netjes |

### 5.8 Sporen en hulpstukken

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Audiospoor kiezen | `audioStreamID` op de stream-URL, `PUT /library/parts/{id}` | (A) spoorkeuze in plan en sessie | PS-6, PS-8 | In roadmap | ja | wisselen van audiospoor werkt op elk pad |
| Ondertitelspoor kiezen (ingebed) | `subtitleStreamID` plus `subtitles=embedded` | (A) ondertitelbesluit in het plan | PS-6, PS-8 | In roadmap | ja | wisselen van ondertitel werkt op elk pad |
| Externe ondertitels als los bestand leveren | `{track.key}.srt?encoding=utf-8&X-Plex-Token=` | (A) sidecar-endpoint naast de stream | PS-2 | Technisch gereed | ja | het endpoint staat er sinds PS-2 en `verify-local.sh` levert er een los `.srt` mee |
| Ondertitels inbranden | `subtitles=burn` | (A) besluit in het plan, uitgevoerd in de sessie | PS-6, PS-8 | In roadmap | nee | een PGS-spoor op een toestel dat het niet rendert |
| Spoorkeuze onthouden per titel en gebruiker | `PUT /library/metadata/{id}/prefs` plus `selectStream` | (A) voorkeur per (gebruiker, item) | geen | **Roadmap gap** | ja | dezelfde serie start op elk toestel met dezelfde taalkeuze |
| Hoofdstukken | `includeChapters=1` | (A) uit ffprobe bij de scan | PS-2, PS-7 | **Roadmap gap** | nee | de hoofdstukkenlijst in de speler is gevuld |
| Scrubvoorbeelden bij de zoekbalk | `GET /library/parts/{id}/indexes/sd` (BIF) | Productbesluit nodig: zelf genereren kost schijfruimte en scantijd | geen | **Productbesluit nodig** | nee | zie [8](#8-open-productbesluiten) |
| Intro en aftiteling overslaan | `includeMarkers=1` | Productbesluit nodig: eigen detectie, of bewust anders | geen | **Roadmap gap** en **Productbesluit nodig** | ja | de knop Intro overslaan verschijnt op het juiste moment |
| Ondertitels zoeken en downloaden via de server | `GET /library/metadata/{id}/subtitles`, `PUT` om te kiezen | Productbesluit nodig: server-proxy of rechtstreeks vanuit de client | geen | **Productbesluit nodig** | nee | zie [8](#8-open-productbesluiten) |

### 5.9 Persoonlijke status

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Kijkvoortgang melden | `GET /:/timeline?state=&time=` | (A) gebeurtenis met `session_id`, `explicit_action` en `base_revision`, [13.2](pleya-server-architecture.md#132-de-server-is-de-bron-van-kijkstatus) | PS-4 | Technisch gereed | ja | PS-4 criterium 4; poort 3 is dicht met DEC-049 |
| Gekeken markeren | `GET /:/scrobble` | (A) `explicit_action: mark_watched` | PS-4 | Technisch gereed | ja | PS-4 criterium 4 |
| Niet-gekeken markeren | `GET /:/unscrobble` | (A) `explicit_action: mark_unwatched` | PS-4 | Technisch gereed | ja | PS-4 criterium 4 |
| Hervatten op een tweede toestel | `viewOffset` op de metadata | (A) gezaghebbende kijkstatus | PS-4 | Technisch gereed | ja | PS-4 criterium 3 op protocolniveau; op twee echte toestellen tegelijk nog niet gemeten |
| Uit Verder kijken halen zonder kijkstatus te wijzigen | `PUT /:/unscrobble?identifier=com.plexapp.plugins.library` | (A) aparte vlag naast de kijkstatus | geen | **Roadmap gap** | nee | de rij Verder kijken laat zich opruimen |
| Drempel voor uitgekeken | `GET /:/prefs`, `LibraryVideoPlayedThreshold` | (A) vaste 0,9 op server en client; instelbaar maken is PS-9P | PS-4 | Technisch gereed | nee | een aflevering telt als gekeken op dezelfde drempel als voorheen |
| Kijkgeschiedenis | `GET /status/sessions/history/all` | (A) `play_sessions` als geschiedenis | geen | **Roadmap gap** | ja | het geschiedenisoverzicht is gevuld na een kijksessie |
| Wie heeft dit gekeken | `GET /accounts` plus de geschiedenis | (A) geschiedenis per gebruiker binnen het huishouden | geen | **Roadmap gap** | nee | de rij Bekeken door toont de juiste namen |
| Favorieten | Jellyfin `FavoriteItems`; bij Plex is de kijklijst een accountfunctie in de cloud | (A) favoriet per (gebruiker, item) | geen | **Roadmap gap** | ja | een favoriet overleeft een profielwissel |
| Waardering geven | Plex `userRating` (0 tot 10) | (A) waardering per (gebruiker, item) | geen | **Roadmap gap** | nee | de sterrenschuif schrijft en leest |
| Offline gekeken materiaal terugsynchroniseren | `OfflineWatchSyncService` tegen `/:/timeline` | (A) dezelfde gebeurtenissen, met `backlog: true` | PS-4, PS-10 | Technisch gereed | ja | een backlog verwerft nooit eigendom en zet een nieuwere toestand niet terug (DEC-049, regel 6) |
| Conflicten tussen toestellen oplossen | Plex: de laatste melding wint | (A) server-authoritative eigendom met een lease en `base_revision`, [DEC-049](DECISIONS.md) | PS-4 | Technisch gereed | ja | het herstart-scenario uit 13.2 zet de kijker niet terug, en achttien tests dekken de zes regels |

### 5.10 Accounts en huishouden

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Eerste start en eigenaar aanmaken | Plex-account koppelen aan de server | (A) eenmalige setup-code op de console, [16.3](pleya-server-architecture.md#163-wachtwoorden-en-geheimen) | PS-2, PS-9 | In roadmap | ja | PS-9 criterium 4 |
| Gebruikers met rollen | Plex Home via plex.tv | (A) `users` met vier rollen | PS-9 | In roadmap | ja | PS-9 criterium 1 |
| Rechten per bibliotheek | Plex sharing | (A) `library_permissions`, onzichtbaar levert `404` | PS-9 | In roadmap | ja | PS-9 criterium 2 |
| Profiel wisselen met pincode | `POST /home/users/{uuid}/switch` op plex.tv | (A) eigen credential-resolver, [4.1](pleya-server-architecture.md#41-profielen-kennen-alleen-plex-home) | PS-9 | In roadmap | ja | PS-9 criterium 1 en 5 |
| Sessie per toestel intrekken | apparaatbeheer op plex.tv | (A) intrekbare sessies, ook voor een lopende stream | PS-9 | In roadmap | ja | PS-9 criterium 3 |
| Kijkstatus per gebruiker | per Plex-account | (A) kijkstatus aan een gebruiker in plaats van aan de server | PS-9 | In roadmap | ja | PS-9 criterium 1 |
| Wachtwoorden veilig bewaren | plex.tv doet dit | (A) Argon2id met parameters in de configuratie | PS-9 | In roadmap | ja | geen defaultwachtwoord, geen ingebouwd account |
| Clientinstellingen (thema, ondertitelstijl, sneltoetsen) | client-side, `SharedPreferences` plus iCloud-synchronisatie | (C) blijft client-side, dit is geen serververantwoordelijkheid | n.v.t. | Bewust buiten scope | nee | instellingen exporteren en importeren blijft werken zoals nu |
| Gedeelde bibliotheken tussen huishoudens | Plex sharing met vrienden | (C) [13.3](pleya-server-architecture.md#133-wat-expliciet-niet-in-v1-zit) | n.v.t. | Bewust buiten scope | nee | het rechtenmodel laat het toe, v1 bouwt het niet |

### 5.11 Remote toegang

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Bereikbaar buiten het eigen netwerk | `plex.direct` plus Plex-relay via plex.tv | (B) omgekeerde proxy, tunnel of mesh-VPN, [15](pleya-server-architecture.md#15-remote-access) | PS-11 | In roadmap | ja | PS-11 stopcriterium |
| HTTPS met een geldig certificaat | Plex geeft `plex.direct`-certificaten uit | (B) de proxy regelt het, niet de binary | PS-11 | In roadmap | ja | remote sessie zonder certificaatwaarschuwing |
| Verbindingskandidaten en endpoint-failover | `GET /resources?includeRelay=1` levert lokaal, remote en relay | (B) één endpoint per verbinding, zoals bij Jellyfin | PS-3 | Ontworpen | nee | een verbinding werkt binnen en buiten huis op hetzelfde adres |
| Range-verkeer door een proxy zonder buffering | Plex regelt dit | (A) getest door twee proxy-opstellingen | PS-11 | In roadmap | ja | PS-11 criterium 1 |
| Tokens in stream-URL's | `X-Plex-Token` in vrijwel elke URL, langlevend | (A) kortlevend streamtoken, gebonden aan gebruiker en resource | PS-1, PS-4 | In roadmap | ja | een gelekt streamtoken geeft geen toegang tot de API |
| Inlogpogingen afremmen | plex.tv doet dit | (A) rate limiting per account en per bron-IP | PS-11 | In roadmap | ja | PS-11 criterium 4 |
| Proxy-headers vertrouwen op de juiste plek | Plex regelt dit | (A) alleen van geconfigureerde proxy-adressen | PS-11 | In roadmap | ja | de logs tonen het echte client-IP |

### 5.12 Downloads en offline

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Bestand downloaden voor offline gebruik | `resolveDownload` levert de directe part-URL | (A) downloadoppervlak op het protocol | PS-10 | In roadmap | ja | PS-10 criterium 1 |
| Een versie kiezen die op het doeltoestel past | de client kiest zelf een `mediaIndex` | (A) de server kiest op capabilities | PS-10 | In roadmap | ja | een 4K-bron levert op een telefoon niet automatisch 4K |
| Vooraf getranscodeerde offline kopie | Plex Sync (`serverSideSync`) | (A) optioneel, op basis van hetzelfde plan | PS-10 | In roadmap | nee | een HEVC-bron is offline speelbaar op een toestel zonder HEVC |
| Ondertitel-sidecars meenemen | `buildExternalSubtitleUrl` per spoor | (A) sidecars in de downloadresolutie | PS-10 | In roadmap | ja | een offline film toont zijn ondertitels |
| Offline kijkstatus terugsturen | `OfflineWatchSyncService` | (A) gebeurtenissen in de wachtrij | PS-10 | In roadmap | ja | PS-10 criterium 2 |
| Downloads scheiden per gebruiker | `clientScopeId`, vandaag nullable | (A) expliciet paar (server, gebruiker), [4.4](pleya-server-architecture.md#44-cachescope-neemt-de-server-als-eenheid) | PS-9, PS-10 | In roadmap | ja | twee gebruikers zien elkaars downloads niet |
| Syncregels en automatische downloads | Plex Sync-regels | (C) PS-10 zet dit expliciet buiten scope; de bestaande client-side syncregels blijven | n.v.t. | Bewust buiten scope | nee | PS-10 drift check |

### 5.13 Serverbeheer en levenscyclus

Dit domein is het minst zichtbaar in de client en daarmee het makkelijkst te vergeten. Een
mediaserver is niet volwaardig omdat een film op het gelukkige pad afspeelt.

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Eerste installatie | installer plus webwizard | (A) container plus setup-code | PS-2, PS-11 | Deels in roadmap | ja | een nieuwe server draait zonder handmatige SQL |
| Bibliotheek toevoegen en verwijderen | Plex Web | (A) beheerscherm in de client | geen | **Roadmap gap** | ja | zie 5.1 |
| Scan starten en de voortgang volgen | `refresh` plus `/activities` | (A) beheer-endpoint plus voortgang | PS-11 deels | **Roadmap gap** | ja | zie 5.1 |
| Scanfouten begrijpen zonder logs | Plex Web toont ze | (A) foutlijst in het beheerdersoverzicht | PS-11 | In roadmap | ja | PS-11 stopcriterium |
| Actieve sessies zien | `GET /status/sessions` | (A) beheerdersoverzicht | PS-11 | In roadmap | nee | het overzicht toont een lopende sessie |
| Een sessie beëindigen | Plex-beheerfunctie | (A) sessie intrekken | geen | **Roadmap gap** | nee | een vastgelopen stream is af te breken |
| Opslagstatus zien | Plex Web | (A) vrije ruimte per `storage_location` | geen | **Roadmap gap** | nee | een volle schijf is zichtbaar voordat hij vol is |
| Databasemigraties bij het opstarten | Plex intern | (A) voorwaartse migraties, [17.3](pleya-server-architecture.md#173-migraties) | PS-2 | Technisch gereed | nee | PS-2 criterium 5 |
| Back-up maken | Plex-datamap kopiëren | (A) opdracht of knop met een controleerbare uitkomst | geen | **Roadmap gap** | ja | een back-up is terug te zetten op een lege server |
| Back-up terugzetten | datamap terugplaatsen | (A) restoreprocedure | geen | **Roadmap gap** | ja | catalogus en kijkstatus komen ongeschonden terug |
| Upgraden | Plex-updater | (A) image bumpen, migratie bij opstart | PS-11 deels | **Roadmap gap** | ja | een upgrade over twee schemaversies slaagt |
| Terugrollen | oudere Plex installeren | (A) terug naar de back-up; neerwaartse migraties bestaan bewust niet | geen | **Roadmap gap** | ja | de binary weigert te starten op een nieuwere database |
| Liveness en readiness | Plex kent dit niet | (A) `/healthz` en `/readyz` | PS-11 | In roadmap | ja | PS-2 criterium 5 |
| Metrics | Plex kent dit niet | (A) Prometheus op loopback | PS-11 | In roadmap | nee | PS-11 criterium 3 |
| Logs exporteren voor support | Plex Web | (A) gestructureerde logs met correlatie-id | PS-11 | Ontworpen | nee | een trage start is te herleiden tot één aanvraag |
| Hardware-capabilities detecteren | Plex toont transcoderinformatie | (A) detectie bij opstarten als servercapability | PS-8 | In roadmap | nee | zichtbaar of hardwareversnelling actief is |
| Gedrag bij volle schijf, database weg, transcode-crash of kapot bestand | Plex varieert per geval | (A) expliciete foutcodes per domein, [12.6](pleya-server-architecture.md#126-foutmodel) | verspreid | **Roadmap gap** | ja | geen enkele fase dekt de faalpaden als samenhangend geheel |

### 5.14 Realtime

Hoofdstuk 14 van de architectuur beschrijft een websocket-hub. PS-2 zet hem expliciet buiten scope,
PS-11 gaat ervan uit dat hij bestaat ("websockets door de proxy"), en geen enkele fase bouwt hem.

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Websocket-hub met volgnummers | de app gebruikt Plex' eventsource niet | (A) [14](pleya-server-architecture.md#14-realtime-en-push) | geen | **Roadmap gap** | nee | een client die kort weg was ziet dat hij iets heeft gemist |
| Scanvoortgang live | de client pollt `/activities` | (A) event bij voortgang | geen | **Roadmap gap** | nee | de voortgangsbalk beweegt zonder pollen |
| Kijkstatus van een ander toestel | geen push vandaag | (A) event per wijziging | geen | **Roadmap gap** | nee | pauzeren op de tv is direct zichtbaar op de telefoon |
| Sessiestatus en serverbrede meldingen | geen push vandaag | (A) event | geen | **Roadmap gap** | nee | een afgebroken transcode meldt zich |

### 5.15 Security

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Padtraversal onmogelijk maken | Plex regelt dit intern | (A) opaque ids, containment na symlinkresolutie, [16.1](pleya-server-architecture.md#161-het-beginpunt-is-een-concrete-bevinding) | PS-2 | Technisch gereed | nee | geen enkel pad uit een aanvraag bereikt het bestandssysteem |
| Bestaan van een resource lekt niet | Plex geeft soms `403` | (A) onzichtbaar levert `404` | PS-9 | In roadmap | ja | PS-9 criterium 2 |
| Kapot mediabestand laat de scan niet vallen | Plex-gedrag varieert | (A) ffprobe als kindproces met timeout | PS-2 | Technisch gereed | nee | een corrupt bestand markeert zichzelf en stopt de scan niet |
| Providerantwoord valideren | Plex-agents | (A) kandidatenlaag, nooit rechtstreeks canoniek | PS-7 | In roadmap | ja | een HTML-antwoord van een provider beschadigt geen record |
| Geen geheimen in logs | Plex logt tokens | (A) tokens nooit, paden afgekort | PS-11 | In roadmap | nee | een gedeeld logbestand bevat geen token |
| Mounts zijn read-only | Plex schrijft in de bibliotheek | (A) gedocumenteerde verwachting waar het dreigingsmodel op steunt | PS-2 | Technisch gereed | nee | de container start met `:ro`-mounts |
| Bestanden uploaden | Plex staat artwork-upload toe | (C) bestaat niet in v1 | n.v.t. | Bewust buiten scope | nee | hangt samen met het productbesluit over artwork |

### 5.16 Migratie vanaf Plex

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Titels koppelen tussen Plex en Pleya | n.v.t. | (A) driestapsmatch met ambiguïteitsregel | PS-12 | In roadmap | ja | PS-12 criterium 2 |
| Kijkstatus en kijkposities overnemen | n.v.t. | (A) per gebruiker | PS-12 | In roadmap | ja | PS-12 criterium 1 |
| Favorieten en verzamelingen overnemen | n.v.t. | (A) waar een equivalent bestaat | PS-12 | In roadmap, afhankelijk van 5.5 en 5.9 | ja | een verzameling komt compleet over |
| Afspeellijsten overnemen | n.v.t. | (A) PS-12 noemt ze niet | geen | **Roadmap gap** | ja | een afspeellijst komt met volgorde over |
| Gebruikers overnemen | n.v.t. | (B) opnieuw aanmaken met eigen wachtwoorden; Plex-wachtwoorden zijn niet over te nemen | PS-9, PS-12 | Ontworpen | nee | het huishouden is in één zitting opnieuw ingericht |
| Droogloop met rapport | n.v.t. | (A) verplicht, niet over te slaan | PS-12 | In roadmap | ja | PS-12 criterium 1 |
| Plex-ids nooit overnemen | n.v.t. | (A) `ratingKey` komt in geen enkele tabel voor | PS-12 | In roadmap | ja | PS-12 criterium 3 |

### 5.17 Meegeleverde webinterface

Plex levert zijn eigen webinterface mee op `:32400/web`, en de matrix had daar tot nu toe geen regel
voor. PS-3W vult dat in. Wat hier staat is uitsluitend wat PS-3W aflevert; afspelen in een browser
volgt op PS-4 en PS-6 en krijgt een regel zodra een fase hem draagt, niet eerder.

Geen van deze regels is een blocker. Een huishouden dat de app op elk toestel heeft, mist de
webinterface bij dagelijks gebruik niet zodra Plex stopt. Waar het wel telt is de beheerkant, en die
staat al als blocker in [5.13](#513-serverbeheer-en-levenscyclus) onder G6 en G7.

| Capability | Vandaag bij Plex | Pleya Server-doel | Fase | Status | Blocker | Bewijs |
| --- | --- | --- | --- | --- | --- | --- |
| Webinterface meegeleverd met de server | Plex Web op `:32400/web` | (A) statische bundel via `//go:embed` in dezelfde binary, [DEC-046](DECISIONS.md#dec-046-pleya-web-is-een-protocolclient-en-co-distributie-geeft-geen-extra-rechten) | PS-3W | Technisch gereed | nee | PS-3W criterium 1: de bundel wordt geserveerd en `/pleya/v1` wordt niet overschaduwd |
| Setup en inloggen zonder een app te installeren | Plex-webwizard | (A) setup-code inwisselen en inloggen in de browser | PS-3W | Technisch gereed | nee | PS-3W criterium 3 |
| Bibliotheken bladeren in een browser | Plex Web | (A) schil plus posterraster op de bestaande leesendpoints | PS-3W | Technisch gereed | nee | PS-3W criterium 3 |
| Zoeken in een browser | Plex Web | (A) `GET /search`, [DEC-045](DECISIONS.md#dec-045-zoeken-levert-standaard-films-series-en-afleveringen-geen-seizoenen) | PS-3W | Technisch gereed | nee | PS-3W criterium 3 |
| Detailpagina in een browser | Plex Web | (A) wat `Item` vandaag draagt; samenvatting, genres en cast volgen in PS-7 | PS-3W | Technisch gereed | nee | PS-3W criterium 3 |
| Serverstatus lezen zonder SSH | Plex Web toont server en versie | (A) overzicht uit `GET /server` en `GET /info`, in dezelfde schil als de mediakant | PS-3W | Technisch gereed | nee | PS-3W criterium 7 |

### 5.18 Buiten de mediaserver

Wat hier staat is niet vergeten maar geplaatst. Elke regel draagt een expliciet oordeel.

| Capability | Vandaag bij Plex | Oordeel | Status | Blocker |
| --- | --- | --- | --- | --- |
| Live TV en kanalen | `/livetv/dvrs`, EPG via `epg.provider.plex.tv` | Productbesluit nodig; voorstel is (C) voor v1, want het vraagt tuners, EPG-licenties en een eigen grabber | **Productbesluit nodig** | nee |
| DVR, opnameregels en geplande opnames | Plex-only, volledig gebouwd in de client | Productbesluit nodig; hangt aan het besluit over Live TV | **Productbesluit nodig** | nee |
| Muziekbibliotheken | Plex ondersteunt ze; Pleya filtert ze weg in `libraries_provider.dart:149` | (C) buiten de productscope | Bewust buiten scope | nee |
| Fotobibliotheken | Plex ondersteunt ze; Pleya toont ze niet | (C) buiten de productscope | Bewust buiten scope | nee |
| Plex-kijklijst (Discover) | plex.tv-cloud, niet de mediaserver | (B) favorieten per gebruiker vervangen het lokale deel; de "nog niet in je bibliotheek"-kant blijft een Plex-accountfunctie | **Productbesluit nodig** | nee |
| Trakt, MyAnimeList, AniList, Simkl | client-side, `lib/services/trackers/` | (C) trackers praten met hun eigen diensten | Bewust buiten scope | nee |
| Discord Rich Presence | client-side, payload is Plex-vormig | (B) werkt op elke backend zodra de payload backend-neutraal is | Bewust anders opgelost | nee |
| Seerr-aanvragen | externe dienst, `lib/services/seerr/` | (C) geen serververantwoordelijkheid | Bewust buiten scope | nee |
| Watch Together | peer-to-peer via `base_peer_service` | (C) blijft client-side | Bewust buiten scope | nee |
| Pleya Remote | companion-verbinding tussen eigen toestellen | (C) blijft client-side | Bewust buiten scope | nee |
| Pleya Share | eigen product, [hoofdstuk 2](pleya-server-architecture.md#2-de-grens-tussen-pleya-share-en-pleya-server) | (C) blijft apart; gedeeld wordt het protocolvocabulaire, niet de productscope | Bewust buiten scope | nee |

---

## 6. Roadmapmapping per fase

Per fase: welke Plex-verantwoordelijkheid vervalt, wat er daarna nog openstaat, en of de fase
technisch gereed kan zijn terwijl het product dat niet is.

| Fase | Plex-verantwoordelijkheid die vervalt | Wat daarna nog openstaat | Technisch gereed zonder productgereed? |
| --- | --- | --- | --- |
| **PS-1** protocol | geen; dit is de grens waarachter de rest kan bestaan | alles | n.v.t., de fase levert een specificatie |
| **PS-2** catalogus in Go, gesloten | bestandsdetectie, identiteit, technische analyse, edities, herscan | bibliotheekbeheer vanuit de client, metadata, afspelen | **ja**: de scanner werkt, maar alleen via de opdrachtregel te bedienen |
| **PS-3** `PleyaServerClient` | bladeren, zoeken, bibliotheeklijst, sortering, de hub-bouwstenen | filters, alfabalk, verzamelingen, afspeellijsten | nee, dit is meteen zichtbaar in de app |
| **PS-3W** Pleya Web, gesloten | de meegeleverde webinterface, voor bladeren, zoeken en de serverstatus | afspelen in de browser, beheer, en alles wat een endpoint mist | **ja**: de schil staat er, maar hij toont alleen wat PS-2 al kan |
| **PS-4** direct play en kijkstatus | de meest voorkomende afspeelweg, plus kijkstatus en hervatten | geschiedenis, favorieten, spoorvoorkeuren, externe ondertitels | **ja**: afspelen werkt, maar een bestand dat het toestel niet aankan faalt zichtbaar |
| **PS-5** `DeviceCapabilities` | niets bij Plex; dit verbetert Plex en Jellyfin ook | de serverkant van de beslissing | nee |
| **PS-6** `PlaybackPlan` | de beslissing welke stream er komt, plus versiekeuze | de uitvoering ervan | **ja**: een plan dat `transcode` zegt levert nog een nette fout op |
| **PS-7** metadata en artwork | agents, matching, posters, achtergronden, cast | metadata bewerken, fix-match, beoordelingen, markers | **ja**: metadata komt binnen, maar een verkeerde match is niet te corrigeren |
| **PS-8** remux en transcoding | de universal transcoder inclusief sessielevenscyclus | externe workers | nee, dit is direct merkbaar |
| **PS-9** gebruikers en rechten | Plex Home, sharing, per-gebruiker kijkstatus | favorieten, geschiedenis, waarderingen, spoorvoorkeuren | nee |
| **PS-10** downloads | Plex Sync voor het offline pad | syncregels, die bewust client-side blijven | nee |
| **PS-11** remote en observability | `plex.direct`, relay, en het beheerdersbeeld | bibliotheekbeheer, back-up, restore, upgrade, terugrollen | **ja**: de server draait remote, maar beheren vraagt nog SSH |
| **PS-12** migratie | de reden om Plex draaiend te houden voor de historie | afspeellijsten migreren | nee |
| **PS-13** externe workers | de laatste hardwarebeperking | niets | nee |

Zes fasen kunnen technisch gereed zijn terwijl het product dat niet is, en dat is precies waarom de
gate in [hoofdstuk 9](#9-de-plex-off-acceptance-gate) op productniveau meet en niet op endpointniveau.

---

## 7. Roadmap gaps

Wat hier staat is een **bevinding**, geen roadmapwijziging. De roadmap wordt alleen aangepast via een
Roadmap deviation proposal met de zes onderdelen uit
[23.1](pleya-server-architecture.md#231-de-roadmap-is-een-contract), en die wordt niet automatisch
doorgevoerd.

Zevenendertig capabilities hangen aan geen enkele fase. Tweeëntwintig daarvan zijn Plex-off blockers.
Gegroepeerd naar waar ze logisch zouden horen:

| # | Gat | Waarom dit een echte blocker is | Waar het logisch hoort |
| --- | --- | --- | --- |
| G1 | Verzamelingen en afspeellijsten, lezen en schrijven | De client heeft er vandaag volledige CRUD voor, inclusief herordenen. Een gebruiker die zijn afspeellijsten kwijtraakt bij de overstap, stapt niet over. | een catalogusfase naast PS-7, of een uitbreiding van PS-3 |
| G2 | Kijkgeschiedenis en "Bekeken door" | PS-4 levert positie en gekeken-vlag, niet de geschiedenis. Het geschiedenisoverzicht en de rij Bekeken door blijven leeg. | PS-9, want geschiedenis is per gebruiker |
| G3 | Favorieten, waarderingen en spoorvoorkeuren per gebruiker | Drie schrijfacties uit `MediaServerClient` (`setFavorite`, `rate`, spoorkeuze) die nergens landen. Zonder deze drie is de persoonlijke laag half. | PS-9 |
| G4 | Intro en aftiteling overslaan | Een zichtbare functie op de verpakking van de app. Plex levert de markers kant-en-klaar; Pleya Server heeft er geen bron voor. | PS-7 voor de opslag, een analysestap na PS-8 voor de detectie |
| G6 | Bibliotheekbeheer vanuit de client | Bibliotheek toevoegen, verwijderen, scannen, voortgang zien, metadata forceren en lopende klussen bekijken. Zonder dit is de server alleen met SSH te bedienen. | PS-11, met de endpoints in PS-2 |
| G7 | Back-up, restore, upgrade en terugrollen | [17.3](pleya-server-architecture.md#173-migraties) en [22](pleya-server-architecture.md#22-deployment-en-distributie) beschrijven het beleid, maar geen fase levert het gereedschap. Terugrollen leunt expliciet op een back-up die niemand bouwt. | PS-11 |
| G8 | Faalpaden als samenhangend geheel | Volle schijf, database weg, transcode-crash, kapot bestand, provider offline. Per stuk komen ze langs, maar geen enkele fase toetst ze als set. | PS-11, als acceptatiecriterium |
| G10 | Beoordelingen | Critici, publiek en het bronlogo staan op het detailscherm. PS-7 noemt titels, samenvattingen en artwork, niet de beoordelingen. | PS-7 |
| G12 | Afspeellijsten migreren | PS-12 noemt kijkstatus, favorieten en verzamelingen, niet afspeellijsten. Volgt uit G1. | PS-12 |
| G13 | Filters op een bibliotheek | Filteren op genre, jaar, kijkstatus en resolutie zit in de app op elke bibliotheekpagina. Het bevroren contract kent geen filterparameter en geen filterendpoint, dus een Pleya Server-bibliotheek levert een ongefilterde lijst. | een catalogusfase, of een contractvraag vóór PS-7 |

**Drie gaten zijn hier weg en dat is geen stille sluiting.**
[docs/pleya-server-ps1-scope-deviation.md](pleya-server-ps1-scope-deviation.md) is op 18 augustus 2026
goedgekeurd en wees G5 aan PS-4 toe, G11 aan PS-2 en G9 aan PS-3. Daarmee is voldaan aan
onderhoudsregel 3: goedgekeurd voorstel plus een Phase ID. Ze staan nu als gewone regel in de matrix,
G11 op `Technisch gereed` omdat PS-2 hem heeft opgeleverd, G5 en G9 op `In roadmap` omdat hun fase nog
moet draaien.

**G13 is er nieuw bij, gevonden bij het sluiten van PS-2 en PS-3W.** De regel voor filters stond op
`PS-1, PS-3` terwijl PS-1 gesloten en bevroren is zonder één filterparameter: `/libraries/{id}/items`
kent `limit`, `cursor` en `sort` en verder niets. Een fase die hem niet kan leveren is geen fase, dus
de regel gaat naar `geen`. Client-side filteren over een gecursorde lijst van duizenden items is geen
oplossing maar een fout antwoord op de vraag. Dezelfde correctie geldt voor de alfabetische
sprongbalk, die om dezelfde reden geen `firstCharacter`-endpoint heeft; die stond al als gap en is
alleen van fase ontdaan. Sorteren blijft wél bij PS-3: het contract draagt `title`, `added_at` en
`year` in beide richtingen.

Vijftien gaps zijn geen blocker: mappenhiërarchie, verwante titels, de alfabetische sprongbalk met
echte offsets, afspeellijst herordenen, hoofdstukken, uit Verder kijken halen, de drempel voor
uitgekeken, een sessie beëindigen, opslagstatus, en de vier realtime-capabilities.

**De realtime-laag verdient een aparte opmerking.** Hoofdstuk 14 beschrijft een websocket-hub met
volgnummers, PS-2 zet hem expliciet buiten scope, en PS-11 gaat ervan uit dat hij bestaat
("websockets door de proxy"). Geen enkele fase bouwt hem. Hij is geen blocker, want alles wat via een
event komt is ook op te halen met een gewone aanroep, maar de tegenstrijdigheid tussen twee fasen
hoort opgelost te zijn voordat PS-11 begint.

---

## 8. Open productbesluiten

Elf capabilities wachten op een productbesluit. Zolang dat besluit uitblijft, staan ze niet in **A**,
niet in **B** en niet in **C**, en telt de gate ze als onbekend. Bij vrijgave van de
replacement-release mag er geen enkele onbekende meer op deze lijst staan.

| Besluit | De vraag | Opties | Uiterlijk beslissen |
| --- | --- | --- | --- |
| B1 | Metadata bewerken in de client | eigen editor met veldvergrendeling (A), alleen een kandidaat bevestigen of afwijzen zoals PS-7 nu voorstelt (B), of helemaal niet (C) | begin PS-7 |
| B2 | Match corrigeren en losmaken | eigen fix-match tegen de provider (A), of alleen handmatig een externe id invullen (B) | begin PS-7 |
| B3 | Artwork kiezen of uploaden | kandidaten tonen en kiezen (A), alleen kiezen zonder upload (B), of niet in v1 (C, want mounts zijn read-only) | begin PS-7 |
| B4 | Extra's en trailers | uit de bestandsboom herkennen (A), van de provider halen (A), of niet in v1 (C) | begin PS-7 |
| B5 | Slimme afspeellijsten en verzamelingen | eigen regelmodel (A), alleen statische lijsten (B), of niet in v1 (C) | zodra G1 een fase krijgt |
| B6 | Scrubvoorbeelden | zelf genereren en cachen (A, kost schijfruimte en scantijd), client-side uit de stream (B), of niet in v1 (C) | begin PS-8 |
| B7 | Intro en aftiteling overslaan | eigen detectie op de audio- of videostroom (A), hoofdstukmarkeringen uit het bestand hergebruiken (B), of niet in v1 (C) | zodra G4 een fase krijgt |
| B8 | Ondertitels zoeken en downloaden | server bemiddelt naar OpenSubtitles (A), de client praat er rechtstreeks mee (B), of niet in v1 (C) | begin PS-7 |
| B9 | Live TV en kanalen | eigen tuner- en EPG-ondersteuning (A), of buiten de productscope voor v1 (C) | vóór de replacement-release |
| B10 | DVR, opnameregels en geplande opnames | volgt B9 | vóór de replacement-release |
| B11 | Plex-kijklijst | favorieten per gebruiker dekken het lokale deel (B); de "nog niet in je bibliotheek"-kant blijft een Plex-accountfunctie en verdwijnt bij Plex-off | vóór de replacement-release |

B9 tot en met B11 zijn geen blockers voor de gate zoals hij nu staat, maar ze bepalen wel wat "geen
Plex meer nodig" voor een individuele gebruiker betekent. Iemand die Live TV via Plex kijkt, kan Plex
niet uitzetten zolang B9 op (C) uitkomt. Dat is een geldige uitkomst, mits hij hier staat en niet
per ongeluk ontstaat.

---

## 9. De Plex-off acceptance gate

`PLEX_OFFLINE_REPLACEMENT_GATE` toetst één ding:

```
Plex-container stoppen
        ↓
Pleya Server blijft zelfstandig functioneren
        ↓
Pleya-clients blijven bruikbaar
        ↓
geen enkele Plex-aanroep op het normale Pleya Server-pad
```

De gate is groen wanneer alle zeven categorieën slagen. Eén rode categorie maakt de hele gate rood,
en een release mag dan niet als volwaardige Plex-vervanging worden aangeduid.

| Categorie | Slaagt wanneer |
| --- | --- |
| **Catalogus** | Bibliotheken tonen inhoud, films en series kloppen inclusief seizoenen en afleveringen, metadata en artwork staan er, zoeken werkt, een herscan verandert geen identiteiten, en edities en meerdere versies blijven uit elkaar. |
| **Playback** | Direct play speelt en seekt, audio- en ondertitelkeuze werkt, meerdere versies leveren de juiste keuze, remux en transcode werken met hardwareversnelling waar aanwezig, het HDR- en Dolby Vision-beleid klopt, audio komt aan zoals de uitgang hem aankan, en elke sessie wordt opgeruimd ook na een harde clientcrash. |
| **Persoonlijke state** | Kijkstatus, hervatten, Verder kijken en geschiedenis kloppen, meerdere gebruikers zien elkaars status niet, en een tweede toestel toont dezelfde positie. |
| **Remote** | De server is buiten huis bereikbaar over HTTPS via proxy of tunnel, range-verkeer blijft intact, authenticatie en streamtokens werken, en realtime gedrag degradeert netjes in plaats van te breken. |
| **Offline** | Downloaden werkt, offline afspelen werkt, en offline gekeken materiaal synchroniseert terug volgens het vastgelegde conflictmodel. |
| **Beheer** | Een beheerder voegt een bibliotheek toe, start een scan, ziet de voortgang, begrijpt een fout, leest logs en metrics, maakt een back-up, zet die terug en voert een upgrade uit, alles zonder database- of SSH-toegang. |
| **Migratie** | Wat uit Plex moest komen is geïmporteerd, ambigue koppelingen zijn door een mens opgelost, en geen enkele Plex-identiteit is een Pleya-identiteit geworden. |

**De harde regel eronder.** Zolang een Pleya Server-verbinding actief is, mag geen normale
functionaliteit runtime van Plex afhangen. Geen catalogus van Pleya Server met metadata van Plex,
geen afspelen van Pleya Server met kijkstatus van Plex, geen gebruikers van Pleya Server met
identiteit van Plex, geen zoeken van Pleya Server dat terugvalt op een Plex-bibliotheek.
Migratiegereedschap mag Plex lezen. Een Plex-adapter mag Plex lezen. Een Pleya Server-runtimepad
niet. Tijdelijke fallback tijdens een migratiefase is toegestaan wanneer hij in die fase beschreven
staat; de gate accepteert geen verborgen fallback.

### 9.1 Stand van zaken

Bijgewerkt bij het opleveren van PS-4 op 21 augustus 2026. De aantallen zijn uit de matrix in
hoofdstuk 5 geteld en niet overgeschreven uit een vorige ronde.

| Meting | Aantal | Vorige ronde |
| --- | --- | --- |
| Domeinen | 18 | 18 |
| Capabilities | 162 | 162 |
| Technisch gereed | 31 | 17 |
| Plex-off blockers | 95 | 96 |
| Blockers met een bestaande fase | 71 | 72 |
| Blockers zonder fase (roadmap gap) | 22 | 22 |
| Blockers die op een productbesluit wachten | 3 | 2 |
| Roadmap gaps in totaal | 36 | 37 |
| Open productbesluiten | 11 | 11 |
| Bewust buiten scope | 12 | 12 |
| Bewust anders opgelost | 1 | 1 |

**De blockerteller daalde met één, en niet door een capability te bouwen.** "Sterke validator en
`If-Range`" is geen blocker meer omdat de belofte eruit is: [DEC-050](DECISIONS.md) laat de
byte-identiteitsgarantie vallen, en de regel staat er nu als een zwakke validator die geen blocker
is. Dat is de eerlijke boeking van een productbelofte die vervalt, en niet van een probleem dat
opgelost is.

De gate staat vandaag **rood**, en dat blijft de verwachte uitkomst: er is een catalogus en een
webclient, en er is geen afspelen, geen kijkstatus, geen metadata en geen gebruikersmodel.

Wat er wel veranderd is: PS-4 zette veertien capabilities erbij op `Technisch gereed`, boven op de
zeventien van PS-2 en PS-3W. Afspelen met range, seeken, kijkstatus melden, gekeken en niet-gekeken
markeren, hervatten op een tweede toestel, conflicten oplossen, Verder kijken, Recent bekeken, de
uitgekeken-drempel, de externe speler, losse ondertitels en het terugsynchroniseren van offline
gekeken materiaal staan er allemaal, en de eerste tien daarvan zijn tegen de draaiende server op de
DS920+ gemeten. Wat níét gemeten is, is de app die een film start op drie vormfactoren; PS-4 heet
daarom "opgeleverd" en niet "gesloten".

De eerdere ronde: PS-2 en PS-3W hebben zeventien capabilities op `Technisch gereed` gezet en
acht Plex-off blockers gesloten. Dat is de eerste keer dat deze telling beweegt, en hij beweegt in de
richting die de roadmap voorspelt: identiteit, verandersdetectie, technische analyse, edities,
migraties en de drie securityregels van de scanner.

Vierentwintig van de zesennegentig blockers hangen aan geen enkele fase, waarvan er twee eerst een
productbesluit vragen. Dat aantal daalde met twee doordat G11 zijn fase kreeg en een filterregel er
juist bijkwam die er niet in stond.

Twee tellingen die eerder niet klopten staan nu vast. De regel "blockers zonder fase" stond op 24
terwijl hoofdstuk 7 er 22 telde; de matrix zelf gaf 24 en hoofdstuk 7 gaf 22, en 22 plus de vijftien
niet-blokkerende gaps was 37 terwijl de matrix er 39 droeg. Beide komen uit hetzelfde patroon: een
telling die met de hand bijgewerkt werd terwijl de tabel eronder verschoof. Vandaar de kolom
"vorige ronde": een verschil dat niemand kan verklaren is een fout in de telling en niet in de
werkelijkheid.

---

## 10. Hoe dit document wordt bijgehouden

Dit bestand is de bron voor de vraag of iets nog bij het eindproduct hoort. Drie regels:

1. **Bij het afsluiten van een fase** gaan de opgeleverde capabilities van `In roadmap` naar
   `Technisch gereed` of `Productgereed`, en verhuizen de blockers die daarmee dicht zijn uit de
   telling in 9.1.
2. **Een nieuwe capability die in de client opduikt** krijgt hier een regel voordat hij ergens anders
   landt. Een functie zonder regel in deze matrix bestaat voor de gate niet.
3. **Een gat wordt nooit stil gesloten.** Een roadmap gap verdwijnt uit hoofdstuk 7 zodra een
   Roadmap deviation proposal is goedgekeurd en de capability een Phase ID heeft, en niet eerder.

Zie ook de sectie Pleya Server in [CLAUDE.md](../CLAUDE.md) voor de werkregels per sessie, en
[hoofdstuk 25](pleya-server-architecture.md#25-definition-of-done-pleya-server-als-zelfstandig-mediaserverproduct)
van de architectuur voor de definitie van "volwaardig".
