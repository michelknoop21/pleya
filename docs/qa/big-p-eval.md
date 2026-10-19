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

## Vierde meting na BP-11l (18 oktober 2026)

Code: main op 400c6fd1, dezelfde opzet (2 modellen, 60 cases, 3 pogingen, 360 runs, label `volledig-na-11l`). Eén glm-run (`disc-title-in-library`) gaf een providerfout en telt niet mee. Vergeleken met de derde meting:

| Model | Runs geslaagd | Cases in alle 3 pogingen goed |
| --- | --- | --- |
| gemma4:31b | 173 van 180 (eerst 171) | 57 van 60 (eerst 56) |
| glm-5.3-flash | 166 van 179 (eerst 169 van 180) | 52 van 60 (eerst 55) |

Gericht gemeten:

- `rec-seen-five-others` (glm): van 0 van 3 naar 3 van 3. Het antwoord noemt vijf titels op de vraag om "vijf andere", de kaarten van de overige zoekopdrachten verdwijnen. Gemma bleef 3 van 3.
- `ser-finished-show` en `disc-empty-honest` (glm) blijven 0 van 3: in die vragen staat geen aantal, dus de regel treedt niet op. `con-everyone-no-capability` (gemma) blijft 0 van 3, zoals verwacht: daar is het één zoekopdracht met drie genoemde titels.
- Ook beter: `ser-next-season-no-source` (glm en gemma), `disc-keyword` en `adm-search-with-offline-server` (gemma).

Wat slechter werd bij glm: `adm-search-with-offline-server`, `con-kids-no-scan`, `con-series-not-film-reverse`, `sea-find-request` en `sea-request-needs-yes` gingen elk van 3 van 3 naar 2 van 3, en `rec-light-after-dinner` van 2 naar 1. BP-11l is hier niet de oorzaak: de regel werkt alleen als de vraag een aantal van twee of meer noemt, en geen van deze vragen doet dat. Bij `sea-find-request` en `sea-request-needs-yes` roept het model in de mislukte runs `find_title` aan in plaats van `find_request_title` en toont het een kaart (Primer, Severance) die niet in de catalogus staat; dat is modelgedrag. Bij gemma ging `disc-english` van 3 van 3 naar 0 van 3: in alle drie de runs roept het model `search_catalog` en `trending_titles` aan, de trending-aanroep geeft een fout, en er komt geen kaart. Dat is bij elke poging hetzelfde patroon en dus waarschijnlijk geen ruis, maar de oorzaak is niet vastgesteld; BP-11l is het ook niet, want het antwoord noemt geen titels. De overige verschuivingen zijn niet herhaald en dus niet van ruis te onderscheiden.

De vergeleken stand (2394cdea tot 400c6fd1) bevat naast BP-11l ook de wijzigingen van RESUME-SYNC1 (mediaclients, kijkstatus, spelernavigatie). De "52 van 60" bij glm telt `disc-title-in-library` mee als goed: twee geldige runs slaagden, de derde was een providerfout.

## Ruismeting: dezelfde code twee keer (18 oktober 2026)

Dezelfde commit (400c6fd1), dezelfde opzet, twee volledige runs: `volledig-na-11l` en `ruis-herhaling-400c6fd1` (360 runs elk). De eerste run had één glm-providerfout (`disc-title-in-library`), de herhaling geen. Dit is de eerste meting van de spreiding; het zijn twee runs, geen steekproef waar je een betrouwbaarheidsinterval uit trekt.

| Model | Runs geslaagd, eerste / tweede | Cases altijd goed, eerste / tweede | Cases met een ander aantal geslaagde pogingen |
| --- | --- | --- | --- |
| gemma4:31b | 173 / 167 van 180 | 57 / 55 van 60 | 3 van 60 |
| glm-5.3-flash | 166 van 179 / 170 van 180 | 52 / 54 van 60 | 9 van 60 (8 zonder de providerfout) |

Bij glm telt de eerste run `disc-title-in-library` als altijd goed (2 geldige pogingen, beide geslaagd); strikt gelezen is dat 51 van 60.

Wat dit zegt:

