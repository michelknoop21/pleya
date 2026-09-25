# Herstelregister: iCloud-voorkeurensync (DEC-133)

Aangelegd op 24 september 2026 bij DEC-133. Eén rij per punt uit de audit van dezelfde dag. De
statusladder is `OPEN`, `CODE CLOSED`, `UNIT VERIFIED`, `HARDWARE OPEN`, `DEFERRED`. Een rij krijgt
bij `CODE CLOSED` de SHA, bij `UNIT VERIFIED` het testbestand, en houdt `HARDWARE OPEN` tot het
recept uit de spec (§7) op twee ingelogde toestellen is gedraaid met datum, build en toestellen.

Spec: `docs/superpowers/specs/2026-09-24-icloud-sync-repair-design.md`.
Plan: `docs/superpowers/plans/2026-09-24-icloud-sync-repair.md`.

| Punt | Wat | Status | SHA | Bewijs |
|---|---|---|---|---|
| B1 | `listen()` in productie | CODE CLOSED · UNIT VERIFIED · HARDWARE OPEN | 4a5838fc, 53fd8c5c | `test/services/icloud_sync_service_test.dart`, `test/services/preferences/sync_status_model_test.dart` |
| B2 | reconcile vergelijkt met de store | CODE CLOSED · UNIT VERIFIED · HARDWARE OPEN | 209c0eb1, a816a20a, 18069161 | `test/services/preferences/reconcile_and_tombstones_test.dart` |
| B3 | envelop op de draad en bij toepassen | CODE CLOSED · UNIT VERIFIED · HARDWARE OPEN | 94c96f15, a2c57694 | `test/services/preferences/revision_on_the_wire_test.dart` |
| B4 | verwijdering reist als tombstone | CODE CLOSED · UNIT VERIFIED · HARDWARE OPEN | 209c0eb1, a816a20a | `reconcile_and_tombstones_test` |
| B5 | oudere build wist nieuwe sleutels (prune) | CODE CLOSED · UNIT VERIFIED · HARDWARE OPEN | 209c0eb1 | `reconcile_and_tombstones_test` |
| B6 | uit en weer aan binnen één sessie | CODE CLOSED · UNIT VERIFIED · HARDWARE OPEN | 4a5838fc, 53fd8c5c | `icloud_sync_service_test`, `sync_status_model_test` |
| B7 | status bij uitgelogd iCloud | CODE CLOSED · UNIT VERIFIED · HARDWARE OPEN | 4a5838fc | `icloud_sync_service_test`, `sync_status_model_test` |
| B8 | quota-melding overleeft een reconcile | CODE CLOSED · UNIT VERIFIED · HARDWARE OPEN | 4a5838fc, 53fd8c5c | `icloud_sync_service_test`, `sync_status_model_test` |
| B9 | accountwissel leest altijd eerst, zonder partitie per account; de store wint wat hij heeft, in de taalkaarten per entry (minor 3), en een sleutel die de store mist houdt de lokale waarde; grens: een uitgelogd gemaakte wijziging verliest bij de volgende aanmelding (zelfde of ander account) van de store voor sleutels die de store heeft. De heuristiek van minor 4 (record van dit toestel = zelfde account) is teruggedraaid na herreview N2. Een accountwissel blijft in het geheugen openstaan tot een actuele beurt de stempels heeft gewist; een beurt die eerder uitvalt (time-out, uitgelogd) laat hem staan voor de volgende reconcile (herreview-2 N4) | CODE CLOSED · UNIT VERIFIED · HARDWARE OPEN | 19fe0df5, aa039dcb | `test/services/preferences/reconcile_lifecycle_test.dart` |
| B10 | taalvoorkeur op de juiste sleutel; de seriekaart houdt 100 levende uitzonderingen (was 250) en 100 tombstones, een verwijdering buiten die 100 tombstones kan terugkomen van een lang offline toestel; op een toestel dat alleen ontvangt kan de cap een oudere lokale keuze (een niet-draagbare scope) laten vallen zonder tombstone, net als bij een eigen write | CODE CLOSED · UNIT VERIFIED · HARDWARE OPEN | dfcc8839, 57f4246b, ddd72b22, 62e44d32, c0b7b2c0 | `test/services/preferences/profile_keyed_map_test.dart`, `test/services/preferences/preference_sync_policy_test.dart` |
| B11 | acht stille sleutels en de guard | CODE CLOSED · UNIT VERIFIED · HARDWARE OPEN | dfcc8839 | `profile_keyed_map_test`, `preference_sync_policy_test` |
| B12 | profielscope Jellyfin en Pleya Server | DEFERRED | | DEC-133, Consequences |
| B13 | lokale write tijdens remote batch | CODE CLOSED · UNIT VERIFIED · HARDWARE OPEN | 209c0eb1 | `reconcile_and_tombstones_test` |
| A1 | event-sink op de platformthread | CODE CLOSED · HARDWARE OPEN | a2c86a0e | `scripts/format_native.sh --check` en de diff; debug-build macOS, iOS-simulator en tvOS-simulator groen op 25 sep (taak 8). Dart-kant geautomatiseerd: `icloud_sync_service_test` ("a native event on the real EventChannel reaches prefs through start()") stuurt een native event over het echte `EventChannel` naar prefs. Dat de sink op de hoofdthread wordt aangeroepen is alleen op hardware te bewijzen |
| A2 | reconcile na de initiële download | CODE CLOSED · UNIT VERIFIED · HARDWARE OPEN | 19fe0df5 | `reconcile_lifecycle_test` |
| A3 | sleutelaantal gemeten | UNIT VERIFIED | taak 8 | `test/services/preferences/kvs_footprint_test.dart`: 655 van 1024 sleutels bij 4 profielen, plus 217 bevroren v1-sleutels (met `__syncFormatVersion`) = 872. Sinds herreview N1 genereert dezelfde test elke sleutel die de policy kan maken (globaal, profiel, per bibliotheek, meta; tombstones delen de sleutel) met de langste id's van Plex, Jellyfin en Pleya Server: de langste is 62 van de 64 bytes. Niet meegeteld: tombstones van verdwenen bibliotheken (drie sleutels per bibliotheek per profiel); reconcile ruimt die na 180 dagen op (eindreview I4, `store_convergence_test`), dus de ruimte voor ongeveer 50 verdwenen bibliotheken geldt per half jaar |
| A4 | revisieblob begrensd | DEFERRED | | DEC-133, Consequences |
| N1 | cloudsleutels binnen de 64 bytes van KVS: profiel-id en `serverId:libraryId` als `shortId`, volledige sleutel in `k`, `maxKeyBytes` op de transport en in `FakeTransport`. Na de upgrade wint voor een Plex Home-profiel het toestel dat als eerste reconcilet `hidden_libraries` en `library_order`; een bewust per toestel afwijkende inrichting wordt eenmalig overschreven (releasenotes) | CODE CLOSED · UNIT VERIFIED · HARDWARE OPEN | aa67712f | `kvs_footprint_test`, `per_profile_stamps_test`, `quota_and_oversize_test` |
| F1 | `parsePlexHomeProfileId` (`lib/profiles/profile.dart`) herkent alleen een home-uuid van 36 tekens; Plex geeft 16 hex (`test/fixtures/plex_detail/home_users.json`), dus `activeUserScope()` is het volledige profiel-id. Vervolgbevinding van de B10-review, raakt Plex Home-detectie elders; niet in deze reparatie aanpassen, want dat laat elke `user_<scope>_`-sleutel verweesd achter. Wie dit later herstelt, verandert ook de vorm van de draagbare scope: `PreferenceSyncScope.isPortableProfileScope` en elke opgeslagen mapsleutel in de twee taalkaarten moeten dan mee. Sinds de eindreview (I5) hangt ook de profielnamespace van `hidden_libraries`, `library_order` en `library_*` aan die vorm: `forProfile` is draagbaar via `isPortableProfileScope`, dus de cloudnamespace is `PreferenceSyncScope.shortId` van dat id (herreview N1); een parserfix verandert het id en verplaatst ook die records (`per_profile_stamps_test`) | OPEN | | review Task 6, eindreview I5 |
| F2 | serverId-gefilterde familie voor `unified_source_preferences` en `preferred_unified_server`; tot dan device-local | DEFERRED | | DEC-133, Consequences |

