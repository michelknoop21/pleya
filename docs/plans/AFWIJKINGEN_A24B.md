# A-24b: afwijkingen tussen northstar en build

Roadmap: A-24 (vervolgronde A-24b). Deze lijst loopt [`VISUELE_ACCEPTATIE.md`](../assets/a24b-northstars/VISUELE_ACCEPTATIE.md) regel voor regel langs: per controlepunt het oordeel, wat de build anders doet, waarom, en wie het verschil heeft geaccepteerd of dat het nog openstaat. De beelden staan in [`docs/assets/a24b-vergelijking/`](../assets/a24b-vergelijking/README.md), de route-voor-route-pariteit in [`PARITEIT_A24B.csv`](PARITEIT_A24B.csv).

Oordelen: **Match** (de build toont wat de northstar toont), **Match met verschil** (structuur en inhoud kloppen, een detail wijkt af), **Afwijking** (zichtbaar anders), **Voorwaardelijk** (de functie bestaat, maar de code toont hem in de vastgelegde staat niet). "Open" betekent dat Michel er nog niet over besloten heeft. Alle beelden komen uit simulators; niets is op een echte iPhone of Apple TV bekeken.

## Instellingen op Apple TV

Bladen: `03-appletv-instellingen-donker.jpg`, `04-appletv-instellingen-licht.jpg`, `appletv-instellingen-*.jpg`.

| Controle | Oordeel | Wat de build anders doet, en waarom | Besluit |
| --- | --- | --- | --- |
| Categorieën | Match met verschil | De rail heeft Weergave, Afspelen, Taal en ondertitels, Bibliotheken, Home aanpassen en Koppelingen met hun iconen, daarna Big P (alleen in een build met Big P) en Geavanceerd. Elke oude route is bereikbaar, zie de tvOS-rijen in de pariteitstabel. Trackers, Seerr, Tautulli, Pleya Share-host en Over Pleya openen een eigen pagina zonder rail, één niveau dieper dan de reeks tekent. | Volgorde en inhoud volgen de northstar. De diepere pagina's: open. |
| Header | Match met verschil | `Instellingen` en `Jouw kijkervaring, tot in detail.` staan er in dezelfde hiërarchie. Boven de pagina staat de bestaande TV-bovenbalk in plaats van het logo met kruimelpad `Mijn Pleya > Instellingen`. | De bouwopdracht vraagt de topnavigatie te behouden; daarmee geaccepteerd. |
| Actieve sectie | Match | `WEERGAVE` boven `Zo ziet jouw Pleya eruit`, de gekozen categorie gemarkeerd in de rail. De build zet er groepskoppen onder (`SCHERM`), omdat Weergave op TV meer rijen heeft dan het bord. | Geen besluit nodig. |
| Achtergrond | Match | Donker: warme wash over `#141414`. Licht: warm gebroken wit (`#F9F5F2`). OLED blijft zwart zonder wash, zodat OLED zijn reden houdt. Contrast getoetst in `tv_settings_studio_contrast_test`. | OLED zonder wash is een keuze uit fase 1; open voor Michel als hij de wash ook op OLED wil. |
| Rijen | Match met verschil | Fijne scheiding, waarde rechts, één focusring. De rijen zelf volgen de bestaande voorkeuren: de build toont Thema, Taal, Liquid Glass, Raster- of lijstweergave, Dichtheid, de northstar Thema, Visuele effecten, Liquid Glass, Raster, Afleveringsposters. App-taal heeft geen plek in de reeks en staat onder Thema. | Welke rijen bestaan beslist de code (BOUWOPDRACHT, "Betekenis van pariteit"). De plek van App-taal: open. |
| Directe schakelaar | Match met verschil | Select op de hele rij zet de waarde om, de schakelaar is geen tweede focusstop en de waarde wordt bewaard (`settings_tv_page_test`, "SELECT on a switch row flips it in place, one stop per row"). De schakelaar is een getekende pil in Studio-koraal, geen echt Liquid Glass-materiaal. Anker 04 schrijft "Aan" als tekst; de build toont ook in Licht de pil. | Open. |
| Voorbeeldkaart | Match | `LIVE VOORBEELD`, drie posters uit de bibliotheek, `Jouw bibliotheek`, de modusregel uit de actuele voorkeur en `Bekijk voorbeeld`, dat Bibliotheken opent. Zonder Home-items houdt de kaart titel en modusregel (`settings_tv_page_test`, "without items it keeps its text"). Op Afspelen toont de kaart Afspeelervaring met de standaardkwaliteit, niet de tijd- en spoorregel van het bord. | Afspeelervaring: open. |

