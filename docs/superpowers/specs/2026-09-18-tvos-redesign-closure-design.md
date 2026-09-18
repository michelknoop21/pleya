# tvOS-redesign: closure workstream TV0 tot en met TV8

Vastgelegd op 18 september 2026. Deze spec is gereconcilieerd tegen `github/main` = `9342ab7c`
vóór de spec-commit. `origin` (Gitea) stond op dat moment nog op `3b08b746`; de drie commits
ertussen raken alleen design-authority (`DESIGN-INDEX.md` en twee beeldenset-README's), en niet de
registers, de correctieronde of de closure. Dit document beschrijft de
werkstroom die het resterende tvOS-werk consolideert tot de tvOS-zijde van
[unified-2026-closure.md](../../unified-2026-closure.md) stap 16 bereikt is, inclusief schuld die
uit eerdere tvOS-stappen is blijven staan.

## 1. Verhouding tot de bestaande closure-authority

TV0 tot en met TV8 mogen `unified-2026-closure.md` niet vervangen, dupliceren of een tweede
releasegate introduceren. Bij tegenspraak wint de bestaande closure-authority.

| Document | Bezit |
|---|---|
| [unified-2026-closure.md](../../unified-2026-closure.md) | statusladder, bewijsregel, werkvolgorde, releasegate, hardware-eindronde, TestFlight |
| [tvos-redesign-register.md](../../tvos-redesign-register.md) | de status per tvOS-workitem |
| [tvos-fysieke-correctieronde.md](../../tvos-fysieke-correctieronde.md) | de bevindingen met hun eigen statussen |
| [DECISIONS.md](../../DECISIONS.md) | besluiten, append-only |
| dit document | de indeling van het resterende tvOS-werk in TV0 tot en met TV8, en de mapping van elk open item naar een plan |

Dit document kent geen eigen statussen toe en verplaatst geen enkele status uit een register
hierheen. Waar het een status noemt, is dat een citaat met de vindplaats erbij.

Er is geen TV9. De hardwareronde is closure §7: één SHA, één archive, samen met iOS. Een eerdere
of tvOS-eigen hardwareronde zou §7 wijzigen en vraagt dan een DEC, wat hier niet aan de orde is.

### Definition of Workstream Done

TV0 tot en met TV8 zijn voltooid wanneer alle niet-hardware tvOS-items uit de gereconcilieerde
open-set een eindstatus hebben, alle vereiste tvOS Verify-journeys groen zijn, geen bekende
tvOS-gerelateerde testschuld meer openstaat, `main` voor de relevante gates groen is, en alleen
expliciet naar closure §7 doorgeschoven hardwarebewijs resteert.

Dit betekent nadrukkelijk niet dat Unified 2026 of tvOS release-ready is. iOS heeft op deze SHA
negen `OPEN` workitems (10, 11, 12, 13, 16, 17, 19, 20, 21) plus eigen Verify-schuld, en de
gezamenlijke §7-gate blijft daarna nog vereist.

## 2. TV0: reconciliatie van de administratie

TV0 wijzigt geen code. Het levert één ondubbelzinnige open-set op door de tegenstrijdigheden
tussen de drie documenten op te lossen op de plek waar ze staan. Er komt geen vierde mastertabel.

### 2.1 MOC-09 tot en met MOC-12 hebben twee statussen

Het register noemt MOC-09, MOC-10, MOC-11 en MOC-12 `IN PROGRESS`. Closure §5 stap 6 noemt
dezelfde vier `CODE/SIM CLOSED`, met `1805c75e` (MOC-09/10), `968d794e` (MOC-11), `62e48d12`
(MOC-12) en `eb5de4c9` (LIB7). Closure §1 bepaalt dat de closure wint bij tegenspraak.

Actie: de vier registerregels naar `CODE/SIM CLOSED · HARDWARE OPEN`, met de SHA erbij.

### 2.2 De drie MOC-12-gaten hebben geen ID

Closure §5 stap 6 schrijft dat "MOC-12's drie visuele gaten (metadata-subregel, resterende tijd,
iconen per actierij) bewust ongebouwd blijven deze ronde". Ze staan alleen in proza, in de closure
en in de registerregel. Werk zonder ID verdwijnt uit de administratie.

