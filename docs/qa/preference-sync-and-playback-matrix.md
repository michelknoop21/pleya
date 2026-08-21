# QA-matrix: preference-sync en kijkvoortgang

Alles hieronder start als **open**. Een fake `MethodChannel` bewijst geen echte iCloud-sync tussen
toestellen, en unit- of widgettests bewijzen geen Apple TV-gedrag. Vul de uitkomst in met datum,
build en toestel, niet met een vinkje.

Bijgewerkt: 2026-08-21, na fase A blok 2. Blok 2 voegde de blokken R en L toe.

## Blok 1: sync tussen twee Apple-installaties op hetzelfde iCloud-account

Vereist minimaal een Mac en een Apple TV, beide ingelogd op hetzelfde iCloud-account, met de
iCloud-schakelaar aan in Instellingen.

| # | Scenario | Verwacht | Status |
|---|---|---|---|
| S1 | Ondertitelgrootte wijzigen op macOS | Apple TV volgt zonder herstart | open |
| S2 | Ondertitelgrootte wijzigen op Apple TV | macOS volgt | open |
| S3 | Een globale instelling (thema) op één toestel | Beide tonen dezelfde waarde | open |
| S4 | Bibliotheek verbergen in profiel A | Profiel A op het andere toestel volgt | open |
| S5 | Hetzelfde in profiel B | Profiel A blijft ongemoeid | open |
| S6 | Een instelling terugzetten naar de standaard | De verwijdering bereikt het andere toestel | open |
| S7 | Wijzigen met wifi uit, daarna weer aan | De wijziging komt alsnog aan | open |
| S8 | Tegelijk wijzigen op beide toestellen | Eén waarde wint, beide toestellen tonen dezelfde | open |
| S9 | App naar achtergrond en terug | Wijzigingen van het andere toestel zijn zichtbaar | open |
| S10 | iCloud uitgelogd of van account gewisseld | Geen dataverlies, geen foutmelding-storm | open |
| S11 | `volume` op één toestel wijzigen | Het andere toestel blijft op zijn eigen waarde | open |
| S12 | Downloadmap op macOS zetten | De Apple TV krijgt hem niet | open |

S11 en S12 zijn nieuw en toetsen een bewuste gedragswijziging: die sleutels zijn nu device-local.

## Blok 2: kijkvoortgang en trackvoorkeuren

| # | Scenario | Verwacht | Status |
|---|---|---|---|
| P1 | macOS gepauzeerd laten staan, Apple TV verder kijken | De macOS-positie komt niet terug | open |
| P2 | Andersom | Idem | open |
| P3 | Direct play | Voortgang klopt aan beide kanten | open |
| P4 | Transcoding | Idem | open |
| P5 | Plex | Idem | open |
| P6 | Jellyfin | Idem | open |
| P7 | Externe SRT zonder taalcode | Bij hervatten hetzelfde spoor | open (fase B) |
| P8 | Twee ondertitels met dezelfde taal | Geen willekeurige keuze | open (fase B) |
| P9 | Speler open laten staan, gepauzeerd, langer dan een uur | Geen terugval | open |
| P10 | App naar achtergrond en terug tijdens afspelen | Hooguit één rapport, met de juiste positie | open |
| P11 | Seeken tijdens een netwerkstoring, daarna pauzeren | De positie komt alsnog aan zodra het netwerk terug is | open |

P11 hoort bij de A0-fix. In unit-tests staat het vast met `fakeAsync`; op hardware is het niet
gemeten.

## Metingen die een ontwerpbeslissing openhouden

Dit zijn geen tests met een verwachte uitkomst maar vragen waarop het antwoord het ontwerp stuurt.

### M1: houdt een Plex-sessie zichzelf in leven zonder heartbeat?

De gepauzeerde heartbeat is in fase C verdwenen omdat hij de canonieke positie herschreef. Hij hield
mogelijk wel de serversessie levend, en dat doel mag niet stil verdwijnen.

