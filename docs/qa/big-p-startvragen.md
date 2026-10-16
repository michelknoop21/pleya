# Big P: handmatige ronde startvragen

Roadmap: BP-10. De routetest (`test/assistant/assistant_examples_route_test.dart`) bewijst wat Pleya zelf uit de woorden van een startvraag vastlegt en dat het doeltool wordt aangeboden en niet geweigerd. Welk tool een echt taalmodel kiest, bewijst geen unittest. Daarvoor is deze ronde.

## Wanneer

Bij elke wijziging van `assistant.examples` in `en.i18n.json` of `nl.i18n.json`, en bij een ander standaardmodel. Alleen de gewijzigde vragen hoeven opnieuw, in beide talen.

## Hoe

1. Modellen: glm-5.3-flash en gemma4:31b via Ollama Cloud, zoals bij de nulmetingen van BP-04b en BP-05.
2. Profiel: een beheerder met Jellyfin of Plex, Seerr, Trakt en geheugen aan, zodat elke mogelijkheid wordt aangeboden. Draai de groep kijken daarna nog eens op een kinderprofiel.
3. Tik de vraag als chip aan (niet typen: een chip telt niet als getypt) en noteer het eerste tool in de stappenlijst.
4. Geslaagd: het eerste tool is een van de tools van de mogelijkheid in `AssistantCapability`, en het antwoord is geen weigering en geen wedervraag. De uitzondering is samen kijken, waar een wedervraag over wie er meekijkt het bedoelde gedrag is.
5. Een vraag die bij een van beide modellen faalt, wordt herschreven of krijgt een route in `assistant_intent.dart`. Daarna de routetest en deze ronde opnieuw voor die vraag.

## Rondes

| Datum | Model | Taal | Vragen | Geslaagd (eerste tool) | Geslaagd (ergens in de run) | Opmerking |
| --- | --- | --- | --- | --- | --- | --- |
| 13 okt 2026 | glm-5.3-flash | en | 32 | 23 | 27 | beheerder |
| 13 okt 2026 | glm-5.3-flash | nl | 32 | 21 | 27 | beheerder |
| 13 okt 2026 | gemma4:31b | en | 32 | 21 | 26 | beheerder |
| 13 okt 2026 | gemma4:31b | nl | 32 | 22 | 26 | beheerder |
| 13 okt 2026 | glm-5.3-flash | en | 11 | 8 | 9 | kinderprofiel, groep kijken |
| 13 okt 2026 | glm-5.3-flash | nl | 11 | 9 | 11 | kinderprofiel, groep kijken |
| 13 okt 2026 | gemma4:31b | en | 11 | 8 | 8 | kinderprofiel, groep kijken |
| 13 okt 2026 | gemma4:31b | nl | 11 | 9 | 9 | kinderprofiel, groep kijken |
| 13 okt 2026, na de vanavond-fix | glm-5.3-flash | en | 5 | 5 | 5 | beheerder, vanavond, serie starten, kinderen |
| 13 okt 2026, na de vanavond-fix | glm-5.3-flash | nl | 5 | 5 | 5 | idem |
| 13 okt 2026, na de vanavond-fix | gemma4:31b | en | 5 | 5 | 5 | idem |
| 13 okt 2026, na de vanavond-fix | gemma4:31b | nl | 5 | 5 | 5 | idem |
| 13 okt 2026, na de vanavond-fix | glm-5.3-flash | en | 5 | 5 | 5 | kinderprofiel |
| 13 okt 2026, na de vanavond-fix | glm-5.3-flash | nl | 5 | 5 | 5 | kinderprofiel |
| 13 okt 2026, na de vanavond-fix | gemma4:31b | en | 5 | 5 | 5 | kinderprofiel |
| 13 okt 2026, na de vanavond-fix | gemma4:31b | nl | 5 | 5 | 5 | kinderprofiel |

### Hoe deze ronde is gedraaid