Een scan van de 132 rijen in de correctieronde levert 47 prefixen op, geen daarvan voor het
contextmenu. Het dichtstbijzijnde was `OVR1`, en dat ging over de overlaygeometrie en is al
gesplitst in OVR1a en OVR1b. TV0 maakt daarom de categorie `CTX` aan en geeft de drie gaten
`CTX1`, `CTX2` en `CTX3`, elk als eigen rij, zodat ze los kunnen sluiten.

### 2.3 OFF2 staat twee keer in de correctieronde, voor twee verschillende problemen

Regel 138 beschrijft de focusbare dode pills in de offline topnav, `FIXED` met `472233db` en
`267e6dc1`. Die rij spiegelt register `OFF-2` en houdt zijn nummer.

Regel 131 beschrijft de offline-tab-routingbug in `main_screen.dart:2143`, waar `_selectTab`
onvoorwaardelijk opnieuw wordt toegewezen zodra `_syncTvDestinations()` een `displaced`-tab
teruggeeft. Die rij is de wees. `OFF4` is bezet door de Code-Analysis-CI-fix, dus het eerstvolgende
vrije nummer in de reeks is `OFF5`. De routingbug wordt `OFF5`, overal met dezelfde identiteit.

### 2.4 De REQ1-noot in het register is verouderd

Register MOC-15 zegt "REQ1 is fixture-blocked, zie T3a". Correctieronde regel 93 zegt `FIXED,
simulator geverifieerd`, met `f72466f2`, `39f266be`, `df3dab65` en `2be95338`: `SeerrFakeServer`
sloot het fixturegat omdat Seerr toch al tegen een eigen geconfigureerde URL praat.

Actie: de noot uit de registerregel halen.

### 2.5 De PS-9F-verwijzing wijst naar een document dat nooit heeft bestaan

Closure §5 stap 7 verwijst voor WL2 naar `docs/pleya-server-ps9f-favorites-proposal.md`, "nog niet
beoordeeld". Dat pad bestaat niet in de werkboom, komt in geen enkele branch voor in
`git log --all --diff-filter=A`, en de string `PS-9F` staat in precies één bestand, namelijk de
closure zelf.

De WL2-rij die het item bezit noemt PS-9F niet en geeft zijn eigen uitweg: "Sluit hem zodra er een
fixture is die favorieten voert, of leg vast dat de dekking op een echte Jellyfin-aanmelding
hoort." Die tweeweg-exit blijft staan.

Actie: de verwijzing uit closure §5 stap 7 schrappen. Er wordt geen PS-9F-document aangemaakt en
geen PS-9F-functionaliteit gebouwd.

### 2.6 SYS-1, SYS-5 en SYS-6 zijn niet-gesloten umbrella's, geen resterend codewerk

Drie werkitems staan open terwijl hun kinderen een eindstatus dragen:

| Umbrella | Kinderen | Stand op `9342ab7c` |
|---|---|---|
| SYS-1 `IN PROGRESS` | SYS-1a `5cafc10` (DEC-091), SYS-1b `bb79a82`, SYS-1c `ad8c456` | alledrie `DONE` |
| SYS-5 `OPEN` | I18N1 tot en met I18N6, STR1 tot en met STR5 | alle elf `FIXED` |
| SYS-6 `OPEN` | TOK1, TOK2, TOK3 | TOK1 en TOK3 `FIXED`, alleen TOK2 open |

