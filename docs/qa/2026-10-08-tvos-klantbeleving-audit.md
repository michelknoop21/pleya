Method: dual-agent (A: /root/review_resume_record · B: /root/review_log_recovery_fixes)

# tvOS-klantbeleving: audit per venster — 8 oktober 2026

Roadmap: REG-01 (vensterdekking), A-11/A-12 en betrokken A-items. **Advies en inventaris, geen implementatieplan, ontwerpapproval, prioriteitswijziging of bewijs van hardwareacceptatie.** De bestaande roadmapvolgorde blijft gelden tot Michel een vervolg kiest. Bronstand `bdedec38b59ce31549d7b522164ca8fc1c149654`, appfix in tvOS TestFlight 342; branch voor deze documentaudit `audit/tvos-customer-experience-20261008`. Auditregistratie AUDIT-TV-UX1. Geen productcode gewijzigd.

## Hoofdoordeel

Pleya heeft een herkenbare streamingstijl en bruikbare TV-primitives. De grootste verbeterkans is dat de kijker minder hoeft te begrijpen van de onderliggende techniek en sneller weet wat zijn druk heeft gedaan. De huidige kansen zitten vooral in actiebetekenis, lege toestanden, startfeedback en de indeling van beheer. Een nieuw thema of een nieuwe shell is daarvoor niet nodig.

Dit is een vensterinventaris met bronanalyse en ontwerpkritiek. **Niet ieder venster is op de huidige build live doorlopen of visueel goedgekeurd.** Waar huidige visuele evidence ontbreekt, is de richting een voorstel, geen gevonden pixeldefect. Ook de voorstellen die logisch lijken kunnen bestaande DEC's raken en vereisen dan een expliciete productkeuze.

## Wat aantoonbaar beter kan

1. **TVUX-56 — P1, bronbevestigd, beperkte scope.** Pleya Server-tegels op Servers presenteren identiteit en status maar Select activeert ontkoppelen; lokale bronrijen activeren verwijderen (`tv_servers_page.dart:112-139`). De verwijderbevestiging blijft aanwezig, dus dit is geen bewezen dataverliesbug. De verwachting is informatie openen. Maak status/herstel de eerste stap; verwijderen expliciet secundair. Niet generaliseren naar alle Plex/Jellyfin-tegels.
2. **TVUX-36 — P2, bronbevestigd.** Een account zonder aanvragen krijgt Geen aanvragen met Retry (`tv_seerr_requests_view.dart:429-436`). Een correct lege lijst herladen helpt niet. Een actie naar de bestaande ontdek-/zoekroute biedt een zinvol begin. De gefilterd-lege state heeft al Filters wissen; die behouden.
3. **TVUX-21 / TVUX-10 — P1, codekandidaat.** De onderzochte detailstart roept async playbacknavigatie aan zonder een lokale busy-overgang op de CTA (`action_buttons.dart:9-43`). Onderzoek de gedeelde flow en laat iedere startactie direct herkenbare ontvangst/startstatus geven. Dit bewijst niet dat alle callers feedback missen en lost RESUME-PLAY1 niet bewezen op. De fysieke melding blijft apart open.
4. **TVUX-22 — P2, codekandidaat.** De detailactiebar kan veel functieacties tegelijk bieden (`action_buttons.dart:322-328`). Herorden op kijkdoel en benoem gefocuste iconen. Geen functies schrappen; behoud bestaande meer-menu en platformvoorwaarden.
5. **TVUX-59 — P2, ontwerpvoorstel.** De instellingenindex groepeert veel featurebestemmingen (`settings_tv_page.dart:129-206`). Een kleine taakindeling maakt een kijkprobleem sneller vindbaar. De oude desktopachtige instellingenlijst is inmiddels vervangen door een TV-grid: die oude fout wordt hier niet opnieuw gemeld.

6. **TVUX-79 — P2, bronbevestigd.** In een actieve Samen kijken-sessie krijgt Verlaten/beëindigen autofocus voor de host of wanneer er geen huidige playback is (`watch_together_screen.dart:797`). Er is al een bevestiging (`:814-820`); dit is geen onbedoeld-beëindigenclaim. Geef een positieve vervolgactie de eerste focus wanneer die beschikbaar is.
7. **TVUX-76 — P2, bronbevestigd.** Het Live TV-schema bevat vaste Engelse teksten zoals “min left”, “Starting in” en “at” (`live_tv_show_schedule_screen.dart:204-220`). Gebruik bestaande vertalingen voor een consistente Nederlandse ervaring.
8. **TVUX-77 — P2, codekandidaat.** De onderzochte schemalader heeft geen lokale foutafhandeling rond `fetchSchedule` en zet loading pas na succes uit (`live_tv_show_schedule_screen.dart:78-102`). Controleer de bovenliggende foutafhandeling en reproduceer een mislukte fetch; pas daarna een vastgelopen loader als runtimebug melden.

## Bestaande sterktes die behouden moeten blijven

- Duidelijke focusbehandeling en expliciete eigenaars voor shell, terugkeer en focusgeheugen. De actuele Home-opname toont een herkenbare ring en aparte actieve bestemming.
- Bronstatus en onzekerheid blijven zichtbaar; onbruikbare bronnen verdwijnen niet stil uit de keuze. Voorkeursbron, selected-track-scroll en bestaande herstelcomponenten zijn bruikbare patronen.
- Progressive disclosure bestaat al voor geavanceerde aanvragen en spelerinstellingen. Big P heeft kaarten en vroege deelresultaten; geen kritiek formuleren alsof die nog ontbreken.

## Heuristieken: voorlopige bronbeoordeling

