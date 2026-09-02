# Changelog

Sessie-voor-sessie logboek. Nieuwste bovenaan. Ouder werk staat in
[docs/archive/CHANGELOG-2026-08-07-tot-19.md](archive/CHANGELOG-2026-08-07-tot-19.md) en
[docs/archive/CHANGELOG-tot-2026-08-06.md](archive/CHANGELOG-tot-2026-08-06.md).

## [2026-09-02] De eindaudit van fase 9, en de acht dingen die eronder lagen

Eén strikt lezende audit over `ee72260..HEAD`, tegen de DoD, het register en de DEC's. Acht
bevestigde defecten, alle acht in code die fase 9 zelf schreef of aanraakte, en alle acht met een
test die vóór de fix omvalt — bij twee daarvan is die negatieve controle ook echt gedraaid en niet
alleen beredeneerd.

**Een trage catalogus meldde zich leeg.** `_fillBuffers` begrenst zijn wachttijd op
`progressiveLoadingGrace` (E5), en dat is goed voor resultaten die er al zijn. Waren er er nog géén —
elke bibliotheek trager dan twee seconden, wat over WAN met twee servers niet exotisch is — dan gaf
`loadMore` een snapshot met nul groepen die niet `isComplete` was, en dat tekent hoofdstuk 29 als
"Deze bibliotheek is leeg", paginabreed. Niets haalde dat weg: het raster dat `onLoadMore` aanroept
wordt pas gebouwd als er groepen zijn, en de bibliotheekset was niet veranderd dus er volgde geen
herstart. Nu wacht `loadMore` in precies dat ene geval — niets gepopt, niets ooit gepopt, en een
fetch nog onderweg — op de lopende fetch. E5 blijft heel: zodra er één item is om te tonen wacht er
niets meer, en die grens staat als eigen test naast de fix. Onderweg bleek de eerste versie een
tweede aanvraag voor dezelfde pagina uit te lokken; de cursors die tijdens dat wachten alsnog falen
gaan nu op dezelfde manier op de "niet nog eens deze ronde"-lijst als na een gewone golf.

**Het concurrencyplafond telde de verkeerde dingen.** Dezelfde genadeperiode laat een golf in de
lucht, en de lus stapte per ronde een vaste `maxConcurrentFetches` op. Het aantal open verzoeken
groeide dus met elke ronde. Het plafond meet nu wat er echt loopt.

**`updateItem` haalde op een tweede server de verkeerde titel op.** Een backend-item-id is alleen
binnen zijn eigen server uniek — twee Plex-servers nummeren allebei vanaf 1 — en de eigenaar werd
gezocht door de zichtbare lijsten af te lopen op een kále id-match. De hele fase draait op
`serverId:itemId`; dit pad was de uitzondering, en juist fase 9 heeft de multi-serverschermen eraan
geknoopt. Film uitkijken op server A gaf zo een refetch van een ongerelateerde titel van server B, in
de rij waar A's kaart stond: verkeerde titel, verkeerde artwork, verkeerde route bij de volgende
Select. De eigenaar gaat nu mee en de match loopt over `globalKey`.

**Twee tellingen die iets wegdeelden.** Een auth-foute membership viel uit álle drie de emmers van
`resolveUnifiedActionTarget` — niet bruikbaar, en bewust niet uitstelbaar — dus "klaar op alle 1"
terwijl een tweede server niets kreeg, en omdat dat als compleet leest zei de app helemaal niets. De
emmer is nu de rest van de groep in plaats van een eigen conditie, waardoor elke membership in precies
één emmer valt. Dezelfde soort stilte bij het cijfer: een membership op een backend zonder
`userRating` werd overgeslagen zonder geteld te worden, en DEC-075's "bereikt wat het kan en meldt de
rest" meldde dus niets.

**En een die de verkeerde uitweg wees.** Is élke membership uitgelogd, dan zei de melding "geen bron
bereikbaar" — hoofdstuk 14.7's tekst voor het offline geval, dat naar serverbeheer stuurt. De server
is juist wél bereikbaar en wil dat je opnieuw inlogt. Er is een tweede blokkade bijgekomen die de
woorden gebruikt die de bronkiezer voor dezelfde toestand al heeft, in alle vijftien talen. Een groep
die half offline en half uitgelogd is houdt de algemene tekst: daar zijn het twee uitwegen.

**De G7-poort werd op de hele groep gelezen.** Het commentaar erboven zegt "de *overlevende*
kandidaten", de code rekende hem uit vóór tier 2. Een extended edition van een jaar geleden, die tier
2 er allang uit had gegooid, zette daarmee nog steeds de progressietiers uit voor twee theatrical
memberships: de winnaar viel terug op de volgorde van de map, en de kaart tekende een vinkje over een
half uur echte kijkpositie. De poort leest nu de overlevers. Dat de groep twee versies bevat blijft
gewoon gerapporteerd — dat is een feit over de groep, geen poort.

**Een korte pagina die geen einde was.** `PleyaServerClient` wandelt door cursorpagina's tot het
venster vol is, en stopte na tien pagina's ongeacht wat ze opleverden. Een server die vier per keer
antwoordt gaf dus veertig items voor een venster van vijftig terwijl zijn cursor nog verder wees — en
één laag hoger *is* een korte pagina het einde-van-de-bibliotheek-signaal (E8). De rest van die
bibliotheek verscheen dus nooit, onder een `isComplete` die zei dat de catalogus af was. De grens telt
nu vruchteloze pagina's: een pagina die iets bijdraagt zet hem terug.

**Twee bevindingen waren geen defect.** Dat een trage bibliotheek achteraan aansluit in plaats van
terug te sorteren is precies wat E14 vastlegt. En de attention-dot in de topnav stond op `Positioned`
met een fysieke `right`, wat onder RTL de verkeerde hoek is; dat is dezelfde verwarring die DEC-072
voor de hero-CTA's oploste en is nu richtinggevoelig, met een test die in beide richtingen meet.

**Wat blijft staan, en waarom.** `search_screen.dart` leest de verborgen-bibliothekenset synchroon.
`ensureInitialized()` afwachten hangt de zoekactie op zodra de opslag niet antwoordt — geprobeerd,
zeven schermtests liepen in een `pumpAndSettle`-timeout — en dat is een ergere fout dan het smalle
venster dat het zou dichten. Blijft staan met de redenering van de auteur. De Pleya Server-client
filtert niet op `query.kind`, en dat is nu **B16** in het register: op te lossen door de cursorledger
per kind te sleutelen, wat losstaand bewijs vraagt en niet in een bevroren protocolvenster hoort. De
lokale-mapclient, waar dezelfde belofte gold en geen wire bestaat, filtert wél. En twee opruimpunten
onderweg: een `_loadFailedFocusNode` die nergens aan hing, en een verouderd doc-blok boven
`_fillBuffers` dat het tegenovergestelde beweerde van het blok eronder.

**De visuele checkpoint over dezelfde boom leverde vier meldingen op, en geen ervan is een
productdefect** — nagelopen in plaats van aangenomen. `intro_ident_dissolve.png` is byte-identiek aan
`intro_ident_rest.png`, en dat ís het bewijs: DEC-077 zet onder het ident dezelfde tekening op
dezelfde grond, dus halverwege de dissolve verandert er niets zichtbaars. Dat het écht halverwege is,
staat als assertie op precies dat moment (`0 < overlayOpacity < 1`) en niet in het plaatje. De
"Active"-pil in `focus_contrast_separator_light.png` is wit op bijna-wit, maar die pil is de
controlegroep van de test zelf: het beeld gaat over de scheidingsschaduw van de *gefocuste* pil, en
die staat er. De tofu in de detailgoldens staat als caveat in het testbestand zelf — `monoTheme`
bouwt zijn `textTheme` uit `Typography.englishLike2021`, dat naar een familie wijst die deze app niet
bundelt, terwijl de geometrie waar die goldens voor bestaan wél exact is. En de afgeknipte vierde
bronrij in de picker is de rand van een scrollviewport.

