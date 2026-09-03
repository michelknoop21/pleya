import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../widgets/desktop_app_bar.dart' show CustomAppBar;

/// Holds the Boeken destination while its screens are still being designed.
///
/// The navigation skeleton for [DEC-069] lands before the e-book screens do,
/// and a destination that builds nothing would crash the `IndexedStack` it
/// lives in. This is deliberately not a first draft of Boeken-home: that screen
/// is schermgolden 01 and may not be built before it is approved.
///
/// It is unreachable in a normal build. The Boeken destination needs
/// `BooksAvailability.available`, which today only a build with
/// `--dart-define=PLEYA_BOOKS=true` produces.
class BooksPlaceholderScreen extends StatelessWidget {
  const BooksPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          CustomAppBar(title: Text(t.navigation.books), automaticallyImplyLeading: false),
          const SliverFillRemaining(hasScrollBody: false, child: SizedBox.shrink()),
        ],
      ),
    );
  }
}
