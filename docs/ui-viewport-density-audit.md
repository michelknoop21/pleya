# UI viewport- en density-audit

Status 23 september 2026: **in uitvoering** (registeritem DENS1). Een bestaande scenariofile is geen actuele PASS. Alleen de genoemde, gelezen evidencebundle sluit een cel.

## Meetcontract

Per snapshot bewaren we apparaat, logische rootviewport, DPR, safe area, Pleya-schaal en interne logische maat, fysieke compositorpixels, invoerroute, zichtbare landmarks en screenshot. Een oppervlakte blijft OPEN als de interactie of visuele capture ontbreekt. Fysieke pixels zijn geen extra layoutruimte: een Apple TV met 3840×2160 output kan een rootviewport van 1920×1080 @2× hebben.

## Uitvoermatrix

| Platform | Klasses en modi | Stand |
|---|---|---|
| tvOS | Apple TV 4K 1080p en 2160p output; D-pad/focus, overscan; hardware voor touch-surface | beide shell-smokes, gevulde filmrail, app-focusrand en zes Mijn Pleya-subpagina's op beide outputs PASS; overige OPEN |
| iPhone | SE, representatief Pro, grootste ondersteunde; Home portret, spelerlandschappen | SE, 15 Pro en 17 Pro Max Home portret PASS; iPhone 17e, 17 Pro en 18 Pro Max vijf schermen incl. Home PASS (7 okt); overige OPEN |
| iPadOS | mini en grote Pro; portret/landschap; full screen, ondersteunde Split View/Stage Manager-maten | mini en Pro portret Home, Media, Zoeken, Mijn Pleya en Instellingen-boven PASS; mini Home landschap gemeten; verdere audit uitgesteld tot redesign |
| macOS | compact 900×600, 1280×800, 1440×900, 1920×1080 logisch; Retina | Discover-shell op alle vier PASS; overige schermen OPEN |

De iOS-app ondersteunt iPhone en iPad (`TARGETED_DEVICE_FAMILY = "1,2"`). Gedeelde responsive breekpunten liggen bij 600, 900, 1200 en 1600 logische punten. Voor macOS is geen formele minimumvenstermaat gevonden; 900×600 is daarom een compacte proefmaat, geen productminimum.

## Surface-inventaris

| Familie | tvOS | iPhone | iPadOS | macOS |
|---|---|---|---|---|
| Eerste start, auth, profielgate/-wissel | scenario's, matrix OPEN | OPEN | OPEN | OPEN |
| Shell, Home, Series, Films | 1080p en 2160p shell en Films-rail PASS; overige OPEN | SE, 15 Pro en 17 Pro Max Home portret PASS; SE en 15 Pro Series/Films PASS; 17e, 17 Pro en 18 Pro Max Home, Series en Films PASS | mini en Pro Home portret PASS; rest OPEN | Discover vier venstermaten PASS |
| Catalogus, bibliotheken, zoeken | scenario's, matrix OPEN | 15 Pro filmcatalogus, filtervel en zoeken PASS; overige OPEN | mini en Pro Media/Zoeken portret PASS; overige OPEN | OPEN |
| Media-, collectie-, persoons- en playlistdetail | deels scenario's, matrix OPEN | SE en 17 Pro Max filmdetail PASS met leesbaarheidsbevinding; overige OPEN | OPEN | OPEN |
| Mijn Pleya, kijklijst, activiteit, downloads en bronnen | zes fixturebereikbare subpagina's op 1080p en 2160p PASS; conditionele tegels OPEN | SE, 15 Pro, 17e, 17 Pro en 18 Pro Max Mijn Pleya-hub PASS; subpagina's OPEN | mini en Pro Mijn Pleya-hub portret PASS; subpagina's OPEN | OPEN |
| Instellingen en subpagina's | deels scenario's, matrix OPEN | SE Instellingen boven/onder, 15 Pro, 17e, 17 Pro en 18 Pro Max boven PASS; subpagina's OPEN | mini en Pro Instellingen-boven portret PASS; overige OPEN | OPEN |
| Aanvragen/Seerr | deels scenario's, matrix OPEN | scenario's, matrix OPEN | OPEN | OPEN |
| Live TV, gids, opnames en programmasheets | fixture zonder tuner; OPEN | OPEN | OPEN | OPEN |
| Speler, controls, panelen en prompts | deels scenario's; hardware OPEN | OPEN | OPEN | OPEN |
| Filters, sortering, bronkeuze, contextmenu, PIN en taal-sheets | deels scenario's, matrix OPEN | deels scenario's, matrix OPEN | OPEN | OPEN |
| Empty/loading/error/offline en softwaretoetsenbord | verspreid, matrix OPEN | verspreid, matrix OPEN | OPEN | OPEN |
| Native vensterchrome, resize, full screen en multi-window | n.v.t. | multi-scene OPEN | multi-window OPEN | resize PASS, overige OPEN |