**Eén losse verbetering uit dezelfde audit.** `.ts` telde als HLS-fragment, dus een opgenomen
uitzending op een niet-gemounte schijf las als "de transcoder loopt achter" in plaats van DEC-078's
"Bestand niet beschikbaar". Een echt segmentprobleem noemt zijn playlist of het woord zelf.

## [2026-09-02] De merkgenerator wordt deterministisch, en de laatste oude P is weg

Twee changelogregels hierboven noemen hetzelfde defect en laten het allebei staan: een kale
`gen_brand_assets.py`-run herschrijft zevenenveertig getrackte iconen die pixel-identiek blijven.
Fase 9 heeft de generator zelf gewijzigd, dus het hoorde niet nóg een keer doorgeschoven te worden.
Het besluit staat als DEC-079.

**De oorzaak is de deflate-implementatie, niet een instelling.** Gemeten: IHDR gelijk, IDAT anders,
`tobytes()` over alle zevenenveertig identiek. Sommige bestanden werden kleiner, andere groter — dat
sluit een verschoven compressieniveau uit. Deze Pillow-wielen zijn gebouwd tegen **zlib-ng 2.3.3**,
de omgeving die de getrackte assets schreef gebruikte stock zlib. De scheidslijn is in de historie
exact te trekken: wat op 2 september in deze omgeving is geschreven blijft stabiel, wat van 19 en
28 augustus op de Mac komt verschilt. Byte-identieke PNG-uitvoer is dus niet draagbaar te maken, en
FreeType komt er nog bovenop — dat rastert de tagline, en dáár verschillen de pixels wél.

**Dus is determinisme op de tekening gedefinieerd.** `save()` codeert naar geheugen, vergelijkt de
pixels met wat er al staat, en schrijft alleen bij verschil; voor de multi-size `.ico` per subbeeld.
De encoderinstellingen staan expliciet in plaats van op de Pillow-standaarden te leunen, en de
canonieke omgeving staat gepind in `scripts/requirements-brand.txt`. Het script drukt bij het starten
af waar het op draait. Bewijs: een schone tree na run #1 én run #2, ook met een afgekapte pipe. Geen
enkel van de zevenenveertig bestanden is opnieuw gecommit en er is geen pixel veranderd.

**De valkuil onderweg is de moeite waard.** De eerste versie zette de `print` van een overgeslagen
bestand binnen de `try` om het decoderen. `BrokenPipeError` is een `OSError`, dus een `| head` viel
stil door naar het schrijfpad en herschreef één icoon alsnog — precies het gedrag dat de wijziging
moest wegnemen, en alleen zichtbaar omdat de tree daarna nog werd nagekeken.

**En de laatste oude P is opgeruimd.** Een referentiegraaf over de hele boom vond drie fossielen. Een
dood `wordmark_layers()` in de generator, geschaduwd door de echte, dat nog naar het handgemaakte
lockup wees via een variabele die niet meer bestaat — weg. `assets/pleya.png`, het beeld bovenaan de
repo — hergenereerd. En het echte gat: `pleya_web/static/brand/pleya-mark-{64,256}.png` stonden als
handmatige `sips`-verkleining in een README en leverden aan `app.html`, `NavRail.svelte`,
`+layout.svelte`, `login/` en `setup/` nog altijd de oude, handgemaakte P. Die twee staan nu in de
generator, met dezelfde ondoorzichtige merkgrond en alleen de P van nu; het handmatige recept is uit
de README gehaald. `assets/branding/pleya_mark.png` is daarmee de enige autoriteit voor de P, in de
app en daarbuiten.

**Register gereconcilieerd.** De standregels liepen achter op J19. De eindstand van fase 9 staat er nu
als eigen alinea boven de tussenstanden: **180 van de 188 rijen `covered`**, acht open en allemaal
geclassificeerd — vijf hardware (J2, J4, J8, J9, I17), twee geregistreerde debts (I21, I24) en één
onopgelost productcontract (J14). Per categorie nageteld en niet overgeschreven.

**Eén hardeningspunt geregistreerd, niet opgelost.** `pubspec.yaml` bundelt `assets/branding/` als
map, dus `pleya_lettering.png`, `pleya_mark.png` en `pleya_wordmark.png` reizen mee in elke build
zonder ooit getekend te worden — samen zo'n 2,6 MB. Dat is bundelhardening en geen productgedrag, dus
het staat als fase-10A-punt onder hoofdstuk 27 en is hier bewust niet aangeraakt.

## [2026-09-02] Bestand niet beschikbaar, en een melding die weer weggaat

Twee klachten uit dezelfde avond, met dezelfde oorzaak eronder: de speler wist meer dan hij zei, en
wat hij zei bleef staan. Het besluit staat als DEC-078.

**De schijf was niet gemount, en de app zei "Afspelen gestopt".** Plex levert de metadata en de
part-key ook uit als het bestand onbereikbaar is. De speler bouwde daar een URL van, mpv kreeg een 404
terug en de gebruiker kreeg een kop zonder tekst eronder. De informatie was er wel: `checkFiles=1`
zet `Part.accessible` en `Part.exists`, en `isPlayable` gebruikte dat al — maar alleen om een andere
versie te kiezen. Waren ze állemaal onleesbaar, dan viel de keuze terug op de eerste en werd die
alsnog geopend. `hasPlayableVersion` maakt dat nu opvraagbaar en de Plex-client weigert erop, met een
eigen melding: "Bestand niet beschikbaar", met de regel dat de schijf of map waar het op staat er
misschien niet meer is.

**Eén logregel was te weinig om iets te concluderen.** ffmpeg logt de 404, mpv logt daaroverheen een
algemene "Failed to open", en alleen die laatste bleef bewaard. De speler houdt nu de laatste vier
fout-regels vast en classificeert ze samen. Daarbij is een 404 op het bestand losgetrokken van een 404
op een segment of playlist: die eerste is een bestand dat er niet is, die tweede een transcoder die
achterloopt, en ze stonden in dezelfde bak omdat het segmentpatroon eerder in de reeks kwam te staan.
Jellyfin heeft geen vlag zoals Plex, dus daar is die logregel het enige bewijs dat er is.

**Drie kaarten over een spelende video.** Een fout heeft in het meldingsysteem bewust geen looptijd,
want een fout wil een handeling. Bij afspelen klopt dat niet: de speler is al weg voordat de kaart
verschijnt, en op een tv klikt niemand hem weg. Drie mislukte pogingen lieten dus drie kaarten achter
die over de video hingen die daarna wél startte. Afspeelmeldingen delen nu het groepsvoorvoegsel
`playback:`, staan twaalf seconden, en verdwijnen zodra er beeld is. En een herhaalde blijvende
melding telt op bij de kaart die er al staat — hetzelfde drie keer onder elkaar zeggen is geen
informatie.

**Wat de tests vastleggen.** Dat een 404 op een bestand iets anders is dan een 404 op een segment, dat
een samengevoegde meerregelige log de 404 nog onder de algemene regel vindt, dat elke afspeelmelding
een looptijd heeft en het groepsvoorvoegsel draagt, dat geen ruwe logregel de kaart haalt, dat
`hasPlayableVersion` onwaar is als álle versies onleesbaar zijn en waar als de server geen vlaggen
stuurde, en dat een blijvende melding buiten het dedupe-venster optelt in plaats van te stapelen.
## [2026-09-02] Het ident is nu het lockup op de paginagrond, en verder niets

