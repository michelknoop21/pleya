import 'package:flutter/material.dart';
import '../theme/mono_theme.dart' show kAccent;
import '../theme/mono_tokens.dart';

/// Reusable media progress bar widget for displaying watch progress
///
/// Shows a linear progress indicator based on viewOffset and duration.
/// Defaults to solid accent red for the played portion, animating smoothly
/// when the value changes (e.g. after resuming playback).
class MediaProgressBar extends StatelessWidget {
  final int viewOffset; // Progress position in milliseconds
  final int duration; // Total duration in milliseconds
  final Color? backgroundColor;
  final Color? valueColor;
  final double? minHeight;

  const MediaProgressBar({
    super.key,
    required this.viewOffset,
    required this.duration,
    this.backgroundColor,
    this.valueColor,
    this.minHeight,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (duration > 0 ? viewOffset / duration : 0.0).clamp(0.0, 1.0);
    final t = tokens(context);
    final height = minHeight ?? 4;

    // Played portion is solid accent red (or a caller-supplied color);
    // animates smoothly when the value changes.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: progress),
      duration: t.normal,
      curve: Curves.easeOut,
      builder: (context, value, _) => ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: backgroundColor ?? Colors.white.withValues(alpha: 0.2))),
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: value,
                heightFactor: 1,
                child: DecoratedBox(decoration: BoxDecoration(color: valueColor ?? kAccent)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
