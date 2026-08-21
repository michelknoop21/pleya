///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	dynamic operator[](String key) => $meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations
	late final TranslationsStatesEn states = TranslationsStatesEn.internal(_root);
	late final TranslationsAppEn app = TranslationsAppEn.internal(_root);
	late final TranslationsAuthEn auth = TranslationsAuthEn.internal(_root);
	late final TranslationsCommonEn common = TranslationsCommonEn.internal(_root);
	late final TranslationsScreensEn screens = TranslationsScreensEn.internal(_root);
	late final TranslationsUpdateEn update = TranslationsUpdateEn.internal(_root);
	late final TranslationsSettingsEn settings = TranslationsSettingsEn.internal(_root);
	late final TranslationsSearchEn search = TranslationsSearchEn.internal(_root);
	late final TranslationsHotkeysEn hotkeys = TranslationsHotkeysEn.internal(_root);
	late final TranslationsFileInfoEn fileInfo = TranslationsFileInfoEn.internal(_root);
	late final TranslationsMediaMenuEn mediaMenu = TranslationsMediaMenuEn.internal(_root);
	late final TranslationsRateSheetEn rateSheet = TranslationsRateSheetEn.internal(_root);
	late final TranslationsAccessibilityEn accessibility = TranslationsAccessibilityEn.internal(_root);
	late final TranslationsTooltipsEn tooltips = TranslationsTooltipsEn.internal(_root);
	late final TranslationsVideoControlsEn videoControls = TranslationsVideoControlsEn.internal(_root);
	late final TranslationsUserStatusEn userStatus = TranslationsUserStatusEn.internal(_root);
	late final TranslationsMessagesEn messages = TranslationsMessagesEn.internal(_root);
	late final TranslationsSubtitlingStylingEn subtitlingStyling = TranslationsSubtitlingStylingEn.internal(_root);
	late final TranslationsMpvConfigEn mpvConfig = TranslationsMpvConfigEn.internal(_root);
	late final TranslationsDialogEn dialog = TranslationsDialogEn.internal(_root);
	late final TranslationsProfilesEn profiles = TranslationsProfilesEn.internal(_root);
	late final TranslationsConnectionsEn connections = TranslationsConnectionsEn.internal(_root);
	late final TranslationsDiscoverEn discover = TranslationsDiscoverEn.internal(_root);
	late final TranslationsErrorsEn errors = TranslationsErrorsEn.internal(_root);
	late final TranslationsNoticesEn notices = TranslationsNoticesEn.internal(_root);
	late final TranslationsLibrariesEn libraries = TranslationsLibrariesEn.internal(_root);
	late final TranslationsAboutEn about = TranslationsAboutEn.internal(_root);
	late final TranslationsServerSelectionEn serverSelection = TranslationsServerSelectionEn.internal(_root);
	late final TranslationsHubDetailEn hubDetail = TranslationsHubDetailEn.internal(_root);
	late final TranslationsLogsEn logs = TranslationsLogsEn.internal(_root);
	late final TranslationsLicensesEn licenses = TranslationsLicensesEn.internal(_root);
	late final TranslationsNavigationEn navigation = TranslationsNavigationEn.internal(_root);
	late final TranslationsWatchlistEn watchlist = TranslationsWatchlistEn.internal(_root);
	late final TranslationsMyPleyaEn myPleya = TranslationsMyPleyaEn.internal(_root);
	late final TranslationsLiveTvEn liveTv = TranslationsLiveTvEn.internal(_root);
	late final TranslationsCollectionsEn collections = TranslationsCollectionsEn.internal(_root);
	late final TranslationsPlaylistsEn playlists = TranslationsPlaylistsEn.internal(_root);
	late final TranslationsWatchTogetherEn watchTogether = TranslationsWatchTogetherEn.internal(_root);
	late final TranslationsDownloadsEn downloads = TranslationsDownloadsEn.internal(_root);
	late final TranslationsShadersEn shaders = TranslationsShadersEn.internal(_root);
	late final TranslationsCompanionRemoteEn companionRemote = TranslationsCompanionRemoteEn.internal(_root);
	late final TranslationsVideoSettingsEn videoSettings = TranslationsVideoSettingsEn.internal(_root);
	late final TranslationsPerformanceOverlayEn performanceOverlay = TranslationsPerformanceOverlayEn.internal(_root);
	late final TranslationsExternalPlayerEn externalPlayer = TranslationsExternalPlayerEn.internal(_root);
	late final TranslationsMetadataEditEn metadataEdit = TranslationsMetadataEditEn.internal(_root);
	late final TranslationsMatchScreenEn matchScreen = TranslationsMatchScreenEn.internal(_root);
	late final TranslationsServerTasksEn serverTasks = TranslationsServerTasksEn.internal(_root);
	late final TranslationsSeerrEn seerr = TranslationsSeerrEn.internal(_root);
	late final TranslationsTautulliEn tautulli = TranslationsTautulliEn.internal(_root);
	late final TranslationsNowWatchingEn nowWatching = TranslationsNowWatchingEn.internal(_root);
	late final TranslationsTraktEn trakt = TranslationsTraktEn.internal(_root);
	late final TranslationsTrackersEn trackers = TranslationsTrackersEn.internal(_root);
	late final TranslationsAddServerEn addServer = TranslationsAddServerEn.internal(_root);
	late final TranslationsAddLocalFolderEn addLocalFolder = TranslationsAddLocalFolderEn.internal(_root);
	late final TranslationsPleyaShareEn pleyaShare = TranslationsPleyaShareEn.internal(_root);
}

// Path: states
class TranslationsStatesEn {
	TranslationsStatesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Nothing here yet'
	String get emptyTitle => 'Nothing here yet';

	/// en: 'Something went wrong'
	String get errorTitle => 'Something went wrong';

	/// en: 'You're offline'
	String get offlineTitle => 'You\'re offline';

	/// en: 'Reconnect to load this content.'
	String get offlineMessage => 'Reconnect to load this content.';
}

// Path: app
class TranslationsAppEn {
	TranslationsAppEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Pleya'
	String get title => 'Pleya';
}

// Path: auth
class TranslationsAuthEn {
	TranslationsAuthEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Sign in'
	String get signIn => 'Sign in';

	/// en: 'Sign in with Plex'
	String get signInWithPlex => 'Sign in with Plex';

	/// en: 'Show QR Code'
	String get showQRCode => 'Show QR Code';

	/// en: 'Authenticate'
	String get authenticate => 'Authenticate';

	/// en: 'Sign-in wasn't completed. Please try again.'
	String get authenticationTimeout => 'Sign-in wasn\'t completed. Please try again.';

	/// en: 'Scan this QR code to sign in'
	String get scanQRToSignIn => 'Scan this QR code to sign in';

	/// en: 'Waiting for authentication... Sign in from your browser.'
	String get waitingForAuth => 'Waiting for authentication...\nSign in from your browser.';

	/// en: 'Use browser'
	String get useBrowser => 'Use browser';

	/// en: 'or'
	String get or => 'or';

	/// en: 'Connect to Jellyfin'
	String get connectToJellyfin => 'Connect to Jellyfin';

	/// en: 'Use Quick Connect'
	String get useQuickConnect => 'Use Quick Connect';

	/// en: 'Open Quick Connect in Jellyfin and enter this code.'
	String get quickConnectInstructions => 'Open Quick Connect in Jellyfin and enter this code.';

	/// en: 'Waiting for approval…'
	String get quickConnectWaiting => 'Waiting for approval…';

	/// en: 'Cancel'
	String get quickConnectCancel => 'Cancel';

	/// en: 'Quick Connect expired. Try again.'
	String get quickConnectExpired => 'Quick Connect expired. Try again.';

	/// en: 'Choose how to sign in'
	String get chooseHowToSignIn => 'Choose how to sign in';

	/// en: 'Pleya connects to your Plex or Jellyfin media server. Pick one to get started.'
	String get chooseHowToSignInDescription => 'Pleya connects to your Plex or Jellyfin media server. Pick one to get started.';

	/// en: 'Using a Jellyfin server? Connect to Jellyfin instead'
	String get usingJellyfinInstead => 'Using a Jellyfin server? Connect to Jellyfin instead';

	/// en: 'Try again'
	String get tryAgain => 'Try again';

	/// en: 'Plex auth token'
	String get plexTokenLabel => 'Plex auth token';

	/// en: 'Enter your plex.tv token'
	String get plexTokenHint => 'Enter your plex.tv token';

	/// en: 'Authentication service is not ready yet. Try again in a moment.'
	String get serviceNotReady => 'Authentication service is not ready yet. Try again in a moment.';
}

// Path: common
class TranslationsCommonEn {
	TranslationsCommonEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'Clear'
	String get clear => 'Clear';

	/// en: 'Reset'
	String get reset => 'Reset';

	/// en: 'Later'
	String get later => 'Later';

	/// en: 'Submit'
	String get submit => 'Submit';

	/// en: 'Confirm'
	String get confirm => 'Confirm';

	/// en: 'Retry'
	String get retry => 'Retry';

	/// en: 'Details'
	String get details => 'Details';

	/// en: 'Logout'
	String get logout => 'Logout';

	/// en: 'Unknown'
	String get unknown => 'Unknown';

	/// en: 'Refresh'
	String get refresh => 'Refresh';

	/// en: 'Yes'
	String get yes => 'Yes';

	/// en: 'No'
	String get no => 'No';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Edit'
	String get edit => 'Edit';

	/// en: 'Shuffle'
	String get shuffle => 'Shuffle';

	/// en: 'Add to...'
	String get addTo => 'Add to...';

	/// en: 'Create new'
	String get createNew => 'Create new';

	/// en: 'Connect'
	String get connect => 'Connect';

	/// en: 'Disconnect'
	String get disconnect => 'Disconnect';

	/// en: 'Play'
	String get play => 'Play';

	/// en: 'Pause'
	String get pause => 'Pause';

	/// en: 'Resume'
	String get resume => 'Resume';

	/// en: 'Error'
	String get error => 'Error';

	/// en: 'Search'
	String get search => 'Search';

	/// en: 'Home'
	String get home => 'Home';

	/// en: 'Back'
	String get back => 'Back';

	/// en: 'Settings'
	String get settings => 'Settings';

	/// en: 'Mute'
	String get mute => 'Mute';

	/// en: 'OK'
	String get ok => 'OK';

	/// en: 'Off'
	String get off => 'Off';

	/// en: 'On'
	String get on => 'On';

	/// en: 'Season ${number}'
	String seasonNumber({required Object number}) => 'Season ${number}';

	/// en: 'Episode ${number} - ${title}'
	String episodeNumberTitle({required Object number, required Object title}) => 'Episode ${number} - ${title}';

	/// en: 'Chapter ${number}'
	String chapterNumber({required Object number}) => 'Chapter ${number}';

	/// en: 'Reconnect'
	String get reconnect => 'Reconnect';

	/// en: 'Exit'
	String get exit => 'Exit';

	/// en: 'View All'
	String get viewAll => 'View All';

	/// en: 'Checking network...'
	String get checkingNetwork => 'Checking network...';

	/// en: 'Refreshing servers...'
	String get refreshingServers => 'Refreshing servers...';

	/// en: 'Loading servers...'
	String get loadingServers => 'Loading servers...';

	/// en: 'Connecting to servers...'
	String get connectingToServers => 'Connecting to servers...';

	/// en: 'Starting offline mode...'
	String get startingOfflineMode => 'Starting offline mode...';

	/// en: 'Loading...'
	String get loading => 'Loading...';

	/// en: 'Fullscreen'
	String get fullscreen => 'Fullscreen';

	/// en: 'Exit fullscreen'
	String get exitFullscreen => 'Exit fullscreen';

	/// en: 'Press back again to exit'
	String get pressBackAgainToExit => 'Press back again to exit';

	/// en: 'Decrease $label'
	String decreaseValue({required Object label}) => 'Decrease ${label}';

	/// en: 'Increase $label'
	String increaseValue({required Object label}) => 'Increase ${label}';

	/// en: 'This took too long. Please try again.'
	String get timedOut => 'This took too long. Please try again.';
}

// Path: screens
class TranslationsScreensEn {
	TranslationsScreensEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Licenses'
	String get licenses => 'Licenses';

	/// en: 'Switch Profile'
	String get switchProfile => 'Switch Profile';

	/// en: 'Who's watching?'
	String get whoIsWatching => 'Who\'s watching?';

	/// en: 'Manage profiles'
	String get manageProfiles => 'Manage profiles';

	/// en: 'Subtitle Styling'
	String get subtitleStyling => 'Subtitle Styling';

	/// en: 'mpv.conf'
	String get mpvConfig => 'mpv.conf';

	/// en: 'Logs'
	String get logs => 'Logs';
}

// Path: update
class TranslationsUpdateEn {
	TranslationsUpdateEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Update Available'
	String get available => 'Update Available';

	/// en: 'Version ${version} is available'
	String versionAvailable({required Object version}) => 'Version ${version} is available';

	/// en: 'Current: ${version}'
	String currentVersion({required Object version}) => 'Current: ${version}';

	/// en: 'Skip This Version'
	String get skipVersion => 'Skip This Version';

	/// en: 'View Release'
	String get viewRelease => 'View Release';

	/// en: 'You are on the latest version'
	String get latestVersion => 'You are on the latest version';

	/// en: 'Failed to check for updates'
	String get checkFailed => 'Failed to check for updates';
}

// Path: settings
class TranslationsSettingsEn {
	TranslationsSettingsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Search settings'
	String get searchHint => 'Search settings';

	/// en: 'URL'
	String get urlLabel => 'URL';

	/// en: 'Settings'
	String get title => 'Settings';

	/// en: 'Support Pleya'
	String get supportDeveloper => 'Support Pleya';

	/// en: 'Donate via Liberapay to fund development'
	String get supportDeveloperDescription => 'Donate via Liberapay to fund development';

	/// en: 'Language'
	String get language => 'Language';

	/// en: 'Theme'
	String get theme => 'Theme';

	/// en: 'Appearance'
	String get appearance => 'Appearance';

	/// en: 'Video Playback'
	String get videoPlayback => 'Video Playback';

	/// en: 'Configure playback behavior'
	String get videoPlaybackDescription => 'Configure playback behavior';

	/// en: 'Advanced'
	String get advanced => 'Advanced';

	/// en: 'Episode Poster Style'
	String get episodePosterMode => 'Episode Poster Style';

	/// en: 'Series Poster'
	String get seriesPoster => 'Series Poster';

	/// en: 'Season Poster'
	String get seasonPoster => 'Season Poster';

	/// en: 'Thumbnail'
	String get episodeThumbnail => 'Thumbnail';

	/// en: 'Display featured content carousel on home screen'
	String get showHeroSectionDescription => 'Display featured content carousel on home screen';

	/// en: 'Seconds'
	String get secondsLabel => 'Seconds';

	/// en: 'Minutes'
	String get minutesLabel => 'Minutes';

	/// en: 's'
	String get secondsShort => 's';

	/// en: 'm'
	String get minutesShort => 'm';

	/// en: 'Enter duration (${min}-${max})'
	String durationHint({required Object min, required Object max}) => 'Enter duration (${min}-${max})';

	/// en: 'System'
	String get systemTheme => 'System';

	/// en: 'Light'
	String get lightTheme => 'Light';

	/// en: 'Dark'
	String get darkTheme => 'Dark';

	/// en: 'OLED'
	String get oledTheme => 'OLED';

	/// en: 'Library Density'
	String get libraryDensity => 'Library Density';

	/// en: 'Compact'
	String get compact => 'Compact';

	/// en: 'Comfortable'
	String get comfortable => 'Comfortable';

	/// en: 'View Mode'
	String get viewMode => 'View Mode';

	/// en: 'Grid'
	String get gridView => 'Grid';

	/// en: 'List'
	String get listView => 'List';

	/// en: 'Show Hero Section'
	String get showHeroSection => 'Show Hero Section';

	/// en: 'Hover-expand cards'
	String get hoverExpandCards => 'Hover-expand cards';

	/// en: 'Grow a preview card with quick actions when hovering a poster'
	String get hoverExpandCardsDescription => 'Grow a preview card with quick actions when hovering a poster';

	/// en: 'Continue Watching Action'
	String get continueWatchingAction => 'Continue Watching Action';

	/// en: 'Play'
	String get continueWatchingPlay => 'Play';

	/// en: 'Open Details'
	String get continueWatchingDetails => 'Open Details';

	/// en: 'Episode Action'
	String get episodeAction => 'Episode Action';

	/// en: 'Play'
	String get episodePlay => 'Play';

	/// en: 'Open Details'
	String get episodeDetails => 'Open Details';

	/// en: 'Use Home Layout'
	String get useGlobalHubs => 'Use Home Layout';

	/// en: 'Show unified home hubs. Otherwise use library recommendations.'
	String get useGlobalHubsDescription => 'Show unified home hubs. Otherwise use library recommendations.';

	/// en: 'Show Server Name on Hubs'
	String get showServerNameOnHubs => 'Show Server Name on Hubs';

	/// en: 'Always show server names in hub titles.'
	String get showServerNameOnHubsDescription => 'Always show server names in hub titles.';

	/// en: 'Group Libraries by Server'
	String get groupLibrariesByServer => 'Group Libraries by Server';

	/// en: 'Group sidebar libraries under each media server.'
	String get groupLibrariesByServerDescription => 'Group sidebar libraries under each media server.';

	/// en: 'Always Keep Sidebar Open'
	String get alwaysKeepSidebarOpen => 'Always Keep Sidebar Open';

	/// en: 'Sidebar stays expanded and content area adjusts to fit'
	String get alwaysKeepSidebarOpenDescription => 'Sidebar stays expanded and content area adjusts to fit';

	/// en: 'Show Unwatched Count'
	String get showUnwatchedCount => 'Show Unwatched Count';

	/// en: 'Display unwatched episode count on shows and seasons'
	String get showUnwatchedCountDescription => 'Display unwatched episode count on shows and seasons';

	/// en: 'Show Episode Number on Cards'
	String get showEpisodeNumberOnCards => 'Show Episode Number on Cards';

	/// en: 'Show season and episode number on episode cards'
	String get showEpisodeNumberOnCardsDescription => 'Show season and episode number on episode cards';

	/// en: 'Show Season Posters on Tabs'
	String get showSeasonPostersOnTabs => 'Show Season Posters on Tabs';

	/// en: 'Show each season's poster above its tab'
	String get showSeasonPostersOnTabsDescription => 'Show each season\'s poster above its tab';

	/// en: 'Full TV Cards'
	String get tvFullCardLayout => 'Full TV Cards';

	/// en: 'Use image-only TV cards with actor names overlaid'
	String get tvFullCardLayoutDescription => 'Use image-only TV cards with actor names overlaid';

	/// en: 'Focus Glow'
	String get focusGlow => 'Focus Glow';

	/// en: 'Draw a soft glow around the focused card'
	String get focusGlowDescription => 'Draw a soft glow around the focused card';

	/// en: 'Visual Effects'
	String get visualEffects => 'Visual Effects';

	/// en: 'Auto'
	String get visualEffectsAuto => 'Auto';

	/// en: 'Reduce effects automatically on low-power devices'
	String get visualEffectsAutoDescription => 'Reduce effects automatically on low-power devices';

	/// en: 'Full'
	String get visualEffectsFull => 'Full';

	/// en: 'Reduced'
	String get visualEffectsReduced => 'Reduced';

	/// en: 'Fewer animations and lower-resolution artwork'
	String get visualEffectsReducedDescription => 'Fewer animations and lower-resolution artwork';

	/// en: 'Hide Spoilers for Unwatched Episodes'
	String get hideSpoilers => 'Hide Spoilers for Unwatched Episodes';

	/// en: 'Blur thumbnails and descriptions for unwatched episodes'
	String get hideSpoilersDescription => 'Blur thumbnails and descriptions for unwatched episodes';

	/// en: 'Player Backend'
	String get playerBackend => 'Player Backend';

	/// en: 'ExoPlayer (Recommended)'
	String get exoPlayer => 'ExoPlayer (Recommended)';

	/// en: 'mpv'
	String get mpv => 'mpv';

	/// en: 'Hardware Decoding'
	String get hardwareDecoding => 'Hardware Decoding';

	/// en: 'Use hardware acceleration when available'
	String get hardwareDecodingDescription => 'Use hardware acceleration when available';

	/// en: 'Buffer Size'
	String get bufferSize => 'Buffer Size';

	/// en: '${size}MB'
	String bufferSizeMB({required Object size}) => '${size}MB';

	/// en: 'Auto (Recommended)'
	String get bufferSizeAuto => 'Auto (Recommended)';

	/// en: '${heap}MB memory available. A ${size}MB buffer may affect playback.'
	String bufferSizeWarning({required Object heap, required Object size}) => '${heap}MB memory available. A ${size}MB buffer may affect playback.';

	/// en: 'Default Quality'
	String get defaultQualityTitle => 'Default Quality';

	/// en: 'Used when starting playback. Lower values reduce bandwidth.'
	String get defaultQualityDescription => 'Used when starting playback. Lower values reduce bandwidth.';

	/// en: 'Subtitle Styling'
	String get subtitleStyling => 'Subtitle Styling';

	/// en: 'Customize subtitle appearance'
	String get subtitleStylingDescription => 'Customize subtitle appearance';

	/// en: 'Small Skip Duration'
	String get smallSkipDuration => 'Small Skip Duration';

	/// en: 'Large Skip Duration'
	String get largeSkipDuration => 'Large Skip Duration';

	/// en: 'Rewind on Resume'
	String get rewindOnResume => 'Rewind on Resume';

	/// en: '${seconds} seconds'
	String secondsUnit({required Object seconds}) => '${seconds} seconds';

	/// en: 'Default Sleep Timer'
	String get defaultSleepTimer => 'Default Sleep Timer';

	/// en: '${minutes} minutes'
	String minutesUnit({required Object minutes}) => '${minutes} minutes';

	/// en: 'Remember track selections per show/movie'
	String get rememberTrackSelections => 'Remember track selections per show/movie';

	/// en: 'Start the next episode in the audio and subtitle language you last picked by hand. Syncs to your other Apple devices via iCloud.'
	String get rememberTrackSelectionsDescription => 'Start the next episode in the audio and subtitle language you last picked by hand. Syncs to your other Apple devices via iCloud.';

	/// en: 'Also save the language to Plex'
	String get writeSeriesLanguageToServer => 'Also save the language to Plex';

	/// en: 'Writes the language onto the show in Plex, so Android, Windows and the official Plex apps follow it too. Overwrites what you set by hand there.'
	String get writeSeriesLanguageToServerDescription => 'Writes the language onto the show in Plex, so Android, Windows and the official Plex apps follow it too. Overwrites what you set by hand there.';

	/// en: 'Show chapter markers on seek bar'
	String get showChapterMarkersOnTimeline => 'Show chapter markers on seek bar';

	/// en: 'Segment the seek bar at chapter boundaries'
	String get showChapterMarkersOnTimelineDescription => 'Segment the seek bar at chapter boundaries';

	/// en: 'Click on video to toggle play/pause'
	String get clickVideoTogglesPlayback => 'Click on video to toggle play/pause';

	/// en: 'Click video to play/pause instead of showing controls.'
	String get clickVideoTogglesPlaybackDescription => 'Click video to play/pause instead of showing controls.';

	/// en: 'Video Player Controls'
	String get videoPlayerControls => 'Video Player Controls';

	/// en: 'Keyboard Shortcuts'
	String get keyboardShortcuts => 'Keyboard Shortcuts';

	/// en: 'Customize keyboard shortcuts'
	String get keyboardShortcutsDescription => 'Customize keyboard shortcuts';

	/// en: 'Video Player Navigation'
	String get videoPlayerNavigation => 'Video Player Navigation';

	/// en: 'Use arrow keys to navigate video player controls'
	String get videoPlayerNavigationDescription => 'Use arrow keys to navigate video player controls';

	/// en: 'Watch Together Relay'
	String get watchTogetherRelay => 'Watch Together Relay';

	/// en: 'Set a custom relay. Everyone must use the same server.'
	String get watchTogetherRelayDescription => 'Set a custom relay. Everyone must use the same server.';

	/// en: 'https://my-relay.example.com'
	String get watchTogetherRelayHint => 'https://my-relay.example.com';

	/// en: 'Crash Reporting'
	String get crashReporting => 'Crash Reporting';

	/// en: 'Send crash reports to help improve the app'
	String get crashReportingDescription => 'Send crash reports to help improve the app';

	/// en: 'Debug Logging'
	String get debugLogging => 'Debug Logging';

	/// en: 'Enable detailed logging for troubleshooting'
	String get debugLoggingDescription => 'Enable detailed logging for troubleshooting';

	/// en: 'View Logs'
	String get viewLogs => 'View Logs';

	/// en: 'View application logs'
	String get viewLogsDescription => 'View application logs';

	/// en: 'Clear Cache'
	String get clearCache => 'Clear Cache';

	/// en: 'Clear cached images and data. Content may load slower.'
	String get clearCacheDescription => 'Clear cached images and data. Content may load slower.';

	/// en: 'Cache cleared successfully'
	String get clearCacheSuccess => 'Cache cleared successfully';

	/// en: 'Reset Settings'
	String get resetSettings => 'Reset Settings';

	/// en: 'Restore default settings. This can't be undone.'
	String get resetSettingsDescription => 'Restore default settings. This can\'t be undone.';

	/// en: 'Settings reset successfully'
	String get resetSettingsSuccess => 'Settings reset successfully';

	/// en: 'Backup'
	String get backup => 'Backup';

	/// en: 'Export Settings'
	String get exportSettings => 'Export Settings';

	/// en: 'Save your preferences to a file'
	String get exportSettingsDescription => 'Save your preferences to a file';

	/// en: 'Settings exported'
	String get exportSettingsSuccess => 'Settings exported';

	/// en: 'Could not export settings'
	String get exportSettingsFailed => 'Could not export settings';

	/// en: 'Import Settings'
	String get importSettings => 'Import Settings';

	/// en: 'Restore preferences from a file'
	String get importSettingsDescription => 'Restore preferences from a file';

	/// en: 'This will replace your current settings. Continue?'
	String get importSettingsConfirm => 'This will replace your current settings. Continue?';

	/// en: 'Settings imported'
	String get importSettingsSuccess => 'Settings imported';

	/// en: 'Could not import settings'
	String get importSettingsFailed => 'Could not import settings';

	/// en: 'This file isn't a valid Pleya settings export'
	String get importSettingsInvalidFile => 'This file isn\'t a valid Pleya settings export';

	/// en: 'Sign in before importing settings'
	String get importSettingsNoUser => 'Sign in before importing settings';

	/// en: 'Sync Settings via iCloud'
	String get icloudSync => 'Sync Settings via iCloud';

	/// en: 'Keep your preferences in sync across your Apple devices'
	String get icloudSyncDescription => 'Keep your preferences in sync across your Apple devices';

	/// en: 'Sign in to iCloud on this device to sync settings'
	String get icloudSyncUnavailable => 'Sign in to iCloud on this device to sync settings';

	/// en: 'This device can't sync settings through iCloud'
	String get icloudSyncNotSupported => 'This device can\'t sync settings through iCloud';

	/// en: 'Couldn't reach iCloud. Your settings will sync once it's back.'
	String get icloudSyncError => 'Couldn\'t reach iCloud. Your settings will sync once it\'s back.';

	/// en: 'Some settings were too large to sync and were skipped'
	String get icloudSyncWarning => 'Some settings were too large to sync and were skipped';

	/// en: 'Could not turn on iCloud settings sync'
	String get icloudSyncEnableFailed => 'Could not turn on iCloud settings sync';

	/// en: 'Shortcuts reset to defaults'
	String get shortcutsReset => 'Shortcuts reset to defaults';

	/// en: 'About'
	String get about => 'About';

	/// en: 'App information and licenses'
	String get aboutDescription => 'App information and licenses';

	/// en: 'Updates'
	String get updates => 'Updates';

	/// en: 'Update Available'
	String get updateAvailable => 'Update Available';

	/// en: 'Check for Updates'
	String get checkForUpdates => 'Check for Updates';

	/// en: 'Automatically check for updates on startup'
	String get autoCheckUpdatesOnStartup => 'Automatically check for updates on startup';

	/// en: 'Notify when an update is available at launch'
	String get autoCheckUpdatesOnStartupDescription => 'Notify when an update is available at launch';

	/// en: 'Please enter a valid number'
	String get validationErrorEnterNumber => 'Please enter a valid number';

	/// en: 'Duration must be between ${min} and ${max} ${unit}'
	String validationErrorDuration({required Object min, required Object max, required Object unit}) => 'Duration must be between ${min} and ${max} ${unit}';

	/// en: 'Shortcut already assigned to ${action}'
	String shortcutAlreadyAssigned({required Object action}) => 'Shortcut already assigned to ${action}';

	/// en: 'Shortcut updated for ${action}'
	String shortcutUpdated({required Object action}) => 'Shortcut updated for ${action}';

	/// en: 'Auto Skip'
	String get autoSkip => 'Auto Skip';

	/// en: 'Auto Skip Intro'
	String get autoSkipIntro => 'Auto Skip Intro';

	/// en: 'Automatically skip intro markers in episodes after a few seconds'
	String get autoSkipIntroDescription => 'Automatically skip intro markers in episodes after a few seconds';

	/// en: 'Auto Skip Credits'
	String get autoSkipCredits => 'Auto Skip Credits';

	/// en: 'Automatically skip credits and play next episode'
	String get autoSkipCreditsDescription => 'Automatically skip credits and play next episode';

	/// en: 'Force Fallback Markers'
	String get forceSkipMarkerFallback => 'Force Fallback Markers';

	/// en: 'Use chapter title patterns even when Plex has markers'
	String get forceSkipMarkerFallbackDescription => 'Use chapter title patterns even when Plex has markers';

	/// en: 'Auto Skip Delay'
	String get autoSkipDelay => 'Auto Skip Delay';

	/// en: 'Wait ${seconds} seconds before auto-skipping'
	String autoSkipDelayDescription({required Object seconds}) => 'Wait ${seconds} seconds before auto-skipping';

	/// en: 'Intro Marker Pattern'
	String get introPattern => 'Intro Marker Pattern';

	/// en: 'Regex pattern to match intro markers in chapter titles'
	String get introPatternDescription => 'Regex pattern to match intro markers in chapter titles';

	/// en: 'Credits Marker Pattern'
	String get creditsPattern => 'Credits Marker Pattern';

	/// en: 'Regex pattern to match credits markers in chapter titles'
	String get creditsPatternDescription => 'Regex pattern to match credits markers in chapter titles';

	/// en: 'Invalid regular expression'
	String get invalidRegex => 'Invalid regular expression';

	/// en: 'Downloads'
	String get downloads => 'Downloads';

	/// en: 'Choose where to store downloaded content'
	String get downloadLocationDescription => 'Choose where to store downloaded content';

	/// en: 'Default (App Storage)'
	String get downloadLocationDefault => 'Default (App Storage)';

	/// en: 'Custom Location'
	String get downloadLocationCustom => 'Custom Location';

	/// en: 'Select Folder'
	String get selectFolder => 'Select Folder';

	/// en: 'Reset to Default'
	String get resetToDefault => 'Reset to Default';

	/// en: 'Current: ${path}'
	String currentPath({required Object path}) => 'Current: ${path}';

	/// en: 'Download location changed'
	String get downloadLocationChanged => 'Download location changed';

	/// en: 'Download location reset to default'
	String get downloadLocationReset => 'Download location reset to default';

	/// en: 'Selected folder is not writable'
	String get downloadLocationInvalid => 'Selected folder is not writable';

	/// en: 'Failed to select folder'
	String get downloadLocationSelectError => 'Failed to select folder';

	/// en: 'Download on WiFi only'
	String get downloadOnWifiOnly => 'Download on WiFi only';

	/// en: 'Prevent downloads when on cellular data'
	String get downloadOnWifiOnlyDescription => 'Prevent downloads when on cellular data';

	/// en: 'Auto-remove watched downloads'
	String get autoRemoveWatchedDownloads => 'Auto-remove watched downloads';

	/// en: 'Delete watched downloads automatically'
	String get autoRemoveWatchedDownloadsDescription => 'Delete watched downloads automatically';

	/// en: 'Downloads are blocked on cellular. Use WiFi or change the setting.'
	String get cellularDownloadBlocked => 'Downloads are blocked on cellular. Use WiFi or change the setting.';

	/// en: 'Maximum Volume'
	String get maxVolume => 'Maximum Volume';

	/// en: 'Allow volume boost above 100% for quiet media'
	String get maxVolumeDescription => 'Allow volume boost above 100% for quiet media';

	/// en: '${percent}%'
	String maxVolumePercent({required Object percent}) => '${percent}%';

	/// en: 'Discord Rich Presence'
	String get discordRichPresence => 'Discord Rich Presence';

	/// en: 'Show what you're watching on Discord'
	String get discordRichPresenceDescription => 'Show what you\'re watching on Discord';

	/// en: 'Trakt'
	String get trakt => 'Trakt';

	/// en: 'Sync watch history with Trakt'
	String get traktDescription => 'Sync watch history with Trakt';

	/// en: 'Trackers'
	String get trackers => 'Trackers';

	/// en: 'Sync progress to Trakt, MyAnimeList, AniList, and Simkl'
	String get trackersDescription => 'Sync progress to Trakt, MyAnimeList, AniList, and Simkl';

	/// en: 'Requests'
	String get requests => 'Requests';

	/// en: 'Request movies and shows via Jellyseerr or Overseerr'
	String get requestsDescription => 'Request movies and shows via Jellyseerr or Overseerr';

	/// en: 'Library Visibility'
	String get libraryVisibility => 'Library Visibility';

	/// en: 'Choose which libraries appear in the menu'
	String get libraryVisibilityDescription => 'Choose which libraries appear in the menu';

	/// en: 'Home Layout'
	String get homeLayout => 'Home Layout';

	/// en: 'Reorder or hide the rows on the home screen'
	String get homeLayoutDescription => 'Reorder or hide the rows on the home screen';

	/// en: 'Open the home screen once so the rows can be loaded'
	String get homeLayoutEmpty => 'Open the home screen once so the rows can be loaded';

	/// en: 'Move up'
	String get homeLayoutMoveUp => 'Move up';

	/// en: 'Move down'
	String get homeLayoutMoveDown => 'Move down';

	/// en: 'Companion Remote Server'
	String get companionRemoteServer => 'Companion Remote Server';

	/// en: 'Allow mobile devices on your network to control this app'
	String get companionRemoteServerDescription => 'Allow mobile devices on your network to control this app';

	/// en: 'Auto Picture-in-Picture'
	String get autoPip => 'Auto Picture-in-Picture';

	/// en: 'Enter picture-in-picture when leaving during playback'
	String get autoPipDescription => 'Enter picture-in-picture when leaving during playback';

	/// en: 'Match Content Frame Rate'
	String get matchContentFrameRate => 'Match Content Frame Rate';

	/// en: 'Match display refresh rate to video content'
	String get matchContentFrameRateDescription => 'Match display refresh rate to video content';

	/// en: 'Match Refresh Rate'
	String get matchRefreshRate => 'Match Refresh Rate';

	/// en: 'Match display refresh rate in fullscreen'
	String get matchRefreshRateDescription => 'Match display refresh rate in fullscreen';

	/// en: 'Match Dynamic Range'
	String get matchDynamicRange => 'Match Dynamic Range';

	/// en: 'Switch HDR on for HDR content, then back to SDR'
	String get matchDynamicRangeDescription => 'Switch HDR on for HDR content, then back to SDR';

	/// en: 'Display Switch Delay'
	String get displaySwitchDelay => 'Display Switch Delay';

	/// en: 'Tunneled Playback'
	String get tunneledPlayback => 'Tunneled Playback';

	/// en: 'Use video tunneling. Disable if HDR playback shows black video.'
	String get tunneledPlaybackDescription => 'Use video tunneling. Disable if HDR playback shows black video.';

	/// en: 'Dolby Vision Conversion'
	String get dvConversionMode => 'Dolby Vision Conversion';

	/// en: 'Choose how ExoPlayer handles Dolby Vision Profile 7 files.'
	String get dvConversionModeDescription => 'Choose how ExoPlayer handles Dolby Vision Profile 7 files.';