Michel vroeg of de intro ook bij het nieuwe ontwerp kon passen. Dat kon, en de reden ging verder dan
smaak: de bron van het ident noemde zichzelf "Netflix-style ident" — veertien roterende rode
lichtstralen — en hoofdstuk 31 #10 verbiedt precies dat.

**Drie merkmomenten die het niet eens waren.** tvOS-launch (zwart), daaroverheen het ident (zuiver
zwart, 2800 ms, stralen, een 5x-inslag, een glansveeg, een rechthoekige rode gloed), en daaronder de
bootsplash (warme radiale, ademende halo, de losse P plus "PLEYA" als gespatieerde tekst, dezelfde
tagline op een andere spec). De cross-dissolve op 88% was de naad die je zag.

**Wat er nu staat.** Eén grond — `#141414`, de paginagrond uit de north star, OLED zijn eigen zwart —
zodat het ident oplost in een pagina van dezelfde kleur. Het lockup zet zich van 0,96 naar 1,0 op de
focuscurve, staat even, en lost op; in en uit zijn elk de hero-crossfade van 460 ms. Achttienhonderd
milliseconden in plaats van 2800. De tagline op de spec die de generator al voor de Top Shelf en de
TV-banner hanteert, zodat het ident op het scherm hetzelfde beeld is als op de shelf. En de
bootsplash tekent voortaan hetzelfde plaatje plus de voortgangslijn, dus na het oplossen ligt er niets
anders onder. Staat als DEC-077.

**Drie gebreken die meeliepen.** De lockuplagen werden nooit vooraf gedecodeerd, dus de eerste frames
konden een lege grond tonen. Een afstandsbediening kon het ident niet overslaan — alleen een tik telde
— dus een TV-kijker zat de volle run uit; Select, Enter, Escape en spatie doen het nu. En het ident had
nul tests; er zijn er acht bij en twee goldens, waaronder één die het oplossen over de bootsplash
vastlegt.

Eén randgeval dat de tests boven water haalden: op exact de laatste milliseconde staat de waarde van de
controller op 1 maar zijn status nog niet op `completed`, en de toetsafhandelaar hing aan die status.
Hij kijkt nu naar de waarde, want het ident is weg zodra die 1 is, wat de status ook zegt.
## [2026-09-02] De backend-badge is een bronglyph, en het merkrood blijft waar het hoort

J19 stond sinds vanochtend als klasse C in het register — hij kwam uit het J18-werk van diezelfde
dag. `BackendBadge` tekent vier glyphs uit één `switch`, en de Pleya-P was de enige die de meegegeven
inkt liet liggen. De vraag eronder was niet
technisch maar productmatig, en die is nu beantwoord in DEC-076.

**Het antwoord, en waarom het niet met DEC-074 botst.** Een merk dat zegt *deze app is Pleya* houdt
zijn kleur; een glyph die zegt *dit item komt van een Pleya-server* is bronnotatie en gedraagt zich
als de tekst ernaast. De grens ligt bij de widget: `PleyaLogo` heeft geen kleurparameter en blijft
rood, `BackendBadge` heeft er wel een en honoreert hem nu op alle vier de takken.
`side_navigation_rail.dart` draagt allebei de regels in één scherm — een rode `PleyaLogo` in de kop,
een gedempte badge in de serverrijen eronder.

**De set was de eenheid, niet de tak.** `MediaBackend.local` is een kale Material-map en kan nooit
iets anders dan inkt dragen, en de twee SVG's zijn als `currentColor` getekend, dus Plex-amber en
Jellyfin-blauw waren hier allang opgegeven. Eén glyph die op tien tot achtentwintig pixels wél kleur
voert leest niet als merk maar als toestand: rood is in dit thema progress en actief. Hoofdstuk 8.2
noemt Pleya-rood voor "badges", maar dat gaat over de TV-oppervlakken, en juist daar komt deze widget
niet voor — hoofdstuk 10.3 zegt over de kaart letterlijk "geen serverlogo's op de poster".

**Een tweede gebrek in dezelfde drie regels, meegenomen omdat het geen besluit vraagt.** De badge
tekende `pleya_mark.png`, de handgemaakte bron. De P staat daar op een alpha-bbox van
(39, 128, 931, 938) binnen een kanvas van 1024x1024: 87% van de breedte, 79% van de hoogte, en een
midden dat 27 pixels naar links en 22 pixels omlaag ligt. Naast twee SVG's die hun viewBox vullen
tekende de Pleya-badge dus kleiner en scheef naast zijn buren, en hij trok er een tweede decode van
1024x1024 bij voor een glyph van twaalf pixels. Hij tekent nu het gegenereerde `pleya_logo.png`,
gecentreerd, 95% van zijn breedte vullend, en al in de image-cache omdat `PleyaLogo` het tekent.

**Het bewijs staat op drie plekken omdat geen van de drie de andere twee ziet.** De widgettests lopen
over `MediaBackend.values` in plaats van over de Pleya-tak, zodat een vijfde backend zonder tint hier
ook omvalt. De assetinvarianten staan op de bytes, want `tester.getSize` geeft de doos terug die de
`Image` kreeg en niet wat hij erin tekent — die assertie bleef in de negatieve controle dan ook
groen. En de twee goldens leggen vast dat de inkt ook echt aankomt: een verkeerde blend mode is een
gevuld vierkant, en dat is in geen van de andere twee tests zichtbaar.

**Negatieve controle gedraaid.** Met de oude tak terug vallen precies de vijf Pleya-tests en allebei
de goldens om, terwijl de dertien tests van de andere drie backends groen blijven.

Daarmee gaat J19 van klasse C naar `covered`: 180 van de 188 registerrijen. Wat overblijft zijn de
acht geclassificeerde — vijf hardwarerijen, twee geregistreerde debts en J14.

## [2026-09-02] De P had een oudere tweelingbroer, en die is nu weg

Michel keek naar het lichte beeld uit de vorige sessie en zag het meteen: dat is de P van het oude
logo. Dat klopte, en het reikte verder dan de topnav.

**Twee P's, en niets dat ze bij elkaar hield.** `pleya_wordmark.png` was handwerk en was achtergebleven
bij `pleya_mark.png`: dichte donkere binnenvorm en flauwe rode snelheidslijnen, tegenover een open
binnenvorm en amberkleurige lijnen. De generator heeft twee families — `mark_canvas()` bouwt uit de
mark, `lockup()` bouwde uit de wordmark — en die liepen dus uiteen. Alles uit `lockup()` droeg de oude
P: het tvOS-app-icoon, alle drie de Top Shelf-beelden, de Android TV-banner en het OG-beeld van de
site. Alles uit `mark_canvas()` droeg de huidige: iOS, macOS, Android, Linux, Windows, favicon,
`pleya_logo.png`. Uitgerekend het platform waar dit hele project over gaat liet de verouderde mark zien.

**Het lockup wordt nu samengesteld in plaats van bewaard.** `pleya_mark.png` plus de belettering,
volgens vastgelegde compositieparameters: dezelfde cap-height als het oude lockup, dezelfde 20px
tussenruimte, dezelfde verticale uitlijning. De huidige mark is werkelijk breder (1,099 tegen 1,002) en
wordt niet platgedrukt om binnen het oude kanvas te passen — dat groeit mee van 1452 naar 1516. De P
bestaat daarmee nog op één plek en kan niet opnieuw los van zichzelf verouderen.