TV0 bepaalt per umbrella of de kinderen de bevinding dekken en hij dus alleen administratief hoeft
te sluiten, met één gerichte controle als tegenwicht: een route die PB-1 nog schendt voor SYS-1,
een verse sweep op hardcoded strings voor SYS-5. Alleen een aangetoond defect gaat als eigen rij
naar TV1. Een brede refactor zonder defect is uitgesloten. SYS-6 heeft geen controle nodig: TOK2 is
zijn enige open kind en staat al bij TV1.

### 2.7 LANG1 en MOC-31 staan op verschillende statussen

Correctieronde `LANG1` staat op `OPEN`, terwijl de rij zelf zegt dat het Verify-scenario groen is
en alleen de hardwareronde nog openstaat. Register `MOC-31` staat op `CODE/SIM CLOSED · HARDWARE
OPEN`, met `tvos.settings.language-preferences.yaml` groen op `a5730f35` en een
`git log a5730f35..main` over de geraakte bestanden zonder resultaten.

Actie: LANG1 naar dezelfde status als MOC-31. Er is geen implementatiewerk meer, alleen
hardwarebewijs, en dat hoort bij closure §7.

### 2.8 De koppeltekenvarianten zijn aliassen, geen aparte ID's

Eenentwintig ID's staan in beide documenten met alleen een koppeltekenverschil. Een steekproef op
zeven paren (`SYS-4`, `OFF-2`, `SRCH-2`, `ACT-2`, `ACT-3`, `PNL-1`, `OVR1b`) laat zien dat het
telkens hetzelfde werkitem is: de correctieronde schrijft `FOC1`, het register schrijft `FOC-1`.
`SYS-4` staat in beide vormen identiek en betekent in beide "gedeelde staat- en lege-presentatie
schaalt niet op TV".

Hier wordt niets hernoemd. Een renaming-diff over 21 ID's levert alleen risico op verweesde
verwijzingen. TV0 legt de conventie vast in de register-kop:

> De correctieronde schrijft historisch `FOC1`, het register `FOC-1`. Dat zijn aliassen van
> hetzelfde werkitem, geen aparte ID's.

### 2.9 CTA1 en HTTP1 krijgen een classificatie, geen fix in deze werkstroom

CTA1 (`test/theme/no_local_cta_shape_override_test.dart` faalt op `main` door een lokale
`shape: const StadiumBorder()` in `mobile_detail_view.dart:265` en `:307`) en HTTP1
(`test/utils/http_lifecycle_test.dart` wisselend rood op de Linux-runner) zijn geen tvOS-werk. Ze
houden `main` wel rood en blokkeren daarmee closure §6.

TV0 classificeert ze als cross-platform gate debt en plant ze. TV1 tot en met TV8 mogen ze niet
opportunistisch meenemen: ze krijgen een eigen klein plan vóór closure-stap 16, tenzij discovery
bewijst dat ze niet meer reproduceren. Een tvOS-subagent raakt `mobile_detail_view.dart` niet.

### 2.10 VER2 blijft DEFERRED

`VER2` (automation-ids escapen geen blokhaken) staat op `DEFERRED`. TV0 bevestigt die status of
motiveert een wijziging, zodat TV8 hem niet als ontbrekende closure behandelt.

### TV0 exit

Elk open item heeft precies één ID, één eigenaar-document en één status. De conflicten uit 2.1 tot
en met 2.7 zijn opgelost in de bestaande documenten, 2.8 tot en met 2.10 zijn vastgelegd als
classificatie. Geen codewijziging.

TV0 wordt uitgevoerd en gecommit vóór TV1 begint. CTX1-3, OFF5, de aliasconventie en de
statuscorrecties zijn dan echte authority voordat een code-agent ermee werkt.

## 3. De gereconcilieerde open-set

Cijfers op deze SHA: de correctieronde telt 132 rijen, waarvan 27 zonder eindstatus en 51 met
`FIXED, hardware open` of een variant daarvan. Die 51 zijn geen werkstroomwerk, die staan al
geparkeerd voor closure §7.

