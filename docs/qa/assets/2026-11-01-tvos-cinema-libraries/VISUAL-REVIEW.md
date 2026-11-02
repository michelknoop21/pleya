# Cinema A — native pixel- en flowreview

**Beperkte GO voor de getoonde native staten.** De enige blokkerende instructiefout is in het opnieuw bekeken orderframe gesloten; overige reviewgrenzen blijven gelden. Geen nieuwe ontwerp-/architectuurronde nodig.

## Bron en werkelijk bekeken bewijs

Persoonlijk alle zeven native PNG's bekeken uit `pleya-tvos-cinema-libraries/.build/pleya-verify/tvos-my-pleya-libraries-cinema-1793567318132/screenshots`, naast goedgekeurde `source/pleya-tvos-cinema-northstar/screenshots/01-cinema-overview.png`. Native 3840×2160 tegenover bron 1920×1080, vergeleken op dezelfde 16:9-verhoudingen. Rapport: PASS, 209204 ms, schone commit `7813969eb8e38143853bb2b699c987c3b2b6d3d7`, tvos-sim. Dit is werkelijk native simulatorbewijs, geen HTML- of widgetbeeld.

| Beeld | Beoordeeld resultaat |
|---|---|
| 00-bronbeheer-list | Cinema A-compositie herkenbaar behouden: links bronlijst, rechts geselecteerde titel/telling/status, lokale glasgeometrie, warme achtergrond en native headeracties. Focus op Movies duidelijk. Fixture 3/1 correct, geen fictieve 485/107 overgenomen. |
| 01-action-sheet-movies | Bestaand actieblad leesbaar, binnen venster, dimt de achterliggende pagina; Sluiten heeft zichtbare focus. Openen/Verbergen/Big P zichtbaar. Geen onderhoudsrechten afleiden uit dit beeld. |
| 02-sheet-closed | Focus keert zichtbaar terug op dezelfde Movies-rij; geselecteerde summary blijft consistent. |
| 02b-cinema-order-picked | Genummerde rijen, Movies opgepakt, label Verplaatsen en Klaar zichtbaar; rechter instructie past bij ordenen. Onderste footer is onjuist — zie bevinding 1. |
| 02c-cinema-order-closed | Normale acties en Movies-focus terug; overviewcompositie hersteld. |
| 03-opened-in-catalog | Bestaande catalogus met 1 bron, 3 fixturetitels; gedeelde navbar blijft staan, geselecteerde eerste kaart duidelijk. Geen herontwerp van dit ongewijzigde catalogusoppervlak beoordeeld. |
| 04-back-on-row | Terug naar Bibliotheken, Movies-focus en summary behouden. |

Zwarte gedeelde navbarzone wijkt af van de doorlopende HTML-bronachtergrond, maar is expliciet te behouden bestaande shellchrome; geen bevinding of verzoek tot navbarwijziging. Titels Movies/Shows en servernaam Zolder komen uit de fixture, niet uit vertaalde mockupdata; ook dit is geen defect.

## Bevindingen — één batch

### Important 1: footer geeft tijdens Ordenen de verkeerde Select-actie aan

`02b-cinema-order-picked.png` toont onderaan **Select voor bibliotheekopties** terwijl Movies is opgepakt. In deze modus opent Select geen actieblad maar zet de rij neer (of pakt een andere rij op). `tv_libraries_screen.dart` rendert `cinemaOptionsHint` onvoorwaardelijk. Kleine correctie: modeafhankelijke, gelokaliseerde Select-instructie voor pakken/neerzetten tijdens Ordenen; normale bibliotheekoptieshint behouden buiten die modus. Geen verandering van immediate-persist/Back-contract nodig. Gerichte assertion moet beide modusinstructies onderscheiden; alleen deze staat opnieuw native visueel vastleggen na fix.

### Minor, niet blokkerend: kolomkop uit A ontbreekt

De goedgekeurde A-bron heeft naast elke serverkop een klein `items`-kolomlabel met scheidingslijn. Het native overview toont alleen de servernaam. Tellingen zelf staan correct uitgelijnd en de summary benoemt items; er is geen functionaliteitsverlies. Dit is een concrete kleine bronafwijking, geen reden voor een nieuwe ontwerpronde of verplicht breed herstel.

## Grenzen — niet uitgevoerd in deze native run

Geen native beelden/proeven voor lege lijst, onbekende telling, verborgen bibliotheek, lange titel, meerdere gelijknamige/interleaved servers, 40-rijenherstel of echte reorder-verplaatsing/persist/relaunch. Daarvoor bestaat eerder unit-/widgetbewijs, geen native acceptatie in dit pakket. Onderhouds-/owner-/Plex-capabilitygevallen en echte provider-/profielwijzigingen zijn hier niet uitgevoerd. Het scenario bewijst het getoonde fixturepad, inclusief actieblad/Back, reorderheader-Menu, picked-row/Menu en catalogusbronfilter/terugkeer. Geen fysieke Siri Remote, overscan of release-/deviceperformance bewezen. Geen push/merge/upload- of algemene release-GO.

Alleen bewijs gelezen en dit reviewbestand geschreven; geen productcode, tests, build, UI of netwerk uitgevoerd.


## Sluiting van Important 1 — definitief orderframe

Persoonlijk uitsluitend het gewijzigde `02b-cinema-order-picked.png` bekeken uit native run `tvos-my-pleya-libraries-cinema-1793568204830`, door eigenaar gekoppeld aan schone commit `1bba038a74525d61de5cc88211f80ec6d35e6794`. Footer toont nu volledig op één regel: **Select: oppakken/neerzetten · ↑↓: verplaatsen · Menu: klaar**. Geen afkapping of overlap; de opgepakte Movies-rij, focusring, Klaar en bestaande compositie blijven behouden. **Important 1 gesloten.** De oude bevinding hierboven is historische onderbouwing, geen resterende blokkade.

De eerdere zeven-statenreview blijft het bewijs voor ongewijzigde staten op `7813969eb`; deze herreview dekt alleen de ene afgesproken footerwijziging. De terminale uitkomst is inmiddels rechtstreeks geverifieerd in report.md en manifest.json: **PASS**, **148389 ms**, **dirty: false**, exact `1bba038a74525d61de5cc88211f80ec6d35e6794`, target tvos-sim. Het gepackte bewijs noemt Debug Verify 2.8.1 (430), bundle `nl.michelknoop.pleya.verify`, idb en tvOS 27 op de eigen Apple TV 4K-simulator. Een eerdere bouwpoging `1793568009429` faalde volgens eigenaar vóór scenario-uitvoering op ld/MoltenVK en is geen scenarioregressiebewijs. Geen algemene release-/hardware-GO of nieuwe native claims buiten het bekeken frame.


## Feitelijke document-/registerclosure

De finale éénpagina-overdracht, assetmanifest/Verify-rapport en LIB-CINEMA1 zijn consistent met de genoemde schone SHA, duur, zes en/nl-labels, beperkte pixel-GO en CODE/SIM CLOSED · HARDWARE OPEN. Ze onderscheiden de eerdere brede lintbatch van de finale gewone codegate en benoemen de tussentijdse MoltenVK-linkfout/clean zonder dat als scenariofail of productwijziging te verkopen. Ze behouden expliciet de native coveragegrenzen en bevatten geen release-, push-, merge- of hardwareacceptatieclaim. **GO voor de documentclosure binnen dit pakket.** Geen nieuwe code-/pixel-/testaudit uitgevoerd.
