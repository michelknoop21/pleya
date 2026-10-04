# iPhone-detail restyle (D-01, D-02, D-03) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** De film- en seriedetailpagina op de iPhone krijgen de opbouw van de goedgekeurde mockups D-01, D-02, D-03 en D-03b: staande poster die overloopt in een waas uit de poster zelf, echte scores per backend, een activiteitskaart, een techniektabel waarin audio en ondertiteling alleen onthouden worden, Plex-recensies, en voor series een seizoensrij die een seizoenspagina opent.

**Architecture:** Alles blijft een presentatiewissel binnen `_MobileMediaDetailView` (`lib/screens/media_detail/mobile_detail_view.dart`, `part of media_detail_screen.dart`). Nieuwe blokken worden losse widgets onder `lib/screens/media_detail/mobile/` die hun data als parameters krijgen; acties hergebruiken de bestaande handlers op `_MediaDetailScreenState`. Twee nieuwe backend-neutrale velden op `MediaItem` (`externalRatings`, `reviews`) worden per backend in de mappers gevuld.

**Tech Stack:** Flutter (gepind in `.fvmrc`, 3.44.0), `provider`, Freezed/JSON-codegen via `scripts/codegen.sh`, `flutter_svg` voor `assets/rating_icons/*.svg`, Pleya Verify voor iOS-simulatorbewijs.

**Spec:** de vier goedgekeurde mockups (Michel, 28 september 2026: "akkoord"), in Task 0 vastgelegd als `docs/assets/ios-unified/detail-2026/D-01-film.png`, `D-02-audio-sheet.png`, `D-03-serie.png`, `D-03b-serie-scroll.png`, met de HTML-bron ernaast; besluit DEC-140 (Task 0) als amendement op DEC-090 en DEC-131.

## Global Constraints

- Alleen de iPhone-route (`PlatformDetector.isPhone(context)`, `media_detail_screen.dart:3712`). iPad en desktop houden op `main` hun eigen layout (DEC-103); TV verandert niet. Zodra DEC-121 (`feat/unified-desktop-ipad`) landt, erft de iPad deze pagina vanzelf.
- Elk blok verschijnt alleen als er data is. Geen lege kaart, geen "geen recensies"-tekst.
- Backendmatrix (bewezen in de verkenning van 28 september):
  - Scores: Plex `Rating[]` plus `ratingImage`/`audienceRatingImage`; Jellyfin `CriticRating` (RT-percentage) en `CommunityRating` (0 tot 10); Pleya Server geen.
  - Recensies: alleen Plex (`includeReviews=1`, element `Review`: `tag`, `text`, `image`, `link`, `source`).
  - Activiteit: alleen Plex, alleen `isOwnerOrAdmin`; "kijkt nu" en tellingen alleen met Tautulli.
- Accentregel uit de mockups: op de getinte ondergrond zijn gekozen waarden en het actieve icoon wit; rood (`#E5140F`) alleen voor voortgangsbalken, het "kijkt nu"-stipje en het label "Verder kijken".
- Scores zijn niet aantikbaar (Michel, 28 september).
- Een audio- of ondertitelkeuze op de detailpagina start nooit afspelen; hij wordt opgeslagen via `TrackPreferenceStore` en geldt bij de volgende start.
- Bestanden die je aanraakt en boven 500 regels uitkomen, splits je; `media_detail_screen.dart` (5581) krijgt er geen regels bij, nieuwe code gaat in `lib/screens/media_detail/mobile/`.
- Context7 vóór code met een framework-API (Flutter: `ShaderMask`, `ImageFiltered`, `SliverAppBar`/scroll-listeners); noteer de gebruikte library-ID in het taakverslag.
- Tekst in de UI via slang (`lib/i18n/*.i18n.json`, dan `scripts/codegen.sh`); Nederlands en Engels verplicht, overige talen vallen terug op Engels.
- Geen AI-vermelding in commits of docs; auteur Michel Knoop. Geen em-dashes in docs.
- Per owner-regel (25 september): geen review per taak; één whole-branch review vóór de build.

## Review Focus

