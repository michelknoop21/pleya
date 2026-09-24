# iCloud-voorkeurensync: herstelontwerp

Vastgelegd op 24 september 2026 door Michel Knoop, op `github/main` = `3ad702d3`, in de worktree
`fix/icloud-sync`. Input is de leesaudit [`docs/qa/icloud-sync-audit-2026-09-24.md`](../../qa/icloud-sync-audit-2026-09-24.md) van dezelfde dag (geschreven tegen
`d23f6c9f` op `feat/unified-desktop-ipad`). Elke regelverwijzing hieronder is opnieuw nagelopen op
`3ad702d3`; waar de audit afwijkt staat dat erbij. Het plan dat dit ontwerp uitvoert staat in
`docs/superpowers/plans/2026-09-24-icloud-sync-repair.md`.

Regelnummers gelden voor `3ad702d3`. "Bevestigd" betekent dat het pad letterlijk in de code staat en
het gevolg eruit volgt zonder aannames over Apple-gedrag.

## 1. Huidige situatie, met bewijs

De engine bestaat uit `ICloudSyncService` (facade, `lib/services/icloud_sync_service.dart`),
`PreferenceSyncCoordinator` (`lib/services/preferences/preference_sync_coordinator.dart`, 867 regels),
de policy, de scope, de status, `PreferenceRevision` en `ICloudKvsTransport` boven drie byte-gelijke
Swift-plugins (`ios/Runner`, `tvos/Runner`, `macos/Runner`; alleen `registrar.messenger` versus
`messenger()` verschilt). De laatste inhoudelijke commits op de map zijn `eae19cb4` (LANG1, 4 sep) en
`86abbe5f` (MOC-20); sinds fase A (`3b81ee20`) is er niets aan het syncmechanisme zelf veranderd.
Geen enkel auditpunt is op `main` al gerepareerd.

| Punt | Wat er staat op `3ad702d3` | Status audit |
|---|---|---|
| B1 | `listen()` gedefinieerd op coordinator 466-470; `rg "listen\(\)" lib/` geeft alleen die definitie. `start()` 75-104 en `enable()` 122-126 roepen hem niet aan. Alleen tests (`reconcile_lifecycle_test.dart:152,165`, `quota_and_oversize_test.dart:127`, `sync_status_model_test.dart:167`). | bevestigd |
| B2 | coordinator 806-809 schrijft elke `eligible` sleutel, zonder vergelijking met `remote` uit regel 756. | bevestigd |
| B3 | uitgaand `SettingsExportService.encodeValue` op 301-316; `PreferenceRevision.encode()` heeft in `lib/` geen aanroeper; `localRevision()` (392-403) evenmin; `applyEntries` 578-592 vervangt onvoorwaardelijk. De klasse-doc op regel 38-42 zegt het zelf: "The wire format is still v1 ... go live together in A6". | bevestigd |
| B4 | `applyAllRemote` 494-497 geeft alleen aanwezige sleutels door; afwezigheid telt alleen in `applyRemoteKeys` 499-506, dat door B1 nooit loopt. | bevestigd |
| B5 | `ownsCloudKey` 660-669: v2-tak eist geen `maySync`; prune 811-830 slaat alleen `eligible`, `oversize` en `known` over. | bevestigd |
| B6 | `disable()` 130-134 roept `_coordinator.dispose()` (846-851, zet `_transport = null`); `enable()` maakt geen nieuwe transport. | bevestigd |
| B7 | `apply()` 260-267 kijkt niet naar `availability`; `starting()` en `writeSucceeded()` forceren `ready` in `preference_sync_status.dart:136-150`, `reconcileSucceeded` op 154-172. De audit noemt regels 563-599: die bestaan niet, het bestand heeft 197 regels. | bevestigd, regels verplaatst |
| B8 | `reconcileSucceeded` zet `health` op `healthy` of `warning`, ongeacht een eerdere `quota` (162). | bevestigd |
| B9 | `_runReconcile` 429-442 doet voor `accountChanged` `applyAllRemote` en daarna `reconcile`, dus alles wat de nieuwe store niet heeft krijgt de waarde van het oude account. `pleya_pref_v1_bootstrap_done` blijft staan (`preference_legacy_bootstrap.dart:29-33`). | bevestigd |
| B10 | policy `preference_sync_policy.dart:251` en `:498` zetten `pleya_profile_language_preferences` op `PreferenceScopeKind.profile`; de store (`lib/services/pleya_profile_language_preference_store.dart:50-51, 66, 93`) leest en schrijft de kale sleutel met `StorageService.activeUserScope()` als mapsleutel. `localKeyFor` (224-229) bouwt inkomend `user_<uuid>_pleya_profile_language_preferences`. Het bestand staat in `lib/services/`, niet waar de audit het zocht. | bevestigd |
| B11 | guard-regex `preference_sync_policy_test.dart:175` `Pref[a-zA-Z<>]*\(\s*'`; nagemeten met `perl` op `settings_service.dart`: 114 treffers, met `Pref[^(]*\(\s*'` 122. De acht ontbrekende: `keyboard_shortcuts`, `keyboard_hotkeys`, `media_version_preferences`, `track_language_preferences`, `unified_source_preferences`, `tv_live_tv_capability`, `preferred_unified_server`, `custom_shader_presets` (`settings_service.dart:584-711`). `lib/services/track_preference_store.dart:17-19` claimt nog "allow-by-default". | bevestigd |
| B12 | `PreferenceSyncScope.forProfile` 67-74; Jellyfin-, Pleya Server- en lokale profielen krijgen `local-<uuid>` (`add_jellyfin_screen.dart:383`, `add_pleya_server_screen.dart:178`, `add_local_profile_screen.dart:68`), per toestel gegenereerd. | bevestigd |
| B13 | coordinator 247-252 laat een lokale write tijdens `_applyingRemote` vallen; na `applyRemoteKeys` volgt geen reconcile. | bevestigd |
| A1 | Swift 90-101 roept `sink(...)` op de thread van de notificatie. | aannemelijk, zie §5 |