## Instellingen op iPhone

Bladen: `01-iphone-instellingen-donker.jpg`, `02-iphone-instellingen-licht.jpg`, `iphone-instellingen-*.jpg`.

| Controle | Oordeel | Wat de build anders doet, en waarom | Besluit |
| --- | --- | --- | --- |
| Kop en media | Match met verschil | `Instellingen`, `PLEYA · PERSOONLIJK`, `Maak Pleya helemaal van jou.` en een filmbeeld uit de geladen titels. Zonder titels of zonder klaar staande server een merkpaneel in plaats van een kapot beeld (`settings_studio_header_test`). Een subpaginatitel die niet naast het beeld past breekt af naar twee regels; de reeks laat hem over het beeld lopen. | Twee regels: open. |
| Structuur | Match met verschil | `VOOR JOU` en `VERBINDINGEN EN PROFIELEN` in het startbeeld, `SYSTEEM` (Geavanceerd, Back-up, Over Pleya) verderop. Ondertitelstijl is een eigen rij in Voor jou. Big P staat alleen in Verbindingen en profielen als de build Big P heeft; het vernieuwde blad `01` komt uit zo'n build en toont hem tussen Koppelingen en Profielen, zoals bord 01. Het lichte bord 03 gebruikt de groepsnamen `KIJKEN` en `JOUW PLEYA`; de build houdt in elk thema de namen van bord 01, die ook in VISUELE_ACCEPTATIE staan. | Groepsnamen: gekozen volgens VISUELE_ACCEPTATIE, Michel kan dat omdraaien. |
| Rijen | Match | Compacte lijst van 50 pt, dunne scheiding, lijniconen zonder vierkant badge op de hoofdpagina, geen iconen op subpagina's, uitleg als VoiceOver-hint (`settings_row_anatomy_test`). Geen tegels meer. | Geen besluit nodig. |
| Weergave | Match met verschil | Bovenaan de kaart `Live voorbeeld` met een poster, `Jouw bibliotheek` en de modusregel; daaronder Thema met de waarde en directe schakelaars. Liquid Glass staat in de fixture uit, op het bord aan. App-taal staat als laatste rij in Scherm, Dichtheid na Raster of lijst (anker 03). | App-taal: open. |
| Gedrag | Match met verschil | Zoeken vindt dezelfde bestemmingen (`settings_search_test`, `settings_hub_pages_test`). Na scrollen schuift een compacte balk met de titel over de pagina en bij terugscrollen weer weg (`dark-main-scrolled`). Terug zit als chevron op de titelregel (`settings.back`, `settings_studio_header_test`). De tabbalk blijft onder Instellingen staan, het bord tekent er geen. | Tabbalk is shell en valt buiten A-24b; open als Michel hem binnen Instellingen weg wil. |

## Mijn Pleya op iPhone (Editorial)

Bladen: `05-iphone-mijn-pleya.jpg`, `iphone-mijn-pleya-gescrold.jpg`, `iphone-mijn-pleya-leeg.jpg`.

| Controle | Oordeel | Wat de build anders doet, en waarom | Besluit |
| --- | --- | --- | --- |
| Profiel | Match | Compacte regel met avatar, naam en `1 van 1 servers online`; tikken opent de profielwissel (`my_pleya_screen_test`). De fixture heeft geen profielfoto, dus een letter-avatar. | Geen besluit nodig. |
| Kijklijst | Match met verschil | Posters direct onder het profiel met `Bekijk alles`, gevoed door de kijklijst van het actieve profiel. Lege kijklijst en geen kijklijst zijn aparte staten (blad `leeg`, twee tests). Op de posters staat alleen het bestaande bekeken-teken, niet de andere badges van het bord. | Badges: open. |
| Content | Voorwaardelijk | Bibliotheken en Downloads als rustige rijen. Aanvragen verschijnt alleen met Seerr; de fixture heeft geen Seerr, de widgettest wel. Het aantal downloads ontbreekt omdat de simulator geen downloads had. | Volgt de code. |
| Big P | Match met verschil | Rode kaart met de eigen Big P-illustratie, opent de bestaande assistent; alleen in een build met Big P en bij recht op de assistent. Het verloop is iets donkerder dan op het bord, omdat het uit de accentkleur van het thema komt. | Kleur: open. |
| Overige | Voorwaardelijk | Servers, Samen kijken, Instellingen (via de bestaande tab), Over Pleya en Uitloggen (rood, met de bestaande bevestiging) zijn er. Activiteit verschijnt alleen onder dezelfde voorwaarde als voorheen en zit niet in de fixture. De tabbalk heeft Series waar het bord Zoeken heeft. | Tabbalk is shell, buiten A-24b. |

