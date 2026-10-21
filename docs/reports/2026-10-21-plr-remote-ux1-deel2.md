# PLR-REMOTE-UX1 deel 2: rapport

Roadmap: A-11 (afwijking en akkoord staan bij deel 1 in `docs/ROADMAP.md`). Unified impact: gedeelde speler; de guards gelden op TV (de bestaande skip-autofocus was al TV-only).

## Wijzigingen (voorstelregels 5 en 6 van het onderzoek)
- Skip-autofocus bij markerstart komt alleen nog uit de neutrale video: niet bij een open infopaneel, open sheet, zichtbare controls (ook queue en gefocuste transportrij) of actieve scrub-preview (`markers.dart`, `_isVideoFocusNeutral`); de zichtbare-controlsguard geldt alleen op Apple TV, andere TV's behouden hun autofocus.
- De zevensecondentimer haalt een gefocuste skipknop niet meer weg zolang de marker geldt; hij kijkt na zeven seconden opnieuw.
- Loopt een marker af of wordt hij geactiveerd terwijl de knop focus heeft, dan gaat focus naar Afspelen (balk zichtbaar) of naar de spelerwortel, tenzij paneel of sheet de focus houdt.
- Play Next-kaart vraagt focus pas als paneel en sheet loslaten (`DeferredFocusGate`; `PlayerChromeController.tvInfoPanelOpen` laat de screen het paneel zien, `OverlaySheetHost.onOpenChanged` de sheet).
- Al aanwezig en ongemoeid: omlaag op de skip-pil gaat naar Afspelen en opent zo nodig de balk; omhoog-snelroute; Select activeert één keer.

## Bewijs
- `test/widgets/video_controls/tv_skip_focus_test.dart` (8), `test/screens/video_player/deferred_focus_gate_test.dart` (3); gedeeld harnas `tv_player_harness.dart`, waar `tv_native_pause_test.dart` nu ook op draait.
- Negatieve controle per fix: zonder de neutraliteitsguard rood (zichtbare controls, sheet); zonder de timerguard rood; zonder focusherstel rood; zonder de paneelmelding rood. De gate-unittests dekken het uitstel zelf.
- Reviewbevinding (Important): na het sluiten van het paneel pakte de root-reclaim de focus terug van de wachtende Play Next-kaart. Gefixt (`_hideTvInfoPanel` slaat de reclaim over zolang `playNextFocusNode` bestaat) met een test die rood is zonder die conditie. Minor: een Android TV-regressie van de balkguard (nu Apple TV-only) is gefixt; twee theoretische Minors (retry bij dispose met paneel open; `_sheetOpen` als de host wegvalt met open sheet) zijn bewust niet gewijzigd.
- Testnaad: `debugApplyPlaybackExtras` (`@visibleForTesting`) voert markers in zoals de loader.

## Open
- De koppeling gate-screen (paneel/sheet naar Play Next-focus) is niet in een volledige `VideoPlayerScreen` getest: dat scherm is niet pompbaar in tests. De onderdelen zijn apart bewezen (gate, paneelmelding, sheet-callback).
- Geen Pleya Verify-scenario: de fixture heeft geen markers of tweede aflevering en de catalogus geen skip/Play Next-ID's (testvoorwaarde uit het onderzoek, niet verzonnen).
- Fysieke Siri Remote-acceptatie blijft open.