Eén nuance op de audit. DEC-059 beschrijft de envelop als gebouwd en getest, maar zegt in zijn
Consequences ook dat `v2CloudFormatEnabled` op `false` stond en "de envelop bestaat en is getest maar
schrijft nog niets". DEC-060 zette de namespace aan en zwijgt over de envelop. Niemand heeft dus
besloten dat de envelop live was; hij is bij de cutover vergeten. Het gat is even groot, de
herkomst is anders dan de audit suggereert.

## 2. Het beoogde contract, en waar de code afwijkt

DEC-059 belooft voor scalaire voorkeuren deterministische last-writer-wins op `(updatedAt,
deviceId)` met tombstones: de nieuwste `updatedAt` wint, bij gelijke tijd de hoogste `deviceId`,
bij gelijke tijd en gelijk toestel de tombstone. Een `migration` stempelt niet. De prune "deletet
alleen wat lokaal echt weg is". Verwijderingen reizen als eersteklas operatie in beide richtingen.

DEC-061 voegt toe: één scheduler met benoemde triggers, drie statusassen waarbij alleen een
geslaagde volledige reconcile health mag opschonen, en gericht herladen van afgeleide schermstaat.

DEC-096 belooft dat de taalvoorkeur van het Pleya-profiel "voor alle content" geldt, over servers,
backends en toestellen heen, met het Pleya-profiel als eigenaar en het serverprofiel als spiegel.

Waar de code afwijkt:

1. Er reist geen stempel. Elk v2-record is `{"type","value"}`. Bij toepassen wint wat de store
   aanlevert; bij reconcile wint wat als laatste bij iCloud aankomt. De tombstone bestaat alleen als
   `x: true` in het lokale revisieblob dat niemand leest.
2. De prune neemt de rol van de tombstone over en doet dat verkeerd om: afwezig-lokaal wordt gelezen
   als verwijderd, terwijl het net zo goed "nog nooit gehad" kan zijn. Het andere toestel zet de
   verwijdering ondertussen terug omdat het zijn volledige set opnieuw schrijft (B2 en B4 zijn één
   asymmetrie).
