import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/services/image_cache_service.dart';
import 'package:pleya/services/multi_server_manager.dart';

void main() {
  test('every network image goes through the shared artwork cache', () {
    // The package default is a second cache with no download limit, no timeout
    // and no Pleya Server header. Seven call sites used it by leaving
    // `cacheManager` out, the Apple TV watchlist and Seerr cards among them.
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.endsWith('.g.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!RegExp(r'\bCachedNetworkImage\(').hasMatch(lines[i])) continue;
        final call = lines.skip(i).take(14).join('\n');
        if (!call.contains('cacheManager:')) offenders.add('${file.path}:${i + 1}');
      }
    }

    expect(offenders, isEmpty);
  });

  test('a server that comes back online asks failed artwork to load again', () {
    final manager = MultiServerManager();
    addTearDown(manager.dispose);
    var reloads = 0;
    void onReload() => reloads++;
    ArtworkReloadSignal.instance.addListener(onReload);
    addTearDown(() => ArtworkReloadSignal.instance.removeListener(onReload));

    manager.updateServerStatus(ServerId('srv'), false);
    expect(reloads, 0);
    manager.updateServerStatus(ServerId('srv'), true);
    expect(reloads, 1);
    manager.updateServerStatus(ServerId('srv'), true);
    expect(reloads, 1, reason: 'no change, no reload');
  });
}
