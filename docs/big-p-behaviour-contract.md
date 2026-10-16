# Big P: gedragscontract

Status: akkoord van Michel op 5 oktober 2026, met de preciseringen hieronder verwerkt. Roadmap: BP-00. Uitgangsstand: `github/main` 1b93c50d (5 oktober 2026).
Besluiten: `DEC-XXX` (intent-laag vóór de model-lus) en `DEC-XXX` (DEC-005 terugdraaien: Trakt inlezen komt terug via BP-07). Nummers volgen bij de merge.

## Doel

Pleya stelt eerst vast wie, wat en welke data bedoeld is, verzamelt gecontroleerd de juiste gegevens, geeft het model alleen de juiste context, controleert de uitkomst en toont tekst en acties uit één waarheid. Code stelt harde feiten vast. Het model vult alleen open velden en schrijft zinnen uit aangeleverde redenen.

## Voorrang

Van hoog naar laag:

1. Security en rechten (kinderprofiel, bevoegdheid per bron en gegevenstype, bevestiging van schrijfacties).
2. Een uitdrukkelijke, actuele gebruikerskeuze in de huidige vraag.
3. De vastgestelde intent (code-feiten, gesprek, knop).
4. Persistent geheugen en voorkeuren.
5. Defaults.
6. Het model, dat alleen open velden vult.

Uitzondering op de bevestiging van schrijfacties, alleen voor het eigen geheugen van het actieve profiel (akkoord Michel, 11 oktober 2026, BP-08a):

- Begint de vraag die de gebruiker zelf typte of dicteerde met een uitdrukkelijk "onthoud dat" (ook "onthoud:", "remember that" en "remember:") en staat er geen vraagteken in, dan geldt dat verzoek als de acceptatie van één schrijfactie: Pleya slaat één nieuw feit direct op en meldt letterlijk wat er is opgeslagen, ook als de rest van het antwoord vervalt of een nieuwe vraag het overneemt. Code herkent de opdrachtvorm, niet het model. Een chip, een overdracht uit Zoeken, een herhaalde vraag na de leeftijdenkaart, een vervolgvraag en een deeltaak van een gesplitste vraag tellen niet als getypt.
- Wat direct wordt opgeslagen is altijd de letterlijk getypte tekst na de opdrachtvorm (getrimd, met een hoofdletter, zonder slotpunt), nooit tekst van het model. De code eist dat dat deel minstens drie woorden telt en dat het opslaan de eerste toolaanroep van de beurt is (er stond dus nog geen toolresultaat in de context). De zin die het model aanlevert wordt bij direct opslaan niet gelezen; alleen de categorie komt van het model. De validatie van het geheugen (leeftijden, taal, lengte) geldt voor de getypte woorden, in hoofdzins- en bijzinsvolgorde. Weigert de validatie of het plafond de getypte woorden, dan meldt Pleya dat met een eigen vaste regel (bij een leeftijd met een verwijzing naar Kinderprofiel, bij een taalvoorkeur naar de taalinstellingen) en toont het antwoord van het model niet, ook niet als de beurt titelkaarten of acties had; die blijven staan. Na zo'n weigering krijgt een voorstel om iets te onthouden of te vervangen in die beurt geen kaart meer. Stond de getypte zin al in het geheugen van het profiel en is er aan het eind van de beurt niets opgeslagen, geweigerd of voorgesteld, dan meldt Pleya met een vaste regel dat de zin er al stond en toont het de modeltekst niet, of het model de tool nu aanriep of niet. Stond hij er niet, riep het model de tool niet aan en is er aan het eind van de beurt niets opgeslagen, geweigerd of voorgesteld, dan toont Pleya de modeltekst evenmin: bij een geldige zin meldt het met een vaste regel dat er niets is opgeslagen, bij een ongeldige zin toont het de regel van de weigering (leeftijd, taal, te lang). Deze vaste regels gelden alleen voor een getypte hoofdvraag met de opdrachtvorm, op een profiel met het geheugen aan. Een deeltaak van een gesplitste vraag, de beleefde vorm ("Wil je onthouden dat ..."), een profiel met het geheugen uit en een kinderprofiel vallen erbuiten: daar blijft de tekst van het model staan en wordt niets direct opgeslagen. Na een direct opgeslagen feit krijgt elke volgende schrijfactie in dezelfde beurt een kaart. Een kaart bij een voorstel van Big P toont de tekst van het model; die wordt alleen na een ja opgeslagen.
- Begint de getypte vraag met de opdrachtvorm en leest de zin ook als verhaal- of spoilervraag, dan volgt geen modelaanroep. Pleya antwoordt met een vaste regel en toont een kaart met de letterlijk getypte woorden als die een geldig feit zijn; alleen een ja slaat ze op. De beleefde vorm zonder vraagteken ("Wil je onthouden dat ...", "Please remember that ...") krijgt in dat geval dezelfde regel en kaart, en slaat nooit direct op.
- Vergeten en vervangen houden altijd een kaart, ook na "onthoud dat". De kaart toont wat verdwijnt. Is dat feit tussen de kaart en het ja gewijzigd of verdwenen, dan gebeurt er niets en meldt Pleya dat.
- Op een kinderprofiel gebruikt Big P geen geheugen: de tools worden niet aangeboden, een wachtende kaart verdwijnt en een ja schrijft niets.
- Een vervolgvraag die het model heeft geschreven telt nooit als uitdrukkelijk verzoek, wat erin staat.

