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

Een tijdelijke test (niet gecommit) stuurt elke formulering, per taal, via `AssistantRun` naar Ollama Cloud met de echte toolnamen, beschrijvingen en eigenschappen. De tools zelf zijn stubs die `{ok: true}` teruggeven. De ronde is dus geen toestelrun: er zijn geen servers, bibliotheken of taken, en geen Seerr, Trakt of geheugen. Er is niet getikt op een chip; de vraag gaat als gewone prompt de run in.

De kolom "eerste tool" is de maat uit stap 4 hierboven. "Ergens in de run" telt ook runs die eerst een hulptool aanriepen (`list_servers`, `list_libraries`, `list_jobs`) en daarna het tool van de mogelijkheid.

### Wat faalde

Bij beide modellen, in beide talen, op beide profielen:

- **vanavond** ("What can I watch tonight?" / "Wat kan ik vanavond kijken?"): faalt in 7 van de 8 combinaties van model, taal en profiel (alleen glm op het kinderprofiel in het Nederlands slaagt). Beheerder: glm roept eerst `my_watching` en dan `trending_titles` aan, gemma alleen `my_watching`. Kinderprofiel (`my_watching` geblokkeerd): eerste tool `trending_titles`, bij gemma daarna `find_title`. Het bedoelde `search_catalog` of `find_media` komt niet vooraan.
- Andere vragen met dezelfde afwijking: "Find an exciting movie for tonight." (gemma beheerder en, glm kinderprofiel en: `trending_titles`, daarna `find_title`; `find_title` hoort niet bij deze mogelijkheid), "Welke serie kan ik nu beginnen?" (gemma beheerder nl: alleen `my_watching`; gemma kinderprofiel nl) en "Which series can I start now?" (gemma kinderprofiel en).
- Opgelost: de vragen noemen nu de bibliotheek ("What in my library can I watch tonight?", "Wat uit mijn bibliotheek kan ik vanavond kijken?", ook voor serie starten), en `AssistantIntent.tonightPick` (vanavond of tonight plus een bibliotheekwoord, zonder tip-, kijklijst-, aanvraag-, groeps- of andere-persoonwoorden) weigert `my_watching` en `trending_titles` met `use_search_catalog` en zet een noot voor het model. De vervolgvragen na een antwoord (`assistant.followUp.tonight`) zijn op dezelfde manier herschreven en geroute. Een vraag naar het populaire (trending, populair) houdt `trending_titles`. Zonder bibliotheekwoord ("Zoek een film voor vanavond") blijft `my_watching` het smaaktool, zoals de aanbevelingskaarten het gebruiken. Een eerste versie van de route zonder bibliotheekwoord brak die kaarten en is daarom verlaten. De ronde is herhaald voor vanavond, serie starten en kinderen: bij beide modellen, beide talen en beide profielen was het eerste tool `search_catalog` (40 van 40 runs, 5 per combinatie van model, taal en profiel).

Door de stubs niet te beoordelen (het model stopt bij het hulptool, omdat de stub geen server-, bibliotheek- of taak-id teruggeeft): scan, taken herstarten, servers vergelijken, bibliotheekdokter (gemma). Gemma loopt bij scan 4 tot 7 keer door `list_*`. Home-rij (glm) is een ander geval: glm riep alleen `search_catalog` aan (1 tot 4 keer) en nooit `create_home_row`; of dat aan de lege stubresultaten ligt, is niet vastgesteld. In de volgende ronde moeten `list_servers`, `list_libraries` en `list_jobs` een server, een bibliotheek en een mislukte taak teruggeven, of moet de ronde op een echt toestel.

Samen kijken: beide modellen riepen `recommend_together` direct aan met de deelnemers "family" of "gezin" (gemma nl: "me" en "gezin"). Een wedervraag over wie er meekijkt, het bedoelde gedrag, kwam niet voor.

Niet in deze ronde: Seerr-, Trakt- en geheugenvragen met een echte bron (het model zag de tools, maar er was niets achter), en Plex versus Jellyfin.

## Status na een actievraag

Te controleren op een echt toestel, per platform (iPhone, iPad, Apple TV):

- "Welke taken zijn vandaag mislukt op mijn servers? Start ze opnieuw." toont per herstarte taak eerst "Taak opnieuw gestart" en daarna "Taak loopt", "Taak klaar" of "Taak mislukt".
- "Scan alle filmbibliotheken op al mijn servers." toont per bibliotheek "Scan gestart" en blijft daar staan. Dat is geen fout: zonder operatie-id volgt Pleya een scan niet (BP-01a). De vervolgvraag naar de lopende taken staat eronder.
