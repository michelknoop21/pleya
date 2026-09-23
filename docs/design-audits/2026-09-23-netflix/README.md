# Pleya Netflix-redesign — huidige interface en verbeterplan

23 september 2026 · tvOS eerst · checkout `6052e824` · ontwerpvoorstel, nog geen productwijzigingen.

## Advies

Behoud Home. Maak de bestaande ontwerpstijl af op de vervolgroutes en sluit de ontbrekende ingangen voordat er meer visuele varianten bijkomen. Begin met Collecties/Afspeellijsten en instellingen-subpagina’s. Meer hero-items is een kleine, afzonderlijke verbetering van de selectie, geen nieuw Home-ontwerp.

Dit document werkt het [goedgekeurde onderzoeksvoorstel](../../superpowers/specs/2026-09-23-netflix-ux-audit-proposal.md) uit. De actuele app is de nulmeting. Historische mockups zijn alleen bronnen voor eerdere besluiten. De vier nieuwe beelden zijn **voorstellen**, geen screenshots van bestaande functionaliteit.

## Actueel bewijs en grenzen

De huidige tvOS-build is gebouwd en door Pleya Verify bediend met idb/HID. `tvos.ux23.current-surfaces` is **PASS**, met 24 echte simulatorbeelden en bijbehorende UI-trees. Home, Mijn Pleya, Bibliotheken, Servers, Samen Kijken, Instellingen, Logs en Over zijn daarmee opnieuw bezocht; relevante openings- en scrollbeelden zijn visueel bekeken. Openen, navigeren en terugkeren zijn gemeten. Dit bewijst geen servermutaties, accountkoppeling, afspelen of hardwaregedrag.

Bewijs: `.build/pleya-verify/tvos-ux23-current-surfaces-1790183928286/`. De eerste run van het oude `tvos.my-pleya.styling-audit` faalde omdat twee keer DOWN nu op Instellingen landt in plaats van Bibliotheken. De beelden en UI-tree bevestigen verouderde choreografie. De aparte auditroute is aan de huidige hub aangepast; productcode en bestaande tests zijn niet gewijzigd.

Het [reviewbord](index.html) gebruikt geselecteerde kopieën van de actuele simulatorbeelden in `current/`, zodat de vergelijking ook in een schone checkout zichtbaar is. De volledige Verify-bundels met rapporten en UI-trees blijven buiten tracked source onder `.build/`.

De fixture bevat één Pleya Server, drie films en één serie; Home valt terug op een Verder kijken-item. De groene artworkvlakken zijn fixturebeelden, geen aangetoonde artworkbug. Deze run bewijst niet hoeveel hero-items een echt Plex/Jellyfin-profiel krijgt. Kijklijst, aanvragen, actieve sessies, Live TV en backendafhankelijke acties vereisen aanvullend bewijs. De volledige app is dus **niet** visueel afgetekend.

De vervolgrun `tvos.ux23.settings-depth` leverde vijf actuele beelden, waaronder Uiterlijk. De run is FAILED door een onjuiste onderzoeksaanname: thema opent geen picker maar is een inline segmentkeuze. Select wijzigde de geïsoleerde fixturevoorkeur naar Systeem. Eén Menu keerde correct terug naar de Uiterlijk-tegel; de tweede keerde naar Mijn Pleya terug. Dit is geen aangetoonde Back-bug. Bewijs: `.build/pleya-verify/tvos-ux23-settings-depth-1790184222009/`.

De Home-indeling-vervolgrun leverde drie beelden. Hij faalde uitsluitend op de achterhaalde verwachting dat Back op Uiterlijk moest landen: de huidige app herstelde juist Home-indeling, de oorspronkelijke tegel. Dat is gewenst gedrag. Bewijs: `.build/pleya-verify/tvos-ux23-settings-followup-1790184518723/`. De pagina zelf toont twee rijen met exact hetzelfde label “Recent toegevoegd” en dezelfde server “Zolder”; dit is een GUI-ambiguïteit, geen bewijs van dubbele catalogusdata.

De aansluitende route `tvos.ux23.forms` is **PASS**: Video afspelen en Verbinding toevoegen zijn actueel vastgelegd, en beide keren keert Menu terug naar de oorspronkelijke instelling. De vijf screenshots staan in `.build/pleya-verify/tvos-ux23-forms-1790184701187/`. Ook dit is alleen navigatie-/presentatiebewijs, geen afspeel- of aanmeldtest.

