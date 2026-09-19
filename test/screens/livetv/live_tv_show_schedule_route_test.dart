/// LIVE1, tweede helft: het showschema hoort binnen de shell te openen.
///
/// Op TV resolvet `Navigator.of(context)` naar de ene navigator die
/// `ProfileSessionScreen` bezit, en die tekent over het hele venster. Vanuit
/// Nu op TV een showschema openen haalde daarmee de topnav weg, wat dezelfde
/// fout is als SYS-1b en SYS-1d en wat PB-1 voor elk goedgekeurd oppervlak
/// verbiedt.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/tv/tv_content_route_registry.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/screens/livetv/tabs/whats_on_tab.dart';

void main() {
  test('the schedule route id is the show on its server, so a re-push dedups', () {
    expect(liveTvScheduleRouteId(serverId: 'nas', showTitle: 'Andere Tijden'), 'tvLiveTvSchedule_nas_Andere Tijden');
    // Dezelfde show op een andere server is een andere pagina.
    expect(
      liveTvScheduleRouteId(serverId: 'other', showTitle: 'Andere Tijden'),
      isNot(liveTvScheduleRouteId(serverId: 'nas', showTitle: 'Andere Tijden')),
    );
  });

  testWidgets('with a TV shell listening, the schedule opens inside it', (tester) async {
    final opened = <TvNestedRoute>[];
    Future<Object?> push(TvNestedRoute route) async {
      opened.add(route);
      return null;
    }

    tvContentRouteRegistry.attach(push);
    addTearDown(() => tvContentRouteRegistry.detach(push));

    final pushed = openTvContentRoute(
      id: liveTvScheduleRouteId(serverId: 'nas', showTitle: 'Andere Tijden'),
      builder: (_) => const SizedBox.shrink(),
    );

    expect(pushed, isNotNull, reason: 'een luisterende shell geeft een future terug, geen null');
    expect(opened, hasLength(1));
    expect(opened.single.id, 'tvLiveTvSchedule_nas_Andere Tijden');
  });

  testWidgets('with no shell listening, the caller gets null and pushes as before', (tester) async {
    expect(
      openTvContentRoute(id: 'tvLiveTvSchedule_nas_x', builder: (_) => const SizedBox.shrink()),
      isNull,
      reason: 'de null is het signaal om te pushen zoals altijd; desktop en mobiel raken dit niet',
    );
  });
}
