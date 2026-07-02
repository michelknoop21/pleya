import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../navigation/navigation_tabs.dart';
import '../theme/mono_tokens.dart';
import 'app_icon.dart';

/// Netflix desktop/web top bar: wordmark left, text tabs, search + profile
/// right. Transparent over the billboard, then a blurred #141414 tint once the
/// page scrolls ([solid]). Used only on desktop non-TV; TV keeps the side rail.
class NetflixTopNav extends StatelessWidget {
  final List<NavigationTab> tabs;
  final NavigationTabId currentTab;
  final ValueChanged<NavigationTabId> onSelectTab;
  final VoidCallback onSearch;
  final VoidCallback onProfile;

  /// True once content has scrolled — switches to the solid blurred bar.
  final bool solid;

  const NetflixTopNav({
    super.key,
    required this.tabs,
    required this.currentTab,
    required this.onSelectTab,
    required this.onSearch,
    required this.onProfile,
    required this.solid,
  });

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final bar = AnimatedContainer(
      duration: tk.normal,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        gradient: solid ? null : const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Color(0x00000000)],
        ),
        color: solid ? const Color(0xF0141414) : null,
        border: solid ? Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))) : null,
      ),
      child: Row(
        children: [
          _Wordmark(),
          const SizedBox(width: 32),
          for (final tab in tabs) ...[
            _NavTab(
              label: tab.getLabel(),
              active: tab.id == currentTab,
              onTap: () => onSelectTab(tab.id),
            ),
            const SizedBox(width: 20),
          ],
          const Spacer(),
          IconButton(
            onPressed: onSearch,
            icon: const AppIcon(Symbols.search_rounded, fill: 1),
            color: Colors.white,
            tooltip: t.common.search,
          ),
          const SizedBox(width: 8),
          _ProfileAvatar(onTap: onProfile),
        ],
      ),
    );

    // Blur only matters when solid; keep it cheap otherwise.
    if (!solid) return bar;
    return ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: bar));
  }
}

class _Wordmark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontFamily: 'ArchivoBlack',
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.6,
        ),
        children: const [
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

class _ProfileAvatar extends StatelessWidget {
  final VoidCallback onTap;
  const _ProfileAvatar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE50914), Color(0xFF7A0C1E)],
          ),
        ),
        alignment: Alignment.center,
        child: const AppIcon(Symbols.person_rounded, fill: 1, size: 18, color: Colors.white),
      ),
    );
  }
}