## Mijn Pleya op Apple TV (Editorial)

Bladen: `06-appletv-mijn-pleya.jpg`, `appletv-mijn-pleya-*.jpg`.

| Controle | Oordeel | Wat de build anders doet, en waarom | Besluit |
| --- | --- | --- | --- |
| Top | Match met verschil | Titel, profielregel met `Profiel wisselen` en een niet-focusbare serverstatus (`Pleya Server · Zolder` in de fixture). Eén focus; terugkomen herstelt de laatst gefocuste actie (`tv_my_pleya_screen_test`, Verify `tvos.my-pleya.editorial`). De bovenbalk is de bestaande TV-shell, zonder Live TV en Zoeken als tekst. | Shell valt buiten A-24b. |
| Kijklijst | Match met verschil | Brede rail met posters, titel en jaar, `Bekijk alles`; links en rechts zonder overlap (blad `posterfocus`). Een lange titel wordt afgekapt op 153 pt ("Tears of S..."). | Afkappen: open. |
| Mijn content | Voorwaardelijk | Aanvragen verschijnt met Seerr (blad `conditioneel`, rechts). Collecties en Afspeellijsten bestaan en zijn getest, maar de fixture levert ze niet, dus ze staan op geen screenshot. Zonder modules verdwijnt de groep en loopt de focus door (blad `conditioneel`, midden). De ondertitel van Aanvragen is die van de iPhone. | Volgt de code. |
| Bronnen | Match met verschil | Bibliotheken, Servers en Samen kijken met aantal als ondertitel. Activiteit volgt de oude voorwaarde en zit niet in de fixture. | Volgt de code. |
| Rechterkant | Match met verschil | Big P-kaart en Beheer met Instellingen, Logboeken, Over Pleya en een rode Uitloggen; terug uit Instellingen landt weer op Instellingen. De kolom is 440 pt in plaats van 480 en de Big P-ondertitel loopt over twee regels, zodat vier tegels op 23 pt passen zonder afkapping. De regel "Aangemeld als" staat onder de vouw tot de focus rechts staat. | Breedte en voetregel: open. |
| Thema | Afwijking | Donker en Licht met leesbare focusring en posters. Het lichte bord 05 heeft een warme gebroken-witte wash; de build houdt in Licht het monoTheme-grijs. | Geaccepteerd: productbesluit 2 in `START-HIER.md` (warm gebroken wit alleen binnen Instellingen) en Michels bevestiging in fase 5. |

## Pariteit per route

`PARITEIT_A24B.csv` heeft de kolommen van `PARITY_TEMPLATE.csv` en 439 rijen: alle sjabloonrijen plus 22 rijen die alleen in de code bestaan of die de code per platform anders aanbiedt. Status: 404 GEBOUWD, 27 AFWIJKING, 8 ALLEEN MOCKUP. Geen bestaande functie is verdwenen; elke rij noemt een test of het bewijs waarom er geen test is.

De acht rijen ALLEEN MOCKUP zijn geen functie in de code: Bronnaam en server bij elke bron, Verborgen bibliotheken blijven bewaard, Downloadmap bekijken, Opslag en status controleren, Nooit automatisch sync inschakelen, Gezinsbeperkingen, Kindvriendelijke antwoorden en op TV Navigatiebreedte en focus. Bouwen vraagt een productbesluit en valt buiten deze ronde.

De 27 rijen AFWIJKING bestaan wel, maar anders dan het bord ze tekent. De meeste zijn een functie zonder eigen rij: toestemming voor sync is een dialoog bij het inschakelen, configuratie per provider wisselt de velden in plaats van een pagina, bronnen per profiel zitten in Verbinding toevoegen, zoeken in het geheugen is een filter. Updates verschijnt alleen met een build-define en is in App Store-builds verborgen. Uitloggen blijft in Mijn Pleya en krijgt geen tweede ingang in Instellingen. Op iPhone opent Home aanpassen voor slepen en verbergen de bestaande editor in plaats van dat per rij te doen.

## Tests per gevraagde klasse

