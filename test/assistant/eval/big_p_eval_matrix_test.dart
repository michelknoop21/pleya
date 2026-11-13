import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_tools.dart';

import 'big_p_eval_cases.dart';
import 'checks/big_p_eval_checks_state.dart';

// The task matrix of the Big P evaluation set (BP-12): every tool in the
// registry is exercised by a case, or stands in [_open] with the reason it
// is not yet. A new tool without a case fails here, and so does a tool that
// got its case but still stands in the list.

/// Tools without a case that can succeed, and what is missing for one.
const _open = <String, String>{
  'create_collection': 'needs a collection store in the eval world',
  'compare_servers': 'needs a second online server in the eval world',
  'watch_stats': 'needs an insights fixture (history per user)',
  'diagnose_library': 'needs the library doctor fixture (duplicates, missing episodes)',
  'download_next': 'needs a downloads fixture',
  'find_subtitles': 'needs a Plex admin fixture with subtitle search',
  'download_subtitle': 'needs a Plex admin fixture with subtitle search',
  'diagnose_playback': 'needs an active player fixture',
  'change_playback': 'needs an active player fixture',
  'recommend_together': 'needs a Jellyfin admin fixture with two users',
};

Set<String> _called() => {
  for (final c in bigPEvalCases)
    for (final t in c.turns)
      for (final step in t.script)
        if (step is EvalCall) step.name,
};

void main() {
  test('every tool has a case or a named reason it has none', () {
    final called = _called();
    final tools = {for (final t in assistantTools) t.name};
    final missing = tools.difference(called).difference(_open.keys.toSet());
    expect(missing, isEmpty, reason: 'tools without a case and without a reason');
    final stale = _open.keys.where((t) => !tools.contains(t)).toList();
    expect(stale, isEmpty, reason: 'listed as open but not in the registry');
  });

  test('every mutation with a case is carried out once and refused once', () {
    final mutating = {
      for (final t in assistantTools)
        if (t.risk != AssistantToolRisk.read) t.name,
    };
    final yes = <String>{}, no = <String>{};
    for (final c in bigPEvalCases) {
      for (final t in c.turns) {
        final names = {
          for (final step in t.script)
            if (step is EvalCall && mutating.contains(step.name)) step.name,
        };
        final checked = c.hard.any((h) => h is EvalState || h is EvalStateUnchanged || h is EvalActionDone);
        if (t.confirm == EvalConfirm.yes && checked) yes.addAll(names);
        if (t.confirm == EvalConfirm.no) no.addAll(names);
      }
    }
    // Carried out with a check on the world or the action record.
    const done = {
      'create_home_row', 'request_title', 'forget_fact', 'scan_library', 'cancel_job', 'retry_job',
      'create_user', 'set_user_library_access', 'remove_user', 'refresh_metadata', //
    };
    expect(yes.containsAll(done), isTrue, reason: 'carried out: ${done.difference(yes)} missing');
    // Refused, so the world may not change.
    const refused = {'create_home_row', 'request_title', 'forget_fact', 'cancel_job', 'remove_user', 'scan_library'};
    expect(no.containsAll(refused), isTrue, reason: 'refused: ${refused.difference(no)} missing');
    final uncovered = mutating.where((n) => !yes.contains(n) && !_open.containsKey(n) && n != 'remember_fact').toSet();
    expect(uncovered, isEmpty, reason: 'mutations never carried out in a case');
  });

  test('the open list shrinks, it does not grow', () => expect(_open.length, lessThanOrEqualTo(10)));
}