Een tijdelijke test (niet gecommit) stuurt elke formulering, per taal, via `AssistantRun` naar Ollama Cloud met de echte toolnamen, beschrijvingen en eigenschappen. De tools zelf zijn stubs die `{ok: true}` teruggeven. De ronde is dus geen toestelrun: er zijn in deze eerste rondes geen (zichtbare) servers, bibliotheken of taken (zie de ronde met realistische stubs hieronder), en geen Seerr, Trakt of geheugen. Er is niet getikt op een chip; de vraag gaat als gewone prompt de run in.

De kolom "eerste tool" is de maat uit stap 4 hierboven. "Ergens in de run" telt ook runs die eerst een hulptool aanriepen (`list_servers`, `list_libraries`, `list_jobs`) en daarna het tool van de mogelijkheid.

### Wat faalde

Bij beide modellen, in beide talen, op beide profielen:

- **vanavond** ("What can I watch tonight?" / "Wat kan ik vanavond kijken?"): faalt in 7 van de 8 combinaties van model, taal en profiel (alleen glm op het kinderprofiel in het Nederlands slaagt). Beheerder: glm roept eerst `my_watching` en dan `trending_titles` aan, gemma alleen `my_watching`. Kinderprofiel (`my_watching` geblokkeerd): eerste tool `trending_titles`, bij gemma daarna `find_title`. Het bedoelde `search_catalog` of `find_media` komt niet vooraan.
- Andere vragen met dezelfde afwijking: "Find an exciting movie for tonight." (gemma beheerder en, glm kinderprofiel en: `trending_titles`, daarna `find_title`; `find_title` hoort niet bij deze mogelijkheid), "Welke serie kan ik nu beginnen?" (gemma beheerder nl: alleen `my_watching`; gemma kinderprofiel nl) en "Which series can I start now?" (gemma kinderprofiel en).
- Opgelost: de vragen noemen nu de bibliotheek ("What in my library can I watch tonight?", "Wat uit mijn bibliotheek kan ik vanavond kijken?", ook voor serie starten), en `AssistantIntent.tonightPick` (vanavond of tonight plus een bibliotheekwoord, zonder tip-, kijklijst-, aanvraag-, groeps- of andere-persoonwoorden) weigert `my_watching` en `trending_titles` met `use_search_catalog` en zet een noot voor het model. De vervolgvragen na een antwoord (`assistant.followUp.tonight`) zijn op dezelfde manier herschreven en geroute. Een vraag naar het populaire (trending, populair) houdt `trending_titles`. Zonder bibliotheekwoord ("Zoek een film voor vanavond") blijft `my_watching` het smaaktool, zoals de aanbevelingskaarten het gebruiken. Een eerste versie van de route zonder bibliotheekwoord brak die kaarten en is daarom verlaten. De ronde is herhaald voor vanavond, serie starten en kinderen: bij beide modellen, beide talen en beide profielen was het eerste tool `search_catalog` (40 van 40 runs, 5 per combinatie van model, taal en profiel).

### Ronde met realistische stubs (16 okt 2026)

De eerste rondes hadden een fout in de opzet, niet in de app: de testcontext was een subklasse die de zichtbare servers zelf opgaf, en `AssistantRun` maakt bij elke ask een kopie met `context.fresh()`, die alleen de basisklasse teruggeeft. De kopie had daardoor geen zichtbare servers. Alleen tools zonder server (zoals `search_catalog`, `list_servers`, `diagnose_library`) werden aangeboden; `list_libraries`, `find_media`, `scan_library`, `retry_job`, `list_jobs` en `compare_servers` ontbraken. De conclusie "stopt bij het hulptool" en de cijfers voor scan, taken herstarten, vergelijken en de Home-rij uit de eerdere rondes gelden daarom niet. De tabelrijen voor vanavond, serie starten en kinderen zijn niet geraakt, behalve dat `find_media` toen ontbrak; die vragen zijn hieronder opnieuw gedraaid.

