# Decisions (ADR-lite)

Append-only. Nummers zijn opeenvolgend; oude beslissingen worden niet verwijderd maar op `superseded`/`deprecated` gezet.

## DEC-001: Rebrand PlexFlixNetwork → Pleya

**Date:** 2026-07-03
**Status:** accepted
**Context:** "PlexFlixNetwork" combineert twee levende merken (Plex + Netflix) en het accent was exact Netflix-rood `#E50914` op Netflix-donkere surfaces — een reëel takedown-risico bij App Store-review en bij beide merkhouders.
**Decision:** Volledig rebranden naar **Pleya** (knipoog naar Plex/Plezy zonder "plex" letterlijk). Naam vervangen in display-naam, client-ID's naar servers, alle 15 i18n-locales, pubspec, README, wordmark en intro-splash. Bundle-ID `nl.michelknoop.plexflixnetwork` → `nl.michelknoop.pleya`, Android appId `com.edde746.plezy` → `nl.michelknoop.pleya`.
**Consequences:** Bundle-ID-wissel verweest de bestaande TestFlight-app (app-ID 6786811460): nieuw App Store Connect-record, App Group `group.nl.michelknoop.pleya` en provisioning nodig vóór de volgende upload. Interne Dart-package-naam `plezy`, method-channels `com.plezy/*` en PIN-salt `plezy-app-profile-pin-v1` blijven ongewijzigd (intern, geen merkrisico; salt wijzigen zou alle profiel-PINs invalideren).

## DEC-002: Merkkleuren uit het echte Pleya-logo

**Date:** 2026-07-03
**Status:** accepted
**Context:** Eerste rebrand koos een losse coral `#FF6B5E`; die paste niet bij het aangeleverde Pleya-logo.
**Decision:** Kleuren samplen uit het logo: rood **`#F42B1F`** (`kAccent`), amber **`#F68F16`** (`kAccentAlt`) en een rood→amber `kBrandGradient` (in `lib/theme/mono_theme.dart`). De P-mark en volledige wordmark worden als transparant-gekeyde crops uit de logo-PNG gebruikt (`assets/branding/pleya_logo.png`, `pleya_wordmark.png`) en als icoon-laag (`ios|macos/pleya.icon/Assets/pleya-cropped.png`). "XX% match"-badge van Netflix-signatuurgroen `#46D369` naar amber.
**Consequences:** BuildMind-brandbook-kleuren (paars/blauw) zijn developer-branding en worden bewust NIET in de app-UI gebruikt. Copyright staat in NOTICE op Michel Knoop tot BuildMind een rechtspersoon is.

## DEC-003: GPL-compliance en secrets ontgiften

**Date:** 2026-07-03
**Status:** accepted
**Context:** Pleya is een fork van GPL-3.0 "Plezy" (edde746); Michel is niet de enige rechthebbende. De app miste attributie/source-offer (GPL-schending) en shipte edde746's Trakt/Simkl/MAL-credentials, Sentry-DSN, auto-update-appcast en donatie-URL.
**Decision:** About-scherm (`lib/screens/settings/about_screen.dart`) kreeg attributie + source-link + upstream-link + privacy-link + "Developed by BuildMind"; `NOTICE`-bestand toegevoegd. Alle third-party-secrets naar `String.fromEnvironment` met lege default (feature verbergt zich netjes als niet geconfigureerd): `TRAKT_CLIENT_ID/SECRET`, `SIMKL_CLIENT_ID`, `MAL_CLIENT_ID`, `SENTRY_DSN`, `UPDATE_GITHUB_REPO/FEED_URL`, `DONATION_URL`, `PLEYA_ICE_BASE`.
**Consequences:** Voor release: repo publiek maken, `SOURCE_REPO_URL` + `PRIVACY_POLICY_URL` zetten, eigen API-apps registreren. Trackers zijn verborgen tot hun key via `--dart-define` meekomt.

## DEC-004: On-device aanbevelingssysteem (privacy-lokaal)

