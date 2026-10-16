/// What the row wizard needs from the app, built once for every surface that
/// runs it (tvOS panel, phone/tablet/desktop screen): which libraries a kind
/// can draw from, and the preview query (HOME-R1).
///
/// The preview is the row's own question, asked early: same loader, same
/// limit, so what step 3 draws is what Home will draw.
library;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../media/ids.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../providers/hidden_libraries_provider.dart';
import '../../providers/libraries_provider.dart';
import '../../providers/home_custom_rows_provider.dart' show kHomeCustomRowCardLimit;
import '../../providers/multi_server_provider.dart';
import 'home_custom_row.dart';
import 'home_custom_row_loader.dart';
import 'source_cursor.dart';

/// Test seam: when set, [HomeRowEditing.of] answers with this instead of
/// reading the app's providers.
@visibleForTesting
HomeRowEditing Function(BuildContext context)? homeRowEditingOverride;

class HomeRowEditing {
  const HomeRowEditing({required this.librariesFor, required this.preview, required this.clientFor});

  final List<CatalogLibrary> Function(MediaKind kind) librariesFor;
  final Future<HomeCustomRowContent> Function(HomeCustomRow draft) preview;
  final MediaServerClient? Function(String serverId) clientFor;

  /// Built per opening rather than held: this is a view over three providers,
  /// and one kept across a profile switch would be a view over the wrong ones.
  static HomeRowEditing of(BuildContext context, {MediaServerClient? Function(String serverId)? clientFor}) {
    final override = homeRowEditingOverride;
    if (override != null) return override(context);
    final multiServer = context.read<MultiServerProvider>();
    final libraries = context.read<LibrariesProvider>();
    final hiddenLibraries = context.read<HiddenLibrariesProvider>();
    final loader = CatalogHomeCustomRowLoader(
      libraries: () => libraries.libraries,
      isServerVisible: multiServer.serverManager.isServerVisible,
      hiddenLibraryKeys: () => hiddenLibraries.hiddenLibraryKeys,
      clientFor: multiServer.serverManager.getClient,
    );
    return HomeRowEditing(
      librariesFor: (kind) => eligibleCatalogLibraries(
        libraries: libraries.libraries,
        kind: kind,
        isServerVisible: multiServer.serverManager.isServerVisible,
        hiddenLibraryKeys: hiddenLibraries.hiddenLibraryKeys,
      ),
      preview: (draft) => loader.load(draft, limit: kHomeCustomRowCardLimit),
      clientFor: clientFor ?? (serverId) => multiServer.serverManager.getClient(ServerId(serverId)),
    );
  }
}
