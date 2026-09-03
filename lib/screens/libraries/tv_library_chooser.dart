/// Which libraries a viewer on TV can reach, and how they are labelled.
///
/// Pulled out of `libraries_screen.dart` on purpose. This is the rule the
/// audit of 2 September 2026 found broken — two libraries loaded, one
/// reachable — and a rule about reachability should be checkable without
/// standing up the whole screen, its nine providers and its tab controller.
///
/// The screen keeps the wiring: it decides when the header line is on show at
/// all, owns the focus nodes, and hands [onSelect] the same
/// `_loadLibraryContent` the mobile dropdown has always called. Selection
/// behaviour is untouched, which is what keeps iOS and macOS exactly as they
/// were.
library;

import '../../media/media_library.dart';
import '../../utils/content_utils.dart';
import '../../widgets/tv/tv_page_chip_bar.dart';

/// Whether the chooser has anything to choose between.
///
/// One library needs no chooser: a row holding a single capsule that reloads
/// what is already open is noise, and the page heading names it already.
bool tvLibraryChooserVisible(List<MediaLibrary> visibleLibraries) => visibleLibraries.length > 1;

/// One capsule per visible library, the open one carrying the outline.
///
/// Hidden libraries are absent because the caller passes the visible list —
/// the chooser must not become a second route around Library Visibility.
List<TvPageChip> tvLibraryChooserChips({
  required List<MediaLibrary> visibleLibraries,
  required String? selectedGlobalKey,
  required void Function(String globalKey) onSelect,
}) {
  // The server name only earns a place on a capsule when there is more than
  // one server, and then it is the thing that tells two "Movies" apart.
  final servers = visibleLibraries.map((l) => l.serverId).toSet();
  final showServer = servers.length > 1;

  return [
    for (final library in visibleLibraries)
      TvPageChip(
        key: 'library_${library.globalKey}',
        icon: ContentTypeHelper.getLibraryIcon(library.kind.id),
        label: showServer && (library.serverName?.isNotEmpty ?? false)
            ? '${library.title} · ${library.serverName}'
            : library.title,
        selected: library.globalKey == selectedGlobalKey,
        onSelect: () => onSelect(library.globalKey),
      ),
  ];
}