3. De notificatie-listener is er en is nergens aangesloten, dus de engine is poll-on-foreground.
4. De taalvoorkeur is als profiel-scoped geregistreerd terwijl haar opslag global is met het profiel
   in de mapsleutel; inkomend landt zij op een sleutel die niemand leest. DEC-096 werkt daardoor op
   geen enkel toestelpaar.

## 3. Herstelontwerp per defect

De volgorde volgt de audit, met één afwijking bij B5 (zie daar). Elke stap laat de app werkend en de
suite groen achter.

### B1: `listen()` in productie

`ICloudSyncService` krijgt één private `_wire(settings, coordinator)` die `start()` en
`debugCreate()` delen: instantie zetten, `BaseSharedPreferencesService.onMutation = coordinator.apply`
en `coordinator.listen()`. De subscriptie is onvoorwaardelijk: `_onRemoteChange` laat events vallen
zolang de schakelaar uit staat (regel 473), en een subscriptie die pas bij `enable()` ontstaat is
precies hoe B1 kon gebeuren. `start()` krijgt een `@visibleForTesting PreferenceTransport?
transport`, zodat de test de productieroute met een `FakeTransport` bewijst in plaats van
`coordinator.listen()` zelf aan te roepen.

### B6: uit en weer aan

`disable()` roept `_coordinator.dispose()` niet meer aan. De transport blijft leven, de subscriptie
blijft staan, `apply()` en `_runReconcile` zijn al op `_enabled()` gegaten. `disable()` wordt:
schakelaar schrijven, `refreshAvailability()`. `enable()`: schakelaar schrijven,
`refreshAvailability()`, `listen()` (idempotent door `??=`), reconcile met trigger `enabled`.
Verwijderen van één regel, geen nieuwe levenscyclus.

### B7: eerlijke beschikbaarheid

Drie wijzigingen. `_runReconcile` begint met `await refreshAvailability()` en stopt als de uitkomst
niet `ready` is: één kanaalaanroep per reconcile, en een foreground na uitloggen komt zo eerlijk
uit. `apply()` stopt na het lokale stempelen wanneer `availability == unavailable`; de eerstvolgende
reconcile na inloggen duwt de wijziging alsnog, omdat de lokale stempel dan wint. In de status
forceert `writeSucceeded` geen `ready` meer, `reconcileSucceeded` neemt de bestaande
`availability` over, en `starting()` promoveert alleen `disabled` naar `ready` (die waarde is op dat
punt aantoonbaar verouderd, want `_enabled()` was waar) en laat `unavailable` staan. `sawRemoteChange`
en `appliedRemote` mogen `ready` blijven zetten: de store heeft dan daadwerkelijk gesproken.

### B8: quota blijft staan

`reconcileSucceeded` houdt `quota` vast: `health = oversize > 0 ? warning : (health == quota ? quota :
healthy)`. KVS meldt een quota-overschrijding maar meldt nooit dat zij is opgeheven; de melding
verdwijnt bij uitschakelen of herstart, zoals de status-doc al zegt over `legacyPeerDetected`.

### B3: de envelop op de draad en bij toepassen

Het draadformaat blijft achterwaarts leesbaar voor de uitgebrachte v2-build, want die leest
dezelfde `__pleya_pref_v2/`-namespace. Een live record wordt
`{"type": T, "value": V, "t": updatedAt, "d": deviceId}`; een tombstone `{"x": true, "t": ..., "d":
...}`. De oude build negeert `t` en `d` (`_decodeTyped` leest alleen `type` en `value`) en slaat een
tombstone over (`type` ontbreekt, `_decodeTyped` geeft null). Een record zonder `t` en `d` is een
record van de oude build en telt als `legacyRevisionAt` (0).

Vergelijken gebeurt met de bestaande regel uit `PreferenceRevision.winsOver`, losgetrokken tot een
statische `stampWins(...)` zodat de coordinator hem kan gebruiken zonder een `PreferenceRevision`
met waarde te construeren (de assert eist een waarde voor een levend record). Eén expliciete extra
regel: zijn beide kanten ongestempeld (beide `t == 0`), dan wint de store. Dat is het bestaande
gedrag bij inschakelen ("remote wins on shared keys") en de keuze van DEC-060 bij de cutover, nu
uitgeschreven in plaats van impliciet.

