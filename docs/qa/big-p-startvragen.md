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

Te controleren op een echt toestel, per platform (iPhone, iPad, Apple TV):

- "Welke taken zijn vandaag mislukt op mijn servers? Start ze opnieuw." toont per herstarte taak eerst "Taak opnieuw gestart" en daarna "Taak loopt", "Taak klaar" of "Taak mislukt".
- "Scan alle filmbibliotheken op al mijn servers." toont per bibliotheek "Scan gestart" en blijft daar staan. Dat is geen fout: zonder operatie-id volgt Pleya een scan niet (BP-01a). De vervolgvraag naar de lopende taken staat eronder.

## Hardwarechecklist iOS 369 en tvOS 370 (vanavond)

De builds 369 (iPhone en iPad) en 370 (Apple TV) bevatten de vanavond-route; de teksten staan in beide binaries (markers geteld op 16 oktober 2026, zie de PR van deze checklist). Op een toestel is niets bevestigd. Voorwaarde: het buildnummer in Instellingen klopt, een beheerdersprofiel met minstens één server online, Big P aan met een ingesteld model. Noteer per punt geslaagd of gefaald, het model en de taal. De chips zijn drie willekeurige mogelijkheden: staat een genoemde chip er niet, open Big P opnieuw. Een getypte vraag telt niet als chip; typ alleen als een punt dat zegt.

1. **Vanavond.** Tik een chip over vanavond, zoals "Wat uit mijn bibliotheek kan ik vanavond kijken?" (Engels: "What in my library can I watch tonight?"), en daarna een vervolgvraag. Geslaagd: het eerste tool in de stappenlijst is `search_catalog` of `find_media`, en het antwoord toont titels uit je eigen bibliotheek als kaarten. Herhaal met de chip voor een komedie en voor een serie starten zodra die langskomen.
2. **Kinderprofiel.** Wissel naar een kinderprofiel. Er kan eerst een kaart voor de leeftijd van het kind verschijnen; vul die in, dat is geen fout. Geslaagd: de chips zijn alleen kijkvragen (vanavond, serie starten, voor de kinderen, ongezien, nieuw binnen, omschrijven), de vanavond-vraag toont alleen titels die de leeftijdscontrole passeren, en het antwoord noemt geen kijkgeschiedenis. De leeftijdscontrole is bewust ruim; beoordeel zelf of een getoonde titel past.
3. **Tip (typen).** Typ "Geef me een tip voor vanavond" en "Zoek een film voor vanavond" (zonder het woord bibliotheek). Geslaagd: je krijgt smaakpicks of aanbevelingskaarten zoals voorheen, met `my_watching` als eerste tool, niet een doorverwijzing naar de bibliotheeklijst.
4. **Kijklijst (typen).** Typ "Wat staat er vanavond op mijn kijklijst in mijn bibliotheek?". Pleya heeft voor een kijklijst in de bibliotheek geen eigen tool, dus het model kan van alles kiezen. Geslaagd: het eerste tool is niet `search_catalog` met de vanavond-route, en het antwoord doet niet alsof het een kijklijst is als dat niet zo is. Een eerlijk "dat kan ik niet" telt als geslaagd. De Trakt-chip hoort niet te verschijnen, want Trakt-aanmelden staat in geen enkele build aan.
5. **Apple TV (alleen 370).** Bedien met de afstandsbediening. Geslaagd: je komt met de D-pad bij de chips, de focus staat zichtbaar op de gekozen chip, en opnieuw openen toont meestal een andere set van drie (nooit bewust dezelfde als net daarvoor). Of de D-pad alle chips bereikt is hier niet uit de code vastgesteld; beschrijf wat je ziet.
6. **Vastleggen.** Bij een gefaalde vraag: het model, de taal, het eerste tool in de stappenlijst en een schermafbeelding. Zet het resultaat in een nieuwe regel in de tabel "Rondes" met in de opmerking "toestel", en met jouw model en taal in de kolommen Model en Taal.
