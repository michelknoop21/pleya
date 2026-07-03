import 'package:flutter/material.dart';

import '../navigation/top_nav_scope.dart';

/// Netflix desktop nav content: wordmark + text tabs. Rendered inside each
/// screen's existing top bar (via [TopNavScope]) so there is never a second
/// stacked bar. Reads the active tab + selection callback from [TopNavScope].
class NetflixNavLeading extends StatelessWidget {
  const NetflixNavLeading({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = TopNavScope.of(context);
    if (scope == null || !scope.active) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Wordmark(),
          const SizedBox(width: 28),
          for (final tab in scope.tabs) ...[
            _NavTab(
              label: tab.getLabel(),
              active: tab.id == scope.currentTab,
              onTap: () => scope.onSelectTab(tab.id),
            ),
            const SizedBox(width: 18),
          ],
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return const Text.rich(
      TextSpan(
        style: TextStyle(fontFamily: 'ArchivoBlack', fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.6),
        children: [
          TextSpan(text: 'PLEXFLIX', style: TextStyle(color: Color(0xFFE50914))),
          TextSpan(text: 'NETWORK', style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavTab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFFE5E5E5),
            fontSize: 13.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