**De vork is vervallen.** Die bestond om de drieëntwintig donkere goldens byte-identiek te houden, en
een merkverversing verandert die sowieso. Dus geen twee codepaden meer: `PleyaWordmark` tekent altijd
de twee lagen, de merklaag houdt altijd zijn eigen kleuren, en de belettering krijgt de inkt die de
aanroeper meegeeft. De topbar geeft de themakleur mee; de introsplash niet, want die staat op zwart en
daar hoort de belettering zijn eigen wit te houden — twee gebruiksmodi, geen twee implementaties.

**Wat er onderweg nog uit kwam.** De huidige mark heeft een *doorzichtige* binnenvorm waar de oude er
een dichtgeschilderde had. Dat is precies waarom hij op een themavlak werkt: de ondergrond schijnt
erdoor. De oude zou ook na de J18-fix nog als donkere vlek op het lichte palet hebben gestaan, dus de
verversing was niet alleen consistentie maar een voorwaarde.

De splash sizede op `width: 340`. Met een breder kanvas zou dat het ident stilletjes hebben verkleind,
dus hij gaat nu op hoogte — dezelfde hoogte die die breedte opleverde.

**Bewijs.** De generator draait deterministisch: twee runs, veertien identieke outputs. De
assetinvarianten zijn uitgebreid met een drift-guard die de P in het lockup vergelijkt met
`pleya_mark.png` op een grof raster in plaats van op een bestandshash; met de oude P erin valt hij om
op 19,7 tegen een drempel van 12, en de controle op de open binnenvorm valt daar apart naast om. Er is
een bronbewaking bij zoals `PleyaLogo` die heeft: geen enkel ander bestand in `lib/` mag een
lockup-asset noemen. Vierentwintig goldens hertekend en stuk voor stuk bekeken, plus het tvOS-icoon, de
Top Shelf, de TV-banner en het OG-beeld. De iconen die al uit `pleya_mark.png` kwamen zijn met opzet
teruggezet: die waren goed en hoeven niet mee te bewegen.

Nog steeds omgevingsdrift, en nog steeds niet meegecommit: een kale generatorrun herschrijft
zevenenveertig getrackte iconen die pixel-identiek blijven, omdat deze Pillow anders comprimeert dan
die van de vorige run.

## [2026-09-02] Het woordmerk op licht, en waarom de splitsing in het asset zit

Fase 10A liet één ding bewust open: op het lichte thema verdween het Pleya-woordmerk in de TV-topnav.
Dat is nu dicht, en het besluit eronder staat als DEC-074.

**Het gebrek, gemeten.** De balk schildert zelf niets en staat op de paginagrond van `TvRootShell`,
die op licht uitkomt op `#F2F2F3`. De witte "LEYA"-letters stonden daar op **1,12:1** — onzichtbaar —
terwijl de rode P op 4,23:1 bleef staan. Hoofdstuk 8.2 wil daar twee dingen tegelijk die op één asset
niet samengaan: donkere tekst, én Pleya-rood voor branddetails.

**Waarom er toch geen `ColorFilter` in staat.** Die zin uit het register klopt nog steeds: geen filter
hertint de letters zonder de mark mee te nemen. Hij is niet weerlegd maar omzeild. De twee kleuren
blijken ruimtelijk uit elkaar te liggen — rood links, letters rechts, met een volledig transparante
gang van kolom 659 tot 678 ertussen — dus `gen_brand_assets.py` schrijft nu twee lagen uit dezelfde
handgemaakte bron. Op licht tekent de balk de mark ongetint en de letters op `MonoTokens.text`
(16,88:1); op donker en OLED verandert er niets.

**De valkuil die geen widgettest ziet.** De bron heeft een alpha-bbox van (0,1,1424,659) op een kanvas
van 1452x659 — er zit dus transparante marge in die het beeld mee bepaalt, want de app tekent met
`BoxFit.contain` op een vaste hoogte. Een laag die op zijn eigen bbox gecropt wordt krijgt een andere
aspect ratio, daarmee een andere breedte, en dan schuift het lockup uit elkaar. Dat ziet er in review
uit als een ontwerpfout, niet als een kapotte build. Beide lagen houden daarom het volle bronkanvas,
en `test/assets/brand_wordmark_layers_test.dart` bewijst dat ze samen pixel voor pixel de bron zijn.

**De vork is een keuze, geen slordigheid.** Eén pad voor alle thema's is netter, maar de letters dragen
compressieruis: zo'n vijftienduizend ondoorzichtige pixels staan op 253-255 in plaats van zuiver wit.
Ze op donker naar wit hertinten verschuift die onmerkbaar en maakt drieëntwintig donkere goldens
ongeldig. Drieëntwintig referentiebeelden verversen om een verandering vast te leggen die niemand ziet
is precies hoe een goldensuite zijn gezag verliest. Nu beweegt er één beeld, en de andere
drieëntwintig zijn byte-identiek gebleven — dat is ook nagelopen en niet aangenomen.

**De regressietest meet contrast, geen gelijkheid.** Een assertie dat de inkt gelijk is aan `tk.text`
zou blijven staan als iemand er later een bleke constante van maakt. De test rekent daarom de
contrastverhouding uit tegen dezelfde grond die `TvRootShell` eronder schildert. Negatieve controle
gedraaid: met `_Wordmark` teruggezet op het onverdeelde bestand vallen precies de twee lichte tests om
en blijven de eenentwintig andere groen.

**Eén rij erbij.** Bij dit werk kwam `backend_badge.dart` boven water: de Pleya-tak van die `switch`
tekent zijn mark kaal, terwijl de Plex- en Jellyfin-buren wél de inktkleur krijgen en `local` ook. Hij
blijft leesbaar op licht — hij is rood, niet wit — dus dat is een consistentievraag en geen
leesbaarheidsbug, en die is niet meegenomen. Staat als **J19**, klasse C. Register daarmee op 179 van
188 `covered`.

Onderweg nog iets waar niets aan gedaan is: een kale `gen_brand_assets.py`-run herschrijft
zevenenvijftig getrackte bestanden, waarvan drieënvijftig pixel-identiek zijn en drie tvOS-icoonlagen
echt verschillen — in de taglinestrook, dus font-rasterisatie tussen Pillow-versies. Dat is
omgevingsdrift en niet van deze wijziging, dus alleen de twee nieuwe assets zijn blijven staan.

## [2026-09-01] Fase 10A: de ontwikkelpoort eruit, en het lichte thema laat iets zien

Laatste automatische fase van Pleya Unified TV 2026. Geen hardware, geen simulator, geen TestFlight —
dat is Final, en die staat expres nog open.

**De ontwikkelpoort is weg.** `DevFlags.tvUnifiedExperience` stond er sinds fase 0 en was al dood:
buiten zijn eigen rij in de Debug-sectie las niets hem nog, want `MainScreen` kiest sinds fase 7 de
TV-shell onvoorwaardelijk. `lib/config/` is daarmee ook verdwenen — dat ene bestand was de hele map.
Belangrijker dan de verwijdering is wat eronder is komen te staan: een architectuurtest die vastlegt
dat er geen poort terugkomt, dat Instellingen geen schakelaar tussen de shells aanbiedt, en dat de
TV-tak vóór de zijbalktak wordt beslist. Die laatste heeft een negatieve controle nodig en heeft er
een, want een TV *is* ook een zijbalkoppervlak — houdt dat ooit op, dan is de volgordeassertie zinloos
en moet ze omvallen in plaats van groen blijven. Rood→groen bewezen door de poort tijdelijk terug te
zetten: drie van de vijf assertions vielen om. Staat als DEC-073.