	/// en: 'Auto'
	String get dvConversionAuto => 'Auto';

	/// en: 'Native / Disabled'
	String get dvConversionNative => 'Native / Disabled';

	/// en: 'P7 → P8.1'
	String get dvConversionDv81 => 'P7 → P8.1';

	/// en: 'P7 → HEVC'
	String get dvConversionHevcStrip => 'P7 → HEVC';

	/// en: 'Use device capability detection and normal fallback behavior'
	String get dvConversionAutoDescription => 'Use device capability detection and normal fallback behavior';

	/// en: 'Force native DV7 and suppress DV conversion retry'
	String get dvConversionNativeDescription => 'Force native DV7 and suppress DV conversion retry';

	/// en: 'Force inline RPU conversion to Dolby Vision profile 8.1'
	String get dvConversionDv81Description => 'Force inline RPU conversion to Dolby Vision profile 8.1';

	/// en: 'Strip Dolby Vision RPU/EL layers and present plain HEVC'
	String get dvConversionHevcStripDescription => 'Strip Dolby Vision RPU/EL layers and present plain HEVC';

	/// en: 'Ask for profile on app open'
	String get requireProfileSelectionOnOpen => 'Ask for profile on app open';

	/// en: 'Show profile selection every time the app is opened'
	String get requireProfileSelectionOnOpenDescription => 'Show profile selection every time the app is opened';

	/// en: 'Force TV mode'
	String get forceTvMode => 'Force TV mode';

	/// en: 'Force TV layout. For devices that don't auto-detect. Requires restart.'
	String get forceTvModeDescription => 'Force TV layout. For devices that don\'t auto-detect. Requires restart.';

	/// en: 'Start in fullscreen'
	String get startInFullscreen => 'Start in fullscreen';

	/// en: 'Open Pleya in fullscreen mode at launch'
	String get startInFullscreenDescription => 'Open Pleya in fullscreen mode at launch';

	/// en: 'Exit fullscreen on player close'
	String get exitFullscreenOnPlayerClose => 'Exit fullscreen on player close';

	/// en: 'Automatically exit fullscreen when closing the video player'
	String get exitFullscreenOnPlayerCloseDescription => 'Automatically exit fullscreen when closing the video player';

	/// en: 'Auto-Hide Performance Overlay'
	String get autoHidePerformanceOverlay => 'Auto-Hide Performance Overlay';

	/// en: 'Fade the performance overlay with the playback controls'
	String get autoHidePerformanceOverlayDescription => 'Fade the performance overlay with the playback controls';

	/// en: 'Show Navigation Bar Labels'
	String get showNavBarLabels => 'Show Navigation Bar Labels';

	/// en: 'Display text labels under navigation bar icons'
	String get showNavBarLabelsDescription => 'Display text labels under navigation bar icons';

	/// en: 'Startup Section'
	String get startupSection => 'Startup Section';

	/// en: 'Choose which section Pleya opens to when it starts'
	String get startupSectionDescription => 'Choose which section Pleya opens to when it starts';

	/// en: 'Default to Favorite Channels'
	String get liveTvDefaultFavorites => 'Default to Favorite Channels';

	/// en: 'Show only favorite channels when opening Live TV'
	String get liveTvDefaultFavoritesDescription => 'Show only favorite channels when opening Live TV';

	/// en: 'Display'
	String get display => 'Display';

	/// en: 'Home Screen'
	String get homeScreen => 'Home Screen';

	/// en: 'Navigation'
	String get navigation => 'Navigation';

	/// en: 'Window'
	String get window => 'Window';

	/// en: 'Content'
	String get content => 'Content';

	/// en: 'Player'
	String get player => 'Player';

	/// en: 'Subtitles & Configuration'
	String get subtitlesAndConfig => 'Subtitles & Configuration';

	/// en: 'Seek & Timing'
	String get seekAndTiming => 'Seek & Timing';

	/// en: 'Audio'
	String get audio => 'Audio';

	/// en: 'Shift audio relative to video for every title'
	String get audioSyncOffsetDescription => 'Shift audio relative to video for every title';

	/// en: 'Behavior'
	String get behavior => 'Behavior';

	/// en: 'Personalized recommendations'
	String get personalizedRecommendations => 'Personalized recommendations';

	/// en: 'Learn your taste on this device to suggest Top Picks and more. Nothing leaves your device.'
	String get personalizedRecommendationsDescription => 'Learn your taste on this device to suggest Top Picks and more. Nothing leaves your device.';

	/// en: 'App & playback'
	String get sectionLibrary => 'App & playback';
}

// Path: search
class TranslationsSearchEn {
	TranslationsSearchEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Search movies, shows, music...'
	String get hint => 'Search movies, shows, music...';

	/// en: 'Try a different search term'
	String get tryDifferentTerm => 'Try a different search term';

	/// en: 'Search your media'
	String get searchYourMedia => 'Search your media';

	/// en: 'Enter a title, actor, or keyword'
	String get enterTitleActorOrKeyword => 'Enter a title, actor, or keyword';

	/// en: 'Recent searches'
	String get recentSearches => 'Recent searches';

	/// en: 'Clear'
	String get clearHistory => 'Clear';

	late final TranslationsSearchFiltersEn filters = TranslationsSearchFiltersEn.internal(_root);

	/// en: 'Search failed'
	String get errorTitle => 'Search failed';

	/// en: 'Couldn't reach your servers. Check your connection and try again.'
	String get errorNetwork => 'Couldn\'t reach your servers. Check your connection and try again.';

	/// en: 'No servers available'
	String get noServersTitle => 'No servers available';

	/// en: 'Add or connect a server to search your media.'
	String get noServersBody => 'Add or connect a server to search your media.';

	/// en: 'Voice search'
	String get voiceSearch => 'Voice search';
}

// Path: hotkeys
class TranslationsHotkeysEn {
	TranslationsHotkeysEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Set Shortcut for ${actionName}'
	String setShortcutFor({required Object actionName}) => 'Set Shortcut for ${actionName}';

	/// en: 'Clear shortcut'
	String get clearShortcut => 'Clear shortcut';

	/// en: 'No shortcut set'
	String get noShortcutSet => 'No shortcut set';

	/// en: 'Current shortcut:'
	String get currentShortcut => 'Current shortcut:';

	late final TranslationsHotkeysActionsEn actions = TranslationsHotkeysActionsEn.internal(_root);
}

// Path: fileInfo
class TranslationsFileInfoEn {
	TranslationsFileInfoEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'File Info'
	String get title => 'File Info';

	/// en: 'Video'
	String get video => 'Video';

	/// en: 'Audio'
	String get audio => 'Audio';

	/// en: 'File'
	String get file => 'File';

	/// en: 'Advanced'
	String get advanced => 'Advanced';

	/// en: 'Codec'
	String get codec => 'Codec';

	/// en: 'Resolution'
	String get resolution => 'Resolution';

	/// en: 'Bitrate'
	String get bitrate => 'Bitrate';

	/// en: 'Frame Rate'
	String get frameRate => 'Frame Rate';

	/// en: 'Aspect Ratio'
	String get aspectRatio => 'Aspect Ratio';

	/// en: 'Profile'
	String get profile => 'Profile';

	/// en: 'Bit Depth'
	String get bitDepth => 'Bit Depth';

	/// en: 'Color Space'
	String get colorSpace => 'Color Space';

	/// en: 'Color Range'
	String get colorRange => 'Color Range';

	/// en: 'Color Primaries'
	String get colorPrimaries => 'Color Primaries';

	/// en: 'Chroma Subsampling'
	String get chromaSubsampling => 'Chroma Subsampling';

	/// en: 'Channels'
	String get channels => 'Channels';

	/// en: 'Subtitles'
	String get subtitles => 'Subtitles';

	/// en: 'Overall Bitrate'
	String get overallBitrate => 'Overall Bitrate';

	/// en: 'Path'
	String get path => 'Path';

	/// en: 'Size'
	String get size => 'Size';

	/// en: 'Container'
	String get container => 'Container';

	/// en: 'Duration'
	String get duration => 'Duration';

	/// en: 'Optimized for Streaming'
	String get optimizedForStreaming => 'Optimized for Streaming';

	/// en: '64-bit Offsets'
	String get has64bitOffsets => '64-bit Offsets';
}

// Path: mediaMenu
class TranslationsMediaMenuEn {
	TranslationsMediaMenuEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Mark as Watched'
	String get markAsWatched => 'Mark as Watched';

	/// en: 'Mark as Unwatched'
	String get markAsUnwatched => 'Mark as Unwatched';

	/// en: 'Remove from Continue Watching'
	String get removeFromContinueWatching => 'Remove from Continue Watching';

	/// en: 'View details'
	String get viewDetails => 'View details';

	/// en: 'Go to series'
	String get goToSeries => 'Go to series';

	/// en: 'Shuffle Play'
	String get shufflePlay => 'Shuffle Play';

	/// en: 'Shuffle not available offline'
	String get shuffleNotAvailableOffline => 'Shuffle not available offline';

	/// en: 'File Info'
	String get fileInfo => 'File Info';

	/// en: 'Delete from server'
	String get deleteFromServer => 'Delete from server';

	/// en: 'Delete this media and its files from your server?'
	String get confirmDelete => 'Delete this media and its files from your server?';

	/// en: 'This includes all episodes and their files.'
	String get deleteMultipleWarning => 'This includes all episodes and their files.';

	/// en: 'Media item deleted successfully'
	String get mediaDeletedSuccessfully => 'Media item deleted successfully';

	/// en: 'Failed to delete media item'
	String get mediaFailedToDelete => 'Failed to delete media item';

	/// en: 'Rate'
	String get rate => 'Rate';

	/// en: 'Play from Beginning'
	String get playFromBeginning => 'Play from Beginning';

	/// en: 'Play Version...'
	String get playVersion => 'Play Version...';
}

// Path: rateSheet
class TranslationsRateSheetEn {
	TranslationsRateSheetEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Rate'
	String get title => 'Rate';

	/// en: 'Server'
	String get server => 'Server';

	/// en: '${rating} / 5'
	String starValue({required Object rating}) => '${rating} / 5';

	/// en: '${score} / 10'
	String scoreValue({required Object score}) => '${score} / 10';

	/// en: 'Set a score'
	String get setScore => 'Set a score';

	/// en: 'Not rated'
	String get notRated => 'Not rated';

	/// en: 'Liked'
	String get liked => 'Liked';

	/// en: 'Not liked'
	String get notLiked => 'Not liked';

	/// en: 'Saved'
	String get saved => 'Saved';

	/// en: 'No match found'
	String get notAvailable => 'No match found';

	/// en: 'Connect a tracker in Settings to rate there.'
	String get noConnectedTrackers => 'Connect a tracker in Settings to rate there.';
}

// Path: accessibility
class TranslationsAccessibilityEn {
	TranslationsAccessibilityEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '${title}, movie'
	String mediaCardMovie({required Object title}) => '${title}, movie';

	/// en: '${title}, TV show'
	String mediaCardShow({required Object title}) => '${title}, TV show';

	/// en: '${title}, ${episodeInfo}'
	String mediaCardEpisode({required Object title, required Object episodeInfo}) => '${title}, ${episodeInfo}';

	/// en: '${title}, ${seasonInfo}'
	String mediaCardSeason({required Object title, required Object seasonInfo}) => '${title}, ${seasonInfo}';

	/// en: 'watched'
	String get mediaCardWatched => 'watched';

	/// en: '${percent} percent watched'
	String mediaCardPartiallyWatched({required Object percent}) => '${percent} percent watched';

	/// en: 'unwatched'
	String get mediaCardUnwatched => 'unwatched';

	/// en: 'Tap to play'
	String get tapToPlay => 'Tap to play';
}

// Path: tooltips
class TranslationsTooltipsEn {
	TranslationsTooltipsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Shuffle play'
	String get shufflePlay => 'Shuffle play';

	/// en: 'Play trailer'
	String get playTrailer => 'Play trailer';

	/// en: 'Mark as watched'
	String get markAsWatched => 'Mark as watched';

	/// en: 'Mark as unwatched'
	String get markAsUnwatched => 'Mark as unwatched';
}

// Path: videoControls
class TranslationsVideoControlsEn {
	TranslationsVideoControlsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Audio'
	String get audioLabel => 'Audio';

	/// en: 'Subtitles'
	String get subtitlesLabel => 'Subtitles';

	/// en: 'Reset to 0ms'
	String get resetToZero => 'Reset to 0ms';

	/// en: '+${amount}${unit}'
	String addTime({required Object amount, required Object unit}) => '+${amount}${unit}';

	/// en: '-${amount}${unit}'
	String minusTime({required Object amount, required Object unit}) => '-${amount}${unit}';

	/// en: '${label} plays later'
	String playsLater({required Object label}) => '${label} plays later';

	/// en: '${label} plays earlier'
	String playsEarlier({required Object label}) => '${label} plays earlier';

	/// en: 'No offset'
	String get noOffset => 'No offset';

	/// en: 'Letterbox'
	String get letterbox => 'Letterbox';

	/// en: 'Fill screen'
	String get fillScreen => 'Fill screen';

	/// en: 'Stretch'
	String get stretch => 'Stretch';

	/// en: 'Lock rotation'
	String get lockRotation => 'Lock rotation';

	/// en: 'Unlock rotation'
	String get unlockRotation => 'Unlock rotation';

	/// en: 'Timer Active'
	String get timerActive => 'Timer Active';

	/// en: 'Playback will pause in ${duration}'
	String playbackWillPauseIn({required Object duration}) => 'Playback will pause in ${duration}';

	/// en: 'End of current video'
	String get sleepTimerEndOfVideo => 'End of current video';

	/// en: 'Stop at'
	String get sleepTimerStopAtHeader => 'Stop at';

	/// en: 'Timer'
	String get sleepTimerDurationHeader => 'Timer';

	/// en: 'Playback will pause at the end of this video'
	String get playbackWillPauseAtEnd => 'Playback will pause at the end of this video';

	/// en: 'Still watching?'
	String get stillWatching => 'Still watching?';

	/// en: 'Pausing in ${seconds}s'
	String pausingIn({required Object seconds}) => 'Pausing in ${seconds}s';

	/// en: 'Continue'
	String get continueWatching => 'Continue';

	/// en: 'Auto-Play Next'
	String get autoPlayNext => 'Auto-Play Next';

	/// en: 'Play Next'
	String get playNext => 'Play Next';

	/// en: 'Next Episode'
	String get nextEpisode => 'Next Episode';

	/// en: 'Skip Intro'
	String get skipIntro => 'Skip Intro';

	/// en: 'Skip Credits'
	String get skipCredits => 'Skip Credits';

	/// en: 'Play'
	String get playButton => 'Play';

	/// en: 'Pause'
	String get pauseButton => 'Pause';

	/// en: 'Seek backward ${seconds} seconds'
	String seekBackwardButton({required Object seconds}) => 'Seek backward ${seconds} seconds';

	/// en: 'Seek forward ${seconds} seconds'
	String seekForwardButton({required Object seconds}) => 'Seek forward ${seconds} seconds';

	/// en: 'Previous episode'
	String get previousButton => 'Previous episode';

	/// en: 'Next episode'
	String get nextButton => 'Next episode';

	/// en: 'Previous chapter'
	String get previousChapterButton => 'Previous chapter';

	/// en: 'Next chapter'
	String get nextChapterButton => 'Next chapter';

	/// en: 'Mute'
	String get muteButton => 'Mute';

	/// en: 'Unmute'
	String get unmuteButton => 'Unmute';

	/// en: 'Playback Settings'
	String get settingsButton => 'Playback Settings';

	/// en: 'Audio & Subtitles'
	String get tracksButton => 'Audio & Subtitles';

	/// en: 'Chapters'
	String get chaptersButton => 'Chapters';

	/// en: 'Video versions'
	String get versionsButton => 'Video versions';

	/// en: 'Version & Quality'
	String get versionQualityButton => 'Version & Quality';

	/// en: 'Version'
	String get versionColumnHeader => 'Version';

	/// en: 'Quality'
	String get qualityColumnHeader => 'Quality';

	/// en: 'Original'
	String get qualityOriginal => 'Original';

	/// en: '${resolution}p ${bitrate} Mbps'
	String qualityPresetLabel({required Object resolution, required Object bitrate}) => '${resolution}p ${bitrate} Mbps';

	/// en: '~${bitrate} Mbps'
	String qualityBandwidthEstimate({required Object bitrate}) => '~${bitrate} Mbps';

	/// en: 'Transcoding unavailable — playing original quality'
	String get transcodeUnavailableFallback => 'Transcoding unavailable — playing original quality';

	/// en: 'Picture-in-Picture mode'
	String get pipButton => 'Picture-in-Picture mode';

	/// en: 'Aspect ratio'
	String get aspectRatioButton => 'Aspect ratio';

	/// en: 'Ambient lighting'
	String get ambientLighting => 'Ambient lighting';

	/// en: 'Subtle'
	String get ambientIntensitySubtle => 'Subtle';

	/// en: 'Balanced'
	String get ambientIntensityBalanced => 'Balanced';

	/// en: 'Bright'
	String get ambientIntensityBright => 'Bright';

	late final TranslationsVideoControlsTvPanelEn tvPanel = TranslationsVideoControlsTvPanelEn.internal(_root);

	/// en: 'Enter fullscreen'
	String get fullscreenButton => 'Enter fullscreen';

	/// en: 'Exit fullscreen'
	String get exitFullscreenButton => 'Exit fullscreen';

	/// en: 'Always on top'
	String get alwaysOnTopButton => 'Always on top';

	/// en: 'Rotation lock'
	String get rotationLockButton => 'Rotation lock';

	/// en: 'Lock screen'
	String get lockScreen => 'Lock screen';

	/// en: 'Screen lock'
	String get screenLockButton => 'Screen lock';

	/// en: 'Long press to unlock'
	String get longPressToUnlock => 'Long press to unlock';

	/// en: 'Video timeline'
	String get timelineSlider => 'Video timeline';

	/// en: 'Volume level'
	String get volumeSlider => 'Volume level';

	/// en: 'Volume is controlled by your audio device during passthrough'
	String get volumeHandledByDevice => 'Volume is controlled by your audio device during passthrough';

	/// en: 'Ends at ${time}'
	String endsAt({required Object time}) => 'Ends at ${time}';

	/// en: 'Playing in Picture-in-Picture'
	String get pipActive => 'Playing in Picture-in-Picture';

	/// en: 'Picture-in-picture failed to start'
	String get pipFailed => 'Picture-in-picture failed to start';

	/// en: 'Screenshot saved'
	String get screenshotSaved => 'Screenshot saved';

	/// en: 'Zoom ${percent}%'
	String zoomPercent({required Object percent}) => 'Zoom ${percent}%';

	late final TranslationsVideoControlsPipErrorsEn pipErrors = TranslationsVideoControlsPipErrorsEn.internal(_root);

	/// en: 'Chapters'
	String get chapters => 'Chapters';

	/// en: 'No chapters available'
	String get noChaptersAvailable => 'No chapters available';

	/// en: 'Queue'
	String get queue => 'Queue';

	/// en: 'No items in queue'
	String get noQueueItems => 'No items in queue';

	/// en: 'Search Subtitles'
	String get searchSubtitles => 'Search Subtitles';

	/// en: 'Language'
	String get language => 'Language';

	/// en: 'No subtitles found'
	String get noSubtitlesFound => 'No subtitles found';

	/// en: 'Downloaded'
	String get downloadedSubtitle => 'Downloaded';

	/// en: 'No subtitles available'
	String get noSubtitlesAvailable => 'No subtitles available';

	/// en: 'No audio tracks available'
	String get noAudioTracksAvailable => 'No audio tracks available';

	/// en: 'No tracks available'
	String get noTracksAvailable => 'No tracks available';

	/// en: 'Subtitle downloaded'
	String get subtitleDownloaded => 'Subtitle downloaded';

	/// en: 'Failed to download subtitle'
	String get subtitleDownloadFailed => 'Failed to download subtitle';

	/// en: 'Search languages...'
	String get searchLanguages => 'Search languages...';

	/// en: 'AirPlay'
	String get airplayButton => 'AirPlay';
}

// Path: userStatus
class TranslationsUserStatusEn {
	TranslationsUserStatusEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Admin'
	String get admin => 'Admin';

	/// en: 'Restricted'
	String get restricted => 'Restricted';

	/// en: 'Protected'
	String get protected => 'Protected';

	/// en: 'CURRENT'
	String get current => 'CURRENT';
}

// Path: messages
class TranslationsMessagesEn {
	TranslationsMessagesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Marked as watched'
	String get markedAsWatched => 'Marked as watched';

	/// en: 'Marked as unwatched'
	String get markedAsUnwatched => 'Marked as unwatched';

	/// en: 'Marked as watched (will sync when online)'
	String get markedAsWatchedOffline => 'Marked as watched (will sync when online)';

	/// en: 'Marked as unwatched (will sync when online)'
	String get markedAsUnwatchedOffline => 'Marked as unwatched (will sync when online)';

	/// en: 'Auto-removed: ${title}'
	String autoRemovedWatchedDownload({required Object title}) => 'Auto-removed: ${title}';

	/// en: 'Removed from Continue Watching'
	String get removedFromContinueWatching => 'Removed from Continue Watching';

	/// en: 'Error'
	String get errorLoading => 'Error';

	/// en: 'File information not available'
	String get fileInfoNotAvailable => 'File information not available';

	/// en: 'Error loading file info'
	String get errorLoadingFileInfo => 'Error loading file info';

	/// en: 'Error loading series'
	String get errorLoadingSeries => 'Error loading series';

	/// en: 'Music playback is not yet supported'
	String get musicNotSupported => 'Music playback is not yet supported';

	/// en: 'No description available'
	String get noDescriptionAvailable => 'No description available';

	/// en: 'No profiles available'
	String get noProfilesAvailable => 'No profiles available';

	/// en: 'Contact your server administrator to add profiles'
	String get contactAdminForProfiles => 'Contact your server administrator to add profiles';

	/// en: 'Unable to determine library section for this item'
	String get unableToDetermineLibrarySection => 'Unable to determine library section for this item';

	/// en: 'Logs cleared'
	String get logsCleared => 'Logs cleared';

	/// en: 'Logs copied to clipboard'
	String get logsCopied => 'Logs copied to clipboard';

	/// en: 'No logs available'
	String get noLogsAvailable => 'No logs available';

	/// en: 'Scanning "${title}"...'
	String libraryScanning({required Object title}) => 'Scanning "${title}"...';

	/// en: 'Library scan started for "${title}"'
	String libraryScanStarted({required Object title}) => 'Library scan started for "${title}"';

	/// en: 'Failed to scan library'
	String get libraryScanFailed => 'Failed to scan library';

	/// en: 'Refreshing metadata for "${title}"...'
	String metadataRefreshing({required Object title}) => 'Refreshing metadata for "${title}"...';

	/// en: 'Metadata refresh started for "${title}"'
	String metadataRefreshStarted({required Object title}) => 'Metadata refresh started for "${title}"';

	/// en: 'Failed to refresh metadata'
	String get metadataRefreshFailed => 'Failed to refresh metadata';

	/// en: 'Are you sure you want to logout?'
	String get logoutConfirm => 'Are you sure you want to logout?';

	/// en: 'No seasons found'
	String get noSeasonsFound => 'No seasons found';

	/// en: 'Couldn't load seasons'
	String get seasonsLoadFailed => 'Couldn\'t load seasons';

	/// en: 'No episodes found in first season'
	String get noEpisodesFound => 'No episodes found in first season';

	/// en: 'No episodes found'
	String get noEpisodesFoundGeneral => 'No episodes found';

	/// en: 'Couldn't load episodes'
	String get episodesLoadFailed => 'Couldn\'t load episodes';

	/// en: 'No results found'
	String get noResultsFound => 'No results found';

	/// en: 'Sleep timer set for ${label}'
	String sleepTimerSet({required Object label}) => 'Sleep timer set for ${label}';

	/// en: 'No items available'
	String get noItemsAvailable => 'No items available';

	/// en: 'Failed to create play queue - no items'
	String get failedToCreatePlayQueueNoItems => 'Failed to create play queue - no items';

	/// en: 'Failed to ${action}'
	String failedPlayback({required Object action}) => 'Failed to ${action}';

	/// en: 'Switching to compatible player...'
	String get switchingToCompatiblePlayer => 'Switching to compatible player...';

	/// en: 'Playback failed'
	String get serverLimitTitle => 'Playback failed';

	/// en: 'Server error (HTTP 500). A bandwidth/transcoding limit likely rejected this session. Ask the owner to adjust it.'
	String get serverLimitBody => 'Server error (HTTP 500). A bandwidth/transcoding limit likely rejected this session. Ask the owner to adjust it.';

	/// en: 'Logs uploaded'
	String get logsUploaded => 'Logs uploaded';

	/// en: 'Failed to upload logs'
	String get logsUploadFailed => 'Failed to upload logs';

	/// en: 'The log is too large to upload. Clear it, reproduce the problem, and upload again.'
	String get logsUploadTooLarge => 'The log is too large to upload. Clear it, reproduce the problem, and upload again.';

	/// en: 'Uploaded too soon after the last one. Try again in ${seconds} seconds.'
	String logsUploadRateLimited({required Object seconds}) => 'Uploaded too soon after the last one. Try again in ${seconds} seconds.';

	/// en: 'The log server refused the upload (HTTP ${status}).'
	String logsUploadRefused({required Object status}) => 'The log server refused the upload (HTTP ${status}).';

	/// en: 'The log server ran into a problem (HTTP ${status}). Try again later.'
	String logsUploadServerError({required Object status}) => 'The log server ran into a problem (HTTP ${status}). Try again later.';

	/// en: 'Could not reach the log server. Check your connection and try again.'
	String get logsUploadNetworkError => 'Could not reach the log server. Check your connection and try again.';

	/// en: 'Log ID'
	String get logId => 'Log ID';

	/// en: 'DVD discs aren't supported on this device.'
	String get dvdNotSupported => 'DVD discs aren\'t supported on this device.';

	/// en: 'This disc format isn't supported on this device.'
	String get discNotSupported => 'This disc format isn\'t supported on this device.';
}

// Path: subtitlingStyling
class TranslationsSubtitlingStylingEn {
	TranslationsSubtitlingStylingEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Text'
	String get text => 'Text';

	/// en: 'Border'
	String get border => 'Border';

	/// en: 'Background'
	String get background => 'Background';

	/// en: 'Font Size'
	String get fontSize => 'Font Size';

	/// en: 'Text Color'
	String get textColor => 'Text Color';

	/// en: 'Border Size'
	String get borderSize => 'Border Size';

	/// en: 'Border Color'
	String get borderColor => 'Border Color';

	/// en: 'Background Opacity'
	String get backgroundOpacity => 'Background Opacity';

	/// en: 'Background Color'
	String get backgroundColor => 'Background Color';

	/// en: 'Position'
	String get position => 'Position';

	/// en: 'ASS Override'
	String get assOverride => 'ASS Override';

	/// en: 'Bold'
	String get bold => 'Bold';

	/// en: 'Italic'
	String get italic => 'Italic';

	/// en: 'Render Resolution'
	String get renderResolution => 'Render Resolution';

	/// en: 'Screen resolution'
	String get renderResolutionScreen => 'Screen resolution';

	/// en: 'Video resolution'
	String get renderResolutionVideo => 'Video resolution';
}

// Path: mpvConfig
class TranslationsMpvConfigEn {
	TranslationsMpvConfigEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'mpv.conf'
	String get title => 'mpv.conf';

	/// en: 'Advanced video player settings'
	String get description => 'Advanced video player settings';

	/// en: 'Presets'
	String get presets => 'Presets';

	/// en: 'No saved presets'
	String get noPresets => 'No saved presets';

	/// en: 'Save as Preset...'
	String get saveAsPreset => 'Save as Preset...';

	/// en: 'Preset Name'
	String get presetName => 'Preset Name';

	/// en: 'Enter a name for this preset'
	String get presetNameHint => 'Enter a name for this preset';

	/// en: 'Load'
	String get loadPreset => 'Load';

	/// en: 'Delete'
	String get deletePreset => 'Delete';

	/// en: 'Preset saved'
	String get presetSaved => 'Preset saved';

	/// en: 'Preset loaded'
	String get presetLoaded => 'Preset loaded';

	/// en: 'Preset deleted'
	String get presetDeleted => 'Preset deleted';

	/// en: 'Are you sure you want to delete this preset?'
	String get confirmDeletePreset => 'Are you sure you want to delete this preset?';

	/// en: 'gpu-api=vulkan hwdec=auto # comment'
	String get configPlaceholder => 'gpu-api=vulkan\nhwdec=auto\n# comment';
}

// Path: dialog
class TranslationsDialogEn {
	TranslationsDialogEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Confirm Action'
	String get confirmAction => 'Confirm Action';
}

// Path: profiles
class TranslationsProfilesEn {
	TranslationsProfilesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Add Pleya profile'
	String get addPleyaProfile => 'Add Pleya profile';

	/// en: 'Switching profile…'
	String get switchingProfile => 'Switching profile…';

	/// en: 'Delete this profile?'
	String get deleteThisProfileTitle => 'Delete this profile?';

	/// en: 'Remove ${displayName}. Connections aren't affected.'
	String deleteThisProfileMessage({required Object displayName}) => 'Remove ${displayName}. Connections aren\'t affected.';

	/// en: 'Active'
	String get active => 'Active';

	/// en: 'Manage'
	String get manage => 'Manage';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Sign out'
	String get signOut => 'Sign out';

	/// en: 'Sign out of Plex?'
	String get signOutPlexTitle => 'Sign out of Plex?';

	/// en: 'Remove ${displayName} and all Plex Home users? Sign back in anytime.'
	String signOutPlexMessage({required Object displayName}) => 'Remove ${displayName} and all Plex Home users? Sign back in anytime.';

	/// en: 'Signed out of Plex.'
	String get signedOutPlex => 'Signed out of Plex.';

	/// en: 'Sign out failed.'
	String get signOutFailed => 'Sign out failed.';

	/// en: 'Profiles'
	String get sectionTitle => 'Profiles';

	/// en: 'Add profiles to mix managed users and local identities'
	String get summarySingle => 'Add profiles to mix managed users and local identities';

	/// en: '${count} profiles · active: ${activeName}'
	String summaryMultipleWithActive({required Object count, required Object activeName}) => '${count} profiles · active: ${activeName}';

	/// en: '${count} profiles'
	String summaryMultiple({required Object count}) => '${count} profiles';

	/// en: 'Remove connection?'
	String get removeConnectionTitle => 'Remove connection?';

	/// en: 'Remove ${displayName}'s access to ${connectionLabel}. Other profiles keep it.'
	String removeConnectionMessage({required Object displayName, required Object connectionLabel}) => 'Remove ${displayName}\'s access to ${connectionLabel}. Other profiles keep it.';

	/// en: 'Delete profile?'
	String get deleteProfileTitle => 'Delete profile?';

	/// en: 'Remove ${displayName} and its connections. Servers stay available.'
	String deleteProfileMessage({required Object displayName}) => 'Remove ${displayName} and its connections. Servers stay available.';

	/// en: 'Profile name'
	String get profileNameLabel => 'Profile name';

	/// en: 'PIN protection'
	String get pinProtectionLabel => 'PIN protection';

	/// en: 'PIN managed by Plex. Edit on plex.tv.'
	String get pinManagedByPlex => 'PIN managed by Plex. Edit on plex.tv.';

	/// en: 'No PIN set. To require one, edit the home user on plex.tv.'
	String get noPinSetEditOnPlex => 'No PIN set. To require one, edit the home user on plex.tv.';

	/// en: 'Set PIN'
	String get setPin => 'Set PIN';

	/// en: 'Set PIN'
	String get setPinTitle => 'Set PIN';

	/// en: 'Confirm PIN'
	String get confirmPinTitle => 'Confirm PIN';

	/// en: 'PIN set'
	String get pinSet => 'PIN set';

	/// en: 'Change'
	String get changePin => 'Change';

	/// en: 'Remove'
	String get removePin => 'Remove';

	/// en: 'Connections'
	String get connectionsLabel => 'Connections';

	/// en: 'Add'
	String get add => 'Add';

	/// en: 'Delete profile'
	String get deleteProfileButton => 'Delete profile';

	/// en: 'No connections — add one to use this profile.'
	String get noConnectionsHint => 'No connections — add one to use this profile.';

	/// en: 'No connections'
	String get noConnections => 'No connections';

	/// en: 'Plex Home account'
	String get plexHomeAccount => 'Plex Home account';

	/// en: 'Default'
	String get connectionDefault => 'Default';

	/// en: 'as ${displayName}'
	String connectionAs({required Object displayName}) => 'as ${displayName}';

	/// en: 'Make default'
	String get makeDefault => 'Make default';

	/// en: 'Remove'
	String get removeConnection => 'Remove';

	/// en: 'Profile renamed.'
	String get profileRenamed => 'Profile renamed.';

	/// en: 'Add to ${displayName}'
	String borrowAddTo({required Object displayName}) => 'Add to ${displayName}';

	/// en: 'Borrow another profile's connection. PIN-protected profiles require a PIN.'
	String get borrowExplain => 'Borrow another profile\'s connection. PIN-protected profiles require a PIN.';

	/// en: 'Nothing to borrow yet.'
	String get borrowEmpty => 'Nothing to borrow yet.';

	/// en: 'Connect Plex or Jellyfin to another profile first.'
	String get borrowEmptySubtitle => 'Connect Plex or Jellyfin to another profile first.';

	/// en: 'From ${displayName}'
	String borrowFromProfile({required Object displayName}) => 'From ${displayName}';

	/// en: 'Connection borrowed.'
	String get borrowConnectionBorrowed => 'Connection borrowed.';

	/// en: 'Failed to borrow connection.'
	String get borrowFailed => 'Failed to borrow connection.';

	/// en: 'Incorrect PIN.'
	String get incorrectPin => 'Incorrect PIN.';

	/// en: 'Source profile is missing its parent account.'
	String get sourceProfileMissingParentAccount => 'Source profile is missing its parent account.';

	/// en: 'Failed to verify PIN.'
	String get failedToVerifyPin => 'Failed to verify PIN.';

	/// en: 'New profile'
	String get newProfile => 'New profile';

	/// en: 'e.g. Guests, Kids, Family Room'
	String get profileNameHint => 'e.g. Guests, Kids, Family Room';

	/// en: 'PIN protection (optional)'
	String get pinProtectionOptional => 'PIN protection (optional)';

	/// en: '4-digit PIN required to switch profiles.'
	String get pinExplain => '4-digit PIN required to switch profiles.';

	/// en: 'Continue'
	String get continueButton => 'Continue';

	/// en: 'PINs don't match'
	String get pinsDontMatch => 'PINs don\'t match';

	/// en: 'Failed to initialize profile services'
	String get initializeServicesFailed => 'Failed to initialize profile services';
}

// Path: connections
class TranslationsConnectionsEn {
	TranslationsConnectionsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Connections'
	String get sectionTitle => 'Connections';

	/// en: 'Add connection'
	String get addConnection => 'Add connection';

	/// en: 'Sign in with Plex or connect a Jellyfin server'
	String get addConnectionSubtitleNoProfile => 'Sign in with Plex or connect a Jellyfin server';

	/// en: 'Add to ${displayName}: Plex, Jellyfin, or another profile connection'
	String addConnectionSubtitleScoped({required Object displayName}) => 'Add to ${displayName}: Plex, Jellyfin, or another profile connection';

	/// en: 'Session expired for ${name}'
	String sessionExpiredOne({required Object name}) => 'Session expired for ${name}';

	/// en: 'Session expired for ${count} servers'
	String sessionExpiredMany({required Object count}) => 'Session expired for ${count} servers';

	/// en: 'Sign in again'
	String get signInAgain => 'Sign in again';

	/// en: 'Edit Jellyfin connection'
	String get editJellyfinTitle => 'Edit Jellyfin connection';

	/// en: 'Add or remove URLs for ${serverName}. Pleya will use the reachable URL with the lowest latency.'
	String editJellyfinIntro({required Object serverName}) => 'Add or remove URLs for ${serverName}. Pleya will use the reachable URL with the lowest latency.';

