///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsNl extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsNl({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.nl,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		super.$meta.setFlatMapFunction($meta.getTranslation); // copy base translations to super.$meta
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <nl>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	@override dynamic operator[](String key) => $meta.getTranslation(key) ?? super.$meta.getTranslation(key);

	late final TranslationsNl _root = this; // ignore: unused_field

	@override 
	TranslationsNl $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsNl(meta: meta ?? this.$meta);

	// Translations
	@override late final _TranslationsStatesNl states = _TranslationsStatesNl._(_root);
	@override late final _TranslationsAppNl app = _TranslationsAppNl._(_root);
	@override late final _TranslationsAuthNl auth = _TranslationsAuthNl._(_root);
	@override late final _TranslationsCommonNl common = _TranslationsCommonNl._(_root);
	@override late final _TranslationsScreensNl screens = _TranslationsScreensNl._(_root);
	@override late final _TranslationsUpdateNl update = _TranslationsUpdateNl._(_root);
	@override late final _TranslationsSettingsNl settings = _TranslationsSettingsNl._(_root);
	@override late final _TranslationsSearchNl search = _TranslationsSearchNl._(_root);
	@override late final _TranslationsHotkeysNl hotkeys = _TranslationsHotkeysNl._(_root);
	@override late final _TranslationsFileInfoNl fileInfo = _TranslationsFileInfoNl._(_root);
	@override late final _TranslationsMediaMenuNl mediaMenu = _TranslationsMediaMenuNl._(_root);
	@override late final _TranslationsRateSheetNl rateSheet = _TranslationsRateSheetNl._(_root);
	@override late final _TranslationsAccessibilityNl accessibility = _TranslationsAccessibilityNl._(_root);
	@override late final _TranslationsTooltipsNl tooltips = _TranslationsTooltipsNl._(_root);
	@override late final _TranslationsVideoControlsNl videoControls = _TranslationsVideoControlsNl._(_root);
	@override late final _TranslationsUserStatusNl userStatus = _TranslationsUserStatusNl._(_root);
	@override late final _TranslationsMessagesNl messages = _TranslationsMessagesNl._(_root);
	@override late final _TranslationsSubtitlingStylingNl subtitlingStyling = _TranslationsSubtitlingStylingNl._(_root);
	@override late final _TranslationsMpvConfigNl mpvConfig = _TranslationsMpvConfigNl._(_root);
	@override late final _TranslationsDialogNl dialog = _TranslationsDialogNl._(_root);
	@override late final _TranslationsProfilesNl profiles = _TranslationsProfilesNl._(_root);
	@override late final _TranslationsConnectionsNl connections = _TranslationsConnectionsNl._(_root);
	@override late final _TranslationsDiscoverNl discover = _TranslationsDiscoverNl._(_root);
	@override late final _TranslationsErrorsNl errors = _TranslationsErrorsNl._(_root);
	@override late final _TranslationsNoticesNl notices = _TranslationsNoticesNl._(_root);
	@override late final _TranslationsLibrariesNl libraries = _TranslationsLibrariesNl._(_root);
	@override late final _TranslationsAboutNl about = _TranslationsAboutNl._(_root);
	@override late final _TranslationsServerSelectionNl serverSelection = _TranslationsServerSelectionNl._(_root);
	@override late final _TranslationsHubDetailNl hubDetail = _TranslationsHubDetailNl._(_root);
	@override late final _TranslationsLogsNl logs = _TranslationsLogsNl._(_root);
	@override late final _TranslationsLicensesNl licenses = _TranslationsLicensesNl._(_root);
	@override late final _TranslationsNavigationNl navigation = _TranslationsNavigationNl._(_root);
	@override late final _TranslationsWatchlistNl watchlist = _TranslationsWatchlistNl._(_root);
	@override late final _TranslationsMyPleyaNl myPleya = _TranslationsMyPleyaNl._(_root);
	@override late final _TranslationsLiveTvNl liveTv = _TranslationsLiveTvNl._(_root);
	@override late final _TranslationsCollectionsNl collections = _TranslationsCollectionsNl._(_root);
	@override late final _TranslationsPlaylistsNl playlists = _TranslationsPlaylistsNl._(_root);
	@override late final _TranslationsWatchTogetherNl watchTogether = _TranslationsWatchTogetherNl._(_root);
	@override late final _TranslationsDownloadsNl downloads = _TranslationsDownloadsNl._(_root);
	@override late final _TranslationsShadersNl shaders = _TranslationsShadersNl._(_root);
	@override late final _TranslationsCompanionRemoteNl companionRemote = _TranslationsCompanionRemoteNl._(_root);
	@override late final _TranslationsVideoSettingsNl videoSettings = _TranslationsVideoSettingsNl._(_root);
	@override late final _TranslationsPerformanceOverlayNl performanceOverlay = _TranslationsPerformanceOverlayNl._(_root);
	@override late final _TranslationsExternalPlayerNl externalPlayer = _TranslationsExternalPlayerNl._(_root);
	@override late final _TranslationsMetadataEditNl metadataEdit = _TranslationsMetadataEditNl._(_root);
	@override late final _TranslationsMatchScreenNl matchScreen = _TranslationsMatchScreenNl._(_root);
	@override late final _TranslationsServerTasksNl serverTasks = _TranslationsServerTasksNl._(_root);
	@override late final _TranslationsTraktNl trakt = _TranslationsTraktNl._(_root);
	@override late final _TranslationsTrackersNl trackers = _TranslationsTrackersNl._(_root);
	@override late final _TranslationsAddServerNl addServer = _TranslationsAddServerNl._(_root);
	@override late final _TranslationsAddLocalFolderNl addLocalFolder = _TranslationsAddLocalFolderNl._(_root);
	@override late final _TranslationsPleyaShareNl pleyaShare = _TranslationsPleyaShareNl._(_root);
	@override late final _TranslationsSeerrNl seerr = _TranslationsSeerrNl._(_root);
	@override late final _TranslationsTautulliNl tautulli = _TranslationsTautulliNl._(_root);
	@override late final _TranslationsNowWatchingNl nowWatching = _TranslationsNowWatchingNl._(_root);
	@override late final _TranslationsSourcePickerNl sourcePicker = _TranslationsSourcePickerNl._(_root);
	@override late final _TranslationsUnifiedCatalogNl unifiedCatalog = _TranslationsUnifiedCatalogNl._(_root);
	@override late final _TranslationsTvNavigationNl tvNavigation = _TranslationsTvNavigationNl._(_root);
	@override late final _TranslationsTvMyPleyaNl tvMyPleya = _TranslationsTvMyPleyaNl._(_root);
	@override late final _TranslationsTvContextMenuNl tvContextMenu = _TranslationsTvContextMenuNl._(_root);
}

// Path: states
class _TranslationsStatesNl extends TranslationsStatesEn {
	_TranslationsStatesNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get emptyTitle => 'Nog niets hier';
	@override String get errorTitle => 'Er ging iets mis';
	@override String get offlineTitle => 'Je bent offline';
	@override String get offlineMessage => 'Maak opnieuw verbinding om dit te laden.';
}

// Path: app
class _TranslationsAppNl extends TranslationsAppEn {
	_TranslationsAppNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Pleya';
}

// Path: auth
class _TranslationsAuthNl extends TranslationsAuthEn {
	_TranslationsAuthNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get signIn => 'Inloggen';
	@override String get signInWithPlex => 'Inloggen met Plex';
	@override String get showQRCode => 'Toon QR-code';
	@override String get authenticate => 'Authenticeren';
	@override String get authenticationTimeout => 'Inloggen is niet voltooid. Probeer het opnieuw.';
	@override String get usingJellyfinInstead => 'Gebruik je een Jellyfin-server? Verbind met Jellyfin';
	@override String get scanQRToSignIn => 'Scan deze QR-code om in te loggen';
	@override String get waitingForAuth => 'Wachten op authenticatie...\nMeld je aan via je browser.';
	@override String get useBrowser => 'Gebruik browser';
	@override String get or => 'of';
	@override String get connectToJellyfin => 'Verbinden met Jellyfin';
	@override String get useQuickConnect => 'Quick Connect gebruiken';
	@override String get quickConnectInstructions => 'Open Quick Connect in Jellyfin en voer deze code in.';
	@override String get quickConnectWaiting => 'Wachten op goedkeuring…';
	@override String get quickConnectCancel => 'Annuleren';
	@override String get quickConnectExpired => 'Quick Connect is verlopen. Probeer opnieuw.';
	@override String get chooseHowToSignIn => 'Kies hoe je inlogt';
	@override String get chooseHowToSignInDescription => 'Pleya verbindt met je Plex- of Jellyfin-mediaserver. Kies er een om te beginnen.';
	@override String get tryAgain => 'Opnieuw proberen';
	@override String get plexTokenLabel => 'Plex-authenticatietoken';
	@override String get plexTokenHint => 'Voer je plex.tv-token in';
	@override String get serviceNotReady => 'Authenticatieservice is nog niet klaar. Probeer het zo opnieuw.';
}

// Path: common
class _TranslationsCommonNl extends TranslationsCommonEn {
	_TranslationsCommonNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get cancel => 'Annuleren';
	@override String get save => 'Opslaan';
	@override String get close => 'Sluiten';
	@override String get clear => 'Wissen';
	@override String get reset => 'Resetten';
	@override String get later => 'Later';
	@override String get submit => 'Verzenden';
	@override String get confirm => 'Bevestigen';
	@override String get retry => 'Opnieuw proberen';
	@override String get details => 'Details';
	@override String get logout => 'Uitloggen';
	@override String get unknown => 'Onbekend';
	@override String get refresh => 'Vernieuwen';
	@override String get yes => 'Ja';
	@override String get no => 'Nee';
	@override String get delete => 'Verwijderen';
	@override String get edit => 'Bewerken';
	@override String get shuffle => 'Willekeurig';
	@override String get addTo => 'Toevoegen aan...';
	@override String get createNew => 'Nieuw aanmaken';
	@override String get connect => 'Verbinden';
	@override String get disconnect => 'Verbinding verbreken';
	@override String get play => 'Afspelen';
	@override String get pause => 'Pauzeren';
	@override String get resume => 'Hervatten';
	@override String get error => 'Fout';
	@override String get search => 'Zoeken';
	@override String get home => 'Home';
	@override String get back => 'Terug';
	@override String get settings => 'Opties';
	@override String get mute => 'Dempen';
	@override String get ok => 'OK';
	@override String get off => 'Uit';
	@override String get on => 'Aan';
	@override String seasonNumber({required Object number}) => 'Seizoen ${number}';
	@override String episodeNumberTitle({required Object number, required Object title}) => 'Aflevering ${number} - ${title}';
	@override String chapterNumber({required Object number}) => 'Hoofdstuk ${number}';
	@override String get reconnect => 'Opnieuw verbinden';
	@override String get exit => 'Afsluiten';
	@override String get viewAll => 'Alles weergeven';
	@override String get checkingNetwork => 'Netwerk controleren...';
	@override String get refreshingServers => 'Servers vernieuwen...';
	@override String get loadingServers => 'Servers laden...';
	@override String get connectingToServers => 'Verbinden met servers...';
	@override String get startingOfflineMode => 'Offlinemodus starten...';
	@override String get loading => 'Laden...';
	@override String get fullscreen => 'Volledig scherm';
	@override String get exitFullscreen => 'Volledig scherm verlaten';
	@override String get pressBackAgainToExit => 'Druk nogmaals op terug om af te sluiten';
	@override String decreaseValue({required Object label}) => '${label} verlagen';
	@override String increaseValue({required Object label}) => '${label} verhogen';
}

// Path: screens
class _TranslationsScreensNl extends TranslationsScreensEn {
	_TranslationsScreensNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get licenses => 'Licenties';
	@override String get switchProfile => 'Wissel van profiel';
	@override String get whoIsWatching => 'Wie is er aan het kijken?';
	@override String get manageProfiles => 'Profielen beheren';
	@override String get subtitleStyling => 'Ondertitel opmaak';
	@override String get mpvConfig => 'mpv.conf';
	@override String get logs => 'Logbestanden';
}

// Path: update
class _TranslationsUpdateNl extends TranslationsUpdateEn {
	_TranslationsUpdateNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get available => 'Update beschikbaar';
	@override String versionAvailable({required Object version}) => 'Versie ${version} is beschikbaar';
	@override String currentVersion({required Object version}) => 'Huidig: ${version}';
	@override String get skipVersion => 'Deze versie overslaan';
	@override String get viewRelease => 'Bekijk release';
	@override String get latestVersion => 'Je hebt de nieuwste versie';
	@override String get checkFailed => 'Kon niet controleren op updates';
}

// Path: settings
class _TranslationsSettingsNl extends TranslationsSettingsEn {
	_TranslationsSettingsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get searchHint => 'Zoek in instellingen';
	@override String get urlLabel => 'URL';
	@override String get title => 'Instellingen';
	@override String get supportDeveloper => 'Steun Pleya';
	@override String get supportDeveloperDescription => 'Doneer via Liberapay om de ontwikkeling te steunen';
	@override String get language => 'Taal';
	@override String get theme => 'Thema';
	@override String get appearance => 'Uiterlijk';
	@override String get videoPlayback => 'Video afspelen';
	@override String get videoPlaybackDescription => 'Afspeelgedrag configureren';
	@override String get advanced => 'Geavanceerd';
	@override String get episodePosterMode => 'Aflevering poster stijl';
	@override String get seriesPoster => 'Serie poster';
	@override String get seasonPoster => 'Seizoen poster';
	@override String get episodeThumbnail => 'Miniatuur';
	@override String get showHeroSectionDescription => 'Toon uitgelichte inhoud carrousel op startscherm';
	@override String get secondsLabel => 'Seconden';
	@override String get minutesLabel => 'Minuten';
	@override String get secondsShort => 's';
	@override String get minutesShort => 'm';
	@override String durationHint({required Object min, required Object max}) => 'Voer duur in (${min}-${max})';
	@override String get systemTheme => 'Systeem';
	@override String get lightTheme => 'Licht';
	@override String get darkTheme => 'Donker';
	@override String get oledTheme => 'OLED';
	@override String get libraryDensity => 'Bibliotheek dichtheid';
	@override String get compact => 'Compact';
	@override String get comfortable => 'Comfortabel';
	@override String get viewMode => 'Weergavemodus';
	@override String get gridView => 'Raster';
	@override String get listView => 'Lijst';
	@override String get showHeroSection => 'Toon hoofdsectie';
	@override String get hoverExpandCards => 'Kaarten uitklappen bij hover';
	@override String get hoverExpandCardsDescription => 'Toon een voorbeeldkaart met snelknoppen als je over een poster zweeft';
	@override String get continueWatchingAction => 'Actie voor Doorgaan met kijken';
	@override String get continueWatchingPlay => 'Afspelen';
	@override String get continueWatchingDetails => 'Details openen';
	@override String get episodeAction => 'Afleveringsactie';
	@override String get episodePlay => 'Afspelen';
	@override String get episodeDetails => 'Details openen';
	@override String get useGlobalHubs => 'Startlayout gebruiken';
	@override String get useGlobalHubsDescription => 'Toon gecombineerde home-hubs. Anders bibliotheekaanbevelingen gebruiken.';
	@override String get showServerNameOnHubs => 'Servernaam tonen bij hubs';
	@override String get showServerNameOnHubsDescription => 'Toon servernamen altijd in hubtitels.';
	@override String get groupLibrariesByServer => 'Bibliotheken groeperen per server';
	@override String get groupLibrariesByServerDescription => 'Groepeer zijbalkbibliotheken onder elke mediaserver.';
	@override String get alwaysKeepSidebarOpen => 'Zijbalk altijd open houden';
	@override String get alwaysKeepSidebarOpenDescription => 'Zijbalk blijft uitgevouwen en inhoudsgebied past zich aan';
	@override String get showUnwatchedCount => 'Aantal ongekeken tonen';
	@override String get showUnwatchedCountDescription => 'Toon aantal ongekeken afleveringen bij series en seizoenen';
	@override String get showEpisodeNumberOnCards => 'Afleveringsnummer op kaarten tonen';
	@override String get showEpisodeNumberOnCardsDescription => 'Toon seizoen- en afleveringsnummer op afleveringskaarten';
	@override String get showSeasonPostersOnTabs => 'Toon seizoensposters op tabbladen';
	@override String get showSeasonPostersOnTabsDescription => 'Toon de poster van elk seizoen boven het tabblad';
	@override String get tvFullCardLayout => 'Volledige tv-kaarten';
	@override String get tvFullCardLayoutDescription => 'Gebruik tv-kaarten met alleen afbeeldingen en namen van acteurs als overlay';
	@override String get focusGlow => 'Focusgloed';
	@override String get focusGlowDescription => 'Toon een zachte gloed rond de kaart met focus';
	@override String get hideSpoilers => 'Spoilers voor ongekeken afleveringen verbergen';
	@override String get hideSpoilersDescription => 'Vervaag miniaturen en beschrijvingen voor niet-bekeken afleveringen';
	@override String get playerBackend => 'Speler backend';
	@override String get exoPlayer => 'ExoPlayer (Aanbevolen)';
	@override String get mpv => 'mpv';
	@override String get hardwareDecoding => 'Hardware decodering';
	@override String get hardwareDecodingDescription => 'Gebruik hardware versnelling indien beschikbaar';
	@override String get bufferSize => 'Buffer grootte';
	@override String bufferSizeMB({required Object size}) => '${size}MB';
	@override String get bufferSizeAuto => 'Auto (Aanbevolen)';
	@override String bufferSizeWarning({required Object heap, required Object size}) => '${heap}MB geheugen beschikbaar. Een buffer van ${size}MB kan afspelen beïnvloeden.';
	@override String get defaultQualityTitle => 'Standaardkwaliteit';
	@override String get defaultQualityDescription => 'Wordt gebruikt bij het starten van de weergave. Lagere waarden verminderen de bandbreedte.';
	@override String get subtitleStyling => 'Ondertitel opmaak';
	@override String get subtitleStylingDescription => 'Pas ondertitel uiterlijk aan';
	@override String get smallSkipDuration => 'Korte skip duur';
	@override String get largeSkipDuration => 'Lange skip duur';
	@override String get rewindOnResume => 'Terugspoelen bij hervatten';
	@override String secondsUnit({required Object seconds}) => '${seconds} seconden';
	@override String get defaultSleepTimer => 'Standaard slaap timer';
	@override String minutesUnit({required Object minutes}) => 'bij ${minutes} minuten';
	@override String get rememberTrackSelections => 'Onthoud track selecties per serie/film';
	@override String get rememberTrackSelectionsDescription => 'Onthoud audio- en ondertitelkeuzes per titel';
	@override String get showChapterMarkersOnTimeline => 'Hoofdstukmarkeringen op tijdlijn tonen';
	@override String get showChapterMarkersOnTimelineDescription => 'Verdeel de tijdlijn bij hoofdstukgrenzen';
	@override String get clickVideoTogglesPlayback => 'Klik op de video om afspelen/pauzeren te wisselen.';
	@override String get clickVideoTogglesPlaybackDescription => 'Klik op video om af te spelen/pauzeren in plaats van bediening te tonen.';
	@override String get videoPlayerControls => 'Videospeler bediening';
	@override String get keyboardShortcuts => 'Toetsenbord sneltoetsen';
	@override String get keyboardShortcutsDescription => 'Pas toetsenbord sneltoetsen aan';
	@override String get videoPlayerNavigation => 'Videospeler navigatie';
	@override String get videoPlayerNavigationDescription => 'Gebruik pijltjestoetsen om door de videospeler bediening te navigeren';
	@override String get watchTogetherRelay => 'Samen Kijken Relay';
	@override String get watchTogetherRelayDescription => 'Stel een aangepaste relay in. Iedereen moet dezelfde server gebruiken.';
	@override String get watchTogetherRelayHint => 'https://mijn-relay.voorbeeld.nl';
	@override String get crashReporting => 'Crashrapportage';
	@override String get crashReportingDescription => 'Crashrapporten verzenden om de app te verbeteren';
	@override String get debugLogging => 'Debug logging';
	@override String get debugLoggingDescription => 'Schakel gedetailleerde logging in voor probleemoplossing';
	@override String get viewLogs => 'Bekijk logs';
	@override String get viewLogsDescription => 'Bekijk applicatie logs';
	@override String get clearCache => 'Cache wissen';
	@override String get clearCacheDescription => 'Wis gecachete afbeeldingen en gegevens. Inhoud kan langzamer laden.';
	@override String get clearCacheSuccess => 'Cache succesvol gewist';
	@override String get resetSettings => 'Instellingen resetten';
	@override String get resetSettingsDescription => 'Standaardinstellingen herstellen. Dit kan niet ongedaan worden gemaakt.';
	@override String get resetSettingsSuccess => 'Instellingen succesvol gereset';
	@override String get backup => 'Back-up';
	@override String get exportSettings => 'Instellingen exporteren';
	@override String get exportSettingsDescription => 'Sla je voorkeuren op in een bestand';
	@override String get exportSettingsSuccess => 'Instellingen geëxporteerd';
	@override String get exportSettingsFailed => 'Kon instellingen niet exporteren';
	@override String get importSettings => 'Instellingen importeren';
	@override String get importSettingsDescription => 'Voorkeuren herstellen vanuit een bestand';
	@override String get importSettingsConfirm => 'Hiermee worden je huidige instellingen vervangen. Doorgaan?';
	@override String get importSettingsSuccess => 'Instellingen geïmporteerd';
	@override String get importSettingsFailed => 'Kon instellingen niet importeren';
	@override String get importSettingsInvalidFile => 'Dit bestand is geen geldige Pleya-export';
	@override String get importSettingsNoUser => 'Meld je aan voordat je instellingen importeert';
	@override String get shortcutsReset => 'Sneltoetsen gereset naar standaard';
	@override String get about => 'Over';
	@override String get aboutDescription => 'App informatie en licenties';
	@override String get updates => 'Updates';
	@override String get updateAvailable => 'Update beschikbaar';
	@override String get checkForUpdates => 'Controleer op updates';
	@override String get autoCheckUpdatesOnStartup => 'Automatisch controleren op updates bij opstarten';
	@override String get autoCheckUpdatesOnStartupDescription => 'Melden wanneer er bij start een update beschikbaar is';
	@override String get validationErrorEnterNumber => 'Voer een geldig nummer in';
	@override String validationErrorDuration({required Object min, required Object max, required Object unit}) => 'Duur moet tussen ${min} en ${max} ${unit} zijn';
	@override String shortcutAlreadyAssigned({required Object action}) => 'Sneltoets al toegewezen aan ${action}';
	@override String shortcutUpdated({required Object action}) => 'Sneltoets bijgewerkt voor ${action}';
	@override String get autoSkip => 'Automatisch Overslaan';
	@override String get autoSkipIntro => 'Intro Automatisch Overslaan';
	@override String get autoSkipIntroDescription => 'Intro-markeringen in afleveringen na enkele seconden automatisch overslaan';
	@override String get autoSkipCredits => 'Credits Automatisch Overslaan';
	@override String get autoSkipCreditsDescription => 'Credits automatisch overslaan en volgende aflevering afspelen';
	@override String get forceSkipMarkerFallback => 'Fallbackmarkeringen afdwingen';
	@override String get forceSkipMarkerFallbackDescription => 'Gebruik hoofdstuktitelpatronen, zelfs wanneer Plex markeringen heeft';
	@override String get autoSkipDelay => 'Vertraging Automatisch Overslaan';
	@override String autoSkipDelayDescription({required Object seconds}) => '${seconds} seconden wachten voor automatisch overslaan';
	@override String get introPattern => 'Intromarkeringspatroon';
	@override String get introPatternDescription => 'Reguliere expressie om intromarkeringen in hoofdstuktitels te herkennen';
	@override String get creditsPattern => 'Aftitelingmarkeringspatroon';
	@override String get creditsPatternDescription => 'Reguliere expressie om aftitelingmarkeringen in hoofdstuktitels te herkennen';
	@override String get invalidRegex => 'Ongeldige reguliere expressie';
	@override String get downloads => 'Downloads';
	@override String get downloadLocationDescription => 'Kies waar gedownloade content wordt opgeslagen';
	@override String get downloadLocationDefault => 'Standaard (App-opslag)';
	@override String get downloadLocationCustom => 'Aangepaste Locatie';
	@override String get selectFolder => 'Selecteer Map';
	@override String get resetToDefault => 'Herstel naar Standaard';
	@override String currentPath({required Object path}) => 'Huidig: ${path}';
	@override String get downloadLocationChanged => 'Downloadlocatie gewijzigd';
	@override String get downloadLocationReset => 'Downloadlocatie hersteld naar standaard';
	@override String get downloadLocationInvalid => 'Geselecteerde map is niet beschrijfbaar';
	@override String get downloadLocationSelectError => 'Kan map niet selecteren';
	@override String get downloadOnWifiOnly => 'Alleen via WiFi downloaden';
	@override String get downloadOnWifiOnlyDescription => 'Voorkom downloads bij gebruik van mobiele data';
	@override String get autoRemoveWatchedDownloads => 'Bekeken downloads automatisch verwijderen';
	@override String get autoRemoveWatchedDownloadsDescription => 'Bekeken downloads automatisch verwijderen';
	@override String get cellularDownloadBlocked => 'Downloads zijn geblokkeerd via mobiel netwerk. Gebruik WiFi of wijzig de instelling.';
	@override String get maxVolume => 'Maximaal volume';
	@override String get maxVolumeDescription => 'Volume boven 100% toestaan voor stille media';
	@override String maxVolumePercent({required Object percent}) => '${percent}%';
	@override String get discordRichPresence => 'Discord Rich Presence';
	@override String get discordRichPresenceDescription => 'Toon op Discord wat je aan het kijken bent';
	@override String get trakt => 'Trakt';
	@override String get traktDescription => 'Kijkgeschiedenis synchroniseren met Trakt';
	@override String get trackers => 'Trackers';
	@override String get trackersDescription => 'Voortgang synchroniseren met Trakt, MyAnimeList, AniList en Simkl';
	@override String get companionRemoteServer => 'Companion Remote-server';
	@override String get companionRemoteServerDescription => 'Sta mobiele apparaten op je netwerk toe om deze app te bedienen';
	@override String get autoPip => 'Automatische beeld-in-beeld';
	@override String get autoPipDescription => 'Ga naar picture-in-picture bij verlaten tijdens afspelen';
	@override String get matchContentFrameRate => 'Inhoudsframesnelheid afstemmen';
	@override String get matchContentFrameRateDescription => 'Stem schermverversing af op videocontent';
	@override String get matchRefreshRate => 'Verversingssnelheid afstemmen';
	@override String get matchRefreshRateDescription => 'Stem schermverversing af in volledig scherm';
	@override String get matchDynamicRange => 'Dynamisch bereik afstemmen';
	@override String get matchDynamicRangeDescription => 'Schakel HDR in voor HDR-content en daarna terug naar SDR';
	@override String get displaySwitchDelay => 'Vertraging bij schermwisseling';
	@override String get tunneledPlayback => 'Getunnelde weergave';
	@override String get tunneledPlaybackDescription => 'Gebruik videotunneling. Schakel uit als HDR-afspelen zwart beeld geeft.';
	@override String get dvConversionMode => 'Dolby Vision-conversie';
	@override String get dvConversionModeDescription => 'Kies hoe ExoPlayer Dolby Vision Profile 7-bestanden verwerkt.';
	@override String get dvConversionAuto => 'Auto';
	@override String get dvConversionNative => 'Native / uitgeschakeld';
	@override String get dvConversionDv81 => 'P7 → P8.1';
	@override String get dvConversionHevcStrip => 'P7 → HEVC';
	@override String get dvConversionAutoDescription => 'Gebruik apparaatdetectie en normaal fallbackgedrag';
	@override String get dvConversionNativeDescription => 'Forceer native DV7 en onderdruk DV-conversie opnieuw proberen';
	@override String get dvConversionDv81Description => 'Forceer inline RPU-conversie naar Dolby Vision-profiel 8.1';
	@override String get dvConversionHevcStripDescription => 'Strip Dolby Vision RPU/EL-lagen en presenteer gewone HEVC';
	@override String get requireProfileSelectionOnOpen => 'Vraag om profiel bij openen';
	@override String get requireProfileSelectionOnOpenDescription => 'Toon profielselectie telkens wanneer de app wordt geopend';
	@override String get forceTvMode => 'TV-modus forceren';
	@override String get forceTvModeDescription => 'Forceer TV-indeling. Voor apparaten zonder autodetectie. Herstart vereist.';
	@override String get startInFullscreen => 'Starten in volledig scherm';
	@override String get startInFullscreenDescription => 'Open Pleya bij het starten in volledig scherm';
	@override String get exitFullscreenOnPlayerClose => 'Volledig scherm verlaten bij sluiten speler';
	@override String get exitFullscreenOnPlayerCloseDescription => 'Verlaat automatisch volledig scherm wanneer de videospeler wordt gesloten';
	@override String get autoHidePerformanceOverlay => 'Prestatie-overlay automatisch verbergen';
	@override String get autoHidePerformanceOverlayDescription => 'Laat de prestatie-overlay meevervagen met de afspeelknoppen';
	@override String get showNavBarLabels => 'Navigatiebalk labels tonen';
	@override String get showNavBarLabelsDescription => 'Tekstlabels onder de pictogrammen van de navigatiebalk weergeven';
	@override String get startupSection => 'Opstartsectie';
	@override String get startupSectionDescription => 'Kies welke sectie Pleya opent bij het opstarten';
	@override String get liveTvDefaultFavorites => 'Standaard favoriete zenders';
	@override String get liveTvDefaultFavoritesDescription => 'Toon alleen favoriete zenders bij het openen van Live TV';
	@override String get display => 'Weergave';
	@override String get homeScreen => 'Startscherm';
	@override String get navigation => 'Navigatie';
	@override String get window => 'Venster';
	@override String get content => 'Inhoud';
	@override String get player => 'Speler';
	@override String get subtitlesAndConfig => 'Ondertitels en configuratie';
	@override String get seekAndTiming => 'Zoeken en timing';
	@override String get audio => 'Audio';
	@override String get audioSyncOffsetDescription => 'Verschuif audio ten opzichte van beeld voor elke titel';
	@override String get behavior => 'Gedrag';
	@override String get personalizedRecommendations => 'Persoonlijke aanbevelingen';
	@override String get personalizedRecommendationsDescription => 'Leert je smaak op dit apparaat voor Aanbevolen voor jou en meer. Er verlaat niets je apparaat.';
}

// Path: search
class _TranslationsSearchNl extends TranslationsSearchEn {
	_TranslationsSearchNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get hint => 'Zoek films, series, muziek...';
	@override String get tryDifferentTerm => 'Probeer een andere zoekterm';
	@override String get searchYourMedia => 'Zoek in je media';
	@override String get enterTitleActorOrKeyword => 'Voer een titel, acteur of trefwoord in';
	@override String get recentSearches => 'Recent gezocht';
	@override String get clearHistory => 'Wissen';
	@override late final _TranslationsSearchFiltersNl filters = _TranslationsSearchFiltersNl._(_root);
}

// Path: hotkeys
class _TranslationsHotkeysNl extends TranslationsHotkeysEn {
	_TranslationsHotkeysNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String setShortcutFor({required Object actionName}) => 'Stel sneltoets in voor ${actionName}';
	@override String get clearShortcut => 'Wis sneltoets';
	@override String get noShortcutSet => 'Geen sneltoets ingesteld';
	@override String get currentShortcut => 'Huidige sneltoets:';
	@override late final _TranslationsHotkeysActionsNl actions = _TranslationsHotkeysActionsNl._(_root);
}

// Path: fileInfo
class _TranslationsFileInfoNl extends TranslationsFileInfoEn {
	_TranslationsFileInfoNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Bestand info';
	@override String get video => 'Video';
	@override String get audio => 'Audio';
	@override String get file => 'Bestand';
	@override String get advanced => 'Geavanceerd';
	@override String get codec => 'Codec';
	@override String get resolution => 'Resolutie';
	@override String get bitrate => 'Bitrate';
	@override String get frameRate => 'Frame rate';
	@override String get aspectRatio => 'Beeldverhouding';
	@override String get profile => 'Profiel';
	@override String get bitDepth => 'Bit diepte';
	@override String get colorSpace => 'Kleurruimte';
	@override String get colorRange => 'Kleurbereik';
	@override String get colorPrimaries => 'Kleurprimaires';
	@override String get chromaSubsampling => 'Chroma subsampling';
	@override String get channels => 'Kanalen';
	@override String get subtitles => 'Ondertitels';
	@override String get overallBitrate => 'Totale bitrate';
	@override String get path => 'Pad';
	@override String get size => 'Grootte';
	@override String get container => 'Container';
	@override String get duration => 'Duur';
	@override String get optimizedForStreaming => 'Geoptimaliseerd voor streaming';
	@override String get has64bitOffsets => '64-bit Offsets';
}

// Path: mediaMenu
class _TranslationsMediaMenuNl extends TranslationsMediaMenuEn {
	_TranslationsMediaMenuNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get markAsWatched => 'Markeer als gekeken';
	@override String get markAsUnwatched => 'Markeer als ongekeken';
	@override String get removeFromContinueWatching => 'Verwijder uit Doorgaan met kijken';
	@override String get viewDetails => 'Details bekijken';
	@override String get goToSeries => 'Ga naar serie';
	@override String get shufflePlay => 'Willekeurig afspelen';
	@override String get shuffleNotAvailableOffline => 'Shuffle is offline niet beschikbaar';
	@override String get fileInfo => 'Bestand info';
	@override String get deleteFromServer => 'Verwijderen van server';
	@override String get confirmDelete => 'Deze media en bestanden van je server verwijderen?';
	@override String get deleteMultipleWarning => 'Dit omvat alle afleveringen en hun bestanden.';
	@override String get mediaDeletedSuccessfully => 'Media-item succesvol verwijderd';
	@override String get mediaFailedToDelete => 'Verwijderen van media-item mislukt';
	@override String get rate => 'Beoordelen';
	@override String get playFromBeginning => 'Afspelen vanaf het begin';
	@override String get playVersion => 'Versie afspelen...';
}

// Path: rateSheet
class _TranslationsRateSheetNl extends TranslationsRateSheetEn {
	_TranslationsRateSheetNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Beoordelen';
	@override String get server => 'Server';
	@override String starValue({required Object rating}) => '${rating} / 5';
	@override String scoreValue({required Object score}) => '${score} / 10';
	@override String get setScore => 'Score instellen';
	@override String get notRated => 'Niet beoordeeld';
	@override String get liked => 'Geliket';
	@override String get notLiked => 'Niet geliket';
	@override String get saved => 'Opgeslagen';
	@override String get notAvailable => 'Geen match gevonden';
	@override String get noConnectedTrackers => 'Verbind een tracker in Instellingen om daar te beoordelen.';
}

