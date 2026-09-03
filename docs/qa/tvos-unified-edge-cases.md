# Edge-case register: Pleya Unified TV 2026

Bron: [docs/tvos-unified-experience.md](../tvos-unified-experience.md) hoofdstuk 26. Dit bestand is
het afvinkbare register; het architectuurdocument houdt alleen de regels en de categorieën.

**Regels.**

- Iedere rij krijgt een unit-, widget-, integratie- of hardwaretest voordat hij op `covered` mag.
- Een nieuw ontdekte situatie zonder expliciet gedrag is een releaseblocker: eerst het gedrag
  vastleggen (in het architectuurdocument of een DEC), dan pas hier een rij toevoegen of aanpassen.
- Status is één van: `open` (nog geen test), `covered` (test bestaat en is groen — vul de
  vindplaats in), `n.v.t.` (met reden, nooit stilzwijgend geschrapt), of — voor een rij die het
  hoofdstuk "Fase-9-classificatie van de open rijen" hieronder een klasse gaf — de klasse zelf
  (`klasse A`/`klasse B`/`klasse C`, eventueel met een korte reden erbij zoals `open (coverage debt)`
  bij I24). Die klasse ís de status voor zo'n rij, geen aparte waarde ernaast.
- Categorieën volgen geen vaste fase-toewijzing behalve waar het architectuurdocument dat expliciet
  zegt (register C is minimaal vereist in fase 1, zie hoofdstuk 27). Een fase mag een deelverzameling
  afvinken; het register als geheel sluit pas bij de laatste fase die het raakt.
- Rijen worden nooit verwijderd. Een geschrapt scenario gaat naar `n.v.t.` met een korte reden.

Bijgewerkt: 2026-09-02 (na de fase-9-eindaudit, gevolgd door twee onafhankelijke correctierondes die
hetzelfde J14 sloten en elkaar verder aanvulden: 182 van de 190 rijen `covered`; de acht die
overblijven zijn allemaal geclassificeerd, geen enkele gewone open rij meer: vijf hardwarerijen en
drie geregistreerde debts — I21, I24 en B16, de Pleya-Server-bevinding. J14 is `covered` geworden als
proof gap, en B17 is een nieuwe, direct `covered` rij voor een eerder ongeregistreerde bevinding —
zie hoofdstuk "Totaal" voor de volledige toelichting). Aangemaakt in fase 0. Fase 1 (unified identity
foundation) dekt register C (C1-C24) volledig af — zie de vindplaatsen in de tabel hieronder. De
overige categorieën blijven `open` tot de fase die ze raakt.

**Fase 4 en register F.** Fase 4 was intern gesplitst in een headless deel (activation coordinator,
ranking, voorkeur, cancellation) en een GUI-deel (de source picker zelf). Het headless deel bewees
per case *het besluit*; of de gebruiker dat besluit ook ziet en met de afstandsbediening kan bedienen
was pas bewezen toen de picker-widgettests er waren. Beide helften staan er nu, dus register F is
gesloten op F19 na — dat scenario heeft nog geen vastgelegd productgedrag en is niet zelf ingevuld.

F21 is in fase 4 toegevoegd: de voorkeursserver van hoofdstuk 14.8a mag zélf een bron kiezen, en dat
is een nieuw scenario met eigen gedrag, geen herformulering van een bestaand. De regel bovenaan
schrijft voor dat gedrag eerst wordt vastgelegd — dat is gebeurd in 14.8a — en pas daarna een rij.

**Fase 5 en de nagelopen rijen.** Fase 5 bouwde Films en Series, en daarmee de merge, de paging, de
filters en het raster. Bij het sluiten is het register nagelopen tegen álles wat er sinds fase 1 aan
tests bij is gekomen: vierentwintig rijen in A, B, D, E, I en J bleken al bewezen en waren alleen
nooit ingevuld. Er is voor die rijen geen test bijgeschreven, alleen de vindplaats opgezocht en de
test gelezen. Een rij die niet precies het scenario van die rij bewijst is `open` gebleven, ook waar
een test er dichtbij kwam; een te optimistisch register is erger dan een leeg.

**Fase 7 en register I.** Fase 7 bouwde de TV-root: de horizontale topnav, de gedeelde
geneste-routestapel en Mijn Pleya. Daarmee is register I van "leeg" naar acht ingevulde rijen
gegaan (I1, I5, I6, I8, I11, I12, I13, plus I7 en I15 die er al stonden). I18 is bewust op `open`
gebleven: de topnav-helft is bewezen, het griditem-geval niet, en een half bewezen rij hoort niet
`covered` te heten. I2, I3, I4 gaan over de hero en horen bij fase 8; I9, I10, I14, I16, I17, I19
en I20 raken paden die fase 7 niet heeft aangelegd. I21 is er tijdens fase 7 bijgekomen als
*bevinding over fase-5-code* en bewust niet opgelost — zie de noot onder register I. I22 en I23
kwamen uit de fase-7-systeemaudit en zijn bij het sluiten van de fase alsnog gerepareerd, omdat ze
allebei gedrag raken dat hoofdstuk 7.4, 7.6 en 24 al vastleggen en dat fase 7 zélf gebroken heeft:
vóór fase 7 was de complete catalogus een fullscreen push, waaruit de balk niet te bereiken was, dus
het scenario bestond niet. I24 is er als laatste bijgekomen en is geen gedragsrij maar een
dekkingsrij: de keten klopt in productie, maar geen test loopt er in zijn geheel doorheen — zie de
noot onder register I voor waarom dat coverage debt is en geen productbug.

**Hardware.** J2 (4K-output), J4 (overscan), J8 (VoiceOver) en J9 (Reduce Motion) zijn niet in een
test vast te leggen — ze vragen een echte Apple TV. Ze staan op `open` met die reden in de
Test-kolom en horen bij de eindacceptatie na fase 10A (hoofdstuk 29), niet bij de gate van een fase.
Ze gelden dan voor de hele TV-UI, dus ook voor de schermen die er nu nog niet zijn.

Fase 7 voegt daar geen nieuwe categorie aan toe, maar wel drie concrete gevallen die onder J8 en J9
vallen en die pas na 10A afgetekend kunnen worden:

- **VoiceOver op de topnav (J8).** `tv_top_navigation_test.dart` legt vast dát de actieve
  bestemming zichzelf anders aankondigt dan de gefocuste (`Films, current section` tegenover
  `Films`), en dat het label niet dubbel in de node zit. Wat VoiceOver er hoorbaar van maakt — en of
  het onderscheid op een echte Apple TV ook als onderscheid *landt* — is hardware.
- **Reduce Motion op de navfocus (J9).** De focus-transitie duurt 160 ms (hoofdstuk 8.4). Of hij
  onder Reduce Motion kort genoeg of instant hoort te zijn is alleen op het toestel te beoordelen.
