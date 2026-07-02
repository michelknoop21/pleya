import 'package:flutter/material.dart';
import '../theme/mono_tokens.dart';

/// Reusable media progress bar widget for displaying watch progress
///
/// Shows a linear progress indicator based on viewOffset and duration.
/// Defaults to the brand accent (Netflix-red) for the played portion.
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
    final progress = duration > 0 ? viewOffset / duration : 0.0;

    return LinearProgressIndicator(
      value: progress.clamp(0.0, 1.0),
      backgroundColor: backgroundColor ?? Colors.white.withValues(alpha: 0.2),
      valueColor: AlwaysStoppedAnimation<Color>(valueColor ?? tokens(context).accent),
      minHeight: minHeight ?? 4,
    );
  }
}