// Path: accessibility
class _TranslationsAccessibilityNl extends TranslationsAccessibilityEn {
	_TranslationsAccessibilityNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String mediaCardMovie({required Object title}) => '${title}, film';
	@override String mediaCardShow({required Object title}) => '${title}, TV-serie';
	@override String mediaCardEpisode({required Object title, required Object episodeInfo}) => '${title}, ${episodeInfo}';
	@override String mediaCardSeason({required Object title, required Object seasonInfo}) => '${title}, ${seasonInfo}';
	@override String get mediaCardWatched => 'bekeken';
	@override String mediaCardPartiallyWatched({required Object percent}) => '${percent} procent bekeken';
	@override String get mediaCardUnwatched => 'niet bekeken';
	@override String get tapToPlay => 'Tik om af te spelen';
}

// Path: tooltips
class _TranslationsTooltipsNl extends TranslationsTooltipsEn {
	_TranslationsTooltipsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get shufflePlay => 'Willekeurig afspelen';
	@override String get playTrailer => 'Trailer afspelen';
	@override String get markAsWatched => 'Markeer als gekeken';
	@override String get markAsUnwatched => 'Markeer als ongekeken';
}

// Path: videoControls
class _TranslationsVideoControlsNl extends TranslationsVideoControlsEn {
	_TranslationsVideoControlsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get audioLabel => 'Audio';
	@override String get subtitlesLabel => 'Ondertitels';
	@override String get resetToZero => 'Reset naar 0ms';
	@override String addTime({required Object amount, required Object unit}) => '+${amount}${unit}';
	@override String minusTime({required Object amount, required Object unit}) => '-${amount}${unit}';
	@override String playsLater({required Object label}) => '${label} speelt later af';
	@override String playsEarlier({required Object label}) => '${label} speelt eerder af';
	@override String get noOffset => 'Geen offset';
	@override String get letterbox => 'Letterbox';
	@override String get fillScreen => 'Vul scherm';
	@override String get stretch => 'Uitrekken';
	@override String get lockRotation => 'Vergrendel rotatie';
	@override String get unlockRotation => 'Ontgrendel rotatie';
	@override String get timerActive => 'Timer actief';
	@override String playbackWillPauseIn({required Object duration}) => 'Afspelen wordt gepauzeerd over ${duration}';
	@override String get sleepTimerEndOfVideo => 'Einde van huidige video';
	@override String get sleepTimerStopAtHeader => 'Stoppen bij';
	@override String get sleepTimerDurationHeader => 'Timer';
	@override String get playbackWillPauseAtEnd => 'Afspelen wordt gepauzeerd aan het einde van deze video';
	@override String get stillWatching => 'Kijk je nog?';
	@override String pausingIn({required Object seconds}) => 'Pauze over ${seconds}s';
	@override String get continueWatching => 'Doorgaan';
	@override String get autoPlayNext => 'Automatisch volgende afspelen';
	@override String get playNext => 'Volgende afspelen';
	@override String get playButton => 'Afspelen';
	@override String get pauseButton => 'Pauzeren';
	@override String seekBackwardButton({required Object seconds}) => 'Terugspoelen ${seconds} seconden';
	@override String seekForwardButton({required Object seconds}) => 'Vooruitspoelen ${seconds} seconden';
	@override String get previousButton => 'Vorige aflevering';
	@override String get nextButton => 'Volgende aflevering';
	@override String get previousChapterButton => 'Vorig hoofdstuk';
	@override String get nextChapterButton => 'Volgend hoofdstuk';
	@override String get muteButton => 'Dempen';
	@override String get unmuteButton => 'Dempen opheffen';
	@override String get settingsButton => 'Afspeelinstellingen';
	@override String get tracksButton => 'Audio en ondertitels';
	@override String get chaptersButton => 'Hoofdstukken';
	@override String get versionsButton => 'Videoversies';
	@override String get versionQualityButton => 'Versie en kwaliteit';
	@override String get versionColumnHeader => 'Versie';
	@override String get qualityColumnHeader => 'Kwaliteit';
	@override String get qualityOriginal => 'Origineel';
	@override String qualityPresetLabel({required Object resolution, required Object bitrate}) => '${resolution}p ${bitrate} Mbps';
	@override String qualityBandwidthEstimate({required Object bitrate}) => '~${bitrate} Mbps';
	@override String get transcodeUnavailableFallback => 'Transcoderen niet beschikbaar — originele kwaliteit wordt afgespeeld';
	@override String get pipButton => 'Beeld-in-beeld modus';
	@override String get aspectRatioButton => 'Beeldverhouding';
	@override String get ambientLighting => 'Omgevingsverlichting';
	@override String get ambientIntensitySubtle => 'Subtiel';
	@override String get ambientIntensityBalanced => 'Evenwichtig';
	@override String get ambientIntensityBright => 'Fel';
	@override late final _TranslationsVideoControlsTvPanelNl tvPanel = _TranslationsVideoControlsTvPanelNl._(_root);
	@override String get fullscreenButton => 'Volledig scherm activeren';
	@override String get exitFullscreenButton => 'Volledig scherm verlaten';
	@override String get alwaysOnTopButton => 'Altijd bovenop';
	@override String get rotationLockButton => 'Rotatievergrendeling';
	@override String get lockScreen => 'Vergrendel scherm';
	@override String get screenLockButton => 'Schermvergrendeling';
	@override String get longPressToUnlock => 'Lang indrukken om te ontgrendelen';
	@override String get timelineSlider => 'Videotijdlijn';
	@override String get volumeSlider => 'Volumeniveau';
	@override String get volumeHandledByDevice => 'Volume wordt tijdens doorvoer door je audioapparaat geregeld';
	@override String endsAt({required Object time}) => 'Eindigt om ${time}';
	@override String get pipActive => 'Afspelen in beeld-in-beeld';
	@override String get pipFailed => 'Beeld-in-beeld kon niet worden gestart';
	@override String get screenshotSaved => 'Schermafbeelding opgeslagen';
	@override String zoomPercent({required Object percent}) => 'Zoom ${percent}%';
	@override late final _TranslationsVideoControlsPipErrorsNl pipErrors = _TranslationsVideoControlsPipErrorsNl._(_root);
	@override String get chapters => 'Hoofdstukken';
	@override String get noChaptersAvailable => 'Geen hoofdstukken beschikbaar';
	@override String get queue => 'Wachtrij';
	@override String get noQueueItems => 'Geen items in de wachtrij';
	@override String get searchSubtitles => 'Ondertitels zoeken';
	@override String get language => 'Taal';
	@override String get noSubtitlesFound => 'Geen ondertitels gevonden';
	@override String get downloadedSubtitle => 'Gedownload';
	@override String get noSubtitlesAvailable => 'Geen ondertitels beschikbaar';
	@override String get noAudioTracksAvailable => 'Geen audiotracks beschikbaar';
	@override String get noTracksAvailable => 'Geen tracks beschikbaar';
	@override String get subtitleDownloaded => 'Ondertitel gedownload';
	@override String get subtitleDownloadFailed => 'Ondertitel downloaden mislukt';
	@override String get searchLanguages => 'Talen zoeken...';
	@override String get airplayButton => 'AirPlay';
}

// Path: userStatus
class _TranslationsUserStatusNl extends TranslationsUserStatusEn {
	_TranslationsUserStatusNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get admin => 'Beheerder';
	@override String get restricted => 'Beperkt';
	@override String get protected => 'Beschermd';
	@override String get current => 'HUIDIG';
}

// Path: messages
class _TranslationsMessagesNl extends TranslationsMessagesEn {
	_TranslationsMessagesNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get markedAsWatched => 'Gemarkeerd als gekeken';
	@override String get markedAsUnwatched => 'Gemarkeerd als ongekeken';
	@override String get markedAsWatchedOffline => 'Gemarkeerd als gekeken (sync wanneer online)';
	@override String get markedAsUnwatchedOffline => 'Gemarkeerd als ongekeken (sync wanneer online)';
	@override String autoRemovedWatchedDownload({required Object title}) => 'Automatisch verwijderd: ${title}';
	@override String get removedFromContinueWatching => 'Verwijderd uit Doorgaan met kijken';
	@override String get errorLoading => 'Fout';
	@override String get fileInfoNotAvailable => 'Bestand informatie niet beschikbaar';
	@override String get errorLoadingFileInfo => 'Fout bij laden bestand info';
	@override String get errorLoadingSeries => 'Fout bij laden serie';
	@override String get musicNotSupported => 'Muziek afspelen wordt nog niet ondersteund';
	@override String get noDescriptionAvailable => 'Geen beschrijving beschikbaar';
	@override String get noProfilesAvailable => 'Geen profielen beschikbaar';
	@override String get contactAdminForProfiles => 'Neem contact op met je serverbeheerder om profielen toe te voegen';
	@override String get unableToDetermineLibrarySection => 'Kan bibliotheeksectie voor dit item niet bepalen';
	@override String get logsCleared => 'Logs gewist';
	@override String get logsCopied => 'Logs gekopieerd naar klembord';
	@override String get noLogsAvailable => 'Geen logs beschikbaar';
	@override String libraryScanning({required Object title}) => 'Scannen "${title}"...';
	@override String libraryScanStarted({required Object title}) => 'Bibliotheek scan gestart voor "${title}"';
	@override String get libraryScanFailed => 'Kon bibliotheek niet scannen';
	@override String metadataRefreshing({required Object title}) => 'Metadata vernieuwen voor "${title}"...';
	@override String metadataRefreshStarted({required Object title}) => 'Metadata vernieuwen gestart voor "${title}"';
	@override String get metadataRefreshFailed => 'Kon metadata niet vernieuwen';
	@override String get logoutConfirm => 'Weet je zeker dat je wilt uitloggen?';
	@override String get noSeasonsFound => 'Geen seizoenen gevonden';
	@override String get seasonsLoadFailed => 'Kan seizoenen niet laden';
	@override String get noEpisodesFound => 'Geen afleveringen gevonden in eerste seizoen';
	@override String get noEpisodesFoundGeneral => 'Geen afleveringen gevonden';
	@override String get episodesLoadFailed => 'Kan afleveringen niet laden';
	@override String get noResultsFound => 'Geen resultaten gevonden';
	@override String sleepTimerSet({required Object label}) => 'Slaap timer ingesteld voor ${label}';
	@override String get noItemsAvailable => 'Geen items beschikbaar';
	@override String get failedToCreatePlayQueueNoItems => 'Kan afspeelwachtrij niet maken - geen items';
	@override String failedPlayback({required Object action}) => 'Afspelen van ${action} mislukt';
	@override String get switchingToCompatiblePlayer => 'Overschakelen naar compatibele speler...';
	@override String get serverLimitTitle => 'Afspelen mislukt';
	@override String get serverLimitBody => 'Serverfout (HTTP 500). Waarschijnlijk weigerde een bandbreedte-/transcodeerlimiet deze sessie. Vraag de eigenaar dit aan te passen.';
	@override String get logsUploaded => 'Logs geüpload';
	@override String get logsUploadFailed => 'Uploaden van logs mislukt';
	@override String get logId => 'Log-ID';
	@override String get dvdNotSupported => 'Dvd-schijven worden op dit apparaat niet ondersteund.';
	@override String get discNotSupported => 'Dit schijfformaat wordt op dit apparaat niet ondersteund.';
}

// Path: subtitlingStyling
class _TranslationsSubtitlingStylingNl extends TranslationsSubtitlingStylingEn {
	_TranslationsSubtitlingStylingNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get text => 'Tekst';
	@override String get border => 'Rand';
	@override String get background => 'Achtergrond';
	@override String get fontSize => 'Lettergrootte';
	@override String get textColor => 'Tekstkleur';
	@override String get borderSize => 'Rand grootte';
	@override String get borderColor => 'Randkleur';
	@override String get backgroundOpacity => 'Achtergrond transparantie';
	@override String get backgroundColor => 'Achtergrondkleur';
	@override String get position => 'Positie';
	@override String get assOverride => 'ASS-overschrijving';
	@override String get bold => 'Vet';
	@override String get italic => 'Cursief';
	@override String get renderResolution => 'Renderresolutie';
	@override String get renderResolutionScreen => 'Schermresolutie';
	@override String get renderResolutionVideo => 'Videoresolutie';
}

// Path: mpvConfig
class _TranslationsMpvConfigNl extends TranslationsMpvConfigEn {
	_TranslationsMpvConfigNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'mpv-configuratie';
	@override String get description => 'Geavanceerde videospeler-instellingen';
	@override String get presets => 'Voorinstellingen';
	@override String get noPresets => 'Geen opgeslagen voorinstellingen';
	@override String get saveAsPreset => 'Opslaan als voorinstelling...';
	@override String get presetName => 'Naam voorinstelling';
	@override String get presetNameHint => 'Voer een naam in voor deze voorinstelling';
	@override String get loadPreset => 'Laden';
	@override String get deletePreset => 'Verwijderen';
	@override String get presetSaved => 'Voorinstelling opgeslagen';
	@override String get presetLoaded => 'Voorinstelling geladen';
	@override String get presetDeleted => 'Voorinstelling verwijderd';
	@override String get confirmDeletePreset => 'Weet je zeker dat je deze voorinstelling wilt verwijderen?';
	@override String get configPlaceholder => 'gpu-api=vulkan\nhwdec=auto\n# comment';
}

// Path: dialog
class _TranslationsDialogNl extends TranslationsDialogEn {
	_TranslationsDialogNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get confirmAction => 'Bevestig actie';
}

// Path: profiles
class _TranslationsProfilesNl extends TranslationsProfilesEn {
	_TranslationsProfilesNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get addPleyaProfile => 'Pleya-profiel toevoegen';
	@override String get switchingProfile => 'Profiel wisselen…';
	@override String get deleteThisProfileTitle => 'Dit profiel verwijderen?';
	@override String deleteThisProfileMessage({required Object displayName}) => 'Verwijder ${displayName}. Verbindingen blijven ongewijzigd.';
	@override String get active => 'Actief';
	@override String get manage => 'Beheren';
	@override String get delete => 'Verwijderen';
	@override String get signOut => 'Afmelden';
	@override String get signOutPlexTitle => 'Afmelden bij Plex?';
	@override String signOutPlexMessage({required Object displayName}) => '${displayName} en alle Plex Home-gebruikers verwijderen? Je kunt altijd opnieuw inloggen.';
	@override String get signedOutPlex => 'Afgemeld bij Plex.';
	@override String get signOutFailed => 'Afmelden mislukt.';
	@override String get sectionTitle => 'Profielen';
	@override String get summarySingle => 'Voeg profielen toe om beheerde gebruikers en lokale identiteiten te combineren';
	@override String summaryMultipleWithActive({required Object count, required Object activeName}) => '${count} profielen · actief: ${activeName}';
	@override String summaryMultiple({required Object count}) => '${count} profielen';
	@override String get removeConnectionTitle => 'Verbinding verwijderen?';
	@override String removeConnectionMessage({required Object displayName, required Object connectionLabel}) => 'Verwijder ${displayName}s toegang tot ${connectionLabel}. Andere profielen behouden die.';
	@override String get deleteProfileTitle => 'Profiel verwijderen?';
	@override String deleteProfileMessage({required Object displayName}) => 'Verwijder ${displayName} en de verbindingen. Servers blijven beschikbaar.';
	@override String get profileNameLabel => 'Profielnaam';
	@override String get pinProtectionLabel => 'PIN-beveiliging';
	@override String get pinManagedByPlex => 'PIN wordt beheerd door Plex. Bewerk op plex.tv.';
	@override String get noPinSetEditOnPlex => 'Geen PIN ingesteld. Bewerk de Home-gebruiker op plex.tv om er één te vereisen.';
	@override String get setPin => 'PIN instellen';
	@override String get setPinTitle => 'PIN instellen';
	@override String get confirmPinTitle => 'PIN bevestigen';
	@override String get pinSet => 'PIN ingesteld';
	@override String get changePin => 'Wijzigen';
	@override String get removePin => 'Verwijderen';
	@override String get connectionsLabel => 'Verbindingen';
	@override String get add => 'Toevoegen';
	@override String get deleteProfileButton => 'Profiel verwijderen';
	@override String get noConnectionsHint => 'Geen verbindingen — voeg er één toe om dit profiel te gebruiken.';
	@override String get noConnections => 'Geen verbindingen';
	@override String get plexHomeAccount => 'Plex Home-account';
	@override String get connectionDefault => 'Standaard';
	@override String connectionAs({required Object displayName}) => 'als ${displayName}';
	@override String get makeDefault => 'Als standaard instellen';
	@override String get removeConnection => 'Verwijderen';
	@override String get profileRenamed => 'Profiel hernoemd.';
	@override String borrowAddTo({required Object displayName}) => 'Toevoegen aan ${displayName}';
	@override String get borrowExplain => 'Leen de verbinding van een ander profiel. PIN-beveiligde profielen vereisen een PIN.';
	@override String get borrowEmpty => 'Nog niets te lenen.';
	@override String get borrowEmptySubtitle => 'Verbind Plex of Jellyfin eerst met een ander profiel.';
	@override String borrowFromProfile({required Object displayName}) => 'Van ${displayName}';
	@override String get borrowConnectionBorrowed => 'Verbinding geleend.';
	@override String get borrowFailed => 'Kan verbinding niet lenen.';
	@override String get incorrectPin => 'Onjuiste PIN.';
	@override String get sourceProfileMissingParentAccount => 'Het bronprofiel mist het bovenliggende account.';
	@override String get failedToVerifyPin => 'Kan PIN niet verifiëren.';
	@override String get newProfile => 'Nieuw profiel';
	@override String get profileNameHint => 'bijv. Gasten, Kinderen, Woonkamer';
	@override String get pinProtectionOptional => 'PIN-beveiliging (optioneel)';
	@override String get pinExplain => '4-cijferige PIN vereist om profielen te wisselen.';
	@override String get continueButton => 'Doorgaan';
	@override String get pinsDontMatch => 'PIN-codes komen niet overeen';
	@override String get initializeServicesFailed => 'Kan profielservices niet initialiseren';
}

// Path: connections
class _TranslationsConnectionsNl extends TranslationsConnectionsEn {
	_TranslationsConnectionsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Verbindingen';
	@override String get addConnection => 'Verbinding toevoegen';
	@override String get addConnectionSubtitleNoProfile => 'Meld je aan met Plex of verbind een Jellyfin-server';
	@override String addConnectionSubtitleScoped({required Object displayName}) => 'Toevoegen aan ${displayName}: Plex, Jellyfin of een andere profielverbinding';
	@override String sessionExpiredOne({required Object name}) => 'Sessie verlopen voor ${name}';
	@override String sessionExpiredMany({required Object count}) => 'Sessie verlopen voor ${count} servers';
	@override String get signInAgain => 'Opnieuw aanmelden';
	@override String get editJellyfinTitle => 'Jellyfin-verbinding bewerken';
	@override String editJellyfinIntro({required Object serverName}) => 'Voeg URL\'s voor ${serverName} toe of verwijder ze. Pleya gebruikt de bereikbare URL met de laagste latentie.';
	@override String get localSources => 'Bronnen op dit apparaat';
	@override String get removeSource => 'Bron verwijderen';
	@override String removeSourceConfirm({required Object name}) => '"${name}" verwijderen van dit apparaat? Gedownloade items blijven staan.';
	@override String get pleyaServers => 'Pleya Servers';
	@override String get disconnectServer => 'Verbinding verbreken';
	@override String disconnectServerConfirm({required Object name}) => 'Verbinding met "${name}" verbreken? De aanmelding voor deze server wordt van dit apparaat verwijderd. Gedownloade items blijven staan.';
	@override String get reauthRequired => 'Opnieuw aanmelden vereist';
}

// Path: discover
class _TranslationsDiscoverNl extends TranslationsDiscoverEn {
	_TranslationsDiscoverNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Ontdekken';
	@override String get switchProfile => 'Wissel van profiel';
	@override String get noContentAvailable => 'Geen inhoud beschikbaar';
	@override String get addMediaToLibraries => 'Voeg wat media toe aan je bibliotheken';
	@override String get continueWatching => 'Verder kijken';
	@override String continueWatchingIn({required Object library}) => 'Verder kijken in ${library}';
	@override String get nextUp => 'Volgende';
	@override String nextUpIn({required Object library}) => 'Volgende in ${library}';
	@override String get recentlyAdded => 'Recent toegevoegd';
	@override String get recentlyReleased => 'Recent uitgebracht';
	@override String recentlyAddedIn({required Object library}) => 'Recent toegevoegd in ${library}';
	@override String playEpisode({required Object season, required Object episode}) => 'S${season}E${episode}';
	@override String get overview => 'Overzicht';
	@override String get cast => 'Acteurs';
	@override String get extras => 'Trailers & Extra\'s';
	@override String get studio => 'Studio';
	@override String get rating => 'Leeftijd';
	@override String get movie => 'Film';
	@override String get tvShow => 'TV Serie';
	@override String minutesLeft({required Object minutes}) => '${minutes} min over';
	@override String get moreLikeThis => 'Meer zoals dit';
	@override String becauseYouWatched({required Object title}) => 'Omdat je ${title} gekeken hebt';
	@override String get topRated => 'Hoogst gewaardeerd';
	@override String get somethingDifferent => 'Eens iets anders';
	@override String get topPicksForYou => 'Aanbevolen voor jou';
	@override String becauseYouLike({required Object genre}) => 'Omdat je van ${genre} houdt';
	@override String get hiddenGems => 'Verborgen parels';
	@override String watchedBy({required Object names}) => 'Bekeken door ${names}';
	@override String get watchedByYou => 'Jij';
	@override String get watchedByAnd => 'en';
	@override String watchedByOthers({required Object count}) => '${count} anderen';
	@override String statsPlays({required Object count}) => '${count} keer afgespeeld';
	@override String statsViewers({required Object count}) => 'door ${count} mensen';
	@override String statsWatchTime({required Object duration}) => '${duration} bekeken';
	@override String statsRecent({required Object count}) => '${count} in de laatste 30 dagen';
	@override String watchingSeriesBy({required Object names}) => 'Kijken deze serie: ${names}';
}

// Path: errors
class _TranslationsErrorsNl extends TranslationsErrorsEn {
	_TranslationsErrorsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get searchFailed => 'Zoeken mislukt';
	@override String connectionTimeout({required Object context}) => 'Verbinding time-out tijdens laden ${context}';
	@override String get connectionFailed => 'Kan geen verbinding maken met mediaserver';
	@override String failedToLoad({required Object context}) => 'Kon ${context} niet laden';
	@override String get noClientAvailable => 'Geen client beschikbaar';
	@override String get authenticationFailed => 'Authenticatie mislukt';
	@override String get couldNotLaunchUrl => 'Kon auth URL niet openen';
	@override String get pleaseEnterToken => 'Voer een token in';
	@override String get invalidToken => 'Ongeldig token';
	@override String get failedToVerifyToken => 'Kon token niet verifiëren';
	@override String failedToSwitchProfile({required Object displayName}) => 'Kon niet wisselen naar ${displayName}';
	@override String failedToDeleteProfile({required Object displayName}) => 'Kon ${displayName} niet verwijderen';
	@override String get failedToRate => 'Beoordeling kon niet worden bijgewerkt';
	@override String get somethingWentWrongTryAgain => 'Er ging iets mis. Probeer het opnieuw.';
	@override String couldNotLoad({required Object context}) => 'Kon ${context} niet laden. Probeer het opnieuw.';
}

// Path: notices
class _TranslationsNoticesNl extends TranslationsNoticesEn {
	_TranslationsNoticesNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get connectionTimeoutTitle => 'Verbinding verlopen';
	@override String connectionTimeoutBody({required Object context}) => '${context} reageerde niet op tijd';
	@override String get connectionFailedTitle => 'Kan niet verbinden';
	@override String connectionFailedBody({required Object serverName}) => '${serverName} reageert niet';
	@override String couldNotLoadTitle({required Object context}) => 'Kon ${context} niet laden';
	@override String get genericErrorTitle => 'Er ging iets mis';
	@override String get authFailedTitle => 'Aanmelden mislukt';
	@override String get playbackStoppedTitle => 'Afspelen gestopt';
	@override String get playbackFileUnavailableTitle => 'Bestand niet beschikbaar';
	@override String get playbackFileUnavailableBody => 'De server kan niet bij het videobestand. Kijk of de schijf of map waar het op staat nog aangesloten is.';
	@override String get playbackSegmentUnavailableBody => 'Dit deel van de video is nu niet beschikbaar';
	@override String get playbackConnectionLostBody => 'Verbinding met de server verloren';
	@override String get playbackCodecUnsupportedBody => 'Dit bestandsformaat wordt niet ondersteund op dit toestel';
	@override String get playbackServerErrorBody => 'De server liep vast tijdens het transcoderen';
}

// Path: libraries
class _TranslationsLibrariesNl extends TranslationsLibrariesEn {
	_TranslationsLibrariesNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Bibliotheken';
	@override String get fallbackTitle => 'Bibliotheek';
	@override String get scanLibraryFiles => 'Scan bibliotheek bestanden';
	@override String get scanLibrary => 'Scan bibliotheek';
	@override String get analyze => 'Analyseren';
	@override String get analyzeLibrary => 'Analyseer bibliotheek';
	@override String get refreshMetadata => 'Vernieuw metadata';
	@override String get emptyTrash => 'Prullenbak legen';
	@override String emptyingTrash({required Object title}) => 'Prullenbak legen voor "${title}"...';
	@override String trashEmptied({required Object title}) => 'Prullenbak geleegd voor "${title}"';
	@override String get failedToEmptyTrash => 'Kon prullenbak niet legen';
	@override String analyzing({required Object title}) => 'Analyseren "${title}"...';
	@override String analysisStarted({required Object title}) => 'Analyse gestart voor "${title}"';
	@override String get failedToAnalyze => 'Kon bibliotheek niet analyseren';
	@override String get noLibrariesFound => 'Geen bibliotheken gevonden';
	@override String get allLibrariesHidden => 'Alle bibliotheken zijn verborgen';
	@override String hiddenLibrariesCount({required Object count}) => 'Verborgen bibliotheken (${count})';
	@override String get thisLibraryIsEmpty => 'Deze bibliotheek is leeg';
	@override String get all => 'Alles';
	@override String get clearAll => 'Alles wissen';
	@override String scanLibraryConfirm({required Object title}) => 'Weet je zeker dat je "${title}" wilt scannen?';
	@override String analyzeLibraryConfirm({required Object title}) => 'Weet je zeker dat je "${title}" wilt analyseren?';
	@override String refreshMetadataConfirm({required Object title}) => 'Weet je zeker dat je metadata wilt vernieuwen voor "${title}"?';
	@override String emptyTrashConfirm({required Object title}) => 'Weet je zeker dat je de prullenbak wilt legen voor "${title}"?';
	@override String get manageLibraries => 'Beheer bibliotheken';
	@override String get sort => 'Sorteren';
	@override String get sortBy => 'Sorteer op';
	@override String get filters => 'Filters';
	@override String get confirmActionMessage => 'Weet je zeker dat je deze actie wilt uitvoeren?';
	@override String get showLibrary => 'Toon bibliotheek';
	@override String get hideLibrary => 'Verberg bibliotheek';
	@override String get libraryOptions => 'Bibliotheek opties';
	@override String get content => 'bibliotheekinhoud';
	@override String get selectLibrary => 'Bibliotheek kiezen';
	@override String filtersWithCount({required Object count}) => 'Filters (${count})';
	@override String get noRecommendations => 'Geen aanbevelingen beschikbaar';
	@override String get noCollections => 'Geen collecties in deze bibliotheek';
	@override String get noFoldersFound => 'Geen mappen gevonden';
	@override String get folders => 'mappen';
	@override late final _TranslationsLibrariesTabsNl tabs = _TranslationsLibrariesTabsNl._(_root);
	@override late final _TranslationsLibrariesGroupingsNl groupings = _TranslationsLibrariesGroupingsNl._(_root);
	@override late final _TranslationsLibrariesFilterCategoriesNl filterCategories = _TranslationsLibrariesFilterCategoriesNl._(_root);
	@override late final _TranslationsLibrariesSortLabelsNl sortLabels = _TranslationsLibrariesSortLabelsNl._(_root);
}

// Path: about
class _TranslationsAboutNl extends TranslationsAboutEn {
	_TranslationsAboutNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Over';
	@override String get openSourceLicenses => 'Open Source licenties';
	@override String versionLabel({required Object version}) => 'Versie ${version}';
	@override String get appDescription => 'Een mooie Plex- en Jellyfin-client voor Flutter';
	@override String get viewLicensesDescription => 'Bekijk licenties van third-party bibliotheken';
	@override String get sourceCode => 'Broncode';
	@override String get sourceCodeDescription => 'Bijbehorende broncode van deze build (GPL-3.0)';
	@override String get basedOnPlezy => 'Gebaseerd op Plezy';
	@override String get upstreamProject => 'Upstream-project';
	@override String get privacyPolicy => 'Privacybeleid';
}

// Path: serverSelection
class _TranslationsServerSelectionNl extends TranslationsServerSelectionEn {
	_TranslationsServerSelectionNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get allServerConnectionsFailed => 'Kon met geen enkele server verbinden. Controleer je netwerk.';
	@override String noServersFoundForAccount({required Object username, required Object email}) => 'Geen servers gevonden voor ${username} (${email})';
	@override String get noServersFoundTitle => 'Geen mediaservers gevonden';
	@override String get noServersFoundDescription => 'Je Plex-account heeft nog geen toegang tot servers. Vraag de server-eigenaar om zijn bibliotheek met je te delen, of verbind in plaats daarvan een Jellyfin-server.';
	@override String get noServersFoundTryJellyfin => 'Verbind een Jellyfin-server';
	@override String get noServersFoundRetryPlex => 'Probeer een ander Plex-account';
	@override String get failedToLoadServers => 'Kon servers niet laden';
	@override String get failedToLoadServersDescription => 'Er ging iets mis bij het laden van je servers. Controleer je internetverbinding en probeer opnieuw.';
	@override String get networkErrorTitle => 'Kan de server niet bereiken';
	@override String get networkErrorDescription => 'Pleya kon geen verbinding maken met internet. Controleer je netwerk en probeer opnieuw.';
}

// Path: hubDetail
class _TranslationsHubDetailNl extends TranslationsHubDetailEn {
	_TranslationsHubDetailNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Titel';
	@override String get releaseYear => 'Uitgavejaar';
	@override String get dateAdded => 'Datum toegevoegd';
	@override String get rating => 'Beoordeling';
	@override String get noItemsFound => 'Geen items gevonden';
}

// Path: logs
class _TranslationsLogsNl extends TranslationsLogsEn {
	_TranslationsLogsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get clearLogs => 'Wis logs';
	@override String get copyLogs => 'Kopieer logs';
	@override String get uploadLogs => 'Logs uploaden';
}

// Path: licenses
class _TranslationsLicensesNl extends TranslationsLicensesEn {
	_TranslationsLicensesNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get relatedPackages => 'Gerelateerde pakketten';
	@override String get license => 'Licentie';
	@override String licenseNumber({required Object number}) => 'Licentie ${number}';
	@override String licensesCount({required Object count}) => '${count} licenties';
}

// Path: navigation
class _TranslationsNavigationNl extends TranslationsNavigationEn {
	_TranslationsNavigationNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get libraries => 'Media';
	@override String get downloads => 'Downloads';
	@override String get liveTv => 'Live TV';
	@override String get watchlist => 'Kijklijst';
	@override String get myPleya => 'Mijn Pleya';
}

// Path: watchlist
class _TranslationsWatchlistNl extends TranslationsWatchlistEn {
	_TranslationsWatchlistNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Kijklijst';
	@override String get seeAll => 'Alles bekijken';
	@override String get empty => 'Nog niets op je kijklijst';
	@override String get emptyBody => 'Titels die je in Plex toevoegt of als Jellyfin-favoriet markeert, verschijnen hier.';
	@override String get emptyFiltered => 'Geen titels binnen dit filter';
	@override String get retry => 'Opnieuw proberen';
	@override String get notAvailable => 'Niet beschikbaar';
	@override String get checking => 'Controleren';
	@override String get notFoundOnServers => 'Niet gevonden op je gekoppelde mediaservers';
	@override String get coverageIncomplete => 'Een deel van je mediaservers was niet bereikbaar. Deze titel staat er misschien al.';
	@override String get remove => 'Uit kijklijst verwijderen';
	@override String get add => 'Aan kijklijst toevoegen';
	@override String get added => 'Toegevoegd aan kijklijst';
	@override String get removed => 'Verwijderd uit kijklijst';
	@override String get addFailed => 'Kon je kijklijst niet bijwerken';
	@override String get partiallyFailed => 'Alleen uit een deel van de lijsten verwijderd. Je kijklijst is opnieuw geladen.';
	@override String get offlineRejected => 'Je hebt verbinding nodig om je kijklijst te wijzigen';
	@override String get filterAll => 'Alles';
	@override String get filterMovies => 'Films';
	@override String get filterShows => 'Series';
	@override String get filterAvailable => 'Beschikbaar';
	@override String get sortRecentlyAdded => 'Recent toegevoegd';
	@override String get sortTitle => 'Titel';
	@override String get sortYear => 'Jaar';
}

// Path: myPleya
class _TranslationsMyPleyaNl extends TranslationsMyPleyaEn {
	_TranslationsMyPleyaNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Mijn Pleya';
	@override String downloadsCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '1 download',
		other: '{n} downloads',
	);
}

