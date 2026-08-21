# Fase A: preference-sync, eindrapport

Datum: 2026-08-21. Status: fase A is af, niets is gecommit, niets is gepusht. Dit rapport is het
afgesproken stoppunt vóór fase B, zodat de architectuur bekeken kan worden voordat trackvoorkeuren
er diep op gaan bouwen.

De twaalf punten die het plan vraagt, in die volgorde.

## 1. Bevestigde root causes

Vier dingen in de oude engine, elk apart bevestigd in de code voordat er iets veranderde.

`BaseSharedPreferencesService.onKeyWritten` was `void Function(String key)`. Die vorm kan geen `set`
van een `remove` onderscheiden: de consument las de waarde terug, vond `null` bij een verwijdering
en stopte. Een lokaal gewiste voorkeur bereikte de cloud dus alleen via een volledige `pushAll`. Het
`void`-terugtype dwong dezelfde consument tot `unawaited(...)`, waarmee elke transportfout verdween
zonder spoor.

`SettingsExportService.isExportable` was een allow-by-default denylist. Elke nieuwe voorkeur
synchroniseerde dus tenzij iemand er expliciet nee tegen zei, en zo reisden
`companion_remote_last_host_address` (een LAN-adres) en de per-tracker bibliotheekfilters mee zonder
dat iemand dat had besloten.

De cloudsleutel stripte de profielidentiteit, dus alle profielen deelden één slot per basissleutel
en de laatste schrijver won.

`pushAll` prunede op afwezigheid uit de push-set. Een waarde die over de 100 KB-grens groeide kwam
niet in die set en werd daarom niet overgeslagen maar **verwijderd**.

Eén vondst veranderde het ontwerp. Na
`migrateLegacySharedPreferencesToSharedPreferencesAsyncIfNecessary` zijn de legacy-store en de
cache-store twee verschillende stores. De migratie kopieert eenmalig en wist niets. Vijf services
schrijven nog in de oude. Voor hun sleutels bestaan dus twee waarden: de levende, die de push niet
ziet, en een bevroren kopie uit het migratiemoment, die hij wél zou uploaden.

Twee dingen die het plan aannam en die **niet** klopten. `fetchWithCacheFallback` is
network-first, niet cache-first, dus er was geen cache-bypass nodig; het echte defect zat in de
`viewOffsetMs == null`-guard in `video_player_navigation.dart`. En `serverId` is niet
apparaatgebonden: voor Plex is het de `clientIdentifier` die plex.tv uitgeeft, voor Jellyfin de
`machineId` van de server zelf. Alleen local-folder en Pleya Share sleutelen op een lokaal
gegenereerde `connection.id`.

## 2. Gevonden rauwe schrijfacties

`test/no_raw_preference_write_test.dart` inventariseert elke rechtstreekse prefs-schrijfactie in
`lib/`: 85 stuks in 23 bestanden, elk met een categorie, een reden en een aantal. Het aantal per
bestand is onderdeel van de test, dus een nieuwe rauwe schrijfactie maakt de suite rood totdat
iemand zegt wat het is.

Ze zijn niet allemaal weggewerkt, en dat is opzet. Cachestempels, credentialblobs en
migratievlaggen horen niet in een syncengine, en ze door de pijplijn duwen om een percentage op te
poetsen maakt de engine alleen moeilijker te volgen. De 35 library- en home-callsites in
`StorageService` zijn wél omgezet, verwijderingen inbegrepen, plus in blok 2 de actieve-profielsleutel,
omdat een profielwissel een reconciliatietrigger is.

## 3. De nieuwe mutatieflow

Elke voorkeurswijziging is één `PreferenceMutation`: `key`, `operation` (`set` of `remove`), `value`
en `source` (`local`, `remote`, `migration`, `import`, `reset`).
`BaseSharedPreferencesService.onMutation` geeft een `Future` terug, en de schrijver wacht die af.

`PreferenceSyncCoordinator` neemt hem aan en beslist in deze volgorde: is de bron een echo
(`remote`), mag deze sleutel überhaupt reizen (policy), is de identiteit in de sleutel portable, is
de scope portable, en wat is de cloudsleutel. Onderweg zet een gebruikerswijziging een revisie; een
`migration` doet dat niet, want een leespad-promotie is geen keuze van de gebruiker.

`PreferenceTransport` is de poort. `ICloudKvsTransport` is de enige implementatie en bevat alleen
kanaalwerk. `ICloudSyncService` is een dunne facade voor de bestaande callsites en draagt zelf geen
syncgedrag meer.

## 4. Hoe REMOVE werkt

`remove` is een eersteklas operatie in beide richtingen. Lokaal verwijderen levert een
`PreferenceMutation.remove`, die `transport.remove(cloudKey)` aanroept. Inkomend betekent een
ontbrekende waarde in een succesvolle store-lezing een verwijdering, en die wordt lokaal uitgevoerd.

