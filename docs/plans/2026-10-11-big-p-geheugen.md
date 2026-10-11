<!-- Directieve documentatie: vereist een onafhankelijke review (AGENTS.md) voor de merge. -->
# Big P: lokaal persoonlijk geheugen (BP-08a)

Status: voorstel, 11 oktober 2026. Roadmap: BP-08a. Mockup: `docs/assets/ios-unified/big-p-geheugen-43/` (PROPOSED). De UI-stap start pas na akkoord van Michel op de mockup. Synchronisatie valt buiten dit plan en staat als BP-08b in de roadmap.

## Wat er al is

De regelnummers hieronder zijn gemeten op `6e839160`; de bouwer controleert ze tegen `main`.

- Eén Drift-database, `AppDatabase` (`lib/database/app_database.dart`), `schemaVersion` 20, handgeschreven `onUpgrade` met `if (from < N)` en `_ignoreAlreadyExists`. Profielgebonden tabellen dragen een `profileId` als tekst zonder foreign key, omdat Plex Home-profielen virtueel zijn. Er zijn geen schema-dumps; `test/database/app_database_test.dart` test migraties met een bestands-database en pint de versie.
- Het actieve profiel komt uit `ActiveProfileProvider`. Bij een profielwissel wordt de providerboom herbouwd onder `ValueKey('profile-session:$activeId')`, dus een service die daar met een `profileId` wordt gemaakt, leeft precies één profielsessie.
- Verwijderen van een profiel loopt door één functie: `deleteProfile()` in `lib/screens/profile/profile_delete_flow.dart`. `deleteRecommendationDataForProfile` heeft een epoch-teller tegen rijen die na het wissen terugkomen.
- Leeftijden van kinderen staan in `KidsAgesStore` (SharedPreferences, per profiel, nooit gesynct). Taalvoorkeuren, smaak (`AffinitySnapshots`), kijklog en kijklijst hebben elk al één eigenaar.
- Big P bouwt per vraag losse systeemregels (`assistant_run_loop.dart`), heeft een gespreksgeheugen dat alleen in het werkgeheugen leeft (6000 tekens) en vraagt bevestiging via `AssistantPendingAction` en de bevestigkaart. `AssistantFieldSource.memory` bestaat al en is ongebruikt.
- De database is een onversleuteld SQLite-bestand in de documentenmap. Op iOS staat `UIFileSharingEnabled` aan, dus het bestand is zichtbaar in Bestanden en gaat mee in de apparaatback-up. De logredactie herkent tokens en adressen, geen vrije tekst.

## Ontwerp

**Opslag.** Eén nieuwe tabel `AssistantMemories` in de bestaande database, schema 21:

| Kolom | Betekenis |
| --- | --- |
| `id` | tekst, UUID v4; stabiel en niet afgeleid van de inhoud, zodat een latere sync ernaar kan verwijzen |
| `profileId` | volle profiel-id, zoals in `MediaInteractions` |
| `category` | `preference`, `dislike`, `household`, `habit`, `other` |
| `slot` | genormaliseerde sleutel van het feit (kleine letters, zonder leestekens); uniek per profiel en categorie |
| `value` | de zin zoals getoond, maximaal 200 tekens |
| `source` | `user_explicit`, `assistant_confirmed`, `settings_manual` |
| `createdAt`, `updatedAt` | UTC |

Een unieke index op (`profileId`, `category`, `slot`) maakt van opnieuw onthouden een update. Zo ontstaan geen dubbele feiten, en een bijgewerkt feit vervangt het oude in plaats van ernaast te staan. Verwijderen is hard; er zijn geen tombstones zolang er geen sync is.

**`MemoryService`.** Eén klasse, gemaakt per profielsessie met het `profileId` in de constructor. Geen methode neemt een profiel-id als argument, dus een aanroeper kan niet bij een ander profiel. API: `list({category, query})`, `get(id)`, `upsert`, `update`, `delete(id)`, `clearAll()`, `relevantFor(question)`, plus `enabled` (voorkeur per profiel, local-only geregistreerd in `PreferenceSyncPolicyRegistry`). Chat en instellingen gebruiken dezelfde instantie. Een epoch-teller naar het voorbeeld van de aanbevelingsdata voorkomt dat een schrijfactie na `clearAll()` of profielverwijdering een rij terugzet. `deleteProfile()` wist de rijen van dat profiel.