| Item | Plan | Opmerking |
|---|---|---|
| SYS-3a (OVR1a), SYS-4 (STA-1), TOK2, FOC1, SYS-1d | TV1 | systemische fundering; SYS-1d is het aangetoonde defect uit 2.6, gevonden tijdens TV0's controle op SYS-1 |
| SEARCH2, LAND6, LAND7, WL3, WL2, REV1, AGG1, CAT20 | TV2 | CAT20 eerst reproduceren tegen de huidige baseline |
| DET4, CTX1, CTX2, CTX3, MOC-11-goldens | TV3 | de CTX-rijen komen uit TV0 |
| MOC-17, LIVE1 | TV4 | Live TV |
| MOC-22 | TV5 | inloggen en eerste start |
| ACT1, MYP1, OFF5, LIB7-scenario's | TV6 | LIB7-scenario-opruiming, niet LIB7-hardware |
| MOC-18, MOC-33, MOC-20, MOC-21, MOC-23, MOC-24, MOC-25 | TV7 | bewijs voor gebouwde surfaces zonder groen scenario |
| SYS-2 (BACK1), SYS-7, MOC-09/10 Verify, MOC-13/14/15/16 Verify, filters en sorteren, FOC1 (`8d5fa38a`), SYS-1d (`9abdaee5`) | TV8 | de historische Verify-gaten; nieuw werk brengt zijn eigen scenario mee. FOC1 en SYS-1d zijn allebei navigatiegedrag: een journey hoort hier, niet bij TV1, want beide zijn een historisch gat in een al gebouwd oppervlak, geen oppervlak dat TV1 zelf bouwt |
| CTA1, HTTP1 | GATE0, parallel aan TV1 | cross-platform gate debt, zie 2.9 |
| PLR6, SEL1, LIB7-hardware, TOK-1, CAT8, LANG1 (MOC-31), de 51 hardware-open rijen | closure §7 | known deferred-to-§7 dependencies |
| VER2, SYS-1, SYS-5, SYS-6, de LANG1-status | TV0 | administratief reconciliëren, zie 2.6 tot en met 2.8 en 2.10; een aangetoond defect gaat alsnog naar TV1 |

De §7-rij staat er expliciet in zodat TV8 hem niet aanziet voor ontbrekende simulatorclosure.
PLR6 is `HARDWARE ONLY, blokkerend`, SEL1 is `CODE CLOSED, hardware-reproductie niet blokkerend`,
LIB7 is `CODE/SIM CLOSED, HARDWARE OPEN`, CAT8 eindigt op "blijft daarom open tot iemand hem op
hardware naloopt", en MOC-31 draagt al een groen scenario met een `git log`-controle erbij. Geen
van deze zes vraagt nog code- of scenariowerk. LANG1 staat ook bij TV0, maar alleen voor de
statuscorrectie uit 2.7.

## 4. De plannen

De afhankelijkheid is:

```
TV0 ─┬─→ TV1 ──→ {TV2, TV3, TV4, TV5, TV6, TV7} ─┬─→ TV8
     └─→ GATE0 (CTA1, HTTP1) ────────────────────┘
```

GATE0 is geen tvOS-featureplan. Het is de voorwaarde dat `main` groen is voor closure-stap 16, en
het loopt parallel aan TV1. TV8 start niet zolang GATE0 openstaat, anders draait de finale
simulator-suite tegen een rode baseline.

TV0 en TV1 worden als één planningssessie uitgeschreven, met een harde checkpoint ertussen: TV0
eerst uitvoeren en committen, daarna pas TV1 vanaf die gereconcilieerde administratie. TV2 tot en
met TV7 mogen daarna parallelle worktrees zijn.

