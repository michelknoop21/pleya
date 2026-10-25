# Instellingen in Studio-stijl: pariteit iOS en tvOS (A-24)

Besluit Michel, 24 oktober 2026: Instellingen krijgt richting 02, Apple TV+ Studio. Deze tabel legt per
huidige rij vast waar hij na PR 1 staat, zodat de restyle niets toevoegt, weghaalt of anders afschermt.
De code is de bron; de ontwerpinventaris in de aangeleverde bundel diende alleen als controlelijst.

PR 1 raakt alleen de weergave. De Studio-kop, de balk met warme tint en de gevulde zoekbalk staan alleen
op een iPhone (`settingsStudioHeaderApplies`); iPad, de iOS-app op een Mac, Android en desktop houden de
gewone balk en het omlijnde zoekveld. De rijstijl hieronder geldt buiten TV overal; elke wijziging in de
gedeelde rijen staat achter `PlatformDetector.isTV()`. tvOS is PR 2, zie het hoofdstuk tvOS onderaan.

## Wat er in de presentatie verandert

- Studio-kop (`lib/widgets/settings/settings_studio_header.dart`) boven de hoofdpagina en elke
  `SettingsPage`: grote titel, regel `PLEYA · <SECTIE>`, rechts artwork uit de items die
  `DiscoverProvider` al heeft geladen (Verder kijken, dan nieuwste films). Zonder provider of zonder
  backdrop: merkverloop met het Pleya-logo. De vaste balk houdt terugknop en acties, draagt de warme tint
  van de kop zolang die in beeld is en toont zijn titel pas als de kop eronder is geschoven.
- Keuze-, getal- en navigatierijen tonen hun huidige waarde (`settingValuePlacement`): zonder uitleg
  rechts voor de chevron, met uitleg aan het eind van de titelregel zodat de uitleg de volle breedte
  houdt. Past de waarde niet naast de titel, dan staat hij heel op de regel eronder, zoals vóór A-24
  (bijvoorbeeld drie servernamen of "Auto (Aanbevolen)"). De titel heeft altijd voorrang.
- Segmentknoppen: een label van één woord ("Systeem") krimpt binnen zijn segment in plaats van midden
  in het woord af te breken.
- Kaarten 14 pt rond, op OLED een kaartkleur van `#1A1A1C` tegen de zwarte pagina; sectiekoppen in licht
  `#A0432A` (5,9:1 op de lichte pagina), in donker en OLED de gedempte tekstkleur.
- Zoekveld op de hoofdpagina, op een iPhone: gevulde balk zonder rand, zelfde zoekindex.

## Hoofdpagina (`settings_screen.dart`, `parts/settings_phone_page.dart`)

`settings_screen_test` is de id-test onder `--dart-define=PLEYA_VERIFY=true` (tien tegels) plus de
Tautulli-voorwaarde; het scenario `ios.settings.northstar` loopt dezelfde lijst op de simulator.