**Geen dubbele waarheid.** Het geheugen weigert wat al een eigenaar heeft: leeftijden van kinderen, taal- en ondertitelvoorkeur. De weigering komt terug als een vaste code, waarna Big P naar de juiste instelling verwijst. Het geheugenscherm toont de leeftijden als verwijsrij naar Kinderprofiel en leest ze uit `KidsAgesStore`. Het leeftijdsfilter blijft ongewijzigd.

**Kindprofielen.** Op een kindprofiel staat het geheugen uit: geen tools, geen context, geen scherm. Dat volgt de bestaande scheiding tussen kind- en volwassenstand.

**Context zonder extra modelcall.** `relevantFor` kiest lokaal: woordoverlap tussen de vraag en `value` plus `slot`, met `household` en `habit` als vaste kleine basis. Maximaal 8 feiten en 600 tekens. Ze gaan als één systeemregel mee, geciteerd als gegevens en niet als instructie, naar het patroon van `_memoryMessages`. Staat het geheugen uit of is er geen treffer, dan komt er geen regel bij. Een feit uit het geheugen krijgt in de intent de herkomst `memory` en overschrijft nooit wat de gebruiker in de vraag zelf zegt (contract, voorrangsregel 4).

**Schrijven via Big P.** Drie tools: `remember_fact`, `forget_fact`, `recall_memory`. Of de gebruiker expliciet om onthouden vroeg, bepaalt de code en niet het model: de intent-parser herkent "onthoud", "vergeet", "remember", "forget" in de vraag. Bij een expliciete vraag slaat Big P direct op en meldt wat er is opgeslagen. In elk ander geval levert `remember_fact` een `AssistantPendingAction` op en verschijnt de bevestigkaart; zonder ja wordt er niets bewaard. `forget_fact` vraagt altijd bevestiging. De kaart toont de gevalideerde waarde, nooit vrije modeltekst.

**Privacy.** De waarde wordt versleuteld opgeslagen met de bestaande `CredentialVault` (AES-GCM). Dat is verhulling tegen meelezen in het bestand en geen bescherming tegen iemand met het toestel in handen; het plan zegt dat ook in de UI niet mooier. Zoeken gebeurt daarom in het werkgeheugen, met een plafond van 200 feiten per profiel. Geheugeninhoud komt in geen enkele logregel: de memory-bestanden krijgen een bron-scannende test naar het voorbeeld van `log_safety_test.dart`, en de toolfout op `assistant_run_execute.dart:216` logt voor deze tools alleen het type. De tabel wordt niet gesynct en niet geëxporteerd. De toolbeschrijving en het invoerveld vragen geen wachtwoorden, medische of financiële gegevens op te slaan. Bij een cloudmodel verlaten de gekozen feiten het toestel samen met de vraag; het scherm zegt dat.

## Drie stappen, elk een eigen PR

1. **Opslag.** Tabel, migratie 20 naar 21, `MemoryService`, de voorkeur aan/uit, wissen bij profielverwijdering. Tests: migratie vanaf 20 en verse installatie, profielisolatie (twee profielen, geen kruislezen), upsert zonder duplicaat, herstart (bestands-database sluiten en openen), `clearAll` met een late schrijfactie, weigering van leeftijd en taal, logverbod. Geen UI, geen assistentcode.
2. **Big P.** De drie tools, de contextregel, expliciet tegenover voorgesteld, kindbeleid, staplabels NL en EN. Tests met het gescripte model: voorgesteld zonder ja bewaart niets, expliciet bewaart direct, een ander profiel ziet niets, het budget van 600 tekens, geheugen uit geeft geen regel, profielwissel tijdens een bevestiging. Adversariële review (roadmapregel voor BP-08).
3. **Beheer-UI.** Het scherm volgens de goedgekeurde mockup, telefoon, tablet en tv, met Pleya Verify-scenario's en beeld. Start na akkoord op de mockup.

## Buiten scope en bekende grenzen

- Geen sync, geen export, geen embeddings of vectorzoeken, geen extra modelcall.
- Rijen van een Plex Home-gebruiker die uit de Home verdwijnt, blijven staan; daar bestaat nu voor geen enkele profieltabel een opruimpad.
- Een lokaal profiel heeft per toestel een andere id. BP-08b moet dat oplossen voordat er iets gesynct wordt, en heeft dan ook tombstones nodig.

## Open keuzes voor Michel

1. Versleuteling van de waarde met `CredentialVault` (voorstel) of platte tekst zoals de kijklog.
2. Geheugen op kindprofielen uit (voorstel) of beperkt aan.
3. Expliciet "onthoud dat" zonder bevestigkaart (voorstel, volgt de opdracht) of altijd een kaart.