## Verse evidence

### macOS Discover-shell

- Scenario: `macos.viewport-density`; bundle: `.build/pleya-verify/macos-viewport-density-1790186837101/` in de geïsoleerde worktree.
- Resultaat: PASS op commit `6052e824a82e7edf48cfa5f87f485c2c4c391f7e`, dirty worktree.
- Logisch/fysiek: 900×600 → 1800×1200; 1280×800 → 2560×1600; 1440×900 → 2880×1800; 1920×1080 → 3840×2160. Allemaal DPR 2, safe area 0.
- De compositorbeelden en de viewportmetingen zijn per maat gelezen. Header, sidebar, Discover-actie en eerste bruikbare content blijven bereikbaar. Bij 900×600 staat de tweede rail onder de vouw; dat is normale verticale scrollruimte en geen overflowclaim. Grote vensters tonen meer zwarte, momenteel ongevulde railruimte; dit vraagt een productmatige density-beoordeling per gevulde contentstaat, niet automatisch een fout.
- De macOS-driver gebruikte eerst `screencapture`; op deze multi-displayhost weigerde dat een geldig niet-gemaximaliseerd Flutter-venster. De run gebruikt nu ScreenCaptureKit met selectie op het eigen proces. Voorafgaande FAILED-runs zijn diagnostiek, geen layoutfout.

### iPhone SE Home portret

- Scenario: `ios.viewport-density.home`; bundle: `.build/pleya-verify/ios-viewport-density-home-1790188421236/`.
- Portretstap en screenshot PASS: 375×667 logisch, 750×1334 fysiek, DPR 2, safe area boven 20. Header, zoekknop, eerste bruikbare content en tabbar zijn binnen de viewport; zoekknop voldoet aan het 44-punts tapdoel.
- De hele scenario-run is FAILED bij de eerste landschapsrotatie: `osascript` heeft op deze host geen toestemming om toetsaanslagen te versturen (1002). Dit is een bedieningsgat, geen productfout. De Simulator-toolbar kan handmatig via de UI roteren; voor een herhaalbare automatische run is nog een toegestane oriëntatieroute nodig.

Een afzonderlijke portret-only run van `ios.viewport-density.home` is inmiddels volledig PASS: `.build/pleya-verify/ios-viewport-density-home-1790189190839/`. De rotatieproef op de iPhone SE bleef met opzet portret (375×667); `OrientationHelper.restoreDefaultOrientations` vergrendelt de iPhone-shell in portret. Dat is geen densitydefect. Liggend is voor de speler relevant; het shell-landschapsscenario geldt voor iPad en heeft een verplichte `assert_viewport`.

### iPhone SE Instellingen

- Scenario: `ios.settings.northstar`; bundle: `.build/pleya-verify/ios-settings-northstar-1790188941710/`.
- PASS voor bovenste instellingen en het onderste deel na twee echte touch-drags. De screenshot `settings-bottom.png` toont onder meer Servers en de vaste tabbar. De assertions controleren de zichtbaarheid van de relevante tegels en een tapdoel van minimaal 44 punten.
- Een eerdere diagnostische run met drie drags overschoot het onderdeel Servers; dat was een scenariofout en is niet als productdefect geteld.

### iPhone 15 Pro Home portret

- Scenario `ios.viewport-density.home`, bundle `.build/pleya-verify/ios-viewport-density-home-1790189812889/`: PASS op 393×852 logisch, DPR 3, 1179×2556 fysieke pixels.
- De screenshot is gelezen: header, Series/Films-acties, eerste rails en vaste tabbar zijn zichtbaar zonder overlap of afsnijding. De eerste rij toont één fixturetitel; andere rails zijn deels onder de vouw, zoals verwacht bij verticaal scrollen.