| Rij en route | Platformvoorwaarde | Voorkeur of provider | Nieuwe plek | Test |
| --- | --- | --- | --- | --- |
| Steun Pleya (extern) | `DonationService.isEnabled` | geen | eerste kaart, ongewijzigd | geen nieuwe |
| Weergave → `AppearanceSettingsScreen` | geen | `ThemeProvider`, `libraryDensity` | Bibliotheek; thema rechts, dichtheid als ondertitel | `settings_phone_page_test` |
| Zichtbare bibliotheken → `LibraryVisibilityScreen` | geen | `HiddenLibrariesProvider` | Bibliotheek, ongewijzigd | geen nieuwe |
| Lokale bibliotheek → `LocalLibrarySettingsScreen` | geen | `LocalLibraryProvider` | Bibliotheek, ongewijzigd | `local_library_settings_screen_test` |
| Indeling van Home → `HomeLayoutScreen` | geen | `HomeLayoutProvider` | Bibliotheek, ongewijzigd | `home_layout_screen_test` |
| Video afspelen → `PlaybackSettingsScreen` | geen | diverse prefs | Bibliotheek, ongewijzigd | `playback_settings_screen_test` |
| Taal en ondertitels → `LanguageSettingsScreen` | geen | profielvoorkeur taal | Bibliotheek, ongewijzigd | `language_settings_screen_test` |
| Ondertitel opmaak → `SubtitleStylingScreen` | geen | ondertitelprefs | Bibliotheek, ongewijzigd | `settings_screen_test` |
| Downloads → `DownloadsSettingsScreen` | niet op Apple TV | downloadprefs | Bibliotheek, ongewijzigd | `downloads_settings_screen_test` |
| Trackers → `TrackersSettingsScreen` | geen | `TraktAccountProvider`, `TrackersProvider` | Integraties; gekoppelde diensten op de titelregel, beschrijving blijft; te lang: diensten eronder zoals vroeger | `settings_screen_test` |
| Aanvragen → `SeerrSettingsScreen` | geen | `SeerrProvider` | Integraties; host rechts als gekoppeld | `seerr_settings_screen_test` |
| Tautulli → `TautulliSettingsScreen` | profiel beheert een Plex-server | `TautulliProvider` | Integraties; servernaam rechts als gekoppeld | `settings_screen_test` (Plex-eigenaar en Jellyfin-beheerder) |
| Big P → `AssistantSettingsScreen` | rollout-define en een `BigPMobileSession` | assistentconfig | Integraties, ongewijzigd | `assistant_settings_screen_test` |
| Profielen → `ProfileSwitchScreen` (root) | geen | `ProfileRegistry`, `ActiveProfileProvider` | Integraties; aantal als ondertitel, actief profiel rechts | `settings_screen_test` |
| Servers → `ServersScreen` | geen | `MultiServerProvider` | Verbindingen; servernamen rechts, of heel eronder als ze niet passen | `settings_phone_page_test` |
| Sneltoetsen, navigatie met toetsenbord | `KeyboardShortcutsService.isPlatformSupported()` | sneltoetsenservice, `videoPlayerNavigationEnabled` | eigen kaart, ongewijzigd | geen nieuwe |
| Samen-kijken-relay (dialoog) | geen | `customRelayUrl` | Geavanceerd, ongewijzigd | geen nieuwe |
| Crashrapportage, debuglogging | geen | `crashReporting`, `enableDebugLogging` | Geavanceerd, ongewijzigd | geen nieuwe |
| Logboeken → `LogsScreen` | geen | geen | Geavanceerd, ongewijzigd | geen nieuwe |
| Cache wissen, instellingen herstellen | geen | `SettingsService` | Geavanceerd; bevestigingsdialoog blijft | geen nieuwe |
| Op updates controleren, automatisch controleren | `UpdateService.isUpdateCheckEnabled` | `autoCheckUpdatesOnStartup` | Updates, ongewijzigd | geen nieuwe |
| Exporteren, importeren | niet op TV | bestandskiezer | Back-up; import houdt zijn bevestiging | geen nieuwe |
| iCloud-sync | iOS of macOS | `icloudSyncEnabled` | Back-up, ongewijzigd | `icloud_sync_status_test` |
| Debug (Sentry, ANR) | `kDebugMode` | geen | onderaan, ongewijzigd | geen nieuwe |
| Over Pleya → `AboutScreen` | geen | geen | laatste kaart, ongewijzigd | geen nieuwe |
| Zoeken (index van bestemmingen) | niet op TV; Tautulli met dezelfde Plex-voorwaarde | geen | onder de kop; zelfde index | `settings_phone_page_test`, `settings_search_test` |

## Subpagina's

| Pagina | Wat verandert | Voorwaarden | Test |
| --- | --- | --- | --- |
| Weergave | Studio-kop; dichtheid als rij met badge, titel en stap rechts, schuifregelaar eronder; segmentrijen met badge; keuzerijen met waarde rechts | alle `isTV`, `glassAppliesTo`, Android- en desktopvoorwaarden ongewijzigd | `appearance_settings_screen_test`, `tv_appearance_categories_test` |
| Afspelen | Studio-kop; keuze- en getalrijen met waarde rechts; audio-uitvoer, audiosync, DV-conversie en maximale resolutie houden hun uitleg als ondertitel | ongewijzigd | `playback_settings_screen_test` |
| Taal en ondertitels | Studio-kop; de vier waarderijen met het gedeelde waardelabel | ongewijzigd | `language_settings_screen_test` |
| Overige `SettingsPage`-pagina's | Studio-kop en de gedeelde rijstijl | ongewijzigd | eigen schermtests |
| tvOS | zie het hoofdstuk tvOS (PR 2) | n.v.t. | `tv_dens1_hig_test`, `settings_studio_rows_test` (groep TV) |

