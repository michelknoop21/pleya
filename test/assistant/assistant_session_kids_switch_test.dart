import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller_session.dart';
import 'package:pleya/assistant/assistant_kids_profile_store.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:provider/provider.dart';

/// The children's switch in Instellingen reaches the waiting memory cards of
/// the conversation and of the memory screen only through the listeners the
/// session factories register.
void main() {
  // ignore: invalid_use_of_protected_member
  bool watched() => KidsProfileStore.changes.hasListeners;

  testWidgets('both session factories listen to the children\'s switch until they are disposed', (tester) async {
    final manager = MultiServerManager();
    addTearDown(manager.dispose);
    final servers = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(servers.dispose);
    late BuildContext session;
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: servers,
        child: Builder(
          builder: (context) {
            session = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(watched(), isFalse);

    final controller = assistantControllerForSession(session);
    expect(watched(), isTrue, reason: 'the conversation looks again when the switch flips');
    controller.dispose();
    expect(watched(), isFalse);

    final host = assistantMemoryHostForSession(session);
    expect(watched(), isTrue, reason: 'the memory screen looks again when the switch flips');
    host.dispose();
    expect(watched(), isFalse);
  });
}
