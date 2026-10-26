import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/navigation/tv/tv_content_route_registry.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/screens/settings/memory/memory_screen.dart';
import 'package:pleya/screens/settings/memory/memory_tv_widgets.dart';
import 'package:pleya/navigation/profile_memory_sync.dart';
import 'package:pleya/screens/settings/memory/memory_sync_screen.dart';
import 'package:pleya/screens/settings/memory/memory_widgets.dart';
import 'package:pleya/services/memory/memory_service.dart';
import 'package:pleya/i18n/strings.g.dart';

import 'memory_screen_support.dart';
import '../../../services/memory/memory_test_support.dart' show resetMemoryPrefs;

class _Server implements MemorySyncTransport {
  int writes = 0;
  MemorySyncSnapshot snapshot = MemorySyncSnapshot(
    epoch: '00000000-0000-4000-8000-000000000001',
    revision: 0,
    facts: [],
  );
  @override
  Future<MemorySyncSnapshot> fetch() async => snapshot;

  @override
  Future<MemorySyncSnapshot> replace({
    required String epoch,
    required int baseRevision,
    required List<MemoryFact> facts,
  }) async {
    if (epoch != snapshot.epoch || baseRevision != snapshot.revision) {
      throw const MemorySyncFailure('memory.conflict');
    }
    writes++;
    return snapshot = MemorySyncSnapshot(epoch: epoch, revision: baseRevision + 1, facts: facts);
  }

  @override
  Future<MemorySyncSnapshot> clear({required String epoch, required int baseRevision}) async =>
      throw UnimplementedError();
}

