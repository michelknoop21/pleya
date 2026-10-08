import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/widgets/big_p/big_p_avatar.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_labels.dart';

import 'tv_assistant_test_support.dart';

/// Texts the TV panel builds around the model's answer (visual audit, 3 Oct 2026).
void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.nl));
  tearDown(() => LocaleSettings.setLocale(AppLocale.en));

  test('every registered tool has a step label, in both languages', () {
    final missing = <String>[];
    for (final tool in assistantTools) {
      LocaleSettings.setLocaleSync(AppLocale.en);
      final en = assistantToolLabel(tool.name);
      final enFallback = t.assistant.steps.fallback;
      LocaleSettings.setLocaleSync(AppLocale.nl);
      final nl = assistantToolLabel(tool.name);
      if (en == enFallback || nl == t.assistant.steps.fallback || en == nl) missing.add(tool.name);
    }
    expect(missing, isEmpty);
  });

  test('the greeting leaves no gap where no profile name is', () {
    expect(assistantGreeting('Michel'), 'Hoi Michel, wat moet er gebeuren?');
    expect(assistantGreeting(''), 'Hoi, wat moet er gebeuren?');
  });

  for (final status in [AssistantTaskStatus.cancelled, AssistantTaskStatus.failed, AssistantTaskStatus.running]) {
    test('task $status cannot project model success, even above title cards', () {
      final c = FakeAssistantController()
        ..state = AssistantSurfaceState.result
        ..answer = 'Gedaan: «Alien», «Aliens».'
        ..tasks = [
          AssistantTask(
            id: '1',
            title: 'Verwijder',
            intent: 'command',
            status: status,
            answer: 'Gedaan: «Alien», «Aliens».',
            displays: const [],
            steps: const [],
            actions: const [],
            error: 'cancelled_by_user',
          ),
        ];
      addTearDown(c.dispose);
      expect(bigPMood(c), isNot(BigPMood.success));
      expect(assistantHeadline(c), isNot(contains('Gedaan')));
      expect(assistantCardsLead(c), isNot(contains('Gedaan')));
    });
  }

  group('the lead above title cards', () {
    String lead(String answer) {
      final c = FakeAssistantController()
        ..state = AssistantSurfaceState.result
        ..answer = answer;
      addTearDown(c.dispose);
      return assistantCardsLead(c);
    }

    test('drops an inline list of the titles the cards show', () {
      expect(
        lead('Dit zijn de beste kandidaten: «The Martian», «Red Planet», «Interstellar» en «Gravity».'),
        'Dit zijn de beste kandidaten.',
      );
      expect(lead('Try these: «Alien» and «Aliens»! Both are on Zolder.'), 'Try these. Both are on Zolder.');
    });

    test('keeps titles named in a sentence, and drops list lines as before', () {
      expect(lead('«The Martian» staat op Zolder.'), 'The Martian staat op Zolder.');
      expect(lead('Gevonden:\n1. «Alien»\n2. «Aliens»'), 'Gevonden:');
    });

    test('a list that runs on in the sentence keeps its titles and years', () {
      expect(
        lead(
          'The latest additions are mostly 2026 releases: «Paw Patrol» (2022) and «Lanterns» (2026) joined alongside a few classics.',
        ),
        'The latest additions are mostly 2026 releases: Paw Patrol (2022) and Lanterns (2026) joined alongside a few classics.',
      );
      expect(
        lead('Also recently added: «Bugonia» (2025), Team America: World Police (2004) and more.'),
        'Also recently added: Bugonia (2025), Team America: World Police (2004) and more.',
      );
    });

    test('a list with years that ends the sentence goes with its years', () {
      expect(
        lead('Nieuw binnen: «Paw Patrol» (2022) en «Lanterns» (2026). Veel kijkplezier.'),
        'Nieuw binnen. Veel kijkplezier.',
      );
      expect(lead('Also recently added: «Bugonia» (2025), «Weapons» (2025)'), 'Also recently added.');
    });
  });
}
