import 'dart:async';

import 'package:flutter/material.dart';

import '../focus/focusable_button.dart';
import '../i18n/strings.g.dart';

/// Modal Stack child shown while a profile activation is rebinding servers.
///
/// The barrier is deliberately non-dismissible, but it is never a permanent
/// trap: after [escapeAfter] a focusable Cancel button appears, so a rebind
/// that hangs on a flaky connection can still be abandoned. That matters most
/// on tvOS, where system BACK cannot exit the app and this overlay was
/// previously fully inert.
class ProfileSwitchingOverlay extends StatefulWidget {
  const ProfileSwitchingOverlay({super.key, this.onCancel, this.escapeAfter = const Duration(seconds: 8)});

  final VoidCallback? onCancel;
  final Duration escapeAfter;

  @override
  State<ProfileSwitchingOverlay> createState() => _ProfileSwitchingOverlayState();
}

class _ProfileSwitchingOverlayState extends State<ProfileSwitchingOverlay> {
  Timer? _timer;
  bool _showCancel = false;

  @override
  void initState() {
    super.initState();
    if (widget.onCancel != null) {
      _timer = Timer(widget.escapeAfter, () {
        if (mounted) setState(() => _showCancel = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onCancel = widget.onCancel;
    // Netflix-style fade to (near) black with a centered spinner + label.
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        builder: (context, v, child) => Opacity(opacity: v, child: child),
        child: Stack(
          children: [
            const ModalBarrier(color: Color(0xF2000000), dismissible: false),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(color: Colors.white)),
                  const SizedBox(height: 20),
                  Text(
                    t.profiles.switchingProfile,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  if (_showCancel && onCancel != null) ...[
                    const SizedBox(height: 28),
                    FocusableButton(
                      autofocus: true,
                      onPressed: onCancel,
                      child: TextButton(
                        onPressed: onCancel,
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        child: Text(t.common.cancel),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