Meten: lang pauzeren op een echte Plex-server, kijken of de sessie uit `/status/sessions` verdwijnt
en of dat ergens functioneel pijn doet (transcode-sessie afgebroken, hervatten dat faalt). Alleen
als het pijn doet komt er een aparte keepalive, en die raakt de canonieke voortgang niet aan.

Status: open.

### M2: levert Plex een signaal dat de gebruiker voor dít item bewust een spoor koos?

Komt een nooit afgespeeld item al met `selected` terug puur uit accountvoorkeuren, en verschuift
`selected` als je alleen die voorkeuren wijzigt?

Status: open. Zolang het antwoord ontbreekt wint de Pleya-profielvoorkeur van de effectieve
backendselectie, en bestaat tier 3 uit fase B niet.

### M3: dezelfde vraag voor Jellyfin

Verandert `DefaultAudioStreamIndex` na een `/Sessions/Playing/Progress` met een niet-default index,
met `RememberAudioSelections` aan tegenover uit?

Status: open.

## De v2-cutover: een bewuste, tijdelijke compatibiliteitsgrens

Vanaf de cutover schrijft Pleya alleen nog het v2-formaat, onder `__pleya_pref_v2/`. De oude
v1-sleutels blijven staan maar worden niet meer geschreven en niet meer samengevoegd.

**Gevolg dat je moet kennen voordat je het meldt als bug:** een toestel op een oudere Pleya blijft
werken en verliest niets, maar wisselt geen instellingen meer uit met een bijgewerkt toestel. Dat is
gekozen boven dual-write. v1 heeft geen gedeelde revisie, geen tombstones en geen profielnamespace,
dus zodra een oude client na een v2-schrijf weer v1 schrijft, kan v2 niet zien of dat een nieuwere
gebruikershandeling is of een oudere momentopname. Dat is precies de onbeslisbaarheid die de envelop
wegneemt; hem via een compatibiliteitslaag terughalen levert dezelfde ambiguïteit in een lastigere
vorm.

De app maakt de grens zichtbaar: zodra er na de cutover nog activiteit op een bekende v1-sleutel
binnenkomt, verschijnt onder de iCloud-schakelaar de melding dat een ander Apple-toestel nog op een
oudere versie draait. Niet-destructief: er wordt niets toegepast en niets verwijderd.

**Eis bij de release:** iOS, iPadOS, macOS en tvOS moeten rond dezelfde release de v2-versie krijgen,
zodat het venster met gemengde versies klein blijft.

| # | Scenario | Verwacht | Status |
|---|---|---|---|
| X1 | Twee bijgewerkte toestellen | Instellingen synchroniseren zoals altijd | open |
| X2 | Eén bijgewerkt, één oud toestel | Beide werken; ze delen niets meer | open |
| X3 | Idem, op het bijgewerkte toestel | De compatibiliteitsmelding verschijnt | open |
| X4 | Idem, op het oude toestel | Geen foutmelding, geen dataverlies | open |
| X5 | Oud toestel na de cutover | De v2-records zijn er nog; het oude toestel raakt ze niet aan | open |
| X6 | Eerste start na de upgrade | Globale v1-waarden staan er nog, ongewijzigd | open |
| X7 | Daarna een instelling wijzigen | De wijziging wint van de geïmporteerde v1-waarde | open |
| X8 | Bibliotheek verbergen op een Plex-server | Volgt op het andere toestel | open |
| X9 | Bibliotheek van een lokale map verbergen | Blijft lokaal, verdwijnt niet bij een remote apply | open |

De KVS-begroting is wel gemeten: bevroren v1 plus v2 komt op een zwaar account (4 servers, 12
bibliotheken elk, 70 globale voorkeuren) uit op 56 KB van de 1024 KB. Bevroren v1 groeit niet meer,
want geen enkele v2-client schrijft er nog in, dus dat getal is een plafond en geen trend. Zie
`test/services/preferences/kvs_footprint_test.dart`.