class _Binding extends ChangeNotifier implements ProfileMemorySync {
  _Binding(this.sync) {
    sync.addListener(notifyListeners);
  }
  @override
  final MemorySyncService sync;
  @override
  bool get eligible => true;
  @override
  List<({String key, String label})> get accounts => [(key: 'account', label: 'Eigen account')];
  @override
  Future<void> refresh() async {}
  @override
  void dispose() {
    sync.removeListener(notifyListeners);
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    await resetMemoryPrefs();
  });
  for (final tv in [false, true]) {
    testWidgets('explicit import preview before upload on ${tv ? 'TV' : 'phone'}', (tester) async {
      final h = MemoryScreenHarness();
      final server = _Server();
      final sync = MemorySyncService(
        memory: h.service,
        transportFor: (_) async => server,
        isEligible: () => true,
        isCurrent: () => true,
      );
      final binding = _Binding(sync);
      await tester.runAsync(() async {
        await useDutch();
        await h.service.add(
          value: 'Houdt van sciencefiction',
          category: MemoryCategory.preference,
          source: MemorySource.settingsManual,
        );
        await h.service.add(
          value: 'Kijkt samen met familie',
          category: MemoryCategory.household,
          source: MemorySource.settingsManual,
        );
      });
      await pumpMemoryApp(
        tester,
        MemorySyncScreen(binding: binding),
        tv: tv,
        size: tv ? tvSize : phoneSize,
      );
      expect(find.text('Eigen account'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Eigen account'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Houdt van sciencefiction'), findsOneWidget);
      expect(find.text('Kijkt samen met familie'), findsNothing);
      expect(server.writes, 0, reason: 'Choosing an account is not upload consent');
      await tester.runAsync(() async {
        await tester.tap(find.text(t.assistant.memory.sync.connect));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(server.writes, 1);
      expect(server.snapshot.facts.single.value, 'Houdt van sciencefiction');
      expect(find.text(t.assistant.memory.sync.synced), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      binding.dispose();
      sync.dispose();
      await tester.runAsync(h.dispose);
    });
  }
  testWidgets('combined device limit blocks confirmation before an import', (tester) async {
    final h = MemoryScreenHarness();
    final server = _Server();
    final at = DateTime.utc(2026);
    server.snapshot = MemorySyncSnapshot(
      epoch: server.snapshot.epoch,
      revision: 1,
      facts: [
        for (var i = 0; i < 200; i++)
          MemoryFact(
            id: '00000000-0000-4000-8000-${(i + 2).toRadixString(16).padLeft(12, '0')}',
            value: 'Server feit $i',
            category: MemoryCategory.preference,
            source: MemorySource.settingsManual,
            createdAt: at,
            updatedAt: at,
          ),
      ],
    );
    final sync = MemorySyncService(
      memory: h.service,
      transportFor: (_) async => server,
      isEligible: () => true,
      isCurrent: () => true,
    );
    final binding = _Binding(sync);
    await tester.runAsync(() async {
      await useDutch();
      await h.service.add(
        value: 'Lokaal nieuw feit',
        category: MemoryCategory.preference,
        source: MemorySource.settingsManual,
      );
    });
    await pumpMemoryApp(tester, MemorySyncScreen(binding: binding));
    await tester.runAsync(() async {
      await tester.tap(find.text('Eigen account'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    final button = tester.widget<MemoryPillButton>(
      find.widgetWithText(MemoryPillButton, t.assistant.memory.sync.connect),
    );
    expect(button.onPressed, isNull);
    expect(find.text(t.assistant.memory.sync.importLimit(count: '201')), findsOneWidget);
    expect(sync.accountKey, isNull);
    expect(server.writes, 0);
    final preview = await tester.runAsync(() => sync.preview('account'));
    expect(preview!.combinedCount({}), 201, reason: 'Unselected facts still occupy local space');
    await tester.pumpWidget(const SizedBox.shrink());
    binding.dispose();
    sync.dispose();
    await tester.runAsync(h.dispose);
  });
  testWidgets('return from the nested sync route restores its TV launcher', (tester) async {
    final h = MemoryScreenHarness();
    final server = _Server();
    final sync = MemorySyncService(
      memory: h.service,
      transportFor: (_) async => server,
      isEligible: () => true,
      isCurrent: () => true,
    );
    final binding = _Binding(sync);
    final content = FocusNode(debugLabel: 'Content fallback');
    final closed = Completer<Object?>();
    TvNestedRoute? opened;
    Future<Object?> push(TvNestedRoute route) {
      opened = route;
      content.requestFocus();
      return closed.future;
    }

    tvContentRouteRegistry.attach(push);
    await tester.runAsync(useDutch);
    await pumpMemoryApp(
      tester,
      Focus(
        focusNode: content,
        child: ChangeNotifierProvider<ProfileMemorySync>.value(
          value: binding,
          child: AssistantMemoryScreen(model: h.model),
        ),
      ),
      tv: true,
      size: tvSize,
    );
    final tile = tester
        .widgetList<MemoryTvTile>(find.byType(MemoryTvTile))
        .firstWhere((tile) => tile.instance == 'sync');
    tile.node.requestFocus();
    await tester.pump();
    expect(tile.node.hasFocus, isTrue);
    tile.onSelect!();
    await tester.pump();
    expect(opened?.id, 'tvSettings_assistantMemorySync');
    expect(content.hasPrimaryFocus, isTrue);
    closed.complete(null);
    await tester.pumpAndSettle();
    expect(tile.node.hasFocus, isTrue);
    tvContentRouteRegistry.detach(push);
    await tester.pumpWidget(const SizedBox.shrink());
    content.dispose();
    binding.dispose();
    sync.dispose();
    await tester.runAsync(h.dispose);
  });
  testWidgets('reviewing restored memory leaves the TV confirmation focused', (tester) async {
    final h = MemoryScreenHarness();
    final server = _Server();
    final sync = MemorySyncService(
      memory: h.service,
      transportFor: (_) async => server,
      isEligible: () => true,
      isCurrent: () => true,
    );
    final binding = _Binding(sync);
    await tester.runAsync(() async {
      await useDutch();
      await sync.connect(await sync.preview('account'));
      final at = DateTime.utc(2026);
      server.snapshot = MemorySyncSnapshot(
        epoch: '00000000-0000-4000-8000-000000000099',
        revision: 0,
        facts: [
          MemoryFact(
            id: '00000000-0000-4000-8000-000000000098',
            value: 'Herstelde voorkeur',
            category: MemoryCategory.preference,
            source: MemorySource.settingsManual,
            createdAt: at,
            updatedAt: at,
          ),
        ],
      );
      await sync.sync(force: true);
    });
    expect(sync.quarantine, isNotNull);
    await pumpMemoryApp(tester, MemorySyncScreen(binding: binding), tv: true, size: tvSize);
    final s = t.assistant.memory.sync;
    final review = Focus.of(tester.element(find.text(s.reviewReset)));
    review.requestFocus();
    await tester.pump();
    expect(review.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final accept = Focus.of(tester.element(find.text(s.acceptReset)));
    expect(accept.hasFocus, isTrue);
    expect(sync.quarantine, isNotNull, reason: 'Focus is not consent');
    await tester.pumpWidget(const SizedBox.shrink());
    binding.dispose();
    sync.dispose();
    await tester.runAsync(h.dispose);
  });
  testWidgets('resolving a conflict leaves a usable TV action focused', (tester) async {
    final h = MemoryScreenHarness();
    final server = _Server();
    var eligible = true;
    final sync = MemorySyncService(
      memory: h.service,
      transportFor: (_) async => server,
      isEligible: () => eligible,
      isCurrent: () => true,
    );
    final binding = _Binding(sync);
    await tester.runAsync(() async {
      await useDutch();
      final added = await h.service.add(
        value: 'Oorspronkelijke voorkeur',
        category: MemoryCategory.preference,
        source: MemorySource.settingsManual,
      );
      await sync.connect(await sync.preview('account'));
      eligible = false;
      final edited = await h.service.update(added.fact!.id, value: 'Lokale wijziging');
      expect(edited.code, MemoryCode.ok);
      final old = server.snapshot.facts.single;
      server.snapshot = MemorySyncSnapshot(
        epoch: server.snapshot.epoch,
        revision: server.snapshot.revision + 1,
        facts: [
          MemoryFact(
            id: old.id,
            value: 'Serverwijziging',
            category: old.category,
            source: old.source,
            createdAt: old.createdAt,
            updatedAt: old.updatedAt.add(const Duration(seconds: 1)),
          ),
        ],
      );
      eligible = true;
      for (var i = 0; i < 3; i++) {
        await sync.sync(force: true);
      }
    });
    expect(sync.status, MemorySyncStatus.conflict);
    expect(sync.conflicts, hasLength(1));
    await pumpMemoryApp(tester, MemorySyncScreen(binding: binding), tv: true, size: tvSize);
    final s = t.assistant.memory.sync;
    final choice = Focus.of(tester.element(find.text(s.keepServer)));
    choice.requestFocus();
    await tester.pump();
    expect(choice.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(sync.conflicts, isEmpty);
    final refresh = Focus.of(tester.element(find.text(s.refresh)));
    expect(refresh.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    binding.dispose();
    sync.dispose();
    await tester.runAsync(h.dispose);
  });
}
