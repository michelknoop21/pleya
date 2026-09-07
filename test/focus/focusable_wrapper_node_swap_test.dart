import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focusable_wrapper.dart';

/// ROW1p: het Home-aanpaspaneel liet meerdere rijen tegelijk de focusindicator
/// dragen — drie witte "Hide"-capsules naast elkaar, vier omringde pijlknoppen
/// onder elkaar. Er kan er maar één de focus hebben, dus de indicator hing daar
/// niet aan.
///
/// De oorzaak zit niet in het paneel maar in [FocusableWrapper]. Zijn
/// `didUpdateWidget` koppelt een gewijzigde `focusNode` netjes aan en laat
/// `_isFocused` staan op wat de *vorige* node had. Er komt daarna ook geen
/// `onFocusChange`: de melding dat de oude node zijn focus kwijt is, gaat naar
/// de `Focus`-widget die inmiddels de nieuwe node draagt, en die vertaalt hem
/// niet meer terug naar het slot waar hij vandaan kwam.
///
/// Een lijst die zijn kinderen zonder `key` herschikt is precies dat geval:
/// Flutter hergebruikt het element op die positie voor een andere rij en reikt
/// het een andere node aan. Het paneel zet de ring daarna zelf terug op de
/// verplaatste rij (`_pendingFocusKey`), dus er komt een nieuw slot bij dat
/// zich gefokust weet — zonder dat het oude slot dat ooit heeft ingetrokken.
/// Elke verplaatsing laat er zo één achter.
void main() {
  /// Hoeveel slots zichzelf op dat moment als gefocust beschouwen.
  ///
  /// Gemeten aan wat [FocusableWrapper] naar buiten meldt, want dat is precies
  /// de waarde waar `TvPanelButton` zijn witte vulling op zet en waar de ring
  /// van de pijlknoppen aan hangt.
  late List<bool> believesFocused;

  Future<void> pumpSlots(WidgetTester tester, List<FocusNode> nodes) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (var i = 0; i < nodes.length; i++)
                FocusableWrapper(
                  focusNode: nodes[i],
                  onFocusChange: (focused) => believesFocused[i] = focused,
                  child: SizedBox(width: 100, height: 40, child: Text('slot $i')),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a reorder leaves exactly one slot believing it is focused', (tester) async {
    final a = FocusNode(debugLabel: 'a');
    final b = FocusNode(debugLabel: 'b');
    final c = FocusNode(debugLabel: 'c');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    addTearDown(c.dispose);

    believesFocused = [false, false, false];
    await pumpSlots(tester, [a, b, c]);

    a.requestFocus();
    await tester.pumpAndSettle();
    expect(believesFocused, [true, false, false], reason: 'slot 0 holds the focus to begin with');

    // Row a moves down past b: the slots keep their positions and swap nodes,
    // which is what a keyless list does. The panel then puts the ring back on
    // the row that moved, the way `_restorePendingFocus` does.
    await pumpSlots(tester, [b, a, c]);
    a.requestFocus();
    await tester.pumpAndSettle();

    expect(
      believesFocused,
      [false, true, false],
      reason:
          'the focused row is now slot 1, so slot 1 draws the indicator and slot 0 does not. '
          'Left uncorrected slot 0 keeps its own true, and every further move adds another',
    );

    // And once more, so the count cannot pass by accident on a single swap.
    await pumpSlots(tester, [b, c, a]);
    a.requestFocus();
    await tester.pumpAndSettle();

    expect(believesFocused.where((f) => f).length, 1, reason: 'after two moves: still one indicator, not three');
  });

  testWidgets('and a swap between two unfocused nodes says nothing', (tester) async {
    final a = FocusNode(debugLabel: 'a');
    final b = FocusNode(debugLabel: 'b');
    addTearDown(a.dispose);
    addTearDown(b.dispose);

    var calls = 0;
    Future<void> pump(FocusNode node) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FocusableWrapper(
              focusNode: node,
              onFocusChange: (_) => calls++,
              child: const SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(a);
    calls = 0;

    await pump(b);
    expect(calls, 0, reason: 'neither node has the focus, so there is no change to report');
  });
}
