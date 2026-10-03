import 'package:flutter/widgets.dart';

import '../../../assistant/assistant_controller.dart';
import '../../../assistant/big_p_voice.dart';

/// Big P's mouth follows the clip he is saying, never the text on screen: a
/// silent Big P (voice off, or no player on this platform) keeps it shut.
class BigPVoiceMouth extends StatelessWidget {
  const BigPVoiceMouth({super.key, required this.controller, required this.builder});

  final AssistantController? controller;
  final Widget Function(String? line) builder;

  @override
  Widget build(BuildContext context) {
    final voice = controller == null ? null : BigPVoice.of(controller!);
    if (voice == null) return builder(null);
    return ValueListenableBuilder<String?>(valueListenable: voice.speaking, builder: (_, line, _) => builder(line));
  }
}
