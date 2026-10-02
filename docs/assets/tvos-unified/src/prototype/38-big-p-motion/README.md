# Big P, motion-prototype bij mockup 38

Een klikbaar, zelfspelend prototype van de Big P-schermen op Apple TV. Het beeld is 1920 x 1080 en schaalt mee met het browservenster. Status: voorstel, geen bouwopdracht.

## Openen

Dubbelklik `index.html` (Chrome of Safari, rechtstreeks van schijf). Er is geen server nodig en er wordt niets van internet geladen; Inter staat in `assets/`.

Onder het tv-beeld staat de bediening: Pauze/Afspelen, Volgende stap, een knop per scene, "Lang drukken Play/Pause" (roept Big P op in scene 0 en 0c) en "Minder beweging". Die laatste doet hetzelfde als de systeeminstelling voor minder beweging.

`index.html?scene=4` begint bij een scene. `index.html?still=4` stopt op het sleutelmoment van die scene; zo zijn de stills gemaakt.

## Scenes

| Nr | Naam | Wat je ziet |
|----|------|-------------|
| 0 | Oproepen | Films-catalogus op Zolder. Na lang drukken op Play/Pause komt Big P rechtsonder in beeld, het systeemtoetsenbord schuift omhoog en het scherm erachter dimt licht. Gedicteerd: "Scan deze bibliotheek opnieuw." Big P weet welk scherm open staat. Daarna twee stappen, een resultaatkaart met lopende voortgang, en Big P schuift weer weg. |
| 0c | Oproepen, bevestiging | Zelfde ingang, nu een gevoelige actie ("Geef Sam ook toegang tot deze bibliotheek."). De Pleya-kaart staat midden over het gedimde scherm, Big P blijft in de hoek tot de kaart is afgehandeld. |
| 1 | Rust | Mijn Pleya ▸ Big P. Begroeting, een chip met de twee mislukte taken op Zolder, "Vraag Big P" en drie voorbeeldvragen. Rechtsboven een statusstrook met de drie servers en een taak waarvan het percentage oploopt. |
| 2 | Luisteren | Toetsenbord met dicteren; de vraag komt woord voor woord binnen en Big P knikt mee, hoogstens eens per seconde. |
| 3 | Werken | Statusregel die meeloopt ("Zolder controleren…", "Taken opnieuw starten…") en een stappenlijst die per server rij voor rij afvinkt. Annuleren heeft de focus. |
| 4 | Resultaat | Big P lacht en knikt een keer. Pleya-kaart met de twee herstarte taken; de scanbalk loopt. Vervolgknoppen "Laat zien wat er misging" en "Melden als het klaar is". |
| 5 | Gebruiker aanmaken | "Maak Sam aan op Woonkamer, alleen Kids en Tekenfilms." Drie controlestappen, dan een bevestigingskaart voor het hele doel met focus op Annuleren. De focus gaat naar Aanmaken, daarna volgt het resultaat. |
| 6 | Fout | Zolder staat offline in de statusstrook. De verbinding mislukt, Big P kijkt bezorgd en zakt een keer licht door, en de foutkaart zegt dat er niets veranderd is. |

De stills staan in `docs/assets/tvos-unified/mockups-2026-10-02-big-p/motion/` als `38-motion-0.png` (opgeroepen, toetsenbord omhoog), `38-motion-0b.png` (compact resultaat) en `38-motion-1.png` tot en met `38-motion-6.png`.

## Wat echt is en wat nagebootst

Echt laagwerk (`bigp.js`): het lichaam, vier monden, beide wenkbrauwen en de oogleden zijn losse lagen uit `~/.claude/skills/big-p/avatar/lagen/`, op de helft verkleind en geplaatst op de maten uit `bigp-layers.json`. De oogleden worden getekend in de lidkleur per oog, geknipt op de oogellips, met een gebogen rand en een wimperlijn. De beweging volgt het Motion-hoofdstuk van `docs/tvos-redesign-38-big-p-proposed.md`: ademen (schaal 1,000 tot 1,012 in 4 s), knipperen om de 3 tot 6 s, af en toe 1,5 graad scheef in rust, 3 graden naar rechts met 2 tot 4 graden heen en weer tijdens werken, een knik van 600 ms bij succes, een zak bij een fout. Overgangen volgen met een tijdconstante van 120 ms; monden wisselen met een crossfade van 120 ms. Met minder beweging staan ademen, knipperen, kantelen en knikken uit en wisselen alleen mond en wenkbrauwen.

Nagebootst: alle serverdata, taken, percentages, tijden en de stappen van Big P. Het toetsenbord is een benadering van het tvOS-toetsenbord, zoals in 38 E. De catalogus gebruikt titels van open films van Blender met kleurvlakken in plaats van posters.

Er is geen pupillaag. Kijken naar het resultaat is daarom een kanteling van de hele figuur.