- Zonder één regel code te wijzigen verschuift het totaal bij gemma met 6 runs en bij glm met 4. Verschillen van die orde tussen twee metingen zijn geen bewijs voor een fix of een regressie.
- Vijf glm-cases die in de vorige meting als slechter werden genoemd (`con-kids-no-scan`, `con-series-not-film-reverse`, `sea-request-needs-yes`, `rec-light-after-dinner`, `disc-title-in-library`) zijn in de herhaling weer 3 van 3. Dat past bij ruis, maar één herhaling bewijst het niet. Niet alles herstelde: `ser-finished-show` (0, 0, 0 over drie runs) en `disc-empty-honest` (0, 0, 1) bleven slecht.
- `rec-seen-five-others` (glm), het doel van BP-11l: 3 en 2 van 3 op 400c6fd1 (0 van 3 in de run daarvoor, op 2394cdea). De verbetering is er, maar niet stabiel 3 van 3.
- `disc-english` (gemma) is geen ruis in de gewone zin: 3 van 3 in de run van 14:41 op 2394cdea, daarna 0 van 3 in beide runs op 400c6fd1, en 0 van 3 in een losse herhaling van alleen die case op zowel 2394cdea als 400c6fd1. Dezelfde code gaf dus een andere uitkomst. In de mislukte pogingen roept gemma `search_catalog` en daarna `trending_titles` aan en komt er geen kaart; in de geslaagde pogingen van 14:41 roept het `trending_titles` niet aan en zoekt het twee keer. Het verschil zit dus in de toolkeuze van het model. De fout van `trending_titles` zelf is normaal (die komt in bijna elke case voor die hem aanroept). Het record bewaart alleen het aantal toolfouten, niet welke tool faalde of wat `search_catalog` teruggaf, dus waarom de zoekopdracht niets opleverde is niet vastgesteld.
- `con-everyone-no-capability` (gemma) is 0 van 3 in alle drie de runs sinds 14:41, een vaste fout. `disc-keyword` (gemma) gaat 2, 3, 0 van 3.

## Vijfde meting na BP-11k, BP-11l en BP-11m (19 oktober 2026)

Code: main op e914f5b7, dezelfde opzet (2 modellen, 60 cases, 3 pogingen, 360 runs, label `volledig-na-11m-e914f5b7`), geen providerfouten. BP-11m zijn de drie laatste reparaties: de dode eindstreep van `min_rating`, de regel dat "wat kijken de anderen" niet met `search_catalog` beantwoord wordt, en de omschrijving van `find_title` voor acteurs. Naast de twee eerdere runs op dezelfde code (400c6fd1):

| Model | Runs geslaagd (na-11l / ruis-herhaling / nu) | Cases altijd goed (na-11l / ruis-herhaling / nu) |
| --- | --- | --- |
| gemma4:31b | 173 / 167 / 165 van 180 | 57 / 55 / 55 van 60 |
| glm-5.3-flash | 166 van 179 / 170 / 174 van 180 | 52 / 54 / 55 van 60 |

Bij gemma ligt de nieuwe run 2 en 8 runs onder de twee eerdere; bij glm 4 en 8 erboven. De ruis tussen twee runs op dezelfde code was 6 (gemma) en 4 (glm). Het verschil van 8 ten opzichte van na-11l ligt bij beide modellen net buiten wat die herhaling liet zien, maar in tegengestelde richting. Eén run per versie is te weinig om dat een effect te noemen.

Gericht gemeten, aantal pogingen van 3 geslaagd (na-11l / ruis-herhaling / nu):

- `ser-finished-show` (glm): 0 / 0 / 3 en `disc-empty-honest` (glm): 0 / 1 / 3. Dit zijn de twee cases die BP-11k (tool-niveau, begonnen series en de `min_rating`-melding) moest oplossen. Het is de enige verschuiving die over drie runs consistent is, maar nog één run.
- `disc-english` (gemma): 3 / 0 / 3. De toolkeuze van het model bepaalt de uitkomst (zie de ruismeting). Dat BP-11m de oorzaak is, is niet aangetoond; de omschrijving van `find_title` raakt deze vraag niet.
- `con-everyone-no-capability` (gemma): 0 / 0 / 0, onveranderd. De regel in het systeemprompt hielp niet: gemma roept `watch_stats` aan, krijgt `unknown_tool` en valt terug op `search_catalog` met `in_progress`. In de nieuwe run toont het zelfs 60 kaarten. Dit is niet met een prompt te sluiten en vraagt een wijziging op tool- of resultaatniveau; die is niet gedaan.
- `rec-seen-five-others` (glm): 3 / 2 / 2. Beter dan voor BP-11l (0), niet stabiel 3 van 3.