Een lager niveau overschrijft nooit een hoger niveau. Onbekend betekent wedervraag of gedeeltelijk antwoord, nooit stil verbreden. Een onbekende identiteit of doelgroep wordt nooit opgelost met een gok. Pleya vraagt (maximaal drie wedervragen, een per keer, twee of drie knoppen plus vrije invoer) of antwoordt gedeeltelijk en zegt wat is weggelaten.

## Capaciteitsgaten en identiteit

- Ontbrekende externe id's, beoordelingen of favorieten (bijvoorbeeld op Pleya Server) zijn een capaciteitsgat. Ze zijn onbekend, niet onwaar en niet negatief: een ontbrekende beoordeling telt niet als "laag", een ontbrekende favoriet niet als "geen favoriet".
- Zonder sterk bewijs (extern id, gedeeld plex.tv-id, profielbinding) blijft identiteit bronlokaal. Een capaciteitsgat is nooit een reden om titels of accounts over servers toch samen te voegen.
- Tests: onbekende beoordeling beïnvloedt de rangschikking niet; zonder extern id geen cross-server merge; ontbrekende favorieten leveren geen "niet favoriet" in een antwoord.

## Nultolerantie

Elk van deze is een harde fout in de handmatige poort. Per fase komt er een test bij die faalt als het gedrag terugkomt (BP-01 voor 4 en 6, BP-02 voor 1, 2 en 7, BP-03 voor 3, 5 en 8):

1. Antwoord over de verkeerde gebruiker.
2. Eigen data bij een vraag over anderen.
3. Een serie bij een filmvraag, of omgekeerd.
4. Data tonen of gebruiken zonder bevoegdheid, ook als de rechten wisselden tijdens het wachten.
5. Verzonnen kijkhistorie, of historie zonder het venster te noemen.
6. Succes tonen voor een taak die mislukte of waarvan de status onbekend is.
7. Een verbreed publiek: "anderen" wordt nooit "iedereen".
8. Een samengevoegde ranglijst presenteren als volledig terwijl niet elke groep een bewezen identiteit heeft.

## Connected Knowledge

Regel: geen gekoppelde, relevante bron blijft onbereikbaar voor Big P alleen omdat er geen losse tool voor bestaat. De grens zijn de rechten van de gebruiker (per bron en per gegevenstype), wat de bron aanbiedt en de privacy van die verbinding.