Opzet nu: twee servers (Zolder, Kelder; Jellyfin, online, beheerder), per server een bibliotheek Films en Series, een mislukte taak (`job-1`) op Zolder, `search_catalog` met `query_id` en `can_become_home_row`, en het echte server-id-argument. De vraag gaat als prompt de run in; de aanvragen van het model worden gelogd, de tools zelf zijn stubs.

| Datum | Model | Taal | Vragen | Bedoeld tool aangeroepen | Opmerking |
| --- | --- | --- | --- | --- | --- |
| 16 okt 2026 | glm-5.3-flash | en | 10 | 10 | vanavond (3), serie starten, scan, taken herstarten, vergelijken, doctor (2), Home-rij |
| 16 okt 2026 | glm-5.3-flash | nl | 10 | 9 | doctor "dubbele films": alleen `list_servers` |
| 16 okt 2026 | gemma4:31b | en | 10 | 10 | |
| 16 okt 2026 | gemma4:31b | nl | 10 | 9 | doctor "ontbrekende afleveringen": `list_libraries`, geen `diagnose_library` |

Vanavond (3 vragen) en serie starten: bij beide modellen en beide talen was het eerste tool `search_catalog` of `find_media` (16 van 16). Scan, taken herstarten, vergelijken en Home-rij: het bedoelde tool werd in alle 16 runs aangeroepen, na de hulptools die het meestal nodig had (`list_servers`, `list_libraries`, `list_jobs`; voor de Home-rij `search_catalog` en dan `create_home_row` met het `query_id`). De scan riep `scan_library` voor beide filmbibliotheken aan, `retry_job` kreeg `job-1` op Zolder, `compare_servers` werd voor beide richtingen aangeroepen.

Doctor was de enige die wisselde. De twee gemiste runs (glm nl "dubbele films": alleen `list_servers`; gemma nl "ontbrekende afleveringen": `list_libraries` zonder `diagnose_library`) zijn herhaald: vier extra runs per model en vraag in beide talen gaf 31 van 32 aanroepen van `diagnose_library`. De ene misser daarbij was weer gemma nl "ontbrekende afleveringen". Over beide modellen 37 van 40 runs, dus de misser is een uitzondering (circa 1 op 13), geen vaste route-fout. Bij een misser antwoordt Pleya met "Geen gecontroleerde bibliotheekgegevens; de diagnose blijft onbekend."

Elke vraag is per model en taal één keer gedraaid (doctor vijf keer): dit zijn steekproeven, geen percentages. De mutaties (`scan_library`, `retry_job`, `create_home_row`) zijn alleen als aanvraag van het model geteld. De bevestigingskaart, het uitvoeren en de status daarna zijn niet getest.

Samen kijken: beide modellen riepen `recommend_together` direct aan met de deelnemers "family" of "gezin" (gemma nl: "me" en "gezin"). Een wedervraag over wie er meekijkt, het bedoelde gedrag, kwam niet voor.

Niet in deze ronde: Seerr-, Trakt- en geheugenvragen met een echte bron (het model zag de tools, maar er was niets achter), en Plex versus Jellyfin.

## Status na een actievraag

Wat Pleya na een actievraag laat zien, in drie lagen. De eerste twee zijn gedraaid; de derde niet.

**1. Widgettest iPhone en iPad** (`test/screens/big_p/big_p_action_flow_test.dart`, 12 tests, groen op 16 oktober 2026). De echte `AssistantController` en de echte tools `list_libraries`, `scan_library`, `list_jobs` en `retry_job` draaien tegen een nep-beheerdersserver, met een gescript model, in de echte ballon op 402 x 874 (iPhone) en 1024 x 1366 (iPad). Een getikte chip is nagebootst met `controller.submit(<chiptekst>)`.

