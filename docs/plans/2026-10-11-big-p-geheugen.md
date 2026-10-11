<!-- Directieve documentatie: vereist een onafhankelijke review (AGENTS.md) voor de merge. -->
# Big P: lokaal persoonlijk geheugen (BP-08a)

Status: voorstel, 11 oktober 2026. Roadmap: BP-08a. Mockup: `docs/assets/ios-unified/big-p-geheugen-43/` (PROPOSED). Stap 1 kan starten zodra open keuze 1 beslist is; stap 2 wacht op keuze 3; stap 3 wacht op akkoord op de mockup. Synchronisatie valt buiten dit plan en staat als BP-08b in de roadmap.

## Wat er al is

Gemeten op `04e5fbeb` (`main`, 11 oktober).

- Eén Drift-database, `AppDatabase` (`lib/database/app_database.dart:112`), `schemaVersion` 21, handgeschreven `onUpgrade` met `if (from < N)` en `_ignoreAlreadyExists`. Profielgebonden tabellen dragen een `profileId` als tekst zonder foreign key, omdat Plex Home-profielen virtueel zijn. Er zijn geen schema-dumps; `test/database/app_database_test.dart` test migraties met een bestands-database en pint de versie.
- Het actieve profiel komt uit `ActiveProfileProvider`. Bij een profielwissel wordt de providerboom herbouwd onder `ValueKey('profile-session:$activeId')` (`lib/navigation/profile_session_screen.dart:144`), dus een service die daar met een `profileId` wordt gemaakt, leeft precies één profielsessie.
- Verwijderen van een profiel loopt door één functie: `deleteProfile()` in `lib/screens/profile/profile_delete_flow.dart:48`, met `clearProfileScopedStores` voor de voorkeuren.
- Leeftijden van kinderen staan in `KidsAgesStore` (SharedPreferences, per profiel, nooit gesynct) en tellen alleen in de kindstand. Taalvoorkeuren, smaak (`AffinitySnapshots`), kijklog en kijklijst hebben elk al één eigenaar.
- Big P bouwt per vraag losse systeemregels (`assistant_run_loop.dart`); het gespreksgeheugen leeft alleen in het werkgeheugen (`_memoryMessages` in `assistant_run_prompt.dart:24`, 6000 tekens in `assistant_controller.dart:187`). `AssistantFieldSource.memory` bestaat en is ongebruikt.
- Er zijn twee bevestigpatronen. `AssistantPendingAction` blokkeert de run, eist een server en hertoetst `tool.serves`. De leeftijdenkaart is een eigen weergave met een controller-methode (`saveKidsAgesAndRetry`), zonder dat het model iets schrijft.
- De database is een onversleuteld SQLite-bestand in de documentenmap. Op iOS staat `UIFileSharingEnabled` aan (`ios/Runner/Info.plist:58`), dus het bestand is zichtbaar in Bestanden en gaat mee in de apparaatback-up. De logredactie herkent tokens en adressen, geen vrije tekst. De toolfout op `assistant_run_execute.dart:216` logt het volledige foutobject.
- `CredentialVault` bewaart zijn sleutel in SharedPreferences en maakt stil een nieuwe als die ontbreekt (`lib/services/credential_vault.dart:131-133`).

## Ontwerp

**Opslag.** Eén nieuwe tabel `AssistantMemories` in de bestaande database, schema 22 (migratie 21 naar 22):

| Kolom | Betekenis |
| --- | --- |
| `id` | tekst, UUID v4; stabiel en niet afgeleid van de inhoud, zodat een latere sync ernaar kan verwijzen |
| `profileId` | volle profiel-id, zoals in `MediaInteractions` |
| `category` | `preference`, `dislike`, `household`, `habit`, `other` |
| `value` | de zin zoals getoond: één regel, geen stuurtekens, maximaal 200 tekens |
| `valueKey` | `value` in kleine letters, zonder leestekens en dubbele spaties; uniek per profiel |
| `source` | `user_explicit`, `assistant_confirmed`, `settings_manual` |
| `createdAt`, `updatedAt` | UTC |

De unieke index op (`profileId`, `valueKey`) vangt letterlijk dezelfde zin, ook onder een andere categorie. Een herformulering ("heeft een hekel aan horror" naast "houdt niet van horror") is voor de database een ander feit; die samenvoeging loopt via bijwerken op id, zie hieronder. Wijzigt de gebruiker een feit met de hand, dan wordt de herkomst `settings_manual`. Verwijderen is hard; er zijn geen tombstones zolang er geen sync is. Het plafond is 200 feiten per profiel; daarboven weigert de service met een vaste code.

**`MemoryService`.** Eén klasse, gemaakt per profielsessie met het `profileId` in de constructor. API: `list({category, query})`, `add`, `update(id, ...)`, `delete(id)`, `clearAll()`, `relevantFor(question)`, plus `enabled`. Elke lees- en schrijfquery, ook op id, filtert op het `profileId` van de instantie; een id van een ander profiel bestaat voor deze service niet. Chat en instellingen gebruiken dezelfde instantie. Alleen `deleteProfile()` gebruikt een databasemethode met een profiel-id als argument, omdat het ook een niet-actief profiel wist.