**Date:** 2026-07-03
**Status:** accepted
**Context:** De discover-feed had geen personalisatie — server-hubs in bibliotheekvolgorde. Alle signalen (genres, cast, rating) werden al geparsed in `MediaItem` maar nergens gebruikt.
**Decision:** Een lokale taste-engine in `lib/services/recommendations/`. Drift v17 tabellen `MediaInteractions` (append-only event-log, gedenormaliseerde features) + `AffinitySnapshots` (gecachte vector per profiel). `InteractionRecorder` abonneert op `WatchStateNotifier`; `AffinityEngine` bouwt een genormaliseerde vector met 90-dagen-decay; `recommendationScore` (puur, in `taste_profile.dart`) weegt genre/actor/director/decade/studio/mood + quality + novelty − already-seen. `RecommendationService` bouwt rijen (Top Picks / Because-you-like / Hidden Gems), gewired als optionele dependency in `DiscoverProvider`. Alles draait buiten de door tests gepinde fetch-paden zodat het call-count-contract in `discover_provider_test.dart` groen blijft.
**Consequences:** Geen ML-framework, geen externe calls: leren blijft on-device per profiel. Settings-toggle `personalizedRecommendations` (default aan); data wordt gewist bij profiel-delete (`deleteRecommendationDataForProfile`). Retentie 365 dagen / 5000 rijen. Snapshot-verversing checkt zowel row-count als `latestInteractionAt` (anders veroudert de vector bij de retentiecap).

## DEC-005: Trakt inbound en ambient trailer-previews uitstellen

**Date:** 2026-07-03
**Status:** accepted
**Context:** Het oorspronkelijke plan was A+B+Trakt-inbound plus trailer-autoplay op de billboard.
**Decision:** Trakt read-endpoints (`recommendations/trending/popular`) zijn toegevoegd, maar de mapping-naar-bibliotheek en de rijen zijn uitgesteld: Trakt is dormant zonder Michels keys en de fuzzy matching heeft live data nodig om te tunen. Ambient trailer-previews (singleton mpv-player) zijn uitgesteld omdat de mpv-lifecycle + TV-perf + audio-focus op device getest moeten worden en niet veilig ongetest vlak vóór een review te shippen zijn.
**Consequences:** Beide zijn post-build follow-ups. De read-endpoints staan klaar zodra keys geconfigureerd zijn.

## DEC-006: Pleya Share-transports als byte-pipes naar de bestaande HTTP-stack

**Date:** 2026-07-22
**Status:** accepted
**Context:** Relay- en Wi-Fi Aware-verbindingen kunnen mpv/downloads geen gewone URL geven, en het share-protocol (pairing-crypto, Range/206, watch-state) opnieuw implementeren per transport zou dubbel werk en dubbele bugs betekenen.
**Decision:** Elk nieuw transport bridged naar loopback-HTTP: de host vertaalt frames/streams naar `127.0.0.1:<hostPort>` (`pleya_share_relay_listener.dart`, `pleya_share_aware.dart`), de guest draait een loopback-proxy (`pleya_share_relay_proxy.dart`, `PleyaShareAwareProxy`). Relay-frames zijn AES-256-GCM-sealed (key uit pairSecret of code+salt); Aware is een pure byte-pipe (link-encryptie + HTTP-auth volstaan).
**Consequences:** Protocol/auth/multi-client werken ongewijzigd op elk transport; nieuwe transports zijn ~200 regels bridge-code; in-process testbaar met stubs/fake streams. ice.pleya.app moet rooms >2 peers, ~90KB frames en object-payloads ondersteunen (nog te valideren).

## DEC-007: Wi-Fi Aware als additioneel transport, nooit vervanging