Gecontroleerd tegen de code op 5 oktober 2026 (de Trakt-rij is bijgewerkt op 11 oktober voor BP-07). "Mist" is wat Big P nu niet kan lezen of koppelen.

| Bron | Levert | Adapter | Rechten | Mist (gecontroleerd) |
|---|---|---|---|---|
| Plex | bibliotheken, items, recent toegevoegd, serverhistorie met account, collecties, eigen beoordeling, watchlist | `PlexClient`, `fetchRecentlyAdded`, `PlexHistoryPlay` (`server_activity.dart`) | eigen token; historie van anderen alleen als eigenaar | `PlexHistoryPlay` draagt geen item-id; eigen beoordeling en watchlist worden niet gelezen; `PlexClient.fetchFavorites` is een stub die een lege pagina geeft, dus geen favorietenbron |
| Jellyfin, Emby | idem plus favorieten | `JellyfinClient`, `fetchFavorites`, `ExternalIds.fromJellyfinProviderIds` | eigen gebruiker; anderen alleen als beheerder | de historie-aanvraag (`_historyFields` in `jellyfin_client/parts/browse.dart`) bevat geen `ProviderIds`; favorieten zijn niet aan Big P gekoppeld |
| Pleya Server | bibliotheken, items, recent toegevoegd, kijkhistorie voor beheerders | `PleyaServerClient`, `fetchRecentlyAdded` in `parts/browse.dart`, `/users/me` | rol op de verbinding | `fetchFavorites` is `unsupported`; geen externe id's of beoordelingen |
| Lokaal | items, recent toegevoegd | `LocalFolderClient` | apparaat | geen accounts, dus geen "anderen" |
| Tautulli | speelhistorie met gebruiker | `TautulliHistoryEntry` | beheerder | model heeft `rating_key` en `grandparent_rating_key`, maar geen `year` of `guid` |
| Seerr | zoeken, ontdekken, status, quota | `SeerrClient` | eigen Seerr-gebruiker | de client kan aanvragen lijsten (`seerr_client_requests.dart`, `GET /request`); of `request_status` op de eigen Seerr-gebruiker filtert, toetst BP-02 |
| TMDB | details, trending, aanbevolen, vergelijkbaar | `TmdbClient` (eigen sleutel) | geen gebruikersdata | `details` geeft een ruwe map; `belongs_to_collection` wordt nergens gelezen |
| Trakt | historie, beoordelingen, watchlist | `TraktClient`: schrijven (`scrobble*`, `addToHistory`, `addRatings`) en lezen van `getRatings`, `getRecommendations`, `getTrending`, `getPopular`; `getUserSettings` | eigen Trakt-account | `getWatched` en `getWatchlist` (BP-07 deel 2) lezen historie en watchlist via de gebonden sync-client, alleen in het geheugen; "gezien" telt Trakt mee en `trakt_watchlist` zet de watchlist naast de bibliotheek; `getRatings`, `getRecommendations`, `getTrending` en `getPopular` zijn nog niet aan Big P gekoppeld |

Eigen sleutel per bron voor "ik" (BP-02): Tautulli via `plexSelfAccountIdIn` (`lib/profiles/plex_self_account.dart`), Plex-historie alleen als eigenaar, Jellyfin/Emby via `connection.userId`, Pleya Server via `/users/me`, Trakt via `getUserSettings`. Is die sleutel er niet, dan is "ik" voor die bron onbekend en geldt de voorrangsregel hierboven.

## Gedragsmatrix

Wat vastligt in code, wat het model mag kiezen, en de terugval. Tools naar huidige registratie in `lib/assistant/assistant_tools*.dart`.

