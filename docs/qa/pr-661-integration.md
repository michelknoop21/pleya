# PR #661-integratie

Roadmap: A-25

- Basis: main `ecc92a1627bc6a9910b4329dea6c1e6a92b3d773`; oorspronkelijke PR `4d66b7b3d6e4402699fdcba5488538070e41d3b8`; merge-base `ae6f72709bcefe1e1d7648937b709fbafd424816`.
- Alle 13 gewijzigde bestanden zijn op main byte-identiek aan de merge-base (Git-blob-SHA vergeleken). De merge hergebruikt exact de PR-versies van die bestanden en behoudt de rest van main. Geen redesign of architectuurwijziging.
- Unified impact: bronkeuze, brongebonden rechten, kijkstatus, artworkcache en nieuwere afleveringnavigatie van main blijven intact. Alleen de bestaande vier presentatiecorrecties worden geïntegreerd.
- De goedgekeurde 20 pt voor paneelwaarden blijft een lokale maat; de nieuwere globale `TvHig.readable` wordt niet gewijzigd. Leesbaarheid op televisie is nog te beoordelen.
- In deze omgeving ontbreekt Flutter en draait Linux zonder Apple-simulator. Geen actuele lokale codegate, widgettests, negatieve controles of Pleya Verify uitgevoerd. Resultaten uit de oorspronkelijke PR blijven historisch bewijs, geen integratiebewijs.
- GitHub CI na de branchupdate controleren. Gericht: `test/screens/media_detail/tv/` en `test/screens/media_detail_synopsis_panel_test.dart`; behoud vooral de nieuwe aflevering-Select- en Unified-tests.
- Goldens nog te regenereren op de bijgewerkte branch via `gh workflow run goldens.yml --ref fix/tvos-detail-northstar-polish -f targets=test/goldens/tv_detail_source_line_golden_test.dart`. Artifact visueel beoordelen, beide PNGs committen en CI opnieuw controleren. De connector heeft geen dispatch-operatie; CLI en browser zijn niet aangemeld.
- Pleya Verify: `tvos.detail.movie`, `tvos.detail.series`, `tvos.detail.more-actions`, inclusief `03-synopsis-focus`. Fysieke Apple TV: achtergrond/leesbaarheid, focus, scrollprestaties. Niet uitgevoerd.
- Onafhankelijke code-review in uitvoering; geen merge-/releaseclaim.
- Bestaande conflictmarkeringen in `docs/tvos-fysieke-correctieronde.md` rond het spelerpakket zijn al aanwezig op main en worden niet in deze scope opgelost.
