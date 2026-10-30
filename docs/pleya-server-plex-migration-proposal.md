# S15.9: afbakening Plex-migratie vóór de vervangingsgate

Status: voorstel, 30 oktober 2026. Roadmap C-05; S15.9 / PS-12. Michel koos eerst afbakenen (DEC-168). Geen import, productiegebruik, protocolwijziging of PS-12-vrijgave.

Uitgebreid op 30 oktober 2026 met een bronneninventaris per veld, de titelkoppeling zoals die in `grouping_service.dart` staat, conflict- en herstelregels, een tabel met open besluiten en een [synthetische droogloop](qa/ps12-synthetic/README.md). Die uitbreiding beslist niets: elke voorgestelde standaard in de tabel wacht op Michel.

## Wat over moet komen

De bestaande architectuur [hoofdstuk 19 en PS-12](pleya-server-architecture.md#19-migratie-vanaf-plex) en de [replacementmatrix, migratie](PLEYA-SERVER-REPLACEMENT-MATRIX.md) blijven leidend. Per expliciet gekoppelde gebruiker: bekekenstatus, hervatpositie, favorieten en verzamelingen waar een equivalent bestaat. Afspeellijsten met volgorde blijven een matrixblocker; dit voorstel verklaart ze niet optioneel. Canonieke huidige kijkstatus en een volledige reeks historische kijkgebeurtenissen zijn verschillende gegevens: een actuele Plex-positie levert geen bewijs van jaren gebeurtenisgeschiedenis. Voor dat laatste moet eerst de beschikbare bron en exportdekking worden vastgesteld. Er wordt geen geschiedenis verzonnen uit alleen `viewCount` of een laatst-gezien-datum.

Geen wachtwoorden, Plex-accounttokens of interne Plex-identiteiten overnemen als Pleya-sleutel. Plex blijft draaien. Geen doorlopende sync en geen Jellyfin-migratie binnen PS-12. Bestaande Plex/Jellyfin/local/Share-koppelingen blijven functioneren.

## Identiteit en gebruiker

1. Maak een expliciete, door de eigenaar beoordeelde koppeltabel van bronserver plus brongebruiker naar een bestaand Pleya-account. Gebruikersnaam of huishoudelijk eigenaarstoken is geen bewijs van dezelfde persoon. Beperkte gebruikers krijgen uitsluitend hun toegestane bibliotheken; geen standaardkoppeling aan de eigenaar.
2. Hergebruik de bestaande driestapsregel: gedeelde GUID, gedeelde externe identiteit, daarna genormaliseerde titel/jaar én soort. Meer dan één kandidaat blijft ambigu; een zwakkere stap lost een conflict in een sterkere stap niet op. Afleveringen vereisen de juiste serie en seizoen-/afleveringidentiteit. Remakes, meerdere bronbibliotheken, herbouwde Plex-sleutels en ontbrekende externe IDs krijgen expliciete fixtures.
3. Titel/jaar-kandidaten zijn geen zekere identiteit: voor een schrijfronde moeten die afzonderlijk worden bevestigd. Toon nul, één of meerdere kandidaten en de herkomst van de match. Geen titelheuristiek als bewezen unified deduplicatie presenteren.
4. Gebruik na bevestiging uitsluitend Pleya-item-UUID's voor de bestemming. `ratingKey` mag hoogstens een bronannotatie in het begrensde migratiejournaal zijn; nooit primaire of vreemde sleutel in producttabellen.

## Gereedschap en conflictregels

Een afzonderlijk, eenmalig migratiecommando hergebruikt de bestaande catalogus-, rechten- en kijkstate-eigenaren. Geen tweede clientprovider, parallelle geschiedenisopslag of nieuwe openbare route zonder een apart protocolvoorstel. Broninloggegevens blijven tijdelijk in geheugen of een expliciet aangewezen privé-invoer; geen token in URL, rapport, shellargument of log.

Elke uitvoering begint verplicht met een droogloop: bronsnapshot/digest, bron- en doelschema/binary, expliciete gebruikerskoppelingen, aantallen per soort en per gebruiker, zekere matches, handmatig te bevestigen kandidaten, ambigu/niet gevonden, geweigerde rechten, ongeldige tijden, conflicten en niet ondersteunde inhoud. Rapporten hebben dezelfde privacygrens als de bron; synthetische fixtures voor ontwikkeling. Geen productie-export tijdens deze afbakening.

Voorstel voor schrijven: behoud bestaande, nieuwere Pleya-status. Vergelijk werkelijke bronwijzigingstijd met doelrevisie; bij ontbrekende/onvergelijkbare tijd of een gewijzigde doelrevisie sinds de droogloop: overslaan en expliciet conflict rapporteren. Niet simpelweg de hoogste positie of de laatste importtijd laten winnen. Geen passieve import die actieve playback overneemt, `play_count` verdubbelt of een markering als nieuwe kijksessie telt. Favorieten en collectie-/playlistlidmaatschap worden alleen volgens de goedgekeurde vervangings-/mergekeuze gewijzigd, niet stilzwijgend gewist.

De schrijfronde bindt aan exact het beoordeelde rapport en de bestemmingsrevisies. Elke eenheid heeft een idempotentiesleutel op importdigest/gebruiker/Pleya-item/handeling; tweede identieke uitvoering verandert niets. Een onderbreking kan gecontroleerd hervatten; gewijzigde bron of mapping vereist een nieuwe droogloop. Gebruik transacties per beoordeelde eenheid en een journaal met aantallen en conflicten. Herstelbaarheid moet vooraf bewezen zijn: verse versleutelde back-up inclusief `/config`, herstelproef op een afzonderlijke testdatabase, en een controle dat terugzetten geen nieuwe kijkacties buiten de import vernietigt. Een volledige terugzetactie blijft een afzonderlijk bevestigd onderhoudsmoment.

## Volgorde en vrijgave

De masterlijst noemt PS-12.0 na S15, terwijl S15.9 een besluit vóór S15.5 vereist. Voorgestelde oplossing, nog te besluiten: vrijgeven van de noodzakelijke PS-12-uitvoering en testacceptatie vóór S15.5, nadat de benodigde serverfuncties en herstelpoorten beschikbaar zijn; Plex blijft aan. Geen S15.5-PASS met een nog onbesliste geschiedeniskeuze. Collectie-/playlistblockers houden hun eigen S19-afhankelijkheid en verdwijnen niet door eerst kijkstatus te bouwen.

Na akkoord: opgenomen en geanonimiseerde antwoordfixtures → pure match-/conflicttests → geïsoleerde testimport met twee gebruikers → onafhankelijke adversariële review → herhaalde import/onderbreking/herstelproef → beoordeeld rapport van de echte bron → afzonderlijke toestemming voor werkelijk schrijven. Nieuwe contractvelden of routes krijgen eerst hun eigen compatibiliteitstoets/venster. Een ontwikkelvrijgave is geen productieautorisatie.

Benodigde besluiten vóór uitvoering: (1) PS-12-volgorde expliciet vóór S15.5 vrijgeven, (2) bevestigen welke bron volledige historische gebeurtenissen beschikbaar stelt en of actuele status plus die gebeurtenissen vereist zijn, (3) expliciete merge-/vervangingskeuze voor bestaande doelgegevens. Het voorstel vraagt geen credentials of exportbestanden in de chat. Deze drie staan als nummer 1 tot en met 3 in de [tabel met open besluiten](#open-besluiten-voor-michel), met twaalf besluiten die uit de uitwerking hieronder volgen.

## Acceptatie

Twee gebruikers met dezelfde titel lekken geen status. Ambigue titel, serie/remakeconflict, gewijzigde rechten, ontbrekende datum, toekomst-/ongeldige positie en veranderde doelrevisie schrijven niets. Een nieuwe Pleya-kijkactie blijft behouden. De droogloop schrijft geen productgegevens. Herhalen is idempotent, afbreken hervat zonder duplicatie, collecties/afspeellijsten behouden de bevestigde inhoud en volgorde. Rapport, herstelde back-up en steekproeven per gekoppelde gebruiker horen bij de gate; een geslaagde fixture is geen bewijs van een echte migratie.

## Bronneninventaris per veld

Elk feit hieronder draagt een van vier bronlabels. Waar geen van de vier iets zegt, staat er **niet geverifieerd**.

| Label | Wat het is | Kanttekening |
|---|---|---|
| code | deze repository, met pad en regel | zegt wat Pleya doet, niet wat Plex garandeert |
| meting | `test/fixtures/plex_detail/README.md`: read-only metingen tegen een eigen Plex-server op 17 augustus 2026, met gesaniteerde antwoorden ernaast | één server, één eigenaarsaccount |
| spec | de community-OpenAPI-specificatie `lukasparke/plex-api-spec`, via Context7 opgehaald op 30 oktober 2026 | niet van Plex zelf; Context7 geeft van veldbeschrijvingen alleen het begin van de zin |
| Plex-docs | `developer.plex.tv/pms` via Context7 (`/websites/developer_plex_tv_pms`) | beschrijft `/accounts` en `/status/sessions/history/all`, maar zwijgt over de velden van een geschiedenisrij, over `viewCount`, `viewOffset`, `lastViewedAt`, `userRating` en over Plex Home-tokens |

### Velden op een item

Gelezen uit een bibliotheeklijst of `/library/metadata/{id}` met het token van de gebruiker zelf.

| Veld | Betekenis en eenheid | Per gebruiker | Bron | Doel in Pleya |
|---|---|---|---|---|
| `viewCount` | aantal voltooide kijkbeurten; spec: "When a users has completed …" (afgekapt) | ja: `/library/all` gesorteerd op `lastViewedAt` is "user-scoped per token" (code, `plex_client.dart:4002`) | code `plex_mappers.dart:610` en `:1055`; spec, type `Metadata` | `watched` bij 1 of meer; `play_count` is besluit 4 |
| `viewOffset` | hervatpositie in milliseconden; spec: "When a user is in the process …" | ja, zelfde bron | code `plex_mappers.dart:608`, gemapt als `viewOffsetMs` op `:1054` | `position_ms` |
| `lastViewedAt` | Unix-seconden; spec: `PlexDateTime` | ja, zelfde bron | code `plex_client.dart:3074` en `:4002-4025` | geen kolom in 0004; `last_played_at` uit 0017 is besluit 5; altijd in het journaal en in de conflictvergelijking |
| `userRating` | getal; spec geeft "0-10" bij het type `Collection`, bij `Metadata` alleen "When the user has rated …" | volgens de formulering van de spec; niet gemeten | code `plex_mappers.dart:574` (double) | geen kolom in 0004; `ratings.rating` (smallint 1 tot 10, 0020) is besluit 10 |
| `duration` | milliseconden, eigenschap van het bestand | nee | code `plex_mappers.dart` | `duration_ms` is besluit 13 |
| `guid`, `Guid[]` | `plex://…` en, met `includeGuids=1`, `imdb://`, `tmdb://`, `tvdb://` | nee | code `plex_client.dart:1693-1724`, `lib/utils/external_ids.dart` | alleen voor de titelkoppeling |

Niet geverifieerd: of `viewCount` bij handmatig "bekeken" ophoogt of op 1 gezet wordt, of een halve ster als geheel getal of als breuk in `userRating` aankomt, en of een handmatige markering `lastViewedAt` verzet. Geen van de vier bronnen zegt het.

### `/status/sessions/history/all`

De parameters volgens de spec: `X-Plex-Container-Start` en `-Size`, `accountID`, `viewedAt`, `viewedAt>`, `viewedAt<`, `librarySectionID`, `metadataItemID`, `deviceID` en `sort` met standaard `viewedAt:desc,accountID`. De app gebruikt daarvan `sort`, `viewedAt>`, paginering en `metadataItemID` (code, `server_activity.dart:60-68` en `plex_client.dart:4080-4085`). De Plex-docs noemen alleen het pad, het token en "watch history for all users".

Een rij heeft `accountID`, `deviceID`, `historyKey`, `key`, `librarySectionID`, `originallyAvailableAt`, `ratingKey`, `thumb`, `title`, `type` en `viewedAt`, voor afleveringen aangevuld met de `parent*`- en `grandparent*`-velden (meting). Er zit geen `guid` in, dus elke rij vraagt nog een opzoeking van het item voor de titelkoppeling, en er zit geen `viewOffset` in: over 9590 rijen geen enkele (meting).

Een rij ontstaat bij een voltooide kijkbeurt. Films op 19 tot 60 procent hadden er nul, en bij acht bekeken films van de eigenaar was het aantal rijen nooit hoger dan `viewCount` (meting). Dat rijen ontbreken na een handmatige markering of na een bewaartermijn noemt de meting als mogelijke oorzaak, niet als gemeten feit. Een bewaartermijn staat in geen van de bronnen: niet geverifieerd.

Wie wat mag lezen, verschilt per bron. De spec zegt: "Admin can see all users, others can only see their own". De code behandelt de route als alleen-eigenaar (`plex_client.dart:4067`, `server_activity.dart:33`). Wat een token van een niet-eigenaar werkelijk terugkrijgt, is in deze repository niet gemeten: niet geverifieerd.

`accountID` is een servernummer. Volgens de code staat de eigenaar op een eigen server onder 1 (`plex_client.dart:4071-4072`). In de meting staat in `accounts.json` een account met id 1, en de tweede Home-gebruiker uit `home_users.json` (id 16906116) staat in `accounts.json` onder hetzelfde id; het beheerdersid uit `home_users.json` (4725462) komt in `accounts.json` niet voor. Pseudoniemen in die fixtures zijn alleen binnen één bestand stabiel, dus dat id 1 de beheerder is volgt uit het codecommentaar en niet uit de fixture. Dat dit voor elke server zo werkt: niet geverifieerd.

Gevolg voor PS-12: de geschiedenisroute geeft een ondergrens van voltooide kijkbeurten zonder posities. Ze kan `play_history` voeden (besluit 2), maar geen hervatpositie.

### Per Plex Home-gebruiker

De app haalt een token per Home-gebruiker zo op (code):

1. `GET clients.plex.tv/api/v2/home/users` met het accounttoken (`plex_auth_service.dart:260`). Velden volgens de meting: `id`, `uuid`, `title`, `username`, `admin`, `restricted`, `guest`, `protected`, `hasPassword` en meer.
2. `POST …/home/users/{uuid}/switch`, met PIN als de gebruiker `protected` is; foutcode 1041 betekent een verkeerde PIN (`lib/profiles/plex_home_switch.dart`). Het antwoord bevat een `authToken` voor die gebruiker.
3. `GET /api/v2/resources` met dat token levert per server het `accessToken` voor die gebruiker (code `active_profile_binder.dart`; spec, `description.md`).
4. Met dat servertoken leest een bibliotheeklijst de `viewCount`, `viewOffset` en `lastViewedAt` van die gebruiker.

De spec beschrijft de switch als `/home/users/{id}/switch` met een numeriek id; de app gebruikt de `uuid` op `clients.plex.tv/api/v2`. Profielwissel in de app werkt via dat tweede pad, dus dat is wat een migratiecommando zou hergebruiken.

| Soort gebruiker | Token voor het commando | Eigen kijkstatus | Geschiedenisroute | Bron |
|---|---|---|---|---|
| eigenaar van de server, beheerder van Home | eigen accounttoken | ja | alle accounts | code, spec |
| Home-gebruiker, niet beperkt | switch vanuit het eigenaarstoken, PIN als `protected` | ja | volgens de spec alleen de eigen rijen | code; route niet gemeten |
| beheerde gebruiker (`restricted: true`) | switch, zelfde route | ja, binnen wat Plex hem toestaat | idem | code; route niet gemeten |
| gedeelde gebruiker buiten Home | geen switch mogelijk; alleen met een eigen login van die persoon | alleen met eigen login | de eigenaar ziet ze volgens de spec | spec; niet gemeten. `plex.tv/api/v2/friends` geeft 410 (meting) |
| gast (`guest: true`) | niet geverifieerd | niet geverifieerd | niet geverifieerd | alleen de veldnaam bestaat (meting) |

Wat een niet-eigenaar kan lezen: de eigen bibliotheekstatus met het eigen servertoken (code). `/accounts` vraagt volgens de code het eigenaarstoken (`plex_client.dart:4034`). Voor de geschiedenisroute geldt wat hierboven staat: de spec zegt eigen rijen, gemeten is het niet. Hoe lang een via switch verkregen token geldig blijft, staat in geen van de bronnen: niet geverifieerd. PIN en tokens blijven in geheugen, zoals onder "Gereedschap en conflictregels" al staat.

## Gebruikers- en titelkoppeling

### Gebruikers

Er zijn twee Plex-identiteiten per persoon. De bibliotheekstatus komt binnen onder een Home-`uuid` (via het token), een geschiedenisrij onder een servergebonden `accountID`, en voor de eigenaar verschillen die nummers. De koppeltabel uit punt 1 van "Identiteit en gebruiker" legt daarom per persoon de Plex-server (`machineIdentifier`), de Home-`uuid` en het `accountID` vast, naast de Pleya-`users.id`. Namen tellen niet als bewijs.

Aan de Pleya-kant beslist de Pleya-rol. `owner` en `admin` hebben geen `library_permissions`-rij nodig, `member` en `restricted` wel (`pleya_server/internal/catalog/permissions.go:41`). Een item dat Plex een gebruiker liet zien, maar dat in een Pleya-bibliotheek zonder recht voor die gebruiker staat, wordt overgeslagen en gerapporteerd.

### Titels: de drie stappen uit `grouping_service.dart`

Eerst een voorwaarde die de rest bepaalt. `_neverMergedBackends` bevat `MediaBackend.local` en `MediaBackend.pleyaServer` (`grouping_service.dart:30`): `groupUnifiedMediaSources` voegt een Pleya Server-bron nooit samen met iets anders (DEC-063). Een migratie kan die functie dus niet aanroepen om Plex aan Pleya te koppelen. Ze kan alleen dezelfde regels toepassen.

**Stap 1, concrete bron ontdubbelen** (`_deduplicateBySourceKey`, r. 131-139). Twee kandidaten met dezelfde `sourceKey` (`serverId:itemId`) zijn één lidmaatschap; de eerste blijft, de rest valt weg voordat er identiteitswerk gebeurt. Het commentaar zegt nadrukkelijk dat dit geen media-identiteit is: twee verschillende `sourceKey`s blijven twee bronnen, ook als het overduidelijk dezelfde film is.

**Stap 2, sterke tokens** (`_unionFind`, r. 159-171). Elk paar dat een identieke tokensleutel `scope:namespace:waarde` deelt, wordt verbonden, ook via een tussenschakel. Tokens komen uit twee bronnen in `identity_evidence.dart`: `guidTokens` neemt een GUID alleen als die `://` bevat en niet `agents.none://` is, in kleine letters, en zet de scope van een aflevering altijd op `episode`; `externalIdTokens` maakt tokens van imdb, tmdb en tvdb, en hangt bij afleveringen `/sXeY` achter het id van de serie. GUID en externe id's zitten in dezelfde stap, niet in twee opeenvolgende stappen zoals de tekst onder "Identiteit en gebruiker" suggereert. Na het verbinden controleert `_componentHasNamespaceConflict` (r. 254-265) de hele component: heeft één `scope:namespace` twee waarden, dan wordt elk lid een eigen groep, zonder gegokte tussensplitsing.

**Stap 3, titel en jaar** (r. 175-199, `_weakFallbackAllowed` r. 208-216). Alleen als `allowWeakFallback` aan staat, en alleen binnen dezelfde `bucketKey`. Een server die meer dan één kandidaat in die bucket levert, doet niet mee (C19). Verder moeten de granulariteit en de genormaliseerde titel gelijk zijn, moeten beide jaren bekend en gelijk zijn (`yearAgreesWith`), en mag geen token in dezelfde scope en namespace botsen.

Wat dat voor Plex naar Pleya betekent, afgeleid uit de code:

1. De GUID-route vindt niets. `media_items` heeft geen Plex-GUID (0002), en dit voorstel verbiedt `ratingKey` of GUID als sleutel op te slaan. Een sterke match is in de praktijk een tmdb-match.
2. Pleya bewaart één extern id: `metadata_candidates.external_id` met provider `tmdb` en status `matched`, en alleen voor films en series (`pleya_server/internal/catalog/store_metadata.go:125` en `:496`). Een Plex-item met alleen imdb of tvdb krijgt geen sterke match.
3. Een aflevering heeft in Pleya geen eigen id. Het token moet uit de tmdb van de serie plus `item_index` van seizoen en aflevering worden opgebouwd, zoals `externalIdTokens` met een discriminator doet. Stap 3 matcht nooit een aflevering: `CanonicalMediaIdentity.episode` heeft geen jaar en `yearAgreesWith` eist er twee. Een aflevering van een serie zonder tmdb-match koppelt dus nooit vanzelf.
4. `normalizeTitleForMatching` haalt `(jjjj)` weg en daarna alles buiten `a-z0-9`. "Amélie" wordt aan beide kanten `amlie` en matcht dus nog, maar een titel helemaal in een niet-Latijns schrift levert geen bucket en dus nooit een titel/jaar-match op.
5. Delen twee Pleya-items hetzelfde tmdb-id (dezelfde film in een HD- en een 4K-bibliotheek), dan maakt stap 2 er één groep van. Een migratie heeft één `item_id` nodig; dit voorstel noemt dat ambigu (besluit 7).
6. Faalt het ophalen van externe id's, dan valt `identity_resolver.dart` stil terug op alleen de GUID (`catch (_)` op r. 156, randgeval C20). In de app is dat gewenst; in een migratie maakt het een match zwakker zonder dat iemand het ziet (besluit 14).
7. C19 geldt aan beide kanten. Levert de Plex-lijst van één gebruiker twee rijen in dezelfde bucket zonder tmdb, of heeft Pleya twee items in die bucket, dan is het ambigu.

De regel staat in Dart en de server is Go. Waar de migratieregel komt te wonen is besluit 11.

## Conflicten, dubbele import, fouten en terugval

### Veldmapping naar `watch_states`

| Kolom | Voorgestelde waarde | Opmerking |
|---|---|---|
| `subject` | Pleya-gebruiker uit de koppeltabel | sinds 0007 een uuid met verwijzing naar `users` |
| `item_id` | Pleya-item na een zekere of bevestigde match | nooit een Plex-sleutel |
| `position_ms` | `viewOffset`, anders 0 | eerst gecontroleerd: niet negatief en niet voorbij de duur |
| `duration_ms` | besluit 13 | |
| `watched` | `viewCount` 1 of meer | `watched` samen met een positie boven 0 komt in Pleya ook voor: `applyProgress` zet `watched` nooit terug (`internal/watch/watch.go`) |
| `play_count` | besluit 4 | Pleya hoogt hem alleen op bij de overgang naar bekeken (`watch.go:233` en `:253`) |
| `revision` | 1 voor een nieuwe rij | 0 betekent volgens 0004 "er is nog geen canonieke toestand" |
| `owner_session_id`, `owner_lease_until` | NULL | een import neemt geen playback over |
| `last_explicit_at`, `last_explicit_kind` | besluit 6 | de CHECK staat vier waarden toe en een import is er geen van |
| `created_at`, `updated_at` | serverklok op het moment van schrijven | |

Migratie 0020 vulde `play_history` eenmalig uit `watch_states`. Die backfill draait niet opnieuw, dus geïmporteerde kijkstatus verschijnt niet in de geschiedenislijst, tenzij besluit 2 dat anders regelt.

### Conflictregels, in volgorde

1. Loopt er een Pleya-lease op het item, dan altijd overslaan.
2. Heeft de gebruiker al een Pleya-rij voor het item, dan beslist besluit 3. De droogloop toont beide tijden (`lastViewedAt` van Plex, `updated_at` en `last_explicit_at` van Pleya), zodat de gevolgen van elke variant per geval zichtbaar zijn.
3. Is de doelrevisie veranderd sinds de droogloop, dan is het een conflict bij schrijven en blijft de Pleya-rij staan.
4. Landen twee Plex-rijen van dezelfde gebruiker op hetzelfde Pleya-item (een film in twee Plex-bibliotheken), dan mag de volgorde niet beslissen: beide worden een conflict (besluit 15).
5. Ontbreekt het Pleya-recht op de bibliotheek, dan overslaan, ook als Plex het wel toestond.

### Dubbele import

De sleutel per eenheid is importdigest, gebruiker, Pleya-item en handeling, en het journaal bewaart daarbij de geschreven revisie. Een tweede schrijfronde met hetzelfde plan herkent elke eenheid aan die sleutel en schrijft niets.

Een nieuwe droogloop na de import ziet de geïmporteerde rijen als bestaande Pleya-status. Voorstel: staat er voor dezelfde gebruiker en hetzelfde item een journaalregel en is de huidige revisie nog de geschreven revisie, dan heet de rij "al geïmporteerd" en geen conflict. Is de revisie veranderd, dan heeft de gebruiker sindsdien zelf iets gedaan, en dan is het een conflict. Een gewijzigde bron geeft een nieuwe digest en dus nieuwe sleutels; ook dan vangt deze vergelijking op revisie de eerder geschreven rijen af. De synthetische droogloop doet dit nog niet.

### Gedeeltelijke fouten

Elke eenheid is één transactie met de rij en de journaalregel samen. Breekt een run af, dan staan de gecommitte eenheden in het journaal en slaat een hervatte run ze over. Faalt in de droogloop het ophalen van een gebruiker, een pagina of de externe id's van een item, dan is de droogloop onvolledig en levert hij geen schrijfbaar plan op (besluit 14).

### Terugval

Een volledige terugzet uit de back-up blijft de noodroute, maar die vernietigt ook Pleya-kijkacties van na de back-up. Voorstel voor een eerste route: een gerichte terugdraai die alleen rijen verwijdert die het journaal als aangemaakt noemt en waarvan de huidige revisie nog de geschreven revisie is. Rijen die de gebruiker sindsdien heeft bijgewerkt blijven staan en komen in het rapport. Niets verwijst naar `watch_states` (`play_history` verwijst naar `users` en `media_items`, 0020), dus zo'n verwijdering raakt geen andere tabel. Kiest besluit 3 voor een variant die bestaande rijen overschrijft, dan werkt een gerichte terugdraai alleen als het journaal de vorige rij bewaart.

## Synthetische droogloop

[`docs/qa/ps12-synthetic/`](qa/ps12-synthetic/README.md) draait deze regels op verzonnen Plex-JSON met vier gebruikers en een verzonnen Pleya-catalogus, in het geheugen. Uitkomst van de run van 30 oktober 2026: 7 nieuw, 5 conflict, 9 overgeslagen, 2 zonder titelmatch. Een tweede run met hetzelfde plan schrijft niets, een run die halverwege afbreekt en hervat eindigt in dezelfde toestand als een ononderbroken run, en de status van twee gebruikers met dezelfde titel blijft gescheiden. Het script maakt de strengste keuze bij besluit 3 en tijdelijke keuzes bij besluit 4, 6 en 13; dat zijn geen besluiten.

## Open besluiten voor Michel

De kolom "Voorgestelde standaard" is een voorstel. De laatste kolom vult Michel in.

| # | Besluit | Opties | Voorgestelde standaard | Waarom | Besluit Michel |
|---|---|---|---|---|---|
| 1 | PS-12-volgorde ten opzichte van S15.5 | vrijgeven vóór S15.5; na S15.5 met een lege start | vóór S15.5, met Plex aan | zonder migratie verliest de vervangingsgate de kijkstatus (S15.9) | open |
| 2 | geschiedenis naast actuele status | alleen actuele status per gebruiker; ook geschiedenisrijen naar `play_history` | alleen actuele status | de geschiedenisroute is een ondergrens zonder posities en de leesrechten van een niet-eigenaar zijn niet geverifieerd | open |
| 3 | bestaande Pleya-rij voor dezelfde gebruiker en hetzelfde item | (a) altijd overslaan en melden; (b) Plex wint als `lastViewedAt` nieuwer is dan Pleya's `updated_at`; (c) per geval kiezen in de droogloop | (a) | Pleya is eigenaar van de status (DEC-049); (b) vergelijkt tijden van twee verschillende servers, en `updated_at` schuift ook op bij passieve voortgang | open |
| 4 | `play_count` | `viewCount` overnemen; 0; aantal geschiedenisrijen | `viewCount` overnemen, alleen bij nieuwe rijen | 0 maakt een bekeken titel tot "nooit afgespeeld"; geschiedenisrijen zijn een ondergrens | open |
| 5 | `last_played_at` (0017) | `lastViewedAt` overnemen; leeg laten | overnemen | leeg zet alles op het importmoment in "laatst gekeken" | open |
| 6 | `last_explicit_at` en `last_explicit_kind` | NULL; een nieuwe waarde `import` | NULL | een nieuwe waarde is een schemawijziging, en het veld beschrijft een handeling op deze server | open |
| 7 | meerdere Pleya-items met hetzelfde tmdb-id | ambigu, handmatig kiezen; naar alle; naar één volgens een vaste regel | ambigu, handmatig | het voorstel zegt al dat meer dan één kandidaat ambigu blijft | open |
| 8 | titel/jaar-kandidaten | per item bevestigen in de droogloop; overslaan | per item bevestigen | titel/jaar is geen zekere identiteit (punt 3 onder "Identiteit en gebruiker") | open |
| 9 | gedeelde Plex-gebruikers buiten Home | niet meenemen; meenemen met hun eigen login; alleen voltooide kijkbeurten via het eigenaarstoken | niet meenemen, tenzij ze zelf inloggen | zonder eigen token is er geen positie, en een koppeling zonder hun medewerking is niet beoordeeld | open |
| 10 | `userRating` naar `ratings` | meenemen bij een geheel getal van 1 tot 10; niet meenemen | niet meenemen, wel tellen in de droogloop | waarderingen staan niet in de lijst onder "Wat over moet komen" | open |
| 11 | plek van de matchregel | overzetten naar Go in `pleya_server` met dezelfde gevallen als de Dart-tests; een losse Dart-tool | Go, met gedeelde fixturegevallen | het commando hergebruikt de catalogus- en kijkstate-eigenaren van de server | open |
| 12 | migratiejournaal | tabel (migratie binnen PS-12); bestand naast de back-up | tabel | idempotentie werkt alleen als rij en journaalregel in dezelfde transactie landen | open |
| 13 | `duration_ms` | duur van de Pleya-versie (`media_versions.duration_ms`); Plex-`duration` | Pleya-versie, Plex alleen als er geen versie is | de positie wordt afgespeeld tegen het Pleya-bestand | open |
| 14 | ophaalfout tijdens de droogloop | droogloop weigeren; terugvallen zoals `identity_resolver.dart` | weigeren | een stille terugval maakt een match zwakker zonder dat het rapport het toont | open |
| 15 | twee Plex-rijen naar hetzelfde Pleya-item | beide conflict; de rij met de nieuwste `lastViewedAt`; de hoogste positie | beide conflict | het voorstel sluit "hoogste positie wint" al uit, en welke klok `lastViewedAt` zet is niet geverifieerd | open |
