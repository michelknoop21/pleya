<!-- Directieve documentatie: vereist een onafhankelijke review (AGENTS.md) voor de merge. -->
# Big P: lokaal persoonlijk geheugen (BP-08a)

Status: goedgekeurd door Michel op 11 oktober 2026, met de besluiten onderaan. Roadmap: BP-08a. Mockup: `docs/assets/ios-unified/big-p-geheugen-43/`, goedgekeurd door Michel op 11 oktober 2026 in de herziene vorm: het hoofdscherm is een geheugenoverzicht in lopende tekst. Synchronisatie valt buiten dit plan en staat als BP-08b in de roadmap.

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

**Geen dubbele waarheid.** Het geheugen weigert wat al een eigenaar heeft: leeftijden van kinderen, taal- en ondertitelvoorkeur. De weigering komt terug als een vaste code, waarna Big P naar de juiste instelling verwijst. Het leeftijdsfilter blijft ongewijzigd. Het lijstscherm "Herinneringen" toont de leeftijden uit `KidsAgesStore` als verwijsrij naar Kinderprofiel, alleen als er leeftijden zijn ingesteld.

**Kindstand.** In de kindstand leest en schrijft Big P geen geheugen: de tools staan in `kidsToolPolicy` op geweigerd en er komt geen contextregel. Het scherm blijft bereikbaar om te bekijken en te wissen: het toont dan de feiten als lijst, zonder geschreven overzicht, vervolgvragen of invoerveld.

**Context zonder extra modelcall.** `relevantFor` kiest lokaal op woordoverlap tussen de vraag en `value`. Maximaal 8 feiten en 600 tekens, elk met een korte verwijzing (de eerste 8 tekens van de id). Ze gaan als één systeemregel mee, geciteerd als gegevens en niet als instructie, naar het patroon van `_memoryMessages`. Staat het geheugen uit of is er geen treffer, dan komt er geen regel bij. Een feit uit het geheugen krijgt in de intent de herkomst `memory` en overschrijft nooit wat de gebruiker in de vraag zelf zegt (contract, voorrangsregel 4). Een herinnering verruimt nooit rechten of het leeftijdsfilter; daar komt een test voor.

**Big P.** Drie tools in een eigen bestand, `assistant_tools_memory.dart`; `serves` geeft false als het geheugen uit staat, zodat ze dan ook geen tokens kosten.

- `recall_memory(category?, query?)` leest, met een plafond van 30 feiten en 2000 tekens, en geeft de korte verwijzing per feit mee.
- `remember_fact(value, category, replaces?)` bewaart een nieuw feit of vervangt het feit waar `replaces` naar verwijst. Zo wordt "we kijken nu op zaterdag" een update van het vrijdagfeit en geen tweede rij.
- `forget_fact(ref)` stelt verwijderen voor.

Een onbekende of dubbelzinnige verwijzing geeft een vaste code terug en wijzigt niets. Botst een bijgewerkte tekst met een bestaand feit van hetzelfde profiel, dan weigert de service met `duplicate`.

Geen van de drie gebruikt `AssistantPendingAction`. Een schrijfactie die niet direct mag, wordt een voorstel op de run. Big P geeft eerst het gevraagde antwoord; daarna toont de app de kaart "Zal ik dit onthouden?" of "Zal ik dit vergeten?" met de voorgestelde tekst en categorie. Ja roept `MemoryService` aan via een controller-methode, naar het patroon van de leeftijdenkaart, na een controle dat het profiel nog hetzelfde is. Zonder ja wordt er niets bewaard, vervangen of gewist. De tekst op de kaart is de tekst die wordt opgeslagen; hij is door het model geformuleerd en door de service gevalideerd op lengte en vorm, en de gebruiker kan hem daarna in het scherm aanpassen.

Direct opslaan zonder kaart gebeurt alleen als de code het verzoek herkent: de vraag begint met een opdrachtvorm ("onthoud dat", "onthoud:", "remember that") en is geen vraagzin. Een titel als "Remember the Titans" verderop in de zin telt niet, en "Remember that film with the heist?" evenmin. Direct geldt alleen voor een nieuw feit. Vergeten en vervangen (`replaces`) gaan altijd via de kaart, omdat een verwijderd of overschreven feit niet terug te halen is; de kaart toont dan ook het feit dat verdwijnt. Per beurt mag hoogstens één schrijfactie direct; elke volgende wordt een voorstel. Big P meldt letterlijk wat er is opgeslagen, met een link naar het geheugen.

Dit raakt het gedragscontract: `docs/big-p-behaviour-contract.md` zet bevestiging van schrijfacties op voorrang 1 en eist nul mutaties zonder acceptatie. Direct opslaan na "onthoud dat" behandelt het verzoek zelf als de acceptatie. Die uitzondering komt als uitdrukkelijke regel in het contract, in dezelfde PR als stap 2, en geldt alleen voor het eigen geheugen van het actieve profiel (besluit 3).