**Hoofdstuk 29 had nog vijf scenario's zonder deterministische uitvoer.** Drie zijn een golden
geworden — Home op het lichte palet, Home met een hero die alleen een poster heeft, en Mijn Pleya met
élke conditionele tegel aan. Twee bewust niet: `single-server` en `reduce-motion` kwamen byte-identiek
uit de bus met `default`, en dit bestand droeg die les al (de long-locale golden die nooit kon falen).
Ze zijn een assertie geworden die dat wél kan — geen bron die zich als meerdere voordoet, en een
billboard dat stilstaat onder Reduce Motion en beweegt zonder, uit dezelfde fixture.

**Twee dingen die de nieuwe beelden zelf aan het licht brachten.** Het volle Mijn Pleya-hub past niet
op het tvOS-canvas: drie groepen, en de onderste rij loopt van het scherm. Dat is geen fout — de pagina
scrollt — maar geen enkele test liep tot dan een hub die overloopt, dus staat er nu een die de
laatste tegel opzoekt en controleert dat hij ook echt in beeld komt. Op 1280x720 past de pagina nog
wel, dus die test draait op het echte canvas uit DEC-028; op de default-maat had hij niets bewezen.

Het tweede is een echte bevinding en blijft open: **op het lichte thema verdwijnt het woordmerk.** De
letters in `pleya_wordmark.png` zijn wit en de topnav tekent dat bestand ongewijzigd, dus rechtsboven
blijft alleen de rode P-mark over. Bereikbaar zonder iets bijzonders te doen, want het lichte thema is
een gewone instelling en volgt onder `system` de appearance van het toestel. Er staat geen fix onder,
en dat is een keuze: het is één PNG met twee kleuren erin — witte letters plus de mark die volgens
hoofdstuk 8.2 juist rood hoort te blijven — en geen `ColorFilter` hertint het ene zonder het andere.
Elke oplossing is dus een merkbeslissing die geen hoofdstuk, DEC of north-starbeeld dekt; alle acht
referentiebeelden zijn donker. Registerrij **J18**, klasse C, naast J14.

Register staat daarmee op 178 van 187 `covered`. Fase 10A heeft geen enkele rij van `open` naar
`covered` bewogen, en dat hoort ook zo: fase 9 had het register al gesloten, dit was harding erop.
Wat openblijft is vijf hardwarerijen, twee geregistreerde debts en twee onopgeloste productcontracten.

## [2026-08-22] De twee PS-4-bevindingen dicht, en de releasenotes blijven staan

Het verlaten van de speler wachtte op de afsluitrapportage van de kijkstatus. Het beeld is op dat
moment al weg en de bibliotheek is nog niet terug, dus een connect-timeout werd letterlijk zwart
scherm, op 21 augustus op iOS en tvOS tegelijk gemeten (logs `xhs3j` en `kzq7c`). Het rapport vertrekt
nu zonder dat het afsluitpad erop wacht, `PlaybackProgressTracker` begrenst de schrijving zelf op vijf
seconden, en wat daarbinnen niet landt gaat naar de offline-wachtrij in plaats van naar de prullenbak.
Een terminaal rapport negeert daarvoor bewust `queueOnOnlineFailure`: bij de periodieke updates draagt
de volgende tik de positie alsnog, na een stop is er geen volgende tik. De lokaal weggeschreven
positie wordt meteen gemeld, anders staat de rij waar de kijker op terugkomt nog op de oude waarde.

De log-uploadknop vuurde elf requests in zeven seconden op een relay die er één per minuut accepteert
(log `kzq7c`, 21:53:39 tot 21:53:46). De bestaande guard dekte alleen een druk die over een lopende
request heen valt, en een weigering komt in zo'n zestig milliseconden terug, dus dat gebeurde nooit.
Het scherm houdt nu vast tot wanneer er weer gevraagd mag worden. Zegt de server met `Retry-After` hoe
lang, dan is dat het antwoord; zwijgt hij, dan verdubbelt de eigen schatting vanaf de bekende minuut
tot maximaal vijf. De datumvorm van die header wordt nu ook gelezen: `HttpDate.parse` meldt een
onleesbare waarde met een `HttpException` en niet met de `FormatException` die de naam suggereert.

Onderweg kwam er iets onder vandaan dat groter is dan allebei. `_postJson` in
`lib/services/pleya_server_client.dart` vangt elke fout af en geeft `null` terug, dus een mislukte
`POST /watch-state` bereikt de aanroeper niet. Bij de PS-4-ronde bleef dat verborgen omdat de
verbinding in een timeout liep en de deadline van de speler alsnog aansloeg; een 404, een 5xx en een
snelle verbindingsweigering vallen nog steeds stil weg. Staat als bevinding in hoofdstuk 24 van het
architectuurdocument, met de aantekening dat het elke aanroep van de client raakt en dus niet binnen
PS-5 hoort.

`main` is erin gemerged. Alleen `playback_progress_tracker_test.dart` botste, en dat was twee keer
aanbouw aan het eind van hetzelfde bestand, dus beide groepen staan er nu naast elkaar. De begrensde
stopmelding zit boven op het hervat-pad uit `b1bb268` en `25d192b`: een rapport dat over de deadline
gaat blijft in de sessie doorlopen, dus het hervatten haalt hem nog steeds in. Bewijs op de
samengevoegde boom: `ci_checks.sh` volledig groen en 4617 tests geslaagd, 1 overgeslagen, met de
gepinde SDK uit `.fvmrc` vooraan in PATH. Zonder die pin staat er 3.44.4 op PATH en valt
`check_flutter_version` om.

Daarna `/update-docs`. Build 240 is afgesloten tot een echte versiekop met het anker op de
bump-commit, en de regels erin zijn herschreven naar wat iemand merkt. Het serverwerk staat er niet
in, om dezelfde reden als bij `fbd19f3`. Twee hoofdstukken bijgewerkt: `settings-reference.md` krijgt
de statusregel onder de iCloud-schakelaar, de instellingen die per toestel blijven en de
geschiedenisschakelaar op het Tautulli-scherm, en `the-home-screen.md` legt uit waarom je die zou
aanzetten. Het Pleya Server-scherm blijft ongedocumenteerd zolang er geen server is die iemand kan
draaien.

**Waarom de releasenotes drie keer waren platgewalst.** `scripts/gen_release_notes.sh` overschrijft
het hele blok tussen `BEGIN GENERATED` en `END GENERATED` bij elke run, en de pre-push hook draait dat
script. De site knipt datzelfde blok er sowieso uit (`website/src/lib/server/releases.ts`) en
publiceert alleen wat eronder staat. De Engelse tekst stond al die tijd ín dat blok, dus hij werd
overschreven én niet gepubliceerd. Hij staat nu onder `END GENERATED`, `--check` geeft exit 0, en de
push ging in één keer door zonder `SKIP_HOOKS`. De zin op de site dat die regels nog in commit-taal
staan klopte daarmee niet meer en is vervangen.

Bij App Store Connect dragen tvOS en macOS de nieuwe tekst, allebei teruggelezen op 2041 tekens. Een
iOS-build 240 bestaat daar niet: de lane wachtte de volle 1800 seconden en `notes_show` bevestigt het
los.

## [2026-08-21] PS-4: afspelen en kijkstatus, met drie poorten dicht ervoor