**Date:** 2026-07-22
**Status:** accepted
**Context:** Michel wil routerloos device-naar-device zonder internet; Apple ondersteunt Wi-Fi Aware sinds iOS 26 (EU-verplichting), Android sinds 8.0, maar oudere devices en simulators kunnen het niet.
**Decision:** Aware toegevoegd als extra kandidaat tussen LAN en relay (`PleyaShareChannel.awareProxyProvider`); `isSupported == false` slaat de stap stil over. Alle bestaande paden (Wi-Fi, hotspot, kabel, USB-tethering, relay) blijven byte-voor-byte intact.
**Consequences:** Geen regressierisico op bestaande verbindingen; iOS vereist eenmalige systeem-pairing (DeviceDiscoveryUI) en `WiFiAwareServices` in Info.plist; device-QA verplicht want simulators ondersteunen Aware niet.

## DEC-008: Ondertitelsporen positioneel koppelen aan serverstreams, met bewijsplicht

**Date:** 2026-07-28
**Status:** accepted
**Context:** Bij direct play krijgt de UI alleen de containertags van mpv, dus een ondertitelspoor zonder taaltag viel terug op "Track 1" terwijl de server (Plex/Jellyfin) de taal wél kent. mpv-track-id's zijn niet gelijk aan server-stream-id's, dus koppelen op id kan niet.
**Decision:** `matchServerSubtitle()` in `lib/utils/player_subtitle_labeling.dart` koppelt op **positie** onder de niet-externe sporen aan beide kanten, en weigert te koppelen zodra het bewijs ontbreekt: geen serverdata, afwijkende aantallen, of één paar waar beide kanten een taal noemen die niet overeenkomt (`_alignmentContradicts`). Een verkeerde taal leest slechter dan geen taal, dus bij twijfel wordt niets samengevoegd; containertags winnen altijd van serverdata.
**Consequences:** De helper faalt per definitie stil, wat een verkeerd label voorkomt maar diagnose onmogelijk maakte toen hij op tvOS niet aansloeg. Daarom is `diagnoseSubtitleAlignment()` toegevoegd die de uitvalsreden benoemt, plus `logSubtitleLabelingDiagnostics()` die hem op **infoniveau** logt (debugniveau wordt in release gefilterd; Instellingen > Logs is de enige praktische inspectie op een TV). Let op de asymmetrie die dit kan triggeren: Plex vult `external` nooit, dus `isExternal` valt daar terug op "heeft een `key`" (`lib/media/media_source_info.dart`), waardoor de aantallen aan beide kanten uiteen kunnen lopen.

## DEC-009: Dictatie op Apple TV loopt via het systeem-toetsenbord, met één gedeelde client

**Date:** 2026-08-05
**Status:** accepted
**Context:** Michel wil op de Apple TV de zoekopdracht kunnen inspreken met de mic-knop van de Siri Remote. Die knop is systeem-gereserveerd: tvOS geeft apps geen microfoontoegang (geen `SFSpeechRecognizer`, geen `AVAudioSession`-opname), dus een eigen spraakherkenner is uitgesloten. De enige route is het **systeem-toetsenbord**, dat dictatie en iPhone-continuity gratis levert zodra een native tekstveld first responder is — precies wat `tvos/Runner/NativeTextEntryPlugin.swift` al deed. Tegelijk kwam er nooit gedicteerde tekst binnen bij voice search, terwijl dezelfde plugin bij gewone tekstvelden wél werkte.
**Decision:** Het zoekveld op Apple TV is een `FocusableButton` geworden (`lib/screens/search_screen.dart:_buildTvSearchHeader`) die op select de native alert opent, voorgevuld met de huidige query; de mic-knop opent dezelfde alert, want op tvOS ís die alert de dictatie-surface. De inline `TvVirtualKeyboardPanel` blijft alleen als fallback (`_nativeEntryUnavailable`). De client is uit `focusable_text_field.dart` gelicht naar één singleton `AppleTvNativeTextEntry` (`lib/services/apple_tv_native_text_entry.dart`): Flutter routeert inkomende platform-calls op **channel-naam**, dus met een instantie per aanroeper won de laatst geconstrueerde handler en landden `textChanged`-events op een afgeronde sessie met genulde callback. De singleton geeft ze aan de actieve sessie door.
**Consequences:** Op Apple TV opent het toetsenbord alleen op expliciete select — nooit op focus, want die auto-open veroorzaakte eerder een reopen-loop (zie `_syncTvKeyboardAutoOpen`). Partials streamen naar de controller zodat de bestaande debounce meezoekt en resultaten er al staan zodra de alert sluit; de alert is fullscreen, dus tijdens het dicteren zie je ze niet. `BUSY` is een stille no-op — fallbacken zou een Flutter-toetsenbord achter de zichtbare alert stapelen. Geen Info.plist- of entitlement-wijzigingen nodig: de app raakt de microfoon nooit aan. Android TV houdt zijn eigen `RecognizerIntent`-route. Dictatie en continuity zijn **niet simuleerbaar** — device-QA blijft verplicht.

