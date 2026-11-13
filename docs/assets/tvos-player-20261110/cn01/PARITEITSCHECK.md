# Pariteitscheck cn01 — draft met benoemde gaten

De actuele bron is na de schets opnieuw gecontroleerd. Per functie verwijzen ID, bron/conditie en trigger naar FUNCTIONALITEITEN.md; de laatste kolom is de actuele mockupuitkomst, geen claim van productimplementatie.

- 01: **partial** — Hoofdbeeld en Info. Verwachte echte uitkomst: Info zichtbaar bij bediening.
- 02: **partial** — Info / Afspeelinformatie. Verwachte echte uitkomst: Info → actuele afspeelgegevens.
- 03: **partial** — Tijdlijnstatus + hardware Play/Pause. Verwachte echte uitkomst: Select of remote → pauzestatus.
- 04: **partial** — Tijdlijn; detailgestures nog uitwerken. Verwachte echte uitkomst: Links/rechts → positie verandert.
- 05: **partial** — Meer → Afspelen. Verwachte echte uitkomst: Select → mediawissel.
- 06: **partial** — Meer → Hoofdstuk overslaan. Verwachte echte uitkomst: Select → hoofdstukpositie.
- 07: **partial** — Hoofdbeeld / state=scrub. Verwachte echte uitkomst: Scrub → preview en tijd; commit → seek.
- 08: **partial** — Audio-paneel. Verwachte echte uitkomst: Audio → track → player/backendselectie.
- 09: **partial** — Audio → detailinstellingen. Verwachte echte uitkomst: Waarde/offset → afspeelaudio.
- 10: **missing** — Audio → uitvoer; nog tekenen. Verwachte echte uitkomst: Keuze → ondersteunde uitvoer; niet beschikbaar bij bitstream.
- 11: **partial** — Ondertitelpaneel. Verwachte echte uitkomst: Ondertitels → track → zichtbare selectie.
- 12: **missing** — Ondertitels → zoeken; nog tekenen. Verwachte echte uitkomst: Zoeken → bestaande zoekroute.
- 13: **partial** — Ondertitelpaneel / stijl. Verwachte echte uitkomst: Waarde wijzigen → rendering.
- 14: **partial** — Meer → Beeldinstellingen; nog tekenen. Verwachte echte uitkomst: Keuze → letterbox/fill/stretch, zoom.
- 15: **partial** — Meer → Beeldinstellingen; nog tekenen. Verwachte echte uitkomst: Instellen → bestaande renderer en verlichting.
- 16: **partial** — Meer → Snelheid. Verwachte echte uitkomst: Waarde → afspeelrate.
- 17: **partial** — Hoofdstukken-paneel. Verwachte echte uitkomst: Hoofdstuk → seek en returnfocus.
- 18: **missing** — Meer → Beeldinstellingen; nog tekenen. Verwachte echte uitkomst: Keuze → geselecteerde versie/kwaliteit.
- 19: **partial** — Meer → Slaaptimer. Verwachte echte uitkomst: Instellen → timer; annuleren → uit.
- 20: **partial** — Meer → Pleya Fly. Verwachte echte uitkomst: Apparaatkeuze → bestaande overdracht/Meenemen-status.
- 21: **missing** — Meer → Afspelen; nog tekenen. Verwachte echte uitkomst: Toggle → bestaande voorkeur/rendering.
- 22: **partial** — Wachtrij-paneel. Verwachte echte uitkomst: Media → bestaande wachtrijselectie.
- 23: **partial** — Rechter glasactie. Verwachte echte uitkomst: Select → systeem-PiP.
- 24: **missing** — Nog aparte markerstaat tekenen. Verwachte echte uitkomst: Marker → tijdelijke overslaanknop; auto reactie volgens settings.
- 25: **missing** — Nog aparte Live-variant tekenen. Verwachte echte uitkomst: Live-edgeactie → actuele uitzending.
- 26: **partial** — Keyboarddemo; native gedrag niet bewezen. Verwachte echte uitkomst: D-pad → focus; Menu → laag terug; auto-hide.
- 27: **partial** — Big P-knop; geen nieuwe AI-functie. Verwachte echte uitkomst: Big P → bestaande assistent.
- 28: **partial** — Lege wachtrij getoond; rest nog tekenen. Verwachte echte uitkomst: Bronstatus → bestaande loading/retry/disabled.

Visueel: hoofdbeeld, focusAudio, audio en Meer lokaal in Chrome geopend over127.0.0.1:8766. Er is één focuswinnaar; back keert naar vorige knop. Audiopaneel heeft uitgewerkte voorbeeldtracks; geselecteerde secundaire tekstcontrast na eerste inspectie verbeterd. Stage behoudt1920×1080-logica; telefoon is kijker van dat TV-beeld, geen iOS-appvoorstel. Native afstandsbediening, state persistence, auth/capabilities, Live, fout/loading, alle geavanceerde subviews en ReduceTransparency nog niet getest/uitgetekend. Geen parity verified en geen implementatie-authority.

Informatie/acties: gedeeltelijk; bovengenoemde missing/partialroutes moeten vóór goedkeuring worden uitgewerkt. Rechten/datascope: bronmatig behouden als verplichting, niet live getest. Runtime: HTMLfocusdemo, geen playback of overdracht. Onafhankelijke kritiek nog in uitvoering.

Telefoonpolish na onafhankelijke kritiek: focus gebruikt preventScroll zodat de collectie niet naar de onderste iframe springt. Er is nu een aanraakbare sluitknop en een afzonderlijke44px-bekijkbalk op de telefoon. De productknoppen worden niet opgeblazen: het blijft een tvOS-ontwerp op1920×1080.

Exacte open runtimeverplichtingen: Audio-selectie moet de huidige track en uitvoer aanpassen; hoofdstukselectie moet seeken; PiP moet het systeemvenster starten; tijdlijn moet play/pause/seek-toestanden doorlopen. Deze conceptschets toont de plek en de panelen, maar voert die effecten nog niet uit. Geen afgevinkte functiepariteit.

Tweede telefoonpolish: de bekijkbalk staat in de normale paginastroom onder het TV-frame, nooit erover. In ingebedde previews is die balk verborgen. In landscape kan de telefoonreviewpagina scrollen naar de44px-knoppen, het TV-frame zelf behoudt16:9 en krijgt geen eigen scroll. Onafhankelijke hercontrole loopt.

De collectie toont exports van de onafhankelijk beoordeelde1920×1080focus-/Meerbeelden als zoomafbeelding in plaats van ingesloten demos. De afzonderlijke links openen nog dezelfde touchbedienbare reviewviewer. Afbeelding openen en inzoomen werkt zonder kleine TV-knoppen op een telefoonscherm te hoeven raken.