// Path: liveTv
class _TranslationsLiveTvNl extends TranslationsLiveTvEn {
	_TranslationsLiveTvNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get serverNotAvailable => 'Live TV-server is niet beschikbaar.';
	@override String get serverNotConnected => 'Live TV-server is niet verbonden.';
	@override String get title => 'Live TV';
	@override String get guide => 'Gids';
	@override String get noChannels => 'Geen zenders beschikbaar';
	@override String get noDvr => 'Geen DVR geconfigureerd op een server';
	@override String get noPrograms => 'Geen programmagegevens beschikbaar';
	@override String get liveStreamFailed => 'Livestream mislukt';
	@override String get unknownProgram => 'Onbekend programma';
	@override String get unknownHub => 'Onbekend';
	@override String get unknownError => 'Onbekende fout';
	@override String channelNumber({required Object number}) => 'Kanaal ${number}';
	@override String get unknownChannel => 'Onbekend kanaal';
	@override String get live => 'LIVE';
	@override String get reloadGuide => 'Gids herladen';
	@override String get now => 'Nu';
	@override String get today => 'Vandaag';
	@override String get tomorrow => 'Morgen';
	@override String get midnight => 'Middernacht';
	@override String get overnight => 'Nacht';
	@override String get morning => 'Ochtend';
	@override String get daytime => 'Overdag';
	@override String get evening => 'Avond';
	@override String get lateNight => 'Late avond';
	@override String get whatsOn => 'Nu op TV';
	@override String get watchChannel => 'Kanaal bekijken';
	@override String get favorites => 'Favorieten';
	@override String get reorderFavorites => 'Favorieten herordenen';
	@override String get favoritesSaveFailed => 'Kon je favoriete kanalen niet opslaan';
	@override String get joinSession => 'Deelnemen aan lopende sessie';
	@override String watchFromStart({required Object minutes}) => 'Kijk vanaf het begin (${minutes} min geleden)';
	@override String get watchLive => 'Live kijken';
	@override String get goToLive => 'Ga naar live';
	@override String get record => 'Opnemen';
	@override String get recordEpisode => 'Aflevering opnemen';
	@override String get recordSeries => 'Serie opnemen';
	@override String get recordOptions => 'Opnameopties';
	@override String get recordings => 'Opnames';
	@override String get scheduledRecordings => 'Gepland';
	@override String get recordingRules => 'Opnameregels';
	@override String get noScheduledRecordings => 'Geen geplande opnames';
	@override String get noRecordingRules => 'Nog geen opnameregels';
	@override String get manageRecording => 'Opname beheren';
	@override String get cancelRecording => 'Opname annuleren';
	@override String get cancelRecordingTitle => 'Deze opname annuleren?';
	@override String cancelRecordingMessage({required Object title}) => '${title} wordt niet meer opgenomen.';
	@override String get deleteRule => 'Regel verwijderen';
	@override String get deleteRuleTitle => 'Opnameregel verwijderen?';
	@override String deleteRuleMessage({required Object title}) => 'Toekomstige afleveringen van ${title} worden niet opgenomen.';
	@override String get recordingScheduled => 'Opname gepland';
	@override String get alreadyScheduled => 'Dit programma is al gepland';
	@override String get dvrAdminRequired => 'DVR-instellingen vereisen een beheerdersaccount';
	@override String get recordingFailed => 'Kon opname niet plannen';
	@override String get recordingTargetMissing => 'Kon opnamebibliotheek niet bepalen';
	@override String get recordNotAvailable => 'Opname niet beschikbaar voor dit programma';
	@override String get recordingCancelled => 'Opname geannuleerd';
	@override String get recordingRuleDeleted => 'Opnameregel verwijderd';
	@override String get processRecordingRules => 'Regels opnieuw evalueren';
	@override String get loadingRecordings => 'Opnames laden...';
	@override String get recordingInProgress => 'Nu aan het opnemen';
	@override String recordingsCount({required Object count}) => '${count} gepland';
	@override String get editRule => 'Regel bewerken';
	@override String get editRuleAction => 'Bewerken';
	@override String get recordingRuleUpdated => 'Opnameregel bijgewerkt';
	@override String get guideReloadRequested => 'Gids-vernieuwing aangevraagd';
	@override String get rulesProcessRequested => 'Regel-herevaluatie aangevraagd';
	@override String get recordShow => 'Programma opnemen';
}

// Path: collections
class _TranslationsCollectionsNl extends TranslationsCollectionsEn {
	_TranslationsCollectionsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Collecties';
	@override String get collection => 'Collectie';
	@override String get empty => 'Collectie is leeg';
	@override String get unknownLibrarySection => 'Kan niet verwijderen: onbekende bibliotheeksectie';
	@override String get deleteCollection => 'Collectie verwijderen';
	@override String deleteConfirm({required Object title}) => '"${title}" verwijderen? Dit kan niet ongedaan worden gemaakt.';
	@override String get deleted => 'Collectie verwijderd';
	@override String get deleteFailed => 'Collectie verwijderen mislukt';
	@override String get deleteFailedWithError => 'Collectie verwijderen mislukt';
	@override String get failedToLoadItems => 'Collectie-items laden mislukt';
	@override String get selectCollection => 'Selecteer collectie';
	@override String get collectionName => 'Collectienaam';
	@override String get enterCollectionName => 'Voer collectienaam in';
	@override String get addedToCollection => 'Toegevoegd aan collectie';
	@override String get errorAddingToCollection => 'Fout bij toevoegen aan collectie';
	@override String get created => 'Collectie gemaakt';
	@override String get removeFromCollection => 'Verwijderen uit collectie';
	@override String removeFromCollectionConfirm({required Object title}) => '"${title}" uit deze collectie verwijderen?';
	@override String get removedFromCollection => 'Uit collectie verwijderd';
	@override String get removeFromCollectionFailed => 'Verwijderen uit collectie mislukt';
	@override String get removeFromCollectionError => 'Fout bij verwijderen uit collectie';
	@override String get searchCollections => 'Collecties zoeken...';
}

// Path: playlists
class _TranslationsPlaylistsNl extends TranslationsPlaylistsEn {
	_TranslationsPlaylistsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Afspeellijsten';
	@override String get playlist => 'Afspeellijst';
	@override String get noPlaylists => 'Geen afspeellijsten gevonden';
	@override String get create => 'Afspeellijst maken';
	@override String get playlistName => 'Naam afspeellijst';
	@override String get enterPlaylistName => 'Voer naam afspeellijst in';
	@override String get delete => 'Afspeellijst verwijderen';
	@override String get removeItem => 'Verwijderen uit afspeellijst';
	@override String get smartPlaylist => 'Slimme afspeellijst';
	@override String itemCount({required Object count}) => '${count} items';
	@override String get oneItem => '1 item';
	@override String get emptyPlaylist => 'Deze afspeellijst is leeg';
	@override String get deleteConfirm => 'Afspeellijst verwijderen?';
	@override String deleteMessage({required Object name}) => 'Weet je zeker dat je "${name}" wilt verwijderen?';
	@override String get created => 'Afspeellijst gemaakt';
	@override String get deleted => 'Afspeellijst verwijderd';
	@override String get itemAdded => 'Toegevoegd aan afspeellijst';
	@override String get itemRemoved => 'Verwijderd uit afspeellijst';
	@override String get selectPlaylist => 'Selecteer afspeellijst';
	@override String get errorCreating => 'Fout bij maken afspeellijst';
	@override String get errorDeleting => 'Fout bij verwijderen afspeellijst';
	@override String get errorLoading => 'Fout bij laden afspeellijsten';
	@override String get errorAdding => 'Fout bij toevoegen aan afspeellijst';
	@override String get errorReordering => 'Fout bij herschikken van afspeellijstitem';
	@override String get errorRemoving => 'Fout bij verwijderen uit afspeellijst';
}

// Path: watchTogether
class _TranslationsWatchTogetherNl extends TranslationsWatchTogetherEn {
	_TranslationsWatchTogetherNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Samen Kijken';
	@override String get description => 'Kijk synchroon met vrienden en familie';
	@override String get createSession => 'Sessie Maken';
	@override String get creating => 'Maken...';
	@override String get joinSession => 'Sessie Deelnemen';
	@override String get joining => 'Deelnemen...';
	@override String get controlMode => 'Controlemodus';
	@override String get controlModeQuestion => 'Wie kan het afspelen bedienen?';
	@override String get hostOnly => 'Alleen Host';
	@override String get anyone => 'Iedereen';
	@override String get hostingSession => 'Sessie Hosten';
	@override String get inSession => 'In Sessie';
	@override String get sessionCode => 'Sessiecode';
	@override String get hostControlsPlayback => 'Host bedient het afspelen';
	@override String get anyoneCanControl => 'Iedereen kan het afspelen bedienen';
	@override String get hostControls => 'Host bedient';
	@override String get anyoneControls => 'Iedereen bedient';
	@override String get participants => 'Deelnemers';
	@override String get host => 'Host';
	@override String get hostBadge => 'HOST';
	@override String get youAreHost => 'Jij bent de host';
	@override String get watchingWithOthers => 'Kijken met anderen';
	@override String get endSession => 'Sessie Beëindigen';
	@override String get leaveSession => 'Sessie Verlaten';
	@override String get endSessionQuestion => 'Sessie Beëindigen?';
	@override String get leaveSessionQuestion => 'Sessie Verlaten?';
	@override String get endSessionConfirm => 'Dit beëindigt de sessie voor alle deelnemers.';
	@override String get leaveSessionConfirm => 'Je wordt uit de sessie verwijderd.';
	@override String get endSessionConfirmOverlay => 'Dit beëindigt de kijksessie voor alle deelnemers.';
	@override String get leaveSessionConfirmOverlay => 'Je wordt losgekoppeld van de kijksessie.';
	@override String get end => 'Beëindigen';
	@override String get leave => 'Verlaten';
	@override String get syncing => 'Synchroniseren...';
	@override String get joinWatchSession => 'Kijksessie Deelnemen';
	@override String get enterCodeHint => 'Voer 5-teken code in';
	@override String get pasteFromClipboard => 'Plakken van klembord';
	@override String get pleaseEnterCode => 'Voer een sessiecode in';
	@override String get codeMustBe5Chars => 'Sessiecode moet 5 tekens zijn';
	@override String get joinInstructions => 'Voer de sessiecode van de host in om deel te nemen.';
	@override String get failedToCreate => 'Sessie maken mislukt';
	@override String get failedToJoin => 'Sessie deelnemen mislukt';
	@override String get sessionCodeCopied => 'Sessiecode gekopieerd naar klembord';
	@override String get relayUnreachable => 'Relay-server onbereikbaar. ISP-blokkering kan Watch Together verhinderen.';
	@override String get reconnectingToHost => 'Opnieuw verbinden met host...';
	@override String get currentPlayback => 'Huidige weergave';
	@override String get joinCurrentPlayback => 'Deelnemen aan huidige weergave';
	@override String get joinCurrentPlaybackDescription => 'Ga terug naar wat de host nu kijkt';
	@override String get failedToOpenCurrentPlayback => 'Huidige weergave kon niet worden geopend';
	@override String participantJoined({required Object name}) => '${name} is toegetreden';
	@override String participantLeft({required Object name}) => '${name} heeft de sessie verlaten';
	@override String participantPaused({required Object name}) => '${name} heeft gepauzeerd';
	@override String participantResumed({required Object name}) => '${name} heeft hervat';
	@override String participantSeeked({required Object name}) => '${name} heeft gespoeld';
	@override String participantBuffering({required Object name}) => '${name} is aan het bufferen';
	@override String get waitingForParticipants => 'Wachten tot anderen geladen zijn...';
	@override String get recentRooms => 'Recente kamers';
	@override String get renameRoom => 'Kamer hernoemen';
	@override String get removeRoom => 'Verwijderen';
	@override String get guestSwitchUnavailable => 'Kon niet schakelen — server niet beschikbaar voor synchronisatie';
	@override String get guestSwitchFailed => 'Kon niet schakelen — inhoud niet gevonden op deze server';
}

// Path: downloads
class _TranslationsDownloadsNl extends TranslationsDownloadsEn {
	_TranslationsDownloadsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Downloads';
	@override String get manage => 'Beheren';
	@override String get tvShows => 'Series';
	@override String get movies => 'Films';
	@override String get noDownloads => 'Nog geen downloads';
	@override String get noDownloadsDescription => 'Gedownloade content verschijnt hier voor offline weergave';
	@override String get downloadNow => 'Download';
	@override String get deleteDownload => 'Download verwijderen';
	@override String get retryDownload => 'Download opnieuw proberen';
	@override String get downloadQueued => 'Download in wachtrij';
	@override String get downloadResumed => 'Download hervat';
	@override String get serverErrorBitrate => 'Serverfout: bestand overschrijdt mogelijk de externe bitrate-limiet';
	@override String episodesQueued({required Object count}) => '${count} afleveringen in wachtrij voor download';
	@override String get downloadDeleted => 'Download verwijderd';
	@override String deleteConfirm({required Object title}) => '"${title}" van dit apparaat verwijderen?';
	@override String get cancelledDownloadTitle => 'Geannuleerde download';
	@override String get cancelledDownloadMessage => 'Deze download is geannuleerd. Wat wil je doen?';
	@override String get allEpisodesAlreadyDownloaded => 'Alle afleveringen zijn al gedownload';
	@override String get resumeDownload => 'Download hervatten';
	@override String get cancelledDownload => 'Geannuleerde download';
	@override String syncingFile({required Object file, required Object status}) => '${file} (${status} synchroniseren)';
	@override String downloadedFileClickToComplete({required Object file}) => '${file} gedownload — klik om te voltooien';
	@override String get partialDownloadClickToComplete => 'Gedeeltelijk gedownload — klik om te voltooien';
	@override String get deleting => 'Verwijderen...';
	@override String deletingWithProgress({required Object title, required Object current, required Object total}) => 'Verwijderen van ${title}... (${current} van ${total})';
	@override String get queuedTooltip => 'In wachtrij';
	@override String queuedFilesTooltip({required Object files}) => 'In wachtrij: ${files}';
	@override String get downloadingTooltip => 'Downloaden...';
	@override String downloadingFilesTooltip({required Object files}) => 'Downloaden ${files}';
	@override String get noDownloadsTree => 'Geen downloads';
	@override String get pauseAll => 'Alles pauzeren';
	@override String get resumeAll => 'Alles hervatten';
	@override String get deleteAll => 'Alles verwijderen';
	@override String get selectVersion => 'Versie selecteren';
	@override String get allEpisodes => 'Alle afleveringen';
	@override String get unwatchedOnly => 'Alleen onbekeken';
	@override String nextNUnwatched({required Object count}) => 'Volgende ${count} onbekeken';
	@override String get customAmount => 'Aangepast aantal...';
	@override String get includeSpecials => 'Specials opnemen';
	@override String get howManyEpisodes => 'Hoeveel afleveringen?';
	@override String itemsQueued({required Object count}) => '${count} items in downloadwachtrij';
	@override String get keepSynced => 'Gesynchroniseerd houden';
	@override String get downloadOnce => 'Eenmalig downloaden';
	@override String keepNUnwatched({required Object count}) => '${count} onbekeken behouden';
	@override String get editSyncRule => 'Synchronisatieregel bewerken';
	@override String get removeSyncRule => 'Synchronisatieregel verwijderen';
	@override String removeSyncRuleConfirm({required Object title}) => 'Synchronisatie van "${title}" stoppen? Gedownloade afleveringen worden behouden.';
	@override String syncRuleCreated({required Object count}) => 'Synchronisatieregel aangemaakt — ${count} onbekeken afleveringen behouden';
	@override String get syncRuleUpdated => 'Synchronisatieregel bijgewerkt';
	@override String get syncRuleRemoved => 'Synchronisatieregel verwijderd';
	@override String syncedNewEpisodes({required Object count, required Object title}) => '${count} nieuwe afleveringen gesynchroniseerd voor ${title}';
	@override String get activeSyncRules => 'Synchronisatieregels';
	@override String get noSyncRules => 'Geen synchronisatieregels';
	@override String get manageSyncRule => 'Synchronisatie beheren';
	@override String get editEpisodeCount => 'Aantal afleveringen';
	@override String get editSyncFilter => 'Synchronisatiefilter';
	@override String get syncAllItems => 'Alle items synchroniseren';
	@override String get syncUnwatchedItems => 'Ongekeken items synchroniseren';
	@override String syncRuleServerContext({required Object server, required Object status}) => 'Server: ${server} • ${status}';
	@override String get syncRuleAvailable => 'Beschikbaar';
	@override String get syncRuleOffline => 'Offline';
	@override String get syncRuleSignInRequired => 'Inloggen vereist';
	@override String get syncRuleNotAvailableForProfile => 'Niet beschikbaar voor huidig profiel';
	@override String get syncRuleUnknownServer => 'Onbekende server';
	@override String get syncRuleListCreated => 'Synchronisatieregel aangemaakt';
}

// Path: shaders
class _TranslationsShadersNl extends TranslationsShadersEn {
	_TranslationsShadersNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Shaders';
	@override String get noShaderDescription => 'Geen videoverbetering';
	@override String get nvscalerDescription => 'NVIDIA-beeldschaling voor scherpere video';
	@override String get artcnnVariantNeutral => 'Neutraal';
	@override String get artcnnVariantDenoise => 'Ruisonderdrukking';
	@override String get artcnnVariantDenoiseSharpen => 'Ruisonderdrukking + verscherpen';
	@override String get qualityFast => 'Snel';
	@override String get qualityHQ => 'Hoge kwaliteit';
	@override String get mode => 'Modus';
	@override String get importShader => 'Shader importeren';
	@override String get customShaderDescription => 'Aangepaste GLSL-shader';
	@override String get shaderImported => 'Shader geïmporteerd';
	@override String get shaderImportFailed => 'Shader importeren mislukt';
	@override String get deleteShader => 'Shader verwijderen';
	@override String deleteShaderConfirm({required Object name}) => '"${name}" verwijderen?';
}

// Path: companionRemote
class _TranslationsCompanionRemoteNl extends TranslationsCompanionRemoteEn {
	_TranslationsCompanionRemoteNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Afstandsbediening';
	@override String connectedTo({required Object name}) => 'Verbonden met ${name}';
	@override String get unknownDevice => 'Onbekend apparaat';
	@override late final _TranslationsCompanionRemoteSessionNl session = _TranslationsCompanionRemoteSessionNl._(_root);
	@override late final _TranslationsCompanionRemotePairingNl pairing = _TranslationsCompanionRemotePairingNl._(_root);
	@override late final _TranslationsCompanionRemoteRemoteNl remote = _TranslationsCompanionRemoteRemoteNl._(_root);
	@override late final _TranslationsCompanionRemoteErrorsNl errors = _TranslationsCompanionRemoteErrorsNl._(_root);
}

// Path: videoSettings
class _TranslationsVideoSettingsNl extends TranslationsVideoSettingsEn {
	_TranslationsVideoSettingsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get playbackSpeed => 'Afspeelsnelheid';
	@override String get zoom => 'Zoom';
	@override String get sleepTimer => 'Slaaptimer';
	@override String get audioSync => 'Audio synchronisatie';
	@override String get subtitleSync => 'Ondertitel synchronisatie';
	@override String get hdr => 'HDR';
	@override String get audioOutput => 'Audio-uitvoer';
	@override String get performanceOverlay => 'Prestatie-overlay';
	@override String get audioPassthrough => 'Audio-doorvoer';
	@override String get audioOutputTitle => 'Audio-uitvoermodus';
	@override late final _TranslationsVideoSettingsAudioOutputModesNl audioOutputModes = _TranslationsVideoSettingsAudioOutputModesNl._(_root);
	@override late final _TranslationsVideoSettingsAudioOutputDecisionsNl audioOutputDecisions = _TranslationsVideoSettingsAudioOutputDecisionsNl._(_root);
	@override late final _TranslationsVideoSettingsAudioOutputModeDescriptionsNl audioOutputModeDescriptions = _TranslationsVideoSettingsAudioOutputModeDescriptionsNl._(_root);
	@override late final _TranslationsVideoSettingsAudioOutputRenderingNl audioOutputRendering = _TranslationsVideoSettingsAudioOutputRenderingNl._(_root);
	@override String audioOutputNow({required Object mode}) => 'nu: ${mode}';
	@override String get audioNormalization => 'Volume normaliseren';
	@override String get audioNormalizationSuspended => 'Dolby-doorvoer loopt, dus volume gelijkmaken staat uit. Je receiver bepaalt het niveau.';
	@override String get audioPriorityTitle => 'Prioriteit';
	@override late final _TranslationsVideoSettingsAudioPrioritiesNl audioPriorities = _TranslationsVideoSettingsAudioPrioritiesNl._(_root);
	@override String get audioLevelVolume => 'Volume gelijkmaken';
	@override String get audioLevelVolumeDescription => 'Brengt elke titel op hetzelfde niveau als de rest van je tv';
	@override String get audioReduceLoudSounds => 'Verminder harde geluiden';
	@override String get audioReduceLoudSoundsDescription => 'Verkleint het verschil tussen dialoog en harde effecten';
	@override String get tryLowerQuality => 'Probeer lagere kwaliteit';
	@override String get audioPassthroughUnavailable => 'Deze uitgang accepteert geen Dolby-bitstream — overgeschakeld op gedecodeerd geluid.';
}

// Path: performanceOverlay
class _TranslationsPerformanceOverlayNl extends TranslationsPerformanceOverlayEn {
	_TranslationsPerformanceOverlayNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get color => 'Kleur';
	@override String get performance => 'Prestaties';
	@override String get buffer => 'Buffer';
	@override String get app => 'App';
	@override String get decoder => 'Decoder';
	@override String get rawDecoder => 'Raw decoder';
	@override String get tunneling => 'Tunneling';
	@override String get aspect => 'Verhouding';
	@override String get rotation => 'Rotatie';
	@override String get dvSource => 'DV-bron';
	@override String get dvPath => 'DV-pad';
	@override String get p7Conversion => 'P7-conv.';
	@override String get sampleRate => 'Samplefrequentie';
	@override String get audioDriver => 'Audiostuurprogramma';
	@override String get audioOutFormat => 'Uitvoerformaat';
	@override String get audioRequested => 'Gevraagd';
	@override String get audioActual => 'Werkelijk';
	@override String get audioMeasuring => 'meten…';
	@override String get audioBitstream => 'bitstream';
	@override String get audioFellBack => 'terugval';
	@override String get audioFilters => 'Filters';
	@override String get audioFiltersNone => 'geen';
	@override String get volume => 'Volume';
	@override String get pixelFormat => 'Pixelformaat';
	@override String get hwFormat => 'HW-formaat';
	@override String get matrix => 'Matrix';
	@override String get primaries => 'Primaire kleuren';
	@override String get transfer => 'Transfer';
	@override String get renderFps => 'Render-FPS';
	@override String get displayFps => 'Scherm-FPS';
	@override String get avSync => 'A/V-sync';
	@override String get dropped => 'Gedropt';
	@override String get dvRpus => 'DV RPU’s';
	@override String get dvRpuAverage => 'DV RPU gem.';
	@override String get dvSampleAverage => 'DV-sample gem.';
	@override String get maxLuma => 'Max luma';
	@override String get minLuma => 'Min luma';
	@override String get maxCll => 'MaxCLL';
	@override String get maxFall => 'MaxFALL';
	@override String get cacheUsed => 'Cache gebruikt';
	@override String get cacheLimit => 'Cachelimiet';
	@override String get speed => 'Snelheid';
	@override String get player => 'Speler';
	@override String get memory => 'Geheugen';
	@override String get uiFps => 'UI FPS';
}

// Path: externalPlayer
class _TranslationsExternalPlayerNl extends TranslationsExternalPlayerEn {
	_TranslationsExternalPlayerNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Externe speler';
	@override String get useExternalPlayer => 'Externe speler gebruiken';
	@override String get useExternalPlayerDescription => 'Open video\'s in een andere app';
	@override String get selectPlayer => 'Speler selecteren';
	@override String get customPlayers => 'Aangepaste spelers';
	@override String get systemDefault => 'Systeemstandaard';
	@override String get addCustomPlayer => 'Aangepaste speler toevoegen';
	@override String get playerName => 'Spelernaam';
	@override String get playerNameHint => 'Mijn speler';
	@override String get playerCommand => 'Commando';
	@override String get playerPackage => 'Pakketnaam';
	@override String get playerUrlScheme => 'URL-schema';
	@override String get off => 'Uit';
	@override String get launchFailed => 'Kan externe speler niet openen';
	@override String appNotInstalled({required Object name}) => '${name} is niet geïnstalleerd';
	@override String get playInExternalPlayer => 'Afspelen in externe speler';
}

// Path: metadataEdit
class _TranslationsMetadataEditNl extends TranslationsMetadataEditEn {
	_TranslationsMetadataEditNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get editMetadata => 'Bewerken...';
	@override String get screenTitle => 'Metadata bewerken';
	@override String get basicInfo => 'Basisinformatie';
	@override String get artwork => 'Artwork';
	@override String get advancedSettings => 'Geavanceerde instellingen';
	@override String get title => 'Titel';
	@override String get sortTitle => 'Sorteertitel';
	@override String get originalTitle => 'Oorspronkelijke titel';
	@override String get releaseDate => 'Releasedatum';
	@override String get contentRating => 'Leeftijdsclassificatie';
	@override String get studio => 'Studio';
	@override String get tagline => 'Tagline';
	@override String get summary => 'Samenvatting';
	@override String get poster => 'Poster';
	@override String get background => 'Achtergrond';
	@override String get logo => 'Logo';
	@override String get squareArt => 'Vierkante afbeelding';
	@override String get selectPoster => 'Poster selecteren';
	@override String get selectBackground => 'Achtergrond selecteren';
	@override String get selectLogo => 'Logo selecteren';
	@override String get selectSquareArt => 'Vierkante afbeelding selecteren';
	@override String get fromUrl => 'Vanaf URL';
	@override String get uploadFile => 'Bestand uploaden';
	@override String get enterImageUrl => 'Voer afbeeldings-URL in';
	@override String get imageUrl => 'Afbeeldings-URL';
	@override String get metadataUpdated => 'Metadata bijgewerkt';
	@override String get metadataUpdateFailed => 'Metadata bijwerken mislukt';
	@override String get artworkUpdated => 'Artwork bijgewerkt';
	@override String get artworkUpdateFailed => 'Artwork bijwerken mislukt';
	@override String get noArtworkAvailable => 'Geen artwork beschikbaar';
	@override String get notSet => 'Niet ingesteld';
	@override String get libraryDefault => 'Bibliotheekstandaard';
	@override String get accountDefault => 'Accountstandaard';
	@override String get seriesDefault => 'Seriestandaard';
	@override String get episodeSorting => 'Afleveringen sorteren';
	@override String get oldestFirst => 'Oudste eerst';
	@override String get newestFirst => 'Nieuwste eerst';
	@override String get keep => 'Bewaren';
	@override String get allEpisodes => 'Alle afleveringen';
	@override String latestEpisodes({required Object count}) => '${count} nieuwste afleveringen';
	@override String get latestEpisode => 'Nieuwste aflevering';
	@override String episodesAddedPastDays({required Object count}) => 'Afleveringen toegevoegd in de afgelopen ${count} dagen';
	@override String get deleteAfterPlaying => 'Afleveringen verwijderen na afspelen';
	@override String get never => 'Nooit';
	@override String get afterADay => 'Na een dag';
	@override String get afterAWeek => 'Na een week';
	@override String get afterAMonth => 'Na een maand';
	@override String get onNextRefresh => 'Bij volgende verversing';
	@override String get seasons => 'Seizoenen';
	@override String get show => 'Tonen';
	@override String get hide => 'Verbergen';
	@override String get episodeOrdering => 'Afleveringsvolgorde';
	@override String get tmdbAiring => 'The Movie Database (Uitgezonden)';
	@override String get tvdbAiring => 'TheTVDB (Uitgezonden)';
	@override String get tvdbAbsolute => 'TheTVDB (Absoluut)';
	@override String get metadataLanguage => 'Metadatataal';
	@override String get useOriginalTitle => 'Oorspronkelijke titel gebruiken';
	@override String get preferredAudioLanguage => 'Voorkeurstaal audio';
	@override String get preferredSubtitleLanguage => 'Voorkeurstaal ondertiteling';
	@override String get subtitleMode => 'Automatische ondertitelselectie';
	@override String get manuallySelected => 'Handmatig geselecteerd';
	@override String get shownWithForeignAudio => 'Weergeven bij anderstalig geluid';
	@override String get alwaysEnabled => 'Altijd ingeschakeld';
	@override String get tags => 'Tags';
	@override String get addTag => 'Tag toevoegen';
	@override String get genre => 'Genre';
	@override String get director => 'Regisseur';
	@override String get writer => 'Schrijver';
	@override String get producer => 'Producent';
	@override String get country => 'Land';
	@override String get collection => 'Collectie';
	@override String get label => 'Label';
	@override String get style => 'Stijl';
	@override String get mood => 'Stemming';
}

// Path: matchScreen
class _TranslationsMatchScreenNl extends TranslationsMatchScreenEn {
	_TranslationsMatchScreenNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get match => 'Koppelen...';
	@override String get fixMatch => 'Koppeling herstellen...';
	@override String get unmatch => 'Ontkoppelen';
	@override String get unmatchConfirm => 'Deze match wissen? Plex behandelt dit als niet-gematcht tot het opnieuw gematcht is.';
	@override String get unmatchSuccess => 'Item ontkoppeld';
	@override String get unmatchFailed => 'Kon item niet ontkoppelen';
	@override String get matchApplied => 'Koppeling toegepast';
	@override String get matchFailed => 'Koppeling kon niet worden toegepast';
	@override String get titleHint => 'Titel';
	@override String get yearHint => 'Jaar';
	@override String get search => 'Zoeken';
	@override String get noMatchesFound => 'Geen overeenkomsten gevonden';
}

// Path: serverTasks
class _TranslationsServerTasksNl extends TranslationsServerTasksEn {
	_TranslationsServerTasksNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Servertaken';
	@override String get failedToLoad => 'Taken konden niet worden geladen';
	@override String get noTasks => 'Geen actieve taken';
}

// Path: trakt
class _TranslationsTraktNl extends TranslationsTraktEn {
	_TranslationsTraktNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Trakt';
	@override String get connected => 'Verbonden';
	@override String connectedAs({required Object username}) => 'Verbonden als @${username}';
	@override String get disconnectConfirm => 'Trakt-account loskoppelen?';
	@override String get disconnectConfirmBody => 'Pleya stopt met gebeurtenissen naar Trakt sturen. Je kunt altijd opnieuw verbinden.';
	@override String get scrobble => 'Realtime scrobbling';
	@override String get scrobbleDescription => 'Verstuur play-, pauze- en stopgebeurtenissen tijdens afspelen naar Trakt.';
	@override String get watchedSync => 'Bekeken-status synchroniseren';
	@override String get watchedSyncDescription => 'Wanneer je items als bekeken markeert in Pleya, worden ze ook op Trakt gemarkeerd.';
}

// Path: trackers
class _TranslationsTrackersNl extends TranslationsTrackersEn {
	_TranslationsTrackersNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Trackers';
	@override String get hubSubtitle => 'Synchroniseer kijkvoortgang met Trakt en andere diensten.';
	@override String get notConnected => 'Niet verbonden';
	@override String connectedAs({required Object username}) => 'Verbonden als @${username}';
	@override String get scrobble => 'Voortgang automatisch volgen';
	@override String get scrobbleDescription => 'Werk je lijst bij wanneer je een aflevering of film afrondt.';
	@override String disconnectConfirm({required Object service}) => '${service} loskoppelen?';
	@override String disconnectConfirmBody({required Object service}) => 'Pleya stopt met ${service} bijwerken. Je kunt altijd opnieuw verbinden.';
	@override String connectFailed({required Object service}) => 'Kan niet verbinden met ${service}. Probeer opnieuw.';
	@override late final _TranslationsTrackersServicesNl services = _TranslationsTrackersServicesNl._(_root);
	@override late final _TranslationsTrackersDeviceCodeNl deviceCode = _TranslationsTrackersDeviceCodeNl._(_root);
	@override late final _TranslationsTrackersOauthProxyNl oauthProxy = _TranslationsTrackersOauthProxyNl._(_root);
	@override late final _TranslationsTrackersLibraryFilterNl libraryFilter = _TranslationsTrackersLibraryFilterNl._(_root);
}

// Path: addServer
class _TranslationsAddServerNl extends TranslationsAddServerEn {
	_TranslationsAddServerNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get addJellyfinTitle => 'Jellyfin-server toevoegen';
	@override String get serverUrls => 'Server-URL\'s';
	@override String get serverUrlsHelper => 'Meerdere URL\'s toegestaan, gescheiden door komma\'s.';
	@override String get findServer => 'Server zoeken';
	@override String get searchingLocalServers => 'Lokale Jellyfin-servers zoeken...';
	@override String get localServers => 'Lokale Jellyfin-servers';
	@override String get username => 'Gebruikersnaam';
	@override String get password => 'Wachtwoord';
	@override String get signIn => 'Inloggen';
	@override String get change => 'Wijzigen';
	@override String get required => 'Vereist';
	@override String get couldNotReachServer => 'Kon de server niet bereiken';
	@override String get signInFailed => 'Inloggen mislukt';
	@override String get quickConnectFailed => 'Quick Connect mislukt';
	@override String get addPlexTitle => 'Inloggen met Plex';
	@override String get pinExpired => 'PIN verlopen vóór inloggen. Probeer opnieuw.';
	@override String get duplicatePlexAccount => 'Al aangemeld bij Plex. Meld je af om van account te wisselen.';
	@override String get failedToRegisterAccount => 'Account registreren mislukt';
	@override String get enterJellyfinUrlError => 'Voer de URL van je Jellyfin-server in';
	@override String get addConnectionTitle => 'Verbinding toevoegen';
	@override String addConnectionTitleScoped({required Object name}) => 'Toevoegen aan ${name}';
	@override String get signInWithPlexCard => 'Inloggen met Plex';
	@override String get signInWithPlexCardSubtitle => 'Autoriseer dit apparaat. Gedeelde servers worden toegevoegd.';
	@override String get signInWithPlexCardSubtitleScoped => 'Autoriseer een Plex-account. Home-gebruikers worden profielen.';
	@override String get connectToJellyfinCard => 'Verbinden met Jellyfin';
	@override String get connectToJellyfinCardSubtitle => 'Voer je server-URL, gebruikersnaam en wachtwoord in.';
	@override String connectToJellyfinCardSubtitleScoped({required Object name}) => 'Log in op een Jellyfin-server. Wordt gekoppeld aan ${name}.';
	@override String get borrowFromAnotherProfile => 'Lenen van een ander profiel';
	@override String get borrowFromAnotherProfileSubtitle => 'Hergebruik de verbinding van een ander profiel. PIN-beveiligde profielen vereisen een PIN.';
}

// Path: addLocalFolder
class _TranslationsAddLocalFolderNl extends TranslationsAddLocalFolderEn {
	_TranslationsAddLocalFolderNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get cardTitle => 'Lokale Map';
	@override String get cardSubtitle => 'Blader door mediabestanden uit een map op je apparaat';
	@override String get title => 'Lokale Map Toevoegen';
	@override String get description => 'Selecteer een map op je apparaat met films of series. Pleya scant de mapstructuur en toont je media.';
	@override String get libraryType => 'Bibliotheektype';
	@override String get typeMovies => 'Films';
	@override String get typeTvShows => 'Series';
	@override String get typeMixed => 'Gemengd';
	@override String get directory => 'Map';
	@override String get chooseDirectory => 'Kies een map…';
	@override String get nameLabel => 'Weergavenaam';
	@override String get nameHint => 'bijv. Mijn Films';
	@override String get save => 'Map toevoegen';
	@override String get saveError => 'Lokale map toevoegen mislukt';
}