	/// en: 'Sources on this device'
	String get localSources => 'Sources on this device';

	/// en: 'Remove source'
	String get removeSource => 'Remove source';

	/// en: 'Remove "$name" from this device? Downloaded items are kept.'
	String removeSourceConfirm({required Object name}) => 'Remove "${name}" from this device? Downloaded items are kept.';
}

// Path: discover
class TranslationsDiscoverEn {
	TranslationsDiscoverEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Discover'
	String get title => 'Discover';

	/// en: 'Switch Profile'
	String get switchProfile => 'Switch Profile';

	/// en: 'No content available'
	String get noContentAvailable => 'No content available';

	/// en: 'Add some media to your libraries'
	String get addMediaToLibraries => 'Add some media to your libraries';

	/// en: 'Continue Watching'
	String get continueWatching => 'Continue Watching';

	/// en: 'Continue Watching in ${library}'
	String continueWatchingIn({required Object library}) => 'Continue Watching in ${library}';

	/// en: 'Next Up'
	String get nextUp => 'Next Up';

	/// en: 'Next Up in ${library}'
	String nextUpIn({required Object library}) => 'Next Up in ${library}';

	/// en: 'Recently Added'
	String get recentlyAdded => 'Recently Added';

	/// en: 'Recently Released'
	String get recentlyReleased => 'Recently Released';

	/// en: 'Recently Added in ${library}'
	String recentlyAddedIn({required Object library}) => 'Recently Added in ${library}';

	/// en: 'S${season}E${episode}'
	String playEpisode({required Object season, required Object episode}) => 'S${season}E${episode}';

	/// en: 'Overview'
	String get overview => 'Overview';

	/// en: 'Cast'
	String get cast => 'Cast';

	/// en: 'Trailers & Extras'
	String get extras => 'Trailers & Extras';

	/// en: 'Studio'
	String get studio => 'Studio';

	/// en: 'Rating'
	String get rating => 'Rating';

	/// en: 'Movie'
	String get movie => 'Movie';

	/// en: 'Watched'
	String get watched => 'Watched';

	/// en: 'TV Show'
	String get tvShow => 'TV Show';

	/// en: '${minutes} min left'
	String minutesLeft({required Object minutes}) => '${minutes} min left';

	/// en: 'More Like This'
	String get moreLikeThis => 'More Like This';

	/// en: 'Because you watched ${title}'
	String becauseYouWatched({required Object title}) => 'Because you watched ${title}';

	/// en: 'Recently Added Shows'
	String get latestShows => 'Recently Added Shows';

	/// en: 'Top Rated'
	String get topRated => 'Top Rated';

	/// en: 'Something Different'
	String get somethingDifferent => 'Something Different';

	/// en: 'Top Picks for You'
	String get topPicksForYou => 'Top Picks for You';

	/// en: 'Because you like ${genre}'
	String becauseYouLike({required Object genre}) => 'Because you like ${genre}';

	/// en: 'Hidden Gems'
	String get hiddenGems => 'Hidden Gems';

	/// en: 'Watched by ${names}'
	String watchedBy({required Object names}) => 'Watched by ${names}';

	/// en: 'You'
	String get watchedByYou => 'You';

	/// en: 'and'
	String get watchedByAnd => 'and';

	/// en: '${count} others'
	String watchedByOthers({required Object count}) => '${count} others';

	/// en: 'Played ${count} times'
	String statsPlays({required Object count}) => 'Played ${count} times';

	/// en: 'by ${count} people'
	String statsViewers({required Object count}) => 'by ${count} people';

	/// en: '${duration} watched'
	String statsWatchTime({required Object duration}) => '${duration} watched';

	/// en: '${count} in the last 30 days'
	String statsRecent({required Object count}) => '${count} in the last 30 days';

	/// en: 'Watching this show: ${names}'
	String watchingSeriesBy({required Object names}) => 'Watching this show: ${names}';
}

// Path: errors
class TranslationsErrorsEn {
	TranslationsErrorsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Search failed'
	String get searchFailed => 'Search failed';

	/// en: 'Connection timeout while loading ${context}'
	String connectionTimeout({required Object context}) => 'Connection timeout while loading ${context}';

	/// en: 'Unable to connect to media server'
	String get connectionFailed => 'Unable to connect to media server';

	/// en: 'Failed to load ${context}'
	String failedToLoad({required Object context}) => 'Failed to load ${context}';

	/// en: 'No client available'
	String get noClientAvailable => 'No client available';

	/// en: 'Authentication failed'
	String get authenticationFailed => 'Authentication failed';

	/// en: 'Could not launch auth URL'
	String get couldNotLaunchUrl => 'Could not launch auth URL';

	/// en: 'Please enter a token'
	String get pleaseEnterToken => 'Please enter a token';

	/// en: 'Invalid token'
	String get invalidToken => 'Invalid token';

	/// en: 'Failed to verify token'
	String get failedToVerifyToken => 'Failed to verify token';

	/// en: 'Failed to switch to ${displayName}'
	String failedToSwitchProfile({required Object displayName}) => 'Failed to switch to ${displayName}';

	/// en: 'Failed to delete ${displayName}'
	String failedToDeleteProfile({required Object displayName}) => 'Failed to delete ${displayName}';

	/// en: 'Couldn't update rating'
	String get failedToRate => 'Couldn\'t update rating';

	/// en: 'Something went wrong. Try again.'
	String get somethingWentWrongTryAgain => 'Something went wrong. Try again.';

	/// en: 'Couldn't load ${context}. Try again.'
	String couldNotLoad({required Object context}) => 'Couldn\'t load ${context}. Try again.';
}

// Path: notices
class TranslationsNoticesEn {
	TranslationsNoticesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Connection timed out'
	String get connectionTimeoutTitle => 'Connection timed out';

	/// en: '${context} took too long to respond'
	String connectionTimeoutBody({required Object context}) => '${context} took too long to respond';

	/// en: 'Can't connect'
	String get connectionFailedTitle => 'Can\'t connect';

	/// en: '${serverName} isn't responding'
	String connectionFailedBody({required Object serverName}) => '${serverName} isn\'t responding';

	/// en: 'Couldn't load ${context}'
	String couldNotLoadTitle({required Object context}) => 'Couldn\'t load ${context}';

	/// en: 'Something went wrong'
	String get genericErrorTitle => 'Something went wrong';

	/// en: 'Sign-in failed'
	String get authFailedTitle => 'Sign-in failed';

	/// en: 'Playback stopped'
	String get playbackStoppedTitle => 'Playback stopped';

	/// en: 'This part of the video isn't available right now'
	String get playbackSegmentUnavailableBody => 'This part of the video isn\'t available right now';

	/// en: 'Lost connection to the server'
	String get playbackConnectionLostBody => 'Lost connection to the server';

	/// en: 'This file's format isn't supported on this device'
	String get playbackCodecUnsupportedBody => 'This file\'s format isn\'t supported on this device';

	/// en: 'The server hit an error while transcoding'
	String get playbackServerErrorBody => 'The server hit an error while transcoding';
}

// Path: libraries
class TranslationsLibrariesEn {
	TranslationsLibrariesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Libraries'
	String get title => 'Libraries';

	/// en: 'Library'
	String get fallbackTitle => 'Library';

	/// en: '${count} items'
	String itemCount({required Object count}) => '${count} items';

	/// en: '1 item'
	String get oneItem => '1 item';

	/// en: 'Scan Library Files'
	String get scanLibraryFiles => 'Scan Library Files';

	/// en: 'Scan Library'
	String get scanLibrary => 'Scan Library';

	/// en: 'Analyze'
	String get analyze => 'Analyze';

	/// en: 'Analyze Library'
	String get analyzeLibrary => 'Analyze Library';

	/// en: 'Refresh Metadata'
	String get refreshMetadata => 'Refresh Metadata';

	/// en: 'Empty Trash'
	String get emptyTrash => 'Empty Trash';

	/// en: 'Emptying trash for "${title}"...'
	String emptyingTrash({required Object title}) => 'Emptying trash for "${title}"...';

	/// en: 'Trash emptied for "${title}"'
	String trashEmptied({required Object title}) => 'Trash emptied for "${title}"';

	/// en: 'Failed to empty trash'
	String get failedToEmptyTrash => 'Failed to empty trash';

	/// en: 'Analyzing "${title}"...'
	String analyzing({required Object title}) => 'Analyzing "${title}"...';

	/// en: 'Analysis started for "${title}"'
	String analysisStarted({required Object title}) => 'Analysis started for "${title}"';

	/// en: 'Failed to analyze library'
	String get failedToAnalyze => 'Failed to analyze library';

	/// en: 'No libraries found'
	String get noLibrariesFound => 'No libraries found';

	/// en: 'All libraries are hidden'
	String get allLibrariesHidden => 'All libraries are hidden';

	/// en: 'Hidden libraries (${count})'
	String hiddenLibrariesCount({required Object count}) => 'Hidden libraries (${count})';

	/// en: 'This library is empty'
	String get thisLibraryIsEmpty => 'This library is empty';

	/// en: 'All'
	String get all => 'All';

	/// en: 'Clear All'
	String get clearAll => 'Clear All';

	/// en: 'Are you sure you want to scan "${title}"?'
	String scanLibraryConfirm({required Object title}) => 'Are you sure you want to scan "${title}"?';

	/// en: 'Are you sure you want to analyze "${title}"?'
	String analyzeLibraryConfirm({required Object title}) => 'Are you sure you want to analyze "${title}"?';

	/// en: 'Are you sure you want to refresh metadata for "${title}"?'
	String refreshMetadataConfirm({required Object title}) => 'Are you sure you want to refresh metadata for "${title}"?';

	/// en: 'Are you sure you want to empty trash for "${title}"?'
	String emptyTrashConfirm({required Object title}) => 'Are you sure you want to empty trash for "${title}"?';

	/// en: 'Manage Libraries'
	String get manageLibraries => 'Manage Libraries';

	/// en: 'Sort'
	String get sort => 'Sort';

	/// en: 'Sort By'
	String get sortBy => 'Sort By';

	/// en: 'Filters'
	String get filters => 'Filters';

	/// en: 'Are you sure you want to perform this action?'
	String get confirmActionMessage => 'Are you sure you want to perform this action?';

	/// en: 'Show library'
	String get showLibrary => 'Show library';

	/// en: 'Hide library'
	String get hideLibrary => 'Hide library';

	/// en: 'Library options'
	String get libraryOptions => 'Library options';

	/// en: 'library content'
	String get content => 'library content';

	/// en: 'Select library'
	String get selectLibrary => 'Select library';

	/// en: 'Filters (${count})'
	String filtersWithCount({required Object count}) => 'Filters (${count})';

	/// en: 'No recommendations available'
	String get noRecommendations => 'No recommendations available';

	/// en: 'No collections in this library'
	String get noCollections => 'No collections in this library';

	/// en: 'No folders found'
	String get noFoldersFound => 'No folders found';

	/// en: 'folders'
	String get folders => 'folders';

	late final TranslationsLibrariesTabsEn tabs = TranslationsLibrariesTabsEn.internal(_root);
	late final TranslationsLibrariesGroupingsEn groupings = TranslationsLibrariesGroupingsEn.internal(_root);
	late final TranslationsLibrariesFilterCategoriesEn filterCategories = TranslationsLibrariesFilterCategoriesEn.internal(_root);
	late final TranslationsLibrariesSortLabelsEn sortLabels = TranslationsLibrariesSortLabelsEn.internal(_root);
}

// Path: about
class TranslationsAboutEn {
	TranslationsAboutEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'About'
	String get title => 'About';

	/// en: 'Open Source Licenses'
	String get openSourceLicenses => 'Open Source Licenses';

	/// en: 'Version ${version}'
	String versionLabel({required Object version}) => 'Version ${version}';

	/// en: 'A beautiful Plex and Jellyfin client for Flutter'
	String get appDescription => 'A beautiful Plex and Jellyfin client for Flutter';

	/// en: 'View licenses of third-party libraries'
	String get viewLicensesDescription => 'View licenses of third-party libraries';

	/// en: 'Source code'
	String get sourceCode => 'Source code';

	/// en: 'Corresponding source for this build (GPL-3.0)'
	String get sourceCodeDescription => 'Corresponding source for this build (GPL-3.0)';

	/// en: 'Based on Plezy'
	String get basedOnPlezy => 'Based on Plezy';

	/// en: 'Upstream project'
	String get upstreamProject => 'Upstream project';

	/// en: 'Privacy policy'
	String get privacyPolicy => 'Privacy policy';
}

// Path: serverSelection
class TranslationsServerSelectionEn {
	TranslationsServerSelectionEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Couldn't connect to any servers. Check your network.'
	String get allServerConnectionsFailed => 'Couldn\'t connect to any servers. Check your network.';

	/// en: 'No servers found for ${username} (${email})'
	String noServersFoundForAccount({required Object username, required Object email}) => 'No servers found for ${username} (${email})';

	/// en: 'No media servers found'
	String get noServersFoundTitle => 'No media servers found';

	/// en: 'Your Plex account doesn't have access to any servers yet. Ask the server owner to share their library with you, or connect a Jellyfin server instead.'
	String get noServersFoundDescription => 'Your Plex account doesn\'t have access to any servers yet. Ask the server owner to share their library with you, or connect a Jellyfin server instead.';

	/// en: 'Connect a Jellyfin server'
	String get noServersFoundTryJellyfin => 'Connect a Jellyfin server';

	/// en: 'Try a different Plex account'
	String get noServersFoundRetryPlex => 'Try a different Plex account';

	/// en: 'Failed to load servers'
	String get failedToLoadServers => 'Failed to load servers';

	/// en: 'Something went wrong while loading your servers. Check your internet connection and try again.'
	String get failedToLoadServersDescription => 'Something went wrong while loading your servers. Check your internet connection and try again.';

	/// en: 'Can't reach the server'
	String get networkErrorTitle => 'Can\'t reach the server';

	/// en: 'Pleya couldn't connect to the internet. Check your network and try again.'
	String get networkErrorDescription => 'Pleya couldn\'t connect to the internet. Check your network and try again.';
}

// Path: hubDetail
class TranslationsHubDetailEn {
	TranslationsHubDetailEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Title'
	String get title => 'Title';

	/// en: 'Release Year'
	String get releaseYear => 'Release Year';

	/// en: 'Date Added'
	String get dateAdded => 'Date Added';

	/// en: 'Rating'
	String get rating => 'Rating';

	/// en: 'No items found'
	String get noItemsFound => 'No items found';
}

// Path: logs
class TranslationsLogsEn {
	TranslationsLogsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Clear Logs'
	String get clearLogs => 'Clear Logs';

	/// en: 'Copy Logs'
	String get copyLogs => 'Copy Logs';

	/// en: 'Upload Logs'
	String get uploadLogs => 'Upload Logs';
}

// Path: licenses
class TranslationsLicensesEn {
	TranslationsLicensesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Related Packages'
	String get relatedPackages => 'Related Packages';

	/// en: 'License'
	String get license => 'License';

	/// en: 'License ${number}'
	String licenseNumber({required Object number}) => 'License ${number}';

	/// en: '${count} licenses'
	String licensesCount({required Object count}) => '${count} licenses';
}

// Path: navigation
class TranslationsNavigationEn {
	TranslationsNavigationEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Libraries'
	String get libraries => 'Libraries';

	/// en: 'Downloads'
	String get downloads => 'Downloads';

	/// en: 'Live TV'
	String get liveTv => 'Live TV';

	/// en: 'Watchlist'
	String get watchlist => 'Watchlist';

	/// en: 'My Pleya'
	String get myPleya => 'My Pleya';
}

// Path: watchlist
class TranslationsWatchlistEn {
	TranslationsWatchlistEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Watchlist'
	String get title => 'Watchlist';

	/// en: 'See all'
	String get seeAll => 'See all';

	/// en: 'Nothing on your watchlist yet'
	String get empty => 'Nothing on your watchlist yet';

	/// en: 'Titles you add from Plex or mark as a Jellyfin favorite show up here.'
	String get emptyBody => 'Titles you add from Plex or mark as a Jellyfin favorite show up here.';

	/// en: 'No titles match this filter'
	String get emptyFiltered => 'No titles match this filter';

	/// en: 'Try again'
	String get retry => 'Try again';

	/// en: 'Not available'
	String get notAvailable => 'Not available';

	/// en: 'Checking'
	String get checking => 'Checking';

	/// en: 'Not found on your connected media servers'
	String get notFoundOnServers => 'Not found on your connected media servers';

	/// en: 'Some of your media servers could not be reached. This title may already be there.'
	String get coverageIncomplete => 'Some of your media servers could not be reached. This title may already be there.';

	/// en: 'Remove from Watchlist'
	String get remove => 'Remove from Watchlist';

	/// en: 'Add to Watchlist'
	String get add => 'Add to Watchlist';

	/// en: 'Added to Watchlist'
	String get added => 'Added to Watchlist';

	/// en: 'Removed from Watchlist'
	String get removed => 'Removed from Watchlist';

	/// en: 'Could not update your watchlist'
	String get addFailed => 'Could not update your watchlist';

	/// en: 'Removed from some lists only. Your watchlist has been refreshed.'
	String get partiallyFailed => 'Removed from some lists only. Your watchlist has been refreshed.';

	/// en: 'You need a connection to change your watchlist'
	String get offlineRejected => 'You need a connection to change your watchlist';

	/// en: 'All'
	String get filterAll => 'All';

	/// en: 'Movies'
	String get filterMovies => 'Movies';

	/// en: 'Shows'
	String get filterShows => 'Shows';

	/// en: 'Available'
	String get filterAvailable => 'Available';

	/// en: 'Recently added'
	String get sortRecentlyAdded => 'Recently added';

	/// en: 'Title'
	String get sortTitle => 'Title';

	/// en: 'Year'
	String get sortYear => 'Year';
}

// Path: myPleya
class TranslationsMyPleyaEn {
	TranslationsMyPleyaEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'My Pleya'
	String get title => 'My Pleya';

	/// en: '(one) {1 download} (other) {{n} downloads}'
	String downloadsCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 download',
		other: '{n} downloads',
	);
}

// Path: liveTv
class TranslationsLiveTvEn {
	TranslationsLiveTvEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Live TV server is not available.'
	String get serverNotAvailable => 'Live TV server is not available.';

	/// en: 'Live TV server is not connected.'
	String get serverNotConnected => 'Live TV server is not connected.';

	/// en: 'Live TV'
	String get title => 'Live TV';

	/// en: 'Guide'
	String get guide => 'Guide';

	/// en: 'No channels available'
	String get noChannels => 'No channels available';

	/// en: 'No DVR configured on any server'
	String get noDvr => 'No DVR configured on any server';

	/// en: 'No program data available'
	String get noPrograms => 'No program data available';

	/// en: 'Live stream failed'
	String get liveStreamFailed => 'Live stream failed';

	/// en: 'Unknown Program'
	String get unknownProgram => 'Unknown Program';

	/// en: 'Unknown'
	String get unknownHub => 'Unknown';

	/// en: 'Unknown error'
	String get unknownError => 'Unknown error';

	/// en: 'Channel ${number}'
	String channelNumber({required Object number}) => 'Channel ${number}';

	/// en: 'Unknown channel'
	String get unknownChannel => 'Unknown channel';

	/// en: 'LIVE'
	String get live => 'LIVE';

	/// en: 'Reload Guide'
	String get reloadGuide => 'Reload Guide';

	/// en: 'Now'
	String get now => 'Now';

	/// en: 'Today'
	String get today => 'Today';

	/// en: 'Tomorrow'
	String get tomorrow => 'Tomorrow';

	/// en: 'Midnight'
	String get midnight => 'Midnight';

	/// en: 'Overnight'
	String get overnight => 'Overnight';

	/// en: 'Morning'
	String get morning => 'Morning';

	/// en: 'Daytime'
	String get daytime => 'Daytime';

	/// en: 'Evening'
	String get evening => 'Evening';

	/// en: 'Late Night'
	String get lateNight => 'Late Night';

	/// en: 'What's On'
	String get whatsOn => 'What\'s On';

	/// en: 'Watch Channel'
	String get watchChannel => 'Watch Channel';

	/// en: 'Favorites'
	String get favorites => 'Favorites';

	/// en: 'Reorder Favorites'
	String get reorderFavorites => 'Reorder Favorites';

	/// en: 'Could not save your favorite channels'
	String get favoritesSaveFailed => 'Could not save your favorite channels';

	/// en: 'Join Session in Progress'
	String get joinSession => 'Join Session in Progress';

	/// en: 'Watch from start (${minutes} min ago)'
	String watchFromStart({required Object minutes}) => 'Watch from start (${minutes} min ago)';

	/// en: 'Watch Live'
	String get watchLive => 'Watch Live';

	/// en: 'Go to Live'
	String get goToLive => 'Go to Live';

	/// en: 'Record'
	String get record => 'Record';

	/// en: 'Record Episode'
	String get recordEpisode => 'Record Episode';

	/// en: 'Record Series'
	String get recordSeries => 'Record Series';

	/// en: 'Record Options'
	String get recordOptions => 'Record Options';

	/// en: 'Recordings'
	String get recordings => 'Recordings';

	/// en: 'Scheduled'
	String get scheduledRecordings => 'Scheduled';

	/// en: 'Recording Rules'
	String get recordingRules => 'Recording Rules';

	/// en: 'Nothing scheduled to record'
	String get noScheduledRecordings => 'Nothing scheduled to record';

	/// en: 'No recording rules yet'
	String get noRecordingRules => 'No recording rules yet';

	/// en: 'Manage recording'
	String get manageRecording => 'Manage recording';

	/// en: 'Cancel recording'
	String get cancelRecording => 'Cancel recording';

	/// en: 'Cancel this recording?'
	String get cancelRecordingTitle => 'Cancel this recording?';

	/// en: '${title} will no longer be recorded.'
	String cancelRecordingMessage({required Object title}) => '${title} will no longer be recorded.';

	/// en: 'Delete rule'
	String get deleteRule => 'Delete rule';

	/// en: 'Delete recording rule?'
	String get deleteRuleTitle => 'Delete recording rule?';

	/// en: 'Future episodes of ${title} will not be recorded.'
	String deleteRuleMessage({required Object title}) => 'Future episodes of ${title} will not be recorded.';

	/// en: 'Recording scheduled'
	String get recordingScheduled => 'Recording scheduled';

	/// en: 'This program is already scheduled'
	String get alreadyScheduled => 'This program is already scheduled';

	/// en: 'DVR settings require an admin account'
	String get dvrAdminRequired => 'DVR settings require an admin account';

	/// en: 'Couldn't schedule recording'
	String get recordingFailed => 'Couldn\'t schedule recording';

	/// en: 'Couldn't determine recording library'
	String get recordingTargetMissing => 'Couldn\'t determine recording library';

	/// en: 'Recording not available for this program'
	String get recordNotAvailable => 'Recording not available for this program';

	/// en: 'Recording cancelled'
	String get recordingCancelled => 'Recording cancelled';

	/// en: 'Recording rule deleted'
	String get recordingRuleDeleted => 'Recording rule deleted';

	/// en: 'Re-evaluate rules'
	String get processRecordingRules => 'Re-evaluate rules';

	/// en: 'Loading recordings...'
	String get loadingRecordings => 'Loading recordings...';

	/// en: 'Recording now'
	String get recordingInProgress => 'Recording now';

	/// en: '${count} scheduled'
	String recordingsCount({required Object count}) => '${count} scheduled';

	/// en: 'Edit rule'
	String get editRule => 'Edit rule';

	/// en: 'Edit'
	String get editRuleAction => 'Edit';

	/// en: 'Recording rule updated'
	String get recordingRuleUpdated => 'Recording rule updated';

	/// en: 'Guide refresh requested'
	String get guideReloadRequested => 'Guide refresh requested';

	/// en: 'Rule re-evaluation requested'
	String get rulesProcessRequested => 'Rule re-evaluation requested';

	/// en: 'Record show'
	String get recordShow => 'Record show';
}

// Path: collections
class TranslationsCollectionsEn {
	TranslationsCollectionsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Collections'
	String get title => 'Collections';

	/// en: 'Collection'
	String get collection => 'Collection';

	/// en: 'Collection is empty'
	String get empty => 'Collection is empty';

	/// en: 'Cannot delete: Unknown library section'
	String get unknownLibrarySection => 'Cannot delete: Unknown library section';

	/// en: 'Delete Collection'
	String get deleteCollection => 'Delete Collection';

	/// en: 'Delete "${title}"? This can't be undone.'
	String deleteConfirm({required Object title}) => 'Delete "${title}"? This can\'t be undone.';

	/// en: 'Collection deleted'
	String get deleted => 'Collection deleted';

	/// en: 'Failed to delete collection'
	String get deleteFailed => 'Failed to delete collection';

	/// en: 'Failed to delete collection'
	String get deleteFailedWithError => 'Failed to delete collection';

	/// en: 'Failed to load collection items'
	String get failedToLoadItems => 'Failed to load collection items';

	/// en: 'Select Collection'
	String get selectCollection => 'Select Collection';

	/// en: 'Collection Name'
	String get collectionName => 'Collection Name';

	/// en: 'Enter collection name'
	String get enterCollectionName => 'Enter collection name';

	/// en: 'Added to collection'
	String get addedToCollection => 'Added to collection';

	/// en: 'Failed to add to collection'
	String get errorAddingToCollection => 'Failed to add to collection';

	/// en: 'Collection created'
	String get created => 'Collection created';

	/// en: 'Remove from collection'
	String get removeFromCollection => 'Remove from collection';

	/// en: 'Remove "${title}" from this collection?'
	String removeFromCollectionConfirm({required Object title}) => 'Remove "${title}" from this collection?';

	/// en: 'Removed from collection'
	String get removedFromCollection => 'Removed from collection';

	/// en: 'Failed to remove from collection'
	String get removeFromCollectionFailed => 'Failed to remove from collection';

	/// en: 'Error removing from collection'
	String get removeFromCollectionError => 'Error removing from collection';

	/// en: 'Search collections...'
	String get searchCollections => 'Search collections...';
}

// Path: playlists
class TranslationsPlaylistsEn {
	TranslationsPlaylistsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Playlists'
	String get title => 'Playlists';

	/// en: 'Playlist'
	String get playlist => 'Playlist';

	/// en: 'No playlists found'
	String get noPlaylists => 'No playlists found';

	/// en: 'Create Playlist'
	String get create => 'Create Playlist';

	/// en: 'Playlist Name'
	String get playlistName => 'Playlist Name';

	/// en: 'Enter playlist name'
	String get enterPlaylistName => 'Enter playlist name';

	/// en: 'Delete Playlist'
	String get delete => 'Delete Playlist';

	/// en: 'Remove from Playlist'
	String get removeItem => 'Remove from Playlist';

	/// en: 'Smart Playlist'
	String get smartPlaylist => 'Smart Playlist';

	/// en: '${count} items'
	String itemCount({required Object count}) => '${count} items';

	/// en: '1 item'
	String get oneItem => '1 item';

	/// en: 'This playlist is empty'
	String get emptyPlaylist => 'This playlist is empty';

	/// en: 'Delete Playlist?'
	String get deleteConfirm => 'Delete Playlist?';

	/// en: 'Are you sure you want to delete "${name}"?'
	String deleteMessage({required Object name}) => 'Are you sure you want to delete "${name}"?';

	/// en: 'Playlist created'
	String get created => 'Playlist created';

	/// en: 'Playlist deleted'
	String get deleted => 'Playlist deleted';

	/// en: 'Added to playlist'
	String get itemAdded => 'Added to playlist';

	/// en: 'Removed from playlist'
	String get itemRemoved => 'Removed from playlist';

	/// en: 'Select Playlist'
	String get selectPlaylist => 'Select Playlist';

	/// en: 'Failed to create playlist'
	String get errorCreating => 'Failed to create playlist';

	/// en: 'Failed to delete playlist'
	String get errorDeleting => 'Failed to delete playlist';

	/// en: 'Failed to load playlists'
	String get errorLoading => 'Failed to load playlists';

	/// en: 'Failed to add to playlist'
	String get errorAdding => 'Failed to add to playlist';

	/// en: 'Failed to reorder playlist item'
	String get errorReordering => 'Failed to reorder playlist item';

	/// en: 'Failed to remove from playlist'
	String get errorRemoving => 'Failed to remove from playlist';
}

// Path: watchTogether
class TranslationsWatchTogetherEn {
	TranslationsWatchTogetherEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Watch Together'
	String get title => 'Watch Together';

	/// en: 'Watch content in sync with friends and family'
	String get description => 'Watch content in sync with friends and family';

	/// en: 'Create Session'
	String get createSession => 'Create Session';

	/// en: 'Creating...'
	String get creating => 'Creating...';

	/// en: 'Join Session'
	String get joinSession => 'Join Session';

	/// en: 'Joining...'
	String get joining => 'Joining...';

	/// en: 'Control Mode'
	String get controlMode => 'Control Mode';

	/// en: 'Who can control playback?'
	String get controlModeQuestion => 'Who can control playback?';

	/// en: 'Host Only'
	String get hostOnly => 'Host Only';

	/// en: 'Anyone'
	String get anyone => 'Anyone';

	/// en: 'Hosting Session'
	String get hostingSession => 'Hosting Session';

	/// en: 'In Session'
	String get inSession => 'In Session';

	/// en: 'Session Code'
	String get sessionCode => 'Session Code';

	/// en: 'Host controls playback'
	String get hostControlsPlayback => 'Host controls playback';

	/// en: 'Anyone can control playback'
	String get anyoneCanControl => 'Anyone can control playback';

	/// en: 'Host controls'
	String get hostControls => 'Host controls';

	/// en: 'Anyone controls'
	String get anyoneControls => 'Anyone controls';

	/// en: 'Participants'
	String get participants => 'Participants';

	/// en: 'Host'
	String get host => 'Host';

	/// en: 'HOST'
	String get hostBadge => 'HOST';

	/// en: 'You are the host'
	String get youAreHost => 'You are the host';

	/// en: 'Watching with others'
	String get watchingWithOthers => 'Watching with others';

	/// en: 'End Session'
	String get endSession => 'End Session';

	/// en: 'Leave Session'
	String get leaveSession => 'Leave Session';

	/// en: 'End Session?'
	String get endSessionQuestion => 'End Session?';

	/// en: 'Leave Session?'
	String get leaveSessionQuestion => 'Leave Session?';

	/// en: 'This will end the session for all participants.'
	String get endSessionConfirm => 'This will end the session for all participants.';

	/// en: 'You will be removed from the session.'
	String get leaveSessionConfirm => 'You will be removed from the session.';

	/// en: 'This will end the watch session for all participants.'
	String get endSessionConfirmOverlay => 'This will end the watch session for all participants.';

	/// en: 'You will be disconnected from the watch session.'
	String get leaveSessionConfirmOverlay => 'You will be disconnected from the watch session.';

	/// en: 'End'
	String get end => 'End';

	/// en: 'Leave'
	String get leave => 'Leave';

	/// en: 'Syncing...'
	String get syncing => 'Syncing...';

	/// en: 'Join Watch Session'
	String get joinWatchSession => 'Join Watch Session';

	/// en: 'Enter 5-character code'
	String get enterCodeHint => 'Enter 5-character code';

	/// en: 'Paste from clipboard'
	String get pasteFromClipboard => 'Paste from clipboard';

	/// en: 'Please enter a session code'
	String get pleaseEnterCode => 'Please enter a session code';

	/// en: 'Session code must be 5 characters'
	String get codeMustBe5Chars => 'Session code must be 5 characters';

	/// en: 'Enter the host's session code to join.'
	String get joinInstructions => 'Enter the host\'s session code to join.';

	/// en: 'Failed to create session'
	String get failedToCreate => 'Failed to create session';

	/// en: 'Failed to join session'
	String get failedToJoin => 'Failed to join session';

	/// en: 'Session code copied to clipboard'
	String get sessionCodeCopied => 'Session code copied to clipboard';

	/// en: 'Relay server unreachable. ISP blocking may prevent Watch Together.'
	String get relayUnreachable => 'Relay server unreachable. ISP blocking may prevent Watch Together.';

	/// en: 'Reconnecting to host...'
	String get reconnectingToHost => 'Reconnecting to host...';

	/// en: 'Current Playback'
	String get currentPlayback => 'Current Playback';

	/// en: 'Join Current Playback'
	String get joinCurrentPlayback => 'Join Current Playback';

	/// en: 'Jump back into what the host is currently watching'
	String get joinCurrentPlaybackDescription => 'Jump back into what the host is currently watching';

	/// en: 'Failed to open current playback'
	String get failedToOpenCurrentPlayback => 'Failed to open current playback';

	/// en: '${name} joined'
	String participantJoined({required Object name}) => '${name} joined';

	/// en: '${name} left'
	String participantLeft({required Object name}) => '${name} left';

	/// en: '${name} paused'
	String participantPaused({required Object name}) => '${name} paused';

	/// en: '${name} resumed'
	String participantResumed({required Object name}) => '${name} resumed';

	/// en: '${name} seeked'
	String participantSeeked({required Object name}) => '${name} seeked';

	/// en: '${name} is buffering'
	String participantBuffering({required Object name}) => '${name} is buffering';

	/// en: '${name} is on an older app version — sync unavailable'
	String participantNeedsUpdate({required Object name}) => '${name} is on an older app version — sync unavailable';

	/// en: 'Resuming without ${name}'
	String resumingWithout({required Object name}) => 'Resuming without ${name}';

	/// en: 'Waiting for others to load...'
	String get waitingForParticipants => 'Waiting for others to load...';

	/// en: 'Waiting for ${name}...'
	String waitingForName({required Object name}) => 'Waiting for ${name}...';

	/// en: 'Recent Rooms'
	String get recentRooms => 'Recent Rooms';

	/// en: 'Rename Room'
	String get renameRoom => 'Rename Room';

	/// en: 'Remove'
	String get removeRoom => 'Remove';

	/// en: 'Couldn't switch — server unavailable for sync'
	String get guestSwitchUnavailable => 'Couldn\'t switch — server unavailable for sync';

	/// en: 'Couldn't switch — content not found on this server'
	String get guestSwitchFailed => 'Couldn\'t switch — content not found on this server';
}

// Path: downloads
class TranslationsDownloadsEn {
	TranslationsDownloadsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Downloads'
	String get title => 'Downloads';

	/// en: 'Manage'
	String get manage => 'Manage';

	/// en: 'TV Shows'
	String get tvShows => 'TV Shows';

	/// en: 'Movies'
	String get movies => 'Movies';

	/// en: 'No downloads yet'
	String get noDownloads => 'No downloads yet';

	/// en: 'Downloaded content will appear here for offline viewing'
	String get noDownloadsDescription => 'Downloaded content will appear here for offline viewing';

	/// en: 'Download'
	String get downloadNow => 'Download';

	/// en: 'Delete download'
	String get deleteDownload => 'Delete download';

	/// en: 'Retry download'
	String get retryDownload => 'Retry download';

	/// en: 'Download queued'
	String get downloadQueued => 'Download queued';

	/// en: 'Waiting for network'
	String get waitingForNetwork => 'Waiting for network';

	/// en: 'Download resumed'
	String get downloadResumed => 'Download resumed';

	/// en: 'Server error: file may exceed the remote bitrate limit'
	String get serverErrorBitrate => 'Server error: file may exceed the remote bitrate limit';

	/// en: 'Not enough storage space on this device'
	String get storageFull => 'Not enough storage space on this device';

	/// en: '${count} episodes queued for download'
	String episodesQueued({required Object count}) => '${count} episodes queued for download';

	/// en: 'Download deleted'
	String get downloadDeleted => 'Download deleted';

	/// en: 'Delete "${title}" from this device?'
	String deleteConfirm({required Object title}) => 'Delete "${title}" from this device?';

	/// en: 'Cancelled Download'
	String get cancelledDownloadTitle => 'Cancelled Download';

	/// en: 'This download was cancelled. What would you like to do?'
	String get cancelledDownloadMessage => 'This download was cancelled. What would you like to do?';

	/// en: 'All episodes already downloaded'
	String get allEpisodesAlreadyDownloaded => 'All episodes already downloaded';

	/// en: 'Resume download'
	String get resumeDownload => 'Resume download';

	/// en: 'Cancelled download'
	String get cancelledDownload => 'Cancelled download';

