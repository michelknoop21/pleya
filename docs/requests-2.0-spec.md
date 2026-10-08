# Requests 2.0 — functionele audit en productspecificatie

Roadmap: A-19. Bronbaseline: `bdedec38` (8 oktober 2026), aangevuld met AUDIT-TV-UX1. Dit document beschrijft gedrag en ontwerpdekking; detailstatus blijft bij de bestaande roadmap/registers. Bronanalyse is geen simulator-, backend- of hardwareacceptatie. A-20 maakt de volledige set; A-21 bouwt pas na expliciete ontwerpapproval.

## Productcontract

De kijker ziet wat beschikbaar, al aangevraagd of nog aan te vragen is, welke volgende actie toegestaan is en wat het resultaat daarvan was. Zoeken, ontdekken en aanvragen delen terugkeercontext; een mislukte actie verliest query, gekozen titel of geldige formulierkeuzes niet. Een lege lijst is geen fout. Bestaande shell, media-/aanvraagidentiteiten, rollen en geavanceerde functies blijven bestaan. Geen nieuwe backend, root-tab, generiek framework of MVP.

De beschikbaarheidsstatus van Seerr is niet automatisch bewijs van een afspeelbaar item op een voor dit profiel bereikbare Pleya-bron. Alleen bij bewezen bron/item-identiteit mag Beschikbaar een concrete kijkroute openen; anders bied je een begrijpelijke zoekroute in de bestaande bibliotheek met de titel/query behouden. Toon geen afspeelgarantie of exacte bron die niet bekend is.

## Huidige eigenaars en contracts

| Oppervlak | Bestaande eigenaar / gedrag dat behouden blijft |
| --- | --- |
| Profiel/koppeling | `lib/providers/seerr_provider.dart`: sessie per profiel, generation-guard bij profielwissel, `canRequest`, `canManageRequests`, `isAdmin`, 4K-recht per mediatype; account/session/store in `lib/services/seerr/` |
| Ontdekken/zoeken | `seerr_discover_screen.dart`, `mobile_seerr_discover_view.dart`, `tv_seerr_discover_view.dart`, bestaande filters/genres/providers en pagination; eigen catalogus/zoekroutes blijven bij A-06/A-13 |
| Titel/detail | `seerr_media_detail_screen.dart`: film/serie, feiten/cast/afbeeldingen en bestaande overlay-requestroute; succesvolle indiening herlaadt detailstatus |
| Formulier | `seerr_request_sheet.dart`: film en serie, seizoenselectie, nog requestable seizoenen vooraf geselecteerd, selecteer alles, 4K per toegestaan type, bekende quota, dubbele aanvraag blokkeren, submitting-guard en fouten |
| Geavanceerd | Alleen bestaande adminpredicate: Radarr/Sonarr-server, kwaliteitsprofiel en rootfolder; serverwissel/4K wissen en herladen afhankelijke opties zodat geen SD/4K-servermix wordt verstuurd |
| Lijst/beheer | `seerr_requests_screen.dart`, `tv_seerr_requests_view.dart`, `seerr_request_row.dart`: eigen/alle aanvragen, statusfilter/counts, pagina toevoegen, refresh, manager approve/decline en eigen pending cancel met bevestiging; titelhydratie mag een aanvraag niet uit de lijst laten vallen |
| Status/error | `seerr_constants.dart`, `seerr_media.dart`, `seerr_request.dart`, `seerr_status_badge.dart`, `seerr_error_message.dart`: media- en aanvraagstatus zijn aparte modellen; unknown is geen available, null count is geen nul; geen ruwe transportexception als copy |

### Transport en rechten

`SeerrClientRequests` gebruikt bestaande `/request`-routes: GET met take/skip/filter/`sort=added`/requestedBy, GET `/request/count`, POST aanmaken, PUT aanpassen, DELETE annuleren, POST approve/decline. Quota en Radarr/Sonarr-targetdetails blijven de bestaande clientroutes. Geen gewijzigd Seerr-protocol en geen nieuwe capability claim.

