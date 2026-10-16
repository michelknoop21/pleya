import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_capabilities.dart';
import 'package:pleya/assistant/assistant_intent.dart';
import 'package:pleya/assistant/assistant_memory_intent.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_spoiler_context.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_examples.dart';

import 'assistant_find_fakes.dart';
import 'assistant_memory_support.dart';

// Every start question, in both languages, against what Pleya itself decides
// from the words: the intent, the fences (spoiler, library diagnosis, memory)
// and the refusals on a tool call. What no test here can show is which tool a
// real model picks; docs/qa/big-p-startvragen.md holds that round.

/// Every real tool by name and risk, answering `ok` and counting its runs: the
/// routing of a run is real, the servers behind it are not needed.
List<AssistantTool> _stubs(Map<String, int> ran) => [
  for (final tool in [...assistantTools, assistantSpoilerTool])
    AssistantTool(
      name: tool.name,
      description: tool.name,
      risk: tool.risk,
      needsServer: false,
      properties: const {},
      serves: (_, _) => true,
      run: (_, _, _) async {
        ran.update(tool.name, (n) => n + 1, ifAbsent: () => 1);
        return const AssistantToolResult({'ok': true});
      },
    ),
];

class _OnlineServer extends FakeServer {
  _OnlineServer(super.id);
  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.online;
}

