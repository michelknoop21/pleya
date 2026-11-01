# Cinema A — onafhankelijke gerichte code-/registerreview

**NO-GO: twee Important correctheidsbevindingen.** Beoordeeld: working diff vanaf `1cc45a4be` in `feat/tvos-cinema-libraries`, inclusief nieuwe Cinema-widgets, scenario, tests en LIB-CINEMA1. Alleen-lezen; geen tests herhaald. Vastgelegd bewijs: finale 73 gerichte tests PASS; `--with-unused`-gate liep tijdens review. Geen native/visuele GO.

## Critical
Geen.

## Important

1. **Menu op de reorder-header sluit de modus niet volgens het vastgelegde contract.** `lib/screens/tv/sections/tv_libraries_screen.dart:386–397`, `:627`; `lib/widgets/tv/tv_panel_primitives.dart:63–134`. Alleen de reorder-rijen hebben `onBack: onExit`. De Klaar-knop gebruikt TvPanelButton, dat geen onBack doorgeeft, en er staat geen reorder-brede Back-handler omheen. Repro: Ordenen openen (dezelfde `_reorderNode` blijft op Klaar), direct Menu/Back indrukken, of vanuit de eerste niet-opgepakte rij UP naar Klaar en dan Menu. Het event kan naar de bovenliggende route doorvallen in plaats van alleen Ordenen te sluiten. `NATIVE-RECONSTRUCTION.md` legt expliciet vast: Klaar/Back sluiten de modus; stappen blijven onmiddellijk opgeslagen. Gerichte negatieve controle: Menu met Klaar gefocust sluit reorder, behoudt Bibliotheken en de reeds opgeslagen volgorde.

2. **Focusherstel kan een geldige maar niet gemounte eerste rij kiezen na diepe lijstwijziging.** `lib/screens/tv/sections/tv_libraries_screen.dart:178–197`, `:344–351`, `:449–475`. De nieuwe ListView realiseert alleen viewport/cache-rijen. Als een diep gefocuste rij extern verdwijnt, prunen we de verdwenen sleutel en kiezen vervolgens de eerste geldige rij. Die eerste rij kan buiten de cache liggen en een detached FocusNode hebben. `canRequestFocus` bewijst niet dat zijn context bestaat; requestFocus onthoudt dan een aanvraag voor heraanhechting, terwijl geen scroll/reveal die rij monteert. De bestaande codecomment waarschuwt zelf voor detached nodes, maar controleert alleen sleutelgeldigheid. Bronrepro: circa 40 bibliotheken; navigeer naar een diepe rij, verwijder die via providerupdate terwijl genoeg andere rijen blijven; na herstel moet primaryFocus een gemounte rij of gemounte headeractie zijn en navigatie werken. De huidige negen-rijentest en test van helemaal leeg raken dekt dit niet. Zelfde risico bij DOWN vanaf een header naar de eerste rij terwijl de lijst diep gescrold blijft. Kleine herstelrichting: expliciet reveal/mount vóór herstel, of een werkelijk gemounte geldige rij/headerfallback; geen scroll-/focusframework nodig.

## Minor
Geen verplichte stijlbevindingen.

## Overig beoordeeld
- Pure helper weigert onderhoud zonder server-ID; echte caller gebruikt rechten van exact die server; Plex-only acties blijven backendgebonden.
- Groepering gebruikt server-ID, ook bij gelijke namen/interleaving; `_movingKey` overleeft insertion op identiteit en vervalt bij verwijdering. Immediate persistence blijft; geen fictieve undo.
- Private GlobalObjectKey op per-scherm unieke FocusNode voorkomt keybotsingen tussen rijen; geen extra cache/map. Lazy detach verklaart wel bevinding 2.
- Decoratie gebruikt lokale gradients/geometrie; geen nieuwe mediafetches. Unknown/hidden/long-title inhoud komt uit echte modellen; TvPageSurface eyebrow blijft standaard afwezig.
- LIB-CINEMA1 blijft terecht IN PROGRESS en claimt geen release/nativebewijs. Nieuwe scenario dekt Back vanaf een rij, maar niet bevinding 1 vanaf Klaar. Finale pixels/native Verify blijven afzonderlijke gates.


## Scoped herreview — herstel van de twee Important bevindingen

**GO voor deze productfixdiff en vijf tekstlabels; finale gegenereerde boom/gates/nativepixels blijven pending.** Geen nieuwe bevindingen in deze afgebakende hercontrole.

- Bevinding 1 gesloten in bron: een bovenliggende Focus handelt Back voor de volledige reordermodus af, dus ook Klaar. De bestaande handleBackKeyAction bepaalt het platformmoment; Apple-TV matching KeyUp wordt na modewisseling apart geconsumeerd. Buiten reorder laat de handler Back door. Modals behouden hun eigen focuspad. Immediate persistence is ongewijzigd.
- Bevinding 2 gesloten in bron: beide beheerlijsten gebruiken weer volledig gemounte rows in een begrensde SingleChildScrollView/Column-pane, zoals het oorspronkelijke beheercontract. Daardoor zijn expliciete offscreenkeys en eerste-rijherstel werkelijk gehecht. Mode-exit revealt een nog gefocuste rij na layout. Geen lazy-focusframework, media/posters of nieuwe cache.
- Toegevoegde negatieve controles richten zich op de oorspronkelijke fouten: Back op Klaar; verwijderen van een diep gefocuste rij uit 40 bibliotheken en aansluitend D-pad naar de volgende rij. Parent rapporteert 27 bibliotheektests PASS na rode controles; geen suite door reviewer herhaald.
- Vijf en/nl Cinema-labels zijn lokale presentatie: zichtbaar, verborgen in dit profiel, Select-hint en twee samenvattingsregels. Slang base_locale-fallback bestaat; nieuwe gegenereerde Engelse/Nederlandse getters komen overeen met bronnen. Geen wire-/rechtenwijziging.
- Tijdens deze herreview liep normale codegen nog en waren gegenereerde bestanden tijdelijk verwijderd. Dat is geen definitieve diff of PASS: finale codegenexit, schone relevante generateddiff, 75 tests/codegate en native pixelvergelijking moeten door eigenaar nog worden vastgelegd. Geen native/visuele of release-GO.