- Normale gebruiker ziet eigen aanvragen. Ontbrekend eigen userId mag nooit `requestedBy=null` worden en daarmee ieders aanvragen tonen. Manager kan de bestaande all-scope gebruiken; een expliciete mine-only-keuze blijft ook voor managers eigen scope.
- 4K wordt per film/serie bepaald via `SeerrPermission.canRequest4k`; een 4K-TV-recht maakt 4K-film niet toegestaan. Admin geldt volgens bestaande `SeerrPermission.has` als toegestane predicate, geen nieuwe rolvertaling.
- Lijsttellingen moeten dezelfde scope als de lijst bewijzen. Toon nooit globale counts naast Mijn aanvragen/own-only; zonder bewezen eigen-scopecount laat je het getal onbekend/weg. Het algemene `/request/count` zonder requestedBy bewijst geen eigen count. Bereken een statuscount niet uit slechts één pagina en gebruik geen nul voor een ontbrekend veld of mislukte countfetch.
- Toon bekende quota en bestaande unlimited-semantiek. Onbekende quota worden niet als nul of onbeperkt gefabriceerd. De backend beslist uiteindelijk; een 403/401/409 is geen aanleiding om frontendrechten te verruimen of blind opnieuw in te dienen.
- Mutationele acties blijven bevestigd waar nu bevestigd en worden eenmaal verstuurd. Een transportonzekerheid na verzenden is geen bewijs dat niets is aangevraagd; behoud bestaande accepted-2xx-afhandeling en herlees resultaat vóór een eventuele nieuwe aanvraag.
- Succes herlaadt detail, lijst én relevante counts via bestaande eigenaars; een oude response na profiel-/filterwissel mag de nieuwe context niet terugzetten. Beheerrechten voor mediaservers blijven apart van Seerr-rechten.

## Actuele auditgaten, geen reeds gebouwde functies veronderstellen

1. TVUX-36: on-gefilterd lege TV-lijst biedt Retry; correct leeg krijgt een route naar het bestaande ontdekken/zoeken. Gefilterd leeg behoudt Filters wissen; echte error behoudt Retry.
2. Op TV opent een aanvraagkaart de titel. De ownercomment zegt manageracties via contextmenu, maar de onderzochte TV-view/card heeft geen gekoppelde approve/decline/cancel-callback. Dat is een brongebaseerd parity-gat voor A-20/A-21, geen bewijs dat die acties al werken op Apple TV.
3. `updateRequest` bestaat als client-API; de actuele `lib`-callers inventaris toont alleen zijn definitie, geen edit-UI. Ontwerp de toegestane editroute volledig en toets backendvoorwaarden; claim geen bestaande schermacceptatie. Dit behoudt de geplande volledige functionaliteit uit de roadmap, zonder een afwezige UI als gebouwd te registreren.
4. Available-detail heeft nu een disabled Available-knop; geen bewezen brongebonden kijkroute. De productspecificatie hierboven bepaalt wanneer kijken versus zoeken gepast is.
5. Countscope/unknown: `getRequestCounts` heeft geen requestedBy en zet ontbrekende velden/fetchfouten om in nul; `_loadCounts` onderdrukt alleen expliciet `widget.mineOnly`, terwijl `_load` ook niet-managers als own-only behandelt. Zonder backendbewijs kan die count niet als eigen-scopecount gelden. Dit is een brongebaseerd scope-/unknown-gat voor A-21, geen bewezen datalek of runtimecount.
6. TVUX-14–20 geven aanvullende zoek/catalogus/filter-oriëntatie; TVUX-34–39 geven requeststates, formulieren en terugkeer. Het zijn inputvensters, geen aparte implementatietaken of nieuwe shellopdracht.

### A-21 protocolcontrole, 8 oktober 2026