- Scan: de server krijgt één scanverzoek, het scherm toont "Scan gestart · Films · Zolder" en blijft daar staan (zonder operatie-id volgt Pleya een scan niet), en toont nooit "Scan klaar" of "Scan mislukt".
- Taak herstarten: de server krijgt één retry; het scherm toont "Taak loopt · 40%" zolang de server de taak als lopend meldt, en pas daarna "Taak klaar" of "Taak mislukt". De oude mislukte uitkomst van een uur eerder wordt niet voor het resultaat van de herstart aangezien: een aparte test laat de server na de herstart nog twee keer de oude mislukking tonen en eist dan "Taak loopt" en nooit "Taak mislukt". Zonder de bewaking in `assistantJobLook` (`ours`) faalt die test (vastgesteld door haar tijdelijk weg te halen).
- Home-rij: eerst de bevestigingskaart "Rij op het beginscherm maken" met de titel; er staat niets op "Rij aangemaakt" voor Bevestigen en `execute` is dan nul keer aangeroepen; na Bevestigen is `execute` één keer aangeroepen, verdwijnt de kaart en staat er "Rij aangemaakt". Negatieve controle: Annuleren laat de kaart verdwijnen en roept `execute` niet aan.
- De Home-rij is de ene vervanger: de echte `create_home_row` heeft de hele catalogusservice nodig, dus een tool met dezelfde naam levert dezelfde `AssistantPendingAction`. De bevestigingskaart zelf en de status eronder zijn echt.

**2. Fixtures voor Pleya Verify** (`pleya_verify/fixture_server`, 144 tests groen, 1 overgeslagen die er al was). De nep-Pleya-server kent met de fixture `server.admin-jobs.v1` nu `GET /jobs`, `POST /jobs/{id}/retry` (200 met de `Job`; de taak leest daarna vier keer als lopend en dan als geslaagd) en `POST /libraries/{id}/scan` (202 met de `Scan`, die geen taak-id heeft om te volgen). De antwoorden zijn gevangen in de contracttest van de fake server en door `scripts/check_server_responses.py --subset` aan `openapi.yaml` getoetst (JobPage, Job en Scan: PASS). De nep-modelserver beantwoordt de drie vragen met de echte tools: lijst de bibliotheken en scan de filmbibliotheek, lijst de taken en herstart de mislukte, zoek en maak de Home-rij alleen uit een resultaat dat een rij kan worden. Het resultaat toont nu ook `jobPhase` in de automatiseringsstatus (`assistant.result`), zodat een scenario de fase kan vergelijken.

**3. tvOS-simulator: niet gedraaid.** Het scenario `pleya_verify/scenarios/tvos.assistant.action-status.yaml` staat klaar en valideert (`dart run bin/verify.dart validate`): het stelt het model in, typt de drie vragen in de native editor en wacht op "scan gestart", op de herstart tot "klaar" en op de bevestigingskaart van de Home-rij, met een schermafbeelding per stap. Het draait nog niet, want er is geen tvOS-simulatorruntime: `xcrun simctl list runtimes` toont alleen iOS 27.0 onder Xcode 27.0 (27A266a), en `scripts/tvos_sim.sh doctor` meldt "geen tvOS-simulator gevonden". Met een tvOS-runtime: `PLEYA_ASSISTANT_ENABLED=true dart run bin/verify.dart run ../scenarios/tvos.assistant.action-status.yaml --json` in `pleya_verify/runner`, na `scripts/tvos_sim.sh doctor`. Het scenario is dus ongetoetst tegen de echte app; een fout in id's of volgorde kan er nog in zitten.

**4. Op een echt toestel** (iPhone, iPad, Apple TV), nog te controleren:

- "Welke taken zijn vandaag mislukt op mijn servers? Start ze opnieuw." toont per herstarte taak eerst "Taak opnieuw gestart" en daarna "Taak loopt", "Taak klaar" of "Taak mislukt".
- "Scan alle filmbibliotheken op al mijn servers." toont per bibliotheek "Scan gestart" en blijft daar staan. Dat is geen fout: zonder operatie-id volgt Pleya een scan niet (BP-01a). De vervolgvraag naar de lopende taken staat eronder.

## Tipantwoord na hardwareronde op build 372 (16 oktober 2026)

