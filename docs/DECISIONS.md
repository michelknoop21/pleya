# Decisions (ADR-lite)

Append-only. Nummers zijn opeenvolgend; oude beslissingen worden niet verwijderd maar op `superseded`/`deprecated` gezet.

> **Hernummering 21 augustus 2026.** Het app-spoor en het Pleya Server-spoor
> nummerden na DEC-029 onafhankelijk door en botsten bij de integratie op
> DEC-030 tot en met DEC-039 en op DEC-049. Het serverspoor hield zijn nummers
> (22 besluiten, 76 verwijzingen); het app-spoor is opgeschoven. Verwijzingen in
> commits en sessielogboeken van vóór die datum lees je met deze tabel:
>
> | oud (app) | nieuw | oud (app) | nieuw |
> | --- | --- | --- | --- |
> | DEC-030 | DEC-052 | DEC-036 | DEC-058 |
> | DEC-031 | DEC-053 | DEC-037 | DEC-059 |
> | DEC-032 | DEC-054 | DEC-038 | DEC-060 |
> | DEC-033 | DEC-055 | DEC-039 | DEC-061 |
> | DEC-034 | DEC-056 | DEC-049 | DEC-062 |
> | DEC-035 | DEC-057 | | |
>
> Historische sessielogboeken zijn bewust niet herschreven: die zijn
> tijdgebonden bewijs van wat er toen stond.

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
**Consequences:** Presentatie is `.overFullScreen` en **nooit** `.fullScreen`: dat laatste haalt de Flutter-view uit de hiërarchie, wat de render-surface sloopt en `AppLifecycleState.paused` naar Dart stuurt — media-controls, wakelock en server-health-checks reageren daar allemaal op. `preferredFocusEnvironments` wordt bewust **niet** op de Flutter-controller overschreven: de fork-engine doet dat zelf al en UIKit raadpleegt de presenter toch niet zolang een modal open staat. `textFieldDidEndEditing` beëindigt de sessie, anders blijf je na het sluiten van het toetsenbord achter met een lege overlay die je nóg eens moet wegklikken. Een watchdog van 4 s zonder `textFieldDidBeginEditing` geeft `KEYBOARD_DEAD`/`KEYBOARD_UNAVAILABLE` terug en zet een latch waardoor élke aanroeper terugvalt op het inline D-pad-toetsenbord. Alleen `KEYBOARD_DEAD` (presses kwamen binnen, niets reageerde — structureel) overleeft een herstart via `SettingsService.nativeTextEntryUnavailable`; `KEYBOARD_UNAVAILABLE` blijft in-memory, want "toetsenbord kwam niet op" kan net zo goed een backgrounded app of Siri zijn. Die pref staat in de denylist van `SettingsExportService`: het is een oordeel over **dit** toestel, geen instelling om te syncen. Een tweede sessie wordt in Dart geweigerd (`_sessionActive`) en niet pas door de plugin — anders sluit de `finally` van de afgewezen aanroep de gate van de sessie die nog op het scherm staat. **De echte oorzaak dat Menu niets deed** (gemeten in de simulator, tvOS 26.2): `press.type == .menu` matcht nooit. De runtime levert de Menu-druk als raw value **2041**, terwijl `UIPress.PressType.menu.rawValue` naar **5** compileert (select = 2040). De escape hatch werd dus overgeslagen en de druk ging naar `next?` in plaats van naar de sessie — zonder actieve sessie ging Menu naar `super` en werkte hij wél, precies het verschil dat op device zichtbaar was. `containsMenuPress()` in `AppDelegate.swift` matcht daarom op de symbolische case **én** de gemeten raw value **én** `key?.keyCode == .keyboardEscape`. Let op: `handlePlayPausePress` vergelijkt nog steeds met `.playPause` en is dus vermoedelijk al even dood — niet aangeraakt, want buiten scope. Twee eerdere valkuilen (build 203). **Sluiten moet via de presenterende controller**, nooit `entry.dismiss()`: zodra het systeemtoetsenbord openstaat is dat een presentatie ván de entry-VC, en UIKit routeert `dismiss` naar het gepresenteerde kind — dus sloot die aanroep het toetsenbord en bleef de overlay staan terwijl de remote al aan Flutter was teruggegeven (achtergrond navigeerde wél terug, venster niet weg). **En `viewDidAppear` vuurt tweemaal**, want tvOS presenteert zijn toetsenbord óver de entry-VC; opnieuw first responder vragen heropent het toetsenbord meteen — dezelfde reopen-loop als in [DEC-009](#dec-009). Een tweede `viewDidAppear` betekent nu: klaar. Let op bij het gaten van de touch-route: de select die het toetsenbord opent komt binnen als `click_s` → key-down, waarna de bijbehorende `click_e` mét actieve sessie arriveert en weggegooid wordt. Zonder `_releaseSelectForNativeSession()` blijft `_selectPressedFromClick` staan en slikt `_shouldConsumeNativeSelectDuplicate` de eerstvolgende echte select ná de sessie in. De gamepad-gate raakt alléén een gekoppelde MFi-controller — de Siri Remote komt nooit langs `GamepadService`, dat is puur een UIKit-responderprobleem. Device-QA blijft verplicht (dictatie is niet simuleerbaar).

## DEC-012: Richtingsinvoer op tvOS heeft één eigenaar per gebaar

**Date:** 2026-08-06
**Status:** accepted
**Context:** Eén veeg over de touch-surface van de Siri Remote levert pijltjes via twee onafhankelijke paden: tvOS' eigen swipe-recognizer synthetiseert `UIPress`-pijlen die de engine als `KeyEvent` aflevert, en diezelfde engine-fork streamt daarnaast de ruwe touch-coördinaten op `flutter/gamepadtouchevent`, waar `AppleTvRemoteTouchService` zelf pijltjes uit bouwt. Die twee werden ontdubbeld per losse toets binnen 120 ms. Dat lekt op twee manieren. **Tijd:** het venster start op emit-moment, terwijl `simulateKeyPress` de dispatch uitstelt tot een post-frame callback — één trage frame (poster-decode, de 250 ms scroll-animatie in de rail) en de native pijl valt erbuiten, dus bewoog de focus twee cellen. Een test legde dat gedrag zelfs vast als gewenst ("delayed native directional press after swipe still passes through"), bedoeld als "tweede bewuste veeg". **As:** beide paden bepalen de veeg-as los van elkaar, en de ontdubbeling matchte alleen dezelfde toets — bij een diagonale veeg kon het ene pad `arrowLeft` geven en het andere `arrowDown`, allebei geldig, samen een sprong schuin weg. Symptomen: focus slaat items over en gaat soms een richting op die je niet geveegd hebt, op álle schermen even erg.
**Decision:** Niet ontdubbelen per toets binnen een tijdvenster, maar **eigenaarschap latchen per gebaar**. De eerste bron die een richting produceert bezit het hele gebaar; de andere wordt gedempt tot het gebaar eindigt. Bezit de accumulator het gebaar, dan consumeert `handleNativeKeyEvent` élk directioneel event — ongeacht toets en ongeacht `KeyDown`/`KeyRepeat`/`KeyUp`. Komt een native pijl eerst (klik op de richtingsring, of tvOS' recognizer wint de race), dan bezit het native pad het gebaar en emit `_moveTouch` niets meer. De tellers die konden desynchroniseren zijn daarmee weg, en `KeyRepeatEvent` — dat in de oude ontdubbeling helemaal niet werd afgehandeld en dus altijd doorlekte — valt nu vanzelf onder de latch.
**Consequences:** Het bezit blijft na het optillen van de vinger nog `gestureOwnershipGrace` (250 ms) staan, want tvOS' recognizer levert zijn `UIPress` regelmatig pas ná `touchesEnded`; zonder die grace voegt die naloper alsnog een tweede stap toe. Een nieuw `started`-bericht neemt een nog lopend *swipe*-bezit over in plaats van te resetten, zodat bij snel achter elkaar vegen de naloper van veeg N niet in veeg N+1 doorglipt; een native bezit start wél vers. Degradeert veilig in beide richtingen: blijft het touch-kanaal stil (ouder remote, iPhone Remote-app), dan wordt de accumulator nooit eigenaar en gaan native pijlen door zoals voorheen. Daarnaast schuift het veeg-anker nu met exact één drempel op in plaats van naar de vinger te snappen — snappen gooide de reis voorbij de drempel weg, en hoevéél weggegooid werd hing af van sample- en frametiming, dus leverde dezelfde fysieke veeg de ene keer één en de andere keer drie stappen. Het aantal stappen is nu `floor(afstand / drempel)`. De 190 ms-cooldown blijft als snelheidsplafond maar draagt de logica niet meer. De as-hysterese in `_resolveSwipeAxis` is **bewust ongemoeid** gelaten: die is op device getuned (zes tests) en de verkeerde-richting-klacht komt aantoonbaar uit de cross-as-lek hierboven, niet uit de as-keuze zelf. `GamepadDuplicateInputGuard` blijft ongewijzigd — die bedient ook de Windows/Steam-Input-route — en `shouldSuppressSyntheticKey` blijft in `_emitKey` als eerste horde staan. De select-kant (`_shouldConsumeNativeSelectDuplicate`) is niet aangeraakt: ander faalpatroon, recent gehard. Device-QA blijft verplicht; een Siri Remote is niet te simuleren.

## DEC-013: Passthrough wint van loudness-normalisatie, en de badge volgt de beslissing

**Date:** 2026-08-09
**Status:** accepted — implementatie nog niet gestart
**Context:** Drie losse waarnemingen bleken één onderwerp. **(1)** Loudness-normalisatie zet `af=loudnorm=…` en normaliseren vereist gedecodeerde PCM, terwijl passthrough de compressed bitstream juist ongewijzigd doorstuurt. Niets coördineert dat, terwijl voor afspeelsnelheid precies zo'n guard al bestaat (`lib/mpv/player/player_native.dart:311-323`, "mpv cannot scaletempo compressed audio and silently keeps playing at 1x"). Sterker: Android TV arbitreert het conflict al, maar de andere kant op — `ExoPlayerCore.kt:1952-1955` blokkeert direct output zodra `audioNormalizationEnabled`, terwijl `AudioOutputCoordinator` `_lastDecision = passthrough` blijft rapporteren en de stall-watchdog draait. De badge liegt daar dus vandaag. Bovendien schrijft `video_player_screen.dart:886-889` de normalisatie ná `audioOutput.prepare()`, en bij `off` wordt `af` helemaal nooit geschreven, zodat een `loudnorm` uit een vorige sessie in de statische, gedeelde mpv-core blijft hangen. **(2)** Tijdens een aantoonbaar werkende E-AC3-bitstream (`AO: [avfoundation] … spdif-eac3`, `EAC3 config: … JOC=yes`) logt de mpv-fork `audio rendering mode: not-applicable`. De app leest exact diezelfde `AVAudioSession.renderingMode` (`shared/apple/AudioSession/AudioSessionPlugin.swift:137`) en `audioRenderingLabel()` mapt `notApplicable` op `null`, dus de badge verdwijnt precies wanneer hij iets te melden heeft. `AudioOutputCoordinator.decision` bestaat, draagt de doc-comment "for the player's rendering badge", en heeft geen enkele lezer in `lib/` of `test/`. **(3)** `auto` bitstreamt sinds build 211 hardcoded nooit, dus de standaardgebruiker krijgt geen Atmos, ook niet op een HDMI-route naar een receiver die het prima aankan.
**Decision:** **Passthrough wint van normalisatie.** `loudnorm` wordt opgeschort zolang de bitstream loopt en automatisch hersteld zodra hij wegvalt — hetzelfde mechanisme als de rate-guard, met de winnaar omgedraaid omdat passthrough de expliciete, enkelvoudige opt-in is en normalisatie een comfortinstelling. De arbitrage komt in een nieuwe `AudioPathArbiter` (`lib/mpv/player/audio_path_arbiter.dart`) die door de speler wordt aangeroepen, niet door de coordinator: `_applyPassthrough` wordt vanuit twee kanten getriggerd (coordinator én `setRate`) en alleen de speler ziet beide. **De badge wordt gevoed uit `AudioOutputCoordinator.decision`**, met `renderingMode` als aanvulling waar die wél iets zegt. **`auto` bitstreamt weer, maar alleen op `route.isDigitalPassthroughPort`** — dat veld bestaat al (`apple_audio_session_service.dart:63-65`) en werd nergens gebruikt — en alleen bij een *bekende* bitstreambare codec, dus zonder de `codec == null`-toegeeflijkheid die modus `passthrough` wel heeft.
**Consequences:** Volgorde is niet onderhandelbaar: `af` moet leeg zijn vóórdat `audio-spdif` wordt gezet. Zet je spdif met een filterchain eraan, dan logt mpv dat, en `AudioOutputCoordinator._onPlayerLog` leest zo'n regel als "deze receiver kan geen Dolby" en zet de route in de **statische** `_bitstreamBlocked` — voor de rest van de app-run, over alle afleveringen heen. De cache van geduwde waarden wordt pas ná de await geschreven, anders ziet een mislukte write eruit als toegepast en slaat elke volgende sync hem over (zelfde argument als `audio_output_coordinator.dart:287-291`). De geduwde staat begint op `null` in plaats van op een aangenomen default, omdat de mpv-core statisch en gedeeld is en een vorige sessie er iets in kan hebben achtergelaten. Android heeft **geen** Kotlin-wijziging nodig: door de *effectieve* modus door te sturen wordt `audioNormalizationEnabled` native `false` zodra de bitstream loopt, valt de block weg en komt passthrough op waar dat nu stil faalt. Bekende ruwe rand daar: bij een gelijktijdige flip doen zowel `setAudioNormalization` als `setAudioPassthrough` een `startAudioRendererBounce`, dus twee hoorbare bounces achter elkaar — aparte follow-up, vereist device-test. De `auto`-wijziging gaat pas door **nadat** op een echte Apple TV met AVR is vastgesteld dat de bitstream daar aankomt; het vangnet uit build 212 blijft de ondergrens. Plan met stappen en verificatie: `~/.claude/plans/pleya-v2-8-0-211-ios-smooth-frog.md`.

## DEC-014: ice.pleya.app draait op de NAS achter een Cloudflare Tunnel

**Date:** 2026-08-09
**Status:** accepted — live sinds 2026-08-10
**Context:** `PLEYA_ICE_BASE` (default `https://ice.pleya.app`) voedt vier features: log-upload (`lib/screens/settings/logs_screen.dart:144`), Watch Together (`watch_together_peer_service.dart:27`), Discord-poster-hosting (`discord_rpc_service.dart:31`) en de Pleya Share-relay-fallback (`pleya_share_relay.dart:24`). Die hostnaam **resolvet niet** — er is nooit een DNS-record voor aangemaakt. De rebrand zette de app-kant om van `plezy` naar `pleya`, maar `server/Caddyfile` en `server/docker-compose.yml` bleven op `ice.plezy.app` staan, wat naar de server van de upstream-fork wijst (212.132.75.249). Gevolg: de log-uploadknop eindigt altijd in `logsUploadFailed`, en Pleya Share valt terug op alleen-LAN. Concreet gemist: de Apple TV kan zijn eigen log nergens heen sturen, wat het Atmos-onderzoek blokkeerde. De server zelf ontbrak niet — `server/main.go` (Go, uit de fork) heeft `/logs`, `/logs/<id>`, `/relay`, `/posters`, `/health` en een OAuth-proxy, en het log-contract klopt exact met wat de app verwacht (geverifieerd: `POST` met `text/plain` → `200` + `application/json` + `{"id":"<5 tekens>"}`).
**Decision:** De relay draait op de Synology achter een **Cloudflare Tunnel**: `cloudflared` belt naar buiten, dus geen inkomende poorten en Cloudflare termineert de TLS — dezelfde route die `pleya.app` al loopt. Dat omzeilt het feit dat de compose Caddy hostpoorten 80 en 443 gaf, die op een Synology al van DSM zijn. Caddy blijft beschikbaar achter een `vps`-profile voor het geval de relay ooit naar een eigen server verhuist. Volledige binary live, dus inclusief `/relay` en de OAuth-proxy; de `bugs`-container uit de fork is eruit gelaten. Deploy via `server/deploy-nas.sh` naar `/volume1/docker/pleya-relay`, met poort 8831 voor LAN-verificatie.
**Consequences:** Handmatig vooraf, en alleen door Michel te doen: tunnel aanmaken in Cloudflare, public hostname `ice.pleya.app` → `http://relay:8080`, en `TUNNEL_TOKEN` in `/volume1/docker/pleya-relay/.env` (gitignored via de root-`.gitignore`-regel `.env`). Cloudflare zet het DNS-record zelf, een handmatig A-record is niet nodig. Gebruik in de compose **geen** `${VAR:?}`-guard: die wordt bij het parsen geëvalueerd en blokkeert dan ook `up relay` en het `vps`-profile — de controle hoort in het deploy-script, en staat daar nu. De LAN-poort is bewust `127.0.0.1:8831` en niet `0.0.0.0`: `POST /logs` is onauthenticated en de OAuth-proxy zit op dezelfde poort, dus een open binding zou alles op het LAN — en alles dat via een bestaande port-forward binnenkomt — langs Cloudflare's TLS, WAF en rate limiting laten; het deploy-script verifieert over ssh op de NAS zelf. **`OAUTH_BASE_URL` verandert de redirect-URI**: `oauth.go:409-411` bouwt hem als `<base>/auth/<service>/callback`, en MyAnimeList en AniList valideren die tegen hun developer-console-registratie, dus die moeten op `https://ice.pleya.app/...` staan vóór de deploy — anders faalt elke koppelpoging met `redirect_uri_mismatch`. Het deploy-script draait met `--remove-orphans`, want `bugs` is uit de compose gehaald en `caddy` zit achter een profile; zonder die vlag blijft een eerder gestarte container gewoon doordraaien. Operationele grenzen uit `server/main.go:38-42`: 1 MB per log, 3 dagen retentie, 500 entries, één upload per minuut per IP, ID van 5 tekens. Die vijf tekens zijn bewust kort genoeg om van een TV-scherm af te lezen, maar daarmee is een log-URL semi-openbaar: tokens worden geredigeerd vóór verzending (`app_logger.dart:89`), server-URL's en IP-adressen niet. Zodra de host leeft werkt de bestaande uploadknop op elk toestel zonder nieuwe build — build 212 heeft hem al — en gaat de openstaande blocker over de Pleya Share-productierelay er tegelijk mee dicht.

## DEC-015: De uitweg naar de andere backend hoort tijdens het wachten, en breekt de poging af

**Date:** 2026-08-10
**Status:** accepted
**Context:** Twee App Review-rondes strandden op 2.1(a) met *"the app displayed 'Authentication timed out' after we entered demo account"* (6 juli, iPad Air M3). Die string had precies één consument: `lib/screens/auth/plex_pin_auth_flow.dart:175`, de Plex PIN-flow. De reviewer koos dus "Sign in with Plex" en typte daar het Jellyfin-demoaccount in; zo'n PIN wordt nooit geclaimd en de poll loopt af. `demo.pleya.app` antwoordt in 60-190 ms, dus traagheid speelde geen rol. Sinds `93e82da` was de melding al milder, stonden Plex en Jellyfin gelijkwaardig op het inlogscherm en bestond de knop `auth.usingJellyfinInstead` — maar alleen in `_buildErrorBlock`, en diezelfde commit verruimde de poll van twee naar **vijf** minuten. Vanuit de reviewer gezien werd het daarmee slechter dan de afgewezen build: vijf minuten naar een PIN staren voordat de app de uitweg aanbiedt. Hij wacht niet, hij noteert "bug".
**Decision:** Dezelfde knop en dezelfde i18n-key ook onder de PIN tonen, op de twee plekken die al `_buildErrorBlock` inhaken (`_buildQr` en `_buildBrowserWaiting`), als ingetogen `TextButton` zodat hij de PIN niet overschreeuwt. Gate op `onSwitchToJellyfin != null`, zoals de foutvariant al deed, zodat "Plex-account toevoegen" vanuit Instellingen ongewijzigd blijft. `_switchToJellyfin()` bumpt nu `_attemptId` en zet `_isPolling`/`_qrAuthUrl` terug vóór de callback. Testbaarheid via een `@visibleForTesting authServiceFactory` op `PlexPinAuthFlow`.
**Consequences:** Het afbreken is geen nette bijvangst maar noodzaak: de ouder (`auth_screen.dart:201`) pusht `AddJellyfinScreen` bóven deze widget, die dus blijft leven en doorpollt. Zonder de bump zou een alsnog geclaimde PIN `onTokenReceived` → `_connectToAllServersAndNavigate` uitvoeren, en die doet een `pushReplacement` — dwars door het Jellyfin-scherm heen, midden in het typen. De vijf minuten poll blijft staan: die is bewust verruimd voor wie écht op plex.tv inlogt (accountaanmaak, 2FA); het probleem was nooit de duur maar dat de uitweg erna kwam. `_buildErrorBlock` blijft de enige plek met een retry-knop, en de `_errorMessage`-tak in beide poll-builders is onbereikbaar (pre-existing) — daarom verschijnt er geen dubbele knop. Bijbehorende paperassen: `docs/APP_REVIEW_NOTES.md` zet de waarschuwing nu bovenaan, `docs/app-review-reply-2026-08.md` bevat het conceptantwoord, en de ASC-versierecords voor macOS en tvOS zijn van 1.0 naar 2.8.0 gezet zodat er überhaupt een build aan te koppelen is (app-id `6787464031`).

## DEC-016: Laden, leeg en stuk zijn drie toestanden — en een tegenspraak telt pas na een bezinkdeadline

**Date:** 2026-08-10
**Status:** accepted
**Context:** Op macOS toonde Pleya bij het opstarten geen profielen; pas na een druk op Esc verscheen "Pleya-profiel toevoegen". Twee oorzaken over elkaar. **(1)** `profile_switch_screen.dart:114` stond op `initialData: ProfilesView.empty` en las nergens `connectionState` of `hasError`, dus "nog niet geladen", "leeg" en "stilgevallen" renderden identiek — permanent en zonder feedback. Extra scherp omdat `watchProfilesView` een handgeschreven `_combineLatest4` is die pas emit als álle vier de bronnen een waarde hebben: één trage of stille bron en het scherm blijft voorgoed leeg. **(2)** In de lege tak vulde `SliverFillRemaining` (default `hasScrollBody: true`) de hele viewport, en de toevoeg-knop stond als eigen sliver structureel eronder. Op TV valt dat niet op omdat `InputModeTracker` daar in keyboard-modus start en de knop meteen focus krijgt; macOS start in pointer-modus (`input_mode_tracker.dart:58`) en `FocusedScrollScaffold._requestInitialFocus()` is expliciet gated op keyboard-modus (`focused_scroll_scaffold.dart:67`). Esc — of élke pijltoets — flipt de modus, waarna `nextFocus()` de knop pakt en `_scrollIntoView` hem in beeld trekt. Er lag dus niets overheen: de knop stond onder de vouw. Het raadsel eronder: `main.dart:1218-1244` pusht de picker uitsluitend als `ActiveProfileProvider.profiles` níét leeg is, dus twee bronnen van waarheid spreken elkaar tegen.
**Decision:** Drie toestanden in plaats van één. `initialData` weg; een uitblijvende snapshot geeft een spinner, een echt lege lijst geeft de lege staat mét de toevoeg-knop erin, en een fout geeft `ErrorStateWidget` met opnieuw proberen (`_reloadProfiles()` vervangt de stream-identiteit). Een lege stream terwijl `ActiveProfileProvider` wél profielen kent telt als **onbezonken**, niet meteen als fout: pas als die tegenspraak de `_settleDeadline` van vijf seconden overleeft, wordt het de fouttoestand. De knop zit in de lege staat zelf, met `hasScrollBody: false`. De focus-gate in `FocusedScrollScaffold` is bewust níét gesloopt. Diagnostiek in `profiles_view.dart`: na drie seconden zonder emissie logt `_combineLatest4` welke slots gevuld en welke pending zijn, en de eerste lege snapshot logt de vier invoergroottes — op infoniveau, want `appLogger.d` wordt gefilterd.
**Consequences:** De deadline is er omdat de picker en `ActiveProfileProvider` dezelfde registries via **losse** abonnementen volgen (`_localSub`/`_connSub`/`_plexHomeSub` tegenover `_combineLatest4`), en `activate()` bovendien in-memory muteert: bij het verwijderen van het laatste profiel loopt de stream een moment vóór op de provider. Zonder marge zou dat "er ging iets mis" tonen met een retry die niets kan oplossen. De deadline wordt opnieuw gespannen zodra het scherm iets echts toont, zodat een latere stilte alsnog gemeld wordt; `_reportedStalledStream` gaat dan ook terug op `false`. `hasScrollBody: false` is niet cosmetisch: mét `true` kan de lege staat op een korte landscape-viewport of bij grote tekstschaal niet scrollen en loopt hij over — de bijbehorende test draait daarom expliciet op 700×310. Let op dat die stand intrinsics meet, dus de inhoud van `StateMessageWidget` moet intrinsic-veilig blijven (zelfde valkuil als de `QrImageView` in `plex_pin_auth_flow.dart:346`). Op TV verandert er niets: die start in keyboard-modus en de knop kreeg daar altijd al focus. Welke van de vier bronnen op macOS stilvalt is nog niet bewezen — dat is precies wat de nieuwe logregel bij de volgende koude start moet verklappen; verdachte is `ConnectionRegistry.watchConnections()` (`connection_registry.dart:25-29`), de enige met `asyncMap` + crypto per rij.

## DEC-017: De enige plek die remote-input kan tegenhouden is de early key handler van FocusManager

**Date:** 2026-08-14
**Status:** accepted, vervangt de diagnose in DEC-011
**Context:** Op Apple TV bediende de D-pad de UI achter het geopende systeemtoetsenbord: select liet het scherm eronder scrollen en de focus verspringen. DEC-011 schreef dat toe aan de responder chain en loste het daar op (`canBecomeFirstResponder`, presses naar `next?` in plaats van `super`). Die diagnose bleek onvolledig. De tvOS-fork-engine swizzlet in `+load` zowel `-[UIApplication sendEvent:]` als `-[UIWindow sendEvent:]` naar `flutterTvos_sendEvent:`, en `FlutterTvosFlutterViewControllerForPress` heeft een onvoorwaardelijke laatste stap die alle scenes en windows afloopt tot hij een `FlutterViewController` vindt. Die vindt dus altijd de root-controller, ook als het systeemtoetsenbord first responder is. Elke press komt daarmee als `flutter/keydata` bij Dart, buiten de responder chain om, en de hele DEC-011-fix draait op een pad dat bij een open toetsenbord nooit wordt uitgevoerd. Alleen Menu ontsnapt, via `shouldPassMenuPressToSystem:`. Daaronder zat een tweede valkuil: de bestaande Dart-gate hing aan `HardwareKeyboard.instance.addHandler`, en een handler die daar `true` teruggeeft stopt de focus-tree niet. `KeyEventManager.handleRawKeyMessage` roept na alle handlers onvoorwaardelijk `_dispatchKeyMessage` aan, dus `FocusManager` loopt `primaryFocus` en zijn voorouders sowieso af. `true` betekent alleen "meld handled aan de embedder", en maakte het zelfs erger doordat de press ook niet meer terugviel op de responder chain.
**Decision:** De gate zit op `FocusManager.instance.addEarlyKeyEventHandler`, want die draait vóór de focus-tree-walk. Zolang `NativeInputSession.isActive` waar is antwoordt hij `KeyEventResult.handled` op alles. Back en escape zijn de uitzondering die nog iets moet dóén: die roepen eerst `NativeInputSession.requestClose()` aan en worden daarna alsnog geconsumeerd, zodat de focus hoe dan ook blijft staan. Registratie gebeurt vanuit `apple_tv_native_text_entry.dart` (`native_input_session.dart` is bewust foundation-only) en is remove-then-add in plaats van een guard-bool, omdat de handlerlijst duplicaten accepteert en widget-tests per test een verse `FocusManager` krijgen. De bestaande gate in `apple_tv_remote_touch_service.dart` blijft staan maar bezit de close niet meer, anders vuren er twee platform-calls per druk. Aan Swift-kant meldt `NativeTextEntryField.finish()` het resultaat pas in de completion van de dismissal, met een backstop-timer van een seconde.
**Consequences:** De fix geldt centraal voor élk invoerveld op tvOS (zoeken, inloggen, server-URL, Seerr) zonder werk per veld. De backstop-timer is geen luxe: zonder terugmelding blijft de Dart-`edit` eeuwig hangen, blijft `NativeInputSession` actief en slikt de gate daarna álle input, wat een remote oplevert die op geen enkel scherm meer iets doet. Datzelfde scenario is ook het enige resterende risico dat alleen op een toestel te zien is; reageert de remote niet meer na een toetsenbordsessie, dan is dit de verdachte. Vier tests leggen vast dat submit, een platformfout en een geweigerde tweede sessie de vlag alle drie terugzetten, en dat de remote na een mislukte sessie weer werkt. De documentatie van DEC-011 beschrijft daarnaast nog een gepresenteerde view controller; het veld hangt inmiddels als 1x1-subview ín de FlutterView, dus `.overFullScreen` en `preferredFocusEnvironments` zijn daar niet meer van toepassing.

## DEC-018: Zonder ITSAppUsesNonExemptEncryption bereikt een macOS-build geen enkele tester

**Date:** 2026-08-14
**Status:** accepted
**Context:** De laatste macOS-build die in TestFlight installeerbaar was, was 196, terwijl de release-lane sindsdien meermaals "Successfully uploaded" meldde en de ASC-API `processingState: VALID` teruggaf. `macos/Runner/Info.plist` miste `ITSAppUsesNonExemptEncryption`; `ios/Runner/Info.plist` en `tvos/Runner/Info.plist` hadden hem allebei wel. Apple zet een build zonder die sleutel op `internalBuildState: MISSING_EXPORT_COMPLIANCE`, en in die toestand is hij voor geen enkele tester zichtbaar, ook niet intern. Alles ervóór in de keten slaagt, dus de lane-output is misleidend groen en het gat valt pas op als iemand in TestFlight kijkt. Bevestigd via `/v1/builds/{id}/buildBetaDetail`: alle macOS-builds vanaf 210 stonden op `MISSING_EXPORT_COMPLIANCE`, alle iOS- en tvOS-builds op `IN_BETA_TESTING`.
**Decision:** De sleutel staat nu in `macos/Runner/Info.plist` met waarde `false`, gelijk aan de andere twee platforms. De al geüploade builds 214 en 216 zijn zonder nieuwe build losgetrokken met `PATCH /v1/builds/{id}` en `{"attributes":{"usesNonExemptEncryption":false}}`.
**Consequences:** `processingState: VALID` is geen bewijs dat een build testbaar is; `internalBuildState` uit `buildBetaDetail` is dat wel, en dat is de check die bij twijfel gedraaid moet worden. Diagnose gaat het snelst rechtstreeks tegen de ASC-API met de sleutels uit `.env` (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`); Ruby met de gems van fastlane heeft `jwt` aan boord, dus `GEM_HOME`/`GEM_PATH` naar `libexec` van de fastlane-formule wijzen volstaat. Let bij het lezen van ASC op twee dingen die verwarring geven: er bestaan twee app-records (`nl.michelknoop.pleya` met id `6787464031` is de actuele, `nl.michelknoop.plexflixnetwork` met id `6786811460` is oud en blijft rond build 140 steken), en de `beta`-lane uploadt alleen. Distributie naar de externe testgroep is de aparte lane `external`, met Beta App Review bij de eerste build van een versie; interne testers krijgen een build wel automatisch zodra export compliance klopt.

## DEC-019: De tvOS-engine claimt elke press, dus het eigendom moet terug op de plek waar hij het vraagt

**Date:** 2026-08-15
**Status:** accepted, vult DEC-017 aan. **Op een fysieke Apple TV bevestigd met tvOS build 219**: navigeren, een letter klikken en de tekst zien verschijnen werken weer, terwijl de UI achter het toetsenbord stil blijft.
**Context:** Op Apple TV opende het systeemtoetsenbord wel, maar een klik op een letter voerde niets in. Vegen werkte, dictatie werkte, continuity-typen werkte. Disassembly van de gepinde engine (`~/.cache/flutter-tvos-engine/v3.44.0+3`) wees de oorzaak aan: `-[UIApplication(FlutterTvosPressEvents) flutterTvos_sendEvent:]` slaat de originele `sendEvent:` over zodra `FlutterTvosHandlePressesEvent` YES teruggeeft, en `-[FlutterViewController tvosHandlePressFromUIEvent:]` eindigt in `synthesizeRemotePressType:`, die onvoorwaardelijk YES retourneert (`mov w0, #0x1` op `0x4b828`, geen enkel pad dat 0 geeft). Een select-press werd dus geclaimd op de allereerste hop, voordat UIKit zijn responder chain uberhaupt begon. Vegen bleef werken omdat de swizzle bovenaan bailt op `[event type] != 3`: een veeg is UIEventTypeTouches, geen UIEventTypePresses. De scheidslijn in het symptoom viel exact samen met de scheidslijn UITouch/UIPress. Twee correcties op eerdere aannames: de Dart-gate uit DEC-017 is niet de oorzaak (select werd al opgeslokt voor die commit, DEC-017 dichtte het achtergrondlek), en er is nooit een app-side override geweest, ondanks een geheugennotitie die het tegendeel beweerde.
**Decision:** `PleyaFlutterViewController` overridet `tvosHandlePress(fromUIEvent:)` en geeft tijdens een native tekstinvoersessie `false` terug zonder `super` aan te roepen. Dan draait de originele `sendEvent:` en wordt UIKit eigenaar van de press. `super` overslaan is het punt: super synthetiseert de press en post `flutter/keydata`, dus meelopen zou het achtergrondlek terugbrengen. De selector staat in geen enkele publieke header, dus `Runner-Bridging-Header.h` (was 0 bytes) declareert hem als categorie op `FlutterViewController`; Swift importeert dat als `tvosHandlePress(fromUIEvent:)`, geverifieerd met `swiftc -typecheck` tegen de gepinde `Flutter.framework`. De sessievlag is strakker gezet: hij gaat aan bij een geslaagde `becomeFirstResponder` in plaats van ervoor in de plugin, en uit in het opruimpad van `NativeTextEntryField.finish`, na de dismissal. De invariant is: van geslaagde `becomeFirstResponder` tot daadwerkelijke responder-release bezit UIKit de remote.
**Consequences:** De hook wordt twee keer per press aangeroepen, want zowel de UIApplication- als de UIWindow-swizzle komt erop uit; hij is daarom bewust vrij van tellers en side effects. De Dart-lagen (`_blockKeysDuringSession` en de gate in `apple_tv_remote_touch_service.dart`) zijn hiermee vangnet geworden en niet meer het normale pad: verschijnt hun logregel tijdens een sessie, dan heeft de native hook gefaald en hoort de volgende stap bij de engine te liggen, niet bij een vierde filterlaag. Uitzondering die geen fout is: de key-up van de select die het toetsenbord opende hoort nog bij de vorige eigenaar. De `requestClose()`-uitzondering voor Back is vervallen, want Menu gaat nu met de rest naar UIKit. `AppDelegate` logt bij het opstarten `instancesRespond(to:)` op `FlutterViewController` (niet op een instance, want de subklasse implementeert de selector zelf en zou altijd ja zeggen), zodat een bump van `tvos/engine.version` zichtbaar wordt in plaats van stil een dood toetsenbord op te leveren. `scripts/tvos_sim.sh check-select` meet of `textChanged length=N` oploopt en of de Dart-vangnetten stil bleven; op de simulator faalt dat zolang Connect Hardware Keyboard aanstaat, omdat Return dan submit in plaats van een letter te kiezen. Twee defecten die hier los van staan en apart opgepakt moeten worden: `forwardedPressCount` telt tijdens een sessie nu nul, waardoor de watchdog altijd `KEYBOARD_UNAVAILABLE` kiest in plaats van `KEYBOARD_DEAD`, en de play/pause-afvang in `AppDelegate.swift` vergelijkt tegen een presstype dat door dezelfde raw-value-mismatch als Menu (2040/2041 tegenover 4/5) waarschijnlijk nooit matcht.

## DEC-020: De kijklijst hangt aan een account plus een echte gebruiker, niet aan een server

**Date:** 2026-08-16
**Status:** accepted
**Context:** Pleya miste de ene lijst die de Plex-app wél heeft: de universele watchlist. De API die hem levert past niet in de bestaande clientlaag. `discover.provider.plex.tv` en `metadata.provider.plex.tv` willen de plex.tv-accounttoken, terwijl `PlexClient._http.defaultHeaders` de servertoken draagt (`lib/services/plex_client.dart:332`) en `MediaServerHttpClient` die headers ook bij een absolute URL meestuurt (`lib/utils/media_server_http_client.dart:288`). Een watchlist-call vanuit `PlexClient` zou dus stil een servertoken naar een Plex-cloudhost lekken, precies zoals `lib/services/plex_client/parts/live_tv.dart` dat vandaag nog doet richting `epg.provider.plex.tv`. Daar komt een tweede scheidslijn overheen: de Plex-watchlist is van een account plus een Plex Home-gebruiker, Jellyfin-favorieten zijn van een server plus een Jellyfin-user, en beide voeden dezelfde lijst. `UserProfileProvider.currentPlexUserToken()` heeft bovendien een gedocumenteerde terugval op de owner-token als de home-user-binding nog niet draaide (`lib/providers/user_profile_provider.dart:225-233`), en met die token toon je zonder foutmelding de lijst van de verkeerde gebruiker. Het contract zelf is niet afgeleid uit documentatie maar gemeten op 16 augustus 2026 tegen een echt account met een Plex Home van twee gebruikers; het gesaniteerde bewijs staat in `test/fixtures/watchlist/`, met een README die per punt vertelt wat de meting opleverde. Vier aannames uit de planfase sneuvelden daar: het padsegment `available` gaat over streamingdiensten en niet over eigen servers, de lijst draagt geen `watchlistedAt` per titel terwijl de serverkant wel op `watchlistedAt:desc` sorteert, dubbel toevoegen geeft 200 in plaats van een fout, en alle 179 beeld-URL's in de gemeten items zijn absolute publieke CDN-links die zonder één header met 200 laden.
**Decision:** De watchlist krijgt een eigen stapel naast `PlexClient`. `PlexWatchlistClient` is een domme HTTP-laag naar het model van `PlexAuthService`: eigen `MediaServerHttpClient` zonder `defaultHeaders`, alles per call mee, en een test die de toegestane headerverzameling exact afpint. De scopecheck valt een laag hoger, in `PlexAccountWatchlistSource`, die bij elke operatie opnieuw om scoped auth vraagt en weigert zodra `isUserScoped` onwaar is; zo kan geen enkele caller per ongeluk de owner-fallback gebruiken. Identiteit zit in `WatchlistScopeId` (profiel, backend, account, gebruiker), waarvan `storageKey` elk onderdeel afzonderlijk percent-encodeert voordat hij samenvoegt, omdat een naïeve join op `:` twee verschillende scopes dezelfde sleutel kan geven en daarmee één profiel de lijst van een ander. De offline-snapshot wordt op die sleutel weggeschreven (`entries/<storageKey>`), en de availability-cache op profiel plus titel (`match/<profileId>/<key>`), want beschikbaarheid hangt aan de servers van het profiel en niet aan de bron waar de titel vandaan komt. `WatchlistEntry` draagt een lijst `WatchlistMembership`, nooit leeg en altijd met een `remoteKey`, want dezelfde film kan tegelijk een Plex-watchlistregel en een Jellyfin-favoriet zijn; kon het model maar één bron dragen, dan verdween de andere bij het mergen en kwam de titel na verwijderen terug. Verwijderen haalt de titel daarom uit alle memberships, zonder bronkeuze, en dat is niet atomair: bij een mislukking worden de al verwijderde memberships opnieuw toegevoegd, en slaagt die compensatie niet, dan volgt `partiallyFailed` in plaats van een rollback die doet alsof. Offline wordt een mutatie geweigerd en niet in de wachtrij gezet, want een uitgestelde schrijfactie heeft geen mergeregel tegen wat hetzelfde account intussen op plex.tv-web deed en zou een handmatig terugtoegevoegde titel later alsnog wissen. `coverageComplete` bestaat omdat "niet gevonden" en "niet gekeken" verschillende dingen zijn: de resolver telt eerst de verwachte eligible servers van het actieve profiel en daarna welke daarvan zonder fout antwoordden, zodat één offline server het Aanvragen-knopje niet primair maakt en er geen dubbele Seerr-aanvraag ontstaat voor een titel die je al hebt. Bronvolgorde is ordinaal: `WatchlistMembership.sourcePosition` naast het optionele `addedAt`, en `WatchlistEntry.byRecentlyAdded` maakt nooit een tijdstempel uit een positie, want de lijst levert een volgorde en geen tijd. Artwork gaat via `MediaImageHelper.catalogPosterUrl` over images.plex.tv zonder auth, met een invariant-test in `test/media/watchlist_artwork_test.dart`, zodat er geen accounttoken in een persistente image-cachekey belandt. De UI komt alleen binnen via `WatchlistUiActions`; `WatchlistActions` blijft puur en zonder `BuildContext` zodat hij zonder widgetboom te testen is. `WatchlistActions.add` geeft via `onAdded` de verse membership terug zodat de provider de rij lokaal bijzet in plaats van de lijst opnieuw op te halen, en bij `partiallyFailed` leest de provider de lijst juist wél terug. Toevoegen en verwijderen staan alleen op film en serie en alleen online; offline verdwijnt de actie in plaats van te falen. De detailknop vraagt eenmalig per profiel om een `WatchlistProvider.ensureLoaded()`, want zonder geladen lijst kan hij Toevoegen en Verwijderen niet uit elkaar houden.
**Consequences:** De watchlist is de eerste feature met een tweede Plex-transport in de app, dus wie er iets aan toevoegt moet weten dat `PlexClient` daar bewust buiten staat en er geen convenience-methode bijkomt die het alsnog samenvoegt. Het tokenlek in `live_tv.dart` blijft open en wordt los gemeten en gerepareerd, met dezelfde bewijsvolgorde: eerst vastleggen wat de huidige call doet, dan de variant zonder PMS-token, pas daarna de fix. De prijs van de ordinale bronvolgorde is dat een gemergde entry alleen te ordenen is op wat de bronnen zelf zeggen; wie per titel wil weten wanneer hij is toegevoegd betaalt daar een aparte `userState`-call voor, en de standaardvolgorde heeft die niet nodig. `partiallyFailed` betekent dat de gebruiker een lijst kan zien die niemand koos, en dat is met opzet zichtbaar in plaats van weggepoetst. De negatieve availability-cache wordt alleen bewaard als de dekking compleet was, dus na een periode met een offline server kost de eerste ronde weer echte calls. `MediaCard` is niet uitgebreid: `WatchlistCard` dispatcht naar `FocusableMediaCard` of naar een eigen kaart. Beide takken rekenen op `MediaCardGridLayout` (`lib/widgets/media_card_grid_layout.dart`), niet op `geometry.itemHeight`. Dat is een correctie van 17 augustus 2026: de kaart gaf `MediaCard` aanvankelijk de celhoogte mee, terwijl `height` daar de **poster**hoogte is en titel plus jaar er nog onder komen. Elke speelbare kaart werd zo 32px hoger dan zijn cel, en omdat `SliverGrid` niet klipt en de scroll-view bewust op `Clip.none` staat, landde de tekst van rij N op de posters van rij N+1. Wie hier iets aan verandert, moet weten dat `MediaCard.height` in standard-grid-modus de poster is en in full-bleed-modus de hele kaart, en dat `hub_section`, `tv_browse_rail` en `extras_section` alle drie op de eerste betekenis rekenen. Kopij die meer claimt dan gecontroleerd is, is vermeden omdat `LocalFolderClient` en `PleyaShareClient` geen `findByIdentity` kunnen: de sheet zegt `Not found on your connected media servers`, niet dat de titel nergens in je bibliotheken staat. Op mobiel zijn Downloads en Verzoeken twee tikken geworden in plaats van één en verhuisde Instellingen naar het tandwiel in Mijn Pleya; de bar-samenstelling wordt bepaald door capabilities, en de selectieprojectie in `main_screen.dart` zorgt dat een sprong vanuit Mijn Pleya niet de verkeerde tab laat oplichten. Wat nog niet is bewezen en dus openstaat: de tvOS-ronde over de sidebar, de focusring en de sheet, en de handmatige toestelronde met een profielwissel tussen twee Plex Home-gebruikers, een titel die tegelijk Plex-watchlist en Jellyfin-favoriet is, en een server die offline gaat.

## DEC-021: De favorietenlijst van Live TV is van een account, niet van een server

**Date:** 2026-08-17
**Status:** accepted, sluit de losse fix af die DEC-020 aankondigde
**Context:** `lib/services/plex_client/parts/live_tv.dart` haalde de favoriete kanalen op bij `https://epg.provider.plex.tv/settings/favoriteChannels` en schreef ze daar ook weg, via `_http`: de `FailoverHttpClient` van `PlexClient`, met `defaultHeaders: config.headers` en dus de **PMS-servertoken** erin. `MediaServerHttpClient._send:288` merget die headers ook bij een absolute URL, dus de servertoken van je eigen mediaserver ging bij elke lees en elke schrijf mee naar een Plex-cloudhost. Precies de fout die DEC-020 voor de kijklijst juist vermijdt. Beide methodes slikten hun fouten, dus uit de code viel niet af te leiden of favorieten vandaag werkten; dat is gemeten, gesaniteerd vastgelegd in `test/fixtures/livetv/`. De uitkomst: lezen met de servertoken geeft 200, zonder token 401 (`You must provide a token!`), met de plex.tv-accounttoken 200 met een identieke container, een lege PUT geeft met beide tokens 200, en een regel met een verzonnen `source` wordt geweigerd met 400 `Bad source value` waarbij niets wordt opgeslagen. Twee dingen kwamen tijdens het onderzoek bovendrijven die er los van stonden. `FailoverHttpClient` overridet alleen `get` (`failover_http_client.dart:78`), dus een 5xx van de cloudhost kon de endpoint-cascade van de eigen server starten en in het uiterste geval `onAllEndpointsExhausted` vuren; de PUT liep dat pad niet. En er zat een stil dataverliespad in: een mislukte lees gaf `[]`, `_loadFavorites` maakte daar een lege lijst van terwijl de store- en source-maps al gevuld waren, en één ster aantikken schreef die leegte daarna terug als de volledige lijst van het account.
**Decision:** De cloudkant verhuist naar dezelfde grens als de kijklijst, en die grens is nu gedeeld. `PlexCloudHttpClient` heeft geen `baseUrl`, geen `defaultHeaders` en is nooit een `FailoverHttpClient`, en neemt de token als verplichte named parameter per call; `PlexWatchlistClient` en de nieuwe `PlexEpgClient` staan er allebei op, waarbij een client-specifieke extra header (`X-Plex-Provider-Version: 5.1` voor epg) bij de host hoort en niet bij de operatie. Een extra header met de naam van de tokenheader wordt vooraf weggegooid, in elke schrijfwijze, want HTTP behandelt headernamen hoofdletterongevoelig en een Dart-map niet. `LiveTvSupport` splitst: `buildFavoriteChannelSource` blijft serverkennis, de vier opslag-members zitten op `LiveTvFavoritesStore`, en `LiveTvSupport.favorites` geeft de store die de server zélf bezit. Jellyfin geeft daar zichzelf terug, Plex geeft `null`, bewust en niet een stub met mode `none`: Plex-favorieten bestaan wél, ze wonen alleen elders, en een stub zou een storekey en vier bodies moeten verzinnen die nooit aangeroepen mogen worden. De Plex-store komt van `PlexFavoriteChannelsService`, die per profiel hangt en per operatie opnieuw om scoped auth vraagt, weigert bij `isUserScoped == false`, en de store cacht op identiteit zodat sleutelgelijkheid en objectgelijkheid hetzelfde antwoord geven. Een bestaande store muteert nooit zijn eigen identiteit: een nieuwe token voor dezelfde gebruiker gaat door, een andere gebruiker maakt de store ongeldig. De storekey codeert elk onderdeel apart, zoals `WatchlistScopeId.storageKey`. Zonder user-scoped auth is de functie **unavailable en niet broken**: geen store, geen ster, geen schrijfactie, geen foutmelding, en zodra de binding landt komt hij vanzelf terug. Er is geen terugval op de servertoken als een schrijfactie 401 of 403 geeft. En een `sharedFullList`-schrijfactie mag alleen uit wanneer precies dezelfde store-instantie in de huidige favorietengeneratie succesvol is gelezen; dat leesbewijs is een eigen type in plaats van een set naast een teller, zodat de regel niet stil kan verzwakken.
**Consequences:** De keuze voor user-scoped auth is een veilige faalrichting, geen vastgesteld credentialgedrag. Of `favoriteChannels` per account of per Home-gebruiker is, kon niet worden gemeten: het testaccount heeft geen provider met het `livetv`-protocol, dus er bestaat geen geldige `source` en er kon geen onderscheidende regel worden weggeschreven. Het meetscript drukte hier "account/owner-scoped" af, en die afleiding is ongeldig omdat hij twee lege antwoorden met elkaar vergeleek; hij staat als ontkrachte hypothese gemarkeerd in de fixture. Bovendien rust de redenering "een home-user-token is een geldige credential van hetzelfde account" zelf op een aanname: dat `accountId` voor eigenaar en managed gebruiker hetzelfde account aanduidt, en dat de endpoint een managed-user-token accepteert voor account-scoped state. Herverifiëren op een account met een echte tuner, met de meting die het beslist: als gebruiker A een favoriet zetten en als B teruglezen. Tot die tijd geldt de prijs: een Home-gebruiker van wie de binding nog loopt ziet geen favorieten, terwijl de servertoken vandaag wél een antwoord gaf. Verder kan er een 400 zichtbaar worden waar nu niets gebeurde, bijvoorbeeld bij een profiel met een Plex-server van een ander account, en de servertekst wordt daarom letterlijk gelogd. De leescall heeft door het wegvallen van de failover één retry minder. Twee bronscannende tests houden de grens vast: geen plex.tv-host binnen `PlexClient`, en de service kent geen `PlexClient`, `PlexConfig` of `defaultHeaders`. De tokenisolatietest bewijst beide kanten, want alleen "SERVER_SECRET komt nergens voor" zou ook slagen als er per ongeluk helemaal geen token meeging.

## DEC-022: De TestFlight-lane koppelt de build zelf aan het versierecord

**Date:** 2026-08-17
**Status:** accepted
**Context:** Een upload naar TestFlight zet de build niet in de versie die je indient. Dat is een tweede handeling in App Store Connect, en die bleef liggen. Bij de 2.1(a)-hertest van augustus 2026 hingen iOS en tvOS 2.8.0 nog aan build 156, de build die Apple op 6 juli afwees, terwijl build 220 met de inlogfix al sinds 15 augustus `VALID` klaarstond; macOS had helemaal geen build gekoppeld. Een reviewer die opnieuw kijkt, hertest dan precies wat hij al afkeurde, en niets in de lane-output wijst daarop: de upload meldt succes en de build staat gewoon in TestFlight. Dit is de derde keer dat de stap tussen "geüpload" en "indienbaar" stil misgaat, na het versierecord dat op 1.0 bleef staan terwijl de builds op 2.8.0 zaten (macOS en tvOS, zie de troubleshooting-tabel in [TESTFLIGHT.md](TESTFLIGHT.md)) en de ontbrekende export compliance ([DEC-018](#dec-018)).
**Decision:** `ios_beta`, `tvos_beta` en `macos_beta` wachten na de upload op processing en selecteren de build in de bewerkbare versie van hun platform (`wait_for_build` plus `attach_build_to_version` in `fastlane/Fastfile`, via `Spaceship::ConnectAPI` `select_build`). In `beta` wordt dat uitgesteld tot na alle drie de uploads, want anders staat het volgende platform te wachten op Apple's processing van het vorige. Koppelen is bewust niet fataal: mislukt het, dan staat de build gewoon op TestFlight en print de lane het herstelcommando. Een versie die in review of live is, wordt overgeslagen met een melding in plaats van aangeraakt. Voor handwerk en herstel is er `fastlane attach_builds [platform:…] [build:…]`, die zonder build-optie het hoogste TestFlight-nummer van dat platform pakt.
**Consequences:** `beta` duurt langer, want de laatste upload moet nu door processing voordat de lane klaar is; de wachttijd is begrensd op `ASC_ATTACH_TIMEOUT` (default 1800s) en een overschrijding is een waarschuwing, geen fout. De lane heeft daarmee schrijfrechten op het versierecord, dus een verkeerd versienummer in App Store Connect wordt nu zichtbaar als een overgeslagen platform in plaats van als een stille no-op. Wat de lane níet doet is indienen: het versierecord blijft `PREPARE_FOR_SUBMISSION` en de knop blijft handwerk.

## DEC-023: Op mobiel is Mijn Pleya de enige persoonlijke ingang

**Date:** 2026-08-17
**Status:** accepted, scherpt de mobiele bar-samenstelling uit [DEC-020](#dec-020) aan
**Context:** Sinds Mijn Pleya in de bottom bar staat, had een telefoon twee ingangen naar hetzelfde: de avatar rechtsboven in de Home-header (`discover_screen.dart`, `_buildUserMenuAction`) met een menu voor snelwisselen, Profielen, Opties en Uitloggen, én de tab Mijn Pleya. De tab droeg bovendien `Symbols.account_circle_rounded` terwijl er een comment naast stond die beweerde dat het icoon de profielavatar was; die comment was aspiratie, geen code. De header zelf bleek verder minder te bevatten dan hij leek: het twee-personen-icoon is Samen Kijken en het telefoon-icoon is de Companion Remote, dus geen van beide is een accountknop. Uitloggen was 40 regels die tien providers uit de context lezen, een bevestiging tonen en eindigen op `pushAndRemoveUntil` naar `AuthScreen`, en die 40 regels stonden in de state van één scherm.
**Decision:** De accountacties verhuizen op mobiel naar Mijn Pleya en verdwijnen daar uit de header. Wat waar staat wordt bepaald door één predicaat, `showsHeaderAccountMenu(isMobile:)` in `lib/navigation/navigation_tabs.dart`, dat dezelfde `isMobile` krijgt als de gate op `NavigationTabId.myPleya` in `getVisibleTabs`. Twee losse condities die toevallig overeenkomen zouden bij afwijking ofwel een dubbel menu ofwel geen enkele manier om uit te loggen opleveren; nu is dat één beslissing met een test die beide kanten afdekt. Desktop en tvOS houden het menu, want hun sidebar rendert Mijn Pleya bewust nooit (`side_navigation_rail.dart` geeft er `null` voor terug) en `isMobile` is daar false, op tvOS via `PlatformDetector.isTV()` en op macOS via het `TargetPlatform`. Het slot in de bar toont de echte avatar: `MyPleyaTabIcon` watcht zelf `ActiveProfileProvider` zodat een profielwissel één icoon hertekent in plaats van elke destination, valt zonder opgelost profiel terug op de oude glyph, en zet de avatar in `ExcludeSemantics` omdat het label van de destination de tab al aankondigt. De PIN-badge gaat er in de bar af: op 24 logische pixels onder een selectiestip is dat ruis, en het slotje staat nog overal waar je een profiel daadwerkelijk kiest. `AccountUiActions` (`lib/services/account_ui_actions.dart`) bezit voortaan `openProfiles` en `logout`, naar het model van `WatchlistUiActions`, en beide ingangen lopen er doorheen. Het tandwiel uit de profielheader is weg omdat Opties nu een rij in dezelfde lijst is.
**Consequences:** Snelwisselen kost op mobiel een tik meer: het was avatar en dan een profiel, nu is het Mijn Pleya, de identiteit bovenaan en dan een profiel in `ProfileSwitchScreen`. Dat is geaccepteerd omdat dat scherm meer doet dan wisselen (beheren, PIN, verwijderen, Plex-account afmelden, Pleya-profiel toevoegen) en een tweede, dunnere wisselaar een tweede plek zou zijn om de PIN-flow correct te houden. De extractie van uitloggen haalde elf imports uit `discover_screen.dart`, waaronder `auth_screen.dart` en vier registries, dus dat scherm hangt nu merkbaar minder aan de sessiebrede state. Mijn Pleya is `onlineOnly: false`, dus uitloggen blijft offline bereikbaar. Wat niet is opgelost: `MainScreen._openSettings()` pusht op mobiel een nieuwe `SettingsScreen`-route terwijl Mijn Pleya de tab schakelt, twee gedragingen voor dezelfde bestemming op hetzelfde platform. Dat pad hoort nu alleen nog bij de sidebar en is buiten scope gelaten in plaats van meegenomen.

## DEC-024: mobile_scanner 7.4.0, met ring 3 bewust geaccepteerd

**Date:** 2026-08-17
**Status:** accepted
**Context:** De iOS-simulator kon de app niet bouwen op Apple Silicon. `mobile_scanner 5.2.3` trekt GoogleMLKit binnen, en die pods leveren geen arm64-slice voor de simulator; `xcodebuild` meldde daardoor `Unable to find a destination matching the provided destination specifier` voor elk simulatortoestel, met vijf targets in de waarschuwing erboven (GoogleMLKit, MLImage, MLKitBarcodeScanning, MLKitCommon, MLKitVision). Vanaf iOS 18 bestaat er geen x86_64-simulator meer om op terug te vallen. Netto: elke visuele controle van een mobiele wijziging moest naar een fysiek toestel, terwijl juist de mobiele navigatie werd verbouwd ([DEC-023](#dec-023)). De scanner heeft in deze app één call site: `MobileScanner(onDetect:)` in `lib/screens/settings/pleya_share_scan_screen.dart`, dat per gedetecteerde barcode `rawValue` door `PleyaSharePairUri.tryParse` haalt.
**Decision:** Bumpen naar `mobile_scanner 7.4.0`. Die versie heeft de ML Kit-afhankelijkheid op iOS vervangen door Apple's Vision-framework; de podspec sluit alleen nog `i386` uit voor de simulator, dus arm64 bouwt weer. De Dart-API die deze app gebruikt is broncompatibel: `MobileScanner(onDetect:)` en `barcode.rawValue` bestaan onveranderd in 7.x, geverifieerd tegen de actuele documentatie. Het scanscherm is niet aangepast en er komt geen abstractielaag omheen; een bump is geen aanleiding voor een refactor. `scripts/classify_lock_diff.sh` classificeert de wijziging als **ring 3** (`plugin: true`, `nativeDiff: differs`), en die ring wordt hier expliciet geaccepteerd in plaats van weggeredeneerd: de native wijziging *is* de oplossing, niet een neveneffect ervan.
**Consequences:** Het onderscheid dat hier telt: dat de simulator weer bouwt bewijst dat de iOS-build gezond is, en verder niets. Of QR-scannen werkt is daarmee niet aangetoond, want een simulator heeft geen camera en de decoder is precies het onderdeel dat veranderde. Daarom staat er een verplichte smoketest op fysieke hardware in [TESTFLIGHT.md](TESTFLIGHT.md#verplicht-vóór-een-ios-upload-qr-scannen-op-echte-hardware), af te vinken vóór de eerstvolgende iOS-upload: permissie, geldige pair-QR, `rawValue`, onleesbare QR, sluiten en heropenen, en één ronde bij matig licht. Tot die test groen is, is QR-pairing technisch bewezen maar niet release-bewezen. tvOS en macOS vallen buiten de impact: `mobile_scanner` staat alleen in `ios/Podfile.lock`. Bij het opruimen van de oude pods viel nog een tweede ding op dat los van deze bump bestaat: `flutter run` hing op `xattr -r -d com.apple.FinderInfo` over de projectmap zolang `build/` was volgelopen tot 12G, wat als een stille build-hang oogt.
## DEC-025: De wijziging bepaalt het bewijsniveau, niet de naam van de dependency

**Date:** 2026-08-17
**Status:** accepted
**Context:** Op vrijwel elke laag liep er iets achter: 26 directe Dart-pakketten, 58 pakketten die binnen de huidige constraints al konden opschuiven, zes GitHub Actions die één tot drie majors achterliepen, de tvOS-engine, MPVKit en libass. De oorzaak was geen achterstalligheid maar een gat in het proces. Alleen MPVKit had een controle (`scripts/check_mpvkit_update.sh`); elke andere pin werd pas zichtbaar als iemand er toevallig naar keek, en de laatste vijftien commits op `pubspec.yaml` waren buildnummer-bumps. Wat dit project bijzonder maakt is dat een deel van die pins geen bibliotheken zijn maar binaries. MPVKit is een specifieke mpv/ffmpeg-build, de tvOS-engine is een gepatchte Flutter-engine waarvan een swizzle het toetsenbord draagt ([DEC-019](#dec-019)), en libass draagt de ondertitelstyling. Een verkeerde bump daar geeft geen compilefout maar een stille A/V- of invoerregressie die pas in TestFlight opvalt. Per-pakket-beleid verzinnen schaalt niet: hetzelfde pakket kan de ene keer onschuldig zijn en de andere keer niet.
**Decision:** Het bewijsniveau volgt uit de eigenschappen van de wijziging. Ring 1 (gereedschap, GitHub Actions, aantoonbaar pure Dart-updates) vraagt `scripts/ci_checks.sh` groen plus `flutter test`. Ring 2 (constraints binnen dezelfde major, elke wijziging waarbij gegenereerde code verandert, Dart-runtimegedrag zonder platformlaag) vraagt daarbovenop `scripts/codegen.sh` en een debug-build op minimaal één platform. Ring 3 (elke binaire, native of platformwijziging) vraagt daarbovenop gericht runtimebewijs op echte hardware, per component gekozen. De regel die dit draagt: **de wijziging bepaalt de ring, niet de naam of de locatie van de dependency, en een wijziging promoveert altijd naar de hoogste ring waarvan de risico-eigenschappen van toepassing zijn.** Zelfde pakket, drie uitkomsten: een pure Dart-patch is ring 1, dezelfde patch die de output van `build_runner` verandert is ring 2, en een plugin-patch met gewijzigde native implementatie is ring 3. `scripts/classify_lock_diff.sh` leest die eigenschappen af uit een lockfile-diff en draagt per regel zijn eigen `classificationEvidence`; kan hij een bron niet vinden, dan is de uitkomst UNKNOWN, en UNKNOWN promoveert, want niet kunnen aantonen dat iets veilig is telt hier als niet veilig. `scripts/check_updates.sh` zet elke pin in één rapport met vier statussen (CURRENT, BLOCKED, OUTDATED, UNKNOWN), en `--strict-through-ring N` bepaalt welke ringen een run mogen laten falen. Ring 3 is begrensd op hoogstens één onafhankelijke change-set per releasecyclus, niet op één dependency: een technisch gekoppelde set (een Flutter-SDK-bump samen met de bijpassende tvOS-engine) telt als één set, want los van elkaar zijn ze niet te verifiëren. Een kritieke security-update in een native component mag altijd tussendoor, met ring-3-bewijs maar zonder op de volgende cyclus te wachten.
**Consequences:** De eerste ronde bewees meteen dat de classificatie een heuristiek is en de bewijsstap het echte mechanisme. De classifier zette de vijf pakketten van de analyzer-stack én `rate_limiter` op ring 1; de codegen-controle en de testsuite haalden ze er alle zes uit ([DEC-026](#dec-026) voor de eerste, en `rate_limiter` 1.1.0 omdat het de tijd via `package:clock` leest waardoor de zoekdebounce onder de fake clock van `flutter_test` anders vuurt). Wie de classifier vertrouwt zonder de bewijsstap te draaien, krijgt precies de regressies waar dit beleid tegen bestaat. Een tweede prijs is zichtbaarheid: `check_updates.sh` rapporteert nu permanent een aantal openstaande ring-3-posten (MPVKit 1.0.17, engine `+5`, libass 0.18.3), en dat is de bedoeling. Daarom draait de `dependency-health`-workflow op `--strict-through-ring 1` en niet op een kale `--strict`. Bewust nog geen Renovate of Dependabot: eerst één of twee cycli met dit rapport draaien om te zien welke checks betrouwbaar zijn en waar de onderhoudslast echt zit. `.fvmrc` is de enige bron voor de Flutter-versie geworden; `subosito/flutter-action` leest hetzelfde bestand via `flutter-version-file`, dus de tien losse `flutter-version`-regels in `ci.yml` en `build.yml` zijn weg. `pubspec.yaml` kan die rol niet spelen, want `environment.flutter` is hier een range.

## DEC-026: De analyzer-stack blijft achter tot bewezen is dat drift zijn relaties houdt

**Date:** 2026-08-17
**Status:** accepted
**Context:** Tijdens de eerste onderhoudsronde onder [DEC-025](#dec-025) bewoog `analyzer` van 10.0.1 naar 10.2.0, `_fe_analyzer_shared` van 93 naar 96, `analyzer_plugin` van 0.14.1 naar 0.14.4 en `dart_code_linter` van 4.0.2 naar 4.2.0. Alle vier kwamen als ring 1 uit `classify_lock_diff.sh`: geen plugin, geen platformcode, pure Dart. `flutter analyze` gaf geen enkele fout of waarschuwing, en de app compileerde. De codegen-controle liet iets anders zien. `lib/database/app_database.g.dart` werd 298 regels korter, en wat eruit verdween was de hele relatie tussen `connections` en `profile_connections`: de `defaultConstraints` met `REFERENCES connections (id) ON DELETE CASCADE`, de `StreamQueryUpdateRules` met de `WritePropagation` die een verwijderde connection naar `profile_connections` doorzet, en de complete `$$ConnectionsTableReferences`-manager met `profileConnectionsRefs`. `drift_dev` bewoog niet mee; het is de nieuwere analyzer die de annotatie niet meer resolvet en er stil niets van maakt. Dat is de gevaarlijkste vorm van kapot: er verdwijnt niets waar iets anders naar verwijst, dus geen typechecker en geen linter ziet het. Wat overblijft is een database die verweesde `profile_connections`-rijen kan houden en streamqueries die na een verwijdering stale blijven. De bisectie is gemeten, niet afgeleid: de build-stack (`build`, `build_config`, `build_daemon`, `built_value`, `source_gen`, `source_helper`, `vm_service`) liet de gegenereerde output ongemoeid, de analyzer-groep reproduceerde het verlies.
**Decision:** De analyzer-stack blijft op de gelockte versies tot het tegendeel bewezen is, en dat besluit is op drie plekken zichtbaar in plaats van alleen hier. `scripts/check_updates.sh` rapporteert de component `analyzer-stack` als **BLOCKED** met deze reden en niet als OUTDATED, want achterlopen is hier de bedoeling en geen achterstand. Dezelfde pakketten staan in `BLOCKED_PACKAGES`, zodat de ring-1-gate van de `dependency-health`-workflow niet permanent rood staat op een keuze. `test/database/drift_relations_test.dart` controleert de gegenereerde output rechtstreeks op de foreign key, de cascade, de writepropagatie en de reference manager; die test vangt de regressie ongeacht via welke route hij binnenkomt, ook als iemand de pin omzeilt. Dit is **geen permanente pin.** Opnieuw upgraden zodra `drift_dev` expliciet compatibiliteit met die analyzer-lijn ondersteunt, óf zodra een gerichte reproductie aantoont dat foreign keys, cascade-relaties en reference managers intact blijven in `app_database.g.dart`. In beide gevallen is `drift_relations_test.dart` groen op de nieuwe versies de meting die de blokkade opheft.
**Consequences:** `dart_code_linter` blijft op 4.0.2 terwijl 4.2.0 er is; het is een dev-dependency, dus de prijs is gemiste lintregels en niet gemist gedrag. De echte kosten zitten in de koppeling: `analyzer` is een transitieve afhankelijkheid van `build_runner`, `drift_dev` en `dart_code_linter`, dus zolang deze blokkade staat kan de generatorgroep als geheel niet zomaar mee. `check_updates.sh` maakt dat expliciet zichtbaar via de regel `dart-lockfile-gekoppeld`: `drift`, `slang`, `sqlite3`, `sqlparser` en `json_annotation` kunnen binnen hun constraint hoger, maar bewegen niet op eigen kracht: `flutter pub upgrade --dry-run` op die vijf meldt "No dependencies would change". Die set is daarmee ring 2 en geen ring 1. Wat hier niet is gedaan: een `dependency_overrides` op `analyzer`. Dat zou de resolutie voor iedereen vastzetten en ook onschuldige upgrades blokkeren, terwijl de bewijsstap uit DEC-025 plus de gegenereerde-outputtest de regressie al vangen op het moment dat hij ontstaat. Een minimale reproductie naar drift upstream sturen is een losse vervolgstap en blokkeert deze onderhoudsronde niet.

## DEC-027: Een gedokte rail en een schuivende rail vragen een andere hero-onderrand

**Date:** 2026-08-17
**Status:** accepted
**Context:** Op de bibliotheektab liep de samenvatting van de hero over de kop van de eerste posterrij. De onderrand van het tekstblok werd berekend met `TvBrowseRailLayout.firstHubPeekHeight`, de formule van het TV-homescherm. Op dat scherm klopt hij: de rail hangt daar in een `AnimatedSlide` die hem precies op die peek houdt en de rest buiten beeld schuift. De bibliotheektab schuift niets. Daar staat `TvBrowseRail` op `bottom: 0` en meet hij zichzelf op zijn volle `railHeight`, die groter is dan de peek met de focusreserve, de peek van de volgende hub en de onderpadding. Dat verschil is precies de strook waar het rijlabel staat. Doorgerekend op een canvas van 1080 punten met de standaard posterdichtheid: `railHeight` ongeveer 472, `firstHubPeek` ongeveer 411, hero-onderkant op 427, dus bijna 49 punten overlap. De rail tekent daar bovendien een verloop van 0,7 in plaats van een dekkend vlak, dus de twee teksten mengden zichtbaar in plaats van dat de onderste netjes wegviel. Het detailscherm deed het al goed en rekende met `(railHeight - railTopPadding) + gap`, maar die kennis zat in één aanroep en niet in een gedeelde naam.
**Decision:** `TvBrowseRailLayout.heroBottomInsetForDockedRail` staat naast `firstHubPeekHeight`, en beide dartdocs verwijzen naar elkaar met de reden waarom je ze niet mag verwisselen. De naam zegt inset en geen coördinaat, want de waarde hoort in `Positioned.bottom` en nooit in `top`. De bovengrens die een minimale hoogte voor het infoblok reserveerde is vervallen: die kon de onderrand terug de rail in duwen om ruimte voor tekst te maken, wat precies de fout is die hier wordt gerepareerd. Krapte wordt voortaan opgelost door synopsisregels te laten vallen via `TvSpotlightBackground.constrainInfoToAvailableHeight`, een vlag die een scherm expliciet aanzet. Afleiden uit "dit blok heeft geen knoppen" is bewust niet gedaan: dat zou stilzwijgend omslaan zodra de bibliotheekhero er een knop bij krijgt.
**Consequences:** De hero op de bibliotheektab wordt korter dan voorheen, want hij houdt nu de hele rail vrij in plaats van alleen de eerste rij. Op een krap canvas betekent dat minder synopsisregels; op het gemeten tvOS-canvas van 540 punten hoog blijft er één regel over. Dat is geen achteruitgang ten opzichte van de oude situatie, want daar werden drie regels door de `FittedBox` uniform verkleind tot ze over het rijlabel vielen. De `FittedBox` blijft als laatste vangnet staan, zodat overlap structureel onmogelijk is ook als het regelbudget zich vergist. `test/widgets/tv_hero_rail_clearance_test.dart` bewaakt de invariant tegen de echte rail, en één test daarin toont aan dat de peek-formule daadwerkelijk overlap geeft, zodat de assertie aantoonbaar kan falen. Het homescherm en het detailscherm zijn ongemoeid gebleven; wie later een derde scherm met een gedokte rail bouwt, vindt de regel via de helper in plaats van via deze bug.

## DEC-028: De Apple TV-vergroting gaat van 2,00 naar 1,85, en verder verandert er niets

**Date:** 2026-08-17
**Status:** accepted
**Context:** De tvOS-interface voelde opgeblazen, alsof een UI voor een lage resolutie werd uitgerekt. De meting legde uit waarom. `_AppleTvScale` in `lib/main.dart` halveert sinds de eerste import de gerapporteerde logische maat en schaalt de gerenderde uitvoer met factor twee terug omhoog, met een commentaar dat uitlegt dat het oppervlak van tvOS anders even fijn is als dat van een grote telefoon. Het canvas is daardoor 960x540, gemeten met een tijdelijke logregel en onafhankelijk bevestigd op de schermafdruk: de icoonbadge van 36 logische punten meet 138 fysieke pixels, dus dpr 4 op een 4K-toestel. `TvLayoutConstants.scaleForHeight` is `(height / 1080).clamp(0.85, 1.35)`, dus bij 540 komt daar 0,5 uit en tilt de clamp dat naar 0,85. Netto wordt alles 1,7 keer zo groot getekend als het ontwerpdoel. Dat verklaart ook waarom gedeelde chrome zo groot aanvoelt terwijl de fonts dat niet zijn: een settings-rij is 81 punten hoog met een titel van 13 punten, en de hele instellingen-stack heeft geen tv-tak voor maatvoering. Een globale `Transform.scale` zou je normaal afraden, maar dit mechanisme draagt de tv-interface al jaren, hittesten lopen er al doorheen, en de vraag is dus niet of we een schaalhack introduceren maar of de bestaande te agressief staat.
**Decision:** `_AppleTvScale._scale` gaat naar 1,85, waarmee het canvas 1038x584 wordt. Verder verandert er niets in deze ronde. De rijhoogtes, de bibliotheekkop, de railmaten en `FocusTheme.focusScale` halen hun ruimte uit dezelfde marge die deze wijziging al vrijmaakt, dus samen uitgevoerd zou je twee keer verkleinen zonder te weten welke ingreep het effect gaf. De clamp in `scaleForHeight` blijft ook staan: bij 584 punten blijft die actief, dus die factor blijft een constante van 0,85 en geen tweede schaalmechanisme dat meebeweegt. Eerst één dimensie tegelijk.
**Consequences:** De keuze is vergeleken op dezelfde simulator tegen 2,00 en 1,90, op Home, Libraries Aanbevolen en Instellingen. Instellingen toont zes rijen waar er vijf pasten, de posterrij op Libraries krijgt er ongeveer een kaart bij, en op het homescherm valt het bijschrift onder de verder-kijken-poster niet meer tegen de schermrand. Het verschil tussen 1,90 en 1,85 is op rijniveau klein; de stap die telt zit tussen 2,00 en de rest. Wat deze meting niet dekt: het oordeel op kijkafstand, want de simulator staat op een bureau, en de bevestiging dat een echt toestel dezelfde 960x540 rapporteert. Dat laatste volgt uit de code, met dpr 2 op een 1080p-toestel en dpr 4 op een 4K-toestel, maar het is een afleiding en geen meting op hardware. Het risico dat hierbij hoort is dat elke plek die een vaste hoogte tegen een schermfractie afzet nu anders uitvalt: de bibliotheekhero is daar het bekendste voorbeeld van en die is in dezelfde ronde gerepareerd en getest, maar dialogen met een vaste maximumhoogte, sheets en de alpha-sprongbalk met zijn `viewportHeight * 0.25` verdienen aandacht in de deviceronde. Tekstoverloop is het tweede risico: meer logische ruimte betekent smallere tekst in verhouding tot knoppen met een vaste breedte, dus de vertalingen met de langste labels zijn de beste steekproef.

## DEC-029: Een eigen `xattr` op PATH tijdens de release, in plaats van Flutter's recursie over de hele repo

**Date:** 2026-08-18
**Status:** accepted
**Context:** De iOS-lane van de release van 18 augustus stond 63 minuten stil voordat `xcodebuild` ook maar begon. De oorzaak zit in `flutter build ios` zelf. `buildXcodeProject` roept op `packages/flutter_tools/lib/src/ios/mac.dart:199` `removeExtendedAttributes(app.project.parent.directory, ...)` aan, dus met de héle projectroot, en die functie doet per attribuut een volledige recursie: eerst `xattr -r -d com.apple.FinderInfo <root>`, daarna hetzelfde voor `com.apple.provenance`. `--config-only` ontsnapt er niet aan, want die return staat op regel 353, ruim na de aanroep. De repo telt 51090 bestanden, waarvan 28360 in `build/`, 5858 in `website/node_modules` en 1113 in `.git`, en staat op een externe USB-APFS-schijf waar elke `removexattr` een schrijftransactie met USB-latency is. Uit de log van die run: de `FinderInfo`-pass liep van 11:52:16 tot 12:31:47, dus 21 bestanden per seconde, ruim veertig minuten per attribuut. Het proces gebruikte daarbij 0,9 seconde CPU in drie kwartier, dus het wacht op de schijf en niet op rekenkracht. Twee metingen tijdens het onderzoek zetten het werk verder in perspectief: `com.apple.provenance` is kernel-beschermd en laat zich in userspace helemaal niet verwijderen (`xattr -d` geeft 0 en het attribuut blijft staan), en in een steekproef van 200 bestanden in `lib/` droeg geen enkel bestand een van beide attributen. De tweede pass van veertig minuten kan dus per definitie niets uitrichten. Alleen iOS betaalt dit: `tvos_beta` draait geen `flutter build` en `macos_beta` loopt via `build_macos.dart`, dat de functie niet aanroept. Dat het op alle drie de lanes leek te slaan komt doordat `beta` met iOS begint en er altijd op bleef staan.
**Decision:** `scripts/xattr-fast/xattr` komt tijdens een release vooraan in `PATH`. Die onderschept uitsluitend het patroon `-r -d <attr> <map>` en voert het parallel uit met `find -print0` en `xargs -0 -P`; elke andere aanroep gaat via `exec` ongewijzigd naar `/usr/bin/xattr`, inclusief Flutter's eigen `xattr -w com.apple.xcode.CreatedByBuildSystem`. Overgeslagen worden `.git`, `node_modules`, `.dart_tool` en `.fvm`, omdat die nooit in een ondertekende bundel terechtkomen; `build/` juist niet, want dat is bouwuitvoer die er wél in belandt. Het aantal workers staat op twaalf en is instelbaar met `PLEYA_XATTR_JOBS`. `PLEYA_XATTR_FAST=0` schakelt alles uit en geeft het kale gedrag van Flutter terug. Het alternatief van `flutter clean` vooraf, jarenlang de noodgreep, verdwijnt naar een expliciete `--clean`-vlag: dat verkleinde de boom wel, maar kostte een volledige hercompilatie en loste de oorzaak niet op.
**Consequences:** De shim geeft geen blinde `exit 0`. Dat kan ook niet op de exitcode gebaseerd worden: `xattr -d` faalt op elk bestand dat het attribuut niet heeft, en BSD-`xargs` op macOS geeft daarvoor 1 terug waar GNU-`xargs` 123 gebruikt, dus die code betekent hier niets. De beslissing valt op de inhoud van stderr, waar `No such xattr` en `No such file` normaal zijn en al het andere exitcode 2 oplevert. De patronen zijn bewust niet verankerd en lege regels vallen weg, omdat twaalf workers naar dezelfde stderr schrijven en meldingen daardoor gesplitst raken: op 702 meldingen leverde dat twintig losse newlines op. `scripts/xattr-fast/selftest.sh` bewaakt doorgeven, recursief verwijderen over meerdere `xargs`-batches, namen met spaties, quotes en unicode, symlinkgedrag gelijk aan het origineel, het prune-contract in beide richtingen, en dat echte fouten zichtbaar blijven. `scripts/xattr-fast/benchmark.sh` meet het aantal workers, maar meet warm: de bestanden worden vlak voor de meting aangemaakt, en `purge` vereist root, dus het echte knelpunt van koude metadata over USB valt er niet mee na te bootsen. Dat script haalde serieel ruim 3600 bestanden per seconde tegen 21 in productie, dus gebruik het om te zien of meer workers nog iets opleveren en niet om de winst te voorspellen. Een koude A/B op twee vergelijkbare, onaangeroerde repo-bomen ging van 145 naar 507 bestanden per seconde. Het onderhoudsrisico is dat dit een lokale ingreep is rond een keuze van Flutter zelf: verandert het aanroeppatroon bij een SDK-bump, dan valt de shim stil terug op doorgeven en is de traagheid terug zonder dat iemand het merkt. Daarom schrijft de shim bij elke onderschepping naar `PLEYA_XATTR_MARKER` en rapporteert `scripts/testflight_release.sh` dat na afloop, met een waarschuwing als de teller op nul staat. **Controleer na elke Flutter-SDK-upgrade of `mac.dart` nog hetzelfde `xattr -r -d <attr> <map>`-contract gebruikt**, en of de marker na een iOS-build nog twee regels bevat.
## DEC-030: Go is de serverruntime voor Pleya Server

**Date:** 2026-08-18
**Status:** accepted
**Context:** Pleya Server moet een bibliotheek scannen, honderden gelijktijdige range-requests dragen en later ffmpeg-kindprocessen superviseren, op een NAS met vier trage cores. Er draait al Go in dit project: `server/` is de relay achter `ice.pleya.app`. Dart zou het ook kunnen en `share_server/` bewijst dat, maar dan met een tweede runtime die naast de app-toolchain onderhouden moet worden op een platform waar hij verder niets doet.
**Decision:** Go, met de standaardbibliotheek als uitgangspunt voor de HTTP-laag. PS-0 heeft dit al waargemaakt: één statische binary van 10,6 MiB residentgeheugen idle, waar de vergelijkbare Plex-container 1,5 GiB gebruikt. De versie is gepind op 1.26.6 en de runtimebasis op Debian bookworm, zodat de gepinde ffmpeg uit hoofdstuk 22 er later op past.
**Consequences:** Eén taal erbij in de repo, naast Dart en de native platformcode. Geen gedeelde code met `server/` of `share_server/`; die blijven aparte producten met een eigen levensduur. De toolchain draait via `pleya_server/scripts/go-tool.sh` in een container, zodat er geen Go op de ontwikkelmachine hoeft te staan.

## DEC-031: Pleya Share en Pleya Server blijven twee producten met één protocolvocabulaire

**Date:** 2026-08-18
**Status:** accepted
**Context:** `share_server/` deelt een map met een gast en Pleya Server is een mediaserver voor een huishouden. Ze lijken op elkaar in wat ze over de lijn sturen en verschillen fundamenteel in vertrouwensmodel, levensduur en beheer. Er samen één runtime van maken zou het strengste model van beide aan het lichtste opdringen.
**Decision:** Twee runtimes, één specificatie. Het protocol draagt in `GET /pleya/v1/info` een `profile` met de waarden `minimal` en `full`. Pleya Server is `full`. Het overzetten van `share_server` op het `minimal`-profiel is optioneel en geen voorwaarde voor v1.
**Consequences:** Een client die het protocol spreekt kan later beide bedienen zonder tweede implementatie. `share_server` blijft tot dat moment op zijn eigen protocol, inclusief de fout die DEC-034 beschrijft.

## DEC-032: eigen identiteiten, los van locatie en los van externe ids

**Date:** 2026-08-18
**Status:** accepted
**Context:** Plex maakt een dubbele entry wanneer een bestand verhuist, omdat de identiteit aan het pad hangt. Pleya's eigen `share_server` gaat verder: daar *is* het item-id het absolute pad, base64url-gecodeerd (`lib/services/pleya_share/pleya_share_protocol.dart`). Beide vormen koppelen identiteit aan iets dat verandert.
**Decision:** Interne ids zijn UUIDv7. De tijdsprefix maakt ze sorteerbaar op aanmaakmoment, wat de index-locality op grote tabellen beter maakt dan een willekeurige v4, en een UUID is uitdeelbaar zonder rondgang naar de database. Een pad is nooit een identiteit. `ratingKey`, een TMDB-id of welk extern id dan ook wordt nooit primaire sleutel; die leven in `external_ids` als herkenningsmiddel.
**Consequences:** Een verhuisd bestand behoudt zijn item-id, zijn kijkstatus en zijn metadata, omdat alleen de `media_files`-rij verandert. Voor de client zijn ids ondoorzichtige strings waar niets uit afgeleid mag worden; dat staat als eis in het protocol.

## DEC-033: Postgres is de enige verplichte infrastructuurdependency voor v1, inclusief de jobwachtrij

**Date:** 2026-08-18
**Status:** accepted
**Context:** Een scanresultaat en de vervolgjob die eruit voortkomt horen bij elkaar. Staan ze in twee systemen, dan zijn "de scan is klaar" en "de metadata-job staat klaar" twee schrijfacties die kunnen divergeren. Een tweede component op een NAS is bovendien een tweede ding dat kan omvallen en bijgewerkt moet worden.
**Decision:** Catalogus, kijkstatus, metadata-kandidaten en de jobwachtrij staan in dezelfde Postgres. Geen Redis en geen NATS in v1; websocket-fan-out gaat later over `LISTEN/NOTIFY`. PS-0 heeft de keuze waargemaakt op de doelhardware: PostgreSQL 18.6 draait op DSM 7.3.2 met kernel 4.4.302 en cgroups v1, en gebruikt idle 27,3 MiB.
**Consequences:** Eén transactie kan een scanresultaat en zijn vervolgjob atomair wegschrijven. Een pooler in transaction mode mag er niet tussen, want die breekt `LISTEN/NOTIFY`. Welke jobbibliotheek precies wordt bij de start van PS-2 vastgesteld tegen actuele documentatie; River is de kandidaat. Externe transcode-workers in fase 13 mogen een ander schedulingmechanisme krijgen; die keuze staat open.

## DEC-034: het protocol is de grens, dus eigen wire-types

**Date:** 2026-08-18
**Status:** accepted
**Context:** Pleya Share serveert de freezed `MediaItem` letterlijk als JSON op `/library` (`lib/services/pleya_share/pleya_share_protocol.dart:14`, `share_server/lib/src/server.dart:330-336`). Server en client zitten daarmee vast aan hetzelfde Dart-model: een veldwijziging in de app is een protocolwijziging, en de wire-vorm draagt een union-discriminator plus Plex-woorden als `viewOffsetMs` en `viewCount`.
**Decision:** Wire-types en domeintypes zijn twee dingen met een expliciete mapper ertussen. Er gaat nooit een freezed model over de lijn, ook niet als de vorm toevallig lijkt. Veldnamen zijn backend-neutraal en snake_case: `position_ms`, `episode_count`, `watched_episode_count`, `play_count`. Bij dit besluit hoort dat `capabilities` leidend is boven `feature_level`, en dat elke fase alleen het oppervlak specificeert dat hij zelf introduceert.
**Consequences:** Eén mapper extra aan beide kanten, en dat is de prijs. `docs/pleya-protocol/v1/openapi.yaml` is contractueel leidend en 25 fixtures toetsen beide implementaties tegen dezelfde verzameling, zodat geen van beide kanten kan afdrijven zonder dat een test rood wordt. De bestaande fout in Pleya Share blijft staan als backlogitem en wordt niet in deze ronde gerepareerd.

## DEC-035: device-capabilities horen in de client, het afspeelplan op de server

**Date:** 2026-08-18
**Status:** accepted
**Context:** De client stelt vandaag geen enkele device-capability vast. `plex_client.dart:3072-3110` en `jellyfin_client/parts/playback.dart:504-543` sturen allebei een hardgecodeerde constante, identiek op een Apple TV 4K en een oude tablet. Tegelijk is de server de enige die de bestanden en zijn eigen belasting kent.
**Decision:** De client is de bron van scherm, uitgang, decoder en verbinding. De server stelt het plan op. Het plan is een aanvraag met een antwoord en een reden, geen bevel in één richting: een client mag een plan weigeren en om een alternatief vragen, en de server mag een plan intrekken als zijn belasting verandert. De planner filtert op harde beperkingen en scoort daarna op zachte voorkeuren. Een reden is een domeincode met parameters en nooit een vertaalsleutel van de client.
**Consequences:** Fase 5 staat los van Pleya Server en verbetert Plex en Jellyfin ook, wat hem zelfstandig waardevol maakt. Het protocoloppervlak hiervoor wordt in PS-6 vastgelegd en staat bewust niet in v1 feature level 1; PS-4 levert direct play zonder enige capability-payload.

## DEC-036: direct play met HTTP-range is de standaard, remux en transcode zijn uitzonderingen

**Date:** 2026-08-18
**Status:** accepted
**Context:** Verreweg de meeste bestanden in een huishoudelijke bibliotheek zijn afspeelbaar zoals ze zijn. Een architectuur die met transcoding begint bouwt de duurste weg als hoofdweg, op hardware die er het minst geschikt voor is.
**Decision:** `GET /pleya/v1/stream/{version_id}` met volledige range-ondersteuning is het hoofdpad. Geen sessie, geen state, geen opruimwerk. Eén bereik per aanvraag; een aanvraag met meerdere bereiken krijgt het volledige bestand als `200` in plaats van een `416`, want dat is de toegestane terugval en houdt een speler die het toch probeert aan de praat. Remux en transcode krijgen wel een sessie met een levenscyclus en een watchdog. fMP4 en HLS op het transcode-pad, geen DASH.
**Consequences:** PS-4 kan afspelen leveren zonder dat er een transcoder bestaat, en een bestand dat het toestel niet aankan faalt daar zichtbaar met een duidelijke melding. Dat is de bedoeling en geen gat. De `ETag`-belofte die bij range hoort is zwaarder dan hij lijkt en heeft een eigen poort gekregen; zie `docs/pleya-server-gates.md`.

## DEC-037: Pleya Server bouwt geen eigen NAT-traversal en geen relay

**Date:** 2026-08-18
**Status:** accepted
**Context:** Plex lost bereikbaarheid buiten het huis op met UPnP, een eigen certificaatdienst en een relay, en dat is een aanzienlijk deel van zijn complexiteit. Pleya heeft al een werkend patroon voor precies dit probleem: `ice.pleya.app` draait achter een Cloudflare Tunnel zonder één inkomende poort (DEC-014).
**Decision:** De binary bevat geen NAT-traversal, geen relay en geen certificaatuitgifte. Hij werkt correct achter HTTPS en achter een omgekeerde proxy: hij vertrouwt `X-Forwarded-For` en `X-Forwarded-Proto` alleen van geconfigureerde proxy-adressen, bouwt absolute URL's op de externe hostnaam, ondersteunt mounten op een subpad, en levert range-verkeer zonder pre-buffering. Hoe die proxy tot stand komt is een deploymentrecept en staat in de documentatie, niet in de binary.
**Consequences:** PS-0 bindt daarom bewust op `127.0.0.1` van de NAS; openstellen gebeurt in de fase waarin de authenticatiegrens bestaat. Een huishouden achter CGNAT dat geen tunnel kan opzetten valt buiten wat de binary oplost, en dat is een bewuste grens die in de replacement matrix als zodanig staat.

## DEC-038: wat v1 compatibel houdt, per richting en per enum

**Date:** 2026-08-18
**Status:** accepted
**Context:** De vier regels uit hoofdstuk 3 van de protocolspecificatie openden met "een veld toevoegen is toegestaan". Die zin dekt twee gevallen niet. Een veld dat in een antwoord bij komt is onschuldig; een veld dat in een aanvraag verplicht wordt breekt elke bestaande client, en omdat elk verzoekschema `additionalProperties: false` draagt wijst een server een nieuw optioneel aanvraagveld af in plaats van het te negeren. Over enums zei de regel niets, terwijl een extra waarde precies de clients breekt die de gesloten lijst serieus namen en er een keuze zonder restgeval op bouwden.
**Decision:** Hoofdstuk 3 telt zes regels. Toevoegen mag in een antwoord, niet als verplichting in een aanvraag; een nieuw optioneel aanvraagveld gaat er pas in nadat `capabilities` of `feature_level` zegt dat de server het kent. Een nieuwe enum-waarde is alleen toegestaan waar het veld unknown-safe is. Vier velden zijn dat, elk met de vastgelegde terugval dat een client de onbekende waarde overslaat: `auth.methods[]`, `Library.kind`, `Item.kind` en `SubtitleStream.format`. De rest is gesloten, inclusief `profile` en de enums in een aanvraag. `openapi.yaml` draagt de eigenschap per veld als `x-unknown-safe` en `scripts/check_protocol.sh` weigert een enum zonder markering.
**Consequences:** Een nieuw enum-veld kan de keuze niet stilzwijgend erven: het document valideert pas nadat iemand `true` of `false` heeft opgeschreven. De vier unknown-safe velden kosten aan clientkant een restgeval dat er anders niet was, en dat is de prijs voor het later kunnen toevoegen van een bibliotheeksoort, een itemsoort, een ondertitelformaat of een authenticatiemethode zonder v2. Een derde `profile` is een feature level erbij en geen waarde erbij.

## DEC-039: hoe de bootstrap-auth-state bewaard wordt, niet alleen welke

**Date:** 2026-08-18
**Status:** accepted
**Context:** Hoofdstuk 6.5 somde uitputtend op welke persistente auth-state PS-2 mag hebben, en dat sloot de drift naar een `users`- of `sessions`-tabel af. Het zei niets over de vorm waarin die state opgeslagen wordt, terwijl juist dat na PS-2 alleen met een migratie te wijzigen is. Rotatie met hergebruikdetectie is bijvoorbeeld niets waard wanneer het bruikbare refreshtoken zelf in de database staat.
**Decision:** Vier eigenschappen liggen vast in 6.5. De setupcode is kortlevend en eenmalig en staat persistent niet leesbaar opgeslagen. Een refreshtoken is een ondoorzichtig geheim dat de server niet bewaart: in de database staat een identificatie die er niet naar terug te rekenen is, met vervalmoment en ingetrokken-vlag. De Argon2id-parameters van een bestaande hash staan in de hash zelf, dus verifiëren hangt niet van de configuratie af; de configuratie noemt alleen wat er voor een nieuwe hash geldt, en een verhoging leidt bij de eerstvolgende geslaagde login tot herhashen. De ondertekensleutel leeft alleen in de eigen persistente `/data` met restrictieve rechten, niet in Postgres en niet in Git.
**Consequences:** Een databasedump levert geen bruikbaar token en geen bruikbare setupcode op. Geen van de vier voegt een categorie persistente state toe, dus de grens uit 6.5 blijft staan. Hoofdstuk 16.3 van het architectuurdocument is bijgetrokken: dat zei dat de Argon2id-parameters in de configuratie staan, wat klopt voor een nieuwe hash en niet voor het verifiëren van een bestaande.

## DEC-040: grouping key en identiteit zijn twee dingen in het catalogusschema

**Date:** 2026-08-19
**Status:** accepted
**Context:** Hoofdstuk 7.2 van de architectuur waarschuwt dat het door elkaar lopen van detectie en identiteit de bron is van stille datacorruptie, maar het schema moest allebei dragen. Een scanner die een nieuw bestand tegenkomt heeft een sleutel nodig om te bepalen bij welk bestaand item het hoort, en die sleutel kan alleen uit het pad komen. Tegelijk mag een pad nooit een identiteit zijn, want dan verliest een verhuisd bestand zijn kijkstatus.
**Decision:** `media_items` en `media_versions` dragen een kolom `grouping_key`, uniek per (bibliotheek, ouder, soort). Hij doet precies één ding: een **nieuw gevonden** bestand aan een bestaand item hangen. Een bestand dat al bekend is komt er nooit langs, want dat wordt een laag eerder herkend aan zijn inode of aan zijn scan-signature en houdt dan zijn `media_files.id`, en daarmee zijn versie en zijn item. De kolom heet bewust niet `identity_key`. Weergavevelden (titel, sorteertitel, jaar, index) worden bij een treffer wél bijgewerkt: de sleutel is uit de titel afgeleid, dus een titel die wezenlijk verandert levert een andere sleutel op en daarmee een ander item; wat er langskomt zijn hoofdletters en leestekens, en dan wint de nieuwste schrijfwijze. `added_at` blijft staan.
**Consequences:** Een hernoeming behoudt het item-id, ook wanneer de nieuwe naam een andere grouping key zou opleveren, omdat de hernoeming eerder wordt herkend dan de sleutel wordt berekend. Een bestand dat verdwijnt en later onder een andere naam terugkomt krijgt wel een nieuw item, want dan is er geen inode en geen signature meer om aan vast te houden. Dat is de grens van wat PS-2 kan beloven; sterker bewijs is de content fingerprint uit 7.2, en die is nullable en wordt in deze fase niet berekend.

## DEC-041: één bestandstabel voor media, ondertitels en artwork

**Date:** 2026-08-19
**Status:** accepted
**Context:** De testbibliotheek telt 2601 videobestanden, 5578 losse `.srt`-bestanden en 2923 `.jpg`-bestanden. Die sidecars hebben exact dezelfde goedkope verandersdetectie nodig als de media zelf: zonder dat wordt elk ondertitelbestand elke ronde opnieuw gelezen. Het ER-diagram in hoofdstuk 7.1 kent alleen `MEDIA_FILE` als bestand.
**Decision:** `media_files` draagt elk pad dat de scanner volgt, met een kolom `role` die `media`, `subtitle` of `artwork` onderscheidt. Media en ondertitels hangen aan een versie, artwork aan een item. Beide verwijzingen zijn nullable, want een net ontdekt bestand hangt nergens aan en een sidecar waarvan de media nog niet gescand was ook niet; dat is een tussenstand en geen fout. Er komt geen aparte `artwork`-tabel in PS-2: een `artwork_id` op de lijn is de id van zo'n rij. De `artwork`-tabel uit hoofdstuk 17.2 gaat over providerdownloads en afgeleide formaten, en hoort bij PS-7.
**Consequences:** De scannerlus is uniform over elk pad op schijf, en de drie lagen uit 7.3 gelden voor sidecars net zo goed als voor media. `GET /artwork/{id}` levert het origineel; de `width`-parameter wordt gelezen en levert de dichtstbijzijnde beschikbare maat, en zolang er één maat is, is dat die. Schalen en cachen komt in PS-7, samen met de providers die de andere maten aanleveren.

## DEC-042: eigen jobtabel, niet River, en dat beantwoordt de open vraag niet

**Date:** 2026-08-19
**Status:** accepted
**Context:** Hoofdstuk 17.1 legt de eigenschap vast en niet de bibliotheek: duurzame jobs met retries en zichtbaarheid, in dezelfde database, zonder tweede infrastructuurcomponent. River werd als voor de hand liggende kandidaat genoemd, maar de keuze stond expliciet open.
**Decision:** PS-2 krijgt een eigen `jobs`-tabel met `FOR UPDATE SKIP LOCKED`, exponentiële backoff met een dak, en een dedupe key die uniek is zolang een job wacht of loopt. Reden: er is één soort werk (een bibliotheek scannen) in één proces, en dat is ongeveer tweehonderd regels zonder dependency. River brengt zijn eigen migratieframework en schemaversionering mee voor een vraagstuk dat er nog niet is.
**Consequences:** Dit is geen antwoord op de open vraag uit 17.1, en het presenteert zich ook niet zo. Overstappen op River blijft een migratie, en de eigenschappen die 17.1 vastlegt zijn intussen waar. De runner zet bij het opstarten alle jobs die als lopend geregistreerd staan terug in de wachtrij; dat gaat uit van één serverinstantie, wat is wat compose neerzet. Met meerdere instanties hoort daar een lease omheen, en dat is dan de wijziging die die stap vraagt.

## DEC-043: de inodebetrouwbaarheid staat per root in de database, en wordt gemeten en niet aangenomen

**Date:** 2026-08-19
**Status:** accepted
**Context:** PS-0 gaf een openstaande meting door: de bibliotheek staat op deze NAS over twee bestandssystemen, btrfs op `/volume1` en `fuseblk.ntfs` op de USB-schijf, en of de goedkope laag uit hoofdstuk 7.3 daar op stabiele inodes kan bouwen was niet gemeten. Het risico dat de fase zelf benoemt is dat inode-hergebruik die laag misleidt.
**Decision:** `storage_locations` draagt `inode_trusted` en `inode_trust_source` per root. De default volgt uit het bestandssysteemtype met een korte lijst waarvan bekend is dat een inode een bestand blijft aanwijzen (btrfs, ext2/3/4, xfs, zfs, apfs, tmpfs, overlay); alles daarbuiten wordt niet vertrouwd. `PLEYA_SERVER_INODE_TRUST` kan het per root overrulen. Op een root zonder vertrouwde inodes draait laag 2 voor elk bestand, elke ronde, en dient de scan-signature daar tegelijk als terugval voor hernoemdetectie: een nieuw pad met de signature van een verdwenen pad is dezelfde rij, mits precies één verdwenen bestand die signature draagt. De scanner rapporteert per ronde per root hoeveel bestanden een inode droegen, hoeveel daarvan uniek waren, en hoe vaak een bekend pad een andere inode had dan de vorige ronde.
**Consequences:** De meting verandert de instelling niet automatisch. Een root op vertrouwen zetten is een besluit en geen bijproduct van een gunstige ronde, want de kosten van verkeerd vertrouwen zijn een bestand dat stil aan het verkeerde item hangt en de kosten van onterecht wantrouwen zijn een hash per bestand per ronde. Op een niet-vertrouwde root leest elke ronde twee megabyte per bestand; bij elfduizend bestanden is dat ruwweg tweeëntwintig gigabyte, en dat is de prijs die de meting moet rechtvaardigen of wegnemen.

## DEC-044: Debians ffmpeg blijft in de image, en PS-8 is het herzieningsmoment

**Date:** 2026-08-19
**Status:** accepted
**Context:** PS-2 zette ffprobe in de runtime-image en die groeide daarvan van 81 MB naar 543 MB, gemeten met `du -sx /` in de amd64-image, de architectuur van de NAS. Van die groei is 459 MB gedeelde bibliotheken, en 159 MB daarvan is Mesa, LLVM, z3 en de DRI-drivers. Pleya raakt die 159 MB nergens aan. Ze komen mee via een keten die van begin tot eind uit harde `Depends` bestaat, dus `--no-install-recommends` verandert er niets aan: `ffprobe → libavdevice59 → libgl1 → libglx0 → libglx-mesa0 → libgl1-mesa-dri → libLLVM-15 + libz3`. `libavdevice` is de component voor opname- en weergaveapparaten, webcams en schermopname; een mediaserver gebruikt hem niet, ook niet bij het transcoderen in PS-8. Debian linkt hem toch mee in `ffprobe`.
**Decision:** Debians `ffmpeg` blijft, op de exacte versie gepind. Zelf bouwen met `--disable-avdevice` zou ongeveer 380 MB opleveren en is scope-neutraal, want avdevice is geen codec en geen formaat, maar het verlegt de CVE-bewaking van Debian naar ons op een project dat al pins bijhoudt voor MPVKit, de Flutter-SDK, de analyzer-stack en zes Docker-digests. Alleen decoderen zou rond 150 MB uitkomen, en dat is de verkeerde volgorde: welke encoders en welke hardwareversnelling erin horen volgt uit PS-6 en PS-8, en dat nu vastleggen is de extensie vooruit bouwen. Het herzieningsmoment is PS-8, dat de ffmpeg-bouw hoe dan ook aanraakt voor QuickSync op de UHD 600; daar is de encoderset bekend en kost `--disable-avdevice` meenemen bijna niets extra.
**Consequences:** 543 MB is een zichtbare post en geen probleem op een NAS met 2,6 TB vrij. De aptlaag is gecachet, dus een codewijziging bouwt alleen de Go-laag opnieuw; dat duurde bij de tweede uitrol seconden. Wie bij PS-8 aan de ffmpeg-bouw komt hoeft niet opnieuw uit te zoeken waar die 159 MB vandaan komt: de keten staat hierboven. Een statische build van derden meeleveren blijft een aparte afweging met een bronaanbod eraan vast, en die is hiermee niet genomen.

## DEC-045: zoeken levert standaard films, series en afleveringen, geen seizoenen

**Date:** 2026-08-19
**Status:** accepted
**Context:** De bibliotheek op de NAS telt 465 films, 95 series, 397 seizoenen en 6.343 afleveringen. Een seizoen heet `Season 3`, dus zijn titel draagt niets van wat iemand intypt: hij matcht alleen op zoektermen die toevallig in het woord `Season` zitten, en dan komen er 396 tegelijk. Gemeten op de echte data levert `season` 5 bruikbare treffers naast 396 seizoenen, `sea` 24 naast 396, en `on` 1.169 naast 396; `matrix` en `breaking` raken er geen. Met een paginagrootte van 100 zijn dat vier pagina's ruis voordat er iets bruikbaars verschijnt. Hoofdstuk 10 laat dit toe, want het zegt niet welke soorten er zonder `kind` in zitten, en `kind` accepteert één waarde en geen lijst, dus een client kan niet om "alles behalve seizoenen" vragen. De standaard van de server is de enige knop die er is.
**Decision:** Zonder `kind` levert `GET /pleya/v1/search` items van soort `movie`, `show` en `episode`. Afleveringen blijven erin, want een aflevering heeft een echte titel waar iemand op zoekt. Seizoenen komen terug zodra er met `kind=season` om gevraagd wordt, en staan verder in `/items/{id}/children`. Dat is wat Plex en Jellyfin ook doen. De zes compatibiliteitsregels uit hoofdstuk 3 van de specificatie zijn erop toegepast: er komt geen veld bij en er gaat er geen weg, `kind` behoudt zijn betekenis en blijft optioneel, `ItemKind` krijgt geen nieuwe waarde, en er is geen aanvraagbody. Wat er verandert is de standaardverzameling, en die was nergens vastgelegd; de wijziging vult een stilte in de specificatie in plaats van een afspraak te breken.
**Consequences:** Hoofdstuk 10 en de `description` van `/search` in `openapi.yaml` zeggen nu welke soorten de standaard levert, dus de stilte is dicht. Het raakt alleen beschrijvende tekst en geen schema, dus `check_protocol.sh` blijft groen zonder nieuwe fixture. Er is nog geen client die tegen het oude gedrag bouwt, want PS-3 is niet begonnen; later zou dit een gedragswijziging voor bestaande clients zijn geweest. Wil een client alsnog alles inclusief seizoenen in één zoekopdracht, dan is dat een protocolwijziging: `kind` zou een lijst moeten worden, en dat is een aanvraagparameter verruimen en geen nieuw veld. Geverifieerd tegen de draaiende container op de DS920+, geauthenticeerd: `GET /search?q=sea` levert 24 treffers (23 `episode`, 1 `show`) en geen enkel seizoen, `GET /search?q=sea&kind=season` levert de eerste pagina van 100 seizoenen, en dezelfde aanvraag zonder token geeft `401` tegen `200` met token.

## DEC-046: Pleya Web is een protocolclient, en co-distributie geeft geen extra rechten

**Date:** 2026-08-19
**Status:** accepted
**Context:** PS-3W levert een webclient die in dezelfde binary zit als de API: de SvelteKit-bundel gaat via `//go:embed` mee en wordt op `/` geserveerd, naast `/pleya/v1`. Dat maakt twee kortere wegen technisch triviaal die bij de Flutter-client onmogelijk zijn. Een query rechtstreeks op Postgres omdat het beheerendpoint nog niet bestaat kost één import, want het proces heeft de verbinding al. Een `/internal/`-route naast het protocol kost één regel in `routes()`, want de mux is dezelfde. Beide zijn aantrekkelijk juist op het moment dat het protocol een gat heeft, en dat is precies waar G6 en G7 vandaag staan: bibliotheekbeheer, scans, jobs, back-up en restore hebben geen endpoint. De architectuur zegt wel dat het protocol de grens is (DEC-034), maar niet dat samen uitgeleverd worden daar geen uitzondering op maakt.
**Decision:** Pleya Web is een Pleya Protocol-client die toevallig samen met Pleya Server wordt gedistribueerd. Samen uitgeleverd worden geeft geen recht op private API's, databasetoegang of serverinterne contracten. Wat een gebruiker of beheerder in Pleya Web ziet, ziet hij via `/pleya/v1`, en dus kan de Flutter-client het morgen ook. Ontbreekt het endpoint, dan is dat een protocolvraag met een fase eraan vast, geen reden voor een kortere weg. De Roadmap Drift Check van PS-3W toetst hierop.
**Consequences:** Beheer blijft een producteigenschap in plaats van een eigenschap van één client, en dat is de voorwaarde onder besluit 7 van het PS-3W-onderzoek: de capability hoort in `/pleya/v1` en Pleya Web wordt de primaire beheerinterface, niet de plek waar de capability gaat wonen. Het kost snelheid op de korte termijn, want een beheerscherm kan niet vooruit op een endpoint dat er nog niet is, en dat is de bedoeling: zonder deze regel zou PS-3W de beheerendpoints uit G6 en G7 stilzwijgend vooruitbouwen zonder fase. De gate uit hoofdstuk 9 van de replacement matrix blijft hierdoor op productniveau meten en heeft geen categorie per client nodig.

## DEC-047: een mislukte analyse laat de versie los

**Date:** 2026-08-19
**Status:** accepted
**Context:** `RecordProbeFailure` schreef de grootte, mtime, inode en scan-signature van de nieuwe bestandsinhoud weg maar liet `version_id`, `probe_duration_ms` en de rijen in `media_streams` van de vorige inhoud staan. Een bestand dat vervangen wordt door iets dat ffprobe niet aankan houdt daardoor de versie, de duur en de sporen van bytes die er niet meer liggen, en omdat de rij nog `role='media'`, `missing_since IS NULL` en een `version_id` draagt ziet `PruneEmpty` hem als aanwezig: de catalogus serveert die metadata onbeperkt door. `internal/migrate/sql/0002_catalog.sql` legt bij `media_versions` al vast dat een versie pas na een geslaagde ffprobe ontstaat, want `container` en `duration_ms` zijn daar `NOT NULL` met die reden erbij; de faalvariant hield die invariant niet. Het bevroren protocol kent geen veld voor een mislukte analyse: `last_probe_error` staat in geen SELECT en in geen wire-type, dus de fout op de lijn zichtbaar maken zou een protocolwijziging langs de zes compatibiliteitsregels vragen.
**Decision:** Een `media_version` blijft niet verbonden aan bytes waarvan de nieuwe analyse faalt. `RecordProbeFailure` is één transactie die `media_streams` op `file_id` wist en in dezelfde update `version_id = NULL`, `part_index = 0` en `probe_duration_ms = NULL` zet, met `generation + 1` erbij. De `media_files`-rij blijft bestaan inclusief `probe_attempts`, `last_probe_at` en `last_probe_error`, dus het bestand blijft bekend bij de scanner en wordt niet als nieuw ontdekt. De losgelaten versie gaat mee in `touchedVersions`, zodat `RecomputeVersionDuration` een gestapelde versie waarvan één deel wegvalt op de som van de overgebleven delen zet.
**Consequences:** Een film waarvan het bestand stukgaat verdwijnt uit de bibliotheek tot hij weer analyseerbaar is. Dat is zichtbaar gedrag voor de gebruiker, en het alternatief is een titel tonen die niet afspeelt en waarvan de duur en de sporen uit een vorige inhoud komen. Het losgekoppelde bestand blijft bekend en kan in volgende rondes opnieuw geprobed worden: `judge` eist `IsAttached()` voor `actionUnchanged`, dus een losgekoppeld bestand komt elke ronde opnieuw langs ffprobe. Dat is precies het gedrag dat een bestand dat bij de eerste probe al faalde nu ook heeft, dus de twee faalgevallen zijn gelijkgetrokken in plaats van uit elkaar gelopen. **Probe-backoff is geen onderdeel van dit besluit.** `probe_attempts` wordt opgehoogd en nergens gelezen; dat staat als zijbevinding in hoofdstuk 24.3 en vraagt een eigen afweging. Bij een gestapelde versie waarvan deel nul faalt verdwijnen ook de sporen, want alleen deel nul schrijft ze weg en het overgebleven deel wordt die ronde niet opnieuw geanalyseerd om ze te reconstrueren; dat is bewust veiliger dan sporen tonen van bytes die er niet meer zijn. De versie zelf blijft bestaan met de duur van de overgebleven delen. **Er is geen wijziging aan `docs/pleya-protocol/v1/openapi.yaml`**, aan een schema of aan een fixture, dus `check_protocol.sh` blijft groen zonder nieuw materiaal. Geverifieerd met `TestFailedProbeReleasesTheOldVersion` en `TestFailedProbeOnOnePartKeepsTheRest`: zonder de wijziging blijft het item met zijn versie staan, en zonder de opname in `touchedVersions` blijft een gestapelde versie op 5046 ms staan terwijl alleen de drie seconden van cd2 nog speelbaar zijn.

## DEC-048: artwork van een Pleya Server reist met een header, via een register per origin

**Date:** 2026-08-19
**Status:** accepted
**Context:** `GET /pleya/v1/artwork/{id}` is klasse `authenticated` en accepteert een bearer-header. Het streamtoken bestaat juist voor spelers die geen header kunnen zetten en is in het contract beperkt tot `/stream` en `/subtitles`; artwork draagt die securityvariant niet. Plex en Jellyfin lossen dit op door hun token in de URL te zetten (`X-Plex-Token=`, `api_key=`), en `MediaServerClient.thumbnailUrl` geeft dan ook alleen een `String` terug. De app tekent artwork met `CachedNetworkImage`, dat wel een `httpHeaders`-parameter kent maar die nergens in de app krijgt aangereikt. Een token in de querystring zetten zou het contract breken; een header-parameter door elke beeld-aanroep trekken raakt tientallen call sites voor één backend.
**Decision:** De token gaat als header mee, en het aanhechtingspunt is de plek waar elke artwork-download toch al langs komt: `_SharedHttpClient` in `lib/services/image_cache_service.dart`. `ArtworkAuthorizationRegistry` koppelt een origin (`scheme://host:port`) aan een leverancier van headers; `PleyaServerClient` registreert zichzelf bij het opzetten en meldt zich af bij `close()`. De leverancier haalt zijn token door de gewone sessie, dus een rotatie tussen twee posters loopt over hetzelfde single-flight-pad als de rest. Een leverancier die faalt levert geen headers op in plaats van de download te laten falen: een poster die 401 geeft is een ontbrekende poster.
**Consequences:** `thumbnailUrl` blijft een `String` teruggeven en het `MediaServerClient`-oppervlak verandert niet, dus de beeldhelper en de tientallen aanroepen eromheen blijven ongemoeid. Het register is backend-neutraal: het kent origins en headers en niets over Pleya Server, zodat een latere backend met dezelfde eis er geen tweede mechanisme naast hoeft te zetten. De sleutel is de origin en niet de verbinding, en dat is een bekende grens: twee verbindingen naar dezelfde server delen één ingang, en de eerste die sluit haalt hem weg. Dat is één server met meerdere identiteiten, wat PS-9 is, en tot dan bestaat het geval niet. **Er verandert niets aan `docs/pleya-protocol/v1/openapi.yaml`.** Dit is een clientarchitectuurbesluit dat het contract juist intact laat; de alternatieven waren allebei een contractwijziging of een refactor met een grote straal. Geverifieerd in `test/pleya_server/pleya_server_search_artwork_test.dart`: de URL draagt geen token en geen `api_key`, het register levert een `Bearer`-header voor die origin, een gesloten client levert niets meer, en een onbekende origin krijgt niets.

## DEC-049: kijkstatus heeft een eigenaar met een lease, en causaliteit loopt via `base_revision`

**Date:** 2026-08-21
**Status:** accepted
**Context:** Poort 3 stond open sinds 18 augustus 2026 omdat de drie voor de hand liggende conflictregels elk falen op een scenario dat gewoon voorkomt: hoogste positie faalt bij een bewuste herstart, laatste update faalt bij een scheve klok of een late offline-synchronisatie, en per sessie bijhouden vraagt een sessiebegrip in de UI dat er niet is. Een vierde model, ordenen op het moment dat de server een sessie voor het eerst zag, sneuvelt op het tv/telefoon-geval: de tv kijkt van 20:00 tot 21:30, de telefoon van 20:15 tot 20:20, en anderhalf uur voortgang zou ondergeschikt blijven aan een sessie die om 20:20 al gestopt was. Alle vier ordenen op de verkeerde as. Positie is geen tijdsas, clienttijd is niet betrouwbaar, en het sessiebegrip zit wél in de data (`session_id` staat in elk event) maar niet in de UI.
**Decision:** De server is eigenaar van de kijkstatus en wijst het schrijfrecht expliciet toe. Per `(subject, item)` draagt de canonieke toestand een monotone, uitsluitend serverzijdig toegekende `revision`, een `owner_session_id`, een `owner_lease_until` op de serverklok, en het laatste expliciete moment plus soort. Zes regels beslissen. (1) Eigendom wordt alleen verworven met `playback_started`; bij `cause: user_started` neemt die sessie over ongeacht de lease van een ander, bij `cause: reclaim` alleen wanneer de lease van de huidige eigenaar verlopen is. (2) Een passief voortgangsevent verwerft nooit eigendom, ook niet bij een verlopen lease en ook niet wanneer er helemaal geen eigenaar is; een verlopen lease maakt het item beschikbaar voor de volgende `playback_started` en meer niet. (3) Elke schrijving draagt `base_revision`, en de server accepteert hem alleen bij gelijkheid met de actuele `revision`; wijkt hij af, dan antwoordt de server met de actuele toestand en verandert er niets. Ontbreekt `base_revision`, dan doet het event geen causale claim en wordt het alleen van de huidige eigenaar met een geldige lease geaccepteerd. (4) De lease is een schrijfrecht met een houdbaarheidsdatum: tweemaal het rapportage-interval met een ondergrens van 90 seconden, gemeten op de serverklok, en elk geaccepteerd event verzet hem. (5) `mark_watched`, `mark_unwatched` en `restart` negeren de lease, nemen het eigendom over en verhogen `revision`; ze ordenen op serverontvangst en niet op `occurred_at`, en een expliciete handeling met een verouderde `base_revision` wordt wél toegepast zolang hij live binnenkomt. (6) Een offline backlog komt als gemarkeerde batch binnen, verwerft nooit eigendom, en verplaatst de canonieke toestand niet zolang `revision > 0`; bij `revision = 0` is er niets te beschermen en vestigt het laatste event uit de batch de toestand alsnog.
**Consequences:** Het contract verandert op drie plekken, en alle drie zijn getoetst tegen de zes regels van hoofdstuk 3 van de specificatie. `revision` in `UserState` is additief en toegestaan. `base_revision`, `cause` en `backlog` in `WatchStateEvent` zijn brekend, want dat schema draagt `additionalProperties: false` en een server die de velden niet kent wijst het verzoek af in plaats van het te negeren. `playback_started` als waarde van `ExplicitAction` is brekend, want dat veld staat op `x-unknown-safe: false`. De aanvraagkant gaat daarom achter de capability `watch_state_ownership`, en een client stuurt de nieuwe velden pas wanneer die waar is. Omdat het een aanvraagschema raakt hoort de wijziging in het venster dat bij het sluiten van PS-3 openging, en niet in een latere ronde; op papier brekend, in het veld leeg, want de enige twee clients zijn leesalleen. **Een niet-canoniek event wordt in PS-4 niet bewaard.** Het masterplan schreef zulke events naar `play_history`, en die tabel hoort bij PS-9P; PS-4 correct laten zijn ten koste van een tabel uit een latere fase is precies de drift die hoofdstuk 23.1 verbiedt. In PS-4 antwoordt de server op een geweigerd event met de actuele toestand en logt hij de weigering met reden, zodat de client bijtrekt. Duurzame, gebruikerszichtbare geschiedenis is en blijft PS-9P, en die fase erft het geweigerde event dus niet uit PS-4. De kosten aan de datakant zijn vijf kolommen op `watch_states` en één beslissing per event op een index die de server toch al raakt.

## DEC-050: de `ETag` op `/stream` is een zwakke validator, en Pleya belooft geen byte-identiteit

**Date:** 2026-08-21
**Status:** accepted
**Context:** Specificatie 13.2 beloofde dat de `ETag` verandert zodra de bytes van de versie veranderen, en de header heette in het contract letterlijk "sterke validator". RFC 9110 §8.8.1 eist van een strong validator twee dingen tegelijk: hij wijzigt bij elke wijziging van de representatie, en hij blijft uniek over alle versies ervan; als onderbouwing noemt de RFC strict revision control of een collision-resistant hash over de bytes. Pleya beheert de bestanden niet. Ze staan op mounts die buiten Pleya om vervangen worden, en de scanner ziet zo'n vervanging pas in de volgende ronde. Het voorgestelde mechanisme eronder, `(MediaFile.id, generation)`, loopt alleen op wanneer de drielagige verandersdetectie iets aanmerkt, en laag 2 is een steekproef die hoofdstuk 7.2 zelf al diskwalificeert als bewijs van gelijkheid: een remux of een gerepareerde container verandert het midden terwijl kop en staart intact blijven. Een validator die aantoonbaar iets mist en tegelijk "sterk" heet is geen strategie die de belofte waarmaakt.
**Decision:** De belofte gaat uit het contract. `GET /stream/{version_id}` levert een zwakke validator in de vorm `W/"..."`, afgeleid uit `(dev, ino, size, mtime_ns, ctime_ns)` van het bestand plus de `generation` van de versie. Gewone `Range` verandert niet: één bereik levert `206`, meerdere bereiken leveren het volledige bestand als `200`, en dat pad hangt van geen enkele validator af. `If-Range` levert nooit meer een `206`: zonder strong validator negeert de server de `Range`-header en antwoordt hij `200` met de volledige representatie, de terugval die RFC 9110 §13.1.5 voorschrijft. Een **verschillende** validator betekent: er is iets veranderd, gooi de buffer weg. Een **gelijke** validator geeft geen informatie over de bytes, want de tupel kan gelijk blijven terwijl de inhoud veranderde: een schrijver die de mtime terugzet, een in-place overschrijving van gelijke lengte, of een bestandssysteem met grovere tijdstempelresolutie dan de vergelijking aanneemt. Gelijkheid mag daarom nergens in Pleya dienen als grond om ontvangen bytes aan later ontvangen bytes te plakken. De steekproef in de scanner blijft bestaan, uitsluitend voor changedetectie en voor de content fingerprint, en er komt geen full-file hashing die alleen HTTP bedient.
**Consequences:** Dit is een brekende protocolwijziging langs regel 3 van hoofdstuk 3: de betekenis van de `ETag`-header verandert, en het antwoordgedrag op `If-Range` verandert mee. Ze hoort daarom in het venster dat bij het sluiten van PS-3 openging. Er is vandaag geen consument die op de sterke semantiek leunt: `pleya_web` heeft geen `<video>` en de Flutter-client is leesalleen. Een speler die na een onderbreking verder wil vraagt een gewoon nieuw bereik en speelt daar verder, zonder ooit te beweren dat twee stukken uit hetzelfde bestand komen; dat is wat elke speler in de praktijk al doet. Het enige pad waar byte-identiteit echt telt is een onderbroken download, en dat is PS-10: die fase krijgt als criterium dat hervatten alleen mag onder een digest over het samengestelde bestand, en niet onder een gelijke `ETag`. Dat criterium staat hier zodat PS-10 het niet opnieuw hoeft te ontdekken. Wat dit besluit **niet** doet is de drempel voor de content fingerprint vastleggen. Die deelt het mechanisme maar niet de faalkost: een gemiste wijziging in de `ETag` kost een verouderde cache-entry, een verkeerde fingerprint-match hangt kijkstatus aan het verkeerde item. Die vraag hoort bij de scannerlogica die relocatie gebruikt en krijgt daar zijn eigen besluit.

## DEC-051: de browser krijgt een streamsessie met een cookie per sessie, en het geheim komt nooit in een URL

**Date:** 2026-08-21
**Status:** accepted
**Context:** Specificatie 6.4 geeft het streamtoken twee tot vijf minuten, en dat is opzet: het reist in een querystring en staat dus in browsergeschiedenis, logs en referrers. Een `<video>`-element stuurt bij elke seek een nieuwe range-aanvraag met de URL uit `src`, dus een film van twee uur in de browser breekt op de eerste seek na vijf minuten. Vier uitwegen vielen af. Een langer token voor browsers verzwakt precies de eigenschap die 6.4 vastlegt en vertakt bovendien op clienttype. Een service worker die de header injecteert vraagt een secure context, en `http://nas:8832` is dat niet. `src` vervangen vlak vóór expiratie geeft een zichtbare hapering en faalt alsnog bij een seek op dat moment. Eén kortlevende cookie op `Path=/pleya/v1/stream/` breekt bij twee gelijktijdige streams: een cookie wordt geïdentificeerd door naam, domein en pad, dus een tweede `Set-Cookie` met dezelfde drie waarden vervangt de eerste, en `Path` is geen securitygrens maar alleen een filter op welke aanvragen de cookie meesturen. Twee tabbladen, picture-in-picture of het voorladen van de volgende aflevering laten stream B het credential van stream A overschrijven.
**Decision:** Een browserstreamsessie is een eigen, kortlevend object. `POST /auth/stream-session` antwoordt met een niet-geheime `stream_session_id` en een `expires_at`, en zet `Set-Cookie: pleya_ss_<stream_session_id>=<geheim>; HttpOnly; SameSite=Strict; Path=/pleya/v1/stream/`, met `Secure` waar de context dat toelaat. De sessie zit in de cookienaam, dus twee gelijktijdige sessies overschrijven elkaar niet. De media-URL draagt alleen de niet-geheime helft: `GET /stream/{version_id}?ss=<stream_session_id>`. De server valideert op elke aanvraag vijf dingen: er is een cookie met die naam, het geheim klopt in een constant-time vergelijking, het geauthenticeerde subject klopt, de binding aan de `version_id` klopt, en de sessie is niet verlopen of ingetrokken. Verlengen zet uitsluitend die ene cookie opnieuw, dus elke stream roteert onafhankelijk. Er geldt een bovengrens van acht **actieve** sessies per subject: de server ruimt eerst verlopen en ingetrokken sessies op, en weigert daarna de negende met een stabiele protocolfout in plaats van de oudste nog levende stream stil te beëindigen.
**Consequences:** Dit is een additieve protocolwijziging: één nieuw endpoint, één nieuwe optionele queryparameter, en een capability `stream_sessions` die zegt of de server het kent. Regel 5 van hoofdstuk 3 is toegepast, dus een client vraagt pas een streamsessie aan wanneer de capability waar is. Het streamtoken in de querystring blijft bestaan en verdwijnt niet: externe spelers delen geen cookiejar met de browser, en de twee mechanismen bedienen twee verschillende clients naast elkaar. De queryparameter zit op `GET /stream/{version_id}`, en dat endpoint is PS-4; het validatiepad hoort daarom in PS-4 en niet pas in PS-4W, want een tweede autorisatievorm er later bovenop zetten is duurder dan hem meteen goed hebben. **Wat dit op een LAN kost, hardop:** op `http://nas:8832` is er geen secure context, dus `Secure` is niet te zetten en het geheim reist in klare tekst over het lokale netwerk. Dat is niet slechter dan het streamtoken in de querystring dat vandaag hetzelfde doet, en het is beter op één punt: JavaScript op de pagina kan er niet bij, en het staat niet in browsergeschiedenis, logs of referrers. `HttpOnly` is geen versleuteling en wordt hier ook niet als zodanig opgeschreven; transportvertrouwelijkheid op het LAN hoort bij de fase die de server buiten het LAN bereikbaar maakt. De bovengrens van acht bestaat omdat browsers het aantal cookies per domein begrenzen en een lek van sessies die grens zou opsouperen; hem afdwingen door de oudste te evicten zou een kijkende gebruiker midden in een film breken, en dat is erger dan een geweigerde negende stream.
## DEC-052: Bij een film verschijnt de skip-intro-knop niet meer

**Date:** 2026-08-19
**Status:** accepted
**Context:** Gemeld: bij films blijft de skip-intro-knop staan tot je hem aantikt. Dat volgt uit een oudere keuze die bewust was gemaakt. `shouldAutoSkipMarker` geeft voor een intro-marker alleen waar terug bij een aflevering, omdat een film zelden een echte Plex-intromarker heeft: die komt dan uit de hoofdstuktitel-fallback, waar het einde op de start van het volgende hoofdstuk ligt (`media_source_info.dart:300-318`). Een openingshoofdstuk duurt minuten tegen zo'n anderhalve minuut voor een afleveringsmarker, dus automatisch springen zou echte film overslaan. Gevolg voor de gebruiker: bij een aflevering springt de speler zelf en is de knop weg, bij een film gebeurt dat nooit. De knop verdween daar alleen via de dismiss-timer van zeven seconden, en `shouldShowSkipMarkerButton` haalt hem terug zodra de bediening in beeld komt (`(!skipButtonDismissed || controlsVisible)`). Op een telefoon is dat bij elke aanraking. De timer werd bovendien maar één keer per marker gezet en nooit opnieuw, dus na de eerste ronde hing de knop volledig aan de bediening.
**Decision:** Een intro-marker geldt bij een film niet meer als actieve marker, dus de knop verschijnt er niet. Vastgelegd in `markerCanOfferSkip` naast de bestaande predicaten in `video_controls.dart`. Het filter zit op de plek waar de actieve marker wordt gekozen en niet bij het inladen van de markers, want dezelfde lijst voedt ook de hoofdstukmarkeringen op de tijdbalk. Aftitelingsmarkers blijven overslaanbaar, ook bij films: daar ging de melding niet over en die knop doet wat je verwacht. De overwogen alternatieven vielen af: automatisch springen ook bij films aanzetten brengt precies het risico terug waarvoor de uitzondering ooit is geschreven, en alleen het wegdrukken onthouden laat de knop nog steeds elke keer verschijnen.
**Consequences:** De episode-clausule in `shouldAutoSkipMarker` is hierdoor dubbelop, maar blijft staan als tweede slot. Meegenomen: staat auto-skip aan met een vertraging van nul, dan armeert `_startAutoSkipTimer` niets terwijl de dismiss-timer alleen bij auto-skip-uit werd gestart, waardoor geen van beide liep en de knop onbeperkt bleef staan. Dat raakte afleveringen met aftiteling en is nu dicht. Wie bij een film wél handmatig over een intro wil springen, gebruikt de tijdbalk; de hoofdstukmarkeringen staan er nog.

## DEC-053: Een kaal Material-widget met een selectiestaat werkt niet vanzelf in dit thema

**Date:** 2026-08-19
**Status:** accepted
**Context:** Gemeld als "de audio-prioriteit is niet te selecteren". De instelling schakelde en bewaarde correct; er was alleen niets aan te zien, en dat is niet te onderscheiden van een kapotte knop. Material vult het gekozen segment van een `SegmentedButton` met `secondaryContainer`, en `mono_theme.dart` zet die op `c.surface`, exact de kleur van de kaart waarop de instellingenrij ligt. `showSelectedIcon: false` haalde het vinkje weg en het thema zet `NoSplash` met een doorzichtige highlight, dus ook geen druk-feedback. Drie signalen, alle drie weg. Hetzelfde geldt voor `primaryContainer`, `surfaceContainerHighest` en `surfaceBright`, die eveneens op `c.surface` uitkomen.
**Decision:** Een `segmentedButtonTheme` geeft de selectie een eigen vlak via `surfaceElevated`, dezelfde stap omhoog die `FocusableTabChip` voor zijn segmented stijl gebruikt. `secondaryContainer` zelf blijft ongemoeid: die aanpassen zou door de hele app doorwerken op plekken die er nu bewust op rekenen.
**Consequences:** Dit repareert elke `SegmentedSetting` in de app tegelijk, niet alleen de audio-prioriteit; daar viel het alleen op. `test/theme/segmented_selection_test.dart` legt vast dat het gekozen segment een andere achtergrond heeft dan het niet-gekozen én dan het oppervlak erachter; die laatste controle is de enige die de fout ook echt vangt. Blijvend aandachtspunt: een kaal Material-widget met een selectie- of actiefstaat werkt in dit palet niet vanzelf. Controleer bij nieuw werk of de staat zichtbaar is, of gebruik de eigen widgets (`FocusableFilterChip`, `FocusableTabChip`, `SegmentedTabGroup`). Nog niet nagelopen zijn de losse `SegmentedButton`-plekken die het vinkje ook uitzetten: `mobile_remote_screen.dart:197` en `sort_bottom_sheet.dart:160`.

## DEC-054: Een overlay-sheet krijgt een presentatiestand in plaats van een tweede modal-systeem

**Date:** 2026-08-19
**Status:** accepted
**Context:** Filters, Sorteren en Groepering openden op een desktopvenster rechtsonder, losgekoppeld van zowel de knop als het venster. Twee oorzaken in de gedeelde component. `_resolveSheetHorizontalAnchor` geeft op een desktop-OS met muisinvoer de laatste muis-x terug en `_OverlaySheetLayoutDelegate` centreert het paneel daarop; die knoppen staan rechtsboven, dus een paneel van 700 breed werd tegen de rechterrand geklemd. En desktop kreeg een vaste `maxHeight` van 400, ongeacht de vensterhoogte. Dat muisanker is bewust gebouwd, voor contextmenu's bij de cursor, maar gold voor élke sheet.
**Decision:** `OverlaySheetHost` krijgt een presentatiestand (`sheet` of `panel`) en de plaatsingsrekenkunde verhuist naar `resolveOverlaySheetGeometry`, een pure functie van presentatie, viewport en `isTV`. Geen tweede presentatiecomponent ernaast: die host draagt de complete focus-, back- en TV-afhandeling, en dat dupliceren kost meer dan het oplevert. `sheet` blijft per pixel wat het was; `panel` centreert boven `ScreenBreakpoints.mobile`, kapt op `min(h-96, 0,8h)`, zet het muisanker uit en klemt ook door de aanroeper meegegeven constraints binnen de viewport.
**Consequences:** Alleen de vier panelen achter een header-actie schakelen om, de twintig andere aanroepen blijven op `sheet`. Telefoons houden de bottom sheet en TV houdt het bestaande focus-pad, want beide takken komen op dezelfde geometrie uit als voorheen. Omdat de functie puur is, ligt het responsive gedrag vast in negentien tests zonder widget te pompen; een widgettest bewaakt daarnaast dat een contextmenu nog steeds de muis volgt. De interne scroll van een lang paneel is alleen door de widgettest gedekt: synthetische scroll-events bereiken deze app niet.

## DEC-055: De zijbalk bezit zijn band via de getekende breedte, niet via `isCollapsed`

**Date:** 2026-08-19
**Status:** accepted
**Context:** Een klik die op een menu-item mikte kon op het billboard eronder landen en meteen een film starten (log `y69x7`). De balk tekent niet buiten zijn hitbox, `Clip.hardEdge` knipt ook het hit-testen weg, dus het verschil zit in de tijd: `isCollapsed` klapt synchroon om en de breedte animeert er 200 ms achteraan. Bij uitklappen was de hover-zone een proxy over die animerende container en dus nooit breder dan de balk op dat moment, waardoor een cursor die naar een label toe beweegt de easeOutCubic inhaalt, de zone verlaat en de collapse-timer start. Bij inklappen legde `IgnorePointer(ignoring: isCollapsed)` alle rijen dood terwijl de balk nog op volle breedte stond te tekenen.
**Decision:** De balk krijgt drie lagen binnen een band ter breedte van de uitgeklapte stand, alle gevoed door één mirror-tween die de breedte-animatie spiegelt. Onderop een `AbsorbPointer` over `max(getekend, doel)`, daarboven de balk zelf, bovenop een translucent `MouseRegion` die de hele band ziet en niets pakt. Alles wat met interactiviteit te maken heeft leest de getekende breedte. De fix hoort in de balk en niet in `main_screen`, want die hoort de toestand pas een frame later via een post-frame notificatie en zou dus per definitie achterlopen. Op TV is de band exact de balk, zodat er niets over de spotlight hangt.
**Consequences:** De regel in één zin: de balk claimt de pointer nooit smaller dan hij tekent, en zodra hij besluit open te gaan claimt hij de hele band meteen. Een klik in de band tijdens de 200 ms uitklap wordt daardoor ingeslikt in plaats van doorgegeven; dat is de bewuste ruil, want het label is daar nog niet zichtbaar. Stil ingeklapt claimt de balk niets voorbij zijn eigen 80px, dus er ontstaat geen dode zone over de content, en een test bewaakt precies dat. **Repareer dit nooit met een debounce of een `AppLifecycleState`-venster**: het is layout en hit-test-eigendom. Bewust niet meegenomen is de tvOS-variant: `NavigationRailItem` is de enige plek die op Select activeert, focus verplaatst en de select-key-up-suppressor niet wapent, maar beide ontvangers in de content weigeren een losse key-up al en in de simulator was het niet te reproduceren.

## DEC-056: Het correlatie-id van een Select reist als parameter, niet als opzoekbare toestand

**Date:** 2026-08-19
**Status:** accepted
**Context:** Log `yto0s` laat zien dat Select op *Joey* het detailscherm van *Avatar* opende, maar niet waar de verwisseling ontstaat. Een log van 337 KB kan die klasse melding niet beantwoorden, want geen enkele regel legt vast welke kaart een activering oploste naar welk item en wat daarna door navigatie, route en detailscherm ging. Bij het uitzoeken bleek bovendien dat `22b4249` de verkeerde widget hardde: op TV bouwt `discover_screen.dart` via `_buildTvContent()` een `TvBrowseRail`, en `HubSection` is het telefoon-, tablet- en desktoppad. `TvBrowseRail._activateCurrentItem()` leest nog `hub.items[_itemIndex]` en `didUpdateWidget` klemt de index alleen, dus de bewezen fout leeft daar door.
**Decision:** Eén trace per Select-druk, geopend door `AppleTvRemoteTouchService` op de key-down en op de key-up gelatcht in `SelectTraceRecorder`. De rij consumeert dat id synchroon in `_activateCurrentItem()` en geeft het vanaf daar mee als parameter aan `navigateToMediaItem`, `navigateToMediaItemDetails`, `mediaDetailRoute` en `MediaDetailScreen`, precies zoals `heroTag` dat al doet. De keten heeft zes schakels: selected, activated, expected, actual, detail, metadata. `expected` komt uit `mediaDetailNavigationTargetFor()` en wordt op de activeringsplek berekend, `actual` bij de routegrens, zodat een aflevering die zijn serie opent correct gedrag blijft en alleen een wissel dáártussen opvalt. Uitdrukkelijk niet gekozen: een Zone, een app-brede focusregistratie, en betekenis ophangen aan `FocusNode`-identiteiten. Het id staat in een eigen veld naast `_nativeSelectPressed`; die vlag is duplicaatonderdrukking en wordt gewist op paden die niets met een druk te maken hebben.
**Consequences:** Na de dispatch mag niemand meer opzoeken welke druk open staat. `consumeActiveSelectTrace()` geeft het id één keer terug en wist de latch, want tijdens een routeovergang kan de volgende druk al lopen. Normaal gedrag levert één `appLogger.i`-regel op, afwijkend gedrag één `appLogger.w` met een begrensde tijdlijn; info is het laagste niveau dat op tvOS overleeft. Vervanging en verwijdering onder de cursor zijn samengevoegd tot één anomalie `focused_target_changed` met drie disposities, omdat een log dat alleen "het item is weg" zegt niet kan tonen dat een refresh een andere kaart onder dezelfde index legde, en dat is juist de oorspronkelijke fout. Een reorder die de rij zelf opvangt telt als `moved` en zwijgt, anders zou Verder kijken bij elke afgekeken aflevering waarschuwen. `TvBrowseRail` rapporteert wel maar corrigeert niet: de identity-fix daar is bewust een aparte commit, want tegelijk repareren wist het bewijs dat deze trace moet opleveren.

## DEC-057: De hero-artworklaag koppelt zijn hoogte los van de hero zelf, in plaats van de container-ratio bij de server aan te vragen

**Date:** 2026-08-20
**Status:** accepted
**Context:** Op een moderne iPhone is de home-hero ongeveer 402×572 punten (verhouding ~0,70). `MediaItem.billboardArt()` kiest daar terecht `backgroundSquarePath` in plaats van een 16:9-backdrop, maar `discover_screen.dart` rendert die vierkante bron vervolgens met `BoxFit.cover` in de volledige hero-box. Een vierkante bron in een 0,70-box verliest zo'n 30% van zijn breedte aan een centrale crop, en `Alignment.topCenter` verhelpt dat niet want de crop is horizontaal. Erger: de aanvraag zelf bakte die crop al in. `discover_screen.dart` vroeg altijd `maxHeight = max(screenWidth*9/16, heroHeight)` op, en Plex' `thumbnailUrl` zet daar `minSize=1&upscale=1` op, wat de gevraagde (portret) box vult door van het midden te croppen vóórdat Flutter ook maar een pixel tekent. `heroLogoWidth`/`heroLogoHeight` waren daarnaast vaste 400×120, die op een 353pt-scherm door de padding werden dichtgeknepen: de logo-URL vroeg 400px breed aan terwijl er 305px getekend werd.
**Decision:** `BillboardArt` krijgt een `BillboardArtKind` (`widescreen`/`square`/`fallback`) in plaats van de bool `isBackdrop`, met `canRenderSharp`/`shouldBlur` als afgeleide gedragsvlaggen. `homeHeroArtGeometry()` (`lib/utils/home_hero_layout.dart`) is een tweede pure functie naast `homeHeroHeight()`: op een brede box of bij `fallback` blijft het gedrag exact zoals het was (`coversHero: true`, aanvraag `max(screenWidth*9/16, heroHeight)`). Op een smalle box koppelt hij de framehoogte los van `heroHeight` en laat hij de aanvraag altijd de ratio van de gekozen bron volgen: `min(screenWidth, heroHeight)` met een vierkante aanvraag voor `square`, `min(screenWidth*9/16, heroHeight)` met een 16:9-aanvraag voor `widescreen`. Zo wordt de server-side crop een no-op, want de gevraagde box heeft altijd dezelfde verhouding als de bron zelf. De artworklaag verhuisde naar een eigen widget, `HomeHeroArtwork` (`lib/widgets/home_hero_artwork.dart`), zodat de geometrie met widgettests op echte frame-rects te toetsen is zonder het hele scherm te pompen. `homeHeroLogoConstraints()` schaalt de logobox op telefoon mee met de schermbreedte (`min(400, screenWidth*0.78, screenWidth-48)`) in plaats van een vaste 400×120 te forceren.
**Consequences:** Een kortere framehoogte op een smalle box laat ruimte over tussen het frame en de rest van de hero; die ruimte blijft onbeschilderd (toont de scaffold-achtergrond) op een band van maximaal 180px na een `fadeHeight`-gradient die het frame naar die achtergrond blendt. Een onafhankelijke codereview (`/code-review`) ving hier een echte bug: die fade-`Positioned` stond op `bottom: 0` van de *hele* hero-Stack (die via `StackFit.expand` van bovenaf de volle `heroHeight` krijgt), niet van het kortere frame, dus de gradient rendersde in de lege ruimte ver onder het frame in plaats van over de eigen onderrand van het frame. Fix: `top: geometry.height - geometry.fadeHeight` in plaats van `bottom: 0`. Beide widgettests op de smalle takken controleren nu expliciet dat de fade-rect eindigt op de eigen onderrand van het frame en niet op die van de hero, zodat een regressie hierop weer rood wordt. Wat nog niet is gebeurd: visuele verificatie op een echt smal scherm (simulator- of TestFlight-screenshot) dat de crop nu echt de gezichten/compositie toont in plaats van de zijkanten. `flutter test`, `flutter analyze` en `scripts/ci_checks.sh` zijn schoon voor de geraakte bestanden; gecommit als `40d9608` op `main`.

## DEC-058: De App Store "What's New" wordt automatisch gezet zodra een build gekoppeld wordt, uit dezelfde bron als de TestFlight-notities

**Date:** 2026-08-20
**Status:** accepted
**Context:** `set_build_notes` zet al sinds DEC-022 de TestFlight-notities (`BetaBuildLocalization.whatsNew`) automatisch uit `docs/RELEASES.md` zodra `attach_build_to_version` een build koppelt. De App Store-versie zelf heeft een apart veld voor hetzelfde soort tekst, `AppStoreVersionLocalization.whatsNew`, wat een gebruiker bij een echte update te zien krijgt. Dat veld bleef onaangeroerd: geen `deliver`-lane, geen metadata-map, dus bij elke indiening moest iemand het met de hand overtypen in App Store Connect. Er is geen `fastlane/metadata/`-structuur in dit project (één gedeeld `Fastfile` voor drie platforms, credentials via `Spaceship::ConnectAPI` in plaats van `deliver`), dus de nieuwe code volgt dat patroon in plaats van de metadata-tooling van fastlane erbij te halen.
**Decision:** `set_version_whats_new`/`verify_version_whats_new` in `fastlane/Fastfile` spiegelen `set_build_notes`/`verify_build_notes` één-op-één, maar praten met `Spaceship::ConnectAPI.patch_app_store_version_localization` (enkelvoud: de meervoudsvorm bestaat niet voor dit endpoint, geverifieerd in de geïnstalleerde spaceship-gem vóór gebruik) op `version.get_app_store_version_localizations` in plaats van `build.get_beta_build_localizations`. `apply_app_store_whats_new` draait automatisch ná `apply_release_notes` in `attach_build_to_version`, dus elke `ios_beta`/`tvos_beta`/`macos_beta`/`beta`/`attach_builds`-run die een build koppelt zet nu ook de App Store-tekst. Losse lanes `whats_new_show` en `whats_new` erbij, analoog aan `notes_show`/`notes`, voor handmatig nazetten of backfillen. Bewust **niet** meegenomen: de lange productbeschrijving, keywords, promotional text — die veranderen zelden en per ongeluk overschrijven van bestaande ASO-copy is duurder om te herstellen dan het handmatig laten. Alleen "What's New" leent zich voor automatisering, want dat is al de bron-van-waarheid-tekst die elke release toch al uit `docs/RELEASES.md` komt.
**Consequences:** Net als bij de TestFlight-notities is dit nooit fataal voor de release zelf: ontbrekende notities in `docs/RELEASES.md` geven een waarschuwing met het herstelcommando, niet een afgebroken upload. Geverifieerd met een read-only `fastlane whats_new_show platform:ios`: de call keten (editable version → localizations → whatsNew) werkt tegen de echte API en bevestigde dat het veld voor de bewerkbare 2.8.0-versie leeg stond. Nog niet gedaan: de tekst voor build 234 daadwerkelijk wegschrijven (`fastlane whats_new build:234`). Dat is een schrijfactie op live App Store Connect-metadata en staat bewust apart van deze automatisering-commit.

## DEC-059: Preference-sync krijgt één mutatiepijplijn met een expliciete policy, en de legacy prefs-store valt er bewust buiten

**Date:** 2026-08-21
**Status:** accepted
**Context:** Twee gebruikersmeldingen (een ondertitelkeuze die na hervatten omsloeg, kijkvoortgang die terugliep) wezen naar hetzelfde: Pleya schreef persoonlijke staat naar iCloud zonder te weten wélke staat daar hoorde. Vier dingen maakten dat concreet. `BaseSharedPreferencesService.onKeyWritten` was `void Function(String key)`, dus de consument moest de waarde terug lezen; bij een verwijdering las hij `null` en stopte, waardoor een lokaal gewiste voorkeur alleen via een volledige `pushAll` de cloud haalde, en een `void` terugtype dwong hem tot `unawaited(...)`, wat elke transportfout weggooide. `SettingsExportService.isExportable` was een allow-by-default denylist, dus elke nieuwe voorkeur synchroniseerde tenzij iemand hem verbood; zo reisden `companion_remote_last_host_address` (een LAN-adres) en `tracker_library_filter_*` ongevraagd mee. De cloudsleutel strípte de profielidentiteit, dus alle profielen deelden één slot per basissleutel. En `pushAll` prunet op afwezigheid uit de push-set, waardoor een waarde die door de 100 KB-grens viel niet werd overgeslagen maar **verwijderd**. Daarbovenop bleek de legacy-`SharedPreferences`-store na `migrateLegacySharedPreferencesToSharedPreferencesAsyncIfNecessary` een aparte store: die migratie kopieert eenmalig en wist niets, en de "al gemigreerd"-vlag leeft in de doelstore. Vijf services schrijven nog in de oude store, waaronder `local_folder_client` met `local_progress_*`. Voor die sleutels bestaan dus twee waarden: de levende in de legacy-store die de push niet ziet, en een bevroren kopie uit het migratiemoment die hij wél zou uploaden.
**Decision:** Het hookcontract is vervangen, niet omwikkeld. `BaseSharedPreferencesService.onMutation` levert een volledige `PreferenceMutation` (`key`, `operation: set|remove`, `value`, `source: local|remote|migration|import|reset`) en geeft een `Future` terug die de schrijver afwacht. `PreferenceSyncCoordinator` (`lib/services/preferences/`) bezit mutatie-orkestratie, policy, scope, merge, reconcile en status; `PreferenceTransport` is de poort en `ICloudKvsTransport` de enige implementatie, met alleen kanaalwerk erin. `ICloudSyncService` blijft over als dunne facade voor de bestaande callsites en draagt zelf geen syncgedrag meer. `PreferenceSyncPolicyRegistry` keert de denylist om: een niet-geregistreerde voorkeur is local-only, en de hand-onderhouden dubbeling met `isUserScopedBaseKey` is verdwenen. `PreferenceSyncScope` houdt de profielidentiteit vast en is eerlijk over portabiliteit: een Plex Home-UUID is portable, een `local-<uuid>` niet en die scope synchroniseert dus niet. `PreferenceRevision` legt scalaire conflicten vast als deterministische last-writer-wins op `(updatedAt, deviceId)` met tombstones, waarbij een `migration` géén gebruikerstijdstempel zet. De ~35 library- en home-callsites in `StorageService` lopen nu rechtstreeks over die pijplijn, verwijderingen inbegrepen. **De vijf legacy-services vallen er bewust buiten**: `flutter.`-sleutels en de benoemde historische namen (`local_progress_*`, `local_watched_*`, `local_server_match_v1`, de Pleya Share-sleutels) zijn geclassificeerd als runtime cache of secret en bereiken iCloud niet. `mergeProgressMaps` blijft staan als *legacy inbound compatibility*, met de verwijderconditie op de methode: hij verdwijnt zodra het syncformaat naar v2 gaat en geen ondersteunde client nog v1-progressie schrijft.
**Consequences:** Wat vandaag anders werkt voor een gebruiker: een uitgezette instelling verdwijnt nu ook op het andere toestel, en `volume`, downloadmappen, hardware-decoding, HDR en het laatst gebruikte LAN-adres synchroniseren niet langer. Dat laatste is een gedragswijziging, geen regressie: het waren apparaatkenmerken die als voorkeur reisden. De cloudinhoud is **niet** aangeraakt. `PreferenceSyncCoordinator.v2CloudFormatEnabled` staat op `false`, dus de scoped namespace en de envelop bestaan en zijn getest maar schrijven nog niets; de v1-sleutels blijven staan. Twee dingen moeten vóór die schakelaar om: v1-cloudsleutels dragen geen profielidentiteit meer, dus ze mogen niet aan het toevallig actieve profiel worden toegewezen, en een oude client moet de nieuwe records met rust laten. Dat tweede is gemeten in plaats van aangenomen: de uitgebrachte implementatie slaat sleutels die met `__` beginnen over in zowel de prune-lus als de apply-lus, en schrijft er zelf niets in behalve `__syncFormatVersion`, vastgelegd in `test/services/icloud_rolling_upgrade_test.dart` met een controle die bewijst dat dezelfde payload in de gewone namespace wél wordt opgeruimd. De v2-namespace krijgt daarom een `__`-voorvoegsel en er is geen tweefasenuitrol nodig. Erkende beperking: client-side LWW hangt aan de klok van het toestel, dus een Apple TV met een verkeerd gezette tijd wint of verliest onterecht; een server-geordende revisie hoort bij de Pleya Server-transport. De prune is daarbij conservatief geworden, en dat was een echte vondst bij het nalopen van de eigen acceptatie: `reconcile` verwijderde een cloudsleutel zodra hij niet meer in de push-set zat, dus het aanscherpen van het beleid zou de clouddata van andere toestellen wissen, en een vergeten registratie zou dataverlies zijn in plaats van een gemiste synchronisatie. Hij deletet nu alleen wat lokaal echt weg is; een sleutel die aanwezig maar niet syncbaar is blijft staan, ook voor een oudere client die hem nog wél leest. Twee tests leggen beide takken vast. In dezelfde ronde bleken 26 gedeclareerde voorkeuren niet geregistreerd, waaronder `app_locale`, `library_density`, `buffer_size`, `default_playback_speed` en de mpv-configuratie; die zijn alsnog geclassificeerd, en een guard in `preference_sync_policy_test.dart` scant de declaraties zodat een nieuwe voorkeur er niet stil doorheen valt. `test/no_raw_preference_write_test.dart` bewaakt dat de 81 overgebleven rauwe prefs-schrijfacties in 20 bestanden alle 81 geclassificeerd zijn, met een aantal per bestand zodat een nieuwe schrijfactie rood wordt. Een aanname uit het plan is onderweg weerlegd en dat verandert het ontwerp: **`serverId` is niet apparaatgebonden.** Voor Plex is het `PlexServer.clientIdentifier` uit plex.tv's `/resources` (`plex_auth_service.dart:354`, gebruikt als clientsleutel op `multi_server_manager.dart:476`), voor Jellyfin `connection.serverMachineId` uit de `machineId` van de server zelf (`jellyfin_auth_service.dart:434`). Beide zijn op elk toestel gelijk. Alleen de local-folder- en Pleya Share-backends sleutelen op een lokaal gegenereerde `connection.id`. De bibliotheekfamilies zijn daarom niet local-only gezet maar krijgen een portabiliteitsfilter op de waarde-inhoud (`preference_value_portability.dart`): entries van een niet-portable backend gaan er vóór transport uit, per-bibliotheeksleutels waarvan de serverId niet portable is worden in hun geheel overgeslagen, en een remote apply mergt in plaats van te vervangen zodat de local-folder-entries die het andere toestel nooit zag blijven staan. `home_row_order` en `hidden_home_rows` blijven wél local-only, en niet vanwege `serverId`: het is `hub.identifier`, de tweede helft van `homeRowId`, die niet is aangetoond als stabiele server-side identiteit over toestellen. Wat wel vaststaat staat bij de registratie; de fallback naar `hub.id` en de meting op twee toestellen niet. Losse follow-up **Legacy store consolidation**: per service een datamigratieplan met terugrolstrategie, niet in deze ronde. `flutter analyze` schoon, `scripts/ci_checks.sh` groen op SDK 3.44.0, volledige suite 3959 groen en dezelfde 15 rood als op `8fea407`.

## DEC-060: De v2-cutover maakt v1 read-only legacy, zonder dual-write

**Date:** 2026-08-21
**Status:** accepted
**Context:** DEC-059 bouwde de scoped namespace en de revisie-envelop maar liet ze uit staan: `v2CloudFormatEnabled` was `false`, dus de cloudinhoud was nog het oude platte formaat. Voor het aanzetten waren er drie routes. Dual-write (beide formaten schrijven) klinkt het veiligst en is het niet: v1 draagt geen revisie en geen profiel, dus een client die beide bijhoudt kan een nieuwere gebruikersactie in v1 niet onderscheiden van een oudere momentopname ervan. Dat is precies de dubbelzinnigheid waarvoor de envelop bestaat, en dual-write bouwt hem terug in een ingewikkelder vorm. Continu dubbel lezen heeft hetzelfde probleem plus een tweede leesronde. Blijft over: v1 bevriezen.
**Decision:** v1 wordt read-only legacy state. Eenmalig, bij de eerste start na de upgrade, importeert `bootstrapFromLegacyV1` de **ondubbelzinnig globale** v1-waarden naar v2 met `legacyRevisionAt = 0`, zodat de eerste echte wijziging op welk toestel dan ook wint; profiel-scoped v1-records worden niet geïmporteerd maar gequarantained, want het formaat heeft hun profiel gestript en niemand kan zeggen van wie ze zijn. De marker `pleya_pref_v1_bootstrap_done` blijft lokaal, en een mislukte read laat hem ongezet zodat de import het opnieuw probeert. Daarna schrijft de client nooit meer v1 en mergt hij geen inkomende v1-wijziging. De bevroren records blijven staan: verwijderen zou een werkende instelling weghalen bij een toestel dat nog de oudere build draait. Een v1-record dat ná de cutover verandert betekent dus dat er nog een oud Apple-toestel meedraait; dat wordt geteld als `legacyPeerDetected` en verschijnt als waarschuwing in Instellingen, niet als fout.
**Consequences:** De gemengde-versiegrens is bewust en tijdelijk: tot alle Apple-toestellen op de nieuwe build staan, delen oud en nieuw geen instellingen meer. Dat is zichtbaar gemaakt in plaats van stil gelaten. Twee dingen zijn gemeten in plaats van aangenomen. De gecombineerde voetafdruk van bevroren v1 plus geprojecteerde v2 is 23 KB + 33 KB = 56 KB van de 1024 KB die KVS per account geeft, op een zwaar account (`kvs_footprint_test.dart`), dus de dubbele opslag is geen quotarisico. En `icloud_rolling_upgrade_test.dart` draait het echte v1-codepad (`useV2CloudFormat: false`) in plaats van de inmiddels-v2 standaard, want een test die het oude algoritme naschrijft bewijst niets over de uitgebrachte client. De v1-implementatie blijft daarom bestaan, uitsluitend voor die test: `v2_only_invariant_test.dart` bewaakt dat geen enkel bestand in `lib/` het formaat nog kiest, dat een productiematig gebouwde coordinator alleen in `__pleya_pref_v2/` schrijft, en dat een volledige levenscyclus over een store vol v1-records die records ongemoeid laat. v2-only is daarmee een invariant, geen standaardwaarde van een omkeerbare vlag.

## DEC-061: Reconciliatie heeft één scheduler, status heeft drie assen, en afgeleide schermstaat wordt gericht ongeldig verklaard

**Date:** 2026-08-21
**Status:** accepted
**Context:** Fase A blok 2 raakte vier dingen die elk op zichzelf klein lijken en samen bepalen of de sync merkbaar werkt. Er was geen plek die zei wánneer er gereconcilieerd wordt: boot deed het, inschakelen deed het, en een profielwissel deed niets, terwijl de scope per aanroep wél opnieuw werd gelezen. Er was één `state`-veld, dus een geslaagde losse write zette `success` en wiste daarmee een quotastop, een transportfout en de legacy-peer-waarschuwing uit beeld terwijl ze nog waar waren. Een remote apply schreef netjes naar `SharedPreferences` en stopte daar: `HiddenLibrariesProvider` had zijn set bij constructie gelezen, `HomeLayoutProvider` bewaakte zichzelf met `if (_isInitialized) return`, en `LibrariesProvider` bakte de volgorde in zijn lijst, dus de waarde klopte en het scherm niet tot een herstart. En de enige merge in de engine werd gedispatcht met een hardgecodeerde `if` op een sleutelprefix, waardoor niets anders ooit een merge kon krijgen.
**Decision:** `PreferenceReconcileScheduler` bezit alle triggers (`boot`, `enabled`, `foreground`, `accountChanged`, `profileChanged`, `imported`, `reset`). Triggers uit dezelfde turn worden één run; een trigger tijdens een lopende run levert precies één vervolgrun. Het coalescingvenster is een microtask, geen `Future.delayed`: deterministisch in een test en niet af te stellen tot een correctheidsbug. Wat een run doet volgt uit de trigger, niet uit de aanroepplek: een import of reset trekt de store niet eerst binnen, want lokaal is dan de bron. Een profielwissel wordt door de engine zelf opgemerkt aan een schrijfactie op `active_app_profile_id`, dus elk pad dat van profiel wisselt is gedekt, ook de bootstrap en de opruiming. `PreferenceSyncStatus` bestaat uit drie assen: `availability` (uit, niet beschikbaar, klaar), `activity` (idle, syncing) en `health` (healthy, warning, error, quota), plus `legacyPeerDetected` als eigenschap van het account. De acht toestanden uit het plan zijn een afgeleide getter, dus niets schrijft nog een toestand en niets kan er dus een overschrijven; `raise` verlaagt nooit, en alleen een geslaagde volledige reconcile mag health opschonen, want alleen die heeft alles bekeken. `PreferenceRefreshFamily` staat in de policy naast alles wat de registry al van een sleutel weet, en `PreferenceRefreshBus` meldt per batch wélke families verlopen zijn; de providers herladen hun eigen plak. `PreferenceMergeRegistry` vervangt de hardgecodeerde `if`: een familie registreert `merge(local, remote)` onder de naam die in de policy staat, en de engine leert nooit wat de waarden betekenen.
**Consequences:** De merge werkt nu ook uitgaand, en dat was de asymmetrie die fase B blokkeerde. Voor de serverlijsten betekent het: een lokale wijziging houdt de entries in de store die van een server zijn waar dit toestel niets over kan zeggen, terwijl een bewuste verwijdering op een gedeelde server gewoon doorreist. Een uitgaande merge die de store niet kan lezen schrijft niet: overschrijven op basis van een mislukte read is precies hoe je andermans data wist. Datzelfde nalopen bracht een echte bug boven die door de v2-sleutelvorm was ontstaan: de prune vergeleek een genamespacete cloudsleutel met een kale basissleutel, dus de bescherming "staat lokaal, alleen niet syncbaar" deed onder v2 helemaal niets en een lijst met uitsluitend local-folder-entries werd bij elke reconcile uit de store verwijderd. De vergelijking gaat nu over basissleutels; twee tests leggen beide takken vast en de test is rood op de oude vergelijking. Native is er alleen gewijzigd waar een contractgat aantoonbaar was, en dat waren er twee van de negen auditpunten: er was geen `deinit` met `removeObserver`, en `NSUbiquityIdentityDidChange` werd nergens waargenomen, waardoor uitloggen tijdens een sessie de status gezond liet terwijl elke write nergens heen ging. Het bufferen van notificaties die vóór de Dart-subscriptie binnenkomen is bewust **niet** gebouwd: elk pad dat abonneert reconcilieert ook, dus de eerstvolgende read draagt die informatie al. De volledige audit staat in `docs/qa/icloud-kvs-native-audit.md`. Wat dit alles niet bewijst blijft staan: een fake `MethodChannel` toont geen echte iCloud-sync tussen toestellen, en de matrix in `docs/qa/preference-sync-and-playback-matrix.md` is nog open. Volledige suite 4068 groen en dezelfde 15 rood als op `8fea407`; `ci_checks.sh` groen op SDK 3.44.0.
## DEC-062: Tautulli-kijkgeschiedenis als bron voor de bestaande smaakengine, servergebonden gekoppeld en profielgebonden verwerkt

**Date:** 2026-08-21
**Status:** accepted

**Context:** De on-device smaakengine uit DEC-004 leert alleen van wat er in Pleya zelf is afgespeeld. Wie zijn Plex-server al jaren via andere clients gebruikt houdt dus een leeg smaakprofiel terwijl Tautulli die geschiedenis compleet heeft. Drie fouten in de scorer moesten daarvoor weg, anders versterkt een import van een jaar geschiedenis de vertekeningen in plaats van ze op te lossen: elke uitgekeken aflevering leverde een volle `+1.0`-rij met de *show*-genres (twintig afleveringen telden als twintig onafhankelijke bewijzen), `isWarm` telde ruwe databaserijen inclusief negatieve, en één dismissal in een dimensie zonder positief signaal kwam via de `maxAbs`-deler precies op `-1.0` uit terwijl `maxOf`/`top2Of` datzelfde signaal daarna weggooiden.

**Decision:**

*Adapter, geen tweede engine.* Tautulli levert genormaliseerde kijkinteracties aan dezelfde `MediaInteractions`-tabel en dezelfde `AffinityEngine`. Er komt geen aanbevelingsengine op Pleya Server en geen tweede rangschikking.

*De koppeling is servergebonden, de data profielgebonden.* Een Tautulli-instance monitort een Plex-*server*, en de beheerder autoriseert hem één keer voor die server. `TautulliServerIntegration` staat daarom onder de ongeprefixte sleutel `tautulli_integration_{machineIdentifier}` in plaats van onder een `user_{uuid}_`-sleutel, zodat elk lokaal profiel dat die server heeft ervan profiteert zonder de admincredential te bezitten. De opslag is even goed beschermd als voorheen: `CredentialVault.protect`/`reveal` zijn profielloze statics op een willekeurige string, dus alleen de sleutelnaam verandert, niet het beschermingsniveau. Wat wél nodig was: `tautulli_integration_` is toegevoegd aan `SettingsExportService._denyPrefixes`, want een sleutel zonder `user_`-prefix valt anders rechtstreeks door naar `isExportable`.

*Configureren vraagt adminrecht, consumeren niet.* `isOwnerOrAdmin(serverId)` gate't het Tautulli-scherm, het koppelen, het wijzigen van de policy en het ontkoppelen, en dezelfde controle staat nog eens in `TautulliProvider.commit`/`disconnect`/`setHistoryForRecommendations` zodat een codepad de UI-gate niet kan omzeilen. Een gewoon profiel dat de server heeft, gebruikt de door de beheerder geautoriseerde integratie zonder zelf admin te zijn. Dat verzwakt de privacygrens niet: elke import blijft exact gebonden aan het plex.tv-account-id van het actieve profiel, dat `plexSelfAccountIdIn` per profiel oplost en dat `null` teruggeeft zodra het zou moeten raden. Geschiedenis van verschillende gebruikers wordt daardoor nooit gemengd.

*Vier zaken die apart moeten blijven.* Het integratierecord scheidt de adminpolicy (`useHistoryForRecommendations`, `bool?`), de verbindingsstand (`connectionState`), de aanwezigheid van de credential (`token`, nullable) en de bronserver (`machineIdentifier`). Ze lopen echt uiteen: raakt de vault-sleutel kwijt, dan is de token onleesbaar terwijl de policy nog geldig is. De oude per-profiel-store gooide in dat geval het hele record weg, waarmee een expliciete "uit" stilzwijgend terugviel op de default "aan"; `TautulliServerIntegration.decode` laat de credential vallen en houdt de rest.

*Default aan zonder migratiecode.* De policy is `bool?`. `null` betekent "nooit expliciet gekozen" en leest als aan, dus elke bestaande geldige koppeling blijft werken. Alleen een expliciete `false` wordt weggeschreven. Herkoppelen van dezelfde `machineIdentifier` behoudt die keuze (`fromSession(existing: …)`); alleen een werkelijk nieuwe server begint op de default.

*Uitsluiten in plaats van wissen, via een whitelist.* Het scoringsfilter is `NOT (source = 'tautulli' AND (source_server_id IS NULL OR source_server_id NOT IN (…)))`. Lokale rijen matchen het binnenste predicaat nooit en tellen dus altijd mee. Een lege verzameling levert `NOT (source = 'tautulli')` op, nooit een lege `IN ()`. Alles wat niet expliciet is ingeschakeld valt gesloten: policy uit, ontkoppeld, credential onleesbaar, onbekende server, `source_server_id` NULL. `AffinitySnapshots.enabledKey` bewaart de gesorteerde verzameling, want het omzetten van de vlag verandert de rijtelling noch de nieuwste timestamp; zonder die kolom zou de versheidscheck de wissel niet zien.

*Ontkoppelen sluit uit maar wist niet.* De credential verdwijnt, `connectionState` wordt `disconnected`, de policy blijft staan en de geïmporteerde rijen blijven bewaard. Cursors blijven ook staan, zodat herkoppelen incrementeel hervat in plaats van een jaar opnieuw te downloaden.

*Twee botsende legacy-koppelingen falen gesloten.* Meerdere profielen konden elk een eigen `user_{uuid}_tautulli_session` voor dezelfde server hebben. Prefs-sleutels dragen geen recency, dus "de nieuwste wint" bestaat niet en kiezen op profielvolgorde zou betekenen dat de URL en de credential van het huishouden afhangen van wie het eerst inlogt. Identieke koppelingen (zelfde URL, modus en token) zijn een duplicaat en worden weggegooid. Verschillende koppelingen zetten `hasUnresolvedConflict` op het overlevende record, wat import uitschakelt tot een beheerder opnieuw koppelt; credentials worden nooit samengevoegd en de log noemt alleen de categorie.

*Serieverzadiging in de pure scorer.* `TasteEvent.evidenceKey` is `seriesKey ?? globalKey`. Positieve events groeperen daarop, het n-de event telt `1/n`, cumulatief geplafonneerd op `kSeriesEvidenceCap = 3.0`. H(11) is ongeveer 3,02, dus een serie verzadigt rond aflevering twaalf en weegt nooit zwaarder dan drie titels. Een film heeft `evidenceKey == globalKey`, dus n=1 en factor 1,0; een rewatch wordt n=2 (0,5) en n=3 (0,33), wat meteen de gevraagde afnemende rewatch-bonus is, centraal geregeld in plaats van in de importer. Binnen een groep wordt op *gedempt* gewicht gesorteerd, dus de nieuwste afleveringen pakken de zwaarste plekken en een oude binge vervaagt met de bestaande 90-dagen-decay.

*Warmte op unieke titels.* `isWarm` telt voortaan `titleCount`, het aantal onderscheiden evidence-sleutels met netto positief bewijs, en de drempel is `kWarmDistinctTitles = 8`. `eventCount` blijft de ruwe rijtelling omdat de versheidscheck daarop staat. `AffinityVector.toJson` draagt `'v': 2`; een snapshot met een lagere versie geldt als stale, wat zelfhelend is en geen migratie vraagt.

*Negatieve affiniteit als apart, begrensd kanaal.* `dims` bevat uitsluitend positieve waarden, genormaliseerd op de sterkste positieve. Dislikes krijgen een eigen kanaal, `penalties`: `min(kPenaltyMax, magnitude / kPenaltyEvidenceUnit)` met `kPenaltyEvidenceUnit = 1.5` en `kPenaltyMax = 1.0`, rauw en niet genormaliseerd, want normaliseren op de grootste magnitude was precies de oorzaak van de `-1`-klap. Eén verwijdering uit Verder kijken (gewicht 0,3) geeft 0,2; vijf herhaalde signalen bereiken de cap. `recommendationScore` trekt een gedempte som af, geplafonneerd op `kMaxTotalPenalty = 2.0`, terwijl de genre-term positief al tot 4,5 levert. `topFeatures` vetot een feature met penalty vanaf `kTopFeaturePenaltyVeto (0.5)`. Een vroeg afgebroken Tautulli-playback levert nooit een negatief signaal.

*Het echte API-contract.* `get_history` krijgt `grouping: 0` (de standaard groepeert opeenvolgende plays tot één synthetische rij met `group_count`/`group_ids`, waardoor `row_id` onbruikbaar wordt als idempotentiesleutel), `include_activity: 0`, `order_column: date`, `order_dir: desc`, en `after`/`before` als inclusieve dagbounds. `start` blijft een pagination-offset en is nooit een datum.

*`duration` is speeltijd, niet mediaduur.* `plexpy/datafactory.py` schrijft binnen `get_history` letterlijk `'duration': item['play_duration']` naast `'play_duration': item['play_duration']`, en die waarde is `SUM(stopped - started) - SUM(paused_counter)`. De mediaduur zit niet in deze respons; die is alleen intern de noemer voor `percent_complete`. Omdat dezelfde sleutel in `get_activity` wél de mediaduur is (in milliseconden), heet het veld in het model `playSeconds` en leest het `play_duration` met `duration` als fallback. Het bestaande veld `duration` blijft ongewijzigd voor bestaande callers.

*Signalen.* `watched_status >= 1` of `percent_complete >= 85` wordt `completed` (+1,0); 50 tot 85 wordt `partial` (+0,4); daaronder wordt genegeerd. De OR is nodig, niet cosmetisch: de gemeten fixture bevat een rij met `watched_status: 1` bij `percent_complete: 82`, want `check_watched` gebruikt de drempel die de beheerder zelf instelt.

*Retentie: één eerlijk contract.* `insertMediaInteraction` snoeide al op 365 dagen én op de nieuwste 5000 rijen per profiel (`ORDER BY occurred_at DESC LIMIT -1 OFFSET 5000`). Een backfill loopt aflopend naar ouder, dus zodra het profiel vol staat ligt elke volgende backfillrij per definitie voorbij die offset en wordt hij in dezelfde call weer verwijderd. Het contract is daarom expliciet gemaakt: **Pleya bewaart de meest recente `kProfileInteractionCap` (5000) interacties per profiel, binnen een maximale leeftijd van 365 dagen; die 365 dagen zijn een bovengrens op de leeftijd, geen garantie dat een druk jaar er volledig in past.** Elke aflopende pass leest na elke pagina de ongefilterde telling en stopt op de cap met `backfillState = 'retentionCap'`, dus er wordt geen pagina opgehaald waarvan vaststaat dat hij weggeprund wordt. De forward pass stopt daar niet op: nieuwe events zijn de nieuwste en verdringen de oudste. Zakt de telling later onder `kBackfillResumeFraction (0.9)` van de cap doordat rijen verjaard zijn, dan hervat backfill.

*Het backfillvenster is bevroren.* De bovengrens wordt één keer vastgezet op de dag van het oudste verwerkte record en verschuift daarna nooit; `backfillOffset` is de enige cursor erbinnen. Daarmee bestaat het geval "een kalenderdag met meer records dan één pass aankan" niet meer als valkuil: de offset loopt over meerdere runs dwars door die dag heen in plaats van zich er opnieuw op te ankeren. Omdat de lijst aflopend op datum is, telt de offset vanaf de nieuwe kant, en de dagelijks stijgende 365-dagenbodem snoeit alleen aan de oude kant zonder de offset te verschuiven. Restrisico: wist een beheerder oude history tijdens een lopende backfill, dan schuiven rijen op en kan de offset er enkele overslaan. Gevolg is een gat in oude geschiedenis, geen corruptie.

*Idempotentie en cross-source-deduplicatie.* `sourceEventId = 'tautulli:{machineIdentifier}:{rowId}'` met een partiële unieke index op `(profile_id, source_event_id) WHERE source_event_id IS NOT NULL`. De importer vraagt bovendien vooraf op welke event-ids al bestaan: `insertOrIgnore` zou ze stilzwijgend laten vallen, en dan zou elke overlappende forward pass eruitzien als nieuwe data en een overbodige herbouw uitlokken. Een Tautulli-event wordt daarnaast onderdrukt door een semantisch equivalente positieve lokale playbackinteractie (`source = 'local' AND event_weight > 0`, zelfde profiel, zelfde `global_key`, binnen zes uur). De `event_weight > 0`-clausule is het punt: een dismissal mag nooit gelden als bewijs dat de view al geregistreerd was. Er gaat één gebundelde query per pagina uit, niet één per rij.

*Lifecycle-guards.* De import-lock is statisch op `'{profileId}|{serverId}'` en wordt in een `finally` vrijgegeven. Vóór elke schrijfactie worden twee dingen opnieuw gecontroleerd: of dit nog het actieve profiel is, en of de in-memory epoch-teller nog gelijk is aan die bij de start. Die tweede is nodig omdat `deleteProfile` eerst `deleteRecommendationDataForProfile` aanroept terwijl het profiel nog actief is, en omdat Plex Home-profielen nooit in de `Profiles`-tabel staan (`Profile.virtualPlexHome`), zodat een bestaanscheck daar niets bewijst. Dart is single-threaded per isolate en de check staat direct vóór de write, wat het venster tot het praktische minimum sluit; het is nadrukkelijk geen transactie over beide operaties heen. `fetchImportHistory` hercontroleert per pagina of import nog is toegestaan, zodat een beheerder die halverwege uitzet de lopende sync ziet stoppen zonder halve staat.

*De credentialgrens.* `TautulliImportAccess` biedt alleen `enabledImportServerIds()` en `fetchImportHistory(serverId, userId: …)`. Er is geen publiek veld en geen getter waarlangs UI-code of een ander profiel de token bereikt, en de enige uitgaande call is een `get_history` met vastgezet `user_id`. Binnen één Dart-isolate bestaat geen taalgrens die geheugen afschermt, dus dit is een API-grens en geen sandbox; die claim wordt niet groter gemaakt dan hij is.

*Bredere kandidatenpool.* `CandidatePool` voegt per server vier lagen samen: de al geladen hub-items, `fetchRecentlyAdded` (12u TTL), top-rated per bibliotheek en een deterministisch roterende steekproef uit de oudste toevoegingen (beide 24u TTL). Dat is een bronreparatie: "Verborgen parels" eist items ouder dan 90 dagen maar kreeg uitsluitend recent-toegevoegd voer. Het budget is `1 + 2 * kMaxLibraries = 13` calls per server per 24u, gehaald door `totalCount` uit de top-rated pagina te hergebruiken voor de offset in plaats van er een probe-call aan te besteden. Top Picks-items worden nu ook uitgesloten van Verborgen parels.

*Serverpopulariteit blijft buiten scope.* `get_home_stats` wordt niet toegevoegd, ook niet als ongebruikte clientmethode, model of fixture. De integratie gebruikt uitsluitend de kijkgeschiedenis van de exact gekoppelde actieve gebruiker; geaggregeerd gedrag van andere servergebruikers wordt niet opgehaald en krijgt geen gewicht en geen verborgen prior.

**Consequences:**

Schema v19 voegt `source`, `sourceEventId`, `sourceServerId`, `completionPercent` en `playSeconds` toe aan `MediaInteractions`, `enabledKey` aan `AffinitySnapshots`, en de tabel `HistorySyncCursors`. Alle nieuwe kolommen zijn nullable of hebben een default, dus bestaande rijen blijven geldig. De partiële unieke index wordt met `customStatement` gemaakt in `onCreate` én in het v19-blok, want drift's `createAll()` kent geen partiële index. Er is geen `SchemaVerifier` in dit project; v19 wordt net als v14 tot en met v18 getest via een in-memory upgrade en `_ignoreAlreadyExists`.

Wat bewust open blijft staan:

- **Een adminbeslissing repliceert niet naar een tweede toestel.** Er bestaat geen laag die dat kan. Plex is voor prefs alleen-lezen (`/:/prefs` komt in heel `lib/` één keer voor, als GET), Tautulli's API kent geen generieke setter (alleen `sql`, `backup_config`, `backup_db`, `restart` en `update` schrijven, en Pleya heeft niets te zoeken in andermans database), en de Go-service in `server/` is de Pleya Share-relay zonder configuratie-endpoint. iCloud KVS gooit sleutels van een ander profiel weg en staat standaard uit. Een tweede toestel heeft dus een eigen adminkoppeling nodig en begint daarbij op de default (aan). Cross-device serverpolicy wordt niet geclaimd.
- Bestaande episode-interacties met rijke metadata hebben geen `seriesKey` en krijgen geen rollup met terugwerkende kracht; ze verdwijnen via decay en retentie.
- Er is geen batch-hydratie van rating keys in de codebase. De importer resolvet per distincte titel met begrensde concurrency: voor een binge van twintig afleveringen is dat één call (de serie), voor driehonderd losse films driehonderd. Vandaar de paginacap en de gescheiden backfill.
- Een legacy Tautulli-sessie zonder `pms_identifier` blijft profielgebonden werken voor de aanwezigheidsoppervlakken en importeert niet, tot iemand opnieuw koppelt.
- `settings.personalizedRecommendationsDescription` is niet herschreven: de bestaande tekst zegt al "Nothing leaves your device", wat sterker is dan de geplande formulering, en herschrijven zou veertien andere locales invalideren zonder winst.

## DEC-063: Pleya Unified TV 2026 — architectuurbaseline, supersedes en afbakening

**Date:** 2026-08-29
**Status:** accepted
**Context:** [docs/tvos-unified-experience.md](tvos-unified-experience.md) is de goedgekeurde baseline voor een unified multi-server catalogus (Films/Series over alle geconfigureerde bronnen heen) met een nieuwe TV-shell erbovenop, uitgevoerd in tien fases (hoofdstuk 27). Fase 0 legt het contract vast vóórdat er productiecode wordt geraakt. Hoofdstuk 4 van dat document maakt zes architectuurbesluiten die niet per fase heropend mogen worden, en het document raakt daarnaast drie bestaande beslissingen: DEC-023 (mobiele navigatie) beschrijft alleen het huidige, niet-unified gedrag; DEC-002 noemt merkkleurwaarden die de code sinds hoofdstuk 34.1 al is voorbijgelopen; en DEC-020 (watchlist-verwijdering) moet expliciet worden afgebakend tegen de nieuwe source picker, want beide raken "welke bron" voor hetzelfde media-item.
**Decision:**

*De zes harde architectuurbesluiten uit hoofdstuk 4* (letterlijk overgenomen, niet heropend):

1. **MediaItem blijft één concrete bron** (4.1). Geen `List<Server>` of "active server" op `MediaItem`: playback, metadata-refresh, verwijderen, tracks/media-versies, play queues en watch-state-events blijven allemaal aan één concrete server gebonden.
2. **Een nieuwe projectielaag komt boven MediaItem, niet erin** (4.2). `UnifiedMediaSource` (één concrete bron plus server-/library-identiteit en availability) en `UnifiedMediaGroup` (identiteit, lijst van sources, representatieve bron, watch-state, coverage) zijn zuivere presentatie-/aggregatiemodellen.
3. **Eén centrale identiteitspijplijn** (4.3). Home, Films, Series, Search, Verder kijken en Watchlist krijgen geen eigen dedupalgoritme; candidate bucketing, externe-ID-verrijking, identiteitsbewijzen, conflictcontrole, grouping, bronresolutie en coverage lopen door één gedeelde service.
4. **Bronkeuze gebeurt vóór de bestaande route** (4.4). Een `UnifiedMediaGroup` met meerdere bronnen gaat via een picker naar één concreet `MediaItem`, en pas dán de bestaande Pleya-flow in. De speler blijft vrij van unified-cataloguslogica.
5. **Bibliotheken blijft bestaan** (4.5). Films en Series zijn de dagelijkse globale catalogus; Mijn Pleya ▸ Bibliotheken blijft de geavanceerde, brongebonden weergave (per-library selectie, Recommended, Browse, Collections, Playlists, backend-specifieke filters, folder browsing, metadata vernieuwen, scan/analyse/prullenbak, tonen/verbergen/ordenen).
6. **Writes zijn standaard brongebonden, en rangorde kent geen willekeur** (4.6 + 4.7 samengevoegd tot één besluit, want beide gaan over hetzelfde: een mutatie mag nooit per ongeluk op de verkeerde bron landen). Lezen mag gegroepeerd; afspelen, details, metadata-refresh en verwijderen werken altijd op de gekozen bron, behalve het expliciete groepscontract van hoofdstuk 13 (Verwijder uit Verder kijken) en de expliciete "Alle bronnen"-optie bij Markeer bekeken. De eerste server die antwoordt wordt nooit automatisch artwork-, playback- of destructive-actionbron; elke rangorde krijgt de vaste tie-break `preferred source → online state → metadata completeness → artwork completeness → quality information → server name → server id → item id`.

*PARTIAL supersede van [DEC-023](#dec-023), uitsluitend het TV/tvOS-deel.* DEC-023 legt vast dat op mobiel Mijn Pleya de enige persoonlijke ingang is, via `showsHeaderAccountMenu(isMobile:)`/`getVisibleTabs`, en dat desktop en tvOS het bestaande headermenu houden omdat hun sidebar Mijn Pleya nooit rendert. Pleya Unified TV 2026 vervangt op tvOS de bestaande sidebar-gebaseerde shell door de nieuwe TV-shell van hoofdstuk 6, met Mijn Pleya als geneste navigator (hoofdstuk 6.3) en een eigen focuscontract (hoofdstuk 7). Die TV-specifieke navigatiewijziging valt dus buiten wat DEC-023 beschreef toen `side_navigation_rail.dart` op tvOS `null` teruggaf voor Mijn Pleya. Deze supersede raakt **uitsluitend het TV/tvOS-gedeelte** van DEC-023: de mobiele bar-samenstelling, `showsHeaderAccountMenu`, `AccountUiActions` en de gehele redenering over `discover_screen.dart` op mobiel blijven ongewijzigd van kracht. Dit is geen correctie van een fout in DEC-023 — die beslissing was correct voor de situatie die hij beschreef — maar een scopewijziging op het tvOS-pad die met de nieuwe shell ontstaat.

*Supersede van uitsluitend het kleurwaardedeel van [DEC-002](#dec-002).* DEC-002 legt `kAccent = #F42B1F` en `kAccentAlt = #F68F16` vast als gesampled uit het Pleya-logo. `lib/theme/mono_theme.dart` draagt inmiddels `kAccent = #E5140F` en `kAccentAlt = #FFB020` (hoofdstuk 34, 34.1) zonder dat DEC-002 was bijgewerkt. Deze paragraaf haalt die drift in: de twee hexwaarden in DEC-002 zijn vervangen door `#E5140F`/`#FFB020` als de canonieke merkkleuren. Het **Pleya-brandprincipe** uit DEC-002 — kleuren gesampled uit het echte logo, rood plus amber als paar, spaarzaam toegepast op logo/progress/badges/selection/actieve navigatie en nooit als algemene knop- of paginafill, BuildMind-paars/-blauw bewust buiten de app-UI — blijft **onverkort geldig** en wordt hier bevestigd, niet heropend.

*Afbakening tegen [DEC-020](#dec-020).* DEC-020 legt vast dat watchlist-verwijdering een titel uit **alle** `WatchlistMembership`-records tegelijk haalt, zonder bronkeuze — dat blijft ongewijzigd. De source picker uit hoofdstuk 14 introduceert géén bronkeuze voor verwijderen uit de watchlist. De picker geldt uitsluitend voor: availability tonen (hoofdstuk 14.7/14.8), een item openen, de detailpagina met source switching (hoofdstuk 15), en afspelen. Watchlist-add/-remove, de partially-failed-afhandeling en de ordinale bronvolgorde uit DEC-020 lopen buiten de unified-picker om.

*Cross-server mergen van Pleya Server, local en Pleya Share.* Zoals hoofdstuk 11 en 33.6 (conflictpunt 3) al specificeren: een `UnifiedMediaGroup` mag een Pleya Server-, local- of Pleya Share-bron als **single-source** groep bevatten, maar die bronnen worden **niet** cross-server gemerged met Plex- of Jellyfin-bronnen, noch onderling met elkaar. Waar de goedgekeurde mockups "Emby" tonen is dat te lezen als Pleya Server of Pleya Share; Pleya heeft geen Emby-backend (`MediaBackend` kent alleen plex, jellyfin, pleyaServer, local, pleyaShare).
**Consequences:** DEC-023, DEC-002 en DEC-020 blijven allemaal `accepted` en worden niet op `superseded` gezet: dit is per paragraaf een partiële supersede/afbakening, geen vervanging van de hele beslissing. Toekomstige lezers van DEC-002 moeten de kleurwaarden hier lezen, niet de oorspronkelijke hexcodes; toekomstige lezers van DEC-023 moeten voor tvOS naar hoofdstuk 6/7 van het unified-plan, voor mobiel blijft DEC-023 zelf de bron. De zes architectuurbesluiten hierboven zijn vanaf nu bindend voor elke fase van Pleya Unified TV 2026 en worden, net als de rest van dit besluit, niet per fase herwogen — een latere fase die een van deze punten wil heropenen heeft een nieuw ADR nodig, geen stille afwijking in code of plan.


## DEC-064: Films en Series zijn twee niveaus — discovery landing en complete catalogus

**Date:** 2026-08-30
**Status:** accepted
**Context:** Hoofdstuk 10.2 van [docs/tvos-unified-experience.md](tvos-unified-experience.md) beschreef Films en Series als één gridpagina: "Geen grote hero op deze pagina's. Vaste topnav. Een compacte sticky page header. Grid met 6–7 kolommen." Fase 5 heeft dat gebouwd en is daar vrijwel mee klaar. Michel heeft daarna de actuele Netflix TV-interface 2025/2026 als primaire compositiereferentie aangeleverd, en die laat een fundamenteel ander model zien voor het rootniveau van een contentbestemming: row-based discovery waarin focus de compositie verandert, buren zichtbaar blijven en metadata voornamelijk bij het gefocuste item verschijnt. Dat botst frontaal met de gridformulering van 10.2. Het conflict is niet in de presentatielaag op te vangen: het verandert het aantal routes, de betekenis van de fase-5 Definition of Done en de status van negentien bestaande goldens. Het is bovendien vier keer eerder als "fase 5 ziet er niet Netflix-achtig genoeg uit" teruggekomen, terwijl de werkelijke oorzaak was dat twee dragende onderdelen van dat eindbeeld — discovery-projecties en horizontale rootnavigatie — bewust nog niet gebouwd waren.
**Decision:** Films en Series worden **twee niveaus**, geen twee alternatieven.

1. **`Films` / `Series` (root) = discovery landing.** Row-based, focus verandert de compositie, buren blijven zichtbaar, metadata verschijnt voornamelijk bij focus, landscape/wide presentatie waar de artwork dat toelaat. Minimale chrome: **geen** permanente `[Alle bronnen] [Filters] [Sorteren]` boven de eerste rail. Hoofdstuk 10.2a.
2. **`Films ▸ Alles bekijken` / `Series ▸ Alles bekijken` = complete catalogus.** Stabiel 2:3-postergrid, witte focusring met kleine scale en lift, géén expanded landscape-transformatie, volledige filters en sortering. Hoofdstuk 10.2b. Dit is exact wat fase 5 al gebouwd heeft.
3. **"Alles bekijken" is een eerste-klas route**, remote-first bereikbaar — geen minuscuul tekstlinkje.

*Fasegrens.* Fase 5 heet vanaf nu **Unified Complete Catalog** en levert niveau 2. Fase 6 heet **Unified Discovery** en levert niveau 1, plus Home-, Search- en Continue Watching-projecties, `TvDiscoveryRail` en de expanded-focuspresentatie. Discovery-rows komen **uitsluitend** uit de fase-6 projectielaag; een TV-widget mag nooit zelf een pseudo-discoveryhub uit de complete catalogus construeren.

*Fase-5 acceptatie geamendeerd.* De eis is niet langer "fase 5 moet eruitzien als de definitieve Netflix Films-pagina" — met de tweeniveaustructuur is dat de verkeerde eis. De eis is dat All Movies en All Series een uitstekende premium TV-catalogusgrid zijn: mooie posters, goede schaal, witte focus, sterke filtermodal, geen databasegevoel, goede typografie, snelle remote-navigatie. Er volgt **geen** nieuwe fase-5-ontwerpronde.

*Topnavvolgorde.* De Netflix-referentie is leidend voor de compositie: `[profiel] [Zoeken] Home Series Films [Live TV] Mijn Pleya [Pleya]`. **Series staat vóór Films.** De bestaande volgorde in `navigation_tabs.dart` wint hier niet louter omdat hij al gecommit is. Actieve bestemming is een lichte/witte capsule. Live TV verschijnt op capability, maar zijn positie blijft stabiel tijdens een tijdelijke serveroutage.

*Conflictregister 33.6 punt 7 en 8, beide beslist.* Punt 7: geen generieke "Gepland"/"Beschikbaar"-badge in Films/Series; aanvraagstatus blijft op de surfaces met betrouwbare requestdata. Punt 8: geen "Onthoud mijn keuze"-optie; er zijn precies twee contracten — `preferredServerId` (profielbreed, automatische selectie) en last-used title source (alleen picker-initiële focus) — en er komt geen derde bij.
**Consequences:** Hoofdstuk 10 is herschreven naar 10.1 / 10.2a / 10.2b; hoofdstuk 27 fase 5 en 6 zijn hernoemd en uitgebreid; 33.6 punt 7 en 8 staan niet langer op `Open`. Het reeds gebouwde fase-5-werk — `TvUnifiedCatalogScreen`, `TvUnifiedMediaGrid`, `TvUnifiedMediaCard`, filter- en sorteerpanelen, paging, query-preferences, source counts, image-prefetch, focusstabiliteit — behoudt volledig zijn waarde en wordt herbestemd, niet weggegooid: het is precies het gereedschap voor "laat me gewoon mijn 500 films zien". De negentien fase-5-goldens blijven geldig als goldens van de *Alles bekijken*-ervaring. Wat wél verschuift is de betekenis van `tv_movies_screen.dart` en `tv_series_screen.dart`: die zijn vanaf nu de tweedeniveaubestemming, en blijven tot fase 6 rechtstreeks aan de topnav hangen als bewuste tussenstate. Het risico dat deze beslissing draagt is dat fase 6 aanzienlijk groter wordt dan oorspronkelijk begroot — hij draagt nu ook twee volledige landingsschermen en een herbruikbare discovery-rail — en dat de Netflix-achtige eindindruk pas na fase 7 zichtbaar wordt, omdat tot dan de oude zijbalk technisch blijft bestaan. Dat is een tussenstate, geen eindbeeld, en dit besluit legt vast dat dat verwacht gedrag is en geen regressie.


## DEC-065: Visuele north star TV 2026 bevroren — acht referentiebeelden bindend voor fase 6–8

**Date:** 2026-08-30
**Status:** accepted
**Context:** Na DEC-064 is het volledige schermenstelsel als high-fidelity mockups uitgewerkt tegen de echte designtokens (HTML op 1920×1080, headless-Chromium-renders, echt TMDb-artwork) en in meerdere correctierondes door Michel beoordeeld: verticale compositie Home, topnav-positie tegen de Netflix-referentie, raildichtheid, focus-subtiliteit in de grids, de filtercategorie, het merk-lockup. Michel heeft de definitieve set expliciet bevroren ("Bevriezen").
**Decision:** De acht beelden in `docs/assets/tvos-unified/northstar/` (01-home t/m 08-mijn-pleya) zijn de bindende compositie- en hiërarchiereferentie voor fase 6, 7 en 8. Hoofdstuk 33 is ernaar herschreven (33.1–33.8; het conflictregister is hernummerd naar 33.10 en blijft van kracht; de 2025-referentieset is historisch). De beelden dragen daarnaast zes expliciete, goedgekeurde afwijkingen van de eerdere baseline of de huidige implementatie, die anders stilzwijgend zouden blijven:

1. **Topnav:** de cluster (zoekicoon + items) staat horizontaal gecentreerd; profielchip los uiterst links; rechts het **wordmark-lockup** `assets/branding/pleya_wordmark.png` (het P-merk op de positie van de letter P, gevolgd door LEYA) op navhoogte — niet het losse P-icoon met tekst ernaast.
2. **Home:** featured card ~66% van de hoogte (in-page, ~2.4:1) met daaronder alléén de peek van de eerste rij; een aparte focus-state (33.2) waarin de hero wegschuift en de CW-rail zijn volle expanded band met metadata toont.
3. **Landings:** rails uitsluitend in de canonieke providervolgorde met de bestaande i18n-labels (CW eerst wanneer gevuld, dan de aanbevelingsrijen); het gefocuste CW-item draagt de episode-still van de concrete aflevering waar beschikbaar; onderaan de view-all-regel als typografische regel.
4. **Catalogusgrid-focus:** witte ring rond het **artwork alléén**, kleine scale, lift en shadow; de footer krijgt géén fill en géén elevated behandeling. Dit wijkt af van de huidige fase-5-implementatie (ring om kaart+footer met `cardFocusFooterFill`) en wordt als fase-6-polish geïmplementeerd; de betrokken fase-5-goldens verschuiven dan mee.
5. **Filters:** de actieve categorie is een subtiele band met smalle indicatorstreep; wit blijft gereserveerd voor het daadwerkelijk gefocuste control.
6. **Mijn Pleya:** de hoofdstuk-18.1-groepen als tegelrijen met de serverstatus in de header (18.4, authfout in amber); menutegels schalen niet bij focus.

**Consequences:** Fase 6–8-werk wordt visueel geaccepteerd tegen deze beelden; afwijken van de set is een nieuw besluit, geen implementatiedetail. Punt 4 raakt bestaande fase-5-code en -goldens en is daarmee een bewuste, geregistreerde visuele wijziging. De getoonde titels en hun artwork zijn niet bindend; de beelden bevatten echt TMDb-artwork en dienen uitsluitend als interne designreferentie. De HTML-bronnen van de mockups leven buiten de repo; hoofdstuk 33 bevat de maten om ze te reproduceren.


## DEC-066: Search unified projectie TV-only; Home-hero-activatie via de fase-4-coördinator

**Date:** 2026-08-31
**Status:** accepted
**Context:** `lib/services/unified_catalog/search_projection.dart` en `lib/services/unified_catalog/featured_selector.dart` waren gebouwd en grondig unit-getest (hoofdstuk 27 fase 6) maar hadden geen enkele production consumer, waardoor ze de `check-unused-code`/`check-unused-files`-CI-gates rood hielden. Twee wiringvragen vroegen om een expliciet besluit voordat ze production-wired konden worden: (1) `search_projection.dart` raakt `lib/screens/search_screen.dart`, het ene gedeelde zoekscherm voor desktop, mobiel én TV — een wijziging daar heeft potentieel bereik buiten de TV-fase; (2) `featured_selector.dart` voedt de Home-hero, en de huidige hero speelt zijn representative source rechtstreeks af (`navigateToMediaItem(billboard, playDirectly: true)`), wat botst met hoofdstuk 4.4's verbod op een representative-source-shortcut zodra de hero een `UnifiedMediaGroup` representeert.
**Decision:**

1. **Search: unified projectie uitsluitend op de TV-tak.** Binnen de bestaande gedeelde `SearchScreen` vertakt de resultaatpresentatie op `PlatformDetector.isTV()`, net als `discover_screen.dart` dat al doet voor zijn hero. TV rendert `TvDiscoveryRail`-secties (Films/Series/Afleveringen) uit `searchProjection(...)`, geactiveerd via `TvDiscoveryActivationMixin.activateDiscoveryGroup` — dezelfde mixin als de discovery-landings, geen tweede activation-implementatie. Collecties, afspeellijsten en personen blijven source-concreet, zoals hoofdstuk 16.1 al voorschrijft. Desktop en mobiel blijven het bestaande source-concrete resultatenpad gebruiken, ongewijzigd. Unified search op alle platforms is een apart, later productbesluit — niet in deze wiring meegenomen.
2. **Home-hero-activatie loopt voor een featured titel via de fase-4-coördinator.** `TvHomeProjectionProvider` (nieuw, profiel-scoped, sibling van `TvDiscoveryLandingProvider`) re-projecteert `DiscoverProvider.latestMovies` via `HomeProjectionService.projectHubs` en rankt met `FeaturedSelector`; `DiscoverProvider.hubs` vult alleen aan wanneer de primaire pool `FeaturedSelector.maxCount` niet vult. Presentatie blijft ongewijzigd op `DiscoverProvider.latestMovies` leunen (zelfde volgorde, aantal, autorotatie, focusgedrag) — dit is een datalaagwissel, geen redesign. Wanneer het item op het scherm een geprojecteerde featured group is, routeren de Play- en Meer info-pillen voortaan via `TvDiscoveryActivationMixin.activateDiscoveryGroup` (uitgebreid met `intent`/`playDirectly`-parameters) in plaats van de representative source direct af te spelen. Gevolg: een single-source titel gedraagt zich identiek aan vandaag; een multi-source titel toont voortaan de source picker in plaats van stilzwijgend één server te kiezen — een bewuste, gewenste gedragswijziging, geen regressie.
3. **Rowfocus-op-hero-gedrag blijft in fase 6 ongewijzigd** (zie hoofdstuk 27 fase 6/8 DoD, geamendeerd). `_setSpotlightDebounced`/`_tvRailRevealed` in `discover_screen.dart` zitten onder de spotlight-presentatie die fase 8 volledig vervangt; loskoppelen in fase 6 zou tijdelijke code bouwen die één fase later weer verdwijnt. Fase 8's Definition of Done krijgt dit expliciet als eigen sluitpunt.

**Consequences:** `search_projection.dart` en `featured_selector.dart` hebben nu echte production consumers; `check-unused-code`/`check-unused-files` zijn groen zonder suppressie. `lib/providers/tv_home_projection_provider.dart` is nieuw en profiel-scoped naast `TvDiscoveryLandingProvider` in `ProfileSessionScreen`. `lib/screens/tv/tv_discovery_activation_mixin.dart`'s `activateDiscoveryGroup` kreeg twee optionele parameters (`intent`, `playDirectly`), default gelijk aan het bestaande fase-6-gedrag — bestaande callers zijn ongewijzigd. De vier fase-0 Home-focus-baselinetests (`test/screens/discover_screen_test.dart`) blijven ongewijzigd groen. Punt 2's multi-source-picker-gedrag is een zichtbare wijziging op de Home-hero die vóór een eventuele TestFlight-release nog handmatig op een toestel bevestigd moet worden (hoofdstuk 36 sluit geautomatiseerde tests hier niet voor uit, maar hardware-acceptatie blijft apart).


## DEC-067: De TV-hero dedupliceert in fase 6 en toont uitsluitend recente films

**Date:** 2026-08-31
**Status:** accepted
**Context:** [DEC-066](#dec-066) punt 2 liet de hero-*presentatie* bewust op `DiscoverProvider.latestMovies` staan en leverde alleen activatieveiligheid; hoofdstuk 27's fase-6 DoD schoof "geen duplicate hero-slide" daarmee door naar fase 8. Twee dingen bleken daaraan niet houdbaar. Ten eerste is het zichtbaar fout: de lichte cross-serverdedup in `data_aggregation_service.dart` klapt alleen *identieke* guids samen, dus één film die op twee servers onder twee guids staat nam twee rotatieslots — een gebruiker ziet dezelfde titel twee keer langskomen. Ten tweede was het architectonisch fout: de weergavelijst (`_latestMovies`) en de activatie-opzoeklijst (`featuredGroupFor` over de geprojecteerde pool) waren twee verschillende objecten, zodat "welke slide staat er nu" door twee bronnen beantwoord kon worden. Daarnaast beschreef hoofdstuk 9.5 nog een kandidaatketen waarin Top Picks, recent toegevoegde series en hubs de hero aanvulden zodra er te weinig recente films waren. Michel heeft beide punten expliciet beslist.
**Decision:**

1. **Hero-deduplicatie is fase-6-werk, niet fase-8-werk.** `TvHomeProjectionProvider.heroGroups` is de ene geordende hero-lijst en bepaalt drie dingen tegelijk: welke slides bestaan, hun volgorde, en bij welke `UnifiedMediaGroup` iedere zichtbare slide hoort. `discover_screen.dart`'s TV-pad roteert daarover en leest de groep van de slide zelf; `featuredGroupFor` blijft bestaan voor de billboards die géén hero-slide zijn (railfocus, en het on-deck/hub-fallbackitem bij een lege hero). De concrete `MediaItem` die de bestaande hero-widgets krijgen is presentatie — backdrop, clearlogo, titel, metadata — en activeert nooit rechtstreeks.
2. **De hero toont uitsluitend recent uitgebrachte films zolang de gededupliceerde pool niet leeg is.** Deduplicatie mag het aantal slides verkleinen; dat gat wordt niet gevuld met Top Picks, gepersonaliseerde hubs of recent toegevoegde series, en er is geen ondergrens waar naartoe wordt aangevuld. `FeaturedSelector.maxCount` blijft hoofdstuk 9.5's bovengrens van acht — dat is een plafond, geen vulling. Alleen bij een echt lege pool geldt het bestaande fallbackgedrag van `DiscoverScreen` (Continue Watching, dan hubs); er komt geen nieuwe fallbacksemantiek bij. Gemengde hero-kandidaten in fase 8 zouden een nieuw expliciet productbesluit vragen.
3. **`Rowfocus verandert de hero` blijft wél fase-8-werk.** Dat gedrag zit onder de spotlight-presentatie die fase 8 volledig vervangt; de deferral daarvan uit DEC-066 punt 3 blijft ongewijzigd van kracht. Fase 6 verandert de hero-dataset en de activatiegrens, niet de presentatie: geometrie, `_setSpotlightDebounced`, autoplaytiming, paginatie, focus en animatie zijn onaangeraakt, en het phone/desktop-heropad (de `latestMovies`-`PageView`) verandert niet.

**Consequences:** Hoofdstuk 9.5 is herschreven (kandidaatketen vervangen door de exclusiviteitsregel), hoofdstuk 27's fase-6 DoD claimt "geen duplicate hero-slide" nu zelf, en de fase-8 DoD verwijst er alleen nog naar. `featuredCandidates` is vervangen door `heroGroups`; `hasProjectedHero` en `projectedLatestMovies` zijn erbij gekomen om een *authoritatief* lege hero ("elke recente film is ongeschikt") te onderscheiden van een nog niet afgeronde projectie — voor de tweede houdt `DiscoverScreen` de rauwe `latestMovies`-hero aan, zodat het billboard tijdens een koude load niet leegvalt. Een titel waarvan de identity-pijplijn de gelijkheid niet kán bewijzen (twee conflicterende guids, hoofdstuk 11.4) levert één slide met één bron; het verbreden daarvan blijft `resolveMoreSources`' werk op activatiemoment (hoofdstuk 12.8/14.5), niet dat van de hero. Zeven productiepad-tests in `test/screens/discover_screen_tv_hero_test.dart` en de provider-tests dekken dit; drie ervan zijn rood tegen de oude hero.


## DEC-068: De complete-catalogusactie staat naast de paginatitel en is de enige launcher

**Date:** 2026-08-31
**Status:** accepted
**Context:** [DEC-064](#dec-064) punt 3 eiste dat "Alles bekijken" een eerste-klas route is en geen "minuscuul tekstlinkje waar focus moeilijk komt". Drie tvOS-patronen voldoen daaraan: een compacte header-actie, een tegel aan het eind van een rail, of een sectierij onderaan de pagina. Fase 6 koos de derde, met het argument dat een paginabrede rij het enige doel is dat een afstandsbediening zonder mikken raakt: één keer omlaag vanaf de laatste rail, geen horizontale beweging. Dat argument klopte over *mikken* en niet over *afstand*. Het optimaliseerde het pad vanaf de onderkant van de pagina — waar een bladerende gebruiker eindigt — en negeerde het pad vanaf de bovenkant, waar iedere gebruiker begint. Wie Films opent omdat hij al zijn films wil zien moest eerst door elke discovery-rail heen. Een variant met de actie rechtsboven uitgelijnd is ook afgewogen en afgewezen: die ligt ruimtelijk te ver van de natuurlijke focus-entry en kost onnodige horizontale remote-navigatie.
**Decision:**

1. **De actie staat direct naast de paginatitel**, niet rechts uitgelijnd en niet onderaan: `Films   Alle films ›` en `Series   Alle series ›`. Vaste tussenruimte (`TvDiscoveryLayout.pageTitleActionGap`), geen `Spacer` — een lange vertaling schuift de actie iets verder naar buiten in plaats van hem tegen de rechtermarge te parkeren.
2. **Hij is zeer rustig.** Tekstactie met een kleine chevron, secundaire typografie op ongeveer de helft van de titelgrootte, gedempte inkt in rust, volle witte focusbehandeling wanneer gefocust. Geen pill, geen boxed button, geen toolbar-chip, geen Settings-rij. De paginatitel blijft dominant.
3. **De onderste "Alles bekijken"-rij verdwijnt.** Er is nog één primaire route naar de complete catalogus op de landing: minder duplicate chrome, een korter focuspad, duidelijkere spatial navigation, en één canonieke launcher als restauratiedoel.
4. **Focuspad.** De paginatitel zelf is niet focusbaar; de actie wel. Omlaag vanaf de actie landt op de huidige tegel van de eerste rail (`focusCurrent`, niet "de eerste tegel" — wie de rail al gelopen heeft houdt zijn plek). Omhoog vanaf de eerste rail keert terug naar de actie. Boven de header ligt de topnav, en die is fase 7.
5. **Routing en state veranderen niet.** De actie pusht exact de bestaande fase-5-catalogus (`TvMoviesScreen` / `TvSeriesScreen`); geen tweede scherm, provider, catalog engine, query-state, paging of filterset. Er komt ook geen aparte `Ontdekken`-tab bij: de discovery-landing *is* de defaultpagina.

**Consequences:** `TvViewAllAction` is herschreven van een paginabrede rij naar een compacte tekstactie; `title`+`actionLabel` zijn één `label` geworden en de i18n-sleutel `unifiedCatalog.discovery.viewAll` ("Alles bekijken") is uit alle zestien locales verwijderd omdat hij nergens meer gerenderd wordt. `TvDiscoveryLayout` verliest `viewAllRowHeight`, `viewAllTitleFontSize` en `viewAllOutline` en wint `viewAllPaddingVertical` en `pageTitleActionGap`. De landing houdt zijn rails nu ook in een `GlobalKey<TvDiscoveryRailState>` bij, zodat omlaag vanuit de header de eerste rail kan bereiken. Eén bestaande testeigenschap is bewust vervallen: de landing bewaarde een niet-nul scrollpositie over een push+pop heen, en dat kán niet meer wanneer de teruggezette focus in de header ligt — de header in beeld brengen ís scrollen. De test bewijst nu wat er wél geldt: de focus keert terug op de actie, de rail onthoudt zijn eigen tegel, en de pagina staat weer bovenaan. De semantics-labels (`Alle films bekijken` / `Alle series bekijken`, al 16/16) zijn ongewijzigd gebleven; ze zeggen meer dan de zichtbare tekst en dat is precies wat een screenreader nodig heeft.

## DEC-069: De TV-root heeft één geneste-routestapel die géén Navigator is, en Live TV is een onthouden capability

**Date:** 31 augustus 2026
**Status:** Accepted
**Phase:** Fase 7 (TV-root-shell en Mijn Pleya)

**Context.** Fase 7 vervangt op TV de verticale `SideNavigationRail` door een horizontale topnav
(hoofdstuk 6.2). Twee dingen die daar niet in de roadmap stonden bleken tijdens de bouw beslissingen
in plaats van implementatiedetails, en allebei zijn ze het soort keuze dat later opnieuw gemaakt
wordt als er geen reden bij staat.

### 1. Een geneste route binnen een bestemming is een expliciete stapel, geen `Navigator`

Hoofdstuk 6.3 vraagt om "een eigen geneste navigator" voor Mijn Pleya. De voor de hand liggende
lezing — een Flutter `Navigator` in de contentzone — is onjuist, en het kost een halve fase om erachter
te komen waarom.

`Navigator.push` zoekt de *dichtstbijzijnde* navigator. De helft van wat een TV-oppervlak pusht is
media-detail: een kaart in Bibliotheken, in de Kijklijst of in een discovery-rail roept
`navigateToMediaItem` aan. Met een navigator in de shell zou dát detailscherm er ook in gevangen
worden en *onder de topnav* renderen in plaats van full-bleed over de hele shell, zoals het vandaag op
elk ander oppervlak doet. Erger nog: hoofdstuk 7.5 wordt er dubbelzinnig van, want stap 2 (een
geneste Mijn Pleya-route poppen) en stap 3 (een detailroute poppen) zouden dan dezelfde pop op
dezelfde stapel zijn.

Dus nesten is expliciet en opt-in: `TvNestedRoute` op `TvNavigationCoordinator`. Wie binnen de shell
wil blijven pusht er één; al het andere gaat ongewijzigd naar de profielnavigator die
`ProfileSessionScreen` bezit. `media_navigation_helper.dart` hoefde daardoor niet aangeraakt te
worden.

**Gevolg dat wél de roadmap raakt.** De complete catalogus (`Alle films` / `Alle series`) verhuist
van een push op de profielnavigator naar zo'n geneste route. Dat is geen smaakkwestie: de gedeelde
shell van hoofdstuk 33 is **bindend op alle acht** referentiebeelden, en 33.5 en 33.6 tekenen die
pagina's mét de topnav erboven en de bestemming nog steeds opgelicht. Een fullscreen push had dat
onmogelijk gemaakt. De landing eronder blijft gemonteerd (offstage, met `TickerMode` uit), dus terug
kost geen herlaadbeurt (hoofdstuk 24).

Eén stapel voor alle bestemmingen, niet één voor Mijn Pleya en één voor de landings: twee
mechanismen zouden twee backketens en twee antwoorden op "wat staat er open" betekenen.
`tv_my_pleya_navigator.dart` is daarom de routetabel van Mijn Pleya geworden en niet een tweede
stapel.

### 2. Live TV-zichtbaarheid is een onthouden profielcapability, geen pollresultaat

`MultiServerProvider.hasLiveTv` is de uitkomst van `checkLiveTvAvailability()`, en die kan "dit
profiel heeft geen tuner" niet onderscheiden van "de server met de tuner antwoordde net niet": een
offline server komt de lus niet eens in, en een die gooit wordt gevangen en overgeslagen. Op een
verticale balk verdwijnt daardoor een rij; in een horizontale balk schuift Mijn Pleya en alles
ertussen zijwaarts weg onder de duim van de kijker, en de pil waar hij op mikte staat ergens anders.
Hoofdstuk 19 verbiedt dat met zoveel woorden.

De regel is bewust asymmetrisch, omdat het bewijs dat is:

- **Onthouden bij elke waarneming.** Eén bereikbare DVR bewijst de capability.
- **Vergeten alleen bij een sluitende meting.** Een poll die niets vond bewijst niets tenzij élke
  verwachte server online was én antwoordde — de nieuwe
  `MultiServerProvider.lastLiveTvCheckWasConclusive`. Alles daaronder is een uitspraak over het
  netwerk, niet over het profiel.

Opslag volgt `PreferredServerStore`: één `JsonPref`-entry per profielscope, en hij gaat mee met het
profiel als dat verwijderd wordt (hoofdstuk 22). `resolveLiveTvCapability` is een pure functie, omdat
het de productregel is en niet de opslag.

### Sluitingsamendement, 31 augustus 2026 — waar de plek van een geneste route woont

De zin hierboven, "de landing eronder blijft gemonteerd … dus terug kost geen herlaadbeurt", was
waar voor *poppen* en niet voor *van bestemming wisselen*. Alleen de actieve bestemming bouwt zijn
bovenste route, dus naar Series gaan en terugkomen bouwde `Alle films` opnieuw op. Dat kostte twee
dingen die hoofdstuk 7.4, 7.6 en 24 al vastleggen: de geladen pagina's, en de plek van de kijker.
Beide zijn bij het sluiten van fase 7 gerepareerd, en het amendement staat hier omdat het de
consequentie is van precies deze beslissing.

De keuze die eronder ligt is *waar* die plek woont. Elke geneste route mounten van elke bestemming
zou het probleem ook oplossen, en is verworpen: het houdt schermen in leven om state te bewaren die
in één record past, en het is precies de brute-force die deze architectuur elders vermijdt. De plek
gaat dus naar `TvNavigationCoordinator`, die de wissel al overleeft, als hoofdstuk 7.6's
`TvDestinationFocusMemory` — waarmee die memory ook zijn eerste productieconsument krijgt. De
pagina's blijven waar ze al stonden: `UnifiedCatalogProvider` leeft in de profielsubtree boven de
shell, en de enige reden dat een remount hem leegde was dat het scherm bij het opstarten
onvoorwaardelijk `setQuery` riep.

Eén regel volgt hieruit en staat in de code: **alleen een surface die de wissel niet overleeft
schrijft in die memory.** Een bestemmingsroot staat in de `IndexedStack` en bewaart zijn eigen
positie al; twee schrijvers per bestemming zouden twee antwoorden op dezelfde vraag zijn.

**Consequences.** `TvNestedRoute`, `TvNavigationCoordinator` en `TvLiveTvCapabilityStore` zijn nieuw;
`MultiServerProvider` krijgt er één afgeleide vlag bij en notificeert nu ook wanneer een meting
sluitend wórdt — dat ziet eruit alsof er niets gebeurde (geen Live TV ervoor, geen erna) maar het is
het enige moment waarop een onthouden capability met recht ingetrokken mag worden. De
`SideNavigationRail` blijft ongewijzigd de root van desktop; niets aan het niet-TV-pad is verlegd.

## DEC-070: De Home-carousel roteert na inactiviteit, en Home-rijen zijn geen hero-invoer meer

**Date:** 31 augustus 2026
**Status:** Accepted
**Phase:** Fase 8 (Final TV Home Experience)

**Context.** Fase 8 vervangt de fullscreen `TvSpotlightBackground`-home door de afgeronde in-page
carousel van hoofdstuk 33.1. Drie dingen bleken daarbij beslissingen in plaats van
implementatiedetails, en alle drie zijn ze het soort keuze dat later opnieuw gemaakt wordt als er
geen reden bij staat.

### 1. Hoofdstuk 9.6's pauzelijst kan niet letterlijk gelden, en lost dat zelf op

9.6 vraagt om een automatische wissel per acht seconden en somt daarna de toestanden op waarin de
timer gepauzeerd blijft — waaronder "een hero-CTA focus heeft". Letterlijk gelezen is dat een
carousel die nooit draait: hoofdstuk 7.1 legt de rustfocus van Home juist op een hero-CTA
(topnav → hero actions), dus de pauzevoorwaarde is altijd waar. De eerste en de laatste zin van
diezelfde alinea kunnen dan niet allebei waar zijn.

De alinea draagt zijn eigen oplossing: "Na echte inactiviteit mag de carousel hervatten." Dat is
geïmplementeerd, en het is het enige punt waarop van de letterlijke tekst wordt afgeweken:

- iedere interactie — een slidewissel, een druk, aankomen op een CTA — stopt de rotatie en start een
  inactiviteitsvenster van dezelfde acht seconden;
- de rotatie hervat pas als dat venster verstrijkt zonder invoer;
- de toestanden uit 9.6 die *niet* over de handen van de kijker gaan — Home niet actief, app niet op
  de voorgrond, een overlay of source picker open, de feed niet op scrollpositie nul, een contentrij
  met focus — blijven onvoorwaardelijke pauzes, en die rapporteert `TvContentFeed` via één vlag.

**Wat expliciet géén pauzevoorwaarde is: focus op de topnavigatie.** Die zit buiten de feed, en een
kijker die op de balk staat terwijl het billboard doorloopt is precies het geval dat 9.6 beschrijft,
niet een dat het uitsluit. Een eerdere versie gebruikte "heeft de feed focus" als proxy voor "staat
er een overlay overheen"; dat leest als hetzelfde en is het niet. `ModalRoute.isCurrent` beantwoordt
die vraag wél, en is het predicaat dat de oude Home er al voor gebruikte.

Onder Reduce Motion draait de rotatie helemaal niet. Een automatische wissel van het grootste element
op het scherm is precies de beweging waar die instelling om vraagt hem niet te doen; links/rechts
blijft gewoon werken.

### 2. Rijfocus is geen hero-state, en dat is nu architectonisch waar

`TvBrowseRail.onFocusedItemChanged` voedde `DiscoverScreen._setSpotlightDebounced`, en 180 ms na een
D-pad-stap werd het billboard het gefocuste rij-item. Hoofdstuk 7.3 en 31.9 verbieden dat;
[DEC-066](#dec-066) punt 3 en [DEC-067](#dec-067) punt 3 stelden het verwijderen uit tot deze fase.

Het is niet uitgezet maar onmogelijk gemaakt op de plek die telt: de actieve slide is privéstate van
`TvHeroBillboardCarousel`, en die klasse heeft geen setter, geen callback en geen constructorveld
waarmee iets van buiten hem kan verzetten. `initialGroupId` wordt één keer bij mount gelezen; alles
daarna is `_index`, privé.

De precieze formulering is hier belangrijk, want de eerste versie van deze alinea beweerde te veel.
`TvContentRow` heeft wél een parameter die de identiteit van de gefocuste kaart draagt —
`onFocusedGroupChanged`, waarmee `TvDiscoveryRail` bij iedere focuswinst zijn `groupId` doorgeeft.
Die is nodig voor restauratie (hoofdstuk 7.6) en gaat in `TvContentFeed` naar
`_focusedGroupIdByRowId` en nergens anders heen; `_heroGroupId` wordt alleen door de carousel zelf
gevoed. De garantie is dus niet "er is geen parameter met die informatie" maar "de feed geeft hem
niet door, en de carousel zou hem niet kunnen ontvangen" — en die tweede helft is de harde: er is
geen ingang. Beide helften staan onder test.

### 3. De overlaid Home-actiebalk verdwijnt, en twee acties verhuizen mee

De oude TV-home tekende bovenop het billboard een `FocusableActionBar` (verversen, Watch Together,
Pleya Remote, gebruikersmenu). 33.1 tekent tussen de balk en de kaart niets, en hoofdstuk 7.3 zegt
"Up vanaf hero gaat naar de actieve topnavbestemming" — waarmee die balk na fase 8 op geen enkel
focuspad meer ligt. Hij was dus niet zozeer overbodig geworden als wel onbereikbaar.

Weghalen zonder meer zou werkende functies van TV af halen, dus **Watch Together** is een tegel in
Mijn Pleya geworden — de bestemming die hoofdstuk 18 al definieert als alles persoonlijks dat geen
browsen is. Het hergebruikt zijn bestaande scherm; de tegel kreeg één nieuwe ondertitelstring, in
alle zestien locales. Het gebruikersmenu was al gedekt door de profielchip in de topnav en door Mijn
Pleya zelf.

**Pleya Remote is bewust níet meeverhuisd**, en dat is de correctie die een onafhankelijke audit
afdwong. De actie op de balk vertakte op `PlatformDetector.shouldActAsRemoteHost`, en dat predicaat
is op TV waar — de balk opende daar dus de **host**-kant (`RemoteSessionDialog`: koppelstatus,
starten en stoppen), niet de client. Een tegel die `MobileRemoteScreen` opent geeft precies de
omgekeerde rol: een televisie die op zoek gaat naar een ander apparaat om te bedienen. De hostkant
bestaat alleen als dialoog en heeft geen schermvorm om als geneste route te pushen, en die maken is
functionele integratie — fase 9. Liever een geregistreerd gat dan het verkeerde scherm.

**Wat hierdoor vervalt, en waar het geregistreerd staat.** Twee dingen, allebei fase 9:

1. de expliciete verversknop op TV-Home — Home laadt bij mount en bij profielwissel, en hoofdstuk
   7.2 verbiedt uitdrukkelijk een netwerkrefresh bij het opnieuw kiezen van de actieve bestemming,
   dus er is geen plek waar hij vanzelf terugkomt;
2. de Pleya Remote **host**-sessie op TV. De capability zelf blijft aan/uit te zetten
   (`enableCompanionRemoteServer` in de afspeelinstellingen); alleen het statuspaneel is onbereikbaar.

### 4. Twee dingen die de visuele audit terecht rood maakte

Een onafhankelijke read-only visuele audit tegen `01-home.jpg` gaf elf van twaalf punten groen en
twee echte bevindingen, beide gecorrigeerd:

- **De scrim was een L, geen lokale linksonder.** Twee onafhankelijke full-card gradiënten — één
  ondoorzichtig langs de linkerrand, één langs de onderrand — tellen niet op tot "alleen lokaal
  linksonder": hun vereniging donkert de hele linkerkolom tot bovenaan en de hele onderrand tot
  rechts, waardoor de kaart zijn rechteronderhoek in de paginagrond verloor. De leesgradiënt is nu
  een *product* (horizontaal, gemaskeerd op hoogte) met daarnaast een duidelijk zwakkere onderrand
  die alleen de kaartrand in de pagina laat overlopen.
- **De witte `Afspelen`-capsule was grijs tot hij focus had.** `FocusableButton` dimt een
  ongefocuste knop in D-pad-modus naar 60%, wat juist is voor een muur van kaarten en verkeerd voor
  een control waarvan de rustkleur bindend is (33.1: "witte `▶ Afspelen`-capsule"). De knop heeft er
  een `dimWhenUnfocused`-opt-out bij die alleen de twee hero-pillen zetten; de acht andere
  `delegated`-aanroepers zijn byte-identiek gebleven.

Een derde, kleine bevinding: de "long locale"-golden was dood bewijs — slang's vertalingen zijn
deferred en een testbinary laadt alleen de basislocale, dus een Material-`Locale` veranderde niets en
de render was identiek aan `play_focused`. Vervangen door een render met werkelijk lange
fixture-titels en -prosa, die de gereserveerde hoogtes wél op de proef stelt.

**Consequences.** `lib/widgets/tv/tv_content_feed.dart`, `tv_content_row.dart`,
`tv_hero_billboard_carousel.dart`, `tv_hero_billboard_card.dart` en `tv_hero_artwork.dart` zijn
nieuw; `TvHomeLayout` staat naast `TvDiscoveryLayout` in `tv_unified_layout.dart`.
`TvHomeProjectionProvider` kreeg er één getter bij (`latestMovies`, de ongelimiteerde geprojecteerde
"Recent uitgebracht"-rij naast de op acht afgetopte `heroGroups`); `FocusableButton` kreeg er één
parameter bij (`dimWhenUnfocused`, default `true`, zie punt 4). `tv_browse_rail.dart` en
`tv_spotlight_background.dart` blijven bestaan en ongewijzigd: `library_recommended_tab.dart`,
`media_detail_screen.dart` en `seerr_poster_card.dart` gebruiken ze terecht nog. De vier fase-0
Home-focusbaselines uit `test/screens/discover_screen_test.dart` beweren hetzelfde als altijd en
wijzen nu naar de nieuwe knopen. Eén bevinding buiten de fase-8-scope is onderweg meegenomen omdat
Home hem blootlegde: `TvDiscoveryRail` liet RECHTS voorbij de laatste tegel door de geometrische
traversal vallen, die op een gestapelde feed de eerste tegel van de *volgende* rij is — de rij-uiteinden
zijn nu harde stops, ook op de fase-6-landings.

## DEC-071: Bekeken is bekeken, dus markeren geldt voor alle bronnen

**Date:** 1 september 2026
**Status:** Accepted
**Supersedes:** de bronkeuze-zin van hoofdstuk 13.5

**Context.** Hoofdstuk 13.5 schreef voor dat "Markeer als bekeken" eerst om een bron vraagt: één
concrete bron of expliciet "Alle bronnen", met de zin "Geen impliciete mutatie van alle bronnen"
eronder. De code deed dat exact: `markWatched`/`markUnwatched` waren
`UnifiedActionScope.sourceSpecificWithAllSources`, en met twee bereikbare bronnen opende het
scope-paneel.

Die regel botst met de rest van het product. Kijkstatus is juist de ene eigenschap die Pleya al over
bronnen heen samenvoegt: een groep draagt één `UnifiedWatchState`, de kaart tekent één vinkje, en
G4/G5 leiden die staat af uit alle memberships samen. Een vraag "op welke server wil je dit bekeken
zetten?" vraagt dus naar een onderscheid dat nergens anders bestaat, en het antwoord "alleen deze"
levert een titel op die op de muur bekeken heet terwijl een zustermembership het tegendeel zegt. Dat
is geen keuze die de gebruiker maakt, het is een inconsistentie die hij erft.

**Decision.** Markeer bekeken en markeer onbekeken zijn `logical`: ze gelden altijd voor alle
bronnen van de titel en vragen niets. Bekeken is bekeken.

Een bron die op het moment van schrijven niet bereikbaar is wordt vastgehouden in plaats van
overgeslagen: `queuesUnreachableMemberships` geldt nu ook voor deze twee acties, en de onbereikbare
memberships gaan door dezelfde `OfflineWatchProvider`-ingang die offline-modus al gebruikt. De
wachtrij is niet voor deze beslissing verzonnen — de kijkstatuswachtrij draagt `watched`- en
`unwatched`-rijen al en speelt ze al terug bij reconnect, wat G11 aantoont. Zonder dat deel zou
"altijd alle bronnen" een belofte zijn die bij de eerste offline server stilletjes breekt.

**Wat bewust niet mee veranderde.** `rate` blijft `sourceSpecific`. Een cijfer dat naar elke kopie
wordt geschreven is niet vanzelfsprekend wat iemand bedoelt die een film waardeert, en dat is een
productbesluit dat niemand genomen heeft. De watchlist-acties blijven offline geweigerd in plaats van
gewachtrijd (DEC-020): een uitgestelde watchlist-schrijfactie heeft geen merge-regel tegen wat
hetzelfde account ondertussen op plex.tv deed, en kijkstatus heeft die wel.

**Consequences.** `UnifiedActionScope.sourceSpecificWithAllSources` verloor hiermee zijn enige
gebruiker en is **verwijderd**, samen met de hele keten eronder: `allowAllSources` op
`AskForActionScope` en op `TvActionScopePicker`, de `kAllSourcesRowKey`-pseudorij, het sealed
`UnifiedActionScopeChoice`-keuzetype (de picker geeft nu rechtstreeks een `UnifiedMediaSource` terug)
en de strings `tvContextMenu.allSources`, `allSourcesDetail`, `scopeTitleMarkWatched` en
`scopeTitleMarkUnwatched`. De laatste twee waren dezelfde soort dode copy: markeer bekeken/onbekeken
bereikt de scope-picker sinds deze DEC nooit meer, dus een paneeltitel voor die twee kon niemand meer
zien.

Het alternatief was de variant als vocabulaire laten staan zodat een toekomstige actie hem met één
regel kon krijgen. Dat is niet gedaan: een onbereikbare tak met een comment dat uitlegt waarom hij
onbereikbaar is kost een lezer meer dan hij een latere bouwer bespaart, en het herstellen ervan is
geen regel code maar een productbesluit over een specifieke actie — met een eigen DEC, precies zoals
deze er een is. `rate` is nu de enige actie die nog om een bron vraagt, en die vraagt uitsluitend
naar concrete servers.

`_queueDeferred` dispatcht nu per actie in plaats van altijd een Continue Watching-verwijdering weg
te schrijven. De register-rijen G12 en G13 beschrijven na deze DEC een schrijfactie die niet meer
vraagt; hun tests zijn meeverhuisd naar `rate`, dat de vraag wel nog stelt en daarmee de negatieve
controle op de reikwijdte van deze DEC is.

## DEC-072: Spatial D-pad navigation volgt de gerenderde geometrie, niet de logische actievolgorde

**Date:** 1 september 2026
**Status:** Accepted
**Vult aan:** de RTL-paragraaf van hoofdstuk 25 (docs/tvos-unified-experience.md)

**Context.** Hoofdstuk 25 bindt twee dingen die onder een rechts-naar-links-directionality uit elkaar
lopen. De CTA-*volgorde* spiegelt logisch — Afspelen en Meer info wisselen van plek, wat `Row` gratis
doet zodra de `Directionality` omgaat — maar links/rechts voor de *carousel* blijft aan de visuele
richting gekoppeld. Wat het hoofdstuk niet noemde is de focusverplaatsing *tussen* die twee knoppen,
en die liep op lijstpositie: `onNavigateRight` op Afspelen sprong naar Meer info omdat Meer info het
volgende item in de lijst is. Zodra de volgorde spiegelt staat Meer info fysiek links, en landt
Rechts dus op een knop die de kijker links ziet liggen. Dat is bij het sluiten van J7 gevonden en
toen bewust niet zelf beantwoord: het was een ontbrekend productbesluit, geen scenario met vastgelegd
gedrag.

**Decision.** Voor TV en tvOS volgt D-pad Links/Rechts **de visuele geometrie na layout**, niet de
abstracte logische of semantische actievolgorde. Links verplaatst de focus naar de focusbare control
die visueel links ligt, Rechts naar die visueel rechts ligt — ook onder RTL.

Semantics en focus zijn daarmee expliciet twee verschillende contracten. RTL mag tekstalignment
spiegelen, de lees- en semantische volgorde aanpassen, en de CTA-compositie visueel spiegelen waar
hoofdstuk 25 dat voorschrijft. Wat het níet mag is de logische volgorde op de richtingstoetsen
leggen, want een afstandsbediening is een fysiek apparaat: de kijker drukt naar de knop die hij
daar ziet liggen, en een pijl die de andere kant op springt voelt kapot, hoe correct de leesvolgorde
er ook onder ligt.

**Wat hier niet onder valt.** Dit gaat uitsluitend over focus traversal tussen focusbare
CTA-controls. De carouselrichting, de slidevolgorde, de artworkrichting, de autoplay en de
CTA-semantiek blijven precies zoals ze contractueel vastliggen; dit is geen bredere RTL-herziening.
De carouselclausule verandert er ook niet door: Links vanaf de linkerrand van de rij blijft de vorige
slide en Rechts vanaf de rechterrand de volgende, in beide richtingen. Alleen wélke knop op die rand
ligt verschilt, en dat volgde altijd al uit de layout.

**Consequences.** Eén autoriteit, niet twee. `_actions` in `tv_hero_billboard_carousel.dart` leest de
`Directionality` in de subtree van de rij zelf — dezelfde die de pillen positioneert — en leidt daar
de linker- en rechterbuur uit af (`_stepFrom`). Twee onafhankelijke hardgecodeerde RTL-tabellen naast
elkaar zouden opnieuw uit elkaar kunnen lopen; de gerenderde volgorde is al beschikbaar en is dus de
bron. Vastgelegd in test/widgets/tv/tv_rtl_contract_test.dart met een echte `Directionality`-override
(geen locale nodig, en Pleya heeft er ook geen), en registerrij J17 draagt het bewijs. Twee van die
tests dekken de verkeerde soort fix af: wie de focusnodes verwisselt in plaats van de bedrading breekt
de binding tussen label en control, en die binding wordt apart geassert.


## DEC-073: De TV-shellkeuze is niet schakelbaar, en dat wordt bewaakt in plaats van aangenomen

**Date:** 2026-09-01
**Status:** accepted
**Context:** Fase 0 van Pleya Unified TV 2026 zette `DevFlags.tvUnifiedExperience` neer als
debug-only ontwikkelpoort ([DEC-063](#dec-063)), zodat de nieuwe shell lokaal aan kon terwijl hij
gebouwd werd. Hoofdstuk 32 van [docs/tvos-unified-experience.md](tvos-unified-experience.md) eist dat
die poort vóór productie weg is, en hoofdstuk 30 noemt als stopcriterium voor het risico *permanent
dubbele architectuur*: "releasebuild bevat nog een eindgebruikersschakelaar tussen beide shells".

Bij het openen van fase 10A was de poort al feitelijk dood — niets buiten zijn eigen rij in de
Debug-sectie van Instellingen las hem nog, want `MainScreen` kiest sinds fase 7 de TV-shell
onvoorwaardelijk op een TV. Dood is echter niet hetzelfde als weg, en "weg" is niet hetzelfde als
"blijft weg".

**Decision:**

1. **De poort is verwijderd**, inclusief `lib/config/` als geheel: `dev_flags.dart` was het enige
   bestand erin.
2. **Er is precies één rootnavigatie-autoriteit op TV**, en de volgorde in `MainScreen._buildContent`
   is het mechanisme: de TV-tak wordt vóór de zijbalktak beslist. Dat is geen stijlkeuze maar een
   noodzaak, want een TV is óók een `shouldUseSideNavigation`-oppervlak — dat was hij tot fase 7 — dus
   de twee takken overlappen echt.
3. **Beide punten worden bewaakt**, niet aangenomen, in
   `test/architecture/tv_shell_single_authority_test.dart`: brononderzoek voor de poort en de
   schakelaar, en een gedragstest voor de tak-volgorde. Die tweede helft draagt een expliciete
   negatieve controle — als een TV ooit ophoudt een zijbalkoppervlak te zijn, wordt de
   volgorde-assertie zinloos, en dan hoort die controle om te vallen in plaats van stilzwijgend groen
   te blijven.

**Consequences.** Een heringevoerde poort, een nieuwe schakelaar in Instellingen, of een omgedraaide
takvolgorde faalt vanaf nu in de testsuite in plaats van pas op een releasebuild op een echte Apple
TV. De Debug-sectie zelf blijft bestaan (Test Sentry, Test ANR); wat verdwijnt is uitsluitend de
shellschakelaar. DEC-063 blijft `accepted` en wordt niet gesuperseded: dit is de afsluiting van een
tijdelijk middel dat DEC-063 zelf al als tijdelijk aankondigde, geen herziening van een besluit.


## DEC-074: Op het lichte thema krijgt het woordmerk donkere letters, en de P-mark blijft rood

**Date:** 2026-09-02
**Status:** accepted
**Context:** Registerrij J18 stond sinds fase 10A op klasse C. De TV-topnav tekent
`assets/branding/pleya_wordmark.png` ongewijzigd op de themakleur, en dat bestand draagt twee kleuren
tegelijk: de rode P-mark en witte "LEYA"-letters. De balk schildert zelf niets en staat op de
paginagrond van `TvRootShell`, die op het lichte palet uitkomt op ongeveer `#F2F2F3`. Gemeten staan de
witte letters daar op **1,12:1** — ze zijn er niet — terwijl de rode P op 4,23:1 blijft staan.

Hoofdstuk 8.2 vraagt op dat oppervlak twee dingen die op één asset uit elkaar lopen: "licht thema
krijgt ... donkere tekst", én Pleya-rood voor "subtiele branddetails". Geen enkel hoofdstuk, DEC of
north-starbeeld besliste hoe een tweekleurig lockup daar getekend hoort te worden; alle acht
referentiebeelden van hoofdstuk 33 zijn donker. Fase 10A heeft de rij daarom geclassificeerd in plaats
van hem zelf in te vullen.

Het is bovendien gewoon bereikbaar: `_buildAppearanceTile()` hangt zonder `!PlatformDetector.isTV()`
in het instellingenscherm — anders dan de tegels eromheen — en het thema volgt onder `system` ook nog
de appearance van het toestel.

**Decision:**

1. **De letters volgen de inkt van het thema** (`MonoTokens.text`), **de P-mark blijft Pleya-rood** op
   elk oppervlak. De letters zijn belettering en gedragen zich als de rest van de tekst in de balk; de
   mark is het merk en beweegt niet mee. Op licht komen de letters daarmee op 16,88:1.
2. **De splitsing zit in het asset, niet in een filter en niet in een marge.**
   `scripts/gen_brand_assets.py` schrijft twee lagen uit dezelfde handgemaakte bron, allebei op het
   **volledige bronkanvas** met de andere helft leeg. In één rect getekend zijn ze samen pixel voor
   pixel het origineel. De handgemaakte `pleya_wordmark.png` blijft de enige bron van waarheid; er komt
   geen tweede met de hand gemaakte variant bij.
3. **Alleen het lichte thema vorkt.** Donker en OLED blijven het onverdeelde bestand tekenen. De
   letters dragen compressieruis — zo'n vijftienduizend ondoorzichtige pixels staan op 253-255 in
   plaats van zuiver wit — dus ze op donker naar zuiver wit hertinten zou duizenden pixels onmerkbaar
   verschuiven en drieëntwintig donkere goldens ongeldig maken. Dat is veel ruis om een verandering
   vast te leggen die niemand ziet.
4. **De introsplash blijft buiten scope.** `intro_splash.dart` tekent hetzelfde bestand op een
   permanent zwarte ondergrond, waar witte letters juist goed zijn.

**Geamendeerd op 2 september 2026 — het lockup wordt samengesteld, en de vork vervalt.**

Bij het nakijken van het eerste lichte beeld bleek de P in `pleya_wordmark.png` een *oudere tekening*
dan `pleya_mark.png`: een dichte donkere binnenvorm en flauwe rode snelheidslijnen, tegenover een open
binnenvorm en amberkleurige lijnen. Omdat `lockup()` uit dat handgemaakte bestand werd opgebouwd, droeg
alles wat daaruit volgt die oude P mee — het tvOS-app-icoon, alle drie de Top Shelf-beelden, de Android
TV-banner en het OG-beeld van de site — terwijl de iOS-, macOS-, Android- en Linux-iconen via
`mark_canvas` de huidige droegen. Eén merk, twee P's, en niets dat ze bij elkaar hield.

Dat verandert twee dingen aan het besluit hierboven:

5. **Het lockup is een product van de generator, geen bewaard bestand.** `pleya_wordmark.png` wordt
   samengesteld uit `pleya_mark.png` plus `pleya_lettering.png` (de belettering, wat er van het
   handwerk overblijft). De mark bestaat daarmee nog op één plek en kan niet opnieuw los van zichzelf
   verouderen. De verhoudingen van het oude lockup blijven — dezelfde cap-height, dezelfde
   tussenruimte van 20px, dezelfde verticale uitlijning — en de huidige mark wordt *niet* platgedrukt
   om binnen de oude kanvasbreedte te passen: die groeit mee van 1452 naar 1516.
6. **De vork uit punt 3 vervalt.** Die bestond alleen om de donkere goldens byte-identiek te houden,
   en de merkverversing verandert die goldens sowieso. Er is dus nog één pad: [PleyaWordmark] tekent
   altijd de twee lagen, de merklaag houdt altijd zijn eigen kleuren, en de belettering krijgt de inkt
   die de aanroeper meegeeft. Licht en donker verschillen nog uitsluitend in wélke inkt dat is.

Wat daarbij *niet* verandert: "één codepad" betekent niet dat het hele lockup naar de themakleur gaat.
De merklaag wordt nooit hertint. De topbar en de introsplash zijn twee gebruiksmodi van dezelfde
compositie — de eerste geeft de themakleur mee, de tweede geen, omdat die op een permanent zwarte
ondergrond staat en de belettering daar zijn eigen wit hoort te houden.

Dat de huidige mark een *doorzichtige* binnenvorm heeft in plaats van een dichtgeschilderde is
overigens precies waarom hij op een themavlak werkt: de ondergrond schijnt erdoor. De oude zou ook na
deze fix nog als donkere vlek op het lichte palet hebben gestaan.

**Consequences.** Twee gegenereerde assets erbij onder `assets/branding/`, zonder pubspec-wijziging —
die map staat als geheel aangegeven. J18 gaat van klasse C naar `covered`. De splitskolom wordt in het
script *afgeleid* en niet vastgezet: raken de twee kleuren in een toekomstige bron verstrengeld, dan
klapt de generator eruit in plaats van er stil middendoor te snijden. De assetinvarianten staan in
`test/assets/brand_wordmark_layers_test.dart`, omdat de gevaarlijkste faalwijze — een laag die op zijn
eigen alpha-bbox gecropt wordt, een andere aspect ratio krijgt en het lockup uit elkaar laat schuiven —
door geen enkele widgettest of golden wordt gezien. `_Wordmark` blijft privé in
`lib/widgets/pleya_wordmark.dart` als gedeelde widget, met een bronbewaking zoals `PleyaLogo` die heeft:
geen enkel ander bestand in `lib/` mag een lockup-asset noemen, zodat er één plek blijft die weet hoe
het merk getekend wordt. Consumenten geven een bedoelde *hoogte* mee en nooit een breedte — het kanvas
is met deze verandering breder geworden, en een aanroeper die een breedte had vastgezet zou het lockup
stilzwijgend hebben ingedrukt of afgesneden.

## DEC-075: Een cijfer geldt voor de titel, niet voor de kopie

**Date:** 2 september 2026
**Status:** Accepted
**Supersedes:** de alinea "Wat bewust niet mee veranderde" van [DEC-071](#dec-071), voor zover die
over `rate` gaat
**PARTIAL supersede van [DEC-063](#dec-063), uitsluitend punt 6**, en dan alleen de opsomming van
welke acties brongebonden zijn

**Context.** Na DEC-071 was `rate` de laatste actie met een bronvraag. Met twee bereikbare servers
opende het scope-paneel "Rate on", de gebruiker koos er één, en de andere kopie hield het cijfer dat
er stond. Op de detailpagina en in het telefoonmenu werd niet eens gevraagd: daar landde het cijfer
stil op de bron waar die pagina toevallig aan gebonden was.

Dat is dezelfde incoherentie die DEC-071 uit de kijkstatus haalde, één laag dieper. Dezelfde film op
twee servers had twee verschillende cijfers, en welk cijfer je zag hing af van welke kaart je opende.
DEC-071's eigen redenering hiervoor was dat "een cijfer op elke kopie schrijven niet vanzelfsprekend
is wat iemand bedoelt, en dat is een productbesluit dat niemand genomen heeft". Dat besluit is nu wel
genomen, en het luidt: waarderen doe je een film, niet een bestand.

**Decision.** `rate` is `logical`. Eén handeling in de waarderingssheet schrijft het cijfer naar elke
bereikbare membership van de titel, vanaf elk oppervlak waar je kunt waarderen: het TV-contextmenu en
de detailpagina. Het telefoonmenu ligt op dezelfde naad maar krijgt zijn zusterbronnen alleen als het
oppervlak eromheen ze kent, wat vandaag nergens zo is.

**De grenzen, expliciet.**

1. **Geen wachtrij.** De offline-wachtrij kent de actietypes progress, watched, unwatched en
   removed-from-Continue-Watching, en geen van die rijen draagt een waarde. Een cijfer heeft daar dus
   geen plek, en er een schema voor bouwen is afgewezen. Een bron die op het moment van schrijven
   onbereikbaar is wordt daarom **gemeld, niet vastgehouden**: hij telt mee in de noemer ("Gelukt op
   1 van 2 bronnen") en daar houdt het op.
2. **De afbeelding naar Jellyfin is lossy, en niet alleen in precisie.** Jellyfin kent alleen
   like/dislike, dus 7/10 wordt daar een like. Opent iemand later de sheet gebonden aan die
   Jellyfin-bron en tikt hij hem aan, dan schrijft de sheet 10.0, en die 10 reist via deze
   beslissing terug naar Plex over de 7 heen. Een gemengde groep schuift dus richting 10 of 0 bij
   elke bewerking vanaf een binaire bron. Dat is bewust geaccepteerd en niet weggeregeld: een
   merge-regel die een binaire bron een numerieke zusterwaarde laat behouden is een eigen
   productbesluit met een eigen DEC. Wat er wél tegen gedaan is: het TV-menu bindt de sheet bij
   voorkeur aan een bron die een getal bewaart, zodat het pad zeldzaam wordt.
3. **De belofte geldt in de servers, niet in de interface.** `UnifiedMediaGroup` draagt een
   `watchState` en geen ratingtegenhanger; geen kaart tekent een samengevoegd cijfer. Wie een titel
   op 7 zet en daarna de Jellyfin-kopie opent ziet een duimpje, niet een 7. Het cijfer is overal
   geschreven en nergens samengevoegd getoond. Een `UnifiedRatingState` is de vervolgstap en staat
   hier als bekende beperking, niet als iets wat deze DEC oplost.

**Wat de partiële supersede van DEC-063 punt 6 precies raakt.** Punt 6 citeert hoofdstuk 4.6
woordelijk, inclusief "en de expliciete 'Alle bronnen'-optie bij Markeer bekeken", en sluit af met de
regel dat een latere fase die een van deze punten wil heropenen een nieuw ADR nodig heeft en geen
stille afwijking in code of plan. 4.6 aanpassen zonder deze paragraaf zou precies die stille
afwijking zijn. Wat verandert is de opsomming: markeer bekeken/onbekeken (sinds DEC-071) en rate
(sinds deze DEC) staan niet meer in de brongebonden lijst. Het **principe** van punt 6 wordt
bevestigd, niet heropend: een mutatie mag nog steeds nooit per ongeluk op de verkeerde bron landen.
Overal waarderen is geen ongeluk maar een breder expliciet groepscontract, dezelfde vorm die
hoofdstuk 13.4 en 13.5 al hebben. Afspelen, details, metadata-refresh en verwijderen blijven
onveranderd brongebonden, en de tie-break van 4.7 blijft woord voor woord staan.

Deze DEC ruimt daarbij het restant van DEC-071 op. Die veranderde de inhoud van 4.6 wel maar de tekst
niet, waardoor hoofdstuk 23 markeer bekeken/onbekeken tot vandaag onder "Acties die bronkeuze
vereisen" bleef zetten. Beide verouderde formuleringen zijn nu weg.

**Consequences.** `UnifiedActionScope` had nog één waarde over en is **verwijderd**, samen met de
`scope`-getter, `ApplyActionToSource` (inclusief de `chosen`-vlag), `AskForActionScope`,
`TvActionScopePicker`, `_askForActionScope`, `_scopeTitleFor`, `_ScopeSession` en de string
`tvContextMenu.scopeTitleRate`. Dat is dezelfde afweging die DEC-071 maakte en met dezelfde uitkomst:
een enum met één waarde is een switch die altijd dezelfde kant op gaat, en een onbereikbare tak met
een comment erboven kost een lezer meer dan hij een latere bouwer bespaart. `resolveUnifiedActionTarget`
geeft nu altijd een `ApplyActionToAllSources`.

Nieuw is `ApplyActionToAllSources.unreachableSources`: de spiegelvorm van `deferredSources` voor een
actie zonder wachtrij. Precies één van de twee lijsten is ooit gevuld, en ze delen de noemer, want
dat is het deel dat de gebruiker leest.

De fan-out zelf staat in `RatingMirror` (`lib/services/rating_actions.dart`) en niet op
`WatchActions`, waarvan de eigen doc vier taken opsomt die rating geen van alle heeft. Twee dingen
daarin zijn niet cosmetisch. `RatingBottomSheet` kreeg een tweede callback,
`onServerRatingWritten`, omdat de bestaande `onServerRatingChanged` de wis-sentinel `-1` naar `0`
plat voor weergave: die waarde spiegelen zou elk "wis mijn cijfer" veranderd hebben in een 0/10 op
elke andere server. En de mirror lost zijn clients op bij constructie, niet bij het schrijven, omdat
de sheet een openstaand cijfer flusht vanuit `dispose()` — de laatste schrijfactie van een handeling
gebeurt nadat de context weg is.

Meegenomen, en onafhankelijk van deze beslissing een echte bug: het telefoonmenu waardeerde via
`getMediaClientWithFallback`, die terugvalt op de eerste online server. Plex-ratingsleutels zijn per
server unieke integers, dus een item waarvan de server was weggevallen schreef een cijfer op een
willekeurige andere titel elders. Stil, permanent en onzichtbaar, oftewel precies het faalgeval
waartegen `tv_unified_context_actions.dart` geschreven is. Dat pad gebruikt nu de strikte lookup en
weigert als die niets oplevert.

Ten slotte is `unifiedActionOutcomeMessage` verhuisd naar `lib/services/unified_action_outcome.dart`.
De regel is geen TV-regel meer zodra de detailpagina hem gebruikt, en een detailpagina die een
TV-contextmenu importeert om aan een string te komen is hoe zo'n helper een tweede keer gekopieerd
wordt.

## DEC-076: Een backend-badge is een bronglyph, en neemt de inkt van zijn regel

**Date:** 2026-09-02
**Status:** accepted
**Verhoudt zich tot [DEC-074](#dec-074):** die gaat over het lockup dat de app zichzelf noemt, deze
over de glyph die een bron noemt. Geen supersede; de grens tussen de twee staat hieronder.

**Context.** Registerrij J19 kwam uit het J18-werk en is toen bewust blijven liggen: `BackendBadge`
tekent vier glyphs uit één `switch`, en drie ervan nemen de inkt van de regel waar ze in staan. De
Plex-chevron en de Jellyfin-mark zijn `currentColor`-SVG's die hun tint via `SvgTheme` krijgen, de
lokale map is een `Icon` met `color:`. De Pleya-P was de enige tak die de `tint` liet liggen, terwijl
het doccommentaar van de widget zelf belooft dat `color` gehonoreerd wordt en vijf van de achttien
callsites er een meegeven — `MediaCard`'s metadataregel geeft gedempte inkt op 60% alpha mee,
`side_navigation_rail.dart` geeft `textMuted`.

Er stond geen productbesluit onder. Hoofdstuk 8.2 noemt Pleya-rood voor "badges", maar dat gaat over
de TV-oppervlakken, en juist daar komt deze widget niet voor: hoofdstuk 10.3 zegt over de kaart
letterlijk "geen serverlogo's op de poster", en de multi-sourcebadge die er wél staat is een donkere
capsule met witte tekst. `BackendBadge` leeft buiten de TV-shell — in de bibliotheeklijsten, de
profiel- en verbindingsschermen, de waarderingssheet, `MediaCard`'s metadataregel en de zijbalk.

**Decision.**

1. **Alle vier de takken nemen de inkt van hun regel**, de Pleya-P dus ook, getint via
   `BlendMode.srcIn` zodat de alpha van die inkt overeind blijft. Het onderscheid is niet "PNG versus
   SVG" maar wat de glyph zegt: een merk dat zegt *deze app is Pleya* houdt zijn kleur, een glyph die
   zegt *dit item komt van een Pleya-server* is bronnotatie en gedraagt zich als de tekst ernaast.
2. **De grens ligt bij de widget, niet bij het asset.** `PleyaLogo` heeft geen kleurparameter en
   houdt merkrood; `BackendBadge` heeft er wel een en honoreert hem. `side_navigation_rail.dart`
   toont allebei de regels in één scherm: een rode `PleyaLogo` in de kop, een gedempte badge in de
   serverrijen eronder. `PleyaWordmark` trekt dezelfde grens sinds de merkverversing van diezelfde
   dag, alleen binnen één widget: de merklaag houdt zijn eigen kleuren, de belettering krijgt de inkt
   die de aanroeper meegeeft.
3. **De set is de eenheid, niet de tak.** `MediaBackend.local` is een kale Material-map en kan nooit
   iets anders dan inkt dragen; de twee SVG's zijn als `currentColor` getekend, dus Plex-amber en
   Jellyfin-blauw waren hier allang opgegeven. Eén glyph die daar wél kleur voert leest op 10 tot
   28 pixels niet als merk maar als toestand — rood is in dit thema progress en actief.

**Wat er in dezelfde drie regels nog mis bleek, en waarom het meeging.** De badge tekende
`assets/branding/pleya_mark.png`, de handgemaakte bron, en niet het gegenereerde
`assets/branding/pleya_logo.png`. De alpha-bbox van die bron is (39, 128, 931, 938) op een kanvas van
1024x1024: de P vult er 87% van de breedte en 79% van de hoogte van, en zijn midden ligt 27 pixels
naar links en 22 pixels omlaag ten opzichte van het kanvasmidden. In een `size x size`-doos naast
twee SVG's die hun viewBox vullen tekende de Pleya-badge dus kleiner en scheef naast zijn buren. Dat
vraagt geen productbesluit — niemand pleit voor een badge die kleiner is dan de rest — dus het is een
gebrek en geen klasse-C-rij, en het zat in precies de regels die deze DEC toch aanraakt. Het
gegenereerde bestand is gecentreerd en vult 95% van zijn breedte, en staat al in de image-cache omdat
`PleyaLogo` het tekent: de badge trok er tot nu toe een tweede decode van 1024x1024 bij voor een
glyph van twaalf pixels.

**Consequences.** J19 gaat van klasse C naar `covered`. Geen asset gewijzigd, geen generator
aangeraakt, `pubspec.yaml` ongemoeid. Het bewijs staat op drie plekken, omdat geen van de drie de
andere twee kan zien: `test/widgets/backend_badge_test.dart` toetst over álle vier de `MediaBackend`-
waarden tegelijk, zodat een vijfde backend die zonder tint wordt toegevoegd hier ook omvalt;
`test/assets/brand_logo_asset_test.dart` bewaakt op de bytes dat de mark vierkant, gecentreerd en
gevuld blijft, want een `Image` rapporteert de doos die hij kreeg en niet wat hij erin tekent; en
`test/goldens/backend_badge_golden_test.dart` legt op beide paletten vast dat de inkt ook echt
aankomt, want een verkeerde blend mode is een gevuld vierkant en dat is in geen van de andere twee
tests zichtbaar. Negatieve controle gedraaid: met de oude tak terug vallen precies de vijf
Pleya-tests en allebei de goldens om, terwijl de dertien tests van de andere drie backends groen
blijven — inclusief "vult dezelfde doos als de andere drie", wat precies aantoont waarom de
assetinvarianten er los naast moeten staan. Daar zijn na de gate drie tests bij gekomen die de
grens van punt 2 van deze beslissing vastpinnen in plaats van hem alleen op te schrijven: dat de
badge dezelfde cachesleutel gebruikt als `PleyaLogo` (wat "geen tweede decode" werkelijk betekent),
dat `PleyaLogo` zelf ongetint tekent, en dat de badge zijn doos ook boven de assetresolutie vult.

**Wat de post-merge gate er nog uit haalde.** Twee dingen, allebei onzichtbaar in de eerste ronde.

`pleya_logo_test.dart` draagt een bronbewaker: het assetpad mag alleen in `pleya_logo.dart` staan,
zodat elke callsite door de widget gaat en het no-clip/no-fill-contract dekt. Deze beslissing maakt
`BackendBadge` een tweede tekenaar, en de bewaker wist dat niet — canonical stond daardoor rood op
precies één test. Opgelost in `61952a6`: de bewaker kent de badge bij naam, met het besluit erbij,
zodat een derde rauwe callsite nog steeds omvalt. Een tweede tekenaar is hier dus expliciet toegestaan
en een derde is een merkbeslissing, geen refactor.

En de badge stond op `Image`'s standaard `BoxFit.scaleDown`, die verkleint maar nooit vergroot. Boven
de 512 pixels van het asset zou de P stoppen met groeien terwijl de twee SVG's hun doos wel bleven
vullen, en dan valt de set juist uiteen op de maten waar hij het meest opvalt. Nu expliciet
`BoxFit.contain`, zoals `PleyaLogo` zelf al deed. De doos-test ziet dat niet: een `Image` rapporteert
de doos die hij kreeg en niet wat hij erin tekent, en dat is dezelfde reden waarom de assetinvarianten
er los naast staan.

Wat hier bewust buiten blijft: de introsplash, `about_screen`, `auth_screen`, `discover_screen` en de
zijbalkkop tekenen de P via `PleyaLogo` en veranderen niet. En de merkkleur is niet uit de app
verdwenen: hij staat nog waar hij hoort, in het lockup en in progress.

**Eén bekend gevolg dat hier níet wordt opgelost.** `pleya_mark.png` was de laatste callsite van dat
bestand; het is nu alleen nog invoer voor `gen_brand_assets.py`, terwijl `pubspec.yaml`
`assets/branding/` als hele map aangeeft en de app die 1,3 MB dus blijft meenemen. Er losse
bestandsregels van maken zou dat terugwinnen, maar ruilt een megabyte in voor een klasse fouten die
pas bij het uitvoeren opvalt: een asset die niet in de lijst staat, ontbreekt in de bundel. Dat is een
eigen afweging over de hele map — `pleya_wordmark.png` is met dezelfde redenering een bronbestand dat
de topnav op donker wél tekent — en hoort niet in een badge-besluit thuis.


## DEC-077: Het ident is het lockup op de paginagrond, en niets anders

**Date:** 2026-09-02
**Status:** accepted
**Context:** Bij het nakijken van de merkverversing ([DEC-074], amendement) vroeg Michel of de intro
ook beter bij het nieuwe ontwerp kon passen. De trace liet drie merkmomenten achter elkaar zien die
het niet met elkaar eens waren: de tvOS-launch (zwart), daaroverheen het `IntroGate`-ident (zuiver
zwart, 2800 ms, een roterende waaier van veertien rode lichtstralen, een 5x-inslag met overshoot, een
glansveeg, een rechthoekige rode gloed, het lockup, een tagline), en daaronder de bootsplash van
`SetupScreen` (warme radiale `#26100D`, een ademende rode halo, de losse P-mark plus "PLEYA" als
gespatieerde tekst, dezelfde tagline op een andere spec, een voortgangsbalk). Drie gronden, twee
logo-vormen, twee taglines. De cross-dissolve op 88% van het ident was de zichtbare naad.

De bron van het ident noemde zichzelf "Netflix-style ident". Hoofdstuk 31 #10 verbiedt precies dat.
Hoofdstuk 8.4 en 24.1 sluiten doorlopend schalen uit, hoofdstuk 34 houdt rood van vlakvullingen, en
in de bevroren north star ([DEC-065]) komt dit register nergens voor: `#141414`, geen blur, geen
grading, terughoudende beweging, dissolves in plaats van transities.

**Decision:**

1. **Eén grond.** Het ident speelt op de paginagrond — `bg` van het donkere of OLED-palet, en op
   het lichte thema alsnog `#141414`, want het ident is geen themavlak. Daarmee blijft de grond
   permanent donker en blijft [DEC-074]'s "geen inktoverride" kloppen, én lost het ident op in een
   pagina van dezelfde kleur in plaats van een stap uit zwart te maken.
2. **De filmische laag verdwijnt**: de lichtstralen, de glansveeg, de rechthoekige gloed, de inslag
   en de doorlopende push. Wat overblijft is het lockup dat zich zet (0,96 naar 1,0 op de focuscurve,
   onder de 1,05 die de app als grootste schaal kent), even staat, en oplost. In en uit duren elk 460
   ms — de hero-crossfade, die "als een dissolve leest en niet als een transitie". De hele run duurt
   1800 ms in plaats van 2800.
3. **De tagline volgt de spec van de generator.** `lockup(tagline=True)` legt hem al vast voor de Top
   Shelf, de TV-banner en het OG-beeld: Inter Medium, 12% van de lockuphoogte, tracking 0,30 maal de
   grootte, tussenruimte 12%, wit op 0,40. `PleyaBrandLockup` tekent exact dat, dus het ident op het
   scherm is hetzelfde beeld als op de shelf.
4. **De bootsplash wordt hetzelfde beeld.** `SetupScreen` tekent dezelfde grond en hetzelfde
   `PleyaBrandLockup`, met alleen de voortgangslijn en de serverstatus erbij. Zodra het ident oplost
   ligt eronder hetzelfde plaatje; de naad is weg. De ademende halo, de warme radiale en de losse P
   met gespatieerde tekst vervallen.
5. **Wat meeliep omdat het gebreken waren, geen ontwerp**: de twee lockuplagen worden vooraf
   gedecodeerd (de eerste frames toonden anders een lege grond); Select, Enter, Escape en spatie
   slaan het ident over, want een afstandsbediening heeft geen tik en een TV-kijker moest de volle
   2800 ms uitzitten; en het ident heeft nu tests en twee goldens, waar het er nul had.

**Wat niet verandert.** Het ident speelt één keer per proces, is over te slaan, en wordt overgeslagen
onder Reduce Motion en op de gereduceerde prestatietier — met de bestaande uitzondering voor Apple
TV, waar de engine de vlag verkeerd rapporteert. De merklaag wordt nergens hertint; het ident en de
topbar zijn twee gebruiksmodi van dezelfde compositie ([DEC-074]).

**Consequences.** `_LightRaysPainter` en `GradientTranslation` zijn weg. `SetupScreen` verliest zijn
`AnimationController` en de ticker-mixin. `PleyaBrandLockup` en `identGround` staan in
`lib/widgets/pleya_wordmark.dart` naast `PleyaWordmark`, zodat er één plek is die weet hoe het merk
op een groot vlak staat. Een latere wens voor méér beweging in het ident is een nieuw besluit tegen
hoofdstuk 8.4, geen aanpassing van een constante.

## DEC-078: Een mislukt afspelen zegt wat er mis is, en de melding gaat vanzelf weg

**Date:** 2026-09-02
**Status:** accepted
**Context:** Staat de externe schijf van de server na een herstart niet gemount, dan levert Plex de
metadata en de part-key gewoon uit, maar is het bestand er niet. De speler bouwde daar een URL van,
mpv kreeg een 404 en de gebruiker las "Afspelen gestopt", zonder tekst eronder. Dat is de enige
uitkomst waar de gebruiker niets aan heeft: de server is bereikbaar, de titel bestaat, het bestand
niet, en dat laatste is precies wat de melding verzweeg.

Twee dingen werkten daarbij tegen elkaar. Plex vertelt met `checkFiles=1` per part of hij het bestand
kan lezen, en `MediaPart.isPlayable` legde dat al vast — maar het werd alleen gebruikt om een betere
versie te kiezen. Stond élke versie op onleesbaar, dan viel de keuze terug op de eerste en werd die
alsnog geopend. En de classificatie aan de andere kant las maar één logregel: ffmpeg logt de 404,
mpv logt daarna een algemene "Failed to open", en alleen die laatste overleefde. Een 404 werd
bovendien als HLS-segmentprobleem gelezen, want dat patroon stond eerder in de reeks.

Los daarvan bleef de melding staan. Een fout heeft in dit systeem bewust geen looptijd, want een fout
wil een handeling. Bij afspelen klopt die aanname niet: de speler is al gesloten voordat de kaart in
beeld komt, er valt niets te doen, en op een tv klikt niemand hem weg. Drie mislukte pogingen lieten
dus drie kaarten achter die over de video bleven hangen die daarna wél startte.

**Decision:** `PlaybackFailureKind` krijgt `fileUnavailable` als eigen uitkomst, met een eigen kop
("Bestand niet beschikbaar") en een regel die zegt wat er te controleren valt. De classifier leest de
laatste vier fout-logregels samen in plaats van de laatste, en scheidt een 404 op het bestand van een
404 op een segment of playlist. `PlexVideoPlaybackData.hasPlayableVersion` maakt de vlaggen van
`checkFiles=1` opvraagbaar, en `PlexClient.getPlaybackInitialization` weigert daarop met
`PlaybackFileUnavailableException` vóór er een URL geopend wordt. Alle afspeelmeldingen delen het
groepsvoorvoegsel `playback:`, krijgen twaalf seconden looptijd, en worden weggehaald zodra er een
beeld staat. Een herhaalde blijvende melding telt op bij de kaart die er al staat in plaats van er
een tweede naast te zetten.

**Consequences:** De weigering gebeurt op de vlaggen van de server, niet op een eigen inschatting;
stuurt Plex ze niet mee (`checkFiles` niet gevraagd, of een oudere server), dan zijn ze null en blijft
alles zoals het was. Jellyfin kent zo'n vlag niet, dus daar blijft de 404 van de stream de bron van de
diagnose — vandaar dat de classifier het ook zonder voorkennis moet kunnen zien. Twaalf seconden is
een keuze en geen meting: lang genoeg om twee zinnen op een tv te lezen, kort genoeg om de volgende
video niet te overleven. Meldingen buiten het afspelen blijven wél staan tot ze weggeklikt worden;
daar is de aanname dat een fout een handeling wil nog steeds waar.

## DEC-079: De merkgenerator schrijft op pixels, en zijn omgeving staat vast

**Date:** 2026-09-02
**Status:** accepted
**Context:** Een kale `python3 scripts/gen_brand_assets.py` herschreef zevenenveertig getrackte
iconen die pixel voor pixel gelijk bleven. Twee changelogregels noemen het al als "omgevingsdrift" en
hebben het allebei laten staan, met het gevolg dat elke generatorrun een vuile tree opleverde en
niemand meer kon zien wat er in zo'n diff wél echt veranderde. Fase 9 heeft de generator zelf
gewijzigd, dus het hoort hier opgelost te worden en niet doorgeschoven.

Gemeten in plaats van aangenomen. De bytes verschillen, de pixels niet: de IHDR is gelijk, de IDAT
niet, en `Image.tobytes()` is over alle zevenenveertig identiek. De richting klopt ook niet met een
verschoven compressieniveau — sommige bestanden werden kleiner, andere groter. Dat wijst op een
andere deflate-implementatie, en dat is precies wat er aan de hand is: deze Pillow-wielen zijn
gebouwd tegen **zlib-ng 2.3.3**, de omgeving die de getrackte assets schreef gebruikte stock zlib.
De scheidslijn is exact te trekken in de git-historie: alles wat op 2 september in deze omgeving
opnieuw geschreven is, blijft stabiel; alles van 19 en 28 augustus, geschreven op de Mac, verschilt.

Byte-identieke PNG-uitvoer is dus niet draagbaar te maken. FreeType komt er nog bovenop: dat rastert
de taglinestrook, en daar verschillen de pixels wél tussen versies — dat zijn de drie tvOS-icoonlagen
uit de vorige changelogregel.

**Decision:** Determinisme wordt gedefinieerd op de tekening, niet op de bytes.

1. `save()` codeert eerst naar geheugen, vergelijkt de **pixels** met het bestand dat er al staat, en
   schrijft alleen als ze verschillen. Run #1 levert de bedoelde uitvoer, run #2 een schone tree — op
   elke omgeving, niet alleen op de gepinde. Voor de multi-size `.ico` gaat de vergelijking per
   subbeeld.
2. De encoderinstellingen staan expliciet in `PNG_SAVE` in plaats van op de Pillow-standaarden te
   leunen, zodat een nieuwe standaard de uitvoer niet stil verschuift. Ze staan op de waarden van de
   pin: een andere waarde zou zevenenveertig bestanden opnieuw comprimeren zonder dat er één pixel
   verandert, en dat is precies wat dit besluit wegneemt.
3. De canonieke generatieomgeving staat in `scripts/requirements-brand.txt` (`Pillow==12.3.0`). Het
   script drukt bij het starten af waar het op draait — Pillow, de deflate-implementatie én FreeType —
   en zegt het als dat niet de pin is. Het weigert niet: de pixels blijven gelijk, alleen nieuw
   geschreven bytes kunnen anders uitvallen.

Wat er *niet* gebeurt: de zevenenveertig bestanden worden niet blind opnieuw gecommit, er verandert
geen pixeldata, en er wordt geen gegenereerd asset uitgezonderd van een controle.

**Consequences:** Een generatorrun is voortaan leesbaar — wat erin verandert, is wat er echt
verandert. De valkuil die dit onderweg opleverde staat in het script zelf beschreven: de `print` van
een overgeslagen bestand mag niet binnen de `try` om het decoderen staan, want `BrokenPipeError` is
een `OSError`, en een afgekapte pipe (`| head`) viel daardoor stil in het schrijfpad — één bestand
werd zo alsnog herschreven. Dat is gerepareerd en met een afgekapte pipe nagelopen.

Bij dit werk kwamen twee afgeleiden boven water die nooit meebewogen met de P: de merkmarkeringen van
Pleya Web (`pleya_web/static/brand/pleya-mark-{64,256}.png`), die als handmatige `sips`-verkleining in
een README stonden en aan `app.html`, `NavRail.svelte`, `+layout.svelte`, `login/` en `setup/` de oude
handgemaakte P bleven leveren, en `assets/pleya.png`, het beeld bovenaan de repo. Allebei staan ze nu
in de generator, met dezelfde ondoorzichtige merkgrond als voorheen en alleen de P van nu. De
handmatige route is uit de README gehaald: een afgeleid merkbeeld hoort geen eigen recept te hebben.
## DEC-080: `tvos.library.filters` is DEFERRED, geblokkeerd door het Pleya Server catalogus/filtercontract (G13)

**Date:** 2026-08-30
**Status:** accepted

**Context:** De Pleya Verify Definition of Done voor Fase 11 noemt vier scenario's, waaronder `tvos.library.filters`. De onafhankelijke Fase-11-audit (feat/testplane @ 02d038b) sloot de andere drie af maar kon dit scenario niet eerlijk end-to-end bouwen: het bevroren Pleya Server-cataloguscontract (`pleya_verify/contract/verify_api_v1.md`, gespiegeld aan het bevroren `docs/pleya-protocol/v1/openapi.yaml`) draagt op `/libraries/{id}/items` alleen `limit`, `cursor` en `sort`, geen filterparameter en geen filterendpoint. Dat gat staat als G13 in `docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md`, toegewezen aan "een catalogusfase, of een contractvraag vóór PS-7", niet aan een fase die al gesloten is. Client-side filteren over een gecursorde lijst van duizenden items zou het scenario technisch laten slagen zonder dat het bewijst wat het beweert te bewijzen, en Verify mag geen productiegedrag verzinnen om een eigen gate groen te krijgen. Het bestaande scenario dat er wél is (`tvos.library.sort.yaml`) test de Sort-control van de bibliotheekheader, een volledig ondersteunde functie vandaag, en is als zodanig al eerlijk hernoemd van `tvos.library.filters` naar `tvos.library.sort`.

**Decision:** `tvos.library.filters` is voor Pleya Verify Core 1.0 **DEFERRED: blocked by Pleya Server catalog/filter contract G13**. Dit is geen ontbrekende runner- of driver-capability: de scenario-grammatica, `assert.state`, geometrie-assertions en de generieke runner-infrastructuur kunnen het scenario morgen dragen. Het is een productcontract dat nog niet bestaat. De requirement wordt niet geschrapt en niet stilzwijgend versimpeld: hij blijft in de Fase-11 Definition of Done staan als open item, en wordt actief zodra Pleya Server een echt filterendpoint levert (de catalogusfase of contractwijziging waar G13 in de matrix naar wijst). Tot die tijd bouwt Verify geen placeholder-scenario dat op PASS kan komen te staan voor een capability die niet bestaat, en dit besluit ontwerpt geen filterprotocol vooruit. Met deze formalisering is Fase 11 voor Verify Core 1.0 administratief gesloten met precies één expliciet gedeferred productcontract-requirement; Fase 12 kan beginnen zonder dat een volgende sessie opnieuw hoeft te bepalen of Fase 11 "bijna groen" of "rood" is.

**Consequences:** `tvos.library.sort` blijft als aparte, geldige regressie-/acceptatiescenario staan en vervangt `tvos.library.filters` niet inhoudelijk. `pleya_verify/scenarios/README.md` benoemt de DEFERRED-status expliciet naast de bestaande uitleg over G13. Reactivering hoort bij het moment waarop het cataloguscontract een filterparameter of filterendpoint krijgt, niet bij een latere Verify-fase op eigen initiatief.

## DEC-081: Fase 12 gesloten, false-PASS-aanval op `tvos.sidebar.collapse` bewijst dat Verify een echte regressie rood maakt

**Date:** 2026-08-30
**Status:** accepted

**Context:** Fase 11 bewijst dat Pleya Verify een goede build groen kan verklaren. Dat bewijst niet dat een kapotte build ook echt rood wordt met een bruikbare FAILED-evidencebundel, en dat is precies het gat waar een niet-bestaand scenario of een timergebaseerde suppressie zich achter kan verschuilen, zoals de Fase-11-audit al bij Back/Menu vond. Fase 12 sluit dat gat met een echte, lokale, nooit-gecommitte sabotage tegen een scenario dat vóór de sabotage aantoonbaar groen was.

**Decision:** Gekozen gate: `tvos.sidebar.collapse` (2x PASS bewezen op tvOS in Fase 11, opnieuw bevestigd deze sessie op commit `d021ffd`, working tree schoon). Gekozen sabotage: `lib/widgets/side_navigation_rail.dart:120`. `state: () => {'selected': isSelected, 'collapsed': isCollapsed}` werd `state: () => {'selected': isSelected, 'collapsed': !isCollapsed}`. Dit breekt geen layout en geen navigatie; het laat `NavigationRailItem` zijn eigen automation-state omgekeerd rapporteren aan `AutomationNode`, hetzelfde booleaans veld dat het scenario op regel 28 toetst. Een echte automation-observatie-invariant, geen YAML-truc.

Cyclus, alle runs deze sessie zelf uitgevoerd:

1. Baseline PASS vóór sabotage: run `tvos-sidebar-collapse-1788112629069`, commit `d021ffd`, dirty=false.
2. Sabotage toegepast (ongecommit), app herbouwd (`scripts/tvos_sim.sh build && run`).
3. FAILED run `tvos-sidebar-collapse-1788112762601`: `assert failed: state(nav.discover.collapsed): 'nav.discover'.state.collapsed is false, expected true`. `manifest.json` toont commit `d021ffd`, dirty=true, target tvos-sim, het juiste app-instance, en alle zeven voorgaande stappen op ok=true met precies de falende stap als achtste. `ui-tree/final.json` bevat `nav.discover` met `bounds.width: 48.0` (de bekende collapsed-breedte) naast `state.collapsed: false`, de tegenstrijdigheid die de bug bewijst zonder de run opnieuw te hoeven zien. `focus-trace.json` (3 overgangen), `fixture/requests.jsonl` (41 echte paden), `app.log`, `driver.log` en `report.md` zijn alle aanwezig en niet leeg. Geen `screenshots/`: de scenario-stap die ze maakt (regel 29) komt na de falende assert op regel 28 en draait dus per scenariocontract niet, geen bundelgat.
4. Sabotage exact gereverteerd (`git checkout -- lib/widgets/side_navigation_rail.dart`); `git status` schoon; app herbouwd.
5. PASS run `tvos-sidebar-collapse-1788112895441`: commit `d021ffd`, dirty=false, ander run-id en ander instance-pid dan de FAILED run (geen hergebruikte evidence), alle drie de screenshots aanwezig, geverifieerd als echte 3840×2160 RGBA-captures met volle luminantierange (niet zwart/leeg), en de state-assertion op regel 28 toont weer `actual: true`.

False-PASS attack-matrix (bestaande hardening getoetst, geen nieuwe infrastructuur nodig: alle negen categorieën zijn al gedekt):

| Aanval | Guard | Bewijs | Status |
| --- | --- | --- | --- |
| Verkeerde/stale app-instance | `instance_discovery.dart` verwerpt een announcement op de verkeerde poort of van vóór deze launch | `instance_discovery_test.dart` (13 tests) + Fase-11-fix `05e5e81` | gedekt |
| Launch failure | `runScenario` termineert het proces ook als `launch()` gooit; een run die nooit launchte roept nooit terminate | `run_scenario_test.dart`: "a launch() that throws still gets terminated", "a run that never launched does not call terminate" | gedekt |
| Zwarte/lege screenshot | `screenshot_probe.dart` verwerpt een capture met te weinig distincte pixelwaarden | `screenshot_probe_test.dart` (7 tests, incl. "rejects the all-black capture") + handmatige luminantiecheck op de PASS-bundel van vandaag (0–255 op alle drie) | gedekt |
| Stale UI tree | elke `assert`/`wait_until`/eindbundel haalt `driver.uiTree()` opnieuw op; geen cachelaag in `run_scenario.dart` | codeonderzoek vandaag (`run_scenario.dart:253,380,406`) + `media-detail.episode-refresh` (Fase-11-audit: child_count 10→11 na fixture-mutatie tijdens playback) | gedekt |
| Lege focus trace | `AutomationFocusLog` start vóór het eerste frame, één persistente callback per proces | `automation_focus_log_test.dart` (4 tests) + niet-lege focus-trace.json in zowel de FAILED- als de PASS-bundel van vandaag | gedekt |
| Ontbrekende fixture requests | `requestsSince()`-castfix (`7c20720`) | echte requestpaden in de FAILED-bundel van vandaag (41 regels) | gedekt |
| Overgeslagen scenario-stap | een onbekend verb faalt hard in plaats van te no-oppen; het manifest legt elke uitgevoerde stap in volgorde vast | `run_scenario_test.dart`: "an unimplemented verb fails cleanly instead of silently no-opping" + FAILED-manifest van vandaag toont alle voorgaande stappen plus precies de falende stap | gedekt |
| Wait/event meldt te vroeg succes | `wait_until` pollt elke 150ms tegen live staat; een event-wacht leest altijd `eventsSince(0)`, dus geen gemist-en-toch-aangenomen event | codeonderzoek (`run_scenario.dart:336-354`) + `run_scenario_test.dart`: "wait_until times out and the run fails with a clear message" | gedekt |
| Onvolledige evidencebundel | elke schrijver produceert zijn bestand ook als de onderliggende inhoud leeg is | `evidence_bundle_test.dart`: "an empty log still produces the file, so a bundle is never silently incomplete" + handmatige inspectie van alle acht bewijsklassen in de FAILED-bundel van vandaag | gedekt |

Testbewijs, alle drie deze sessie zelf gedraaid: `flutter test` 4787 passed / 9 skipped / 0 failed. `pleya_verify/runner`: `dart test` 198/198. `pleya_verify/fixture_server`: `dart test` 75/75.

**Consequences:** Fase 11 en Fase 12 zijn beide gesloten voor Verify Core 1.0. `tvos.sidebar.collapse` blijft de referentiegate voor een toekomstige false-PASS-regressietoets op een ander scenario. Er is geen productcode of testinfrastructuur bijgekomen: de negen aanvalscategorieën waren al gedekt, en de sabotage van vandaag bestaat nergens meer buiten deze DEC en de niet-ingecheckte `.build/pleya-verify/`-evidencebundels op deze machine. `working tree` was bij het schrijven van deze DEC schoon op `d021ffd` plus deze documentatiewijziging.

## DEC-082: Pleya Verify MCP is een dunne adapter boven de bestaande CLI, geen tweede implementatie

**Date:** 2026-08-30
**Status:** accepted

**Context:** Fase 13 vroeg om een MCP (Model Context Protocol) laag waarmee een agent een bestaand Verify-scenario kan starten, zonder dat er een tweede scenario-engine, driver-laag of PASS/FAIL-beslissing naast de bestaande CLI ontstaat. De bindende architectuur was vooraf vastgelegd: MCP praat uitsluitend met `pleya_verify/runner/bin/verify.dart` als subprocess, en gebruikt de bestaande `--json`-modus.

Het bestaande `run --json`-contract had daarvoor één klein gat: het gaf alleen `ok`, `result`, `bundle` en `failureMessage` terug, nooit `scenario`, `target`, het echte proces-exitcode of het pasteable CLI-commando, en foutpaden (ontbrekend bestand, parse-fout, validatiefout, geen driver voor het target) schreven alléén platte tekst naar stderr, ook met `--json` aan. Zonder die velden had de MCP-laag zelf opnieuw moeten bepalen of een run een echte scenario-uitkomst was of een configuratiefout, precies de duplicatie die de opdracht verbood.

**Decision:** Twee wijzigingen, beide chirurgisch:

1. `pleya_verify/runner/bin/verify.dart`'s `run --json` geeft nu op elk exit-pad hetzelfde envelope terug: `ok`, `result` (`PASS`/`FAILED`/`ERROR`), `scenario`, `target`, `bundle_dir`, `failure_message`, eventueel `errors`, `exit_code` en `command` (de exacte argv om de run buiten MCP te herhalen). `ERROR` is een nieuwe, aparte waarde voor alles dat vóór of tijdens dispatch afbreekt (ontbrekend bestand, parse-/validatiefout, geen driver); die staat nooit gelijk aan `FAILED`. Er is geen scenario-, fixture-, driver- of assertion-logica bijgekomen: dit is uitsluitend het al bestaande resultaat consistent naar buiten brengen. `dart test` in `pleya_verify/runner`: 201/201 (198 bestaand + 3 nieuw, gericht op precies dit contract).
2. `pleya_verify/mcp/` is een nieuw, op zichzelf staand Dart-pakket met twee tools: `list_scenarios` (dunne wrap om `list scenarios --json`) en `run_scenario` (matcht de opgegeven naam tegen die lijst, start `run <pad> --json` als subprocess met een argv-lijst, nooit een shell-string, en geeft het CLI-envelope ongewijzigd door). `lib/src/mcp_server.dart` implementeert alleen het stdio-transport (newline-delimited JSON-RPC 2.0: `initialize`, `tools/list`, `tools/call`); een exception uit een tool-handler wordt `isError: true`, nooit een crash van de server. `dart test` in `pleya_verify/mcp`: 23/23, waarvan één test (`test/real_cli_integration_test.dart`) tegen de echte CLI-subprocess draait (`list scenarios --json`, bewust de goedkoopste subcommando, geen simulator of `flutter build` nodig) in plaats van tegen een fake.

**End-to-end bewijs, twee keer zelf gedraaid via de echte stdio MCP-server tegen `macos.smoke.boot`:**

Run 1: bundle `.build/pleya-verify/macos-smoke-boot-1788116256855` (pid 21265). Run 2: bundle `.build/pleya-verify/macos-smoke-boot-1788116458383` (pid 29543, dus een echt tweede, onafhankelijk app-instance, geen hergebruikte evidence). Beide runs: `reset_app`, `launch`, `sign_in`, `wait_until`, `assert` allemaal `ok: true`; beide falen deterministisch op exact dezelfde stap, `snapshot` (regel 10), met `Bad state: screencapture failed (exit 1): could not create image from window`. Een losse `screencapture -x` op dezelfde machine slaagt (volledig scherm, 2560×1440), dus het is geen ontbrekende Screen Recording-permissie in algemene zin; dit is een window-scoped capture (`-l<windowid>`) die in deze koppen-loze/remote sessie op een drie-schermen-opstelling niet lukt, exact de klasse fout die `macos_driver.dart`'s eigen foutmelding al benoemt. Dat is een omgevingsbeperking van deze sessie, geen defect in de MCP-laag of de CLI: de fixture server, de isolatie-build, de app-launch, sign-in, wachtcondities en de state-assertion werkten allebei de keren volledig, en de MCP-tool gaf het echte `FAILED`-resultaat (inclusief `bundle_dir` en `failure_message`) ongewijzigd door, met `isError: false`, precies zoals bedoeld: een echte CLI-uitkomst, geen MCP-infrastructuurfout, en geen false PASS.

**Consequences:** De architectuur `MCP -> CLI -> runner -> evidence` staat bewezen, inclusief de FAIL-tak: een echte, reproduceerbare FAILED-uitkomst komt via MCP net zo eerlijk binnen als via de CLI zelf. Een schone PASS-demonstratie van `macos.smoke.boot` op deze specifieke machine vereist eerst het window-capture-probleem op te lossen (buiten de scope van Fase 13, en geen MCP- of CLI-wijziging); wie dat wil narekenen kan het teruggegeven `command`-veld één-op-één in `pleya_verify/runner` draaien. `pleya_verify/mcp/README.md` documenteert de architectuur, de tools, agent-gebruik en de security-eigenschappen (geen path traversal, geen shell-interpolatie, stdout uitsluitend protocol). Fase 13 is hiermee gesloten.

## DEC-083: Pleya Verify CI, drie gescheiden gates, geen tweede execution-path

**Date:** 2026-08-30
**Status:** accepted

**Context:** Fase 14 vroeg om CI voor Pleya Verify volgens een vooraf vastgelegde richting: een verplichte, snelle Linux-gate voor alles dat geen simulator nodig heeft, een aparte macOS/simulator-gate, en tvOS aanvankelijk niet-verplicht. De bindende regel was dat CI uitsluitend orchestration is: de bestaande CLI/runner blijft de enige plek waar scenario's gedraaid en beoordeeld worden, en geen enkele scenario-FAIL of infrastructuur-ERROR als PASS mag verschijnen, ook niet om een run "groen genoeg" te krijgen.

Inventarisatie vooraf: `.github/workflows/ci.yml` (de bestaande Flutter-app-CI) raakt `pleya_verify/` nergens, en `scripts/ci_checks.sh` evenmin. De drie standalone Dart-pakketten (`fixture_server`, `runner`, `mcp`, alle drie `sdk: ">=3.12.0 <4.0.0"`, voldaan door de gepinde Flutter 3.44.0's gebundelde Dart 3.12.2) hadden geen CI-dekking. Er bestaat geen `.gitea/workflows/` in deze repository; Gitea (`origin`) is hier uitsluitend een git-remote, geen aparte CI-pipeline om mee te synchroniseren. Er is geen classic branch protection en geen ruleset op `main` of `feat/testplane` (`gh api repos/.../branches/.../protection` → 404, `gh api repos/.../rulesets` → `[]`): "required" is in deze repository dus een intentie die alleen via workflow-triggers en documentatie is af te dwingen, niet via GitHub-governance.

**Decision:** Eén nieuwe workflow, `.github/workflows/pleya-verify.yml`, drie jobs:

1. **`portable`** (ubuntu-latest, required-kandidaat). `dart test` in `pleya_verify/{fixture_server,runner,mcp}` plus een scenario schema-check (`list scenarios --json` en `validate` op elk bestand in `pleya_verify/scenarios/*.yaml`), puur parsen, geen driver-dispatch. Geen simulator, geen Xcode, geen secrets, geen netwerk. Triggers: push/PR naar `main`, `workflow_dispatch`, wekelijkse `schedule`.
2. **`macos-verify`** (macos-26, bewust buiten required omdat er geen governance is om het aan te hangen én omdat één scenario aantoonbaar niet draait, zie hieronder). Draait `macos.smoke.boot` (target `macos`) en `discover.hero.layout` (target `ios-sim`) elk via `dart run bin/verify.dart run <scenario> --json`, precies het bestaande CLI-commando uit `pleya_verify/mcp/README.md`. Geen los `flutter build`-commando in de workflow: `run_scenario.dart` roept `driver.build()` zelf al aan, dus CI voegt geen tweede build-pad toe.
3. **`tvos-verify`** (macos-26, `if: workflow_dispatch || schedule`, dus nooit op een gewone push/PR-check). Installeert `idb` via `brew tap facebook/fb && brew trust --tap facebook/fb && brew install facebook/fb/idb` (de actuele upstream-route uit de `facebook/idb`-README; `idb.rb` is een metapackage die `idb-cli` en `idb-companion` binnenhaalt), gevolgd door een harde verificatiestap (`which idb`, `which idb_companion`, `idb_companion --version`) en draait daarna `tvos.smoke.boot`. Dit is de enige driver die `idb` nodig heeft (`inputRoute => 'idb'`, hardcoded, `doctor()` eist `checks['input'] == 'idb'`); de andere twee targets hebben geen HID-tool nodig (macOS praat transport-HTTP, iOS-sim stuurt input via `xcrun simctl` direct).

Elke jobs' evidence (`.build/pleya-verify/*`, met de per-driver app-installcaches `*-app/` uitgesloten) gaat als `actions/upload-artifact@v7` mee, `if: always()`, `retention-days: 14`. Alle acties volgen de bestaande pin-conventie uit `ci.yml`/`build.yml`: `subosito/flutter-action` op exact SHA met versiecommentaar, first-party GitHub-actions op major-versietag (`@v7`/`@v6`), `flutter-version-file: .fvmrc`. `permissions: contents: read` op alle drie de jobs, geen secrets nodig voor `portable` of `macos-verify`.

**Echte GitHub Actions-runs, alle vier zelf getriggerd en geïnspecteerd (repo `michelknoop21/pleya`, branch `feat/testplane`, tijdelijk toegevoegd aan de `push`-trigger voor deze validatie, zie Consequences):**

| Run | Aanleiding | `portable` | `macos-verify` | `tvos-verify` |
| --- | --- | --- | --- | --- |
| `33330978192` | eerste push | FAILED: `dart pub get --enforce-lockfile`, elk `pleya_verify/*`-pakket gitignored zijn eigen `pubspec.lock` (library-conventie, anders dan het root-pubspec.lock); `--enforce-lockfile` eist een bestand dat hier nooit gecommit wordt | FAILED, zelfde oorzaak (`runner dependencies`-stap) | skipped (push, geen dispatch/schedule) |
| `33331085982` | fix: `--enforce-lockfile` weg voor de drie subpackages | **PASS**, 75+201+23 tests + 7/7 scenario's gevalideerd | job-conclusie failure, maar uiteengelegd: `macos.smoke.boot` **FAILED** op `flutter build macos` zelf (`No profiles for 'nl.michelknoop.pleya' were found`, automatische signing heeft geen Development Team/profiel op de hosted runner); `discover.hero.layout` **PASS**, echt, exit 0, bundel `discover-hero-layout-1788118612062` | skipped |
| `33332096402` | fix: evidence-upload sluit `*-app/` build-caches uit (de vorige run uploadde 155MB, waarvan bijna alles de geïnstalleerde `ios-app/Runner.app`-kopie was, geen evidence) | **PASS** (reproductie) | zelfde uitkomst als hierboven, reproductie: `macos.smoke.boot` FAILED (signing), `discover.hero.layout` PASS; evidence-artifact nu 253KB in plaats van 155MB | skipped |
| `33332644130` | handmatige `workflow_dispatch` (na drie push-runs registreert GitHub de workflow pas als dispatchbaar) | PASS (reproductie) | zelfde uitkomst als hierboven (reproductie) | FAILED, infrastructuurfout: de installatiestap deed `brew trust facebook/fb || true` gevolgd door een niet-gekwalificeerde `brew install idb-companion`, zonder eerst `brew tap facebook/fb` te draaien. Homebrew kon de formule daardoor niet resolven (`No available formula with the name "idb-companion"`, met de misleidende suggestie `brew install --cask companion`, een ander product). `tvos_sim.sh doctor` en `tvos.smoke.boot` werden om die reden overgeslagen. Dit was geen upstream-beperking: `facebook/homebrew-fb` bevat op controledatum 31 augustus 2026 nog steeds `idb-companion.rb` (v1.5.1) en de metapackage `idb.rb`, en de officiële `facebook/idb`-README schrijft `brew install facebook/fb/idb` voor |
| `33370765380` | correctieronde: `brew tap facebook/fb && brew trust --tap facebook/fb && brew install facebook/fb/idb` plus een harde `which`/`--version`-verificatiestap | PASS (reproductie) | zelfde uitkomst als hierboven (reproductie) | Voor het eerst voorbij de installatie: `which idb`/`which idb_companion`/`idb --help`/`idb_companion --version` slaagden alle vier, en `tvos_sim.sh doctor --json` bevestigde `"input":"idb"` (dus een echte idb-HID-verbinding, geen AppleScript-fallback). `tvos.smoke.boot` zelf **FAILED**, maar op een andere, eveneens corrigeerbare oorzaak: `xcodebuild` liep stuk op `Unable to load contents of file list: '.../Pods-Runner-frameworks-Debug-input-files.xcfilelist'`, omdat `tvos/Pods/` in `.gitignore` staat en op een verse checkout nooit bestaat; noch `tvos_sim.sh build`, noch de `tvos_beta`-fastlane-lane riep ooit het al aanwezige `tvos/scripts/pod_install.sh` aan. Gefixt door die aanroep toe te voegen aan `tvos_sim.sh build` (vóór `xcodebuild`, na `fetch_engine.sh`, want het Podfile leest `tvos/Flutter/Generated.xcconfig` dat `fetch_engine.sh` schrijft) |
| `33371859018` | correctieronde: `tvos_sim.sh build` roept nu `tvos/scripts/pod_install.sh` aan, ná `fetch_engine.sh` en vóór `xcodebuild` | PASS (reproductie) | zelfde uitkomst als hierboven (reproductie): `macos.smoke.boot` FAILED op dezelfde signingbeperking, `discover.hero.layout` PASS | `tvos.smoke.boot` **PASS**: `{"ok":true,"result":"PASS","scenario":"tvos.smoke.boot","target":"tvos-sim","exit_code":0}`, bundel `tvos-smoke-boot-1788164225236`. De scenariostap zelf liep van 08:16:58 tot 08:24:20 UTC, ruim zeven minuten reële simulatorboot- en assertietijd op een verse checkout zonder enige handmatige voorbereiding. Alle stappen van de job, inclusief `Upload evidence bundle`, groen |

`discover.hero.layout` (target `ios-sim`) is hiermee het eerste Apple-platform Verify-scenario met een bewezen, herhaalbare, echte PASS op een GitHub-hosted macOS-runner: geen `idb`, geen Apple-signing nodig (simulatorbuilds worden niet code-signed), driver praat via `xcrun simctl` en de bestaande transport-HTTP-laag. `macos.smoke.boot` faalt niet op de Fase-13-window-capture-beperking (die stap werd nooit bereikt) maar op een eerdere, even reële hosted-runner-beperking: de macOS Debug-scheme van `Runner.xcodeproj` vraagt automatische signing met een echt Apple Developer Team, en een hosted runner heeft er geen. Een Apple-signing-secret (team-ID, certificaat of een App Store Connect API-key) is één mogelijke oplossing, maar niet de enige: `MacosDriver.build()` kopieert de gebouwde app al naar een geïsoleerde Verify-bundel en tekent die kopie zelf al ad hoc met `codesign --force --deep --sign -` (`pleya_verify/runner/lib/src/driver/macos_driver.dart:141-145`), terwijl de bronbuild op zijn beurt draait onder `CODE_SIGN_STYLE = Automatic` met `"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development"` en zonder `DEVELOPMENT_TEAM` (`macos/Runner.xcodeproj/project.pbxproj:785-786`). Er ligt dus ook een onderzoeksroute open waarin alleen de bronbuild voor Verify ongetekend of ad hoc gebouwd wordt, zonder secret en zonder de productie-signing aan te raken. Beide routes zijn een aparte, aanzienlijke beslissing die buiten de Fase-14-scope valt (Deel H: "geen secrets nodig voor deterministic gates"); dit blijft de niet-vereiste toestand tot een toekomstige sessie er expliciet voor kiest. Verify zelf gedroeg zich hier exact zoals ontworpen: een echte `FAILED` met `failure_message`, geen false PASS, geen verzwakte assertion.

**Consequences:**

- De `push`-trigger op `.github/workflows/pleya-verify.yml` kreeg tijdelijk `feat/testplane` naast `main` toegevoegd, uitsluitend om deze vier runs op deze branch te kunnen zien zonder een PR te openen of op `main` te werken (`workflow_dispatch` vereist dat het workflow-bestand al op de default branch staat, wat vóór de eerste merge niet het geval is). Die regel wordt uit de trigger verwijderd zodra deze DEC gecommit is; de definitieve trigger is push/PR naar `main` plus `workflow_dispatch` plus wekelijkse `schedule`, identiek aan de bestaande `ci.yml`-conventie.
- **Intended vs. enforced required status.** `portable` is de required-kandidaat: deterministisch, geen secrets, tweemaal reproduceerbaar groen. Er is geen branch protection of ruleset op deze repository (geverifieerd via de GitHub API, zie Context), dus niets in GitHub zelf dwingt dat vandaag af. Wie dat wil instellen, voegt `portable` toe als required status check in de branch-protection-instellingen van `main`, een repository-instelling die deze sessie bewust niet zelf heeft gewijzigd.
- `macos-verify` blijft buiten "intended required" tot de signing-beperking is opgelost (via een Apple-signing-secret, of via een Verify-only ad hoc/ongetekend buildpad zoals hierboven beschreven, beide buiten scope) of het `macos.smoke.boot`-scenario is losgekoppeld van een lokale Debug-build met automatische signing (een wijziging aan `macos_driver.dart`/`Runner.xcodeproj`, ook buiten scope). `discover.hero.layout` op zichzelf heeft nu wél een reproduceerbaar bewijs van betrouwbaarheid; een toekomstige sessie kan overwegen om alleen dát scenario naar een eigen, wél required job te verplaatsen; deze sessie doet dat niet, om niet vooruit te lopen op een scope die Fase 14 niet vroeg.
- `tvos-verify` is en blijft initieel niet-required per de oorspronkelijke Fase-14-beslissing; de trigger (`workflow_dispatch`/`schedule` only) zorgt daar al voor, niet een governance-instelling. Runs `33332644130` en `33370765380` waren allebei geen platformbeperking, maar twee losse, corrigeerbare fouten in onze eigen automatisering: eerst een ontbrekende `brew tap`, daarna een nooit aangeroepen `pod_install.sh` voor de niet-gecommitte `tvos/Pods/`. Beide zijn gerepareerd, en run `33371859018` bevestigt het resultaat: `tvos.smoke.boot` haalt een echte PASS op een verse GitHub-hosted runner, zonder enige handmatige voorbereiding. Fase 14 sluit hiermee met alle drie de gates aantoonbaar werkend: `portable` en `tvos-verify` allebei tweemaal reproduceerbaar groen, `macos-verify` met één bewezen PASS (`discover.hero.layout`) en één `FAILED` die op een hosted-runner-signingbeperking staat, niet op een fout in Verify zelf.
- Gitea (`origin`) draait geen eigen CI voor dit project; er is niets om mee te synchroniseren of te dupliceren.
- `pleya_verify/scenarios/README.md` noemt nu welke scenario's welke CI-job draait.

## DEC-084: Fase 15 gesloten, Pleya Verify heeft nu een documentatielaag naast de code

**Date:** 2026-08-31
**Status:** accepted

**Context:** Pleya Verify (`pleya_verify/`) draait sinds Fase 14 met een bewezen CLI, MCP-laag en CI, maar had geen enkel document dat het geheel uitlegt: `lib/automation/pleya_verify.dart:2` verwees al naar `docs/architecture/pleya-verify.md`, een pad dat nog niet bestond, en `CLAUDE.md`/`AGENTS.md`/`CONTRIBUTING.md` noemden Pleya Verify nergens. Het oorspronkelijke plan (`pleya-verify-refactored-seal.md`, Fase 15) noemde vijf deliverables: de architectuurdoc, een agent-imperatieve testdoc, referenties plus een agentregel in de drie instructiebestanden, deze DEC-entry, en `pleya_verify/README.md`. Twee aannames uit dat plan bleken achterhaald: het wilde `DEC-080` nemen (inmiddels al gebruikt door de G13-defer uit Fase 11; het eerstvolgende vrije nummer is dit, DEC-084), en het beschreef de Fase-13-MCP-laag als "TypeScript op bun", terwijl hij in Dart gebouwd is (`pleya_verify/mcp/lib/src/mcp_server.dart`), zoals `pleya_verify/mcp/README.md` ook al correct documenteerde.

**Decision:** Alle vijf deliverables geschreven, geverifieerd tegen de daadwerkelijke code in plaats van tegen het plan uit augustus:

- `docs/architecture/pleya-verify.md`: waarom Pleya Verify bestaat, de grens met `flutter test`/`tvos_sim.sh`/`pleya_web`-e2e, het `/v1/*`-transportcontract, de fixture-server, de scenariogrammatica (`setupVerbs`/`stepVerbs`), de tvOS-invoerinvariant ([C2]), de bewijsstructuur inclusief screenshot-source-of-truth ([C5]), en de bekende grenzen (G13-defer, macOS-signing in CI, MCP is Dart).
- `docs/testing/pleya-verify-for-agents.md`: imperatief, in het Engels zoals `AGENTS.md` en `pleya_verify`'s eigen README's/SPEC's: het eerste commando (`scripts/tvos_sim.sh doctor` voor tvOS; er bestaat geen los `verify.dart doctor`-subcommando), hoe je een scenario schrijft, wat je doet bij een `FAILED`/`ERROR`, en een expliciete "never do this"-lijst (geen tvOS-invoer via `/v1/input/*`, geen `/v1/screenshot` als visuele waarheid, geen verzonnen fixture-gedrag om een scenario groen te krijgen).
- `CLAUDE.md` (nieuwe sectie "Pleya Verify"), `AGENTS.md` (nieuwe bullets onder "Architecture That Matters" en "Working Rules For Future Agents"), `CONTRIBUTING.md` (nieuwe sectie vóór "tvOS testen in de simulator"): elk met de agentregel: een relevante UI-/focuswijziging is niet volledig geverifieerd zonder passende Pleya Verify-assertions en visuele evidence, tenzij de omgeving aantoonbaar geen ondersteund target kan draaien (dan expliciet rapporteren welk bewijs ontbreekt), en geen zware gate voor pure backendcode.
- Deze entry, `DEC-084`, in plaats van het door het plan veronderstelde `DEC-080`.
- `pleya_verify/README.md`: top-levelniveau, layout-tabel, quick start, en de drie CI-jobs uit DEC-083.

Taalkeuze, niet expliciet in het plan vastgelegd: `docs/architecture/pleya-verify.md` en deze entry in het Nederlands, zoals alle overige bestanden direct in `docs/` (`DECISIONS.md`, `pleya-server-architecture.md`); `docs/testing/pleya-verify-for-agents.md` en `pleya_verify/README.md` in het Engels, zoals `AGENTS.md` en de bestaande `pleya_verify/{scenarios,mcp,geometry,redact}`-README's/SPEC's. De toevoegingen in `CLAUDE.md`/`AGENTS.md`/`CONTRIBUTING.md` volgen de bestaande taal van elk bestand.

**Consequences:** Alle vijf Fase-15-deliverables staan op schijf, elk stuk feitelijk beweerde inhoud (endpointlijst, verbwoordenlijsten, MCP-toolnamen, CLI-subcommando's, testpaden) is teruggelezen tegen de daadwerkelijke bronbestanden en niet overgenomen uit het plan zonder controle. Op het moment van schrijven van deze entry was dat nog uitsluitend documentatie. Een audit ná deze entry, en vóór het committen ervan, vond alsnog tien reële hardening-gaten in de code eronder; die ronde en de definitieve Core 1.0-sluiting staan in [DEC-085](#dec-085-vijf-hardening-fixes-en-het-definitieve-hosted-ci-bewijs-sluiten-pleya-verify-core-10), niet hier.

## DEC-085: Vijf hardening-fixes en het definitieve hosted CI-bewijs sluiten Pleya Verify Core 1.0

**Date:** 2026-08-31
**Status:** accepted

**Context:** Ná DEC-084 (de vijf Fase-15-documentatiedeliverables), en vóór die entry gecommit werd, vond een aparte controleronde tien punten die vóór een echte Core 1.0-sluiting opgelost moesten zijn, allemaal in de code onder `pleya_verify/` en `lib/automation/`, niet in documentatie. Vijf commits losten ze op:

- `4595ebf`: `/v1/*` accepteerde elk verzoek zonder `Authorization` zodra `PLEYA_VERIFY_TOKEN` niet op build-tijd was gezet, wat in elke CI-build het geval was. `AutomationServer.start()` genereert nu per launch een eigen `Random.secure()`-bearer-token, vereist die zonder uitzondering op elk `/v1/*`-verzoek, en schrijft hem alleen in `instance.json` naast port/pid. Een tweede gat zat in dezelfde commit: een ongevalideerde `base_url` op `/v1/signin` en `/v1/connections/seed` maakte van een loopback-only endpoint een open SSRF-proxy; `rejectNonLoopbackBaseUrl` laat nu alleen een letterlijk `http://127.0.0.1`- of `http://[::1]`-adres door.
- `bb6d2fd`: evidence-redactie herkende een credentialveld alleen bij een exacte naam, zodat een samengestelde sleutel als `oldPassword` of `userAccessToken` ongeredacteerd doorheen liep. `_isSecretKey` matcht nu op woordgrenzen van de canonieke sleutelvorm; `fixture_mutate`-resultaten en teardown-exceptionstrings gaan voortaan door dezelfde redactie als elk ander stepresultaat.
- `62c3739`: subprocess- en fixture-controlcalls hadden geen eigen deadline, dus een vastgelopen simulator of een niet-antwoordende fixture blokkeerde een MCP-aanroep onbepaald en liet het kindproces achter. Elke call race't nu tegen een deadline en ruimt het kindproces op (`SIGTERM` dan `SIGKILL`) vóór de aanroep teruggeeft; een timeout is altijd een expliciete infrastructuurfout, nooit een scenario-uitkomst.
- `7a9c8c0`: een onverwachte exception boven de al afgehandelde paden (kapotte YAML die niet als `ScenarioParseException` binnenkwam) liet `main()` de fout ongevangen laten vallen, zonder JSON op stdout. `_runScenarioCommand` en `_runValidate` vangen dat nu af met een top-level catch die alsnog exact de envelope teruggeeft die `--json` voor elk ander pad al belooft.
- `3eac2d8`: `set_pref`, `focus` en `back` stonden in `setupVerbs`/`stepVerbs` zonder case in `run_scenario.dart` en zonder gedefinieerde semantiek; verwijderd in plaats van alsnog geïmplementeerd, bewaakt door een nieuwe structurele parity-test tussen de vocabulaire en de engine-switch.

Elk van de vijf is inhoudelijk uitgeschreven in `docs/architecture/pleya-verify.md`, sectie "Security-grens (Core 1.0)".

**Decision:** Ná de vijf fixes is hosted CI-run [`33391955462`](https://github.com/michelknoop21/pleya/actions/runs/33391955462) het definitieve hardening-bewijs, gedraaid op HEAD `d4459bd9ddebd74b047ddc8b209df3fa3371d756`:

- `portable` (Linux): **PASS**, alle drie testsuites (76+216+25 tests) en het schema-check op alle zeven scenario's.
- `discover.hero.layout` (target `ios-sim`): **PASS**, `exit_code: 0`.
- `tvos.smoke.boot` (target `tvos-sim`, `workflow_dispatch`, niet required): **PASS**, `exit_code: 0`, met echte `idb`-invoer en per-instance auth/discovery (dezelfde `instance.json`-mint als hierboven).
- `macos.smoke.boot` (target `macos`): **FAILED**, `Bad state: flutter build macos failed (exit 1)`, dezelfde reeds gedocumenteerde hosted-runner-signingbeperking als in [DEC-083](#dec-083-pleya-verify-ci-drie-gescheiden-gates-geen-tweede-execution-path) (geen Development Team/profiel op de hosted runner), geen nieuwe regressie.

De required-candidate `portable`-gate en de uitgevoerde iOS/tvOS Verify-scenario's zijn groen; de gecombineerde workflowconclusie van run `33391955462` blijft rood, uitsluitend door de expliciet non-required `macos.smoke.boot`-signingbeperking. Branch protection dwingt dit op dit moment niet af; er is geen required-status-check ingesteld op `feat/testplane` of `main` die dit garandeert.

**Consequences:** Pleya Verify Core 1.0 is hiermee compleet: deterministic fixture-backed scenario's, drie platformdrivers (macOS/iOS-sim/tvOS-sim), UI-boom/focus/events/geometrie-assertions, autoritatieve compositor-screenshots als visuele waarheid, complete evidencebundels, false-PASS-verdediging (Fase 12), CLI, MCP-laag (Fase 13), CI-orkestratie (Fase 14), fail-closed control-plane-auth, bounded execution, en redactie-/securityhardening (dit besluit). Bekende, niet-blokkerende grenzen: macOS-hosted-buildsigning in CI, `tvos.library.filters` (DEFERRED voor G13, [DEC-080](#dec-080-tvoslibraryfilters-is-deferred-geblokkeerd-door-het-pleya-server-cataloguscontract-g13)), en tvOS-D-pad-navigatie binnen het systeemtoetsenbord (niet simuleerbaar, zie CONTRIBUTING.md). Geen nieuwe featurescope geopend; een volgende sessie die verder wil dan Core 1.0 begint bij een expliciet nieuw besluit, niet bij het stilzwijgend heropenen van Fase 1 t/m 15.


## DEC-086: Verder kijken staat alleen op Home; de Films- en Series-landing tonen het niet

**Date:** 2026-09-02
**Status:** accepted

**Context:** `TvDiscoveryLandingProvider` zette een Continue Watching-rij vooraan op zowel de Films-
als de Series-landing, en 33.3 en 33.4 leggen dat allebei BINDEND vast ("CW eerst wanneer gevuld",
"zelfde systeem als 33.3 met CW bovenaan"). Op een echte Apple TV levert dat dezelfde rij op drie
pagina's op, en hij duwt op elke landing de rij weg waar die pagina voor bestaat.

Bij het weghalen bleek er een tweede, zwaardere reden onder te zitten die in de melding niet stond.
De rij was **niet kind-gesplitst**. Hij werd één keer geprojecteerd over de volledige
`DiscoverProvider.onDeck` en aan beide landingen voorgeplakt, terwijl de hubs ernaast wél in
`movieBackendHubs`/`seriesBackendHubs` werden gesorteerd. De Films-landing opende dus met
halfgekeken afleveringen en de Series-landing met films, precies wat de klassedoc van diezelfde
provider uitsluit ("split by [MediaKind] so a Films landing never shows a show and vice versa").
Dat is een zelfstandig defect, en het maakt "de rij hoort hier niet" een sterker argument dan
alleen herhaling.

**Decision:** Alle CW-plumbing is uit `TvDiscoveryLandingProvider` verwijderd: het
`continueWatchingTitle`-constructorargument, het veld, de `projectContinueWatching`-aanroep, de
`Future.wait`-positie, de `_withContinueWatching`-wrapper en de CW-tak van `hubById`. `movieRails`
is `_movieHubs` en `seriesRails` is `_seriesHubs`. `TvHomeProjectionProvider.continueWatching` is
de enige eigenaar van die rij, en dat was hij op Home al.

Dit overrulet 33.3 en 33.4; beide referenties hebben een afwijkingsnotitie gekregen.

De projectiecontracten die aan die rij hangen (hoofdstuk 11.8's exacte-aflevering-identiteit,
hoofdstuk 13.1's per-bron watch state, hoofdstuk 21.4's partial-gedrag) zijn niet vervallen maar
verhuisd: `test/providers/tv_discovery_landing_provider_test.dart` draait diezelfde groep nu tegen
`TvHomeProjectionProvider`. Ze staan nog in dat bestand omdat ze op de on-deck-fixtures daarvan
gebouwd zijn; wat ze beweren is ongewijzigd.

**Consequences:** De eerste rij van een landing is een aanbevelingsrij. Traversal is nagelopen en
niet aangenomen: rails zijn op `hubId` gesleuteld, niet op index, en
`test/screens/tv/tv_discovery_landing_screen_test.dart` bewijst dat ↑ vanaf de eerste rail nog
steeds op de paginakop uitkomt. Home is ongewijzigd. Registerrij B21 in
`docs/qa/tvos-unified-edge-cases.md`.

## DEC-087: TV-discovery-dichtheid, `cardHeight` 220 en een kortere metaregel

**Date:** 2026-09-02
**Status:** accepted

**Context:** Op een echte Apple TV vulde één discovery-rij 64% van het scherm, stonden er in
ruststand vijf volle kaarten, en nam de gefocuste 16:9-kaart 42,3% van de bruikbare railbreedte met
drie volle buren ernaast. `TvDiscoveryLayout.cardHeight` (270) is de enige knop; al het andere is
daarvan afgeleid, want de gefocuste kaart is per constructie exact 2,67 posterbreedtes.

Doorgerekend op het canonieke canvas (1038×584, `scaleOf` klemt op 0,85, bruikbare railbreedte
964,9):

| cardHeight | poster | wide | ruststand | naast de gefocuste kaart |
|---|---|---|---|---|
| 270 | 153,0 | 408,0 | 5 vol + 89 px | 3 vol, gefocust 42,3% |
| 240 | 136,0 | 362,7 | 6 vol + 16 px | 3 vol, gefocust 37,6% |
| **220** | **124,7** | **332,4** | **6 vol + 84 px** | **4 vol, gefocust 34,5%** |
| 200 | 113,3 | 302,2 | 7 vol + 17 px | 4 vol, gefocust 31,3% |

**Decision:** `cardHeight` staat op **220**. Beide helften van de dichtheidseis moeten tegelijk
kloppen: zes volle kaarten in ruststand *met* een zichtbaar gedeeltelijke zevende, zodat de rij
leest als doorlopend in plaats van eindigend, en vier volle buren naast de gefocuste kaart, zodat de
expansie een klemtoonverschuiving is en geen overname van de rij. 240 haalt de eerste helft met 16
px peek (niet te onderscheiden van een clipping-fout) en houdt drie buren. 200 haalt de tweede
helft en zet er in ruststand zeven neer, wat de catalogusgrid-indruk is waar dit oppervlak tegen
bestaat.

Twee dingen horen bij dezelfde beslissing, omdat ze dezelfde verticale ruimte betreffen:

- **De metaregel wordt korter.** Het bronnenaantal gaat eruit (de kaart erboven draagt daar een
  `TvSourceCountBadge` voor, in dezelfde oogopslag) en een film krijgt zijn speelduur, het enige
  feit dat de regel niet had en dat een kijker vóór een avond wél weegt. Een aflevering krijgt die
  niet: zijn resterende tijd beantwoordt dezelfde vraag beter.
- **De onderrand krijgt de teruggewonnen ruimte.** `TvCatalogLayout.bottomSafeInset` is nieuw en
  staat op 81 referentiepixels, 7,5% van de referentiehoogte, tegen `topSafeInset`'s 56. Hoofdstuk
  8.1 noemt een *minimum* ("geen tekst of focusring binnen de buitenste 56 pixels"), en 56 is 5,2%
  van de hoogte, ongeveer precies de overscanband die een consumentenset opeet. Een pagina die op
  56 uitkomt zet zijn laatste leesbare regel en de focusring van de onderste rij dus *op* die band
  in plaats van erbuiten. Dit is een strengere marge, geen afwijking van 8.1, en hij is alleen
  betaalbaar omdat de rijen korter zijn.

Dit supersedet 33.2 (band 400 / gefocust 711 / buren 267), 33.3 (gefocust ≈40%, drie buren) en
33.4 (het metadataformaat inclusief bronnenaantal). Alle drie de referenties hebben een
afwijkingsnotitie gekregen.

**Consequences:** Eén rij zakt van 374,8 naar ≈332 logische pixels. `test/widgets/tv/tv_discovery_density_test.dart`
telt de kaarten op het canonieke canvas in beide toestanden in plaats van de constante te asserten.
Een test op `cardHeight == 220` zou groen blijven nadat iemand `itemGap` of `pageInset` veranderde
en de zevende kaart stilletjes kwijtraakte. `tvos.discovery.density` bewijst dezelfde compositie op
een echte build, voor zover het transportcontract dat kan: `insideViewport` heeft geen negatie, dus
"zes vol en een zevende ernaast" is wat een scenario kan zeggen en "de zevende is niet helemaal
zichtbaar" niet. Kijklijst en Aanvragen draaiden op een ander maatsysteem (`MediaGridGeometry` +
`GridSizeCalculator`, gestuurd door `SettingsService.libraryDensity`) en zijn op TV op de gedeelde
`TvCatalogGrid`-geometrie gezet; de zeven andere `MediaGridGeometry`-call-sites en alle niet-TV-paden
zijn ongemoeid. Registerrij B22.

## DEC-088: focus-entry en Back-eigendom van een geneste TV-route horen bij de shell, niet bij het scherm

**Date:** 2026-09-02
**Status:** accepted

**Context:** Op de echte Apple TV was Mijn Pleya onbedienbaar, en dat is met Pleya Verify in de
tvOS-simulator met echte HID-invoer gereproduceerd (`docs/tvos-my-pleya-audit-2026-09-02.md`, bewijs
in `.build/pleya-verify/tvos-my-pleya-sections-1788370856568`). SELECT op een tegel opende de route,
maar de focus landde op de content-`FocusScope` zelf, DOWN deed niets, en Menu verplaatste de ring
naar de tabstrip zonder de sectie te sluiten. Er was geen weg terug naar de hub.

Drie oorzaken stapelden. `tv_my_pleya_navigator.dart` maakte voor acht van de tien secties een
`GlobalKey` die aan geen widget werd gegeven, zodat de enige focus-entry van de shell
(`route.screenKey?.currentState is FocusableTab`) nooit matchte. Zes secties hebben sowieso geen
`FocusableTab`, en drie daarvan zijn `StatelessWidget`s, dus voor die drie kan een sleutel per
definitie geen `State` opleveren. En `focusActiveTabIfReady()` geeft `void` terug, dus de aanroeper
kon niet zien dat er niets gebeurde en consumeerde de gewapende focus-intentie met een aanroep die
niets deed.

De vastgelopen Menu is een vierde, aparte oorzaak. Flutter stuurt een toets eerst naar de gefocuste
node en loopt alleen omhoog zolang het antwoord `ignored` is. `TvBrowseRail` draait
`handleBackKeyAction` op zijn eigen `onBack`, en `LibrariesScreen` geeft daar `focusTabBar` aan mee:
een focusverplaatsing binnen het scherm. De rail antwoordt `handled`, de wandeling stopt, en de
`popNested`-stap komt nooit aan de beurt. Dat is precies wat `TvRootShell` in zijn eigen documentatie
verbiedt.

**Decision:** Focus-entry en Back-eigendom van een geneste TV-route liggen bij de shell.

`TvNestedSurface` omhult elke geneste route, ook die van de catalogus. Hij vraagt eerst het scherm
zelf, want een scherm dat zijn onthouden positie kent weet het beter dan een algemene regel, en valt
anders terug op de eerste focusbare afstammeling van de route. Daarmee werkt entry voor een
`StatelessWidget` net zo goed als voor een scherm met een volledig contract, en hangt hij niet langer
aan een sleutel die iemand vergat door te geven. `focusEntry()` geeft terug of er een echt doel om
focus gevraagd is, zodat een nog ladend scherm de gewapende intentie laat staan in plaats van hem op
te souperen. De herhaling is begrensd op vijf seconden, stopt zodra de focus binnen is, en wordt bij
`dispose` afgebroken: een herhaling die zijn widget overleeft is dezelfde soort fout als de
tijdelijke overrides waar `TemporaryOverride` voor bestaat.

`TvNestedBackOwner` markeert de subboom van een geneste route, en `handleBackKeyFocusMove` is de
variant van de backafhandeling voor een `onBack` die een focusverplaatsing is. Die trekt zich binnen
zo'n route terug. Een echte afwijzing (dialoog, sheet, overlay) blijft `handleBackKeyAction` gebruiken
en houdt dus voorrang, want dat is precies het geval waarin een afstammeling Back hóórt op te eten.
`TvBrowseRail` is de enige omgezette aanroepplek, omdat dat de enige is die aantoonbaar vastliep.

**Bewijs:** dezelfde route, dezelfde echte HID-invoer, na de wijziging. Logs en diagnose (geen
`FocusableTab`, sleutel hing nergens aan) opent op `ActionBar[0]`, RIGHT loopt naar `ActionBar[1]`,
en Menu zet `tvNestedRoute` terug op null met de tegel weer gefocust. Servers (een
`StatelessWidget`) doet hetzelfde. Bundels:
`.build/pleya-verify/tvos-my-pleya-section-logs-1788373241707` en
`tvos-my-pleya-section-servers-1788373614514`.

## DEC-089: verticale navigatie in het Mijn Pleya-raster volgt de rijen, niet een vaste stap

**Date:** 2026-09-02
**Status:** accepted

**Context:** In de simulator sprong DOWN vanaf Servers, de tweede tegel van een rij van drie, naar
Over, de derde tegel van de rij eronder. `_verticalNeighbour` stapte `TvMyPleyaLayout.tilesPerRow`
plaatsen door de platte sleutellijst. Dat is alleen "één rij omlaag" wanneer elke rij vol is, en de
platte lijst begint bovendien met de profielactie, die geen deel van het raster uitmaakt. Twee
fouten die optellen, en beide zichtbaar zodra een groep minder tegels heeft dan het raster breed is,
wat op elke fixture zonder Seerr en zonder downloads het geval is.

**Decision:** Een groep is een rij. De kolom is de index van de tegel binnen zijn eigen groep, en de
buur is dezelfde kolom in de aangrenzende groep, afgekapt op de breedte van die groep. Vanaf de
bovenste rij landt UP op de profielactie, die zelf verder omhoog naar de topnavigatie gaat; vanaf de
onderste rij blijft DOWN staan in plaats van naar de laatste tegel van de pagina te springen, wat
klemmen op `keys.last` vanuit elke kolom deed.

Drie regressietests in `test/screens/tv/tv_my_pleya_screen_test.dart` leggen dit vast, en ze zijn met
een negatieve controle nagelopen: alle drie worden rood zodra de oude implementatie wordt
teruggezet.

## DEC-091: Een TV-contentroute opent binnen de shell, via een registry en niet via een tweede Navigator

**Nummer.** DEC-090 is op `feat/netflix-mobile` al vergeven aan de iOS-northstar. Die branch is
niet samengevoegd, dus het nummer wordt hier overgeslagen in plaats van een tweede keer gebruikt.

**Context.** De mockups 09 tot en met 25 zijn op 3 september 2026 goedgekeurd
(`docs/tvos-redesign-09-25-approved.md`). PB-1 van het implementatiecontract zegt dat de
heringerichte TV-contentroutes de topnav houden: filmdetail, seriedetail, collectie, persoon en
de Instellingen-subpagina's. Die worden vandaag op de `ProfileSessionNavigator` gepusht en dekken
de shell volledig af.

**Wat DEC-069 hier al over zei.** Dat besluit weigerde een `Navigator` binnen de shell, met twee
argumenten. Het eerste is dat `Navigator.push` de dichtstbijzijnde navigator vindt, dus een
navigator in de contentbox zou elke `navigateToMediaItem` impliciet opvangen. Het tweede is dat
`Navigator.pop` dan stap 2 en stap 3 van de terugketen uit hoofdstuk 7.5 niet meer uit elkaar
houdt. Allebei gelden nog. De conclusie die DEC-069 eraan verbond, dat een detailpagina daarom
niet in de geneste stapel hoort, geldt niet meer: dat was een uitspraak over welke schermen erin
horen, niet over het mechanisme.

**Besluit.** Het mechanisme blijft de geneste routestapel die géén Navigator is. Wat verandert is
hoe een aanroeper erbij komt. `lib/navigation/tv/tv_content_route_registry.dart` is één
procesbrede registry waar `MainScreen` zijn push publiceert zolang de TV-shell staat. Een
aanroeper vraagt er expliciet om, en krijgt `null` wanneer er geen shell luistert. Dat null is de
kern van de vorm: elke aanroeper schrijft het shellpad en het gewone pad naast elkaar, en niemand
hoeft te weten wat een TV-shell is behalve dat hij er kan zijn.

**Waarom expliciet en niet impliciet.** Een tweede `Navigator` zou hetzelfde bereiken zonder dat
iemand het opschrijft, en precies daar zit het verschil. Bij een registry staat in de aanroeper
te lezen dat hij binnen de shell wil openen; bij een navigator gebeurt dat door de plaats in de
boom, en dan is de enige manier om te weten welk pad een push neemt, uitzoeken welke navigator
toevallig het dichtst bij staat.

**Gevolgen.** `TvNestedRoute` heeft een resultaat gekregen, zodat een aanroeper die eerst een
`Navigator.push` afwachtte dezelfde vorm houdt. `pushNested` geeft terug welke route bovenop komt
te liggen, want bij een genegeerde dubbele push is dat niet het object dat de aanroeper meegaf.
`clearNestedRoutes` sluit bij een profielwissel elk openstaand resultaat af.

**Uitzonderingen.** De speler in fullscreen, authenticatie, de profielselectiepoort, het native
tvOS-toetsenbord en echte modale presentatie houden de volledige-venster route.

**Bewijs.** `test/screens/tv/tv_content_route_test.dart`. De eerste test is de negatieve controle
en legt het oude gedrag vast: na een volledige-venster push is niets in de balk nog bereikbaar.

## DEC-092: Mijn Pleya ▸ Bibliotheken wordt bronbeheer; bladeren per bibliotheek loopt via de unified catalogus

**Date:** 2026-09-04
**Status:** accepted
**Context:** §4.5 van `docs/tvos-unified-experience.md` houdt Bibliotheken als "de geavanceerde bronweergave": één library kiezen, Aanbevolen, Bladeren, Collecties, Afspeellijsten. Mockup 26 (`docs/assets/tvos-unified/mockups-2026-09-04/26-bibliotheken-*.png`) tekent precies dat in de nieuwe taal, en Michel wees het op 4 september af, letterlijk: "Ik vind de werking van deze pagina gewoon niet in lijn met wat we aan het bouwen zijn", met als toelichting "in kader van unified". De spec spreekt zichzelf hier tegen. §10.4 zet server en library al bij de globale filters van de unified catalogus, en de app heeft die knop als "Alle bronnen" op Alle films (`lib/widgets/tv/tv_catalog_header_bar.dart`). Bladeren per bibliotheek heeft dus al een unified thuis; §4.5 bouwt er een tweede, per bron, naast. Wat §1524 als "alleen in Bibliotheken" benoemt is beheer: scan, analyse, prullenbak, metadata-refresh op de hele library, mappen bladeren, verbergen en ordenen. De styling-audit van 2 september had Bibliotheken als klasse E gemarkeerd, het enige scherm waar het productcontract zelf in het geding is, en vroeg er apart akkoord voor. Dat akkoord is er nu niet gekomen; er kwam een andere richting voor terug.
**Decision:** Bibliotheken wordt bronbeheer en verliest het bladeren. (1) De pagina toont per server de bibliotheken als beheerregels met soort, aantal, zichtbaar of verborgen en volgorde; per regel de acties Openen in catalogus, Vernieuwen, Scannen, Verbergen, en waar de backend het draagt Mappen, Analyseren en Prullenbak. Openen in catalogus landt op de bestaande Alle films of Alle series met deze bibliotheek als bronfilter; dat is de enige bladerweergave. (2) De tabs Aanbevolen en Bladeren vervallen; aanbevelingen doen Home, Films en Series over alle bronnen heen. (3) Collecties en Afspeellijsten verlaten de pagina en worden eigen ingangen in de Mijn Pleya-hub, over alle bronnen, met mockup 24 als detail. Mockup 27 (`27-bronbeheer-a` tot en met `-e`) tekent dit in het systeem van 09 tot en met 26. Spec-wijzigingen die dit vraagt, pas door te voeren zodra dit besluit `accepted` is: §4.5 herschrijven naar bronbeheer; in de tabel van 18.2 de rij "Bibliotheken verbergen/ordenen" laten staan en "Bibliotheken" beschrijven als beheer; in §1524 collectionbeheer en playlistbeheer verplaatsen naar hun eigen ingangen. De twee acceptatie-eisen van Michel gaan mee: elke knop bereikbaar met de afstandsbediening, en geen afwijking van de andere schermen.
**Consequences:** `LibrariesScreen` op TV verliest de tabstructuur en de kiezer uit LIB1 tot en met LIB3; die drie bevindingen zijn gesloten op een contract dat verdwijnt, en dat is geen verspilling: de verzoening tussen selectie en lijst (LIB1) en de race bij snel wisselen (LIB2) gelden onverkort voor een beheerlijst die dezelfde bibliotheken laadt. iOS en macOS blijven buiten deze wijziging; hun bibliotheekinterface volgt DEC-090. Negatieve controle voor de bouwronde: een widgettest die de TV-route van Bibliotheken pompt en eist dat er geen tab Aanbevolen of Bladeren bestaat en dat elke bibliotheekregel een actie Openen in catalogus draagt, rood op de huidige code. Wat dit besluit niet doet: code raken. Dit is de correctieronde van 4 september; de bouw is een eigen ronde met eigen bewijs. LIB4 is vervangen door LIB7 in `docs/tvos-fysieke-correctieronde.md`. Geaccepteerd door Michel op 4 september 2026 op mockup 27, in zijn woorden: "Verder akkoord op de mockup alleen de filters nog bij alle films en series posities." Dat voorbehoud gaat over de positie van Bronnen, Filters en Sortering op de catalogus zelf, staat als CAT5 in de correctieronde en krijgt een eigen besluit; het raakt de werking van Bibliotheken niet.

## DEC-093: De catalogusacties op TV zitten in een inklapbare rail links van het raster, en de gekozen filters staan als tags rechtsboven

**Date:** 2026-09-04
**Status:** accepted
**Context:** Hoofdstuk 10.2 van `docs/tvos-unified-experience.md` bindt de éénregelige kop met Bronnen, Filters en Sortering rechtsboven naast de paginakop, en de code volgt dat (`lib/widgets/tv/tv_catalog_header_bar.dart`). CAT3 zette die cluster op de canonieke rechterrand en CAT4 maakte hem bereikbaar; beide zijn dicht. Op een fysieke Apple TV met build 248 vond Michel de plek zelf verkeerd: klein, ver van het raster, en één UP te ver is de topnav. Zijn woorden bij het goedkeuren van mockup 27: "de filters moeten ook nog een betere positie krijgen zodat je deze makkelijker kan bereiken op tvos". Drie posities zijn getekend als mockup 28 (`docs/assets/tvos-unified/mockups-2026-09-04/28-catalogusfilters-*.png`): A de huidige, B de cluster links naast de kop met Play/Pause als snelkoppeling, C een verticale rail links van het raster. Hij koos C, met twee eisen: niet permanent in beeld, en de gekozen filters subtiel zichtbaar in het raster. Op de eerste uitwerking vroeg hij de tags naar rechtsboven, omdat die plek vrijkomt zodra er niets bedienbaars meer hoeft te staan.
**Decision:** De drie catalogusacties verhuizen naar een rail links van het raster die dicht is zolang de focus in het raster zit (D1) en opent op LEFT vanaf kolom 0 (D2). Dicht: zes kolommen, een stille streep aan de linkerrand als affordance, en de actieve keuzes als niet-bedienbare tags rechtsboven op de plek van de oude cluster, met de sortering gestippeld zodat hij niet als filter leest. Open: één paneel in de tegeltaal, per regel icoon, label en huidige waarde (Bronnen, Filters, Sortering), daaronder de keuzes als tags en Wissen; het raster schuift naar vijf kolommen. RIGHT of Menu sluit de rail en de focus keert terug op de kaart waar hij vandaan kwam. Het filterpaneel van 10.6 blijft bestaan en opent vanuit de rij Filters; de Play/Pause-snelkoppeling uit 10.6 blijft toegestaan en is geen vervanging. Dit geldt voor Alle films, Alle series, Kijklijst (mockup 14) en elke catalogus die de kop van 10.2 gebruikt, dus ook state D van mockup 27.
**Consequences:** 10.2 en 10.6 zijn aangepast en northstar 05, 06 en mockup 14 lopen achter op het besluit; ze worden bij de eerstvolgende herschietronde bijgetrokken en tot die tijd is 28 D1/D2 bindend voor de positie. De code verandert nog niet: dit is de correctieronde van 4 september en de bouw is een eigen ronde. Negatieve controle voor die ronde: een widgettest die Alle films pompt met de focus op kolom 0 en eist dat LEFT de rail opent met de focus op Bronnen, dat RIGHT hem sluit met de focus terug op dezelfde kaart, en dat de kop geen focusbare actie meer draagt; rood op de huidige code. De reachability-test van CAT4 (`test/screens/tv/tv_catalog_header_reachability_test.dart`) verliest zijn onderwerp en wordt herschreven op de rail, niet verwijderd. Wat open blijft: de exacte breedte van de rail tegen de 8.1-veiligheidsband, en of vijf kolommen op de 1280x918-ondergrens van CAT1 nog passen; beide zijn maten voor de bouwronde. Vastgelegd als CAT5 in `docs/tvos-fysieke-correctieronde.md`.

## DEC-094: De hero vraagt artwork in de bronratio aan, en de uitsnede heeft één eigenaar

**Date:** 2026-09-04
**Status:** accepted
**Context:** HERO1 in `docs/tvos-fysieke-correctieronde.md`: op de Apple TV met build 248 zag Michel "halve afbeeldingen" in de hero op Home. `TvHeroArtwork` vroeg de backdrop aan in de pixels én de ratio van de kaart, 2,465:1, en tekende hem met `BoxFit.cover` en `Alignment.topCenter`. Plex' `/photo/:/transcode` vult met `minSize=1` de gevraagde box en snijdt het overschot gecentreerd weg, dus het beeld kwam al op 2,465:1 binnen en de uitlijning in Flutter deed niets. Jellyfin past met `maxWidth`/`maxHeight` in en snijdt niet, dus daar sneed Flutter wél, onderaan. Twee backends, twee uitsneden, geen van beide de bedoelde. De widget beriep zich op DEC-057, terwijl dat besluit precies het omgekeerde zegt: vraag de ratio van de bron, zodat de servercrop een no-op is; het liet alleen de brede box ongemoeid. Michel vroeg op 4 september of dit op te lossen was, en merkte terecht op dat het niet alleen om Plex gaat.
**Decision:** De aanvraag volgt de ratio van de bron, op elke backend. `OptimizedMediaImage` krijgt een optionele `requestSize`: de box die de server gevraagd wordt en waarop de decode-bucket wordt bepaald, los van `width`/`height` waarin het beeld getekend wordt; null betekent wat het altijd was, dus tegels en posters veranderen niet. `tvHeroRequestBox(card, sourceAspectRatio)` is een pure functie in `tv_hero_artwork.dart` die de box in de bronratio geeft die de kaart precies dekt: breedtegebonden voor een bron die hoger is dan de kaart, hoogtegebonden voor een bredere. `tvHeroArtFor` levert daarvoor de bronratio mee (16:9 voor widescreen, 1 voor vierkant). Daarmee snijdt geen enkele server meer, en heeft de uitsnede één eigenaar: `BoxFit.cover` plus `TvHomeLayout.heroArtAlignment`, een benoemd token op `Alignment(0, -0.3)`. Dat anker houdt de bovenste 35 procent heel en neemt de rest van beide kanten; het is dezelfde keuze die de mockupfamilie tekent als `object-position: 50% 35%`, en hij vervangt de losse `topCenter` die op Plex dood was.
**Consequences:** Een 16:9-backdrop in de 2,465:1-kaart verliest nog steeds 28 procent van zijn hoogte; dat is een eigenschap van de kaartratio uit de northstar en geen bug. Wat verandert is wélke 28 procent, en dat dit nu op Plex, Jellyfin en Pleya Server hetzelfde is. Of `-0,3` het juiste anker is, is alleen op hardware te zien: het is een token, dus een ander getal is één regel. Vierkante art zonder backdrop komt op de brede kaart nooit in de scherpe tak (`billboardArt` geeft dan `fallback`), dus de vierkante tak van `tvHeroRequestBox` is op de hero onbereikbaar en alleen als algemene afbeelding correct; de posterfill-tak vraagt zijn eiland nog in 2:3 aan, wat voor een echte poster klopt en voor een vierkante bron een kleine servercrop laat staan. Dat is buiten HERO1 en staat hier genoteerd, niet gerepareerd. Negatieve controle: `test/widgets/tv_hero_artwork_request_test.dart` vroeg op de oude code 3840 bij 1500 aan, ratio 2,56, en eist 16:9 binnen de bucket-tolerantie; rood vóór, groen na. Gerichte suite van 78 tests groen, `flutter analyze` schoon op de vier geraakte bestanden. Hardwarebewijs staat open in HERO1 en wordt met build 249 gehaald.

## DEC-095: De Home-hero is full-bleed, de eerste rail piept eronder, en de railstapel wordt dichter

**Date:** 2026-09-04
**Status:** accepted
**Context:** HOME1 in `docs/tvos-fysieke-correctieronde.md`. Hoofdstuk 9.2 en 33.1 binden de hero als afgeronde kaart ín de pagina, 1770 bij 718 op inset 75, "nooit full bleed". Die kaart is 2,465:1 en toont 72 procent van een 16:9-backdrop; HERO1 (DEC-094) bepaalde wélke 72 procent, maar Michel wilde op 4 september het hele item in beeld: "volgens mij is in de hero namelijk nog niet hele item goed in beeld". Mockup 29 tekende vier richtingen (A northstar op maat, B kaart 2,0:1, C backdrop heel binnen de kaart, D full-bleed) en hij koos D. De eerste uitwerking van mockup 30 zette de railband op 654 achter de schermvullende backdrop en sneed het gezicht van het onderwerp af bij de mond; Michel: "dan moet wel het item goed in beeld zijn en niet half worden afgesneden door de volgende carroussel die erover heen staat. Dat neemt het effect van de hero weg." Vier landing-opties zijn getekend (`30-home-a1` tot en met `a4`): de rail piept, het beeld past rechts met geblurde vulling, alleen het label, en een mini-rail. Hij koos A1 en gaf akkoord op B tot en met E. Tegelijk is de rest van de pagina in de simulator gemeten: elk gefocust raillabel staat op ongeveer 372 referentiepixels met zwart erboven, het bijschrift reserveert twee regels synopsis, en samen met het volgende label past er precies één rail per scherm. Nieuw-markeringen zijn tekstpillen waar hoofdstuk 34 en 33.6 een amberpunt vragen (audit, divergentie 5), het raillabel "Recently Added Shows" staat in het Engels omdat `nl.i18n.json` de sleutel `discover.latestShows` mist (I18N5), en de topnav dimt niet mee onder een overlay (audit, divergentie 13).
**Decision:** (1) **De hero is full-bleed.** De backdrop staat op 16:9 schermvullend achter de topnav en de herotekst; op een 16:9-bron is er geen uitsnede meer, en voor een bron in een andere ratio blijft `TvHomeLayout.heroArtAlignment` uit DEC-094 de enige eigenaar van de uitsnede. De billboardkaart met ring, radius en schaduw uit 9.2 en 33.1 vervalt. Twee scrims: horizontaal van links voor de tekstkolom, verticaal boven voor de nav en onder naar de paginagrond, zodat de posters van de eerste rail op de grond staan en niet op het beeld. (2) **De landing is A1, de rail piept.** Op de 1080-referentie staat de tekstkolom op 579 tot 840 (titel 56, meta, synopsis van twee regels, CTA's van 60), het label van de eerste rail op 880 en de posters piepen 147 van 346 boven de onderrand. Het onderwerp van de backdrop staat daarmee heel in beeld; de eerste rail staat dat niet meer, en dat is de prijs die 9.2 hier betaalt. De rustfocus van 7.1 blijft de primaire CTA. (3) **Eén anker voor elke rij: het label van de gefocuste rail staat onder de navbalk.** Op DOWN uit de CTA's scrolt de feed daarheen, de herotekst dooft en de backdrop treedt terug; er blijft geen band voor de hero open. Northstar 02 zet het label van de eerste rail op 372, en die 242 referentiepixels onder de balk waren daar de zichtbare onderrand van de billboardkaart. Full-bleed heeft die kaart verwijderd, dus onder de nieuwe compositie hielden ze ruimte vrij voor iets dat er niet meer is: een railsectie is 524 hoog, dus bijna de helft van een rij ging op aan een backdrop waar de dim de contrasten al uit had gehaald, en op een donker beeld las dat als een lege band. Michel heeft dat op 4 september op de simulator gezien en gekozen om het anker helemaal weg te halen. De hero blijft bereikbaar: UP brengt hem terug in beeld (P1), en tijdens de scroll ernaartoe is hij zichtbaar; hij verandert daar niet (7.3, de rijfocus kiest de hero niet, en 9.6 pauzeert de rotatie zolang een rij focus heeft). (4) **Dieper op de pagina ankert het gefocuste label onder de nav.** Zodra de hero uit beeld is staat het label van de gefocuste rail op 132 in plaats van op 372, zodat de volgende rail er heel onder staat. (5) **Het bijschrift wordt korter.** Achttien referentiepixels boven de titel, titel 27, meta 20 met puntspatiëring, synopsis op één regel met ellipsis, 26 naar het volgende label. Dit amendeert DEC-087's "titel, meta en synopsis eronder" van twee regels naar één; de band 346, de 615-kaart en de 231-buren blijven. (6) **Styling en labels.** Nieuw is een amberpunt van 12 rechtsboven op de kaart, geen tekstpil; het vinkje is de witte schijf met donkere tick uit 33.5; `discover.latestShows` krijgt zijn Nederlandse vertaling "Recent toegevoegde series"; de topnav dimt naar 0,35 zodra een overlay open is. De profielchip toont de initiaal van het actieve profiel wanneer er geen beeld is, niet het merk. (7) **De poster-only fallback van 9.4 blijft** en werkt onder full-bleed als dezelfde poster sterk geblurd en donker als schermvulling met de scherpe poster als eiland rechts (`30-home-d`). Mockup 30 A1, B, C, D en E zijn bindend voor de compositie; `01-home.jpg` en `02-home-rail-focus.jpg` blijven bindend voor wat ze daarnaast vastleggen en krijgen een afwijkingsnotitie.
**Consequences:** Hoofdstuk 9.1, 9.2, 7.1 en 33.1/33.2 zijn aangepast; 9.3 en 9.6 staan er ongewijzigd naast en zijn nagelopen. De ambient tint van 9.3 blijft in fase 9 (`docs/tvos-unified-fase8-ambient-background-deviation.md`, goedgekeurd 1 september): mockup 30 B en C tekenen hem als eindstaat, de HOME1-bouwronde laat de paginagrond vlak en haalt hem niet naar voren. De code verandert nog niet; de bouw is een eigen ronde. Wat die ronde raakt: `TvContentFeed` legt de carousel niet meer in een `Padding` met `SizedBox` op `heroHeight`, maar schermvullend achter de kolom met de rijen als overlay en een scroll die op DOWN naar het anker gaat; `TvHeroBillboardCard` verliest ring, radius en schaduw en krijgt de twee scrims; `TvDiscoveryLayout.metaSynopsisMaxLines` gaat naar 1 en `railMetaGap` en de labelmarges volgen de maten hierboven; `NewContentBadge` krijgt op de TV-kaart de puntvorm; `nl.i18n.json` krijgt `latestShows`; `TvTopNavigation` krijgt de dim; de initiaal zonder profielbeeld tekent `ProfileAvatar` al, het merk verschijnt alleen zonder profiel. De bijschriftfonts volgen mockup 30 mee (titel 27, meta 20, synopsis 19 referentiepixels, raillabel 27 in plaats van 31,5: audit divergentie 6), en dat raakt ook de Films- en Serieslanding en Zoeken, die dezelfde rail tekenen. Voor de nav bovenop de content wisselt de shell zijn `Column` voor een `CustomMultiChildLayout` die de balk eerst uitmeet en als laatste tekent, en publiceert de gemeten bandhoogte via `TvShellSurface` zodat de feed de backdrop er precies achter kan trekken. Negatieve controle voor de bouwronde: een widgettest die `TvContentFeed` op het canonieke canvas pompt en eist dat de hero de volle contentbreedte en -hoogte inneemt zonder pagina-inset, dat het label van de eerste rail in de landing zichtbaar is met de band gedeeltelijk onder de viewport, en dat na DOWN het label op het anker staat; rood op de huidige code. Wat dit besluit niet doet: de featured selectie (9.5), het carouselcontract (9.6) en de late-data-regels (9.7) veranderen niet. Geaccepteerd door Michel op 4 september 2026: "Ik denk a 1 de rail piept en btme akkoord".

## DEC-096: Taalvoorkeuren in drie lagen, met een fallback die niets overschrijft

**Date:** 2026-09-04
**Status:** proposed
**Context:** LANG1 in `docs/tvos-fysieke-correctieronde.md`, sectie G van de personalisatie-opdracht van 4 september. Het per-serie taalgeheugen van 17 augustus (`TrackPreferenceStore`, de sticky-prioriteit in `TrackSelectionService`, de Plex-spiegeling) dekt de gevraagde journey grotendeels, maar de code legt drie dingen niet vast. De speler geeft bij de overgang naar de volgende aflevering de spelende track door als navigatiekeuze, en die staat boven de sticky keuze, dus een tijdelijke fallback wordt binnen de sessie permanent. De sleutel is een ratingKey op één server, terwijl hoofdstuk 14.8 de bronvoorkeur al op de canonieke identiteit sleutelt. En er is geen beheer: geen overzicht, geen terugzetten. De secties A tot en met F van de opdracht zijn in de ontwerpsessie niet beschikbaar; dit besluit gaat uit van het serverprofiel als globale laag en moet worden bijgesteld als die secties een eigen laag in Pleya vragen.
**Decision:** (1) **Drie lagen, in deze volgorde.** De uitdrukkelijke keuze in de lopende afspeelsessie, als bedoeling en niet als uitkomst; de serievoorkeur per profiel en logische serie (een film sleutelt op zichzelf); de globale profielvoorkeur, en dat is het gebruikersprofiel op de server, Plex-account of Jellyfin-gebruiker, zonder eigen laag in Pleya. (2) **De fallback is tijdelijk en voorspelbaar.** Audio: serievoorkeur, globale audiotaal, serverkeuze, standaardtrack. Ondertitels: serievoorkeur, globale ondertiteltaal in de profielmodus, uit. Nooit de eerste track in een willekeurige taal. Een onthouden "uit" wint altijd. Een fallback wordt niet opgeslagen, reist niet mee naar de volgende aflevering en meldt zich één keer met een toast. (3) **Een wijziging tijdens een serie is de serievoorkeur.** Geen driekeuzevraag; een toast bevestigt de keuze en zegt dat de globale voorkeur blijft. "Alleen deze aflevering" is de schakelaar Onthouden voor deze serie in het infopaneel. De globale voorkeur wordt alleen op de instellingenpagina gewijzigd, en alleen waar de backend een schrijfpad heeft. (4) **De sleutel wordt logisch.** `show:{genormaliseerde titel}` plus de sterke tokens op show-niveau waar bekend, per profiel; de serversleutel blijft als terugval leesbaar en wordt bij de eerstvolgende schrijfactie omgezet. Matching op taal, type, geforceerd en titel, nooit op stream-id. (5) **Beheer op één plek.** Mijn Pleya ▸ Instellingen ▸ Taal en ondertitels toont de globale voorkeur met bron, de serievoorkeuren met herkomst, en per serie de actie Gebruik globale voorkeur. De twee bestaande schakelaars verhuizen uit Afspelen hierheen. Mockup 31 A tot en met D is de compositie.
**Consequences:** `TrackSelectionService` moet een navigatiekeuze die zelf een fallback was niet boven de sticky keuze zetten, en `episode_navigation.dart` geeft de bedoeling door en niet de spelende track. `TrackPreferenceStore` krijgt een tweede sleutel en een leesvolgorde; `TrackLanguageChoice` krijgt een manier om een veld te wissen zodat een regel weer leeg kan worden. `PlayerToastController` krijgt een tweede regel en een langere duur. De pagina is een nieuwe Instellingen-subpagina in de bestaande geneste route, en `playback_settings_screen.dart` verliest twee rijen. Het Plex-schrijfpad voor accountinstellingen wordt gemeten voordat een rij op de pagina hem aanroept. Wat dit besluit niet doet: het verandert de Plex-spiegeling niet, het voegt geen Pleya-eigen globale laag toe, en het raakt de bronvoorkeur van 14.8 niet. Wordt het aangenomen, dan is LANG1 de bouwronde, met de drie negatieve controles die daar staan.
