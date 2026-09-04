import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../books/book.dart';
import '../../books/book_reader_layout.dart';
import '../../books/book_reader_page.dart';
import '../../books/book_reader_theme.dart';
import '../../books/book_toc.dart';
import '../../books/reader_settings.dart';
import '../../theme/mono_theme.dart' show kAccent;
import 'books_toc_screen.dart';
import 'widgets/book_reader_chrome.dart';
import 'widgets/reader_settings_sheet.dart';

/// De reader, built against approved golden 07 revisie B
/// (`docs/assets/ebooks/northstar/07a-books-reader.png`).
///
/// The reading surface: a page of the publication, a running head above it, and
/// the chrome that comes over it and goes away again. The golden's three frames
/// are one screen. `07a` is the canonical state with the chrome shown, `07b` is
/// the same page with it hidden, `07c` is the shape specification of the three
/// reading themes.
///
/// **Nothing here reflows when the chrome moves.** Every band is anchored on its
/// own: the running head on the chrome's top edge, the column 126 below it, the
/// footer on the bottom inset. Showing or hiding the chrome adds and removes two
/// layers of a [Stack] and touches no constraint of the column. That is the one
/// behaviour `07b` exists to prove, and a widget test measures the column's rect
/// in both states rather than trusting the tree.
///
/// **What the reader can and cannot do here**, and the line runs where the
/// golden's approval runs:
///
/// - the back arrow leaves the book, the inhoudsopgave glyph pushes golden 06 as
///   a page, and `Aa` opens the reading settings of golden 08, the fifth slot
///   approved with that golden;
/// - the search glyph is drawn and inert. It opens `Zoeken in boek`, panel 9,
///   which has no golden;
/// - the bookmark is drawn hollow and inert. Hollow means the current locator
///   carries no bookmark, and that is all it means;
/// - the scrubber is drawn and inert;
/// - a tap on the page shows and hides the chrome. That is the convention golden
///   07 names, and the reader does nothing else with a tap: what a tap near the
///   edge does, and paging in general, is panel 8 and is deliberately absent.
///
/// **There is no pagination.** The page comes from the fixture as a page, and
/// the column draws the paragraphs of it that fit the type the reader has set:
/// at 24 points two of golden 07's four, which is what approved golden 08b
/// shows. Producing the page after this one, and holding the reader's place
/// across a resetting, is the reader engine and belongs to PS-15.
class BookReaderScreen extends StatefulWidget {
  const BookReaderScreen({super.key, required this.book, required this.page, this.toc});

  final Book book;

  /// The page to draw, passed in rather than fetched: this screen renders a
  /// page, it does not own one.
  final BookReaderPage page;

