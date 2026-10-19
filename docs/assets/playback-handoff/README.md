# Playback Handoff, northstar-voorstel

Roadmap: A-23. Status: voorstel (19 oktober 2026), wacht op akkoord van Michel. Geen implementatie of hardwarebewijs.

Zes iPhone-staten (`board-phone.html`, 874x402 landscape op ware grootte) en twee tvOS-staten (`board-tv.html`,
1880x1058). Tokens, fonts en kaartstijl komen uit `../tvos-unified/src/tv.css` en `../ios-unified`.
Render: `pw screenshot --viewport-size=1800,1500 --full-page board-phone.html board-phone.png`.

| Code | Scherm | Staat |
|---|---|---|
| H1 | iPhone speler | knop naast Cast en AirPlay |
| H2 | sheet | Apple TV's kiezen |
| H3 | sheet | bezig, iPhone blijft spelen |
| H4 | speler | mislukt, iPhone speelt verder |
| H5 | detail | gelukt, speler gesloten |
| H6 | sheet | geen Apple TV gevonden |
| T1 | tvOS speler | ontvangen, melding met bron |
| T2 | tvOS ander scherm | melding voor start |