### iPhone 17 Pro Max Home portret

- Hetzelfde scenario, bundle `.build/pleya-verify/ios-viewport-density-home-1790189941989/`: PASS bij 440×956 logisch, 1320×2868 fysiek, DPR 3.
- De screenshot is gelezen: de extra breedte toont drie kaarten in de latere rail en meer verticale inhoud, terwijl header en tabbar vrij blijven. Geen zichtbare clip of disproportionele schaal ten opzichte van de 15 Pro.

### iPhone 15 Pro navigatie en schermen

- Scenario `ios.viewport-density.navigation`, bundle `.build/pleya-verify/ios-viewport-density-navigation-1790190473875/`: PASS voor Home, Series, Films, Mijn Pleya en de bovenkant van Instellingen binnen één echte tikreis. Per scherm zijn compositorbeeld en zichtbare landmarks gecontroleerd.
- De vijf screenshots zijn gelezen. Headers en ondernavigatie blijven zichtbaar; Series en Films tonen de eerste rail. Op Mijn Pleya worden de secundaire teksten in de twee halve-breedte bronkaarten met ellips afgekapt (`Media, collecties, afsp…`, `Verbindingen en lokale…`). De primaire titels en acties blijven bruikbaar, maar dit is een leesbaarheidsvraag voor het productontwerp bij kleine breedtes, nog geen bewezen functionele clip.
- Hetzelfde scenario is op de iPhone SE PASS in `.build/pleya-verify/ios-viewport-density-navigation-1790190549928/`. Alle vijf screenshots zijn gelezen. De smalle telefoon toont eveneens afgekorte subteksten in de twee bronkaarten, maar geen afgesneden primaire titel of onbereikbare navigatie. De Films-rail toont bewust een gedeeltelijke derde poster als horizontale-scrollhint.

### iPhone 15 Pro filmcatalogus en filtervel

- Het actuele `ios.catalog.northstar` is PASS in `.build/pleya-verify/ios-catalog-northstar-1790191101726/`. De catalogus toont drie posterkaarten met titel/jaar, chiprij en resultaatteller binnen de viewport; het filtervel toont Servers, Bibliotheken en een bereikbare toepasknop. Beide compositorbeelden zijn gelezen.
- Twee oude assertions vroegen om een box op een puur structurele gridmarker en om filtercategorieën die de Pleya Server-fixture niet ondersteunt. De scenarioassertions meten nu de echte eerste kaart en alleen de beschikbare categorieën. De voorgaande FAILED-bundles waren testcontractproblemen, geen product-layoutfouten.

### iPhone 17 Pro Max filmdetail

- Scenario `ios.detail.northstar`, bundle `.build/pleya-verify/ios-detail-northstar-1790191119051/`: PASS voor de route naar filmdetail; de screenshot toont kop, hoofdacties en de vier secundaire acties zonder geometrische overflow.
- Leesbaarheidsbevinding: de labels van minimaal twee secundaire acties worden zelfs op 440 punten breed afgekapt (`Aan kijklijst to…`, `Markeer als g…`). De iconen en acties zijn zichtbaar, maar de functie is niet volledig uit de tekst af te lezen. Dit verdient een afzonderlijke ontwerp-/toegankelijkheidsbeslissing (bijvoorbeeld labels laten afbreken of een andere actie-indeling), niet een blinde schaalverlaging.
- Op de iPhone SE is hetzelfde scenario PASS in `.build/pleya-verify/ios-detail-northstar-1790191169627/`; de gelezen screenshot laat nog kortere afgebroken labels zien (`Aan kijklijst…`, `Markeer al…`). De bevinding is dus reproduceerbaar op beide uiteinden van de gekozen telefoonmatrix.

### iPhone 15 Pro zoeken

- Scenario `ios.search.text-input`, bundle `.build/pleya-verify/ios-search-text-input-1790191169626/`: PASS. Een via de echte invoerroute getypte zoekterm toont een filmtreffer; het compositorbeeld laat zoekveld, filters, resultaat en tabbar zonder overlap zien.

### iPad mini Home portret

