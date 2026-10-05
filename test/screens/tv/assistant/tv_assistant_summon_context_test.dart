import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_summon_context.dart';

void main() {
  test('one library\'s catalog route is that library', () {
    final ctx = tvAssistantSummonContext(
      active: TvDestinationId.myPleya,
      nestedRouteId: '${tvLibraryCatalogRoutePrefix}zolder:12',
    );
    expect(ctx?.serverId, 'zolder');
    expect(ctx?.libraryId, '12');
  });

  test('any other route or destination gives no context', () {
    expect(tvAssistantSummonContext(active: TvDestinationId.home), isNull);
    expect(tvAssistantSummonContext(active: TvDestinationId.movies, nestedRouteId: 'tvCollection_zolder:9'), isNull);
    expect(tvAssistantSummonContext(active: TvDestinationId.movies), isNull, reason: 'no catalogs in scope');
  });
}