1. **Poster ontbreekt of is liggend** (Jellyfin-item zonder Primary, Plex zonder `thumb`): de hero valt terug op `artPath` in 16:9 met de titel als tekst, en de waas gebruikt dezelfde afbeelding. Test in Task 2.
2. **Plex-item met alleen `ratingImage` en geen `Rating[]`** (oudere PMS of agent zonder externe scores): de bestaande RT-chips blijven werken via de fallback. Test in Task 1.
3. **Film met één audiospoor en geen ondertitels**: de tabel toont Audio zonder chevron en niet aantikbaar, Ondertiteling "Uit" met chevron (je kunt altijd kiezen voor uit/aan zodra er minstens één spoor is; zonder sporen geen rij). Test in Task 5.
4. **Serie zonder seizoenen of met alleen Specials**: geen lege seizoensrij; bij precies één seizoen toont de rij één poster. Test in Task 7.
5. **Offline (gedownload item)**: Beoordeel, recensies, activiteit en seizoenspagina's die serverdata vragen verdwijnen; afspelen en de techniektabel uit het lokale bestand blijven. Test in Task 3 en Task 5.

---

## Bestandsindeling

| Bestand | Verantwoordelijkheid |
| --- | --- |
| `lib/media/external_rating.dart` (nieuw) | `ExternalRating`-model en `ExternalRatingSource`-enum, pure mapping naar asset en weergave |
| `lib/media/media_review.dart` (nieuw) | `MediaReview`-model |
| `lib/media/media_item.dart` | twee velden erbij: `externalRatings`, `reviews` |
| `lib/services/plex_mappers.dart`, `lib/services/plex_client.dart` | `Rating[]`/`Review[]` parsen, `includeReviews=1` meevragen |
| `lib/services/jellyfin_mappers.dart`, `lib/services/jellyfin_client/parts/browse.dart` | `CriticRating`/`CommunityRating` naar `externalRatings` |
| `lib/screens/media_detail/mobile/detail_ambient_background.dart` (nieuw) | vervaagde poster achter de pagina, verloop naar `--bg` |
| `lib/screens/media_detail/mobile/mobile_poster_hero.dart` (nieuw) | staande poster, meta, scorerij |
| `lib/screens/media_detail/mobile/detail_score_row.dart` (nieuw) | scorerij uit `externalRatings` |
| `lib/screens/media_detail/mobile/detail_primary_actions.dart` (nieuw) | hoofdknop, "vanaf begin", iconenrij |
| `lib/screens/media_detail/mobile/detail_activity_card.dart` (nieuw) | kaart rond watchers/now watching/stats |
| `lib/screens/media_detail/mobile/detail_tech_table.dart` (nieuw) | Video/Audio/Ondertiteling |
| `lib/widgets/mobile/mobile_subtitle_track_picker_sheet.dart` (nieuw) | ondertitelpaneel, spiegel van het audiopaneel |
| `lib/screens/media_detail/mobile/detail_reviews_section.dart` (nieuw) | recensierij |
| `lib/screens/media_detail/mobile/detail_seasons_rail.dart` (nieuw) | seizoensposters |
| `lib/screens/media_detail/mobile_detail_view.dart` | compositie in de volgorde van de mockups |
| `lib/screens/media_detail/mobile_detail_hero.dart` | titel in de vastgezette balk bij scrollen (D-03b) |
| `lib/screens/media_detail/audio_selector.dart` | keuze onthouden, niet afspelen |
| `lib/utils/media_navigation_helper.dart` | seizoen openen als eigen detailpagina op de iPhone |

---

### Task 0: Besluit en mockups vastleggen

**Files:**
- Create: `docs/assets/ios-unified/detail-2026/` met `D-01-film.png`, `D-02-audio-sheet.png`, `D-03-serie.png`, `D-03b-serie-scroll.png` en de HTML-bronnen plus gebruikte assets uit de scratchpad `.../scratchpad/detail-mockup/`
- Modify: `docs/DECISIONS.md` (nieuwe entry DEC-140 na DEC-139)
- Modify: `docs/ios-unified-implementation-register.md` (rij voor DEC-140)

**Interfaces:** Produces: de paden hierboven; latere taken verwijzen naar `docs/assets/ios-unified/detail-2026/D-0x-*.png`.

