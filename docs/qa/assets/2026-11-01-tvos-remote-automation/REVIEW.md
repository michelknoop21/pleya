# LIB-REMOTE1 — gerichte onafhankelijke review

**GO voor de test-/scenario-/CI-/documentatiediff sinds `22e525707` en de hieronder vastgelegde native appacceptatie.** Geen concrete blokkerende bevindingen. Alleen bron en bestaande bewijsclaims gelezen; geen tests, build, netwerk of UI gestart en geen productcode gewijzigd.

## Beoordeeld

- Drie Cinema-widgettests sturen expliciete down/repeat/up-events en toetsen de eindfocus, stoppen na release, één actieblad met volgende bruikbare Select, en verwijderen van een opgepakte rij tijdens held input zonder onbedoelde verplaatsing van een andere rij. Ze gebruiken bestaande fakes/provider/UI. Geen productiepredicate of bestaande assertion verzwakt.
- Nieuw `tvos.my-pleya.libraries-remote-hold`: HID-holds van 250 ms op pijlen/Menu en 650 ms op Select; assertions voor focus, modalreturn/afwezigheid, Klaar→normale header, moving true/false, echte rijvolgorde na move, en werkende vervolginvoer. Eén Menu moet het actieblad volledig sluiten; dit vangt een achterblijvend gestapeld actieblad af. De run moet nog terminale native resultaten leveren; schrijven van het scenario is geen PASS.
- `tvos.nav.held-press-lands-once` wijzigt alleen onjuiste toelichtingsclaims. Setup/stappen/predicates blijven gelijk. De nieuwe tekst past bij de repo-gemeten station-3-grens: idb keyboard-HID levert geen bewijs voor de geswizzelde UIPress-hook, engine pressed-set of repeattimer. De app-side parked/held-enable-diagnostiek blijft de bewezen invariant.
- CI voegt uitsluitend drie sequentiële canonical Verify-commando's toe na succesvolle tvOS smoke in de bestaande job, met appreuse binnen dezelfde onveranderde checkout. Geen nieuwe permissions, triggers, installaties, runner of continue-on-error. De bestaande 60-minutengrens en evidence-upload bij always blijven staan. Drie extra scenario's vergroten looptijd, maar er is geen bronbewijs dat de bestaande limiet hierdoor onhaalbaar is. Native looptijd moet worden vastgelegd; geen tweede eigenaar of parallelle devicebesturing toegevoegd.
- De overdracht onderscheidt Flutter fixtures, gemodelleerde bounce-/touchtests, daadwerkelijk idb-HID en niet-uitgevoerde XCUIRemote-proeven. Ze claimt geen fysieke Bluetooth-, touchpad- of Swift/enginefilteracceptatie. Installed idb1.1.7 versus actuele documentatie wordt expliciet onderscheiden; geen impliciete toolupgrade of alternatieve inputroute.
- Appcode-tree wordt als gelijk aan `1bba038a7` beschreven; de nieuwe diff raakt geen productcode. Native hergebruik moet zoals afgesproken door de eigenaar met artifact/source-hashguard worden bevestigd. De CI-variant hergebruikt alleen de app die dezelfde job zojuist op dezelfde checkout heeft gebouwd.
- LIB-REMOTE1 staat terecht IN PROGRESS. De 128 gerichte tests zijn reeds door de eigenaar uitgevoerd; geen hardware-/release-GO uit afgeleid. Wekelijkse maandag04:17UTC/dispatch-job is duidelijk onderscheiden van een verplichte PR-gate.

## Grenzen

Geen nieuwe native run of screenshot door deze reviewer uitgevoerd/beoordeeld in deze stap. Native pack van de drie flows, correcte artifactidentiteit, terminale resultaten en relevante beelden moeten nog worden aangeleverd. Fysieke touch/Bluetooth/bounce en toestelperformance blijven buiten dit appacceptatiebewijs. Geen push-, merge-, NAS- of releaseuploadautorisatie afgeleid.


## Finale bewijsclosure — native appacceptatie GO

Drie gepackte Verify-rapporten en manifest gelezen: schone testcommit `af7a42ee6b51ca8e6d090e707409c7f9969cb60a`, alle drie **PASS**: Cinema `1793570066663` **124291 ms**; navigatie `1793570192264` **40326 ms**; profielkiezer `1793570233784` **26263 ms**. Het manifest onderscheidt testcommit van ongewijzigde appcode `1bba038a74525d61de5cc88211f80ec6d35e6794`, 2.8.1 (430) Debug Verify, en legt drie voor/na gelijke app-payloadhashes plus hergebruik vast. Geen appherbouw- of actuele testcode-in-appclaim uit alleen HEAD afgeleid.

De drie representatieve native PNG's persoonlijk bekeken en hun SHA256 tegen het manifest gecontroleerd: Cinema toont Movies opgepakt op positie02 onder Shows01 met correcte footer; navigatie toont de gewone Home-inhoud met Home actief; profielkiezer toont één gefocust synthetisch verify-profiel. Geen nieuwe visuele appbevinding in deze beperkte frames. Alle tien beelden blijven volgens eigenaar in de benoemde lokale bundels; deze closure beoordeelt de drie gepackte representatieve beelden en de rapportasserties, geen nieuwe volledige pixelaudit.

De bewijsnotitie en LIB-REMOTE1 zijn consistent: **128 Fluttertests + 11 inputcontracttests + drie native scenario's PASS**, APP-AUTOMATISERING CLOSED voor de fixtures. CI-toevoegingen worden pas na integratie in de bestaande maandag04:17UTC/dispatch-job actief; er is geen externe dispatch of push verricht. XCUIRemote is onderzocht maar niet uitgevoerd. Fysieke Bluetooth, werkelijk touchpadgedrag, UIKit/Swift/engine pressed-set/repeattimer en toestelperformance blijven onbewezen. Geen hardware-, release-, push- of merge-GO. **GO voor de feitelijke document-/registerclosure en overdracht aan de eigenaar.** Geen extra uitvoerproeven gedaan.