**Verify hoort bij de wijziging die hem nodig maakt.** TV2 tot en met TV7 zijn eigenaar van de
tests én de nieuwe Verify-scenario's voor alles wat ze zelf bouwen of wijzigen. Een plan dat een
oppervlak bouwt en zijn journey aan TV8 overlaat kan zijn eigen exit niet halen: `CODE/SIM CLOSED`
vraagt per closure §3 een groene run, niet het bestaan van een scenario. TV8 is daarmee geen
inhaalronde voor vers werk, maar de ronde voor de historische gaten, de dekkingsaudit en de finale
suite. Dat lokaliseert een regressie bij de wijziging die hem veroorzaakt.

Elk plan draait de branch-preflight uit closure §4, werkt op een eigen branch vanaf de actuele
`main`, en volgt voor correctieronde-bevindingen de zes stappen bovenaan dat document, inclusief de
negatieve controle die aantoonbaar rood was.

### TV1: systemische fundering

Eigenaren: `lib/screens/main_screen.dart`, `lib/screens/tv/tv_root_shell.dart`,
`lib/widgets/tv/tv_top_navigation.dart`, `lib/utils/layout_constants.dart`,
`lib/widgets/overlay_sheet_geometry.dart`, `lib/widgets/tv/tv_unified_layout.dart`,
`lib/widgets/state_view.dart`, `lib/screens/libraries/state_messages.dart`,
`lib/widgets/tv/tv_content_feed.dart`, `lib/screens/tv/tv_my_pleya_screen.dart:833`.

FOC1 krijgt een contract: verdwijnt een gefocuste topnav-destination, dan kiest de coordinator een
geldige vervanger, verhuist de echte `FocusNode` naar precies die destination, is er nooit meer dan
één focusring, bereikt DOWN de bijbehorende content en blijft BACK consistent. De falende test komt
eerst, tegen de echte `TvRootShell` plus `TvTopNavigation`.

SYS-3a heeft een brede blast radius. De string `scaleForHeight` komt in `lib` maar drie keer voor,
en dat is misleidend: `layout_constants.dart:77` is de definitie, en de twee andere treffers zijn
commentaar. De echte fan-out loopt via `scaleForSize(Size)` en vooral via
`TvLayoutConstants.scaleOf(context)` op regel 97, die in 67 bestanden en 94 call sites wordt
gebruikt, waaronder zoeken, de topnav, de catalogi, detail, het contextmenu, de bronkeuze, de
speler, Mijn Pleya en discovery.

Discovery brengt alle daadwerkelijke runtime-consumers in kaart vóór het schaalcontract wijzigt.
Het doel blijft dat displayschaal display-authoritative is en paneelgeometrie
viewport-authoritative, niet dat alles kleiner wordt tot het past. De bestaande J3-tests leggen de
0,85-klem als contract vast; die spanning wordt met een besluit opgelost, niet met een
stilzwijgende wijziging.

SYS-4 krijgt één TV-bewust presentatiecontract of laat de gedeelde staten op TV de bestaande
catalogusprimitieven gebruiken, en geen derde set TV-empty-widgets naast `TvCatalogEmptyState`.

TOK2 koppelt `Color(0xFF3FBF5F)` aan de bestaande statuskleur-authority, en vervangt hem niet door
een ander magic number.

SYS-1, SYS-5 en SYS-6 komen alleen hierheen als TV0 een aangetoond defect vindt, zie 2.6. Hun
kinderen zijn gesloten, dus zonder zo'n bevinding is er niets te bouwen. TOK2 is de uitzondering:
hij is SYS-6's enige open kind en staat hierboven al.

Exit: FOC1, SYS-4 en TOK2 gesloten; SYS-3a gesloten of met bewijs opgesplitst, met de
consumer-inventarisatie erbij; shell- en goldentests groen.

### TV2: zoeken, landings, catalogus en kijklijst

SEARCH2 is de grootste zichtbare bevinding: de zoekbalk staat verkeerd uitgelijnd, het
resultaataantal hangt los, en content scrolt door de header en de topnav heen. Eerst een fixture met
genoeg resultaten om echt verticaal te scrollen, dan uitzoeken welke widget werkelijk scrollt en wie
de chrome bezit. Een `Padding(top: 24)` is hier geen fix.