## Bevindingen en prioriteit

| Prioriteit | Bevinding | Bewijsstatus | Voorstel / bestaande eigenaar |
|---|---|---|---|
| P1 | Collecties en Afspeellijsten missen hun bedoelde zelfstandige ingang in Mijn Pleya. De Bibliotheken-subtitel belooft ze wel. | Huidige fixture-hub bekeken; `TvMyPleyaSection` heeft geen van beide bestemmingen; LIB7 registreert de verhuizing expliciet als niet meegenomen. Dit is sterker dan alleen afwezigheid in een fixture. | Eerst bestaande LIB7 / I7-child 15/18-afhankelijkheid reconciliëren. Mockup 01 toont de ingangen; achterliggende overzichten en brongebonden acties horen bij hetzelfde opleverpakket. |
| P1 | Uiterlijk, Home-indeling, zichtbaarheid, afspeelvoorkeuren en meerdere formulieren gebruiken nog gedeelde pagina-/rijprimitieven, tegenover TV-tegels op het bovenliggende niveau. | Code vastgesteld in `SettingsPage`, `SettingsWidthLimit`, `SettingsFocusRow`, `HomeLayoutScreen`; actuele Uiterlijk-capture bevestigt de afwijkende titel-/inhoudsmarges en grote gesegmenteerde voorkeurblokken. | Eén TV-presentatie voor voorkeuren, met bestaande state/handlers. Geen los redesign per setting. Mockups 02/03. |
| Bewaken | Instellingen herstellen in de onderzochte actuele routes de oorspronkelijke tegel. | Uiterlijk én Home-indeling keerden terug naar hun eigen tegel. Oude scenario-opmerkingen over altijd de eerste tegel zijn hier achterhaald. | Behouden als regressie-eis; geen focusherbouw zonder een echte nieuwe reproductie. |
| P1 | Offline/focus/schaal/Live TV hebben bekende nog open items. | Bestaande correctieronde: OFF5, SYS-3c/d/e, LIVE2 en hardwarepunten; in deze ronde niet allemaal opnieuw gereproduceerd. | Bestaande TV6/TV3/TV4/TV8-eigenaren aanhouden. Niet als nieuw gevonden bugs sluiten. |
| P2 | Home-indeling heeft ononderscheidbare rijlabels en bediening vlak bij de schermrand. | Actueel beeld `01-home-layout` uit de vervolgrun: tweemaal Recent toegevoegd / Zolder. | Voeg bekende mediatype-/bibliotheekcontext toe, behoud rij-ID’s en gebruik de bestaande TV-safe-insets. Mockup 03. |
| P2 | Mappen bladeren ontbreekt in het nieuwe TV-bibliotheekbeheer. | LIB7 en `TvLibrariesScreen` documenteren expliciet dat de TV-foldernavigator niet is gebouwd. | Bestaand uitgesteld werk meenemen in pakket A; een bruikbare ingang en navigator zijn nodig, niet alleen een nieuwe tegel. Geen hardwareclaim. |
| P2 | Beheerpagina’s zijn al grotendeels in de nieuwe stijl, maar diepe voorkeuren en dialogs kunnen daarvan afwijken. | Actuele beelden van Bibliotheken, Servers, Samen Kijken, Instellingen, Logs en Over; gedeelde subpagina-code. | Behoud de werkende bovenliggende schermen. Trek de stijl door naar de daadwerkelijke vervolgroutes. |
| P2 | Hero-selectie kapt af op acht unieke recente films; ophalen gebruikt al limiet twaalf. | `FeaturedSelector`, `TvHomeProjectionProvider` en `DiscoverProvider` gelezen. | Voorkeur: maximaal twaalf geschikte recente films, geen nieuwe categorieën of minimumquota. Eerst echte kandidaatpool meten. |
| P2 | Bibliotheken toont grote beheerkaarten met veel ongebruikte breedte; op de fixture zijn twee items zichtbaar. | Actueel beeld `10-libraries-opened`; geen bewijs dat twee items op zichzelf een dichtheidsbug zijn. | Alleen bij veel bibliotheken een compactere beheerregel vergelijken. Titel, bron, aantal, zichtbaar/verborgen en alle acties behouden. |
| P2 | Lange instellingenlijst vereist veel scrollen; de eerste viewport toont circa drie volledige tegelrijen. | Actueel beeld `40-settings-opened`, scrollbeeld `42-settings-scrolled`. | Groepen en huidige waarden beter scanbaar; maak vooral de onderliggende voorkeuren consistent. Geen verplichte herbouw van de instellingenindex. |
| P2 | Remote is minder vindbaar; de hostvoorkeur bestaat nog onder Video afspelen. | `PlaybackSettingsScreen` en het nieuwe Home-pad gelezen. | Geen claim dat de functie ontbreekt. Controleer koppelen/start-stop/status in de werkende app; behoud host/client-onderscheid. |
| P3 | Verouderde auditpaden kunnen verkeerde regressiemeldingen geven. | Eerste audit faalt, actuele afzonderlijke wandeling slaagt. | Scenario’s naar huidige routes migreren, asserties op echte focus/bereikbaarheid bewaren; nooit appcode wijzigen om een oude choreografie te bedienen. |