PS-3 is gesloten met de meting die eraan ontbrak. Een live test legt dezelfde route die de app loopt
tegen de draaiende server op de DS920+: drie bibliotheken (Films 461, Kids 5, Series 97), artwork met
de header uit DEC-048, zoeken, en daarna een verse client die met het bewaarde refreshtoken opnieuw
inlogt. De test slaat zichzelf over zonder adres, want een suite die een NAS nodig heeft om groen te
zijn is geen suite.

Daarmee ging het contractvenster open, en het is weer dicht met drie besluiten erin.

**DEC-049, kijkstatus heeft een eigenaar.** De drie voor de hand liggende conflictregels falen elk op
een scenario dat gewoon voorkomt, en een vierde (ordenen op sessiestart) breekt op het tv/telefoon-
geval. Wat er staat is server-authoritative eigendom: een monotone `revision`, een eigenaarssessie en
een lease op de serverklok. Eigendom wordt alleen verworven met `playback_started`, een passief
voortgangsevent verwerft nooit, `base_revision` draagt de causaliteit, een expliciete handeling
negeert de lease, en een offline backlog is geschiedenis zolang er een toestand is. Achttien tests
dekken de zes regels plus het tv/telefoon-scenario.

**DEC-050, de `ETag` op `/stream` is zwak.** De belofte dat hij verandert zodra de bytes veranderen
gaat uit het contract. RFC 9110 §8.8.1 vraagt strict revision control of een hash over de bytes, en
Pleya beheert de bestanden niet. `If-Range` levert daarom altijd het hele bestand; gewone `Range`
verandert niet, en dat is het pad dat elke seek gebruikt. Gelijkheid van de validator is nergens in
Pleya grond om bytes aan elkaar te plakken.

**DEC-051, de browser krijgt een streamsessie.** Eén cookie op één pad breekt bij twee tabbladen,
want cookies met dezelfde naam, domein en pad vervangen elkaar. De cookienaam draagt daarom de
sessie-id, het geheim staat er als SHA-256 in de database, en er gaan er ten hoogste acht tegelijk
actief: de negende wordt geweigerd in plaats van dat de oudste stream stil sneuvelt.

Daar bovenop PS-4 zelf: twee voorwaartse migraties, `GET /stream/{version_id}` met volledige
range-ondersteuning, beide kijkstatus-endpoints, `POST /auth/stream-session`, en aan de clientkant
een `PleyaServerClient` die afspeelt en kijkstatus schrijft. 182 Go-tests, 214 Dart-tests in
`test/pleya_server/`, de volledige Flutter-suite op 3721, `verify-local.sh` op 72 controles, en 32
controles tegen de draaiende server op de DS920+ (seek naar 73% van een bestand van 1,87 GB in 164 ms
voor 1 MB).

Eén grens is tijdens de uitvoering hersteld. Het masterplan schreef een geweigerd kijkstatusevent
naar `play_history`, en die tabel hoort bij PS-9P. PS-4 correct laten zijn ten koste van een tabel
uit een latere fase is precies de drift die hoofdstuk 23.1 verbiedt, dus zo'n event wordt beantwoord
met de actuele toestand en gelogd, en niet bewaard.

Eén meting viel de andere kant op dan verwacht. De `MediaServerClient`-beoordeling uit PS-4 criterium
5 komt uit op 28 van de 84 members die in drie of meer van de vijf implementaties structureel leeg
zijn, tegen een drempel van 21. De klasse is te breed volgens haar eigen criterium; het getal en de
plek staan in hoofdstuk 5.3 zodat de opsplitsingsronde met een lijst kan beginnen.

**PS-4 staat op "opgeleverd, ter goedkeuring" en niet op "gesloten."** Acceptatiecriterium 1 vraagt
een direct-play-bestand dat op desktop, mobiel en TV speelt met werkende seek, en er is deze sessie
geen film gestart vanuit de app. Alles wat hierboven staat is gemeten op de lijn.

## [2026-08-21] De sync-engine reconcilieert op één plek, en de schermen volgen zonder herstart

Op `main`, nog niet gecommit. Fase A blok 2 (A8 tot en met A16), plus de vijf voorwaarden uit de
reviewronde op de v2-cutover. Hiermee is fase A af; fase B begint na het architectuurrapport.

### Fixed
- **De prune verwijderde clouddata van andere toestellen.** De bescherming "staat lokaal, alleen
  niet syncbaar" vergeleek een genamespacete v2-cloudsleutel met een kale basissleutel, dus hij
  matchte onder v2 nooit. Een lijst met uitsluitend local-folder-entries werd daardoor bij elke
  reconcile uit de store gegooid. De vergelijking gaat nu over basissleutels; de test is rood op de
  oude vergelijking.
- **Een uitgaande schrijfactie kon entries van een ander toestel overschrijven.** De merge draaide
  alleen inkomend. Voor de serverlijsten houdt de uitgaande merge nu de entries in de store die van
  een server zijn waar dit toestel niets over kan zeggen, terwijl een bewuste verwijdering op een
  gedeelde server gewoon doorreist. Kan de store niet gelezen worden, dan wordt er niet geschreven.
- **Een geslaagde schrijfactie wiste een quotastop, een transportfout of de legacy-peer-waarschuwing
  uit beeld.** Er was één `state`-veld, dus `success` overschreef alles wat nog waar was.
- **Een remote wijziging kwam pas na een herstart op het scherm.** `HiddenLibrariesProvider` las
  zijn set bij constructie, `HomeLayoutProvider` blokkeerde elke herlaadpoging met
  `if (_isInitialized) return`, en `LibrariesProvider` bakte de volgorde in zijn lijst.
- **Uitloggen bij iCloud tijdens een sessie bereikte de app nooit.**
  `NSUbiquityIdentityDidChangeNotification` werd nergens waargenomen, dus de status bleef gezond
  terwijl elke schrijfactie nergens heen ging.

### Changed
- **Eén `PreferenceReconcileScheduler` bezit alle triggers** (boot, inschakelen, foreground,
  accountwissel, profielwissel, import, reset). Triggers uit dezelfde turn worden één run; een
  trigger tijdens een lopende run levert precies één vervolgrun. Het venster is een microtask, geen
  `Future.delayed`. Een profielwissel wordt opgemerkt aan de schrijfactie op `active_app_profile_id`,
  dus elk pad dat van profiel wisselt is gedekt.
- **`PreferenceSyncStatus` heeft drie assen** (`availability`, `activity`, `health`) plus
  `legacyPeerDetected`. De acht toestanden uit het plan zijn een afgeleide getter, dus niets
  schrijft nog een toestand. Alleen een geslaagde volledige reconcile schoont health op.
- **`PreferenceMergeRegistry`** vervangt de hardgecodeerde `if` op een sleutelprefix. Een familie
  registreert `merge(local, remote)` onder de naam die in de policy staat; de engine leert nooit wat
  de waarden betekenen. `mergeProgressMaps` is daarmee een geregistreerde familie geworden.
- **`PreferenceRefreshBus`** meldt per batch welke afgeleide families verlopen zijn, en de providers
  herladen hun eigen plak. Geen herstart, geen globale rebuild. De ponytail-notitie op `main.dart`
  is daarmee weg.
- **Instellingen toont één statusregel** onder de iCloud-schakelaar, met nieuwe strings in
  `lib/i18n/en.i18n.json`. Nooit een sleutel, waarde of telling met identiteit, en nooit de claim
  dat andere toestellen bij zijn: KVS accepteert een write, het meldt geen aflevering.