Bij toepassen (`applyEntries`) wordt voor een sleutel zonder merge-familie het inkomende record
alleen toegepast als zijn stempel wint over de lokale stempel; bij winst wordt de remote stempel
lokaal overgenomen (`_adoptStamp`), zodat een latere lokale wijziging via `_nextRevisionTimestamp`
gegarandeerd hoger stempelt. Een winnende tombstone verwijdert de lokale waarde en slaat `x` op.
Merge-families (`hidden_libraries`, `library_order`, en de nieuwe map-familie uit B10) blijven
altijd mergen; voor hen is de stempel geen beslisser.

`PreferenceRevision.encode()`, `decode()` en `toJson()` hebben na deze stap nog steeds geen
productie-aanroeper; ze gaan weg, met de vier bijbehorende tests in `preference_revision_test.dart`.
De klasse-doc van de coordinator (regel 38-42) wordt herschreven.

### B2 en B4: reconcile vergelijkt, verwijderingen reizen als tombstone

`reconcile()` leest de store één keer (dat gebeurde al) en schrijft per sleutel alleen als de lokale
stempel strikt wint, of als de sleutel in de store ontbreekt. Voor merge-families wordt op de
waarde vergeleken (`json.encode` van beide `value`-velden) en alleen bij verschil geschreven. De
metasleutel wordt alleen geschreven als hij ontbreekt of afwijkt. Een geslaagde reconcile op een
onveranderde store schrijft daarmee nul records; de test "running twice changes nothing" wordt
scherper dan hij was.

Een lokale `remove` schrijft een tombstone in plaats van `transport.remove`. Het andere toestel past
de tombstone toe wanneer die wint, en zijn eigen reconcile duwt daarna niets terug, want zijn lokale
stempel is nu de tombstone. Reconcile herhaalt bovendien de tombstones uit het revisieblob voor elke
sleutel waar de store nog een ouder levend record heeft (de uitgebrachte build schrijft die terug;
zie §7).

Gevolg voor `transport.remove`: onder v2 roept niets het meer aan. De v1-tak blijft het gebruiken
voor de rolling-upgrade-test, die het echte v1-algoritme draait.

### B5: de prune verdwijnt onder v2

De audit adviseert `maySync` in de v2-tak van `ownsCloudKey`. Dat lost B5 op zolang de prune
bestaat, maar de prune bestaat onder v2 na B2/B4 niet meer: een sleutel die de store heeft en dit
toestel niet, is met tombstones altijd "nog niet gehad" en wordt door `applyAllRemote` overgenomen.
Prune-op-afwezigheid was de plaatsvervanger van de tombstone; met de tombstone is hij een tweede,
strijdige verwijderregel. `ownsCloudKey` geeft onder v2 dus `false` ("nothing is pruned"), en de
prune-lus draait alleen nog voor `!_useV2CloudFormat`. Dat sluit B5 met minder code dan de
audit-fix en zonder een dode tak achter te laten. De tests `v2: only records inside the owned
namespace are pruned` (`namespace_ownership_test`), `a key that is genuinely gone locally is still
pruned` (`preference_sync_coordinator_test`, `merge_strategy_test`) en `pushAll removes KVS keys
that no longer exist locally` (`icloud_sync_service_test`) beschrijven het oude contract en worden
herschreven naar het nieuwe. De v1-varianten blijven.

Wat dit niet oplost: de uitgebrachte build N prunet nog wél sleutels die hij niet kent. Dat gedrag
zit in de binaire die al bij gebruikers staat en is alleen te dichten door alle Apple-toestellen
tegelijk bij te werken, de releasevoorwaarde die DEC-060 al stelt. Zie §7.

### B13: geen weggegooide write meer

De guard op `_applyingRemote` in `apply()` gaat weg, met het veld. De reden dat hij bestond
("ordering it against the batch") is met B3 verdwenen: een lokale write stempelt eerst, en als
`applyEntries` dezelfde sleutel later in de batch bereikt, verliest het remote record van die
verse stempel. Echo was al onmogelijk, want remote writes gaan rechtstreeks naar `prefs` en passeren
`onMutation` niet.

