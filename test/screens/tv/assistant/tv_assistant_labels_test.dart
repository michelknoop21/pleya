import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_labels.dart';

import 'tv_assistant_test_support.dart';

/// Texts the TV panel builds around the model's answer (visual audit, 3 Oct 2026).
void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.nl));
  tearDown(() => LocaleSettings.setLocale(AppLocale.en));

  test('the greeting leaves no gap where no profile name is', () {
    expect(assistantGreeting('Michel'), 'Hoi Michel, wat moet er gebeuren?');
    expect(assistantGreeting(''), 'Hoi, wat moet er gebeuren?');
  });

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
  });
}
