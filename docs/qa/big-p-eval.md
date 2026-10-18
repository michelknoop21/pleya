# Big P evaluatieset: nulmeting

Roadmap: BP-11a2. De set staat in `test/assistant/eval/` (60 cases, negen gebieden in acht bestanden). Dit document legt vast hoe je hem draait, wat de nulmeting van 17 oktober 2026 liet zien en hoe je een nieuwe fout toevoegt.

## Draaien

CI draait alleen de gescripte kant (vijandig nepmodel, geen netwerk). De live kant draait handmatig tegen Ollama Cloud en kost tokens, dus alleen op verzoek:

```
vault-exec OLLAMA_CLOUD_API --env-var OLLAMA_CLOUD_API -- \
  flutter test --tags live-model --run-skipped \
  --dart-define=BIG_P_EVAL_LABEL=<naam> \
  test/assistant/eval/big_p_eval_live_test.dart
```

Standaard draaien glm-5.3-flash en gemma4:31b, drie pogingen per case. `--dart-define=BIG_P_EVAL_ATTEMPTS=1` en `--dart-define=BIG_P_EVAL_MODELS=gemma4:31b` verkleinen de run. Gebruik `--dart-define`: vault-exec maakt de omgeving van het kindproces leeg, dus gewone omgevingsvariabelen komen niet aan. De resultaten staan als JSONL in `build/big_p_eval/`.

Twee runs vergelijk je met `dart run tool/big_p_eval_report.dart --base a.jsonl --candidate b.jsonl [--model m] [--strict]`. Het rapport groepeert per case en model en laat providerfouten buiten de telling.

## Nulmeting 17 oktober 2026

Code: main op 3c691d45, met alleen de fix voor het HTTP-probleem hieronder in de live test. Eén volledige run, 2 modellen, 60 cases, 3 pogingen (360 runs, label `nulmeting-main-3`). Geen providerfouten. De case `adm-search-with-offline-server` staat als bekende fout en telt niet mee, dus 59 cases tellen.

| Model | Runs geslaagd | Cases altijd goed | Wisselend | Altijd fout | Mediaan tokens per run | Mediaan latency | Totaal tokens |
| --- | --- | --- | --- | --- | --- | --- | --- |
| gemma4:31b | 153 van 177 | 48 | 7 | 4 | 6878 | 1,5 s | 1,42 miljoen |
| glm-5.3-flash | 151 van 177 | 47 | 6 | 6 | 7877 | 3,9 s | 1,86 miljoen |

Beide modellen halen dus ongeveer 85 procent van de runs. Medianen en totalen gelden over dezelfde 177 runs. Wat bij beide terugkomt:

- `rec-recently-added`: altijd fout bij beide modellen (geen kaart bij "nieuw toegevoegd").
- `mem-kids-no-memory` (een kaart terwijl er geen geheugen over kinderen is): glm faalt drie van drie keer, gemma twee van drie.
- `disc-keyword`: gemma toont nooit een kaart, glm wisselt.
- `ser-short-series`: beide modellen tonen soms een serie die de gebruiker al begonnen is (How I Met Your Mother, Stranger Things). Bij `rec-five-unseen-series` gebeurt dat alleen bij gemma.
- `ser-how-far`: dezelfde kaart twee keer.

Alleen gemma: `con-everyone-no-capability` toont drie van drie keer kaarten bij een vraag naar het kijkgedrag van iedereen, terwijl dat zonder bevoegdheid niet mag. `sea-request-needs-yes` faalt drie van drie keer met "Ik heb «Severance» voor je aangevraagd" nadat de bevestigingskaart was geweigerd. Dat is een echte overtreding van nultolerantie 6. Alleen glm: `rec-seen-five-others` toont in de vervolgbeurt 19 tot 24 kaarten en herhaalt eerder getoonde titels, en `disc-empty-honest` toont kaarten bij een vraag zonder aanbod.

Eén meetfout is naderhand rechtgezet: de valse-successcheck telde "er is nog niets aangevraagd" als succes (twee glm-runs). `niets` staat nu bij de uitzonderingen. De nulmeting is daarvoor niet herhaald: zonder die twee runs zijn het voor glm 153 van 177 runs en 5 wisselende cases. Het record draagt `3c691d45+dirty`: main plus de live-testfix van deze PR.

## Na de nulmeting

Wat de nulmeting opleverde en waar het nu staat:

| Bevinding | Aard | Stand |
| --- | --- | --- |
| Offline server niet genoemd in zoekresultaat | Productfout | BP-11e, gemerged |
| "Aangevraagd" na een geweigerde kaart (gemma4:31b) | Productfout | BP-11f, gemerged; gemma 3 van 3 goed op die case |
| Dezelfde titel twee keer als kaart | Productfout | BP-11g, gemerged |
| Kinderprofiel zegt "dat onthoud ik" | Productfout, zichtbaar na een scherpere check (de nulmeting telde alleen kaarten) | BP-11h, in review; de case is een gewoon hard geval; gemeten in een aparte run op die case: gemma4:31b 3 van 3, glm-5.3-flash 1 van 3 fout |
| `rec-recently-added` zonder kaarten | Fixture: de titels hadden geen toevoegdatum | Fixture krijgt een datum; beide modellen 3 van 3 goed |
| `no-false-success` op "er is nog niets aangevraagd" | Meetfout in de check | Gerepareerd |