**Geheugenoverzicht.** Het hoofdscherm toont een overzicht dat Big P in de tweede persoon schrijft, met daaronder drie vervolgvragen ("Duik dieper"). De feiten in `AssistantMemories` blijven de waarheid; het overzicht is afgeleid, wordt nooit zelf bewerkt en nooit als bron voor een antwoord gebruikt.

- De secties liggen vast: `overview` (een korte samenvatting over alle feiten heen) en daarna de vijf categorieën. Een sectie zonder feiten vervalt, dus "Overig" staat er alleen als er zulke feiten zijn.
- Het overzicht staat in een tweede kleine tabel in dezelfde migratie, `AssistantMemoryOverviews`: `profileId` (sleutel), `factsHash`, `locale`, `status` (`ok` of `failed`), `body` (JSON met secties en vervolgvragen), `generatedAt`. De hash loopt over de id, `updatedAt` en de tekst van alle feiten van het profiel, de taal en een formaatversie. `MemoryService` bewaart en leest het overzicht (`overview()`, `overviewIsStale()`, `saveOverview(...)`); de modelaanroep zelf zit in de assistentlaag en komt in stap 2. Ook deze lezen en schrijven alleen de rij van het eigen profiel.
- De modelaanroep gaat uit als het scherm openstaat en de hash afwijkt van de bewaarde rij: bij het openen na een wijziging, en direct na een wijziging via het invoerveld of het lijstscherm. Gelijke hash: de bewaarde tekst wordt getoond en er gaat niets uit. Een schrijfactie vanuit het gesprek start geen aanroep; dat gebeurt pas als het scherm opent.
- Levert het model ongeldige uitvoer, dan wordt die poging met haar hash bewaard als `failed`. Het scherm toont dan de lijst en probeert het niet opnieuw tot de feiten wijzigen of de gebruiker "Overzicht opnieuw schrijven" kiest. Zo kan een model dat het formaat niet haalt geen aanroep per bezoek kosten. Geen verbinding, een time-out, een fout van de provider of geen ingesteld model wordt niet bewaard: het volgende bezoek probeert het opnieuw.
- Naast gewijzigde feiten zijn er drie aanleidingen voor een nieuwe aanroep: een andere app-taal, een nieuwe formaatversie na een update, en de handmatige actie "Overzicht opnieuw schrijven". Het geheugen uit- en weer aanzetten doet dat niet: het bewaarde overzicht blijft staan, net als de feiten.
- De aanroep heeft geen tools en een vast JSON-formaat als uitvoer. De invoer is begrensd op 8000 tekens aan feiten, de laatst gewijzigde eerst; passen ze niet allemaal, dan zegt de voetregel op hoeveel van de herinneringen het overzicht is gebaseerd.
- De uitvoer wordt gevalideerd: alleen de vaste secties, platte tekst, een lengteplafond per sectie, hoogstens drie vervolgvragen van maximaal 80 tekens. Een vervolgvraag die met een opdrachtvorm begint ("onthoud", "vergeet", "remember", "forget") wordt weggegooid. Ongeldige uitvoer, geen ingesteld model, geen verbinding of een fout: het scherm toont de feiten per categorie als lijst.
- Leeftijden gaan niet naar het model. Zijn er leeftijden ingesteld, dan voegt de app zelf onder Huishouden de vaste verwijzing naar Kinderprofiel toe. Hoeveel kinderen er zijn staat alleen in de tekst als de gebruiker dat als feit heeft laten onthouden.
- `clearAll()` en profielverwijdering wissen ook het bewaarde overzicht. In de kindstand en met het geheugen uit gaat er geen aanroep uit.
- Dit is de ene extra modelaanroep in dit ontwerp. Hij is nodig omdat lopende tekst niet zonder model te schrijven is. Bij een cloudmodel gaan hiervoor de feiten van het profiel mee, niet alleen de relevante; de tekst bij de schakelaar zegt dat.
- Bekende grens: de validatie toetst de vorm, niet of elke zin uit de feiten volgt. Het model kan iets te stellig of verkeerd samenvatten. Daarom staat onder het overzicht dat Big P het geschreven heeft en waar de herinneringen zelf staan, en gebruikt Big P voor antwoorden alleen de feiten.

