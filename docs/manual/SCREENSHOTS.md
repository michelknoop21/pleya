# Schotlijst voor de handleiding

De handleiding op <https://pleya.app/docs> verwijst naar afbeeldingen in
`website/static/docs-media/`. Staat een bestand er nog niet, dan tekent de pagina een
plaatshouder op de juiste plek met het gewenste pad eronder. De tekst is zonder beeld al
af, dus een ontbrekende schermafbeelding is geen kapotte pagina.

`/update-docs` somt bij elke run op welke bestanden uit deze lijst nog missen.

## Dit is een eigen ronde

Eenendertig schermafbeeldingen is te veel om tussendoor te doen, en ze vragen iets wat de
tekst niet vraagt: een ingelogd toestel per vormfactor, met de juiste content in beeld. Plan
het als losse contentronde en meng het niet met nieuwe documentatiefuncties, anders blijft
de helft half.

Klaar is: elk bestand uit de tabel hieronder staat in `website/static/docs-media/`, elke
regel in de kolom Klaar staat op ja, en `/docs` toont nergens meer een plaatshouder. Tot die
tijd is de handleiding gewoon bruikbaar; het beeld maakt hem beter, niet werkend.

Een tussenstap die de moeite waard is: de acht hoofdstukken die het meest bezocht zullen
worden (Getting started, The home screen, The player, Downloads, Search, Watchlist,
Requests, Troubleshooting) eerst doen. Dat is elf van de eenendertig schoten.

## Regels voor het beeld

Alleen materiaal dat we mogen tonen. Dat betekent in de praktijk Blender-content
(Sintel, Big Buck Bunny, Tears of Steel, Cosmos Laundromat) en de demo-Jellyfin op
`demo.pleya.app`. Geen posters van commerciële titels, ook niet als ze toevallig in de
bibliotheek staan. Dezelfde grens als bij de App Store Connect-screenshots.

Verder: donker thema (OLED), geen profielnaam of e-mailadres in beeld, geen serveradres
of token zichtbaar, en geen half geladen posters.

## Maken

```bash
# tvOS: simulator draait al via scripts/tvos_sim.sh run
scripts/tvos_sim.sh goto search
scripts/tvos_sim.sh shot                     # print het pad, ligt in $TMPDIR

# iPhone en iPad
xcrun simctl io booted screenshot ~/Desktop/shot.png

# macOS: gewoon cmd-shift-4 met spatie op het venster
```

Daarna bijsnijden op het app-venster, opslaan als PNG in
`website/static/docs-media/<naam>.png` en de regel in de tabel afvinken. Breedte mag
ruim: de pagina schaalt terug naar de kolombreedte.

## Lijst

| Bestand | Hoofdstuk | Toestel | Wat erop moet staan | Klaar |
|---|---|---|---|---|
| `home-overview.png` | What Pleya is | iPhone | Home met billboard en twee rijen eronder, zodat één beeld de app samenvat | nee |
| `signin-choice.png` | Getting started | iPhone | Het keuzescherm met Plex en Jellyfin naast elkaar | nee |
| `jellyfin-connect.png` | Getting started | iPhone | Het Jellyfin-adresveld met een gevonden server eronder | nee |
| `profile-picker.png` | Profiles | Apple TV | "Wie is er aan het kijken?" met drie avatars, één met slotje | nee |
| `home-hero.png` | The home screen | Apple TV | Het billboard bijna schermvullend, met de rij eronder die piept | nee |
| `home-rows.png` | The home screen | iPhone | Verder kijken met voortgangsbalken, plus een Top 10-rij | nee |
| `library-browse.png` | Browsing your libraries | iPad | Bibliotheekraster met de letterbalk aan de zijkant | nee |
| `library-filters.png` | Browsing your libraries | iPad | Het filterpaneel open met twee actieve filters | nee |
| `detail-show.png` | Movie and show details | iPhone | Seriedetail met achtergrondbeeld, knoppenrij en seizoenkiezer | nee |
| `detail-episodes.png` | Movie and show details | iPhone | Afleveringenlijst met een half gekeken aflevering | nee |
| `detail-watched-by.png` | Movie and show details | Desktop | De regel "Bekeken door" met twee avatars en de statistiekregel eronder, op een Blender-titel | nee |
| `player-controls.png` | The player | iPad | Bediening zichtbaar, hoofdstukmarkeringen op de tijdbalk | nee |
| `player-scrub.png` | The player | Apple TV | Voorbeeldminiatuur tijdens het spoelen met de remote | nee |
| `player-tracks.png` | Subtitles and audio | iPhone | Het sporenmenu met audio- en ondertitelkeuze | nee |
| `subtitle-styling.png` | Subtitles and audio | macOS | Ondertitelopmaak met de voorbeeldregel eronder | nee |
| `downloads-manage.png` | Downloads and offline | iPhone | Downloads-tab met één lopende en één afgeronde download | nee |
| `sync-rules.png` | Downloads and offline | iPhone | Een sync-regel op een serie, met het aantal afleveringen | nee |
| `livetv-guide.png` | Live TV and recordings | Apple TV | De gids met tijdvakken en een gemarkeerde favoriet | nee |
| `livetv-recordings.png` | Live TV and recordings | macOS | Opnames met een geplande opname erbij | nee |
| `search-results.png` | Search | iPhone | Zoekresultaten over twee servers heen | nee |
| `search-tv.png` | Search | Apple TV | Het systeemtoetsenbord open boven de resultaten | nee |
| `my-pleya.png` | Watchlist and My Pleya | iPhone | Mijn Pleya met de profielavatar bovenaan en de ingangen eronder | nee |
| `watchlist-grid.png` | Watchlist and My Pleya | iPad | Kijklijstraster met een gemengde Plex- en Jellyfin-inhoud | nee |
| `requests-discover.png` | Requests | iPhone | Discover in Verzoeken met statusbadges op de posters | nee |
| `requests-status.png` | Requests | iPhone | Een aanvraag in behandeling naast een beschikbare | nee |
| `watch-together.png` | Watch Together | macOS | Sessiescherm met de code van vijf tekens en twee deelnemers | nee |
| `share-host.png` | Pleya Share | iPhone | Het hostscherm met de QR-code | nee |
| `share-library.png` | Pleya Share | iPad | De gedeelde bibliotheek zoals een guest hem ziet | nee |
| `tv-sidebar.png` | Apple TV and remotes | Apple TV | De uitgeklapte zijbalk met de focusring op één item | nee |
| `settings-overview.png` | Settings reference | macOS | Instellingen met de icoonbadges per rij | nee |
| `settings-playback.png` | Settings reference | iPhone | Video afspelen, met kwaliteit en hardwaredecodering zichtbaar | nee |
| `logs-screen.png` | Troubleshooting | iPhone | Instellingen, Logs, met de uploadknop | nee |