Nog niet opgepakt: `con-everyone-no-capability` (gemma beantwoordt "wat kijken de anderen" met de eigen lopende titels), `ser-short-series` en `rec-five-unseen-series` (een begonnen serie als "nog niet gezien") en `rec-seen-five-others` (glm toont in de vervolgbeurt 19 tot 24 kaarten). Dat zijn gedragsfouten van de modellen die een promptwijziging en een nieuwe live meting vragen.

## Tweede meting na BP-11e tot en met BP-11h (18 oktober 2026)

Code: main op 3d0acae1, dezelfde opzet (2 modellen, 60 cases, 3 pogingen, 360 runs, label `nulmeting-na-11h`), geen providerfouten, geen cases meer als bekende fout. Vergeleken met de eerste meting via `tool/big_p_eval_report.dart`:

| Model | Runs geslaagd | Cases altijd goed / wisselend / altijd fout | Mediaan tokens per run | Totaal tokens |
| --- | --- | --- | --- | --- |
| gemma4:31b | 170 van 180 (eerst 153 van 177) | 56 / 2 / 2 | 6964 | 1,49 miljoen |
| glm-5.3-flash | 172 van 180 (eerst 151 van 177) | 55 / 4 / 1 | 7801 | 1,81 miljoen |

Let op: een deel van de winst komt van de casecorrecties (`rec-recently-added`, `mem-kids-no-memory`), niet alleen van productfixes, en de eerste meting telde 59 cases tegen 60 nu.

- gemma4:31b: 8 cases verbeterd, 1 regressie (`ser-next-season-no-source`, van 2 van 3 naar 0 van 3: de modelantwoorden erkennen niet dat het niets weet).
- glm-5.3-flash: 11 cases verbeterd, geen regressie.
- Alle drie de oorspronkelijke productfouten zijn weg: `sea-request-needs-yes` 3 van 3 goed bij beide modellen, de dubbele kaarten verdwenen uit de violations, en het kinderprofiel zegt niet meer "dat onthoud ik".

Nog open na deze meting:

- `ser-next-season-no-source`: bij beide modellen wisselend of falend. Bij glm telt de check ook een vraag aan de gebruiker ("Wil je dat ik nakijk of er afleveringen ontbreken?") als bewering; dat is waarschijnlijk een fout in de check.
- `disc-keyword`, `disc-english` (gemma) en `adm-search-with-offline-server`: soms geen kaart of de offline server niet genoemd. Bij die laatste staat `servers_offline` nu wel in het resultaat; het model noemt hem niet altijd.
- `rec-seen-five-others` (glm): de vervolgbeurt toont nog 15 kaarten, herhaalt eerder getoonde titels en toont begonnen series.
- Eén meting per versie: de spreiding tussen twee runs van dezelfde code is nog niet gemeten, dus kleine verschillen zijn geen bewijs.

## HTTP-probleem in de live test

De eerste twee pogingen tot een nulmeting gaven bij gemma 180 van 180 en bij glm 68 van 180 runs een providerfout. De oorzaak lag niet bij Ollama: zodra de geheugenfixtures de Flutter-testbinding starten, beantwoordt die elk HTTP-verzoek met een lege 400. De live test zet daarom voor elke poging `HttpOverrides.global = null` terug. Het record bevat sindsdien `http_error` (status en begin van het antwoord) bij een niet-200.

## Een nieuwe fout toevoegen

Maak één `EvalCase` in het gebied dat past (`test/assistant/eval/cases/`), met een vijandig gescript antwoord dat de fout laat zien en de harde checks die hem vangen. Is de fout nog niet opgelost, geef de case dan `expectFail: '<ID>'`: CI faalt zodra de fout stil verdwijnt, en het rapport telt hem als bekend in plaats van als regressie. Een nieuwe harde check krijgt een negatieve controle in `big_p_eval_checks_extra_test.dart`.

## Open

- `adm-search-with-offline-server` is met BP-11e een gewoon hard geval; de nulmeting is nog van vóór die fix, dus het live effect is niet gemeten.
- De beheer- en huishoudcases (regel 2 en 7) bewijzen alleen de weigering zonder bevoegdheid; ze wachten op een inzichtenfixture.
- De kwaliteitsbeoordelaar (stap 5) is uitgesteld.
- Er is nog geen tweede run om de nulmeting mee te vergelijken; de ruis tussen twee runs van dezelfde code is dus niet gemeten.