- [ ] **Step 1:** kopieer de vier PNG's en HTML-bestanden (plus `*.jpg`, `*.otf`, `*.svg` die de HTML laadt) naar `docs/assets/ios-unified/detail-2026/`. Controleer dat `D-01-film.html` er lokaal nog identiek uit rendert: `pw screenshot --viewport-size=402,874 --full-page file://$PWD/docs/assets/ios-unified/detail-2026/D-01-film.html /tmp/d01.png` en vergelijk met de PNG (zelfde afmetingen).
- [ ] **Step 2:** schrijf DEC-140 in de vorm van DEC-131 (Date 2026-09-28, Status accepted, Context, Decision, Consequences). Inhoud van de Decision, letterlijk af te leiden uit dit plan: poster-hero met waas, scorerij met echte iconen per backend, hoofdknop plus "vanaf begin", actierij film (Kijklijst, Trailer, Beoordeel, Bekeken, Downloaden, Meer) en serie (zelfde zonder Downloaden; seizoen downloaden, Delen en Aanvragen onder Meer), bronregel, activiteitskaart (Plex, eigenaar of beheerder), techniektabel met onthouden keuze voor audio en ondertiteling, recensies (Plex), seizoensrij die een seizoenspagina opent, titelbalk bij scrollen. Consequences: vervangt de voorvertoningskaart en de Downloaden-capsule van northstar 06, de inline afleveringen en seizoenpil van DEC-131 op de seriepagina, Delen verhuist naar Meer. Citeer Michel: "akkoord" (28 september 2026) en "nee scores hoeven niet aantikbaar te zijn".
- [ ] **Step 3:** registerrij toevoegen in de stijl van de bestaande rijen, status `OPEN`.
- [ ] **Step 4:** commit.

```bash
git add docs/assets/ios-unified/detail-2026 docs/DECISIONS.md docs/ios-unified-implementation-register.md
SKIP_HOOKS=1 git commit -m "docs: DEC-140 iPhone-detail restyle, mockups D-01 tot en met D-03b"
```

---

### Task 1: Scores en recensies als backend-neutrale data

**Files:**
- Create: `lib/media/external_rating.dart`, `lib/media/media_review.dart`
- Modify: `lib/media/media_item.dart` (Freezed), `lib/services/plex_mappers.dart:570-723`, `lib/services/plex_client.dart:1003-1007` en `:1065`, `lib/services/jellyfin_mappers.dart:200`, `lib/services/jellyfin_client/parts/browse.dart:123-134`, `lib/utils/rating_utils.dart`
- Test: `test/media/external_rating_test.dart`, `test/services/plex_mappers_ratings_test.dart`, `test/services/jellyfin_mappers_ratings_test.dart`

**Interfaces:**
- Produces:
  - `enum ExternalRatingSource { imdb, rottenTomatoesCritic, rottenTomatoesAudience, tmdb, community }`
  - `class ExternalRating { final ExternalRatingSource source; final double value; final String? imageUri; String get assetPath; String get label; }` waarbij `value` in de schaal van de bron staat (IMDb en community 0 tot 10, RT en TMDB 0 tot 100) en `assetPath` voor RT de variant uit `imageUri` kiest (`ripe`/`rotten`/`upright`/`spilled`) en anders op de drempel 60 terugvalt.
  - `class MediaReview { final String author; final String text; final String? imageUri; final String? link; final String? source; }`
  - `MediaItem.externalRatings` (`List<ExternalRating>`, default `const []`) en `MediaItem.reviews` (`List<MediaReview>`, default `const []`).

- [ ] **Step 1: Live-controle Plex.** Vraag de controller om een Plex-antwoord van `/library/metadata/<film>?includeReviews=1` (JSON, `Accept: application/json`) van Michels server; als dat niet lukt, gebruik de veldnamen uit python-plexapi (Context7 `/websites/python-plexapi_readthedocs_io_en`: `Rating` = `image`, `type`, `value`; `Review` = `tag`, `text`, `image`, `link`, `source`) en noteer in het verslag dat de JSON-sleutels (`Rating`, `Review`) niet live bevestigd zijn. Sla het antwoord zonder token op als `test/fixtures/plex/metadata_with_ratings_reviews.json`.

- [ ] **Step 2: Failing tests schrijven.**

```dart
// test/media/external_rating_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/external_rating.dart';

void main() {
  test('RT critic picks the fresh icon from a ripe image uri', () {
    const r = ExternalRating(source: ExternalRatingSource.rottenTomatoesCritic, value: 92, imageUri: 'rottentomatoes://image.rating.ripe');
    expect(r.assetPath, 'assets/rating_icons/rt_fresh.svg');
    expect(r.label, '92%');
  });
  test('RT critic without image uri falls back on the 60 threshold', () {
    expect(const ExternalRating(source: ExternalRatingSource.rottenTomatoesCritic, value: 59).assetPath, 'assets/rating_icons/rt_rotten.svg');
    expect(const ExternalRating(source: ExternalRatingSource.rottenTomatoesCritic, value: 60).assetPath, 'assets/rating_icons/rt_fresh.svg');
  });
  test('RT audience maps to upright/spilled', () {
    expect(const ExternalRating(source: ExternalRatingSource.rottenTomatoesAudience, value: 88).assetPath, 'assets/rating_icons/rt_upright.svg');
    expect(const ExternalRating(source: ExternalRatingSource.rottenTomatoesAudience, value: 40).assetPath, 'assets/rating_icons/rt_spilled.svg');
  });
  test('IMDb shows one decimal, TMDB a percentage', () {
    expect(const ExternalRating(source: ExternalRatingSource.imdb, value: 7.4).label, '7.4');
    expect(const ExternalRating(source: ExternalRatingSource.tmdb, value: 73).label, '73%');
  });
}
```

