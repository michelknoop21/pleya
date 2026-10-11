import 'package:intl/intl.dart';

import '../../../assistant/assistant_memory.dart';
import '../../../assistant/assistant_memory_overview.dart';
import '../../../i18n/strings.g.dart';
import 'memory_screen_model.dart';

/// Text of the memory screens, built from Pleya's own strings and from the
/// fixed codes the service answers with. Nothing here quotes an error.

/// "9 oktober 2026" in the app language.
String memoryDate(DateTime at) {
  final local = at.toLocal();
  try {
    return DateFormat.yMMMMd(LocaleSettings.currentLocale.languageCode).format(local);
  } on Exception {
    return '${local.day}-${local.month}-${local.year}';
  }
}

/// The line under the title, or empty while the screen still loads.
String memoryStatusLabel(MemoryScreenModel model) {
  final s = t.assistant.memory.screen.status;
  return switch (model.status) {
    MemoryScreenStatus.none => '',
    MemoryScreenStatus.error => s.error,
    MemoryScreenStatus.kids => s.kids,
    MemoryScreenStatus.off => s.off,
    MemoryScreenStatus.empty => s.empty,
    MemoryScreenStatus.waiting => s.waiting,
    MemoryScreenStatus.asking => s.asking,
    MemoryScreenStatus.writing => s.writing,
    MemoryScreenStatus.updated => s.updated,
    MemoryScreenStatus.updatedOn => s.updatedOn(date: memoryDate(model.writtenAt ?? DateTime.now())),
    MemoryScreenStatus.list => s.list,
  };
}

/// The heading of a section of the overview ([kMemoryOverviewSections]).
String memorySectionTitle(String id) {
  final s = t.assistant.memory.screen.sections;
  return switch (id) {
    'overview' => s.overview,
    'preference' => s.preference,
    'dislike' => s.dislike,
    'household' => s.household,
    'habit' => s.habit,
    _ => s.other,
  };
}

String memorySourceLabel(MemorySource source) {
  final s = t.assistant.memory.screen.sources;
  return switch (source) {
    MemorySource.userExplicit => s.userExplicit,
    MemorySource.assistantConfirmed => s.assistantConfirmed,
    MemorySource.settingsManual => s.settingsManual,
  };
}

/// Why a write of the list or the sheet changed nothing, as one sentence.
String memoryCodeMessage(MemoryCode code) {
  final c = t.assistant.memory.screen.codes;
  return switch (code) {
    MemoryCode.exists => c.exists,
    MemoryCode.duplicate => c.duplicate,
    MemoryCode.empty => c.empty,
    MemoryCode.tooLong => c.tooLong(max: kMemoryValueMaxLength),
    MemoryCode.notSingleLine => c.notSingleLine,
    MemoryCode.controlCharacters => c.controlCharacters,
    MemoryCode.ownedKidsAges => c.ownedKidsAges,
    MemoryCode.ownedLanguage => c.ownedLanguage,
    MemoryCode.limitReached => c.limitReached,
    MemoryCode.notFound || MemoryCode.ambiguous => c.notFound,
    MemoryCode.noProfile || MemoryCode.profileGone => c.profileGone,
    MemoryCode.ok || MemoryCode.staleHash || MemoryCode.invalidOverview || MemoryCode.storageFailed => c.storageFailed,
  };
}

/// "8 en 11" for the reference row to Kinderprofiel.
String memoryAgesLabel(List<int> ages) {
  if (ages.length < 2) return ages.join();
  final head = ages.sublist(0, ages.length - 1).join(', ');
  return '$head ${t.assistant.memory.screen.list.and} ${ages.last}';
}

/// "6 herinneringen", or "2 van 6 herinneringen" when a filter hides some.
String memoryCountLabel(int shown, int total) {
  final l = t.assistant.memory.screen.list;
  if (shown != total) return l.countOf(n: shown, m: total);
  return total == 1 ? l.countOne : l.count(n: total);
}

/// The line under the overview: who wrote it, from how many facts, and where
/// the facts themselves are managed ([viaMenu] on a phone, where they sit
/// behind the menu button).
String memoryFooter(MemoryOverviewText overview, {required bool viaMenu}) {
  final s = t.assistant.memory.screen;
  final from = overview.basedOn < overview.total
      ? s.footerPartial(n: overview.basedOn, m: overview.total)
      : overview.total == 1
      ? s.footerOne
      : s.footer(n: overview.total);
  return '$from ${viaMenu ? s.footerManageMenu : s.footerManageList}';
}

/// Why the field gave no answer, from the host's fixed code.
String memoryAskFailure(String code) {
  final a = t.assistant;
  return switch (code) {
    'needs_setup' => a.memory.screen.needsSetup,
    'memory_off' => a.memory.off,
    'kids_mode_unsupported' => a.memory.kids,
    'toolsUnsupported' => a.ends.toolsUnsupported,
    'notEntitled' => a.ends.notEntitled,
    'stepLimit' => a.ends.stepLimit,
    _ => a.memory.screen.askFailed,
  };
}