	/// en: '${file} (syncing ${status})'
	String syncingFile({required Object file, required Object status}) => '${file} (syncing ${status})';

	/// en: 'Downloaded ${file} - Click to complete'
	String downloadedFileClickToComplete({required Object file}) => 'Downloaded ${file} - Click to complete';

	/// en: 'Partially downloaded - Click to complete'
	String get partialDownloadClickToComplete => 'Partially downloaded - Click to complete';

	/// en: 'Deleting...'
	String get deleting => 'Deleting...';

	/// en: 'Deleting ${title}... (${current} of ${total})'
	String deletingWithProgress({required Object title, required Object current, required Object total}) => 'Deleting ${title}... (${current} of ${total})';

	/// en: 'Queued'
	String get queuedTooltip => 'Queued';

	/// en: 'Queued ${files}'
	String queuedFilesTooltip({required Object files}) => 'Queued ${files}';

	/// en: 'Downloading...'
	String get downloadingTooltip => 'Downloading...';

	/// en: 'Downloading ${files}'
	String downloadingFilesTooltip({required Object files}) => 'Downloading ${files}';

	/// en: 'No downloads'
	String get noDownloadsTree => 'No downloads';

	/// en: 'Pause all'
	String get pauseAll => 'Pause all';

	/// en: 'Resume all'
	String get resumeAll => 'Resume all';

	/// en: 'Delete all'
	String get deleteAll => 'Delete all';

	/// en: 'Select Version'
	String get selectVersion => 'Select Version';

	/// en: 'All episodes'
	String get allEpisodes => 'All episodes';

	/// en: 'Unwatched only'
	String get unwatchedOnly => 'Unwatched only';

	/// en: 'Next ${count} unwatched'
	String nextNUnwatched({required Object count}) => 'Next ${count} unwatched';

	/// en: 'Custom amount...'
	String get customAmount => 'Custom amount...';

	/// en: 'Include Specials'
	String get includeSpecials => 'Include Specials';

	/// en: 'How many episodes?'
	String get howManyEpisodes => 'How many episodes?';

	/// en: '${count} items queued for download'
	String itemsQueued({required Object count}) => '${count} items queued for download';

	/// en: 'Keep synced'
	String get keepSynced => 'Keep synced';

	/// en: 'Download once'
	String get downloadOnce => 'Download once';

	/// en: 'Keep ${count} unwatched'
	String keepNUnwatched({required Object count}) => 'Keep ${count} unwatched';

	/// en: 'Edit sync rule'
	String get editSyncRule => 'Edit sync rule';

	/// en: 'Remove sync rule'
	String get removeSyncRule => 'Remove sync rule';

	/// en: 'Stop syncing "${title}"? Downloaded episodes will be kept.'
	String removeSyncRuleConfirm({required Object title}) => 'Stop syncing "${title}"? Downloaded episodes will be kept.';

	/// en: 'Sync rule created — keeping ${count} unwatched episodes'
	String syncRuleCreated({required Object count}) => 'Sync rule created — keeping ${count} unwatched episodes';

	/// en: 'Sync rule updated'
	String get syncRuleUpdated => 'Sync rule updated';

	/// en: 'Sync rule removed'
	String get syncRuleRemoved => 'Sync rule removed';

	/// en: 'Synced ${count} new episodes for ${title}'
	String syncedNewEpisodes({required Object count, required Object title}) => 'Synced ${count} new episodes for ${title}';

	/// en: 'Sync rules'
	String get activeSyncRules => 'Sync rules';

	/// en: 'No sync rules'
	String get noSyncRules => 'No sync rules';

	/// en: 'Manage sync'
	String get manageSyncRule => 'Manage sync';

	/// en: 'Episode count'
	String get editEpisodeCount => 'Episode count';

	/// en: 'Sync filter'
	String get editSyncFilter => 'Sync filter';

	/// en: 'Syncing all items'
	String get syncAllItems => 'Syncing all items';

	/// en: 'Syncing unwatched items'
	String get syncUnwatchedItems => 'Syncing unwatched items';

	/// en: 'Server: ${server} • ${status}'
	String syncRuleServerContext({required Object server, required Object status}) => 'Server: ${server} • ${status}';

	/// en: 'Available'
	String get syncRuleAvailable => 'Available';

	/// en: 'Offline'
	String get syncRuleOffline => 'Offline';

	/// en: 'Sign in required'
	String get syncRuleSignInRequired => 'Sign in required';

	/// en: 'Not available for current profile'
	String get syncRuleNotAvailableForProfile => 'Not available for current profile';

	/// en: 'Unknown server'
	String get syncRuleUnknownServer => 'Unknown server';

	/// en: 'Sync rule created'
	String get syncRuleListCreated => 'Sync rule created';
}

// Path: shaders
class TranslationsShadersEn {
	TranslationsShadersEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Shaders'
	String get title => 'Shaders';

	/// en: 'No video enhancement'
	String get noShaderDescription => 'No video enhancement';

	/// en: 'NVIDIA image scaling for sharper video'
	String get nvscalerDescription => 'NVIDIA image scaling for sharper video';

	/// en: 'Neutral'
	String get artcnnVariantNeutral => 'Neutral';

	/// en: 'Denoise'
	String get artcnnVariantDenoise => 'Denoise';

	/// en: 'Denoise + Sharpen'
	String get artcnnVariantDenoiseSharpen => 'Denoise + Sharpen';

	/// en: 'Fast'
	String get qualityFast => 'Fast';

	/// en: 'High Quality'
	String get qualityHQ => 'High Quality';

	/// en: 'Mode'
	String get mode => 'Mode';

	/// en: 'Import Shader'
	String get importShader => 'Import Shader';

	/// en: 'Custom GLSL shader'
	String get customShaderDescription => 'Custom GLSL shader';

	/// en: 'Shader imported'
	String get shaderImported => 'Shader imported';

	/// en: 'Failed to import shader'
	String get shaderImportFailed => 'Failed to import shader';

	/// en: 'Delete Shader'
	String get deleteShader => 'Delete Shader';

	/// en: 'Delete "${name}"?'
	String deleteShaderConfirm({required Object name}) => 'Delete "${name}"?';
}

// Path: companionRemote
class TranslationsCompanionRemoteEn {
	TranslationsCompanionRemoteEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Companion Remote'
	String get title => 'Companion Remote';

	/// en: 'Connected to ${name}'
	String connectedTo({required Object name}) => 'Connected to ${name}';

	/// en: 'Unknown Device'
	String get unknownDevice => 'Unknown Device';

	late final TranslationsCompanionRemoteSessionEn session = TranslationsCompanionRemoteSessionEn.internal(_root);
	late final TranslationsCompanionRemotePairingEn pairing = TranslationsCompanionRemotePairingEn.internal(_root);
	late final TranslationsCompanionRemoteRemoteEn remote = TranslationsCompanionRemoteRemoteEn.internal(_root);
	late final TranslationsCompanionRemoteErrorsEn errors = TranslationsCompanionRemoteErrorsEn.internal(_root);
}

// Path: videoSettings
class TranslationsVideoSettingsEn {
	TranslationsVideoSettingsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Playback Speed'
	String get playbackSpeed => 'Playback Speed';

	/// en: 'Zoom'
	String get zoom => 'Zoom';

	/// en: 'Sleep Timer'
	String get sleepTimer => 'Sleep Timer';

	/// en: 'Audio Sync'
	String get audioSync => 'Audio Sync';

	/// en: 'Subtitle Sync'
	String get subtitleSync => 'Subtitle Sync';

	/// en: 'HDR'
	String get hdr => 'HDR';

	/// en: 'Audio Output'
	String get audioOutput => 'Audio Output';

	/// en: 'Performance Overlay'
	String get performanceOverlay => 'Performance Overlay';

	/// en: 'Audio Passthrough'
	String get audioPassthrough => 'Audio Passthrough';

	/// en: 'Audio Output Mode'
	String get audioOutputTitle => 'Audio Output Mode';

	late final TranslationsVideoSettingsAudioOutputModesEn audioOutputModes = TranslationsVideoSettingsAudioOutputModesEn.internal(_root);
	late final TranslationsVideoSettingsAudioOutputDecisionsEn audioOutputDecisions = TranslationsVideoSettingsAudioOutputDecisionsEn.internal(_root);
	late final TranslationsVideoSettingsAudioOutputModeDescriptionsEn audioOutputModeDescriptions = TranslationsVideoSettingsAudioOutputModeDescriptionsEn.internal(_root);
	late final TranslationsVideoSettingsAudioOutputRenderingEn audioOutputRendering = TranslationsVideoSettingsAudioOutputRenderingEn.internal(_root);

	/// en: 'now: ${mode}'
	String audioOutputNow({required Object mode}) => 'now: ${mode}';

	/// en: 'Normalize Loudness'
	String get audioNormalization => 'Normalize Loudness';

	/// en: 'Dolby passthrough is running, so volume levelling is paused. Your receiver sets the level.'
	String get audioNormalizationSuspended => 'Dolby passthrough is running, so volume levelling is paused. Your receiver sets the level.';

	/// en: 'Priority'
	String get audioPriorityTitle => 'Priority';

	late final TranslationsVideoSettingsAudioPrioritiesEn audioPriorities = TranslationsVideoSettingsAudioPrioritiesEn.internal(_root);

	/// en: 'Even out volume'
	String get audioLevelVolume => 'Even out volume';

	/// en: 'Brings every title to the same level as the rest of your TV'
	String get audioLevelVolumeDescription => 'Brings every title to the same level as the rest of your TV';

	/// en: 'Reduce loud sounds'
	String get audioReduceLoudSounds => 'Reduce loud sounds';

	/// en: 'Narrows the gap between dialogue and loud effects'
	String get audioReduceLoudSoundsDescription => 'Narrows the gap between dialogue and loud effects';

	/// en: 'Try lower quality'
	String get tryLowerQuality => 'Try lower quality';

	/// en: 'This output can't take a Dolby bitstream — switched to decoded audio.'
	String get audioPassthroughUnavailable => 'This output can\'t take a Dolby bitstream — switched to decoded audio.';
}

// Path: performanceOverlay
class TranslationsPerformanceOverlayEn {
	TranslationsPerformanceOverlayEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Color'
	String get color => 'Color';

	/// en: 'Performance'
	String get performance => 'Performance';

	/// en: 'Buffer'
	String get buffer => 'Buffer';

	/// en: 'App'
	String get app => 'App';

	/// en: 'Decoder'
	String get decoder => 'Decoder';

	/// en: 'Raw Decoder'
	String get rawDecoder => 'Raw Decoder';

	/// en: 'Tunneling'
	String get tunneling => 'Tunneling';

	/// en: 'Aspect'
	String get aspect => 'Aspect';

	/// en: 'Rotation'
	String get rotation => 'Rotation';

	/// en: 'DV Source'
	String get dvSource => 'DV Source';

	/// en: 'DV Path'
	String get dvPath => 'DV Path';

	/// en: 'P7 Conv'
	String get p7Conversion => 'P7 Conv';

	/// en: 'Sample Rate'
	String get sampleRate => 'Sample Rate';

	/// en: 'Audio Driver'
	String get audioDriver => 'Audio Driver';

	/// en: 'Out Format'
	String get audioOutFormat => 'Out Format';

	/// en: 'Requested'
	String get audioRequested => 'Requested';

	/// en: 'Actual'
	String get audioActual => 'Actual';

	/// en: 'measuring…'
	String get audioMeasuring => 'measuring…';

	/// en: 'bitstream'
	String get audioBitstream => 'bitstream';

	/// en: 'fell back'
	String get audioFellBack => 'fell back';

	/// en: 'Filters'
	String get audioFilters => 'Filters';

	/// en: 'none'
	String get audioFiltersNone => 'none';

	/// en: 'Volume'
	String get volume => 'Volume';

	/// en: 'Pixel Fmt'
	String get pixelFormat => 'Pixel Fmt';

	/// en: 'HW Fmt'
	String get hwFormat => 'HW Fmt';

	/// en: 'Matrix'
	String get matrix => 'Matrix';

	/// en: 'Primaries'
	String get primaries => 'Primaries';

	/// en: 'Transfer'
	String get transfer => 'Transfer';

	/// en: 'Render FPS'
	String get renderFps => 'Render FPS';

	/// en: 'Display FPS'
	String get displayFps => 'Display FPS';

	/// en: 'A/V Sync'
	String get avSync => 'A/V Sync';

	/// en: 'Dropped'
	String get dropped => 'Dropped';

	/// en: 'DV RPUs'
	String get dvRpus => 'DV RPUs';

	/// en: 'DV RPU Avg'
	String get dvRpuAverage => 'DV RPU Avg';

	/// en: 'DV Sample Avg'
	String get dvSampleAverage => 'DV Sample Avg';

	/// en: 'Max Luma'
	String get maxLuma => 'Max Luma';

	/// en: 'Min Luma'
	String get minLuma => 'Min Luma';

	/// en: 'MaxCLL'
	String get maxCll => 'MaxCLL';

	/// en: 'MaxFALL'
	String get maxFall => 'MaxFALL';

	/// en: 'Cache Used'
	String get cacheUsed => 'Cache Used';

	/// en: 'Cache Limit'
	String get cacheLimit => 'Cache Limit';

	/// en: 'Speed'
	String get speed => 'Speed';

	/// en: 'Player'
	String get player => 'Player';

	/// en: 'Memory'
	String get memory => 'Memory';

	/// en: 'UI FPS'
	String get uiFps => 'UI FPS';
}

// Path: externalPlayer
class TranslationsExternalPlayerEn {
	TranslationsExternalPlayerEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'External Player'
	String get title => 'External Player';

	/// en: 'Use External Player'
	String get useExternalPlayer => 'Use External Player';

	/// en: 'Open videos in another app'
	String get useExternalPlayerDescription => 'Open videos in another app';

	/// en: 'Select Player'
	String get selectPlayer => 'Select Player';

	/// en: 'Custom Players'
	String get customPlayers => 'Custom Players';

	/// en: 'System Default'
	String get systemDefault => 'System Default';

	/// en: 'Add Custom Player'
	String get addCustomPlayer => 'Add Custom Player';

	/// en: 'Player Name'
	String get playerName => 'Player Name';

	/// en: 'My Player'
	String get playerNameHint => 'My Player';

	/// en: 'Command'
	String get playerCommand => 'Command';

	/// en: 'Package Name'
	String get playerPackage => 'Package Name';

	/// en: 'URL Scheme'
	String get playerUrlScheme => 'URL Scheme';

	/// en: 'Off'
	String get off => 'Off';

	/// en: 'Failed to open external player'
	String get launchFailed => 'Failed to open external player';

	/// en: '${name} is not installed'
	String appNotInstalled({required Object name}) => '${name} is not installed';

	/// en: 'Play in External Player'
	String get playInExternalPlayer => 'Play in External Player';
}

// Path: metadataEdit
class TranslationsMetadataEditEn {
	TranslationsMetadataEditEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Edit...'
	String get editMetadata => 'Edit...';

	/// en: 'Edit Metadata'
	String get screenTitle => 'Edit Metadata';

	/// en: 'Basic Info'
	String get basicInfo => 'Basic Info';

	/// en: 'Artwork'
	String get artwork => 'Artwork';

	/// en: 'Advanced Settings'
	String get advancedSettings => 'Advanced Settings';

	/// en: 'Title'
	String get title => 'Title';

	/// en: 'Sort Title'
	String get sortTitle => 'Sort Title';

	/// en: 'Original Title'
	String get originalTitle => 'Original Title';

	/// en: 'Release Date'
	String get releaseDate => 'Release Date';

	/// en: 'Content Rating'
	String get contentRating => 'Content Rating';

	/// en: 'Studio'
	String get studio => 'Studio';

	/// en: 'Tagline'
	String get tagline => 'Tagline';

	/// en: 'Summary'
	String get summary => 'Summary';

	/// en: 'Poster'
	String get poster => 'Poster';

	/// en: 'Background'
	String get background => 'Background';

	/// en: 'Logo'
	String get logo => 'Logo';

	/// en: 'Square Art'
	String get squareArt => 'Square Art';

	/// en: 'Select Poster'
	String get selectPoster => 'Select Poster';

	/// en: 'Select Background'
	String get selectBackground => 'Select Background';

	/// en: 'Select Logo'
	String get selectLogo => 'Select Logo';

	/// en: 'Select Square Art'
	String get selectSquareArt => 'Select Square Art';

	/// en: 'From URL'
	String get fromUrl => 'From URL';

	/// en: 'Upload File'
	String get uploadFile => 'Upload File';

	/// en: 'Enter image URL'
	String get enterImageUrl => 'Enter image URL';

	/// en: 'Image URL'
	String get imageUrl => 'Image URL';

	/// en: 'Metadata updated'
	String get metadataUpdated => 'Metadata updated';

	/// en: 'Failed to update metadata'
	String get metadataUpdateFailed => 'Failed to update metadata';

	/// en: 'Artwork updated'
	String get artworkUpdated => 'Artwork updated';

	/// en: 'Failed to update artwork'
	String get artworkUpdateFailed => 'Failed to update artwork';

	/// en: 'No artwork available'
	String get noArtworkAvailable => 'No artwork available';

	/// en: 'Not set'
	String get notSet => 'Not set';

	/// en: 'Library default'
	String get libraryDefault => 'Library default';

	/// en: 'Account default'
	String get accountDefault => 'Account default';

	/// en: 'Series default'
	String get seriesDefault => 'Series default';

	/// en: 'Episode Sorting'
	String get episodeSorting => 'Episode Sorting';

	/// en: 'Oldest first'
	String get oldestFirst => 'Oldest first';

	/// en: 'Newest first'
	String get newestFirst => 'Newest first';

	/// en: 'Keep'
	String get keep => 'Keep';

	/// en: 'All episodes'
	String get allEpisodes => 'All episodes';

	/// en: '${count} latest episodes'
	String latestEpisodes({required Object count}) => '${count} latest episodes';

	/// en: 'Latest episode'
	String get latestEpisode => 'Latest episode';

	/// en: 'Episodes added in the past ${count} days'
	String episodesAddedPastDays({required Object count}) => 'Episodes added in the past ${count} days';

	/// en: 'Delete Episodes After Playing'
	String get deleteAfterPlaying => 'Delete Episodes After Playing';

	/// en: 'Never'
	String get never => 'Never';

	/// en: 'After a day'
	String get afterADay => 'After a day';

	/// en: 'After a week'
	String get afterAWeek => 'After a week';

	/// en: 'After a month'
	String get afterAMonth => 'After a month';

	/// en: 'On next refresh'
	String get onNextRefresh => 'On next refresh';

	/// en: 'Seasons'
	String get seasons => 'Seasons';

	/// en: 'Show'
	String get show => 'Show';

	/// en: 'Hide'
	String get hide => 'Hide';

	/// en: 'Episode Ordering'
	String get episodeOrdering => 'Episode Ordering';

	/// en: 'The Movie Database (Aired)'
	String get tmdbAiring => 'The Movie Database (Aired)';

	/// en: 'TheTVDB (Aired)'
	String get tvdbAiring => 'TheTVDB (Aired)';

	/// en: 'TheTVDB (Absolute)'
	String get tvdbAbsolute => 'TheTVDB (Absolute)';

	/// en: 'Metadata Language'
	String get metadataLanguage => 'Metadata Language';

	/// en: 'Use Original Title'
	String get useOriginalTitle => 'Use Original Title';

	/// en: 'Preferred Audio Language'
	String get preferredAudioLanguage => 'Preferred Audio Language';

	/// en: 'Preferred Subtitle Language'
	String get preferredSubtitleLanguage => 'Preferred Subtitle Language';

	/// en: 'Auto-Select Subtitle Mode'
	String get subtitleMode => 'Auto-Select Subtitle Mode';

	/// en: 'Manually selected'
	String get manuallySelected => 'Manually selected';

	/// en: 'Shown with foreign audio'
	String get shownWithForeignAudio => 'Shown with foreign audio';

	/// en: 'Always enabled'
	String get alwaysEnabled => 'Always enabled';

	/// en: 'Tags'
	String get tags => 'Tags';

	/// en: 'Add tag'
	String get addTag => 'Add tag';

	/// en: 'Genre'
	String get genre => 'Genre';

	/// en: 'Director'
	String get director => 'Director';

	/// en: 'Writer'
	String get writer => 'Writer';

	/// en: 'Producer'
	String get producer => 'Producer';

	/// en: 'Country'
	String get country => 'Country';

	/// en: 'Collection'
	String get collection => 'Collection';

	/// en: 'Label'
	String get label => 'Label';

	/// en: 'Style'
	String get style => 'Style';

	/// en: 'Mood'
	String get mood => 'Mood';
}

// Path: matchScreen
class TranslationsMatchScreenEn {
	TranslationsMatchScreenEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Match...'
	String get match => 'Match...';

	/// en: 'Fix Match...'
	String get fixMatch => 'Fix Match...';

	/// en: 'Unmatch'
	String get unmatch => 'Unmatch';

	/// en: 'Clear this match? Plex treats it as unmatched until rematched.'
	String get unmatchConfirm => 'Clear this match? Plex treats it as unmatched until rematched.';

	/// en: 'Item unmatched'
	String get unmatchSuccess => 'Item unmatched';

	/// en: 'Failed to unmatch item'
	String get unmatchFailed => 'Failed to unmatch item';

	/// en: 'Match applied'
	String get matchApplied => 'Match applied';

	/// en: 'Failed to apply match'
	String get matchFailed => 'Failed to apply match';

	/// en: 'Title'
	String get titleHint => 'Title';

	/// en: 'Year'
	String get yearHint => 'Year';

	/// en: 'Search'
	String get search => 'Search';

	/// en: 'No matches found'
	String get noMatchesFound => 'No matches found';
}

// Path: serverTasks
class TranslationsServerTasksEn {
	TranslationsServerTasksEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Server Tasks'
	String get title => 'Server Tasks';

	/// en: 'Failed to load tasks'
	String get failedToLoad => 'Failed to load tasks';

	/// en: 'No tasks running'
	String get noTasks => 'No tasks running';
}

// Path: seerr
class TranslationsSeerrEn {
	TranslationsSeerrEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Requests'
	String get title => 'Requests';

	/// en: 'Request movies and shows from your Jellyseerr or Overseerr server.'
	String get hubSubtitle => 'Request movies and shows from your Jellyseerr or Overseerr server.';

	/// en: 'Not configured'
	String get notConfigured => 'Not configured';

	/// en: 'Server URL'
	String get serverUrl => 'Server URL';

	/// en: 'https://requests.example.com'
	String get serverUrlHint => 'https://requests.example.com';

	/// en: 'Sign-in method'
	String get authMode => 'Sign-in method';

	/// en: 'Sign in with Plex'
	String get authPlex => 'Sign in with Plex';

	/// en: 'One-tap using your existing Plex login.'
	String get authPlexSubtitle => 'One-tap using your existing Plex login.';

	/// en: 'Email and password'
	String get authLocal => 'Email and password';

	/// en: 'API key'
	String get authApiKey => 'API key';

	/// en: 'Email'
	String get email => 'Email';

	/// en: 'Password'
	String get password => 'Password';

	/// en: 'API key'
	String get apiKey => 'API key';

	/// en: 'From Settings → General on your server'
	String get apiKeyHint => 'From Settings → General on your server';

	/// en: 'API-key mode files requests as the admin user. Sign in with Plex for per-user attribution.'
	String get adminAttributionNote => 'API-key mode files requests as the admin user. Sign in with Plex for per-user attribution.';

	/// en: 'Tip: this is easier to set up on your phone or computer.'
	String get setupOnDesktopNote => 'Tip: this is easier to set up on your phone or computer.';

	/// en: 'Test connection'
	String get testConnection => 'Test connection';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Disconnect'
	String get disconnect => 'Disconnect';

	/// en: 'Disconnect requests server?'
	String get disconnectConfirm => 'Disconnect requests server?';

	/// en: 'Pleya will stop sending requests. You can reconnect any time.'
	String get disconnectConfirmBody => 'Pleya will stop sending requests. You can reconnect any time.';

	/// en: 'Signed in as ${name}'
	String connectedAs({required Object name}) => 'Signed in as ${name}';

	/// en: 'Server version ${version}'
	String serverVersion({required Object version}) => 'Server version ${version}';

	/// en: 'Administrator'
	String get permissionAdmin => 'Administrator';

	/// en: 'Can approve requests'
	String get permissionManage => 'Can approve requests';

	/// en: 'Can request'
	String get permissionRequest => 'Can request';

	/// en: 'Request'
	String get request => 'Request';

	/// en: 'Requested'
	String get requested => 'Requested';

	/// en: 'Request'
	String get requestAgain => 'Request';

	/// en: 'Processing'
	String get processing => 'Processing';

	/// en: 'Partially available'
	String get partiallyAvailable => 'Partially available';

	/// en: 'Available'
	String get available => 'Available';

	/// en: 'Already requested'
	String get alreadyRequested => 'Already requested';

	/// en: 'Pending'
	String get pending => 'Pending';

	/// en: 'Approved'
	String get approved => 'Approved';

	/// en: 'Declined'
	String get declined => 'Declined';

	/// en: 'Failed'
	String get failed => 'Failed';

	/// en: 'Completed'
	String get completed => 'Completed';

	/// en: 'Request "${title}"?'
	String requestConfirm({required Object title}) => 'Request "${title}"?';

	/// en: 'Request movie'
	String get requestMovie => 'Request movie';

	/// en: 'Requested'
	String get requestSuccess => 'Requested';

	/// en: 'Request failed. Try again.'
	String get requestFailed => 'Request failed. Try again.';

	/// en: 'Select seasons'
	String get selectSeasons => 'Select seasons';

	/// en: 'Season ${number}'
	String season({required Object number}) => 'Season ${number}';

	/// en: 'All seasons'
	String get allSeasons => 'All seasons';

	/// en: 'Seasons ${range}'
	String seasonsRange({required Object range}) => 'Seasons ${range}';

	/// en: '${count} seasons'
	String seasonsCount({required Object count}) => '${count} seasons';

	/// en: 'Requested by ${name}'
	String requestedBy({required Object name}) => 'Requested by ${name}';

	/// en: 'Request in 4K'
	String get fourK => 'Request in 4K';

	/// en: '4K'
	String get fourKBadge => '4K';

	/// en: '${percent}% match'
	String percentMatch({required Object percent}) => '${percent}% match';

	/// en: '${remaining} of ${limit} requests left'
	String quotaRemaining({required Object remaining, required Object limit}) => '${remaining} of ${limit} requests left';

	/// en: 'Unlimited requests'
	String get quotaUnlimited => 'Unlimited requests';

	/// en: 'Advanced options'
	String get advancedOptions => 'Advanced options';

	/// en: 'Server'
	String get server => 'Server';

	/// en: 'Quality profile'
	String get qualityProfile => 'Quality profile';

	/// en: 'Root folder'
	String get rootFolder => 'Root folder';

	/// en: 'My requests'
	String get myRequests => 'My requests';

	/// en: 'All requests'
	String get allRequests => 'All requests';

	/// en: 'All'
	String get filterAll => 'All';

	/// en: 'Pending'
	String get filterPending => 'Pending';

	/// en: 'Approved'
	String get filterApproved => 'Approved';

	/// en: 'Available'
	String get filterAvailable => 'Available';

	/// en: 'Movies'
	String get filterMovies => 'Movies';

	/// en: 'Shows'
	String get filterShows => 'Shows';

	/// en: 'Approve'
	String get approve => 'Approve';

	/// en: 'Decline'
	String get decline => 'Decline';

	/// en: 'Edit'
	String get edit => 'Edit';

	/// en: 'Cancel request'
	String get cancelRequest => 'Cancel request';

	/// en: 'Cancel this request?'
	String get cancelRequestConfirm => 'Cancel this request?';

	/// en: 'Discover on Requests'
	String get discoverTitle => 'Discover on Requests';

	/// en: 'Trending'
	String get trending => 'Trending';

	/// en: 'Popular movies'
	String get popularMovies => 'Popular movies';

	/// en: 'Popular shows'
	String get popularTv => 'Popular shows';

	/// en: 'Upcoming'
	String get upcoming => 'Upcoming';

	/// en: 'Recommendations'
	String get recommendations => 'Recommendations';

	/// en: 'Cast'
	String get cast => 'Cast';

	/// en: 'Load more'
	String get loadMore => 'Load more';

	/// en: 'Not in your library? Search on Jellyseerr / Overseerr'
	String get searchOnSeerr => 'Not in your library? Search on Jellyseerr / Overseerr';

	/// en: 'Search on Requests'
	String get searchOnSeerrShort => 'Search on Requests';

	/// en: 'No results found.'
	String get noResults => 'No results found.';

	/// en: 'Sign-in failed. Check your credentials.'
	String get errorAuth => 'Sign-in failed. Check your credentials.';

	/// en: 'You don't have permission for that.'
	String get errorForbidden => 'You don\'t have permission for that.';

	/// en: 'Couldn't reach the server. Check the URL.'
	String get errorNetwork => 'Couldn\'t reach the server. Check the URL.';

	/// en: 'Something went wrong. Try again.'
	String get errorGeneric => 'Something went wrong. Try again.';

	/// en: 'Search for a movie or show to request'
	String get searchPlaceholder => 'Search for a movie or show to request';

	/// en: 'By streaming service'
	String get byStreamingService => 'By streaming service';

	/// en: 'Show all'
	String get showAll => 'Show all';
}

// Path: tautulli
class TranslationsTautulliEn {
	TranslationsTautulliEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Tautulli'
	String get title => 'Tautulli';

	/// en: 'Tautulli tracks who watches what on your Plex server. Connect it to see viewers, statistics and live activity inside Pleya.'
	String get subtitle => 'Tautulli tracks who watches what on your Plex server. Connect it to see viewers, statistics and live activity inside Pleya.';

	/// en: 'Tautulli has one key that opens its whole admin API, so it stays on this device and only you see what it reports. The people you share your server with are not affected and need to set up nothing.'
	String get adminOnlyNote => 'Tautulli has one key that opens its whole admin API, so it stays on this device and only you see what it reports. The people you share your server with are not affected and need to set up nothing.';

	/// en: 'Use history for recommendations'
	String get useHistoryForRecommendations => 'Use history for recommendations';

	/// en: 'Uses viewing history from this Tautulli server to improve personal recommendations for every profile on this device. Each profile only ever gets its own history, and processing stays local in Pleya.'
	String get useHistoryForRecommendationsDescription => 'Uses viewing history from this Tautulli server to improve personal recommendations for every profile on this device. Each profile only ever gets its own history, and processing stays local in Pleya.';

	/// en: 'Two different Tautulli pairings were found for this server, so history is not being used until you reconnect the one you want to keep.'
	String get integrationConflictNote => 'Two different Tautulli pairings were found for this server, so history is not being used until you reconnect the one you want to keep.';

	/// en: 'Tautulli address'
	String get serverUrl => 'Tautulli address';

	/// en: 'http://192.168.1.10:8181 or https://tautulli.example.com'
	String get serverUrlHint => 'http://192.168.1.10:8181 or https://tautulli.example.com';

	/// en: 'How to connect'
	String get authMode => 'How to connect';

	/// en: 'Device token'
	String get modeDevice => 'Device token';

	/// en: 'In Tautulli, open Settings, Tautulli Remote App, and register a device. Paste the generated token here within five minutes. Your permanent API key stays out of the app, and you can revoke this one device later.'
	String get modeDeviceHelp => 'In Tautulli, open Settings, Tautulli Remote App, and register a device. Paste the generated token here within five minutes. Your permanent API key stays out of the app, and you can revoke this one device later.';

	/// en: 'API key'
	String get modeApiKey => 'API key';

	/// en: 'The permanent key from Settings, Web Interface. It grants full access to Tautulli, so use it only if the device token does not work for you.'
	String get modeApiKeyHelp => 'The permanent key from Settings, Web Interface. It grants full access to Tautulli, so use it only if the device token does not work for you.';

	/// en: 'Device token'
	String get deviceToken => 'Device token';

	/// en: 'API key'
	String get apiKey => 'API key';

	/// en: 'Test connection'
	String get testConnection => 'Test connection';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Connected'
	String get connected => 'Connected';

	/// en: 'Disconnect'
	String get disconnect => 'Disconnect';

	/// en: 'Disconnect Tautulli?'
	String get disconnectConfirm => 'Disconnect Tautulli?';

	/// en: 'Pleya forgets the address and the token. Viewers, statistics and live activity disappear until you connect again.'
	String get disconnectConfirmBody => 'Pleya forgets the address and the token. Viewers, statistics and live activity disappear until you connect again.';

	/// en: 'Easier on your phone or computer: the address and token are long to type with a remote.'
	String get setupOnDesktopNote => 'Easier on your phone or computer: the address and token are long to type with a remote.';

	/// en: 'Could not reach Tautulli. Check the address and whether it is reachable from this device.'
	String get errorNetwork => 'Could not reach Tautulli. Check the address and whether it is reachable from this device.';

	/// en: 'Tautulli rejected this key.'
	String get errorAuth => 'Tautulli rejected this key.';

	/// en: 'Tautulli rejected this token. A device token is only valid for five minutes, so generate a new one and try again.'
	String get errorTokenExpired => 'Tautulli rejected this token. A device token is only valid for five minutes, so generate a new one and try again.';

	/// en: 'Tautulli rejected this token, and it looks like your permanent API key rather than a device token. Switch to API key above, or register a device in Tautulli and paste that token.'
	String get errorModeMismatch => 'Tautulli rejected this token, and it looks like your permanent API key rather than a device token. Switch to API key above, or register a device in Tautulli and paste that token.';

	/// en: 'Enter the address of your Tautulli server.'
	String get errorUrlRequired => 'Enter the address of your Tautulli server.';

	/// en: 'Enter a token.'
	String get errorTokenRequired => 'Enter a token.';

	/// en: 'Something answered at that address, but it was not Tautulli. Check the address and the base path, and whether a login page sits in front of it.'
	String get errorNotTautulli => 'Something answered at that address, but it was not Tautulli. Check the address and the base path, and whether a login page sits in front of it.';

	/// en: 'Tautulli reported a server error (HTTP ${code}).'
	String errorServer({required Object code}) => 'Tautulli reported a server error (HTTP ${code}).';

	/// en: 'Connecting failed.'
	String get errorGeneric => 'Connecting failed.';
}

// Path: nowWatching
class TranslationsNowWatchingEn {
	TranslationsNowWatchingEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Now watching'
	String get title => 'Now watching';

	/// en: 'See who is watching now'
	String get tooltip => 'See who is watching now';

	/// en: '${count} streams'
	String streams({required Object count}) => '${count} streams';

	/// en: '1 stream'
	String get oneStream => '1 stream';

	/// en: '${count} transcoding'
	String transcoding({required Object count}) => '${count} transcoding';

	/// en: 'Direct play'
	String get directPlay => 'Direct play';

	/// en: 'Direct stream'
	String get directStream => 'Direct stream';

	/// en: 'Transcode'
	String get transcode => 'Transcode';

	/// en: 'Paused'
	String get paused => 'Paused';

	/// en: '${time} left'
	String remaining({required Object time}) => '${time} left';

	/// en: '${name} is watching this now'
	String watchingNow({required Object name}) => '${name} is watching this now';

	/// en: 'Hardware'
	String get hardware => 'Hardware';

	/// en: 'On your network'
	String get onLan => 'On your network';

	/// en: 'Remote'
	String get onWan => 'Remote';

	/// en: 'Tautulli did not answer'
	String get unavailable => 'Tautulli did not answer';

	/// en: 'Now watching'
	String get sidebarLabel => 'Now watching';
}

// Path: trakt
class TranslationsTraktEn {
	TranslationsTraktEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Trakt'
	String get title => 'Trakt';

	/// en: 'Connected'
	String get connected => 'Connected';

	/// en: 'Connected as @${username}'
	String connectedAs({required Object username}) => 'Connected as @${username}';

	/// en: 'Disconnect Trakt account?'
	String get disconnectConfirm => 'Disconnect Trakt account?';

	/// en: 'Pleya will stop sending events to Trakt. You can reconnect any time.'
	String get disconnectConfirmBody => 'Pleya will stop sending events to Trakt. You can reconnect any time.';