// Path: pleyaShare
class _TranslationsPleyaShareNl extends TranslationsPleyaShareEn {
	_TranslationsPleyaShareNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get cardTitle => 'Pleya Share';
	@override String get cardSubtitle => 'Verbind met een ander Pleya-apparaat dat media deelt';
	@override String get hostTitle => 'Mijn media delen';
	@override String get hostDescription => 'Andere Pleya-apparaten op dit netwerk kunnen je lokale mappen bekijken, streamen en downloaden. Houd dit scherm open tijdens het delen.';
	@override String get hostToggle => 'Lokale mappen delen';
	@override String get noLocalFolders => 'Voeg eerst een lokale map toe — er is nog niets om te delen.';
	@override String get pairCodeLabel => 'Koppelcode';
	@override String get pairCodeHint => 'Voer deze code in op het andere apparaat. De code verandert na elke geslaagde koppeling.';
	@override String get regenerateCode => 'Nieuwe code';
	@override String get pairedDevices => 'Gekoppelde apparaten';
	@override String get noGuests => 'Nog geen apparaten gekoppeld';
	@override String get revokeGuest => 'Apparaat verwijderen';
	@override String get joinTitle => 'Verbinden met Pleya Share';
	@override String get joinDescription => 'Kies een host op je netwerk of voer het adres in, en typ daarna de 6-cijferige code die op dat apparaat staat.';
	@override String get hostsFound => 'Hosts op je netwerk';
	@override String get searching => 'Zoeken naar hosts…';
	@override String get noHostsFound => 'Geen hosts gevonden. Zet delen aan op het andere apparaat en controleer of beide op hetzelfde netwerk zitten.';
	@override String get refresh => 'Opnieuw zoeken';
	@override String get manualHost => 'Hostadres (IP)';
	@override String get codeLabel => '6-cijferige code';
	@override String get scanQr => 'QR-code scannen';
	@override String get scanQrHint => 'Richt de camera op de QR-code op het host-apparaat';
	@override String get cameraPermissionDenied => 'Camera-toegang is nodig om de QR-code te scannen.';
	@override String get connect => 'Verbinden';
	@override String get pairFailed => 'Koppelen mislukt. Controleer de code en probeer opnieuw.';
	@override String paired({required Object name}) => 'Verbonden met ${name}';
	@override String get pairUnreachable => 'Host niet bereikbaar. Controleer het adres en het netwerk.';
	@override String get addFolder => 'Lokale map toevoegen';
	@override String get notificationTitle => 'Media wordt gedeeld';
	@override String get notificationText => 'Andere Pleya-apparaten kunnen je lokale mappen streamen';
	@override String get hostDescriptionAndroid => 'Andere Pleya-apparaten op dit netwerk kunnen je lokale mappen bekijken, streamen en downloaden. Delen blijft op de achtergrond draaien met een melding.';
	@override String get scanningSubnet => 'Netwerk scannen…';
}

// Path: seerr
class _TranslationsSeerrNl extends TranslationsSeerrEn {
	_TranslationsSeerrNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Aanvragen';
	@override String get hubSubtitle => 'Vraag films en series aan op je Jellyseerr- of Overseerr-server.';
	@override String get notConfigured => 'Niet ingesteld';
	@override String get serverUrl => 'Server-URL';
	@override String get serverUrlHint => 'https://aanvragen.voorbeeld.nl';
	@override String get authMode => 'Inlogmethode';
	@override String get authPlex => 'Inloggen met Plex';
	@override String get authPlexSubtitle => 'Met één tik via je bestaande Plex-login.';
	@override String get authLocal => 'E-mail en wachtwoord';
	@override String get authApiKey => 'API-sleutel';
	@override String get email => 'E-mail';
	@override String get password => 'Wachtwoord';
	@override String get apiKey => 'API-sleutel';
	@override String get apiKeyHint => 'Te vinden onder Instellingen → Algemeen op je server';
	@override String get adminAttributionNote => 'Met een API-sleutel komen aanvragen op naam van de beheerder. Log in met Plex om ze per gebruiker te registreren.';
	@override String get setupOnDesktopNote => 'Tip: dit is makkelijker in te stellen op je telefoon of computer.';
	@override String get testConnection => 'Verbinding testen';
	@override String get save => 'Opslaan';
	@override String get disconnect => 'Ontkoppelen';
	@override String get disconnectConfirm => 'Aanvraagserver ontkoppelen?';
	@override String get disconnectConfirmBody => 'Pleya stuurt geen aanvragen meer. Je kunt altijd opnieuw verbinden.';
	@override String connectedAs({required Object name}) => 'Ingelogd als ${name}';
	@override String serverVersion({required Object version}) => 'Serverversie ${version}';
	@override String get permissionAdmin => 'Beheerder';
	@override String get permissionManage => 'Mag aanvragen goedkeuren';
	@override String get permissionRequest => 'Mag aanvragen';
	@override String get request => 'Aanvragen';
	@override String get requested => 'Aangevraagd';
	@override String get requestAgain => 'Aanvragen';
	@override String get processing => 'Bezig';
	@override String get partiallyAvailable => 'Deels beschikbaar';
	@override String get available => 'Beschikbaar';
	@override String get alreadyRequested => 'Al aangevraagd';
	@override String get pending => 'In afwachting';
	@override String get approved => 'Goedgekeurd';
	@override String get declined => 'Afgewezen';
	@override String get failed => 'Mislukt';
	@override String get completed => 'Afgerond';
	@override String requestConfirm({required Object title}) => '"${title}" aanvragen?';
	@override String get requestMovie => 'Film aanvragen';
	@override String get requestSuccess => 'Aangevraagd';
	@override String get requestFailed => 'Aanvragen mislukt. Probeer opnieuw.';
	@override String get selectSeasons => 'Seizoenen kiezen';
	@override String season({required Object number}) => 'Seizoen ${number}';
	@override String get allSeasons => 'Alle seizoenen';
	@override String seasonsRange({required Object range}) => 'Seizoenen ${range}';
	@override String seasonsCount({required Object count}) => '${count} seizoenen';
	@override String requestedBy({required Object name}) => 'Aangevraagd door ${name}';
	@override String get searchPlaceholder => 'Zoek een film of serie om aan te vragen';
	@override String get byStreamingService => 'Per streamingdienst';
	@override String get showAll => 'Alles tonen';
	@override String get fourK => 'In 4K aanvragen';
	@override String get fourKBadge => '4K';
	@override String percentMatch({required Object percent}) => '${percent}% match';
	@override String quotaRemaining({required Object remaining, required Object limit}) => 'Nog ${remaining} van ${limit} aanvragen';
	@override String get quotaUnlimited => 'Onbeperkt aanvragen';
	@override String get advancedOptions => 'Geavanceerde opties';
	@override String get server => 'Server';
	@override String get qualityProfile => 'Kwaliteitsprofiel';
	@override String get rootFolder => 'Hoofdmap';
	@override String get myRequests => 'Mijn aanvragen';
	@override String get allRequests => 'Alle aanvragen';
	@override String get filterAll => 'Alle';
	@override String get filterPending => 'In afwachting';
	@override String get filterApproved => 'Goedgekeurd';
	@override String get filterAvailable => 'Beschikbaar';
	@override String get filterMovies => 'Films';
	@override String get filterShows => 'Series';
	@override String get approve => 'Goedkeuren';
	@override String get decline => 'Afwijzen';
	@override String get edit => 'Bewerken';
	@override String get cancelRequest => 'Aanvraag annuleren';
	@override String get cancelRequestConfirm => 'Deze aanvraag annuleren?';
	@override String get discoverTitle => 'Ontdekken via Aanvragen';
	@override String get trending => 'Populair nu';
	@override String get popularMovies => 'Populaire films';
	@override String get popularTv => 'Populaire series';
	@override String get upcoming => 'Binnenkort';
	@override String get recommendations => 'Aanbevolen';
	@override String get cast => 'Cast';
	@override String get loadMore => 'Meer laden';
	@override String get searchOnSeerr => 'Niet in je bibliotheek? Zoek op Jellyseerr / Overseerr';
	@override String get searchOnSeerrShort => 'Zoeken via Aanvragen';
	@override String get noResults => 'Geen resultaten gevonden.';
	@override String get errorAuth => 'Inloggen mislukt. Controleer je gegevens.';
	@override String get errorForbidden => 'Je hebt hier geen rechten voor.';
	@override String get errorNetwork => 'Kan de server niet bereiken. Controleer de URL.';
	@override String get errorGeneric => 'Er ging iets mis. Probeer opnieuw.';
}

// Path: tautulli
class _TranslationsTautulliNl extends TranslationsTautulliEn {
	_TranslationsTautulliNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Tautulli';
	@override String get subtitle => 'Tautulli houdt bij wie wat kijkt op je Plex-server. Koppel hem om kijkers, statistieken en live activiteit in Pleya te zien.';
	@override String get adminOnlyNote => 'Tautulli heeft één sleutel die zijn hele beheer-API opent, dus die blijft op dit toestel en alleen jij ziet wat hij meldt. De mensen met wie je je server deelt merken er niets van en hoeven niets in te stellen.';
	@override String get useHistoryForRecommendations => 'Kijkgeschiedenis gebruiken voor aanbevelingen';
	@override String get useHistoryForRecommendationsDescription => 'Gebruikt kijkgeschiedenis van deze Tautulli-server om persoonlijke aanbevelingen te verbeteren voor elk profiel op dit apparaat. Elk profiel krijgt alleen zijn eigen geschiedenis en de verwerking blijft lokaal in Pleya.';
	@override String get integrationConflictNote => 'Er zijn twee verschillende Tautulli-koppelingen voor deze server gevonden, dus de kijkgeschiedenis wordt niet gebruikt tot je opnieuw koppelt met de koppeling die je wilt houden.';
	@override String get serverUrl => 'Tautulli-adres';
	@override String get serverUrlHint => 'http://192.168.1.10:8181 of https://tautulli.voorbeeld.nl';
	@override String get authMode => 'Hoe koppelen';
	@override String get modeDevice => 'Apparaat-token';
	@override String get modeDeviceHelp => 'Ga in Tautulli naar Settings, Tautulli Remote App, en registreer een apparaat. Plak het token hier binnen vijf minuten. Je vaste API-key blijft zo buiten de app, en je kunt dit ene apparaat later weer intrekken.';
	@override String get modeApiKey => 'API-key';
	@override String get modeApiKeyHelp => 'De vaste sleutel uit Settings, Web Interface. Die geeft volledige toegang tot Tautulli, dus gebruik hem alleen als het apparaat-token niet lukt.';
	@override String get deviceToken => 'Apparaat-token';
	@override String get apiKey => 'API-key';
	@override String get testConnection => 'Verbinding testen';
	@override String get save => 'Opslaan';
	@override String get connected => 'Verbonden';
	@override String get disconnect => 'Ontkoppelen';
	@override String get disconnectConfirm => 'Tautulli ontkoppelen?';
	@override String get disconnectConfirmBody => 'Pleya vergeet het adres en het token. Kijkers, statistieken en live activiteit verdwijnen tot je opnieuw koppelt.';
	@override String get setupOnDesktopNote => 'Makkelijker op je telefoon of computer: het adres en het token typen lastig met een afstandsbediening.';
	@override String get errorNetwork => 'Tautulli niet bereikbaar. Controleer het adres en of hij vanaf dit toestel te bereiken is.';
	@override String get errorAuth => 'Tautulli weigert deze sleutel.';
	@override String get errorTokenExpired => 'Tautulli weigert dit token. Een apparaat-token is maar vijf minuten geldig, dus maak een nieuwe aan en probeer opnieuw.';
	@override String get errorModeMismatch => 'Tautulli weigert dit token, en het lijkt op je permanente API-sleutel in plaats van op een apparaat-token. Zet hierboven om naar API-sleutel, of registreer een apparaat in Tautulli en plak dat token.';
	@override String get errorUrlRequired => 'Vul het adres van je Tautulli-server in.';
	@override String get errorTokenRequired => 'Vul een token in.';
	@override String get errorNotTautulli => 'Er antwoordt iets op dat adres, maar het is geen Tautulli. Controleer het adres en het basispad, en of er een loginpagina voor staat.';
	@override String errorServer({required Object code}) => 'Tautulli meldt een serverfout (HTTP ${code}).';
	@override String get errorGeneric => 'Koppelen is niet gelukt.';
}

// Path: nowWatching
class _TranslationsNowWatchingNl extends TranslationsNowWatchingEn {
	_TranslationsNowWatchingNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Nu aan het kijken';
	@override String get tooltip => 'Bekijk wie er nu kijkt';
	@override String streams({required Object count}) => '${count} streams';
	@override String get oneStream => '1 stream';
	@override String transcoding({required Object count}) => '${count} transcoderen';
	@override String get directPlay => 'Direct play';
	@override String get directStream => 'Direct stream';
	@override String get transcode => 'Transcoderen';
	@override String get paused => 'Gepauzeerd';
	@override String remaining({required Object time}) => 'nog ${time}';
	@override String watchingNow({required Object name}) => '${name} kijkt dit nu';
	@override String get hardware => 'Hardware';
	@override String get onLan => 'Op je netwerk';
	@override String get onWan => 'Van buiten';
	@override String get unavailable => 'Tautulli gaf geen antwoord';
	@override String get sidebarLabel => 'Nu aan het kijken';
}

// Path: sourcePicker
class _TranslationsSourcePickerNl extends TranslationsSourcePickerEn {
	_TranslationsSourcePickerNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get playTitle => 'Kies waar je wilt afspelen';
	@override String get detailsTitle => 'Kies een bron voor de details';
	@override String get availableOnOneServer => 'Beschikbaar op 1 server';
	@override String availableOnManyServers({required Object count}) => 'Beschikbaar op ${count} servers';
	@override String get oneServerUnchecked => '1 server kon niet worden gecontroleerd';
	@override String manyServersUnchecked({required Object count}) => '${count} servers konden niet worden gecontroleerd';
	@override String get checkingMoreSources => 'Meer bronnen controleren…';
	@override String get lastUsed => 'Laatst gebruikt';
	@override String get currentSource => 'Huidige bron';
	@override String get unavailable => 'Niet beschikbaar';
	@override String get signInRequired => 'Opnieuw aanmelden vereist';
	@override String resumeAt({required Object position}) => 'Hervatten op ${position}';
	@override String get watched => 'Bekeken';
	@override String get noneReachableTitle => 'Geen bron is momenteel bereikbaar.';
	@override String get reauthRequiredTitle => 'Meld je opnieuw aan om deze titel te bereiken.';
	@override String get manageServers => 'Servers beheren';
	@override String sourceLabel({required Object source}) => 'Bron: ${source}';
	@override String get change => 'Wijzigen';
	@override String get playbackFailedTitle => 'Deze bron kon niet worden afgespeeld.';
	@override String get detailLoadFailedTitle => 'Deze titel kon niet worden geladen.';
	@override String get chooseAnotherSource => 'Andere bron kiezen';
	@override String rowSemantics({required Object index, required Object count, required Object description}) => 'Bron ${index} van ${count}: ${description}';
	@override String get preferredServer => 'Voorkeursserver';
	@override String setPreferredServer({required Object server}) => 'Altijd ${server} gebruiken';
}

// Path: unifiedCatalog
class _TranslationsUnifiedCatalogNl extends TranslationsUnifiedCatalogEn {
	_TranslationsUnifiedCatalogNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get moviesTitle => 'Films';
	@override String get seriesTitle => 'Series';
	@override String sources({required Object count}) => '${count} bronnen';
	@override String get allSources => 'Alle bronnen';
	@override String get oneSource => '1 bron';
	@override String seasons({required Object count}) => '${count} seizoenen';
	@override String get oneSeason => '1 seizoen';
	@override String titleCount({required Object count}) => '${count} titels';
	@override String get oneTitle => '1 titel';
	@override String titlesLoaded({required Object count}) => '${count} titels geladen';
	@override String get loadMore => 'Meer laden';
	@override String get loadingMore => 'Meer laden…';
	@override late final _TranslationsUnifiedCatalogSortNl sort = _TranslationsUnifiedCatalogSortNl._(_root);
	@override late final _TranslationsUnifiedCatalogFiltersNl filters = _TranslationsUnifiedCatalogFiltersNl._(_root);
	@override late final _TranslationsUnifiedCatalogStatesNl states = _TranslationsUnifiedCatalogStatesNl._(_root);
	@override late final _TranslationsUnifiedCatalogSemanticsNl semantics = _TranslationsUnifiedCatalogSemanticsNl._(_root);
	@override late final _TranslationsUnifiedCatalogDiscoveryNl discovery = _TranslationsUnifiedCatalogDiscoveryNl._(_root);
	@override late final _TranslationsUnifiedCatalogHomeNl home = _TranslationsUnifiedCatalogHomeNl._(_root);
}

// Path: tvNavigation
class _TranslationsTvNavigationNl extends TranslationsTvNavigationEn {
	_TranslationsTvNavigationNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get activeDestination => 'huidige sectie';
	@override String get attentionRequired => 'vereist aandacht';
}

// Path: tvMyPleya
class _TranslationsTvMyPleyaNl extends TranslationsTvMyPleyaEn {
	_TranslationsTvMyPleyaNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get groupContent => 'Mijn content';
	@override String get groupSources => 'Bibliotheken en bronnen';
	@override String get groupPleya => 'Pleya';
	@override String serversOnline({required Object online, required Object total}) => '${online} van ${total} servers online';
	@override String get noServers => 'Geen servers verbonden';
	@override String get statusOnline => 'Online';
	@override String get statusOffline => 'Offline';
	@override String get servers => 'Servers';
	@override String get activity => 'Activiteit';
	@override String get logs => 'Logs en diagnose';
	@override String signedInAs({required Object name, required Object version}) => 'Aangemeld als ${name} · Pleya ${version}';
	@override String get watchlistSubtitle => 'Bewaarde films en series';
	@override String get requestsSubtitle => 'Verzoeken en ontdekken';
	@override String get downloadsSubtitle => 'Offline en synchronisatieregels';
	@override String get librariesSubtitle => 'Media, collecties, afspeellijsten';
	@override String get serversSubtitle => 'Verbindingen en lokale bronnen';
	@override String get activitySubtitle => 'Nu kijken, samen kijken, remote';
	@override String get watchTogetherSubtitle => 'Kijk gelijk met vrienden';
	@override String get settingsSubtitle => 'Weergave, speler, trackers';
	@override String get logsSubtitle => 'Logbestanden en crashrapportage';
	@override String get aboutSubtitle => 'Versie en licenties';
	@override String get logoutSubtitle => 'Afmelden op dit apparaat';
	@override late final _TranslationsTvMyPleyaSemanticsNl semantics = _TranslationsTvMyPleyaSemanticsNl._(_root);
}

// Path: tvContextMenu
class _TranslationsTvContextMenuNl extends TranslationsTvContextMenuEn {
	_TranslationsTvContextMenuNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Acties';
	@override String menuSemantics({required Object index, required Object count, required Object label}) => 'Actie ${index} van ${count}: ${label}';
	@override String get noUsableSource => 'Er is momenteel geen bron bereikbaar, dus dit kan nu niet worden gewijzigd.';
	@override String doneOnAll({required Object count}) => 'Gereed op alle ${count} bronnen';
	@override String doneOnSome({required Object done, required Object total}) => 'Gereed op ${done} van ${total} bronnen. De rest wordt opnieuw geprobeerd zodra ze weer online zijn.';
	@override String doneOnSomeNoRetry({required Object done, required Object total}) => 'Gereed op ${done} van ${total} bronnen.';
	@override String get failed => 'Dat is niet gelukt';
}

// Path: search.filters
class _TranslationsSearchFiltersNl extends TranslationsSearchFiltersEn {
	_TranslationsSearchFiltersNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get all => 'Alles';
	@override String get movies => 'Films';
	@override String get shows => 'Series';
	@override String get episodes => 'Afleveringen';
	@override String get people => 'Personen';
	@override String get other => 'Overig';
}

// Path: hotkeys.actions
class _TranslationsHotkeysActionsNl extends TranslationsHotkeysActionsEn {
	_TranslationsHotkeysActionsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get playPause => 'Afspelen/Pauzeren';
	@override String get volumeUp => 'Volume omhoog';
	@override String get volumeDown => 'Volume omlaag';
	@override String seekForward({required Object seconds}) => 'Vooruitspoelen (${seconds}s)';
	@override String seekBackward({required Object seconds}) => 'Terugspoelen (${seconds}s)';
	@override String get fullscreenToggle => 'Volledig scherm';
	@override String get muteToggle => 'Dempen';
	@override String get subtitleToggle => 'Ondertiteling';
	@override String get audioTrackNext => 'Volgende audiotrack';
	@override String get subtitleTrackNext => 'Volgende ondertiteltrack';
	@override String get chapterNext => 'Volgend hoofdstuk';
	@override String get chapterPrevious => 'Vorig hoofdstuk';
	@override String get episodeNext => 'Volgende aflevering';
	@override String get episodePrevious => 'Vorige aflevering';
	@override String get speedIncrease => 'Snelheid verhogen';
	@override String get speedDecrease => 'Snelheid verlagen';
	@override String get speedReset => 'Snelheid resetten';
	@override String get zoomIn => 'Inzoomen';
	@override String get zoomOut => 'Uitzoomen';
	@override String get zoomReset => 'Zoom resetten';
	@override String get subSeekNext => 'Naar volgende ondertitel';
	@override String get subSeekPrev => 'Naar vorige ondertitel';
	@override String get shaderToggle => 'Shaders aan/uit';
	@override String get skipMarker => 'Intro/aftiteling overslaan';
	@override String get screenshot => 'Schermafbeelding maken';
}

// Path: videoControls.tvPanel
class _TranslationsVideoControlsTvPanelNl extends TranslationsVideoControlsTvPanelEn {
	_TranslationsVideoControlsTvPanelNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get information => 'Informatie';
	@override String get audio => 'Geluid';
	@override String get tracks => 'Sporen';
	@override String get options => 'Opties';
	@override String get more => 'Meer…';
}

// Path: videoControls.pipErrors
class _TranslationsVideoControlsPipErrorsNl extends TranslationsVideoControlsPipErrorsEn {
	_TranslationsVideoControlsPipErrorsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get androidVersion => 'Vereist Android 8.0 of nieuwer';
	@override String get iosVersion => 'Vereist iOS 15.0 of nieuwer';
	@override String get permissionDisabled => 'Picture-in-picture is uitgeschakeld. Schakel het in via systeeminstellingen.';
	@override String get notSupported => 'Dit apparaat ondersteunt geen beeld-in-beeld modus';
	@override String get voSwitchFailed => 'Kan video-uitvoer niet wisselen voor beeld-in-beeld';
	@override String get failed => 'Beeld-in-beeld kon niet worden gestart';
	@override String get unknown => 'Er is een fout opgetreden';
}

// Path: libraries.tabs
class _TranslationsLibrariesTabsNl extends TranslationsLibrariesTabsEn {
	_TranslationsLibrariesTabsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get recommended => 'Aanbevolen';
	@override String get browse => 'Bladeren';
	@override String get collections => 'Collecties';
	@override String get playlists => 'Afspeellijsten';
}

// Path: libraries.groupings
class _TranslationsLibrariesGroupingsNl extends TranslationsLibrariesGroupingsEn {
	_TranslationsLibrariesGroupingsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Groepering';
	@override String get all => 'Alles';
	@override String get movies => 'Films';
	@override String get shows => 'Series';
	@override String get seasons => 'Seizoenen';
	@override String get episodes => 'Afleveringen';
	@override String get folders => 'Mappen';
}

// Path: libraries.filterCategories
class _TranslationsLibrariesFilterCategoriesNl extends TranslationsLibrariesFilterCategoriesEn {
	_TranslationsLibrariesFilterCategoriesNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get genre => 'Genre';
	@override String get year => 'Jaar';
	@override String get contentRating => 'Leeftijdsclassificatie';
	@override String get tag => 'Tag';
	@override String get unwatched => 'Onbekeken';
}

// Path: libraries.sortLabels
class _TranslationsLibrariesSortLabelsNl extends TranslationsLibrariesSortLabelsEn {
	_TranslationsLibrariesSortLabelsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Titel';
	@override String get dateAdded => 'Toegevoegd op';
	@override String get releaseDate => 'Uitgavedatum';
	@override String get rating => 'Beoordeling';
	@override String get communityRating => 'Communitybeoordeling';
	@override String get criticRating => 'Criticusbeoordeling';
	@override String get userRating => 'Gebruikersbeoordeling';
	@override String get lastPlayed => 'Laatst afgespeeld';
	@override String get datePlayed => 'Afspeeldatum';
	@override String get playCount => 'Aantal afspelingen';
	@override String get productionYear => 'Productiejaar';
	@override String get runtime => 'Speelduur';
	@override String get officialRating => 'Officiële beoordeling';
	@override String get premiereDate => 'Premièredatum';
	@override String get startDate => 'Begindatum';
	@override String get airTime => 'Uitzendtijd';
	@override String get studio => 'Studio';
	@override String get random => 'Willekeurig';
	@override String get dateShared => 'Gedeeld op';
	@override String get latestEpisodeAirDate => 'Laatste afleveringsuitzending';
	@override String get lastEpisodeDateAdded => 'Datum laatst toegevoegde aflevering';
}

// Path: companionRemote.session
class _TranslationsCompanionRemoteSessionNl extends TranslationsCompanionRemoteSessionEn {
	_TranslationsCompanionRemoteSessionNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get startingServer => 'Externe server starten...';
	@override String get failedToCreate => 'Kan externe server niet starten:';
	@override String get hostAddress => 'Hostadres';
	@override String get connected => 'Verbonden';
	@override String get serverRunning => 'Externe server actief';
	@override String get serverStopped => 'Externe server gestopt';
	@override String get serverRunningDescription => 'Mobiele apparaten op je netwerk kunnen met deze app verbinden';
	@override String get serverStoppedDescription => 'Start de server om mobiele apparaten te laten verbinden';
	@override String get usePhoneToControl => 'Gebruik je mobiele apparaat om deze app te bedienen';
	@override String get startServer => 'Server starten';
	@override String get stopServer => 'Server stoppen';
	@override String get minimize => 'Minimaliseren';
}

// Path: companionRemote.pairing
class _TranslationsCompanionRemotePairingNl extends TranslationsCompanionRemotePairingEn {
	_TranslationsCompanionRemotePairingNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get discoveryDescription => 'Pleya-apparaten met hetzelfde Plex-account verschijnen hier';
	@override String get hostAddressHint => '192.168.1.100:48632';
	@override String get connecting => 'Verbinden...';
	@override String get searchingForDevices => 'Apparaten zoeken...';
	@override String get noDevicesFound => 'Geen apparaten gevonden op je netwerk';
	@override String get noDevicesHint => 'Open Pleya op desktop en gebruik dezelfde WiFi';
	@override String get availableDevices => 'Beschikbare apparaten';
	@override String get manualConnection => 'Handmatige verbinding';
	@override String get cryptoInitFailed => 'Kon beveiligde verbinding niet starten. Log eerst in bij Plex.';
	@override String get validationHostRequired => 'Voer het hostadres in';
	@override String get validationHostFormat => 'Formaat moet IP:poort zijn (bijv. 192.168.1.100:48632)';
	@override String get connectionTimedOut => 'Verbinding verlopen. Gebruik hetzelfde netwerk op beide apparaten.';
	@override String get sessionNotFound => 'Apparaat niet gevonden. Zorg dat Pleya op de host draait.';
	@override String get authFailed => 'Authenticatie mislukt. Beide apparaten hebben hetzelfde Plex-account nodig.';
	@override String get failedToConnect => 'Kan niet verbinden';
}

// Path: companionRemote.remote
class _TranslationsCompanionRemoteRemoteNl extends TranslationsCompanionRemoteRemoteEn {
	_TranslationsCompanionRemoteRemoteNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get disconnectConfirm => 'Wil je de verbinding met de externe sessie verbreken?';
	@override String get reconnecting => 'Opnieuw verbinden...';
	@override String attemptOf({required Object current}) => 'Poging ${current} van 5';
	@override String get retryNow => 'Nu opnieuw proberen';
	@override String get tabRemote => 'Afstandsbediening';
	@override String get tabPlay => 'Afspelen';
	@override String get tabMore => 'Meer';
	@override String get menu => 'Menu';
	@override String get tabNavigation => 'Tabnavigatie';
	@override String get tabDiscover => 'Ontdekken';
	@override String get tabLibraries => 'Bibliotheken';
	@override String get tabSearch => 'Zoeken';
	@override String get tabDownloads => 'Downloads';
	@override String get tabSettings => 'Instellingen';
	@override String get previous => 'Vorige';
	@override String get playPause => 'Afspelen/Pauzeren';
	@override String get next => 'Volgende';
	@override String get seekBack => 'Terugspoelen';
	@override String get stop => 'Stoppen';
	@override String get seekForward => 'Vooruitspoelen';
	@override String get volume => 'Volume';
	@override String get volumeDown => 'Omlaag';
	@override String get volumeUp => 'Omhoog';
	@override String get fullscreen => 'Volledig scherm';
	@override String get subtitles => 'Ondertitels';
	@override String get audio => 'Audio';
	@override String get searchHint => 'Zoeken op desktop...';
}

// Path: companionRemote.errors
class _TranslationsCompanionRemoteErrorsNl extends TranslationsCompanionRemoteErrorsEn {
	_TranslationsCompanionRemoteErrorsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get noNetworkInterface => 'Geen netwerkinterface gevonden';
	@override String get authenticationFailed => 'Authenticatie mislukt';
	@override String get joinTimedOut => 'Time-out bij deelnemen aan sessie';
	@override String get failedToConnectAnyAddress => 'Kan met geen enkel adres verbinden';
	@override String connectionLostAfterAttempts({required Object attempts}) => 'Verbinding verloren na ${attempts} pogingen';
	@override String get connectionLost => 'Verbinding verloren';
}

// Path: videoSettings.audioOutputModes
class _TranslationsVideoSettingsAudioOutputModesNl extends TranslationsVideoSettingsAudioOutputModesEn {
	_TranslationsVideoSettingsAudioOutputModesNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get auto => 'Automatisch';
	@override String get passthrough => 'Doorvoeren';
	@override String get pcm => 'PCM (decoderen)';
}

// Path: videoSettings.audioOutputDecisions
class _TranslationsVideoSettingsAudioOutputDecisionsNl extends TranslationsVideoSettingsAudioOutputDecisionsEn {
	_TranslationsVideoSettingsAudioOutputDecisionsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get passthrough => 'Dolby-doorvoer';
	@override String get pcmMultichannel => 'PCM meerkanaals';
	@override String get pcmStereo => 'PCM stereo';
}

// Path: videoSettings.audioOutputModeDescriptions
class _TranslationsVideoSettingsAudioOutputModeDescriptionsNl extends TranslationsVideoSettingsAudioOutputModeDescriptionsEn {
	_TranslationsVideoSettingsAudioOutputModeDescriptionsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get auto => 'Verbreedt naar meerkanaals waar de uitgang dat toelaat; stuurt nooit een bitstream';
	@override String get passthrough => 'Stuur Dolby altijd onbewerkt naar de ontvanger';
	@override String get pcm => 'Decodeer altijd in de app';
}

// Path: videoSettings.audioOutputRendering
class _TranslationsVideoSettingsAudioOutputRenderingNl extends TranslationsVideoSettingsAudioOutputRenderingEn {
	_TranslationsVideoSettingsAudioOutputRenderingNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get monoStereo => 'Stereo';
	@override String get surround => 'Surround';
	@override String get spatialAudio => 'Spatial Audio';
	@override String get dolbyAudio => 'Dolby Audio';
	@override String get dolbyAtmos => 'Dolby Atmos';
}

// Path: videoSettings.audioPriorities
class _TranslationsVideoSettingsAudioPrioritiesNl extends TranslationsVideoSettingsAudioPrioritiesEn {
	_TranslationsVideoSettingsAudioPrioritiesNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get evenVolume => 'Gelijkmatig volume';
	@override String get originalDolby => 'Originele Dolby Atmos';
}

// Path: trackers.services
class _TranslationsTrackersServicesNl extends TranslationsTrackersServicesEn {
	_TranslationsTrackersServicesNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get mal => 'MyAnimeList';
	@override String get anilist => 'AniList';
	@override String get simkl => 'Simkl';
}

// Path: trackers.deviceCode
class _TranslationsTrackersDeviceCodeNl extends TranslationsTrackersDeviceCodeEn {
	_TranslationsTrackersDeviceCodeNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String title({required Object service}) => 'Pleya activeren op ${service}';
	@override String body({required Object url}) => 'Ga naar ${url} en voer deze code in:';
	@override String openToActivate({required Object service}) => 'Open ${service} om te activeren';
	@override String get waitingForAuthorization => 'Wachten op autorisatie…';
	@override String get codeCopied => 'Code gekopieerd';
}

// Path: trackers.oauthProxy
class _TranslationsTrackersOauthProxyNl extends TranslationsTrackersOauthProxyEn {
	_TranslationsTrackersOauthProxyNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String title({required Object service}) => 'Aanmelden bij ${service}';
	@override String get body => 'Scan deze QR-code of open de URL op een apparaat.';
	@override String openToSignIn({required Object service}) => '${service} openen om aan te melden';
	@override String get urlCopied => 'URL gekopieerd';
}

// Path: trackers.libraryFilter
class _TranslationsTrackersLibraryFilterNl extends TranslationsTrackersLibraryFilterEn {
	_TranslationsTrackersLibraryFilterNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Bibliotheekfilter';
	@override String get subtitleAllSyncing => 'Alle bibliotheken synchroniseren';
	@override String get subtitleNoneSyncing => 'Niets wordt gesynchroniseerd';
	@override String subtitleBlocked({required Object count}) => '${count} geblokkeerd';
	@override String subtitleAllowed({required Object count}) => '${count} toegestaan';
	@override String get mode => 'Filtermodus';
	@override String get modeBlacklist => 'Zwarte lijst';
	@override String get modeWhitelist => 'Witte lijst';
	@override String get modeHintBlacklist => 'Synchroniseer alle bibliotheken behalve die hieronder aangevinkt zijn.';
	@override String get modeHintWhitelist => 'Synchroniseer alleen de hieronder aangevinkte bibliotheken.';
	@override String get libraries => 'Bibliotheken';
	@override String get noLibraries => 'Geen bibliotheken beschikbaar';
}

// Path: unifiedCatalog.sort
class _TranslationsUnifiedCatalogSortNl extends TranslationsUnifiedCatalogSortEn {
	_TranslationsUnifiedCatalogSortNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Sorteren';
	@override String get titleAsc => 'Titel A–Z';
	@override String get titleDesc => 'Titel Z–A';
	@override String get recentlyAdded => 'Recent toegevoegd';
	@override String get oldestAdded => 'Oudst toegevoegd';
	@override String get newestRelease => 'Nieuwste release';
	@override String get oldestRelease => 'Oudste release';
	@override String get recentlyWatched => 'Recent bekeken';
}

// Path: unifiedCatalog.filters
class _TranslationsUnifiedCatalogFiltersNl extends TranslationsUnifiedCatalogFiltersEn {
	_TranslationsUnifiedCatalogFiltersNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Filters';
	@override String get status => 'Status';
	@override String get genre => 'Genre';
	@override String get year => 'Jaar';
	@override String get servers => 'Servers';
	@override String get libraries => 'Bibliotheken';
	@override String get apply => 'Toepassen';
	@override String get clearAll => 'Alles wissen';
	@override String get all => 'Alle';
	@override String get unwatched => 'Niet bekeken';
	@override String get unsupported => 'Niet beschikbaar voor de huidige bronnen';
	@override String get someUnavailable => 'Sommige filters zijn niet beschikbaar voor de geselecteerde bronnen';
	@override String get noValues => 'Niets om uit te kiezen';
}

