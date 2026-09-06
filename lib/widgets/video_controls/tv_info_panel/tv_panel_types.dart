/// The four tabs of the TV player panel (DEC-101).
enum TvInfoPanelTab { information, video, audio, subtitles }

/// A layer the panel can open over a tab. Menu goes back one layer.
enum TvInfoPanelSubView { none, audioSync, subtitleSync, chapters, sleepTimer, versionQuality, shaders }

/// What a caller asks the panel to open on: a tab, and optionally a sub-view
/// over it. The tune button asks for [TvInfoPanelTab.video], the tracks button
/// for audio or subtitles, the chapters button for video with [chapters].
class TvInfoPanelRequest {
  const TvInfoPanelRequest(this.tab, {this.subView = TvInfoPanelSubView.none});

  final TvInfoPanelTab tab;
  final TvInfoPanelSubView subView;

  static const information = TvInfoPanelRequest(TvInfoPanelTab.information);
  static const video = TvInfoPanelRequest(TvInfoPanelTab.video);
  static const audio = TvInfoPanelRequest(TvInfoPanelTab.audio);
  static const subtitles = TvInfoPanelRequest(TvInfoPanelTab.subtitles);
  static const chapters = TvInfoPanelRequest(TvInfoPanelTab.video, subView: TvInfoPanelSubView.chapters);

  @override
  bool operator ==(Object other) => other is TvInfoPanelRequest && other.tab == tab && other.subView == subView;

  @override
  int get hashCode => Object.hash(tab, subView);

  @override
  String toString() => 'TvInfoPanelRequest(${tab.name}, ${subView.name})';
}