Score 0–4, bedoeld als richtingswijzer. Niet gemeten op echte kijkers; niet een totale styling-/accessibilityscore.

| Heuristiek | Score | Oordeel |
| --- | ---: | --- |
| Zichtbaarheid systeemstatus | 2 | Bronstatus sterk; startfeedback nader onderzoeken. |
| Aansluiting op kijkerswereld | 3 | Kijken/hervatten herkenbaar; informatie openen versus verwijderen botst. |
| Controle en vrijheid | 3 | Menu/terugkeer expliciet ontworpen, niet opnieuw live geaccepteerd. |
| Consistentie | 3 | Gedeelde shell en componenten; taakprioritering kan consequenter. |
| Foutpreventie | 3 | Bevestigingen en rechten behouden; geen securityauditclaim. |
| Herkennen boven onthouden | 2 | Iconen en featuregroepen vragen interpretatie. |
| Efficiëntie | 3 | Focusherstel, voorkeuren en trackscroll aanwezig. |
| Esthetiek / minimalisme | Niet gescoord | Geen representatieve actuele screenshotset voor alle vensters. |
| Foutherstel | 2 | Retry aanwezig; lege aanvragenstate heeft ongeschikte eerste actie. |
| Hulp / documentatie | Niet gescoord | Contextuele hulpjourneys onvoldoende live gedekt. |
| **Totaal voor acht beoordeelde aspecten** | **21/32** | **Geen volledige productscore; niet extrapoleren naar 40.** |

Meer dan vier herkenbare filmkaarten is op zichzelf geen fout. Keuzebelasting gaat over gelijktijdige beslissingen en onduidelijke gevolgen, niet simpelweg over het aantal posters.

## Venstermatrix

**B** = huidig broncontract bevestigd; **K** = codekandidaat, effect/owner nog reproduceren; **V** = ontwerp- of acceptatievoorstel, geen bewezen ontbrekende functie; **H** = fysieke/input/accessibilitycontrole vereist. P1/P2/P3 zijn impactadviezen, geen ingeplande roadmapprioriteit of releaseblokkade. Alleen de hoofbevindingen boven zijn diep genoeg onderzocht voor concrete issueclaims; overige routes zijn geïnventariseerd met een beoordelingsrichting.