LAND6 (een lege landing verbergt de route naar een gevulde catalogus) en LAND7 (de actieve
discovery-rail krijgt geen vaste verticale focuspositie) horen bij dezelfde landing-authority.

WL3 is een duidelijke TDD-taak met een bestaande rode test: bij verwijderen blijft de focus liefst
in hetzelfde rasterslot, anders op de dichtstbijzijnde geldige kaart, bij het laatste item in een
logische lege staat, en nooit nergens.

WL2 is een verificatie-infrastructuurgat, geen featuregat. Onderzoek eerst of er een testnaad rond
`WatchlistSourceFactory` mogelijk is. Kan dat niet, dan wordt vastgelegd dat deze dekking op een
echte Jellyfin-aanmelding hoort. Er wordt geen favorietenbron gebouwd.

REV1 is release-kritiek en geen polish: bij Apple Review toonde Home met Jellyfin wel content
terwijl Films en Series leeg bleven en een concrete bibliotheek niet zichtbaar was. Dat krijgt een
eigen root-cause-taak langs library projection, discovery projection, zichtbaarheid, filtering,
unified identity en Jellyfin capability detection.

AGG1 vraagt geen nieuwe merge-architectuur, alleen het bewijs dat een echte Plex- plus
Jellyfin-titel met een sterke externe ID één unified item wordt, de juiste bronbadge toont en
correct activeert.

CAT8 hoort hier niet. De rij is `DEELS GEDEKT door CAT10` en eindigt met de vaststelling dat hij
openblijft tot iemand hem op hardware naloopt. Er is geen codewerk meer, dus hij staat bij de
§7-groep.

CAT20 (Alle films toont niet alle servers, vermoedelijk het opgeslagen ingekorte bronfilter in
`tv_unified_catalog_screen.dart:319-329` of `source_cursor.dart:62-86`) staat op "Michel meldt
opgelost, niet geverifieerd". Eerst reproduceren tegen de huidige `main`, dan pas beslissen.

### TV3: detail, bronkeuze en contextmenu

DET4 (niet-geselecteerde seizoentekst rendert dubbel of verschoven) begint met een minimale
reproductie, en pas daarna een fix. Impeller, focused tegen unfocused, opacity, tekststijl,
transforms, rastercache en animatie zijn de kandidaten.

CTX1 tot en met CTX3 sluiten de drie contextmenu-gaten met de canonieke metadata- en
watch-state-helpers, zonder een tweede formatteringslaag ernaast.

De acht gewijzigde MOC-11-goldens worden geregenereerd via de Linux-route in `goldens.yml`, niet
lokaal op macOS.

De historische detail-Verify voor MOC-09 en MOC-10 komt in TV8. De journeys voor wat TV3 zelf
wijzigt, DET4 en CTX1-3, horen bij TV3.

### TV4: Live TV

MOC-17 is een van de twee oppervlakken die echt nog niet gebouwd zijn. Authority: mockup 17 en PB-8.
Eigenaar: `lib/screens/livetv/live_tv_screen.dart`.

Bestaande functionaliteit blijft: Nu op TV, Gids, Opnames, kanaal- en programmaselectie, de
bestaande live playback en de bestaande gids- en opname-acties.

LIVE1 is de kern: `PlatformDetector.shouldUseSideNavigation` kan nog tot twee navigatiesystemen
leiden. tvOS krijgt precies één shell en één topnav. De legacy-navigatie gaat er pas uit nadat tests
aantonen dat de unified shell de eigenaar is.

TV4 levert zijn eigen Verify-journey: Live TV openen, Nu op TV, Gids, Opnames, een kanaal openen,
terug, een overlay openen en sluiten, de topnav verlaten en opnieuw bereiken.

Exit: `CODE/SIM CLOSED · HARDWARE OPEN`, met die run groen.

### TV5: inloggen en eerste start