## Hardwareronde

Nog niet gedraaid. Recept: spec §7 en blok 5 van `docs/qa/preference-sync-and-playback-matrix.md`
(H1 tot H9). Vul per rij datum, build en toestellen in; een vinkje zonder die drie is geen bewijs.

Kort recept voor de ronde, twee Apple-toestellen op hetzelfde iCloud-account met dezelfde build en de
iCloud-schakelaar aan op beide:

1. Zet op het ene toestel een voorkeurstaal voor ondertitels (Plex Home-profiel) en een
   ondertitelgrootte; beide verschijnen op het andere toestel zonder herstart (H1, H8).
2. Reset de instellingen op het ene toestel; de waarden verdwijnen op het andere en komen na een
   foreground op het eerste niet terug (H2).
3. Log op het ene toestel uit bij iCloud, wijzig iets, log weer in; de status toont geen verzending
   zolang je uitgelogd bent en de volgende wijziging na inloggen komt aan (H4).
4. Importeer instellingen uit een bestand op het ene toestel; de waarden verschijnen op het andere
   en blijven staan na een foreground op het eerste (H9).

Stand van de geautomatiseerde tests bij het sluiten van de code (taak 8, 25 sep 2026, Flutter
3.44.0): `flutter test` gaf `+7138 ~10 -79: Some tests failed.` Alle 79 falers zitten in 14
goldenbestanden onder `test/goldens/` (bekende Linux-baseline, zie CAT5 en GOLD4); geen enkele
niet-golden test faalt. `scripts/ci_checks.sh --with-unused` groen.