| ID | Domein | Venster / toestand | Adviesprioriteit | Type | Concreet verbeteren of behouden | Bestaande eigenaar |
| --- | --- | --- | --- | --- | --- | --- |
| TVUX-01 | Start | Eerste start / intro | P2 | V | Toon zo snel mogelijk bruikbare content; introductie mag de eerste kijkactie niet onnodig ophouden. Meet koude start en terugkeer apart. | `lib/main.dart` |
| TVUX-02 | Start | Aanmeldkeuze | P2 | V | Eén duidelijk gekozen bron; rechts de concrete volgende stap in plaats van herhaalde uitleg. | `lib/screens/tv/tv_auth_view.dart:105` |
| TVUX-03 | Start | Plex-code / QR | P2 | V | Maak wachten, voltooid en verlopen herkenbaar; code en telefoonhandeling hebben voorrang boven beheerinformatie. | `lib/screens/auth_screen.dart:321` |
| TVUX-04 | Start | Serveradres / aanmelden andere backend | P2 | V | Beperk remote-typen; telefoonoverdracht is een productvoorstel, geen bestaande bewezen functie. | `lib/screens/settings/add_connection_screen.dart:63` |
| TVUX-05 | Start | Aanmeldfout / geen servers | P1 | V | Onderscheid accounttoegang van bereikbaarheid; herstel de mislukte stap in plaats van onnodig opnieuw aanmelden. | `lib/screens/auth_screen.dart:304` |
| TVUX-06 | Start | Profielkeuze | P2 | H | Actieve kijker moet ook hoorbaar herkenbaar zijn; PIN en beheren apart houden van kiezen. VoiceOver op toestel controleren. | `lib/screens/tv/tv_profile_gate.dart:161` |
| TVUX-07 | Start | PIN invoeren | P2 | H | Controleer remote-invoer, foutfeedback en terugkeer naar hetzelfde profiel op hardware; geen nieuwe invoerbug vastgesteld. | `lib/screens/profile/pin_entry_dialog.dart:79` |
| TVUX-08 | Start | Profiel toevoegen / bewerken | P2 | V | Maak zichtbaar voor welk profiel bronnen en voorkeuren gelden; beheeractie hoeft geen extra stap in normaal kijken te zijn. | `lib/screens/profile/profile_detail_screen.dart` |
| TVUX-09 | Kiezen | Home / hero | P2 | V | Behoud artwork, witte primaire CTA en sterke focus. Onderzoek of hervatten vaker eerste kijkactie moet zijn; geen goedgekeurde compositie stil vervangen. | `lib/widgets/tv/tv_hero_billboard_card.dart` |
| TVUX-10 | Kiezen | Verder kijken-rij | P1 | K | Koppelen aan dezelfde directe startstatus als detail; kaart blijft herkenbaar tijdens voorbereiden en na een fout. Resume-melding blijft onopgelost. | `lib/widgets/tv/tv_continue_watching_card.dart` |
| TVUX-11 | Kiezen | Verder kijken-overzicht | P2 | V | Maak aflevering en resterende tijd beslisinformatie; opruimen van een titel blijft secundair. Nieuwe 4-oktoberbeelden zijn proposed. | `lib/screens/tv/tv_continue_watching_screen.dart:91` |
| TVUX-12 | Kiezen | Home aanpassen | P2 | V | Toon effect van wijziging en herstel de gekozen positie na opslaan. Geen tweede personalisatiesysteem naast de bestaande editor. | `lib/widgets/tv/tv_home_customize_panel.dart` |
| TVUX-13 | Kiezen | Rij toevoegen / bewerken | P2 | V | Eerst het kijkdoel van de rij, daarna bron en filterdetails; eindig met een begrijpelijke samenvatting. | `lib/widgets/tv/tv_home_row_wizard.dart` |
| TVUX-14 | Kiezen | Films-landing | P2 | V | Behoud onderscheid ontdekken versus volledige catalogus; toets of eerste rij een bruikbare kijkkeuze biedt voor kleine én grote bibliotheken. | `lib/screens/tv/tv_movies_landing_screen.dart` |
| TVUX-15 | Kiezen | Series-landing | P2 | V | Geef hervatten van eigen series context naast nieuwe ontdekking; vermijd dubbele titelkaarten zonder uitleg. | `lib/screens/tv/tv_series_landing_screen.dart` |
| TVUX-16 | Kiezen | Alle films / alle series | P2 | V | Breng actieve filters, sortering en aantallen samen in één korte oriëntatieregel; brondekking is iets anders dan titelaantal. | `lib/screens/tv/tv_unified_catalog_screen.dart` |
| TVUX-17 | Kiezen | Filters / bronfilter | P2 | V | Behoud zichtbare selectie naast focus; toon wat het resultaat vernauwt en houd Wissen beschikbaar. Filters zijn geen technische checklist. | `lib/widgets/tv/tv_catalog_filter_rail.dart` |
| TVUX-18 | Kiezen | Sortering | P2 | V | Huidige sortering vóór de keuzelijst leesbaar; behoud gridpositie na wijzigen waar dat betekenisvol is. | `lib/widgets/tv/tv_catalog_sort_panel.dart` |
| TVUX-19 | Kiezen | Zoeken / toetsenbord | P2 | V | Recente zoekacties en systeeminvoer behouden; terug uit het toetsenbord mag de query niet onverwacht verliezen. | `lib/screens/tv/tv_search_view.dart` |
| TVUX-20 | Kiezen | Zoekresultaten / geen resultaat / fout | P2 | V | Bestaande skeleton, retry en zoeken-bij-aanvragen behouden. Onderscheid geen match van onvolledige brondekking alleen als die state bekend is. | `lib/screens/tv/tv_search_view.dart:229` |
| TVUX-21 | Details | Filmdetail / primaire acties | P1 | K | Select op Afspelen direct zichtbaar beantwoorden met Starten en stabiele focus; geen bewezen root cause van de fysieke resume-fout. | `lib/screens/media_detail/action_buttons.dart:34` |
| TVUX-22 | Details | Secundaire detailacties / meer-menu | P2 | K | Laat gebruikersdoel de volgorde bepalen: één primaire actie, passende secundaire actie; beheer in bestaand meer-menu. Gefocuste iconen herkenbaar benoemen. | `lib/screens/media_detail/action_buttons.dart:328` |
| TVUX-23 | Details | Volledige synopsis | P2 | V | Behoud leesbare alinea's en terugkeer naar dezelfde titel; voorkom dat langer lezen focus op Afspelen kwijtraakt. | `lib/screens/media_detail_screen.dart` |
| TVUX-24 | Details | Seriedetail / seizoen | P2 | V | Benoem precies wat start: hervatten, volgende of eerste aflevering; toon seizoenkeuze zonder schijnbaar meerdere primaire routes. | `lib/screens/media_detail/action_buttons.dart:9` |
| TVUX-25 | Details | Afleveringen / afleveringdetail | P2 | V | Kijkstatus, titel en speelduur helpen kiezen; bepaal focus na playback met de daadwerkelijke voortgang, niet alleen laatste klik. | `lib/screens/media_detail/action_buttons.dart:46` |
| TVUX-26 | Details | Bronkeuze / onbereikbare bron | P2 | V | Bestaande bereikbaarheid en onbekende metadata behouden; vat betekenisvolle verschillen voor de kijker samen. Voorkeur alleen uit bewezen eigenschappen. | `lib/widgets/tv/tv_media_source_picker.dart:163` |
| TVUX-27 | Details | Contextmenu | P2 | V | Werkwoorden en onderscheid Hervatten versus Vanaf begin; schijf-/bron-/schrijfacties blijven secundair. Terugkeer op dezelfde kaart behouden. | `lib/screens/tv/tv_unified_context_menu.dart` |
| TVUX-28 | Details | Collectie-overzicht / collectie | P2 | V | Toon inhoud en passend kijkdoel; collectie is een verzameling, geen gegarandeerde afspeelvolgorde. | `lib/screens/tv/tv_collection_screen.dart` |
| TVUX-29 | Details | Afspeellijst-overzicht / detail | P2 | V | Maak volgorde, omvang en voortgang duidelijk; de primaire actie respecteert het type lijst. | `lib/screens/tv/sections/tv_personal_media_overview_screens.dart:177` |
| TVUX-30 | Details | Persoon / filmografie | P2 | V | Heldere naam en beschikbare titels; geen Volgen of biografie fabriceren wanneer backend of contract die niet ondersteunt. | `lib/screens/tv/tv_person_screen.dart` |
| TVUX-31 | Persoonlijk | Mijn Pleya-hub | P2 | V | Kijkerszaken hebben meer gebruikswaarde dan support/beheer. Behoud grid en groepen; overweeg support onder een secundaire ingang zonder functies te schrappen. | `lib/screens/tv/tv_my_pleya_tiles.dart:33` |
| TVUX-32 | Persoonlijk | Kijklijst | P2 | V | Maak Nu te kijken herkenbaar naast bewaarintentie; onbeschikbaar bewaren mag niet aanvoelen als kapotte playback. | `lib/screens/watchlist_screen.dart:219` |
| TVUX-33 | Persoonlijk | Kijklijstfilters / sortering | P2 | V | Huidige selectie en uitweg uit lege filterstate zichtbaar; bewaren, beschikbaarheid en gekekenstatus niet verwarren. | `lib/widgets/watchlist_filter_sheet.dart` |
| TVUX-34 | Aanvragen | Ontdekken / aanvraagzoekroute | P2 | V | Maak verschil tussen eigen bibliotheek en nog aan te vragen content expliciet; voorkom een zoekopdracht opnieuw typen in een andere route. | `lib/screens/tv/tv_seerr_discover_view.dart` |
| TVUX-35 | Aanvragen | Mijn aanvragen / statusfilter | P2 | V | Status verklaart wat de kijker kan doen: wachten, beschikbaar bekijken of reden van afwijzing lezen. Beheerrechten blijven expliciet. | `lib/screens/tv/tv_seerr_requests_view.dart:323` |
| TVUX-36 | Aanvragen | Lege aanvragenlijst | P2 | B | Geen aanvragen is geen fout: vervang primaire Retry door zoeken/ontdekken. Retry hoort bij de echte errorstate. | `lib/screens/tv/tv_seerr_requests_view.dart:429` |
| TVUX-37 | Aanvragen | Aanvraagdetail | P2 | V | Één begrijpelijke volgende stap per status; beschikbaar opent de concrete kijkroute waar die bron bekend is. | `lib/screens/seerr/seerr_media_detail_screen.dart:118` |
| TVUX-38 | Aanvragen | Aanvraagformulier / seizoenen / 4K | P2 | V | Vóór indienen een samenvatting van titel, seizoenen, kwaliteit en gevolg; geen instellingen tonen die de gebruiker niet mag veranderen. | `lib/widgets/seerr_request_sheet.dart:201` |
| TVUX-39 | Aanvragen | Geavanceerde aanvraagopties | P3 | V | Server/profile/root-folderdetails achter de bestaande advanced-stap houden; kijkers hoeven die niet eerst te begrijpen. | `lib/widgets/seerr_request_sheet.dart:309` |
| TVUX-40 | Kijken | Speler / OSD / pauze | P1 | K | Afspelen, voorbereiden en fout moeten zichtbaar verschillende staten zijn; bedieningspaneel snel weg uit de film en betrouwbaar terug. | `lib/widgets/video_controls/desktop_video_controls.dart:426` |
| TVUX-41 | Kijken | Tijdlijn / touchpad | P2 | H | SCRUB2 is al uitgebracht in build342; niet opnieuw als ontbrekend melden. Klik/veeg/annuleerhints en precisie op Siri Remote toetsen. | `lib/widgets/video_controls/desktop_video_controls.dart:645` |
| TVUX-42 | Kijken | Speler-informatie / technisch overzicht | P2 | V | Eerst titel en kijkinformatie, daarna codecs en diagnostiek. Gebruik het goedgekeurde paneel33, niet het vervangen paneel19. | `lib/widgets/video_controls/tv_info_panel.dart` |
| TVUX-43 | Kijken | Audioselectie | P2 | V | Wat hoor ik staat vooraan: taal, audiobeschrijving en begrijpelijk onderscheid. Codec/kanaalinfo secundair; gekozen track direct herkenbaar. | `lib/widgets/video_controls/sheets/track_sheet.dart:61` |
| TVUX-44 | Kijken | Ondertitelselectie | P2 | V | Geen, taal, forced/SDH en eigen voorkeur helder onderscheiden; tijdelijke keuze niet als profieldefault presenteren. | `lib/widgets/video_controls/sheets/track_sheet.dart:159` |
| TVUX-45 | Kijken | Ondertitels zoeken / downloaden | P2 | V | Laat zoekstatus, bruikbaarheid en resultaat van de keuze zien zonder technische bestandskennis; geen backendgaranties verzinnen. | `lib/widgets/video_controls/sheets/subtitle_search_sheet.dart` |
| TVUX-46 | Kijken | Versie / kwaliteit | P2 | V | Vat effect samen als beeldkwaliteit en afspeelwijze waar bekend; een versie, server en transcodekwaliteit zijn verschillende keuzes. | `lib/widgets/video_controls/sheets/version_quality_sheet.dart:14` |
| TVUX-47 | Kijken | Hoofdstukken | P2 | V | Titel en tijd maken de sprong voorspelbaar; huidige plek herkenbaar, focus na de sprong behouden. | `lib/widgets/video_controls/sheets/chapter_sheet.dart:71` |
| TVUX-48 | Kijken | Wachtrij / volgende aflevering | P2 | V | Maak zichtbaar wat automatisch hierna speelt; queue geen tweede onduidelijke catalogus. Bestaande lijstsemantiek behouden. | `lib/widgets/video_controls/sheets/queue_sheet.dart:45` |
| TVUX-49 | Kijken | Zoom / beeldinstellingen | P2 | V | Toon het effect in het videobeeld en bied een duidelijke standaard; instelling en tijdelijke keuze niet stil laten doorwerken. | `lib/widgets/video_controls/tv_info_panel/tv_video_tab.dart` |
| TVUX-50 | Kijken | Synchronisatie / slaaptimer | P2 | V | Benoem eenheid, resterende tijd en geldigheid; geavanceerde offsets achter de bestaande subview. | `lib/widgets/video_controls/tv_info_panel/tv_sync_sub_view.dart` |
| TVUX-51 | Live / samen | Live TV / favorieten / gids | P2 | V | Toets snel zappen, Nu versus Straks en programmaovergang; behoud favorieten als snelle route. Nog geen actuele hardwarejourney. | `lib/screens/livetv/live_tv_screen.dart` |
| TVUX-52 | Live / samen | Programma / zenderschema | P2 | V | Maak live kijken versus later programma bekijken onderscheidbaar; tijden en terugkeer naar zender zijn belangrijker dan beheerinfo. | `lib/screens/livetv/live_tv_show_schedule_screen.dart` |
| TVUX-53 | Live / samen | Samen Kijken / kamer / deelnemen | P2 | V | Uitnodigen, wachten en samen afspelen verdienen eigen begrijpelijke staten; geen groen succes vóór verbinding en deelname bekend zijn. | `lib/watch_together/screens/watch_together_screen.dart` |
| TVUX-54 | Live / samen | Samen Kijken / verlaten / storing | P2 | V | Laat zien of alleen jij vertrekt en wat met playback gebeurt; herstelroute zonder de gebruiker blind opnieuw te laten beginnen. | `lib/watch_together/screens/watch_together_screen.dart` |
| TVUX-55 | Beheer | Bibliotheken / onderhoudsheet | P2 | V | Bekijken en onderhouden expliciet scheiden; benoem gevolgen van scannen/wissen. Beheerbevestigingen behouden. | `lib/screens/tv/sections/tv_libraries_screen.dart:391` |
| TVUX-56 | Beheer | Servers: Pleya Server / lokale bron | P1 | B | Select op informatietegel activeert nu ontkoppelen/verwijderen. Open een statuspaneel; maak verwijderen een expliciete secundaire actie. Dit is niet een claim over alle Plex/Jellyfin-tegels. | `lib/screens/tv/sections/tv_servers_page.dart:125` |
| TVUX-57 | Beheer | Verbinding toevoegen / delen | P2 | V | Eerst doel en status, daarna alleen benodigde velden. Koppel aan actief profiel; telefoonoverdracht is nog een productkeuze. | `lib/screens/settings/add_connection_screen.dart:63` |
| TVUX-58 | Beheer | Activiteit / wie kijkt | P2 | V | Wie kijkt wat en waar; profiel-/beheerscope duidelijk, geen onbekende kijkers of sessies als zekerheid tonen. | `lib/screens/tv/sections/tv_now_watching_screen.dart:107` |
| TVUX-59 | Beheer | Instellingen-index | P2 | V | Taakgroepen boven de bestaande schermen: Beeld en geluid, Taal en ondertitels, Bibliotheek en bronnen, Account. Bestaande grid behouden. | `lib/screens/settings/parts/settings_tv_page.dart:129` |
| TVUX-60 | Beheer | Uiterlijk / thema | P2 | V | Effect zichtbaar vóór keuze afronden; focus, actief en preview niet verwarren. Licht/OLED/contrast op echt scherm testen. | `lib/screens/settings/appearance_settings_screen.dart:33` |
| TVUX-61 | Beheer | Home-layout / bibliotheekzichtbaarheid | P2 | V | Laat zien voor wie en waar de verandering geldt; wijziging heeft een duidelijke eindstatus. Geen tweede home-editor bouwen. | `lib/screens/settings/home_layout_screen.dart` |
| TVUX-62 | Beheer | Playback-instellingen | P2 | V | Groepeer op kijkprobleem, met huidige waarde en effect: starten, beeld, geluid. Technische instellingen blijven beschikbaar op tweede niveau. | `lib/screens/settings/playback_settings_screen.dart` |
| TVUX-63 | Beheer | Taal / serievoorkeuren | P2 | V | Profieldefault, seriewens en tijdelijke spelerkeuze als verschillende scopes benoemen; de vier lagen zijn bestaand contract. | `lib/screens/settings/parts/language_settings_tv.dart:42` |
| TVUX-64 | Beheer | Ondertitelstijl / preview | P2 | V | Voorbeeld op een videobeeld met donkere én lichte delen; terug naar standaard en geldigheid duidelijk. Voorbeeld is geen tienvoet-acceptatie. | `lib/screens/settings/subtitle_styling_screen.dart:44` |
| TVUX-65 | Beheer | Trackers / Trakt / Tautulli | P3 | V | Leg kijkersvoordeel en verbindingsstatus uit vóór credentials; lange tekstinvoer via bestaande systeeminvoer beperken. | `lib/screens/settings/trackers_settings_screen.dart` |
| TVUX-66 | Beheer | Aanvragen-configuratie | P2 | V | Toon of de service bruikbaar is, daarna noodzakelijke server/authvelden. API-key-invoer op de remote blijft een frictiepunt. | `lib/screens/settings/seerr_settings_screen.dart:157` |
| TVUX-67 | Big P | Niet ingesteld / gate | P2 | V | Behoud één concrete uitweg; leg uit wat configuratie mogelijk maakt, zonder eindeloze providerkeuze vóór de eerste bruikbare stap. | `lib/screens/tv/assistant/tv_assistant_gate.dart:31` |
| TVUX-68 | Big P | Provider / model / verbinding | P2 | V | Verbindingssamenvatting vóór modeldetails; credentials niet als kijkerskennis veronderstellen. Geen automatische providerwisseling. | `lib/screens/settings/assistant_settings_screen.dart:114` |
| TVUX-69 | Big P | Gesprek / resultaten / ballon | P2 | V | Resultaat en passende kijkactie vóór lang protocolproza; bestaande kaarten en vroege deelresultaten behouden. | `lib/screens/tv/assistant/tv_assistant_conversation.dart:286` |
| TVUX-70 | Big P | Taken / bevestiging / kind-instelling | P1 | V | Heldere status en gevolg per actie; kijkactie niet verwarren met wijziging. Bevestigingen en permissies behouden, geen breedte stil uitbreiden. | `lib/screens/tv/assistant/tv_assistant_confirm_flow.dart` |
| TVUX-71 | Herstel | Offline / gedeeltelijk bereikbare bronnen | P1 | V | Vertel wat nog wél kan; accountprobleem, onbereikbare server en lege collectie zijn verschillende staten. Geen bronoffline gelijkstellen aan allesoffline. | `lib/screens/tv/tv_offline_home_screen.dart` |
| TVUX-72 | Herstel | Meldingen / fout / retry | P1 | V | Blijf bij de mislukte taak, laat een herstelactie zien en behoud focus. Geen rauwe exceptionclaim: zoekfouten worden al vertaald. | `lib/widgets/notice/notice_host.dart` |
| TVUX-73 | Herstel | Logs / upload / support | P2 | V | Begeleid probleem melden met logperiode en upload-ID. Retentie bestaat al; geen nieuwe retentiefix voorstellen als ontbrekend. | `lib/screens/settings/logs_screen.dart:596` |
| TVUX-74 | Herstel | Over / privacy / licenties | P3 | V | Houd versie en support vindbaar; lange webtekst via telefoon-QR is een voorstel, geen al bestaande bewezen route. | `lib/screens/tv/sections/tv_about_screen.dart:89` |
| TVUX-75 | Live TV | Programmadetail: nu / later / verleden | P2 | V | Laat Kijken of Opnemen afhangen van tijd en backendcapaciteit; bestaande acties behouden. | `lib/screens/livetv/program_details_sheet.dart:95` |
| TVUX-76 | Live TV | Schema: relatieve tijden | P2 | B | Vervang vaste Engelse tijdteksten door bestaande vertalingen. | `lib/screens/livetv/live_tv_show_schedule_screen.dart:204` |
| TVUX-77 | Live TV | Schema: laden mislukt | P2 | K | Reproduceer fetch-fout en controleer bovenliggende afhandeling; bied vervolgens herstel zonder eindeloze loading. | `lib/screens/livetv/live_tv_show_schedule_screen.dart:82` |
| TVUX-78 | Samen kijken | Sessie maken: bedieningsrechten | P2 | V | Leg uit wie mag pauzeren en zoeken; behoud keuze Alleen ik / Iedereen. | `lib/watch_together/screens/watch_together_screen.dart:382` |
| TVUX-79 | Samen kijken | Actieve sessie: eerste focus | P2 | B | Verlaten/beëindigen krijgt onder genoemde voorwaarden autofocus; positieve vervolgactie eerst indien beschikbaar. Bevestiging behouden. | `lib/watch_together/screens/watch_together_screen.dart:797` |
| TVUX-80 | Samen kijken | Recente sessie: naam / vergeten | P2 | V | Maak lang indrukken vindbaar; behoud bestaand focusherstel na verwijderen. | `lib/watch_together/screens/watch_together_screen.dart:477` |
| TVUX-81 | Samen kijken | Gast: huidige film starten | P2 | V | Bestaande deelnamestart behouden; toon film en sessiestatus als belangrijkste context. | `lib/watch_together/screens/watch_together_screen.dart:786` |
| TVUX-82 | Live TV | Gids: dag / tijd selecteren | P2 | V | Gekozen dag en tijd zichtbaar houden; Nu als begrijpelijke terugweg. | `lib/screens/livetv/tabs/guide_tab.dart:1151` |
| TVUX-83 | Live TV | Opnameopties: aflevering / serie | P2 | V | Vat regel, bron en gevolg samen; behoud beschikbare opnamevelden. | `lib/screens/livetv/record_options_sheet.dart:213` |
| TVUX-84 | Instellingen | Ondertitelstijl: kleur / grootte | P2 | V | Een vast leesvoorbeeld kan wijzigingen begrijpelijk maken; ontbreken van een globale preview is niet bewezen. | `lib/screens/settings/subtitle_styling_screen.dart:93` |
| TVUX-85 | Instellingen | Trackeraccount: bibliotheken | P2 | V | Benoem scope en synchronisatierichting; bestaande bibliotheekfilters behouden. | `lib/screens/settings/tracker_account_settings_body.dart:75` |
| TVUX-86 | Instellingen | Tautulli: verbinden / testen | P2 | V | Behoud bestaande test en resultaatkaart; verduidelijk gekoppelde server en beschikbare functies. | `lib/screens/settings/tautulli_settings_screen.dart:311` |
| TVUX-87 | Instellingen | Big P: model / test / opslaan | P2 | V | Maak verbinding, model, test en opgeslagen status één begrijpelijke volgorde; bestaande opslaggate behouden. | `lib/screens/settings/assistant_settings_screen.dart:343` |