Twee dingen die daarbij vastliggen. Een echo is uitgesloten omdat een remote apply rechtstreeks naar
`prefs` schrijft en de bron `remote` is. En een **mislukte** lezing is geen lege store: `readAll()`
geeft `null` terug bij een fout, en afwezigheid betekent alleen "verwijderd" als de lezing lukte.
Anders wist een tijdelijke kanaalfout iemands instellingen.

## 5. Wat syncbaar is, en wat expliciet niet

`PreferenceSyncPolicyRegistry` keert de oude regel om: een niet-geregistreerde sleutel is local-only.
Elke registratie zegt scope (`global`, `profile`, `deviceLocal`), gevoeligheid (`normal`, `secret`,
`runtimeCache`), of hij exporteerbaar is, of hij mag synchroniseren, welke merge-familie hij claimt
en welke afgeleide schermstaat hij voedt.

Syncbaar zijn de echte voorkeuren: ondertitelweergave, afspeelgedrag, thema en interface,
integratieschakelaars, en profiel-scoped de bibliotheekfamilies.

Expliciet local-only, met de reden erbij:

- **apparaatkenmerken** die als voorkeur reisden: `volume`, downloadmappen, hardware-decoding, HDR,
  `custom_relay_url`, `companion_remote_last_host_address`;
- **secrets**: trackersessies, Pleya Share-tokens en gastrecords, Tautulli-sessie;
- **runtime cache**: server-endpoints, aflevertellingen, kijkdrempels, Plex Home-cache;
- **de legacy-storesleutels**: `flutter.`-prefix en de benoemde historische namen;
- **home-rijen** (`home_row_order`, `hidden_home_rows`), en niet vanwege `serverId`. Het is
  `hub.identifier`, de tweede helft van `homeRowId`, die niet is aangetoond als stabiele
  server-side identiteit over toestellen;
- **de eigen boekhouding**: bootstrap-marker, install-id, revisieopslag, quarantaine en de
  actieve-profielsleutel. Bewaakt door `local_only_bookkeeping_test.dart`, want juist de
  bootstrap-marker zou op een tweede toestel een import overslaan die daar nooit heeft gelopen.

## 6. Profielisolatie

`PreferenceSyncScope` houdt de identiteit vast in de cloudsleutel:
`__pleya_pref_v2/global/<key>` of `__pleya_pref_v2/profile/<id>/<key>`. Profiel A en profiel B delen
dus geen slot meer.

De scope is eerlijk over portabiliteit. Een Plex Home-UUID is portable, want Plex geeft die overal
uit. Een `local-<uuid>` is dat niet: een tweede toestel genereert een andere, dus synchroniseren
onder die naam doet niets of ent iemands voorkeuren op het profiel van een ander. Zo'n profiel is
daarom local-only.

Bij het toepassen wordt de scope positief gecontroleerd: een record onder een andere profielnaam is
niet "onbekend", het is van iemand anders en wordt overgeslagen. Datzelfde geldt voor de prune, die
alleen verwijdert wat hij positief als eigen kan claimen.

## 7. Hoe legacy cloudsleutels migreren

Eén keer per installatie importeert `bootstrapFromLegacyV1` de **ondubbelzinnig globale** v1-waarden
naar v2, met `legacyRevisionAt = 0` in plaats van `now()`. Dat getal is de hele truc: een
gemigreerde waarde heeft geen echt wijzigingsmoment, en hem stempelen met het moment van de import
zou het laatst bijgewerkte toestel tot recentste redacteur van elke instelling maken. Op nul wint de
eerste echte wijziging, waar die ook vandaan komt.

Profiel-scoped v1-records worden niet geïmporteerd. Het formaat heeft hun profiel gestript, dus
niemand kan zeggen van wie ze zijn; ze worden gequarantained, met de verwijderconditie erbij. Ze
toewijzen aan het toevallig actieve profiel zou de botsing niet oplossen maar permanent en stil
maken.

De marker `pleya_pref_v1_bootstrap_done` blijft lokaal, en een mislukte lezing laat hem ongezet, dus
de import probeert het gewoon opnieuw.

## 8. Hoe oude en nieuwe clients samengaan

Vanaf de cutover schrijft Pleya alleen v2. v1 blijft staan en wordt niet meer geschreven en niet
meer samengevoegd. Een toestel op een oudere Pleya blijft dus werken en verliest niets, maar wisselt
geen instellingen meer uit met een bijgewerkt toestel.

