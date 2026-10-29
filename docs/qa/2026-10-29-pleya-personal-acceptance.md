# Persoonlijke appfuncties: acceptatiebasis

Roadmap: C-05 / S14 / S20. Bronbaseline: `b6ab8b4125e3206c0305addc74dcfd97d91b2779` (GitHub main, live gecontroleerd op 29 oktober 2026). Implementatie in `feat/pleya-server-personal-apps`; oude werkboom blijft ongemoeid.

Het serverketenbewijs van 25 oktober (`pleya_server/scripts/chain-smoke.sh`, masterlijst en toestelchecklist) blijft bestaand bewijs. De productie-SHA `138a2b8e` is een overdrachtsgegeven, niet live bevestigd. Testinstance, dataset, bereikbaarheid en werkelijk gedeployed schema zijn in deze ronde niet opnieuw vastgesteld. Geen productie als fixture.

S20.3 bewijst serveropslag en voorouderterugval. S20.5 bewijst tot deze baseline slechts concrete adapterhelpers, geen volledige publieke appaansluiting. Vervolgbewijs betreft favorieten, ratings en spoorvoorkeuren via de bestaande gedeelde eigenaars. Titelgebonden favorieten zonder externe ID krijgen een servergebonden sleutel; geen titelmatch als deduplicatiebewijs.

Platformacceptatie wordt apart vastgelegd voor iOS, tvOS, iPadOS, macOS, Android, Android TV, Windows en Linux, telkens met build-SHA, actieve speler en bewijs. In deze ronde zijn die fysieke checks nog open; gemeenschappelijke Dart-tests sluiten geen native platformrij. Volg `pleya-server-device-checklist.md` en `qa/ps5-hardware-round.md`.

Bestaande matrix-gaps (intro/credits, identiteit, beoordelingen), beheerrestbewijs en S14.3/S14.5 blijven onder hun huidige slices. Gebouwde beheerfuncties krijgen geen tweede Flutter-beheersuite. Kids is een afzonderlijk datasetbesluit. Volledige journeys, off-site herstel, migratiekeuze en vervangingsgate blijven buiten deze implementatieclaim.

## Platformrijen

| Doel | Buildbasis / speler | Bewijs in deze ronde | Fysieke acceptatie |
| --- | --- | --- | --- |
| iOS | `b6ab8b41` + lokale wijzigingen; Debug; mpv-configuratie | iPhone SE-simulator, favoriet via contextmenu naar Mijn Pleya; rapport/beeldmanifest | open |
| tvOS | dezelfde basis; Debug; mpv-configuratie | Apple TV 4K-simulator, `/favorites`, D-pad/focus/back; rapport/beeldmanifest | open |
| iPadOS | geen nieuwe build | geen | open |
| macOS | geen nieuwe build | geen | open |
| Android | geen nieuwe build | geen | open |
| Android TV | geen nieuwe build | geen | open |
| Windows | geen nieuwe build | geen | open |
| Linux | geen nieuwe build | geen | open |

De simulatorjourneys starten geen video en meten geen decoder/HDR/audio. Spoorvoorkeuren zijn via adapter, gedeelde store, track-manager en fake-player bewezen; native playback en de volledige toestelronde blijven open. Detailstatus staat uitsluitend in de masterlijst.