## Ontwerpreferentie per venster

Deze koppeling benoemt de te behouden baseline, **geen vastgestelde pixelpariteit**. De actuele Home-compositie is bekeken; de overige koppelingen zijn documentautoriteit, geen nieuwe live vergelijking. Een beeld voor een hoofdscherm keurt niet automatisch alle lege/fout/dialogstanden goed. Waar geen specifiek beeld is gekoppeld, blijft de huidige implementatie uitgangspunt en is het advies een voorstel.

| Venster-IDs | Baseline / autoriteit | Dekking en betekenis van het advies |
| --- | --- | --- |
| 02–05 | Inloggen 22, [approval 09–25](../tvos-redesign-09-25-approved.md) | Hoofdschermreferentie; backendformulieren, wacht- en foutstanden niet afzonderlijk visueel geverifieerd. |
| 06 | Profielkeuze 21, [approval 09–25](../tvos-redesign-09-25-approved.md) | Profielcompositie behouden; hoorbare selectie is een hardwarecontrole. |
| 09–10 | Home30 / DEC-095; resterend northstar01/02 en DEC-087, [statuskaart](../assets/tvos-unified/README.md) | Home30 is compositieautoriteit; actuele Home-opname bekeken. Startfeedback is geen goedgekeurde nieuwe compositie. |
| 11–13, 61 | Home38/39 van4oktober [proposed set](../assets/tvos-unified/mockups-2026-10-04-home/README.md); bestaande Homecontracten blijven gelden | Geen bouwplicht uit deze nieuwe beelden. Editor/subvensters zijn hier niet afzonderlijk aan een approved doelbeeld gekoppeld. |
| 14–15 | Northstar03/04 met DEC-064, [statuskaart](../assets/tvos-unified/README.md) | Behoud landingtaal; oorspronkelijke kaarttaal is deels vervangen. Geen actuele pixelpariteit vastgesteld. |
| 16–18 | [Implementatiecontract](../tvos-redesign-implementatiecontract.md) en bestaande cataloguscomponenten | Specifiek geldig catalogus-/filter-/sorteringsbeeld niet afzonderlijk vastgesteld in deze audit. Adviezen zijn voorstellen. |
| 19–20 | Zoeken36 / DEC-108, [approval 34–36](../tvos-redesign-34-36-approved.md) | 36 geeft de latere zoekcorrecties naast de oorspronkelijke13; geen bewezen nieuw zoekpixeldefect. |
| 21–25 | Details09/10 plus37 / DEC-109, [approval37](../tvos-redesign-37-approved.md) | 37 corrigeert expliciete onderdelen; overige09/10 blijven geldig. Startstatus/actiehiërarchie zijn nader te onderzoeken aanvullingen. |
| 26 | Bronkeuze11, [approval 09–25](../tvos-redesign-09-25-approved.md) | Status/broncontract behouden; voorstel tot begrijpelijker beslisinformatie. |
| 27–28, 30 | Contextmenu12, Collectie24 en Persoon25 voor hun respectieve hoofdoppervlakken, [approval 09–25](../tvos-redesign-09-25-approved.md) | Geen afzonderlijke actuele pariteitscontrole van alle bijbehorende subvensters. |
| 32–33 | Kijklijst34 / DEC-108, [approval 34–36](../tvos-redesign-34-36-approved.md) | Hoofdgrid/filterrichting; behoud bestaand gedrag, voorstellen voor statusbetekenis. |
| 34–39 | Aanvragen35 / DEC-108, [approval 34–36](../tvos-redesign-34-36-approved.md) | Aanvragengrid heeft doelbeeld; detail/formulier/empty zijn niet ieder visueel geaccepteerd. Retry-bevinding komt uit broncode. |
| 40–41 | Speler18, [approval 09–25](../tvos-redesign-09-25-approved.md); SCRUB2 in fysieke register | Spelerstijl behouden; touchpadgedrag vraagt echte hardware. |
| 42–50 | Paneel33 / DEC-101, [statuskaart](../assets/tvos-unified/README.md) | 19 is vervangen. Paneel33 bepaalt zijn standen; aparte sheets niet automatisch visueel afgedekt. |
| 51–52, 75–77, 82–83 | Live TV17, [approval 09–25](../tvos-redesign-09-25-approved.md) | Gidsreferentie; schema/detail/datum/opname-subvensters niet afzonderlijk aan eigen approved beeld gekoppeld. Copy/fetch-bevindingen zijn bronanalyse. |
| 31, 55–56, 58–60, 74 | Mijn Pleya-set2september, [design-index §7](../DESIGN-INDEX.md); Uiterlijk20 en Activiteit16 in [approval 09–25](../tvos-redesign-09-25-approved.md) | Hoofdsecties hebben referenties. Laatste specifieke26–31-amendement per sectie niet opnieuw volledig uitgeplozen; geen pixelmismatchclaim. |
| 67–70 | Big P38, [eigen approval](../tvos-redesign-38-big-p-approved.md), plus huidige fysieke correctieregister voor ballon | Dit is een andere38 dan proposed Home38. 38 bevat ook gate, instellen en bevestiging; de besproken specifieke substanden zijn niet allemaal opnieuw visueel vergeleken. Latere registercorrecties gaan vóór verouderde overlay-/bewegingszinnen in het manifest. |
| 71 | Offline23, [approval 09–25](../tvos-redesign-09-25-approved.md) | Offlinehoofdstaat; gedeeltelijke bereikbaarheid niet afzonderlijk visueel geverifieerd. |
| 01, 07–08, 29, 53–54, 57, 62–66, 72–73, 78–81, 84–87 | Bestaande implementatie + [TV-regels](../agents/ui-and-tv.md) en [implementatiecontract](../tvos-redesign-implementatiecontract.md) | Specifieke goedgekeurde mockup/DEC **niet vastgesteld in deze audit**; dit zegt niet dat die nergens bestaat. Beoordelingsrichting/bronbevinding, geen ontwerpafwijking of nieuwe approval. |

