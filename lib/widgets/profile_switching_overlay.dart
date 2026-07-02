import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';

/// Modal Stack child shown while a profile activation is rebinding servers.
class ProfileSwitchingOverlay extends StatelessWidget {
  const ProfileSwitchingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