Op de Apple TV gaf "geef me een tip voor vanavond" het antwoord "Hoe klinkt The Bear (2022)?", een stelling die als vraag las. Daarnaast noemde "Give me a tip based on what I watched" drie titels met jaartal terwijl er één kaart kwam, en "paar tips" ging samen met één kaart.

**Wijziging:** één regel in de systeemprompt, alleen met `my_watching`: voor een tip een stelling geven en nooit een vraag, alleen titels noemen die `my_watching` als pick teruggaf, niet meer dan gevraagd, en bij één pick één tip ("nooit 'een paar'").

**Meting** (echte modellen via Ollama Cloud, echte `my_watching`, steekproef; telkens vier runs per vraag):

| Model | Variant | Runs | Antwoord eindigt als vraag |
| --- | --- | --- | --- |
| glm-5.3-flash | zonder de regel, drie tipvragen met drie picks | 12 | 4 |
| glm-5.3-flash | met de regel, vijf vragen (drie picks, "drie tips" bij acht picks, één pick) | 20 | 0 |
| gemma4:31b | zonder de regel | 12 | 0 |
| gemma4:31b | met de regel | 20 | 0 |

"Geef me drie tips voor vanavond" bij acht picks: bij beide modellen in alle vier runs drie titels in de tekst en drie kaarten.

**Het geval "meer titels in de tekst dan kaarten" is wel gereproduceerd, en de oorzaak is gevonden.** "Zoek een film voor vanavond" telt als één gevraagde titel (`assistantAskedCount`: "een film"), en Pleya houdt het aantal kaarten bewust op het gevraagde aantal (test "an asked number caps the cards even when the answer names more"). Noemt het model dan twee titels, zoals "«Heat» (1995) ... Wil je iets luchtigers, dan «Puss in Boots» (2022)", dan staat er één kaart bij twee titels. Dit gebeurde in 2 van 40 runs met de nieuwe regel (één per model, bij die vraag). De regel "niet meer dan gevraagd" verlaagt de kans, maar sluit het niet uit. Besluit van Michel (16 oktober 2026): niet méér kaarten tonen, maar tekst en kaarten gelijk maken, met het gevraagde aantal leidend. Gebouwd: na het antwoord laat Pleya een zin weg die een aanbevolen titel noemt zonder kaart (voorbij het gevraagde aantal, niet in de gevalideerde resultaten, niet in de bibliotheek). Blijft er geen zin over die een kaart noemt, dan staat Pleya's eigen korte regel ("Dit zijn de titels die ik kon controleren." of, zonder kaarten, "Ik kon hier geen titel voor controleren."). Een titel die als reden wordt genoemd ("omdat je Reacher keek") blijft staan. Een gevraagd alternatief ("een film en een alternatief") telt als twee. Het model wordt niet nog eens aangeroepen en de kaarten blijven wat Pleya valideerde.

Grenzen van de regel, bewust zo gebouwd: een zin die zowel een titel met kaart als een titel zonder kaart noemt, vervalt helemaal (ook de uitleg bij de goede titel); een kale titel van één kort woord ("Her", "It", "Heat") telt alleen als genoemd met « » of met zijn jaartal, anders was gewone tekst eraan verloren; na een actie (aanvragen, op de lijst zetten) is de bevestiging het antwoord en blijft de tekst ongemoeid; een lijst houdt zijn regels en een titel tussen « » wordt nooit doormidden gesneden. Titels met een punt die niet tussen « » staan ("Mr. Robot"), en varianten als "&" tegenover "and" of een kaal ondertiteldeel, worden niet herkend; dan blijft die titel in de tekst staan.

Meting na de wijziging (echte modellen, steekproef, vijf runs per vraag, vier vragen: "zoek een film voor vanavond", "geef me een tip voor vanavond", "geef me drie tips voor vanavond", "een film voor vanavond en een alternatief", en voor de laatste ronde met de uiteindelijke code): bij glm-5.3-flash en gemma4:31b noemde de tekst in 40 van 40 runs precies de titels van de kaarten (1, 1, 3 en 2 kaarten per vraag), eindigde geen antwoord als vraag en viel de neutrale regel nergens terug. De eerdere meting zonder de wijziging (twee van de 40 runs, bij "zoek een film voor vanavond", met meer titels in de tekst dan kaarten) is een aparte reeks van 20 runs per model en geen vergelijking op dezelfde runs.