## Bewijsmanifest en geldigheid

### Actueel runtimebewijs

- Run `.build/pleya-verify/tvos-my-pleya-explore-1791442873613` op bron-SHA `bdedec38`, alleen documentaudit dirty. `report.md` gelezen. Setup, aanmelden, discover-ready en eerste snapshot PASS; eerste RIGHT mislukt door idb. **De journey als geheel FAILED, geen geslaagde Mijn Pleya-traversal.**
- `screenshots/00-home.png`, 2048×1152: door root visueel bekeken; Home, topnav en begin Verder kijken. Leesbare Nederlandse tekst, duidelijk contrast van primaire CTA en focus. Artwork is synthetisch fixturemateriaal: geen oordeel over echte posterkwaliteit of commerciële hiërarchie van echte titels.
- Ruwe bounded idb-diagnose: SimulatorKit ontbreekt op `/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework`. Doctor meldde connectiviteit maar de echte HID-actie faalde. Dit is een toolchainblokkade, geen bewijs van een Pleya-focusbug.
- Native CUA-poging kon Simulator niet binden, ook niet via bundle-ID. Geen extra desktop-/device-beelden verkregen. Geen terugval naar AppleScript voor Verify.

### Referenties en widgetbeelden, apart van runtime

- Door root bekeken golden fixtures: `test/goldens/tv_shell_my_pleya_full.png`, `tv_home_production_first_row_focused.png`, `tv_catalog_films_rail_open.png` (1040×584). Layoutreferenties; geen nieuwe rendering of acceptatie van deze bronstand. Synthetische artworkkleuren zijn testdata.
- Door A/B bekeken `.build/tvos-1005/screenshots/requests-grid-entry.png`, `requests-grid-scrolled.png`, `requests-field-returned.png` (1038×584, Ahem-testfont, placeholder-artwork). Alleen geometrie bruikbaar. Geen actuele leesbaarheid/copy/contrastclaim uit blokglyphs. Losse bundel niet aan huidige SHA bewezen.
- Historische septemberbeelden in `mockups-2026-09-02/before/` zijn context, geen huidige fouten. De inmiddels gebouwde instellingen-TV-grid mag niet worden beoordeeld alsof de oude lange lijst nog live is.
- Ontwerppixels werkelijk bekeken: goedgekeurde film-/bron-/spelerbeelden 09/11/18 en search36-A, plus historische losse movies/series/source-picker references. Status via `docs/assets/tvos-unified/README.md`, approval-manifests, implementatiecontract en latere DEC's. Mockup19 is vervangen door paneel33, details09/10 deels door37. Home38/39 van4oktober zijn proposed; niet als bouwplicht behandelen.