- Scenario: `ipados.viewport-density.portrait`; bundle: `.build/pleya-verify/ipados-viewport-density-portrait-1790189574788/`.
- PASS: 744×1133 logisch, 1488×2266 fysieke compositorpixels, DPR 2. De eerste rail en ondernavigatie blijven binnen de viewport. De screenshot is gelezen: de beperkte fixture bevat slechts één item in de eerste twee rails en oogt daardoor rechts leeg; dit is nog geen bewijs van verkeerd kaartformaat bij een gevuld catalogusaanbod.
- Het eerdere iPhone-scenario faalde op de iPad omdat `home.header` uitsluitend op de telefoonshell bestaat. De iPad heeft een andere bovenbalk en navigatie; daarom zijn aparte iPad-scenario's toegevoegd.

### iPad Pro 13-inch Home portret

- Hetzelfde scenario, bundle `.build/pleya-verify/ipados-viewport-density-portrait-1790189675593/`: PASS bij 1032×1376 logisch en 2064×2752 fysieke pixels, DPR 2, safe area 32 boven / 20 onder.
- De screenshot is gelezen: geen afsnijding van rails of ondernavigatie. Ook hier laat de kleine fixture grote ongebruikte rechterruimte; een gevulde fixture is nodig voor een definitief oordeel over dichtheid, niet voor de clip-asserties.

### iPad mini en Pro navigatie portret

- Scenario `ipados.viewport-density.navigation`: PASS op mini in `.build/pleya-verify/ipados-viewport-density-navigation-1790191435507/` en op Pro in `.build/pleya-verify/ipados-viewport-density-navigation-1790191467914/`. Beide runs leggen Home, Media, Zoeken, Mijn Pleya en Instellingen-boven vast. Alle tien compositorbeelden zijn gelezen; de gemeten viewport bleef portret en de gecontroleerde navigatie/tegels lagen binnen beeld.
- De mini toont in Media drie gevulde fixturekaarten op één rij; de Pro houdt dezelfde drie kaarten met meer lege rechterruimte. De fixture begrenst hier de inhoud, zodat dit geen automatisch densitydefect is. Mijn Pleya laat op beide iPads de volledige secundaire teksten in de twee bronkaarten zien, anders dan op de iPhones. Instellingen is op de Pro bewust in een gecentreerde, begrensde kolom weergegeven; op de mini benut het bijna de volle breedte.
- Zoeken opent op de mini met softwaretoetsenbord en op de Pro zonder zichtbaar toetsenbord (Simulator-invoertoestand); de lege zoekstaat en tabbar blijven in beide beelden bruikbaar. Een eerste mini-run faalde op `minimumTapTarget(nav.search)`: de automatiserings-ID omvat alleen het 24×32-icoon, niet het volledige `NavigationDestination`-tikvlak. De werkende echte tik en de code bevestigen dat dit een meetcontractfout was; het scenario eist nu alleen zichtbaarheid van dat icoon. Een aparte hit-area-meting blijft wenselijk.

### iPad mini Home landschap — audit gepauzeerd voor redesign

- Na ontgrendeling en handmatige Simulator-rotatie is `ipados.viewport-density.landscape` PASS in `.build/pleya-verify/ipados-viewport-density-landscape-1790196261725/`: de app meldt 1133×744 logische punten, DPR 2 en safe area 32 boven / 20 onder. De Home-landmarks en navigatie vallen binnen de gemeten viewport.
- Het `simctl`-compositorbeeld toont liggende app-inhoud in een staand opgeslagen PNG-raster van 1488×2266; de captureoriëntatie moet dus afzonderlijk van de app-viewport worden gelezen. Dit is geen bewijs voor overige iPad-schermen of Stage Manager.
- Michel heeft verdere iPad-controle gestopt omdat de iPad-UI nog een redesign krijgt. De grote iPad-landschapsrun is tijdens de build afgebroken en telt niet als PASS; beide iPad-simulators zijn daarna afgesloten. De rest van de iPad-matrix blijft OPEN tot na de redesign.

### iPhone 17e, 17 Pro en 18 Pro Max: Home en navigatie (iOS 27)