**Niet gemeten:** de situatie op het toestel zelf, andere modellen, lijsten met afkortingen en titels met een punt buiten « », en picks die niet in de bibliotheek staan (de aanname dat Spider-Man: Homecoming en Emily in Paris daarom geen kaart kregen is niet uit het logboek gecontroleerd).

## Hardwarechecklist iOS 369 en tvOS 370 (vanavond)

De builds 369 (iPhone en iPad) en 370 (Apple TV) bevatten de vanavond-route; de teksten staan in beide binaries (markers geteld op 16 oktober 2026, zie PR #347). Op een toestel is niets bevestigd. Voorwaarde: het buildnummer in Instellingen klopt, een beheerdersprofiel met minstens één server online, Big P aan met een ingesteld model. Noteer per punt geslaagd of gefaald, het model en de taal. De chips zijn drie willekeurige mogelijkheden: staat een genoemde chip er niet, open Big P opnieuw. Een getypte vraag telt niet als chip; typ alleen als een punt dat zegt.

1. **Vanavond.** Tik een chip over vanavond, zoals "Wat uit mijn bibliotheek kan ik vanavond kijken?" (Engels: "What in my library can I watch tonight?"), en daarna een vervolgvraag. Geslaagd: het eerste tool in de stappenlijst is `search_catalog` of `find_media`, en het antwoord toont titels uit je eigen bibliotheek als kaarten. Herhaal met de chip voor een komedie en voor een serie starten zodra die langskomen.
2. **Kinderprofiel.** Wissel naar een kinderprofiel. Er kan eerst een kaart voor de leeftijd van het kind verschijnen; vul die in, dat is geen fout. Geslaagd: de chips zijn alleen kijkvragen (vanavond, serie starten, voor de kinderen, ongezien, nieuw binnen, omschrijven), de vanavond-vraag toont alleen titels die de leeftijdscontrole passeren, en het antwoord noemt geen kijkgeschiedenis. De leeftijdscontrole is bewust ruim; beoordeel zelf of een getoonde titel past.
3. **Tip (typen).** Typ "Geef me een tip voor vanavond" en "Zoek een film voor vanavond" (zonder het woord bibliotheek). Geslaagd: je krijgt smaakpicks of aanbevelingskaarten zoals voorheen, met `my_watching` als eerste tool, niet een doorverwijzing naar de bibliotheeklijst.
4. **Kijklijst (typen).** Typ "Wat staat er vanavond op mijn kijklijst in mijn bibliotheek?". Pleya heeft voor een kijklijst in de bibliotheek geen eigen tool, dus het model kan van alles kiezen. Geslaagd: het eerste tool is niet `search_catalog` met de vanavond-route, en het antwoord doet niet alsof het een kijklijst is als dat niet zo is. Een eerlijk "dat kan ik niet" telt als geslaagd. De Trakt-chip hoort niet te verschijnen, want Trakt-aanmelden staat in geen enkele build aan.
5. **Apple TV (alleen 370).** Bedien met de afstandsbediening. Geslaagd: je komt met de D-pad bij de chips, de focus staat zichtbaar op de gekozen chip, en opnieuw openen toont meestal een andere set van drie (nooit bewust dezelfde als net daarvoor). Of de D-pad alle chips bereikt is hier niet uit de code vastgesteld; beschrijf wat je ziet.
6. **Vastleggen.** Bij een gefaalde vraag: het model, de taal, het eerste tool in de stappenlijst en een schermafbeelding. Zet het resultaat in een nieuwe regel in de tabel "Rondes" met in de opmerking "toestel", en met jouw model en taal in de kolommen Model en Taal.