MOC-22, het tweede ontbrekende oppervlak. Eigenaren beginnen bij `lib/screens/auth_screen.dart`,
`lib/services/account_ui_actions.dart` en `lib/main.dart`. De auth-architectuur wordt niet
herschreven en de bestaande iOS- en macOS-auth verandert niet.

Te dekken standen: eerste start, geen sessie, inloggen, laden, fout, opnieuw proberen, geslaagde
sessie, server deels of volledig offline, de profielpoort waar die geldt, tekstinvoer met de Siri
Remote en het systeemtoetsenbord, en terug waar dat mag. De automation hooks rond `AuthScreen`
bestaan al en worden hergebruikt.

Het resultaat is een echte TV-compositie, geen vergrote mobiele layout.

Exit: `CODE/SIM CLOSED · HARDWARE OPEN`, met een eigen Verify-journey over de auth-flow.

### TV6: Mijn Pleya, Activiteit, offline en bibliotheken

ACT1 is eerst een contractbesluit en pas daarna code. Vandaag hangt de Activiteit- en
Tautulli-tegel aan `MultiServerManager.isOwnerOrAdmin`, en "mag deze gebruiker deze activiteit
zien" is een andere vraag dan "is deze gebruiker serverbeheerder". Het voorkeurscontract is een
expliciete capability, maar alleen als dat in het bestaande securitymodel past: Tautulli bevat
serverbrede informatie, dus rechten worden niet verzwakt om een fixture groen te krijgen. De fake
Tautulli-server staat klaar (`f72466f2`, `0aa71164`) voor zodra het besluit er is.

OFF5 (voorheen de tweede OFF2) mag de zojuist bewust gekozen Downloads- of Kijklijst-destination
niet overschrijven bij een offline statuswijziging. De test loopt over de echte keten
`MainScreen` naar offline change naar user destination naar destination recompute.

MYP1 volgt na ACT1 en de kijklijstverificatie, als volledige regressieflow over sectieraster,
kijklijst, activiteit, downloads, bibliotheken, instellingen, terug en focusherstel.

LIB7-opruiming: `tvos.my-pleya.library-chooser` en `tvos.library.sort` testen vervangen UI. Per
scenario een besluit, ofwel intrekken omdat het contract vervangen is, ofwel herschrijven tegen
bronbeheer. Een closure-suite draagt geen bewust verouderde rode scenario's. De hardware-acceptatie
van LIB7 zelf hoort bij §7.

### TV7: speler en de al gebouwde meta-oppervlakken

Dit is bewijs, geen herontwerp: MOC-18, MOC-33, MOC-20, MOC-21, MOC-23, MOC-24 en MOC-25. Per
oppervlak gerichte tests groen, een Verify-scenario, een simulatorrun met bundel, een screenshot
tegen de northstar, en dan `HARDWARE OPEN`.

Bij de speler blijft elke functie bestaan: aflevering en hoofdstuk, afspeelinstellingen,
beeldverhouding, audio en ondertitels, het infopaneel, de kwaliteitssamenvatting, en Menu of terug.
MOC-33 blijft het enige spelermenu op TV. PLR6 blijft hardware-only tot §7.

MOC-31 en LANG1 staan hier niet. Ze zijn gebouwd (`eae19cb4`, `a9a50ad9`, `a5730f35`), het
scenario `tvos.settings.language-preferences.yaml` is groen op `a5730f35`, en de geraakte bestanden
zijn sindsdien niet gewijzigd. TV8 draait het scenario mee in de finale suite, de acceptatie zelf
hoort bij §7.

### TV8: Verify-dekking en visuele acceptatie

TV8 bezit de historische Verify-gaten, niet de journeys van vers werk. Dat onderscheid bepaalt de
omvang: wat TV2 tot en met TV7 bouwen brengt zijn eigen scenario mee, TV8 haalt in wat al gebouwd
was toen er nog geen journey bij hoorde.