	/// en: 'Real-time scrobbling'
	String get scrobble => 'Real-time scrobbling';

	/// en: 'Send play, pause, and stop events to Trakt during playback.'
	String get scrobbleDescription => 'Send play, pause, and stop events to Trakt during playback.';

	/// en: 'Sync watched status'
	String get watchedSync => 'Sync watched status';

	/// en: 'When you mark items watched in Pleya, mark them on Trakt.'
	String get watchedSyncDescription => 'When you mark items watched in Pleya, mark them on Trakt.';
}

// Path: trackers
class TranslationsTrackersEn {
	TranslationsTrackersEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Trackers'
	String get title => 'Trackers';

	/// en: 'Sync watch progress with Trakt and other services.'
	String get hubSubtitle => 'Sync watch progress with Trakt and other services.';

	/// en: 'Not connected'
	String get notConnected => 'Not connected';

	/// en: 'Connected as @${username}'
	String connectedAs({required Object username}) => 'Connected as @${username}';

	/// en: 'Track progress automatically'
	String get scrobble => 'Track progress automatically';

	/// en: 'Update your list when you finish an episode or movie.'
	String get scrobbleDescription => 'Update your list when you finish an episode or movie.';

	/// en: 'Disconnect ${service}?'
	String disconnectConfirm({required Object service}) => 'Disconnect ${service}?';

	/// en: 'Pleya will stop updating ${service}. Reconnect any time.'
	String disconnectConfirmBody({required Object service}) => 'Pleya will stop updating ${service}. Reconnect any time.';

	/// en: 'Couldn't connect to ${service}. Try again.'
	String connectFailed({required Object service}) => 'Couldn\'t connect to ${service}. Try again.';

	late final TranslationsTrackersServicesEn services = TranslationsTrackersServicesEn.internal(_root);
	late final TranslationsTrackersDeviceCodeEn deviceCode = TranslationsTrackersDeviceCodeEn.internal(_root);
	late final TranslationsTrackersOauthProxyEn oauthProxy = TranslationsTrackersOauthProxyEn.internal(_root);
	late final TranslationsTrackersLibraryFilterEn libraryFilter = TranslationsTrackersLibraryFilterEn.internal(_root);
}

// Path: addServer
class TranslationsAddServerEn {
	TranslationsAddServerEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Add Jellyfin server'
	String get addJellyfinTitle => 'Add Jellyfin server';

	/// en: 'Server URLs'
	String get serverUrls => 'Server URLs';

	/// en: 'Multiple URLs allowed, separated by commas.'
	String get serverUrlsHelper => 'Multiple URLs allowed, separated by commas.';

	/// en: 'Find server'
	String get findServer => 'Find server';

	/// en: 'Looking for local Jellyfin servers...'
	String get searchingLocalServers => 'Looking for local Jellyfin servers...';

	/// en: 'Local Jellyfin servers'
	String get localServers => 'Local Jellyfin servers';

	/// en: 'Username'
	String get username => 'Username';

	/// en: 'Password'
	String get password => 'Password';

	/// en: 'Sign in'
	String get signIn => 'Sign in';

	/// en: 'Change'
	String get change => 'Change';

	/// en: 'Required'
	String get required => 'Required';

	/// en: 'Could not reach the server'
	String get couldNotReachServer => 'Could not reach the server';

	/// en: 'Sign-in failed'
	String get signInFailed => 'Sign-in failed';

	/// en: 'Quick Connect failed'
	String get quickConnectFailed => 'Quick Connect failed';

	/// en: 'Sign in with Plex'
	String get addPlexTitle => 'Sign in with Plex';

	/// en: 'PIN expired before sign-in. Please try again.'
	String get pinExpired => 'PIN expired before sign-in. Please try again.';

	/// en: 'Already signed in to Plex. Sign out to switch accounts.'
	String get duplicatePlexAccount => 'Already signed in to Plex. Sign out to switch accounts.';

	/// en: 'Failed to register account'
	String get failedToRegisterAccount => 'Failed to register account';

	/// en: 'Enter your Jellyfin server URL'
	String get enterJellyfinUrlError => 'Enter your Jellyfin server URL';

	/// en: 'Add connection'
	String get addConnectionTitle => 'Add connection';

	/// en: 'Add to ${name}'
	String addConnectionTitleScoped({required Object name}) => 'Add to ${name}';

	/// en: 'Sign in with Plex'
	String get signInWithPlexCard => 'Sign in with Plex';

	/// en: 'Authorize this device. Shared servers are added.'
	String get signInWithPlexCardSubtitle => 'Authorize this device. Shared servers are added.';

	/// en: 'Authorize a Plex account. Home users become profiles.'
	String get signInWithPlexCardSubtitleScoped => 'Authorize a Plex account. Home users become profiles.';

	/// en: 'Connect to Jellyfin'
	String get connectToJellyfinCard => 'Connect to Jellyfin';

	/// en: 'Enter your server URL, username, and password.'
	String get connectToJellyfinCardSubtitle => 'Enter your server URL, username, and password.';

	/// en: 'Sign in to a Jellyfin server. Binds to ${name}.'
	String connectToJellyfinCardSubtitleScoped({required Object name}) => 'Sign in to a Jellyfin server. Binds to ${name}.';

	/// en: 'Borrow from another profile'
	String get borrowFromAnotherProfile => 'Borrow from another profile';

	/// en: 'Reuse another profile's connection. PIN-protected profiles require a PIN.'
	String get borrowFromAnotherProfileSubtitle => 'Reuse another profile\'s connection. PIN-protected profiles require a PIN.';
}

// Path: addLocalFolder
class TranslationsAddLocalFolderEn {
	TranslationsAddLocalFolderEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Local Folder'
	String get cardTitle => 'Local Folder';

	/// en: 'Browse media files from a folder on your device'
	String get cardSubtitle => 'Browse media files from a folder on your device';

	/// en: 'Add Local Folder'
	String get title => 'Add Local Folder';

	/// en: 'Select a folder on your device containing movies or TV shows. Pleya will scan the folder structure and list your media.'
	String get description => 'Select a folder on your device containing movies or TV shows. Pleya will scan the folder structure and list your media.';

	/// en: 'Library type'
	String get libraryType => 'Library type';

	/// en: 'Movies'
	String get typeMovies => 'Movies';

	/// en: 'TV Shows'
	String get typeTvShows => 'TV Shows';

	/// en: 'Mixed'
	String get typeMixed => 'Mixed';

	/// en: 'Directory'
	String get directory => 'Directory';

	/// en: 'Choose a directory…'
	String get chooseDirectory => 'Choose a directory…';

	/// en: 'Display name'
	String get nameLabel => 'Display name';

	/// en: 'e.g. My Movies'
	String get nameHint => 'e.g. My Movies';

	/// en: 'Add folder'
	String get save => 'Add folder';

	/// en: 'Failed to add local folder'
	String get saveError => 'Failed to add local folder';

	/// en: '${count} items found in folder'
	String entriesFound({required Object count}) => '${count} items found in folder';
}

// Path: pleyaShare
class TranslationsPleyaShareEn {
	TranslationsPleyaShareEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Pleya Share'
	String get cardTitle => 'Pleya Share';

	/// en: 'Connect to another Pleya device sharing its media'
	String get cardSubtitle => 'Connect to another Pleya device sharing its media';

	/// en: 'Share my media'
	String get hostTitle => 'Share my media';

	/// en: 'Other Pleya devices on this network can browse, stream, and download your local folders. Keep this screen open while sharing.'
	String get hostDescription => 'Other Pleya devices on this network can browse, stream, and download your local folders. Keep this screen open while sharing.';

	/// en: 'Other Pleya devices on this network can browse, stream, and download your local folders. Sharing keeps running while your device is locked.'
	String get hostDescriptionIos => 'Other Pleya devices on this network can browse, stream, and download your local folders. Sharing keeps running while your device is locked.';

	/// en: 'How Pleya Share works'
	String get howItWorksTitle => 'How Pleya Share works';

	/// en: 'One device is the server: it shares its local folders. Other Pleya devices pair once with the QR code or the 6-digit code and can then browse, stream, and download from it. • On newer devices (iOS 26+, most Android phones) devices also find each other directly via Wi-Fi Aware, with no hotspot or router at all. • Works over Wi-Fi, a personal hotspot, or a cable: ethernet adapters, or USB-C with USB tethering enabled on the host (Android, or iPhone to a computer). Direct iPhone-to-iPad over USB is not supported by iOS. No internet needed. • With internet on both devices, streaming also works remotely through the encrypted Pleya relay. • Paired devices reconnect automatically — pairing is needed only once. • Watch progress and artwork sync with your Plex or Jellyfin account when available.'
	String get howItWorksBody => 'One device is the server: it shares its local folders. Other Pleya devices pair once with the QR code or the 6-digit code and can then browse, stream, and download from it.\n\n• On newer devices (iOS 26+, most Android phones) devices also find each other directly via Wi-Fi Aware, with no hotspot or router at all.\n• Works over Wi-Fi, a personal hotspot, or a cable: ethernet adapters, or USB-C with USB tethering enabled on the host (Android, or iPhone to a computer). Direct iPhone-to-iPad over USB is not supported by iOS. No internet needed.\n• With internet on both devices, streaming also works remotely through the encrypted Pleya relay.\n• Paired devices reconnect automatically — pairing is needed only once.\n• Watch progress and artwork sync with your Plex or Jellyfin account when available.';

	/// en: 'Share local folders'
	String get hostToggle => 'Share local folders';

	/// en: 'Add a local folder first — there is nothing to share yet.'
	String get noLocalFolders => 'Add a local folder first — there is nothing to share yet.';

	/// en: 'Pairing code'
	String get pairCodeLabel => 'Pairing code';

	/// en: 'Enter this code on the other device. The code changes after each successful pairing.'
	String get pairCodeHint => 'Enter this code on the other device. The code changes after each successful pairing.';

	/// en: 'New code'
	String get regenerateCode => 'New code';

	/// en: 'Paired devices'
	String get pairedDevices => 'Paired devices';

	/// en: 'No devices paired yet'
	String get noGuests => 'No devices paired yet';

	/// en: 'Remove device'
	String get revokeGuest => 'Remove device';

	/// en: 'Connect to Pleya Share'
	String get joinTitle => 'Connect to Pleya Share';

	/// en: 'Pick a host found on your network or enter its address, then type the 6-digit code shown on that device.'
	String get joinDescription => 'Pick a host found on your network or enter its address, then type the 6-digit code shown on that device.';

	/// en: 'Hosts on your network'
	String get hostsFound => 'Hosts on your network';

	/// en: 'Searching for hosts…'
	String get searching => 'Searching for hosts…';

	/// en: 'No hosts found. Make sure sharing is turned on and both devices are on the same network.'
	String get noHostsFound => 'No hosts found. Make sure sharing is turned on and both devices are on the same network.';

	/// en: 'Search again'
	String get refresh => 'Search again';

	/// en: 'Host address (IP)'
	String get manualHost => 'Host address (IP)';

	/// en: '6-digit code'
	String get codeLabel => '6-digit code';

	/// en: 'Scan QR code'
	String get scanQr => 'Scan QR code';

	/// en: 'Point the camera at the QR code on the host device'
	String get scanQrHint => 'Point the camera at the QR code on the host device';

	/// en: 'Camera access is needed to scan the QR code.'
	String get cameraPermissionDenied => 'Camera access is needed to scan the QR code.';

	/// en: 'Connect'
	String get connect => 'Connect';

	/// en: 'Pairing failed. Check the code and try again.'
	String get pairFailed => 'Pairing failed. Check the code and try again.';

	/// en: 'Connected to $name'
	String paired({required Object name}) => 'Connected to ${name}';

	/// en: 'Host not reachable. Check the address and network.'
	String get pairUnreachable => 'Host not reachable. Check the address and network.';

	/// en: 'Add a local folder'
	String get addFolder => 'Add a local folder';

	/// en: 'Sharing media'
	String get notificationTitle => 'Sharing media';

	/// en: 'Other Pleya devices can stream your local folders'
	String get notificationText => 'Other Pleya devices can stream your local folders';

	/// en: 'Other Pleya devices on this network can browse, stream, and download your local folders. Sharing keeps running in the background with a notification.'
	String get hostDescriptionAndroid => 'Other Pleya devices on this network can browse, stream, and download your local folders. Sharing keeps running in the background with a notification.';

	/// en: 'Scanning the network…'
	String get scanningSubnet => 'Scanning the network…';
}

// Path: search.filters
class TranslationsSearchFiltersEn {
	TranslationsSearchFiltersEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'All'
	String get all => 'All';

	/// en: 'Movies'
	String get movies => 'Movies';

	/// en: 'Shows'
	String get shows => 'Shows';

	/// en: 'Episodes'
	String get episodes => 'Episodes';

	/// en: 'People'
	String get people => 'People';
}

// Path: hotkeys.actions
class TranslationsHotkeysActionsEn {
	TranslationsHotkeysActionsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Play/Pause'
	String get playPause => 'Play/Pause';

	/// en: 'Volume Up'
	String get volumeUp => 'Volume Up';

	/// en: 'Volume Down'
	String get volumeDown => 'Volume Down';

	/// en: 'Seek Forward (${seconds}s)'
	String seekForward({required Object seconds}) => 'Seek Forward (${seconds}s)';

	/// en: 'Seek Backward (${seconds}s)'
	String seekBackward({required Object seconds}) => 'Seek Backward (${seconds}s)';

	/// en: 'Toggle Fullscreen'
	String get fullscreenToggle => 'Toggle Fullscreen';

	/// en: 'Toggle Mute'
	String get muteToggle => 'Toggle Mute';

	/// en: 'Toggle Subtitles'
	String get subtitleToggle => 'Toggle Subtitles';

	/// en: 'Next Audio Track'
	String get audioTrackNext => 'Next Audio Track';

	/// en: 'Next Subtitle Track'
	String get subtitleTrackNext => 'Next Subtitle Track';

	/// en: 'Next Chapter'
	String get chapterNext => 'Next Chapter';

	/// en: 'Previous Chapter'
	String get chapterPrevious => 'Previous Chapter';

	/// en: 'Next Episode'
	String get episodeNext => 'Next Episode';

	/// en: 'Previous Episode'
	String get episodePrevious => 'Previous Episode';

	/// en: 'Increase Speed'
	String get speedIncrease => 'Increase Speed';

	/// en: 'Decrease Speed'
	String get speedDecrease => 'Decrease Speed';

	/// en: 'Reset Speed'
	String get speedReset => 'Reset Speed';

	/// en: 'Zoom In'
	String get zoomIn => 'Zoom In';

	/// en: 'Zoom Out'
	String get zoomOut => 'Zoom Out';

	/// en: 'Reset Zoom'
	String get zoomReset => 'Reset Zoom';

	/// en: 'Seek to Next Subtitle'
	String get subSeekNext => 'Seek to Next Subtitle';

	/// en: 'Seek to Previous Subtitle'
	String get subSeekPrev => 'Seek to Previous Subtitle';

	/// en: 'Toggle Shaders'
	String get shaderToggle => 'Toggle Shaders';

	/// en: 'Skip Intro/Credits'
	String get skipMarker => 'Skip Intro/Credits';

	/// en: 'Take Screenshot'
	String get screenshot => 'Take Screenshot';
}

// Path: videoControls.tvPanel
class TranslationsVideoControlsTvPanelEn {
	TranslationsVideoControlsTvPanelEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Information'
	String get information => 'Information';

	/// en: 'Audio'
	String get audio => 'Audio';

	/// en: 'Tracks'
	String get tracks => 'Tracks';

	/// en: 'Options'
	String get options => 'Options';

	/// en: 'More…'
	String get more => 'More…';
}

// Path: videoControls.pipErrors
class TranslationsVideoControlsPipErrorsEn {
	TranslationsVideoControlsPipErrorsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Requires Android 8.0 or newer'
	String get androidVersion => 'Requires Android 8.0 or newer';

	/// en: 'Requires iOS 15.0 or newer'
	String get iosVersion => 'Requires iOS 15.0 or newer';

	/// en: 'Picture-in-picture is disabled. Enable it in system settings.'
	String get permissionDisabled => 'Picture-in-picture is disabled. Enable it in system settings.';

	/// en: 'Device doesn't support picture-in-picture mode'
	String get notSupported => 'Device doesn\'t support picture-in-picture mode';

	/// en: 'Failed to switch video output for picture-in-picture'
	String get voSwitchFailed => 'Failed to switch video output for picture-in-picture';

	/// en: 'Picture-in-picture failed to start'
	String get failed => 'Picture-in-picture failed to start';

	/// en: 'An error occurred'
	String get unknown => 'An error occurred';
}

// Path: libraries.tabs
class TranslationsLibrariesTabsEn {
	TranslationsLibrariesTabsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Recommended'
	String get recommended => 'Recommended';

	/// en: 'Browse'
	String get browse => 'Browse';

	/// en: 'Collections'
	String get collections => 'Collections';

	/// en: 'Playlists'
	String get playlists => 'Playlists';
}

// Path: libraries.groupings
class TranslationsLibrariesGroupingsEn {
	TranslationsLibrariesGroupingsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Grouping'
	String get title => 'Grouping';

	/// en: 'All'
	String get all => 'All';

	/// en: 'Movies'
	String get movies => 'Movies';

	/// en: 'TV Shows'
	String get shows => 'TV Shows';

	/// en: 'Seasons'
	String get seasons => 'Seasons';

	/// en: 'Episodes'
	String get episodes => 'Episodes';

	/// en: 'Folders'
	String get folders => 'Folders';
}

// Path: libraries.filterCategories
class TranslationsLibrariesFilterCategoriesEn {
	TranslationsLibrariesFilterCategoriesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Genre'
	String get genre => 'Genre';

	/// en: 'Year'
	String get year => 'Year';

	/// en: 'Content Rating'
	String get contentRating => 'Content Rating';

	/// en: 'Tag'
	String get tag => 'Tag';

	/// en: 'Unwatched'
	String get unwatched => 'Unwatched';
}

// Path: libraries.sortLabels
class TranslationsLibrariesSortLabelsEn {
	TranslationsLibrariesSortLabelsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Title'
	String get title => 'Title';

	/// en: 'Date Added'
	String get dateAdded => 'Date Added';

	/// en: 'Release Date'
	String get releaseDate => 'Release Date';

	/// en: 'Rating'
	String get rating => 'Rating';

	/// en: 'Community Rating'
	String get communityRating => 'Community Rating';

	/// en: 'Critic Rating'
	String get criticRating => 'Critic Rating';

	/// en: 'User Rating'
	String get userRating => 'User Rating';

	/// en: 'Last Played'
	String get lastPlayed => 'Last Played';

	/// en: 'Date Played'
	String get datePlayed => 'Date Played';

	/// en: 'Play Count'
	String get playCount => 'Play Count';

	/// en: 'Production Year'
	String get productionYear => 'Production Year';

	/// en: 'Runtime'
	String get runtime => 'Runtime';

	/// en: 'Official Rating'
	String get officialRating => 'Official Rating';

	/// en: 'Premiere Date'
	String get premiereDate => 'Premiere Date';

	/// en: 'Start Date'
	String get startDate => 'Start Date';

	/// en: 'Air Time'
	String get airTime => 'Air Time';

	/// en: 'Studio'
	String get studio => 'Studio';

	/// en: 'Random'
	String get random => 'Random';

	/// en: 'Date Shared'
	String get dateShared => 'Date Shared';

	/// en: 'Latest Episode Air Date'
	String get latestEpisodeAirDate => 'Latest Episode Air Date';

	/// en: 'Last Episode Date Added'
	String get lastEpisodeDateAdded => 'Last Episode Date Added';
}

// Path: companionRemote.session
class TranslationsCompanionRemoteSessionEn {
	TranslationsCompanionRemoteSessionEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Starting remote server...'
	String get startingServer => 'Starting remote server...';

	/// en: 'Failed to start remote server:'
	String get failedToCreate => 'Failed to start remote server:';

	/// en: 'Host Address'
	String get hostAddress => 'Host Address';

	/// en: 'Connected'
	String get connected => 'Connected';

	/// en: 'Remote server active'
	String get serverRunning => 'Remote server active';

	/// en: 'Remote server stopped'
	String get serverStopped => 'Remote server stopped';

	/// en: 'Mobile devices on your network can connect to this app'
	String get serverRunningDescription => 'Mobile devices on your network can connect to this app';

	/// en: 'Start the server to allow mobile devices to connect'
	String get serverStoppedDescription => 'Start the server to allow mobile devices to connect';

	/// en: 'Use your mobile device to control this app'
	String get usePhoneToControl => 'Use your mobile device to control this app';

	/// en: 'Start Server'
	String get startServer => 'Start Server';

	/// en: 'Stop Server'
	String get stopServer => 'Stop Server';

	/// en: 'Minimize'
	String get minimize => 'Minimize';
}

// Path: companionRemote.pairing
class TranslationsCompanionRemotePairingEn {
	TranslationsCompanionRemotePairingEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Pleya devices with the same Plex account appear here'
	String get discoveryDescription => 'Pleya devices with the same Plex account appear here';

	/// en: '192.168.1.100:48632'
	String get hostAddressHint => '192.168.1.100:48632';

	/// en: 'Connecting...'
	String get connecting => 'Connecting...';

	/// en: 'Looking for devices...'
	String get searchingForDevices => 'Looking for devices...';

	/// en: 'No devices found on your network'
	String get noDevicesFound => 'No devices found on your network';

	/// en: 'Open Pleya on desktop and use the same WiFi'
	String get noDevicesHint => 'Open Pleya on desktop and use the same WiFi';

	/// en: 'Available Devices'
	String get availableDevices => 'Available Devices';

	/// en: 'Manual Connection'
	String get manualConnection => 'Manual Connection';

	/// en: 'Couldn't start secure connection. Sign in to Plex first.'
	String get cryptoInitFailed => 'Couldn\'t start secure connection. Sign in to Plex first.';

	/// en: 'Please enter host address'
	String get validationHostRequired => 'Please enter host address';

	/// en: 'Format must be IP:port (e.g., 192.168.1.100:48632)'
	String get validationHostFormat => 'Format must be IP:port (e.g., 192.168.1.100:48632)';

	/// en: 'Connection timed out. Use the same network on both devices.'
	String get connectionTimedOut => 'Connection timed out. Use the same network on both devices.';

	/// en: 'Device not found. Make sure Pleya is running on the host.'
	String get sessionNotFound => 'Device not found. Make sure Pleya is running on the host.';

	/// en: 'Authentication failed. Both devices need the same Plex account.'
	String get authFailed => 'Authentication failed. Both devices need the same Plex account.';

	/// en: 'Failed to connect'
	String get failedToConnect => 'Failed to connect';
}

// Path: companionRemote.remote
class TranslationsCompanionRemoteRemoteEn {
	TranslationsCompanionRemoteRemoteEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Do you want to disconnect from the remote session?'
	String get disconnectConfirm => 'Do you want to disconnect from the remote session?';

	/// en: 'Reconnecting...'
	String get reconnecting => 'Reconnecting...';

	/// en: 'Attempt ${current} of 5'
	String attemptOf({required Object current}) => 'Attempt ${current} of 5';

	/// en: 'Retry Now'
	String get retryNow => 'Retry Now';

	/// en: 'Remote'
	String get tabRemote => 'Remote';

	/// en: 'Play'
	String get tabPlay => 'Play';

	/// en: 'More'
	String get tabMore => 'More';

	/// en: 'Menu'
	String get menu => 'Menu';

	/// en: 'Tab Navigation'
	String get tabNavigation => 'Tab Navigation';

	/// en: 'Discover'
	String get tabDiscover => 'Discover';

	/// en: 'Libraries'
	String get tabLibraries => 'Libraries';

	/// en: 'Search'
	String get tabSearch => 'Search';

	/// en: 'Downloads'
	String get tabDownloads => 'Downloads';

	/// en: 'Settings'
	String get tabSettings => 'Settings';

	/// en: 'Previous'
	String get previous => 'Previous';

	/// en: 'Play/Pause'
	String get playPause => 'Play/Pause';

	/// en: 'Next'
	String get next => 'Next';

	/// en: 'Seek Back'
	String get seekBack => 'Seek Back';

	/// en: 'Stop'
	String get stop => 'Stop';

	/// en: 'Seek Fwd'
	String get seekForward => 'Seek Fwd';

	/// en: 'Volume'
	String get volume => 'Volume';

	/// en: 'Down'
	String get volumeDown => 'Down';

	/// en: 'Up'
	String get volumeUp => 'Up';

	/// en: 'Fullscreen'
	String get fullscreen => 'Fullscreen';

	/// en: 'Subtitles'
	String get subtitles => 'Subtitles';

	/// en: 'Audio'
	String get audio => 'Audio';

	/// en: 'Search on desktop...'
	String get searchHint => 'Search on desktop...';
}

// Path: companionRemote.errors
class TranslationsCompanionRemoteErrorsEn {
	TranslationsCompanionRemoteErrorsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'No network interface found'
	String get noNetworkInterface => 'No network interface found';

	/// en: 'Authentication failed'
	String get authenticationFailed => 'Authentication failed';

	/// en: 'Timed out joining session'
	String get joinTimedOut => 'Timed out joining session';

	/// en: 'Failed to connect to any address'
	String get failedToConnectAnyAddress => 'Failed to connect to any address';

	/// en: 'Connection lost after ${attempts} attempts'
	String connectionLostAfterAttempts({required Object attempts}) => 'Connection lost after ${attempts} attempts';

	/// en: 'Connection lost'
	String get connectionLost => 'Connection lost';
}

// Path: videoSettings.audioOutputModes
class TranslationsVideoSettingsAudioOutputModesEn {
	TranslationsVideoSettingsAudioOutputModesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Auto'
	String get auto => 'Auto';

	/// en: 'Passthrough'
	String get passthrough => 'Passthrough';

	/// en: 'PCM (decode)'
	String get pcm => 'PCM (decode)';
}

// Path: videoSettings.audioOutputDecisions
class TranslationsVideoSettingsAudioOutputDecisionsEn {
	TranslationsVideoSettingsAudioOutputDecisionsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Dolby bitstream'
	String get passthrough => 'Dolby bitstream';

	/// en: 'PCM multichannel'
	String get pcmMultichannel => 'PCM multichannel';

	/// en: 'PCM stereo'
	String get pcmStereo => 'PCM stereo';
}

// Path: videoSettings.audioOutputModeDescriptions
class TranslationsVideoSettingsAudioOutputModeDescriptionsEn {
	TranslationsVideoSettingsAudioOutputModeDescriptionsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Widens to multichannel where the output allows it; never bitstreams'
	String get auto => 'Widens to multichannel where the output allows it; never bitstreams';

	/// en: 'Always send Dolby untouched to the receiver'
	String get passthrough => 'Always send Dolby untouched to the receiver';

	/// en: 'Always decode in the app'
	String get pcm => 'Always decode in the app';
}

// Path: videoSettings.audioOutputRendering
class TranslationsVideoSettingsAudioOutputRenderingEn {
	TranslationsVideoSettingsAudioOutputRenderingEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Stereo'
	String get monoStereo => 'Stereo';

	/// en: 'Surround'
	String get surround => 'Surround';

	/// en: 'Spatial Audio'
	String get spatialAudio => 'Spatial Audio';

	/// en: 'Dolby Audio'
	String get dolbyAudio => 'Dolby Audio';

	/// en: 'Dolby Atmos'
	String get dolbyAtmos => 'Dolby Atmos';
}

// Path: videoSettings.audioPriorities
class TranslationsVideoSettingsAudioPrioritiesEn {
	TranslationsVideoSettingsAudioPrioritiesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Even volume'
	String get evenVolume => 'Even volume';

	/// en: 'Original Dolby Atmos'
	String get originalDolby => 'Original Dolby Atmos';
}

// Path: trackers.services
class TranslationsTrackersServicesEn {
	TranslationsTrackersServicesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'MyAnimeList'
	String get mal => 'MyAnimeList';

	/// en: 'AniList'
	String get anilist => 'AniList';

	/// en: 'Simkl'
	String get simkl => 'Simkl';
}

// Path: trackers.deviceCode
class TranslationsTrackersDeviceCodeEn {
	TranslationsTrackersDeviceCodeEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Activate Pleya on ${service}'
	String title({required Object service}) => 'Activate Pleya on ${service}';

	/// en: 'Visit ${url} and enter this code:'
	String body({required Object url}) => 'Visit ${url} and enter this code:';

	/// en: 'Open ${service} to activate'
	String openToActivate({required Object service}) => 'Open ${service} to activate';

	/// en: 'Waiting for authorization…'
	String get waitingForAuthorization => 'Waiting for authorization…';

	/// en: 'Code copied'
	String get codeCopied => 'Code copied';
}

// Path: trackers.oauthProxy
class TranslationsTrackersOauthProxyEn {
	TranslationsTrackersOauthProxyEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Sign in to ${service}'
	String title({required Object service}) => 'Sign in to ${service}';

	/// en: 'Scan this QR code or open the URL on any device.'
	String get body => 'Scan this QR code or open the URL on any device.';

	/// en: 'Open ${service} to sign in'
	String openToSignIn({required Object service}) => 'Open ${service} to sign in';

	/// en: 'URL copied'
	String get urlCopied => 'URL copied';
}

// Path: trackers.libraryFilter
class TranslationsTrackersLibraryFilterEn {
	TranslationsTrackersLibraryFilterEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Library filter'
	String get title => 'Library filter';

	/// en: 'Syncing all libraries'
	String get subtitleAllSyncing => 'Syncing all libraries';

	/// en: 'Nothing syncing'
	String get subtitleNoneSyncing => 'Nothing syncing';

	/// en: '${count} blocked'
	String subtitleBlocked({required Object count}) => '${count} blocked';

	/// en: '${count} allowed'
	String subtitleAllowed({required Object count}) => '${count} allowed';

	/// en: 'Filter mode'
	String get mode => 'Filter mode';

	/// en: 'Blacklist'
	String get modeBlacklist => 'Blacklist';

	/// en: 'Whitelist'
	String get modeWhitelist => 'Whitelist';

	/// en: 'Sync every library except the ones checked below.'
	String get modeHintBlacklist => 'Sync every library except the ones checked below.';

	/// en: 'Sync only the libraries checked below.'
	String get modeHintWhitelist => 'Sync only the libraries checked below.';

	/// en: 'Libraries'
	String get libraries => 'Libraries';