| Vraagsoort | Publiek | Soort | Bron | Tool | Model kiest | Terugval |
|---|---|---|---|---|---|---|
| Wat heb ik gekeken | ik | film/serie uit de vraag | kijkhistorie plus ooit-gezien | `my_watching` | alleen zachte filters | venster noemen; sleutel onbekend: wedervraag |
| Kijkcijfers, wat kijken anderen | anderen op account-id, nooit iedereen | uit de vraag | historie per bron | `watch_stats` | periode binnen vaste lijst | publiek onbekend: wedervraag; geen bewijsde identiteit over servers: per server tonen |
| Aanbevelen voor mij | ik | uit de vraag, anders vragen | bibliotheek eerst | `recommend_together` (bestaat al; werkt nu alleen als de aanvrager Jellyfin-administrator is, niet op Emby of andere backends; geblokkeerd op kinderprofielen; de rest van de BP-07-pijplijn is gepland) | alleen zachte argumenten | te weinig resultaat: apart gemarkeerd buiten de bibliotheek |
| Trakt-watchlist | ik | uit de vraag | eigen Trakt-account naast de bibliotheken | `trakt_watchlist` (BP-07 deel 2; geblokkeerd op kinderprofielen; vraagt gekoppeld Trakt en personalisatie) | alleen soort | server niet bereikbaar of niet op identiteit te vragen: `not_checked`, nooit "ontbreekt"; Trakt onbereikbaar: `trakt_unreachable` |
| Aanbevelen samen | ik plus genoemde personen | uit de vraag | bibliotheek | `recommend_together` (werkt nu alleen als de aanvrager Jellyfin-administrator is, niet op Emby of andere backends; geblokkeerd op kinderprofielen) | persoonskeuze alleen uit treffers | meerdere treffers: knoppen |
| Recent toegevoegd | ik (zichtbare bibliotheken) | uit de vraag | `fetchRecentlyAdded`, `addedAt` | `search_catalog` met `sort: added` | geen | bron die het venster niet haalt: als gedeeltelijk melden |
| Titel zoeken, vergelijkbaar, trending | ik | uit de vraag | catalogus, TMDB | `search_catalog`, `find_title`, `similar_titles`, `trending_titles` | zoektermen | geen treffer: zeggen, niet raden |
| Aanvragen | ik | uit de vraag | Seerr | `find_request_title`, `request_title`, `request_status` | titelkeuze uit treffers | schrijfactie altijd met bevestiging |
| Beheer (taken, scans, gebruikers) | beheerder | n.v.t. | server | `scan_library`, `list_jobs`, enz. | parameters binnen schema | rechten opnieuw toetsen na wachten (BP-01) |
| Diagnose | ik/beheerder | n.v.t. | server | `diagnose_library`, `diagnose_playback` | geen | status onbekend is geen "klaar" |

## Startvragen

De drie vragen onder de begroeting laten zien wat Big P kan. Ze komen uit code, niet uit het model: ze staan er direct, kosten niets en elke vraag is getest.

- Eén bron. `AssistantCapability` (`lib/assistant/assistant_capabilities.dart`) noemt per mogelijkheid de groep, de tools die de vraag hoort te bereiken en een eventuele extra voorwaarde. De teksten staan in `assistant.examples.<naam>` (en en nl). Elke tool zit in een mogelijkheid of in de uitzonderingslijst van `test/assistant/assistant_capabilities_test.dart`, met de reden erbij.
- Alleen wat werkt. Een mogelijkheid wordt aangeboden als minstens één van haar tools wordt bediend door `assistantServedTools`, de poort die ook een run gebruikt, en de extra voorwaarde klopt. Zonder Seerr dus geen aanvraagvraag, en zonder beheerrecht geen vraag die een beheertool nodig heeft (taken, gebruikers, scan, vergelijken, kijkcijfers). De vragen naar de serverlijst, de bibliotheekdokter en een Home-rij blijven voor elk profiel, want een profiel mag die zelf.
- Kinderprofiel. Alleen de groep kijken, en alleen via een tool die in `kidsToolPolicy` op `gated` staat. Zolang de profielstatus niet is gelezen geldt het profiel als kinderprofiel.
- Kinderwoorden. De startvragen "Heb ik iets voor de kinderen?" en "Wat kan ik vanavond met mijn gezin kijken?" zijn kindvragen: op een volwassen profiel met ingevoerde kinderen geldt de poort, zonder kinderen komt er geen titel (zie Kinderen in het huishouden).
- Geen titel, geen naam. Een startvraag noemt geen titel, server of persoon. Een chip telt niet als getypt en schrijft dus nooit geheugen.
- Kiezen. Drie mogelijkheden uit drie groepen waar het profiel er zoveel heeft. Wat langer niet is getoond weegt zwaarder, wat nooit is getoond het zwaarst. De laatste 24 getoonde vragen worden per profiel onthouden, alleen op dit toestel. Binnen één keer openen blijft de set staan, behalve dat hij één keer opnieuw wordt gekozen zodra de profielstatus is gelezen of de taal wijzigt. Twee keer achter elkaar dezelfde set komt niet voor.
- Niets bereikbaar. Dan staan er de drie basis-kijkvragen, en het antwoord zegt wat onbereikbaar is.
- Nieuwe of gewijzigde formulering. De routetest moet groen zijn, en de handmatige ronde in `docs/qa/big-p-startvragen.md` wordt opnieuw gedraaid tegen het ingestelde model.