// Path: unifiedCatalog.states
class _TranslationsUnifiedCatalogStatesNl extends TranslationsUnifiedCatalogStatesEn {
	_TranslationsUnifiedCatalogStatesNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get emptyTitle => 'Deze catalogus is leeg';
	@override String get emptyBody => 'Geen zichtbare bibliotheek bevat iets voor deze pagina.';
	@override String get filterEmptyTitle => 'Niets voldoet aan deze filters';
	@override String get filterEmptyBody => 'Wis een filter om meer titels te zien.';
	@override String get clearFilters => 'Filters wissen';
	@override String get errorTitle => 'De catalogus kon niet worden geladen';
	@override String get errorBody => 'Geen enkele server antwoordde. Controleer je verbinding en probeer het opnieuw.';
	@override String get partialOne => '1 bibliotheek antwoordde niet';
	@override String partialMany({required Object count}) => '${count} bibliotheken antwoordden niet';
}

// Path: unifiedCatalog.semantics
class _TranslationsUnifiedCatalogSemanticsNl extends TranslationsUnifiedCatalogSemanticsEn {
	_TranslationsUnifiedCatalogSemanticsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get watched => 'Bekeken';
	@override String get inProgress => 'Bezig';
	@override String get loadingMore => 'Meer titels laden';
}

// Path: unifiedCatalog.discovery
class _TranslationsUnifiedCatalogDiscoveryNl extends TranslationsUnifiedCatalogDiscoveryEn {
	_TranslationsUnifiedCatalogDiscoveryNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get allMovies => 'Alle films';
	@override String get allSeries => 'Alle series';
	@override String episodeLabel({required Object season, required Object episode}) => 'S${season} A${episode}';
	@override String get partial => 'Niet alle bronnen antwoordden';
	@override String get emptyTitle => 'Nog niets te ontdekken';
	@override String get emptyBody => 'Geen zichtbare bibliotheek heeft hier iets te tonen.';
	@override late final _TranslationsUnifiedCatalogDiscoverySemanticsNl semantics = _TranslationsUnifiedCatalogDiscoverySemanticsNl._(_root);
}

// Path: unifiedCatalog.home
class _TranslationsUnifiedCatalogHomeNl extends TranslationsUnifiedCatalogHomeEn {
	_TranslationsUnifiedCatalogHomeNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get featured => 'Uitgelicht';
}

// Path: tvMyPleya.semantics
class _TranslationsTvMyPleyaSemanticsNl extends TranslationsTvMyPleyaSemanticsEn {
	_TranslationsTvMyPleyaSemanticsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String tile({required Object title, required Object subtitle}) => '${title}. ${subtitle}';
	@override String tileWithCount({required Object title, required Object subtitle, required Object count}) => '${title}. ${subtitle}. ${count}';
}

// Path: unifiedCatalog.discovery.semantics
class _TranslationsUnifiedCatalogDiscoverySemanticsNl extends TranslationsUnifiedCatalogDiscoverySemanticsEn {
	_TranslationsUnifiedCatalogDiscoverySemanticsNl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String section({required Object title, required Object count}) => '${title}, ${count} titels';
	@override String position({required Object position, required Object count}) => '${position} van ${count}';
	@override String get viewAllMovies => 'Alle films bekijken, opent de volledige catalogus';
	@override String get viewAllSeries => 'Alle series bekijken, opent de volledige catalogus';
}