- Scenario's `ios.viewport-density.home` en `ios.viewport-density.navigation`, beide PASS op commit `2e5e21d0` (dirty: lokale `ARCHS`-regel voor de Xcode 27-lipo-valkuil). Het manifest noemt nu het concrete toestel en de runtime (`iOS-27-0`).
- iPhone 17e: 390×844 logisch @3, safe area boven 47, onder 34. Bundles `ios-viewport-density-home-1791382151187` en `ios-viewport-density-navigation-1791382245302`.
- iPhone 17 Pro: 402×874 @3 (1206×2622 px), safe area boven 62, onder 34. Bundles `ios-viewport-density-home-1791381734986` en `ios-viewport-density-navigation-1791382032461`.
- iPhone 18 Pro Max: 440×956 @3, safe area boven 62, onder 34. Bundles `ios-viewport-density-home-1791382285760` en `ios-viewport-density-navigation-1791382361522`.
- Per toestel zijn Home, Series, Films, Mijn Pleya en de bovenkant van Instellingen vastgelegd. Gelezen: Mijn Pleya op de 17e en 17 Pro, Home op de 17 Pro, Instellingen-boven op de 18 Pro Max. Header, rails, tabbar en lijstrijen blijven binnen de viewport en zonder overlap.
- Bevinding die terugkomt: in de twee halve-breedte kaarten op Mijn Pleya worden de ondertitels afgekapt (`Mediabibliotheken beh...`, `Verbindingen en lokal...` op de 17e; `Connections and local ...` op de 17 Pro). Titels en tap-doelen blijven bruikbaar. Het is een ontwerpbeslissing, geen layoutfout.
- Begrenzing: dit sluit de vijf navigatieschermen (Home, Series, Films, Mijn Pleya, Instellingen-boven) op deze drie klassen. Landschap blijft OPEN, omdat de iPhone-shell in portret vergrendeld is. Een SE-klasse en 15 Pro zijn niet meer als simulator beschikbaar onder Xcode 27, de 17e is de kleinste beschikbare klasse.

### tvOS 4K shell

- Scenario `tvos.smoke.boot`, eerdere bundle in de hoofdcheckout: `.build/pleya-verify/tvos-smoke-boot-1790183145983/`.
- PASS: compositor 3840×2160, root 1920×1080 @2×, Pleya-schaal 1,85, interne logische maat 1037,84×583,78, safe area 0. Dit bewijst shell en topnavigatie, niet de volledige tvOS-inventaris.
- De voorafgaande lege screenshotrun (`tvos-smoke-boot-1790182966526`) is terecht FAILED en telt niet als beeldbewijs.
- Een verse run in dezelfde geïsoleerde worktree is ook PASS: `.build/pleya-verify/tvos-smoke-boot-1790190342064/`. De gemeten 1920×1080 rootviewport @2×, 3840×2160 compositorpixels en schaal 1,85 zijn gelijk aan de eerdere 4K-run.

### tvOS 1080p shell

- Een aparte Apple TV 4K (3rd generation) “at 1080p” is aangemaakt. `scripts/tvos_sim.sh doctor --json` bevestigde `idb` als invoerroute; het scenario `tvos.smoke.boot` is daarna PASS in `.build/pleya-verify/tvos-smoke-boot-1790189831484/`.
- Compositorbeeld 1920×1080, rootviewport 1920×1080 @1×, Pleya-schaal 1,85 en interne logische maat 1037,84×583,78. Safe area 0. Het beeld is gelezen: navigatie en Home-aanpassenactie zijn zichtbaar; de grote zwarte inhoudsruimte hoort bij de lege smoke-fixture en zegt niets over catalogusdichtheid.
- Vergeleken met de verse 2160p-run is de **logische layout identiek**; de fysieke rasterdichtheid verschilt (1× versus 2×).

### tvOS gevulde filmrail 1080p

- Scenario `tvos.discovery.density`, bundle `.build/pleya-verify/tvos-discovery-density-1790190384739/`: PASS. De D-pad-route navigeert naar Films; de asserts meten zes volledige tegels en een zevende die rechts doorloopt.
- De screenshot is gelezen: de rij heeft zes volledig zichtbare tegels en een afgesneden aanzet van de zevende, zonder visuele clip van de volledige tegels. Dit is inhoudelijk bewijs boven op de lege shell-smoke.
- De 4K-tegenhanger is inmiddels ook PASS: `.build/pleya-verify/tvos-discovery-density-1790190460044/`. De gelezen screenshot toont dezelfde zes-plus-een compositie op een 3840×2160 raster. De logische layout verandert dus niet met de hogere outputresolutie.