### B9: accountwissel

Besluit: bij `accountChanged` leest de engine eerst, duwt daarna alleen wat het nieuwe account nog
niet heeft, en wist lokaal niets. Concreet in `_runReconcile`, wanneer de triggerset
`accountChanged` bevat: `clearRevisions()` (de stempels beschrijven de wijzigingsgeschiedenis van
dit toestel tegenover het vorige account; tegenover een ander account zeggen ze niets, en ze laten
staan zou de waarden van A als "nieuwer" in B's store duwen) en `PreferenceLegacyBootstrap.reset`
zodat de v1-import voor het nieuwe account één keer loopt. Daarna het bestaande pad: bootstrap,
`applyAllRemote` (alles lokaal is nu ongestempeld, dus de store wint elke aanwezige sleutel) en
`reconcile` (sleutels die B mist krijgen de lokale waarde met stempel 0, zodat de eerste echte
wijziging waar dan ook wint).

Wat dit wel doet: een lek van A naar B blijft mogelijk voor sleutels die B nog nooit had. Dat is de
gekozen default uit de opdracht en de kant waar geen data verloren gaat. Wat het niet doet: lokale
voorkeuren wissen of een tweede lokale namespace per account aanleggen. Een echte per-account-scheiding
is een ontwerpronde op zich en wordt in DEC-131 als niet-gebouwd vastgelegd. `RemoteChangeReason.
accountChanged` dekt ook uitloggen; dat pad stopt al op `unavailable` en verandert niet.

### B10: de taalvoorkeur

De registratie van `pleya_profile_language_preferences` gaat van `profile` naar `global` met een
nieuwe merge-familie `profileKeyedMap`. De sleutelvorm die de store schrijft (kaal, profiel in de
mapsleutel) is dan ook de vorm die de engine verwacht, zonder datamigratie en zonder de
`user_<scope>_`-prefix alsnog door te voeren in een store die DEC-096 juist backend-neutraal
gemaakt heeft. Hetzelfde geldt voor de export: `isUserScopedBaseKey` gebruikt dezelfde policy, dus
ook een import landde tot nu toe op de dode sleutel.

De familie kent de vorm `{profileScope}` of `{profileScope}|{rest}` van de mapsleutels.
Draagbaarheid van een scope: `StorageService.activeUserScope()` is de Plex Home-uuid voor een Plex
Home-profiel en anders het volledige profiel-id, en dat is `local-<uuid>` (per toestel gegenereerd)
of leeg (uitgelogd). Draagbaar is dus precies "ziet eruit als een uuid". Inkomend behoudt het toestel
zijn niet-draagbare entries en de entries van scopes die de zender niet kent; voor scopes die beide
kennen vervangt de zender de set (een gewiste serie-uitzondering bereikt zo het andere toestel).
Uitgaand vertrekken alleen draagbare entries, aangevuld met de entries in de store van scopes die
dit toestel niet heeft. Hebben beide kanten een entry onder dezelfde sleutel en dragen beide een
`updatedAt`, dan wint de hoogste; `PleyaProfileLanguagePreferences` stempelt dat veld al bij elke
schrijfactie, waardoor de profielvoorkeur per entry deterministisch is en niet op aankomstvolgorde.

Bekende grens, vastgelegd in DEC-131: verwijdert een toestel de láátste entry van een scope, dan
verdwijnt die scope uit zijn lokale map en ziet de ontvanger de store-entries als "scope die de
zender niet kent"; die ene verwijdering reist niet. Voor de profielvoorkeur (één entry per profiel,
nooit gewist) speelt dit niet; voor serie-uitzonderingen alleen bij de laatste van een profiel.

### B11: de acht stille sleutels en de guard

De guard-regex wordt `Pref(?:<[^()]*>)?\(\s*'([a-z0-9_.]+)'`: een optioneel generiek type met
komma's en spaties, en niets anders tussen `Pref` en het haakje, zodat `PreferenceMutation.set(`
niet meetelt. Nagemeten: 122 sleutels, waarvan de acht uit B11 nieuw. Zij krijgen alle een
registratie (§6). `track_preference_store.dart:17-19` wordt herschreven naar de werkelijke
registratie.