Plex-mappertest: laad de fixture, map via dezelfde functie die `getMetadataWithImagesAndOnDeck` gebruikt, en verwacht vier ratings in de volgorde IMDb, RT critic, RT audience, TMDB plus minstens één `MediaReview` met niet-lege `author` en `text`. Tweede test (Review Focus 2): een fixture zonder `Rating[]` maar met `rating: 9.2, ratingImage: rottentomatoes://image.rating.ripe, audienceRating: 8.8, audienceRatingImage: rottentomatoes://image.rating.upright` levert RT critic 92 en RT audience 88.

Jellyfin-mappertest:

```dart
test('CriticRating becomes an RT critic score, CommunityRating a community score', () {
  final item = mapJellyfinItem({'Id': 'x', 'Type': 'Movie', 'Name': 'Sintel', 'CriticRating': 92, 'CommunityRating': 7.4});
  expect(item.externalRatings.map((r) => r.source), [ExternalRatingSource.rottenTomatoesCritic, ExternalRatingSource.community]);
  expect(item.externalRatings.first.value, 92);
});
```

(Gebruik de werkelijke publieke mapperfunctie uit `jellyfin_mappers.dart`; de naam `mapJellyfinItem` is een voorbeeld, zoek hem op met `rg -n "CommunityRating" lib/services/jellyfin_mappers.dart`.)

- [ ] **Step 3:** run `flutter test test/media/external_rating_test.dart test/services/plex_mappers_ratings_test.dart test/services/jellyfin_mappers_ratings_test.dart`; verwacht FAIL (ontbrekende types).
- [ ] **Step 4:** implementeer de modellen, de twee `MediaItem`-velden, de Plex-parsing (`Rating[]` met `type == 'critic'|'audience'` en `image`-prefix `imdb://`, `rottentomatoes://`, `themoviedb://`; fallback op `ratingImage`/`audienceRatingImage` als `Rating[]` leeg is), `includeReviews: 1` in beide detailrequests (`plex_client.dart:1003` en `:1065`), en de Jellyfin-mapping. Zet `CriticRating` en `CommunityRating` expliciet in `_detailFields` als de server ze niet standaard meelevert. Controleer dat `parseCache` het volledige antwoord bewaart, zodat een cachehit de ratings en reviews ook heeft. Draai `scripts/codegen.sh`.
- [ ] **Step 5:** tests PASS; draai daarnaast `flutter test test/utils/ test/widgets/media_rating_badge_test.dart` als die bestaat, zodat de oude chips niet breken.
- [ ] **Step 6:** commit `feat(detail): externe scores en Plex-recensies als data per backend (DEC-140)`.

---

### Task 2: Poster-hero, waas en scorerij

**Files:**
- Create: `lib/screens/media_detail/mobile/detail_ambient_background.dart`, `lib/screens/media_detail/mobile/mobile_poster_hero.dart`, `lib/screens/media_detail/mobile/detail_score_row.dart`
- Modify: `lib/screens/media_detail/mobile_detail_view.dart` (vervangt `_buildMobileGlassHero` en de voorvertoningskaart op de iPhone)
- Test: `test/screens/media_detail/mobile_poster_hero_test.dart`

**Interfaces:**
- Consumes: `MediaItem.externalRatings` (Task 1).
- Produces:
  - `DetailAmbientBackground({required ImageProvider? image, required Widget child})`: stapelt een `ImageFiltered(ImageFilter.blur(sigmaX: 60, sigmaY: 60))`-kopie van de poster (160% breed, verankerd onderaan de poster) onder een verloop van transparant naar `Theme.of(context).scaffoldBackgroundColor` op ongeveer 1500 logische pixels, zoals `D-01-film.html` (`.ambient`).
  - `MobilePosterHero({required MediaItem item, required String? posterUrl, required String? fallbackArtUrl, required Widget scoreRow})`: poster op volle breedte, hoogte 640 bij 402 breed (schaal lineair met de breedte), `ShaderMask` met `BlendMode.dstIn` en stops `[0.55, 0.78, 1.0]` zodat de onderkant in de waas oplost; meta-regel (jaar · duur of seizoenen · genres, kader met leeftijdsclassificatie) en de scorerij onderaan eroverheen.
  - `DetailScoreRow({required List<ExternalRating> ratings})`: `SvgPicture.asset(r.assetPath, height: 18)` plus `r.label`, gecentreerd, niet aantikbaar; leeg als `ratings` leeg is.