`enabled` is een voorkeur per profiel, local-only geregistreerd in `PreferenceSyncPolicyRegistry` en opgenomen in `clearProfileScopedStores`. Standaard aan: er wordt alleen iets bewaard na een uitdrukkelijk verzoek of een ja, en uit betekent geen tools, geen context en geen voorstellen.

**Geen dubbele waarheid.** Het geheugen weigert wat al een eigenaar heeft: leeftijden van kinderen, taal- en ondertitelvoorkeur. De weigering komt terug als een vaste code, waarna Big P naar de juiste instelling verwijst. Het leeftijdsfilter blijft ongewijzigd. Het geheugenscherm toont de leeftijden uit `KidsAgesStore` als verwijsrij naar Kinderprofiel, alleen als er leeftijden zijn ingesteld.

**Kindstand.** In de kindstand leest en schrijft Big P geen geheugen: de tools staan in `kidsToolPolicy` op geweigerd en er komt geen contextregel. Het scherm blijft bereikbaar om te bekijken en te wissen; de rij "Vraag Big P over je geheugen" is daar verborgen.

**Context zonder extra modelcall.** `relevantFor` kiest lokaal op woordoverlap tussen de vraag en `value`. Maximaal 8 feiten en 600 tekens, elk met een korte verwijzing (de eerste 8 tekens van de id). Ze gaan als één systeemregel mee, geciteerd als gegevens en niet als instructie, naar het patroon van `_memoryMessages`. Staat het geheugen uit of is er geen treffer, dan komt er geen regel bij. Een feit uit het geheugen krijgt in de intent de herkomst `memory` en overschrijft nooit wat de gebruiker in de vraag zelf zegt (contract, voorrangsregel 4). Een herinnering verruimt nooit rechten of het leeftijdsfilter; daar komt een test voor.

**Big P.** Drie tools in een eigen bestand, `assistant_tools_memory.dart`; `serves` geeft false als het geheugen uit staat, zodat ze dan ook geen tokens kosten.

- `recall_memory(category?, query?)` leest, met een plafond van 30 feiten en 2000 tekens, en geeft de korte verwijzing per feit mee.
- `remember_fact(value, category, replaces?)` bewaart een nieuw feit of vervangt het feit waar `replaces` naar verwijst. Zo wordt "we kijken nu op zaterdag" een update van het vrijdagfeit en geen tweede rij.
- `forget_fact(ref)` stelt verwijderen voor.

Een onbekende of dubbelzinnige verwijzing geeft een vaste code terug en wijzigt niets. Botst een bijgewerkte tekst met een bestaand feit van hetzelfde profiel, dan weigert de service met `duplicate`.

Geen van de drie gebruikt `AssistantPendingAction`. Een schrijfactie die niet direct mag, wordt een voorstel op de run. Big P geeft eerst het gevraagde antwoord; daarna toont de app de kaart "Zal ik dit onthouden?" of "Zal ik dit vergeten?" met de voorgestelde tekst en categorie. Ja roept `MemoryService` aan via een controller-methode, naar het patroon van de leeftijdenkaart, na een controle dat het profiel nog hetzelfde is. Zonder ja wordt er niets bewaard, vervangen of gewist. De tekst op de kaart is de tekst die wordt opgeslagen; hij is door het model geformuleerd en door de service gevalideerd op lengte en vorm, en de gebruiker kan hem daarna in het scherm aanpassen.

Direct opslaan zonder kaart gebeurt alleen als de code het verzoek herkent: de vraag begint met een opdrachtvorm ("onthoud dat", "onthoud:", "remember that") en is geen vraagzin. Een titel als "Remember the Titans" verderop in de zin telt niet, en "Remember that film with the heist?" evenmin. Direct geldt alleen voor een nieuw feit. Vergeten en vervangen (`replaces`) gaan altijd via de kaart, omdat een verwijderd of overschreven feit niet terug te halen is; de kaart toont dan ook het feit dat verdwijnt. Per beurt mag hoogstens één schrijfactie direct; elke volgende wordt een voorstel. Big P meldt letterlijk wat er is opgeslagen, met een link naar het geheugen.

Dit raakt het gedragscontract: `docs/big-p-behaviour-contract.md` zet bevestiging van schrijfacties op voorrang 1 en eist nul mutaties zonder acceptatie. Direct opslaan na "onthoud dat" behandelt het verzoek zelf als de acceptatie. Die uitzondering komt als uitdrukkelijke regel in het contract, in dezelfde PR als stap 2, en geldt alleen voor het eigen geheugen van het actieve profiel. Zie open keuze 3.

**Vraag Big P over je geheugen.** De rij in het scherm opent Big P met een klaargezette vraag ("Wat weet je over mij?") in het invoerveld; de gebruiker verstuurt zelf. Op tv opent hij het assistentscherm op dezelfde manier.