## Alleen in de mockups, niet in de code

Gecontroleerd tegen de code op 25 oktober 2026; deze punten komen er in PR 1 niet bij.

- Downloads: "Downloadmap bekijken" en "Opslag en status controleren". De pagina heeft locatie, alleen via
  wifi en bekeken downloads verwijderen.
- Big P: "Kindvriendelijke antwoorden" als eigen instelling. Kindprofielen en leeftijden bestaan wel.
- Profielen: "Gezinsbeperkingen" als instelling. Beperkingen volgen uit het profiel, er is geen rij.
- "Lokale bron waar mogelijk" als afspeelvoorkeur bestaat niet.

Wel in de code, dus geen mockup-verzinsel: Big P-endpoint, API-sleutel en modelkeuze
(`assistant_settings_screen*.dart`), MyAnimeList, AniList en Simkl (`TrackersProvider`), en Uitloggen,
dat in Mijn Pleya staat en niet in Instellingen.

## tvOS (PR 2)

De hoofdpagina (`parts/settings_tv_page.dart`) was een raster van tegels in twee kolommen. Nu staan de
bestaande secties als categorieën links, de rijen van de gekozen categorie in het midden (titel links,
waarde rechts) en alleen bij Bibliotheek een voorbeeld rechts: drie posters uit wat `DiscoverProvider` al
heeft geladen plus thema en dichtheid. Zonder geladen items toont het voorbeeld alleen die regel. Bij de
andere categorieën krijgen de rijen die ruimte.

De lijst met secties is dezelfde als vóór PR 2, met dezelfde sleutels, voorwaarden en routes. De twee
secties zonder kop kregen een bestaand label als categorienaam: Steun Pleya (`supportDeveloper`) en Over
(`about`). De rijen houden `my_pleya.section.tile[settings.<key>]` met dezelfde state-velden; de categorieën
registreren als `settings.category[i]`.

| Categorie | Rijen | Voorwaarde | Voorbeeld |
| --- | --- | --- | --- |
| Steun Pleya | `donate` | `DonationService.isEnabled` | nee |
| Bibliotheek | `appearance`, `library_visibility`, `home_layout`, `playback`, `language`, `subtitle_styling`, `trackers`, `requests`, `tautulli`, Big P | Tautulli alleen bij een beheerde Plex-server, Big P via `assistantSettingsTvItem` | ja |
| Verbindingen | `settings_add_connection`, `settings_pleya_share`, `settings_profiles` | geen | nee |
| Downloads | `download_location` (niet op iOS), wifi, bekeken verwijderen | niet op Apple TV | nee |
| Sneltoetsen | `video_player_controls`, `video_player_navigation` | `KeyboardShortcutsService.isPlatformSupported()` | nee |
| Geavanceerd | relay, crashrapportage, debuglogging, logboeken, cache wissen, herstellen | geen; dialogen en bevestigingen ongewijzigd | nee |
| Updates | controleren, automatisch controleren | `UpdateService.isUpdateCheckEnabled` | nee |
| Back-up | `icloud_sync` | iOS of macOS | nee |
| Over | `about` | geen | nee |

Bediening: RIGHT op een categorie gaat naar de eerste rij, LEFT vanaf een rij terug naar de gekozen
categorie, SELECT op een categorie kiest hem en SELECT op een voorkeursrij schakelt hem om. De pagina opent
zoals voorheen op Weergave. Terug van een subpagina staat de focus weer op de rij waar je vandaan kwam, in
dezelfde categorie. Weergave (`TvAppearanceCategories`) gebruikt nu dezelfde widget
(`TvSettingsCategories`), met alleen de nieuwe categoriemarkering.

De gekozen categorie krijgt een rode balk op een warme vulling, nooit de focusring; de ring blijft de enige
focusaanduiding. Kleuren per palet staan in `tv_settings_studio_style.dart`, contrast in
`tv_appearance_categories_test` (groep A-24). Gedrag in `settings_tv_page_test`.

