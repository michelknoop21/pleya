# Pleya Server persoonlijke appaansluiting

Roadmap: C-05 / S14 / S20. Scope: pakket 0 en 1 van het gezamenlijke plan, plus Michels keuze om alle favorieten te tonen, ook zonder externe ID. Geen protocol-, productie-, merge- of releasevrijgave.

## Task 1: status en acceptatie
Lees masterlijst, matrix, DoD en bestaand ketenbewijs. Corrigeer clientclaims zonder serverwerk te heropenen; leg baseline en ontbrekend bewijs vast. Controle: git diff --check en onafhankelijke documentaire eindreview.

## Task 2: publieke persoonlijke interface
RED: publieke favoriet/rating/wire/capabilitytests. GREEN: bestaande personal-routes, veilige paginering, wirehydratie en specifieke capabilities. Ratings: negatief wist, 1–10 afronden, andere invoer weigeren. Controle: flutter test test/pleya_server/pleya_server_personal_test.dart test/pleya_server/pleya_server_capabilities_test.dart test/pleya_server/pleya_server_mappers_test.dart.

## Task 3: productie-kijklijst
RED: Pleya-source/factorytests, servergebonden identiteit zonder externe ID, profielwissel. GREEN: bestaande source/repository gebruiken; geen Verify-route in productie. Controle: flutter test test/services/watchlist_source_factory_test.dart test/services/pleya_favorites_source_test.dart.

## Task 4: spoorvoorkeuren en eindreview
RED: gedeelde voorkeurprioriteit, bewust opslaan/wissen, oude server en profielwissel. GREEN: bestaande track-manager/eigenaren gebruiken; geen automatische fallback opslaan. Controle: gerichte track-tests, scripts/ci_checks.sh en toepasselijke persoonlijke/kijklijsttests. UI: Verify-asserties en native beelden voor mobiel/TV. Onafhankelijke eindreview, masterlijst en compact bewijsrapport.
