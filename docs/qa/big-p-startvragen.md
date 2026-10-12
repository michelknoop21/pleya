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

| Datum | Model | Taal | Vragen | Geslaagd | Gefaald | Opmerking |
| --- | --- | --- | --- | --- | --- | --- |
| nog niet gedraaid | | | | | | eerste catalogus van 12 oktober 2026 (22 mogelijkheden, 32 formuleringen per taal) |

## Status na een actievraag

Te controleren op een echt toestel, per platform (iPhone, iPad, Apple TV):

- "Welke taken zijn vandaag mislukt op mijn servers? Start ze opnieuw." toont per herstarte taak eerst "Taak opnieuw gestart" en daarna "Taak loopt", "Taak klaar" of "Taak mislukt".
- "Scan alle filmbibliotheken op al mijn servers." toont per bibliotheek "Scan gestart" en blijft daar staan. Dat is geen fout: zonder operatie-id volgt Pleya een scan niet (BP-01a). De vervolgvraag naar de lopende taken staat eronder.