- [ ] **Step 1: Failing tests.**

```dart
testWidgets('score row renders one icon per rating and no tap target', (tester) async {
  await tester.pumpWidget(MaterialApp(home: DetailScoreRow(ratings: const [
    ExternalRating(source: ExternalRatingSource.imdb, value: 7.4),
    ExternalRating(source: ExternalRatingSource.rottenTomatoesCritic, value: 92),
  ])));
  expect(find.byType(SvgPicture), findsNWidgets(2));
  expect(find.text('7.4'), findsOneWidget);
  expect(find.text('92%'), findsOneWidget);
  expect(find.byType(InkWell), findsNothing);
  expect(find.byType(GestureDetector), findsNothing);
});

testWidgets('hero without poster falls back to the art image and a text title', (tester) async {
  // Review Focus 1
  final item = MediaItem(id: 'm', backend: MediaBackend.jellyfin, kind: MediaKind.movie, title: 'Sintel', serverId: 's', serverName: 'S');
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: MobilePosterHero(item: item, posterUrl: null, fallbackArtUrl: 'https://x/art.jpg', scoreRow: const SizedBox()))));
  expect(find.text('Sintel'), findsOneWidget);
});
```

Plus in `test/screens/media_detail_screen_test.dart`, groep I6: een `pumpPhoneDetail`-test die eist dat `MobilePosterHero` en `DetailAmbientBackground` er staan en dat de oude voorvertoningskaart (`find.byKey(...)` die de huidige tests voor de 16:9-kaart gebruiken) weg is.

- [ ] **Step 2:** run, verwacht FAIL.
- [ ] **Step 3:** implementeer. Posterbron: `thumbPath` (staand) via dezelfde URL-helper die de rest van de detail voor artwork gebruikt; `artPath` alleen als fallback. Bij een ontbrekende poster en art: effen `scaffoldBackgroundColor`, geen waas. Laat de bestaande `MobileDetailHeroBar` (terug, Meer) bovenop de hero staan.
- [ ] **Step 4:** tests PASS; pas de tests in `mobile_detail_glass_test.dart` en de I6-groep die de oude hero of kaart pinden aan, met per aangepaste test één regel in de commit-body waarom.
- [ ] **Step 5:** commit `feat(detail): staande poster met waas en scorerij op de iPhone (DEC-140)`.

---

### Task 3: Hoofdknop, "vanaf begin" en actierij

**Files:**
- Create: `lib/screens/media_detail/mobile/detail_primary_actions.dart`
- Modify: `lib/screens/media_detail/mobile_detail_view.dart:304-371`, `lib/screens/media_detail/mobile_detail_info.dart:64-251` (oude actierij en Downloaden-capsule weg), `lib/widgets/media_context_menu.dart` (Delen en Aanvragen erbij als menu-items als ze er nog niet zijn)
- Test: `test/screens/media_detail/detail_primary_actions_test.dart`

**Interfaces:**
- Produces:
  - `DetailPrimaryActions({required String playLabel, String? playDetail, VoidCallback? onPlay, VoidCallback? onPlayFromStart, required List<DetailActionItem> actions})`
  - `class DetailActionItem { final IconData icon; final String label; final bool active; final VoidCallback onTap; final Key key; }`, rij met `Row` van gelijke `Expanded`-kolommen zodat vijf of zes items passen.
- Keys: `media-detail.play`, `media-detail.play-from-start`, `media-detail.action.watchlist|trailer|rate|watched|download|more`. `media-detail.play` bestaat al in `ios.glass.detail.yaml`, houd hem gelijk.

- [ ] **Step 1: Failing tests.**

```dart
testWidgets('play-from-start only shows while there is progress', (tester) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: DetailPrimaryActions(playLabel: 'Afspelen', onPlay: () {}, actions: const []))));
  expect(find.byKey(const Key('media-detail.play-from-start')), findsNothing);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: DetailPrimaryActions(playLabel: 'Hervatten', playDetail: 'nog 8 min', onPlay: () {}, onPlayFromStart: () {}, actions: const []))));
  expect(find.byKey(const Key('media-detail.play-from-start')), findsOneWidget);
});
```