## DEC-010: Xcode-systeemcomponenten bijwerken, niet verwijderen

**Date:** 2026-08-05
**Status:** accepted
**Context:** Na de Xcode-update naar 26.6 (4 aug) faalde élke build, ook via fastlane, op `DVTPlugInLoading: Failed to load code for plug-in com.apple.dt.IDESimulatorFoundation — Symbol not found ... Expected in /Library/Developer/PrivateFrameworks/DVTDownloads.framework`. Xcode.app was 26.6, maar de systeemcomponenten in `/Library/Developer/PrivateFrameworks/` stonden nog op 26.3 (receipt van 27 feb): Xcode installeert die pas bij de **eerste handmatige start** na een update, en dat was nooit gebeurd.
**Decision:** De componenten worden bijgewerkt door Xcode één keer handmatig te starten (of `sudo installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/XcodeSystemResources.pkg -target /`). `xcodebuild -runFirstLaunch` werkt hier niet: het ziet een bestaande receipt en slaat de update over.
**Consequences:** Het framework mag **niet** verwijderd worden als "stale leftover" — Xcode.app levert geen eigen kopie mee, dus weggooien maakt Xcode onbruikbaar. Alle vijf mappen (CoreDevice, CoreDeviceUtilities, CoreSimulator, DVTDownloads, ROCKit) komen uit dat ene pakket en worden in één keer gelijkgetrokken. Diagnose in twee commando's: `pkgutil --pkg-info com.apple.pkg.XcodeSystemResources` naast `xcodebuild -version` — die versies horen overeen te komen. Verwacht dit opnieuw bij elke Xcode-update; zie ook [TESTFLIGHT.md](TESTFLIGHT.md).

## DEC-011: Native tekstinvoer op tvOS eist een expliciete responder-overdracht