## Kinderen in het huishouden

De leeftijdspoort hangt aan de vraag, niet alleen aan het profiel. Een ouder voert de kinderen één keer in (naam en geboortemaand, geen leeftijd). Gaat een vraag over de kinderen, dan zet de code op elk profiel een harde poort voor het jongste bedoelde kind, wat het model ook als toolargument stuurt.

- Opslag. `household_kids` in `lib/profiles/household_kids_store.dart`: één sleutel voor alle profielen, alleen dit toestel, niet gesynchroniseerd en niet geëxporteerd (deviceLocal plus runtimeCache). Elk profiel leest hem voor de poort; alleen een profiel dat geen kinderprofiel is bewerkt hem.
- Leeftijd. Streng in hele maanden: de verjaardag telt vanaf de maand na de geboortemaand. Een toekomstige maand en een leeftijd van 18 of ouder tellen niet mee. Het jongste bedoelde kind bepaalt de poort; een naam uit het huishouden (op woordgrens) beperkt de poort tot dat kind.
- Herkenning (`lib/assistant/assistant_kid_audience.dart`). "Mijn/de kinderen", "kids", "de kleintjes", "zoon", "dochter", "jongste/oudste" na "mijn/onze", kinderfilm en kinderserie, "kindvriendelijke film", de Engelse varianten en namen uit het huishouden. "Gezin" en "familie" tellen pas zodra er kinderen zijn ingevoerd. Een kinderwoord dat alleen wordt weggelaten ("vergeet de kinderfilms", "geen kids movies") of alleen zegt wie het account deelt telt niet. Een vals positief maakt het antwoord strenger, een vals negatief laat titels ongefilterd door: de woorden zijn ruim gekozen.
- Gesprek. Een vervolgvraag erft het kinderpubliek uit de eerdere vragen van het gesprek. "Voor mij" of "voor mezelf" en Nieuw gesprek wissen het.
- Afdwingen. `AssistantToolContext.ageGate` is `none`, `kidsProfile` of `kidAudience`. Titeltools, de controle op genoemde titels en de correctieronde volgen `ageGate`, niet `kidsMode`. `kidsMode` blijft alleen uit het profiel komen (geheugen en het blokkeren van tools). Bij `kidAudience` weigert de code de tools die `kidsToolPolicy` op `blocked` zet, behalve de drie geheugentools (ze geven geen titels). Dat geldt ook voor `create_home_row`: een opgeslagen query bevat elke titel, niet alleen wat de poort passeerde; de kinderrij met een afgeleid leeftijdsfilter komt in BP-12b.
- Het model. Het krijgt alleen "Youngest intended child: N years", nooit een naam.
- Titels zonder rating. Onder 6 jaar passeert een titel zonder rating nooit, ook niet met een familiegenre (lokale en Pleya Server-items hebben vaak geen rating). Vanaf 6 geldt de familiegenre-regel zoals bij het kinderprofiel.
- Splitsen en gesprek. Een kindvraag die in taken wordt gesplitst houdt het kinderpubliek in elke taak, wat de woorden van het model ook zijn. Onder een kindvraag worden eerdere volwassen beurten niet aan het model herhaald. Een naam beperkt de poort nooit naar boven: naast een algemeen kinderwoord, of na een eerder alles-kinderen, blijft het jongste kind leidend.
- Nog geen kinderen ingevoerd. Een kindvraag toont dan geen titel en Pleya zegt dat het niet weet welke kinderen bedoeld zijn. Het invoeren zelf hoort bij de editor van BP-11c.
- Kinderprofielen houden hun profielleeftijden tot een ouder de kinderen invoert; de gezinspoort geldt niet op een kinderprofiel, daar geldt de profielpoort.
- Geheugen. Leeftijden van kinderen worden geweigerd, ook als "zoon van bijna 4", "dochter is 2", "kids zijn 3 en 5" en "wordt in maart 4".