In de I6-groep: film toont zes actiesleutels in de volgorde watchlist, trailer, rate, watched, download, more; serie vijf zonder download; offline (Review Focus 5) geen rate. Film zonder trailer laat trailer weg.

- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** implementeer. Handlers: `_handlePlayPressed`, de bestaande "afspelen vanaf begin" uit `media_context_menu.dart` (rond regel 571; trek de kern eruit naar een methode die beide gebruiken), `WatchlistUiActions.toggle`, `_showRatingDialog`, `_handleWatchedTogglePressed`, `_handleDownloadButtonPressed`, `_getPrimaryTrailer` + `navigateToVideoPlayer`, en Meer = `MediaContextMenu`. Zet in het contextmenu Delen (`_shareMobileItem`-logica) en, als `SeerrProvider.isConfigured`, Aanvragen; seizoen downloaden staat er al (`media_context_menu.dart:455-495`). Actief-staat (Bekeken, Kijklijst): witte cirkel met donker icoon.
- [ ] **Step 4:** PASS, commit `feat(detail): hoofdknop met vanaf begin en de nieuwe actierij (DEC-140)`.

---

### Task 4: Bronregel en activiteitskaart

**Files:**
- Create: `lib/screens/media_detail/mobile/detail_activity_card.dart`
- Modify: `lib/screens/media_detail/mobile_detail_view.dart`, stijl van `_buildUnifiedSourceLine` alleen voor de iPhone-aanroep (`action_buttons.dart:379`, via een parameter; TV-uiterlijk ongemoeid)
- Test: `test/screens/media_detail/detail_activity_card_test.dart`

**Interfaces:**
- Consumes: `_watchers`, `_watchStats` en `NowWatchingProvider` zoals `NowWatchingLine`/`WatchedByRow`/`WatchStatsRow` ze nu lezen (`media_detail_screen.dart:2240-2270`).
- Produces: `DetailActivityCard({required List<ItemWatcher> watchers, required String? nowWatchingName, required int? playCount, required int? viewerCount, required bool isSeries, String? ownProgressLabel})`; rendert niets als `watchers` leeg is en `nowWatchingName == null`.

- [ ] **Step 1: Failing tests:** lege invoer levert `SizedBox.shrink`; met twee watchers en "Robin" als kijker staat "Robin kijkt dit nu" in wit met een rood stipje; voor een serie toont de tweede regel `ownProgressLabel` ("Jij bent bij S1 A3"). Gebruik het echte watcher-type uit `lib/services/item_watchers_service.dart` (zoek de klassenaam op).
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** implementeer; avatars overlappend (36 px, -10 px), kaart met `Colors.white.withValues(alpha: 0.08)` en radius 14, zoals `.act` in `D-01-film.html`. Geen nieuwe data-aanroepen: de gates (Plex, `isOwnerOrAdmin`, Tautulli) blijven waar ze zitten.
- [ ] **Step 4:** I6-test: een Jellyfin-item toont geen kaart.
- [ ] **Step 5:** PASS, commit `feat(detail): activiteitskaart op de iPhone (DEC-140)`.

---

### Task 5: Techniektabel, audio onthouden, ondertiteling kiezen

**Files:**
- Create: `lib/screens/media_detail/mobile/detail_tech_table.dart`, `lib/widgets/mobile/mobile_subtitle_track_picker_sheet.dart`
- Modify: `lib/screens/media_detail/audio_selector.dart:60-113`, `lib/screens/media_detail/mobile_detail_view.dart:70-80`, `lib/widgets/mobile/mobile_audio_track_picker_sheet.dart` (uiterlijk naar D-02: vinkje rechts, subtitel "geldt voor deze film" of "voor deze serie")
- Test: `test/screens/media_detail/detail_tech_table_test.dart`, bestaande `test/widgets/mobile/mobile_audio_track_picker_sheet_test.dart`

**Interfaces:**
- Consumes: `MediaFileInfo` via `client.getFileInfo()` (al geladen in `audio_selector.dart:41`), `TrackPreferenceStore.read`, `.saveAudio`, `.saveSubtitle` (`lib/services/track_preference_store.dart:169-191`).
- Produces: `DetailTechTable({required String? videoLabel, required String? audioLabel, VoidCallback? onAudioTap, required String? subtitleLabel, VoidCallback? onSubtitleTap, String? heading})`; `heading` is "Volgende aflevering · S1 A3" op de seriepagina (niet gebruikt, zie Task 7) en op de seizoenspagina.