/// The flat map containing all translations for locale <nl>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsNl {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'states.emptyTitle' => 'Nog niets hier',
			'states.errorTitle' => 'Er ging iets mis',
			'states.offlineTitle' => 'Je bent offline',
			'states.offlineMessage' => 'Maak opnieuw verbinding om dit te laden.',
			'app.title' => 'Pleya',
			'auth.signIn' => 'Inloggen',
			'auth.signInWithPlex' => 'Inloggen met Plex',
			'auth.showQRCode' => 'Toon QR-code',
			'auth.authenticate' => 'Authenticeren',
			'auth.authenticationTimeout' => 'Inloggen is niet voltooid. Probeer het opnieuw.',
			'auth.usingJellyfinInstead' => 'Gebruik je een Jellyfin-server? Verbind met Jellyfin',
			'auth.scanQRToSignIn' => 'Scan deze QR-code om in te loggen',
			'auth.waitingForAuth' => 'Wachten op authenticatie...\nMeld je aan via je browser.',
			'auth.useBrowser' => 'Gebruik browser',
			'auth.or' => 'of',
			'auth.connectToJellyfin' => 'Verbinden met Jellyfin',
			'auth.useQuickConnect' => 'Quick Connect gebruiken',
			'auth.quickConnectInstructions' => 'Open Quick Connect in Jellyfin en voer deze code in.',
			'auth.quickConnectWaiting' => 'Wachten op goedkeuring…',
			'auth.quickConnectCancel' => 'Annuleren',
			'auth.quickConnectExpired' => 'Quick Connect is verlopen. Probeer opnieuw.',
			'auth.chooseHowToSignIn' => 'Kies hoe je inlogt',
			'auth.chooseHowToSignInDescription' => 'Pleya verbindt met je Plex- of Jellyfin-mediaserver. Kies er een om te beginnen.',
			'auth.tryAgain' => 'Opnieuw proberen',
			'auth.plexTokenLabel' => 'Plex-authenticatietoken',
			'auth.plexTokenHint' => 'Voer je plex.tv-token in',
			'auth.serviceNotReady' => 'Authenticatieservice is nog niet klaar. Probeer het zo opnieuw.',
			'common.cancel' => 'Annuleren',
			'common.save' => 'Opslaan',
			'common.close' => 'Sluiten',
			'common.clear' => 'Wissen',
			'common.reset' => 'Resetten',
			'common.later' => 'Later',
			'common.submit' => 'Verzenden',
			'common.confirm' => 'Bevestigen',
			'common.retry' => 'Opnieuw proberen',
			'common.details' => 'Details',
			'common.logout' => 'Uitloggen',
			'common.unknown' => 'Onbekend',
			'common.refresh' => 'Vernieuwen',
			'common.yes' => 'Ja',
			'common.no' => 'Nee',
			'common.delete' => 'Verwijderen',
			'common.edit' => 'Bewerken',
			'common.shuffle' => 'Willekeurig',
			'common.addTo' => 'Toevoegen aan...',
			'common.createNew' => 'Nieuw aanmaken',
			'common.connect' => 'Verbinden',
			'common.disconnect' => 'Verbinding verbreken',
			'common.play' => 'Afspelen',
			'common.pause' => 'Pauzeren',
			'common.resume' => 'Hervatten',
			'common.error' => 'Fout',
			'common.search' => 'Zoeken',
			'common.home' => 'Home',
			'common.back' => 'Terug',
			'common.settings' => 'Opties',
			'common.mute' => 'Dempen',
			'common.ok' => 'OK',
			'common.off' => 'Uit',
			'common.on' => 'Aan',
			'common.seasonNumber' => ({required Object number}) => 'Seizoen ${number}',
			'common.episodeNumberTitle' => ({required Object number, required Object title}) => 'Aflevering ${number} - ${title}',
			'common.chapterNumber' => ({required Object number}) => 'Hoofdstuk ${number}',
			'common.reconnect' => 'Opnieuw verbinden',
			'common.exit' => 'Afsluiten',
			'common.viewAll' => 'Alles weergeven',
			'common.checkingNetwork' => 'Netwerk controleren...',
			'common.refreshingServers' => 'Servers vernieuwen...',
			'common.loadingServers' => 'Servers laden...',
			'common.connectingToServers' => 'Verbinden met servers...',
			'common.startingOfflineMode' => 'Offlinemodus starten...',
			'common.loading' => 'Laden...',
			'common.fullscreen' => 'Volledig scherm',
			'common.exitFullscreen' => 'Volledig scherm verlaten',
			'common.pressBackAgainToExit' => 'Druk nogmaals op terug om af te sluiten',
			'common.decreaseValue' => ({required Object label}) => '${label} verlagen',
			'common.increaseValue' => ({required Object label}) => '${label} verhogen',
			'screens.licenses' => 'Licenties',
			'screens.switchProfile' => 'Wissel van profiel',
			'screens.whoIsWatching' => 'Wie is er aan het kijken?',
			'screens.manageProfiles' => 'Profielen beheren',
			'screens.subtitleStyling' => 'Ondertitel opmaak',
			'screens.mpvConfig' => 'mpv.conf',
			'screens.logs' => 'Logbestanden',
			'update.available' => 'Update beschikbaar',
			'update.versionAvailable' => ({required Object version}) => 'Versie ${version} is beschikbaar',
			'update.currentVersion' => ({required Object version}) => 'Huidig: ${version}',
			'update.skipVersion' => 'Deze versie overslaan',
			'update.viewRelease' => 'Bekijk release',
			'update.latestVersion' => 'Je hebt de nieuwste versie',
			'update.checkFailed' => 'Kon niet controleren op updates',
			'settings.searchHint' => 'Zoek in instellingen',
			'settings.urlLabel' => 'URL',
			'settings.title' => 'Instellingen',
			'settings.supportDeveloper' => 'Steun Pleya',
			'settings.supportDeveloperDescription' => 'Doneer via Liberapay om de ontwikkeling te steunen',
			'settings.language' => 'Taal',
			'settings.theme' => 'Thema',
			'settings.appearance' => 'Uiterlijk',
			'settings.videoPlayback' => 'Video afspelen',
			'settings.videoPlaybackDescription' => 'Afspeelgedrag configureren',
			'settings.advanced' => 'Geavanceerd',
			'settings.episodePosterMode' => 'Aflevering poster stijl',
			'settings.seriesPoster' => 'Serie poster',
			'settings.seasonPoster' => 'Seizoen poster',
			'settings.episodeThumbnail' => 'Miniatuur',
			'settings.showHeroSectionDescription' => 'Toon uitgelichte inhoud carrousel op startscherm',
			'settings.secondsLabel' => 'Seconden',
			'settings.minutesLabel' => 'Minuten',
			'settings.secondsShort' => 's',
			'settings.minutesShort' => 'm',
			'settings.durationHint' => ({required Object min, required Object max}) => 'Voer duur in (${min}-${max})',
			'settings.systemTheme' => 'Systeem',
			'settings.lightTheme' => 'Licht',
			'settings.darkTheme' => 'Donker',
			'settings.oledTheme' => 'OLED',
			'settings.libraryDensity' => 'Bibliotheek dichtheid',
			'settings.compact' => 'Compact',
			'settings.comfortable' => 'Comfortabel',
			'settings.viewMode' => 'Weergavemodus',
			'settings.gridView' => 'Raster',
			'settings.listView' => 'Lijst',
			'settings.showHeroSection' => 'Toon hoofdsectie',
			'settings.hoverExpandCards' => 'Kaarten uitklappen bij hover',
			'settings.hoverExpandCardsDescription' => 'Toon een voorbeeldkaart met snelknoppen als je over een poster zweeft',
			'settings.continueWatchingAction' => 'Actie voor Doorgaan met kijken',
			'settings.continueWatchingPlay' => 'Afspelen',
			'settings.continueWatchingDetails' => 'Details openen',
			'settings.episodeAction' => 'Afleveringsactie',
			'settings.episodePlay' => 'Afspelen',
			'settings.episodeDetails' => 'Details openen',
			'settings.useGlobalHubs' => 'Startlayout gebruiken',
			'settings.useGlobalHubsDescription' => 'Toon gecombineerde home-hubs. Anders bibliotheekaanbevelingen gebruiken.',
			'settings.showServerNameOnHubs' => 'Servernaam tonen bij hubs',
			'settings.showServerNameOnHubsDescription' => 'Toon servernamen altijd in hubtitels.',
			'settings.groupLibrariesByServer' => 'Bibliotheken groeperen per server',
			'settings.groupLibrariesByServerDescription' => 'Groepeer zijbalkbibliotheken onder elke mediaserver.',
			'settings.alwaysKeepSidebarOpen' => 'Zijbalk altijd open houden',
			'settings.alwaysKeepSidebarOpenDescription' => 'Zijbalk blijft uitgevouwen en inhoudsgebied past zich aan',
			'settings.showUnwatchedCount' => 'Aantal ongekeken tonen',
			'settings.showUnwatchedCountDescription' => 'Toon aantal ongekeken afleveringen bij series en seizoenen',
			'settings.showEpisodeNumberOnCards' => 'Afleveringsnummer op kaarten tonen',
			'settings.showEpisodeNumberOnCardsDescription' => 'Toon seizoen- en afleveringsnummer op afleveringskaarten',
			'settings.showSeasonPostersOnTabs' => 'Toon seizoensposters op tabbladen',
			'settings.showSeasonPostersOnTabsDescription' => 'Toon de poster van elk seizoen boven het tabblad',
			'settings.tvFullCardLayout' => 'Volledige tv-kaarten',
			'settings.tvFullCardLayoutDescription' => 'Gebruik tv-kaarten met alleen afbeeldingen en namen van acteurs als overlay',
			'settings.focusGlow' => 'Focusgloed',
			'settings.focusGlowDescription' => 'Toon een zachte gloed rond de kaart met focus',
			'settings.hideSpoilers' => 'Spoilers voor ongekeken afleveringen verbergen',
			'settings.hideSpoilersDescription' => 'Vervaag miniaturen en beschrijvingen voor niet-bekeken afleveringen',
			'settings.playerBackend' => 'Speler backend',
			'settings.exoPlayer' => 'ExoPlayer (Aanbevolen)',
			'settings.mpv' => 'mpv',
			'settings.hardwareDecoding' => 'Hardware decodering',
			'settings.hardwareDecodingDescription' => 'Gebruik hardware versnelling indien beschikbaar',
			'settings.bufferSize' => 'Buffer grootte',
			'settings.bufferSizeMB' => ({required Object size}) => '${size}MB',
			'settings.bufferSizeAuto' => 'Auto (Aanbevolen)',
			'settings.bufferSizeWarning' => ({required Object heap, required Object size}) => '${heap}MB geheugen beschikbaar. Een buffer van ${size}MB kan afspelen beïnvloeden.',
			'settings.defaultQualityTitle' => 'Standaardkwaliteit',
			'settings.defaultQualityDescription' => 'Wordt gebruikt bij het starten van de weergave. Lagere waarden verminderen de bandbreedte.',
			'settings.subtitleStyling' => 'Ondertitel opmaak',
			'settings.subtitleStylingDescription' => 'Pas ondertitel uiterlijk aan',
			'settings.smallSkipDuration' => 'Korte skip duur',
			'settings.largeSkipDuration' => 'Lange skip duur',
			'settings.rewindOnResume' => 'Terugspoelen bij hervatten',
			'settings.secondsUnit' => ({required Object seconds}) => '${seconds} seconden',
			'settings.defaultSleepTimer' => 'Standaard slaap timer',
			'settings.minutesUnit' => ({required Object minutes}) => 'bij ${minutes} minuten',
			'settings.rememberTrackSelections' => 'Onthoud track selecties per serie/film',
			'settings.rememberTrackSelectionsDescription' => 'Onthoud audio- en ondertitelkeuzes per titel',
			'settings.showChapterMarkersOnTimeline' => 'Hoofdstukmarkeringen op tijdlijn tonen',
			'settings.showChapterMarkersOnTimelineDescription' => 'Verdeel de tijdlijn bij hoofdstukgrenzen',
			'settings.clickVideoTogglesPlayback' => 'Klik op de video om afspelen/pauzeren te wisselen.',
			'settings.clickVideoTogglesPlaybackDescription' => 'Klik op video om af te spelen/pauzeren in plaats van bediening te tonen.',
			'settings.videoPlayerControls' => 'Videospeler bediening',
			'settings.keyboardShortcuts' => 'Toetsenbord sneltoetsen',
			'settings.keyboardShortcutsDescription' => 'Pas toetsenbord sneltoetsen aan',
			'settings.videoPlayerNavigation' => 'Videospeler navigatie',
			'settings.videoPlayerNavigationDescription' => 'Gebruik pijltjestoetsen om door de videospeler bediening te navigeren',
			'settings.watchTogetherRelay' => 'Samen Kijken Relay',
			'settings.watchTogetherRelayDescription' => 'Stel een aangepaste relay in. Iedereen moet dezelfde server gebruiken.',
			'settings.watchTogetherRelayHint' => 'https://mijn-relay.voorbeeld.nl',
			'settings.crashReporting' => 'Crashrapportage',
			'settings.crashReportingDescription' => 'Crashrapporten verzenden om de app te verbeteren',
			'settings.debugLogging' => 'Debug logging',
			'settings.debugLoggingDescription' => 'Schakel gedetailleerde logging in voor probleemoplossing',
			'settings.viewLogs' => 'Bekijk logs',
			'settings.viewLogsDescription' => 'Bekijk applicatie logs',
			'settings.clearCache' => 'Cache wissen',
			'settings.clearCacheDescription' => 'Wis gecachete afbeeldingen en gegevens. Inhoud kan langzamer laden.',
			'settings.clearCacheSuccess' => 'Cache succesvol gewist',
			'settings.resetSettings' => 'Instellingen resetten',
			'settings.resetSettingsDescription' => 'Standaardinstellingen herstellen. Dit kan niet ongedaan worden gemaakt.',
			'settings.resetSettingsSuccess' => 'Instellingen succesvol gereset',
			'settings.backup' => 'Back-up',
			'settings.exportSettings' => 'Instellingen exporteren',
			'settings.exportSettingsDescription' => 'Sla je voorkeuren op in een bestand',
			'settings.exportSettingsSuccess' => 'Instellingen geëxporteerd',
			'settings.exportSettingsFailed' => 'Kon instellingen niet exporteren',
			'settings.importSettings' => 'Instellingen importeren',
			'settings.importSettingsDescription' => 'Voorkeuren herstellen vanuit een bestand',
			'settings.importSettingsConfirm' => 'Hiermee worden je huidige instellingen vervangen. Doorgaan?',
			'settings.importSettingsSuccess' => 'Instellingen geïmporteerd',
			'settings.importSettingsFailed' => 'Kon instellingen niet importeren',
			'settings.importSettingsInvalidFile' => 'Dit bestand is geen geldige Pleya-export',
			'settings.importSettingsNoUser' => 'Meld je aan voordat je instellingen importeert',
			'settings.shortcutsReset' => 'Sneltoetsen gereset naar standaard',
			'settings.about' => 'Over',
			'settings.aboutDescription' => 'App informatie en licenties',
			'settings.updates' => 'Updates',
			'settings.updateAvailable' => 'Update beschikbaar',
			'settings.checkForUpdates' => 'Controleer op updates',
			'settings.autoCheckUpdatesOnStartup' => 'Automatisch controleren op updates bij opstarten',
			'settings.autoCheckUpdatesOnStartupDescription' => 'Melden wanneer er bij start een update beschikbaar is',
			'settings.validationErrorEnterNumber' => 'Voer een geldig nummer in',
			'settings.validationErrorDuration' => ({required Object min, required Object max, required Object unit}) => 'Duur moet tussen ${min} en ${max} ${unit} zijn',
			'settings.shortcutAlreadyAssigned' => ({required Object action}) => 'Sneltoets al toegewezen aan ${action}',
			'settings.shortcutUpdated' => ({required Object action}) => 'Sneltoets bijgewerkt voor ${action}',
			'settings.autoSkip' => 'Automatisch Overslaan',
			'settings.autoSkipIntro' => 'Intro Automatisch Overslaan',
			'settings.autoSkipIntroDescription' => 'Intro-markeringen in afleveringen na enkele seconden automatisch overslaan',
			'settings.autoSkipCredits' => 'Credits Automatisch Overslaan',
			'settings.autoSkipCreditsDescription' => 'Credits automatisch overslaan en volgende aflevering afspelen',
			'settings.forceSkipMarkerFallback' => 'Fallbackmarkeringen afdwingen',
			'settings.forceSkipMarkerFallbackDescription' => 'Gebruik hoofdstuktitelpatronen, zelfs wanneer Plex markeringen heeft',
			'settings.autoSkipDelay' => 'Vertraging Automatisch Overslaan',
			'settings.autoSkipDelayDescription' => ({required Object seconds}) => '${seconds} seconden wachten voor automatisch overslaan',
			'settings.introPattern' => 'Intromarkeringspatroon',
			'settings.introPatternDescription' => 'Reguliere expressie om intromarkeringen in hoofdstuktitels te herkennen',
			'settings.creditsPattern' => 'Aftitelingmarkeringspatroon',
			'settings.creditsPatternDescription' => 'Reguliere expressie om aftitelingmarkeringen in hoofdstuktitels te herkennen',
			'settings.invalidRegex' => 'Ongeldige reguliere expressie',
			'settings.downloads' => 'Downloads',
			'settings.downloadLocationDescription' => 'Kies waar gedownloade content wordt opgeslagen',
			'settings.downloadLocationDefault' => 'Standaard (App-opslag)',
			'settings.downloadLocationCustom' => 'Aangepaste Locatie',
			'settings.selectFolder' => 'Selecteer Map',
			'settings.resetToDefault' => 'Herstel naar Standaard',
			'settings.currentPath' => ({required Object path}) => 'Huidig: ${path}',
			'settings.downloadLocationChanged' => 'Downloadlocatie gewijzigd',
			'settings.downloadLocationReset' => 'Downloadlocatie hersteld naar standaard',
			'settings.downloadLocationInvalid' => 'Geselecteerde map is niet beschrijfbaar',
			'settings.downloadLocationSelectError' => 'Kan map niet selecteren',
			'settings.downloadOnWifiOnly' => 'Alleen via WiFi downloaden',
			'settings.downloadOnWifiOnlyDescription' => 'Voorkom downloads bij gebruik van mobiele data',
			'settings.autoRemoveWatchedDownloads' => 'Bekeken downloads automatisch verwijderen',
			'settings.autoRemoveWatchedDownloadsDescription' => 'Bekeken downloads automatisch verwijderen',
			'settings.cellularDownloadBlocked' => 'Downloads zijn geblokkeerd via mobiel netwerk. Gebruik WiFi of wijzig de instelling.',
			'settings.maxVolume' => 'Maximaal volume',
			'settings.maxVolumeDescription' => 'Volume boven 100% toestaan voor stille media',
			'settings.maxVolumePercent' => ({required Object percent}) => '${percent}%',
			'settings.discordRichPresence' => 'Discord Rich Presence',
			'settings.discordRichPresenceDescription' => 'Toon op Discord wat je aan het kijken bent',
			'settings.trakt' => 'Trakt',
			'settings.traktDescription' => 'Kijkgeschiedenis synchroniseren met Trakt',
			'settings.trackers' => 'Trackers',
			'settings.trackersDescription' => 'Voortgang synchroniseren met Trakt, MyAnimeList, AniList en Simkl',
			'settings.companionRemoteServer' => 'Companion Remote-server',
			'settings.companionRemoteServerDescription' => 'Sta mobiele apparaten op je netwerk toe om deze app te bedienen',
			'settings.autoPip' => 'Automatische beeld-in-beeld',
			'settings.autoPipDescription' => 'Ga naar picture-in-picture bij verlaten tijdens afspelen',
			'settings.matchContentFrameRate' => 'Inhoudsframesnelheid afstemmen',
			'settings.matchContentFrameRateDescription' => 'Stem schermverversing af op videocontent',
			'settings.matchRefreshRate' => 'Verversingssnelheid afstemmen',
			'settings.matchRefreshRateDescription' => 'Stem schermverversing af in volledig scherm',
			'settings.matchDynamicRange' => 'Dynamisch bereik afstemmen',
			'settings.matchDynamicRangeDescription' => 'Schakel HDR in voor HDR-content en daarna terug naar SDR',
			'settings.displaySwitchDelay' => 'Vertraging bij schermwisseling',
			'settings.tunneledPlayback' => 'Getunnelde weergave',
			'settings.tunneledPlaybackDescription' => 'Gebruik videotunneling. Schakel uit als HDR-afspelen zwart beeld geeft.',
			'settings.dvConversionMode' => 'Dolby Vision-conversie',
			'settings.dvConversionModeDescription' => 'Kies hoe ExoPlayer Dolby Vision Profile 7-bestanden verwerkt.',
			'settings.dvConversionAuto' => 'Auto',
			'settings.dvConversionNative' => 'Native / uitgeschakeld',
			'settings.dvConversionDv81' => 'P7 → P8.1',
			'settings.dvConversionHevcStrip' => 'P7 → HEVC',
			'settings.dvConversionAutoDescription' => 'Gebruik apparaatdetectie en normaal fallbackgedrag',
			'settings.dvConversionNativeDescription' => 'Forceer native DV7 en onderdruk DV-conversie opnieuw proberen',
			'settings.dvConversionDv81Description' => 'Forceer inline RPU-conversie naar Dolby Vision-profiel 8.1',
			'settings.dvConversionHevcStripDescription' => 'Strip Dolby Vision RPU/EL-lagen en presenteer gewone HEVC',
			'settings.requireProfileSelectionOnOpen' => 'Vraag om profiel bij openen',
			'settings.requireProfileSelectionOnOpenDescription' => 'Toon profielselectie telkens wanneer de app wordt geopend',
			'settings.forceTvMode' => 'TV-modus forceren',
			'settings.forceTvModeDescription' => 'Forceer TV-indeling. Voor apparaten zonder autodetectie. Herstart vereist.',
			'settings.startInFullscreen' => 'Starten in volledig scherm',
			'settings.startInFullscreenDescription' => 'Open Pleya bij het starten in volledig scherm',
			'settings.exitFullscreenOnPlayerClose' => 'Volledig scherm verlaten bij sluiten speler',
			'settings.exitFullscreenOnPlayerCloseDescription' => 'Verlaat automatisch volledig scherm wanneer de videospeler wordt gesloten',
			'settings.autoHidePerformanceOverlay' => 'Prestatie-overlay automatisch verbergen',
			'settings.autoHidePerformanceOverlayDescription' => 'Laat de prestatie-overlay meevervagen met de afspeelknoppen',
			'settings.showNavBarLabels' => 'Navigatiebalk labels tonen',
			'settings.showNavBarLabelsDescription' => 'Tekstlabels onder de pictogrammen van de navigatiebalk weergeven',
			'settings.startupSection' => 'Opstartsectie',
			'settings.startupSectionDescription' => 'Kies welke sectie Pleya opent bij het opstarten',
			'settings.liveTvDefaultFavorites' => 'Standaard favoriete zenders',
			'settings.liveTvDefaultFavoritesDescription' => 'Toon alleen favoriete zenders bij het openen van Live TV',
			'settings.display' => 'Weergave',
			'settings.homeScreen' => 'Startscherm',
			'settings.navigation' => 'Navigatie',
			'settings.window' => 'Venster',
			'settings.content' => 'Inhoud',
			'settings.player' => 'Speler',
			'settings.subtitlesAndConfig' => 'Ondertitels en configuratie',
			'settings.seekAndTiming' => 'Zoeken en timing',
			'settings.audio' => 'Audio',
			'settings.audioSyncOffsetDescription' => 'Verschuif audio ten opzichte van beeld voor elke titel',
			'settings.behavior' => 'Gedrag',
			'settings.personalizedRecommendations' => 'Persoonlijke aanbevelingen',
			'settings.personalizedRecommendationsDescription' => 'Leert je smaak op dit apparaat voor Aanbevolen voor jou en meer. Er verlaat niets je apparaat.',
			'search.hint' => 'Zoek films, series, muziek...',
			'search.tryDifferentTerm' => 'Probeer een andere zoekterm',
			'search.searchYourMedia' => 'Zoek in je media',
			'search.enterTitleActorOrKeyword' => 'Voer een titel, acteur of trefwoord in',
			'search.recentSearches' => 'Recent gezocht',
			'search.clearHistory' => 'Wissen',
			'search.filters.all' => 'Alles',
			'search.filters.movies' => 'Films',
			'search.filters.shows' => 'Series',
			'search.filters.episodes' => 'Afleveringen',
			'search.filters.people' => 'Personen',
			'search.filters.other' => 'Overig',
			'hotkeys.setShortcutFor' => ({required Object actionName}) => 'Stel sneltoets in voor ${actionName}',
			'hotkeys.clearShortcut' => 'Wis sneltoets',
			'hotkeys.noShortcutSet' => 'Geen sneltoets ingesteld',
			'hotkeys.currentShortcut' => 'Huidige sneltoets:',
			'hotkeys.actions.playPause' => 'Afspelen/Pauzeren',
			'hotkeys.actions.volumeUp' => 'Volume omhoog',
			'hotkeys.actions.volumeDown' => 'Volume omlaag',
			'hotkeys.actions.seekForward' => ({required Object seconds}) => 'Vooruitspoelen (${seconds}s)',
			'hotkeys.actions.seekBackward' => ({required Object seconds}) => 'Terugspoelen (${seconds}s)',
			'hotkeys.actions.fullscreenToggle' => 'Volledig scherm',
			'hotkeys.actions.muteToggle' => 'Dempen',
			'hotkeys.actions.subtitleToggle' => 'Ondertiteling',
			'hotkeys.actions.audioTrackNext' => 'Volgende audiotrack',
			'hotkeys.actions.subtitleTrackNext' => 'Volgende ondertiteltrack',
			'hotkeys.actions.chapterNext' => 'Volgend hoofdstuk',
			'hotkeys.actions.chapterPrevious' => 'Vorig hoofdstuk',
			'hotkeys.actions.episodeNext' => 'Volgende aflevering',
			'hotkeys.actions.episodePrevious' => 'Vorige aflevering',
			'hotkeys.actions.speedIncrease' => 'Snelheid verhogen',
			'hotkeys.actions.speedDecrease' => 'Snelheid verlagen',
			'hotkeys.actions.speedReset' => 'Snelheid resetten',
			'hotkeys.actions.zoomIn' => 'Inzoomen',
			'hotkeys.actions.zoomOut' => 'Uitzoomen',
			'hotkeys.actions.zoomReset' => 'Zoom resetten',
			'hotkeys.actions.subSeekNext' => 'Naar volgende ondertitel',
			'hotkeys.actions.subSeekPrev' => 'Naar vorige ondertitel',
			'hotkeys.actions.shaderToggle' => 'Shaders aan/uit',
			'hotkeys.actions.skipMarker' => 'Intro/aftiteling overslaan',
			'hotkeys.actions.screenshot' => 'Schermafbeelding maken',
			'fileInfo.title' => 'Bestand info',
			'fileInfo.video' => 'Video',
			'fileInfo.audio' => 'Audio',
			'fileInfo.file' => 'Bestand',
			'fileInfo.advanced' => 'Geavanceerd',
			'fileInfo.codec' => 'Codec',
			'fileInfo.resolution' => 'Resolutie',
			'fileInfo.bitrate' => 'Bitrate',
			'fileInfo.frameRate' => 'Frame rate',
			'fileInfo.aspectRatio' => 'Beeldverhouding',
			'fileInfo.profile' => 'Profiel',
			'fileInfo.bitDepth' => 'Bit diepte',
			'fileInfo.colorSpace' => 'Kleurruimte',
			'fileInfo.colorRange' => 'Kleurbereik',
			'fileInfo.colorPrimaries' => 'Kleurprimaires',
			'fileInfo.chromaSubsampling' => 'Chroma subsampling',
			'fileInfo.channels' => 'Kanalen',
			'fileInfo.subtitles' => 'Ondertitels',
			'fileInfo.overallBitrate' => 'Totale bitrate',
			'fileInfo.path' => 'Pad',
			'fileInfo.size' => 'Grootte',
			'fileInfo.container' => 'Container',
			'fileInfo.duration' => 'Duur',
			'fileInfo.optimizedForStreaming' => 'Geoptimaliseerd voor streaming',
			'fileInfo.has64bitOffsets' => '64-bit Offsets',
			'mediaMenu.markAsWatched' => 'Markeer als gekeken',
			'mediaMenu.markAsUnwatched' => 'Markeer als ongekeken',
			'mediaMenu.removeFromContinueWatching' => 'Verwijder uit Doorgaan met kijken',
			'mediaMenu.viewDetails' => 'Details bekijken',
			'mediaMenu.goToSeries' => 'Ga naar serie',
			'mediaMenu.shufflePlay' => 'Willekeurig afspelen',
			'mediaMenu.shuffleNotAvailableOffline' => 'Shuffle is offline niet beschikbaar',
			'mediaMenu.fileInfo' => 'Bestand info',
			'mediaMenu.deleteFromServer' => 'Verwijderen van server',
			'mediaMenu.confirmDelete' => 'Deze media en bestanden van je server verwijderen?',
			'mediaMenu.deleteMultipleWarning' => 'Dit omvat alle afleveringen en hun bestanden.',
			'mediaMenu.mediaDeletedSuccessfully' => 'Media-item succesvol verwijderd',
			'mediaMenu.mediaFailedToDelete' => 'Verwijderen van media-item mislukt',
			'mediaMenu.rate' => 'Beoordelen',
			'mediaMenu.playFromBeginning' => 'Afspelen vanaf het begin',
			'mediaMenu.playVersion' => 'Versie afspelen...',
			'rateSheet.title' => 'Beoordelen',
			'rateSheet.server' => 'Server',
			'rateSheet.starValue' => ({required Object rating}) => '${rating} / 5',
			'rateSheet.scoreValue' => ({required Object score}) => '${score} / 10',
			'rateSheet.setScore' => 'Score instellen',
			'rateSheet.notRated' => 'Niet beoordeeld',
			'rateSheet.liked' => 'Geliket',
			'rateSheet.notLiked' => 'Niet geliket',
			'rateSheet.saved' => 'Opgeslagen',
			'rateSheet.notAvailable' => 'Geen match gevonden',
			'rateSheet.noConnectedTrackers' => 'Verbind een tracker in Instellingen om daar te beoordelen.',
			'accessibility.mediaCardMovie' => ({required Object title}) => '${title}, film',
			'accessibility.mediaCardShow' => ({required Object title}) => '${title}, TV-serie',
			'accessibility.mediaCardEpisode' => ({required Object title, required Object episodeInfo}) => '${title}, ${episodeInfo}',
			'accessibility.mediaCardSeason' => ({required Object title, required Object seasonInfo}) => '${title}, ${seasonInfo}',
			'accessibility.mediaCardWatched' => 'bekeken',
			'accessibility.mediaCardPartiallyWatched' => ({required Object percent}) => '${percent} procent bekeken',
			'accessibility.mediaCardUnwatched' => 'niet bekeken',
			'accessibility.tapToPlay' => 'Tik om af te spelen',
			'tooltips.shufflePlay' => 'Willekeurig afspelen',
			'tooltips.playTrailer' => 'Trailer afspelen',
			'tooltips.markAsWatched' => 'Markeer als gekeken',
			'tooltips.markAsUnwatched' => 'Markeer als ongekeken',
			'videoControls.audioLabel' => 'Audio',
			'videoControls.subtitlesLabel' => 'Ondertitels',
			'videoControls.resetToZero' => 'Reset naar 0ms',
			'videoControls.addTime' => ({required Object amount, required Object unit}) => '+${amount}${unit}',
			'videoControls.minusTime' => ({required Object amount, required Object unit}) => '-${amount}${unit}',
			'videoControls.playsLater' => ({required Object label}) => '${label} speelt later af',
			'videoControls.playsEarlier' => ({required Object label}) => '${label} speelt eerder af',
			'videoControls.noOffset' => 'Geen offset',
			'videoControls.letterbox' => 'Letterbox',
			'videoControls.fillScreen' => 'Vul scherm',
			'videoControls.stretch' => 'Uitrekken',
			'videoControls.lockRotation' => 'Vergrendel rotatie',
			'videoControls.unlockRotation' => 'Ontgrendel rotatie',
			'videoControls.timerActive' => 'Timer actief',
			'videoControls.playbackWillPauseIn' => ({required Object duration}) => 'Afspelen wordt gepauzeerd over ${duration}',
			'videoControls.sleepTimerEndOfVideo' => 'Einde van huidige video',
			'videoControls.sleepTimerStopAtHeader' => 'Stoppen bij',
			'videoControls.sleepTimerDurationHeader' => 'Timer',
			'videoControls.playbackWillPauseAtEnd' => 'Afspelen wordt gepauzeerd aan het einde van deze video',
			'videoControls.stillWatching' => 'Kijk je nog?',
			'videoControls.pausingIn' => ({required Object seconds}) => 'Pauze over ${seconds}s',
			'videoControls.continueWatching' => 'Doorgaan',
			'videoControls.autoPlayNext' => 'Automatisch volgende afspelen',
			'videoControls.playNext' => 'Volgende afspelen',
			'videoControls.playButton' => 'Afspelen',
			'videoControls.pauseButton' => 'Pauzeren',
			'videoControls.seekBackwardButton' => ({required Object seconds}) => 'Terugspoelen ${seconds} seconden',
			'videoControls.seekForwardButton' => ({required Object seconds}) => 'Vooruitspoelen ${seconds} seconden',
			'videoControls.previousButton' => 'Vorige aflevering',
			'videoControls.nextButton' => 'Volgende aflevering',
			'videoControls.previousChapterButton' => 'Vorig hoofdstuk',
			'videoControls.nextChapterButton' => 'Volgend hoofdstuk',
			'videoControls.muteButton' => 'Dempen',
			'videoControls.unmuteButton' => 'Dempen opheffen',
			'videoControls.settingsButton' => 'Afspeelinstellingen',
			'videoControls.tracksButton' => 'Audio en ondertitels',
			'videoControls.chaptersButton' => 'Hoofdstukken',
			'videoControls.versionsButton' => 'Videoversies',
			'videoControls.versionQualityButton' => 'Versie en kwaliteit',
			'videoControls.versionColumnHeader' => 'Versie',
			'videoControls.qualityColumnHeader' => 'Kwaliteit',
			'videoControls.qualityOriginal' => 'Origineel',
			'videoControls.qualityPresetLabel' => ({required Object resolution, required Object bitrate}) => '${resolution}p ${bitrate} Mbps',
			'videoControls.qualityBandwidthEstimate' => ({required Object bitrate}) => '~${bitrate} Mbps',
			'videoControls.transcodeUnavailableFallback' => 'Transcoderen niet beschikbaar — originele kwaliteit wordt afgespeeld',
			'videoControls.pipButton' => 'Beeld-in-beeld modus',
			'videoControls.aspectRatioButton' => 'Beeldverhouding',
			'videoControls.ambientLighting' => 'Omgevingsverlichting',
			'videoControls.ambientIntensitySubtle' => 'Subtiel',
			'videoControls.ambientIntensityBalanced' => 'Evenwichtig',
			'videoControls.ambientIntensityBright' => 'Fel',
			'videoControls.tvPanel.information' => 'Informatie',
			'videoControls.tvPanel.audio' => 'Geluid',
			'videoControls.tvPanel.tracks' => 'Sporen',
			'videoControls.tvPanel.options' => 'Opties',
			'videoControls.tvPanel.more' => 'Meer…',
			'videoControls.fullscreenButton' => 'Volledig scherm activeren',
			'videoControls.exitFullscreenButton' => 'Volledig scherm verlaten',
			'videoControls.alwaysOnTopButton' => 'Altijd bovenop',
			'videoControls.rotationLockButton' => 'Rotatievergrendeling',
			'videoControls.lockScreen' => 'Vergrendel scherm',
			'videoControls.screenLockButton' => 'Schermvergrendeling',
			'videoControls.longPressToUnlock' => 'Lang indrukken om te ontgrendelen',
			'videoControls.timelineSlider' => 'Videotijdlijn',
			'videoControls.volumeSlider' => 'Volumeniveau',
			'videoControls.volumeHandledByDevice' => 'Volume wordt tijdens doorvoer door je audioapparaat geregeld',
			'videoControls.endsAt' => ({required Object time}) => 'Eindigt om ${time}',
			'videoControls.pipActive' => 'Afspelen in beeld-in-beeld',
			'videoControls.pipFailed' => 'Beeld-in-beeld kon niet worden gestart',
			'videoControls.screenshotSaved' => 'Schermafbeelding opgeslagen',
			'videoControls.zoomPercent' => ({required Object percent}) => 'Zoom ${percent}%',
			'videoControls.pipErrors.androidVersion' => 'Vereist Android 8.0 of nieuwer',
			'videoControls.pipErrors.iosVersion' => 'Vereist iOS 15.0 of nieuwer',
			'videoControls.pipErrors.permissionDisabled' => 'Picture-in-picture is uitgeschakeld. Schakel het in via systeeminstellingen.',
			'videoControls.pipErrors.notSupported' => 'Dit apparaat ondersteunt geen beeld-in-beeld modus',
			'videoControls.pipErrors.voSwitchFailed' => 'Kan video-uitvoer niet wisselen voor beeld-in-beeld',
			'videoControls.pipErrors.failed' => 'Beeld-in-beeld kon niet worden gestart',
			'videoControls.pipErrors.unknown' => 'Er is een fout opgetreden',
			'videoControls.chapters' => 'Hoofdstukken',
			'videoControls.noChaptersAvailable' => 'Geen hoofdstukken beschikbaar',
			'videoControls.queue' => 'Wachtrij',
			'videoControls.noQueueItems' => 'Geen items in de wachtrij',
			'videoControls.searchSubtitles' => 'Ondertitels zoeken',
			'videoControls.language' => 'Taal',
			'videoControls.noSubtitlesFound' => 'Geen ondertitels gevonden',
			'videoControls.downloadedSubtitle' => 'Gedownload',
			'videoControls.noSubtitlesAvailable' => 'Geen ondertitels beschikbaar',
			'videoControls.noAudioTracksAvailable' => 'Geen audiotracks beschikbaar',
			'videoControls.noTracksAvailable' => 'Geen tracks beschikbaar',
			'videoControls.subtitleDownloaded' => 'Ondertitel gedownload',
			'videoControls.subtitleDownloadFailed' => 'Ondertitel downloaden mislukt',
			'videoControls.searchLanguages' => 'Talen zoeken...',
			'videoControls.airplayButton' => 'AirPlay',
			'userStatus.admin' => 'Beheerder',
			'userStatus.restricted' => 'Beperkt',
			_ => null,
		} ?? switch (path) {
			'userStatus.protected' => 'Beschermd',
			'userStatus.current' => 'HUIDIG',
			'messages.markedAsWatched' => 'Gemarkeerd als gekeken',
			'messages.markedAsUnwatched' => 'Gemarkeerd als ongekeken',
			'messages.markedAsWatchedOffline' => 'Gemarkeerd als gekeken (sync wanneer online)',
			'messages.markedAsUnwatchedOffline' => 'Gemarkeerd als ongekeken (sync wanneer online)',
			'messages.autoRemovedWatchedDownload' => ({required Object title}) => 'Automatisch verwijderd: ${title}',
			'messages.removedFromContinueWatching' => 'Verwijderd uit Doorgaan met kijken',
			'messages.errorLoading' => 'Fout',
			'messages.fileInfoNotAvailable' => 'Bestand informatie niet beschikbaar',
			'messages.errorLoadingFileInfo' => 'Fout bij laden bestand info',
			'messages.errorLoadingSeries' => 'Fout bij laden serie',
			'messages.musicNotSupported' => 'Muziek afspelen wordt nog niet ondersteund',
			'messages.noDescriptionAvailable' => 'Geen beschrijving beschikbaar',
			'messages.noProfilesAvailable' => 'Geen profielen beschikbaar',
			'messages.contactAdminForProfiles' => 'Neem contact op met je serverbeheerder om profielen toe te voegen',
			'messages.unableToDetermineLibrarySection' => 'Kan bibliotheeksectie voor dit item niet bepalen',
			'messages.logsCleared' => 'Logs gewist',
			'messages.logsCopied' => 'Logs gekopieerd naar klembord',
			'messages.noLogsAvailable' => 'Geen logs beschikbaar',
			'messages.libraryScanning' => ({required Object title}) => 'Scannen "${title}"...',
			'messages.libraryScanStarted' => ({required Object title}) => 'Bibliotheek scan gestart voor "${title}"',
			'messages.libraryScanFailed' => 'Kon bibliotheek niet scannen',
			'messages.metadataRefreshing' => ({required Object title}) => 'Metadata vernieuwen voor "${title}"...',
			'messages.metadataRefreshStarted' => ({required Object title}) => 'Metadata vernieuwen gestart voor "${title}"',
			'messages.metadataRefreshFailed' => 'Kon metadata niet vernieuwen',
			'messages.logoutConfirm' => 'Weet je zeker dat je wilt uitloggen?',
			'messages.noSeasonsFound' => 'Geen seizoenen gevonden',
			'messages.seasonsLoadFailed' => 'Kan seizoenen niet laden',
			'messages.noEpisodesFound' => 'Geen afleveringen gevonden in eerste seizoen',
			'messages.noEpisodesFoundGeneral' => 'Geen afleveringen gevonden',
			'messages.episodesLoadFailed' => 'Kan afleveringen niet laden',
			'messages.noResultsFound' => 'Geen resultaten gevonden',
			'messages.sleepTimerSet' => ({required Object label}) => 'Slaap timer ingesteld voor ${label}',
			'messages.noItemsAvailable' => 'Geen items beschikbaar',
			'messages.failedToCreatePlayQueueNoItems' => 'Kan afspeelwachtrij niet maken - geen items',
			'messages.failedPlayback' => ({required Object action}) => 'Afspelen van ${action} mislukt',
			'messages.switchingToCompatiblePlayer' => 'Overschakelen naar compatibele speler...',
			'messages.serverLimitTitle' => 'Afspelen mislukt',
			'messages.serverLimitBody' => 'Serverfout (HTTP 500). Waarschijnlijk weigerde een bandbreedte-/transcodeerlimiet deze sessie. Vraag de eigenaar dit aan te passen.',
			'messages.logsUploaded' => 'Logs geüpload',
			'messages.logsUploadFailed' => 'Uploaden van logs mislukt',
			'messages.logId' => 'Log-ID',
			'messages.dvdNotSupported' => 'Dvd-schijven worden op dit apparaat niet ondersteund.',
			'messages.discNotSupported' => 'Dit schijfformaat wordt op dit apparaat niet ondersteund.',
			'subtitlingStyling.text' => 'Tekst',
			'subtitlingStyling.border' => 'Rand',
			'subtitlingStyling.background' => 'Achtergrond',
			'subtitlingStyling.fontSize' => 'Lettergrootte',
			'subtitlingStyling.textColor' => 'Tekstkleur',
			'subtitlingStyling.borderSize' => 'Rand grootte',
			'subtitlingStyling.borderColor' => 'Randkleur',
			'subtitlingStyling.backgroundOpacity' => 'Achtergrond transparantie',
			'subtitlingStyling.backgroundColor' => 'Achtergrondkleur',
			'subtitlingStyling.position' => 'Positie',
			'subtitlingStyling.assOverride' => 'ASS-overschrijving',
			'subtitlingStyling.bold' => 'Vet',
			'subtitlingStyling.italic' => 'Cursief',
			'subtitlingStyling.renderResolution' => 'Renderresolutie',
			'subtitlingStyling.renderResolutionScreen' => 'Schermresolutie',
			'subtitlingStyling.renderResolutionVideo' => 'Videoresolutie',
			'mpvConfig.title' => 'mpv-configuratie',
			'mpvConfig.description' => 'Geavanceerde videospeler-instellingen',
			'mpvConfig.presets' => 'Voorinstellingen',
			'mpvConfig.noPresets' => 'Geen opgeslagen voorinstellingen',
			'mpvConfig.saveAsPreset' => 'Opslaan als voorinstelling...',
			'mpvConfig.presetName' => 'Naam voorinstelling',
			'mpvConfig.presetNameHint' => 'Voer een naam in voor deze voorinstelling',
			'mpvConfig.loadPreset' => 'Laden',
			'mpvConfig.deletePreset' => 'Verwijderen',
			'mpvConfig.presetSaved' => 'Voorinstelling opgeslagen',
			'mpvConfig.presetLoaded' => 'Voorinstelling geladen',
			'mpvConfig.presetDeleted' => 'Voorinstelling verwijderd',
			'mpvConfig.confirmDeletePreset' => 'Weet je zeker dat je deze voorinstelling wilt verwijderen?',
			'mpvConfig.configPlaceholder' => 'gpu-api=vulkan\nhwdec=auto\n# comment',
			'dialog.confirmAction' => 'Bevestig actie',
			'profiles.addPleyaProfile' => 'Pleya-profiel toevoegen',
			'profiles.switchingProfile' => 'Profiel wisselen…',
			'profiles.deleteThisProfileTitle' => 'Dit profiel verwijderen?',
			'profiles.deleteThisProfileMessage' => ({required Object displayName}) => 'Verwijder ${displayName}. Verbindingen blijven ongewijzigd.',
			'profiles.active' => 'Actief',
			'profiles.manage' => 'Beheren',
			'profiles.delete' => 'Verwijderen',
			'profiles.signOut' => 'Afmelden',
			'profiles.signOutPlexTitle' => 'Afmelden bij Plex?',
			'profiles.signOutPlexMessage' => ({required Object displayName}) => '${displayName} en alle Plex Home-gebruikers verwijderen? Je kunt altijd opnieuw inloggen.',
			'profiles.signedOutPlex' => 'Afgemeld bij Plex.',
			'profiles.signOutFailed' => 'Afmelden mislukt.',
			'profiles.sectionTitle' => 'Profielen',
			'profiles.summarySingle' => 'Voeg profielen toe om beheerde gebruikers en lokale identiteiten te combineren',
			'profiles.summaryMultipleWithActive' => ({required Object count, required Object activeName}) => '${count} profielen · actief: ${activeName}',
			'profiles.summaryMultiple' => ({required Object count}) => '${count} profielen',
			'profiles.removeConnectionTitle' => 'Verbinding verwijderen?',
			'profiles.removeConnectionMessage' => ({required Object displayName, required Object connectionLabel}) => 'Verwijder ${displayName}s toegang tot ${connectionLabel}. Andere profielen behouden die.',
			'profiles.deleteProfileTitle' => 'Profiel verwijderen?',
			'profiles.deleteProfileMessage' => ({required Object displayName}) => 'Verwijder ${displayName} en de verbindingen. Servers blijven beschikbaar.',
			'profiles.profileNameLabel' => 'Profielnaam',
			'profiles.pinProtectionLabel' => 'PIN-beveiliging',
			'profiles.pinManagedByPlex' => 'PIN wordt beheerd door Plex. Bewerk op plex.tv.',
			'profiles.noPinSetEditOnPlex' => 'Geen PIN ingesteld. Bewerk de Home-gebruiker op plex.tv om er één te vereisen.',
			'profiles.setPin' => 'PIN instellen',
			'profiles.setPinTitle' => 'PIN instellen',
			'profiles.confirmPinTitle' => 'PIN bevestigen',
			'profiles.pinSet' => 'PIN ingesteld',
			'profiles.changePin' => 'Wijzigen',
			'profiles.removePin' => 'Verwijderen',
			'profiles.connectionsLabel' => 'Verbindingen',
			'profiles.add' => 'Toevoegen',
			'profiles.deleteProfileButton' => 'Profiel verwijderen',
			'profiles.noConnectionsHint' => 'Geen verbindingen — voeg er één toe om dit profiel te gebruiken.',
			'profiles.noConnections' => 'Geen verbindingen',
			'profiles.plexHomeAccount' => 'Plex Home-account',
			'profiles.connectionDefault' => 'Standaard',
			'profiles.connectionAs' => ({required Object displayName}) => 'als ${displayName}',
			'profiles.makeDefault' => 'Als standaard instellen',
			'profiles.removeConnection' => 'Verwijderen',
			'profiles.profileRenamed' => 'Profiel hernoemd.',
			'profiles.borrowAddTo' => ({required Object displayName}) => 'Toevoegen aan ${displayName}',
			'profiles.borrowExplain' => 'Leen de verbinding van een ander profiel. PIN-beveiligde profielen vereisen een PIN.',
			'profiles.borrowEmpty' => 'Nog niets te lenen.',
			'profiles.borrowEmptySubtitle' => 'Verbind Plex of Jellyfin eerst met een ander profiel.',
			'profiles.borrowFromProfile' => ({required Object displayName}) => 'Van ${displayName}',
			'profiles.borrowConnectionBorrowed' => 'Verbinding geleend.',
			'profiles.borrowFailed' => 'Kan verbinding niet lenen.',
			'profiles.incorrectPin' => 'Onjuiste PIN.',
			'profiles.sourceProfileMissingParentAccount' => 'Het bronprofiel mist het bovenliggende account.',
			'profiles.failedToVerifyPin' => 'Kan PIN niet verifiëren.',
			'profiles.newProfile' => 'Nieuw profiel',
			'profiles.profileNameHint' => 'bijv. Gasten, Kinderen, Woonkamer',
			'profiles.pinProtectionOptional' => 'PIN-beveiliging (optioneel)',
			'profiles.pinExplain' => '4-cijferige PIN vereist om profielen te wisselen.',
			'profiles.continueButton' => 'Doorgaan',
			'profiles.pinsDontMatch' => 'PIN-codes komen niet overeen',
			'profiles.initializeServicesFailed' => 'Kan profielservices niet initialiseren',
			'connections.sectionTitle' => 'Verbindingen',
			'connections.addConnection' => 'Verbinding toevoegen',
			'connections.addConnectionSubtitleNoProfile' => 'Meld je aan met Plex of verbind een Jellyfin-server',
			'connections.addConnectionSubtitleScoped' => ({required Object displayName}) => 'Toevoegen aan ${displayName}: Plex, Jellyfin of een andere profielverbinding',
			'connections.sessionExpiredOne' => ({required Object name}) => 'Sessie verlopen voor ${name}',
			'connections.sessionExpiredMany' => ({required Object count}) => 'Sessie verlopen voor ${count} servers',
			'connections.signInAgain' => 'Opnieuw aanmelden',
			'connections.editJellyfinTitle' => 'Jellyfin-verbinding bewerken',
			'connections.editJellyfinIntro' => ({required Object serverName}) => 'Voeg URL\'s voor ${serverName} toe of verwijder ze. Pleya gebruikt de bereikbare URL met de laagste latentie.',
			'connections.localSources' => 'Bronnen op dit apparaat',
			'connections.removeSource' => 'Bron verwijderen',
			'connections.removeSourceConfirm' => ({required Object name}) => '"${name}" verwijderen van dit apparaat? Gedownloade items blijven staan.',
			'connections.pleyaServers' => 'Pleya Servers',
			'connections.disconnectServer' => 'Verbinding verbreken',
			'connections.disconnectServerConfirm' => ({required Object name}) => 'Verbinding met "${name}" verbreken? De aanmelding voor deze server wordt van dit apparaat verwijderd. Gedownloade items blijven staan.',
			'connections.reauthRequired' => 'Opnieuw aanmelden vereist',
			'discover.title' => 'Ontdekken',
			'discover.switchProfile' => 'Wissel van profiel',
			'discover.noContentAvailable' => 'Geen inhoud beschikbaar',
			'discover.addMediaToLibraries' => 'Voeg wat media toe aan je bibliotheken',
			'discover.continueWatching' => 'Verder kijken',
			'discover.continueWatchingIn' => ({required Object library}) => 'Verder kijken in ${library}',
			'discover.nextUp' => 'Volgende',
			'discover.nextUpIn' => ({required Object library}) => 'Volgende in ${library}',
			'discover.recentlyAdded' => 'Recent toegevoegd',
			'discover.recentlyReleased' => 'Recent uitgebracht',
			'discover.recentlyAddedIn' => ({required Object library}) => 'Recent toegevoegd in ${library}',
			'discover.playEpisode' => ({required Object season, required Object episode}) => 'S${season}E${episode}',
			'discover.overview' => 'Overzicht',
			'discover.cast' => 'Acteurs',
			'discover.extras' => 'Trailers & Extra\'s',
			'discover.studio' => 'Studio',
			'discover.rating' => 'Leeftijd',
			'discover.movie' => 'Film',
			'discover.tvShow' => 'TV Serie',
			'discover.minutesLeft' => ({required Object minutes}) => '${minutes} min over',
			'discover.moreLikeThis' => 'Meer zoals dit',
			'discover.becauseYouWatched' => ({required Object title}) => 'Omdat je ${title} gekeken hebt',
			'discover.topRated' => 'Hoogst gewaardeerd',
			'discover.somethingDifferent' => 'Eens iets anders',
			'discover.topPicksForYou' => 'Aanbevolen voor jou',
			'discover.becauseYouLike' => ({required Object genre}) => 'Omdat je van ${genre} houdt',
			'discover.hiddenGems' => 'Verborgen parels',
			'discover.watchedBy' => ({required Object names}) => 'Bekeken door ${names}',
			'discover.watchedByYou' => 'Jij',
			'discover.watchedByAnd' => 'en',
			'discover.watchedByOthers' => ({required Object count}) => '${count} anderen',
			'discover.statsPlays' => ({required Object count}) => '${count} keer afgespeeld',
			'discover.statsViewers' => ({required Object count}) => 'door ${count} mensen',
			'discover.statsWatchTime' => ({required Object duration}) => '${duration} bekeken',
			'discover.statsRecent' => ({required Object count}) => '${count} in de laatste 30 dagen',
			'discover.watchingSeriesBy' => ({required Object names}) => 'Kijken deze serie: ${names}',
			'errors.searchFailed' => 'Zoeken mislukt',
			'errors.connectionTimeout' => ({required Object context}) => 'Verbinding time-out tijdens laden ${context}',
			'errors.connectionFailed' => 'Kan geen verbinding maken met mediaserver',
			'errors.failedToLoad' => ({required Object context}) => 'Kon ${context} niet laden',
			'errors.noClientAvailable' => 'Geen client beschikbaar',
			'errors.authenticationFailed' => 'Authenticatie mislukt',
			'errors.couldNotLaunchUrl' => 'Kon auth URL niet openen',
			'errors.pleaseEnterToken' => 'Voer een token in',
			'errors.invalidToken' => 'Ongeldig token',
			'errors.failedToVerifyToken' => 'Kon token niet verifiëren',
			'errors.failedToSwitchProfile' => ({required Object displayName}) => 'Kon niet wisselen naar ${displayName}',
			'errors.failedToDeleteProfile' => ({required Object displayName}) => 'Kon ${displayName} niet verwijderen',
			'errors.failedToRate' => 'Beoordeling kon niet worden bijgewerkt',
			'errors.somethingWentWrongTryAgain' => 'Er ging iets mis. Probeer het opnieuw.',
			'errors.couldNotLoad' => ({required Object context}) => 'Kon ${context} niet laden. Probeer het opnieuw.',
			'notices.connectionTimeoutTitle' => 'Verbinding verlopen',
			'notices.connectionTimeoutBody' => ({required Object context}) => '${context} reageerde niet op tijd',
			'notices.connectionFailedTitle' => 'Kan niet verbinden',
			'notices.connectionFailedBody' => ({required Object serverName}) => '${serverName} reageert niet',
			'notices.couldNotLoadTitle' => ({required Object context}) => 'Kon ${context} niet laden',
			'notices.genericErrorTitle' => 'Er ging iets mis',
			'notices.authFailedTitle' => 'Aanmelden mislukt',
			'notices.playbackStoppedTitle' => 'Afspelen gestopt',
			'notices.playbackFileUnavailableTitle' => 'Bestand niet beschikbaar',
			'notices.playbackFileUnavailableBody' => 'De server kan niet bij het videobestand. Kijk of de schijf of map waar het op staat nog aangesloten is.',
			'notices.playbackSegmentUnavailableBody' => 'Dit deel van de video is nu niet beschikbaar',
			'notices.playbackConnectionLostBody' => 'Verbinding met de server verloren',
			'notices.playbackCodecUnsupportedBody' => 'Dit bestandsformaat wordt niet ondersteund op dit toestel',
			'notices.playbackServerErrorBody' => 'De server liep vast tijdens het transcoderen',
			'libraries.title' => 'Bibliotheken',
			'libraries.fallbackTitle' => 'Bibliotheek',
			'libraries.scanLibraryFiles' => 'Scan bibliotheek bestanden',
			'libraries.scanLibrary' => 'Scan bibliotheek',
			'libraries.analyze' => 'Analyseren',
			'libraries.analyzeLibrary' => 'Analyseer bibliotheek',
			'libraries.refreshMetadata' => 'Vernieuw metadata',
			'libraries.emptyTrash' => 'Prullenbak legen',
			'libraries.emptyingTrash' => ({required Object title}) => 'Prullenbak legen voor "${title}"...',
			'libraries.trashEmptied' => ({required Object title}) => 'Prullenbak geleegd voor "${title}"',
			'libraries.failedToEmptyTrash' => 'Kon prullenbak niet legen',
			'libraries.analyzing' => ({required Object title}) => 'Analyseren "${title}"...',
			'libraries.analysisStarted' => ({required Object title}) => 'Analyse gestart voor "${title}"',
			'libraries.failedToAnalyze' => 'Kon bibliotheek niet analyseren',
			'libraries.noLibrariesFound' => 'Geen bibliotheken gevonden',
			'libraries.allLibrariesHidden' => 'Alle bibliotheken zijn verborgen',
			'libraries.hiddenLibrariesCount' => ({required Object count}) => 'Verborgen bibliotheken (${count})',
			'libraries.thisLibraryIsEmpty' => 'Deze bibliotheek is leeg',
			'libraries.all' => 'Alles',
			'libraries.clearAll' => 'Alles wissen',
			'libraries.scanLibraryConfirm' => ({required Object title}) => 'Weet je zeker dat je "${title}" wilt scannen?',
			'libraries.analyzeLibraryConfirm' => ({required Object title}) => 'Weet je zeker dat je "${title}" wilt analyseren?',
			'libraries.refreshMetadataConfirm' => ({required Object title}) => 'Weet je zeker dat je metadata wilt vernieuwen voor "${title}"?',
			'libraries.emptyTrashConfirm' => ({required Object title}) => 'Weet je zeker dat je de prullenbak wilt legen voor "${title}"?',
			'libraries.manageLibraries' => 'Beheer bibliotheken',
			'libraries.sort' => 'Sorteren',
			'libraries.sortBy' => 'Sorteer op',
			'libraries.filters' => 'Filters',
			'libraries.confirmActionMessage' => 'Weet je zeker dat je deze actie wilt uitvoeren?',
			'libraries.showLibrary' => 'Toon bibliotheek',
			'libraries.hideLibrary' => 'Verberg bibliotheek',
			'libraries.libraryOptions' => 'Bibliotheek opties',
			'libraries.content' => 'bibliotheekinhoud',
			'libraries.selectLibrary' => 'Bibliotheek kiezen',
			'libraries.filtersWithCount' => ({required Object count}) => 'Filters (${count})',
			'libraries.noRecommendations' => 'Geen aanbevelingen beschikbaar',
			'libraries.noCollections' => 'Geen collecties in deze bibliotheek',
			'libraries.noFoldersFound' => 'Geen mappen gevonden',
			'libraries.folders' => 'mappen',
			'libraries.tabs.recommended' => 'Aanbevolen',
			'libraries.tabs.browse' => 'Bladeren',
			'libraries.tabs.collections' => 'Collecties',
			'libraries.tabs.playlists' => 'Afspeellijsten',
			'libraries.groupings.title' => 'Groepering',
			'libraries.groupings.all' => 'Alles',
			'libraries.groupings.movies' => 'Films',
			'libraries.groupings.shows' => 'Series',
			'libraries.groupings.seasons' => 'Seizoenen',
			'libraries.groupings.episodes' => 'Afleveringen',
			'libraries.groupings.folders' => 'Mappen',
			'libraries.filterCategories.genre' => 'Genre',
			'libraries.filterCategories.year' => 'Jaar',
			'libraries.filterCategories.contentRating' => 'Leeftijdsclassificatie',
			'libraries.filterCategories.tag' => 'Tag',
			'libraries.filterCategories.unwatched' => 'Onbekeken',
			'libraries.sortLabels.title' => 'Titel',
			'libraries.sortLabels.dateAdded' => 'Toegevoegd op',
			'libraries.sortLabels.releaseDate' => 'Uitgavedatum',
			'libraries.sortLabels.rating' => 'Beoordeling',
			'libraries.sortLabels.communityRating' => 'Communitybeoordeling',
			'libraries.sortLabels.criticRating' => 'Criticusbeoordeling',
			'libraries.sortLabels.userRating' => 'Gebruikersbeoordeling',
			'libraries.sortLabels.lastPlayed' => 'Laatst afgespeeld',
			'libraries.sortLabels.datePlayed' => 'Afspeeldatum',
			'libraries.sortLabels.playCount' => 'Aantal afspelingen',
			'libraries.sortLabels.productionYear' => 'Productiejaar',
			'libraries.sortLabels.runtime' => 'Speelduur',
			'libraries.sortLabels.officialRating' => 'Officiële beoordeling',
			'libraries.sortLabels.premiereDate' => 'Premièredatum',
			'libraries.sortLabels.startDate' => 'Begindatum',
			'libraries.sortLabels.airTime' => 'Uitzendtijd',
			'libraries.sortLabels.studio' => 'Studio',
			'libraries.sortLabels.random' => 'Willekeurig',
			'libraries.sortLabels.dateShared' => 'Gedeeld op',
			'libraries.sortLabels.latestEpisodeAirDate' => 'Laatste afleveringsuitzending',
			'libraries.sortLabels.lastEpisodeDateAdded' => 'Datum laatst toegevoegde aflevering',
			'about.title' => 'Over',
			'about.openSourceLicenses' => 'Open Source licenties',
			'about.versionLabel' => ({required Object version}) => 'Versie ${version}',
			'about.appDescription' => 'Een mooie Plex- en Jellyfin-client voor Flutter',
			'about.viewLicensesDescription' => 'Bekijk licenties van third-party bibliotheken',
			'about.sourceCode' => 'Broncode',
			'about.sourceCodeDescription' => 'Bijbehorende broncode van deze build (GPL-3.0)',
			'about.basedOnPlezy' => 'Gebaseerd op Plezy',
			'about.upstreamProject' => 'Upstream-project',
			'about.privacyPolicy' => 'Privacybeleid',
			'serverSelection.allServerConnectionsFailed' => 'Kon met geen enkele server verbinden. Controleer je netwerk.',
			'serverSelection.noServersFoundForAccount' => ({required Object username, required Object email}) => 'Geen servers gevonden voor ${username} (${email})',
			'serverSelection.noServersFoundTitle' => 'Geen mediaservers gevonden',
			'serverSelection.noServersFoundDescription' => 'Je Plex-account heeft nog geen toegang tot servers. Vraag de server-eigenaar om zijn bibliotheek met je te delen, of verbind in plaats daarvan een Jellyfin-server.',
			'serverSelection.noServersFoundTryJellyfin' => 'Verbind een Jellyfin-server',
			'serverSelection.noServersFoundRetryPlex' => 'Probeer een ander Plex-account',
			'serverSelection.failedToLoadServers' => 'Kon servers niet laden',
			'serverSelection.failedToLoadServersDescription' => 'Er ging iets mis bij het laden van je servers. Controleer je internetverbinding en probeer opnieuw.',
			'serverSelection.networkErrorTitle' => 'Kan de server niet bereiken',
			'serverSelection.networkErrorDescription' => 'Pleya kon geen verbinding maken met internet. Controleer je netwerk en probeer opnieuw.',
			'hubDetail.title' => 'Titel',
			'hubDetail.releaseYear' => 'Uitgavejaar',
			'hubDetail.dateAdded' => 'Datum toegevoegd',
			'hubDetail.rating' => 'Beoordeling',
			'hubDetail.noItemsFound' => 'Geen items gevonden',
			'logs.clearLogs' => 'Wis logs',
			'logs.copyLogs' => 'Kopieer logs',
			'logs.uploadLogs' => 'Logs uploaden',
			'licenses.relatedPackages' => 'Gerelateerde pakketten',
			'licenses.license' => 'Licentie',
			'licenses.licenseNumber' => ({required Object number}) => 'Licentie ${number}',
			'licenses.licensesCount' => ({required Object count}) => '${count} licenties',
			'navigation.libraries' => 'Media',
			'navigation.downloads' => 'Downloads',
			'navigation.liveTv' => 'Live TV',
			'navigation.watchlist' => 'Kijklijst',
			'navigation.myPleya' => 'Mijn Pleya',
			'watchlist.title' => 'Kijklijst',
			'watchlist.seeAll' => 'Alles bekijken',
			'watchlist.empty' => 'Nog niets op je kijklijst',
			'watchlist.emptyBody' => 'Titels die je in Plex toevoegt of als Jellyfin-favoriet markeert, verschijnen hier.',
			'watchlist.emptyFiltered' => 'Geen titels binnen dit filter',
			'watchlist.retry' => 'Opnieuw proberen',
			'watchlist.notAvailable' => 'Niet beschikbaar',
			'watchlist.checking' => 'Controleren',
			'watchlist.notFoundOnServers' => 'Niet gevonden op je gekoppelde mediaservers',
			'watchlist.coverageIncomplete' => 'Een deel van je mediaservers was niet bereikbaar. Deze titel staat er misschien al.',
			'watchlist.remove' => 'Uit kijklijst verwijderen',
			'watchlist.add' => 'Aan kijklijst toevoegen',
			'watchlist.added' => 'Toegevoegd aan kijklijst',
			'watchlist.removed' => 'Verwijderd uit kijklijst',
			'watchlist.addFailed' => 'Kon je kijklijst niet bijwerken',
			'watchlist.partiallyFailed' => 'Alleen uit een deel van de lijsten verwijderd. Je kijklijst is opnieuw geladen.',
			'watchlist.offlineRejected' => 'Je hebt verbinding nodig om je kijklijst te wijzigen',
			'watchlist.filterAll' => 'Alles',
			'watchlist.filterMovies' => 'Films',
			'watchlist.filterShows' => 'Series',
			'watchlist.filterAvailable' => 'Beschikbaar',
			'watchlist.sortRecentlyAdded' => 'Recent toegevoegd',
			'watchlist.sortTitle' => 'Titel',
			'watchlist.sortYear' => 'Jaar',
			'myPleya.title' => 'Mijn Pleya',
			'myPleya.downloadsCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '1 download', other: '{n} downloads', ), 
			'liveTv.serverNotAvailable' => 'Live TV-server is niet beschikbaar.',
			'liveTv.serverNotConnected' => 'Live TV-server is niet verbonden.',
			'liveTv.title' => 'Live TV',
			'liveTv.guide' => 'Gids',
			'liveTv.noChannels' => 'Geen zenders beschikbaar',
			'liveTv.noDvr' => 'Geen DVR geconfigureerd op een server',
			'liveTv.noPrograms' => 'Geen programmagegevens beschikbaar',
			'liveTv.liveStreamFailed' => 'Livestream mislukt',
			'liveTv.unknownProgram' => 'Onbekend programma',
			'liveTv.unknownHub' => 'Onbekend',
			'liveTv.unknownError' => 'Onbekende fout',
			'liveTv.channelNumber' => ({required Object number}) => 'Kanaal ${number}',
			'liveTv.unknownChannel' => 'Onbekend kanaal',
			'liveTv.live' => 'LIVE',
			'liveTv.reloadGuide' => 'Gids herladen',
			'liveTv.now' => 'Nu',
			'liveTv.today' => 'Vandaag',
			'liveTv.tomorrow' => 'Morgen',
			'liveTv.midnight' => 'Middernacht',
			'liveTv.overnight' => 'Nacht',
			'liveTv.morning' => 'Ochtend',
			'liveTv.daytime' => 'Overdag',
			'liveTv.evening' => 'Avond',
			'liveTv.lateNight' => 'Late avond',
			'liveTv.whatsOn' => 'Nu op TV',
			'liveTv.watchChannel' => 'Kanaal bekijken',
			'liveTv.favorites' => 'Favorieten',
			'liveTv.reorderFavorites' => 'Favorieten herordenen',
			'liveTv.favoritesSaveFailed' => 'Kon je favoriete kanalen niet opslaan',
			'liveTv.joinSession' => 'Deelnemen aan lopende sessie',
			'liveTv.watchFromStart' => ({required Object minutes}) => 'Kijk vanaf het begin (${minutes} min geleden)',
			'liveTv.watchLive' => 'Live kijken',
			'liveTv.goToLive' => 'Ga naar live',
			'liveTv.record' => 'Opnemen',
			'liveTv.recordEpisode' => 'Aflevering opnemen',
			'liveTv.recordSeries' => 'Serie opnemen',
			'liveTv.recordOptions' => 'Opnameopties',
			'liveTv.recordings' => 'Opnames',
			'liveTv.scheduledRecordings' => 'Gepland',
			'liveTv.recordingRules' => 'Opnameregels',
			'liveTv.noScheduledRecordings' => 'Geen geplande opnames',
			'liveTv.noRecordingRules' => 'Nog geen opnameregels',
			'liveTv.manageRecording' => 'Opname beheren',
			'liveTv.cancelRecording' => 'Opname annuleren',
			'liveTv.cancelRecordingTitle' => 'Deze opname annuleren?',
			'liveTv.cancelRecordingMessage' => ({required Object title}) => '${title} wordt niet meer opgenomen.',
			'liveTv.deleteRule' => 'Regel verwijderen',
			'liveTv.deleteRuleTitle' => 'Opnameregel verwijderen?',
			'liveTv.deleteRuleMessage' => ({required Object title}) => 'Toekomstige afleveringen van ${title} worden niet opgenomen.',
			'liveTv.recordingScheduled' => 'Opname gepland',
			'liveTv.alreadyScheduled' => 'Dit programma is al gepland',
			'liveTv.dvrAdminRequired' => 'DVR-instellingen vereisen een beheerdersaccount',
			'liveTv.recordingFailed' => 'Kon opname niet plannen',
			'liveTv.recordingTargetMissing' => 'Kon opnamebibliotheek niet bepalen',
			'liveTv.recordNotAvailable' => 'Opname niet beschikbaar voor dit programma',
			'liveTv.recordingCancelled' => 'Opname geannuleerd',
			'liveTv.recordingRuleDeleted' => 'Opnameregel verwijderd',
			'liveTv.processRecordingRules' => 'Regels opnieuw evalueren',
			'liveTv.loadingRecordings' => 'Opnames laden...',
			'liveTv.recordingInProgress' => 'Nu aan het opnemen',
			'liveTv.recordingsCount' => ({required Object count}) => '${count} gepland',
			'liveTv.editRule' => 'Regel bewerken',
			'liveTv.editRuleAction' => 'Bewerken',
			'liveTv.recordingRuleUpdated' => 'Opnameregel bijgewerkt',
			'liveTv.guideReloadRequested' => 'Gids-vernieuwing aangevraagd',
			'liveTv.rulesProcessRequested' => 'Regel-herevaluatie aangevraagd',
			'liveTv.recordShow' => 'Programma opnemen',
			'collections.title' => 'Collecties',
			'collections.collection' => 'Collectie',
			'collections.empty' => 'Collectie is leeg',
			'collections.unknownLibrarySection' => 'Kan niet verwijderen: onbekende bibliotheeksectie',
			'collections.deleteCollection' => 'Collectie verwijderen',
			'collections.deleteConfirm' => ({required Object title}) => '"${title}" verwijderen? Dit kan niet ongedaan worden gemaakt.',
			'collections.deleted' => 'Collectie verwijderd',
			'collections.deleteFailed' => 'Collectie verwijderen mislukt',
			'collections.deleteFailedWithError' => 'Collectie verwijderen mislukt',
			'collections.failedToLoadItems' => 'Collectie-items laden mislukt',
			'collections.selectCollection' => 'Selecteer collectie',
			'collections.collectionName' => 'Collectienaam',
			'collections.enterCollectionName' => 'Voer collectienaam in',
			'collections.addedToCollection' => 'Toegevoegd aan collectie',
			'collections.errorAddingToCollection' => 'Fout bij toevoegen aan collectie',
			'collections.created' => 'Collectie gemaakt',
			'collections.removeFromCollection' => 'Verwijderen uit collectie',
			'collections.removeFromCollectionConfirm' => ({required Object title}) => '"${title}" uit deze collectie verwijderen?',
			'collections.removedFromCollection' => 'Uit collectie verwijderd',
			'collections.removeFromCollectionFailed' => 'Verwijderen uit collectie mislukt',
			'collections.removeFromCollectionError' => 'Fout bij verwijderen uit collectie',
			'collections.searchCollections' => 'Collecties zoeken...',
			'playlists.title' => 'Afspeellijsten',
			'playlists.playlist' => 'Afspeellijst',
			'playlists.noPlaylists' => 'Geen afspeellijsten gevonden',
			'playlists.create' => 'Afspeellijst maken',
			'playlists.playlistName' => 'Naam afspeellijst',
			'playlists.enterPlaylistName' => 'Voer naam afspeellijst in',
			'playlists.delete' => 'Afspeellijst verwijderen',
			'playlists.removeItem' => 'Verwijderen uit afspeellijst',
			'playlists.smartPlaylist' => 'Slimme afspeellijst',
			'playlists.itemCount' => ({required Object count}) => '${count} items',
			'playlists.oneItem' => '1 item',
			'playlists.emptyPlaylist' => 'Deze afspeellijst is leeg',
			'playlists.deleteConfirm' => 'Afspeellijst verwijderen?',
			'playlists.deleteMessage' => ({required Object name}) => 'Weet je zeker dat je "${name}" wilt verwijderen?',
			'playlists.created' => 'Afspeellijst gemaakt',
			'playlists.deleted' => 'Afspeellijst verwijderd',
			'playlists.itemAdded' => 'Toegevoegd aan afspeellijst',
			'playlists.itemRemoved' => 'Verwijderd uit afspeellijst',
			'playlists.selectPlaylist' => 'Selecteer afspeellijst',
			'playlists.errorCreating' => 'Fout bij maken afspeellijst',
			'playlists.errorDeleting' => 'Fout bij verwijderen afspeellijst',
			'playlists.errorLoading' => 'Fout bij laden afspeellijsten',
			'playlists.errorAdding' => 'Fout bij toevoegen aan afspeellijst',
			'playlists.errorReordering' => 'Fout bij herschikken van afspeellijstitem',
			'playlists.errorRemoving' => 'Fout bij verwijderen uit afspeellijst',
			'watchTogether.title' => 'Samen Kijken',
			'watchTogether.description' => 'Kijk synchroon met vrienden en familie',
			'watchTogether.createSession' => 'Sessie Maken',
			'watchTogether.creating' => 'Maken...',
			'watchTogether.joinSession' => 'Sessie Deelnemen',
			'watchTogether.joining' => 'Deelnemen...',
			'watchTogether.controlMode' => 'Controlemodus',
			'watchTogether.controlModeQuestion' => 'Wie kan het afspelen bedienen?',
			'watchTogether.hostOnly' => 'Alleen Host',
			'watchTogether.anyone' => 'Iedereen',
			'watchTogether.hostingSession' => 'Sessie Hosten',
			'watchTogether.inSession' => 'In Sessie',
			'watchTogether.sessionCode' => 'Sessiecode',
			'watchTogether.hostControlsPlayback' => 'Host bedient het afspelen',
			'watchTogether.anyoneCanControl' => 'Iedereen kan het afspelen bedienen',
			'watchTogether.hostControls' => 'Host bedient',
			'watchTogether.anyoneControls' => 'Iedereen bedient',
			'watchTogether.participants' => 'Deelnemers',
			'watchTogether.host' => 'Host',
			'watchTogether.hostBadge' => 'HOST',
			'watchTogether.youAreHost' => 'Jij bent de host',
			'watchTogether.watchingWithOthers' => 'Kijken met anderen',
			'watchTogether.endSession' => 'Sessie Beëindigen',
			'watchTogether.leaveSession' => 'Sessie Verlaten',
			'watchTogether.endSessionQuestion' => 'Sessie Beëindigen?',
			'watchTogether.leaveSessionQuestion' => 'Sessie Verlaten?',
			'watchTogether.endSessionConfirm' => 'Dit beëindigt de sessie voor alle deelnemers.',
			'watchTogether.leaveSessionConfirm' => 'Je wordt uit de sessie verwijderd.',
			'watchTogether.endSessionConfirmOverlay' => 'Dit beëindigt de kijksessie voor alle deelnemers.',
			'watchTogether.leaveSessionConfirmOverlay' => 'Je wordt losgekoppeld van de kijksessie.',
			'watchTogether.end' => 'Beëindigen',
			'watchTogether.leave' => 'Verlaten',
			'watchTogether.syncing' => 'Synchroniseren...',
			'watchTogether.joinWatchSession' => 'Kijksessie Deelnemen',
			'watchTogether.enterCodeHint' => 'Voer 5-teken code in',
			'watchTogether.pasteFromClipboard' => 'Plakken van klembord',
			'watchTogether.pleaseEnterCode' => 'Voer een sessiecode in',
			'watchTogether.codeMustBe5Chars' => 'Sessiecode moet 5 tekens zijn',
			'watchTogether.joinInstructions' => 'Voer de sessiecode van de host in om deel te nemen.',
			'watchTogether.failedToCreate' => 'Sessie maken mislukt',
			'watchTogether.failedToJoin' => 'Sessie deelnemen mislukt',
			'watchTogether.sessionCodeCopied' => 'Sessiecode gekopieerd naar klembord',
			'watchTogether.relayUnreachable' => 'Relay-server onbereikbaar. ISP-blokkering kan Watch Together verhinderen.',
			'watchTogether.reconnectingToHost' => 'Opnieuw verbinden met host...',
			_ => null,
		} ?? switch (path) {
			'watchTogether.currentPlayback' => 'Huidige weergave',
			'watchTogether.joinCurrentPlayback' => 'Deelnemen aan huidige weergave',
			'watchTogether.joinCurrentPlaybackDescription' => 'Ga terug naar wat de host nu kijkt',
			'watchTogether.failedToOpenCurrentPlayback' => 'Huidige weergave kon niet worden geopend',
			'watchTogether.participantJoined' => ({required Object name}) => '${name} is toegetreden',
			'watchTogether.participantLeft' => ({required Object name}) => '${name} heeft de sessie verlaten',
			'watchTogether.participantPaused' => ({required Object name}) => '${name} heeft gepauzeerd',
			'watchTogether.participantResumed' => ({required Object name}) => '${name} heeft hervat',
			'watchTogether.participantSeeked' => ({required Object name}) => '${name} heeft gespoeld',
			'watchTogether.participantBuffering' => ({required Object name}) => '${name} is aan het bufferen',
			'watchTogether.waitingForParticipants' => 'Wachten tot anderen geladen zijn...',
			'watchTogether.recentRooms' => 'Recente kamers',
			'watchTogether.renameRoom' => 'Kamer hernoemen',
			'watchTogether.removeRoom' => 'Verwijderen',
			'watchTogether.guestSwitchUnavailable' => 'Kon niet schakelen — server niet beschikbaar voor synchronisatie',
			'watchTogether.guestSwitchFailed' => 'Kon niet schakelen — inhoud niet gevonden op deze server',
			'downloads.title' => 'Downloads',
			'downloads.manage' => 'Beheren',
			'downloads.tvShows' => 'Series',
			'downloads.movies' => 'Films',
			'downloads.noDownloads' => 'Nog geen downloads',
			'downloads.noDownloadsDescription' => 'Gedownloade content verschijnt hier voor offline weergave',
			'downloads.downloadNow' => 'Download',
			'downloads.deleteDownload' => 'Download verwijderen',
			'downloads.retryDownload' => 'Download opnieuw proberen',
			'downloads.downloadQueued' => 'Download in wachtrij',
			'downloads.downloadResumed' => 'Download hervat',
			'downloads.serverErrorBitrate' => 'Serverfout: bestand overschrijdt mogelijk de externe bitrate-limiet',
			'downloads.episodesQueued' => ({required Object count}) => '${count} afleveringen in wachtrij voor download',
			'downloads.downloadDeleted' => 'Download verwijderd',
			'downloads.deleteConfirm' => ({required Object title}) => '"${title}" van dit apparaat verwijderen?',
			'downloads.cancelledDownloadTitle' => 'Geannuleerde download',
			'downloads.cancelledDownloadMessage' => 'Deze download is geannuleerd. Wat wil je doen?',
			'downloads.allEpisodesAlreadyDownloaded' => 'Alle afleveringen zijn al gedownload',
			'downloads.resumeDownload' => 'Download hervatten',
			'downloads.cancelledDownload' => 'Geannuleerde download',
			'downloads.syncingFile' => ({required Object file, required Object status}) => '${file} (${status} synchroniseren)',
			'downloads.downloadedFileClickToComplete' => ({required Object file}) => '${file} gedownload — klik om te voltooien',
			'downloads.partialDownloadClickToComplete' => 'Gedeeltelijk gedownload — klik om te voltooien',
			'downloads.deleting' => 'Verwijderen...',
			'downloads.deletingWithProgress' => ({required Object title, required Object current, required Object total}) => 'Verwijderen van ${title}... (${current} van ${total})',
			'downloads.queuedTooltip' => 'In wachtrij',
			'downloads.queuedFilesTooltip' => ({required Object files}) => 'In wachtrij: ${files}',
			'downloads.downloadingTooltip' => 'Downloaden...',
			'downloads.downloadingFilesTooltip' => ({required Object files}) => 'Downloaden ${files}',
			'downloads.noDownloadsTree' => 'Geen downloads',
			'downloads.pauseAll' => 'Alles pauzeren',
			'downloads.resumeAll' => 'Alles hervatten',
			'downloads.deleteAll' => 'Alles verwijderen',
			'downloads.selectVersion' => 'Versie selecteren',
			'downloads.allEpisodes' => 'Alle afleveringen',
			'downloads.unwatchedOnly' => 'Alleen onbekeken',
			'downloads.nextNUnwatched' => ({required Object count}) => 'Volgende ${count} onbekeken',
			'downloads.customAmount' => 'Aangepast aantal...',
			'downloads.includeSpecials' => 'Specials opnemen',
			'downloads.howManyEpisodes' => 'Hoeveel afleveringen?',
			'downloads.itemsQueued' => ({required Object count}) => '${count} items in downloadwachtrij',
			'downloads.keepSynced' => 'Gesynchroniseerd houden',
			'downloads.downloadOnce' => 'Eenmalig downloaden',
			'downloads.keepNUnwatched' => ({required Object count}) => '${count} onbekeken behouden',
			'downloads.editSyncRule' => 'Synchronisatieregel bewerken',
			'downloads.removeSyncRule' => 'Synchronisatieregel verwijderen',
			'downloads.removeSyncRuleConfirm' => ({required Object title}) => 'Synchronisatie van "${title}" stoppen? Gedownloade afleveringen worden behouden.',
			'downloads.syncRuleCreated' => ({required Object count}) => 'Synchronisatieregel aangemaakt — ${count} onbekeken afleveringen behouden',
			'downloads.syncRuleUpdated' => 'Synchronisatieregel bijgewerkt',
			'downloads.syncRuleRemoved' => 'Synchronisatieregel verwijderd',
			'downloads.syncedNewEpisodes' => ({required Object count, required Object title}) => '${count} nieuwe afleveringen gesynchroniseerd voor ${title}',
			'downloads.activeSyncRules' => 'Synchronisatieregels',
			'downloads.noSyncRules' => 'Geen synchronisatieregels',
			'downloads.manageSyncRule' => 'Synchronisatie beheren',
			'downloads.editEpisodeCount' => 'Aantal afleveringen',
			'downloads.editSyncFilter' => 'Synchronisatiefilter',
			'downloads.syncAllItems' => 'Alle items synchroniseren',
			'downloads.syncUnwatchedItems' => 'Ongekeken items synchroniseren',
			'downloads.syncRuleServerContext' => ({required Object server, required Object status}) => 'Server: ${server} • ${status}',
			'downloads.syncRuleAvailable' => 'Beschikbaar',
			'downloads.syncRuleOffline' => 'Offline',
			'downloads.syncRuleSignInRequired' => 'Inloggen vereist',
			'downloads.syncRuleNotAvailableForProfile' => 'Niet beschikbaar voor huidig profiel',
			'downloads.syncRuleUnknownServer' => 'Onbekende server',
			'downloads.syncRuleListCreated' => 'Synchronisatieregel aangemaakt',
			'shaders.title' => 'Shaders',
			'shaders.noShaderDescription' => 'Geen videoverbetering',
			'shaders.nvscalerDescription' => 'NVIDIA-beeldschaling voor scherpere video',
			'shaders.artcnnVariantNeutral' => 'Neutraal',
			'shaders.artcnnVariantDenoise' => 'Ruisonderdrukking',
			'shaders.artcnnVariantDenoiseSharpen' => 'Ruisonderdrukking + verscherpen',
			'shaders.qualityFast' => 'Snel',
			'shaders.qualityHQ' => 'Hoge kwaliteit',
			'shaders.mode' => 'Modus',
			'shaders.importShader' => 'Shader importeren',
			'shaders.customShaderDescription' => 'Aangepaste GLSL-shader',
			'shaders.shaderImported' => 'Shader geïmporteerd',
			'shaders.shaderImportFailed' => 'Shader importeren mislukt',
			'shaders.deleteShader' => 'Shader verwijderen',
			'shaders.deleteShaderConfirm' => ({required Object name}) => '"${name}" verwijderen?',
			'companionRemote.title' => 'Afstandsbediening',
			'companionRemote.connectedTo' => ({required Object name}) => 'Verbonden met ${name}',
			'companionRemote.unknownDevice' => 'Onbekend apparaat',
			'companionRemote.session.startingServer' => 'Externe server starten...',
			'companionRemote.session.failedToCreate' => 'Kan externe server niet starten:',
			'companionRemote.session.hostAddress' => 'Hostadres',
			'companionRemote.session.connected' => 'Verbonden',
			'companionRemote.session.serverRunning' => 'Externe server actief',
			'companionRemote.session.serverStopped' => 'Externe server gestopt',
			'companionRemote.session.serverRunningDescription' => 'Mobiele apparaten op je netwerk kunnen met deze app verbinden',
			'companionRemote.session.serverStoppedDescription' => 'Start de server om mobiele apparaten te laten verbinden',
			'companionRemote.session.usePhoneToControl' => 'Gebruik je mobiele apparaat om deze app te bedienen',
			'companionRemote.session.startServer' => 'Server starten',
			'companionRemote.session.stopServer' => 'Server stoppen',
			'companionRemote.session.minimize' => 'Minimaliseren',
			'companionRemote.pairing.discoveryDescription' => 'Pleya-apparaten met hetzelfde Plex-account verschijnen hier',
			'companionRemote.pairing.hostAddressHint' => '192.168.1.100:48632',
			'companionRemote.pairing.connecting' => 'Verbinden...',
			'companionRemote.pairing.searchingForDevices' => 'Apparaten zoeken...',
			'companionRemote.pairing.noDevicesFound' => 'Geen apparaten gevonden op je netwerk',
			'companionRemote.pairing.noDevicesHint' => 'Open Pleya op desktop en gebruik dezelfde WiFi',
			'companionRemote.pairing.availableDevices' => 'Beschikbare apparaten',
			'companionRemote.pairing.manualConnection' => 'Handmatige verbinding',
			'companionRemote.pairing.cryptoInitFailed' => 'Kon beveiligde verbinding niet starten. Log eerst in bij Plex.',
			'companionRemote.pairing.validationHostRequired' => 'Voer het hostadres in',
			'companionRemote.pairing.validationHostFormat' => 'Formaat moet IP:poort zijn (bijv. 192.168.1.100:48632)',
			'companionRemote.pairing.connectionTimedOut' => 'Verbinding verlopen. Gebruik hetzelfde netwerk op beide apparaten.',
			'companionRemote.pairing.sessionNotFound' => 'Apparaat niet gevonden. Zorg dat Pleya op de host draait.',
			'companionRemote.pairing.authFailed' => 'Authenticatie mislukt. Beide apparaten hebben hetzelfde Plex-account nodig.',
			'companionRemote.pairing.failedToConnect' => 'Kan niet verbinden',
			'companionRemote.remote.disconnectConfirm' => 'Wil je de verbinding met de externe sessie verbreken?',
			'companionRemote.remote.reconnecting' => 'Opnieuw verbinden...',
			'companionRemote.remote.attemptOf' => ({required Object current}) => 'Poging ${current} van 5',
			'companionRemote.remote.retryNow' => 'Nu opnieuw proberen',
			'companionRemote.remote.tabRemote' => 'Afstandsbediening',
			'companionRemote.remote.tabPlay' => 'Afspelen',
			'companionRemote.remote.tabMore' => 'Meer',
			'companionRemote.remote.menu' => 'Menu',
			'companionRemote.remote.tabNavigation' => 'Tabnavigatie',
			'companionRemote.remote.tabDiscover' => 'Ontdekken',
			'companionRemote.remote.tabLibraries' => 'Bibliotheken',
			'companionRemote.remote.tabSearch' => 'Zoeken',
			'companionRemote.remote.tabDownloads' => 'Downloads',
			'companionRemote.remote.tabSettings' => 'Instellingen',
			'companionRemote.remote.previous' => 'Vorige',
			'companionRemote.remote.playPause' => 'Afspelen/Pauzeren',
			'companionRemote.remote.next' => 'Volgende',
			'companionRemote.remote.seekBack' => 'Terugspoelen',
			'companionRemote.remote.stop' => 'Stoppen',
			'companionRemote.remote.seekForward' => 'Vooruitspoelen',
			'companionRemote.remote.volume' => 'Volume',
			'companionRemote.remote.volumeDown' => 'Omlaag',
			'companionRemote.remote.volumeUp' => 'Omhoog',
			'companionRemote.remote.fullscreen' => 'Volledig scherm',
			'companionRemote.remote.subtitles' => 'Ondertitels',
			'companionRemote.remote.audio' => 'Audio',
			'companionRemote.remote.searchHint' => 'Zoeken op desktop...',
			'companionRemote.errors.noNetworkInterface' => 'Geen netwerkinterface gevonden',
			'companionRemote.errors.authenticationFailed' => 'Authenticatie mislukt',
			'companionRemote.errors.joinTimedOut' => 'Time-out bij deelnemen aan sessie',
			'companionRemote.errors.failedToConnectAnyAddress' => 'Kan met geen enkel adres verbinden',
			'companionRemote.errors.connectionLostAfterAttempts' => ({required Object attempts}) => 'Verbinding verloren na ${attempts} pogingen',
			'companionRemote.errors.connectionLost' => 'Verbinding verloren',
			'videoSettings.playbackSpeed' => 'Afspeelsnelheid',
			'videoSettings.zoom' => 'Zoom',
			'videoSettings.sleepTimer' => 'Slaaptimer',
			'videoSettings.audioSync' => 'Audio synchronisatie',
			'videoSettings.subtitleSync' => 'Ondertitel synchronisatie',
			'videoSettings.hdr' => 'HDR',
			'videoSettings.audioOutput' => 'Audio-uitvoer',
			'videoSettings.performanceOverlay' => 'Prestatie-overlay',
			'videoSettings.audioPassthrough' => 'Audio-doorvoer',
			'videoSettings.audioOutputTitle' => 'Audio-uitvoermodus',
			'videoSettings.audioOutputModes.auto' => 'Automatisch',
			'videoSettings.audioOutputModes.passthrough' => 'Doorvoeren',
			'videoSettings.audioOutputModes.pcm' => 'PCM (decoderen)',
			'videoSettings.audioOutputDecisions.passthrough' => 'Dolby-doorvoer',
			'videoSettings.audioOutputDecisions.pcmMultichannel' => 'PCM meerkanaals',
			'videoSettings.audioOutputDecisions.pcmStereo' => 'PCM stereo',
			'videoSettings.audioOutputModeDescriptions.auto' => 'Verbreedt naar meerkanaals waar de uitgang dat toelaat; stuurt nooit een bitstream',
			'videoSettings.audioOutputModeDescriptions.passthrough' => 'Stuur Dolby altijd onbewerkt naar de ontvanger',
			'videoSettings.audioOutputModeDescriptions.pcm' => 'Decodeer altijd in de app',
			'videoSettings.audioOutputRendering.monoStereo' => 'Stereo',
			'videoSettings.audioOutputRendering.surround' => 'Surround',
			'videoSettings.audioOutputRendering.spatialAudio' => 'Spatial Audio',
			'videoSettings.audioOutputRendering.dolbyAudio' => 'Dolby Audio',
			'videoSettings.audioOutputRendering.dolbyAtmos' => 'Dolby Atmos',
			'videoSettings.audioOutputNow' => ({required Object mode}) => 'nu: ${mode}',
			'videoSettings.audioNormalization' => 'Volume normaliseren',
			'videoSettings.audioNormalizationSuspended' => 'Dolby-doorvoer loopt, dus volume gelijkmaken staat uit. Je receiver bepaalt het niveau.',
			'videoSettings.audioPriorityTitle' => 'Prioriteit',
			'videoSettings.audioPriorities.evenVolume' => 'Gelijkmatig volume',
			'videoSettings.audioPriorities.originalDolby' => 'Originele Dolby Atmos',
			'videoSettings.audioLevelVolume' => 'Volume gelijkmaken',
			'videoSettings.audioLevelVolumeDescription' => 'Brengt elke titel op hetzelfde niveau als de rest van je tv',
			'videoSettings.audioReduceLoudSounds' => 'Verminder harde geluiden',
			'videoSettings.audioReduceLoudSoundsDescription' => 'Verkleint het verschil tussen dialoog en harde effecten',
			'videoSettings.tryLowerQuality' => 'Probeer lagere kwaliteit',
			'videoSettings.audioPassthroughUnavailable' => 'Deze uitgang accepteert geen Dolby-bitstream — overgeschakeld op gedecodeerd geluid.',
			'performanceOverlay.color' => 'Kleur',
			'performanceOverlay.performance' => 'Prestaties',
			'performanceOverlay.buffer' => 'Buffer',
			'performanceOverlay.app' => 'App',
			'performanceOverlay.decoder' => 'Decoder',
			'performanceOverlay.rawDecoder' => 'Raw decoder',
			'performanceOverlay.tunneling' => 'Tunneling',
			'performanceOverlay.aspect' => 'Verhouding',
			'performanceOverlay.rotation' => 'Rotatie',
			'performanceOverlay.dvSource' => 'DV-bron',
			'performanceOverlay.dvPath' => 'DV-pad',
			'performanceOverlay.p7Conversion' => 'P7-conv.',
			'performanceOverlay.sampleRate' => 'Samplefrequentie',
			'performanceOverlay.audioDriver' => 'Audiostuurprogramma',
			'performanceOverlay.audioOutFormat' => 'Uitvoerformaat',
			'performanceOverlay.audioRequested' => 'Gevraagd',
			'performanceOverlay.audioActual' => 'Werkelijk',
			'performanceOverlay.audioMeasuring' => 'meten…',
			'performanceOverlay.audioBitstream' => 'bitstream',
			'performanceOverlay.audioFellBack' => 'terugval',
			'performanceOverlay.audioFilters' => 'Filters',
			'performanceOverlay.audioFiltersNone' => 'geen',
			'performanceOverlay.volume' => 'Volume',
			'performanceOverlay.pixelFormat' => 'Pixelformaat',
			'performanceOverlay.hwFormat' => 'HW-formaat',
			'performanceOverlay.matrix' => 'Matrix',
			'performanceOverlay.primaries' => 'Primaire kleuren',
			'performanceOverlay.transfer' => 'Transfer',
			'performanceOverlay.renderFps' => 'Render-FPS',
			'performanceOverlay.displayFps' => 'Scherm-FPS',
			'performanceOverlay.avSync' => 'A/V-sync',
			'performanceOverlay.dropped' => 'Gedropt',
			'performanceOverlay.dvRpus' => 'DV RPU’s',
			'performanceOverlay.dvRpuAverage' => 'DV RPU gem.',
			'performanceOverlay.dvSampleAverage' => 'DV-sample gem.',
			'performanceOverlay.maxLuma' => 'Max luma',
			'performanceOverlay.minLuma' => 'Min luma',
			'performanceOverlay.maxCll' => 'MaxCLL',
			'performanceOverlay.maxFall' => 'MaxFALL',
			'performanceOverlay.cacheUsed' => 'Cache gebruikt',
			'performanceOverlay.cacheLimit' => 'Cachelimiet',
			'performanceOverlay.speed' => 'Snelheid',
			'performanceOverlay.player' => 'Speler',
			'performanceOverlay.memory' => 'Geheugen',
			'performanceOverlay.uiFps' => 'UI FPS',
			'externalPlayer.title' => 'Externe speler',
			'externalPlayer.useExternalPlayer' => 'Externe speler gebruiken',
			'externalPlayer.useExternalPlayerDescription' => 'Open video\'s in een andere app',
			'externalPlayer.selectPlayer' => 'Speler selecteren',
			'externalPlayer.customPlayers' => 'Aangepaste spelers',
			'externalPlayer.systemDefault' => 'Systeemstandaard',
			'externalPlayer.addCustomPlayer' => 'Aangepaste speler toevoegen',
			'externalPlayer.playerName' => 'Spelernaam',
			'externalPlayer.playerNameHint' => 'Mijn speler',
			'externalPlayer.playerCommand' => 'Commando',
			'externalPlayer.playerPackage' => 'Pakketnaam',
			'externalPlayer.playerUrlScheme' => 'URL-schema',
			'externalPlayer.off' => 'Uit',
			'externalPlayer.launchFailed' => 'Kan externe speler niet openen',
			'externalPlayer.appNotInstalled' => ({required Object name}) => '${name} is niet geïnstalleerd',
			'externalPlayer.playInExternalPlayer' => 'Afspelen in externe speler',
			'metadataEdit.editMetadata' => 'Bewerken...',
			'metadataEdit.screenTitle' => 'Metadata bewerken',
			'metadataEdit.basicInfo' => 'Basisinformatie',
			'metadataEdit.artwork' => 'Artwork',
			'metadataEdit.advancedSettings' => 'Geavanceerde instellingen',
			'metadataEdit.title' => 'Titel',
			'metadataEdit.sortTitle' => 'Sorteertitel',
			'metadataEdit.originalTitle' => 'Oorspronkelijke titel',
			'metadataEdit.releaseDate' => 'Releasedatum',
			'metadataEdit.contentRating' => 'Leeftijdsclassificatie',
			'metadataEdit.studio' => 'Studio',
			'metadataEdit.tagline' => 'Tagline',
			'metadataEdit.summary' => 'Samenvatting',
			'metadataEdit.poster' => 'Poster',
			'metadataEdit.background' => 'Achtergrond',
			'metadataEdit.logo' => 'Logo',
			'metadataEdit.squareArt' => 'Vierkante afbeelding',
			'metadataEdit.selectPoster' => 'Poster selecteren',
			'metadataEdit.selectBackground' => 'Achtergrond selecteren',
			'metadataEdit.selectLogo' => 'Logo selecteren',
			'metadataEdit.selectSquareArt' => 'Vierkante afbeelding selecteren',
			'metadataEdit.fromUrl' => 'Vanaf URL',
			'metadataEdit.uploadFile' => 'Bestand uploaden',
			'metadataEdit.enterImageUrl' => 'Voer afbeeldings-URL in',
			'metadataEdit.imageUrl' => 'Afbeeldings-URL',
			'metadataEdit.metadataUpdated' => 'Metadata bijgewerkt',
			'metadataEdit.metadataUpdateFailed' => 'Metadata bijwerken mislukt',
			'metadataEdit.artworkUpdated' => 'Artwork bijgewerkt',
			'metadataEdit.artworkUpdateFailed' => 'Artwork bijwerken mislukt',
			'metadataEdit.noArtworkAvailable' => 'Geen artwork beschikbaar',
			'metadataEdit.notSet' => 'Niet ingesteld',
			'metadataEdit.libraryDefault' => 'Bibliotheekstandaard',
			'metadataEdit.accountDefault' => 'Accountstandaard',
			'metadataEdit.seriesDefault' => 'Seriestandaard',
			'metadataEdit.episodeSorting' => 'Afleveringen sorteren',
			'metadataEdit.oldestFirst' => 'Oudste eerst',
			'metadataEdit.newestFirst' => 'Nieuwste eerst',
			'metadataEdit.keep' => 'Bewaren',
			'metadataEdit.allEpisodes' => 'Alle afleveringen',
			'metadataEdit.latestEpisodes' => ({required Object count}) => '${count} nieuwste afleveringen',
			'metadataEdit.latestEpisode' => 'Nieuwste aflevering',
			'metadataEdit.episodesAddedPastDays' => ({required Object count}) => 'Afleveringen toegevoegd in de afgelopen ${count} dagen',
			'metadataEdit.deleteAfterPlaying' => 'Afleveringen verwijderen na afspelen',
			'metadataEdit.never' => 'Nooit',
			'metadataEdit.afterADay' => 'Na een dag',
			'metadataEdit.afterAWeek' => 'Na een week',
			'metadataEdit.afterAMonth' => 'Na een maand',
			'metadataEdit.onNextRefresh' => 'Bij volgende verversing',
			'metadataEdit.seasons' => 'Seizoenen',
			'metadataEdit.show' => 'Tonen',
			'metadataEdit.hide' => 'Verbergen',
			'metadataEdit.episodeOrdering' => 'Afleveringsvolgorde',
			'metadataEdit.tmdbAiring' => 'The Movie Database (Uitgezonden)',
			'metadataEdit.tvdbAiring' => 'TheTVDB (Uitgezonden)',
			'metadataEdit.tvdbAbsolute' => 'TheTVDB (Absoluut)',
			'metadataEdit.metadataLanguage' => 'Metadatataal',
			'metadataEdit.useOriginalTitle' => 'Oorspronkelijke titel gebruiken',
			'metadataEdit.preferredAudioLanguage' => 'Voorkeurstaal audio',
			'metadataEdit.preferredSubtitleLanguage' => 'Voorkeurstaal ondertiteling',
			'metadataEdit.subtitleMode' => 'Automatische ondertitelselectie',
			'metadataEdit.manuallySelected' => 'Handmatig geselecteerd',
			'metadataEdit.shownWithForeignAudio' => 'Weergeven bij anderstalig geluid',
			'metadataEdit.alwaysEnabled' => 'Altijd ingeschakeld',
			'metadataEdit.tags' => 'Tags',
			'metadataEdit.addTag' => 'Tag toevoegen',
			'metadataEdit.genre' => 'Genre',
			'metadataEdit.director' => 'Regisseur',
			'metadataEdit.writer' => 'Schrijver',
			'metadataEdit.producer' => 'Producent',
			'metadataEdit.country' => 'Land',
			'metadataEdit.collection' => 'Collectie',
			'metadataEdit.label' => 'Label',
			'metadataEdit.style' => 'Stijl',
			'metadataEdit.mood' => 'Stemming',
			'matchScreen.match' => 'Koppelen...',
			'matchScreen.fixMatch' => 'Koppeling herstellen...',
			'matchScreen.unmatch' => 'Ontkoppelen',
			'matchScreen.unmatchConfirm' => 'Deze match wissen? Plex behandelt dit als niet-gematcht tot het opnieuw gematcht is.',
			'matchScreen.unmatchSuccess' => 'Item ontkoppeld',
			'matchScreen.unmatchFailed' => 'Kon item niet ontkoppelen',
			'matchScreen.matchApplied' => 'Koppeling toegepast',
			'matchScreen.matchFailed' => 'Koppeling kon niet worden toegepast',
			'matchScreen.titleHint' => 'Titel',
			'matchScreen.yearHint' => 'Jaar',
			'matchScreen.search' => 'Zoeken',
			'matchScreen.noMatchesFound' => 'Geen overeenkomsten gevonden',
			'serverTasks.title' => 'Servertaken',
			'serverTasks.failedToLoad' => 'Taken konden niet worden geladen',
			'serverTasks.noTasks' => 'Geen actieve taken',
			'trakt.title' => 'Trakt',
			'trakt.connected' => 'Verbonden',
			'trakt.connectedAs' => ({required Object username}) => 'Verbonden als @${username}',
			'trakt.disconnectConfirm' => 'Trakt-account loskoppelen?',
			'trakt.disconnectConfirmBody' => 'Pleya stopt met gebeurtenissen naar Trakt sturen. Je kunt altijd opnieuw verbinden.',
			'trakt.scrobble' => 'Realtime scrobbling',
			'trakt.scrobbleDescription' => 'Verstuur play-, pauze- en stopgebeurtenissen tijdens afspelen naar Trakt.',
			'trakt.watchedSync' => 'Bekeken-status synchroniseren',
			'trakt.watchedSyncDescription' => 'Wanneer je items als bekeken markeert in Pleya, worden ze ook op Trakt gemarkeerd.',
			'trackers.title' => 'Trackers',
			'trackers.hubSubtitle' => 'Synchroniseer kijkvoortgang met Trakt en andere diensten.',
			'trackers.notConnected' => 'Niet verbonden',
			'trackers.connectedAs' => ({required Object username}) => 'Verbonden als @${username}',
			'trackers.scrobble' => 'Voortgang automatisch volgen',
			'trackers.scrobbleDescription' => 'Werk je lijst bij wanneer je een aflevering of film afrondt.',
			'trackers.disconnectConfirm' => ({required Object service}) => '${service} loskoppelen?',
			'trackers.disconnectConfirmBody' => ({required Object service}) => 'Pleya stopt met ${service} bijwerken. Je kunt altijd opnieuw verbinden.',
			'trackers.connectFailed' => ({required Object service}) => 'Kan niet verbinden met ${service}. Probeer opnieuw.',
			'trackers.services.mal' => 'MyAnimeList',
			'trackers.services.anilist' => 'AniList',
			'trackers.services.simkl' => 'Simkl',
			'trackers.deviceCode.title' => ({required Object service}) => 'Pleya activeren op ${service}',
			'trackers.deviceCode.body' => ({required Object url}) => 'Ga naar ${url} en voer deze code in:',
			'trackers.deviceCode.openToActivate' => ({required Object service}) => 'Open ${service} om te activeren',
			'trackers.deviceCode.waitingForAuthorization' => 'Wachten op autorisatie…',
			'trackers.deviceCode.codeCopied' => 'Code gekopieerd',
			'trackers.oauthProxy.title' => ({required Object service}) => 'Aanmelden bij ${service}',
			'trackers.oauthProxy.body' => 'Scan deze QR-code of open de URL op een apparaat.',
			'trackers.oauthProxy.openToSignIn' => ({required Object service}) => '${service} openen om aan te melden',
			'trackers.oauthProxy.urlCopied' => 'URL gekopieerd',
			'trackers.libraryFilter.title' => 'Bibliotheekfilter',
			'trackers.libraryFilter.subtitleAllSyncing' => 'Alle bibliotheken synchroniseren',
			'trackers.libraryFilter.subtitleNoneSyncing' => 'Niets wordt gesynchroniseerd',
			'trackers.libraryFilter.subtitleBlocked' => ({required Object count}) => '${count} geblokkeerd',
			'trackers.libraryFilter.subtitleAllowed' => ({required Object count}) => '${count} toegestaan',
			'trackers.libraryFilter.mode' => 'Filtermodus',
			'trackers.libraryFilter.modeBlacklist' => 'Zwarte lijst',
			'trackers.libraryFilter.modeWhitelist' => 'Witte lijst',
			'trackers.libraryFilter.modeHintBlacklist' => 'Synchroniseer alle bibliotheken behalve die hieronder aangevinkt zijn.',
			'trackers.libraryFilter.modeHintWhitelist' => 'Synchroniseer alleen de hieronder aangevinkte bibliotheken.',
			'trackers.libraryFilter.libraries' => 'Bibliotheken',
			'trackers.libraryFilter.noLibraries' => 'Geen bibliotheken beschikbaar',
			'addServer.addJellyfinTitle' => 'Jellyfin-server toevoegen',
			'addServer.serverUrls' => 'Server-URL\'s',
			'addServer.serverUrlsHelper' => 'Meerdere URL\'s toegestaan, gescheiden door komma\'s.',
			'addServer.findServer' => 'Server zoeken',
			'addServer.searchingLocalServers' => 'Lokale Jellyfin-servers zoeken...',
			'addServer.localServers' => 'Lokale Jellyfin-servers',
			'addServer.username' => 'Gebruikersnaam',
			'addServer.password' => 'Wachtwoord',
			'addServer.signIn' => 'Inloggen',
			'addServer.change' => 'Wijzigen',
			'addServer.required' => 'Vereist',
			'addServer.couldNotReachServer' => 'Kon de server niet bereiken',
			'addServer.signInFailed' => 'Inloggen mislukt',
			'addServer.quickConnectFailed' => 'Quick Connect mislukt',
			'addServer.addPlexTitle' => 'Inloggen met Plex',
			'addServer.pinExpired' => 'PIN verlopen vóór inloggen. Probeer opnieuw.',
			'addServer.duplicatePlexAccount' => 'Al aangemeld bij Plex. Meld je af om van account te wisselen.',
			'addServer.failedToRegisterAccount' => 'Account registreren mislukt',
			'addServer.enterJellyfinUrlError' => 'Voer de URL van je Jellyfin-server in',
			'addServer.addConnectionTitle' => 'Verbinding toevoegen',
			'addServer.addConnectionTitleScoped' => ({required Object name}) => 'Toevoegen aan ${name}',
			'addServer.signInWithPlexCard' => 'Inloggen met Plex',
			'addServer.signInWithPlexCardSubtitle' => 'Autoriseer dit apparaat. Gedeelde servers worden toegevoegd.',
			'addServer.signInWithPlexCardSubtitleScoped' => 'Autoriseer een Plex-account. Home-gebruikers worden profielen.',
			'addServer.connectToJellyfinCard' => 'Verbinden met Jellyfin',
			'addServer.connectToJellyfinCardSubtitle' => 'Voer je server-URL, gebruikersnaam en wachtwoord in.',
			'addServer.connectToJellyfinCardSubtitleScoped' => ({required Object name}) => 'Log in op een Jellyfin-server. Wordt gekoppeld aan ${name}.',
			'addServer.borrowFromAnotherProfile' => 'Lenen van een ander profiel',
			'addServer.borrowFromAnotherProfileSubtitle' => 'Hergebruik de verbinding van een ander profiel. PIN-beveiligde profielen vereisen een PIN.',
			'addLocalFolder.cardTitle' => 'Lokale Map',
			'addLocalFolder.cardSubtitle' => 'Blader door mediabestanden uit een map op je apparaat',
			'addLocalFolder.title' => 'Lokale Map Toevoegen',
			'addLocalFolder.description' => 'Selecteer een map op je apparaat met films of series. Pleya scant de mapstructuur en toont je media.',
			'addLocalFolder.libraryType' => 'Bibliotheektype',
			'addLocalFolder.typeMovies' => 'Films',
			'addLocalFolder.typeTvShows' => 'Series',
			'addLocalFolder.typeMixed' => 'Gemengd',
			'addLocalFolder.directory' => 'Map',
			'addLocalFolder.chooseDirectory' => 'Kies een map…',
			'addLocalFolder.nameLabel' => 'Weergavenaam',
			'addLocalFolder.nameHint' => 'bijv. Mijn Films',
			'addLocalFolder.save' => 'Map toevoegen',
			'addLocalFolder.saveError' => 'Lokale map toevoegen mislukt',
			'pleyaShare.cardTitle' => 'Pleya Share',
			'pleyaShare.cardSubtitle' => 'Verbind met een ander Pleya-apparaat dat media deelt',
			'pleyaShare.hostTitle' => 'Mijn media delen',
			'pleyaShare.hostDescription' => 'Andere Pleya-apparaten op dit netwerk kunnen je lokale mappen bekijken, streamen en downloaden. Houd dit scherm open tijdens het delen.',
			'pleyaShare.hostToggle' => 'Lokale mappen delen',
			'pleyaShare.noLocalFolders' => 'Voeg eerst een lokale map toe — er is nog niets om te delen.',
			'pleyaShare.pairCodeLabel' => 'Koppelcode',
			'pleyaShare.pairCodeHint' => 'Voer deze code in op het andere apparaat. De code verandert na elke geslaagde koppeling.',
			'pleyaShare.regenerateCode' => 'Nieuwe code',
			'pleyaShare.pairedDevices' => 'Gekoppelde apparaten',
			'pleyaShare.noGuests' => 'Nog geen apparaten gekoppeld',
			'pleyaShare.revokeGuest' => 'Apparaat verwijderen',
			'pleyaShare.joinTitle' => 'Verbinden met Pleya Share',
			'pleyaShare.joinDescription' => 'Kies een host op je netwerk of voer het adres in, en typ daarna de 6-cijferige code die op dat apparaat staat.',
			'pleyaShare.hostsFound' => 'Hosts op je netwerk',
			'pleyaShare.searching' => 'Zoeken naar hosts…',
			'pleyaShare.noHostsFound' => 'Geen hosts gevonden. Zet delen aan op het andere apparaat en controleer of beide op hetzelfde netwerk zitten.',
			'pleyaShare.refresh' => 'Opnieuw zoeken',
			'pleyaShare.manualHost' => 'Hostadres (IP)',
			'pleyaShare.codeLabel' => '6-cijferige code',
			'pleyaShare.scanQr' => 'QR-code scannen',
			'pleyaShare.scanQrHint' => 'Richt de camera op de QR-code op het host-apparaat',
			'pleyaShare.cameraPermissionDenied' => 'Camera-toegang is nodig om de QR-code te scannen.',
			'pleyaShare.connect' => 'Verbinden',
			'pleyaShare.pairFailed' => 'Koppelen mislukt. Controleer de code en probeer opnieuw.',
			'pleyaShare.paired' => ({required Object name}) => 'Verbonden met ${name}',
			'pleyaShare.pairUnreachable' => 'Host niet bereikbaar. Controleer het adres en het netwerk.',
			'pleyaShare.addFolder' => 'Lokale map toevoegen',
			'pleyaShare.notificationTitle' => 'Media wordt gedeeld',
			'pleyaShare.notificationText' => 'Andere Pleya-apparaten kunnen je lokale mappen streamen',
			'pleyaShare.hostDescriptionAndroid' => 'Andere Pleya-apparaten op dit netwerk kunnen je lokale mappen bekijken, streamen en downloaden. Delen blijft op de achtergrond draaien met een melding.',
			'pleyaShare.scanningSubnet' => 'Netwerk scannen…',
			'seerr.title' => 'Aanvragen',
			'seerr.hubSubtitle' => 'Vraag films en series aan op je Jellyseerr- of Overseerr-server.',
			'seerr.notConfigured' => 'Niet ingesteld',
			'seerr.serverUrl' => 'Server-URL',
			'seerr.serverUrlHint' => 'https://aanvragen.voorbeeld.nl',
			'seerr.authMode' => 'Inlogmethode',
			'seerr.authPlex' => 'Inloggen met Plex',
			'seerr.authPlexSubtitle' => 'Met één tik via je bestaande Plex-login.',
			'seerr.authLocal' => 'E-mail en wachtwoord',
			'seerr.authApiKey' => 'API-sleutel',
			'seerr.email' => 'E-mail',
			'seerr.password' => 'Wachtwoord',
			'seerr.apiKey' => 'API-sleutel',
			'seerr.apiKeyHint' => 'Te vinden onder Instellingen → Algemeen op je server',
			'seerr.adminAttributionNote' => 'Met een API-sleutel komen aanvragen op naam van de beheerder. Log in met Plex om ze per gebruiker te registreren.',
			'seerr.setupOnDesktopNote' => 'Tip: dit is makkelijker in te stellen op je telefoon of computer.',
			'seerr.testConnection' => 'Verbinding testen',
			'seerr.save' => 'Opslaan',
			'seerr.disconnect' => 'Ontkoppelen',
			'seerr.disconnectConfirm' => 'Aanvraagserver ontkoppelen?',
			'seerr.disconnectConfirmBody' => 'Pleya stuurt geen aanvragen meer. Je kunt altijd opnieuw verbinden.',
			'seerr.connectedAs' => ({required Object name}) => 'Ingelogd als ${name}',
			'seerr.serverVersion' => ({required Object version}) => 'Serverversie ${version}',
			'seerr.permissionAdmin' => 'Beheerder',
			'seerr.permissionManage' => 'Mag aanvragen goedkeuren',
			'seerr.permissionRequest' => 'Mag aanvragen',
			'seerr.request' => 'Aanvragen',
			'seerr.requested' => 'Aangevraagd',
			'seerr.requestAgain' => 'Aanvragen',
			'seerr.processing' => 'Bezig',
			'seerr.partiallyAvailable' => 'Deels beschikbaar',
			'seerr.available' => 'Beschikbaar',
			'seerr.alreadyRequested' => 'Al aangevraagd',
			'seerr.pending' => 'In afwachting',
			'seerr.approved' => 'Goedgekeurd',
			'seerr.declined' => 'Afgewezen',
			'seerr.failed' => 'Mislukt',
			'seerr.completed' => 'Afgerond',
			'seerr.requestConfirm' => ({required Object title}) => '"${title}" aanvragen?',
			'seerr.requestMovie' => 'Film aanvragen',
			'seerr.requestSuccess' => 'Aangevraagd',
			'seerr.requestFailed' => 'Aanvragen mislukt. Probeer opnieuw.',
			'seerr.selectSeasons' => 'Seizoenen kiezen',
			'seerr.season' => ({required Object number}) => 'Seizoen ${number}',
			'seerr.allSeasons' => 'Alle seizoenen',
			'seerr.seasonsRange' => ({required Object range}) => 'Seizoenen ${range}',
			'seerr.seasonsCount' => ({required Object count}) => '${count} seizoenen',
			'seerr.requestedBy' => ({required Object name}) => 'Aangevraagd door ${name}',
			'seerr.searchPlaceholder' => 'Zoek een film of serie om aan te vragen',
			'seerr.byStreamingService' => 'Per streamingdienst',
			_ => null,
		} ?? switch (path) {
			'seerr.showAll' => 'Alles tonen',
			'seerr.fourK' => 'In 4K aanvragen',
			'seerr.fourKBadge' => '4K',
			'seerr.percentMatch' => ({required Object percent}) => '${percent}% match',
			'seerr.quotaRemaining' => ({required Object remaining, required Object limit}) => 'Nog ${remaining} van ${limit} aanvragen',
			'seerr.quotaUnlimited' => 'Onbeperkt aanvragen',
			'seerr.advancedOptions' => 'Geavanceerde opties',
			'seerr.server' => 'Server',
			'seerr.qualityProfile' => 'Kwaliteitsprofiel',
			'seerr.rootFolder' => 'Hoofdmap',
			'seerr.myRequests' => 'Mijn aanvragen',
			'seerr.allRequests' => 'Alle aanvragen',
			'seerr.filterAll' => 'Alle',
			'seerr.filterPending' => 'In afwachting',
			'seerr.filterApproved' => 'Goedgekeurd',
			'seerr.filterAvailable' => 'Beschikbaar',
			'seerr.filterMovies' => 'Films',
			'seerr.filterShows' => 'Series',
			'seerr.approve' => 'Goedkeuren',
			'seerr.decline' => 'Afwijzen',
			'seerr.edit' => 'Bewerken',
			'seerr.cancelRequest' => 'Aanvraag annuleren',
			'seerr.cancelRequestConfirm' => 'Deze aanvraag annuleren?',
			'seerr.discoverTitle' => 'Ontdekken via Aanvragen',
			'seerr.trending' => 'Populair nu',
			'seerr.popularMovies' => 'Populaire films',
			'seerr.popularTv' => 'Populaire series',
			'seerr.upcoming' => 'Binnenkort',
			'seerr.recommendations' => 'Aanbevolen',
			'seerr.cast' => 'Cast',
			'seerr.loadMore' => 'Meer laden',
			'seerr.searchOnSeerr' => 'Niet in je bibliotheek? Zoek op Jellyseerr / Overseerr',
			'seerr.searchOnSeerrShort' => 'Zoeken via Aanvragen',
			'seerr.noResults' => 'Geen resultaten gevonden.',
			'seerr.errorAuth' => 'Inloggen mislukt. Controleer je gegevens.',
			'seerr.errorForbidden' => 'Je hebt hier geen rechten voor.',
			'seerr.errorNetwork' => 'Kan de server niet bereiken. Controleer de URL.',
			'seerr.errorGeneric' => 'Er ging iets mis. Probeer opnieuw.',
			'tautulli.title' => 'Tautulli',
			'tautulli.subtitle' => 'Tautulli houdt bij wie wat kijkt op je Plex-server. Koppel hem om kijkers, statistieken en live activiteit in Pleya te zien.',
			'tautulli.adminOnlyNote' => 'Tautulli heeft één sleutel die zijn hele beheer-API opent, dus die blijft op dit toestel en alleen jij ziet wat hij meldt. De mensen met wie je je server deelt merken er niets van en hoeven niets in te stellen.',
			'tautulli.useHistoryForRecommendations' => 'Kijkgeschiedenis gebruiken voor aanbevelingen',
			'tautulli.useHistoryForRecommendationsDescription' => 'Gebruikt kijkgeschiedenis van deze Tautulli-server om persoonlijke aanbevelingen te verbeteren voor elk profiel op dit apparaat. Elk profiel krijgt alleen zijn eigen geschiedenis en de verwerking blijft lokaal in Pleya.',
			'tautulli.integrationConflictNote' => 'Er zijn twee verschillende Tautulli-koppelingen voor deze server gevonden, dus de kijkgeschiedenis wordt niet gebruikt tot je opnieuw koppelt met de koppeling die je wilt houden.',
			'tautulli.serverUrl' => 'Tautulli-adres',
			'tautulli.serverUrlHint' => 'http://192.168.1.10:8181 of https://tautulli.voorbeeld.nl',
			'tautulli.authMode' => 'Hoe koppelen',
			'tautulli.modeDevice' => 'Apparaat-token',
			'tautulli.modeDeviceHelp' => 'Ga in Tautulli naar Settings, Tautulli Remote App, en registreer een apparaat. Plak het token hier binnen vijf minuten. Je vaste API-key blijft zo buiten de app, en je kunt dit ene apparaat later weer intrekken.',
			'tautulli.modeApiKey' => 'API-key',
			'tautulli.modeApiKeyHelp' => 'De vaste sleutel uit Settings, Web Interface. Die geeft volledige toegang tot Tautulli, dus gebruik hem alleen als het apparaat-token niet lukt.',
			'tautulli.deviceToken' => 'Apparaat-token',
			'tautulli.apiKey' => 'API-key',
			'tautulli.testConnection' => 'Verbinding testen',
			'tautulli.save' => 'Opslaan',
			'tautulli.connected' => 'Verbonden',
			'tautulli.disconnect' => 'Ontkoppelen',
			'tautulli.disconnectConfirm' => 'Tautulli ontkoppelen?',
			'tautulli.disconnectConfirmBody' => 'Pleya vergeet het adres en het token. Kijkers, statistieken en live activiteit verdwijnen tot je opnieuw koppelt.',
			'tautulli.setupOnDesktopNote' => 'Makkelijker op je telefoon of computer: het adres en het token typen lastig met een afstandsbediening.',
			'tautulli.errorNetwork' => 'Tautulli niet bereikbaar. Controleer het adres en of hij vanaf dit toestel te bereiken is.',
			'tautulli.errorAuth' => 'Tautulli weigert deze sleutel.',
			'tautulli.errorTokenExpired' => 'Tautulli weigert dit token. Een apparaat-token is maar vijf minuten geldig, dus maak een nieuwe aan en probeer opnieuw.',
			'tautulli.errorModeMismatch' => 'Tautulli weigert dit token, en het lijkt op je permanente API-sleutel in plaats van op een apparaat-token. Zet hierboven om naar API-sleutel, of registreer een apparaat in Tautulli en plak dat token.',
			'tautulli.errorUrlRequired' => 'Vul het adres van je Tautulli-server in.',
			'tautulli.errorTokenRequired' => 'Vul een token in.',
			'tautulli.errorNotTautulli' => 'Er antwoordt iets op dat adres, maar het is geen Tautulli. Controleer het adres en het basispad, en of er een loginpagina voor staat.',
			'tautulli.errorServer' => ({required Object code}) => 'Tautulli meldt een serverfout (HTTP ${code}).',
			'tautulli.errorGeneric' => 'Koppelen is niet gelukt.',
			'nowWatching.title' => 'Nu aan het kijken',
			'nowWatching.tooltip' => 'Bekijk wie er nu kijkt',
			'nowWatching.streams' => ({required Object count}) => '${count} streams',
			'nowWatching.oneStream' => '1 stream',
			'nowWatching.transcoding' => ({required Object count}) => '${count} transcoderen',
			'nowWatching.directPlay' => 'Direct play',
			'nowWatching.directStream' => 'Direct stream',
			'nowWatching.transcode' => 'Transcoderen',
			'nowWatching.paused' => 'Gepauzeerd',
			'nowWatching.remaining' => ({required Object time}) => 'nog ${time}',
			'nowWatching.watchingNow' => ({required Object name}) => '${name} kijkt dit nu',
			'nowWatching.hardware' => 'Hardware',
			'nowWatching.onLan' => 'Op je netwerk',
			'nowWatching.onWan' => 'Van buiten',
			'nowWatching.unavailable' => 'Tautulli gaf geen antwoord',
			'nowWatching.sidebarLabel' => 'Nu aan het kijken',
			'sourcePicker.playTitle' => 'Kies waar je wilt afspelen',
			'sourcePicker.detailsTitle' => 'Kies een bron voor de details',
			'sourcePicker.availableOnOneServer' => 'Beschikbaar op 1 server',
			'sourcePicker.availableOnManyServers' => ({required Object count}) => 'Beschikbaar op ${count} servers',
			'sourcePicker.oneServerUnchecked' => '1 server kon niet worden gecontroleerd',
			'sourcePicker.manyServersUnchecked' => ({required Object count}) => '${count} servers konden niet worden gecontroleerd',
			'sourcePicker.checkingMoreSources' => 'Meer bronnen controleren…',
			'sourcePicker.lastUsed' => 'Laatst gebruikt',
			'sourcePicker.currentSource' => 'Huidige bron',
			'sourcePicker.unavailable' => 'Niet beschikbaar',
			'sourcePicker.signInRequired' => 'Opnieuw aanmelden vereist',
			'sourcePicker.resumeAt' => ({required Object position}) => 'Hervatten op ${position}',
			'sourcePicker.watched' => 'Bekeken',
			'sourcePicker.noneReachableTitle' => 'Geen bron is momenteel bereikbaar.',
			'sourcePicker.reauthRequiredTitle' => 'Meld je opnieuw aan om deze titel te bereiken.',
			'sourcePicker.manageServers' => 'Servers beheren',
			'sourcePicker.sourceLabel' => ({required Object source}) => 'Bron: ${source}',
			'sourcePicker.change' => 'Wijzigen',
			'sourcePicker.playbackFailedTitle' => 'Deze bron kon niet worden afgespeeld.',
			'sourcePicker.detailLoadFailedTitle' => 'Deze titel kon niet worden geladen.',
			'sourcePicker.chooseAnotherSource' => 'Andere bron kiezen',
			'sourcePicker.rowSemantics' => ({required Object index, required Object count, required Object description}) => 'Bron ${index} van ${count}: ${description}',
			'sourcePicker.preferredServer' => 'Voorkeursserver',
			'sourcePicker.setPreferredServer' => ({required Object server}) => 'Altijd ${server} gebruiken',
			'unifiedCatalog.moviesTitle' => 'Films',
			'unifiedCatalog.seriesTitle' => 'Series',
			'unifiedCatalog.sources' => ({required Object count}) => '${count} bronnen',
			'unifiedCatalog.allSources' => 'Alle bronnen',
			'unifiedCatalog.oneSource' => '1 bron',
			'unifiedCatalog.seasons' => ({required Object count}) => '${count} seizoenen',
			'unifiedCatalog.oneSeason' => '1 seizoen',
			'unifiedCatalog.titleCount' => ({required Object count}) => '${count} titels',
			'unifiedCatalog.oneTitle' => '1 titel',
			'unifiedCatalog.titlesLoaded' => ({required Object count}) => '${count} titels geladen',
			'unifiedCatalog.loadMore' => 'Meer laden',
			'unifiedCatalog.loadingMore' => 'Meer laden…',
			'unifiedCatalog.sort.title' => 'Sorteren',
			'unifiedCatalog.sort.titleAsc' => 'Titel A–Z',
			'unifiedCatalog.sort.titleDesc' => 'Titel Z–A',
			'unifiedCatalog.sort.recentlyAdded' => 'Recent toegevoegd',
			'unifiedCatalog.sort.oldestAdded' => 'Oudst toegevoegd',
			'unifiedCatalog.sort.newestRelease' => 'Nieuwste release',
			'unifiedCatalog.sort.oldestRelease' => 'Oudste release',
			'unifiedCatalog.sort.recentlyWatched' => 'Recent bekeken',
			'unifiedCatalog.filters.title' => 'Filters',
			'unifiedCatalog.filters.status' => 'Status',
			'unifiedCatalog.filters.genre' => 'Genre',
			'unifiedCatalog.filters.year' => 'Jaar',
			'unifiedCatalog.filters.servers' => 'Servers',
			'unifiedCatalog.filters.libraries' => 'Bibliotheken',
			'unifiedCatalog.filters.apply' => 'Toepassen',
			'unifiedCatalog.filters.clearAll' => 'Alles wissen',
			'unifiedCatalog.filters.all' => 'Alle',
			'unifiedCatalog.filters.unwatched' => 'Niet bekeken',
			'unifiedCatalog.filters.unsupported' => 'Niet beschikbaar voor de huidige bronnen',
			'unifiedCatalog.filters.someUnavailable' => 'Sommige filters zijn niet beschikbaar voor de geselecteerde bronnen',
			'unifiedCatalog.filters.noValues' => 'Niets om uit te kiezen',
			'unifiedCatalog.states.emptyTitle' => 'Deze catalogus is leeg',
			'unifiedCatalog.states.emptyBody' => 'Geen zichtbare bibliotheek bevat iets voor deze pagina.',
			'unifiedCatalog.states.filterEmptyTitle' => 'Niets voldoet aan deze filters',
			'unifiedCatalog.states.filterEmptyBody' => 'Wis een filter om meer titels te zien.',
			'unifiedCatalog.states.clearFilters' => 'Filters wissen',
			'unifiedCatalog.states.errorTitle' => 'De catalogus kon niet worden geladen',
			'unifiedCatalog.states.errorBody' => 'Geen enkele server antwoordde. Controleer je verbinding en probeer het opnieuw.',
			'unifiedCatalog.states.partialOne' => '1 bibliotheek antwoordde niet',
			'unifiedCatalog.states.partialMany' => ({required Object count}) => '${count} bibliotheken antwoordden niet',
			'unifiedCatalog.semantics.watched' => 'Bekeken',
			'unifiedCatalog.semantics.inProgress' => 'Bezig',
			'unifiedCatalog.semantics.loadingMore' => 'Meer titels laden',
			'unifiedCatalog.discovery.allMovies' => 'Alle films',
			'unifiedCatalog.discovery.allSeries' => 'Alle series',
			'unifiedCatalog.discovery.episodeLabel' => ({required Object season, required Object episode}) => 'S${season} A${episode}',
			'unifiedCatalog.discovery.partial' => 'Niet alle bronnen antwoordden',
			'unifiedCatalog.discovery.emptyTitle' => 'Nog niets te ontdekken',
			'unifiedCatalog.discovery.emptyBody' => 'Geen zichtbare bibliotheek heeft hier iets te tonen.',
			'unifiedCatalog.discovery.semantics.section' => ({required Object title, required Object count}) => '${title}, ${count} titels',
			'unifiedCatalog.discovery.semantics.position' => ({required Object position, required Object count}) => '${position} van ${count}',
			'unifiedCatalog.discovery.semantics.viewAllMovies' => 'Alle films bekijken, opent de volledige catalogus',
			'unifiedCatalog.discovery.semantics.viewAllSeries' => 'Alle series bekijken, opent de volledige catalogus',
			'unifiedCatalog.home.featured' => 'Uitgelicht',
			'tvNavigation.activeDestination' => 'huidige sectie',
			'tvNavigation.attentionRequired' => 'vereist aandacht',
			'tvMyPleya.groupContent' => 'Mijn content',
			'tvMyPleya.groupSources' => 'Bibliotheken en bronnen',
			'tvMyPleya.groupPleya' => 'Pleya',
			'tvMyPleya.serversOnline' => ({required Object online, required Object total}) => '${online} van ${total} servers online',
			'tvMyPleya.noServers' => 'Geen servers verbonden',
			'tvMyPleya.statusOnline' => 'Online',
			'tvMyPleya.statusOffline' => 'Offline',
			'tvMyPleya.servers' => 'Servers',
			'tvMyPleya.activity' => 'Activiteit',
			'tvMyPleya.logs' => 'Logs en diagnose',
			'tvMyPleya.signedInAs' => ({required Object name, required Object version}) => 'Aangemeld als ${name} · Pleya ${version}',
			'tvMyPleya.watchlistSubtitle' => 'Bewaarde films en series',
			'tvMyPleya.requestsSubtitle' => 'Verzoeken en ontdekken',
			'tvMyPleya.downloadsSubtitle' => 'Offline en synchronisatieregels',
			'tvMyPleya.librariesSubtitle' => 'Media, collecties, afspeellijsten',
			'tvMyPleya.serversSubtitle' => 'Verbindingen en lokale bronnen',
			'tvMyPleya.activitySubtitle' => 'Nu kijken, samen kijken, remote',
			'tvMyPleya.watchTogetherSubtitle' => 'Kijk gelijk met vrienden',
			'tvMyPleya.settingsSubtitle' => 'Weergave, speler, trackers',
			'tvMyPleya.logsSubtitle' => 'Logbestanden en crashrapportage',
			'tvMyPleya.aboutSubtitle' => 'Versie en licenties',
			'tvMyPleya.logoutSubtitle' => 'Afmelden op dit apparaat',
			'tvMyPleya.semantics.tile' => ({required Object title, required Object subtitle}) => '${title}. ${subtitle}',
			'tvMyPleya.semantics.tileWithCount' => ({required Object title, required Object subtitle, required Object count}) => '${title}. ${subtitle}. ${count}',
			'tvContextMenu.title' => 'Acties',
			'tvContextMenu.menuSemantics' => ({required Object index, required Object count, required Object label}) => 'Actie ${index} van ${count}: ${label}',
			'tvContextMenu.noUsableSource' => 'Er is momenteel geen bron bereikbaar, dus dit kan nu niet worden gewijzigd.',
			'tvContextMenu.doneOnAll' => ({required Object count}) => 'Gereed op alle ${count} bronnen',
			'tvContextMenu.doneOnSome' => ({required Object done, required Object total}) => 'Gereed op ${done} van ${total} bronnen. De rest wordt opnieuw geprobeerd zodra ze weer online zijn.',
			'tvContextMenu.doneOnSomeNoRetry' => ({required Object done, required Object total}) => 'Gereed op ${done} van ${total} bronnen.',
			'tvContextMenu.failed' => 'Dat is niet gelukt',
			_ => null,
		};
	}
}