**Date:** 2026-08-06
**Status:** accepted
**Supersedes:** het `UIAlertController`-deel van [DEC-009](#dec-009)
**Context:** De alert uit DEC-009 bleek op een echt toestel volledig dood: pijltjes deden niets en zelfs Menu sloot hem niet. Oorzaak is een responder-conflict dat er al vanaf de eerste native-tekstinvoer in zat. `PleyaFlutterViewController` neemt first responder in `viewDidAppear` en geeft die alleen terug in `viewWillDisappear` — en een `.alert`-presentatie haalt de presenter niet uit de hiërarchie, dus dat vuurt nooit. Alle presses landen daardoor bij de Flutter-controller, die ze aan `super` geeft: `FlutterViewController` zet ze om in `flutter/keydata` en valt pas op de responder-chain terug als Dart de toets als *onafgehandeld* terugmeldt. Pleya's focus-tree handelt élke pijl en select af, dus dat gebeurt nooit. De `MenuDismissAlertController`-override zat op de alert, precies waar presses niet langskomen.
**Decision:** Eén sessie-vlag (`NativeInputSession` in `tvos/Runner/NativeTextEntryViewController.swift`) is de bron van waarheid. Zolang die actief is geeft `canBecomeFirstResponder` `false`, staat de Flutter-controller first responder af, en gaan presses naar `next?.pressesXxx(...)` in plaats van naar `super` — niet naar `return`, want dan ziet de focus-engine ze evenmin. `pressesChanged` is toegevoegd (ontbrak, terwijl de engine hem wél overschrijft). Het Menu-vangnet verhuisde naar `PleyaFlutterViewController`, het enige object dat gegarandeerd in het press-pad zit. De alert zelf is vervangen door `NativeTextEntryViewController`: één `UITextField` die in `viewDidAppear` first responder wordt, zodat tvOS meteen zijn systeem-toetsenbord toont — geen tussenscherm meer vóór de dictatie-surface. Aan Dart-kant gaat elke synthetische-key-route (`lib/utils/key_event_simulator.dart`, `GamepadService`, `AppleTvRemoteTouchService`) op slot via `lib/utils/native_input_session.dart`.
**Consequences:** Presentatie is `.overFullScreen` en **nooit** `.fullScreen`: dat laatste haalt de Flutter-view uit de hiërarchie, wat de render-surface sloopt en `AppLifecycleState.paused` naar Dart stuurt — media-controls, wakelock en server-health-checks reageren daar allemaal op. `preferredFocusEnvironments` wordt bewust **niet** op de Flutter-controller overschreven: de fork-engine doet dat zelf al en UIKit raadpleegt de presenter toch niet zolang een modal open staat. `textFieldDidEndEditing` beëindigt de sessie, anders blijf je na het sluiten van het toetsenbord achter met een lege overlay die je nóg eens moet wegklikken. Een watchdog van 4 s zonder `textFieldDidBeginEditing` geeft `KEYBOARD_DEAD`/`KEYBOARD_UNAVAILABLE` terug en zet een latch waardoor élke aanroeper terugvalt op het inline D-pad-toetsenbord. Alleen `KEYBOARD_DEAD` (presses kwamen binnen, niets reageerde — structureel) overleeft een herstart via `SettingsService.nativeTextEntryUnavailable`; `KEYBOARD_UNAVAILABLE` blijft in-memory, want "toetsenbord kwam niet op" kan net zo goed een backgrounded app of Siri zijn. Die pref staat in de denylist van `SettingsExportService`: het is een oordeel over **dit** toestel, geen instelling om te syncen. Een tweede sessie wordt in Dart geweigerd (`_sessionActive`) en niet pas door de plugin — anders sluit de `finally` van de afgewezen aanroep de gate van de sessie die nog op het scherm staat. Twee valkuilen die pas op device zichtbaar werden (build 203). **Sluiten moet via de presenterende controller**, nooit `entry.dismiss()`: zodra het systeemtoetsenbord openstaat is dat een presentatie ván de entry-VC, en UIKit routeert `dismiss` naar het gepresenteerde kind — dus sloot die aanroep het toetsenbord en bleef de overlay staan terwijl de remote al aan Flutter was teruggegeven (achtergrond navigeerde wél terug, venster niet weg). **En `viewDidAppear` vuurt tweemaal**, want tvOS presenteert zijn toetsenbord óver de entry-VC; opnieuw first responder vragen heropent het toetsenbord meteen — dezelfde reopen-loop als in [DEC-009](#dec-009). Een tweede `viewDidAppear` betekent nu: klaar. Let op bij het gaten van de touch-route: de select die het toetsenbord opent komt binnen als `click_s` → key-down, waarna de bijbehorende `click_e` mét actieve sessie arriveert en weggegooid wordt. Zonder `_releaseSelectForNativeSession()` blijft `_selectPressedFromClick` staan en slikt `_shouldConsumeNativeSelectDuplicate` de eerstvolgende echte select ná de sessie in. De gamepad-gate raakt alléén een gekoppelde MFi-controller — de Siri Remote komt nooit langs `GamepadService`, dat is puur een UIKit-responderprobleem. Device-QA blijft verplicht (dictatie is niet simuleerbaar).
