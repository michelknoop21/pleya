import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/library_atmosphere.dart';

MediaItem _item(String id, {String title = 'Title'}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  serverId: 'source',
  artPath: '/art/$id',
);

class _Host extends StatefulWidget {
  const _Host({super.key});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  List<MediaItem> items = [_item('a'), _item('b')];
  final nodes = [FocusNode(), FocusNode()];
  int taps = 0;

  void clearItems() => setState(() => items = []);
  void replaceFirst() => setState(() => items[0] = _item('replacement'));

  @override
  void dispose() {
    for (final node in nodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LibraryAtmosphere(
      automationInstance: 'test',
      child: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                LibraryArtworkSelection(
                  key: ValueKey(i),
                  item: items[i],
                  child: SizedBox(
                    key: ValueKey('card-$i'),
                    width: 150,
                    height: 210,
                    child: TextButton(focusNode: nodes[i], onPressed: () => taps++, child: Text(items[i].displayTitle)),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Map<String, Object?> _selection(WidgetTester tester) {
  final node = tester.widget<AutomationNode>(
    find.byWidgetPredicate((widget) => widget is AutomationNode && widget.id == AutomationIds.libraryAtmosphere),
  );
  return node.state!()! as Map<String, Object?>;
}

void main() {
  Future<_HostState> pumpHost(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: _Host(key: key),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    return key.currentState!;
  }

  testWidgets('focus changes atmosphere without moving cards or adding an activation tap', (tester) async {
    final host = await pumpHost(tester);
    final before = tester.getRect(find.byKey(const ValueKey('card-1')));
    host.nodes[1].requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_selection(tester)['item_key'], 'source:b');
    expect(_selection(tester)['artwork'], '/art/b');
    expect(tester.getRect(find.byKey(const ValueKey('card-1'))), before);
    await tester.tap(find.byKey(const ValueKey('card-1')));
    expect(host.taps, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unavailable scoped artwork leaves the original page background visible', (tester) async {
    await pumpHost(tester);
    expect(_selection(tester)['available'], false);
    final layer = find.byWidgetPredicate(
      (widget) => widget is AutomationNode && widget.id == AutomationIds.libraryAtmosphere,
    );
    expect(find.descendant(of: layer, matching: find.byType(ColoredBox)), findsNothing);
    expect(find.descendant(of: layer, matching: find.byType(DecoratedBox)), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('removing all titles clears the old atmosphere', (tester) async {
    final host = await pumpHost(tester);
    host.nodes[0].requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_selection(tester)['item_key'], 'source:a');
    host.clearItems();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_selection(tester)['item_key'], isNull);
    expect(_selection(tester)['artwork'], isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('replacement in the same focused cell uses the new item', (tester) async {
    final host = await pumpHost(tester);
    host.nodes[0].requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    host.replaceFirst();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(host.nodes[0].hasFocus, isTrue);
    expect(_selection(tester)['item_key'], 'source:replacement');
    expect(_selection(tester)['artwork'], '/art/replacement');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mobile viewport resize follows the newly central visible card', (tester) async {
    await pumpHost(tester);
    expect(_selection(tester)['item_key'], 'source:b');
    tester.view.physicalSize = const Size(280, 400);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_selection(tester)['item_key'], 'source:a');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rapid A to B to A cancels the pending intermediate artwork', (tester) async {
    final host = await pumpHost(tester);
    host.nodes[0].requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    host.nodes[1].requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    host.nodes[0].requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_selection(tester)['item_key'], 'source:a');
    await tester.pumpWidget(const SizedBox());
  });
}