	/// en: 'No libraries available'
	String get noLibraries => 'No libraries available';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'states.emptyTitle' => 'Nothing here yet',
			'states.errorTitle' => 'Something went wrong',
			'states.offlineTitle' => 'You\'re offline',
			'states.offlineMessage' => 'Reconnect to load this content.',
			'app.title' => 'Pleya',
			'auth.signIn' => 'Sign in',
			'auth.signInWithPlex' => 'Sign in with Plex',
			'auth.showQRCode' => 'Show QR Code',
			'auth.authenticate' => 'Authenticate',
			'auth.authenticationTimeout' => 'Sign-in wasn\'t completed. Please try again.',
			'auth.scanQRToSignIn' => 'Scan this QR code to sign in',
			'auth.waitingForAuth' => 'Waiting for authentication...\nSign in from your browser.',
			'auth.useBrowser' => 'Use browser',
			'auth.or' => 'or',
			'auth.connectToJellyfin' => 'Connect to Jellyfin',
			'auth.useQuickConnect' => 'Use Quick Connect',
			'auth.quickConnectInstructions' => 'Open Quick Connect in Jellyfin and enter this code.',
			'auth.quickConnectWaiting' => 'Waiting for approval…',
			'auth.quickConnectCancel' => 'Cancel',
			'auth.quickConnectExpired' => 'Quick Connect expired. Try again.',
			'auth.chooseHowToSignIn' => 'Choose how to sign in',
			'auth.chooseHowToSignInDescription' => 'Pleya connects to your Plex or Jellyfin media server. Pick one to get started.',
			'auth.usingJellyfinInstead' => 'Using a Jellyfin server? Connect to Jellyfin instead',
			'auth.tryAgain' => 'Try again',
			'auth.plexTokenLabel' => 'Plex auth token',
			'auth.plexTokenHint' => 'Enter your plex.tv token',
			'auth.serviceNotReady' => 'Authentication service is not ready yet. Try again in a moment.',
			'common.cancel' => 'Cancel',
			'common.save' => 'Save',
			'common.close' => 'Close',
			'common.clear' => 'Clear',
			'common.reset' => 'Reset',
			'common.later' => 'Later',
			'common.submit' => 'Submit',
			'common.confirm' => 'Confirm',
			'common.retry' => 'Retry',
			'common.details' => 'Details',
			'common.logout' => 'Logout',
			'common.unknown' => 'Unknown',
			'common.refresh' => 'Refresh',
			'common.yes' => 'Yes',
			'common.no' => 'No',
			'common.delete' => 'Delete',
			'common.edit' => 'Edit',
			'common.shuffle' => 'Shuffle',
			'common.addTo' => 'Add to...',
			'common.createNew' => 'Create new',
			'common.connect' => 'Connect',
			'common.disconnect' => 'Disconnect',
			'common.play' => 'Play',
			'common.pause' => 'Pause',
			'common.resume' => 'Resume',
			'common.error' => 'Error',
			'common.search' => 'Search',
			'common.home' => 'Home',
			'common.back' => 'Back',
			'common.settings' => 'Settings',
			'common.mute' => 'Mute',
			'common.ok' => 'OK',
			'common.off' => 'Off',
			'common.on' => 'On',
			'common.seasonNumber' => ({required Object number}) => 'Season ${number}',
			'common.episodeNumberTitle' => ({required Object number, required Object title}) => 'Episode ${number} - ${title}',
			'common.chapterNumber' => ({required Object number}) => 'Chapter ${number}',
			'common.reconnect' => 'Reconnect',
			'common.exit' => 'Exit',
			'common.viewAll' => 'View All',
			'common.checkingNetwork' => 'Checking network...',
			'common.refreshingServers' => 'Refreshing servers...',
			'common.loadingServers' => 'Loading servers...',
			'common.connectingToServers' => 'Connecting to servers...',
			'common.startingOfflineMode' => 'Starting offline mode...',
			'common.loading' => 'Loading...',
			'common.fullscreen' => 'Fullscreen',
			'common.exitFullscreen' => 'Exit fullscreen',
			'common.pressBackAgainToExit' => 'Press back again to exit',
			'common.decreaseValue' => ({required Object label}) => 'Decrease ${label}',
			'common.increaseValue' => ({required Object label}) => 'Increase ${label}',
			'common.timedOut' => 'This took too long. Please try again.',
			'screens.licenses' => 'Licenses',
			'screens.switchProfile' => 'Switch Profile',
			'screens.whoIsWatching' => 'Who\'s watching?',
			'screens.manageProfiles' => 'Manage profiles',
			'screens.subtitleStyling' => 'Subtitle Styling',
			'screens.mpvConfig' => 'mpv.conf',
			'screens.logs' => 'Logs',
			'update.available' => 'Update Available',
			'update.versionAvailable' => ({required Object version}) => 'Version ${version} is available',
			'update.currentVersion' => ({required Object version}) => 'Current: ${version}',
			'update.skipVersion' => 'Skip This Version',
			'update.viewRelease' => 'View Release',
			'update.latestVersion' => 'You are on the latest version',
			'update.checkFailed' => 'Failed to check for updates',
			'settings.searchHint' => 'Search settings',
			'settings.urlLabel' => 'URL',
			'settings.title' => 'Settings',
			'settings.supportDeveloper' => 'Support Pleya',
			'settings.supportDeveloperDescription' => 'Donate via Liberapay to fund development',
			'settings.language' => 'Language',
			'settings.theme' => 'Theme',
			'settings.appearance' => 'Appearance',
			'settings.videoPlayback' => 'Video Playback',
			'settings.videoPlaybackDescription' => 'Configure playback behavior',
			'settings.advanced' => 'Advanced',
			'settings.episodePosterMode' => 'Episode Poster Style',
			'settings.seriesPoster' => 'Series Poster',
			'settings.seasonPoster' => 'Season Poster',
			'settings.episodeThumbnail' => 'Thumbnail',
			'settings.showHeroSectionDescription' => 'Display featured content carousel on home screen',
			'settings.secondsLabel' => 'Seconds',
			'settings.minutesLabel' => 'Minutes',
			'settings.secondsShort' => 's',
			'settings.minutesShort' => 'm',
			'settings.durationHint' => ({required Object min, required Object max}) => 'Enter duration (${min}-${max})',
			'settings.systemTheme' => 'System',
			'settings.lightTheme' => 'Light',
			'settings.darkTheme' => 'Dark',
			'settings.oledTheme' => 'OLED',
			'settings.libraryDensity' => 'Library Density',
			'settings.compact' => 'Compact',
			'settings.comfortable' => 'Comfortable',
			'settings.viewMode' => 'View Mode',
			'settings.gridView' => 'Grid',
			'settings.listView' => 'List',
			'settings.showHeroSection' => 'Show Hero Section',
			'settings.hoverExpandCards' => 'Hover-expand cards',
			'settings.hoverExpandCardsDescription' => 'Grow a preview card with quick actions when hovering a poster',
			'settings.continueWatchingAction' => 'Continue Watching Action',
			'settings.continueWatchingPlay' => 'Play',
			'settings.continueWatchingDetails' => 'Open Details',
			'settings.episodeAction' => 'Episode Action',
			'settings.episodePlay' => 'Play',
			'settings.episodeDetails' => 'Open Details',
			'settings.useGlobalHubs' => 'Use Home Layout',
			'settings.useGlobalHubsDescription' => 'Show unified home hubs. Otherwise use library recommendations.',
			'settings.showServerNameOnHubs' => 'Show Server Name on Hubs',
			'settings.showServerNameOnHubsDescription' => 'Always show server names in hub titles.',
			'settings.groupLibrariesByServer' => 'Group Libraries by Server',
			'settings.groupLibrariesByServerDescription' => 'Group sidebar libraries under each media server.',
			'settings.alwaysKeepSidebarOpen' => 'Always Keep Sidebar Open',
			'settings.alwaysKeepSidebarOpenDescription' => 'Sidebar stays expanded and content area adjusts to fit',
			'settings.showUnwatchedCount' => 'Show Unwatched Count',
			'settings.showUnwatchedCountDescription' => 'Display unwatched episode count on shows and seasons',
			'settings.showEpisodeNumberOnCards' => 'Show Episode Number on Cards',
			'settings.showEpisodeNumberOnCardsDescription' => 'Show season and episode number on episode cards',
			'settings.showSeasonPostersOnTabs' => 'Show Season Posters on Tabs',
			'settings.showSeasonPostersOnTabsDescription' => 'Show each season\'s poster above its tab',
			'settings.tvFullCardLayout' => 'Full TV Cards',
			'settings.tvFullCardLayoutDescription' => 'Use image-only TV cards with actor names overlaid',
			'settings.focusGlow' => 'Focus Glow',
			'settings.focusGlowDescription' => 'Draw a soft glow around the focused card',
			'settings.visualEffects' => 'Visual Effects',
			'settings.visualEffectsAuto' => 'Auto',
			'settings.visualEffectsAutoDescription' => 'Reduce effects automatically on low-power devices',
			'settings.visualEffectsFull' => 'Full',
			'settings.visualEffectsReduced' => 'Reduced',
			'settings.visualEffectsReducedDescription' => 'Fewer animations and lower-resolution artwork',
			'settings.hideSpoilers' => 'Hide Spoilers for Unwatched Episodes',
			'settings.hideSpoilersDescription' => 'Blur thumbnails and descriptions for unwatched episodes',
			'settings.playerBackend' => 'Player Backend',
			'settings.exoPlayer' => 'ExoPlayer (Recommended)',
			'settings.mpv' => 'mpv',
			'settings.hardwareDecoding' => 'Hardware Decoding',
			'settings.hardwareDecodingDescription' => 'Use hardware acceleration when available',
			'settings.bufferSize' => 'Buffer Size',
			'settings.bufferSizeMB' => ({required Object size}) => '${size}MB',
			'settings.bufferSizeAuto' => 'Auto (Recommended)',
			'settings.bufferSizeWarning' => ({required Object heap, required Object size}) => '${heap}MB memory available. A ${size}MB buffer may affect playback.',
			'settings.defaultQualityTitle' => 'Default Quality',
			'settings.defaultQualityDescription' => 'Used when starting playback. Lower values reduce bandwidth.',
			'settings.subtitleStyling' => 'Subtitle Styling',
			'settings.subtitleStylingDescription' => 'Customize subtitle appearance',
			'settings.smallSkipDuration' => 'Small Skip Duration',
			'settings.largeSkipDuration' => 'Large Skip Duration',
			'settings.rewindOnResume' => 'Rewind on Resume',
			'settings.secondsUnit' => ({required Object seconds}) => '${seconds} seconds',
			'settings.defaultSleepTimer' => 'Default Sleep Timer',
			'settings.minutesUnit' => ({required Object minutes}) => '${minutes} minutes',
			'settings.rememberTrackSelections' => 'Remember track selections per show/movie',
			'settings.rememberTrackSelectionsDescription' => 'Start the next episode in the audio and subtitle language you last picked by hand. Syncs to your other Apple devices via iCloud.',
			'settings.writeSeriesLanguageToServer' => 'Also save the language to Plex',
			'settings.writeSeriesLanguageToServerDescription' => 'Writes the language onto the show in Plex, so Android, Windows and the official Plex apps follow it too. Overwrites what you set by hand there.',
			'settings.showChapterMarkersOnTimeline' => 'Show chapter markers on seek bar',
			'settings.showChapterMarkersOnTimelineDescription' => 'Segment the seek bar at chapter boundaries',
			'settings.clickVideoTogglesPlayback' => 'Click on video to toggle play/pause',
			'settings.clickVideoTogglesPlaybackDescription' => 'Click video to play/pause instead of showing controls.',
			'settings.videoPlayerControls' => 'Video Player Controls',
			'settings.keyboardShortcuts' => 'Keyboard Shortcuts',
			'settings.keyboardShortcutsDescription' => 'Customize keyboard shortcuts',
			'settings.videoPlayerNavigation' => 'Video Player Navigation',
			'settings.videoPlayerNavigationDescription' => 'Use arrow keys to navigate video player controls',
			'settings.watchTogetherRelay' => 'Watch Together Relay',
			'settings.watchTogetherRelayDescription' => 'Set a custom relay. Everyone must use the same server.',
			'settings.watchTogetherRelayHint' => 'https://my-relay.example.com',
			'settings.crashReporting' => 'Crash Reporting',
			'settings.crashReportingDescription' => 'Send crash reports to help improve the app',
			'settings.debugLogging' => 'Debug Logging',
			'settings.debugLoggingDescription' => 'Enable detailed logging for troubleshooting',
			'settings.viewLogs' => 'View Logs',
			'settings.viewLogsDescription' => 'View application logs',
			'settings.clearCache' => 'Clear Cache',
			'settings.clearCacheDescription' => 'Clear cached images and data. Content may load slower.',
			'settings.clearCacheSuccess' => 'Cache cleared successfully',
			'settings.resetSettings' => 'Reset Settings',
			'settings.resetSettingsDescription' => 'Restore default settings. This can\'t be undone.',
			'settings.resetSettingsSuccess' => 'Settings reset successfully',
			'settings.backup' => 'Backup',
			'settings.exportSettings' => 'Export Settings',
			'settings.exportSettingsDescription' => 'Save your preferences to a file',
			'settings.exportSettingsSuccess' => 'Settings exported',
			'settings.exportSettingsFailed' => 'Could not export settings',
			'settings.importSettings' => 'Import Settings',
			'settings.importSettingsDescription' => 'Restore preferences from a file',
			'settings.importSettingsConfirm' => 'This will replace your current settings. Continue?',
			'settings.importSettingsSuccess' => 'Settings imported',
			'settings.importSettingsFailed' => 'Could not import settings',
			'settings.importSettingsInvalidFile' => 'This file isn\'t a valid Pleya settings export',
			'settings.importSettingsNoUser' => 'Sign in before importing settings',
			'settings.icloudSync' => 'Sync Settings via iCloud',
			'settings.icloudSyncDescription' => 'Keep your preferences in sync across your Apple devices',
			'settings.icloudSyncUnavailable' => 'Sign in to iCloud on this device to sync settings',
			'settings.icloudSyncNotSupported' => 'This device can\'t sync settings through iCloud',
			'settings.icloudSyncError' => 'Couldn\'t reach iCloud. Your settings will sync once it\'s back.',
			'settings.icloudSyncWarning' => 'Some settings were too large to sync and were skipped',
			'settings.icloudSyncEnableFailed' => 'Could not turn on iCloud settings sync',
			'settings.shortcutsReset' => 'Shortcuts reset to defaults',
			'settings.about' => 'About',
			'settings.aboutDescription' => 'App information and licenses',
			'settings.updates' => 'Updates',
			'settings.updateAvailable' => 'Update Available',
			'settings.checkForUpdates' => 'Check for Updates',
			'settings.autoCheckUpdatesOnStartup' => 'Automatically check for updates on startup',
			'settings.autoCheckUpdatesOnStartupDescription' => 'Notify when an update is available at launch',
			'settings.validationErrorEnterNumber' => 'Please enter a valid number',
			'settings.validationErrorDuration' => ({required Object min, required Object max, required Object unit}) => 'Duration must be between ${min} and ${max} ${unit}',
			'settings.shortcutAlreadyAssigned' => ({required Object action}) => 'Shortcut already assigned to ${action}',
			'settings.shortcutUpdated' => ({required Object action}) => 'Shortcut updated for ${action}',
			'settings.autoSkip' => 'Auto Skip',
			'settings.autoSkipIntro' => 'Auto Skip Intro',
			'settings.autoSkipIntroDescription' => 'Automatically skip intro markers in episodes after a few seconds',
			'settings.autoSkipCredits' => 'Auto Skip Credits',
			'settings.autoSkipCreditsDescription' => 'Automatically skip credits and play next episode',
			'settings.forceSkipMarkerFallback' => 'Force Fallback Markers',
			'settings.forceSkipMarkerFallbackDescription' => 'Use chapter title patterns even when Plex has markers',
			'settings.autoSkipDelay' => 'Auto Skip Delay',
			'settings.autoSkipDelayDescription' => ({required Object seconds}) => 'Wait ${seconds} seconds before auto-skipping',
			'settings.introPattern' => 'Intro Marker Pattern',
			'settings.introPatternDescription' => 'Regex pattern to match intro markers in chapter titles',
			'settings.creditsPattern' => 'Credits Marker Pattern',
			'settings.creditsPatternDescription' => 'Regex pattern to match credits markers in chapter titles',
			'settings.invalidRegex' => 'Invalid regular expression',
			'settings.downloads' => 'Downloads',
			'settings.downloadLocationDescription' => 'Choose where to store downloaded content',
			'settings.downloadLocationDefault' => 'Default (App Storage)',
			'settings.downloadLocationCustom' => 'Custom Location',
			'settings.selectFolder' => 'Select Folder',
			'settings.resetToDefault' => 'Reset to Default',
			'settings.currentPath' => ({required Object path}) => 'Current: ${path}',
			'settings.downloadLocationChanged' => 'Download location changed',
			'settings.downloadLocationReset' => 'Download location reset to default',
			'settings.downloadLocationInvalid' => 'Selected folder is not writable',
			'settings.downloadLocationSelectError' => 'Failed to select folder',
			'settings.downloadOnWifiOnly' => 'Download on WiFi only',
			'settings.downloadOnWifiOnlyDescription' => 'Prevent downloads when on cellular data',
			'settings.autoRemoveWatchedDownloads' => 'Auto-remove watched downloads',
			'settings.autoRemoveWatchedDownloadsDescription' => 'Delete watched downloads automatically',
			'settings.cellularDownloadBlocked' => 'Downloads are blocked on cellular. Use WiFi or change the setting.',
			'settings.maxVolume' => 'Maximum Volume',
			'settings.maxVolumeDescription' => 'Allow volume boost above 100% for quiet media',
			'settings.maxVolumePercent' => ({required Object percent}) => '${percent}%',
			'settings.discordRichPresence' => 'Discord Rich Presence',
			'settings.discordRichPresenceDescription' => 'Show what you\'re watching on Discord',
			'settings.trakt' => 'Trakt',
			'settings.traktDescription' => 'Sync watch history with Trakt',
			'settings.trackers' => 'Trackers',
			'settings.trackersDescription' => 'Sync progress to Trakt, MyAnimeList, AniList, and Simkl',
			'settings.requests' => 'Requests',
			'settings.requestsDescription' => 'Request movies and shows via Jellyseerr or Overseerr',
			'settings.libraryVisibility' => 'Library Visibility',
			'settings.libraryVisibilityDescription' => 'Choose which libraries appear in the menu',
			'settings.homeLayout' => 'Home Layout',
			'settings.homeLayoutDescription' => 'Reorder or hide the rows on the home screen',
			'settings.homeLayoutEmpty' => 'Open the home screen once so the rows can be loaded',
			'settings.homeLayoutMoveUp' => 'Move up',
			'settings.homeLayoutMoveDown' => 'Move down',
			'settings.companionRemoteServer' => 'Companion Remote Server',
			'settings.companionRemoteServerDescription' => 'Allow mobile devices on your network to control this app',
			'settings.autoPip' => 'Auto Picture-in-Picture',
			'settings.autoPipDescription' => 'Enter picture-in-picture when leaving during playback',
			'settings.matchContentFrameRate' => 'Match Content Frame Rate',
			'settings.matchContentFrameRateDescription' => 'Match display refresh rate to video content',
			'settings.matchRefreshRate' => 'Match Refresh Rate',
			'settings.matchRefreshRateDescription' => 'Match display refresh rate in fullscreen',
			'settings.matchDynamicRange' => 'Match Dynamic Range',
			'settings.matchDynamicRangeDescription' => 'Switch HDR on for HDR content, then back to SDR',
			'settings.displaySwitchDelay' => 'Display Switch Delay',
			'settings.tunneledPlayback' => 'Tunneled Playback',
			'settings.tunneledPlaybackDescription' => 'Use video tunneling. Disable if HDR playback shows black video.',
			'settings.dvConversionMode' => 'Dolby Vision Conversion',
			'settings.dvConversionModeDescription' => 'Choose how ExoPlayer handles Dolby Vision Profile 7 files.',
			'settings.dvConversionAuto' => 'Auto',
			'settings.dvConversionNative' => 'Native / Disabled',
			'settings.dvConversionDv81' => 'P7 → P8.1',
			'settings.dvConversionHevcStrip' => 'P7 → HEVC',
			'settings.dvConversionAutoDescription' => 'Use device capability detection and normal fallback behavior',
			'settings.dvConversionNativeDescription' => 'Force native DV7 and suppress DV conversion retry',
			'settings.dvConversionDv81Description' => 'Force inline RPU conversion to Dolby Vision profile 8.1',
			'settings.dvConversionHevcStripDescription' => 'Strip Dolby Vision RPU/EL layers and present plain HEVC',
			'settings.requireProfileSelectionOnOpen' => 'Ask for profile on app open',
			'settings.requireProfileSelectionOnOpenDescription' => 'Show profile selection every time the app is opened',
			'settings.forceTvMode' => 'Force TV mode',
			'settings.forceTvModeDescription' => 'Force TV layout. For devices that don\'t auto-detect. Requires restart.',
			'settings.startInFullscreen' => 'Start in fullscreen',
			'settings.startInFullscreenDescription' => 'Open Pleya in fullscreen mode at launch',
			'settings.exitFullscreenOnPlayerClose' => 'Exit fullscreen on player close',
			'settings.exitFullscreenOnPlayerCloseDescription' => 'Automatically exit fullscreen when closing the video player',
			'settings.autoHidePerformanceOverlay' => 'Auto-Hide Performance Overlay',
			'settings.autoHidePerformanceOverlayDescription' => 'Fade the performance overlay with the playback controls',
			'settings.showNavBarLabels' => 'Show Navigation Bar Labels',
			'settings.showNavBarLabelsDescription' => 'Display text labels under navigation bar icons',
			'settings.startupSection' => 'Startup Section',
			'settings.startupSectionDescription' => 'Choose which section Pleya opens to when it starts',
			'settings.liveTvDefaultFavorites' => 'Default to Favorite Channels',
			'settings.liveTvDefaultFavoritesDescription' => 'Show only favorite channels when opening Live TV',
			'settings.display' => 'Display',
			'settings.homeScreen' => 'Home Screen',
			'settings.navigation' => 'Navigation',
			'settings.window' => 'Window',
			'settings.content' => 'Content',
			'settings.player' => 'Player',
			'settings.subtitlesAndConfig' => 'Subtitles & Configuration',
			'settings.seekAndTiming' => 'Seek & Timing',
			'settings.audio' => 'Audio',
			'settings.audioSyncOffsetDescription' => 'Shift audio relative to video for every title',
			'settings.behavior' => 'Behavior',
			'settings.personalizedRecommendations' => 'Personalized recommendations',
			'settings.personalizedRecommendationsDescription' => 'Learn your taste on this device to suggest Top Picks and more. Nothing leaves your device.',
			'settings.sectionLibrary' => 'App & playback',
			'search.hint' => 'Search movies, shows, music...',
			'search.tryDifferentTerm' => 'Try a different search term',
			'search.searchYourMedia' => 'Search your media',
			'search.enterTitleActorOrKeyword' => 'Enter a title, actor, or keyword',
			'search.recentSearches' => 'Recent searches',
			'search.clearHistory' => 'Clear',
			'search.filters.all' => 'All',
			'search.filters.movies' => 'Movies',
			'search.filters.shows' => 'Shows',
			'search.filters.episodes' => 'Episodes',
			'search.filters.people' => 'People',
			'search.errorTitle' => 'Search failed',
			'search.errorNetwork' => 'Couldn\'t reach your servers. Check your connection and try again.',
			'search.noServersTitle' => 'No servers available',
			'search.noServersBody' => 'Add or connect a server to search your media.',
			'search.voiceSearch' => 'Voice search',
			'hotkeys.setShortcutFor' => ({required Object actionName}) => 'Set Shortcut for ${actionName}',
			'hotkeys.clearShortcut' => 'Clear shortcut',
			'hotkeys.noShortcutSet' => 'No shortcut set',
			'hotkeys.currentShortcut' => 'Current shortcut:',
			'hotkeys.actions.playPause' => 'Play/Pause',
			'hotkeys.actions.volumeUp' => 'Volume Up',
			'hotkeys.actions.volumeDown' => 'Volume Down',
			'hotkeys.actions.seekForward' => ({required Object seconds}) => 'Seek Forward (${seconds}s)',
			'hotkeys.actions.seekBackward' => ({required Object seconds}) => 'Seek Backward (${seconds}s)',
			'hotkeys.actions.fullscreenToggle' => 'Toggle Fullscreen',
			'hotkeys.actions.muteToggle' => 'Toggle Mute',
			'hotkeys.actions.subtitleToggle' => 'Toggle Subtitles',
			'hotkeys.actions.audioTrackNext' => 'Next Audio Track',
			'hotkeys.actions.subtitleTrackNext' => 'Next Subtitle Track',
			'hotkeys.actions.chapterNext' => 'Next Chapter',
			'hotkeys.actions.chapterPrevious' => 'Previous Chapter',
			'hotkeys.actions.episodeNext' => 'Next Episode',
			'hotkeys.actions.episodePrevious' => 'Previous Episode',
			'hotkeys.actions.speedIncrease' => 'Increase Speed',
			'hotkeys.actions.speedDecrease' => 'Decrease Speed',
			'hotkeys.actions.speedReset' => 'Reset Speed',
			'hotkeys.actions.zoomIn' => 'Zoom In',
			'hotkeys.actions.zoomOut' => 'Zoom Out',
			'hotkeys.actions.zoomReset' => 'Reset Zoom',
			'hotkeys.actions.subSeekNext' => 'Seek to Next Subtitle',
			'hotkeys.actions.subSeekPrev' => 'Seek to Previous Subtitle',
			'hotkeys.actions.shaderToggle' => 'Toggle Shaders',
			'hotkeys.actions.skipMarker' => 'Skip Intro/Credits',
			'hotkeys.actions.screenshot' => 'Take Screenshot',
			'fileInfo.title' => 'File Info',
			'fileInfo.video' => 'Video',
			'fileInfo.audio' => 'Audio',
			'fileInfo.file' => 'File',
			'fileInfo.advanced' => 'Advanced',
			'fileInfo.codec' => 'Codec',
			'fileInfo.resolution' => 'Resolution',
			'fileInfo.bitrate' => 'Bitrate',
			'fileInfo.frameRate' => 'Frame Rate',
			'fileInfo.aspectRatio' => 'Aspect Ratio',
			'fileInfo.profile' => 'Profile',
			'fileInfo.bitDepth' => 'Bit Depth',
			'fileInfo.colorSpace' => 'Color Space',
			'fileInfo.colorRange' => 'Color Range',
			'fileInfo.colorPrimaries' => 'Color Primaries',
			'fileInfo.chromaSubsampling' => 'Chroma Subsampling',
			'fileInfo.channels' => 'Channels',
			'fileInfo.subtitles' => 'Subtitles',
			'fileInfo.overallBitrate' => 'Overall Bitrate',
			'fileInfo.path' => 'Path',
			'fileInfo.size' => 'Size',
			'fileInfo.container' => 'Container',
			'fileInfo.duration' => 'Duration',
			'fileInfo.optimizedForStreaming' => 'Optimized for Streaming',
			'fileInfo.has64bitOffsets' => '64-bit Offsets',
			'mediaMenu.markAsWatched' => 'Mark as Watched',
			'mediaMenu.markAsUnwatched' => 'Mark as Unwatched',
			'mediaMenu.removeFromContinueWatching' => 'Remove from Continue Watching',
			'mediaMenu.viewDetails' => 'View details',
			'mediaMenu.goToSeries' => 'Go to series',
			'mediaMenu.shufflePlay' => 'Shuffle Play',
			'mediaMenu.shuffleNotAvailableOffline' => 'Shuffle not available offline',
			'mediaMenu.fileInfo' => 'File Info',
			'mediaMenu.deleteFromServer' => 'Delete from server',
			'mediaMenu.confirmDelete' => 'Delete this media and its files from your server?',
			'mediaMenu.deleteMultipleWarning' => 'This includes all episodes and their files.',
			'mediaMenu.mediaDeletedSuccessfully' => 'Media item deleted successfully',
			'mediaMenu.mediaFailedToDelete' => 'Failed to delete media item',
			'mediaMenu.rate' => 'Rate',
			'mediaMenu.playFromBeginning' => 'Play from Beginning',
			'mediaMenu.playVersion' => 'Play Version...',
			'rateSheet.title' => 'Rate',
			'rateSheet.server' => 'Server',
			'rateSheet.starValue' => ({required Object rating}) => '${rating} / 5',
			'rateSheet.scoreValue' => ({required Object score}) => '${score} / 10',
			'rateSheet.setScore' => 'Set a score',
			'rateSheet.notRated' => 'Not rated',
			'rateSheet.liked' => 'Liked',
			'rateSheet.notLiked' => 'Not liked',
			'rateSheet.saved' => 'Saved',
			'rateSheet.notAvailable' => 'No match found',
			'rateSheet.noConnectedTrackers' => 'Connect a tracker in Settings to rate there.',
			'accessibility.mediaCardMovie' => ({required Object title}) => '${title}, movie',
			'accessibility.mediaCardShow' => ({required Object title}) => '${title}, TV show',
			'accessibility.mediaCardEpisode' => ({required Object title, required Object episodeInfo}) => '${title}, ${episodeInfo}',
			'accessibility.mediaCardSeason' => ({required Object title, required Object seasonInfo}) => '${title}, ${seasonInfo}',
			'accessibility.mediaCardWatched' => 'watched',
			'accessibility.mediaCardPartiallyWatched' => ({required Object percent}) => '${percent} percent watched',
			'accessibility.mediaCardUnwatched' => 'unwatched',
			'accessibility.tapToPlay' => 'Tap to play',
			'tooltips.shufflePlay' => 'Shuffle play',
			'tooltips.playTrailer' => 'Play trailer',
			'tooltips.markAsWatched' => 'Mark as watched',
			'tooltips.markAsUnwatched' => 'Mark as unwatched',
			'videoControls.audioLabel' => 'Audio',
			'videoControls.subtitlesLabel' => 'Subtitles',
			'videoControls.resetToZero' => 'Reset to 0ms',
			'videoControls.addTime' => ({required Object amount, required Object unit}) => '+${amount}${unit}',
			'videoControls.minusTime' => ({required Object amount, required Object unit}) => '-${amount}${unit}',
			'videoControls.playsLater' => ({required Object label}) => '${label} plays later',
			'videoControls.playsEarlier' => ({required Object label}) => '${label} plays earlier',
			'videoControls.noOffset' => 'No offset',
			'videoControls.letterbox' => 'Letterbox',
			'videoControls.fillScreen' => 'Fill screen',
			'videoControls.stretch' => 'Stretch',
			'videoControls.lockRotation' => 'Lock rotation',
			'videoControls.unlockRotation' => 'Unlock rotation',
			'videoControls.timerActive' => 'Timer Active',
			'videoControls.playbackWillPauseIn' => ({required Object duration}) => 'Playback will pause in ${duration}',
			'videoControls.sleepTimerEndOfVideo' => 'End of current video',
			'videoControls.sleepTimerStopAtHeader' => 'Stop at',
			'videoControls.sleepTimerDurationHeader' => 'Timer',
			'videoControls.playbackWillPauseAtEnd' => 'Playback will pause at the end of this video',
			'videoControls.stillWatching' => 'Still watching?',
			'videoControls.pausingIn' => ({required Object seconds}) => 'Pausing in ${seconds}s',
			'videoControls.continueWatching' => 'Continue',
			'videoControls.autoPlayNext' => 'Auto-Play Next',
			'videoControls.playNext' => 'Play Next',
			'videoControls.nextEpisode' => 'Next Episode',
			'videoControls.skipIntro' => 'Skip Intro',
			'videoControls.skipCredits' => 'Skip Credits',
			'videoControls.playButton' => 'Play',
			'videoControls.pauseButton' => 'Pause',
			'videoControls.seekBackwardButton' => ({required Object seconds}) => 'Seek backward ${seconds} seconds',
			'videoControls.seekForwardButton' => ({required Object seconds}) => 'Seek forward ${seconds} seconds',
			'videoControls.previousButton' => 'Previous episode',
			'videoControls.nextButton' => 'Next episode',
			'videoControls.previousChapterButton' => 'Previous chapter',
			'videoControls.nextChapterButton' => 'Next chapter',
			'videoControls.muteButton' => 'Mute',
			'videoControls.unmuteButton' => 'Unmute',
			'videoControls.settingsButton' => 'Playback Settings',
			'videoControls.tracksButton' => 'Audio & Subtitles',
			'videoControls.chaptersButton' => 'Chapters',
			'videoControls.versionsButton' => 'Video versions',
			'videoControls.versionQualityButton' => 'Version & Quality',
			'videoControls.versionColumnHeader' => 'Version',
			'videoControls.qualityColumnHeader' => 'Quality',
			'videoControls.qualityOriginal' => 'Original',
			'videoControls.qualityPresetLabel' => ({required Object resolution, required Object bitrate}) => '${resolution}p ${bitrate} Mbps',
			'videoControls.qualityBandwidthEstimate' => ({required Object bitrate}) => '~${bitrate} Mbps',
			'videoControls.transcodeUnavailableFallback' => 'Transcoding unavailable — playing original quality',
			'videoControls.pipButton' => 'Picture-in-Picture mode',
			'videoControls.aspectRatioButton' => 'Aspect ratio',
			'videoControls.ambientLighting' => 'Ambient lighting',
			'videoControls.ambientIntensitySubtle' => 'Subtle',
			'videoControls.ambientIntensityBalanced' => 'Balanced',
			'videoControls.ambientIntensityBright' => 'Bright',
			'videoControls.tvPanel.information' => 'Information',
			'videoControls.tvPanel.audio' => 'Audio',
			'videoControls.tvPanel.tracks' => 'Tracks',
			'videoControls.tvPanel.options' => 'Options',
			'videoControls.tvPanel.more' => 'More…',
			'videoControls.fullscreenButton' => 'Enter fullscreen',
			'videoControls.exitFullscreenButton' => 'Exit fullscreen',
			'videoControls.alwaysOnTopButton' => 'Always on top',
			'videoControls.rotationLockButton' => 'Rotation lock',
			'videoControls.lockScreen' => 'Lock screen',
			'videoControls.screenLockButton' => 'Screen lock',
			_ => null,
		} ?? switch (path) {
			'videoControls.longPressToUnlock' => 'Long press to unlock',
			'videoControls.timelineSlider' => 'Video timeline',
			'videoControls.volumeSlider' => 'Volume level',
			'videoControls.volumeHandledByDevice' => 'Volume is controlled by your audio device during passthrough',
			'videoControls.endsAt' => ({required Object time}) => 'Ends at ${time}',
			'videoControls.pipActive' => 'Playing in Picture-in-Picture',
			'videoControls.pipFailed' => 'Picture-in-picture failed to start',
			'videoControls.screenshotSaved' => 'Screenshot saved',
			'videoControls.zoomPercent' => ({required Object percent}) => 'Zoom ${percent}%',
			'videoControls.pipErrors.androidVersion' => 'Requires Android 8.0 or newer',
			'videoControls.pipErrors.iosVersion' => 'Requires iOS 15.0 or newer',
			'videoControls.pipErrors.permissionDisabled' => 'Picture-in-picture is disabled. Enable it in system settings.',
			'videoControls.pipErrors.notSupported' => 'Device doesn\'t support picture-in-picture mode',
			'videoControls.pipErrors.voSwitchFailed' => 'Failed to switch video output for picture-in-picture',
			'videoControls.pipErrors.failed' => 'Picture-in-picture failed to start',
			'videoControls.pipErrors.unknown' => 'An error occurred',
			'videoControls.chapters' => 'Chapters',
			'videoControls.noChaptersAvailable' => 'No chapters available',
			'videoControls.queue' => 'Queue',
			'videoControls.noQueueItems' => 'No items in queue',
			'videoControls.searchSubtitles' => 'Search Subtitles',
			'videoControls.language' => 'Language',
			'videoControls.noSubtitlesFound' => 'No subtitles found',
			'videoControls.downloadedSubtitle' => 'Downloaded',
			'videoControls.noSubtitlesAvailable' => 'No subtitles available',
			'videoControls.noAudioTracksAvailable' => 'No audio tracks available',
			'videoControls.noTracksAvailable' => 'No tracks available',
			'videoControls.subtitleDownloaded' => 'Subtitle downloaded',
			'videoControls.subtitleDownloadFailed' => 'Failed to download subtitle',
			'videoControls.searchLanguages' => 'Search languages...',
			'videoControls.airplayButton' => 'AirPlay',
			'userStatus.admin' => 'Admin',
			'userStatus.restricted' => 'Restricted',
			'userStatus.protected' => 'Protected',
			'userStatus.current' => 'CURRENT',
			'messages.markedAsWatched' => 'Marked as watched',
			'messages.markedAsUnwatched' => 'Marked as unwatched',
			'messages.markedAsWatchedOffline' => 'Marked as watched (will sync when online)',
			'messages.markedAsUnwatchedOffline' => 'Marked as unwatched (will sync when online)',
			'messages.autoRemovedWatchedDownload' => ({required Object title}) => 'Auto-removed: ${title}',
			'messages.removedFromContinueWatching' => 'Removed from Continue Watching',
			'messages.errorLoading' => 'Error',
			'messages.fileInfoNotAvailable' => 'File information not available',
			'messages.errorLoadingFileInfo' => 'Error loading file info',
			'messages.errorLoadingSeries' => 'Error loading series',
			'messages.musicNotSupported' => 'Music playback is not yet supported',
			'messages.noDescriptionAvailable' => 'No description available',
			'messages.noProfilesAvailable' => 'No profiles available',
			'messages.contactAdminForProfiles' => 'Contact your server administrator to add profiles',
			'messages.unableToDetermineLibrarySection' => 'Unable to determine library section for this item',
			'messages.logsCleared' => 'Logs cleared',
			'messages.logsCopied' => 'Logs copied to clipboard',
			'messages.noLogsAvailable' => 'No logs available',
			'messages.libraryScanning' => ({required Object title}) => 'Scanning "${title}"...',
			'messages.libraryScanStarted' => ({required Object title}) => 'Library scan started for "${title}"',
			'messages.libraryScanFailed' => 'Failed to scan library',
			'messages.metadataRefreshing' => ({required Object title}) => 'Refreshing metadata for "${title}"...',
			'messages.metadataRefreshStarted' => ({required Object title}) => 'Metadata refresh started for "${title}"',
			'messages.metadataRefreshFailed' => 'Failed to refresh metadata',
			'messages.logoutConfirm' => 'Are you sure you want to logout?',
			'messages.noSeasonsFound' => 'No seasons found',
			'messages.seasonsLoadFailed' => 'Couldn\'t load seasons',
			'messages.noEpisodesFound' => 'No episodes found in first season',
			'messages.noEpisodesFoundGeneral' => 'No episodes found',
			'messages.episodesLoadFailed' => 'Couldn\'t load episodes',
			'messages.noResultsFound' => 'No results found',
			'messages.sleepTimerSet' => ({required Object label}) => 'Sleep timer set for ${label}',
			'messages.noItemsAvailable' => 'No items available',
			'messages.failedToCreatePlayQueueNoItems' => 'Failed to create play queue - no items',
			'messages.failedPlayback' => ({required Object action}) => 'Failed to ${action}',
			'messages.switchingToCompatiblePlayer' => 'Switching to compatible player...',
			'messages.serverLimitTitle' => 'Playback failed',
			'messages.serverLimitBody' => 'Server error (HTTP 500). A bandwidth/transcoding limit likely rejected this session. Ask the owner to adjust it.',
			'messages.logsUploaded' => 'Logs uploaded',
			'messages.logsUploadFailed' => 'Failed to upload logs',
			'messages.logsUploadTooLarge' => 'The log is too large to upload. Clear it, reproduce the problem, and upload again.',
			'messages.logsUploadRateLimited' => ({required Object seconds}) => 'Uploaded too soon after the last one. Try again in ${seconds} seconds.',
			'messages.logsUploadRefused' => ({required Object status}) => 'The log server refused the upload (HTTP ${status}).',
			'messages.logsUploadServerError' => ({required Object status}) => 'The log server ran into a problem (HTTP ${status}). Try again later.',
			'messages.logsUploadNetworkError' => 'Could not reach the log server. Check your connection and try again.',
			'messages.logId' => 'Log ID',
			'messages.dvdNotSupported' => 'DVD discs aren\'t supported on this device.',
			'messages.discNotSupported' => 'This disc format isn\'t supported on this device.',
			'subtitlingStyling.text' => 'Text',
			'subtitlingStyling.border' => 'Border',
			'subtitlingStyling.background' => 'Background',
			'subtitlingStyling.fontSize' => 'Font Size',
			'subtitlingStyling.textColor' => 'Text Color',
			'subtitlingStyling.borderSize' => 'Border Size',
			'subtitlingStyling.borderColor' => 'Border Color',
			'subtitlingStyling.backgroundOpacity' => 'Background Opacity',
			'subtitlingStyling.backgroundColor' => 'Background Color',
			'subtitlingStyling.position' => 'Position',
			'subtitlingStyling.assOverride' => 'ASS Override',
			'subtitlingStyling.bold' => 'Bold',
			'subtitlingStyling.italic' => 'Italic',
			'subtitlingStyling.renderResolution' => 'Render Resolution',
			'subtitlingStyling.renderResolutionScreen' => 'Screen resolution',
			'subtitlingStyling.renderResolutionVideo' => 'Video resolution',
			'mpvConfig.title' => 'mpv.conf',
			'mpvConfig.description' => 'Advanced video player settings',
			'mpvConfig.presets' => 'Presets',
			'mpvConfig.noPresets' => 'No saved presets',
			'mpvConfig.saveAsPreset' => 'Save as Preset...',
			'mpvConfig.presetName' => 'Preset Name',
			'mpvConfig.presetNameHint' => 'Enter a name for this preset',
			'mpvConfig.loadPreset' => 'Load',
			'mpvConfig.deletePreset' => 'Delete',
			'mpvConfig.presetSaved' => 'Preset saved',
			'mpvConfig.presetLoaded' => 'Preset loaded',
			'mpvConfig.presetDeleted' => 'Preset deleted',
			'mpvConfig.confirmDeletePreset' => 'Are you sure you want to delete this preset?',
			'mpvConfig.configPlaceholder' => 'gpu-api=vulkan\nhwdec=auto\n# comment',
			'dialog.confirmAction' => 'Confirm Action',
			'profiles.addPleyaProfile' => 'Add Pleya profile',
			'profiles.switchingProfile' => 'Switching profile…',
			'profiles.deleteThisProfileTitle' => 'Delete this profile?',
			'profiles.deleteThisProfileMessage' => ({required Object displayName}) => 'Remove ${displayName}. Connections aren\'t affected.',
			'profiles.active' => 'Active',
			'profiles.manage' => 'Manage',
			'profiles.delete' => 'Delete',
			'profiles.signOut' => 'Sign out',
			'profiles.signOutPlexTitle' => 'Sign out of Plex?',
			'profiles.signOutPlexMessage' => ({required Object displayName}) => 'Remove ${displayName} and all Plex Home users? Sign back in anytime.',
			'profiles.signedOutPlex' => 'Signed out of Plex.',
			'profiles.signOutFailed' => 'Sign out failed.',
			'profiles.sectionTitle' => 'Profiles',
			'profiles.summarySingle' => 'Add profiles to mix managed users and local identities',
			'profiles.summaryMultipleWithActive' => ({required Object count, required Object activeName}) => '${count} profiles · active: ${activeName}',
			'profiles.summaryMultiple' => ({required Object count}) => '${count} profiles',
			'profiles.removeConnectionTitle' => 'Remove connection?',
			'profiles.removeConnectionMessage' => ({required Object displayName, required Object connectionLabel}) => 'Remove ${displayName}\'s access to ${connectionLabel}. Other profiles keep it.',
			'profiles.deleteProfileTitle' => 'Delete profile?',
			'profiles.deleteProfileMessage' => ({required Object displayName}) => 'Remove ${displayName} and its connections. Servers stay available.',
			'profiles.profileNameLabel' => 'Profile name',
			'profiles.pinProtectionLabel' => 'PIN protection',
			'profiles.pinManagedByPlex' => 'PIN managed by Plex. Edit on plex.tv.',
			'profiles.noPinSetEditOnPlex' => 'No PIN set. To require one, edit the home user on plex.tv.',
			'profiles.setPin' => 'Set PIN',
			'profiles.setPinTitle' => 'Set PIN',
			'profiles.confirmPinTitle' => 'Confirm PIN',
			'profiles.pinSet' => 'PIN set',
			'profiles.changePin' => 'Change',
			'profiles.removePin' => 'Remove',
			'profiles.connectionsLabel' => 'Connections',
			'profiles.add' => 'Add',
			'profiles.deleteProfileButton' => 'Delete profile',
			'profiles.noConnectionsHint' => 'No connections — add one to use this profile.',
			'profiles.noConnections' => 'No connections',
			'profiles.plexHomeAccount' => 'Plex Home account',
			'profiles.connectionDefault' => 'Default',
			'profiles.connectionAs' => ({required Object displayName}) => 'as ${displayName}',
			'profiles.makeDefault' => 'Make default',
			'profiles.removeConnection' => 'Remove',
			'profiles.profileRenamed' => 'Profile renamed.',
			'profiles.borrowAddTo' => ({required Object displayName}) => 'Add to ${displayName}',
			'profiles.borrowExplain' => 'Borrow another profile\'s connection. PIN-protected profiles require a PIN.',
			'profiles.borrowEmpty' => 'Nothing to borrow yet.',
			'profiles.borrowEmptySubtitle' => 'Connect Plex or Jellyfin to another profile first.',
			'profiles.borrowFromProfile' => ({required Object displayName}) => 'From ${displayName}',
			'profiles.borrowConnectionBorrowed' => 'Connection borrowed.',
			'profiles.borrowFailed' => 'Failed to borrow connection.',
			'profiles.incorrectPin' => 'Incorrect PIN.',
			'profiles.sourceProfileMissingParentAccount' => 'Source profile is missing its parent account.',
			'profiles.failedToVerifyPin' => 'Failed to verify PIN.',
			'profiles.newProfile' => 'New profile',
			'profiles.profileNameHint' => 'e.g. Guests, Kids, Family Room',
			'profiles.pinProtectionOptional' => 'PIN protection (optional)',
			'profiles.pinExplain' => '4-digit PIN required to switch profiles.',
			'profiles.continueButton' => 'Continue',
			'profiles.pinsDontMatch' => 'PINs don\'t match',
			'profiles.initializeServicesFailed' => 'Failed to initialize profile services',
			'connections.sectionTitle' => 'Connections',
			'connections.addConnection' => 'Add connection',
			'connections.addConnectionSubtitleNoProfile' => 'Sign in with Plex or connect a Jellyfin server',
			'connections.addConnectionSubtitleScoped' => ({required Object displayName}) => 'Add to ${displayName}: Plex, Jellyfin, or another profile connection',
			'connections.sessionExpiredOne' => ({required Object name}) => 'Session expired for ${name}',
			'connections.sessionExpiredMany' => ({required Object count}) => 'Session expired for ${count} servers',
			'connections.signInAgain' => 'Sign in again',
			'connections.editJellyfinTitle' => 'Edit Jellyfin connection',
			'connections.editJellyfinIntro' => ({required Object serverName}) => 'Add or remove URLs for ${serverName}. Pleya will use the reachable URL with the lowest latency.',
			'connections.localSources' => 'Sources on this device',
			'connections.removeSource' => 'Remove source',
			'connections.removeSourceConfirm' => ({required Object name}) => 'Remove "${name}" from this device? Downloaded items are kept.',
			'discover.title' => 'Discover',
			'discover.switchProfile' => 'Switch Profile',
			'discover.noContentAvailable' => 'No content available',
			'discover.addMediaToLibraries' => 'Add some media to your libraries',
			'discover.continueWatching' => 'Continue Watching',
			'discover.continueWatchingIn' => ({required Object library}) => 'Continue Watching in ${library}',
			'discover.nextUp' => 'Next Up',
			'discover.nextUpIn' => ({required Object library}) => 'Next Up in ${library}',
			'discover.recentlyAdded' => 'Recently Added',
			'discover.recentlyReleased' => 'Recently Released',
			'discover.recentlyAddedIn' => ({required Object library}) => 'Recently Added in ${library}',
			'discover.playEpisode' => ({required Object season, required Object episode}) => 'S${season}E${episode}',
			'discover.overview' => 'Overview',
			'discover.cast' => 'Cast',
			'discover.extras' => 'Trailers & Extras',
			'discover.studio' => 'Studio',
			'discover.rating' => 'Rating',
			'discover.movie' => 'Movie',
			'discover.watched' => 'Watched',
			'discover.tvShow' => 'TV Show',
			'discover.minutesLeft' => ({required Object minutes}) => '${minutes} min left',
			'discover.moreLikeThis' => 'More Like This',
			'discover.becauseYouWatched' => ({required Object title}) => 'Because you watched ${title}',
			'discover.latestShows' => 'Recently Added Shows',
			'discover.topRated' => 'Top Rated',
			'discover.somethingDifferent' => 'Something Different',
			'discover.topPicksForYou' => 'Top Picks for You',
			'discover.becauseYouLike' => ({required Object genre}) => 'Because you like ${genre}',
			'discover.hiddenGems' => 'Hidden Gems',
			'discover.watchedBy' => ({required Object names}) => 'Watched by ${names}',
			'discover.watchedByYou' => 'You',
			'discover.watchedByAnd' => 'and',
			'discover.watchedByOthers' => ({required Object count}) => '${count} others',
			'discover.statsPlays' => ({required Object count}) => 'Played ${count} times',
			'discover.statsViewers' => ({required Object count}) => 'by ${count} people',
			'discover.statsWatchTime' => ({required Object duration}) => '${duration} watched',
			'discover.statsRecent' => ({required Object count}) => '${count} in the last 30 days',
			'discover.watchingSeriesBy' => ({required Object names}) => 'Watching this show: ${names}',
			'errors.searchFailed' => 'Search failed',
			'errors.connectionTimeout' => ({required Object context}) => 'Connection timeout while loading ${context}',
			'errors.connectionFailed' => 'Unable to connect to media server',
			'errors.failedToLoad' => ({required Object context}) => 'Failed to load ${context}',
			'errors.noClientAvailable' => 'No client available',
			'errors.authenticationFailed' => 'Authentication failed',
			'errors.couldNotLaunchUrl' => 'Could not launch auth URL',
			'errors.pleaseEnterToken' => 'Please enter a token',
			'errors.invalidToken' => 'Invalid token',
			'errors.failedToVerifyToken' => 'Failed to verify token',
			'errors.failedToSwitchProfile' => ({required Object displayName}) => 'Failed to switch to ${displayName}',
			'errors.failedToDeleteProfile' => ({required Object displayName}) => 'Failed to delete ${displayName}',
			'errors.failedToRate' => 'Couldn\'t update rating',
			'errors.somethingWentWrongTryAgain' => 'Something went wrong. Try again.',
			'errors.couldNotLoad' => ({required Object context}) => 'Couldn\'t load ${context}. Try again.',
			'notices.connectionTimeoutTitle' => 'Connection timed out',
			'notices.connectionTimeoutBody' => ({required Object context}) => '${context} took too long to respond',
			'notices.connectionFailedTitle' => 'Can\'t connect',
			'notices.connectionFailedBody' => ({required Object serverName}) => '${serverName} isn\'t responding',
			'notices.couldNotLoadTitle' => ({required Object context}) => 'Couldn\'t load ${context}',
			'notices.genericErrorTitle' => 'Something went wrong',
			'notices.authFailedTitle' => 'Sign-in failed',
			'notices.playbackStoppedTitle' => 'Playback stopped',
			'notices.playbackSegmentUnavailableBody' => 'This part of the video isn\'t available right now',
			'notices.playbackConnectionLostBody' => 'Lost connection to the server',
			'notices.playbackCodecUnsupportedBody' => 'This file\'s format isn\'t supported on this device',
			'notices.playbackServerErrorBody' => 'The server hit an error while transcoding',
			'libraries.title' => 'Libraries',
			'libraries.fallbackTitle' => 'Library',
			'libraries.itemCount' => ({required Object count}) => '${count} items',
			'libraries.oneItem' => '1 item',
			'libraries.scanLibraryFiles' => 'Scan Library Files',
			'libraries.scanLibrary' => 'Scan Library',
			'libraries.analyze' => 'Analyze',
			'libraries.analyzeLibrary' => 'Analyze Library',
			'libraries.refreshMetadata' => 'Refresh Metadata',
			'libraries.emptyTrash' => 'Empty Trash',
			'libraries.emptyingTrash' => ({required Object title}) => 'Emptying trash for "${title}"...',
			'libraries.trashEmptied' => ({required Object title}) => 'Trash emptied for "${title}"',
			'libraries.failedToEmptyTrash' => 'Failed to empty trash',
			'libraries.analyzing' => ({required Object title}) => 'Analyzing "${title}"...',
			'libraries.analysisStarted' => ({required Object title}) => 'Analysis started for "${title}"',
			'libraries.failedToAnalyze' => 'Failed to analyze library',
			'libraries.noLibrariesFound' => 'No libraries found',
			'libraries.allLibrariesHidden' => 'All libraries are hidden',
			'libraries.hiddenLibrariesCount' => ({required Object count}) => 'Hidden libraries (${count})',
			'libraries.thisLibraryIsEmpty' => 'This library is empty',
			'libraries.all' => 'All',
			'libraries.clearAll' => 'Clear All',
			'libraries.scanLibraryConfirm' => ({required Object title}) => 'Are you sure you want to scan "${title}"?',
			'libraries.analyzeLibraryConfirm' => ({required Object title}) => 'Are you sure you want to analyze "${title}"?',
			'libraries.refreshMetadataConfirm' => ({required Object title}) => 'Are you sure you want to refresh metadata for "${title}"?',
			'libraries.emptyTrashConfirm' => ({required Object title}) => 'Are you sure you want to empty trash for "${title}"?',
			'libraries.manageLibraries' => 'Manage Libraries',
			'libraries.sort' => 'Sort',
			'libraries.sortBy' => 'Sort By',
			'libraries.filters' => 'Filters',
			'libraries.confirmActionMessage' => 'Are you sure you want to perform this action?',
			'libraries.showLibrary' => 'Show library',
			'libraries.hideLibrary' => 'Hide library',
			'libraries.libraryOptions' => 'Library options',
			'libraries.content' => 'library content',
			'libraries.selectLibrary' => 'Select library',
			'libraries.filtersWithCount' => ({required Object count}) => 'Filters (${count})',
			'libraries.noRecommendations' => 'No recommendations available',
			'libraries.noCollections' => 'No collections in this library',
			'libraries.noFoldersFound' => 'No folders found',
			'libraries.folders' => 'folders',
			'libraries.tabs.recommended' => 'Recommended',
			'libraries.tabs.browse' => 'Browse',
			'libraries.tabs.collections' => 'Collections',
			'libraries.tabs.playlists' => 'Playlists',
			'libraries.groupings.title' => 'Grouping',
			'libraries.groupings.all' => 'All',
			'libraries.groupings.movies' => 'Movies',
			'libraries.groupings.shows' => 'TV Shows',
			'libraries.groupings.seasons' => 'Seasons',
			'libraries.groupings.episodes' => 'Episodes',
			'libraries.groupings.folders' => 'Folders',
			'libraries.filterCategories.genre' => 'Genre',
			'libraries.filterCategories.year' => 'Year',
			'libraries.filterCategories.contentRating' => 'Content Rating',
			'libraries.filterCategories.tag' => 'Tag',
			'libraries.filterCategories.unwatched' => 'Unwatched',
			'libraries.sortLabels.title' => 'Title',
			'libraries.sortLabels.dateAdded' => 'Date Added',
			'libraries.sortLabels.releaseDate' => 'Release Date',
			'libraries.sortLabels.rating' => 'Rating',
			'libraries.sortLabels.communityRating' => 'Community Rating',
			'libraries.sortLabels.criticRating' => 'Critic Rating',
			'libraries.sortLabels.userRating' => 'User Rating',
			'libraries.sortLabels.lastPlayed' => 'Last Played',
			'libraries.sortLabels.datePlayed' => 'Date Played',
			'libraries.sortLabels.playCount' => 'Play Count',
			'libraries.sortLabels.productionYear' => 'Production Year',
			'libraries.sortLabels.runtime' => 'Runtime',
			'libraries.sortLabels.officialRating' => 'Official Rating',
			'libraries.sortLabels.premiereDate' => 'Premiere Date',
			'libraries.sortLabels.startDate' => 'Start Date',
			'libraries.sortLabels.airTime' => 'Air Time',
			'libraries.sortLabels.studio' => 'Studio',
			'libraries.sortLabels.random' => 'Random',
			'libraries.sortLabels.dateShared' => 'Date Shared',
			'libraries.sortLabels.latestEpisodeAirDate' => 'Latest Episode Air Date',
			'libraries.sortLabels.lastEpisodeDateAdded' => 'Last Episode Date Added',
			'about.title' => 'About',
			'about.openSourceLicenses' => 'Open Source Licenses',
			'about.versionLabel' => ({required Object version}) => 'Version ${version}',
			'about.appDescription' => 'A beautiful Plex and Jellyfin client for Flutter',
			'about.viewLicensesDescription' => 'View licenses of third-party libraries',
			'about.sourceCode' => 'Source code',
			'about.sourceCodeDescription' => 'Corresponding source for this build (GPL-3.0)',
			'about.basedOnPlezy' => 'Based on Plezy',
			'about.upstreamProject' => 'Upstream project',
			'about.privacyPolicy' => 'Privacy policy',
			'serverSelection.allServerConnectionsFailed' => 'Couldn\'t connect to any servers. Check your network.',
			'serverSelection.noServersFoundForAccount' => ({required Object username, required Object email}) => 'No servers found for ${username} (${email})',
			'serverSelection.noServersFoundTitle' => 'No media servers found',
			'serverSelection.noServersFoundDescription' => 'Your Plex account doesn\'t have access to any servers yet. Ask the server owner to share their library with you, or connect a Jellyfin server instead.',
			'serverSelection.noServersFoundTryJellyfin' => 'Connect a Jellyfin server',
			'serverSelection.noServersFoundRetryPlex' => 'Try a different Plex account',
			'serverSelection.failedToLoadServers' => 'Failed to load servers',
			'serverSelection.failedToLoadServersDescription' => 'Something went wrong while loading your servers. Check your internet connection and try again.',
			'serverSelection.networkErrorTitle' => 'Can\'t reach the server',
			'serverSelection.networkErrorDescription' => 'Pleya couldn\'t connect to the internet. Check your network and try again.',
			'hubDetail.title' => 'Title',
			'hubDetail.releaseYear' => 'Release Year',
			'hubDetail.dateAdded' => 'Date Added',
			'hubDetail.rating' => 'Rating',
			'hubDetail.noItemsFound' => 'No items found',
			'logs.clearLogs' => 'Clear Logs',
			'logs.copyLogs' => 'Copy Logs',
			'logs.uploadLogs' => 'Upload Logs',
			'licenses.relatedPackages' => 'Related Packages',
			'licenses.license' => 'License',
			'licenses.licenseNumber' => ({required Object number}) => 'License ${number}',
			'licenses.licensesCount' => ({required Object count}) => '${count} licenses',
			'navigation.libraries' => 'Libraries',
			'navigation.downloads' => 'Downloads',
			'navigation.liveTv' => 'Live TV',
			'navigation.watchlist' => 'Watchlist',
			'navigation.myPleya' => 'My Pleya',
			'watchlist.title' => 'Watchlist',
			'watchlist.seeAll' => 'See all',
			'watchlist.empty' => 'Nothing on your watchlist yet',
			'watchlist.emptyBody' => 'Titles you add from Plex or mark as a Jellyfin favorite show up here.',
			'watchlist.emptyFiltered' => 'No titles match this filter',
			'watchlist.retry' => 'Try again',
			'watchlist.notAvailable' => 'Not available',
			'watchlist.checking' => 'Checking',
			'watchlist.notFoundOnServers' => 'Not found on your connected media servers',
			'watchlist.coverageIncomplete' => 'Some of your media servers could not be reached. This title may already be there.',
			'watchlist.remove' => 'Remove from Watchlist',
			'watchlist.add' => 'Add to Watchlist',
			'watchlist.added' => 'Added to Watchlist',
			'watchlist.removed' => 'Removed from Watchlist',
			'watchlist.addFailed' => 'Could not update your watchlist',
			'watchlist.partiallyFailed' => 'Removed from some lists only. Your watchlist has been refreshed.',
			'watchlist.offlineRejected' => 'You need a connection to change your watchlist',
			'watchlist.filterAll' => 'All',
			'watchlist.filterMovies' => 'Movies',
			'watchlist.filterShows' => 'Shows',
			'watchlist.filterAvailable' => 'Available',
			'watchlist.sortRecentlyAdded' => 'Recently added',
			'watchlist.sortTitle' => 'Title',
			'watchlist.sortYear' => 'Year',
			'myPleya.title' => 'My Pleya',
			'myPleya.downloadsCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '1 download', other: '{n} downloads', ), 
			'liveTv.serverNotAvailable' => 'Live TV server is not available.',
			'liveTv.serverNotConnected' => 'Live TV server is not connected.',
			'liveTv.title' => 'Live TV',
			'liveTv.guide' => 'Guide',
			'liveTv.noChannels' => 'No channels available',
			'liveTv.noDvr' => 'No DVR configured on any server',
			'liveTv.noPrograms' => 'No program data available',
			'liveTv.liveStreamFailed' => 'Live stream failed',
			'liveTv.unknownProgram' => 'Unknown Program',
			'liveTv.unknownHub' => 'Unknown',
			'liveTv.unknownError' => 'Unknown error',
			'liveTv.channelNumber' => ({required Object number}) => 'Channel ${number}',
			'liveTv.unknownChannel' => 'Unknown channel',
			'liveTv.live' => 'LIVE',
			'liveTv.reloadGuide' => 'Reload Guide',
			'liveTv.now' => 'Now',
			'liveTv.today' => 'Today',
			'liveTv.tomorrow' => 'Tomorrow',
			'liveTv.midnight' => 'Midnight',
			'liveTv.overnight' => 'Overnight',
			'liveTv.morning' => 'Morning',
			'liveTv.daytime' => 'Daytime',
			'liveTv.evening' => 'Evening',
			'liveTv.lateNight' => 'Late Night',
			'liveTv.whatsOn' => 'What\'s On',
			'liveTv.watchChannel' => 'Watch Channel',
			'liveTv.favorites' => 'Favorites',
			'liveTv.reorderFavorites' => 'Reorder Favorites',
			'liveTv.favoritesSaveFailed' => 'Could not save your favorite channels',
			'liveTv.joinSession' => 'Join Session in Progress',
			'liveTv.watchFromStart' => ({required Object minutes}) => 'Watch from start (${minutes} min ago)',
			'liveTv.watchLive' => 'Watch Live',
			'liveTv.goToLive' => 'Go to Live',
			'liveTv.record' => 'Record',
			'liveTv.recordEpisode' => 'Record Episode',
			'liveTv.recordSeries' => 'Record Series',
			'liveTv.recordOptions' => 'Record Options',
			'liveTv.recordings' => 'Recordings',
			'liveTv.scheduledRecordings' => 'Scheduled',
			'liveTv.recordingRules' => 'Recording Rules',
			'liveTv.noScheduledRecordings' => 'Nothing scheduled to record',
			'liveTv.noRecordingRules' => 'No recording rules yet',
			'liveTv.manageRecording' => 'Manage recording',
			'liveTv.cancelRecording' => 'Cancel recording',
			'liveTv.cancelRecordingTitle' => 'Cancel this recording?',
			'liveTv.cancelRecordingMessage' => ({required Object title}) => '${title} will no longer be recorded.',
			'liveTv.deleteRule' => 'Delete rule',
			'liveTv.deleteRuleTitle' => 'Delete recording rule?',
			'liveTv.deleteRuleMessage' => ({required Object title}) => 'Future episodes of ${title} will not be recorded.',
			'liveTv.recordingScheduled' => 'Recording scheduled',
			'liveTv.alreadyScheduled' => 'This program is already scheduled',
			'liveTv.dvrAdminRequired' => 'DVR settings require an admin account',
			'liveTv.recordingFailed' => 'Couldn\'t schedule recording',
			'liveTv.recordingTargetMissing' => 'Couldn\'t determine recording library',
			'liveTv.recordNotAvailable' => 'Recording not available for this program',
			'liveTv.recordingCancelled' => 'Recording cancelled',
			'liveTv.recordingRuleDeleted' => 'Recording rule deleted',
			'liveTv.processRecordingRules' => 'Re-evaluate rules',
			'liveTv.loadingRecordings' => 'Loading recordings...',
			'liveTv.recordingInProgress' => 'Recording now',
			'liveTv.recordingsCount' => ({required Object count}) => '${count} scheduled',
			'liveTv.editRule' => 'Edit rule',
			'liveTv.editRuleAction' => 'Edit',
			'liveTv.recordingRuleUpdated' => 'Recording rule updated',
			'liveTv.guideReloadRequested' => 'Guide refresh requested',
			'liveTv.rulesProcessRequested' => 'Rule re-evaluation requested',
			'liveTv.recordShow' => 'Record show',
			'collections.title' => 'Collections',
			'collections.collection' => 'Collection',
			'collections.empty' => 'Collection is empty',
			'collections.unknownLibrarySection' => 'Cannot delete: Unknown library section',
			'collections.deleteCollection' => 'Delete Collection',
			'collections.deleteConfirm' => ({required Object title}) => 'Delete "${title}"? This can\'t be undone.',
			'collections.deleted' => 'Collection deleted',
			'collections.deleteFailed' => 'Failed to delete collection',
			'collections.deleteFailedWithError' => 'Failed to delete collection',
			'collections.failedToLoadItems' => 'Failed to load collection items',
			'collections.selectCollection' => 'Select Collection',
			'collections.collectionName' => 'Collection Name',
			'collections.enterCollectionName' => 'Enter collection name',
			'collections.addedToCollection' => 'Added to collection',
			'collections.errorAddingToCollection' => 'Failed to add to collection',
			'collections.created' => 'Collection created',
			'collections.removeFromCollection' => 'Remove from collection',
			'collections.removeFromCollectionConfirm' => ({required Object title}) => 'Remove "${title}" from this collection?',
			'collections.removedFromCollection' => 'Removed from collection',
			'collections.removeFromCollectionFailed' => 'Failed to remove from collection',
			'collections.removeFromCollectionError' => 'Error removing from collection',
			'collections.searchCollections' => 'Search collections...',
			'playlists.title' => 'Playlists',
			'playlists.playlist' => 'Playlist',
			'playlists.noPlaylists' => 'No playlists found',
			'playlists.create' => 'Create Playlist',
			'playlists.playlistName' => 'Playlist Name',
			'playlists.enterPlaylistName' => 'Enter playlist name',
			'playlists.delete' => 'Delete Playlist',
			'playlists.removeItem' => 'Remove from Playlist',
			'playlists.smartPlaylist' => 'Smart Playlist',
			'playlists.itemCount' => ({required Object count}) => '${count} items',
			'playlists.oneItem' => '1 item',
			'playlists.emptyPlaylist' => 'This playlist is empty',
			'playlists.deleteConfirm' => 'Delete Playlist?',
			'playlists.deleteMessage' => ({required Object name}) => 'Are you sure you want to delete "${name}"?',
			'playlists.created' => 'Playlist created',
			'playlists.deleted' => 'Playlist deleted',
			'playlists.itemAdded' => 'Added to playlist',
			'playlists.itemRemoved' => 'Removed from playlist',
			'playlists.selectPlaylist' => 'Select Playlist',
			'playlists.errorCreating' => 'Failed to create playlist',
			'playlists.errorDeleting' => 'Failed to delete playlist',
			'playlists.errorLoading' => 'Failed to load playlists',
			'playlists.errorAdding' => 'Failed to add to playlist',
			'playlists.errorReordering' => 'Failed to reorder playlist item',
			'playlists.errorRemoving' => 'Failed to remove from playlist',
			'watchTogether.title' => 'Watch Together',
			'watchTogether.description' => 'Watch content in sync with friends and family',
			'watchTogether.createSession' => 'Create Session',
			'watchTogether.creating' => 'Creating...',
			'watchTogether.joinSession' => 'Join Session',
			'watchTogether.joining' => 'Joining...',
			'watchTogether.controlMode' => 'Control Mode',
			'watchTogether.controlModeQuestion' => 'Who can control playback?',
			_ => null,
		} ?? switch (path) {
			'watchTogether.hostOnly' => 'Host Only',
			'watchTogether.anyone' => 'Anyone',
			'watchTogether.hostingSession' => 'Hosting Session',
			'watchTogether.inSession' => 'In Session',
			'watchTogether.sessionCode' => 'Session Code',
			'watchTogether.hostControlsPlayback' => 'Host controls playback',
			'watchTogether.anyoneCanControl' => 'Anyone can control playback',
			'watchTogether.hostControls' => 'Host controls',
			'watchTogether.anyoneControls' => 'Anyone controls',
			'watchTogether.participants' => 'Participants',
			'watchTogether.host' => 'Host',
			'watchTogether.hostBadge' => 'HOST',
			'watchTogether.youAreHost' => 'You are the host',
			'watchTogether.watchingWithOthers' => 'Watching with others',
			'watchTogether.endSession' => 'End Session',
			'watchTogether.leaveSession' => 'Leave Session',
			'watchTogether.endSessionQuestion' => 'End Session?',
			'watchTogether.leaveSessionQuestion' => 'Leave Session?',
			'watchTogether.endSessionConfirm' => 'This will end the session for all participants.',
			'watchTogether.leaveSessionConfirm' => 'You will be removed from the session.',
			'watchTogether.endSessionConfirmOverlay' => 'This will end the watch session for all participants.',
			'watchTogether.leaveSessionConfirmOverlay' => 'You will be disconnected from the watch session.',
			'watchTogether.end' => 'End',
			'watchTogether.leave' => 'Leave',
			'watchTogether.syncing' => 'Syncing...',
			'watchTogether.joinWatchSession' => 'Join Watch Session',
			'watchTogether.enterCodeHint' => 'Enter 5-character code',
			'watchTogether.pasteFromClipboard' => 'Paste from clipboard',
			'watchTogether.pleaseEnterCode' => 'Please enter a session code',
			'watchTogether.codeMustBe5Chars' => 'Session code must be 5 characters',
			'watchTogether.joinInstructions' => 'Enter the host\'s session code to join.',
			'watchTogether.failedToCreate' => 'Failed to create session',
			'watchTogether.failedToJoin' => 'Failed to join session',
			'watchTogether.sessionCodeCopied' => 'Session code copied to clipboard',
			'watchTogether.relayUnreachable' => 'Relay server unreachable. ISP blocking may prevent Watch Together.',
			'watchTogether.reconnectingToHost' => 'Reconnecting to host...',
			'watchTogether.currentPlayback' => 'Current Playback',
			'watchTogether.joinCurrentPlayback' => 'Join Current Playback',
			'watchTogether.joinCurrentPlaybackDescription' => 'Jump back into what the host is currently watching',
			'watchTogether.failedToOpenCurrentPlayback' => 'Failed to open current playback',
			'watchTogether.participantJoined' => ({required Object name}) => '${name} joined',
			'watchTogether.participantLeft' => ({required Object name}) => '${name} left',
			'watchTogether.participantPaused' => ({required Object name}) => '${name} paused',
			'watchTogether.participantResumed' => ({required Object name}) => '${name} resumed',
			'watchTogether.participantSeeked' => ({required Object name}) => '${name} seeked',
			'watchTogether.participantBuffering' => ({required Object name}) => '${name} is buffering',
			'watchTogether.participantNeedsUpdate' => ({required Object name}) => '${name} is on an older app version — sync unavailable',
			'watchTogether.resumingWithout' => ({required Object name}) => 'Resuming without ${name}',
			'watchTogether.waitingForParticipants' => 'Waiting for others to load...',
			'watchTogether.waitingForName' => ({required Object name}) => 'Waiting for ${name}...',
			'watchTogether.recentRooms' => 'Recent Rooms',
			'watchTogether.renameRoom' => 'Rename Room',
			'watchTogether.removeRoom' => 'Remove',
			'watchTogether.guestSwitchUnavailable' => 'Couldn\'t switch — server unavailable for sync',
			'watchTogether.guestSwitchFailed' => 'Couldn\'t switch — content not found on this server',
			'downloads.title' => 'Downloads',
			'downloads.manage' => 'Manage',
			'downloads.tvShows' => 'TV Shows',
			'downloads.movies' => 'Movies',
			'downloads.noDownloads' => 'No downloads yet',
			'downloads.noDownloadsDescription' => 'Downloaded content will appear here for offline viewing',
			'downloads.downloadNow' => 'Download',
			'downloads.deleteDownload' => 'Delete download',
			'downloads.retryDownload' => 'Retry download',
			'downloads.downloadQueued' => 'Download queued',
			'downloads.waitingForNetwork' => 'Waiting for network',
			'downloads.downloadResumed' => 'Download resumed',
			'downloads.serverErrorBitrate' => 'Server error: file may exceed the remote bitrate limit',
			'downloads.storageFull' => 'Not enough storage space on this device',
			'downloads.episodesQueued' => ({required Object count}) => '${count} episodes queued for download',
			'downloads.downloadDeleted' => 'Download deleted',
			'downloads.deleteConfirm' => ({required Object title}) => 'Delete "${title}" from this device?',
			'downloads.cancelledDownloadTitle' => 'Cancelled Download',
			'downloads.cancelledDownloadMessage' => 'This download was cancelled. What would you like to do?',
			'downloads.allEpisodesAlreadyDownloaded' => 'All episodes already downloaded',
			'downloads.resumeDownload' => 'Resume download',
			'downloads.cancelledDownload' => 'Cancelled download',
			'downloads.syncingFile' => ({required Object file, required Object status}) => '${file} (syncing ${status})',
			'downloads.downloadedFileClickToComplete' => ({required Object file}) => 'Downloaded ${file} - Click to complete',
			'downloads.partialDownloadClickToComplete' => 'Partially downloaded - Click to complete',
			'downloads.deleting' => 'Deleting...',
			'downloads.deletingWithProgress' => ({required Object title, required Object current, required Object total}) => 'Deleting ${title}... (${current} of ${total})',
			'downloads.queuedTooltip' => 'Queued',
			'downloads.queuedFilesTooltip' => ({required Object files}) => 'Queued ${files}',
			'downloads.downloadingTooltip' => 'Downloading...',
			'downloads.downloadingFilesTooltip' => ({required Object files}) => 'Downloading ${files}',
			'downloads.noDownloadsTree' => 'No downloads',
			'downloads.pauseAll' => 'Pause all',
			'downloads.resumeAll' => 'Resume all',
			'downloads.deleteAll' => 'Delete all',
			'downloads.selectVersion' => 'Select Version',
			'downloads.allEpisodes' => 'All episodes',
			'downloads.unwatchedOnly' => 'Unwatched only',
			'downloads.nextNUnwatched' => ({required Object count}) => 'Next ${count} unwatched',
			'downloads.customAmount' => 'Custom amount...',
			'downloads.includeSpecials' => 'Include Specials',
			'downloads.howManyEpisodes' => 'How many episodes?',
			'downloads.itemsQueued' => ({required Object count}) => '${count} items queued for download',
			'downloads.keepSynced' => 'Keep synced',
			'downloads.downloadOnce' => 'Download once',
			'downloads.keepNUnwatched' => ({required Object count}) => 'Keep ${count} unwatched',
			'downloads.editSyncRule' => 'Edit sync rule',
			'downloads.removeSyncRule' => 'Remove sync rule',
			'downloads.removeSyncRuleConfirm' => ({required Object title}) => 'Stop syncing "${title}"? Downloaded episodes will be kept.',
			'downloads.syncRuleCreated' => ({required Object count}) => 'Sync rule created — keeping ${count} unwatched episodes',
			'downloads.syncRuleUpdated' => 'Sync rule updated',
			'downloads.syncRuleRemoved' => 'Sync rule removed',
			'downloads.syncedNewEpisodes' => ({required Object count, required Object title}) => 'Synced ${count} new episodes for ${title}',
			'downloads.activeSyncRules' => 'Sync rules',
			'downloads.noSyncRules' => 'No sync rules',
			'downloads.manageSyncRule' => 'Manage sync',
			'downloads.editEpisodeCount' => 'Episode count',
			'downloads.editSyncFilter' => 'Sync filter',
			'downloads.syncAllItems' => 'Syncing all items',
			'downloads.syncUnwatchedItems' => 'Syncing unwatched items',
			'downloads.syncRuleServerContext' => ({required Object server, required Object status}) => 'Server: ${server} • ${status}',
			'downloads.syncRuleAvailable' => 'Available',
			'downloads.syncRuleOffline' => 'Offline',
			'downloads.syncRuleSignInRequired' => 'Sign in required',
			'downloads.syncRuleNotAvailableForProfile' => 'Not available for current profile',
			'downloads.syncRuleUnknownServer' => 'Unknown server',
			'downloads.syncRuleListCreated' => 'Sync rule created',
			'shaders.title' => 'Shaders',
			'shaders.noShaderDescription' => 'No video enhancement',
			'shaders.nvscalerDescription' => 'NVIDIA image scaling for sharper video',
			'shaders.artcnnVariantNeutral' => 'Neutral',
			'shaders.artcnnVariantDenoise' => 'Denoise',
			'shaders.artcnnVariantDenoiseSharpen' => 'Denoise + Sharpen',
			'shaders.qualityFast' => 'Fast',
			'shaders.qualityHQ' => 'High Quality',
			'shaders.mode' => 'Mode',
			'shaders.importShader' => 'Import Shader',
			'shaders.customShaderDescription' => 'Custom GLSL shader',
			'shaders.shaderImported' => 'Shader imported',
			'shaders.shaderImportFailed' => 'Failed to import shader',
			'shaders.deleteShader' => 'Delete Shader',
			'shaders.deleteShaderConfirm' => ({required Object name}) => 'Delete "${name}"?',
			'companionRemote.title' => 'Companion Remote',
			'companionRemote.connectedTo' => ({required Object name}) => 'Connected to ${name}',
			'companionRemote.unknownDevice' => 'Unknown Device',
			'companionRemote.session.startingServer' => 'Starting remote server...',
			'companionRemote.session.failedToCreate' => 'Failed to start remote server:',
			'companionRemote.session.hostAddress' => 'Host Address',
			'companionRemote.session.connected' => 'Connected',
			'companionRemote.session.serverRunning' => 'Remote server active',
			'companionRemote.session.serverStopped' => 'Remote server stopped',
			'companionRemote.session.serverRunningDescription' => 'Mobile devices on your network can connect to this app',
			'companionRemote.session.serverStoppedDescription' => 'Start the server to allow mobile devices to connect',
			'companionRemote.session.usePhoneToControl' => 'Use your mobile device to control this app',
			'companionRemote.session.startServer' => 'Start Server',
			'companionRemote.session.stopServer' => 'Stop Server',
			'companionRemote.session.minimize' => 'Minimize',
			'companionRemote.pairing.discoveryDescription' => 'Pleya devices with the same Plex account appear here',
			'companionRemote.pairing.hostAddressHint' => '192.168.1.100:48632',
			'companionRemote.pairing.connecting' => 'Connecting...',
			'companionRemote.pairing.searchingForDevices' => 'Looking for devices...',
			'companionRemote.pairing.noDevicesFound' => 'No devices found on your network',
			'companionRemote.pairing.noDevicesHint' => 'Open Pleya on desktop and use the same WiFi',
			'companionRemote.pairing.availableDevices' => 'Available Devices',
			'companionRemote.pairing.manualConnection' => 'Manual Connection',
			'companionRemote.pairing.cryptoInitFailed' => 'Couldn\'t start secure connection. Sign in to Plex first.',
			'companionRemote.pairing.validationHostRequired' => 'Please enter host address',
			'companionRemote.pairing.validationHostFormat' => 'Format must be IP:port (e.g., 192.168.1.100:48632)',
			'companionRemote.pairing.connectionTimedOut' => 'Connection timed out. Use the same network on both devices.',
			'companionRemote.pairing.sessionNotFound' => 'Device not found. Make sure Pleya is running on the host.',
			'companionRemote.pairing.authFailed' => 'Authentication failed. Both devices need the same Plex account.',
			'companionRemote.pairing.failedToConnect' => 'Failed to connect',
			'companionRemote.remote.disconnectConfirm' => 'Do you want to disconnect from the remote session?',
			'companionRemote.remote.reconnecting' => 'Reconnecting...',
			'companionRemote.remote.attemptOf' => ({required Object current}) => 'Attempt ${current} of 5',
			'companionRemote.remote.retryNow' => 'Retry Now',
			'companionRemote.remote.tabRemote' => 'Remote',
			'companionRemote.remote.tabPlay' => 'Play',
			'companionRemote.remote.tabMore' => 'More',
			'companionRemote.remote.menu' => 'Menu',
			'companionRemote.remote.tabNavigation' => 'Tab Navigation',
			'companionRemote.remote.tabDiscover' => 'Discover',
			'companionRemote.remote.tabLibraries' => 'Libraries',
			'companionRemote.remote.tabSearch' => 'Search',
			'companionRemote.remote.tabDownloads' => 'Downloads',
			'companionRemote.remote.tabSettings' => 'Settings',
			'companionRemote.remote.previous' => 'Previous',
			'companionRemote.remote.playPause' => 'Play/Pause',
			'companionRemote.remote.next' => 'Next',
			'companionRemote.remote.seekBack' => 'Seek Back',
			'companionRemote.remote.stop' => 'Stop',
			'companionRemote.remote.seekForward' => 'Seek Fwd',
			'companionRemote.remote.volume' => 'Volume',
			'companionRemote.remote.volumeDown' => 'Down',
			'companionRemote.remote.volumeUp' => 'Up',
			'companionRemote.remote.fullscreen' => 'Fullscreen',
			'companionRemote.remote.subtitles' => 'Subtitles',
			'companionRemote.remote.audio' => 'Audio',
			'companionRemote.remote.searchHint' => 'Search on desktop...',
			'companionRemote.errors.noNetworkInterface' => 'No network interface found',
			'companionRemote.errors.authenticationFailed' => 'Authentication failed',
			'companionRemote.errors.joinTimedOut' => 'Timed out joining session',
			'companionRemote.errors.failedToConnectAnyAddress' => 'Failed to connect to any address',
			'companionRemote.errors.connectionLostAfterAttempts' => ({required Object attempts}) => 'Connection lost after ${attempts} attempts',
			'companionRemote.errors.connectionLost' => 'Connection lost',
			'videoSettings.playbackSpeed' => 'Playback Speed',
			'videoSettings.zoom' => 'Zoom',
			'videoSettings.sleepTimer' => 'Sleep Timer',
			'videoSettings.audioSync' => 'Audio Sync',
			'videoSettings.subtitleSync' => 'Subtitle Sync',
			'videoSettings.hdr' => 'HDR',
			'videoSettings.audioOutput' => 'Audio Output',
			'videoSettings.performanceOverlay' => 'Performance Overlay',
			'videoSettings.audioPassthrough' => 'Audio Passthrough',
			'videoSettings.audioOutputTitle' => 'Audio Output Mode',
			'videoSettings.audioOutputModes.auto' => 'Auto',
			'videoSettings.audioOutputModes.passthrough' => 'Passthrough',
			'videoSettings.audioOutputModes.pcm' => 'PCM (decode)',
			'videoSettings.audioOutputDecisions.passthrough' => 'Dolby bitstream',
			'videoSettings.audioOutputDecisions.pcmMultichannel' => 'PCM multichannel',
			'videoSettings.audioOutputDecisions.pcmStereo' => 'PCM stereo',
			'videoSettings.audioOutputModeDescriptions.auto' => 'Widens to multichannel where the output allows it; never bitstreams',
			'videoSettings.audioOutputModeDescriptions.passthrough' => 'Always send Dolby untouched to the receiver',
			'videoSettings.audioOutputModeDescriptions.pcm' => 'Always decode in the app',
			'videoSettings.audioOutputRendering.monoStereo' => 'Stereo',
			'videoSettings.audioOutputRendering.surround' => 'Surround',
			'videoSettings.audioOutputRendering.spatialAudio' => 'Spatial Audio',
			'videoSettings.audioOutputRendering.dolbyAudio' => 'Dolby Audio',
			'videoSettings.audioOutputRendering.dolbyAtmos' => 'Dolby Atmos',
			'videoSettings.audioOutputNow' => ({required Object mode}) => 'now: ${mode}',
			'videoSettings.audioNormalization' => 'Normalize Loudness',
			'videoSettings.audioNormalizationSuspended' => 'Dolby passthrough is running, so volume levelling is paused. Your receiver sets the level.',
			'videoSettings.audioPriorityTitle' => 'Priority',
			'videoSettings.audioPriorities.evenVolume' => 'Even volume',
			'videoSettings.audioPriorities.originalDolby' => 'Original Dolby Atmos',
			'videoSettings.audioLevelVolume' => 'Even out volume',
			'videoSettings.audioLevelVolumeDescription' => 'Brings every title to the same level as the rest of your TV',
			'videoSettings.audioReduceLoudSounds' => 'Reduce loud sounds',
			'videoSettings.audioReduceLoudSoundsDescription' => 'Narrows the gap between dialogue and loud effects',
			'videoSettings.tryLowerQuality' => 'Try lower quality',
			'videoSettings.audioPassthroughUnavailable' => 'This output can\'t take a Dolby bitstream — switched to decoded audio.',
			'performanceOverlay.color' => 'Color',
			'performanceOverlay.performance' => 'Performance',
			'performanceOverlay.buffer' => 'Buffer',
			'performanceOverlay.app' => 'App',
			'performanceOverlay.decoder' => 'Decoder',
			'performanceOverlay.rawDecoder' => 'Raw Decoder',
			'performanceOverlay.tunneling' => 'Tunneling',
			'performanceOverlay.aspect' => 'Aspect',
			'performanceOverlay.rotation' => 'Rotation',
			'performanceOverlay.dvSource' => 'DV Source',
			'performanceOverlay.dvPath' => 'DV Path',
			'performanceOverlay.p7Conversion' => 'P7 Conv',
			'performanceOverlay.sampleRate' => 'Sample Rate',
			'performanceOverlay.audioDriver' => 'Audio Driver',
			'performanceOverlay.audioOutFormat' => 'Out Format',
			'performanceOverlay.audioRequested' => 'Requested',
			'performanceOverlay.audioActual' => 'Actual',
			'performanceOverlay.audioMeasuring' => 'measuring…',
			'performanceOverlay.audioBitstream' => 'bitstream',
			'performanceOverlay.audioFellBack' => 'fell back',
			'performanceOverlay.audioFilters' => 'Filters',
			'performanceOverlay.audioFiltersNone' => 'none',
			'performanceOverlay.volume' => 'Volume',
			'performanceOverlay.pixelFormat' => 'Pixel Fmt',
			'performanceOverlay.hwFormat' => 'HW Fmt',
			'performanceOverlay.matrix' => 'Matrix',
			'performanceOverlay.primaries' => 'Primaries',
			'performanceOverlay.transfer' => 'Transfer',
			'performanceOverlay.renderFps' => 'Render FPS',
			'performanceOverlay.displayFps' => 'Display FPS',
			'performanceOverlay.avSync' => 'A/V Sync',
			'performanceOverlay.dropped' => 'Dropped',
			'performanceOverlay.dvRpus' => 'DV RPUs',
			'performanceOverlay.dvRpuAverage' => 'DV RPU Avg',
			'performanceOverlay.dvSampleAverage' => 'DV Sample Avg',
			'performanceOverlay.maxLuma' => 'Max Luma',
			'performanceOverlay.minLuma' => 'Min Luma',
			'performanceOverlay.maxCll' => 'MaxCLL',
			'performanceOverlay.maxFall' => 'MaxFALL',
			'performanceOverlay.cacheUsed' => 'Cache Used',
			'performanceOverlay.cacheLimit' => 'Cache Limit',
			'performanceOverlay.speed' => 'Speed',
			'performanceOverlay.player' => 'Player',
			'performanceOverlay.memory' => 'Memory',
			'performanceOverlay.uiFps' => 'UI FPS',
			'externalPlayer.title' => 'External Player',
			'externalPlayer.useExternalPlayer' => 'Use External Player',
			'externalPlayer.useExternalPlayerDescription' => 'Open videos in another app',
			'externalPlayer.selectPlayer' => 'Select Player',
			'externalPlayer.customPlayers' => 'Custom Players',
			'externalPlayer.systemDefault' => 'System Default',
			'externalPlayer.addCustomPlayer' => 'Add Custom Player',
			'externalPlayer.playerName' => 'Player Name',
			'externalPlayer.playerNameHint' => 'My Player',
			'externalPlayer.playerCommand' => 'Command',
			'externalPlayer.playerPackage' => 'Package Name',
			'externalPlayer.playerUrlScheme' => 'URL Scheme',
			'externalPlayer.off' => 'Off',
			'externalPlayer.launchFailed' => 'Failed to open external player',
			'externalPlayer.appNotInstalled' => ({required Object name}) => '${name} is not installed',
			'externalPlayer.playInExternalPlayer' => 'Play in External Player',
			'metadataEdit.editMetadata' => 'Edit...',
			'metadataEdit.screenTitle' => 'Edit Metadata',
			'metadataEdit.basicInfo' => 'Basic Info',
			'metadataEdit.artwork' => 'Artwork',
			'metadataEdit.advancedSettings' => 'Advanced Settings',
			'metadataEdit.title' => 'Title',
			'metadataEdit.sortTitle' => 'Sort Title',
			'metadataEdit.originalTitle' => 'Original Title',
			'metadataEdit.releaseDate' => 'Release Date',
			'metadataEdit.contentRating' => 'Content Rating',
			'metadataEdit.studio' => 'Studio',
			'metadataEdit.tagline' => 'Tagline',
			'metadataEdit.summary' => 'Summary',
			'metadataEdit.poster' => 'Poster',
			'metadataEdit.background' => 'Background',
			'metadataEdit.logo' => 'Logo',
			'metadataEdit.squareArt' => 'Square Art',
			'metadataEdit.selectPoster' => 'Select Poster',
			'metadataEdit.selectBackground' => 'Select Background',
			'metadataEdit.selectLogo' => 'Select Logo',
			'metadataEdit.selectSquareArt' => 'Select Square Art',
			'metadataEdit.fromUrl' => 'From URL',
			'metadataEdit.uploadFile' => 'Upload File',
			'metadataEdit.enterImageUrl' => 'Enter image URL',
			'metadataEdit.imageUrl' => 'Image URL',
			'metadataEdit.metadataUpdated' => 'Metadata updated',
			'metadataEdit.metadataUpdateFailed' => 'Failed to update metadata',
			'metadataEdit.artworkUpdated' => 'Artwork updated',
			'metadataEdit.artworkUpdateFailed' => 'Failed to update artwork',
			'metadataEdit.noArtworkAvailable' => 'No artwork available',
			'metadataEdit.notSet' => 'Not set',
			'metadataEdit.libraryDefault' => 'Library default',
			'metadataEdit.accountDefault' => 'Account default',
			'metadataEdit.seriesDefault' => 'Series default',
			'metadataEdit.episodeSorting' => 'Episode Sorting',
			'metadataEdit.oldestFirst' => 'Oldest first',
			'metadataEdit.newestFirst' => 'Newest first',
			'metadataEdit.keep' => 'Keep',
			'metadataEdit.allEpisodes' => 'All episodes',
			'metadataEdit.latestEpisodes' => ({required Object count}) => '${count} latest episodes',
			'metadataEdit.latestEpisode' => 'Latest episode',
			'metadataEdit.episodesAddedPastDays' => ({required Object count}) => 'Episodes added in the past ${count} days',
			'metadataEdit.deleteAfterPlaying' => 'Delete Episodes After Playing',
			'metadataEdit.never' => 'Never',
			'metadataEdit.afterADay' => 'After a day',
			'metadataEdit.afterAWeek' => 'After a week',
			'metadataEdit.afterAMonth' => 'After a month',
			'metadataEdit.onNextRefresh' => 'On next refresh',
			'metadataEdit.seasons' => 'Seasons',
			'metadataEdit.show' => 'Show',
			'metadataEdit.hide' => 'Hide',
			'metadataEdit.episodeOrdering' => 'Episode Ordering',
			'metadataEdit.tmdbAiring' => 'The Movie Database (Aired)',
			'metadataEdit.tvdbAiring' => 'TheTVDB (Aired)',
			'metadataEdit.tvdbAbsolute' => 'TheTVDB (Absolute)',
			'metadataEdit.metadataLanguage' => 'Metadata Language',
			'metadataEdit.useOriginalTitle' => 'Use Original Title',
			'metadataEdit.preferredAudioLanguage' => 'Preferred Audio Language',
			'metadataEdit.preferredSubtitleLanguage' => 'Preferred Subtitle Language',
			'metadataEdit.subtitleMode' => 'Auto-Select Subtitle Mode',
			'metadataEdit.manuallySelected' => 'Manually selected',
			'metadataEdit.shownWithForeignAudio' => 'Shown with foreign audio',
			'metadataEdit.alwaysEnabled' => 'Always enabled',
			'metadataEdit.tags' => 'Tags',
			'metadataEdit.addTag' => 'Add tag',
			'metadataEdit.genre' => 'Genre',
			'metadataEdit.director' => 'Director',
			'metadataEdit.writer' => 'Writer',
			'metadataEdit.producer' => 'Producer',
			'metadataEdit.country' => 'Country',
			'metadataEdit.collection' => 'Collection',
			'metadataEdit.label' => 'Label',
			'metadataEdit.style' => 'Style',
			'metadataEdit.mood' => 'Mood',
			'matchScreen.match' => 'Match...',
			'matchScreen.fixMatch' => 'Fix Match...',
			'matchScreen.unmatch' => 'Unmatch',
			'matchScreen.unmatchConfirm' => 'Clear this match? Plex treats it as unmatched until rematched.',
			'matchScreen.unmatchSuccess' => 'Item unmatched',
			'matchScreen.unmatchFailed' => 'Failed to unmatch item',
			'matchScreen.matchApplied' => 'Match applied',
			'matchScreen.matchFailed' => 'Failed to apply match',
			'matchScreen.titleHint' => 'Title',
			'matchScreen.yearHint' => 'Year',
			'matchScreen.search' => 'Search',
			'matchScreen.noMatchesFound' => 'No matches found',
			'serverTasks.title' => 'Server Tasks',
			'serverTasks.failedToLoad' => 'Failed to load tasks',
			'serverTasks.noTasks' => 'No tasks running',
			'seerr.title' => 'Requests',
			'seerr.hubSubtitle' => 'Request movies and shows from your Jellyseerr or Overseerr server.',
			'seerr.notConfigured' => 'Not configured',
			'seerr.serverUrl' => 'Server URL',
			'seerr.serverUrlHint' => 'https://requests.example.com',
			'seerr.authMode' => 'Sign-in method',
			'seerr.authPlex' => 'Sign in with Plex',
			'seerr.authPlexSubtitle' => 'One-tap using your existing Plex login.',
			'seerr.authLocal' => 'Email and password',
			'seerr.authApiKey' => 'API key',
			'seerr.email' => 'Email',
			'seerr.password' => 'Password',
			'seerr.apiKey' => 'API key',
			'seerr.apiKeyHint' => 'From Settings → General on your server',
			'seerr.adminAttributionNote' => 'API-key mode files requests as the admin user. Sign in with Plex for per-user attribution.',
			'seerr.setupOnDesktopNote' => 'Tip: this is easier to set up on your phone or computer.',
			'seerr.testConnection' => 'Test connection',
			'seerr.save' => 'Save',
			'seerr.disconnect' => 'Disconnect',
			'seerr.disconnectConfirm' => 'Disconnect requests server?',
			'seerr.disconnectConfirmBody' => 'Pleya will stop sending requests. You can reconnect any time.',
			'seerr.connectedAs' => ({required Object name}) => 'Signed in as ${name}',
			'seerr.serverVersion' => ({required Object version}) => 'Server version ${version}',
			'seerr.permissionAdmin' => 'Administrator',
			'seerr.permissionManage' => 'Can approve requests',
			'seerr.permissionRequest' => 'Can request',
			'seerr.request' => 'Request',
			'seerr.requested' => 'Requested',
			'seerr.requestAgain' => 'Request',
			'seerr.processing' => 'Processing',
			'seerr.partiallyAvailable' => 'Partially available',
			'seerr.available' => 'Available',
			'seerr.alreadyRequested' => 'Already requested',
			'seerr.pending' => 'Pending',
			'seerr.approved' => 'Approved',
			'seerr.declined' => 'Declined',
			'seerr.failed' => 'Failed',
			'seerr.completed' => 'Completed',
			'seerr.requestConfirm' => ({required Object title}) => 'Request "${title}"?',
			'seerr.requestMovie' => 'Request movie',
			'seerr.requestSuccess' => 'Requested',
			'seerr.requestFailed' => 'Request failed. Try again.',
			'seerr.selectSeasons' => 'Select seasons',
			'seerr.season' => ({required Object number}) => 'Season ${number}',
			'seerr.allSeasons' => 'All seasons',
			'seerr.seasonsRange' => ({required Object range}) => 'Seasons ${range}',
			'seerr.seasonsCount' => ({required Object count}) => '${count} seasons',
			'seerr.requestedBy' => ({required Object name}) => 'Requested by ${name}',
			'seerr.fourK' => 'Request in 4K',
			'seerr.fourKBadge' => '4K',
			'seerr.percentMatch' => ({required Object percent}) => '${percent}% match',
			'seerr.quotaRemaining' => ({required Object remaining, required Object limit}) => '${remaining} of ${limit} requests left',
			'seerr.quotaUnlimited' => 'Unlimited requests',
			'seerr.advancedOptions' => 'Advanced options',
			'seerr.server' => 'Server',
			'seerr.qualityProfile' => 'Quality profile',
			'seerr.rootFolder' => 'Root folder',
			'seerr.myRequests' => 'My requests',
			'seerr.allRequests' => 'All requests',
			'seerr.filterAll' => 'All',
			'seerr.filterPending' => 'Pending',
			'seerr.filterApproved' => 'Approved',
			'seerr.filterAvailable' => 'Available',
			'seerr.filterMovies' => 'Movies',
			'seerr.filterShows' => 'Shows',
			'seerr.approve' => 'Approve',
			'seerr.decline' => 'Decline',
			'seerr.edit' => 'Edit',
			'seerr.cancelRequest' => 'Cancel request',
			'seerr.cancelRequestConfirm' => 'Cancel this request?',
			'seerr.discoverTitle' => 'Discover on Requests',
			'seerr.trending' => 'Trending',
			'seerr.popularMovies' => 'Popular movies',
			'seerr.popularTv' => 'Popular shows',
			'seerr.upcoming' => 'Upcoming',
			'seerr.recommendations' => 'Recommendations',
			'seerr.cast' => 'Cast',
			'seerr.loadMore' => 'Load more',
			'seerr.searchOnSeerr' => 'Not in your library? Search on Jellyseerr / Overseerr',
			'seerr.searchOnSeerrShort' => 'Search on Requests',
			'seerr.noResults' => 'No results found.',
			'seerr.errorAuth' => 'Sign-in failed. Check your credentials.',
			'seerr.errorForbidden' => 'You don\'t have permission for that.',
			'seerr.errorNetwork' => 'Couldn\'t reach the server. Check the URL.',
			'seerr.errorGeneric' => 'Something went wrong. Try again.',
			'seerr.searchPlaceholder' => 'Search for a movie or show to request',
			'seerr.byStreamingService' => 'By streaming service',
			'seerr.showAll' => 'Show all',
			'tautulli.title' => 'Tautulli',
			'tautulli.subtitle' => 'Tautulli tracks who watches what on your Plex server. Connect it to see viewers, statistics and live activity inside Pleya.',
			'tautulli.adminOnlyNote' => 'Tautulli has one key that opens its whole admin API, so it stays on this device and only you see what it reports. The people you share your server with are not affected and need to set up nothing.',
			'tautulli.useHistoryForRecommendations' => 'Use history for recommendations',
			'tautulli.useHistoryForRecommendationsDescription' => 'Uses viewing history from this Tautulli server to improve personal recommendations for every profile on this device. Each profile only ever gets its own history, and processing stays local in Pleya.',
			'tautulli.integrationConflictNote' => 'Two different Tautulli pairings were found for this server, so history is not being used until you reconnect the one you want to keep.',
			'tautulli.serverUrl' => 'Tautulli address',
			'tautulli.serverUrlHint' => 'http://192.168.1.10:8181 or https://tautulli.example.com',
			'tautulli.authMode' => 'How to connect',
			'tautulli.modeDevice' => 'Device token',
			'tautulli.modeDeviceHelp' => 'In Tautulli, open Settings, Tautulli Remote App, and register a device. Paste the generated token here within five minutes. Your permanent API key stays out of the app, and you can revoke this one device later.',
			'tautulli.modeApiKey' => 'API key',
			'tautulli.modeApiKeyHelp' => 'The permanent key from Settings, Web Interface. It grants full access to Tautulli, so use it only if the device token does not work for you.',
			'tautulli.deviceToken' => 'Device token',
			'tautulli.apiKey' => 'API key',
			'tautulli.testConnection' => 'Test connection',
			'tautulli.save' => 'Save',
			'tautulli.connected' => 'Connected',
			'tautulli.disconnect' => 'Disconnect',
			'tautulli.disconnectConfirm' => 'Disconnect Tautulli?',
			'tautulli.disconnectConfirmBody' => 'Pleya forgets the address and the token. Viewers, statistics and live activity disappear until you connect again.',
			'tautulli.setupOnDesktopNote' => 'Easier on your phone or computer: the address and token are long to type with a remote.',
			'tautulli.errorNetwork' => 'Could not reach Tautulli. Check the address and whether it is reachable from this device.',
			'tautulli.errorAuth' => 'Tautulli rejected this key.',
			'tautulli.errorTokenExpired' => 'Tautulli rejected this token. A device token is only valid for five minutes, so generate a new one and try again.',
			'tautulli.errorModeMismatch' => 'Tautulli rejected this token, and it looks like your permanent API key rather than a device token. Switch to API key above, or register a device in Tautulli and paste that token.',
			'tautulli.errorUrlRequired' => 'Enter the address of your Tautulli server.',
			'tautulli.errorTokenRequired' => 'Enter a token.',
			'tautulli.errorNotTautulli' => 'Something answered at that address, but it was not Tautulli. Check the address and the base path, and whether a login page sits in front of it.',
			'tautulli.errorServer' => ({required Object code}) => 'Tautulli reported a server error (HTTP ${code}).',
			'tautulli.errorGeneric' => 'Connecting failed.',
			'nowWatching.title' => 'Now watching',
			'nowWatching.tooltip' => 'See who is watching now',
			'nowWatching.streams' => ({required Object count}) => '${count} streams',
			'nowWatching.oneStream' => '1 stream',
			'nowWatching.transcoding' => ({required Object count}) => '${count} transcoding',
			'nowWatching.directPlay' => 'Direct play',
			'nowWatching.directStream' => 'Direct stream',
			_ => null,
		} ?? switch (path) {
			'nowWatching.transcode' => 'Transcode',
			'nowWatching.paused' => 'Paused',
			'nowWatching.remaining' => ({required Object time}) => '${time} left',
			'nowWatching.watchingNow' => ({required Object name}) => '${name} is watching this now',
			'nowWatching.hardware' => 'Hardware',
			'nowWatching.onLan' => 'On your network',
			'nowWatching.onWan' => 'Remote',
			'nowWatching.unavailable' => 'Tautulli did not answer',
			'nowWatching.sidebarLabel' => 'Now watching',
			'trakt.title' => 'Trakt',
			'trakt.connected' => 'Connected',
			'trakt.connectedAs' => ({required Object username}) => 'Connected as @${username}',
			'trakt.disconnectConfirm' => 'Disconnect Trakt account?',
			'trakt.disconnectConfirmBody' => 'Pleya will stop sending events to Trakt. You can reconnect any time.',
			'trakt.scrobble' => 'Real-time scrobbling',
			'trakt.scrobbleDescription' => 'Send play, pause, and stop events to Trakt during playback.',
			'trakt.watchedSync' => 'Sync watched status',
			'trakt.watchedSyncDescription' => 'When you mark items watched in Pleya, mark them on Trakt.',
			'trackers.title' => 'Trackers',
			'trackers.hubSubtitle' => 'Sync watch progress with Trakt and other services.',
			'trackers.notConnected' => 'Not connected',
			'trackers.connectedAs' => ({required Object username}) => 'Connected as @${username}',
			'trackers.scrobble' => 'Track progress automatically',
			'trackers.scrobbleDescription' => 'Update your list when you finish an episode or movie.',
			'trackers.disconnectConfirm' => ({required Object service}) => 'Disconnect ${service}?',
			'trackers.disconnectConfirmBody' => ({required Object service}) => 'Pleya will stop updating ${service}. Reconnect any time.',
			'trackers.connectFailed' => ({required Object service}) => 'Couldn\'t connect to ${service}. Try again.',
			'trackers.services.mal' => 'MyAnimeList',
			'trackers.services.anilist' => 'AniList',
			'trackers.services.simkl' => 'Simkl',
			'trackers.deviceCode.title' => ({required Object service}) => 'Activate Pleya on ${service}',
			'trackers.deviceCode.body' => ({required Object url}) => 'Visit ${url} and enter this code:',
			'trackers.deviceCode.openToActivate' => ({required Object service}) => 'Open ${service} to activate',
			'trackers.deviceCode.waitingForAuthorization' => 'Waiting for authorization…',
			'trackers.deviceCode.codeCopied' => 'Code copied',
			'trackers.oauthProxy.title' => ({required Object service}) => 'Sign in to ${service}',
			'trackers.oauthProxy.body' => 'Scan this QR code or open the URL on any device.',
			'trackers.oauthProxy.openToSignIn' => ({required Object service}) => 'Open ${service} to sign in',
			'trackers.oauthProxy.urlCopied' => 'URL copied',
			'trackers.libraryFilter.title' => 'Library filter',
			'trackers.libraryFilter.subtitleAllSyncing' => 'Syncing all libraries',
			'trackers.libraryFilter.subtitleNoneSyncing' => 'Nothing syncing',
			'trackers.libraryFilter.subtitleBlocked' => ({required Object count}) => '${count} blocked',
			'trackers.libraryFilter.subtitleAllowed' => ({required Object count}) => '${count} allowed',
			'trackers.libraryFilter.mode' => 'Filter mode',
			'trackers.libraryFilter.modeBlacklist' => 'Blacklist',
			'trackers.libraryFilter.modeWhitelist' => 'Whitelist',
			'trackers.libraryFilter.modeHintBlacklist' => 'Sync every library except the ones checked below.',
			'trackers.libraryFilter.modeHintWhitelist' => 'Sync only the libraries checked below.',
			'trackers.libraryFilter.libraries' => 'Libraries',
			'trackers.libraryFilter.noLibraries' => 'No libraries available',
			'addServer.addJellyfinTitle' => 'Add Jellyfin server',
			'addServer.serverUrls' => 'Server URLs',
			'addServer.serverUrlsHelper' => 'Multiple URLs allowed, separated by commas.',
			'addServer.findServer' => 'Find server',
			'addServer.searchingLocalServers' => 'Looking for local Jellyfin servers...',
			'addServer.localServers' => 'Local Jellyfin servers',
			'addServer.username' => 'Username',
			'addServer.password' => 'Password',
			'addServer.signIn' => 'Sign in',
			'addServer.change' => 'Change',
			'addServer.required' => 'Required',
			'addServer.couldNotReachServer' => 'Could not reach the server',
			'addServer.signInFailed' => 'Sign-in failed',
			'addServer.quickConnectFailed' => 'Quick Connect failed',
			'addServer.addPlexTitle' => 'Sign in with Plex',
			'addServer.pinExpired' => 'PIN expired before sign-in. Please try again.',
			'addServer.duplicatePlexAccount' => 'Already signed in to Plex. Sign out to switch accounts.',
			'addServer.failedToRegisterAccount' => 'Failed to register account',
			'addServer.enterJellyfinUrlError' => 'Enter your Jellyfin server URL',
			'addServer.addConnectionTitle' => 'Add connection',
			'addServer.addConnectionTitleScoped' => ({required Object name}) => 'Add to ${name}',
			'addServer.signInWithPlexCard' => 'Sign in with Plex',
			'addServer.signInWithPlexCardSubtitle' => 'Authorize this device. Shared servers are added.',
			'addServer.signInWithPlexCardSubtitleScoped' => 'Authorize a Plex account. Home users become profiles.',
			'addServer.connectToJellyfinCard' => 'Connect to Jellyfin',
			'addServer.connectToJellyfinCardSubtitle' => 'Enter your server URL, username, and password.',
			'addServer.connectToJellyfinCardSubtitleScoped' => ({required Object name}) => 'Sign in to a Jellyfin server. Binds to ${name}.',
			'addServer.borrowFromAnotherProfile' => 'Borrow from another profile',
			'addServer.borrowFromAnotherProfileSubtitle' => 'Reuse another profile\'s connection. PIN-protected profiles require a PIN.',
			'addLocalFolder.cardTitle' => 'Local Folder',
			'addLocalFolder.cardSubtitle' => 'Browse media files from a folder on your device',
			'addLocalFolder.title' => 'Add Local Folder',
			'addLocalFolder.description' => 'Select a folder on your device containing movies or TV shows. Pleya will scan the folder structure and list your media.',
			'addLocalFolder.libraryType' => 'Library type',
			'addLocalFolder.typeMovies' => 'Movies',
			'addLocalFolder.typeTvShows' => 'TV Shows',
			'addLocalFolder.typeMixed' => 'Mixed',
			'addLocalFolder.directory' => 'Directory',
			'addLocalFolder.chooseDirectory' => 'Choose a directory…',
			'addLocalFolder.nameLabel' => 'Display name',
			'addLocalFolder.nameHint' => 'e.g. My Movies',
			'addLocalFolder.save' => 'Add folder',
			'addLocalFolder.saveError' => 'Failed to add local folder',
			'addLocalFolder.entriesFound' => ({required Object count}) => '${count} items found in folder',
			'pleyaShare.cardTitle' => 'Pleya Share',
			'pleyaShare.cardSubtitle' => 'Connect to another Pleya device sharing its media',
			'pleyaShare.hostTitle' => 'Share my media',
			'pleyaShare.hostDescription' => 'Other Pleya devices on this network can browse, stream, and download your local folders. Keep this screen open while sharing.',
			'pleyaShare.hostDescriptionIos' => 'Other Pleya devices on this network can browse, stream, and download your local folders. Sharing keeps running while your device is locked.',
			'pleyaShare.howItWorksTitle' => 'How Pleya Share works',
			'pleyaShare.howItWorksBody' => 'One device is the server: it shares its local folders. Other Pleya devices pair once with the QR code or the 6-digit code and can then browse, stream, and download from it.\n\n• On newer devices (iOS 26+, most Android phones) devices also find each other directly via Wi-Fi Aware, with no hotspot or router at all.\n• Works over Wi-Fi, a personal hotspot, or a cable: ethernet adapters, or USB-C with USB tethering enabled on the host (Android, or iPhone to a computer). Direct iPhone-to-iPad over USB is not supported by iOS. No internet needed.\n• With internet on both devices, streaming also works remotely through the encrypted Pleya relay.\n• Paired devices reconnect automatically — pairing is needed only once.\n• Watch progress and artwork sync with your Plex or Jellyfin account when available.',
			'pleyaShare.hostToggle' => 'Share local folders',
			'pleyaShare.noLocalFolders' => 'Add a local folder first — there is nothing to share yet.',
			'pleyaShare.pairCodeLabel' => 'Pairing code',
			'pleyaShare.pairCodeHint' => 'Enter this code on the other device. The code changes after each successful pairing.',
			'pleyaShare.regenerateCode' => 'New code',
			'pleyaShare.pairedDevices' => 'Paired devices',
			'pleyaShare.noGuests' => 'No devices paired yet',
			'pleyaShare.revokeGuest' => 'Remove device',
			'pleyaShare.joinTitle' => 'Connect to Pleya Share',
			'pleyaShare.joinDescription' => 'Pick a host found on your network or enter its address, then type the 6-digit code shown on that device.',
			'pleyaShare.hostsFound' => 'Hosts on your network',
			'pleyaShare.searching' => 'Searching for hosts…',
			'pleyaShare.noHostsFound' => 'No hosts found. Make sure sharing is turned on and both devices are on the same network.',
			'pleyaShare.refresh' => 'Search again',
			'pleyaShare.manualHost' => 'Host address (IP)',
			'pleyaShare.codeLabel' => '6-digit code',
			'pleyaShare.scanQr' => 'Scan QR code',
			'pleyaShare.scanQrHint' => 'Point the camera at the QR code on the host device',
			'pleyaShare.cameraPermissionDenied' => 'Camera access is needed to scan the QR code.',
			'pleyaShare.connect' => 'Connect',
			'pleyaShare.pairFailed' => 'Pairing failed. Check the code and try again.',
			'pleyaShare.paired' => ({required Object name}) => 'Connected to ${name}',
			'pleyaShare.pairUnreachable' => 'Host not reachable. Check the address and network.',
			'pleyaShare.addFolder' => 'Add a local folder',
			'pleyaShare.notificationTitle' => 'Sharing media',
			'pleyaShare.notificationText' => 'Other Pleya devices can stream your local folders',
			'pleyaShare.hostDescriptionAndroid' => 'Other Pleya devices on this network can browse, stream, and download your local folders. Sharing keeps running in the background with a notification.',
			'pleyaShare.scanningSubnet' => 'Scanning the network…',
			_ => null,
		};
	}
}
