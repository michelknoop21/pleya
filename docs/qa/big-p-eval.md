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
| Kinderprofiel zegt "dat onthoud ik" | Productfout, zichtbaar na een scherpere check (de nulmeting telde alleen kaarten) | BP-11h, gemerged; de case is een gewoon hard geval; gemeten in een aparte run op die case: gemma4:31b 3 van 3, glm-5.3-flash 1 van 3 fout |
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

- gemma4:31b: 8 cases verbeterd, 1 regressie (`ser-next-season-no-source`, van 2 van 3 naar 0 van 3). Dat is een fout in de check: gemma zegt "Ik kan deze informatie niet vinden" en `EvalHonestMissing` herkende "ik kan ... niet" niet als erkenning. Gerepareerd in deze PR, met een negatieve controle.
- glm-5.3-flash: 11 cases verbeterd, geen regressie.
- Alle drie de oorspronkelijke productfouten zijn weg: `sea-request-needs-yes` 3 van 3 goed bij beide modellen, de dubbele kaarten zijn bijna weg (nog één geval: glm toont «The Bear» twee keer bij `ser-next-season-no-source`), en het kinderprofiel zegt niet meer "dat onthoud ik".

Nog open na deze meting:

- `ser-next-season-no-source`: bij glm wisselend. De check telde een vraag aan de gebruiker ("Wil je dat ik nakijk of er afleveringen ontbreken van seizoenen die al uit zijn?") ten onrechte als bewering; een zin met een vraagteken telt nu niet meer. Eén glm-antwoord was wel een echte verzonnen bewering ("seizoen 4 verscheen in juni 2025 ... vijfde seizoen naar verwachting in 2026").
- `disc-keyword`, `disc-english` (gemma), `disc-empty-honest` en `ser-short-series` (glm) en `adm-search-with-offline-server`: soms geen kaart, een kaart te veel, een begonnen serie als ongezien of de offline server niet genoemd. Bij die laatste staat `servers_offline` nu wel in het resultaat; het model noemt hem niet altijd.
- `rec-seen-five-others` (glm): de vervolgbeurt toont nog 15 tot 19 kaarten, herhaalt eerder getoonde titels en toont begonnen series.
- Eén meting per versie: de spreiding tussen twee runs van dezelfde code is nog niet gemeten, dus kleine verschillen zijn geen bewijs.

## Derde meting na BP-11k (18 oktober 2026)

Code: main op 2394cdea, dezelfde opzet (2 modellen, 60 cases, 3 pogingen, 360 runs, label `volledig-na-11k`), geen providerfouten. Vergeleken met de tweede meting:

| Model | Runs geslaagd | Cases die in alle 3 pogingen slagen |
| --- | --- | --- |
| gemma4:31b | 171 van 180 (eerst 170) | 56 van 60 (eerst 56) |
| glm-5.3-flash | 169 van 180 (eerst 172) | 55 van 60 (eerst 55) |

Per saldo is er niets aantoonbaar verbeterd of verslechterd: de verschillen zijn drie runs of minder. Of dat binnen de ruis valt, is niet gemeten (zie Open). Wat gericht is gemeten:

- `ser-short-series` (glm): van 2 van 3 naar 3 van 3. Begonnen series komen met `unwatched=true` niet meer als kaart terug (BP-11k). Verder werden `adm-search-with-offline-server` (glm) en bij gemma `disc-english`, `disc-keyword` en `ser-next-season-no-source` beter; BP-11k raakt die cases niet.
- Twee promptregels (eerder getoonde titels mogen niet terugkomen; één zoekopdracht voor een genoemd aantal) zijn geprobeerd en geschrapt: gemma zakte met de regels bij `rec-seen-five-others` van 3 van 3 naar 0 van 3, zonder de regels was het weer 3 van 3.
- Regressies bij glm: `ser-finished-show` (3 van 3 naar 0 van 3, 18 kaarten waar er 2 mochten zijn), `disc-empty-honest` (2 van 3 naar 0 van 3, 3 tot 5 kaarten waar er geen mochten zijn) en `rec-light-after-dinner` (3 van 3 naar 2 van 3, films bij een serievraag). Bij gemma: `con-everyone-no-capability` (3 van 3 naar 0 van 3, drie kaarten, ook zonder de promptregels) en `adm-search-with-offline-server` (1 van 3 naar 0 van 3, noemt de offline server niet).
- Waarschijnlijke oorzaak bij glm, uit de kaartaantallen afgeleid en niet met een fix getest: een model dat meerdere zoekopdrachten doet, toont de kaarten van alle zoekopdrachten, ook als het er maar enkele noemt. Bij gemma `con-everyone-no-capability` past dit niet: daar is het één zoekopdracht die drie titels noemt, dus de oorzaak is nog onbekend.