**Vraag of werk bij.** Het invoerveld onder het overzicht start een beperkte Big P-run: dezelfde `MemoryService` en dezelfde drie geheugentools als het gesprek, en geen andere tools. `AssistantRun` kent daarvoor al de parameters `tools` en `conversation`; het scherm krijgt een eigen kleine host in een nieuw bestand met een eigen bezetstatus. Aanvragen, beheer en afspelen blijven in het gesprek. De run staat los van het gespreksgeheugen en de bezetstatus van de chat, zodat een vraag hier niet in het gesprek belandt en een openstaande kaart daar dit veld niet blokkeert. Het antwoord en een eventuele kaart verschijnen in het scherm boven het invoerveld. De regels voor schrijven zijn dezelfde: een nieuw feit na een getypt "onthoud dat" direct, vervangen en vergeten met een kaart die toont wat verdwijnt. Een aangetikte vervolgvraag uit "Duik dieper" is door het model geschreven en schrijft daarom nooit direct; elke schrijfactie die eruit volgt krijgt een kaart. Op tv opent de tegel "Vraag of werk bij" het toetsenbord of dicteren.

**Privacy.** Platte tekst (besluit 1), met dezelfde bescherming als de kijklog. Versleutelen met `CredentialVault` is afgewogen en afgeraden. De sleutel staat in SharedPreferences, dus de apparaatback-up bevat sleutel en database samen. Raakt alleen de sleutel weg (containerreset op macOS, hersteld toestel), dan is het hele geheugen onleesbaar zonder herstelpad. De winst zou alleen zijn dat de tekst in Bestanden niet leesbaar is, en dan zou ook `valueKey` versleuteld moeten zijn, wat de unieke index onbruikbaar maakt.

Wat wel gebeurt: geheugeninhoud komt in geen enkele logregel. De memory-bestanden krijgen een bron-scannende test naar het voorbeeld van `log_safety_test.dart`, en de toolfout op `assistant_run_execute.dart:216` logt voor deze tools alleen het type. De tabel wordt niet gesynct en niet geëxporteerd. De toolbeschrijving en het invoerveld vragen geen wachtwoorden, medische of financiële gegevens op te slaan. Bij een cloudmodel verlaten de gekozen feiten het toestel samen met de vraag, en voor het overzicht de feiten van het profiel; het scherm zegt dat. Wat voor de feiten geldt, geldt ook voor het bewaarde overzicht: dezelfde tabelbescherming, geen logregel, geen sync, geen export.

## Drie stappen, elk een eigen PR

Stap 1 en 2 krijgen een adversariële review (roadmapregel voor BP-08a), stap 3 de volledige UI-review met Verify en beeld.

1. **Opslag.** Beide tabellen, migratie 21 naar 22, `MemoryService`, de voorkeur aan/uit, wissen bij profielverwijdering. Tests: migratie vanaf 21 en verse installatie; profielisolatie voor lezen, bijwerken en verwijderen op id en voor het overzicht (twee profielen, geen kruistoegang); dezelfde zin twee keer geeft één rij; bijwerken naar een bestaande zin geeft `duplicate`; herstart (bestands-database sluiten en openen); profiel verwijderen wist rijen en voorkeur; weigering van leeftijd en taal; plafond; de hash verandert bij toevoegen, bijwerken en verwijderen en niet bij alleen lezen; `clearAll` en profielverwijdering wissen het bewaarde overzicht, uitzetten niet; de status `failed` blijft bij gelijke hash staan en vervalt bij een gewijzigd feit; logverbod. Geen UI, geen assistentcode.
2. **Big P.** De drie tools, de schrijver van het overzicht, de contextregel, voorstelkaart, direct opslaan, kindbeleid, staplabels NL en EN, contractregel. Tests met het gescripte model: voorstel zonder ja bewaart niets; "onthoud dat" bewaart direct en precies één keer; op "Wat herinner je je over mij?" bereikt het antwoord uit het geheugen de gebruiker en op "Vergeet de herinnering over horror" de vergeetkaart, in het gesprek en in het scherm, en geen spoilerantwoord; een titel met remember en een vraagzin die met "remember that" begint bewaren niets direct; vergeten wist nooit zonder ja; een onbekende of dubbelzinnige verwijzing wijzigt niets; "onthoud dat" met `replaces` vervangt niet zonder ja; `replaces` vervangt; een ander profiel ziet niets; de budgetten van 600 en 2000 tekens; geheugen uit geeft geen tool en geen regel; kindstand; profielwissel tussen voorstel en ja; een herinnering verruimt het leeftijdsfilter niet. Voor het overzicht: gelijke hash geeft geen modelaanroep, een gewijzigd feit precies één; ongeldige uitvoer geeft de lijst en bij een volgend bezoek geen nieuwe aanroep, daarna geeft een gewijzigd feit of de handmatige actie er precies één; geen verbinding geeft de lijst en bij het volgende bezoek wel een nieuwe poging; taalwissel en formaatversie geven er één; de invoer blijft onder 8000 tekens; een vervolgvraag met een opdrachtvorm wordt weggegooid en een aangetikte vervolgvraag schrijft niet zonder ja; de run vanuit het scherm biedt alleen de drie geheugentools aan en raakt het gespreksgeheugen niet; leeftijden staan niet in de invoer; geheugen uit en kindstand geven geen aanroep; de feiten en het overzicht komen in geen logregel.
3. **Beheer-UI.** Het overzicht, het menu, het lijstscherm met zoeken en categorieën, de sheets en de kaarten volgens de goedgekeurde mockup, telefoon, tablet en tv, met Pleya Verify-scenario's en beeld. De laadstaat, de lijst als terugval en de uit-stand horen bij het bewijs.

