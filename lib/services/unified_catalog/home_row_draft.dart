/// The state of "Nieuwe rij" / "Rij bewerken", independent of how it is drawn
/// (HOME-R1, mockup 32 C and 44 G-J).
///
/// The tvOS wizard and the phone, tablet and desktop wizard run the same three
/// steps over the same question: name and kind, filters, and a preview that is
/// a real query. Everything that is a rule rather than a widget lives here once:
///
/// * changing the kind drops a source restriction, because the libraries it
///   names belong to the other kind (hoofdstuk 10.6);
/// * the preview carries a generation so a slow answer to a filter the viewer
///   has already changed cannot land on top of a newer one;
/// * an empty preview cannot be saved (C4): the way forward is the filters.
library;

import 'package:flutter/widgets.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_kind.dart';
import '../../utils/home_custom_row_labels.dart';
import 'home_custom_row.dart';
import 'home_custom_row_loader.dart';
import 'unified_catalog_filters.dart';

enum HomeRowWizardStep { nameAndKind, filters, preview }

/// The five lines of the filters step: which one, what it is called, and what
/// is currently set (mockup 28 D2). [key] is one of `status`, `genre`, `year`,
/// `sources`, `sort`.
typedef HomeRowFilterLine = ({String key, String label, String value});

class HomeRowDraft extends ChangeNotifier {
  HomeRowDraft({this.initial, required Future<HomeCustomRowContent> Function(HomeCustomRow draft) preview})
    : _preview = preview,
      name = TextEditingController(text: initial?.name ?? ''),
      id = initial?.id ?? HomeCustomRow.newId(),
      kind = initial?.kind ?? MediaKind.movie,
      preferences = initial?.preferences ?? UnifiedCatalogPreferences.defaults {
    name.addListener(notifyListeners);
  }

  /// The row being edited, or null for a new one. An edit keeps the id, so the
  /// row keeps its place in the stored order.
  final HomeCustomRow? initial;
  final Future<HomeCustomRowContent> Function(HomeCustomRow draft) _preview;

  final TextEditingController name;
  final String id;
  MediaKind kind;
  UnifiedCatalogPreferences preferences;

  HomeRowWizardStep step = HomeRowWizardStep.nameAndKind;
  HomeCustomRowContent? content;
  bool isPreviewing = false;
  int _generation = 0;
  bool _disposed = false;

  HomeCustomRow get draft => HomeCustomRow(id: id, kind: kind, name: name.text.trim(), preferences: preferences);

  /// A preview that found something. Never an empty one (C4).
  bool get canSave => step == HomeRowWizardStep.preview && content != null && !content!.isEmpty;

  void setKind(MediaKind next) {
    kind = next;
    // An invisible filter with no row to untick it is worse than a lost choice.
    preferences = preferences.copyWith(
      filters: preferences.filters.copyWith(serverIds: const {}, libraryKeys: const {}),
    );
    notifyListeners();
  }

  void setFilters(UnifiedCatalogFilterSelection filters) {
    preferences = preferences.copyWith(filters: filters);
    notifyListeners();
  }

  void setSort(UnifiedCatalogSort sort) {
    preferences = preferences.copyWith(sort: sort);
    notifyListeners();
  }

  void goTo(HomeRowWizardStep next) {
    step = next;
    notifyListeners();
    if (next == HomeRowWizardStep.preview) loadPreview();
  }

  Future<void> loadPreview() async {
    final generation = ++_generation;
    isPreviewing = true;
    notifyListeners();
    final result = await _preview(draft);
    if (_disposed || generation != _generation) return;
    content = result;
    isPreviewing = false;
    notifyListeners();
  }

  /// The filters step's five lines, worded once for every surface.
  List<HomeRowFilterLine> filterLines(String Function(UnifiedCatalogSort sort) sortLabel) {
    final filters = preferences.filters;
    final rows = t.unifiedCatalog.homeRows;
    return [
      (key: 'status', label: rows.status, value: unifiedWatchFilterLabel(filters.watchState)),
      (
        key: 'genre',
        label: rows.genre,
        value: filters.genres.isEmpty ? t.unifiedCatalog.rail.noFilters : (filters.genres.toList()..sort()).join(', '),
      ),
      (
        key: 'year',
        label: rows.year,
        value: filters.years.isEmpty ? rows.allYears : (filters.years.toList()..sort()).join(', '),
      ),
      (
        key: 'sources',
        label: rows.sources,
        value: filters.restrictsSources
            ? t.unifiedCatalog.rail.filtersActive(count: filters.activeCount - filters.itemFilterCount)
            : t.unifiedCatalog.allSources,
      ),
      (key: 'sort', label: rows.sorting, value: sortLabel(preferences.sort)),
    ];
  }

  /// The chips under the filter lines: the kind and every item filter. The
  /// sort is the muted chip after them and is the caller's to word.
  List<String> filterTags() => [
    kind == MediaKind.movie ? t.unifiedCatalog.moviesTitle : t.unifiedCatalog.seriesTitle,
    ...homeCustomRowFilterParts(draft),
  ];

  @override
  void dispose() {
    _disposed = true;
    name.dispose();
    super.dispose();
  }
}
