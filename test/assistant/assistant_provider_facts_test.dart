import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_title_facts.dart';
import 'package:pleya/assistant/assistant_title_facts_cache.dart';
import 'package:pleya/utils/log_redaction_manager.dart';

import '../test_helpers/prefs.dart';

const _cloud = AssistantProviderConfig(
  kind: AssistantProviderKind.ollamaCloud,
  baseUrl: AssistantProviderConfig.ollamaCloudUrl,
  apiKey: 'k',
  model: 'm',
);

void main() {
  test('tmdbKey and the online switch survive toJson, fromJson and copyWith', () {
    expect(_cloud.onlineFacts, isTrue, reason: 'on until the user turns it off');
    expect(_cloud.toJson().containsKey('onlineFacts'), isFalse);

    final set = _cloud.copyWith(tmdbKey: 'tmdb-token', onlineFacts: false);
    final back = AssistantProviderConfig.fromJson(jsonDecode(jsonEncode(set.toJson())) as Map<String, Object?>)!;
    expect(back.tmdbKey, 'tmdb-token');
    expect(back.onlineFactsChoice, isFalse);
    expect(back.onlineFacts, isFalse);

    // Other edits keep them; an empty string clears the key.
    expect(set.copyWith(model: 'x').tmdbKey, 'tmdb-token');
    expect(set.copyWith(model: 'x').onlineFacts, isFalse);
    expect(set.copyWith(tmdbKey: '').tmdbKey, isEmpty);
    expect(AssistantProviderConfig.fromJson(_cloud.toJson())!.onlineFacts, isTrue);
  });

  test('the store registers tmdbKey as a secret, so logs never carry it', () async {
    resetSharedPreferencesForTest();
    await AssistantProviderStore.instance.save(_cloud.copyWith(tmdbKey: 'tmdb-secret-123456'));
    expect(LogRedactionManager.redact('token tmdb-secret-123456 here'), isNot(contains('tmdb-secret-123456')));
    await AssistantProviderStore.instance.clear();
  });

  test('a settings change counts at the next lookup of the same service', () async {
    resetSharedPreferencesForTest();
    final store = AssistantProviderStore.instance;
    // The wiring of assistantControllerForSession.
    final service = TitleFactsService(
      cache: TitleFactsCache(),
      tmdbKey: () => AssistantProviderStore.current?.tmdbKey,
      online: () => AssistantProviderStore.current?.onlineFacts ?? true,
    );
    expect(service.tmdb(), isNull, reason: 'no config, no key');

    await store.save(_cloud.copyWith(tmdbKey: 'tok'));
    expect(service.tmdb(), isNotNull);
    await store.save(_cloud.copyWith(tmdbKey: 'tok', onlineFacts: false));
    expect(service.tmdb(), isNull, reason: 'online off');
    await store.save(_cloud.copyWith(tmdbKey: ''));
    expect(service.tmdb(), isNull, reason: 'key cleared');
    await store.clear();
  });
}