Gedeelde bestanden met ander BP-werk die stap 2 wijzigt, elk op één begrensde plek:

- `assistant_tools.dart`: de drie tools in de toollijst.
- `assistant_tool_context.dart`: `MemoryService` als veld, ook in `fresh()`.
- `assistant_run_loop.dart`: de systeemregel met relevante feiten.
- De spoilerstand: een geheugenvraag komt daar niet in terecht. De spoilerherkenning (`assistant_spoiler_context.dart`, gebruikt in `assistant_run.dart`) slaat nu aan op woorden als "herinner" en "remind", en de spoilerstand vervangt daarna het toolaanbod en dwingt het antwoord uit de spoilercontext af (`assistant_run_execute.dart`, `assistant_run_loop.dart`). Zonder ingreep krijgt "Wat herinner je je over mij?" een spoilerantwoord. De code herkent een geheugenvraag vóór de spoilerclassificatie. In de doctorstand, die schrijftools weglaat, blijven de geheugentools aangeboden.
- `assistant_run.dart` en `assistant_run_result.dart`: het voorstel als veld op het resultaat, naar het voorbeeld van `kidsAgesNeeded`.
- `assistant_controller.dart` en `assistant_controller_task.dart`: het voorstel van het resultaat naar de taak, en de methode die een ja op de kaart uitvoert.
- `assistant_controller_session.dart`: de `MemoryService` in de toolcontext.
- `kidsToolPolicy` en de staplabels.

De rest staat in nieuwe bestanden: de tools, de schrijver van het overzicht en de host van het geheugenscherm. Deze lijst is gemeten op `main` van 11 oktober; het rapport van stap 2 noemt de werkelijk geraakte plekken en de review toetst op gedrag. Wie tegelijk een van de genoemde bestanden wijzigt, stemt dat vooraf af.

## Mockup: wat bij de bouw afwijkt van het beeld

- De tekst bij de schakelaar in 43 C noemt alleen relevante herinneringen bij een vraag. Erbij komt dat voor het overzicht de herinneringen van het profiel meegaan, tot het invoerplafond.
- 43 M toont drie beheeracties; "Overzicht opnieuw schrijven" komt er op tv als vierde bij.
- Het lijstscherm op tv is niet getekend. Het volgt 43 D in de tv-stijl van 43 M; zoeken gaat via een rij die het systeemtoetsenbord opent (besluit 4).
- De cursieve toelichtingsregels in 43 K horen bij de mockup en komen niet in de app.

## Buiten scope en bekende grenzen

- Geen sync, geen export, geen embeddings of vectorzoeken. De enige extra modelaanroep is het schrijven van het overzicht, bij gewijzigde feiten en de drie genoemde aanleidingen.
- Twee verschillend geformuleerde zinnen met dezelfde betekenis kunnen naast elkaar staan tot de gebruiker of Big P er één vervangt.
- Rijen van een Plex Home-gebruiker die uit de Home verdwijnt, blijven staan; daar bestaat nu voor geen enkele profieltabel een opruimpad.
- Een lokaal profiel heeft per toestel een andere id. BP-08b moet dat oplossen voordat er iets gesynct wordt, en heeft dan ook tombstones nodig.

## Besluiten (Michel, 11 oktober 2026)

1. Platte tekst zoals de kijklog, voor de feiten en voor het bewaarde overzicht. Geen versleuteling met `CredentialVault`.
2. Kindstand: Big P gebruikt geen geheugen; het scherm blijft bereikbaar om te bekijken en te wissen.
3. "Onthoud dat ..." slaat een nieuw feit direct op, met een uitzondering in het gedragscontract. Vergeten en vervangen houden altijd een kaart.
4. Zoeken in het lijstscherm op tv via een rij met het systeemtoetsenbord.
5. De herziene mockupset 43, met het geheugenoverzicht als hoofdscherm, een modelaanroep alleen bij gewijzigde feiten en de feiten als waarheid. De handmatige actie staat in de mockup; taalwissel en een nieuwe formaatversie zijn uitwerking van dit plan.

Buiten deze besluiten blijven de ontwerppunten in de README van de mockupset open (kleur van de gevaaractie op tv, chipvulling, focusring, tabbalk); stap 3 legt ze voor.
