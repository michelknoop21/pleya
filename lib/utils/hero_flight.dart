import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Shared [HeroFlightShuttleBuilder] for poster → detail-backdrop flights.
///
/// The default shuttle just shows the destination child, which snaps the
/// corner radius from the poster's rounded rect to the backdrop's square
/// corners in a single frame. This builder clips the in-flight child with a
/// radius interpolated between [posterRadius] (card end) and [targetRadius]
/// (detail end) so the corners round off smoothly during the flight.
///
/// Attach it on the *card*-side [Hero]: Flutter prefers the destination
/// hero's shuttle and falls back to the source's, so a card-side builder
/// covers both push (card → detail) and pop (detail → card).
HeroFlightShuttleBuilder posterHeroFlightShuttle({required double posterRadius, double targetRadius = 0}) {
  return (
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    // The flight animation always runs 0 → 1 from the flight's source hero to
    // its destination hero (pops fly with a reversed route animation).
    final begin = direction == HeroFlightDirection.push ? posterRadius : targetRadius;
    final end = direction == HeroFlightDirection.push ? targetRadius : posterRadius;
    final heroChild = (toHeroContext.widget as Hero).child;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) =>
          ClipRRect(borderRadius: BorderRadius.circular(lerpDouble(begin, end, animation.value)!), child: child),
      child: heroChild,
    );
  };
}