Dat is gekozen boven dual-write, en de reden is niet gemak. v1 heeft geen gedeelde revisie, geen
tombstones en geen profielnamespace. Zodra een oude client na een v2-schrijf weer v1 schrijft, kan
v2 niet zien of dat een nieuwere handeling is of een oudere momentopname. Dual-write bouwt precies
de onbeslisbaarheid terug die de envelop wegneemt.

Twee dingen zijn hier gemeten in plaats van aangenomen. De uitgebrachte oude client slaat
`__`-sleutels over in zowel de prune-lus als de apply-lus, aangetoond tegen het echte v1-codepad in
`icloud_rolling_upgrade_test.dart`, met een controle die bewijst dat dezelfde payload in de gewone
namespace wél wordt opgeruimd. En de gecombineerde voetafdruk is 23 KB bevroren v1 plus 33 KB v2 op
een zwaar account, samen 56 KB van de 1024 KB die KVS per account geeft. Bevroren v1 groeit niet
meer, dus dat is een plafond en geen trend.

De grens is zichtbaar gemaakt: activiteit op een bekende v1-sleutel ná de cutover zet
`legacyPeerDetected`, en dat verschijnt als melding onder de iCloud-schakelaar. Niet-destructief.
**Releasevoorwaarde:** iOS, iPadOS, macOS en tvOS moeten rond dezelfde release mee, zodat het venster
met gemengde versies klein blijft.

## 9. Hoe runtime refresh werkt

Een remote apply die alleen `SharedPreferences` verandert was niet genoeg, en dat was een echte bug:
de waarde klopte en het scherm niet, tot een herstart.

De policy zegt nu per sleutel welke afgeleide staat hij voedt (`hiddenLibraries`, `libraryOrder`,
`libraryView`, `homeLayout`). Een batch verzamelt de families die hij daadwerkelijk raakte en meldt
alleen die via `PreferenceRefreshBus`. De providers luisteren en herladen hun eigen plak:
`HiddenLibrariesProvider.refresh()`, een nieuwe `HomeLayoutProvider.refresh()` die niet meer op de
init-guard stukloopt, en `LibrariesProvider.reapplyOrder()`, dat de lijst die al op het scherm staat
hersorteert zonder netwerkronde. Import en reset melden alles ongeldig, want die herschreven de
lokale staat in bulk.

De tests toetsen wat de provider *toont*, niet dat een callback vuurde. Op de oude vorm van
`HomeLayoutProvider.refresh()` zijn er daarvan twee rood.

## 10. Status en UI

`PreferenceSyncStatus` heeft drie assen: `availability` (uit, niet beschikbaar, klaar), `activity`
(idle, syncing) en `health` (healthy, warning, error, quota), plus `legacyPeerDetected` als
eigenschap van het account. De acht toestanden uit het plan zijn een afgeleide getter, dus niets
schrijft nog een toestand en niets kan er dus een overschrijven. `raise` verlaagt nooit, en alleen
een geslaagde volledige reconcile mag health opschonen, want alleen die heeft alles bekeken.

In Instellingen houdt de bestaande schakelaar zijn plek en krijgt er één regel onder: bezig,
wanneer dit toestel voor het laatst iets verstuurde, of iCloud geen ruimte meer heeft, of er iets te
groot was, en of er nog een toestel op een oudere Pleya meedraait. Er staat nooit een sleutel, een
waarde of een telling met identiteit in, en nooit de bewering dat andere toestellen bij zijn: KVS
accepteert een schrijfactie, het meldt geen aflevering. Een widgettest controleert dat laatste
letterlijk op de tekst.

## 11. Testresultaten

Volledige suite: **4068 groen, 15 rood**. Die 15 zijn byte-identiek aan de 15 op commit `8fea407`,
gecontroleerd door de gesorteerde faallijsten te diffen; ze zitten in `logs_screen` (7),
`watchlist_ui_actions` (4), `sync_rules_screen` (2), `media_detail_screen` (1) en
`watchlist_screen` (1) en raken de sync niet.

Fase A zelf: 23 testbestanden onder `test/services/preferences/`, samen 220 tests, plus
`no_raw_preference_write_test`, `icloud_rolling_upgrade_test`,
`test/screens/settings/icloud_sync_status_test.dart` en de vijf seektests in
`playback_progress_tracker_test`.

`scripts/ci_checks.sh` groen op SDK 3.44.0: formattering, codegen-versheid, native formattering,
`flutter analyze` zonder fouten of waarschuwingen, en beide dart_code_linter-controles.

Waar het kon is een wijziging rood bewezen op de oude code: drie van de vijf seektests, de
prune-bescherming onder v2, de twee home-layout-herlaadtests, en de guard die rood wordt bij een
ongeclassificeerde schrijfactie.

## 12. Wat de fake KVS wél en niet bewijst