| Klasse | Testbestanden |
| --- | --- |
| Opslag van schakelaars | `test/screens/settings/settings_tv_page_test.dart` (Select zet `focusGlow` en `enableDebugLogging` om en bewaart ze), `test/screens/settings/appearance_settings_screen_test.dart`, `test/screens/settings/appearance_playback_studio_test.dart` |
| Platform- en capabilityvoorwaarden | `test/screens/settings/settings_screen_test.dart` (Tautulli alleen voor een Plex-eigenaar), `test/screens/settings/settings_hub_pages_test.dart` (geen Downloads op Apple TV), `test/screens/settings/settings_tv_page_test.dart`, `test/screens/my_pleya_screen_test.dart`, `test/screens/tv/tv_my_pleya_screen_test.dart` met `test/test_helpers/tv_my_pleya_conditions.dart`, `test/screens/tv/assistant/tv_my_pleya_assistant_tile_test.dart` |
| Donker, licht en OLED | `test/widgets/settings_studio_theme_test.dart` (Studio binnen Instellingen, monoTheme erbuiten), `test/widgets/tv_settings_studio_contrast_test.dart`, `test/screens/settings/settings_phone_page_test.dart` |
| Terugnavigatie en focusherstel | `test/widgets/settings/settings_studio_header_test.dart` (`settings.back`), `test/screens/settings/settings_tv_page_test.dart` (herstel na subpagina), `test/screens/tv/tv_my_pleya_screen_test.dart` (terug naar de laatste focus) |
| Destructieve bevestigingen | `test/screens/settings/settings_hub_pages_test.dart` (Cache wissen, import), `test/screens/my_pleya_screen_test.dart` (Uitloggen), `test/screens/settings/local_library_settings_screen_test.dart` (lokale gegevens wissen) |
| VoiceOver | `test/widgets/settings_row_anatomy_test.dart` (uitleg als hint), `test/screens/settings/settings_phone_page_test.dart`, `test/screens/tv/tv_my_pleya_screen_test.dart` (tegel noemt titel en doel), `test/screens/my_pleya_screen_test.dart` (nieuw in fase 6: elke Editorial-rij en een kijklijstposter is met VoiceOver te activeren) |
| Grotere tekst en breedtes | `test/screens/tv/tv_my_pleya_screen_test.dart` (dubbele tekstgrootte, geen afkapping), `test/screens/settings/settings_studio_shots_test.dart` (320, 390, 1280, 1440 en 1920 pt) en `test/screens/my_pleya_shots_test.dart` (320 en 390 pt) |

De VoiceOver-test van fase 6 vond een echte fout: de rijen, de Big P-kaart en de posters van iPhone Mijn Pleya hadden een label maar geen actie, omdat `excludeSemantics` ook de tikactie van de InkWell wegnam. Hersteld in `bd1b80cc`; de test is rood zonder die fix.

## Bewijsronde fase 6

Eén ronde, gebundeld, op de eindcode van de branch. Apple TV: één build van `20a49376` (de merge met `github/main`), daarna hergebruikt, op de Apple TV 4K-simulator. iPhone: één build van `bd1b80cc` met Big P aan, hergebruikt op de iPhone 17 Pro- en de iPhone SE-simulator. De hostbelasting lag tijdens de iPhone-runs tussen 14 en 18 door andere sessies.

Apple TV, 20 scenario's die in fase 5 alleen gevalideerd waren: 19 PASS (`tvos.settings.appearance`, `assistant-memory`, `home-layout`, `language-preferences`, `language.walk`, `tvos.my-pleya.sections`, `section-about`, `section-logs`, `styling-audit`, `requests-discover`, `tvos.theme.dark-hero-cta`, `tvos.glass.topnav`, `tvos.glass.topnav-light` en de zes `tvos.assistant.*`: `action-status`, `long-lead`, `memory-card`, `multitask`, `multitask-summoned`, `trending-dense`).

`tvos.glass.player` faalt, en niet door A-24b. De A-24b-stappen slagen (Mijn Pleya, Instellingen, Liquid Glass aan, Menu terug). Het scenario loopt vast in de speler: vier keer Rechts vanaf afspelen/pauzeren eindigt op `TrackControl2` in plaats van `player.settings_button`, omdat de spelerbalk sinds het scenario meer knoppen heeft. De branch wijzigt geen spelercode. Eén controlerun op een schone build van `github/main` (`7925b126`) faalt ook, alleen eerder: daar landt Omlaag, Omlaag op Mijn Pleya op de Big P-tegel in plaats van Instellingen, omdat TV-builds Big P standaard aan hebben. Het scenario is dus op main al rood; de spelerstap is daar niet bereikt en niet vergeleken. Niet in deze PR opgelost.

