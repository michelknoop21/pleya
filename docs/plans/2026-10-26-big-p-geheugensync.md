# BP-08b: Big P-geheugen via Pleya Server

Roadmap: BP-08b. Productkeuze Michel, 26 oktober 2026: "Ja via pleya server is goed".
Status: scoped venster en bijbehorende server/client-migraties vrijgegeven door Michel op
26 oktober 2026: "En ga door tot build naarvtestglight samen met de terug knop van downloads".
Besluit voor het venster: [DEC-165](../DECISIONS.md#dec-165-bp-08b-geheugensync-krijgt-een-scoped-protocolvenster).

## 1. Afbakening en afwijking van de servervolgorde

1. Oorspronkelijke aanname: BP-08a bewaart geheugen lokaal; BP-08b wacht op een apart
   syncbesluit. De servervolgorde kent nog geen geheugenslice.
2. Nieuwe bevinding: opgeslagen herinneringen reizen niet tussen apparaten. Michel heeft nu
   Pleya Server gekozen als syncbron voor dezelfde persoon.
3. Waarom de planning aanvulling vraagt: het bestaande serverwerk levert geen opslag/API voor
   herinneringen. Bestaande kijkstatus of voorkeuren hiervoor misbruiken verandert hun betekenis.
4. Voorgestelde wijziging: afzonderlijke fase BP-08b naast de serverstroom, uitsluitend de drie
   operaties en capability hieronder; eerst contractvrijgave, daarna implementatie en acceptatie.
   Het ontwerp mag nu starten. Bouwvolgorde/WIP van ander werk blijft staan tot de scoped vrijgave.
5. Gevolgen: eigen voorwaartse servermigratie, lokale Drift-migratie en privacy-/backupcontrole;
   geen afhankelijkheid voor de bestaande servermijlpalen of het lokale BP-08a.
6. Vervalt binnen deze opdracht: chatsync, gezinsprofielsync, iCloud-route, nieuwe bibliotheeklaag,
   MCP-toegang tot herinneringen en een algemeen syncframework. Latere productscope vervalt niet.

Unified impact: dezelfde MemoryService en beheer-UI blijven eigenaar voor alle native clients.
Plex, Jellyfin, Emby, lokale bestanden en Pleya Share blijven bronnen van de gedeelde bibliotheek;
zij krijgen geen eigen geheugensync. Ook in een gemengde bibliotheek is er precies één gekozen
Pleya Server-account voor dit geheugen, nooit fan-out naar alle servers.

## 2. Identiteit, toestemming en bereik

- Sleutel is `(server.id, users/me.id)`, niet profielnaam, URL of lokale profiel-id.
  Bestaand: PleyaServerConnection.serverId/accountUserId en PleyaServerCredentialResolver.
  Een legacy-connection zonder accountUserId wordt eerst via eigen `/users/me` gecontroleerd;
  geen eigenaar-token als terugval. De resolver laat lokale profielen door: dat is op zichzelf
  geen toestemming om hun herinneringen te uploaden.
- In het bestaande geheugenscherm kiest de gebruiker één eigen Pleya Server-account. Voor een
  serverprofiel is die keuze eenduidig; een lokaal/Plex-profiel kiest expliciet. Een tweede lokaal
  profiel wordt nooit stil aan hetzelfde geheugen gekoppeld. Geen koppeling via gelijknamigheid.
- Voor de eerste upload ziet de gebruiker de te delen lokale feiten en het gekozen account.
  Alleen bevestigde feiten gaan mee; afbreken houdt alles lokaal. Bestaande serverfeiten worden
  eerst opgehaald en blijven behouden. De limiet van 200 wordt vóór bevestigen getoetst.
- Kindstand en rol `restricted`: geen sync, ook niet via een eerder gekozen koppeling. `household`
  feiten blijven lokaal. KidsAgesStore, andere gezinsinstellingen en chatgeschiedenis gaan niet mee.
  Vrije tekst wordt niet voorgesteld als automatisch betrouwbaar geanonimiseerd: de uploadpreview
  toont letterlijk wat gedeeld zal worden. Niet-gedeelde feiten blijven in het lokale geheugen.
- Ontkoppelen stopt aanvragen en bewaart lokale feiten; het wist geen servergeheugen. Een nieuw
  account krijgt een nieuwe bevestiging, basisstand en wachtrij. Geen oude wijzigingen doorsturen.
- Geheugen gebruiken blijft de bestaande lokale schakelaar. Ontvangen feiten zetten hem niet aan.
  De uit een feit afgeleide excludeSeen-voorkeur wordt via de bestaande regel opnieuw berekend;
  audio-, ondertitel- en overige apparaatvoorkeuren worden niet gesynchroniseerd.

## 3. Klein contractvoorstel

Alle paden hieronder staan onder `/pleya/v1`. Geen bestaande route verandert.
Sessiebearer vereist, geen streamtoken of API-token/MCP-toegang. Alle antwoorden: `Cache-Control:
no-store`. Server bepaalt gebruiker alleen uit geverifieerde claims; geen user_id in pad of body.
Owner/admin/member hebben uitsluitend hun eigen geheugen; restricted krijgt 403, zonder inhoud.
Verwijderde gebruikers, ingetrokken sessies en gewijzigde rollen worden per aanvraag gecontroleerd.

| Operatie | Aanvraag | Antwoord |
| --- | --- | --- |
| `GET /users/me/memory` | geen nieuwe parameters | 200 MemorySnapshot |
| `PUT /users/me/memory` | MemoryReplace | 200 MemorySnapshot na atomair opslaan |
| `POST /users/me/memory/clear` | MemoryClear | 200 lege MemorySnapshot met nieuwe epoch |

`capabilities.assistant_memory`: optionele boolean, afwezig betekent false. Alleen true als de drie
operaties en hun opslag beschikbaar zijn. Zonder vlag stuurt de client geen geheugenaanvragen;
serveruitval of een geweigerde aanvraag betekent nooit leeg geheugen of succesvolle sync.

Wirevormen (alle aanvraagobjecten gesloten, `additionalProperties: false`):

- MemorySnapshot: `{epoch: UUID, revision: int64 >= 0, facts: [MemoryFact]}`. Revision in JSON als
  geheel getal, maximum 9007199254740991 voor exactheid in alle clients. Nieuw account: revision 0,
  lege lijst, eenmaal opgeslagen willekeurige epoch. Elke mutatie verhoogt revision onder rijlock.
- MemoryFact: `{id: UUID, category: string, value: string, source: string,
  created_at: RFC3339 UTC, updated_at: RFC3339 UTC}`.
- MemoryReplace: `{epoch: UUID, base_revision: integer, facts: [MemoryFactInput]}`.
  MemoryFactInput: `{id: UUID, category: string, value: string, source: string}`. Alle velden
  verplicht op uitsluitend deze nieuwe routes. Bestaande feiten behouden created_at; server zet
  updated_at bij inhoudswijziging en beide tijden bij nieuwe feiten. Geen clientklok voor volgorde.
- MemoryClear: `{epoch: UUID, base_revision: integer}`. Alle velden verplicht.
- Categorieën op deze nieuwe routes: `preference`, `dislike`, `habit`, `other`; bronnen:
  `user_explicit`, `assistant_confirmed`, `settings_manual`. Gesloten aanvraagenums; clients slaan
  toekomstige onbekende antwoordwaarden niet stil als een bekende waarde op en blokkeren het
  terugschrijven van die snapshot. Geen uitbreiding van bestaande gesloten enums.
- Maximaal 200 levende feiten, unieke ids en dezelfde valueKey-deduplicatie als MemoryService;
  maximaal 200 Unicode-codepunten per feit, één regel, geen verboden controles/owned facts.
  Server herhaalt de lokale validatie, met gedeelde testvectoren voor normalisatie en uitsluitingen.
  Requestlimiet 256 KiB; 413 bij overschrijding, vóór bodylogging of inhoudsverwerking.

Nieuwe codes in het nieuwe domein `memory`: 400 `memory.invalid`, 409 `memory.conflict`,
409 `memory.epoch_changed`, 409 `memory.deleted`, 409 `memory.limit_reached`,
409 `memory.duplicate`. 403 `memory.not_permitted` en 413 `memory.too_large` bewaken toegang en bodylimiet;
bestaande auth- en interne foutcodes worden hergebruikt;
geen fout bevat feittekst, valueKey, SQL-parameters of een server-snapshot. Conflicten worden met
GET opnieuw gelezen. Geen nieuwe claims, rollen, token-scopes of antwoordvelden op login.

## 4. Verwijderen, concurrentie en offline

Een volledig snapshot past bij de bestaande limiet van 200; geen paginering, events of realtimehub.
PUT vergelijkt epoch en revision onder een accountlock. Bij verschil: geen enkele wijziging, 409.
Weggelaten bestaande ids krijgen tombstones `(user_id, fact_id, deleted_revision)` zonder tekst;
hetzelfde id mag daarna niet opnieuw worden aangemaakt. Tombstones blijven tot accountverwijdering.
Clear roteert epoch, verhoogt revision en wist levende feiten/tombstones atomair. Oude apparaten
worden daarmee altijd afgewezen, ook als zij een nog nooit geüpload feit in hun wachtrij hebben.
Een clear-conflict wist niets op de server en vereist opnieuw lezen/bevestigen; geen blind herhalen.
Een bevestigde lokale wisactie verwijdert ook oude conflictdrafts, quarantaine en verzendreceipts.
De client bewaart alleen de bekende epoch/revision voor de pending serverwisactie. Wijzigde de
server sindsdien, dan verschijnt de actuele snapshot uitsluitend ter beoordeling; de volgende
bevestiging heet expliciet serverherinneringen wissen en activeert die feiten nooit opnieuw.

Client bewaart per expliciete koppeling de laatst bevestigde basissnapshot, epoch/revision en
lokale wijzigingen in Drift. Wijziging plus pendingstatus in dezelfde transactie; geen extra
geheugenbron naast MemoryStore. Profiel-, server- of accountwissel annuleert de run; vóór elk lokaal
apply en voor elke uitgaande aanvraag worden de binding en generatie opnieuw gecontroleerd.
Elke lokale mutatie krijgt een duurzame oplopende generatie. Een PUT legt de verzonden generatie
vast; de bevestiging ruimt uitsluitend die generatie op. Nieuwere lokale wijzigingen blijven pending.
Een GET/PUT-antwoord en zijn basisstand worden samen toegepast in één lokale transactie, waarbij
alle wijzigingen sinds het verzendmoment opnieuw worden meegenomen; nooit blind de huidige feiten
overschrijven. Een crash tussen serveracceptatie en lokale ack volgt het time-out/herleespad.

Na 409/een onzekere time-out: GET, dan drie partijen vergelijken (bevestigde basis, lokale versie,
serverversie), nooit simpel de twee lijsten samenvoegen. Niet-overlappende wijzigingen mogen samen;
hetzelfde id gelijktijdig gewijzigd blijft een zichtbaar conflict. De gebruiker kiest in het
bestaande geheugenbeheer welke versie blijft, of bewaart beide met een nieuw id binnen de limiet.
Een extern verwijderd feit wordt lokaal verwijderd; een daarmee botsende lokale edit blijft apart
als niet-actief concept zichtbaar, nooit als Big P-context of automatische upload. Een gewijzigde
epoch maakt alle oude pendingmutaties ongeschikt voor automatisch uploaden, ook nieuwe ids.
Opnieuw toevoegen/importeren vereist expliciete bevestiging. Bij gewijzigde epoch worden actieve
synchroon beheerde feiten/overzicht ongeldig gemaakt; een ontvangen niet-lege snapshot blijft
in quarantaine en buiten Big P-context tot bevestiging. Een lege snapshot kan direct worden verwerkt.
Bij gelijke epoch is een serverrevision onder de lokaal bevestigde revision een herstelfout,
geen gewone wijziging. Bij een nieuwe restore-epoch mag de revision lager zijn: pas na bevestiging
van de quarantainesnapshot wordt die combinatie de nieuwe basis.
Een verlorengegaan PUT-antwoord mag
geen extra kopie opleveren: gelijkheid met het opgehaalde snapshot bevestigt de eigen wijziging;
bij latere serverwijzigingen gelden dezelfde driepartijenregels.

Een download vervangt uitsluitend de gesynchroniseerde subset; lokale household/niet-gedeelde
feiten blijven staan. Dubbelen met die lokale subset of de lokale limiet worden eerst opgelost,
niet stil verwijderd. Elk apply maakt het afgeleide overzicht ongeldig in dezelfde transactie;
een lopende overview-run mag een oude hash niet terugplaatsen. Geen upload van het overzicht.

Sync bij start/herstel van de actieve profielbinding, terugkeer naar de app, openen van geheugen,
na een lokale wijziging en via bestaande vernieuwactie. Tijdens actieve sessie één bescheiden
interval van 30 seconden zodat een open tweede apparaat wijzigingen ook ontvangt. Eén aanvraag
tegelijk, wijzigingen gebundeld, begrensde backoff bij fouten; geen OS-backgroundservice. Op het
scherm alleen feitelijke status: pending, laatst bevestigd, fout of conflict; nooit 'gesynchroniseerd'
als er nog pendingmutaties zijn. Een lokaal leeg antwoord bij een opslagfout is geen clear-opdracht.

Bij iedere ondersteunde serverrestore roteert de herstelprocedure alle geheugen-epochs, vóór de
herstelde server weer aanvragen accepteert; dit geldt ook voor oudere backups zonder geheugentabel.
Daardoor kan een pre-delete backup niet stil terugkeren als nieuwe feiten onder dezelfde epoch.
De client behandelt zo'n herstel als bovenstaande quarantaine, niet als een automatische merge.
Een backuprestore kan gewiste tekst fysiek terugbrengen: deze beperking wordt bij herstel expliciet
getoond, inclusief de bestaande backupretentie. Handmatig terugzetten buiten de ondersteunde
restoreprocedure biedt deze garantie niet en valt buiten acceptatie. Test daarom de echte lokale
restoreprocedure, niet uitsluitend een nagemaakte gewijzigde epoch.

## 5. Zes compatibiliteitsregels

| Regel uit protocol hoofdstuk 3 | Toets van dit voorstel |
| --- | --- |
| 1 Optioneel antwoordveld | Alleen capability erbij, afwezig=false; oude parsers blijven bruikbaar. |
| 2 Niet hernoemen/verwijderen | Geen bestaand veld, schema of pad wijzigt of verdwijnt. |
| 3 Bestaande betekenis behouden | Geen gebruik van watch state, ratings, settings of household-sync als geheugen. |
| 4 Geen nieuw verplicht aanvraagveld | Verplichtingen alleen op drie nieuwe operaties, nooit op bestaande aanvragen. |
| 5 Gesloten aanvragen/capability | Nieuwe bodies en geneste inputobjecten gesloten; client stuurt pas bij assistant_memory=true. |
| 6 Geen onveilige enumuitbreiding | Alleen nieuwe schemas; bestaande enums blijven exact gelijk. Onbekende geheugenwaarden blokkeren schrijven. |

Dit is een ontwerpcontrole, nog geen bewezen oude/nieuwe-clientcompatibiliteit. Het scoped venster
bevat uitsluitend deze capability, drie operaties, schemas, foutdomein en autorisatiematrixregels.
Het opent geen boekenvenster en verandert geen lopende vensters. Nummering/conflicten met parallel
werk worden bij merge opnieuw tegen main bepaald; geen migratienummer vooraf claimen.

## 6. Bouw, bewijs en sluiting

Bestaande aansluitpunten: `MemoryService`, `MemoryStore`, `profile_session_screen.dart`,
`memory_screen_model.dart` en het bestaande geheugenscherm; Pleya Server-client/wire-parser en
credentialresolver. Backend: eigen domeinopslag, api-wiremapper, autorisatiematrix, voorwaartse
migratie en backup/restore. Geen nieuw providerframework, geen backend-specifieke Big P-tools.

1. Na vensterbesluit: contract+fixtures+capabilitytests; oude server blijft lokale modus,
   oude client blijft werken tegen de nieuwe server; webtypes regenereren, geen webgeheugen-UI.
2. Server: transactie/CAS, wis-epoch/tombstones en autorisatie met wegwerp-Postgres. Negatieve
   controles: andermans gebruiker, restricted/rolwissel, read/API-token, ingetrokken sessie,
   bodyvervalsing, ontbrekende capability, foutmeldingen/logs zonder inhoud en herleven na wissen.
3. Client: bestaande geheugenvalidatie/overzichttests behouden; offlinequeue atomair, driepartijen-
   conflict, time-out na geaccepteerde PUT, dubbele zin, 200/201, Unicode/owned-factpariteit,
   account/server/profielwissel tijdens aanvraag, lokale mutatie tijdens GET/PUT plus crash vóór ack,
   pre-delete backup → wissen → ondersteunde restore → quarantaine/bevestiging,
   clear met offline nieuwe feiten, lokale-only
   feiten, limietbotsing, uitgeschakelde geheugenschakelaar en excludeSeen herberekening.
4. Pleya Verify met twee geïsoleerde clients/fixtureaccounts: toevoegen/wijzigen/wissen,
   heropenen, open tweede client, uitval/reconnect, import/annuleren, conflict en lange tekst.
   Beoordeelde screenshots op iPhone en tvOS; tablet/desktop aansluiting gericht controleren.
5. Onafhankelijke adversariële review van exact diff vóór bundelreview. Codegate, protocolgate,
   relevante tests en PR-CI; geen volledige lokale Flutter-suite. Privacytekst en serverbackups
   controleren op feitopslag en verwijderen; nooit inhoud in logs, audit, telemetry of foutbody.
6. Hardware: iPhone + Apple TV, hetzelfde testaccount en een ander account; reconnect en Siri
   Remote. Geen echte herinneringen of productie-NAS als testfixture. Release apart van hardware-
   acceptatie rapporteren; venster pas sluiten na bewijs, niet na alleen upload/merge.

## 7. Vrijgave en bouwgrens

Productrichting en het hierboven uitputtend begrensde BP-08b-venster zijn vrijgegeven, inclusief
de bijbehorende server/client-migraties en bouw naast de bestaande stroom. De opdracht loopt
door tot TestFlight, samen met de Downloads-terugknop (IOS-DL-BACK1).
Geen productie-upload, live databasedeploy of profielimport wordt door alleen dit ontwerp uitgevoerd.
Het venster blijft uitsluitend voor de genoemde capability/operaties/schema’s/foutcodes open.
Productiedatabases en bestaande herinneringen worden nooit als testfixture gebruikt.
