# cn01 · tvOS-afspeler — concept, geen goedgekeurde North Star

Roadmap A-10. Bronbasis824f18399 met actuele lokale correcties; live bewijs zijn Michels TV-foto’s van10november2026 en directe Mac-observatie (geen native tvOS-bedieningstest). Referentie: actuele Apple-gebruikershandleiding, https://support.apple.com/guide/tv/control-video-playback-atvb7944597f/tvos . Scope: presentatie van alleen de tvOS-speler; afspeelengine, rechten, profiel/serverbereik, iOS en appnavigatie ongewijzigd. Bestaande account/capabilityvoorwaarden blijven verplicht. Geen credentials of echte bibliotheekdata in de demo.

Operator: kijker op bank met Siri Remote. Primair: film blijven zien, pauze/seek; secundair: taalkeuze. Hiërarchie: video → titel/tijdlijn → taalacties → overige routes. Vormfamilie: cirkels66pt, tekstcapsules58pt, marge90pt op1920×1080, één lichte focuswinnaar, bestaand Inter en Pleya-mark. Wit/grijs glas volgt Apple; rood#E5140F blijft Pleya-accent, geen rode focusglow. Dark/OLEDcontext; Light/ReducedTransparency/native rendering niet getest.

Deze catalogus is bij toepassing van de expliciet aangeroepen skill gemaakt vóór verdere herziening van de eerste schets; v1.html bewaart die eerdere poging. Elke native actie hieronder is in HTML slechts gesimuleerd; netwerk/effecten worden niet uitgevoerd.

| ID | Bestaande functie | Bron/conditie (lib/widgets/video_controls tenzij anders) | Trigger → resultaat | Nieuwe plek | Dekking |
|---|---|---|---|---|---|
| 01 | Titel, aflevering, speelduur en eindtijd | desktop_video_controls.dart / metadata | Info zichtbaar bij bediening | Hoofdbeeld en Info | simulated |
| 02 | Resolutie, codec, audioformaat, taal, direct play/transcode | widgets/tv_quality_summary_line.dart; tv_information_tab.dart | Info → actuele afspeelgegevens | Info / Afspeelinformatie | partial |
| 03 | Play/pause | desktop_video_controls.dart:1231; remote Play/Pause | Select of remote → pauzestatus | Tijdlijnstatus + hardware Play/Pause | simulated |
| 04 | Terug/vooruit met ingestelde seekTimeSmall | desktop_video_controls.dart:1217/1258 | Links/rechts → positie verandert | Tijdlijn; detailgestures nog uitwerken | partial |
| 05 | Vorige/volgende media, alleen als callback beschikbaar | desktop_video_controls.dart:1180/1307 | Select → mediawissel | Meer → Afspelen | partial |
| 06 | Vorig/volgend hoofdstuk, alleen met chapters | desktop_video_controls.dart:1195/1287 | Select → hoofdstukpositie | Meer → Hoofdstuk overslaan | partial |
| 07 | Tijdlijn, buffer, hoofdstukpreview en scrubbing | widgets/video_timeline_bar.dart; desktop_video_controls.dart | Scrub → preview en tijd; commit → seek | Hoofdbeeld / state=scrub | simulated |
| 08 | Audio trackselectie inclusief huidige en bronspecifieke tracks | tv_audio_subtitle_tabs.dart:135-195 | Audio → track → player/backendselectie | Audio-paneel | simulated |
| 09 | Audiovolume/boost en vertraging | tv_audio_subtitle_tabs.dart:240-252 | Waarde/offset → afspeelaudio | Audio → detailinstellingen | partial |
| 10 | Audio-uitvoer, prioriteit, levelvolume, reduce loud sounds; passthroughbeperking | tv_audio_subtitle_tabs.dart:265-371 | Keuze → ondersteunde uitvoer; niet beschikbaar bij bitstream | Audio → uitvoer; nog tekenen | missing |
| 11 | Ondertitels uit/track, deferred loading | tv_audio_subtitle_tabs.dart:482-537 | Ondertitels → track → zichtbare selectie | Ondertitelpaneel | partial |
| 12 | Ondertitels zoeken indien capability/rechten | tv_audio_subtitle_tabs.dart:550 | Zoeken → bestaande zoekroute | Ondertitels → zoeken; nog tekenen | missing |
| 13 | Ondertitelvertraging, tekstgrootte en achtergrond | tv_audio_subtitle_tabs.dart:566-596 | Waarde wijzigen → rendering | Ondertitelpaneel / stijl | partial |
| 14 | Beeldverhouding en zoom | tv_video_tab.dart:168-196 | Keuze → letterbox/fill/stretch, zoom | Meer → Beeldinstellingen; nog tekenen | partial |
| 15 | HDR, shaders en ambient light, platform/capabilitygebonden | tv_video_tab.dart:211-258 | Instellen → bestaande renderer en verlichting | Meer → Beeldinstellingen; nog tekenen | partial |
| 16 | Afspeelsnelheid | tv_video_tab.dart:279 | Waarde → afspeelrate | Meer → Snelheid | partial |
| 17 | Hoofdstukkenlijst met huidige positie | tv_video_tab.dart:304 | Hoofdstuk → seek en returnfocus | Hoofdstukken-paneel | simulated |
| 18 | Versie/kwaliteit, alleen met beschikbare versies/transcoding | tv_video_tab.dart:325 | Keuze → geselecteerde versie/kwaliteit | Meer → Beeldinstellingen; nog tekenen | missing |
| 19 | Slaaptimer uit/einde video/minuten | tv_video_tab.dart:346 | Instellen → timer; annuleren → uit | Meer → Slaaptimer | partial |
| 20 | Pleya Fly met canHandoff en bestaand profiel/serverbereik | tv_video_tab.dart:369; tv_pleya_fly_sub_view.dart | Apparaatkeuze → bestaande overdracht/Meenemen-status | Meer → Pleya Fly | partial |
| 21 | Autoplay volgende en statistiekoverlay | tv_video_tab.dart:382-397 | Toggle → bestaande voorkeur/rendering | Meer → Afspelen; nog tekenen | missing |
| 22 | Wachtrij indien queue actief | widgets/content_strip.dart | Media → bestaande wachtrijselectie | Wachtrij-paneel | simulated |
| 23 | Beeld in beeld indien ondersteund | widgets/track_chapter_controls.dart | Select → systeem-PiP | Rechter glasactie | simulated |
| 24 | Intro/credits overslaan met bestaande markers en auto-skipvoorwaarden | video_controls.dart:1081; widgets/skip_marker_button.dart | Marker → tijdelijke overslaanknop; auto reactie volgens settings | Nog aparte markerstaat tekenen | missing |
| 25 | Live-tv, terug naar live, capturebufferbeperkingen | desktop_video_controls.dart:1273; widgets/live_timeline_bar.dart | Live-edgeactie → actuele uitzending | Nog aparte Live-variant tekenen | missing |
| 26 | Remote focus, Menu/back, auto-hide, locked remotecontrol | parts/key_events.dart; desktop_video_controls.dart _canControl | D-pad → focus; Menu → laag terug; auto-hide | Keyboarddemo; native gedrag niet bewezen | partial |
| 27 | Big P bestaande assistentactie en settingsgate | widgets/track_chapter_controls.dart; huidige TV-foto | Big P → bestaande assistent | Big P-knop; geen nieuwe AI-functie | partial |
| 28 | Laden, fouten, ondertitels deferred, geen volgende media | video_controls.dart; tv_deferred_subtitle_row.dart | Bronstatus → bestaande loading/retry/disabled | Lege wachtrij getoond; rest nog tekenen | partial |