### Onafhankelijke methodiek

Assessment A beoordeelde product/UX zonder detectoruitvoer. Daarna is B gelezen. B begon op `82eb7eb0`; de relevante `lib/screens/tv`/`lib/widgets/tv`-boom is byte-identiek aan `bdedec38`, gecontroleerd met gerichte git diff. De nieuwe runtime-opname kwam daarna als aanvullende root-evidence.

Detectorscan werkelijk uitgevoerd: `detect.mjs --json lib/screens/tv`, exit0, `[]`. **0 scannable files:** alle43 doelbestanden zijn Dart, buiten het HTML/CSS/JS/TS/Vue/Svelte/Astro-bereik. Daarom geen native kwaliteitsgoedkeuring en geen claim nul problemen. Geen browser-DOM of detectoroverlay voor de native tvOS-app; een HTML-mockup is een ander productoppervlak.

VoiceOver, Reduce Motion, lange tekst, licht/OLED op echte TV, afstandsleesbaarheid, Siri Remote touchpad, resume/reconnect en volledige routes blijven zonder actuele hardwareacceptatie. Er zijn geen tests of golden-regeneraties gedaan voor deze documentaudit; geen productcodewijziging.

## Klantreis: waar de ervaring moet winnen

- Eerste gebruiker: zonder beheerderskennis weten hoe aanmelden naar kunnen kijken leidt.
- Dagelijkse kijker: Verder kijken en volgende aflevering met onmiddellijke ontvangstfeedback; geen stille startvallei.
- Ervaren gebruiker: bronnen/kwaliteit/trackkeuzes beschikbaar, met betekenis vóór techniek en stabiele terugkeer.
- Minder goedziende of motorisch beperkte kijker: focus én actieve selectie hoorbaar/zichtbaar, geen gebaar als enige uitweg. Dit is een acceptatiedoel, nog geen vastgestelde toegankelijkheidsfout.