A-20 inclusief zeven keuzes is goedgekeurd na Impeccable polish en onafhankelijke review.
De volgende technische grenzen wijzigen geen rechten of productkeuzes en bewijzen geen
geïnstalleerde serverversie. Ze zijn gecontroleerd in de officiële Seerr-bron op
[`53e45647`](https://github.com/seerr-team/seerr/blob/53e45647acc92a8e9a18b68e7c6429fdf2de55be/server/routes/request.ts)
en de bijbehorende MovieRequestModal/TvRequestModal.

- PUT vereist het werkelijke `mediaType`; de route verwerkt `is4k` niet. Bewaar bestaande
  kwaliteit, kies advanced targets voor die kwaliteit en gebruik de goedgekeurde unsupported-route
  wanneer kwaliteit bewerken niet ondersteund is. Geen stille vervangingsaanvraag of vals succes.
- PUT schrijft server/profile/rootFolder/tags en bij series languageProfileId; weglaten is geen
  bewezen PATCH-behoud. Bewaar onbewerkte waarden uit de verse aanvraag, de eigenaar en de
  oorspronkelijke identiteit. Een lege seizoenselectie annuleert niet stilzwijgend.
- De gecontroleerde GET-route kent geen `declined`-filter: die waarde valt terug op alle statussen.
  Een gedeeltelijke pagina lokaal filteren bewijst geen volledige lijst Afgewezen. Gebruik uitsluitend
  bewezen filtergedrag of complete bevoegde gegevens; toon onbekende/niet ondersteunde uitkomsten
  expliciet in de bestaande fout-/herstelroute.
- `count.available` en de available-lijst hebben op deze bron verschillende requeststatuscriteria;
  processing-countcriteria verschillen ook. Toon geen decoratieve count als bewezen lijsttotaal
  zonder overeenkomende criteria. Een scoped `pageInfo.results` is geen statusrailcount voor een
  andere filter en een paginalengte is geen compleet totaal.
- Eigen pending series bewerken is toegestaan; eigen film bewerken vereist ook advanced-recht,
  terwijl managers beide kunnen. De app behoudt haar goedgekeurde rolgrenzen en de server beslist.
  Een ontvangen 2xx/202 op edit moet worden herlezen op het werkelijk behouden resultaat; onbekende
  uitkomst blijft de statuscontrole-route van 8J, nooit blind herhalen.

## Volledige A-20 Northstar-dekking

Elke familie hieronder krijgt alle genoemde staten/rollen en de passende TV-, touch- en desktoppresentatie. Deel compositie waar bestaand gedrag werkelijk gedeeld is, maar één iPhone-/TV-beeld bewijst niet de andere platforms. Maak onderscheid tussen ontwerp, implemented en accepted. Gebruik de bestaande Requests-beelden/DEC-108 als basis; veranderingen die hun keuze wijzigen vragen expliciet akkoord.

| Familie | Verplichte staten en acties |
| --- | --- |
| Ontdekken | Geconfigureerd/niet geconfigureerd, geladen/loading/leeg/fout/retry; bestaande ontdekfilters, pagination en terugkeer naar gekozen kaart |
| Zoeken | Native TV-invoer, query/resultaten, beschikbare/requestable/al aangevraagde titels, geen match, incomplete/error state alleen als bekend, queryoverdracht naar bestaande bibliotheek/requestsroute |
| Detail film/serie | Unknown, pending, processing, partial, available en request-afwijzing waar bekend; betekenisvolle toegestane volgende actie, cast/facts, brononzekerheid, terugkeer en refresh |
| Aanvraag film | Samenvatting van titel/kwaliteit, 4K toegestaan/niet toegestaan, bekende/onbekende/uitgeputte quota, duplicate, geen recht, submitting, fout/herstel en bevestigd resultaat |
| Aanvraag serie | Alle/een/meerdere nog requestable seizoenen, deels beschikbaar/aangevraagd, selecteer alles, geen requestable seizoen, lange scrolllijst, 4K en quota; dezelfde indien-/herstelstaten |
| Advanced target | Admin/non-admin, SD/4K-serverkeuze, profiel/rootfolder, loading/error/geen configuratie, wijziging met afhankelijke keuzes herladen; geen stil behoud van ongeldige eerdere target |
| Aanvragenlijst | Eigen/alle (manager), alle bestaande filters/counts/sortbetekenis, loading, leeg, gefilterd leeg, fout, pagination/load-more-fout, statusverandering, terugkeer naar kaart; onbekende/ontbrekende counts expliciet |
| Aanvraagbeheer | Pending approve/decline waar toegestaan, eigen pending cancel met bevestiging, toegestane edit en unsupported/forbidden, action-busy/fout/succes, refresh en focusherstel; TV via bestaande contextmenu-/overlaycontracten |

Dezelfde gedragsdekking geldt voor toepasselijke bestaande Flutter-platforms: tvOS, Android TV, iOS/iPadOS, Android en desktop (macOS/Windows/Linux). Native keyboard/touch/D-pad en platformvoorwaarden blijven eigen contracts. Pleya Web is niet automatisch een Requests-surface; uitbreiden daarnaartoe vraagt dezelfde productspec en expliciete bestaande Webwerkpakketten.

## A-21 acceptatiecontract

Behoud regressiecoverage voor permissions, profielwisseling, 4K-serverselectie, quota, seizoenen, duplicaten, hydration-failure en pagination. Bestaande tests zijn onder andere `seerr_permissions_test.dart`, `seerr_service_server_selection_test.dart`, `seerr_request_sheet_test.dart`, `seerr_requests_pagination_test.dart` en TV discovery/requests-view-tests; hun bestaan is geen bewijs voor nog niet gebouwde beheer/edit-/kijkroutes.

Elke nieuwe correctie heeft reproductie/root cause, rode negatieve controle, gerichte tests, codegate, onafhankelijke adversarial review en scoped fixreview. Relevante UI heeft geregistreerde automation-IDs, Pleya Verify-assertions en beoordeelde actuele screenshots. Hardwareafhankelijk gedrag vraagt fysieke acceptatie. Noteer code complete, tests complete, simulator verified en hardware verified afzonderlijk in bestaande registers. Geen volledige acceptatie op basis van CI, goldens of Northstarpixels.