iPhone, de scenario's die in fase 2 en 4 alleen gevalideerd waren: PASS voor `ios.settings.studio`, `ios.glass.tabbar`, `ios.glass.detail`, `ios.player.sheets-glass` en `ios.viewport-density.navigation`. Met dezelfde build daarna `a24b.ios.settings.phase2` (iPhone SE, alle Instellingen-pagina's in OLED, Donker en Licht) en `a24b.ios.mypleya.phase4` (iPhone 17 Pro, drie thema's en de themawissel via Instellingen): beide PASS; hun screenshots leverden de vernieuwde bladen `01`, `02` en `05`.

Drie iPhone-scenario's bleven rood. Ze zijn per run uitgezocht en hooguit één keer opnieuw gedraaid, met een aanwijsbare reden:

- `ios.scroll-crown.ends` (IOS-CROWN-END1) draaide op de hoofdpagina van Instellingen. Die heeft na de A-24b-indeling nog twaalf rijen; op de SE is het scrollbereik volgens de ui-tree van de run minder dan 500 pt, dus minder dan één scherm van 667 pt, terwijl `ScrollCrown` pas vanaf twee schermen inhoud verschijnt (`minContentScreens = 2.0`). Op de 17 Pro verschijnt de kroon daar dus niet; op de SE verscheen hij bij de start wel en was hij aan het eind weg. Het scenario test daarmee een pagina die geen kroon meer hoort te hebben. Eén proef met Home als doel faalde op `at_end` en is teruggedraaid. Open: een nieuwe doelpagina voor dit scenario kiezen.
- `ios.library.crown-list` staat op SE-coördinaten (`tap: {x: 185, y: 110}`). Op de 17 Pro faalde hij precies op die tik; de herhaling op de SE faalde eerder, op het openen van `screen.libraries` na een tik op `library.picker.card[0]`, een stap die de eerste run wel haalde. Geen crash in `app.log`, de app reageerde. Onverklaard en niet bewezen.
- `ios.glass.player` haalde in de eerste run alle A-24b-stappen en de route naar de film, en faalde bij de start van de speler op een 500 van `/v1/ui_tree`: `AutomationRegistry.snapshot()` gooide, en de app logt dat alleen op debugniveau, dus de oorzaak staat niet in het log. De herhaling faalde eerder, op een tik op `landing.view_all[movies]` die geen catalogus opende. Geen spelercode in deze branch. Onverklaard en niet bewezen.

Niet gedraaid: `ios.library.local-offline` en `ios.library.local-storage`, omdat de standaardroute van de host een VPN-tunnel is (`utun12`) en de index op wifi wacht; `ipados.viewport-density.navigation`, omdat er geen iPad-simulator op deze machine staat.

Goldens die deze branch raakt: `test/goldens/tv_shell_my_pleya.png`, `tv_shell_my_pleya_focused.png`, `tv_shell_my_pleya_full.png` en `tv_shell_auth_my_pleya.png` (alle vier uit `test/goldens/tv_root_shell_golden_test.dart`). Ze worden na de eerste push via `goldens.yml` op de CI-runner opnieuw gemaakt en bekeken voor ze worden gecommit; lokaal op macOS zijn goldens niet te reproduceren.

## Wat nog niet bewezen is

- Geen run op een echte iPhone of Apple TV, en geen VoiceOver-ronde op een toestel. Alles hierboven komt uit simulators en widgettests.
- `ios.library.crown-list` en `ios.glass.player` zijn rood zonder verklaring; `ios.scroll-crown.ends` heeft een nieuwe doelpagina nodig; `tvos.glass.player` is al rood op main.
- `ios.library.local-offline`, `ios.library.local-storage` en `ipados.viewport-density.navigation` zijn niet gedraaid (wifi achter de VPN-route, geen iPad-simulator).
- De VoiceOver-actie van de Big P-kaart op iPhone zit in de code, maar geen test dekt hem: in testbuilds staat Big P uit.
- Aanvragen, Activiteit, Collecties en Afspeellijsten staan op geen simulatorscreenshot, omdat de fixture ze niet levert; ze zijn alleen in widgettests bewezen.
- De Apple TV-bladen zijn niet opnieuw gemaakt na fase 3 en 5; de Verify-ronde hierboven liep wel over die schermen.
- De vier goldens hierboven zijn nog niet opnieuw gemaakt op de CI-runner.