void main() {
  late MultiServerManager servers;
  setUp(() {
    servers = MultiServerManager();
    addTearDown(servers.dispose);
    // A library diagnosis with no reachable server ends before the model is asked.
    servers.debugRegisterClientForTesting(_OnlineServer('s'));
    servers.setVisibleServerIds(null);
  });

  /// Asks [question] with a model that calls [tool] at once.
  Future<({ScriptedModel model, Map<String, int> ran})> ask(String question, String tool, {bool kids = false}) async {
    final ran = <String, int>{};
    final model = ScriptedModel([callTool(tool), say('ok')]);
    await AssistantRun(
      model: model,
      context: AssistantToolContext(servers: servers, kidsProfile: () async => kids, kidsAges: () async => [6]),
      confirm: (_) async => fail('a start question shows no card before its tool ran'),
      entitlement: const Entitled(),
      tools: _stubs(ran),
    ).ask(question);
    return (model: model, ran: ran);
  }

  for (final locale in [AppLocale.en, AppLocale.nl]) {
    group(locale.name, () {
      setUp(() async {
        addTearDown(() => LocaleSettings.setLocale(AppLocale.en));
        await LocaleSettings.setLocale(locale);
      });

      for (final c in AssistantCapability.values) {
        test('${c.name}: what Pleya fixes from the words', () {
          for (final q in assistantExamples(c)) {
            final intent = AssistantIntent.fromPrompt(q);
            // The two routes Pleya forces, and only where they belong.
            expect(intent.addedToLibraries, c == AssistantCapability.recentlyAdded, reason: q);
            expect(intent.unseenInLibrary, c == AssistantCapability.unwatched, reason: q);
            expect(
              intent.tonightPick,
              c == AssistantCapability.tonight || c == AssistantCapability.startSeries,
              reason: q,
            );
            expect(intent.group != null, c == AssistantCapability.together, reason: q);
            expect(assistantNeedsLibraryDoctorScope(q), c == AssistantCapability.doctor, reason: q);
            // No fence that swaps the tool list, no write to the memory.
            expect(assistantNeedsSpoilerScope(q), isFalse, reason: q);
            expect(assistantMemoryTypedFact(q), isNull, reason: q);
            expect(assistantMemoryTypedFact(q, polite: true), isNull, reason: q);
            expect(assistantOpensAsMemoryWrite(q), isFalse, reason: q);
            // A chip is answered, not asked back about or cut in two.
            expect(AssistantIntent.audienceChoiceNeeded(q), isFalse, reason: q);
            expect(AssistantIntent.splitMixedAudience(q), isNull, reason: q);
            expect(intent.mixedAudience, isFalse, reason: q);
            // Nothing the tools cannot give.
            expect(intent.previousWeek, isFalse, reason: q);
            expect(intent.longPeriodAsked, isFalse, reason: q);
            // Whose viewing: the household's only where the question is about it.
            final audience = intent.audience.value;
            if (c == AssistantCapability.watchStats) {
              expect(audience, isNot(AssistantAudience.me), reason: q);
            } else {
              expect(audience, anyOf(isNull, AssistantAudience.me), reason: q);
            }
            for (final tool in c.tools) {
              expect(intent.constrain(tool, {'scope': 'period'}).error, isNull, reason: '$tool for: $q');
            }
          }
        });

        test('${c.name}: its tools are offered and not refused', () async {
          for (final q in assistantExamples(c)) {
            for (final tool in c.tools) {
              final (:model, :ran) = await ask(q, tool);
              expect(model.offeredTo(0), contains(tool), reason: '$tool offered for: $q');
              expect(ran[tool], 1, reason: '$tool ran for: $q');
              expect(model.toolOutputs, [
                {'ok': true},
              ], reason: q);
            }
          }
        });
      }

      test('a children\'s profile: every watch question still reaches a gated tool', () async {
        for (final c in AssistantCapability.values) {
          if (c.group != AssistantCapabilityGroup.watch) continue;
          final gated = [
            for (final tool in c.tools)
              if (kidsToolPolicy[tool] == KidsTool.gated) tool,
          ];
          expect(gated, isNotEmpty, reason: c.name);
          for (final q in assistantExamples(c)) {
            final (:model, :ran) = await ask(q, gated.first, kids: true);
            expect(ran[gated.first], 1, reason: q);
            expect(model.toolOutputs.single, isNot(containsPair('error', 'kids_mode_unsupported')), reason: q);
          }
        }
      });
    });
  }

  group('negative controls: phrasings the catalogue replaced', () {
    test('"not seen yet" without the library has no route', () {
      for (final q in ["Which movies haven't I seen yet?", 'Welke films heb ik nog niet gezien?']) {
        expect(AssistantIntent.fromPrompt(q).unseenInLibrary, isFalse, reason: q);
      }
      // Its tool is then the model's own guess: my_watching is not refused.
      expect(AssistantIntent.fromPrompt("Which movies haven't I seen yet?").constrain('my_watching', {}).error, isNull);
      expect(
        AssistantIntent.fromPrompt('Which films in my library have I not seen yet?').constrain('my_watching', {}).error,
        'use_search_catalog',
      );
    });

    test('"tonight" in my library asks the libraries: history tips and the popular list are refused', () {
      for (final q in [
        'What in my library can I watch tonight?',
        'Wat uit mijn bibliotheek kan ik vanavond kijken?',
        'Find an exciting movie in my library for tonight.',
        'Zoek een spannende film in mijn bibliotheek voor vanavond.',
      ]) {
        final intent = AssistantIntent.fromPrompt(q);
        expect(intent.tonightPick, isTrue, reason: q);
        expect(intent.constrain('my_watching', {}).error, 'use_search_catalog', reason: q);
        expect(intent.constrain('trending_titles', {}).error, 'use_search_catalog', reason: q);
        expect(intent.constrain('search_catalog', {}).error, isNull, reason: q);
        expect(intent.describe(), contains('search_catalog'), reason: q);
      }
    });

    test('the follow-up chips for tonight reach the libraries too', () {
      for (final locale in [AppLocale.en, AppLocale.nl]) {
        LocaleSettings.setLocaleSync(locale);
        final routed = t.assistant.followUp.tonight.where((q) => AssistantIntent.fromPrompt(q).tonightPick);
        // Three of the four; "something for the kids" has no tonight.
        expect(routed, hasLength(3), reason: locale.name);
      }
      LocaleSettings.setLocaleSync(AppLocale.en);
    });

    test('each exclusion keeps tonight with the tool the user asked for', () {
      for (final q in [
        'What is trending in my library tonight?',
        'Wat is populair in mijn bibliotheek vanavond?',
        'What in my library can Sam and I watch tonight?',
        'Wat uit mijn bibliotheek kunnen we samen vanavond kijken?',
        'What in my library has Sam to watch tonight?',
        'What in my library is everyone watching tonight?',
      ]) {
        expect(AssistantIntent.fromPrompt(q).tonightPick, isFalse, reason: q);
      }
    });

    test('a child task keeps the flag, a children\'s profile is refused the same two tools', () {
      final intent = AssistantIntent.fromPrompt('What in my library can I watch tonight?');
      expect(intent.inheriting(AssistantIntent.unknown).tonightPick, isTrue);
      expect(AssistantIntent.unknown.inheriting(intent).tonightPick, isFalse, reason: 'decided by its own words');
      expect(kidsToolPolicy['my_watching'], KidsTool.blocked);
      expect(kidsToolPolicy['trending_titles'], KidsTool.gated);
      expect(intent.constrain('trending_titles', {}).error, 'use_search_catalog');
    });

    test('negative control: without "tonight" and the library the same tools are not refused', () {
      for (final q in [
        'Give me a tip based on what I watched.',
        'Give me a tip from my library for tonight.',
        'Zoek een film voor vanavond',
        'What can I watch tonight?',
        'Which titles on my Trakt watchlist can I watch here tonight?',
        'What can I watch with my family tonight?',
        'What did I watch yesterday evening?',
      ]) {
        final intent = AssistantIntent.fromPrompt(q);
        expect(intent.tonightPick, isFalse, reason: q);
        expect(intent.constrain('my_watching', {}).error, isNull, reason: q);
        expect(intent.constrain('trending_titles', {}).error, isNull, reason: q);
      }
    });

    test('"what is everyone watching" reads as household viewing, not as what is popular', () {
      for (final q in ['What is everyone watching right now?', 'Wat kijkt iedereen nu?']) {
        expect(AssistantIntent.fromPrompt(q).audience.value, AssistantAudience.everyone, reason: q);
      }
    });

    test('"the whole family" without "with" names no group', () {
      expect(AssistantIntent.fromPrompt('What can the whole family watch together?').group, isNull);
    });

    test('a kids profile is refused a blocked tool, whatever the chip', () async {
      final (:model, :ran) = await ask('Who watched the most this week?', 'watch_stats', kids: true);
      expect(ran, isEmpty);
      expect(model.toolOutputs.single['error'], 'kids_mode_unsupported');
    });
  });
}