- **Native gewijzigd op precies twee punten** van de negen auditpunten: een `deinit` met
  `removeObserver`, en waarneming van `NSUbiquityIdentityDidChange`. De volledige audit staat in
  `docs/qa/icloud-kvs-native-audit.md`, inclusief waarom er géén buffer voor vroege notificaties is
  gebouwd.

### Added
- `test/services/preferences/v2_only_invariant_test.dart` bewaakt dat v2-only een invariant is en
  geen standaardwaarde: geen bestand in `lib/` kiest het formaat, en een volledige levenscyclus over
  een store vol v1-records laat die records ongemoeid.
- `test/services/preferences/local_only_bookkeeping_test.dart` bewaakt dat de bootstrap-marker, de
  install-id, de revisieopslag, de quarantaine en de actieve-profielsleutel het toestel nooit
  verlaten.
- `test/services/preferences/log_safety_test.dart` scant de logregels op het syncpad en eist dat elke
  interpolatie op een veilige lijst staat. Een nieuwe logregel met een waarde erin wordt rood.
- Verder: `reconcile_scheduler_test`, `reconcile_lifecycle_test`, `runtime_refresh_test`,
  `sync_status_model_test`, `merge_strategy_test`, `quota_and_oversize_test` en
  `test/screens/settings/icloud_sync_status_test.dart`. Suite 4068 groen, dezelfde 15 rood als op
  `8fea407`.