## De vier ontwerpvoorstellen

Open [het reviewbord](index.html) voor huidige beelden naast voorstellen.

1. **Mijn Pleya aanvullen.** Collecties en Afspeellijsten in de persoonlijke groep, bestaande beheer-, sessie-, profiel- en uitlogacties behouden. Tegels blijven afhankelijk van backend/rechten. De demonstratie toont een rijker voorbeeldprofiel dan de fixture; de extra Kijklijst/Aanvragen/Activiteit-tegels betekenen niet dat die vandaag overal ontbreken. Servernamen/status en appversie blijven aanwezig. De rusttoestand van de topnav in het beeld is geen voorstel om het huidige inklapgedrag te wijzigen.
2. **Uiterlijk als TV-voorkeurenpagina.** Vier herkenbare categorieën met een lijst van voorkeuren en hun waarde, vaste tekstuitlijning, witte focusring en contextuele toelichting. Het HTML-voorbeeld wisselt categorieën; Page Down/Up toont de overige voorkeuren. Waarden zijn voorbeeldwaarden. Wijzigen/opslag, pickers en volledige remote-interactie zijn nog niet geïmplementeerd. Bestaande voorkeuren blijven traceerbaar in de controle-inventaris; oude sidebarvoorkeuren eerst op werkelijk effect beoordelen vóór eventuele verwijdering.
3. **Home-indeling.** Zichtbare acties voor omhoog, omlaag en zichtbaar/verborgen, met de vaste Hero/Verder kijken-positie uitgelegd. Eigen rijen en verborgen rijen blijven vindbaar. Bij eerste/laatste verplaatsbare rij vervalt alleen de onmogelijke richting; focus blijft op dezelfde rij na verplaatsen. Het voorbeeld is een compositiestudie; knoppen veranderen nog geen lijst of voorkeur.
4. **Verbinding toevoegen.** Dezelfde TV-tegels en profielcontext als Servers. Plex, Jellyfin, Pleya Server, lokale map, Pleya Share en lenen van een profiel zijn uit de huidige picker overgenomen. Dit is nadrukkelijk niet het eerste-startscherm, dat zijn eigen twee-keuzecontract houdt. De actuele picker is inmiddels ook vastgelegd; per optie nog capability/bruikbaarheid op tvOS bewijzen; geen nieuwe backend via een mockup beloven.

Voor Home is bewust geen vervangend beeld gemaakt: twaalf slides veranderen het aantal mogelijke beelden, niet de goedgekeurde compositie. Meet de pool na filtering en ontdubbeling. Uitbreiden zonder voldoende geschikte titels levert geen extra slides op.

## Functiebehoud: dekking per pakket