Slechter in de nieuwe run:

- `rec-light-after-dinner` (gemma): 3 / 3 / 0. In alle drie de pogingen komt «Toy Story» als kaart terwijl een serie gevraagd is. Het record bewaart niet welke tools de zoekopdracht deden, dus de oorzaak is niet vastgesteld.
- `ser-next-season-no-source` (gemma 3 / 2 / 0, glm 3 / 2 / 1) en `ser-new-episodes-no-source` (glm 3 / 3 / 2). De meeste meldingen zijn echter eerlijke antwoorden die de check als bewering telt: "Ik kan helaas niet zien wanneer het volgende seizoen van «The Bear» komt" en "Ik weet helaas niet wanneer het volgende seizoen van The Bear komt" staan als `honest-missing: claims`. Bij gemma is dat het hele verschil. Dat is een zwakte van de check (een ontkenning in de zin maakt een bewering niet ongeldig als de zin zelf het volgende seizoen noemt), geen aantoonbare achteruitgang van het product. Bij glm staan er wel echte beweringen tussen ("er lijken nieuwe afleveringen te zijn" op basis van een bijwerkdatum). De check is niet aangepast.
- `disc-keyword` (glm): 3 / 3 / 2, zonder kaart in de mislukte poging. Gemma 3 / 0 / 0.

Wat dit zegt: BP-11k heeft twee glm-cases omgezet die in alle voorgaande runs mislukten, en BP-11m heeft het doel (`con-everyone-no-capability`) niet gehaald. De totalen verschuiven ongeveer zoveel als de ruis, bij gemma omlaag en bij glm omhoog. Dat is geen bewijs dat de drie reparaties samen niets verslechteren: bij gemma staan `rec-light-after-dinner` en de check voor `ser-next-season-no-source` hier tegenover.

## HTTP-probleem in de live test

De eerste twee pogingen tot een nulmeting gaven bij gemma 180 van 180 en bij glm 68 van 180 runs een providerfout. De oorzaak lag niet bij Ollama: zodra de geheugenfixtures de Flutter-testbinding starten, beantwoordt die elk HTTP-verzoek met een lege 400. De live test zet daarom voor elke poging `HttpOverrides.global = null` terug. Het record bevat sindsdien `http_error` (status en begin van het antwoord) bij een niet-200.

## Een nieuwe fout toevoegen

Maak één `EvalCase` in het gebied dat past (`test/assistant/eval/cases/`), met een vijandig gescript antwoord dat de fout laat zien en de harde checks die hem vangen. Is de fout nog niet opgelost, geef de case dan `expectFail: '<ID>'`: CI faalt zodra de fout stil verdwijnt, en het rapport telt hem als bekend in plaats van als regressie. Een nieuwe harde check krijgt een negatieve controle in `big_p_eval_checks_extra_test.dart`.

## Open

- `adm-search-with-offline-server` is met BP-11e een gewoon hard geval; de nulmeting is nog van vóór die fix, dus het live effect is niet gemeten.
- De beheer- en huishoudcases (regel 2 en 7) bewijzen alleen de weigering zonder bevoegdheid; ze wachten op een inzichtenfixture.
- De kwaliteitsbeoordelaar (stap 5) is uitgesteld.
- De ruis is gemeten met één herhaling op 400c6fd1; de vijfde meting is een andere code en dus geen derde run op dezelfde code.
- `con-everyone-no-capability` (gemma) blijft 0 van 3 en vraagt een wijziging op tool- of resultaatniveau.
- De check `EvalHonestMissing` markeert een eerlijk "ik kan niet zien wanneer het volgende seizoen komt" als bewering; daardoor zijn `ser-next-season-no-source` en `ser-new-episodes-no-source` onbetrouwbaar tot de check is aangescherpt.
- `rec-light-after-dinner` (gemma, 0 van 3 met een filmkaart bij een serievraag) en de Library Doctor-oorzaak op het toestel zijn niet onderzocht.
- Kaarten van meerdere zoekopdrachten in één beurt worden samen getoond, ook als het antwoord er maar enkele noemt (waarschijnlijk de oorzaak bij `rec-seen-five-others`, `ser-finished-show` en `disc-empty-honest` van glm; niet getest).