## Ruismeting: dezelfde code twee keer (18 oktober 2026)

Dezelfde commit (400c6fd1), dezelfde opzet, twee volledige runs: `volledig-na-11l` en `ruis-herhaling-400c6fd1` (360 runs elk, geen providerfouten in de herhaling). Dit is de eerste meting van de spreiding; het zijn twee runs, geen steekproef waar je een betrouwbaarheidsinterval uit trekt.

| Model | Runs geslaagd, eerste / tweede | Cases altijd goed, eerste / tweede | Cases waarvan het aantal geslaagde pogingen verschilt |
| --- | --- | --- | --- |
| gemma4:31b | 173 / 167 van 180 | 57 / 55 van 60 | 3 van 60 |
| glm-5.3-flash | 166 / 170 (eerste had een providerfout) | 52 / 54 van 60 | 9 van 60 |

Wat dit zegt:

- Zonder één regel code te wijzigen verschuift het totaal bij gemma met 6 runs en bij glm met 4. Verschillen van die orde tussen twee metingen zijn dus geen bewijs voor een fix of een regressie. De drie "regressies" en vijf "verbeteringen" per model uit de eerdere vergelijkingen horen grotendeels in dezelfde orde.
- De vijf glm-cases die in de vorige meting als slechter werden genoemd (`con-kids-no-scan`, `con-series-not-film-reverse`, `sea-request-needs-yes`, `rec-light-after-dinner`, `disc-title-in-library`) staan in de herhaling weer op of boven hun oude niveau. Dat bevestigt dat het ruis was en geen gevolg van BP-11l.
- `rec-seen-five-others` (glm), het doel van BP-11l: 0, 3 en daarna 2 van 3 over drie runs. De verbetering is er, maar niet stabiel 3 van 3.
- `disc-english` (gemma) is geen ruis in de gewone zin: 3 van 3 in de run van 14:41 op 2394cdea, daarna 0 van 3 in beide runs op 400c6fd1, en 0 van 3 in een losse herhaling van alleen die case op zowel 2394cdea als 400c6fd1. Dezelfde code gaf dus een andere uitkomst. In elke mislukte poging geeft `trending_titles` een fout en geeft `search_catalog` niets terug. De oorzaak is niet vastgesteld; een bron die wisselt in de loop van de dag past erbij, maar dat is niet bewezen.
- `con-everyone-no-capability` (gemma) is 0 van 3 in alle drie de runs sinds 14:41 en dus een vaste fout. `disc-keyword` (gemma) gaat 2, 3, 0 van 3.

## HTTP-probleem in de live test

De eerste twee pogingen tot een nulmeting gaven bij gemma 180 van 180 en bij glm 68 van 180 runs een providerfout. De oorzaak lag niet bij Ollama: zodra de geheugenfixtures de Flutter-testbinding starten, beantwoordt die elk HTTP-verzoek met een lege 400. De live test zet daarom voor elke poging `HttpOverrides.global = null` terug. Het record bevat sindsdien `http_error` (status en begin van het antwoord) bij een niet-200.

## Een nieuwe fout toevoegen

Maak één `EvalCase` in het gebied dat past (`test/assistant/eval/cases/`), met een vijandig gescript antwoord dat de fout laat zien en de harde checks die hem vangen. Is de fout nog niet opgelost, geef de case dan `expectFail: '<ID>'`: CI faalt zodra de fout stil verdwijnt, en het rapport telt hem als bekend in plaats van als regressie. Een nieuwe harde check krijgt een negatieve controle in `big_p_eval_checks_extra_test.dart`.

## Open

- `adm-search-with-offline-server` is met BP-11e een gewoon hard geval; de nulmeting is nog van vóór die fix, dus het live effect is niet gemeten.
- De beheer- en huishoudcases (regel 2 en 7) bewijzen alleen de weigering zonder bevoegdheid; ze wachten op een inzichtenfixture.
- De kwaliteitsbeoordelaar (stap 5) is uitgesteld.
- De ruis is gemeten met één herhaling (zie de ruismeting); een derde run op dezelfde code zou de schatting verbeteren.
- Kaarten van meerdere zoekopdrachten in één beurt worden samen getoond, ook als het antwoord er maar enkele noemt (waarschijnlijk de oorzaak bij `rec-seen-five-others`, `ser-finished-show` en `disc-empty-honest` van glm; niet getest).