| Pakket | Schermen en vensters | Functies die expliciet behouden/gecontroleerd worden |
|---|---|---|
| A — navigatie en persoonlijke ingangen | Mijn Pleya, Collecties, Afspeellijsten, collectie- en playlistdetail, bibliotheekbeheer en mappen | Bronidentiteit, laden/paginering, leeg/fout/retry, openen, afspelen/shuffle waar ondersteund, verwijderen en itemverwijdering, terugkeer/focus; bibliotheken vernieuwen/scannen/verbergen/ordenen/analyseren/prullenbak waar ondersteund, plus het uitgestelde mappenpad. Geen onbewezen cross-server samenvoeging van collecties of personen. |
| B — voorkeuren | Uiterlijk, Home-indeling, zichtbaarheid, Afspelen, taal/serievoorkeuren, ondertitelopmaak, mpv-config, externe speler waar ondersteund | Alle bestaande voorkeuren, voorwaarden/defaults, waarden/pickers, reset/herstart waar nu vereist, bron-/profielscope, eigen en verborgen rijen. Taalpagina’s met goedgekeurd TV-ontwerp niet onnodig vervangen. |
| C — accounts en beheer | Servers, toevoegen/bewerken/lenen, Plex/Jellyfin/Pleya Server, Share-host/join/scan, lokale mappen, profiel kiezen/beheren/PIN/verwijderen, eerste start | Bestaande authflow, toetsenbord, maskering, annuleren, opslaan/fout/herstel, beheerrechten, verwijderen met bevestiging. Eerste start en verbinding toevoegen blijven verschillende flows. |
| D — integraties en hulpschermen | Trackers en accounts, Trakt/MAL/AniList/Simkl, Seerr/Tautulli, Samen kijken/sessie/recente kamers, Remote, activiteit, logs, Over/licenties, cache/reset/iCloud | Koppelen/ontkoppelen en status, sessie maken/deelnemen/verlaten, recente kamers hernoemen/vergeten, remote-hoststatus, filters/verversen/kopie/upload/wissen, alle links en bevestigingen. Geen externe acties uitvoeren tijdens ontwerpaudit. |
| E — ontdekken en detail | Home/hero/rijen, Films/Series/Alle, zoeken/personen, Ontdekken/aanvragen, filters/sortering/bronnen, kijklijst, film/serie/aflevering, synopsis/cast/extra’s/contextmenu/bronkeuze | Alle catalogusingangen, metadata, seizoenen en afleveringen, watched/resume, voorkeurbron, requeststatus, multi-source badges, pagination, verborgen bibliotheken, focus-/scrollherstel en lege/foutstaten. |
| F — afspelen en Live TV | OSD, vier informatietabs, zes submenu’s, afleveringnavigatie, autoplay/prompts, Live TV/gids/favorieten/opnames/regels/schedule | Play/pause/seek, kwaliteit/versies, chapters, shader/slaap/sync, audio/subs/beeldverhouding, alle opnameacties en rechten, buffering/error/offline, Menu één niveau terug. Echte backend en hardwarebewijs waar fixture/simulator tekortschieten. |
| Platformgrens | Downloads, synchronisatieregels, touch-/desktop-only routes, ebooks/web | Downloads zijn op Apple TV bewust afwezig. Niet als ontbrekend TV-ontwerp toevoegen. Mobiel/desktop blijven geïnventariseerd maar buiten deze eerste ronde; ebooks/web hebben eigen branches/ontwerpen. |

De [schermindex](surface-inventory.md) verwijst naar elk gevonden screen/view/sheet/dialog-bestand in de onderzochte screenmappen. De [controle-extractie](controls-inventory.tsv) is een zoekhulp, geen afgevinkte pariteitslijst. Ook de widgets onder `lib/widgets/video_controls/`, `lib/widgets/tv/`, `lib/widgets/companion_remote/` en de sheets in `lib/screens/livetv/` moeten per pakket worden gereconcilieerd. Geen pakket mag klaar heten met niet toegewezen bestaande acties.

## Gefaseerd plan na beoordeling

### 1. Pariteit en kritieke bediening

- Koppel Collecties/Afspeellijsten aan de bestaande LIB7-vervolgitems, inclusief data-eigenaar en beide backends. Begin bij `tv_my_pleya_sections.dart`, `tv_my_pleya_navigator.dart`, `tv_my_pleya_screen.dart`, de bestaande library-tabs en collectie/playlistdetails. Lever de ingang én het werkende overzicht samen op.
- Bewaar het nu waargenomen focusherstel bij verdere veranderingen en toets ook dialogs via `settings_tv_page.dart`, `tv_navigation_coordinator.dart` en `main_screen.dart`. Gewenst: oorspronkelijke instelling, met fallback als die is verdwenen; geen refactor enkel vanwege oude documentatie.
- Neem de al onder LIB7 uitgestelde TV-foldernavigator expliciet op; bepaal de ondersteunde backendpaden en behoud mappenhiërarchie, broncontext en Back naar de bovenliggende map.
- Maak de functiematrix per pakket af met expliciete behouden/verplaatst/niet-van-toepassing-uitkomst. Alle onverklaarde verschillen blokkeren uitvoering van dat pakket.