  /// The publication's navigation, for the inhoudsopgave glyph.
  ///
  /// `null` for a publication that declares none, and then the glyph is drawn
  /// and opens nothing — the same treatment `Ga naar pagina` got in golden 06.
  /// It is drawn either way because the golden draws it.
  final BookToc? toc;

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> {
  /// The chrome is up when you arrive. `07a` is the canonical state and it is
  /// the one that tells you where you are and how to get out.
  bool _chromeVisible = true;

  /// How the page is set, in one place the page and the sheet both read.
  ///
  /// A notifier rather than two copies of the same state: the sheet lives on its
  /// own route and the page keeps drawing underneath it, so a setting has to
  /// reach both the moment it changes. That is the whole reason the sheet leaves
  /// the page visible.
  final ValueNotifier<ReaderSettings> _settings = ValueNotifier(ReaderSettings.canonical);

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  /// Golden 08's sheet: no scrim, and the page it is about stays visible above
  /// it. `barrierColor` is transparent rather than absent, so a tap on the page
  /// still closes the sheet instead of falling through to the chrome toggle.
  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ReaderSettingsSheet(settings: _settings, onChanged: (value) => _settings.value = value),
    );
  }

  void _openToc() {
    final toc = widget.toc;
    if (toc == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BooksTocScreen(book: widget.book, toc: toc),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final frame = MediaQuery.sizeOf(context);
    final chromeTop = BookReaderLayout.chromeTopFor(viewPadding);
    final footTop = BookReaderLayout.footTopFor(frame, viewPadding);

    return AutomationScreen(
      id: AutomationIds.screenBookReader,
      readiness: () => const AutomationReadiness.ready(),
      child: ValueListenableBuilder<ReaderSettings>(
        valueListenable: _settings,
        builder: (context, settings, _) => _page(context, settings, frame, chromeTop, footTop),
      ),
    );
  }

  Widget _page(BuildContext context, ReaderSettings settings, Size frame, double chromeTop, double footTop) {
    final theme = settings.theme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: theme.wantsLightStatusBar ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: theme.page,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleChrome,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: chromeTop + BookReaderLayout.runningHeadTop,
                left: BookReaderLayout.chromeMargin,
                right: BookReaderLayout.chromeMargin,
                height: BookReaderLayout.runningHeadHeight,
                child: BookReaderRunningHead(text: widget.page.runningHead, theme: theme),
              ),
              Positioned(
                top: chromeTop + BookReaderLayout.columnTop,
                left: settings.margin,
                right: settings.margin,
                // The column ends where the footer's band begins. It is a box
                // the page has to fit in, not a window onto a longer text:
                // scrolling a page is panel 8 and pagination is PS-15.
                bottom: frame.height - footTop,
                child: AutomationNode(
                  id: AutomationIds.bookReaderColumn,
                  role: 'surface',
                  child: ClipRect(
                    // Vertically at the band's own edge, horizontally seven
                    // points wider on both sides. A highlight overshoots the
                    // measure the way a marker overshoots the words it covers,
                    // and a clip on the measure would shave that off.
                    clipper: const _MarginBleedClipper(BookReaderLayout.markBleed),
                    child: BookReaderColumn(paragraphs: widget.page.paragraphs, theme: theme, settings: settings),
                  ),
                ),
              ),
              if (_chromeVisible)
                Positioned(
                  top: chromeTop,
                  left: 0,
                  right: 0,
                  height: BookReaderLayout.chromeHeight,
                  child: AutomationNode(
                    id: AutomationIds.bookReaderChrome,
                    role: 'nav',
                    child: _Chrome(
                      theme: theme,
                      onBack: () => Navigator.of(context).maybePop(),
                      onToc: widget.toc == null ? null : _openToc,
                      onSettings: _openSettings,
                    ),
                  ),
                ),
              if (_chromeVisible)
                Positioned(
                  top: footTop,
                  left: 0,
                  right: 0,
                  height: BookReaderLayout.footHeight,
                  child: AutomationNode(
                    id: AutomationIds.bookReaderFoot,
                    role: 'surface',
                    child: BookReaderFoot(position: widget.page.position, theme: theme, accent: kAccent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Clips the column at the footer's band and lets it breathe sideways.
///
/// The vertical clip is the one that matters: there is no pagination under this
/// screen, so a page that did not fit would otherwise be drawn straight through
/// the footer. The horizontal slack is for the highlight's overshoot and for
/// nothing else, which is why it is exactly the bleed and not a round number.
class _MarginBleedClipper extends CustomClipper<Rect> {
  const _MarginBleedClipper(this.bleed);

  final double bleed;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-bleed, 0, size.width + bleed, size.height);

  @override
  bool shouldReclip(_MarginBleedClipper old) => old.bleed != bleed;
}

/// Four glyphs on the page itself, without the scrim `20-speler.png` puts under
/// its controls: that scrim lifts white glyphs off a moving photograph, and a
/// page of text is neither moving nor a photograph.
class _Chrome extends StatelessWidget {
  const _Chrome({required this.theme, required this.onBack, required this.onToc, required this.onSettings});

  final BookReaderTheme theme;
  final VoidCallback onBack;
  final VoidCallback? onToc;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BookReaderLayout.chromeMargin),
      child: Row(
        children: [
          _Slot(
            glyph: BookReaderGlyph.back,
            theme: theme,
            onTap: onBack,
            semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          const SizedBox(width: BookReaderLayout.glyphGap),
          AutomationNode(
            id: AutomationIds.bookReaderToc,
            role: 'button',
            child: _Slot(glyph: BookReaderGlyph.toc, theme: theme, onTap: onToc),
          ),
          const Spacer(),
          AutomationNode(
            id: AutomationIds.bookReaderTypeSettings,
            role: 'button',
            child: _Slot(glyph: BookReaderGlyph.settings, theme: theme, onTap: onSettings),
          ),
          const SizedBox(width: BookReaderLayout.glyphGap),
          _Slot(glyph: BookReaderGlyph.search, theme: theme),
          const SizedBox(width: BookReaderLayout.glyphGap),
          _Slot(glyph: BookReaderGlyph.bookmark, theme: theme),
        ],
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.glyph, required this.theme, this.onTap, this.semanticLabel});

  final BookReaderGlyph glyph;
  final BookReaderTheme theme;

  /// `null` for a glyph that is drawn and opens nothing, which is three of the
  /// four. A tap on one of those falls through to the page and toggles the
  /// chrome rather than doing nothing at all, which is the honest behaviour for
  /// a control with no function yet.
  final VoidCallback? onTap;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final icon = BookReaderGlyphIcon(glyph: glyph, colour: theme.ink);
    final child = SizedBox.square(
      dimension: BookReaderLayout.glyphSlot,
      child: Center(
        child: semanticLabel == null ? icon : Semantics(button: true, label: semanticLabel, child: icon),
      ),
    );
    if (onTap == null) return child;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child);
  }
}