### B12: profielscope voor Jellyfin en Pleya Server

Besluit: niet in deze ronde. Een portable profielidentiteit voor deze backends vraagt een nieuwe
id-vorm (`<serverMachineId>/<userId>` voor Jellyfin, een server-uitgegeven id voor Pleya Server),
een migratie van de `local-<uuid>`-profielen en de `user_<id>_`-prefixen die daaraan hangen, en
raakt `ProfileRegistry`, `ActiveProfileBinder` en de exportre-scoping. Dat is een profielronde, geen
syncbugfix. DEC-131 legt vast dat `hidden_libraries`, `library_order` en `library_*` voor deze
profielen niet synchroniseren, en dat de taalvoorkeur na B10 wél reist voor Plex Home maar niet voor
`local-`-profielen. De memory "Pleya Server altijd meenemen" blijft daarmee een open schuld met
naam en vindplaats.

## 4. Aannemelijke punten

| Punt | Besluit | Reden |
|---|---|---|
| A1 event-sink op een niet-hoofdthread | nu fixen | Flutter eist de platformthread voor kanaalverkeer en logt anders `The '...' channel sent a message from native to Flutter on a non-platform thread`; `NotificationCenter` levert op de postende thread en Apple documenteert voor beide notificaties geen thread. Eén `DispatchQueue.main.async` in een gedeelde `emit(_:)` in drie identieke bestanden. Niet meetbaar in een unittest; bewijs is de Flutter-regel, `scripts/format_native.sh --check` en een diff die alleen de messenger-regels laat verschillen. |
| A2 eerste write vóór de initiële download | nu fixen | Zodra B1 de `InitialSyncChange` aflevert, volgt na `applyRemoteKeys` een reconcile met de nieuwe trigger `ReconcileTrigger.initialSync` (ambient, dus op `_enabled()` gegaten). De lokale stempels winnen van wat de store nog niet had, dus wat het systeem weggooide wordt opnieuw geschreven. Drie regels plus een enumwaarde; de lijst triggers is "closed on purpose" en dit is een benoemd moment. |
| A3 sleutelaantal richting 1024 | meten, niet fixen | `kvs_footprint_test` krijgt naast bytes een telling op hetzelfde zware account (4 profielen, 4 servers, 12 bibliotheken: 4 × 146 + 70 = 654 sleutels) met een assert onder 1024. Tombstones voegen geen sleutels toe: ze bezetten het slot dat de waarde al had. Een echte fix (per-bibliotheeksleutels samenvouwen tot één map per profiel) is een formaatwijziging en hoort niet in een herstelronde. |
| A4 revisieblob groeit | vastleggen | Na B3 bevat het blob ook overgenomen remote stempels: hooguit één entry per sleutel die dit toestel ooit zag, dus begrensd door A3 (654 entries × ~60 bytes ≈ 40 KB, één JSON-decode per write). Tombstones moeten blijven staan. Geen opruiming; het plafond staat in DEC-131. |

## 5. Scopewijzigingen

De registry is de enige plek waar dit verandert. `_deviceBoundPref` is nieuw: `deviceLocal`,
`icloudSyncable: false`, `exportable: true`. Deze ronde raakt alleen de iCloud-kant; wat vandaag in
een exportbestand zit blijft daarin, en wat er niet in zit komt er niet bij, met twee bewuste
uitzonderingen hieronder.

Van sync naar toestelgebonden (`_deviceBoundPref`, export ongewijzigd):

- `default_quality_preset`: hangt aan het netwerk van het toestel.
- `buffer_size`: hangt aan het geheugen.
- `mpv_config_text`, `mpv_config_presets`: kunnen `hwdec` en paden bevatten.
- `global_shader_preset`: GPU-gebonden.
- `enable_discord_rpc`: bestaat alleen op desktop, per installatie.
- `video_player_navigation_enabled`: desktopgedrag.
- `auto_check_updates_on_startup`: App Store versus sideload verschilt per installatie.

Van stil-lokaal naar sync:

- `pleya_profile_language_preferences`: `global` + `profileKeyedMap` (B10). Was al exportable.
- `track_language_preferences`: `global` + `profileKeyedMap`; wordt hiermee ook exportable, zoals
  de doc in `track_preference_store.dart` al aannam.