- [ ] **Step 1: Failing tests.**

```dart
testWidgets('choosing an audio track stores it and does not start playback', (tester) async {
  // pump the phone detail with a fake client whose getFileInfo returns two audio tracks,
  // tap the Audio row, pick the second track in the sheet
  // expect: TrackPreferenceStore holds the second language for this item
  // expect: the fake navigator observer saw no push of the video player route
});

testWidgets('single audio track: row without chevron and not tappable', (tester) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: DetailTechTable(videoLabel: '1080p (H.264)', audioLabel: 'Engels (AAC stereo)', onAudioTap: null, subtitleLabel: 'Uit', onSubtitleTap: () {}))));
  expect(find.byIcon(Symbols.chevron_right_rounded), findsOneWidget); // alleen de ondertitelrij
});
```

Schrijf de eerste test volledig uit met de fakes die `media_detail_screen_test.dart` al heeft (`_FakeMediaServerClient`, `pumpPhoneDetail`) en een `NavigatorObserver`; de bestaande test die nu bewijst dat een keuze afspelen start, moet je omdraaien, niet verwijderen. Offline (Review Focus 5): tabel blijft, gevuld uit de lokale `MediaFileInfo`.

- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** implementeer. Haal `navigateToVideoPlayerWithRefresh` uit `_chooseDetailAudioTrack` (`audio_selector.dart:96-111`) en laat alleen `saveAudio` plus `setState` staan. Ondertitelpaneel: sporen uit `MediaFileInfo` plus "Uit" bovenaan; keuze via `saveSubtitle`. Labels: taal plus codec en kanalen (`Nederlands (EAC3 5.1)`), video als resolutie plus HDR-type plus codec (`4K Dolby Vision (HEVC Main 10)`); zoek eerst of `FileInfoBottomSheet` die formattering al heeft en hergebruik die.
- [ ] **Step 4:** PASS, commit `fix(detail): audio- en ondertitelkeuze onthouden in plaats van afspelen, techniektabel (DEC-140)`.

---

### Task 6: Recensies, cast, extra's en verwante rijen