Besluiten: [DEC-060](DECISIONS.md#dec-060) (de v2-cutover als bevroren v1) en
[DEC-061](DECISIONS.md#dec-061) (scheduler, statusassen, gerichte invalidatie, merge per familie).

## [2026-08-21] Preference-sync kreeg één pijplijn, en de grens met de legacy prefs-store ligt nu vast

Op `main`, nog niet gecommit. Fase A blok 1 van het vijffasenplan (A0 tot en met A5 en A7, plus de
vier amendementen uit de planreview). Blok 2 (A8 tot en met A16) en de cloudinhoud-migratie (A6)
volgen apart.

### Fixed
- **Een seek tijdens een netwerkstoring verdween.** `onSeek()` gooide de debouncetimer weg zodra de
  foutbackoff liep. Erger dan het lijkt: de periodieke timer draait alleen tijdens afspelen, dus wie
  seekte en daarna pauzeerde liet de oude positie op de server staan tot er toevallig weer gespeeld
  werd. De seek wordt nu uitgesteld in plaats van weggegooid, en het uitstel tikt de backoff zelf af
  zodat een gepauzeerde speler convergeert. Vijf tests erbij; drie ervan zijn rood op de oude code.
- **Een lokale verwijdering bereikte iCloud niet.** `onKeyWritten` gaf alleen een sleutel door, dus
  de consument las de waarde terug, vond `null` bij een remove en stopte. Alleen een volledige
  `pushAll` propageerde nog verwijderingen.
- **Een waarde die over de 100 KB-grens groeide werd uit de cloud verwijderd in plaats van
  overgeslagen.** `pushAll` prunede op afwezigheid uit de push-set, en een te grote waarde belandde
  daar niet in. Oversize-sleutels worden nu expliciet buiten de prune gehouden en leveren een
  zichtbare waarschuwing.
- **Een transportfout verdween.** Het `void`-terugtype dwong de consument tot `unawaited(...)`.

### Changed
- **Het hookcontract is vervangen, niet omwikkeld.** `BaseSharedPreferencesService.onMutation`
  levert een volledige `PreferenceMutation` met operatie en bron en geeft een `Future` terug.
- **Nieuwe laag `lib/services/preferences/`**: `PreferenceSyncCoordinator` (mutatie, policy, scope,
  merge, reconcile, status), `PreferenceTransport` als poort, `ICloudKvsTransport` als enige
  implementatie. `ICloudSyncService` is een dunne facade geworden en draagt geen syncgedrag meer.
- **Syncbaarheid is een expliciete registratie.** De allow-by-default denylist is weg: een
  niet-geregistreerde voorkeur is local-only. Gevolg dat een gebruiker merkt: `volume`,
  downloadmappen, hardware-decoding, HDR, `custom_relay_url` en het laatst gebruikte LAN-adres
  synchroniseren niet meer.
- **Profielidentiteit blijft aan de waarde hangen** via `PreferenceSyncScope`, dat eerlijk is over
  portabiliteit: een Plex Home-UUID is portable, een `local-<uuid>` niet.
- **Scalaire conflicten hebben een regel.** `PreferenceRevision`: deterministische last-writer-wins
  op `(updatedAt, deviceId)` met tombstones, waarbij een `migration` geen gebruikerstijdstempel zet.
- **De ~35 library- en home-callsites lopen rechtstreeks over de pijplijn**, verwijderingen
  inbegrepen. Read-path-migraties dragen `source: migration`.

### Added
- `test/no_raw_preference_write_test.dart`: 81 rauwe prefs-schrijfacties in 20 bestanden, alle 81
  geclassificeerd met een aantal per bestand. Een nieuwe schrijfactie in een onbekend bestand én een
  extra schrijfactie in een bekend bestand zijn allebei aantoonbaar rood gemaakt.
- `test/services/icloud_rolling_upgrade_test.dart`: de uitgebrachte client laat `__`-sleutels met
  rust in zowel de prune-lus als de apply-lus, met een controle die bewijst dat dezelfde payload in
  de gewone namespace wél wordt opgeruimd. Daarom krijgt de v2-namespace een `__`-voorvoegsel en is
  er geen tweefasenuitrol nodig.
- `docs/qa/preference-sync-and-playback-matrix.md`, met de drie openstaande metingen.

### Notes
- **De cloudinhoud is niet aangeraakt.** `PreferenceSyncCoordinator.v2CloudFormatEnabled` staat op
  `false`: de scoped namespace en de envelop bestaan en zijn getest, maar er is geen v2-record
  geschreven en geen v1-record verwijderd. A6 wacht op een eigen checkpoint, omdat v1-cloudsleutels
  geen profielidentiteit meer dragen en dus niet aan het toevallig actieve profiel mogen worden
  toegewezen.
- **De vijf legacy-services vallen bewust buiten de engine.** `flutter.`-sleutels en de benoemde
  historische namen bereiken iCloud niet. `mergeProgressMaps` blijft als legacy inbound
  compatibility, met de verwijderconditie op de methode. Zie DEC-059.
- **Bij het nalopen van de eigen acceptatie kwam er nog een gat uit.** De prune in `reconcile`
  verwijderde een cloudsleutel zodra hij niet meer in de push-set zat, dus het omkeren van de
  denylist zou clouddata van andere toestellen wissen, en een vergeten registratie zou dataverlies
  zijn in plaats van een gemiste sync. De prune deletet nu alleen wat lokaal echt weg is. In
  dezelfde controle bleken 26 gedeclareerde voorkeuren niet geregistreerd (`app_locale`,
  `library_density`, `buffer_size`, `default_playback_speed`, de mpv-configuratie en meer); die zijn
  alsnog geclassificeerd, en een guard scant voortaan de declaraties.
- Meting: volledige suite 3909 groen / 15 rood, byte-identiek aan de 15 op `8fea407`.
  `flutter analyze` zonder fouten of waarschuwingen, `scripts/ci_checks.sh` groen op SDK 3.44.0.

## [2026-08-21] De hervatpositie kwam uit twee plekken die elkaar tegenspraken

Op `main`, nog niet gecommit. Fase C van het vijffasenplan voor voorkeurensynchronisatie en
kijkvoortgang; A, B, D en E volgen.

### Fixed
- **Een gepauzeerde speler zette de positie van een spelende speler terug.** De melding: *Mutiny*
  stond open op de MacBook (gepauzeerd, 1:03 resterend) en op de Apple TV (actief, 0:57
  resterend), en de MacBook won. De oorzaak stond in `playback_progress_tracker.dart`: de
  periodieke timer stuurde elke zesde tik een `paused`-rapport "om de serversessie in leven te
  houden", met steeds dezelfde positie. Die heartbeat is weg. Een rapport dat zowel de staat als
  de positie van het vorige rapport herhaalt gaat nu niet meer de deur uit.
- **Een seek bereikte de server pas bij de volgende tik.** Wie sprong en binnen tien seconden
  afsloot, liet de positie van vóór de sprong staan. `PlaybackProgressTracker.onSeek()` rapporteert
  na een trailing debounce van 500 ms, herstart daarbij de periodieke timer en respecteert een
  lopende foutbackoff. De 30 seconden-drempel op `_notifyProgressIfNeeded` slikt de sprong niet
  meer op.
- **Een gedownload bestand hervatte op de lokale positie, ook online.** `_resolveOpenResumePosition`
  las bij offline afspelen eerst de lokaal bijgehouden voortgang en gaf die terug zodra hij groter
  dan nul was, ongeacht wat de server wist. Een tweede toestel dat verder had gekeken verloor het
  daarmee altijd.
- **De verse ophaalactie bij het starten sloeg juist het gevaarlijke geval over.**
  `navigateToVideoPlayer` haalde het item alleen opnieuw op als het helemaal geen `viewOffsetMs`
  droeg. Een scherm met een verouderde offset sloeg de ophaalactie dus over en hervatte op die
  verouderde waarde. `shouldRefetchForFreshResume()` haalt online elke film en aflevering vers op.

### Added
- **`lib/services/playback_resume_resolver.dart`**: de enige plek die bepaalt waar een open begint.
  Vijf lagen op intentie, herkomst en tijd, nooit op "welke positie is groter". Een lokale
  handeling wint alleen van een vers opgehaalde serverwaarde als hij aantoonbaar nieuwer is én
  als bewuste gebruikershandeling is vastgelegd; tegen een verouderde cachewaarde volstaat een
  nieuwere tijdstempel. 19 tests.
- **`lib/services/playback_write_authority.dart`**: `ObservedPlaybackAuthority`, een lokale
  waarneming van wie mag schrijven. Uitdrukkelijk geen lease: een vertraagd socketevent, een
  Plex-notificatie zonder bruikbare sessie-informatie of twee spelers die gelijk starten laten
  twee toestellen tegelijk denken dat ze mogen schrijven. `PlaybackReportSession` weigert bij een
  ingetrokken autoriteit alle drie de signalen, `stopped` incluis, want juist dat late stopbericht
  draagt de oude positie. `retakeAfterRefresh` legt de volgorde vast: eerst de serverstaat lezen,
  dan pas terugnemen. Wat de autoriteit intrekt komt in fase D. 13 tests.
- **`lib/services/playback_lifecycle_report_decision.dart`**: wat de achtergrond-, detach- en
  disposepaden schrijven. Ingetrokken autoriteit schrijft niets; een positie die niet bewoog heeft
  niets toe te voegen; een speler die nog speelde schrijft één keer af, en die schrijfactie kan
  niets terugzetten omdat hij een al verstuurde positie herhaalt. 12 tests.
- **`OfflineWatchSyncService.getLocalResumeProgress()`** geeft dezelfde offset als
  `getLocalViewOffset`, met de tijdstempel van de actie erbij. Zonder die tijdstempel bestaat er
  maar één regel, "lokaal wint altijd", en dat was de bug.

### Changed
- **`VideoPlayerScreen` krijgt `resumeProgressIsFresh`.** Alleen de startroute kan zeggen dat de
  offset deze keer bij de backend is opgehaald; de herlaadroutes dragen een eerder opgehaald
  moment.
- **`WatchStateResolver.latestAction()`** staat los van `fromActions()`, omdat de resolver de
  tijdstempel van de winnende actie nodig heeft en niet alleen de staat die eruit volgt.

### Notes
- **Het plan schreef dat de verse ophaalactie langs de cache moest.** Dat klopt niet:
  `fetchWithCacheFallback` (`lib/media/media_server_client.dart:704-732`) gaat network-first en
  raakt de cache alleen in offlinemodus of nadat het verzoek faalde. `fetchItem` levert online dus
  al verse data. Het echte gat zat in de `viewOffsetMs == null`-voorwaarde eromheen.
- **Rood aangetoond op de oude code.** Met de heartbeat teruggezet falen beide
  heartbeat-tests (`Expected: empty`); met `onSeek` leeggemaakt falen alle vijf de seektests.
  Daarna 45 van de 45 groen.
- **Er komt geen permanente DEC voor een leasemodel.** Wat landt is een tijdelijke strategie op
  basis van waarneming. Een echt toegekende lease wacht op PS-4 in de serverrepo.
- 89 gerichte tests groen, `flutter analyze` zonder fouten of waarschuwingen, `scripts/ci_checks.sh`
  groen op de gepinde SDK 3.44.0. De volledige suite geeft 3826 groen en 15 rood; diezelfde 15
  falen op een schone worktree van `8fea407`, in `logs_screen`, `watchlist`, `sync_rules` en
  `media_detail`, geen daarvan raakt afspelen.
- Niet gedaan: verificatie op echte hardware. Twee Apple-toestellen die hetzelfde item openen is de
  enige manier om te zien dat de terugzetter echt weg is.

## [2026-08-20] Hero-artwork vroeg de containerratio op, niet die van de bron

Op `main`, één commit: `40d9608`.

### Fixed
- **De home-hero croppte vierkante artwork op een smalle telefoon horizontaal weg.** `billboardArt()` koos bij een smalle hero-box terecht de vierkante `backgroundSquarePath` in plaats van een 16:9-backdrop, maar `discover_screen.dart` vroeg de afbeelding nog steeds op met de volle 16:9-hoogte van de container. Plex' server-side crop (`minSize=1&upscale=1`) vulde die box vanuit het midden en croppte zo'n 30% van de breedte al weg vóórdat Flutter iets tekende. `homeHeroArtGeometry()` (`lib/utils/home_hero_layout.dart`) ontkoppelt de framehoogte van `heroHeight` en laat de aanvraag altijd de ratio van de gekozen bron volgen, zodat de server-side crop een no-op wordt. Zie [DEC-057](DECISIONS.md#dec-057).

### Added
- **`BillboardArtKind`** (`lib/media/media_item.dart`) vervangt de bool `isBackdrop` op `BillboardArt`: `widescreen`, `square` of `fallback`, met `canRenderSharp`/`shouldBlur` als afgeleide.
- **`HomeHeroArtwork`** (`lib/widgets/home_hero_artwork.dart`, nieuw): de scherpe artworklaag van de hero geëxtraheerd uit `_buildHeroItemContent`, zodat de geometrie los van het hele scherm te toetsen is.
- **`homeHeroLogoConstraints()`** maakt het vaste 400×120-herologo responsive op telefoonbreedtes.

### Notes
- Een onafhankelijke codereview (`/code-review`) op de diff ving een echte bug in de nieuwe widget: de fade-gradient onder een korter frame stond op de onderkant van de hele hero-Stack in plaats van op de onderkant van het frame zelf. Gefixt vóór de commit, met een regressietest die de fade-rect tegen de frame-rect toetst.
- Visuele verificatie op een echt smal scherm (simulator- of TestFlight-screenshot) is nog niet gedaan.