- `keyboard_shortcuts`, `keyboard_hotkeys`: `_globalPref`; zinnig tussen twee Macs, onschadelijk op
  tvOS. Worden exportable.
- `live_tv_default_favorites`: van `_deviceLocalPref` naar `_globalPref`, zoals de audit adviseert;
  de waarde draagt geen toestelkenmerk.

Van stil-lokaal naar expliciet lokaal (registratie zonder gedragswijziging):

- `media_version_preferences`: `_deviceLocalPref`; de versie-index hangt aan wat de server dít
  toestel aanbiedt. Blijft te bespreken.
- `unified_source_preferences`, `preferred_unified_server`: `_deviceLocalPref`; het audit-advies
  "sync met serverId-filter" vraagt een eigen merge-familie op de waarde en is een vervolg, niet een
  bugfix.
- `custom_shader_presets`: `_deviceLocalPref`, om dezelfde reden als `global_shader_preset`.
- `tv_live_tv_capability`: `_runtimeCache`.

Blijft zoals het is, met de twijfel uit de audit genoteerd en niet beslist: `library_density`,
`hover_expand_cards`, `always_keep_sidebar_open`, `show_nav_bar_labels`, `startup_section`,
`require_profile_selection_on_open` (layout per vormfactor), `tv_full_card_layout`,
`tv_show_titles_under_posters`, `tv_hero_clear_logo`, `tv_hero_auto_advance`, `tv_reduce_motion`
(TV-opties; `tv_reduce_motion` is toegankelijkheid van dát scherm en is de sterkste kandidaat om
later te verhuizen), `library_filters*`, `library_sort_*`, `library_grouping_*`, `library_tab_*`
(sessiestaat versus persoonlijke voorkeur). Alles uit "Niet gesynchroniseerd, terecht" in de audit
blijft lokaal.

## 6. Wat niet verandert

Geen nieuwe transport en geen server-side sync: `ICloudKvsTransport` blijft de enige implementatie,
`PleyaServerPreferenceTransport` bestaat niet en komt hier niet. Geen dual-write en geen v1-schrijf;
de v1-tak blijft uitsluitend voor `icloud_rolling_upgrade_test`. Geen UI-herontwerp: de statusregel
krijgt geen nieuwe tekst, hij stopt alleen met beweren dat er iets verzonden is als iCloud
uitgelogd is. Geen nieuwe scope-soort en geen profielmigratie (B12). Android, Windows en Linux
blijven no-op; de tekst in Instellingen die zegt dat sync alleen op Apple bestaat komt er in deze
ronde niet.

## 7. Bewijs per platform en de statusladder

Unit: coordinator, policy, revisie en merge-families tegen `FakeTransport`
(`test/services/preferences/fake_transport.dart`) en de facade tegen dezelfde fake via de nieuwe
`transport`-parameter op `start()`. De bestaande suite onder `test/services/preferences/` plus
`icloud_sync_service_test`, `icloud_rolling_upgrade_test`, `icloud_progress_merge_test`,
`test/screens/settings/icloud_sync_status_test.dart` en `no_raw_preference_write_test` (de telling
voor de coordinator gaat van 4 naar 5 raw writes: `_adoptStamp`).

Wat de simulator niet kan: de iOS-, tvOS- en macOS-simulators hebben geen iCloud-account, dus
`ubiquityIdentityToken == nil` en `NSUbiquitousKeyValueStore` synchroniseert niet. Geen simulatorrun
bewijst cross-device-gedrag. De statusladder per punt is daarom `CODE CLOSED · UNIT VERIFIED ·
HARDWARE OPEN`, en `HARDWARE OPEN` blijft staan tot het recept hieronder gedraaid is.

Hardware-recept (twee toestellen, hetzelfde iCloud-account, dezelfde TestFlight-build met deze
wijzigingen, iCloud-schakelaar aan op beide, debug-logging aan):

1. S1 en S9: ondertitelgrootte op de Mac wijzigen met de Apple TV open in Instellingen; verwacht
   binnen een minuut de nieuwe waarde zonder herstart en zonder de app weg te zetten. Daarna
   hetzelfde met de Apple TV in de achtergrond en terughalen.