**Wel.** De policy, de scope en de conflictregel zijn pure functies en volledig getest. De
mutatiepijplijn is getest tegen een in-memory transport, dus tegen de eigen contracten. De
rolling-upgrade-acceptatie draait tegen het echte v1-codepad in plaats van tegen een nagebouwd
model. De coalescing van reconciliatietriggers is getest op de microtaskwachtrij, dus deterministisch
en zonder klok. Het live herladen is getest op de staat die de provider toont.

**Niet.** Geen van deze tests bewijst dat twee Apple-toestellen daadwerkelijk een instelling
uitwisselen. Een fake `MethodChannel` zegt niets over `NSUbiquitousKeyValueStore`, over de
uitrolsnelheid van iCloud, over gedrag bij slecht netwerk of over hoe dit op een Apple TV voelt. De
native audit is een code- en configuratie-audit: dat de drie platforms dezelfde KVS-identiteit
gebruiken is uit de projectinstellingen afgeleid, niet op hardware waargenomen.

**Fysiek bewezen:** niets. De matrix in `preference-sync-and-playback-matrix.md` staat volledig open,
inclusief de nieuwe blokken R (reconciliatie en live herladen, 9 scenario's) en L (de statusregel, 7
scenario's).

## Resterende beperkingen

- **Client-side last-writer-wins hangt aan de klok van het toestel.** Een Apple TV met een verkeerd
  gezette tijd wint of verliest onterecht. Lokaal is het dichtgezet (een revisie loopt op dit toestel
  nooit terug), tussen toestellen niet. Een server-geordende revisie hoort bij de Pleya
  Server-transport.
- **Home-rijen synchroniseren niet.** Het opgeslagen formaat gebruikt al portable ids; wat ontbreekt
  is bewijs dat `hub.identifier` op twee toestellen hetzelfde is, inclusief de fallback naar
  `hub.id`.
- **De legacy-store staat er nog.** Vijf services schrijven erin. Losse follow-up met per service
  een datamigratieplan en terugrolstrategie.
- **De uitgaande merge doet een extra store-lezing** per schrijfactie van een merge-familie. Dat zijn
  er vandaag twee (`hidden_libraries`, `library_order`), en de lezing is een
  `dictionaryRepresentation`, geen netwerkronde. Wel iets om in de gaten te houden als fase B meer
  families met een uitgaande merge toevoegt.
- **Quarantaine loopt niet af.** Een gequarantained v1-record blijft staan tot een van de twee
  benoemde condities geldt. Dat is bewust geen timer.

## Gewijzigde en nieuwe bestanden

Nieuw onder `lib/services/preferences/` (16 bestanden, 2692 regels): `preference_mutation`,
`preference_sync_policy`, `preference_sync_scope`, `preference_sync_coordinator`,
`preference_sync_status`, `preference_transport`, `icloud_kvs_transport`, `preference_revision`,
`preference_value_portability`, `portable_server_ids`, `preference_device_id`,
`preference_quarantine`, `preference_legacy_bootstrap`, `preference_merge_strategies`,
`preference_reconcile_scheduler`, `preference_refresh`.

Nieuw elders: `lib/screens/settings/icloud_sync_status_line.dart`, en uit fase C
`playback_resume_resolver`, `playback_write_authority`, `playback_lifecycle_report_decision`.

Gewijzigd: `base_shared_preferences_service` (het hookcontract), `icloud_sync_service` (facade,
lifecycle-listener), `storage_service` (~35 callsites plus de actieve-profielsleutel),
`settings_service` (policy op `Pref`, reset-bron, refresh-signaal), `settings_export_service`
(classificatie eruit), `main.dart` (bootstrap, portable server-ids, de ponytail-notitie is weg),
`settings_screen` (statusregel, invalidatie na import), de drie providers
(`hidden_libraries`, `home_layout`, `libraries`), en uit fase C de playbackbestanden.

Native: `ICloudKvsPlugin.swift` op iOS, tvOS en macOS, op twee punten.

Documentatie: `docs/DECISIONS.md` (DEC-059, DEC-060, DEC-061), `docs/CHANGELOG.md`, `STATUS.md`,
`docs/RELEASES.md`, `docs/qa/preference-sync-and-playback-matrix.md`,
`docs/qa/icloud-kvs-native-audit.md` en dit rapport. In `CLAUDE.md` en `CONTRIBUTING.md` is één
regel gecorrigeerd: het i18n-bronbestand is `lib/i18n/en.i18n.json`, niet het niet-bestaande
`strings.i18n.json`.

## Wat er nu níet is gebeurd

Niets is gecommit en niets is gepusht. Fase B is niet begonnen. `PleyaServerPreferenceTransport` is
niet gebouwd, `ObservedPlaybackAuthority` blijft inert tot fase D, en er zijn geen
dependency-upgrades gedaan.