De filmkeuze en hervatactie zijn de gewenste piek; starten zonder herkenbaar gevolg is de ervaren vallei. Na stoppen, aanvragen of logupload verdient de kijker een ondubbelzinnig resultaat en terugkeercontext.

## Advies voor vervolgstappen, niet ingepland

1. Reproduceer de gedeelde startfeedback op detail en Verder kijken; laat user-reported RESUME-PLAY1 als eigen root-causeonderzoek staan.
2. Werk de twee bronbevestigde actiebetekenissen uit: Pleya Server/lokale bron en lege aanvragenlijst. Kleine afgebakende fixes met negatieve controle.
3. Kies taakgroepering/actieprioriteit als productvoorstel binnen de bestaande shell. Wijzig geen goedgekeurde primaire compositie zonder expliciet besluit.
4. Verzamel actuele screenshots en focusreizen voor alle genoemde vensters; eerst de idb/Xcode-toolchain herstellen of echte device-review uitvoeren. Voor stylingacceptatie per venster: donker/licht, rust/focus/actief, geladen/leeg/fout, lange tekst en juiste terugkeer. Geen green status alleen omdat CI of een golden bestaat.

## Externe toetssteen

Apple vraagt duidelijke focus en herkenbare bediening op de TV en adviseert tekstinvoer op tvOS te minimaliseren. Deze uitgangspunten ondersteunen de bovenstaande interpretatie; ze bewijzen geen fout in Pleya. Bronnen: [Designing for tvOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos/), [Text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields/), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/).

## Vragen voor de productkeuze na de audit

Welke winst eerst: onmiddellijk starten/herstellen, concrete actiebetekenissen of taakgericht beheer? Hoeveel verandering past binnen de huidige shell: kleine correcties eerst of ook secundaire vensters herordenen? Deze audit autoriseert nog geen uitvoering.
