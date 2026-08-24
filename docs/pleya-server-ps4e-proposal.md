# Roadmap deviation proposal: PS-4E, PS-7N, PS-7A, en de knip in PS-4W

**Status:** goedgekeurd 24 augustus 2026, vastgelegd als [DEC-073](DECISIONS.md)
**Auteur:** Michel Knoop
**Betreft:** [docs/pleya-server-architecture.md](pleya-server-architecture.md) hoofdstuk 23,
[docs/pleya-server-masterplan-proposal.md](pleya-server-masterplan-proposal.md) 16.3 (PS-4W),
[docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md](PLEYA-SERVER-REPLACEMENT-MATRIX.md) 5.3 en 5.4

Dit voorstel volgt de zes onderdelen uit
[hoofdstuk 23.1](pleya-server-architecture.md#231-de-roadmap-is-een-contract). Het is vastgelegd
voordat er een regel PS-4E-, PS-7N- of PS-7A-code is geschreven. PS-3W en PS-4 zijn gesloten; PS-4W
staat in het masterplan als goedgekeurde fase maar is niet begonnen.

---

## 1. De oorspronkelijke aanname

PS-3W levert een webclient met de belofte dat Pleya Web daarna de primaire beheerinterface wordt
(PS-3W-voorstel 5.4). De achterliggende aanname was dat verdere webfunctionaliteit vanzelf volgt uit
latere fasen die de webclient toch al raken: PS-4 levert kijkstatus, PS-4W levert een speler, PS-7
levert metadata, en Pleya Web plukt daar telkens een stuk van mee.

Die aanname veronderstelt ook dat wat een fase technisch oplevert, ook werkelijk aankomt bij de
client die het gebruikt. Voor PS-4 gold dat: de matrixregel "Verder kijken" staat vandaag al op
**Technisch gereed** ([`PLEYA-SERVER-REPLACEMENT-MATRIX.md:160`](PLEYA-SERVER-REPLACEMENT-MATRIX.md)),
vooruitlopend op precies dat.

## 2. De nieuwe bevinding

Vijf dingen, elk verifieerbaar tegen de code zoals hij op de laatst gesloten commit stond.

**Ten eerste, en dit stuurt de rest van het voorstel: het doel van dit werk is niet gecodeerd, alleen
geïmpliceerd.** Nergens in de roadmap staat met zoveel woorden wat "de webbeleving app-paritair
maken" precies betekent. Het is niet "zo dicht mogelijk tegen de Flutter-app aan", en het is ook niet
"een werkende speler, ongeacht hoe de schil eruitziet". Het is allebei tegelijk:

> **Pleya Web moet zowel herkenbaar dezelfde Pleya-interface krijgen als de bestaande app, als
> daadwerkelijk bruikbaar worden om media te bladeren, openen en afspelen. Visuele pariteit zonder
> bruikbaarheid is onvoldoende, maar bruikbaarheid met een afwijkende generieke webinterface is
> eveneens geen geslaagde oplevering.**

Zonder die zin ergens vastgelegd is elke latere afweging tussen "lijkt het genoeg op de app" en "werkt
het al" een losse beslissing per PR in plaats van een getoetst criterium.

**Ten tweede: de hubs zijn stubs, en de capability liegt erover.** `handleHub` in
`internal/api/handlers_library.go` geeft voor `continue_watching` en `next_up` onvoorwaardelijk een
lege `ItemPage` terug, met een comment die uitlegt dat dit de normale toestand is "van een
catalogusserver die nog niet kan afspelen". Dat commentaar dateert van vóór PS-4. Sinds PS-4 gesloten
is, staat `capabilities.watch_state` op `true` zodra de watch-store bestaat
(`handlers_auth.go:65`, `WatchState: s.opts.Watch != nil`), en dat is in elke productieconfiguratie
het geval. De server claimt dus een capability die hij op dit ene punt niet levert. Gevolg tot in de
Flutter-app: `fetchGlobalHubs` filtert lege hubs weg
(`lib/services/pleya_server_client/parts/browse.dart:239`), dus "Verder kijken" ontbreekt ook daar op
een Pleya Server-verbinding, ook al staat de matrixregel al op Technisch gereed.

**Ten derde: `?width=` is een bewust gedocumenteerd deferral, geen verborgen bug.** De doc-comment op
`handleArtwork` (`handlers_media.go:27-32`) zegt expliciet dat de width-parameter niet verwerkt wordt
en legt uit waarom: "Afgeleide formaten renderen en cachen hoort bij PS-7". Dat is dus geen leugen in
de code, wél een reëel gat dat een browserraster van dertig posters op ware grootte laat laden. De
Flutter-app stuurt de parameter wél, geclamped op 1-4096 (`parts/artwork.dart:31`), en krijgt hem
zonder fout genegeerd.

**Ten vierde: er is geen fase die de webclient naar afspelen brengt zonder een gat te laten.**
PS-3W is bevroren en heeft geen opvolger. PS-4W (masterplan 16.3, "Pleya Web: afspelen en kijkstatus")
dekt de speler, maar expliciet niet de schil eromheen: geen aangepaste hero, geen NEW-badge, geen
detailpagina met samenvatting. Wat PS-4W wél in scope zet, staat op gespannen voet met zijn eigen
"Backendwijzigingen: geen"-regel: acceptatiecriterium 5 luidt "de rijen Verder kijken en Nieuwe
afleveringen vullen zich na een kijksessie", en die rijen zijn precies de hubs die vandaag leeg zijn.
PS-4W kan dat criterium vandaag niet halen zonder de fout uit bevinding twee te repareren, en die
reparatie hoort qua onderwerp niet bij PS-4W maar bij PS-4.

**Ten vijfde: PS-4W's eigen aanname over browserplayback is nooit gemeten.** PS-4W's scope zegt "geen
transcoding en geen HLS: een MKV die de browser niet speelt levert een melding op". Dat is een
correcte scope-keuze, maar er staat nergens een cijfer bij hoeveel van de echte bibliotheek daardoor
wél of niet speelt. `<video>` in een browser ondersteunt lang niet elke container/codec-combinatie
die de scanner catalogiseert; met name HEVC, DTS, TrueHD en PGS-ondertitels zijn bekende
probleemgevallen. Stopcriterium 5 van PS-4W ("iemand kijkt een film uit in een browser") is pas een
zinnige claim over het product als bekend is welk deel van de bibliotheek die claim waarmaakt.

## 3. Waarom de huidige roadmap daardoor niet meer klopt

**PS-3W-voorstel 5.4 heeft geen drager.** Het belooft dat Pleya Web de primaire beheerinterface
wordt. Er is geen fase die dat ooit oppakt, en er is ook geen fase die de mediabeleving eromheen
optilt naar wat nodig is om die belofte geloofwaardig te maken.

**PS-4 is niet volledig gesloten gebleken op zijn eigen matrixclaim.** De matrix zegt dat "Verder
kijken" Technisch gereed is; de code op de webclient-consumptieroute laat zien dat dat voor het
`continue_watching`/`next_up`-hubpad niet klopt. Dat is geen nieuwe fase, het is een gat in een
gesloten fase dat gerapporteerd en gecorrigeerd hoort te worden, precies zoals onderhoudsregel 3 van
de matrix voorschrijft ("een gat wordt nooit stil gesloten").

**PS-4W kan zijn eigen acceptatiecriterium 5 niet halen zonder een reparatie buiten zijn scope.** Een
fase die voor zijn eigen stopcriterium leunt op een fix in een andere, gesloten fase, moet die
afhankelijkheid expliciet maken, niet stilzwijgend meenemen als scope-uitbreiding.

**PS-4W's voortgangsweergave hoort logisch bij lezen, niet bij de browserspeler.** PS-4W zet
"voortgangsbalken op `MediaCard`" en de twee hub-rijen in zijn scope, samen met de speler zelf. Maar
een voortgangsbalk is presentatie van bestaande watch state (`user_state.position_ms`,
`user_state.watched`), die al meekomt op elke item- en hubresponse via `hydrateItems`, zonder dat er
één regel browserspelercode voor nodig is. Wie op de webclient zonder speler naar Home gaat, moet nu
al kunnen zien wat hij aan het kijken is. Dat vastbinden aan de speler-fase betekent dat een gebruiker
die alleen browst en niet in de browser afspeelt (bijvoorbeeld omdat hij de Flutter-app gebruikt om
te kijken) nooit voortgang op de webclient ziet, ook niet nadat PS-4E live is.

**Er is geen poort die de browser-afspeelbaarheid van de echte bibliotheek meet.** De vijf poorten in
`docs/pleya-server-gates.md` gaan over autorisatie, validators en sessies. Geen ervan meet of de
media zelf in een `<video>`-element speelt. Zonder die meting is "Pleya Web kan afspelen" een
bewering over de code, niet over het product.

**Er is geen vastgelegde grens voor wanneer metadata ontbreekt.** PS-7N (hieronder) hangt af van hoe
goed de bibliotheek is voorzien van `.nfo`-bestanden. Zonder een vooraf afgesproken en binaire
drempel wordt de vraag "is dit goed genoeg" een oordeel achteraf in plaats van een poort vooraf.

## 4. De concrete voorgestelde wijziging

### 4.1 Drie nieuwe fasen

**PS-4E, Pleya Web: app-paritaire beleving.**

| Veld | Inhoud |
| --- | --- |
| Phase ID | PS-4E |
| Doel | Pleya Web krijgt herkenbaar dezelfde Pleya-interface als de app (schil, hero-carrousel, kaarten, detailpagina), én toont bestaande watch state (voortgang, watched-status, Verder kijken, Nieuwe afleveringen) |
| Afhankelijkheden | PS-3W, PS-4 (na de correctie in 4.2) |
| Eerstvolgende fase | PS-4W |

In scope: schil en navigatie, hero-carrousel, kaarten met NEW-badge/watched-vinkje/**voortgangsbalk**,
Home met de drie hubs (Verder kijken, Nieuwe afleveringen, Recent toegevoegd), detailpagina met
samenvatting en genres uit PS-7N waar beschikbaar.

Buiten scope: de speler zelf, elke vorm van watch-state-*schrijven* vanuit de browser, seek- of
playbackrapportage. **PS-4E introduceert geen nieuwe watch-state writes.** Wat een gebruiker op de
webclient ziet, is uitsluitend een weergave van state die de app of een eerdere sessie al heeft
geschreven.

**PS-7N, lokale sidecar-metadata.** Een uitsnede van PS-7, laag 2 van de vijflaagse
prioriteitsvolgorde die het masterplan in 7.3 beschrijft. Drie velden: `summary`, `genres`,
`content_rating`. Cast, beoordelingen, studio, externe ids en logo-artwork blijven bij PS-7.
Voorwaardelijk: alleen uitvoeren als de coverage-gate in 4.3 op **minstens 80%** uitkomt.

**PS-7A, afgeleide artworkformaten.** De tweede uitsnede van PS-7: `?width=` werkend maken, met
cache, single-flight bij gelijktijdige cache miss, en terugval naar het origineel bij een
niet-decodeerbaar bronformaat.

### 4.2 Correctie op PS-4 (geen nieuwe fase)

De hub-implementatie is geen nieuwe fase maar een defectcorrectie in een gesloten fase: het endpoint
bestaat, de capability adverteert hem, en het antwoord is leeg. `docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md:160`
("Verder kijken | ... | PS-4 | Technisch gereed") wordt na de fix bevestigd in plaats van
gecorrigeerd.

Regel `:162` ("Volgende aflevering bij een serie") blijft daarentegen **In roadmap**. Een eerdere
lezing van dit voorstel zette hem op Technisch gereed zodra `next_up` echte data levert, en dat is bij
nader inzien een overclaim: de bewijskolom van die regel luidt "detailscherm toont de juiste volgende
aflevering", en dat is een per-item on-deck. Het protocol kent daar geen veld voor, en
`fetchItemWithOnDeck` (`lib/services/pleya_server_client/parts/browse.dart:143`) geeft nog steeds
`null`. De hub krijgt daarom een eigen regel ernaast, op PS-4 en Technisch gereed, met de hub zelf als
bewijs. Alles in dezelfde commit als de codefix, niet losstaand.

De `next_up`-semantiek wordt bij die fix normatief vastgelegd in hoofdstuk 15 van
`docs/pleya-protocol-v1.md` en in de hub-beschrijving van `docs/pleya-protocol/v1/openapi.yaml`,
zodat web en Flutter-client nooit een verschillende betekenis aan dezelfde hub kunnen geven: per
serie precies één rij, de laagst genummerde ongekeken aflevering na de hoogst genummerde aflevering
waar deze identiteit kijkstatus op heeft, met `season.item_index >= 1` en een niet-lege `item_index`,
dus met specials en ongenummerde afleveringen uitgesloten als kandidaat én als ankerpunt. Een serie
zonder kijkactiviteit staat niet in de hub.

Die tekst is vóór implementatie getoetst aan wat de Flutter-client vandaag al van `next_up` verwacht,
met de afspraak dat de bestaande clientverwachting wint bij een afwijking. Er is er geen: `_hub()`
(`lib/services/pleya_server_client/parts/browse.dart:301`) typeert `next_up` als `episode` en
`continue_watching` als `mixed`, en beide lopen door dezelfde cursorwandeling als `recently_added`.
De client legt verder niets vast, dus de semantiek hierboven vult een gat in plaats van er een te
overschrijven.

### 4.3 De knip in PS-4W

PS-4W (masterplan 16.3) behoudt zijn Phase ID, zijn doel en het grootste deel van zijn scope. Twee
onderdelen verhuizen naar PS-4E, en één voorwaarde komt erbij:

**Verhuist naar PS-4E (lezen):** "De rijen Verder kijken en Nieuwe afleveringen op Home, en
voortgangsbalken op `MediaCard`" uit PS-4W's Scope-paragraaf. PS-4W blijft verantwoordelijk voor het
*schrijven*: kijkstatus rapporteren als gebeurtenis, `session_id`, `playback_started`,
`base_revision`, hervatten vanaf `user_state.position_ms`. De grens:

> **PS-4E leest bestaande watch state en toont die waar de app dat ook doet. PS-4E introduceert geen
> nieuwe watch-state writes vanuit de browser. PS-4W is en blijft verantwoordelijk voor seek- en
> playbackrapportage en voor het tijdens browserplayback bijwerken van die state.**

PS-4W's acceptatiecriterium 5 ("de rijen Verder kijken en Nieuwe afleveringen vullen zich na een
kijksessie") blijft geldig en wordt aantoonbaar zodra PS-4E er al staat: de rijen bestaan dan al, en
PS-4W hoeft alleen te bewijzen dat een kijksessie ze bijwerkt, niet dat ze uit de grond komen.

**Nieuwe voorwaarde: de browser-playability-poort.** Vóór PS-4W's stopcriterium ("iemand kijkt een
film uit in een browser") als gehaald geldt, moet een read-only meting op de echte NAS-bibliotheek
liggen met minstens: containerverdeling, videocodec, audiocodec, ondertitelformaat, en de indeling in
vier emmers (direct afspeelbaar, video wel/audio niet, container niet compatibel, overig), apart voor
films en afleveringen. Geen harde stopgrens op het percentage, wel een harde regel:

> **PS-4W wordt niet afgesloten met de claim "Pleya Web kan media afspelen" zonder dat percentage
> gemeten en gerapporteerd te hebben.** Valt het aandeel direct afspeelbare media op de echte
> bibliotheek laag uit, dan is dat een terugmelding vóór verdere implementatie dat de productmijlpaal
> zonder een deel van PS-6 of PS-8 niet haalbaar is, niet een reden om de speler alsnog op te leveren
> en het probleem in productie te laten opvallen.

### 4.4 De NFO-coverage-gate, binair

Vóór PS-7N wordt uitgevoerd:

> **coverage = percentage films en series per bibliotheek met een geldige, parsebare `.nfo` én een
> niet-lege `<plot>`.** Genres en kijkwijzer worden gerapporteerd maar tellen niet mee in dit getal.
> **≥80% per bibliotheek die in de UI meetelt:** PS-7N uitvoeren.
> **<80% in een bibliotheek:** PS-7N wordt voor die bibliotheek niet als oplossing geaccepteerd; er
> volgt een apart voorstel voor een minimale provider-slice. "Geen metadata" is geen fallback.

De drempel geldt per bibliotheek, niet op het gewogen totaal over de hele mediaverzameling: één grote
goed onderhouden filmbibliotheek mag een kaal gebleven seriebibliotheek niet wegmiddelen.

### 4.5 Wat er in de andere documenten verandert

`docs/pleya-server-architecture.md` hoofdstuk 23 krijgt PS-4E, PS-7N en PS-7A als fasen, met het
diagram in 23.2 aangevuld: `P3W --> P4E`, `P4 --> P4E`, `P4E --> P4W`, `P2 --> P7N`, `P2 --> P7A`.
`docs/pleya-server-masterplan-proposal.md` 16.3 wordt bijgewerkt met de knip uit 4.3 hierboven; de
rest van PS-4W blijft ongewijzigd staan. `docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md` krijgt de correctie
uit 4.2 en nieuwe regels voor wat PS-4E, PS-7N en PS-7A afleveren. `docs/DECISIONS.md` krijgt DEC-073
voor dit voorstel en voor het protocolvenster van 4.2; dat nummer volgt op de PS-9-reeks, die op
DEC-072 eindigde.

### 4.6 Het protocolvenster voor PS-7N

`summary`, `genres` en `content_rating` zijn nieuwe optionele velden in een bestaand antwoord, en dat
is regel 1 van hoofdstuk 3: toegestaan, want een client die ze negeert blijft correct werken. Geen van
de andere vijf compatibiliteitsregels wordt geraakt. Maar het contract is bevroren zolang de lopende
fase loopt, en het PS-9-venster (DEC-068) is open voor precies zeven wijzigingen en sluit zodra
`check_protocol.sh` daarna slaagt. **PS-7N heeft daarom een eigen venster nodig, met een eigen DEC
eronder**, te openen bij de uitvoering van stap 5 uit het bijbehorende implementatieplan en te sluiten
zodra `check_protocol.sh` na die drie velden weer slaagt.

## 5. De gevolgen voor latere fasen

**PS-7 verliest twee uitsnedes en houdt de rest.** Cast, beoordelingen, studio, tagline,
releasedatum, externe ids, logo-artwork, matching, en de providerladder zelf blijven volledig bij
PS-7. PS-7N neemt drie velden mee op basis van lokale sidecars, niet op basis van een externe
provider; PS-7's eigen matchpatroon en providerlaag worden hier niet vooruitgebouwd. `detection`
(de herkomstlaag met bron en status per veld, zoals `media_versions`/`media_streams` al kennen) komt
in PS-7N bewust niet mee, want met precies één bron per veld is er niets te onderscheiden; dit is een
bekende toekomstige migratie voor PS-7, hier vastgelegd en niet vooruit gebouwd.

**PS-4W wordt uitvoerbaar op de manier die zijn eigen acceptatiecriterium 5 altijd al vroeg.** Zonder
de knip in 4.3 zou PS-4W ofwel zijn "Backendwijzigingen: geen"-belofte breken, ofwel een
acceptatiecriterium dragen dat het niet kan halen zonder buiten zijn scope te werken.

**PS-11A schuift op in de tijd maar niet in de afhankelijkheidsgraaf.** De gekozen doorloop na PS-4
blijft PS-5, PS-9, PS-11A, en daarna PS-6, PS-7, PS-8
(`docs/pleya-server-phase-order-deviation.md`). PS-4E, PS-7N en PS-7A hangen alle drie aan fasen die
al gesloten zijn (PS-2, PS-3W, PS-4) en voegen geen nieuwe afhankelijkheid toe aan PS-9 of PS-11A.

**Twee bekende gaten gaan naar de backlog in hoofdstuk 24.3, niet mee in dit spoor.**
Aanbevelingsrijen ("Omdat je X gekeken hebt") blijven een roadmap gap tot PS-7 een relatie-endpoint
levert. De achttien hardcoded Engelse foutstrings in `pleya_web/src/lib/errors.ts:80-99` zijn een
bestaand defect van vóór dit voorstel en worden niet stilzwijgend meegefixt.

## 6. Welke scope hierdoor vervalt

Geen enkele bestaande fase verliest scope die hij niet expliciet naar een andere goedgekeurde fase
verhuisd ziet. PS-4W is de enige fase die hier daadwerkelijk wijzigt: hij levert twee scope-items
(de twee hub-rijen en de voortgangsbalk) niet meer zelf op, omdat PS-4E ze eerder aflevert. Dat is
geen vervallen scope maar een verplaatsing binnen dezelfde totale levering, expliciet vastgelegd in
4.3 en niet stilzwijgend doorgevoerd via een latere PR.

Wat wél vervalt ten opzichte van de aanname in onderdeel 1: het idee dat de webclient app-pariteit
"vanzelf" krijgt als bijvangst van latere fasen. Die aanname wordt vervangen door een eigen fase met
een eigen stopcriterium.
