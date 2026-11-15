# PR #661-integratie

Roadmap: A-25

- Basis: main `ecc92a16`; oorspronkelijke correcties `4d66b7b3`; integratie `7cf98037`; lichte focusfix `e4c19302`; goldens en testharnas `dff4b1de`.
- Alle 13 oorspronkelijke PR-bestanden waren op main byte-identiek aan merge-base `ae6f7270`. De vier correcties zijn hergebruikt; nieuwere serienavigatie, menurechten, bronkeuze en artwork/cachecode blijven behouden. Geen redesign of architectuurwijziging.
- Unified impact: bestaande brongebonden kijkstatus, rechten en afleveringroutes behouden. De goedgekeurde 20 pt-paneelwaarde blijft lokaal; globale TV-schaling niet gewijzigd.
- Onafhankelijke code-review: één Important, vrijwel onzichtbare synopsisfocus in licht thema. Hersteld met de bestaande lichte focusrand; donker, geometrie en callbacks gelijk. Onafhankelijke fixreview en review van het gecorrigeerde invoermodus-testharnas akkoord.
- [Linux-validatie 43713382318](https://github.com/michelknoop21/pleya/actions/runs/43713382318) op `dff4b1de`: **164 gerichte tests PASS** (`test/screens/media_detail/tv/` en `test/screens/media_detail_synopsis_panel_test.dart`). Inclusief actuele serie-Select-, bron-, menu-, focus- en laadstatustests.
- Nieuwe focusfix: negatieve controle **1 FAIL verwacht**, na uitsluitend verwijderen van de lichte focusdecoratie; het testharnas gebruikt de productie-`InputModeTracker`. Productiebestand daarna hersteld.
- Goldens: [Linux-generatie 43712760287](https://github.com/michelknoop21/pleya/actions/runs/43712760287), twee PNGs onafhankelijk visueel akkoord en gecommit in `dff4b1de`. Hermeting in 43713382318: **2 tests PASS**, geen referentie gewijzigd.
- Beeldmanifest: `test/goldens/tv_detail_source_line.png` en `test/goldens/tv_detail_no_source_line.png`, beide 1038×584. Alleen wijzigingsgebied x83–616/y222–289: Meer lezen weg, compactere pill en grotere actie-iconen; bronregel en overige geometrie behouden. De witte titelplaceholder bestaat ook op main. Dit bewijst geen artworkkleuren, lichte/focusrender of hardwareprestaties.
- De tijdelijke branch-trigger en validatiestap in `goldens.yml` worden na de bewijsrun volledig verwijderd; de oorspronkelijke handmatige workflow blijft ongewijzigd.
- Volledige PR-CI/codeanalyse: controleer de actuele checks op de PR. De lokale `scripts/ci_checks.sh` kon niet draaien: Linux-omgeving zonder Flutter SDK. Historisch test-/simulatorbewijs uit de oorspronkelijke PR geldt niet als actuele native verificatie.
- Open: Pleya Verify `tvos.detail.movie`, `tvos.detail.series` (incl. `03-synopsis-focus`), `tvos.detail.more-actions` met screenshots op de gecombineerde code. Geen ondersteunde Apple-runtime in deze omgeving. Fysieke Apple TV: kleuren/leesbaarheid, focus en scrollprestaties blijven open.
- Bestaande conflictmarkeringen rond het spelerpakket in `docs/tvos-fysieke-correctieronde.md` zijn afkomstig van main en buiten deze scope. Geen merge naar main of release uitgevoerd.