**Files:**
- Create: `lib/screens/media_detail/mobile/detail_reviews_section.dart`
- Modify: `lib/screens/media_detail/cast_section.dart` (rond 96 px op de iPhone, rol eronder), `lib/screens/media_detail/mobile_detail_view.dart:88-97` (volgorde: cast, recensies, trailers en extra's, dan `_relatedHubs`)
- Test: `test/screens/media_detail/detail_reviews_section_test.dart`

**Interfaces:**
- Consumes: `MediaItem.reviews` (Task 1).
- Produces: `DetailReviewsSection({required List<MediaReview> reviews})`; kaarten van 300 bij 150, auteur vet, bron plus fresh/rotten-icoon uit `imageUri` als dat een `rottentomatoes://image.review.*`-uri is, tekst op vier regels afgekapt; leeg als `reviews` leeg is. Een tik opent de volledige tekst in een `OverlaySheetHost`-sheet (link naar de bron als knop, via `url_launcher` als dat al een dependency is; anders geen knop).

- [ ] **Step 1: Failing tests:** lege lijst rendert niets; twee reviews renderen twee kaarten met auteur; tik opent de sheet met de volledige tekst.
- [ ] **Step 2:** FAIL. **Step 3:** implementeer. **Step 4:** PASS.
- [ ] **Step 5:** commit `feat(detail): Plex-recensies en ronde cast op de iPhone (DEC-140)`.

---

### Task 7: Seizoensrij en seizoenspagina

**Files:**
- Create: `lib/screens/media_detail/mobile/detail_seasons_rail.dart`
- Modify: `lib/screens/media_detail/mobile_detail_view.dart` (seriepagina: seizoensrij in plaats van `_buildMobileEpisodesSection`), `lib/screens/media_detail/mobile_episodes_section.dart` (alleen nog voor `isSeason`: geen seizoenpil), `lib/utils/media_navigation_helper.dart:103-121`
- Test: `test/screens/media_detail/detail_seasons_rail_test.dart`, `test/utils/media_navigation_helper_test.dart`

**Interfaces:**
- Produces:
  - `DetailSeasonsRail({required List<MediaItem> seasons, required void Function(MediaItem season) onOpen})`: kop "N seizoenen" (of "1 seizoen"), posters 130 bij 195, voortgangsbalk als het seizoen deels bekeken is, badge met het aantal onbekeken afleveringen; niets bij een lege lijst.
  - In `media_navigation_helper.dart`: een parameter of aparte functie `openSeasonDetail(BuildContext, MediaItem season)` die op de iPhone `MediaDetailScreen` met het seizoen zelf opent (de weergave voor `isSeason` bestaat al, `mobile_episodes_section.dart:24`). TV, iPad en desktop houden de bestaande omleiding naar de serie met `initialSeasonIndex`.

- [ ] **Step 1: Failing tests:** rail met twee seizoenen toont "2 seizoenen" en twee posters; tik roept `onOpen` met het tweede seizoen aan; lege lijst rendert niets (Review Focus 4); navigatietest: op een phone-sized `MediaQuery` levert de helper een route naar het seizoen, op TV nog steeds naar de serie.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** implementeer. De seriepagina laadt de seizoenen al (`childrenByParent`/`_fetchSeasons`); geef die door. De seizoenspagina hergebruikt de hele mobiele view: poster-hero met de seizoensposter, hoofdknop voor de volgende aflevering in dit seizoen, techniektabel met `heading` "Volgende aflevering · S1 A3", en de afleveringslijst (rijen uit `_buildEpisodesList`, stijl van northstar 07 zoals DEC-131 voorschrijft).
- [ ] **Step 4:** pas de I6-test "switching season on the season-picker chip survives an unrelated rebuild" aan: die hoort nu bij de seizoenspagina, of vervalt met een regel in de commit-body als de pil niet meer bestaat.
- [ ] **Step 5:** PASS, commit `feat(detail): seizoensrij en eigen seizoenspagina op de iPhone (DEC-140)`.

---

### Task 8: Titelbalk bij scrollen (D-03b)

**Files:**
- Modify: `lib/screens/media_detail/mobile_detail_hero.dart` (`MobileDetailHeroBar`), `lib/screens/media_detail/mobile_detail_view.dart` (scroll-offset doorgeven)
- Test: `test/screens/media_detail/mobile_detail_glass_test.dart` (bestaande B5-groep uitbreiden)

**Interfaces:** `MobileDetailHeroBar` krijgt `String title` en `double collapseProgress` (0 tot 1). Bij 1: balkachtergrond ondoorzichtig in een donkere variant van de waas (of `surface` als er geen poster is), titel gecentreerd, 17 pt vet.

- [ ] **Step 1: Failing test:** na een scroll voorbij de hero (bijvoorbeeld `tester.drag(find.byType(CustomScrollView), const Offset(0, -900))`) is de titel in de balk zichtbaar (`Opacity` 1), vóór het scrollen niet.
- [ ] **Step 2:** FAIL. **Step 3:** implementeer met een `ScrollController`-listener en `ValueListenableBuilder`, zodat alleen de balk opnieuw bouwt. **Step 4:** PASS.
- [ ] **Step 5:** commit `feat(detail): titelbalk bij scrollen op de iPhone (DEC-140)`.

---

### Task 9: Verificatie en register

**Files:**
- Modify: `pleya_verify/scenarios/ios.detail.northstar.yaml`, `ios.detail-episodes.northstar.yaml`, `ios.glass.detail.yaml` (asserts op de nieuwe keys), `docs/ios-unified-implementation-register.md` (status met SHA's)

- [ ] **Step 1:** `scripts/ci_checks.sh`, volledige uitvoer bewaren buiten de repo.
- [ ] **Step 2:** `flutter test test/screens/media_detail/ test/screens/media_detail_screen_test.dart test/media/ test/services/ test/widgets/mobile/`; daarna de volledige suite met de gepinde SDK.
- [ ] **Step 3:** Verify op een iPhone-simulator (`PLEYA_VERIFY_IOS_UDID` zetten als er meer dan één iPhone opgestart is): film, serie, seizoenspagina, audio kiezen zonder afspelen. Screenshots naast `docs/assets/ios-unified/detail-2026/D-0x-*.png` leggen en per blok PASS of FIX noteren in het taakverslag. Scenario's die schermen van Jellyfin gebruiken tonen geen activiteit en geen recensies; dat is het verwachte gedrag.
- [ ] **Step 4:** register bijwerken naar `CODE CLOSED · SIMULATOR VERIFIED · HARDWARE OPEN`, met de SHA's van Task 0 tot en met 8.
- [ ] **Step 5:** commit `docs: DEC-140 gesloten op code- en simulatorniveau`.

Daarna: één whole-branch review (owner-regel 25 september), één fixronde, en `superpowers:finishing-a-development-branch`.