- **De Menu-press op de root (J8/J9-buur).** De engine claimt presses vóór de responder chain
  (`CLAUDE.md`, [DEC-019](../DECISIONS.md#dec-019)). Fase 7 heeft dat pad níet aangeraakt en voert
  Menu door hetzelfde `shouldPassTvosMenuToSystem`-predicaat als de zijbalk, dus er is geen nieuw
  native gedrag om te bewijzen — maar dat de nieuwe rootgrens op echte hardware op dezelfde plek
  ligt, is wel een runtimewaarneming.

## Fase-9-classificatie van de open rijen

Vastgesteld op 1 september 2026, aan het begin van fase 9. Fase 9 is de laatste **functionele** fase
vóór 10A-hardening. Daarom geldt voor iedere nog niet-`covered` rij:

> **DEFAULT OWNER = FASE 9**, als en alleen als de rij automatiseerbaar is, productmatig voldoende
> gedefinieerd is, functioneel gedrag betreft, en niet al een expliciete andere owner of
> defer-status heeft.

Een rij mag alleen buiten fase 9 blijven met een van deze vier concrete redenen:

| Klasse | Betekenis |
| --- | --- |
| **A. Hardware-only** | Alleen op een echt toestel vast te stellen → eindacceptatie na 10A. |
| **B. Accepted registered debt** | Eerder expliciet geaccepteerd, en alleen zolang fase-9-code die seam niet wijzigt. |
| **C. Unresolved product decision** | Gedrag nog niet vastgelegd. Niet zelf invullen. |
| **D. Explicit later owner** | Alleen wanneer dit document of een DEC werkelijk een latere fase noemt. |

Er is bewust **geen numerieke scope-cap**. Omdat er na fase 9 geen functionele fase meer komt, mag
er geen verzameling gewone functionele edge cases overblijven met als enige reden "die hebben we
niet geraakt".

**Uitkomst over de 83 open rijen: 4 hardware, 2 debt, 1 onopgelost, 76 fase-9-owned.** Tijdens fase 9
zelf kwam I17 daar als vijfde hardware-rij bij (zie de noot eronder) — de 76 fase-9-owned rijen worden
er zo 75. J7 stond daarnaast korte tijd als zesde hardware-achtige rij genoteerd; die
herclassificatie is teruggedraaid toen bleek dat twee van zijn vijf clausules werkelijk stuk waren —
zie de noot eronder — dus het blijven er 75.

**Stand bij het sluiten van fase 9: alle 75 fase-9-owned rijen zijn gesloten.** Wat openstaat is precies
de tabel hieronder: vijf rijen die alleen op echte hardware vast te stellen zijn, twee geregistreerde
debts, en één onopgelost productcontract. Zes van die sluitingen bleken geen bewijsgat maar een
gedragsgat — A18, D11, I9, de F19/A14-layoutfout, en de twee RTL-clausules van J7 — en die staan met
hun fix in de rijen zelf.

Dit register is het samengevoegde resultaat van twee sessies die fase 9 parallel hebben gesloten. Waar
ze uiteenliepen is dat in de rijen zelf te lezen: D11's server-lokale episodecache en J7's twee
gespiegelde clausules zijn allebei echte bugs die de andere sessie niet vond, en J7's
klasse-A-herclassificatie is teruggedraaid omdat een `Directionality`-override die clausules wél kan
keuren.

**F19 is inmiddels opgelost.** Was klasse C (onopgelost productbesluit) tot de reconciliation van
1 september 2026 hoofdstuk 21.7 als authority vaststelde — zie de noot onder register F en de rij
zelf. Geen aparte klasse meer nodig.

**J14 is tijdens fase 9 klasse C geworden.** De existing-proof-first-audit vond geen enkel hoofdstuk,
DEC of stuk productiecode dat "een panelsectie" definieert — laat staan welk panel de rij bedoelt of
wat een lege sectie zou moeten tonen. Dat is geen aantoonbare bestaande correctheid om een test tegen
te schrijven, en ook geen bug: het is een geval waar sectie 7 van de reconciliation-instructie zelf om
vraagt — "kom terug bij een écht nieuw, niet-gedefinieerd productcontract" — dus die rij is hier
geclassificeerd in plaats van zelf ingevuld. Verplaatst van WP11 naar hier; blijft in het register
staan als `open`/klasse C tot er een productantwoord is.

> **Achterhaald op 2 september 2026. J14 is geen klasse C maar een proof gap, en is nu `covered`.**
> De alinea hierboven blijft staan omdat hij niet onjuist was over wat hij onderzocht — hij was
> onvolledig. De audit zocht "een panelsectie" in `tv_action_scope_picker.dart` en
> `tv_unified_context_menu.dart`, waar inderdaad niets zit voorbij `sectionGap`-witruimte, en keek
> niet in `tv_catalog_filter_panel.dart`. Dáár staat de invariant volledig uitgevoerd, in drie
> stukken: `_availableSections`/`_supports` laten een niet-uitvoerbare categorie weg in plaats van
> hem leeg te tekenen, `_buildOptions` geeft een ondersteunde categorie zonder waarden een expliciete
> `noValues`-regel, en `_zoneHeight` houdt de contentzone op dezelfde hoogte zodat een lege categorie
> geen verticale sprong veroorzaakt. Er was dus wél aantoonbare bestaande correctheid; er was alleen
> geen test. Zie de rij zelf verderop voor het bewijs. Geen productcontract toegevoegd en geen
> productiecode gewijzigd — dit is een herclassificatie op grond van code die er al stond.
>
> Dit is onafhankelijk twee keer geconstateerd: één sessie schreef er twee regressietests voor
> (loading/`noValues` als impliciete staat, geen apart bewijs), de andere drie (met een expliciet
> derde geval voor loading versus `noValues`). Beide zijn hetzelfde bewijs over dezelfde drie
> productiestukken; de rij zelf wijst naar de versie die uiteindelijk in dit register bleef staan.

**J7 was tijdens fase 9 klasse A, en is dat na herbeoordeling niet.** De eerste lezing was dat RTL-acceptatie zonder rechts-naar-links locale niet vast te stellen is, zoals J2/J4/J8/J9 zonder toestel. Dat gaat niet op: hoofdstuk 25 somt vijf concrete clausules op, en vier daarvan zijn met een `Directionality`-override in een widgettest te keuren, zonder locale en zonder toestel. Bij het schrijven van die tests bleken er twee werkelijk stuk — het leesscrim en het titelblok stonden hardgecodeerd op links — dus de klasse-A-lezing verklaarde een echte bug tot niet-vaststelbaar. Het onderscheid dat overblijft: de clausules zijn nu bewezen, een visuele sweep over een echte RTL-locale blijft onmogelijk zolang Pleya er geen verscheept, maar dát is niet wat deze rij vraagt.

**I17 is tijdens fase 9 alsnog klasse A geworden.** De existing-proof-first-audit van WP11 vond geen
`PopScope`/`WillPopScope` of enige andere back-button-interceptie onder `lib/screens/tv/` of
`lib/navigation/` — TV-schermen routeren terug via het eigen remote-focussysteem
(`onBack`-callbacks), niet via Android's hardware-backdispatcher. Dat is geen gat om dicht te testen:
of de Android-systeemknop het juiste doet op die stack is precies de klasse waar J2/J4/J8/J9 al onder
vallen, en alleen op een echt Android TV-toestel vast te stellen. Verplaatst van WP11 naar hier in
plaats van als losse open rij te laten staan.

### Buiten fase 9 (8 rijen)

Het bijschrift zei bij het sluiten van fase 9 "9 rijen", wat al niet klopte met de acht die er toen
onder stonden (J2, J4, J8, J9, I17, I21, I24, J14) — B16 stond er toen nog niet in, terwijl de
standparagraaf hem al wél als geregistreerde debt meetelde. J14 is op 2 september 2026 alsnog
`covered` geworden (zie de noot hierboven) en dus geen buiten-fase-9-rij meer; B16 is er in dezelfde
correctieronde bij gezet, dus het blijven acht rijen — alleen niet meer dezelfde acht.

| # | Klasse | Reden |
| --- | --- | --- |
| J2 | A | 4K-output is alleen op een echte Apple TV vast te stellen. |
| J4 | A | Overscan idem. |
| J8 | A | Of VoiceOver het onderscheid hóórbaar maakt, idem. |
| J9 | A | Of de 160 ms-transitie onder Reduce Motion kort genoeg is, idem. |
| I17 | A | De Android TV-hardware-terugknop is alleen op een echt toestel vast te stellen — zie de noot hierboven. |
| I21 | B | Geregistreerde fase-5-debt: 7.4 en 10.6 noemen de Play/Pause-snelkoppeling "mag", en de zichtbare knop blijft de primaire route. Vervalt als fase-9-code het catalogusheaderpad wijzigt. |
| I24 | B | Geregistreerde integration-test debt: schakel 2 loopt door `MainScreen`, dat geen enkele test monteert. Geen productiebug (statisch nagelopen). Vervalt als fase-9-code `_focusSidebar` of de nav-nodes raakt. |
| B16 | B | Geregistreerde debt uit de fase-9-eindaudit: `query.kind` bereikt de Pleya Server-wire niet, en client-side filteren zou de offsetrekening van de cursorledger breken terwijl het protocol bevroren is (PS-5). De lokale-mapkant is wél gedekt. Vervalt zodra het protocolvenster opengaat. |

Fase 10A voegt daar één rij aan toe, langs dezelfde regel en om dezelfde reden:

| # | Klasse | Reden |
| --- | --- | --- |
| J18 | C | Onopgelost productcontract: hoe de tweekleurige merklockup op het lichte thema hoort te worden getekend ligt in geen enkel hoofdstuk, DEC of north-starbeeld vast — zie de noot onder register J. **Opgelost op 2 september 2026, zie hieronder.** |

**J18 is opgelost op 2 september 2026.** Het ontbrekende productbesluit is genomen en staat als
[DEC-074](../DECISIONS.md#dec-074): **op het lichte thema volgen de letters de themakleur en blijft de
P-mark merkrood.** De rij verderop in dit register is daarmee `covered`; de klasse-C-regel hierboven
blijft staan als vastlegging van hoe de rij ontstaan is.

Bij dat werk kwam er één rij bij, langs dezelfde regel als altijd — eerst het gedrag geclassificeerd,
en juist omdat het níet vastligt is het klasse C en geen fix:

| # | Klasse | Reden |
| --- | --- | --- |
| J19 | C | Onopgelost productcontract: `backend_badge.dart` tekent de Pleya-mark ongetint terwijl de Plex- en Jellyfin-buren wél de inktkleur krijgen. Een consistentievraag, geen leesbaarheidsbug — zie de rij zelf. **Opgelost op 2 september 2026, zie hieronder.** |

**J19 is opgelost op 2 september 2026, dezelfde dag waarop hij ontstond.** Het ontbrekende productbesluit is
genomen en staat als [DEC-076](../DECISIONS.md#dec-076): **een backend-badge is een bronglyph en
neemt de inkt van zijn regel; het merkrood blijft bij `PleyaLogo` en het lockup.** De rij verderop in
dit register is daarmee `covered`; de klasse-C-regel hierboven blijft staan als vastlegging van hoe
de rij ontstaan is.

Bij dat werk kwam er géén rij bij. Wat er wél bij kwam is een gebrek in dezelfde drie regels dat geen
productbesluit vraagt en dus geen registerrij is: de badge tekende de handgemaakte bron
`pleya_mark.png`, waarvan de P ongecentreerd op zijn eigen kanvas staat en het niet vult, in plaats
van het gegenereerde `pleya_logo.png`. Dat is meegenomen en staat in de rij zelf.

### Fase-9-owned (75 rijen), met het werkpakket dat ze sluit

75, niet 76: dat is het aantal na de I17-verschuiving hierboven ("de 76 fase-9-owned rijen worden er
zo 75"). De tabel eronder groepeert alleen de rijen die dit register in een genoemd werkpakket
onderbracht — WP5 en WP9 zijn nooit toegekend en bestaan dus niet; de nummering is niet doorlopend.
Rijen die individueel fase-9-werk bleven zonder eigen werkpakket (I18, J7 — zie de eerste aantekening
eronder) tellen wél mee in de 75, maar staan niet als tabelrij.

| Werkpakket | Rijen |
| --- | --- |
| WP1 — hidden-library lekken ✅ gesloten | B8 |
| WP2 — contextmenu + write-scope ✅ gesloten | G12, G13 |
| WP3 — auth-status ✅, Mijn Pleya en deep links (I9, I10, I14) nog open | I9, I10, I14 |
| WP4 — all-source verwijderen uit Verder kijken ✅ gesloten | G10, G11 |
| WP6 — playbackreturn en detailfouten | A14, A15, D14, D15, I19, I20 |
| WP7 — profielwissel en serverlevenscyclus | A16, A17, A18, A19, E12 |
| WP8 — volgende aflevering | D11 |
| WP10 — Live TV-melding ✅ gesloten | A20 |
| WP11 — resterende registerrijen ✅ gesloten (J11 was de laatste) | J11 |

Vier aantekeningen bij die verdeling:

- **I18 en J7 zijn half bewezen, niet onbewezen, en blijven daarom open fase-9-werk zonder eigen
  werkpakket.** I18's topnav-helft en J7's rasterhelft staan er; wat ontbreekt is het griditem-geval
  respectievelijk de RTL-sweep over de fase-6/7/8-oppervlakken. Een half bewezen rij hoort geen
  `covered` te heten, en "WP11 ✅ gesloten" hierboven gaat alleen over WP11's eigen backloglijst — het
  betekent niet dat elke nog openstaande fase-9-rij dicht is.
- **J3, J6, J10, J11, J12, J13, J14, J15 zijn wél automatiseerbaar** en horen daarom niet bij de
  vijf hardwarerijen. Dat is inmiddels ook waargemaakt: J14 was de laatste van die acht die nog
  openstond en is op 2 september 2026 gesloten met widgettests tegen het productiefilterpaneel. `monoTheme({dark, oled})` maakt de themavarianten goedkoop, en een kleinere
  logische surface is een `binding.window`-instelling, geen toestel.
- **G1–G8 hangen aan één functie**, `selectRepresentativeWatchState`. Bij het openen van fase 9 week
  die op drie punten af van hoofdstuk 13.2; de G-groep is tijdens fase 9 zelf herschreven om te
  conformeren (zie hun eigen rijen verderop), dus er is geen deviation proposal meer nodig — deze
  aantekening stond eerder nog op "gaat als deviation proposal mee", wat na de herschrijving niet meer
  klopte.
- **A15-A18, D11, D14, I9, I14 en I20 staan nog op `open` binnen WP3/WP6/WP7/WP8.** Die
  werkpakketten zijn dus, anders dan WP1/WP2/WP4/WP10/WP11, nog niet gesloten — zie de einduitkomst
  verderop in dit document voor het volledige overzicht van wat na fase 9 nog openstaat.

### WP2 — contextmenu-bereikbaarheid: gebouwd

Vastgesteld op 1 september 2026, gebouwd dezelfde dag. De bevinding was bevestigd in code: **geen
enkele fase-6/7/8-TV-kaart had een contextmenu.** `grep` op `onLongPress`, `enableLongPress`, `isContextMenuKey`,
`MediaContextMenu` en `showContextMenu` over `lib/widgets/tv/` en `lib/screens/tv/` geeft nul hits.
Markeer bekeken/onbekeken, rate, verwijder uit Verder kijken en Kijklijst zijn daarmee onbereikbaar
vanaf Home, de Films- en Series-landings, de complete catalogus en TV-Search. De legacy-oppervlakken
(`tv_browse_rail.dart:937`, `hub_section.dart:574`) hebben hem wél — dit is dus een regressie van de
rewrite, geen ontbrekende functie.

**De naad is bekend en klein.** Beide unified tegels wrappen al in `FocusableWrapper`:
`tv_expandable_media_tile.dart:126` (Home-rijen, beide landings, TV-Search) en
`tv_unified_media_card.dart:114` (complete catalogus). `FocusableWrapper` draagt het
TV-contextmenucontract al — `onLongPress` vuurt op `key.isContextMenuKey` en op een lange Select,
met `SelectKeyUpSuppressor.suppressSelectUntilKeyUp()` ertegen. Er is dus geen nieuwe gesture nodig,
alleen een `onContextMenu`-callback op die twee tegels en een menu dat hem invult.

**Het write-scopecontract is beslist** (hoofdstuk 13.4, 13.5, 13.8 en 23, plus DEC-020): **elke
actie geldt voor alle memberships van de titel, en geen enkele vraagt om een bron.**

Daar is het in twee stappen op uitgekomen. WP2 leverde drie semantieken: `logical`,
`sourceSpecific` en een `sourceSpecificWithAllSources` met een expliciete "Alle bronnen"-rij voor
markeer bekeken/onbekeken. [DEC-071](../DECISIONS.md#dec-071) maakte die twee acties `logical`,
waarmee de derde variant zijn enige gebruiker verloor en met de hele keten eronder verdween.
[DEC-075](../DECISIONS.md#dec-075) deed daarna hetzelfde met `rate`, de laatste actie die nog vroeg,
en toen was `sourceSpecific` zelf over: een enum met één waarde is een switch die altijd dezelfde
kant op gaat, dus ook die is weg, samen met `ApplyActionToSource`, `AskForActionScope` en de picker.

De harde regel eronder is niet zwakker geworden maar zwaarder: een write kiest **nooit**
stilzwijgend `representativeSource` of de preferred server. Die twee zijn
activation/playback-conveniences; een verkeerd gelande write is onzichtbaar en permanent. Dat wordt
nu door de vorm afgedwongen in plaats van door discipline — er is één doeltype, het draagt een
lijst, en de lijst is elke membership. Een implementatie die naar `representativeSource` grijpt
levert een lijst van één, en dat is precies wat de negatieve controles zoeken.

**Wat er staat.** Drie lagen, elk met één verantwoordelijkheid:

| Laag | Bestand | Wat het beslist |
| --- | --- | --- |
| doel | `lib/screens/tv/tv_unified_context_actions.dart` | welke bronnen een actie raakt, en welke daarvan nu bereikbaar zijn |
| menu | `lib/screens/tv/tv_unified_context_menu.dart` | welke acties dit oppervlak aanbiedt, en de dispatch |
| rijen | `lib/widgets/tv/tv_source_row.dart` | de presentatie, gedeeld met de playbackpicker |

Die laatste was een extractie voor de scope-picker: `_SourceList` en `_SourceRow` zaten privé in
`tv_media_source_picker.dart` en zijn er ongewijzigd uit gelicht, met `TvSourceRowDescriptor` als
naad in plaats van `UnifiedMediaSource`. De picker die er de tweede consument van was bestaat niet
meer; de extractie is blijven staan omdat de playbackpicker er zelf op draait.

**De onthouden playbackkeuze blijft buiten de schrijfkant.** `rankSources` krijgt in
`resolveUnifiedActionTarget` bewust geen `preferredSourceKey`. Dat is geen dode voorzorg meer nu er
niets meer gevraagd wordt: `sources.first` is de membership waar de waarderingssheet aan bindt, dus
hij bepaalt of er sterren of duimpjes staan en welke servernaam onder "Opgeslagen" verschijnt. Een
preferred-tier vooraan zou de zichtbare helft van een schrijfactie op een bron zetten die de
gebruiker nooit koos. `the candidate list carries no preferred-source tier` bewaakt dat.

**De hero heeft bewust geen menu.** Hoofdstuk 7.3 somt het heromodel uitputtend op — Afspelen en Meer
info, met links/rechts gebonden aan het wisselen van slide — en kent daar geen contextmenu. Een lange
Select op een CTA die "start dit nu" betekent is een nieuw gebaar op een knop, geen kaartactie. Niet
toegevoegd, dus, en niet om symmetrie.

**Wat er níét in zat, en waarom.** `_applyToSources` meldde een gedeeltelijke mislukking eerlijk
(`doneOnSome`) in plaats van te rollbacken, wat 13.4 punt 5 en 13.5's "mislukte subset" vragen. De
lokale suppressie en het opnieuw uitvoeren bij reconnect — 13.4 punten 3 en 4 — waren **G10 en G11**
en hoorden bij WP4. Dat was de grens: WP2 vertelde de waarheid over de bronnen die het niet bereikte,
WP4 onthoudt ze. **WP4 is inmiddels gebouwd** — zie de noot onder register G.

Rijen die hierop wachtten: **G12** en **G13**, beide nu `covered`.


### WP3 — de permanente TV-banner is weg, de deep-linkhelft niet

Gebouwd op 1 september 2026. **Let op de tweedeling:** WP3 draagt in de tabel hierboven de rijen
I9, I10 en I14, en die gaan over Back en overlays — niet over auth. Wat hier gesloten is, is het
*defect*: `AuthErrorBanner` werd op regel 1168 van `main_screen.dart` onvoorwaardelijk gemonteerd,
dus ook op TV, waar hij als permanente volle-breedte rode strook boven Home, Films, Series en Search
stond. Hoofdstuk 18.4 verbiedt dat met zoveel woorden en schrijft het alternatief voor: "Een klein
statuspunt bij Mijn Pleya mag aandacht vragen, maar mag geen permanente grote rode melding over
content leggen." I9, I10 en I14 blijven `open` en zijn het resterende WP3-werk.

**Twee regels productie.** De mount krijgt `if (!_isTvShell)`, en `TvTopNavigation` krijgt een
`needsAttention`-vlag die op de Mijn Pleya-bestemming een amberen punt tekent. Meer was het niet,
omdat de rest er al stond: `MultiServerProvider.authErrorServerIds` scheidt 401/403 al van offline,
`TvMyPleyaScreen` toont de regel "Sessie verlopen voor NAS" al (met een commentaarregel die naar
18.4 verwijst), en `TvMyPleyaSection.servers` → `TvServersScreen` is de bestaande beheerroute. Geen
nieuwe server-managementarchitectuur, geen nieuw scherm, geen nieuwe heuristiek.

**Waarom het punt een overlay is en geen extra kind in de rij.** Een `Stack` meet zich naar zijn
grootste niet-gepositioneerde kind, en dat is de pill; het punt hangt eraan met `Positioned` en
`Clip.none`. Een extra box in de `Row` zou elke bestemming ernaast verschuiven op het moment dat een
token verloopt, en hoofdstuk 7.2 gaat er nu juist over dat de balk niet onder de afstandsbediening
vandaan beweegt. Het bewijs is dubbel: een test die de rechthoek van elke bestemming vóór en ná het
omklappen vergelijkt, en het feit dat `flutter test --update-goldens` geen enkele bestaande golden
herschreef — `tv_shell_home_active.png` is byte-identiek gebleven.

**Amber, niet rood.** Hoofdstuk 14.7 houdt die twee overal in deze rewrite uit elkaar: een verlopen
sessie is iets dat je vanaf de bank oplost, een kapotte server niet. De testfinder matcht daarom op
de kleur en niet op het widgettype, zodat een punt dat naar rood afdrijft rood gaat in plaats van
stilletjes door te glippen.

**De semantiek moest apart.** De inhoud van een navigatie-item zit in een `ExcludeSemantics` (anders
leest VoiceOver het label twee keer), dus het punt kan geen eigen semantische node dragen. De tekst
hangt aan `FocusableWrapper.semanticLabel`, en een aparte negatieve controle bewijst dat die regel
zelfstandig draagt.

Zeventien tests. Drie negatieve controles, los per onderdeel: de guard weghalen maakt er dertien
rood, het punt weghalen vier, de semantiekregel weghalen één. De eerste controle vond bovendien een
echt gat in de eerste opzet — de vier "geen rode strook"-tests monteerden alleen `TvRootShell`,
terwijl de banner erboven in `MainScreen` hangt, dus ze bleven groen mét verwijderde guard. De
harness monteert nu dezelfde `Column` die `MainScreen` bouwt, guard en al.

Non-TV is ongewijzigd: `AuthErrorBanner` zelf is niet aangeraakt, zijn eigen tests in
`test/widgets/auth_error_banner_test.dart` staan er nog, en twee tests pinnen de mountconditie in
beide richtingen vast via `TvDetectionService.debugSetAppleTVOverride`.

Visueel bewijs: `test/goldens/tv_shell_auth_attention.png` en `tv_shell_auth_my_pleya.png`.


## A. Server- en topologycases

| # | Case | Test | Status |
|---|---|---|---|
| A1 | Geen servers geconfigureerd | test/services/unified_catalog_service_test.dart (groep `WP11: server/library topology`, `A1: zero libraries never claims initialLoadFailed — nothing failed, there is nothing`) — een lege librarylijst is meteen `isComplete` en nooit `initialLoadFailed`, dat laatste is voor libraries die wél antwoordden en faalden | covered |
| A2 | Eén Plex-server | test/providers/unified_catalog_provider_test.dart (`ensureStarted loads the first page and settles into the snapshot`) — één Plex-client, één library, en de snapshot die de grid tekent | covered |
| A3 | Eén Jellyfin-server | test/services/unified_catalog_service_test.dart (`A3: a Jellyfin-only library set merges the same as a Plex-only one`) — de merge-engine vertakt nergens op `MediaBackend`, dus dit bewijst het letterlijk in plaats van het aan te nemen | covered |
| A4 | Eén Pleya Server | test/services/unified_catalog_service_test.dart (`A4: a Pleya Server-only library set merges the same as any other backend`) — PS-4 is vrijgegeven en `MediaBackend.pleyaServer` bestaat, dus deze rij was uitvoerbaar, alleen nog niet uitgevoerd | covered |
| A5 | Plex plus Jellyfin | test/services/unified_catalog_service_test.dart (`A5: Plex and Jellyfin libraries merge into one stream together`) — één globaal geordende stream over beide backends | covered |
| A6 | Drie of meer servers | test/services/unified_catalog_service_test.dart (`merges two libraries into one globally title-ordered stream, collapsing a shared duplicate`, drie servers in één merge); test/services/unified_catalog/source_resolver_test.dart (`the same film on three servers yields three concrete sources`) | covered |
| A7 | Twee servers met dezelfde displaynaam | test/services/unified_catalog/unified_activation_coordinator_test.dart (`F12: duplicate server names fall through to server id, then item id`); test/widgets/tv/tv_media_source_picker_test.dart (`F12: two servers with one name stay tellable apart by their library`) | covered |
| A8 | Eén server offline bij twee online servers | test/services/unified_catalog_service_test.dart (`one library erroring leaves the healthy results in place, and is retried on the next call`); test/services/unified_catalog/source_resolver_test.dart (`an offline expected server makes coverage incomplete`); test/goldens/tv_unified_catalog_golden_test.dart (`films, complete with one library missing`) voor de melding onder de grid | covered |
| A9 | Eén server met auth-error | test/services/unified_catalog/source_resolver_test.dart (`an auth-errored server is distinguished from a plain offline one`); test/services/unified_catalog/unified_activation_coordinator_test.dart (`F7: an auth error outranks offline…`); test/widgets/tv/tv_media_source_picker_test.dart (`F7: an auth error says something else than an offline server`) | covered |
| A10 | Alle servers offline | test/services/unified_catalog_service_test.dart (`every library failing on the very first round reports initialLoadFailed`); test/goldens/tv_unified_catalog_states_golden_test.dart (`films, nothing answered`) | covered |
| A11 | Server komt laat online | test/providers/unified_catalog_provider_test.dart (`a late server coming online reconciles the eligible library set`) | covered |
| A12 | Server valt weg tijdens paging | test/services/unified_catalog_service_test.dart (`A12: a library that fails after already contributing a page keeps what it gave, and is retried`) — anders dan A8 (die faalt vóór de eerste pagina) faalt deze server ná een geslaagde eerste pagina; die pagina blijft staan en de volgende `loadMore()` herprobeert dezelfde generieke foutafhandeling | covered |
| A13 | Server valt weg in source picker | test/services/unified_catalog/unified_activation_coordinator_test.dart (`focus after a source stops being usable`, vijf tests); test/widgets/tv/tv_media_source_picker_test.dart (`F11: the focused source going offline moves focus to the nearest usable row`) | covered |
| A14 | Server valt weg tijdens detail load | test/screens/media_detail_screen_test.dart (groep `F19/A14: detail load failure offers an alternative source`, vijf tests) plus de tweede schakel in groep `D14` (`F19/A14: the failure panel is the other door to the same switch`) — deelt precies dezelfde bindende regel als F19, hoofdstuk 21.7 | covered |
| A15 | Server valt weg tijdens playerstart | test/services/unified_catalog/unified_activation_coordinator_test.dart (groep `A15: the server that vanished during the start takes its whole shelf with it`, drie tests) — deelt F18's bindende regel; het verschil is *wanneer* beschikbaarheid gelezen wordt. `evaluatePlaybackFailure` herstempelt elke bron via `availabilityFor` op het moment van falen, dus een server die tijdens de start wegviel neemt élke bron die hij draagt uit het aanbod, niet alleen de bron die faalde, en bij niets bereikbaars verschijnt er geen paneel. De widgethelft is F18's `offers a choice and a way out, and takes neither by itself`; A15 verandert het paneel niet, alleen óf het verschijnt. Kanttekening: `unifiedServerHealth` neemt `authErrorServerIds` als momentopname mee terwijl `isOnline` live is, dus een auth-fout die tijdens het spelen ontstaat leest hier terug als offline — dezelfde alternatievenlijst, alleen een ander label | covered |
| A16 | Server wordt verwijderd | test/services/unified_catalog/unified_activation_coordinator_test.dart (`A16: a preferred server removed from the profile does not apply`); test/services/unified_catalog/source_resolver_test.dart (`A16: a hit naming a server that left the profile is revalidated, not trusted`); test/providers/unified_catalog_provider_test.dart (`A16: a server removed from the profile takes its titles with it`), plus de al bestaande runtimehelft test/profiles/profile_connection_cleanup_test.dart (`an unreachable Plex server is gone from the runtime, and its banner with it`) — elke lezer van een verdwenen server-id valt door: de onthouden bronsleutel matcht niets, de voorkeursserver vindt geen bron, de warme cache-hit wordt geherwaardeerd en de catalogus herprojecteert zonder zijn titels. Kanttekening, geen bug: tussen het verwijderen en het landen van de rebind noemt `expectedServerIds` de server nog, dus dekking meldt hem één ronde lang als niet-gecontroleerd — dat is A19's bewuste veilige kant | covered |
| A17 | Server wordt hernoemd | test/services/unified_catalog/unified_activation_coordinator_test.dart (`A17: a rename moves a row, and moves nothing else`, `A17: renaming reorders the picker without changing what is in it`) — identiteit is altijd het `serverId`: `sourceKey` is `serverId:itemId`, en `PreferredServerStore` legt in zijn eigen documentatie vast dat een voorkeur die een naam volgde stilletjes naar een andere machine zou wijzen. De naam heeft precies één functie voorbij weergave: hoofdstuk 4.7's tiebreaker, die doorvalt naar het id — hernoemen kan dus een rij verplaatsen, en verder niets. De weergegeven naam is item-gestempeld en ververst bij de volgende merge, dezelfde uitgestelde zichtbaarheid die 12.5 al voor herordening kent | covered |
| A18 | Server wordt opnieuw toegevoegd met ander ID | test/services/unified_catalog/unified_activation_coordinator_test.dart (groep `A16/A17/A18`, drie A18-tests: de onthouden sleutel van vóór de re-add noemt niets meer, de staande voorkeur overleeft de id-wissel niet dus de gebruiker wordt gevraagd, en opnieuw instellen op het nieuwe id werkt gewoon); test/services/unified_catalog/source_resolver_test.dart (`A18: a complete negative is not replayed over a server the profile has since added`, `A18: a negative still stands over a narrower profile than it was cached for`) — **gedragsgat, niet alleen bewijsgat**: een compleet negatief antwoord droeg geen serverset, zodat `_readCache` het herspeelde als `complete(expectedIds)` over de servers van *vandaag* en dus beweerde dat een net toegevoegde server niets heeft zonder hem ooit gevraagd te hebben. Negatieven dragen nu hun `checkedServerIds`, en een verbrede verwachting gooit de rij weg en herresolvet; rijen van vóór deze fix hebben geen ids en vallen er net zo uit, dus de migratie heelt zichzelf | covered |
| A19 | Profiel verwacht server die nog geen live client heeft | test/services/unified_catalog/source_resolver_test.dart (groep `A19: expected-server denominator`, negen tests: geen client, online maar geen antwoord, auth-error, niet-verwacht-en-niet-zichtbaar, zichtbaar-maar-nog-niet-verwacht, alles beantwoord, en de onbekende backend die tóch meetelt), plus de bronbewaker `every SourceAllResolver in lib/ takes its server list from eligibleSourceServers` die de twee aanroeppunten aan `eligibleSourceServers` bindt | covered |
| A20 | Live TV-capability komt laat binnen | test/navigation/tv/tv_live_tv_capability_test.dart (`a fresh sighting is visible and gets stored`, `a sighting that is already remembered is visible and does not trigger a redundant write`) voor het besluit; test/screens/tv/tv_root_shell_test.dart (`appears and disappears without disturbing its neighbours`) en test/widgets/tv/tv_top_navigation_test.dart (`a Live TV slot appearing does not replace the focus node of an existing item`) voor de balk die er al stond toen de capability binnenkwam | covered |

## B. Librarycases

| # | Case | Test | Status |
|---|---|---|---|
| B1 | Eén movie library | test/providers/unified_catalog_provider_test.dart (`ensureStarted loads the first page and settles into the snapshot`); test/services/unified_catalog/source_cursor_test.dart (`restricts to the requested kind`) | covered |
| B2 | Meerdere movie libraries op dezelfde server | test/services/unified_catalog_service_test.dart (`paging target is a group count: it stops at groupsPerPage new groups, not a raw item count`) — twee libraries op één server, allebei in de merge | covered |
| B3 | Movie libraries op meerdere servers | test/services/unified_catalog_service_test.dart (`merges two libraries into one globally title-ordered stream, collapsing a shared duplicate`) | covered |
| B4 | Series-only profiel | test/services/unified_catalog/source_cursor_test.dart (`B4: a series-only profile has no movie libraries, and a Films query answers empty rather than guessing`) — `eligibleCatalogLibraries`'s kindfilter was alleen getest met beide kinds aanwezig; dit dwingt het nul-resultaat af | covered |
| B5 | Movies-only profiel | test/services/unified_catalog/source_cursor_test.dart (`B5: a movies-only profile has no show libraries, and a Series query answers empty the same way`) | covered |
| B6 | Mixed/shared Plex library | test/services/unified_catalog/source_cursor_test.dart (groep `B6: mixed libraries`, vijf tests: een `MediaKind.unknown`-library telt mee voor Films, telt mee voor Series, een concreet niet-matchend kind blijft uitgesloten, zichtbaarheid blijft gelden, en een gewone en een gemengde library tellen samen mee) en test/services/unified_catalog_service_test.dart (groep `B6: a mixed library splits correctly by catalog`, twee tests: één fysieke gemengde library levert een film alleen onder Films en een serie alleen onder Series, en een library met geen van beide typen antwoordt voor allebei leeg in plaats van te gokken) — `eligibleCatalogLibraries` sloot een library met `kind == unknown` voorheen overal uit; nu telt hij voor elke catalogus mee en doet de bestaande per-request serverfilter (Plex `type=`, Jellyfin `IncludeItemTypes`, allebei al elders getest) de echte item-level classificatie. **Die belofte geldt niet op elke backend** — zie B16, dat het restant vastlegt | covered |
| B7 | Verborgen library als enige bron | test/providers/unified_catalog_provider_test.dart (`server.hidden excludes a library from the merge, matching eligibleCatalogLibraries`, `a hidden-library change after starting reconciles and reloads with the library excluded`); test/services/unified_catalog/source_cursor_test.dart (`excludes a library the user hid, even though its server is visible`) | covered |
| B8 | Verborgen library als tweede duplicate bron | zoekhelft: test/services/data_aggregation_bridge_test.dart (`searchAcrossServers applies hidden-library visibility`, negen tests). Resolverhelft: test/services/unified_catalog/source_resolver_test.dart (groep `hidden libraries`, veertien tests — A/B `a hidden second copy drops out, the visible one stays` en `a title only a hidden library holds resolves to no source at all`, D `hiding a library after a warm positive does not serve the cached source`, E `unhiding lands back on the row the visible resolve already wrote`, F `two visibility sets on one profile never share a row`, G `an item in no library at all is kept, whatever is hidden`, H `with nothing hidden the answer is exactly what it was`); C via de pickernaad in test/screens/tv/tv_unified_activation_hidden_library_test.dart (`a duplicate in a hidden library never becomes a picker row`) | covered |
| B9 | Library wordt tijdens gebruik verborgen | test/providers/unified_catalog_provider_test.dart (`a hidden-library change after starting reconciles and reloads with the library excluded`) | covered |
| B10 | Library wordt verwijderd | test/providers/unified_catalog_provider_test.dart (`B10: a library deleted server-side reconciles the same way a hidden one does`) — `LibrariesProvider.debugSetLibraries` die het setje laat *krimpen* in plaats van groeien (A11's spiegelbeeld); dezelfde reconciliatie die B9 al voor verbergen bewees | covered |
| B11 | Library heeft geen items | test/services/unified_catalog_service_test.dart (`B11: a legitimately empty library sits quietly alongside a populated one`) — leeg is geen fout, `failedLibraryIds` blijft leeg | covered |
| B12 | Library fetch geeft timeout | test/services/unified_catalog_service_test.dart (`B12: a timeout is handled exactly like any other transient fetch failure`) — een `TimeoutException` valt in dezelfde generieke catch als elke andere fout uit A8/A12, aantoonbaar in plaats van aangenomen | covered |
| B13 | Library antwoordt met lege pagina vóór total bereikt | test/services/unified_catalog_service_test.dart (groep `E8: totalCount is advisory, never sole exhaustion authority`, `an empty final page ends the cursor regardless of what the total claims`) — een `totalCount` die voor altijd 999 blijft claimen wordt genegeerd zodra de pagina zelf leeg komt; dezelfde E8-exhaustielogica die B13 nodig heeft, hergebruikt in plaats van apart getest | covered |
| B14 | Backend herhaalt item op twee pagina's | test/services/unified_catalog_service_test.dart (`B14: an item the backend repeats on the next page does not become a second card`) door de echte pagingmotor; test/services/unified_grouping_service_test.dart (groep `concrete-source dedup (B14/B15/E15)`: `B14: an item the backend repeats on a later page does not become a second card`, `B14: the repeat never moves the card off the position its first sighting won`) | covered |
| B16 | Gemengde library op een backend die niet op de wire filtert | Lokale map: `test/services/local_folder_ordering_test.dart` (`a library page honours the kind the query asked for`) — `_applyFilters` leest `query.kind` nu, want daar ís geen wire en die regel *is* het filter. **Pleya Server niet:** `browse.dart` stuurt alleen `sort` mee, en `query.kind` bereikt de wire niet. Zolang die server geen librarykind noemt dat deze build niet kent terwijl de items er wél classificeerbaar zijn, is er niets te zien; gebeurt dat wel, dan toont Series de films van die map en andersom. Niet opgelost omdat het protocol bevroren is (PS-5) en client-side filteren de offsetrekening breekt: de cursorledger telt in serverposities en de beller in teruggegeven items, en filteren laat die twee uit elkaar lopen. De fix is de ledger per kind sleutelen en in gefilterde posities laten tellen — een aparte wijziging met eigen bewijs, geen regel erbij | open (coverage debt) |
| B15 | Item verhuist tussen libraries | test/services/unified_grouping_service_test.dart (`B15: an item reported under two libraries is one membership, keeping the first library`) — `sourceKey` is `serverId:id`, dus beide waarnemingen zijn dezelfde concrete membership en de eerste wint | covered |
| B17 | TV Search kan lopen terwijl `HiddenLibrariesProvider` zijn persisted visibility nog niet geladen heeft | test/screens/search_screen_test.dart (groep `B17: hidden-library visibility and TV search`, drie tests) — hoofdstuk 22's harde regel is VISIBILITY vóór grouping/resolution/activation, en `_performSearch` leest `hiddenLibraryKeys` synchroon (bewust, zie de noot bij fase-9-sluiting hierboven en `docs/CHANGELOG.md`): een query vlak na het monteren van de profielsessie kan dus nog tegen een leeg setje draaien. In plaats van de dispatch zelf te blokkeren (dat bleek exact de eerder verworpen fix, en brak opnieuw op dezelfde `pumpAndSettle`-timeout uit zeven schermtests toen het geprobeerd werd) luistert het scherm al op `HiddenLibrariesProvider`'s eigen wijzigingen: `_initialize()` eindigt met dezelfde onvoorwaardelijke `notifyListeners()` als een latere hide/unhide, dus dezelfde listener draait de laatst gezochte query opnieuw zodra de echte set landt, vóór een gebruiker er redelijkerwijs op kan hebben gehandeld. Twee tests bewijzen die kant: een library die tijdens een actieve sessie verborgen wordt haalt zijn resultaat van het scherm, en het omgekeerde (unhide) brengt het terug. Een sleutelvergelijking tegen de laatst gebruikte set (`setEquals`) voorkomt dat zo'n correctie zelf een overbodige tweede fan-out kost wanneer de effectieve set niet verandert — bewezen door de derde test, die na een no-op-wijziging exact één `client.queries`-entry telt. Negatieve controle gedraaid: zonder de listener vallen precies de eerste twee tests om, terwijl de derde (die niets hoeft te draaien) groen blijft. De smalle cold-start-race zelf — een query die start vóórdat de opslag geladen is — wordt door hetzelfde mechanisme gecorrigeerd (`_initialize()`'s eigen notify is niet anders dan een hide/unhide), maar is hier niet apart als test opgenomen: hij bleek onder `flutter_test`s eigen scheduling te betrouwbaar weg te vallen om zonder vals-negatief bewijs te leveren. Bijvangst: het testbestand initialiseerde `StorageService` ná `SettingsService`, wat op deze `flutter_test`-versie een echte, orde-afhankelijke deadlock in `BaseSharedPreferencesService.initializeInstance` blootlegde zodra een test die afronding daadwerkelijk afwacht — omgekeerde volgorde in `setUp()` lost het op; zie het losse issue dat daarvoor is aangemaakt | covered |
| B18 | Home komt terug vanaf de eerste rij (P1) | test/screens/tv/tv_content_feed_test.dart (groep `P1: the hero comes back into view, not just back into the focus tree`, drie tests). `_focusHeroFromFirstRow` probeerde `focusLastCta()` vóór het herstellen van de scrollpositie en keerde terug zodra dat lukte. Dat lukt terwijl de carousel nog binnen `cacheExtent` gemonteerd is, dus volledig buiten beeld: `canRequestFocus` is waar voor een gemonteerde offscreen node, en een kale `requestFocus()` lokt geen `ensureVisible` uit. Alleen de traversal policy doet dat, en dit ís geen traversal. De `jumpTo(0)` een regel lager werd daardoor overgeslagen, de volgende druk vertrok naar de topnav, en het billboard was van onderaf onbereikbaar. De scroll gaat nu eerst, in beide takken. Beide helften worden geassert (focus **en** `scrollOffset == 0`), want het defect voldeed aan de eerste; een test die alleen naar focus keek was er groen doorheen gelopen. Negatieve controle gedraaid: met de oude volgorde terug staan alle drie op offset 269,3 | covered |
| B19 | Eén autoriteit voor "de afstandsbediening hoort nu in de content" (P2) | test/screens/tv/tv_content_focus_authority_test.dart (acht regeltests plus de DOWN-consument op de productie-`TvRootShell`) en test/screens/discover_screen_tv_hero_test.dart (groep `P2: one content-focus authority`, twee tests op het echte `DiscoverScreen`). Drie onafhankelijke paden verplaatsten de focus naar TV-content: `_selectTab`'s `focusActiveTabIfReady`, `_selectTvDestination`'s onvoorwaardelijke `_focusContent`, en `DiscoverScreen`'s initial-load-postframe. Er is nu één `TvContentFocusAuthority` met een consume-once-intent: Select op een *andere* bestemming wisselt de pagina en laat de ring in de balk, Select op de actieve bestemming herstelt (hoofdstuk 7.2, ongewijzigd), DOWN uit de balk vraagt erom, en laat aankomende content mag alléén een al gewapende intent consumeren. Een koude start legt de focus voortaan expliciet op de balk. Vóór deze ronde deed niets dat, en viel de uitkomst toe aan welk van de drie paden toevallig als laatste vuurde. Negatieve controle gedraaid: zonder de guard in `DiscoverScreen` pakt het billboard de afstandsbediening zonder dat iemand erom vroeg. **Niet gedekt:** `MainScreen` zelf wordt door geen enkele test in deze repo gemonteerd, dus dat `MainScreen` deze autoriteit correct aanroept is niet behavioraal bewezen; de regel is dat wel | covered (met genoemde grens) |
| B20 | Kijklijst is met een afstandsbediening te bedienen (P5) | test/screens/watchlist_screen_test.dart (groep `TV focus (P5)`, acht tests) en test/screens/tv/tv_offstage_focus_test.dart (drie tests). Vier gestapelde oorzaken: de Mijn Pleya-route maakte een `GlobalKey` en gaf hem aan niets door, `_WatchlistScreenState` implementeerde `FocusableTab` niet, `WatchlistCard` accepteerde `key` en `focusNode` en de call-site gaf geen van beide mee, en zowel de `IndexedStack` in `MainScreen` als de `Offstage`-tak in `TvRootShell` hield een complete tweede, onzichtbare kopie van elk scherm focusbaar in dezelfde scope. Alle vier gerepareerd; het knooppuntenpatroon van `TvUnifiedMediaGrid` (nodes op stabiele id, `ValueKey`, expliciete `onNavigate*`) is overgenomen. De `IndexedStack`-compositie is als `mainScreenDestinationStack` naar toplevel getild zodat de guard de productiecompositie draait en geen kopie ervan | covered |
| B21 | Verder kijken staat op één oppervlak (P3, [DEC-086]) | test/providers/tv_discovery_landing_provider_test.dart (`DEC-086: neither landing carries a Continue Watching row, however full on-deck is`, `DEC-086: Home still has it, over the very same on-deck list`, `the landing never showed an episode on Films, which is why the row had to go`) en test/screens/tv/tv_discovery_landing_screen_test.dart (twee tests, waaronder de traversal ↑ vanaf de eerste rail naar de paginakop). Beide richtingen zijn geassert, want alleen bewijzen dat de rij weg is zou groen blijven als hij nergens meer bestond. De CW-projectiecontracten (hoofdstuk 11.8, 13.1, 21.4) zijn mee verhuisd naar `TvHomeProjectionProvider` en beweren hetzelfde als eerst | covered |
| B22 | Dichtheid en compositie van een discovery-rail ([DEC-087]) | test/widgets/tv/tv_discovery_density_test.dart (vijf tests). Telt kaarten op het canonieke 1038×584-canvas in plaats van de constante te asserten: zes vol in ruststand met een zevende die meer dan 60 px toont, vier volle buren naast de gefocuste kaart, een gefocust aandeel van ~34,5%, en een bandhoogte die niet met de focus meebeweegt. Een assertie op `cardHeight == 220` zou groen blijven nadat iemand `itemGap` of `pageInset` veranderde en de zevende kaart kwijtraakte. Kijklijst en Aanvragen staan op TV op dezelfde `TvCatalogGrid`-geometrie (bewezen in `watchlist_screen_test.dart`), de niet-TV-paden zijn ongemoeid | covered |
| B23 | De onderrand ligt buiten de overscanband (P12) | test/widgets/tv/tv_discovery_density_test.dart (`the bottom edge clears the overscan band with room to spare (P12)`). `TvCatalogLayout.bottomSafeInset` (81 referentiepixels, 7,5% van de referentiehoogte) staat naast `topSafeInset` (56). Hoofdstuk 8.1 noemt een minimum, en 56 is 5,2% van de hoogte: ongeveer precies de band die een consumentenset opeet, dus een pagina die daarop uitkomt zet zijn laatste regel *op* de rand in plaats van erbuiten. Dit is een strengere marge, geen afwijking. De focusgroei telt apart en wordt niet uit de marge betaald | covered |
| B24 | De gefocuste kaart valt niet buiten de rail (P9) | test/widgets/tv/tv_discovery_rail_test.dart (groep `P9`, vier tests). De rail heeft geen eigen `ensureVisible`, en Flutter's traversal policy kan er geen leveren: die meet de tegel op het moment dat focus landt, dus nog op posterbreedte, waarna hij naar 2,67 keer die breedte groeit. `FocusableWrapper._scrollIntoView` zoekt een *verticale* scrollable en vindt er geen. `_revealFocused` rekent daarom uit de layouttokens, niet uit render boxes, en houdt de page inset aan beide kanten aan: dezelfde rechthoek die `tvos.discovery.overscan` tegen `discover.safe_area` meet. Negatieve controle gedraaid: zonder de reveal loopt tegel 5 over de rechterrand. **Bevinding:** de tweede helft van de gemelde diagnose ("de laatste tegel heeft geen trailing ruimte om in uit te klappen") klopt niet. De expansie is een `AnimatedContainer` *binnen* de scrollable, dus hij vergroot de content zelf en `maxScrollExtent` komt op de pixel uit waar de reveal hem wil hebben. De trailing padding daarvoor is geschreven, getest, en verwijderd toen de negatieve controle ervan groen bleef | covered |
| B25 | Volgende pagina wordt gevraagd vóór het einde (P11) | test/widgets/tv/tv_unified_media_grid_test.dart (groep `P11: paging`, vier tests). De trigger was DOWN op de laatste rij en verder niets: geen scroll-listener, geen drempel, geen achtergrondprefetch, dus de kijker moest eerst tegen het einde aan navigeren en dán wachten. `_maybeLoadMore` vuurt zodra de gefocuste index binnen twee gridrijen van het einde valt, en verplaatst de focus niet (hoofdstuk 28 verbiedt een reflow). De DOWN-trigger blijft staan als achtervang voor het geval `hasMore` pas waar wordt nadat de focus al onderaan stond. Negatieve controle gedraaid | covered |
| B26 | Artwork is warm vóór de focus arriveert (P8) | test/services/unified_catalog/unified_artwork_prefetcher_test.dart (groep `a second variant`, zeven tests) en test/widgets/tv/tv_discovery_rail_test.dart (groep `P8`, drie tests). De 16:9-variant is een ánder bestand dan de poster en werd opgehaald op het moment dat focus arriveerde. De prefetcher warmt nu beide op **één** wachtrij, één `_inFlight`-teller en één `maxConcurrent`: twee losse prefetchers van drie zouden samen de zes globale permits uit `image_cache_service.dart` kunnen bezetten en precies de tegel op het scherm uithongeren. De wide-variant heeft een eigen, veel kortere lookahead (vier tegen twaalf) en de LRU is níét verhoogd. Eigendom ligt bij `TvDiscoveryRailState`, niet bij `itemBuilder`. De verplichte fast-focus-eis is geen wedloop maar een garantie: de wide-tak draagt het posterframe als placeholder, dus er is nooit een lege beat. Negatieve controle gedraaid op die placeholder | covered |
| B27 | Metaregel toont geen informatie die al zichtbaar is (P10, [DEC-087]) | test/widgets/tv/tv_discovery_rail_test.dart (groep `P10`, vijf tests). Het bronnenaantal stond zowel in de metaregel als, in dezelfde oogopslag, als `TvSourceCountBadge` op de kaart erboven; die eerste is weg. Een film wint zijn speelduur, tenzij hij een resume-positie heeft: dan zegt "nog 60 min" hetzelfde beter. Een aflevering krijgt geen speelduur, om diezelfde reden. Een server die geen duur meldt levert geen regel op in plaats van een verzonnen nul, dezelfde regel die de resterende-tijdregel al volgde | covered |
| B28 | Aanvragen op TV (P7) | test/screens/seerr/seerr_discover_tv_test.dart (negen tests). Vier reële resten na `505e8cc`/`f8c7d47`: de filterbalk overschreef `showDivider` niet en tekende dus een streep die op geen ander TV-scherm bestaat; een hardgecodeerde `fontSize: 26` liep niet door de scale clamp; het resultatengrid stond op een horizontale inset van 8 tegen de 72 van de zoekbalk erboven, oftewel 64 px naar links en in de overscanband; en er stonden twee inbox-knoppen waarvan er één in de `ExcludeFocus`-appbar zat en dus onbereikbaar was, terwijl `SeerrPosterCard` geen enkele richtingscallback had. **De gemelde eigen `Scaffold`/`SliverAppBar` bestaat niet meer** en is niet opnieuw opgelost. **Niet gedekt:** `SeerrDiscoverScreen` zelf wordt niet gemonteerd, want `SeerrProvider` heeft geen testseam voor een sessie, dus de twee schermregels worden bewezen via de benoemde functies die het scherm aanroept (`seerrDiscoverAppBarActions`, `seerrRowHeaderStyle`) en niet via een kopie ervan | covered (met genoemde grens) |
| B29 | Contextmenu noemt positie en aantal (J8-software) | test/widgets/tv/tv_unified_context_menu_semantics_test.dart (vier tests). `tvContextMenu.menuSemantics` stond sinds fase 9 in zestien talen en werd nergens aangeroepen; het paneel bevatte geen enkele `Semantics(` en de enige toegankelijkheidsuitvoer van een rij was de kale actienaam. De samenstelling staat op de call-site, waar `index` en `actions.length` al in scope zijn, achter een optionele parameter. Het sorteer- en filterpaneel delen dezelfde `TvCatalogOptionRow` en veranderen niet, wat apart geassert wordt | covered |


**B8 had twee helften, en fase 9 heeft ze allebei gesloten.** Eerst de zoekhelft:
`DataAggregationService.searchAcrossServers` was de enige aggregatie-ingang zonder
`hiddenLibraryKeys` — servers werden door `_clientsFor` uitgesloten, libraries door niemand — en
filtert nu vóór ranking en trimmen, met een gedeelde `filterHiddenLibraryItems` die de drie
gedupliceerde inline-predicaten in on-deck, latest movies en hubs vervangt. Negen tests dekken de
gevallen; zonder de filter gaan er zeven van rood, en de twee die groen blijven zijn de
fail-open-controles (een item zonder `libraryId` — een Plex Discover-hit uit `includeExternalMedia`
bijvoorbeeld — zit in geen enkele library, dus geen verborgen sleutel kan hem noemen).

De **resolverhelft** is daarna gesloten, en die zat inderdaad open zoals hierboven beschreven: de
kaart zei terecht "1 bron" en even later voegde `SourceAllResolver` de verborgen bibliotheek alsnog
als pickerrij toe. `hiddenLibraryKeysFor` is nu een tweede live callback naast `serversFor`, en het
filter zit in `onBatch`, dus vóór het antwoord bewaard wordt: een filter ná de cache zou zeven dagen
lang teruggedraaid worden door de eerstvolgende warme hit.

Twee dingen bleken bij het repareren anders te liggen dan de noot hierboven aannam.

**Het bestaande `filterHiddenLibraryItems` kon hier niet hergebruikt worden.** Die leest
`item.serverId`, en de identity-fan-out levert items waar die niet op staat. Plex'
`findAllByIdentity` heeft twee takken en alleen de guid-tak loopt via `_tagMetadata`, dat de
serverId erop zet; de titel-fallback mapt met `PlexMappers.mediaItemFromJson(raw)` en geeft
er geen mee (`plex_client.dart`, `_candidatesWithGuids`). Die items dragen dus wél een `libraryId`
en géén `serverId`, en een filter op `item.serverId` zou fail-open gaan op precies de tak die een
identity zonder guid neemt. `visibleMatchesFromServer` gebruikt daarom de server die *antwoordde* —
een client geeft alleen zijn eigen items terug, dus dat is de gezaghebbende id. De fail-open blijft
staan waar hoofdstuk 22 hem zette, maar alleen nog voor een item zonder `libraryId`; een ontbrekende
serverId is geen fail-open-grond meer. `an item with a library id but no server id is still filtered`
bewaakt dat.

**De cachesleutel moest de zichtbaarheid meedragen.** Zonder dat lost het filter alleen de koude
resolve op: een rij die geschreven is toen de bibliotheek nog zichtbaar was, wordt daarna gewoon
warm teruggegeven. De sleutel is `match/<profiel>/<vingerafdruk>/<identity>`, waarbij de
vingerafdruk een sha1 over de gesorteerde verborgen sleutels is — gesorteerd, zodat twee volgordes
van dezelfde verzameling dezelfde rij zijn, en een digest in plaats van de verzameling zelf, zodat
een profiel met veertig verborgen bibliotheken geen sleutel krijgt die langer is dan de identity die
hij indexeert. De verzameling wordt één keer per resolve gelezen en doorgegeven, niet opnieuw bij het
schrijven: anders kan een hide die halverwege landt gefilterde items opslaan onder de vingerafdruk
van de verzameling waarmee ze *niet* gefilterd zijn. Verbergen maakt de oude rij daarmee
onbereikbaar in plaats van muf, en zichtbaar maken landt terug op de rij die de eerdere zichtbare
resolve al schreef — geen extra invalidatiehaak nodig, en `invalidate()` blijft de hele namespace
wissen.

Negatieve controles, beide takken los uitgezet: zonder het filter gaan er negen rood, zonder de
vingerafdruk drie (`D: hiding a library after a warm positive…`, `D: a warm negative written while
hidden…`, `F: two visibility sets on one profile never share a row`). Beide helften dragen dus
gewicht.


## C. Identitycases

Minimaal deze categorie is vereist in fase 1 (hoofdstuk 27, `test/media/canonical_media_identity_test.dart`
en `test/services/unified_grouping_service_test.dart`).

| # | Case | Test | Status |
|---|---|---|---|
| C1 | Zelfde TMDB-ID | test/media/canonical_media_identity_test.dart (`externalIdTokens C1`); test/services/unified_grouping_service_test.dart (`C1`) | covered |
| C2 | Zelfde IMDb-ID | test/media/canonical_media_identity_test.dart (`externalIdTokens C2`) | covered |
| C3 | Zelfde TVDB-ID voor serie | test/media/canonical_media_identity_test.dart (`externalIdTokens C3`) | covered |
| C4 | Zelfde stabiele GUID | test/media/canonical_media_identity_test.dart (`normalizeStableGuid C4`, `guidTokens C4`) | covered |
| C5 | Gelijke titel en jaar zonder IDs, ondubbelzinnig | test/services/unified_grouping_service_test.dart (`two sources with no strong evidence still merge via title+year when unambiguous`) | covered |
| C6 | Gelijke titel met verschillend jaar | test/media/canonical_media_identity_test.dart (`bucketKey C6/C9`) | covered |
| C7 | Gelijke titel en jaar met conflicterende IDs | test/services/unified_grouping_service_test.dart (`C7`) | covered |
| C8 | Gelijke titel zonder jaar | test/media/canonical_media_identity_test.dart (`bucketKey C8`) | covered |
| C9 | Remake met dezelfde titel | test/services/unified_grouping_service_test.dart (`C9`); test/media/canonical_media_identity_test.dart (`bucketKey C6/C9`) | covered |
| C10 | Movie en serie met dezelfde titel | test/media/canonical_media_identity_test.dart (`bucketKey C10`, `canonicalIdentityOf C10`) | covered |
| C11 | `agents.none://` GUID | test/media/canonical_media_identity_test.dart (`normalizeStableGuid C11`, `guidTokens C11/C12`) | covered |
| C12 | Serverlokale GUID | test/media/canonical_media_identity_test.dart (`normalizeStableGuid C12`, `guidTokens C11/C12`) | covered |
| C13 | Director's Cut en theatrical edition | test/services/unified_grouping_service_test.dart (`C13`) | covered |
| C14 | Zelfde item met meerdere media versions | test/services/unified_grouping_service_test.dart (`C14`) | covered |
| C15 | Unicode, leestekens en diakritische titels | test/media/canonical_media_identity_test.dart (`bucketKey C15`) | covered |
| C16 | Alternatieve of originele titel | test/services/unified_grouping_service_test.dart (`C16`) | covered |
| C17 | Verkeerd serverjaar | test/services/unified_grouping_service_test.dart (`C17`); test/media/canonical_media_identity_test.dart (`yearAgreesWith C17`) | covered |
| C18 | Eén bron heeft jaar, andere niet | test/media/canonical_media_identity_test.dart (`yearAgreesWith C18`) | covered |
| C19 | Meerdere kandidaten op één server | test/services/unified_grouping_service_test.dart (`C19`) | covered |
| C20 | External-ID-fetch faalt | test/services/unified_catalog/identity_resolver_test.dart (`C20`) | covered |
| C21 | External IDs veranderen na metadata-refresh | test/services/unified_catalog/identity_resolver_test.dart (`C21`) | covered |
| C22 | Group krijgt later sterker bewijs | test/services/unified_grouping_service_test.dart (`C22`) — alleen inhoudelijke stabiliteit; sessie-stabiliteit van `groupId` volgt pas met fase 3's `UnifiedCatalogProvider` | covered |
| C23 | Groupingconflict in een connected component | test/services/unified_grouping_service_test.dart (`C23`) | covered |
| C24 | Pleya Server/local item zonder external IDs | test/media/canonical_media_identity_test.dart (`externalIdTokens C24`); test/services/unified_grouping_service_test.dart (`C24`) | covered |

## D. Series- en episodecases

| # | Case | Test | Status |
|---|---|---|---|
| D1 | Zelfde serie op twee servers | test/providers/tv_discovery_landing_provider_test.dart (`D1: the same episode of one series on two servers is one card carrying both sources`, `D1: two episodes of one series on two servers stay two cards`) — beide helften van de rij, door de productieprovider heen; test/services/unified_catalog/home_projection_service_test.dart (`C: the same episode on two servers is one card, and its sources stay the concrete episodes`, `A/E: two episodes of one series stay two cards, on one shared series-wide id`, `B: two seasons of one series stay two cards`) voor dezelfde regel op serviceniveau. In alle vijf krijgen beide rijen dezelfde serie-brede tmdb/tvdb, dus geen ervan slaagt doordat de externe ids leeg waren | covered |
| D2 | Verschillende seizoensdekking | test/services/unified_catalog/home_projection_service_test.dart (`D2: sources reporting different season coverage for the same show still merge into one card`) — identiteit sleutelt op titel/jaar/extern id, nooit op `childCount`; een bron die tot seizoen 2 zit forkt niet naast een die al seizoen 3 heeft | covered |
| D3 | Zelfde episode met sterke ID | test/services/unified_catalog/identity_resolver_test.dart (`D3: an episode guid is exact-episode evidence and contributes on its own`); test/services/unified_catalog/home_projection_service_test.dart (`D: two servers reporting the same strong episode guid merge without any external id`, `D/E: a strong episode guid never merges two different episodes of one series`) | covered |
| D4 | Zelfde episode via serie-ID plus S/E | test/services/unified_catalog/identity_resolver_test.dart (`D4: a series-wide external id becomes exact-episode evidence, not series evidence`, `E: two episodes forced into one bucket still get different tokens from one series id`); test/services/data_aggregation_bridge_test.dart (`getOnDeckFromAllServers hides the same episode listed twice under one stable show id`, `getOnDeckFromAllServers keeps two different episodes of one show under one stable show id`) — de upstream-dedup, die vóór elke Home-projectie draait | covered |
| D5 | Specials seizoen 0 | test/media/canonical_media_identity_test.dart (`D5: season 0 (specials) is a real, distinct, bucketable season index`) | covered |
| D6 | Ontbrekend seizoennummer | test/media/canonical_media_identity_test.dart (`D6/D7: a missing season or episode index makes the episode bucket unusable`, `D6: an episode missing its season index has no bucketable identity`); test/services/unified_catalog/identity_resolver_test.dart (`D6/D7: an episode with no usable ordinal has no bucket at all, so it never buys a series id`) voor de Verder kijken-helft | covered |
| D7 | Ontbrekend afleveringsnummer | test/media/canonical_media_identity_test.dart (`D6/D7: a missing season or episode index makes the episode bucket unusable`); test/services/unified_catalog/identity_resolver_test.dart (`D6/D7: an episode with no usable ordinal has no bucket at all, so it never buys a series id`), plus test/services/unified_catalog/home_projection_service_test.dart (`G: episodes with no usable season or episode index never merge on their series alone`) | covered |
| D8 | Double episode | test/services/unified_catalog/home_projection_service_test.dart (`D8: a combined double episode on one server only matches the first half on a server that split it`) — geen absolute-numbering-vertaler (D9's eigen regel): een gecombineerde dubbelaflevering "4" matcht letterlijk alleen bron B's eigen "4", en B's losse "5" blijft een echte, ongekoppelde eenbrons-kaart | covered |
| D9 | Absolute numbering versus season numbering | test/services/unified_catalog/home_projection_service_test.dart (groep `D9: absolute vs season/episode numbering`, drie tests: een echte nummeringsbotsing zonder sterk ID blijft twee kaarten, een gedeeld episode-guid merget ondanks de botsende nummering, en een gedeeld series-ID met botsende ordinal-narrowing merget ook niet) — bleek al correct: `continueWatchingOrdinal` vergelijkt seizoen/aflevering letterlijk zoals elke bron ze rapporteert, bouwt geen vertaling tussen nummeringsschema's, en een botsende ordinal geeft een andere bucketsleutel die nooit met de andere concurreert; een sterk ID blijft daarnaast leidend ongeacht de presentatie. Bewijsgat, geen gedragsgat | covered |
| D10 | Eén bron loopt één aflevering achter | test/providers/tv_discovery_landing_provider_test.dart (`D1: two episodes of one series on two servers stay two cards`) — server_1 op S02E04, server_2 al op S02E05, beide met dezelfde series-tmdb; blijven twee Verder-kijken-kaarten in plaats van één geblende positie. Andere provider (fase-6 landing, niet fase-8 Home) maar dezelfde `HomeProjectionService`/identity-pipeline; existing-proof-first citeert het bestaande bewijs in plaats van het te dupliceren | covered |
| D11 | Next Episode alleen op andere bron | test/services/episode_navigation_service_test.dart (drie tests) — hoofdstuk 15's bindende zin is het verbod, niet het aanbod: de queue wordt uit precies één client gebouwd (`metadata.serverId`), dus een volgende aflevering die alleen elders bestaat levert géén next op en de andere server wordt niet eens bevraagd. **Gedragsgat gevonden en gedicht**: de per-sessie episodecache stond op de kale `grandparentId`, en dat id is server-lokaal — twee servers die hun show hetzelfde noemen lieten de ene lijst voor de andere playback antwoorden. Alleen de cachesleutel is server-gescoped; de contextsleutel blijft het kale serie-id omdat `JellyfinSequentialLauncher` hem in die vorm schrijft en de playlistbescherming daartegen vergelijkt. Het optionele half van 15 ('de volgende aflevering staat op NAS, overschakelen?') is met *kan* verleend en bewust niet gebouwd — er bestaat nergens een i18n-sleutel voor | covered |
| D12 | Verschillende editions/runtimes van aflevering | test/media/unified/unified_watch_state_test.dart (`D12: the gate is kind-agnostic — an extended-cut episode is exactly as incompatible as a film`) — G7's poort leest alleen `durationMs`, geen `MediaKind`; dezelfde garantie die G7 al voor films bewijst, nu expliciet met een episode-fixture | covered |
| D13 | Show watched count verschilt | test/services/unified_catalog/home_projection_service_test.dart (`D13: a show's watched-episode count stays with its representative source, never blended`) — hoofdstuk 13.1's "per source bewaren: … viewCount" geldt onveranderd voor een show's `viewedLeafCount`: de getoonde telling is één echte bron, nooit een som of gemiddelde | covered |
| D14 | Bronwissel op open seriesdetail | test/screens/media_detail_screen_test.dart (groep `D14: switching source on an open series detail`, drie tests) — gedreven door de echte `activateUnifiedMediaGroup`, zodat `onChangeSource` de productiesluiting `_changeSourceFromDetail` is en geen stub. Beide deuren van hoofdstuk 15 zijn gedekt: de altijd-zichtbare `[ Wijzigen ]`-chip en het foutpaneel. De route wordt **vervangen, niet gestapeld** (precies één pop en één push, geteld door een `NavigatorObserver`), de pagina leest daarna de gekozen bron, en de keuze wordt onthouden voor latere Play. Opnieuw dezelfde bron kiezen is de negatieve controle: geen pop, geen push | covered |
| D15 | Nieuwe episode verschijnt terwijl details openstaat | test/screens/media_detail_screen_test.dart (`refreshAfterPlayback reveals a server-side episode without a season jump or spinner`, `revalidation grows the request past an exact page boundary (200 -> 201)`, `app resume revalidates the visible episodes, with a cooldown against repeat probes`) — het open detailscherm neemt de nieuwe aflevering op zonder van seizoen te springen, zonder spinner en zonder de tweede probe die een resume anders uitlokt | covered |

## E. Paginationcases

| # | Case | Test | Status |
|---|---|---|---|
| E1 | Bronnen met verschillende page sizes | test/services/unified_catalog_service_test.dart (`E1: a source that answers shorter than the requested pageSize exhausts on its own, mid-merge`) — de `page.items.length < pageSize`-tak was alleen impliciet meegelift in fixtures met kleine libraries, nooit expliciet bewezen naast een bron die wél een volle pagina geeft | covered |
| E2 | Eén bron veel groter dan de andere | test/services/unified_catalog_service_test.dart (`E2: one source far larger than the other does not starve or block it`) — een library van 1 item naast één van 500 | covered |
| E3 | Veel duplicates waardoor één fetchronde weinig groups oplevert | test/services/unified_catalog_service_test.dart (`paging target is a group count: it stops at groupsPerPage new groups, not a raw item count`) — vier ruwe items voor twee groups | covered |
| E4 | Duplicate verschijnt pas veel pagina's later | test/services/unified_catalog_service_test.dart (`a duplicate arriving many pages later merges into the existing group instead of creating a new one`) | covered |
| E5 | Eén bron is veel trager | test/services/unified_catalog_service_test.dart (groep `E5: a slow source does not block the fast ones (hoofdstuk 12.6)`, drie tests: het snelle antwoord verschijnt binnen `progressiveLoadingGrace` zonder op de vastzittende bron te wachten, de late bron merget in-place zodra hij landt, en een cursor die de gratieperiode overleeft wordt nooit dubbel bevraagd) — `_fillBuffers` wachtte eerst voluit op `Future.wait` per golf, wat een globaal gesorteerde merge nodig heeft; een `Future.any`-poging brak die garantie zelfs bij gelijksnelle bronnen, dus de oplossing is een tijdslimiet op de golf zelf, niet op het individuele verzoek | covered |
| E6 | Eén bron faalt na eerdere succesvolle pagina's | test/services/unified_catalog_service_test.dart (`A12: a library that fails after already contributing a page keeps what it gave, and is retried`) — dezelfde gebeurtenis als A12, alleen vanuit de pagineermotor bekeken in plaats van vanuit de servertopologie; anders dan A8 (fout vóór de eerste pagina) faalt deze bron ná een geslaagde pagina | covered |
| E7 | Total ontbreekt | test/services/unified_catalog_service_test.dart (groep `E8: totalCount is advisory, never sole exhaustion authority`) — `LibraryPage.totalCount` is non-nullable, dus een backend zonder een echt total valt al vóór deze laag terug op een schatting (`pleya_server_client/parts/browse.dart`'s `estimate ?? (offset + items.length)`); "ontbrekend" en "onjuist" bereiken de merge-engine als hetzelfde ding, en E8 bewijst al dat geen van beide de exhaustie beslist | covered |
| E8 | Total verandert tijdens paging | test/services/unified_catalog_service_test.dart (groep `E8: totalCount is advisory, never sole exhaustion authority`, zes tests: krimpende total, groeiende total, lege eindpagina, herhaalde identieke pagina, en de negatieve controle dat een gewone grote bibliotheek nog steeds alles aflevert) — exhaustion komt nu uit het concrete paginaprotocol (lege of korte pagina, of het no-progress-vangnet), nooit meer uit `offset >= totalCount` | covered |
| E9 | Sort key ontbreekt | test/services/unified_catalog/unified_catalog_query_test.dart (`release-date sort sinks a dateless item to the end regardless of direction`, `addedAt sort sinks a missing value to the end`, `recentlyWatched sort compares lastViewedAt, missing sinks to the end`) | covered |
| E10 | Sort key verschilt tussen duplicate sources | test/services/unified_catalog_service_test.dart (groep `E10: a group's sort position follows the aggregate rule, not pop order`, drie tests: addedAt-aflopend kiest de hoogste van de twee bronnen, recentlyWatched-aflopend idem, en een echte gelijkstand valt terug op de stabiele group-ID) — bleek al correct: zolang beide bronnen in dezelfde ronde gebufferd zijn kiest de k-way-merge-comparator zelf al de juiste positie, dit was een bewijsgat, geen gedragsgat | covered |
| E11 | Query verandert met requests in flight | test/services/unified_catalog_service_test.dart (`a stale in-flight fetch from before a query change never lands in the new state`) | covered |
| E12 | Profiel wisselt met requests in flight | test/services/unified_catalog_service_test.dart (groep `E12: cancelInFlight (hoofdstuk 22, profile switch)`, drie tests) en test/providers/unified_catalog_provider_test.dart (groep `E12: dispose cancels a request still in flight`, twee tests) — `UnifiedCatalogProvider.dispose()` riep voorheen nooit iets aan op de onderliggende service, dus een lopend verzoek voor het verlaten profiel bleef gewoon doorlopen; `UnifiedCatalogService.cancelInFlight()` is nu de nette stopzet die hoofdstuk 22's "annuleert requests" waarmaakt | covered |
| E13 | Filter verwijdert de gefocuste group | test/screens/tv/tv_unified_catalog_screen_focus_test.dart (`E13: choosing a sort returns focus to the Sort action, never to a grid card`) — structureel onbereikbaar zoals beschreven vanaf een filter-/sortactie zelf: `_updatePreferences` wordt alleen aangeroepen vanuit een headeractie of de "Wis filters"-lege-staatknop, nooit vanaf een gridkaart, dus focus staat nooit op een group die die specifieke mutatie kan wegvegen. Bewezen is de garantie die hoofdstuk 7.6 wél geeft: de actie die het paneel opende krijgt de focus terug, over het echte scherm, niet de losse header+grid-compositie die de goldens gebruiken. De letterlijke case — een gefocust item verdwijnt terwijl de focus erop staat — is wél bereikbaar (een server die offline gaat, een item dat van de server verdwijnt) en dat scenario staat apart bewezen op het rasterniveau zelf: test/widgets/tv/tv_unified_media_grid_test.dart (groep `I18: a focused card that disappears (hoofdstuk 7.6)`, `focus moves to the next surviving neighbour, not nowhere`, `focus moves to the nearest remaining neighbour when the forward side is also gone`, `nothing survives the change: focus goes back up to the controls, not into the void`) | covered |
| E14 | Late merge zou zichtbare sortpositie wijzigen | test/services/unified_catalog_service_test.dart (`E14: a duplicate arriving on a later page never moves its group past ones already placed ahead of it`) — een duplicate met een addedAt dat, herwogen, de kaart naar de voorkant zou sturen, komt pas op een derde pagina binnen en verplaatst niets; E10 bewijst het spiegelgeval (beide bronnen in dezelfde ronde) waar de positie wél de juiste blend toont, omdat er dan nog niets vastligt | covered |
| E15 | Bron geeft dezelfde source twee keer terug | test/services/unified_grouping_service_test.dart (`E15: the same source returned twice inside one page is one membership`, `E15: a page replayed after a retry adds nothing`, `a duplicate sourceKey never trips C19 into refusing a genuine weak merge`), met twee negatieve controles die bewijzen dat het concrete-source-dedup is en geen media-identity-dedup | covered |

## F. Source-pickercases

`ACT` = test/services/unified_catalog/unified_activation_coordinator_test.dart.
`RES` = test/services/unified_catalog/source_resolver_test.dart.
`PREF` = test/services/unified_catalog/source_preference_store_test.dart.
`PICK` = test/widgets/tv/tv_media_source_picker_test.dart.
`ROW` = test/widgets/tv/tv_source_row_descriptor_test.dart.
`GOLD` = test/goldens/tv_media_source_picker_golden_test.dart.

| # | Case | Test | Status |
|---|---|---|---|
| F1 | Eén source | ACT (`F1: exactly one online source skips the picker and routes directly`) — de picker gaat niet open, dus er is geen visueel deel meer | covered |
| F2 | Twee sources | ACT (`F2: two online sources open the picker`) plus PICK (`the row the coordinator named is the one that starts focused`, `Select activates exactly the focused source, not its neighbour`) en GOLD (`two online sources`) | covered |
| F3 | Tien sources met scroll | PICK (`F10: a late source lands at the bottom without moving the focus`) bewijst het groeien; de lijst scrollt binnen het paneel en vervaagt aan de rand die nog inhoud heeft (GOLD `mixed states`) | covered |
| F4 | Alle sources online | ACT (`F4/F9: the route context carries coverage and every source key`, plus de ranking-groep) en PICK (`complete coverage says nothing about unchecked servers`) | covered |
| F5 | Eén source offline | ACT (`F5/14.6: one online source plus an offline one still skips the picker`) — de picker gaat niet open | covered |
| F6 | Alle sources offline | ACT (`F6: every source offline reports allOffline, keeping all rows`, `F6: with nothing online there is still a focused row`) en PICK (`with nothing reachable the two panel actions appear and take the focus`, beide headline-tests) plus GOLD (`nothing reachable`) | covered |
| F7 | Auth-error | ACT (`F7: an auth error outranks offline…`), ROW (`an unusable row says why, and outranks every other marking`) en PICK (`F7: an auth error says something else than an offline server`) | covered |
| F8 | Coverage nog bezig | RES (`cancellation (hoofdstuk 14.5)`, vier tests) en PICK (`F8: the resolving line shows without blocking the list`) plus GOLD (`still resolving`) | covered |
| F9 | Coverage incompleet | ACT (`F4/F9: …`), RES (`a cancelled run reports the servers it never reached as unchecked`) en PICK (`F9: partial coverage is stated in the header`) | covered |
| F10 | Nieuwe source arriveert terwijl modal open is | ACT (`F10: sources arriving while the modal is open`, vier tests) en PICK (`F10: a late source lands at the bottom without moving the focus`) | covered |
| F11 | Source verdwijnt terwijl modal open is | ACT (`focus after a source stops being usable`, vijf tests) en PICK (`F11: the focused source going offline moves focus to the nearest usable row`) | covered |
| F12 | Duplicaatservernamen | ACT (`F12: duplicate server names fall through to server id, then item id`) en PICK (`F12: two servers with one name stay tellable apart by their library`) | covered |
| F13 | Geen quality metadata | ROW (`F13: a source with no media versions has no quality line at all`, plus de hele `quality line`-groep) en PICK (`F13: a source with no quality metadata simply has one line fewer`) | covered |
| F14 | Afwijkende editions | ROW (`context line`-groep: edition, library en backend worden alleen getoond wanneer ze bestaan) en GOLD (`two online sources`, met Director's Cut) | covered |
| F15 | Afwijkende progress | ACT (`F15: with no remembered source, the most recent progress takes focus`) en ROW (`progress`-groep, vier tests) | covered |
| F16 | Last-used source offline | ACT (`F16: an offline remembered source falls back…`), PREF en PICK (`F16: an offline remembered source is not focused and is not marked`) | covered |
| F17 | Cancel | test/diagnostics/select_trace_test.dart (`a picker cancel that opened nothing is ordinary, not an anomaly`) en PICK (`Menu closes the picker, activates nothing, and restores the exact CTA`) | covered |
| F18 | Playerstart faalt | ACT (`F18: playback failure offers an alternative but never takes it`, vijf tests) en PICK (`offers a choice and a way out, and takes neither by itself`) plus GOLD (`playback failure alternative`) | covered |
| F19 | Detailroute faalt | test/screens/media_detail_screen_test.dart (groep `F19/A14: detail load failure offers an alternative source`, vijf tests: expliciete 'Andere bron kiezen' bij alternatieven, sluiten laat de pagina bruikbaar, geen paneel zonder alternatief, geen paneel bij één bron, geen paneel bij een geslaagde load) — hoofdstuk 21.7 is nu authority (zie de instructie boven dit bestand). `_loadFullMetadata`'s catch-tak viel al stil terug op de meegegeven metadata (`bestaande foutafhandeling`, ongewijzigd); nieuw is `_offerAlternativeSourceAfterDetailLoadFailure`, die alleen vuurt wanneer `widget.onChangeSource` niet-null is — dezelfde poort als hoofdstuk 15's altijd-zichtbare bronregel — en `TvPlaybackFailureAlternative` hergebruikt (nu met een parametriseerbare titel) in plaats van een tweede paneel te bouwen. De contractflow is in twee lagen bewezen, niet in één: **(A)** detailfout → aanbod → callback, de vijf tests hierboven, en **(B)** picker → alternatieve bron → detailroute, test/screens/media_detail_screen_test.dart (`F19/A14: the failure panel is the other door to the same switch`, en dezelfde schakel via de `[ Wijzigen ]`-chip in groep `D14`). Laag B draait door de echte `activateUnifiedMediaGroup`, zodat de productiesluiting `_changeSourceFromDetail` wordt uitgevoerd in plaats van een teststub: de route wordt vervangen (één pop, één push), de pagina leest daarna de gekozen bron en het foutpaneel staat niet meer achter de goede pagina | covered |
| F20 | Terugkeer behoudt focus | PICK (`Menu closes the picker, activates nothing, and restores the exact CTA`) — de overlay geeft de focus terug aan exact de node die hem had | covered |
| F21 | Voorkeursserver kiest zelf (14.8a) | ACT (`preferred server (profile default)` elf tests + `the preferred server is global to the profile, not per title` acht tests, incl. de A-t/m-G-tabel uit 14.8a), test/services/unified_catalog/preferred_server_store_test.dart (elf tests, incl. de sleutelvorm) en PICK (`the preferred server can be set from here`, `explicit source selection bypasses the global preference`) | covered |

## G. Watch-statecases

| # | Case | Test | Status |
|---|---|---|---|
| G1 | Eén actieve progress | test/media/unified/unified_watch_state_test.dart (`G1: one source with active progress speaks for the group`) | covered |
| G2 | Twee verschillende progressposities | test/media/unified/unified_watch_state_test.dart (`G2: two different positions are decided by the newer reliable timestamp`) | covered |
| G3 | Oudere bron heeft hogere progress | test/media/unified/unified_watch_state_test.dart (`G3: an older source with higher progress does not outrank a newer one`) — 13.2's openingszin, expliciet getest | covered |
| G4 | Nieuwere bron is watched | test/media/unified/unified_watch_state_test.dart (`G4: a demonstrably newer watched state beats older active progress` en het spiegelgeval `G4: a stale watched bit does not bury a position the viewer is sitting at`) — tier 2 sluit dit af vóór tier 3 erbij komt | covered |
| G5 | Clock skew | test/media/unified/unified_watch_state_test.dart (`G5: a difference inside the reliability margin does not order the sources`, `G5: one second past the margin the newer source is believed`, `G5: the margin is the one WatchStateStore already uses`) — de marge is `watchStateReliabilityMargin`, dezelfde 30 seconden als `WatchStateStore.serverWinsMargin` | covered |
| G6 | Geen timestamps | test/media/unified/unified_watch_state_test.dart (`G6: with no timestamps anywhere the progress tiers decide`, `G6: a source with no timestamp loses to one that has any`, `G6: no timestamps and no progress is still deterministic`) | covered |
| G7 | Verschillende runtimes | test/media/unified/unified_watch_state_test.dart (groep `G7: runtime compatibility gate`, zeven tests: PAL-tolerantie, extended cut, de hogere ruwe offset die niet wint, actieve progress die niet geprojecteerd wordt, recency die wél blijft gelden, onbekende runtime, en één incompatibel paar dat de hele groep brongebonden maakt) | covered |
| G8 | Scrobble race | test/media/unified/unified_watch_state_test.dart (`G8: a scrobble race lands inside the margin and is not resolved by the clock`) — twee servers die dezelfde kijkbeurt seconden na elkaar noteren vallen binnen de marge, dus de klok beslist niet en de kaart flikkert niet tussen twee kopieën | covered |
| G9 | Playback return met null route result | test/utils/media_navigation_helper_test.dart (`onPlaybackReturned fires when the player pops null`, `onRefresh alone does not fire when the player pops null`) — `handlePlaybackReturn` is puur en heeft geen visueel deel | covered |
| G10 | Remove Continue gedeeltelijk mislukt | test/screens/tv/tv_unified_context_actions_test.dart (groep `G10: the intended target count`, vijf tests: de onbereikbare membership blijft in de noemer, `unknown` telt mee, auth-error nooit, geen andere actie stelt uit, alles online stelt niets uit) plus `a removal with nothing online is deferred, not refused`; test/widgets/tv/tv_unified_context_menu_reachability_test.dart (groep `the outcome message tells the truth about what landed`, zes tests, inclusief de negatieve controle dat de retry-belofte wegvalt zonder wachtrij-entry); test/providers/discover_provider_test.dart (`G10: a removed row does not come back while the server still lists it`, `G10: the suppression lifts once the server stops listing the row`) | covered |
| G11 | Offline suppressie wordt later gereplayed | test/services/offline_watch_sync_service_test.dart (groep `G11: remove from Continue Watching replays on reconnect`, acht tests: de wachtrij-entry, de replay die hem opruimt, idempotentie, de server die nog plat ligt, de backend zonder endpoint, de her-aankondiging na herstart, geen her-aankondiging na een geslaagde replay, en de id-round-trip); test/exceptions/media_server_write_retry_test.dart (zeven tests over wat wél en niet in de wachtrij mag) | covered |
| G12 | Mark watched op één source | test/screens/tv/tv_unified_context_actions_test.dart (`a single usable source is written to without a question (14.6)`, nu geparametriseerd over élke actie, plus `an unreachable membership is held rather than dropped` en `an offline source is written later, not written off`) — herschreven onder [DEC-071](../DECISIONS.md#dec-071) en opnieuw onder [DEC-075](../DECISIONS.md#dec-075): één bereikbare bron is nog steeds geen vraag, maar dat is nu een lijst van lengte één in plaats van een uitzondering, en er is geen actie meer waarvoor het níét geldt. De pickertest die hier stond is met de picker zelf verwijderd | covered |
| G13 | Mark watched op alle sources gedeeltelijk mislukt | test/screens/tv/tv_unified_context_actions_test.dart (`marking watched never asks, it takes every membership (DEC-071)`, `an offline source is written later, not written off`, `a logical action still skips an unreachable membership` voor de partial-semantiek, en `no action asks which source a write lands on (DEC-071, DEC-075)` dat de eigenschap nu over álle acties aftelt); de melding zelf komt uit `_applyToSources` in lib/screens/tv/tv_unified_context_menu.dart, die per bron telt en `doneOnSome` toont in plaats van te rollbacken, met test/services/unified_action_outcome_test.dart als bewijs voor de zin zelf. Onder DEC-071 wordt er niet meer gevraagd: een onbereikbare bron gaat de kijkstatuswachtrij in en wordt bij reconnect alsnog geschreven. Onder [DEC-075](../DECISIONS.md#dec-075) geldt dat ook voor rate, met dit verschil dat rate geen wachtrij heeft: `an unreachable membership stays in a rating's denominator` legt vast dat zo'n membership in `unreachableSources` belandt, meetelt in de noemer en geen retry belooft | covered |
| G14 | Episodeprogress op verkeerde serie mag niet mergen | test/services/unified_catalog/home_projection_service_test.dart (`G14: the same season/episode of two different series never share a card`, `G14: two series with no external ids at all still never merge on ordinals`, `G14: one series' progress stays on its own card when the other is further along`) — dezelfde S02E04 op twee series blijft twee kaarten, met en zonder externe ids, en 13.2 kiest alleen uit de eigen bronnen van een groep | covered |

**Contextmenu op een hub-rij liet zijn eigen kaart stil staan.** Gevonden bij de
commentaar-versus-code-audit van `tv_content_feed.dart` (fase 9, taak "misleidende comments"), niet
bij een vooraf gevlagde registerrij — het commentaar zelf was het eerste bewijs: `_openContextMenu`
gaf `onChanged: null` mee met de motivering "de projectie rekent zelf al opnieuw vanaf de
watch-state-events die de writes al zenden, dus een rij hoeft niet twee keer verteld te worden". Dat
klopt voor Verder kijken — `DiscoverProvider._onWatchStateChanged` draait `refreshContinueWatching()`
op elk event — maar dat commentaar staat op de menu-opening voor **elke** rij, en dezelfde
`refreshContinueWatching()` zegt in zijn eigen doc-comment expliciet "nooit opnieuw hubs ophalen".
Markeer bekeken/onbekeken vanaf een Top Picks- of Recently Released-kaart raakte dus precies het gat:
`_hubs` bleef de al aanwezige lijst, `TvHomeProjectionProvider`'s eigen change-guard
(`listEquals`, element-identiteit) vuurde niet, en de kaart die de gebruiker net aansprak — zijn
`watchState.isWatched` komt rechtstreeks uit de geprojecteerde groep, geen live patch-laag — bleef de
oude staat tonen tot de volgende volledige `load()`. Het commentaar was niet zomaar onnauwkeurig; het
beschreef een garantie die voor de meeste rijen op dit scherm niet bestond.

De reparatie geeft `onChanged` een echte callback: `_refreshGroupSources` roept
`DiscoverProvider.updateItem` voor elke bron in de groep, dezelfde incrementele refresh die I19 al aan
een playbackreturn geeft. test/screens/tv/tv_content_feed_test.dart (groep "hoofdstuk 23's menu
reageert op elke rij, niet alleen Verder kijken", `marking a hub-row title watched updates that exact
card`) drijft het echte pad — lange Select opent het menu, "Markeer als bekeken" kiezen schrijft naar
de fake client — en bewijst zowel de write (`markWatchedCalls`) als de refetch (`fetchItemCalls`) als
het zichtbare effect (`watchState.isWatched` na de herprojectie); zonder de fix faalt precies de
refetch-assertie, negatief gecontroleerd door de fix tijdelijk terug te draaien. Het tweede
commentaar dat de audit meenam — `tv_hero_billboard_card.dart`'s `textOpacity`-doc, die "de carousel"
crediteerde voor een waarde die feitelijk `TvContentFeed` bepaalt en de carousel alleen doorgeeft —
was code die al klopte; alleen het commentaar is gecorrigeerd, zonder test.

**WP4 — verwijderen uit Verder kijken onthoudt nu wat het niet bereikte.** Gebouwd in fase 9. Twee
dingen waren stuk, en het tweede was het ergste.

De **noemer** telde alleen de bereikbare bronnen. `resolveUnifiedActionTarget` gaf voor een logische
actie `ApplyActionToAllSources(usable)`, dus een titel op drie servers waarvan er één plat lag
meldde "klaar op alle 2". Hoofdstuk 13.4 punt 5 schrijft letterlijk "Verwijderd op 2 van 3 bronnen"
voor, en die 3 telt een membership mee dat nooit online was. `ApplyActionToAllSources` draagt daarom
nu ook `deferredSources`, met `intendedTargetCount` als de eerlijke noemer.

En de melding beloofde een herkansing die niet bestond. `doneOnSome` eindigt op "The rest will be
retried when they are back online", terwijl er nergens een wachtrij-entry werd aangemaakt. Dat is de
duurste soort onwaarheid in dit register: de gebruiker doet niets meer, want het is toegezegd.

De reparatie is één actie breed, met opzet. `UnifiedGroupAction.queuesUnreachableMemberships` is
alleen waar voor verwijder-uit-Verder-kijken, omdat 13.4 als enige actiecontract *beide* helften van
een uitstel vastlegde — punt 3 bewaart, punt 4 speelt af. De kijklijstacties blijven offline helemaal
weg (DEC-020).

**Bijgewerkt door [DEC-071](../DECISIONS.md#dec-071):** markeer bekeken/onbekeken hoort er nu ook bij.
Toen "bekeken is bekeken" de regel werd, werd een schrijfactie die stopt bij de servers die toevallig
aanstonden geen halve nakoming maar een stille schending, en de kijkstatuswachtrij droeg `watched`- en
`unwatched`-rijen al met een replay die G11 aantoont. `doneOnSomeNoRetry` blijft over voor wat écht
mislukte op een server die antwoordde en weigerde.

De wachtrij-entry **is** de lokale suppressie. Geen tweede mechanisme ernaast: de rij overleeft een
herstart, staat op dezelfde `serverId:itemId` als de on-deck-lijst, en verdwijnt precies wanneer de
write landt. `OfflineActionType.removedFromContinueWatching` vroeg geen driftmigratie —
`actionType` is een kale tekstkolom zonder constraint — maar wél een replaytak in `_syncAction`, en
dat is het onderdeel dat je stil kwijtraakt: een rij waarvan niemand het type afhandelt wordt netjes
opgeruimd zonder ooit iets te doen.

Twee dingen worden **niet** in de wachtrij gezet, en dat is de kern van punt 7 van het
lifecycle-contract: een `authError`-bron (opnieuw verbinden logt niemand in) en een backend die het
endpoint helemaal niet heeft — Jellyfins `removeFromContinueWatching` gooit `UnsupportedError`.
`isRetryableServerWriteFailure` is die scheidslijn, met de veilige richting expliciet gekozen: bij
twijfel wél in de wachtrij, want een kansloze rij loopt tegen `maxSyncAttempts` aan, terwijl een
weggegooide rij een write is waarvan de gebruiker te horen kreeg dat hij onthouden was.

Ten slotte: `DiscoverProvider` *onderdrukte* een verwijderde rij niet, hij haalde hem alleen weg.
Zolang de replay nog niet geland is blijft de server de titel noemen, dus de kaart kwam bij de
eerstvolgende verversing terug — hoofdstuk 13.4 punt 6. Hij gaat nu in dezelfde zelfopruimende
`_suppressedOnDeckKeys` als een uitgekeken film, en `_reannouncePendingContinueWatchingRemovals`
herstelt die verzameling na een herstart uit de wachtrij.

## H. Herocases

| # | Case | Test | Status |
|---|---|---|---|
| H1 | Clearlogo aanwezig | `tv_hero_billboard_card.dart` `_titleBlock` tekent de clearlogo in dezelfde gereserveerde band als de titeltypografie, zodat de metaregel eronder niet verschuift; de band is een constante van [TvHomeLayout.heroLogoMaxHeight] | covered |
| H2 | Geen clearlogo | idem — de titelfallback vult exact dezelfde band, `test/goldens/tv_home_production_golden_test.dart` rendert die tak (de fixtures dragen geen clearlogo) | covered |
| H3 | Landscape-art | test/widgets/tv_hero_artwork_test.dart (`a real backdrop is drawn sharp`, `the backdrop wins over the poster…`) | covered |
| H4 | Square-art | test/widgets/tv_hero_artwork_test.dart (`square background art is sharp on a wide card only when no backdrop exists`) — op een 2.465:1-kaart wint de backdrop, square is de fallback (DEC-057's ratio-invariant) | covered |
| H5 | Alleen poster | test/widgets/tv_hero_artwork_test.dart (`poster-only art becomes a blurred fill, never a sharp crop`) | covered |
| H6 | Geen artwork | test/widgets/tv_hero_artwork_test.dart (`a title with no artwork at all resolves to nothing, not to a stand-in`) plus `_EmptyHeroArt`'s themagradiënt | covered |
| H7 | Lange titel | test/goldens/tv_home_production_golden_test.dart (`Home with long titles and prose`) — titel, metaregel en synopsis kappen af binnen hun gereserveerde hoogtes; de knoppenrij staat op exact dezelfde plaats als in `Home at rest` | covered |
| H8 | Geen synopsis | `tv_hero_billboard_card.dart` reserveert de synopsisband ook zonder tekst, dus een titel zonder samenvatting verplaatst de CTA-rij niet | covered |
| H9 | Spoilers verbergen | test/widgets/tv_hero_billboard_carousel_test.dart (`H9: hideSpoilers suppresses the synopsis of an unwatched-episode fallback billboard`, `H9: the same episode shows its synopsis when hideSpoilers is off`) — de enige vorm waar `hideSpoilers` op bijt, per de eigen doc van `TvHeroBillboardCard` | covered |
| H10 | Watched titel | test/widgets/tv_hero_billboard_carousel_test.dart (`H10: a watched title still reads "Play", not "Resume", and carries no progress`) — `resumeFractionFor` geeft null zodra er geen actieve progress is, dus een afgeronde titel herstart in plaats van te hervatten | covered |
| H11 | In-progress titel | test/widgets/tv_hero_billboard_carousel_test.dart (`H11: an in-progress title reads "Resume", matching its own offset/duration fraction`) | covered |
| H12 | Meerdere bronnen | test/screens/discover_screen_tv_hero_test.dart (`a mergeable duplicate becomes one slide carrying both sources`, `two concrete copies of one recent film are one hero slide, not two`) — één slide per logische titel, met beide bronnen erin, gereden door het echte `DiscoverScreen`; de tweede test legt ook vast dat een titel waarvan de identiteit niet te bewijzen is één bron houdt in plaats van er stilzwijgend een bij te verzinnen | covered |
| H13 | Source valt weg | test/screens/tv/tv_content_feed_test.dart (`a row whose sources did not all answer says so, and still shows what it has`) — de projectie markeert partial, de rij toont wat er is; de hero verliest een slide pas als de logische groep zelf verdwijnt, en volgt dan zijn groep en niet zijn index (test/widgets/tv_hero_billboard_carousel_test.dart, `the carousel follows its group, not its index, when the list shortens`) | covered |
| H14 | Hero-data komt laat | test/screens/tv/tv_content_feed_test.dart — `TvContentFeed` onderscheidt "nog niet geprojecteerd" van "authoritatief leeg" via `hasProjectedHero` + `projectedLatestMovies`, en reserveert in het eerste geval de billboardruimte (hoofdstuk 9.7) in plaats van een fallback te tonen die een tel later omklapt | covered |
| H15 | Geen hero-kandidaten | test/screens/discover_screen_tv_hero_test.dart (`zero recent films keeps the existing hub fallback billboard`) en test/providers/tv_home_projection_provider_test.dart (`a hero with no eligible recent film is empty rather than padded from hubs`) — een lege filmpool valt terug op het bestaande on-deck/hub-billboard en wordt niet met hubs opgevuld (DEC-067) | covered |
| H16 | Alleen series beschikbaar | test/screens/tv/tv_content_feed_test.dart (`no recent films falls back to the first Continue Watching title`) — een filmloze bibliotheek valt terug op het bestaande on-deck/hub-billboard, met één slide en zonder rotatie | covered |
| H17 | Auto-rotation tijdens focus | test/widgets/tv_hero_billboard_carousel_test.dart (`an interaction pauses the rotation for the inactivity window`) en test/screens/tv/tv_content_feed_test.dart (`a focused content row holds the rotation and fades the hero text`) — zie [DEC-070](../DECISIONS.md#dec-070) punt 1 voor waarom 9.6's lijst niet letterlijk kan gelden | covered |
| H18 | App gaat background | test/widgets/tv_hero_billboard_carousel_test.dart (`autoplayEnabled false stops the rotation, and restoring it resumes deterministically`) en test/screens/tv/tv_content_feed_test.dart (`leaving the destination stops the rotation, and returning resumes it`) — `TvContentFeed` observeert de lifecycle en vouwt hem samen met de overige pauzeredenen in één vlag | covered |
| H19 | Reduce Motion | test/widgets/tv_hero_billboard_carousel_test.dart (`reduced motion stops the rotation but not the remote`) — geen automatische wissel, handmatige navigatie blijft werken; hardwarebevestiging blijft J9 | covered |
| H20 | Light theme | `tv_hero_billboard_card.dart` las `TvHomeLayout.heroScrimAlpha`/`inkSecondary`/`inkTertiary` rechtstreeks — één sterkte voor beide thema's, terwijl `MonoTokens.artworkScrimAlpha`/`onArtworkInk` precies hiervoor bestaan (het scrim is op light een wit vlak dat artwork juist *ophelderd* in plaats van dimt). Fix laat de wash en inkt harder werken op light, `dark:` blijft byte-identiek aan de oude waarde. test/goldens/tv_hero_billboard_theme_golden_test.dart (`the reading scrim and ink wash harder on a light surface than on dark`, `the same scene on the dark palette keeps its existing, unboosted strength`) bewijst het mechanisme zowel via de golden als via een directe assertie op `artworkScrimAlpha`/`onArtworkInk`; alle 71 bestaande goldens (waaronder de hero-eigen) blijven pixel-exact ongewijzigd op het dark thema | covered |
| H21 | Artworkrequest faalt | `tv_hero_artwork.dart` geeft `_EmptyHeroArt` als zowel `placeholder` als `errorWidget` mee, dus een mislukte request valt terug op de themagradiënt in plaats van op een lege of kapotte laag | covered |

## I. Navigatiecases

| # | Case | Test | Status |
|---|---|---|---|
| I1 | Cold-start focus | test/screens/tv/tv_my_pleya_screen_test.dart (`Down from the top navigation lands on the profile action`) en test/screens/tv/tv_root_shell_test.dart (`the scope every content screen already talks to reaches the bar`) — de shell verplaatst focus uitsluitend expliciet, er staat geen `autofocus` op de contentscope | covered |
| I2 | Topnav naar hero | test/screens/discover_screen_test.dart (`TV tab focus returns to the Home feed instead of the reload action`) — de shell vraagt `focusActiveTabIfReady` en landt op `tvHeroPlay` (hoofdstuk 7.1/7.3) | covered |
| I3 | Hero naar row | test/screens/discover_screen_test.dart (`Down from the hero Play pill reaches the first browse row`) en test/widgets/tv_hero_billboard_carousel_test.dart (`Down leaves for the content feed and Up for the top navigation`) | covered |
| I4 | First row terug naar hero | test/screens/tv/tv_content_feed_test.dart (`walking a content row leaves the featured slide exactly where it was`, `the hero keeps its slide across a row focus round trip`) — UP keert terug naar de *laatst gebruikte* CTA, en haalt de carousel eerst terug in beeld wanneer de feed hem weggescrold had | covered |
| I5 | Root Back naar topnav | test/screens/tv/tv_back_chain_test.dart (`step 4: root content hands the focus to the top navigation`) | covered |
| I6 | Topnav Back naar systeem | test/screens/tv/tv_back_chain_test.dart (`step 5: the top navigation at the root defers to the system contract`, `Menu reaches the system only from the root destination with the bar focused`) — het bestaande `shouldPassTvosMenuToSystem`-predicaat, ongewijzigd van vorm; wat de engine daarna met de press doet is hardware (DEC-019) | covered |
| I7 | Source picker Back | test/widgets/tv/tv_media_source_picker_test.dart (`Menu closes the picker, activates nothing, and restores the exact CTA`) | covered |
| I8 | Nested Mijn Pleya Back | test/screens/tv/tv_back_chain_test.dart (`step 2 comes first`, `step 2 beats the focus test, wherever the remote happens to be`) en test/navigation/tv/tv_navigation_coordinator_test.dart (de nested-routegroep) en test/screens/tv/tv_root_shell_test.dart (`popping brings the destination back`) | covered |
| I9 | Profile picker Back | test/screens/profile/profile_switch_screen_test.dart (groep `I9: Back in the profile picker`, twee tests: de beheerspicker verlaat op Back, de startpoort niet) en test/screens/tv/tv_back_chain_test.dart (`I9: the profile picker keeps Menu for the app`, `I9: the TV shell never opens the profile picker without the Menu bracket`) — **gedragsgat gevonden en gedicht** aan de tvOS-kant: `AccountUiActions.openProfiles` pusht op de *root*-navigator, die dit scherm niet observeert, dus niets herberekende de Menu-passthrough en de eerste Menu-druk verliet de app in plaats van de picker te sluiten. Beide TV-aanroeppunten gaan nu door `_openProfilesFromShell`, dat het bezoek omsluit zoals de startpoort al deed; een broncontrole bewaakt het aanroeppunt | covered |
| I10 | Native keyboard Back | test/services/apple_tv_native_text_entry_key_gate_test.dart (`a back key that reaches Dart is consumed without a platform call`, `real key events are blocked while the native keyboard owns the remote`, `the session ends after a submit`) — een Back die de gate bereikt betekent dat de native hook faalde, en wordt geconsumeerd in plaats van doorgegeven aan de backketen; de native helft (UIKit sluit zijn eigen toetsenbord) is de simulatorregressie `scripts/tvos_sim.sh check-keyboard`, zie [DEC-019](../DECISIONS.md#dec-019) | covered |
| I11 | Live TV-item verschijnt | test/widgets/tv/tv_top_navigation_test.dart (`a Live TV slot appearing does not replace the focus node of an existing item`) en test/screens/tv/tv_root_shell_test.dart (`appears and disappears without disturbing its neighbours`) — het nieuwe item krijgt een eigen stabiele id, en de buren houden hun focusnode én hun volgorde | covered |
| I12 | Live TV-item verdwijnt | test/screens/tv/tv_root_shell_test.dart (`losing it while it is open moves the viewer to Home`) en test/navigation/tv/tv_live_tv_capability_test.dart (`a transient outage does not retire a remembered capability`) — een tijdelijke storing laat het item staan, alleen een sluitende meting haalt het weg (DEC-069) | covered |
| I13 | Actieve destination opnieuw selecteren | test/navigation/tv/tv_navigation_coordinator_test.dart (activate op de reeds actieve bestemming geeft `false` en notificeert niet, dus geen rebuild en geen refetch — hoofdstuk 7.2) | covered |
| I14 | Tab wisselen met overlay open | test/screens/tv/tv_root_shell_test.dart (groep `I14: switching tab while an overlay is open`, drie tests) — een open sheet bezit de afstandsbediening: Select en de pijlen gaan naar de sheet, de bestemming eronder verandert niet, en Back sluit de sheet zonder óók de bestemming te verlaten. Vastgelegd is het contract dat werkelijk geldt (de focus blijft in de sheet-scope), niet de focus-trap die `_fallbackKeyHandler`'s commentaar belooft: een druk die ná een programmatische focusverplaatsing naar de balk komt activeert die balk wél. Niet bereikbaar in productie — niets verplaatst de focus uit een open sheet — dus genoteerd in plaats van gedrag veranderd. Niet-remote bestemmingswissels (companion remote, deeplink, wegvallende Live TV) laten de sheet staan; geen hoofdstuk of DEC zegt wat daar zou moeten gebeuren | covered |
| I15 | Select KeyUp na focusverplaatsing | test/focus/focusable_wrapper_select_test.dart (`key-up landing on a wrapper that never saw the key-down fires nothing`); test/focus/dpad_navigator_suppressor_test.dart (`armed suppressor eats the in-flight select key-up and clears`) | covered |
| I16 | Trackpad swipe versus D-pad | test/services/apple_tv_remote_touch_service_test.dart (`synthetic swipe followed by matching native arrow down and up moves once`, `synthetic swipe also suppresses a native arrow on the other axis`, `native directional press claims the gesture and mutes the accumulator`, `native-only directional press still passes through`, `native arrow after the grace expires passes through again`) — één gebaar wordt nooit twee stappen, welk pad hem ook eerst claimt, en een kale D-pad-druk blijft ongemoeid | covered |
| I17 | Android TV back | zie "Buiten fase 9" — geen back-button-interceptie onder `lib/screens/tv/`/`lib/navigation/`, TV-schermen routeren terug via het eigen remote-focussysteem; of Android's hardware-terugknop het juiste doet op die stack is alleen op een echt toestel vast te stellen | klasse A |
| I18 | Focused item verdwijnt | test/navigation/tv/tv_navigation_coordinator_test.dart (topnav-helft, ongewijzigd) plus nu ook het griditem-geval: test/widgets/tv/tv_unified_media_grid_test.dart (groep `I18: a focused card that disappears (hoofdstuk 7.6)`, drie tests: focus verhuist naar de eerstvolgende overlevende buur vóórwaarts, naar de dichtstbijzijnde buur wanneer vóórwaarts niets overleeft, en terug naar de headercontrols wanneer er niets overleeft) — `_reconcileNodes`/`_nearestSurvivor` bestonden al, alleen de test ontbrak | covered |
| I19 | Return uit player | test/media/unified/unified_media_group_test.dart (`withUpdatedSourceItem`, vijf tests) en test/services/unified_catalog_service_test.dart (groep `I19: applyUpdatedSourceItem`, vier tests) voor de kaartherberekening; test/providers/unified_catalog_provider_test.dart (groep `I19: refreshItem re-reads one source in place`, vijf tests) voor de reactieve laag — de complete catalogus krijgt `onPlaybackReturned` dat één item herleest en in zijn groep terugzet, zonder opnieuw te pagen. Home, beide landings en TV-Search delen `TvDiscoveryActivationMixin.activateDiscoveryGroup`, en die roept nu `DiscoverProvider.updateItem` — het bestaande post-edit-verversingspad, geen tweede eventbus — zodat `TvHomeProjectionProvider` en `TvDiscoveryLandingProvider` op dezelfde `DiscoverProvider`-notificatie herprojecteren. Focus verplaatst niet: geen van beide paden pusht of routeert, dus er is niets terug te herstellen | covered |
| I20 | Return uit settings | test/screens/tv/tv_destination_restoration_test.dart (groep `I20: coming back from Settings`, twee tests) — Instellingen is op TV geen bestemming maar een geneste route op Mijn Pleya, dus de balk beweegt niet en er valt niets te herstellen behalve de focus: poppen zet de afstandsbediening terug op de tegel waar de sectie vanaf openging, via `restoreFocusKey`. De tweede test pint de productieroute `tvMyPleyaNestedRoute(settings)` vast zodat de shell-helft en de routehelft niet uit elkaar kunnen lopen. Een verversing bij terugkeer is niet nodig en bestaat bewust niet: elke instelling die een TV-oppervlak ziet komt binnen via een `ChangeNotifier` waar dat oppervlak al naar luistert — hetzelfde argument dat I19 maakt. Settings-subpagina's zijn gewone pushes op de profielnavigator, back-keten stap 3 | covered |
| I21 | Filters bereiken vanaf diep in het grid | gedrag ligt vast in hoofdstuk 7.4 en 10.6, maar de snelkoppeling is niet gebouwd — zie de noot onder deze tabel | open |
| I22 | Terugkeren op dezelfde kaart binnen een bestemming | test/screens/tv/tv_destination_restoration_test.dart (`All movies`/`All series comes back to the card and the scroll region it was left on`, `the Films landing comes back to the rail tile it was left on`) — binnenkomen vanaf de balk landt op de primaire focus van het scherm (hoofdstuk 7.1/7.4), en DOWN daaruit landt op de kaart waar de kijker stond; de catalogus leest die kaart uit `TvNavigationCoordinator.contentFocusFor`, de landing uit zijn eigen rails | covered |
| I23 | Bestemming wisselen met een geneste route open | test/screens/tv/tv_root_shell_test.dart (`belongs to its own destination and does not follow the viewer elsewhere`) bewijst dat de route bij zijn eigen bestemming blijft; test/screens/tv/tv_destination_restoration_test.dart (`coming back does not restart the merge that is already loaded`, plus de twee restauratierijen hierboven) bewijst dat terugkeren de geladen pagina's, de scrollpositie en de gefocuste kaart houdt | covered |
| I24 | Vanuit content de balk bereiken, end-to-end | beide helften bewezen, de schakel ertussen niet; geclassificeerd als *integration-test coverage debt* en niet als productiedefect — zie de noot onder deze tabel | open (coverage debt) |

**I24 — de content→balk-keten is aan beide uiteinden bewezen en in het midden met de hand
geknoopt.** Toegevoegd op 31 augustus 2026, na fase 7.

De keten die een kijker gebruikt om vanuit een pagina bij de balk te komen loopt in drie schakels:

1. het scherm vraagt erom — `onNavigateUp`/`onNavigateLeft` → `MainScreenFocusScope.focusSidebar`
   (`tv_unified_catalog_screen.dart:503,517,529` en `:586`);
2. `MainScreen._focusSidebar` (`main_screen.dart:1419`) vertaalt dat op TV naar
   `SidebarFocusCoordinator.focusSidebar(focusActiveItem: …)` en focust de node van
   `TvNavigationCoordinator.focusedDestination`;
3. de balk krijgt de ring.

Schakel 1 is bewezen in `test/screens/tv/tv_unified_catalog_focus_test.dart` (`UP from every header
action reaches for the top navigation`, plus de twee LEFT-rijen), schakel 3 in
`test/screens/tv/tv_root_shell_test.dart` (`reaching the bar puts the ring on a destination in it`).
Schakel 2 wordt door geen enkele test uitgevoerd: niets in de suite monteert `MainScreen` — met
`grep -rln "MainScreen(" test/` is de uitkomst leeg — en de twee tests die eromheen staan stoppen
allebei op een stub (de ene op een `focusSidebar`-teller, de andere op een `onFocusNav` die het
lichaam van `_focusSidebar` nabouwt).

Het gevolg is scherp: een breuk in die zes regels productiecode zou groen door CI komen. Het staat
hier omdat het opschrijven eerlijker is dan een testcommentaar dat suggereert dat de keten sluit.
Repareren betekent `MainScreen` monteerbaar maken in een test of die TV-tak eruit trekken naar iets
dat los te testen is; dat is groter dan het gat dat fase 7 achterliet en hoort in een eigen stuk werk
thuis, niet als bijvangst van een testuitbreiding.

**Wat I24 wél en niet is.** Bij het sluiten van fase 7 is schakel 2 één keer statisch nagelopen, om
te bepalen of hier een productiebug onder zit of alleen een gat in de dekking. Er zit geen bug
onder, en dat is aantoonbaar uit vier regels die allemaal naar hetzelfde exemplaar wijzen:

- `_tvNavNodes` is één `FocusMemoryTracker` (`main_screen.dart:413`) en gaat als `navNodes` naar
  `TvRootShell` (`:2186`), die hem ongewijzigd doorgeeft aan `TvTopNavigation.nodes`;
- de balk maakt zijn nodes met `nodes.get(destinations[i].focusKey, …)`
  (`tv_top_navigation.dart:133`), en `_focusSidebar` vraagt er één op met
  `_tvNavNodes.get(_tvNav.focusedDestination.focusKey)` (`main_screen.dart:1431`) — dezelfde
  tracker, en dezelfde sleutelafleiding (`TvDestinationId.focusKey`);
- `_tvNav` is één `TvNavigationCoordinator` (`:408`) en gaat als `coordinator` naar diezelfde shell
  (`:2185`), dus `focusedDestination` en de getekende items komen uit één bron;
- `onFocusNav: _focusSidebar` (`:2193`) is wat `TvRootShell` als
  `MainScreenFocusScope.focusSidebar` publiceert, en dat is precies wat schakel 1 aanroept.

Er is dus geen tweede tracker, geen tweede coördinator en geen tweede sleutelconventie waar de
keten op mis kan lopen. Daarmee is I24 **integration-test coverage debt** en geen productbug: het
risico is een toekomstige regressie die niemand ziet, niet gedrag dat vandaag stuk is. Een
`MainScreen`-harnas bouwen om zes regels bedrading te dekken zou meer testoppervlak toevoegen dan
het bewijst, dus dat is bewust niet gedaan.

Dezelfde vaststelling geldt voor een tweede stuk bedrading, en dat hoort er eerlijk bij:
`_openTvCompleteCatalog` bindt `restoreFrom: _tvNav.contentFocusFor(destination)` en
`onRemember: (place) => _tvNav.rememberContentFocus(destination, place)`
(`main_screen.dart:1901,1902,1907,1908`). De restauratietests uit I22/I23 draaien op de
productieschermen en de productiecoördinator, maar de `_ShellHost`-harnas legt díe twee regels zelf
weer aan in plaats van ze uit `MainScreen` te halen. Ook hier wijzen beide kanten naar hetzelfde
`_tvNav`-exemplaar en is de binding eenduidig; ook hier zou een breuk groen door CI komen. Wie I24
ooit oplost, lost deze in dezelfde beweging op — het is één gat met twee uitgangen, niet twee
problemen.

**I21 — de filterknop ligt ver weg vanaf rij zes.** Toegevoegd op 31 augustus 2026, tijdens fase 7,
over fase-5-code. `TvUnifiedMediaGrid` geeft de uitgang naar de header alleen aan de bovenste rij
(`onNavigateUp: isFirstRow ? widget.onExitTop : null`, `tv_unified_media_grid.dart:313`). Dat is op
zichzelf correct spatial navigation — omhoog is omhoog — maar het betekent dat iemand die op rij zes
van vijfhonderd films staat zes keer Up plus Right nodig heeft om bij Filters te komen.

Hoofdstuk 7.4 en 10.6 hebben daar allebei al een antwoord op staan: *"Play/Pause mag als zichtbare
snelkoppeling het filterpaneel openen, maar filters blijven ook met een normale focusbare knop
bereikbaar"*, en *"De zichtbare knop blijft de primaire route; Play/Pause is hooguit een
snelkoppeling"*. Het gedrag is dus vastgelegd — wat ontbreekt is de implementatie: er is geen enkele
Play/Pause-afhandeling op het catalogusscherm.

Dit is geen regressie van fase 7, en fase 7 heeft het pad juist één stap korter gemaakt door
`Up` vanaf de header op de topnav aan te sluiten. Het staat hier omdat het tot nu toe nergens stond:
het was stilzwijgend blijven liggen als "mag" in plaats van als "moet nog", en dat is precies hoe een
bereikbaarheidsgat een release haalt. **De positie van de controls is niet het probleem en staat niet
ter discussie** — hoofdstuk 33.5 legt die als bindend vast (rustige controls rechts naast de kop,
ondergeschikt, geen CTA-pillen).

Niet ingevuld tijdens fase 7, met opzet: het catalogusscherm is fase-5-scope, en een snelkoppeling
erbij bouwen zou werk uit een andere fase vooruittrekken (hoofdstuk 27, regel 4). Het hoort thuis bij
fase 9 (functionele integratie en uitzonderingen) of bij een gerichte fase-5-aanvulling.

**I22 en I23 — wat de fase-7 systeemaudit vond en wat er niet aan gedaan is.** Een read-only audit
op de volledige fase-7-diff vond één blokkerend defect en acht kleinere. Het blokkerende is
gerepareerd en heeft nu een test die er zonder de fix rood van gaat
(`test/navigation/tv/tv_destination_test.dart`, `the bar cannot name a destination the screens list
will not build`): Mijn Pleya stond in de balk maar werd door `getVisibleTabs` op TV weggefilterd,
omdat de poort op `isMobile` stond en dat op een TV onwaar is. De pil lichtte op, het scherm werd
nooit gebouwd, en élke route erbinnen — Instellingen, Servers, Bibliotheken, de hoofdstuk-6.4-adapter
— was onbereikbaar. Dat geen enkele test het zag komt doordat ze allemaal het scherm rechtstreeks
monteerden in plaats van via de schermenlijst; de nieuwe test loopt wél door de productiepoort.

Vier kleinere bevindingen zijn ook gerepareerd: opnieuw selecteren van de actieve bestemming deed een
netwerkrefresh (hoofdstuk 7.2 verbiedt dat); `lastLiveTvCheckWasConclusive` was waar wanneer er
*niets* gevraagd was, waardoor een meting die met geen enkele server sprak een onthouden capability
kon intrekken; `TvLiveTvCapabilityStore.clearForProfileScope` werd nergens aangeroepen bij het
verwijderen van een profiel; en een geneste Mijn Pleya-sectie opende zonder gefocust element.

Twee zijn eerst geregistreerd in plaats van opgelost. Bij het sluiten van fase 7 zijn ze allebei
alsnog gerepareerd — ze bleken één defect met twee namen, en het was fase 7 dat het introduceerde:

- **I22 — kaartniveau focusherstel.** `TvNavigationCoordinator.rememberContentFocus` bestond en was
  getest, maar had geen productieconsument, dus de map bleef in de praktijk leeg en
  `clearFocusMemory` wiste niets. De reparatie is die consument, niet een tweede mechanisme: de
  memory is nu hoofdstuk 7.6's `TvDestinationFocusMemory` (gefocust element, `groupId`,
  scrolloffset) en `TvUnifiedCatalogScreen` schrijft hem weg bij `deactivate` en leest hem terug bij
  `initState`. Alleen de catalogus schrijft: elk ander bestemmingsscherm staat in de `IndexedStack`
  en bewaart zijn eigen positie al — de rails van een landing houden hun tegel in
  `TvDiscoveryRailState`, Mijn Pleya zijn tegel in zijn `FocusMemoryTracker` — en twee schrijvers per
  bestemming zouden twee antwoorden op dezelfde vraag zijn.

  Wat daarmee *niet* verandert, en ook niet hoort te veranderen: binnenkomen vanaf de balk landt op
  de primaire focus van het scherm en niet meteen op een kaart. Hoofdstuk 7.1 en 7.4 schrijven dat
  voor ("Down vanaf topnav focust de eerste headeractie"), en de kaart is één stap verder: DOWN
  daaruit landt op de kaart waar de kijker stond.
- **I23 — de complete catalogus herlaadde bij bestemmingswissel.** De landing eronder blijft
  gemonteerd, de geneste catalogus niet: alleen de *actieve* bestemming bouwt zijn bovenste route, dus
  naar Series wisselen en terug bouwde `Alle films` opnieuw op. Twee dingen gingen daarbij verloren
  en allebei zijn ze nu gedicht. De pagina's: `_applyQuery(startIfNeeded: true)` riep
  onvoorwaardelijk `setQuery`, wat de merge van generatie wisselt en elke geladen pagina weggooit —
  `startIfNeeded` betekent nu "start hem als hij niet loopt" in plaats van "start hem opnieuw", wat
  precies de belofte uit [DEC-069](../DECISIONS.md#dec-069) en hoofdstuk 24 is dat een geneste route
  geen herlaadbeurt kost. En de plek: die reist via de memory uit I22.

  De doccommentaren die het tegenovergestelde beweerden (`TvRootShell.child`: "switching
  destinations never … throws away a loaded catalogue") zijn meegecorrigeerd. Een commentaar dat een
  contract claimt dat de code niet nakomt is de duurste soort fout in dit register: hij zorgt dat
  niemand meer kijkt.

**Wie wat onthoudt, per bestemming.** Bij het sluiten van fase 7 is per bestemming nagelopen welke
laag daadwerkelijk bewaard wordt, omdat "focusherstel werkt" op deze shell twee verschillende
mechanismen kan betekenen en het verschil precies is waar I22 en I23 zaten. De scheidslijn is of het
scherm gemonteerd blijft:

| Oppervlak | Scherm blijft staan | Rij/sectie | Exacte kaart/tegel | Scrolloffset | Binnenkomst vanaf de balk |
| --- | --- | --- | --- | --- | --- |
| Home | ja — `IndexedStack` (`main_screen.dart:1190`, `_discoverKey`) | `TvBrowseRailState._hubIndex` | `TvBrowseRailState`, via `requestFocus()` (`tv_browse_rail.dart:544`) | `DiscoverScreen._scrollController` (`:156`) + de rail zelf | `focusActiveTabIfReady` → `_focusTvBrowseRailWhenReady` (`discover_screen.dart:1035,422`) |
| Films landing | ja — `IndexedStack` (`:1198`, `_moviesKey`) | `_railKeys`, gesleuteld op `hubId` (`tv_discovery_landing_screen.dart:104`) | `_focusedGroupIdByHubId` → `initialFocusedGroupId` (`:101,226`) | `_scrollController` (`:91`) | `focusActiveTabIfReady` → `_viewAllFocus`, de paginakop (`:279`) — hoofdstuk 7.1, niet de kaart |
| Series landing | ja — `IndexedStack` (`:1203`, `_seriesKey`) | idem (zelfde `TvDiscoveryLandingScreen`) | idem | idem | idem |
| Search | ja — `IndexedStack` (`:1214`, `_searchKey`) | `_firstTvRailKey` (`search_screen.dart:119`) | `TvDiscoveryRailState`, eigen nodes op `groupId` | met het scherm; query en resultaten ook | `focusActiveTabIfReady` → `_searchFocusNode`, het invoerveld (`:538`) |
| Mijn Pleya | ja — `IndexedStack` (`:1225`, `_tvMyPleyaKey`) | tegelgroepen in één scherm | `nodes.lastFocusedKey` op de eigen `FocusMemoryTracker` (`tv_my_pleya_screen.dart:204,235`) | `SingleChildScrollView`'s eigen positie (`:286`) | `focusActiveTabIfReady` → de laatst gefocuste tegel (`:235`) |
| Alle films | **nee** — `TvNestedRoute`, alleen de actieve bestemming bouwt hem | n.v.t., één plat grid | `TvDestinationFocusMemory.groupId` → `initialFocusedGroupId` (`tv_unified_catalog_screen.dart:578`) | `TvDestinationFocusMemory.scrollOffset`, geklemd toegepast in `_scheduleRestore` (`:215`) | `focusActiveTabIfReady` → `focusedElementId`, de laatst gebruikte headeractie (hoofdstuk 7.4) |
| Alle series | **nee** — idem | n.v.t. | idem | idem | idem |

Vijf van de zeven oppervlakken bewaren dus niets *ergens anders*: ze staan in de `IndexedStack` van
`MainScreen`, worden nooit afgebroken, en houden hun scrollpositie, hun rails en hun focusnodes
gewoon in hun eigen `State`. Alleen de complete catalogus wordt bij een bestemmingswissel
afgebroken, en alleen die schrijft daarom naar `TvNavigationCoordinator` — bij `deactivate`
(`tv_unified_catalog_screen.dart:175`) en terug bij `initState` (`:156`). Dat is met opzet precies
één schrijver per bestemming; twee zouden twee antwoorden op dezelfde vraag zijn.

De kolom "binnenkomst vanaf de balk" staat er los in, omdat hij een andere vraag beantwoordt dan de
rest van de rij en dat verschil bij het sluiten van fase 7 twee keer voor verwarring zorgde. Down
uit de balk landt op de *primaire focus van het scherm* — een paginakop, een invoerveld, een
headeractie — en niet meteen op een kaart. Hoofdstuk 7.1 en 7.4 schrijven dat zo voor. De onthouden
kaart ligt één stap verder: DOWN daaruit. Een matrixrij die "exacte kaart" leest en "landt op de
kaart" betekent, zou dus de verkeerde eis zijn.

Daarnaast drie noteringen zonder rij, omdat ze geen scenario zijn maar een tekortkoming: bij het
wegvallen van Live TV terwijl het open staat gaat Pleya wél naar Home maar zónder de korte melding
die hoofdstuk 19 noemt; `TvLiveTvCapabilityStore` bepaalt zijn profielscope op het moment van
schrijven in plaats van bij de aanroep, zodat een schrijfactie die over een profielwissel heen
uitloopt in de verkeerde entry kan landen; en de vijf schermen die op TV via Mijn Pleya geopend
worden staan óók nog in de `IndexedStack`, zodat er twee exemplaren tegelijk gemonteerd zijn.

## J. Accessibility en layoutcases

| # | Case | Test | Status |
|---|---|---|---|
| J1 | 1080p | test/goldens/tv_unified_catalog_golden_test.dart (`films, default state`, `series, default state`) en test/goldens/tv_unified_catalog_states_golden_test.dart — elke catalogusgolden rendert op het DEC-028-canvas, 1920x1080 gedeeld door 1,85 | covered |
| J2 | 4K-output | alleen op echte hardware vast te stellen; uitgesteld tot de eindacceptatie na fase 10A | open |
| J3 | Laagste ondersteunde TV-surface | test/utils/layout_constants_test.dart (groep `J3: TvLayoutConstants.scaleForHeight floors at the lowest supported TV surface`, twee tests: 918px — 0,85x van het 1080p-canvas — is de vloer en niets eronder zakt verder, en net boven de vloer schaalt nog gewoon evenredig) plus test/widgets/tv/tv_unified_media_grid_test.dart (`J3: the grid renders and focuses without overflow at the lowest supported TV surface`) — het echte grid rendert en focust zonder overflow op 1280×918 | covered |
| J4 | Overscan | alleen op echte hardware vast te stellen; uitgesteld tot de eindacceptatie na fase 10A | open |
| J5 | Lange vertaling | test/goldens/tv_unified_catalog_golden_test.dart (`films, labels at the length a long locale produces`, `films, long titles`) — de labels hebben de lengte van de Duitse strings; een echt omgeschakelde locale is in `flutter test` niet te renderen, want elke niet-basislocale is deferred. Fase 7 voegt de topnav toe: test/widgets/tv/tv_top_navigation_test.dart (`a long locale keeps every destination on one line and the bar one row high`) en test/goldens/tv_shell_long_locale.png | covered |
| J6 | Grote tekst | test/widgets/tv/tv_top_navigation_test.dart (`J6: a large system text scale keeps the bar one row high and does not overflow`) — 1,5x tekstschaal, dezelfde balkhoogte en geen enkele destination die naar een tweede regel wrapt, exact hoofdstuk 25's "Topnav mag niet buiten beeld lopen". `tester.platformDispatcher.textScaleFactorTestValue`, niet een handmatig ingevoegde `MediaQuery`/`Builder`-override — die combinatie met deze balk's eigen `ValueListenableBuilder`s bleek een echte, reproduceerbare oneindige rebuild-lus (stack overflow), losstaand geïsoleerd en niets met de balk zelf te maken | covered |
| J7 | RTL | test/widgets/tv/tv_rtl_contract_test.dart (groep `J7: the hero under a right-to-left directionality`, zes tests, één per clausule van hoofdstuk 25 plus de scrim apart) — **twee van de vijf clausules waren stuk**, en dat is de reden dat deze rij géén klasse A is: het leesscrim was een hardgecodeerde links-naar-rechts-ramp en het titelblok een fysieke `bottomLeft`, dus onder RTL zou de wash aan de overkant liggen van de tekst waarvoor hij bestaat en het titelblok 149px uit het spiegelbeeld schuiven. Dat is met een `Directionality`-override in een widgettest vast te stellen en vraagt geen toestel en geen locale — anders dan J2/J4/J8/J9, waar het instrument zelf ontbreekt. Beide zijn nu directioneel (`OptimizedMediaImage.alignment` is daarvoor verbreed naar `AlignmentGeometry`, wat elke sink al accepteerde). De andere drie clausules — CTA-volgorde, ongespiegeld artwork, en de carousel die aan de visuele richting gekoppeld blijft — klopten al en zijn vastgelegd. Elke test rendert beide richtingen en vergelijkt: een assertie die alleen het RTL-beeld leest onderscheidt "gespiegeld" niet van "in allebei hetzelfde, en fout". Alle goldens bleven byte-identiek, want onder LTR lost directioneel naar exact hetzelfde op. Het oude rastergarantietje (`builds under a right-to-left directionality without breaking`) staat er nog. Wat híer wél buiten bereik blijft is een echte locale-sweep, en dat is ook niet wat deze rij vraagt | covered |
| J8 | VoiceOver | alleen op echte hardware vast te stellen; uitgesteld tot de eindacceptatie na fase 10A. test/widgets/tv/tv_media_source_picker_test.dart (`a row announces its position and everything it actually shows`) en test/widgets/tv/tv_unified_media_card_semantics_test.dart leggen de semantics van een source row en van een catalogkaart vast — inclusief dat de kaart één node aanbiedt en niet titel en jaar dubbel uitspreekt — maar niet wat VoiceOver ervan maakt | open |
| J9 | Reduce Motion | alleen op echte hardware vast te stellen; uitgesteld tot de eindacceptatie na fase 10A | open |
| J10 | Light theme | `FocusTheme.focusDecoration`/`shapeFocusRing` kregen een dark separator-shadow (`FocusTheme.contrastSeparatorShadows`) naast de witte ring, precies wanneer `FocusTheme.needsContrastSeparator` — `MonoTokens.isLight` — waar is; de ring zelf blijft wit, hoofdstuk 8's regel dat wit de enige TV-focusidentiteit is verandert niet. test/focus/focus_theme_contrast_separator_test.dart (9 tests: `needsContrastSeparator` per palet, `contrastSeparatorShadows` gebruikt de eigen inktkleur van het thema en is een strakke lijn geen zachte glow, `focusDecoration`/`shapeFocusRing` dragen de separator precies op focused+light en nergens anders) plus het verplichte golden op de light surface: test/goldens/focus_contrast_separator_golden_test.dart (`a focused white pill stays visually distinct on a light/white surface`, `the same scene on the dark palette needs no separator, and gets none`) — geschilderd rechtstreeks vanaf de decoratiefuncties, niet via `FocusableWrapper`, zodat een falende golden ondubbelzinnig naar deze laag wijst | covered |
| J11 | OLED theme | test/goldens/tv_hero_billboard_theme_golden_test.dart (`J11: OLED only changes bg to pure black — surface, text and ink stay identical to dark`) — `mono_theme.dart`'s eigen tokentabel bewezen: `bg` gaat van `#141414` naar zuiver `#000000` en `surface` stapt één trede mee (`#1F1F1F` → `#141414`), maar `surfaceElevated`, `outline`, `text` en `textMuted` zijn byte-identiek aan dark, en `isLight` blijft `false` zodat het H20-lichtthemapad niet per ongeluk meeloopt. Gerenderd op dezelfde felgele plaatsvervangende artwork als H20 zodat een regressie in `artworkScrimAlpha`/`onArtworkInk` onder OLED evengoed zichtbaar zou zijn: test/goldens/tv_hero_billboard_oled_theme.png | covered |
| J12 | Focusglow bij eerste/laatste card | N.v.t. voor de unified-oppervlakken. `FocusableWrapper.useFocusGlow` (die `FocusGlowOverlay` naar de root-Overlay tilt, precies om de eerste/laatste-card-occlusie uit issue #1231 op te lossen) staat standaard uit, en geen enkele fase-5/6/8-kaart (`TvExpandableMediaTile`, `TvUnifiedMediaCard`) zet hem aan — beide draaien op `FocusIndicatorMode.delegated` zonder glow. `grep -rn "useFocusGlow" lib/` buiten `focusable_wrapper.dart`/`focus_builders.dart` zelf heeft precies twee treffers — `tv_browse_rail.dart` (`useFocusGlow: fullCardLayout`) en `focusable_media_card.dart` (`useFocusGlow: widget.fullBleedImage`) — allebei legacy pre-fase-8 code, buiten de scope van dit register. Geen hoofdstuk van docs/tvos-unified-experience.md noemt een focusgloed-vereiste. Een test tegen de unified kaarten zou dus niets echts bewijzen — dit is een bevinding over de scope, geen bewijsgat | covered |
| J13 | Panel met veel sources | test/widgets/tv/tv_media_source_picker_test.dart (groep `J13: a panel with many sources`, `twenty sources render without overflowing, and every one is reachable by D-pad`) — `TvSourceRowList` draait al op een echte `ListView.separated`/`ScrollController`, alleen ongetest; twintig bronnen renderen zonder overflow en de laatste rij is met de afstandsbediening bereikbaar | covered |
| J14 | Lege panelsecties | test/widgets/tv/tv_catalog_foundation_test.dart (groep `J14: empty panel sections`, drie tests: `a supported category with no values shows the no-values line, not a void`, `the no-values line is inside the zone, which keeps its size`, `loading and no-values are different states, not one blank`) plus de bestaande `a backend that cannot filter omits genre, year and status, not servers` voor de eerste invariant. Productie is `lib/widgets/tv/tv_catalog_filter_panel.dart`: `TvCatalogFilterSection` met `_availableSections`/`_supports`, `_buildOptions` en `_zoneHeight`. **Nul productiewijzigingen** — de rij was een proof gap, geen gat in het gedrag; de klasse-C-lezing keek naar de verkeerde panelen en is achterhaald (zie de gemarkeerde noot in "Fase-9-classificatie van de open rijen"). Drie invarianten bewezen: een niet-uitvoerbare categorie wordt weggelaten in plaats van leeg getekend en verantwoord met één `someUnavailable`-regel; een ondersteunde categorie met nul waarden houdt zijn plek in de rail, blijft de actieve categorie (geen terugval omdat de waardeset leeg is) en toont een expliciete `noValues`-regel zonder unsupported-waarschuwing; en die lege staat houdt dezelfde zonehoogte, dezelfde panelhoogte en dezelfde footerpositie als dezelfde categorie mét waarden, met de regel binnen die zone. `loading` en `noValues` zijn daarbij aparte staten: de seam is `clientFor` plus `_isLoadingOptions`, dus een client die nooit antwoordt bewijst het onderscheid zonder timer of netwerk. Twee negatieve controles echt gedraaid: de `noValues`-tak als `SizedBox.shrink()` maakt alle drie de tests rood, en de zonehoogte verlagen voor de lege state maakt de geometrietest rood (paneel 404,4 tegen 230,3). Eén ding valt er bewust buiten: dat de zone bij een ruim paneel op de ideale hoogte *aftopt* in plaats van mee te groeien is een andere eigenschap dan "een lege categorie springt niet", en die claimt deze rij niet | covered |
| J15 | Selected versus focused | test/widgets/tv/tv_catalog_foundation_test.dart (groep `J15: selected versus focused on a sort/filter option row`, `the selected row keeps its checkmark after focus moves away from it`) — `TvCatalogOptionRow` was al gebouwd met drie onafhankelijke lagen (base fill voor selected, additieve sheen voor focus, plus een vinkje) precies om de DEC-053-val te vermijden; de test bewijst dat het vinkje blijft staan als focus weggaat en niet meeloopt naar een rij die alleen focus krijgt | covered |
| J16 | Focus verandert de layout niet | test/widgets/tv/tv_unified_media_grid_test.dart (`focus moves nothing but the focused card`) — het raster is een `Column` van `Row`s en een `Row` is zo hoog als zijn hoogste kind, dus een kaart die bij focus groeit tilt zijn hele rij op en duwt de rijen eronder omlaag terwijl de gebruiker ernaar kijkt. De test legt alle negenendertig andere kaarten vast vóór en na de focus. Toegevoegd in fase 5; het gedrag zelf staat in hoofdstuk 10.2b ("ruimtelijk stabiel") | covered |
| J17 | D-pad LEFT/RIGHT tussen de hero-CTA's onder een gespiegelde volgorde | test/widgets/tv/tv_rtl_contract_test.dart (groep `J17: D-pad LEFT/RIGHT across the hero CTAs follows the rendered geometry`, zeven tests) — het productbesluit dat hier ontbrak is genomen op 1 september 2026: **spatial D-pad navigation volgt de gerenderde geometrie, niet de logische actievolgorde**. Semantics en focus zijn twee contracten; hoofdstuk 25 laat de leesvolgorde en de CTA-compositie spiegelen, maar Links betekent op een afstandsbediening de knop die je links ziet liggen. De `Row` in `tv_hero_billboard_carousel.dart` spiegelde zijn kinderen al (dat *is* clausule 2), maar `onNavigateRight` op Afspelen sprong naar Meer info op lijstpositie, dus onder RTL wandelde Rechts de focus naar links over het scherm. `_actions` leest nu de `Directionality` in de subtree van de rij zelf en leidt daar de linker- en rechterbuur uit af (`_stepFrom`), zodat er één autoriteit is voor plaatsing én traversal in plaats van twee tabellen die opnieuw uit elkaar kunnen lopen. De carouselclausule verandert niet mee: Links van de linkerrand blijft de vorige slide en Rechts van de rechterrand de volgende, in beide richtingen — clausule 5 meet dat nu vanaf de CTA op de *rand* in plaats van vanaf een vaste knop, want de rand is een positie en geen knop. Bewezen met een echte `Directionality`-override, geen locale nodig; en tegen de verkeerde soort fix afgedekt: twee tests leggen vast dat de labels aan hun eigen control gebonden blijven en dat Afspelen nog steeds `play` activeert en Meer info `details`, zodat een oplossing die de focusnodes verwisselt in plaats van de bedrading niet groen kan worden. Negatieve controle gedraaid: met de oude lijstvolgorde terug vallen precies de twee RTL-traversaltests, de dead-end-test en de RTL-helft van clausule 5 om, terwijl beide LTR-tests groen blijven. Alle goldens bleven byte-identiek | covered |
| J18 | Merklockup op het lichte thema | test/widgets/tv/tv_top_navigation_test.dart (groep `J18: the wordmark on the light theme`, vijf tests) plus test/assets/brand_wordmark_layers_test.dart (vier assetinvarianten) en het hertekende test/goldens/tv_home_production_light.png — het beeld dat het gebrek vastlegde, legt nu de oplossing vast. De "PLEYA"-letters in `assets/branding/pleya_wordmark.png` zijn wit en de topnav tekende dat bestand ongewijzigd op de themakleur, dus op het lichte palet stonden ze op 1,12:1 tegen een grond van #F2F2F3 en bleef alleen de rode P over. Opgelost langs [DEC-074](../DECISIONS.md#dec-074): `gen_brand_assets.py` splitst de bron in twee lagen op hetzelfde kanvas, en op licht tekent de balk de mark ongetint plus de letters op `MonoTokens.text` (16,88:1). Donker en OLED tekenen onverminderd het onverdeelde bestand, dus alle drieëntwintig donkere goldens bleven byte-identiek — dat is de hele reden dat de vork er is en niet één pad voor alles. Twee dingen maken deze rij falsifieerbaar in plaats van cosmetisch: de assertie meet **contrast** tegen de grond die `TvRootShell` eronder schildert, niet gelijkheid aan een constante, dus een latere hardgecodeerde bleke kleur valt er ook door; en de negatieve controle is gedraaid — met `_Wordmark` teruggezet op het onverdeelde bestand vallen precies de twee lichte tests om terwijl de eenentwintig andere groen blijven. De assetinvarianten dekken de faalwijze af die geen enkele widgettest ziet: de bron heeft een alpha-bbox van (0,1,1424,659) op een kanvas van 1452x659, dus een laag die op zijn eigen bbox gecropt wordt krijgt een andere aspect ratio, onder `BoxFit.contain` een andere breedte, en dan schuift het lockup uit elkaar **Bij datzelfde beeld bleek de P in de bron een oudere tekening dan `pleya_mark.png`** — dichte binnenvorm, flauwe rode lijnen — en omdat `lockup()` uit die bron werd opgebouwd droegen het tvOS-app-icoon, de drie Top Shelf-beelden, de Android TV-banner en het OG-beeld diezelfde oude P, terwijl de overige iconen de huidige droegen. Het lockup wordt nu samengesteld uit `pleya_mark.png` plus de belettering, dus de mark bestaat nog op één plek, en `test/assets/brand_wordmark_layers_test.dart` bewaakt dat hij niet opnieuw wegdrijft — negatieve controle gedraaid: met de oude P valt die assertie om op een gemiddelde kanaalafwijking van 19,7 tegen een drempel van 12, en de controle op de open binnenvorm valt apart om. Daarmee verviel ook de licht/donker-vork, die alleen bestond om de donkere goldens byte-identiek te houden: de merkverversing verandert ze toch, dus er is nu één compositiepad voor elk palet. | covered |
| J19 | Backend-badge van de Pleya-bron volgt de inktkleur niet | test/widgets/backend_badge_test.dart (achttien tests) plus test/assets/brand_logo_asset_test.dart (drie assetinvarianten) en test/goldens/backend_badge_set_dark.png / _light.png — de vraag die deze rij openhield (houdt een merkmark in een rij backend-badges zijn merkkleur, of voegt hij zich naar de inkt?) is beantwoord in [DEC-076](../DECISIONS.md#dec-076): een badge hier is een bronglyph en neemt de inkt van zijn regel, terwijl het merkrood bij `PleyaLogo` en het lockup blijft. `side_navigation_rail.dart` draagt allebei die regels in één scherm. De tint gaat door `BlendMode.srcIn`, zodat de alpha die `MediaCard`'s metadataregel meegeeft (60%) overeind blijft. Twee dingen maken de rij falsifieerbaar in plaats van cosmetisch: de widgettests lopen over `MediaBackend.values` in plaats van over de Pleya-tak, dus een vijfde backend zonder tint valt hier ook om; en de negatieve controle is gedraaid — met de oude tak terug vallen precies de vijf Pleya-tests en allebei de goldens om terwijl de dertien van de andere drie backends groen blijven. In dezelfde drie regels zat een tweede gebrek dat geen productbesluit vraagt: de badge tekende de handgemaakte bron `pleya_mark.png`, met een alpha-bbox van (39, 128, 931, 938) op een kanvas van 1024x1024, dus 87% van de breedte, 79% van de hoogte en een midden dat 27 pixels naar links en 22 pixels omlaag ligt, naast twee SVG's die hun viewBox vullen. Hij tekent nu het gegenereerde, gecentreerde `pleya_logo.png`. Dat is precies de faalwijze die geen widgettest ziet — `tester.getSize` geeft de doos terug die de `Image` kreeg, niet wat hij erin tekent, en die assertie bleef in de negatieve controle dan ook groen — dus de invarianten staan op de bytes. De post-merge gate haalde er nog twee dingen uit. De bronbewaker in `pleya_logo_test.dart` eiste dat alleen `PleyaLogo` het assetpad noemt en stond daardoor rood; hij kent de badge nu bij naam als tweede tekenaar met het besluit erbij (`61952a6`), zodat een derde rauwe callsite nog steeds omvalt. En de badge stond op `Image`'s standaard `BoxFit.scaleDown`, die verkleint maar nooit vergroot: boven de 512 pixels van het asset zou de P stoppen met groeien terwijl de twee SVG's hun doos wel bleven vullen. Staat nu op `BoxFit.contain`, met een test op maat 600 die de doos-test niet kan vangen, plus twee tests die de andere kant van de grens vastleggen: de badge deelt zijn cachesleutel met `PleyaLogo`, en `PleyaLogo` tekent ongetint | covered |
**De CTA-traversal onder een gespiegelde CTA-volgorde — opgelost op 1 september 2026.** Dit stond
hier als losse bevinding en niet als rij, omdat hoofdstuk 25 twee dingen bindt die onder RTL uit
elkaar lopen: de CTA-*volgorde* spiegelt logisch, maar links/rechts voor de *carousel* blijft aan de
visuele richting gekoppeld. De focusverplaatsing tússen die twee knoppen noemde het hoofdstuk niet,
en die liep op lijstpositie: `onNavigateRight` op Afspelen sprong naar Meer info, dus zodra de
volgorde spiegelde landde Rechts op een knop die visueel links stond.

Het ontbrekende productbesluit is genomen: **spatial D-pad navigation volgt de gerenderde geometrie,
niet de logische actievolgorde.** Semantics en focus zijn verschillende contracten — RTL mag
tekstalignment, leesvolgorde en de CTA-compositie spiegelen, maar Links en Rechts blijven op een
afstandsbediening de knop die daar fysiek ligt. Daarmee is de keten ook niet meer inconsistent, want
de carousel blijft precies staan waar hij stond: Links van de linkerrand is de vorige slide, Rechts
van de rechterrand de volgende, in beide richtingen. Alleen *welke* knop op die rand ligt verschilt,
en dat volgde altijd al uit de layout.

De bevinding is daarmee een gewone rij geworden — J17, hierboven, `covered`.


**J18 is tijdens fase 10A ontstaan, uit het eerste lichte Home-beeld.** Hoofdstuk 29 vraagt om
`tvos.home.unified.light` en die render bestond nog niet: `tv_hero_billboard_light_theme.png` toont
het billboard los, niet de balk erboven. Zodra de hele compositie op het lichte palet stond was het
zichtbaar — het woordmerk rechtsboven verdwijnt.

Het is een echt en bereikbaar geval. Het lichte thema is een gewone gebruikersinstelling
(`ThemeProvider.materialThemeMode`) zonder TV-uitzondering, en onder `system` volgt het bovendien de
appearance van het toestel, dus een Apple TV kan hier komen zonder dat iemand iets bijzonders doet.

Waarom er hier geen fix onder staat. Hoofdstuk 8.2 zegt "licht thema krijgt ... donkere tekst", maar
het woordmerk is geen tekst: het is één PNG met twee kleuren erin — witte letters plus de rode
P-mark, die volgens datzelfde hoofdstuk juist rood blijft als branddetail. Er is geen `ColorFilter`
die het ene hertint en het andere niet, dus elke oplossing is een merkbeslissing: een tweede asset
met donkere letters, alleen de mark op licht, of een andere behandeling van de lockup. Geen enkel
hoofdstuk, DEC of north-starbeeld dekt dat af — alle acht referentiebeelden van hoofdstuk 33 zijn
donker. Dat is exact de klasse waarin J14 toen zat, en de regel bovenaan dit register schrijft voor dat
zo'n geval eerst een vastgelegd gedrag krijgt en pas daarna een fix. Fase 10A is bovendien harding
zonder visuele art direction, dus de keuze hoort niet in deze fase gemaakt te worden.

**En dat is precies zo gegaan.** Het besluit is een dag later genomen en staat als
[DEC-074](../DECISIONS.md#dec-074). De zin hierboven dat geen enkele `ColorFilter` het ene hertint
zonder het andere te pakken klopt nog steeds — hij is niet weerlegd maar omzeild: de splitsing zit nu
in het *asset*, niet in een filter. `gen_brand_assets.py` schrijft twee lagen uit dezelfde handgemaakte
bron, allebei op het volledige bronkanvas met de andere helft leeg, zodat ze in één rect getekend
samen exact het origineel zijn. Op licht tekent de balk de mark ongetint en de letters op
`MonoTokens.text`; op donker en OLED verandert er niets. De rij is `covered`.

## Totaal

181 cases: A20, B15, C24, D15, E15, F21, G14, H21, I20, J16. Nul `covered` bij aanmaak (fase 0).
F21 kwam er in fase 4 bij, samen met het gedrag dat hij beschrijft (hoofdstuk 14.8a). J16 kwam er bij
het sluiten van fase 5 bij, langs dezelfde regel: het gedrag stond al vast in hoofdstuk 10.2b, de
situatie — een focus die de rij eronder verschuift — was alleen nog niet als rij benoemd. I21 tot en
met I24 kwamen er in fase 7 bij. J17 is de laatste, bij het sluiten van fase 9, en langs diezelfde
regel: eerst het ontbrekende gedrag vastgelegd (de noot onder register J), daarna pas de rij. Dat
brengt het register op 186. J18 is er in fase 10A bij gekomen, langs diezelfde regel — eerst het
gedrag geclassificeerd, en juist omdat het níet vastligt is de rij klasse C en geen fix — wat het
register op 187 brengt. J19 is er op 2 september 2026 bij gekomen, bij het oplossen van J18, wat het
op 188 brengt. B17 is er dezelfde dag nog bij gekomen, langs diezelfde regel — eerst het gedrag
gecorrigeerd (search reageert al op wijzigingen in `HiddenLibrariesProvider`, zie de noot verderop),
daarna pas de rij — wat het op 190 brengt (het register stond na de eindaudit al op 189, één hoger
dan de 188 hierboven; dat verschil zit 'm in B16 zelf, dat als bestaande rij niet in deze
optelreeks is meegenomen).

**Stand na de J14/B17-correcties (2 september 2026): 182 `covered` en 8 niet-`covered`, op een
register van 190.** J14 was ten onrechte als onopgelost productcontract geclassificeerd (het gedrag
lag al vast, alleen het bewijs ontbrak) en B17 is een nieuwe rij voor een bevinding die eerder
bewust zonder rij bleef — zie de noten bij beide hierboven en de rijen zelf. Dat brengt het aantal
op: A 20 van 20, B 16 van 17, C 24 van 24, D 15 van 15, E 15 van 15, F 21 van 21, G 14 van 14,
H 21 van 21, I 21 van 24, J 15 van 19. Wat openstaat: vijf hardware (J2, J4, J8, J9, I17), drie
geregistreerde debts (I21, I24, B16 — het oorspronkelijke B16, de Pleya-Server-bevinding; zie de
rij zelf, niet te verwarren met het nieuwe B17) en **geen enkele normale open rij meer**. Dit is de
huidige eindstand; onderstaande "stand bij het sluiten van fase 9" is de tussenstand vóór deze twee
correcties en blijft staan omdat hij de weg ernaartoe vastlegt.

Stand na J14 (2 september 2026, na de eindaudit hieronder): **181 `covered` en 8 niet-`covered`**, op
een register van 189, en daarmee **nul onopgeloste productcontracten**. De eindaudit hieronder noemde
zichzelf de eindstand van de fase en was dat op dat moment ook; J14 is er dezelfde dag alsnog
uitgevallen, en niet door een productbesluit. De rij bleek geen klasse C maar een proof gap: het
gedrag stond al in `tv_catalog_filter_panel.dart` en er was alleen geen test. Nul productiewijzigingen,
twee negatieve controles gedraaid. Wat overblijft is uitsluitend geclassificeerd: vijf hardwarerijen
(J2, J4, J8, J9, I17) en drie geregistreerde debts (I21, I24, B16). Per categorie is dat A 20 van 20,
B 15 van 16, C 24 van 24, D 15 van 15, E 15 van 15, F 21 van 21, G 14 van 14, H 21 van 21, I 21 van
24 en J 15 van 19.

Stand bij het sluiten van fase 9 (2 september 2026, na de eindaudit): **180 `covered` en 9
niet-`covered`**, op een register van 189. Dit was de eindstand van de fase vóór de J14/B17-correcties
hierboven; de regels hieronder zijn de tussenstanden in omgekeerde volgorde en blijven staan omdat ze
de weg ernaartoe vastleggen. Wat toen overbleef was uitsluitend geclassificeerd werk, geen gewone
functionele of bewijsrij:

- **vijf hardware (klasse A):** J2 (4K-output), J4 (overscan), J8 (VoiceOver), J9 (Reduce Motion) en
  I17 (de Android TV-hardwareterugknop). Ze horen bij de eindacceptatie na fase 10A, niet bij de gate
  van deze fase.
- **drie geregistreerde debts (klasse B):** I21 en I24, allebei met hun vervalvoorwaarde in de rij
  zelf — fase-9-code heeft het catalogusheaderpad, `_focusSidebar` noch de nav-nodes geraakt, dus
  geen van beide is vervallen — plus **B16**, dat uit de eindaudit komt: de lokale-mapclient filtert
  nu wél op `query.kind`, de Pleya Server-client niet, en dat laatste is niet op te lossen zonder
  aan de cursorledger te rekenen terwijl het protocol bevroren is.
- **één onopgelost productcontract (klasse C):** J14. Er is geen hoofdstuk en geen DEC die definieert
  wat "een panelsectie" is, dus er is ook geen gedrag om tegen te testen. Blijft `open`; niet
  stilzwijgend geherclassificeerd en niet `covered` gemaakt. *(Nog diezelfde dag achterhaald: het
  gedrag bleek wél te bestaan, in het filterpaneel in plaats van in de panelen waar de audit keek.
  Zie de stand hierboven en de rij zelf. Ook dat is niet stilzwijgend gegaan.)*

Per categorie is dat A 20 van 20, B 15 van 16, C 24 van 24, D 15 van 15, E 15 van 15, F 21 van 21,
G 14 van 14, H 21 van 21, I 21 van 24 en J 14 van 19.

**De eindaudit heeft negen defecten opgeleverd die zijn opgelost**, en met terugwerkende kracht een
tiende (zie de correctie hieronder). Acht zitten in code die fase 9 zelf heeft geschreven of
aangeraakt, allemaal met een test die vóór de fix omvalt: een catalogus die "leeg" meldde zodra elke
bibliotheek trager was dan de genadeperiode; `updateItem` dat op een tweede server de verkeerde titel
ophaalde omdat het op een kale item-id zocht; een auth-foute membership die uit álle drie de emmers
viel en de teller dus "klaar op alle 1" liet zeggen; dezelfde membership die "geen bruikbare bron"
kreeg in plaats van "opnieuw aanmelden"; de G7-poort die op de hele groep werd gelezen in plaats van
op de overlevers; een cijferdoel op een backend zonder `userRating` dat uit de noemer viel; een korte
pagina van de Pleya Server-client die als "bibliotheek uit" werd gelezen terwijl de cursor nog verder
wees; en een concurrencyplafond dat per ronde opnieuw begon te tellen. Het negende is de
attention-dot in de topnav: die stond op een kale `Positioned` met een fysieke `right`, wat onder RTL
de verkeerde hoek is — dezelfde verwarring die DEC-072 voor de hero-CTA's al oploste. Dat is hier
verkeerd opgeschreven: een eerdere versie van dit register telde hem mee bij de bevindingen die
*geen* defect bleken, in dezelfde zin als de vermeende trage-bibliotheek-fout, terwijl het proza
ernaast al zei dat hij gerepareerd was ("is nu richtinggevoelig, met een test die in beide richtingen
meet" — zie ook `docs/CHANGELOG.md`). Geen enkele bevinding is tegelijk *rebutted* en *fixed*; hij
stond hier verkeerd bijgeteld en is nu bij de negen opgeloste defecten gezet, waar hij hoort. Eén
bevinding is wél *geen* defect gebleken: dat een trage bibliotheek achteraan aansluit in plaats van
terug te sorteren is precies wat E14 vastlegt.

**Wat bij het sluiten van fase 9 nog stond te wachten, is inmiddels ook opgelost.** Eén bevinding
bleef destijds staan zonder fix en zonder rij, omdat de voor de hand liggende oplossing erger leek
dan de kwaal: `search_screen.dart` las de verborgen-bibliothekenset synchroon in plaats van
`ensureInitialized()` af te wachten, want dat laatste hing de zoekactie op zodra opslag niet
antwoordde — geprobeerd, en zeven schermtests liepen toen in een `pumpAndSettle`-timeout. Die
afweging was zelf niet fout (een blokkerende wachtrij op de dispatch is inderdaad de verkeerde
plek, zoals bij het opnieuw proberen op 2 september 2026 bevestigd werd), maar het venster zelf —
TV Search die nog kan lopen terwijl `HiddenLibrariesProvider` zijn persisted visibility nog niet
geladen heeft — was ten onrechte als geaccepteerde debt aangemerkt in plaats van als
gedragsgat binnen het automatiseerbare bereik van deze fase. Dat is nu **B17** in het register
(zie de rij en de noot eronder) — een nieuw nummer, niet B16: dat nummer draagt al de
Pleya-Server-bevinding uit dezelfde eindaudit en is een andere zaak. Een luisteraar op
`HiddenLibrariesProvider`'s eigen wijzigingen — dezelfde die een hide/unhide tijdens een actieve
sessie al moest afvangen — draait de laatst gezochte query alsnog opnieuw zodra de echte
zichtbaarheid alsnog landt, zonder de dispatch zelf te blokkeren; een sleutelvergelijking tegen de
laatst gebruikte zichtbaarheidsset voorkomt dat die correctie zelf een overbodige tweede fan-out
kost. B17 is `covered`.

Stand na de J19-fix (2 september 2026): **180 `covered` en 8 niet-`covered`**, op een register van
188. J19 is dezelfde dag nog gesloten langs [DEC-076](../DECISIONS.md#dec-076) — de badge is een
bronglyph en neemt de inkt van zijn regel — waarmee het aantal onopgeloste productcontracten weer op
één komt. Open blijven: vijf hardware (J2, J4, J8, J9, I17), twee geregistreerde debts (I21, I24) en
één onopgelost productcontract (J14). Per categorie is dat A 20 van 20, B 15 van 15, C 24 van 24,
D 15 van 15, E 15 van 15, F 21 van 21, G 14 van 14, H 21 van 21, I 21 van 24 en J 14 van 19.

Tijdens hetzelfde etmaal zijn er twee gebreken gesloten die geen registerrij hebben, omdat ze uit
gebruikersmeldingen kwamen en niet uit een edge case in dit register: een onbereikbaar mediabestand
dat als "Afspelen gestopt" zonder uitleg aankwam, en afspeelmeldingen die bleven staan en stapelden.
Ze staan als [DEC-078](../DECISIONS.md#dec-078) en zijn hier genoteerd als *additional regression
fixes* binnen fase 9, niet als registerrijen: ze raken de speler en het meldingsysteem, niet de
unified TV-oppervlakken die dit register aftelt. Ze verschuiven dus geen enkele telling hierboven.

Stand na de J18-fix (2 september 2026): **179 `covered` en 9 niet-`covered`**, op een register van
188. J18 is van klasse C naar `covered` gegaan langs [DEC-074](../DECISIONS.md#dec-074), en J19 is er
bij dat werk bij gekomen — de Pleya-backendbadge die als enige tak van zijn `switch` de inktkleur
negeert. Netto blijft het aantal openstaande rijen dus gelijk: vijf hardware (J2, J4, J8, J9, I17),
twee geregistreerde debts (I21, I24) en twee onopgeloste productcontracten (J14, J19). Per categorie
is dat A 20 van 20, B 15 van 15, C 24 van 24, D 15 van 15, E 15 van 15, F 21 van 21, G 14 van 14,
H 21 van 21, I 21 van 24 en J 13 van 19.

Stand na fase 10A: **178 `covered` en 9 niet-`covered`**, op een register van 187. J18 is de enige
rij die 10A eraan toevoegt — een tweede onopgelost productcontract, ontstaan uit het eerste lichte
Home-beeld (zie de noot onder register J). Fase 10A heeft geen rij van `open` naar `covered`
verplaatst en dat is de bedoeling: het was hardingswerk op een register dat fase 9 al had gesloten,
geen tweede inhaalronde. Per categorie is dat A 20 van 20, B 15 van 15, C 24 van 24, D 15 van 15,
E 15 van 15, F 21 van 21, G 14 van 14, H 21 van 21, I 21 van 24 en J 12 van 18.

Stand na fase 9: **178 `covered` en 8 niet-`covered`** — vijf hardware (J2, J4, J8, J9, I17), twee
geregistreerde debt (I21, I24) en één onopgelost productcontract (J14). Per categorie is dat A 20 van
20, B 15 van 15, C 24 van 24, D 15 van 15, E 15 van 15, F 21 van 21, G 14 van 14, H 21 van 21, I 21
van 24 en J 12 van 17. Er staat geen bevinding meer zonder rij: de CTA-traversal onder een
gespiegelde CTA-volgorde is J17 geworden.

Stand na fase 6: 73 `covered` en 108 `open`. Fase 5 sloot op 70/111; fase 6 voegt D1, H12 en H15
toe. Per categorie is dat A 8 van 20, B 5 van 15, C 24 van 24, D 4 van 15, E 4 van 15, F 20 van 21,
G 1 van 14, H 2 van 21, I 2 van 20 en J 3 van 16.

De stand na fase 5 was 70 `covered` en 111 `open`. Dat was de stand na fase 4 — C1-C24, F1-F18, F20-F21 en
G9, samen 45 rijen, hier eerder als 46 opgeteld — plus de vierentwintig rijen die fase 5 heeft
nagelopen: A2, A6-A11, A13, B1-B3, B7, B9, D5-D7, E3, E4, E9, E11, I7, I15, J1 en J5. Per categorie
is dat A 8 van 20, B 5 van 15, C 24 van 24, D 3 van 15, E 4 van 15, F 20 van 21, G 1 van 14, H 17 van
21, I 5 van 20 en J 3 van 16 — J16 meegeteld. (H en I zijn bijgewerkt bij het sluiten van fase 8;
de overige tellingen zijn die van fase 6/7.)

Register F is nog steeds volledig op één rij na: F19 (detailroute faalt) heeft nog geen vastgelegd
productgedrag en wacht daarop, niet op een test.

**Fase 6 en de drie rijen die erbij komen.** Fase 6 bouwde de discovery-landings, de unified Search
op de TV-tak, de Continue Watching-projectie en — na [DEC-067](../DECISIONS.md#dec-067) — de
gededupliceerde TV-hero. Bij het sluiten is het register nagelopen tegen wat die fase daadwerkelijk
bewijst, met dezelfde strengheid als fase 5: een rij verschuift alleen als er een test is die
precies dát scenario aantoont. Dat leverde er drie op — D1, H12 en H15 — en niet meer. Wat
nadrukkelijk `open` blijft, met reden:

- **H14 (hero-data komt laat).** De datakant is bewezen (`hasProjectedHero` en
  `projectedLatestMovies` scheiden een nog niet afgeronde projectie van een echt lege filmpool, en
  het billboard valt tijdens een koude load niet leeg), maar hoofdstuk 9.7's layoutregel — een hero
  die pas wordt toegepast wanneer Home weer bovenaan staat en er geen interactie loopt — is
  presentatie en daarmee fase-8-werk. Half bewezen is hier niet `covered`.
- **H16 (alleen series beschikbaar).** De lege-filmpool-test gebruikt een filmhub als fallback, niet
  een bibliotheek die alleen series heeft. Dat is een ander scenario.
- **G1-G8 (watch-state merge).** `every source keeps its own watch state` bewijst hoofdstuk 13.1
  (bronstate blijft intact) voor Continue Watching, maar geen van die rijen vraagt dát — ze vragen
  welke voortgang de kaart *toont* (hoofdstuk 13.2). Die keuze is niet apart vastgelegd in een test.
- **D2 (verschillende seizoensdekking).** D1's tests hebben twee servers op dezelfde en op
  verschillende afleveringen, niet twee servers met een verschillend seizoensbereik. *(Bijgewerkt bij
  de fase-8-sluiting: D1's fixtures zijn herschreven naar exact-episode-semantiek, zie de noot
  daarover verderop. D2 blijft om dezelfde reden open.)*

De overige fase-6-rijen (H1-H11, H13, H17-H21) hangen aan hero-*presentatie* en horen bij fase 8;
I1-I6 en I8-I14 hangen aan de topnav en de root-shell en horen bij fase 7.

**Fase 8 en de zeventien rijen die erbij komen.** Fase 8 bouwde de definitieve Home: de afgeronde
in-page carousel, de unified contentfeed eronder, en het loskoppelen van rijfocus en hero
([DEC-070](../DECISIONS.md#dec-070)). Register H gaat daarmee van 2 van 21 naar 17 van 21, en I2,
I3 en I4 sluiten. Dezelfde strengheid als altijd: een rij verschuift alleen als er een test of een
constructie is die precies dát scenario aantoont, en H14 is een goed voorbeeld van wat dat betekent
— hij stond hier als "half bewezen is niet covered", en sluit nu pas omdat de layoutkant van
hoofdstuk 9.7 er is (`TvContentFeed` reserveert de billboardruimte tijdens een onafgeronde
projectie in plaats van een fallback te tonen die een tel later omklapt).

Wat in register H **open** blijft, en waarom:

- **H9 (spoilers verbergen)** en **H10/H11 (watched / in-progress titel).** De hero leest
  `hideSpoilers` en tekent een resumebalk in de primaire pil, en `_HeroPill`'s `progress` komt uit
  `resumeFractionFor(group)` — maar geen test rijdt die drie toestanden af, en de hero draagt per
  hoofdstuk 9.5 alleen films en series, dus de spoilerregel bijt er in de praktijk alleen op een
  fallbackbillboard. Ongetest is ongetest.
- **H20 (light theme).** Alle Home-renders staan op het donkere thema. De kaart leest zijn kleuren
  uit `MonoTokens`, dus er is geen hardgecodeerde donkere aanname, maar dat is een argument en geen
  bewijs.

**De tegenspraak tussen hoofdstuk 11.8 en rij D1 over Verder kijken is opgeheven.** Geregistreerd op
1 september 2026 bij het naverifiëren van de fase-8-sluiting, en op dezelfde dag opgelost door de
identiteitslaag naar het hoofdstuk toe te brengen in plaats van andersom.

Hoofdstuk 11.8 schrijft voor: *"Verder kijken groepeert op exacte aflevering: `show identity +
season + episode`. Nooit: alle afleveringen van dezelfde serie als één Continue Watching-item."* De
implementatie deed dat niet. `continueWatchingScope` gaf `'show'` voor een aflevering,
`continueWatchingBucketKey` bucket'te op `grandparentTitle`, en de externe ids kwamen van de *serie*,
zodat twee verschillende afleveringen die hetzelfde serie-brede tmdb/tvdb oplosten één sterk token
deelden en één kaart werden.

Wat er is veranderd, in `lib/services/unified_catalog/identity_resolver.dart` en
`lib/media/unified/identity_evidence.dart` — de smalste plek die deze regel bezit, en de enige twee
bestanden met een gedragswijziging:

- een aflevering wordt gescoped op `episode` en een seizoen op `season`, niet meer allebei op `show`;
- `continueWatchingOrdinal` levert de ordinaal (`s2e4`, `s2`), die als `discriminator` aan
  `externalIdTokens` meegaat: een serie-breed `tmdb:95396` wordt daarmee `episode:tmdb:95396/s2e4`,
  dus bewijs over één aflevering in plaats van over de hele serie (rij D4);
- dezelfde ordinaal zit in de bucketsleutel, dus twee verschillende afleveringen delen geen bucket
  meer en kopen die serie-brede id niet eens meer op;
- de eigen guid van een aflevering telt weer mee — die is al exact-aflevering-bewijs en is nu
  precies de granulariteit waarop gegroepeerd wordt (rij D3);
- een aflevering zonder bruikbare seizoen- of afleveringsindex heeft géén bucket, dus valt terug op
  alleen zijn guid: hoofdstuk 11.8's "ontbrekende indexen vereisen een sterk episode-ID", en de
  invariant dat een false merge erger is dan een false negative (rijen D6/D7).

Beide kanten zijn met een negatieve controle bewezen. Met de identiteit tijdelijk terug op
serie-breed vallen tien tests over vijf bestanden om, in de identity-laag, de upstream dedup, de
productieprovider, de serviceprojectie én de Home-feed; met alleen de token-discriminator
uitgeschakeld vallen de twee identity-tests om die precies dát isoleren. De vier tests die het oude
contract vastlegden zijn herschreven in plaats van verwijderd, en de gedeelde fixture
(`tvDiscoveryEpisodeGroup`, `disc-cw-two-servers`) draagt nu één aflevering op twee servers in plaats
van twee verschillende afleveringen in één groep — met een assert die dat afdwingt. Geen enkele
golden veranderde: de representative source van die groep rendert byte-identiek.

Register D gaat daarmee van 4 van 15 naar 6 van 15: D3 en D4 sluiten op de tests hierboven, en D1
blijft `covered` maar nu zonder voorbehoud. D2 blijft open — seizoensdekking is niet wat deze
correctie aantoont — en D8-D15 evenmin.

De F-rijen dragen nu beide helften: het besluit (coordinator, resolver, stores) én het zichtbare en
met de afstandsbediening bedienbare deel (`test/widgets/tv/tv_media_source_picker_test.dart`,
`test/widgets/tv/tv_source_row_descriptor_test.dart`). De goldens in
`test/goldens/tv_media_source_picker_golden_test.dart` renderen dezelfde toestanden op het
tvOS-canvas van DEC-028; ze bewaken compositie op dit platform en vervangen geen hardwareverificatie
(hoofdstuk 29).

De rijen die fase 5 heeft ingevuld leunen op de merge-engine
(`test/services/unified_catalog_service_test.dart`) en op de provider die hem aanstuurt. Waar zo'n
rij ook een zichtbaar deel heeft staat dat ernaast: A8 en A10 wijzen naar de goldens, want een
library die niet antwoordde meldt zich onder de grid en een catalogus waar niets uit kwam vult de
hele pagina. D5-D7 zijn identityrijen en worden, net als register C, door de identiteitstests alleen
bewezen; er is nog geen serie- of afleveringscherm waar iets van te zien zou zijn.

Wat bewust `open` is gebleven, en waarom. *(Deze alinea is geschreven bij het sluiten van fase 5 en
beschrijft de stand van toen; de fase-6- en fase-8-alinea's hierboven zijn de actuele lezing van H
en I.)* Register H staat nog helemaal open: de hero bestaat niet, die komt in fase 6 en 8. Register I
is op twee rijen na een zaak van fase 7 (topnav en Mijn Pleya); alleen I7 en I15 gaan over
mechanismen die er nu al zijn. Register G is op G9 na open, en dat is de
zwaarste post: `selectRepresentativeWatchState` — de functie die per group beslist wélke bron de
kijkstatus levert, inclusief de klok-skew, de ontbrekende timestamps en de afwijkende runtimes uit
G5 tot en met G7 — heeft geen enkele eigen test. In A, B en E zijn de rijen die over een tweede ronde
gaan open gebleven (A12 server valt weg tijdens paging, B13 lege pagina vóór total, E6 bron faalt ná
geslaagde pagina's, E8 total verandert onderweg, E15 dezelfde source twee keer): de tests die er het
dichtst bij komen falen of stoppen in de eerste ronde, en dat is een ander pad door dezelfde code.
Elke fake client in de catalogustests is bovendien een Plex-client, dus A3 (Jellyfin), A4 (Pleya
Server) en A5 (Plex plus Jellyfin) zijn niet aangetoond, hoe klein het verschil ook lijkt.
