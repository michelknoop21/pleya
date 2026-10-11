import 'package:flutter/widgets.dart';

import '../../../services/speech_search_service.dart';
import '../../../utils/dialogs.dart';

/// Text from the viewer on a TV, through the path Big P's own question takes:
/// the system keyboard with dictation on Apple TV, Pleya's text dialog where
/// that is not there. Null when the viewer backed out or sent nothing.
Future<String?> memoryTvCaptureText(
  BuildContext context,
  SpeechSearchService speech, {
  required String prompt,
  String initial = '',
  String action = 'send',
}) async {
  if (await speech.isSupported()) {
    final result = await speech.capture(prompt: prompt, action: action, initialText: initial);
    // Still supported: the viewer cancelled. Written off meanwhile (the
    // native editor did not come up): the dialog below takes over.
    if (result != null || await speech.isSupported()) return result != null && result.submitted ? result.text : null;
  }
  if (!context.mounted) return null;
  return showTextInputDialog(context, title: prompt, labelText: prompt, hintText: '', initialValue: initial);
}