## Vragenset en nulmeting

Ongeveer 40 echte vragen, handmatige poort vóór elke build tegen twee modellen; vaste gevallen lopen als gewone tests in CI. Eerste volledige route: "Wat is deze week aan mijn bibliotheken toegevoegd?" (BP-05). De set groeit per fase met de nultolerantiegevallen hierboven.

De nulmeting op de baseline (1b93c50d) volgt in BP-01 vóór de eerste codewijziging; ze staat in het fase-rapport, niet hier, zodat dit document geen statusadministratie wordt.

## Acceptatieaanvulling AUDIT-BIGP-UX1 (8 oktober 2026)

Deze gevallen versterken bestaande pakketten; de herstelronde voltooit die pakketten niet.

- **BP-04b:** “ik”, “anderen”, gemengde doelgroepen, onbekende personen en “vorige week”.
  Onbekend blijft een wedervraag of expliciet gedeeltelijk antwoord; geen gegokte verbreding.
  Bewezen bronrechten blijven ook bij een wijziging tijdens wachten gelden.
- **BP-05:** tekst, kaarten en acties volgen dezelfde bewezen resultaatset en taakstatus.
  Weigeren en verlopen bevestiging bewijzen nul mutaties; één geaccepteerde actie precies één.
  Gedeeltelijke uitvoering behoudt eerdere acties; vroege resultaten heten nog niet volledig klaar.
  “Recent toegevoegd” controleert bron, soort, bibliotheken en expliciet periodevenster.
- **BP-06:** “die tweede”, een andere titelsoort en een andere periode wijzigen alleen expliciet
  gekozen velden; laatst gekozen persoon, titel en periode blijven anders behouden. Nieuw gesprek
  wist gespreksscope. Gestructureerd intentgeheugen krijgt pas acceptatie na implementatie en tests.

Gebruik de bestaande controller/conversation state en de 28 audittoestanden per bestaande flow.
Unit/widget, simulator, echte providers/bevoegdheden en fysieke Apple TV zijn afzonderlijke poorten.

## Besluiten van Michel (5 oktober 2026)

1. Akkoord op nultolerantielijst en voorrang.
2. DEC-005 is als architectuurbeslissing teruggedraaid. BP-07 blijft achter de echte Trakt-poort: geslaagde device activation, tokenuitgifte, verversen zonder secret en correcte tokenrotatie. Werkt dat niet betrouwbaar, dan PKCE. Stand 11 oktober 2026: de poort is geslaagd zonder secret (device code, token, refresh en rotatie, revoke; bewijs in `docs/ROADMAP.md`, "BP-07 Trakt-poort"), dus de PKCE-terugval is niet ingegaan. Het bewijs is één activatie van één account; blijft Trakt dit gedrag niet toestaan, dan geldt de terugval alsnog.
3. Pleya Server zonder externe id's en beoordelingen is voorlopig een capaciteitsgat (zie boven).