Ook zo blijft het een bouwronde. Er zijn vandaag 34 tvOS-scenario's in `pleya_verify/scenarios/`.
Detail, zoeken, filters, sorteren, kijklijst, aanvragen, activiteit, collectie, persoon, bronkeuze
en contextmenu hebben er geen enkele. Het plan dat hieruit volgt breekt dat op in losse taken per
oppervlak.

MOC-09 en MOC-10 staan hier expliciet bij. Ze mogen in het register `CODE/SIM CLOSED · HARDWARE
OPEN` blijven, maar hun ontbrekende journeys horen bij TV8. Anders ziet een uitvoerende agent
"hardware open" en slaat de detail-Verify over. Hetzelfde geldt voor MOC-13, MOC-14, MOC-15 en
MOC-16, en voor filters en sorteren.

SYS-2 (BACK1) en SYS-7 (automation-ids en journeys per heringericht oppervlak) horen hier ook.
SYS-7 is in feite de opdracht van dit plan.

Daarna de dekkingsaudit: welk geldend oppervlak heeft nog geen groene journey, en welk scenario
test nog vervangen UI. Visuele acceptatie per oppervlak gaat langs huidige screenshot,
goedgekeurde northstar, verschil, besluit, fix of opnieuw draaien. Er wordt niet opnieuw ontworpen.

De finale suite sluit af: `flutter analyze`, `scripts/ci_checks.sh`, de TV-widget-, navigatie- en
focustests, de goldens via `goldens.yml`, en de volledige Verify-suite inclusief de scenario's die
eerdere plannen al groen opleverden.

## 5. Buiten scope

| Niet in deze werkstroom | Waarom |
|---|---|
| PS-7 external IDs voor cross-backend merge | Pleya Server-roadmap, en de huidige fase is PS-5 |
| PS-9F favorieten bouwen | te grote scope voor een fixtureprobleem, zie 2.5 |
| I17 Android TV hardware-back | hoort bij de cross-TV-hardwaregate |
| alle iOS-implementatiewerk | closure §5 stappen 2, 4, 5, 8, 10 tot en met 14, 17 |
| de hardware-eindronde | closure §7, één SHA samen met iOS |
| TestFlight | closure §8 |
| TA-1 t/m TA-13 tokenbacklog | nog niet beoordeelde auditbevindingen onder `docs/tvos-redesign-register.md`'s "Tokenafwijkingen uit de audit"; promoveren tot workitem is een scopebesluit dat buiten TV0's mandaat (documentatie reconciliëren) valt |

CTA1 wordt niet in tvOS-code opgelost. De fix ligt in `mobile_detail_view.dart` of in de
`allowed`-lijst van de test met een reden erbij, en dat is een mobiel besluit.

## 6. Waar dit document op rust

Alles hierboven is tegen `github/main` = `9342ab7c` nagegaan. De controleerbare stappen:

```bash
git rev-parse github/main                                 # 9342ab7c
grep -c '' docs/tvos-fysieke-correctieronde.md            # 4313 regels
grep -cE '^\| *[A-Z][A-Z0-9-]{1,9} *\|' docs/tvos-fysieke-correctieronde.md   # 133, incl. kop
grep -rl 'scaleForHeight' lib                             # 3, waarvan 1 definitie en 2 commentaar
grep -rl 'scaleOf' lib | wc -l                            # 67 bestanden, 94 call sites
grep -n '3FBF5F' lib/screens/tv/tv_my_pleya_screen.dart   # regel 833
ls pleya_verify/scenarios/ | grep -c '^tvos'              # 34
git log --all --diff-filter=A --name-only -- '*ps9f*'     # leeg
grep -rln 'PS-9F' docs/                                   # alleen unified-2026-closure.md
```

Een latere lezer die een van deze uitkomsten anders ziet, leest een ander punt in de tijd en moet de
mapping in hoofdstuk 3 opnieuw tegen de registers leggen voordat hij erop bouwt.