### tvOS focus en app-veilige rand 1080p

- Scenario `tvos.discovery.overscan`, bundle `.build/pleya-verify/tvos-discovery-overscan-1790190466583/`: PASS. De focusring is na D-pad-navigatie links én verder rechts in de rail binnen de door Pleya getekende veilige rechthoek gemeten.
- Beide screenshots zijn gelezen: de uitvergrote tegel en de ring blijven geheel in beeld; de rij schuift om ruimte te maken. Dit bewijst de software-insets, niet eventuele overscan door een fysiek televisiepaneel.
- De gelijksoortige 4K-run is na het begrenzen van `idb` ook PASS in `.build/pleya-verify/tvos-discovery-overscan-1790194571753/`. Beide compositorbeelden zijn gelezen: de focusring blijft links en verder rechts binnen de app-veilige rand op 3840×2160 output. De eerdere hangende `idb connect` was een onbeperkte toolaanroep, geen productfout. Verify probeert nu hooguit twee begrensde verbindingen en weigert een stille AppleScript-fallback.
- De eerste 4K-run van `tvos.my-pleya.sections` in `.build/pleya-verify/tvos-my-pleya-sections-1790194967914/` bereikte Logs maar verloor daarna de verbinding door een gelijktijdige installatie van dezelfde Verify-bundle op dezelfde UDID door een andere worktree. Een herhaling op een aparte Apple TV 4K-simulator is volledig PASS in `.build/pleya-verify/tvos-my-pleya-sections-1790195837397/`. Alle zes geopende-subpagina-compositorbeelden zijn gelezen: Bibliotheken, Servers, Samen Kijken, Instellingen, Logs en diagnose en Over; de focusrand en primaire inhoud blijven in beeld. Elk snapshot meet 1920×1080 rootpunten, DPR 2, Pleya-schaal 1,85 en 3840×2160 fysieke pixels. De drie conditionele tegels buiten deze fixture blijven OPEN. De tijdelijke 4K-simulator is na het uitlezen afgesloten.

### tvOS Mijn Pleya-subpagina's 1080p

- Scenario `tvos.my-pleya.sections`, bundle `.build/pleya-verify/tvos-my-pleya-sections-1790190741546/`: PASS voor Bibliotheken, Servers, Samen Kijken, Instellingen, Logs en diagnose en Over; per subpagina zijn openen, één D-pad-stap en terugkeer vastgelegd.
- De geopende en na-omlaag-screenshots zijn gelezen. Koppen, kaarten en focusring blijven binnen de 1080p-viewport; langere instellingen- en loglijsten vragen verder scrollen. De fixture heeft geen kijklijst-, aanvragen-, downloads- of activiteitstegel; die cellen blijven OPEN.
- De eerste run faalde doordat het scenario na binnenkomst twee keer omlaag drukte en Bibliotheken oversloeg. De actuele focusroute vraagt één druk; het scenario is daarop gecorrigeerd, waarna de hele run PASS was.

## Resterend werk en grenzen

1. Controleer de overige tvOS-oppervlakken op de 2160p-output; shell, gevulde Films-rail, focusrand en zes Mijn Pleya-subpagina's zijn nu op beide outputs vastgelegd. Beoordeel rasterkwaliteit apart.
2. Controleer resterende familieschermen, tekstinvoer, sheets, detail, speler en onderste scrolldelen afzonderlijk op de relevante formaten; een PASS op Home sluit die cellen niet.
3. Herneem de iPad-matrix pas na de iPad-redesign. Een handmatig vooraf geroteerde iPad mini levert nu wel een gemeten liggende app-viewport en compositorbeeld; de grote iPad, overige schermen, Split View/Stage Manager en spelerlandschap blijven OPEN. Automatische hosttoetsrotatie is nog niet bewezen en blijft afhankelijk van macOS Accessibility-toestemming.
4. Split View/Stage Manager en fysieke Apple TV remote/overscan/speler vragen een aparte toestel- of venstermodusrun. De simulator kan touch-surfacegedrag niet bewijzen.
5. Sluit alleen met een compositorbeeld, gemeten viewport en een relevante landmark-/focus-/tapassertie. De Pleya Verify-runner heeft nu device-identiteit, fysieke PNG-afmetingen, macOS-resize en touch-drag in het bewijscontract.