2. S6 en R8: op de Mac een instelling terugzetten naar standaard, daarna Instellingen resetten;
   verwacht dat de Apple TV beide volgt en dat de Mac na een eigen foreground niets terugkrijgt.
   Controleer in het log dat de tombstone-write (`x`) geschreven is en niet opnieuw geschreven wordt
   bij een tweede foreground.
3. S8: dezelfde instelling binnen vijf seconden op beide toestellen anders zetten; verwacht dat beide
   op de laatst gezette waarde uitkomen en dat een derde foreground niets meer wisselt.
4. R5 en R6: uitloggen bij iCloud op de Mac met de app open; verwacht de ondertitel "Sign in to iCloud"
   onder de schakelaar en geen "Last sent"-regel na een wijziging. Weer inloggen; verwacht dat de
   volgende wijziging weer aankomt, zonder herstart en zonder de schakelaar aan te raken.
5. B6: schakelaar uit, wijziging maken, schakelaar aan, wijziging maken; verwacht dat de tweede
   wijziging aankomt en de eerste na de reconcile bij inschakelen ook.
6. S10 en B9: op de Apple TV wisselen van iCloud-account naar een tweede testaccount met een eigen
   store; verwacht dat de waarden van dat account op de Apple TV verschijnen, dat wat het account
   miste met stempel 0 in zijn store staat, en dat niets lokaal gewist is. Terugwisselen; verwacht
   het omgekeerde.
7. L4: KVS vol laten lopen is niet praktisch uit te voeren; deze rij blijft `HARDWARE OPEN` met die
   reden.

Bij een rode rij: `curl ice.pleya.app/logs/<nummer>` volgens memory "Pleya-log terughalen".

## 8. Governance

DEC-131 in `docs/DECISIONS.md`. Gecontroleerd op `3ad702d3`: `rg -n "^## DEC-" docs/DECISIONS.md`
eindigt op DEC-130 en `rg "DEC-12[3-9]|DEC-13[1-9]" docs/` geeft niets; DEC-121 is door
`feat/unified-desktop-ipad` geclaimd en DEC-122 door de Liquid Glass-ronde. Botsingsrisico:
concurrente branches kunnen 123 tot 129 of 131 al gebruiken zonder dat `main` het weet; bij de
merge wint wie eerst op `main` staat en de ander hernummert (zie "Main-sync 6 sep 2026" in het
geheugen). DEC-131 bevat: de envelop op de draad met het achterwaarts leesbare formaat, tombstones
in plaats van prune onder v2, de accountwisselregel, `profileKeyedMap` met zijn bekende grens, B12
als niet-gebouwd, de scopetabel uit §5, en het plafond uit A4.

Register: nieuw `docs/icloud-sync-repair-register.md`, één rij per B- en A-punt met status
(`OPEN`, `CODE CLOSED`, `UNIT VERIFIED`, `HARDWARE OPEN`, `DEFERRED`), SHA en bewijsregel, aangelegd
in taak 1 en gesloten in taak 8. De matrix `docs/qa/preference-sync-and-playback-matrix.md` krijgt
een blok met het hardware-recept uit §7 en een correctie bij S6 (tombstone in plaats van remove);
`docs/qa/icloud-kvs-native-audit.md` krijgt bij "buffering" de correctie dat `listen()` tot DEC-131
nergens liep.

`docs/agents/workflow-evaluation.md` staat op 3 van 3 regels en krijgt niets.

## 9. Open beslissingen die de repo niet beantwoordt

1. Of de "twijfel"-rijen uit §5 (layout per vormfactor, TV-opties, per-bibliotheekweergave) ooit
   verhuizen; dit ontwerp laat ze staan.
2. Of `unified_source_preferences` en `preferred_unified_server` een eigen serverId-gefilterde familie
   krijgen; alleen het advies is genoteerd.
3. Of een echte per-account-scheiding van lokale voorkeuren (B9) gewenst is boven de gekozen
   lees-eerst-regel.
4. De profielidentiteit voor Jellyfin en Pleya Server (B12).