**Privacy.** Voorstel: platte tekst, met dezelfde bescherming als de kijklog. Versleutelen met `CredentialVault` is afgewogen en afgeraden. De sleutel staat in SharedPreferences, dus de apparaatback-up bevat sleutel en database samen. Raakt alleen de sleutel weg (containerreset op macOS, hersteld toestel), dan is het hele geheugen onleesbaar zonder herstelpad. De winst zou alleen zijn dat de tekst in Bestanden niet leesbaar is, en dan zou ook `valueKey` versleuteld moeten zijn, wat de unieke index onbruikbaar maakt.

Wat wel gebeurt: geheugeninhoud komt in geen enkele logregel. De memory-bestanden krijgen een bron-scannende test naar het voorbeeld van `log_safety_test.dart`, en de toolfout op `assistant_run_execute.dart:216` logt voor deze tools alleen het type. De tabel wordt niet gesynct en niet geëxporteerd. De toolbeschrijving en het invoerveld vragen geen wachtwoorden, medische of financiële gegevens op te slaan. Bij een cloudmodel verlaten de gekozen feiten het toestel samen met de vraag; het scherm zegt dat.

## Drie stappen, elk een eigen PR

Stap 1 en 2 krijgen een adversariële review (roadmapregel voor BP-08a), stap 3 de volledige UI-review met Verify en beeld.

1. **Opslag.** Tabel, migratie 21 naar 22, `MemoryService`, de voorkeur aan/uit, wissen bij profielverwijdering. Tests: migratie vanaf 21 en verse installatie; profielisolatie voor lezen, bijwerken en verwijderen op id (twee profielen, geen kruistoegang); dezelfde zin twee keer geeft één rij; bijwerken naar een bestaande zin geeft `duplicate`; herstart (bestands-database sluiten en openen); profiel verwijderen wist rijen en voorkeur; weigering van leeftijd en taal; plafond; logverbod. Geen UI, geen assistentcode.
2. **Big P.** De drie tools, de contextregel, voorstelkaart, direct opslaan, kindbeleid, staplabels NL en EN, contractregel. Tests met het gescripte model: voorstel zonder ja bewaart niets; "onthoud dat" bewaart direct en precies één keer; een titel met remember en een vraagzin die met "remember that" begint bewaren niets direct; vergeten wist nooit zonder ja; een onbekende of dubbelzinnige verwijzing wijzigt niets; "onthoud dat" met `replaces` vervangt niet zonder ja; `replaces` vervangt; een ander profiel ziet niets; de budgetten van 600 en 2000 tekens; geheugen uit geeft geen tool en geen regel; kindstand; profielwissel tussen voorstel en ja; een herinnering verruimt het leeftijdsfilter niet.
3. **Beheer-UI.** Het scherm volgens de goedgekeurde mockup, telefoon, tablet en tv, met Pleya Verify-scenario's en beeld.

Gedeelde bestanden met ander BP-werk raakt stap 2 alleen op vaste plekken: één regel in de toollijst van `assistant_tools.dart`, één systeemregel in `assistant_run_loop.dart`, de drie rijen in `kidsToolPolicy` en de staplabels. De rest staat in nieuwe bestanden.

## Mockup: punten bij het akkoord

- Tv heeft geen zoekveld in beeld; de opdracht vraagt zoeken. Voorstel: een rij "Zoeken" die het systeemtoetsenbord opent.
- De schakelaartekst wordt "Big P onthoudt wat je hem vraagt te onthouden", omdat er niets automatisch wordt bewaard.
- In beeld en nu in het plan: de link "Bekijk geheugen" na direct opslaan, verwijderen van één herinnering met bevestiging, wissen kan ook als het geheugen uit staat.
- De voorstelkaart in 43 G staat in het echt onder het antwoord, niet in plaats ervan.

## Buiten scope en bekende grenzen

- Geen sync, geen export, geen embeddings of vectorzoeken, geen extra modelcall.
- Twee verschillend geformuleerde zinnen met dezelfde betekenis kunnen naast elkaar staan tot de gebruiker of Big P er één vervangt.
- Rijen van een Plex Home-gebruiker die uit de Home verdwijnt, blijven staan; daar bestaat nu voor geen enkele profieltabel een opruimpad.
- Een lokaal profiel heeft per toestel een andere id. BP-08b moet dat oplossen voordat er iets gesynct wordt, en heeft dan ook tombstones nodig.

## Open keuzes voor Michel

1. Platte tekst zoals de kijklog (voorstel) of toch versleutelen, met het risico op onleesbaar geheugen.
2. Kindstand: Big P gebruikt geen geheugen, het scherm blijft bereikbaar (voorstel).
3. "Onthoud dat ..." slaat direct op (vergeten en vervangen houden altijd een kaart), met een uitzondering in het gedragscontract (voorstel, volgt de opdracht), of altijd een kaart en geen contractwijziging.
4. Zoeken op tv via een rij met het systeemtoetsenbord (voorstel) of geen zoeken op tv.