### 2. Eén instellingenpresentatie, daarna de consumenten

- Kies de voorgestelde lijst/categorie-indeling of behoud de huidige lijststructuur met uitsluitend TV-tokens. De categorievariant maakt lange pagina’s overzichtelijker, maar vraagt extra focus-/scrollstaat; alleen TV-styling is goedkoper en verandert minder bediening. Aanbevolen: categorieën voor lange voorkeurpagina’s, het bestaande overzicht met tegels behouden.
- Hergebruik `TvPageSurface`, `TvMenuGrid` en bestaande voorkeurhandlers waar passend. Voeg geen nieuwe state-library of tweede opslaglaag toe. TV-specifieke presentatie naast gedeelde logica; desktop/mobiel mogen niet meeveranderen.
- Migreer eerst Uiterlijk en Home-indeling als representatieve pagina’s. Daarna zichtbaarheid, Afspelen, ondertitelopmaak en de overige gedeelde formulieren. Elke voorkeur koppelen aan de bestaande sleutel en platformvoorwaarde.
- Formulieren/keuzepanels krijgen dezelfde marge, focusring, titelhiërarchie, scrollgrens en terugkeer. Een fout verschijnt bij de betreffende actie/veld; invoer blijft bij een herstelbare fout behouden.

### 3. Hero apart uitbreiden

- Meet het aantal opgehaalde, geschikte en unieke films op een echt profiel; log geen gevoelige titellijst in het plan.
- Voorgestelde bovengrens twaalf; recente-filmsemantiek, zichtbaarheid en ontdubbeling behouden. Geen serie/Top Picks-padding en geen nieuwe instellingenoptie nodig.
- Eigenaren: `discover_provider.dart`, `tv_home_projection_provider.dart`, `featured_selector.dart`, `tv_hero_billboard_carousel.dart`, bestaande artwork-prefetch.
- Verifieer 0/1/8/12 kandidaten, duplicaten op meerdere servers, toekomstige metadata, refresh tijdens focus, wrap-around, handmatig wisselen, auto-wissel uit, verminderde beweging en beperkt artworkgeheugen. Home-layout en Verder kijken blijven gelijk.

### 4. Overige vensters en bestaande schuld afmaken

- Voer pakketten C–F uit op actuele beelden en hun geldende doelontwerp. Geen blinde rebuild van al gebouwde schermen.
- Houd bestaande TV0–TV8-eigenaren en `unified-2026-closure.md` aan. SYS-3c/d/e, OFF5, Live TV-fixturegrens en hardwaregedrag blijven expliciete afhankelijkheden.
- Per gewijzigd oppervlak: gerichte regressietest met negatieve controle voor bugs, `scripts/ci_checks.sh`, toepasselijke tests, Pleya Verify-asserties plus gelezen compositorbeelden. Hardware-only blijft open tot een toestelrun.

## Goedgekeurd startpunt en open vervolg

Michel heeft de vier getoonde richtingen goedgekeurd met de expliciete kanttekening dat dit nog niet alles is. De uitvoering start met het [Superpowers-plan voor tranche 1](../../superpowers/plans/2026-09-23-netflix-redesign-tranche-1.md): hero-uitbreiding en persoonlijke Collecties/Afspeellijsten. Uiterlijk, Home-indeling en Verbinding toevoegen volgen als afzonderlijk pakket; pakketten B–F blijven open totdat ieder bestaand oppervlak en iedere actie een aantoonbare bestemming heeft.

## Controle van deze oplevering

Vier HTML-ontwerpen gerenderd op 1920×1080 en visueel bekeken; geen buiten het canvas lopende content na correctie. Het reviewbord laadt alle vier actuele vergelijkingsbeelden en de voorstellen. Categorie wisselen in de Uiterlijk-studie is in de browser gecontroleerd. Lokale Markdown-links en `git diff --check` gecontroleerd. Geen Dart/native-productcode of tests gewijzigd, dus geen Flutter-CI-gate voor deze documenten-/mockupoplevering. Niet-gerelateerde werkboomwijzigingen zijn behouden.
