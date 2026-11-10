import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/widgets/optimized_media_image.dart';
import 'package:pleya/widgets/unified_media_image.dart';

import '../test_helpers/tv_catalog_fixtures.dart';

class _Client extends Fake implements MediaServerClient {
  _Client(String id, {this.empty = false}) : serverId = ServerId(id);
  final bool empty;
  @override
  final ServerId serverId;
  @override
  String thumbnailUrl(String? path, {int? width, int? height}) =>
      empty ? '' : 'https://${serverId.value}.invalid/${Uri.encodeComponent(path ?? '')}';
}

void main() {
  setUp(() => OptimizedMediaImage.debugImageBuilder = (_, path) => Text(path ?? 'NONE'));
  tearDown(() => OptimizedMediaImage.debugImageBuilder = null);

  for (final primaryBackend in MediaBackend.values) {
    testWidgets('missing poster falls back from $primaryBackend with the matching client', (tester) async {
      final primary = tvGoldenMovie(id: 'one', title: 'Dune', serverId: 'one', backend: primaryBackend);
      final other = tvGoldenMovie(
        id: 'two',
        title: 'Dune',
        serverId: 'two',
        backend: primaryBackend == MediaBackend.pleyaServer ? MediaBackend.plex : MediaBackend.pleyaServer,
      ).copyWith(thumbPath: '/two-poster');
      final clients = {'one': _Client('one'), 'two': _Client('two')};
      final group = tvGoldenGroup('g', [primary, other]);
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedMediaImage(group: group, pathOf: (item) => item.posterThumb(), clientFor: (id) => clients[id]),
        ),
      );
      expect(find.text('/two-poster'), findsOneWidget);
      final image = tester.widget<OptimizedMediaImage>(find.byType(OptimizedMediaImage));
      expect(image.client, same(clients['two']));
      expect(group.representativeSource.item, same(primary));
    });
  }

  testWidgets('failed images advance in order, terminate and reset for a new group', (tester) async {
    final first = tvGoldenMovie(id: 'one', title: 'Dune', serverId: 'one').copyWith(thumbPath: '/one');
    final second = tvGoldenMovie(id: 'two', title: 'Dune', serverId: 'two').copyWith(thumbPath: '/two');
    final clients = {'one': _Client('one'), 'two': _Client('two')};
    Widget mount(Widget child) => MaterialApp(home: child);
    await tester.pumpWidget(
      mount(
        UnifiedMediaImage(
          group: tvGoldenGroup('g', [first, second]),
          pathOf: (item) => item.posterThumb(),
          clientFor: (id) => clients[id],
        ),
      ),
    );
    var image = tester.widget<OptimizedMediaImage>(find.byType(OptimizedMediaImage));
    expect(image.imagePath, '/one');
    expect(image.client, same(clients['one']));
    var fallback = image.errorWidget!(tester.element(find.byType(OptimizedMediaImage)), 'failed', Exception('404'));
    await tester.pumpWidget(mount(fallback));
    image = tester.widget<OptimizedMediaImage>(find.byType(OptimizedMediaImage));
    expect(image.imagePath, '/two');
    expect(image.client, same(clients['two']));
    fallback = image.errorWidget!(tester.element(find.byType(OptimizedMediaImage)), 'failed', Exception('403'));
    await tester.pumpWidget(mount(fallback));
    image = tester.widget<OptimizedMediaImage>(find.byType(OptimizedMediaImage));
    expect(image.imagePath, isNull);
    expect(image.errorWidget, isNull);
    await tester.pumpWidget(
      mount(
        UnifiedMediaImage(
          group: tvGoldenGroup('other-profile', [first]),
          pathOf: (item) => item.posterThumb(),
          clientFor: (id) => clients[id],
        ),
      ),
    );
    expect(find.text('/one'), findsOneWidget);
  });

  testWidgets('another ungrouped same-name title is never used', (tester) async {
    final bare = tvGoldenMovie(id: 'one', title: 'Dune');
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedMediaImage(group: tvGoldenGroup('unmatched', [bare]), pathOf: (item) => item.posterThumb()),
      ),
    );
    expect(find.text('NONE'), findsOneWidget);
  });
  testWidgets('disconnected relative-path source falls through to connected source', (tester) async {
    final first = tvGoldenMovie(id: 'one', title: 'Dune', serverId: 'one').copyWith(thumbPath: '/one');
    final second = tvGoldenMovie(id: 'two', title: 'Dune', serverId: 'two').copyWith(thumbPath: '/two');
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedMediaImage(
          group: tvGoldenGroup('g', [first, second]),
          pathOf: (item) => item.posterThumb(),
          clientFor: (id) => id == 'two' ? _Client(id) : null,
        ),
      ),
    );
    expect(find.text('/two'), findsOneWidget);
  });

  testWidgets('unavailable signed URL falls through without a network retry', (tester) async {
    final first = tvGoldenMovie(id: 'one', title: 'Dune', serverId: 'one').copyWith(thumbPath: '/one');
    final second = tvGoldenMovie(id: 'two', title: 'Dune', serverId: 'two').copyWith(thumbPath: '/two');
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedMediaImage(
          group: tvGoldenGroup('g', [first, second]),
          pathOf: (item) => item.posterThumb(),
          clientFor: (id) => _Client(id, empty: id == 'one'),
        ),
      ),
    );
    expect(find.text('/two'), findsOneWidget);
  });
}