## Blok 3: reconciliatie, status en live herladen (nieuw in fase A blok 2)

De engine reconcilieert nu op benoemde momenten en de schermen herladen zonder herstart. Beide zijn
in unit- en widgettests vastgelegd tegen een fake transport, en dat zegt niets over echte iCloud.
Deze rij toetst wat een gebruiker ervan ziet.

| # | Scenario | Verwacht | Status |
|---|---|---|---|
| R1 | Bibliotheek verbergen op de Mac, Apple TV staat open op het overzicht | De Apple TV verbergt hem zonder herstart | open |
| R2 | Bibliotheekvolgorde wijzigen op de Mac | De zijbalk op het andere toestel hersorteert, zonder nieuwe fetch | open |
| R3 | Wijzigen terwijl het andere toestel in de achtergrond staat, daarna terughalen | De wijziging staat er bij het terugkomen | open |
| R4 | Van profiel wisselen | De instellingen van dát profiel worden opgehaald | open |
| R5 | Uitloggen bij iCloud terwijl de app open staat | De schakelaar meldt dat iCloud niet beschikbaar is, geen foutstorm | open |
| R6 | Weer inloggen bij hetzelfde account | Sync hervat zonder herstart | open |
| R7 | Instellingen importeren uit een bestand | Verborgen bibliotheken, volgorde en home-indeling herladen meteen | open |
| R8 | Instellingen resetten | Idem | open |
| R9 | Snel achter elkaar drie dingen wijzigen | Geen storm van reconciliaties, geen zichtbare hapering | open |

## Blok 4: wat de statusregel zegt

Onder de iCloud-schakelaar staat één regel. Hij mag nooit beweren dat andere toestellen bij zijn.

| # | Scenario | Verwacht | Status |
|---|---|---|---|
| L1 | Sync aan, niets gebeurd | Geen extra regel | open |
| L2 | Tijdens een sync | "Syncing…" | open |
| L3 | Na een geslaagde wijziging | Het tijdstip waarop dit toestel iets verstuurde | open |
| L4 | KVS-quota vol | De quotamelding, en een volgende geslaagde write laat hem staan | open |
| L5 | iCloud onbereikbaar | De melding dat de instellingen lokaal bewaard zijn | open |
| L6 | Een waarde boven de 100 KB | De melding dat iets te groot is, zonder te zeggen wát | open |
| L7 | Ander toestel op een oudere Pleya | De compatibiliteitsmelding, náást de statusregel | open |

## Wat de geautomatiseerde tests wél bewijzen

Zodat niemand ze aanziet voor het bovenstaande:

- de policy, de scope en de conflictregel zijn pure functies en volledig getest;
- de mutatiepijplijn is getest tegen een in-memory transport, dus tegen een fake, niet tegen iCloud;
- de rolling-upgrade-acceptatie in `test/services/icloud_rolling_upgrade_test.dart` draait tegen het
  echte v1-codepad (`useV2CloudFormat: false`), dus tegen het algoritme dat de uitgebrachte build
  draait en niet tegen een nagebouwd model ervan. Hij bewijst wat die code doet met de
  v2-namespace, niet wat `NSUbiquitousKeyValueStore` ermee doet;
- de A0-seekfix is getest met `fakeAsync`, dus met een gesimuleerde klok;
- de coalescing van reconciliatietriggers is getest op de microtaskwachtrij, dus deterministisch en
  zonder klok. Wat het niet meet is of de app tijdens een echte foreground-piek merkbaar hapert;
- het live herladen is getest op de staat die de provider tóónt, niet op een callback die vuurde.
  Dat sluit het gat dat de bug was; het zegt niets over hoe snel dat op een Apple TV voelt;
- de native audit is een code- en configuratie-audit. Dat de drie platforms dezelfde KVS-identiteit
  gebruiken is uit de projectinstellingen afgeleid, niet op hardware waargenomen.
