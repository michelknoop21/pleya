import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/continue_watching_removal.dart';

/// Mockup 38 E (DEC-144 fase 3): one row, and its wording follows what each
/// source can do. "On all sources" only when that is literally true.
void main() {
  ContinueWatchingRemovalSource source(String? name, {required bool server, bool reachable = true}) =>
      (serverName: name, removesOnServer: server, reachable: reachable);

  test('a source that cannot remove server-side is hidden on this device, and says so', () {
    final p = continueWatchingRemovalPresentation([source('Zolder', server: false)]);
    expect(p.label, 'Hide from Continue Watching');
    expect(p.scope, 'On this device only');
  });

  test('a single server-side source needs no scope', () {
    final p = continueWatchingRemovalPresentation([source('NAS', server: true)]);
    expect(p.label, 'Remove from Continue Watching');
    expect(p.scope, isNull);
  });

  test('several server-side sources, all reachable: on all sources', () {
    final p = continueWatchingRemovalPresentation([source('NAS', server: true), source('Attic', server: true)]);
    expect(p.scope, 'On all sources');
  });

  test('the claim is not made while one of them is unreachable', () {
    final p = continueWatchingRemovalPresentation([
      source('NAS', server: true),
      source('Attic', server: true, reachable: false),
    ]);
    expect(p.label, 'Remove from Continue Watching');
    expect(p.scope, isNull, reason: 'a queued removal is not a guarantee');
  });

  test('a merged Plex and Jellyfin title names which source gets what', () {
    final p = continueWatchingRemovalPresentation([source('Zolder', server: true), source('NAS', server: false)]);
    expect(p.label, 'Remove from Continue Watching');
    expect(p.scope, 'Zolder on the server, NAS here only');
  });

  test('without server names the mixed case still says it is partly local', () {
    final p = continueWatchingRemovalPresentation([source(null, server: true), source('NAS', server: false)]);
    expect(p.scope, 'Partly on this device only');
  });
}
