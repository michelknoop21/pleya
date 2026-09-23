# Netflix-redesign: ontwerpaudit en aanpak voor verbetering

Datum: 23 september 2026. Onderzochte checkout: `6052e824`, met bestaande lokale documentwijzigingen.
Status: **eerste vier ontwerprichtingen goedgekeurd** door Michel op 23 september, met de expliciete kanttekening dat dit nog niet alle vensters zijn. Tranche 1 mag starten; de volledige runtime-audit en pakketten B–F blijven open.

## Doel en grenzen

Michel vindt Home al de gewenste richting. Behoud de compositie en onderzoek daar alleen uitbreiding van de hero-selectie. Maak overige schermen visueel en in bediening consistent, inclusief vensters die nog geen volledige redesign kregen. Geen bestaande functie of item mag verdwijnen. Eerst concrete mockups beoordelen, daarna implementeren.

Voorlopig is tvOS het onderzoeksanker, omdat het Netflix-IA-plan daarop betrekking heeft. Na akkoord is tvOS als eerste ronde gestart; mobiel en desktop blijven buiten deze eerste ronde. De onderstaande inventaris is een controlelijst, geen bewering dat ieder genoemd scherm nog ongebouwd is.

De bestaande [design-index](../../DESIGN-INDEX.md), [closure](../../unified-2026-closure.md), [redesignregister](../../tvos-redesign-register.md) en [correctieronde](../../tvos-fysieke-correctieronde.md) blijven autoriteit. Dit voorstel vervangt TV0–TV8 niet en kent bestaande items geen nieuwe status toe.

## Wat het oorspronkelijke ontwerp wilde bereiken

Content als hoofdingang; horizontale TV-navigatie; Home met grote beeldvullende hero en direct zicht op Verder kijken; Films en Series met redactionele landings én bereikbare volledige catalogi; Mijn Pleya voor persoonlijke en beheertaken. Eén herkenbare kaart-, focus- en paneeltaal, behoud van bronkeuze en betrouwbare terugnavigatie.

Home volgt mockup 30 / DEC-095, niet de inmiddels deels vervangen afgeronde hero uit northstar 01. Detail volgt 09/10 met correcties uit 37; spelerinformatie volgt 33 in plaats van 19. Oude mockups blind namaken zou goedgekeurde wijzigingen terugdraaien.

## Vaststellingen uit deze verkenning

| Onderwerp | Bewijs | Betekenis |
|---|---|---|
| Hero maximaal acht | `FeaturedSelector(maxCount: 8)` in `lib/services/unified_catalog/featured_selector.dart` | Eerst aantal kandidaten meten; een hogere limiet helpt alleen als er meer geschikte titels zijn. |
| Hero bewust alleen recente films | `TvHomeProjectionProvider` projecteert alleen `latestMovies` naar de selector; DEC-067 | Series/Top Picks toevoegen is een inhoudelijke ontwerpwijziging, geen simpele limietfix. |
| Oudere Home-compositie visueel bekeken | Mockup `30-home-a1.png` en screenshot plus PASS-report uit `.build/pleya-verify/tvos-home-full-bleed-1788545268365/` | Ondersteunt de richting, bewijst niet de huidige checkout. Fixture-artwork is geen basis voor een oordeel over echte beeldkwaliteit. |
| Actueel beeldbewijs ontbreekt in recente smoke-run | `tvos-smoke-boot-1790182966526/report.md`: screenshot geweigerd als leeg | Geen nieuwe GUI-bug afleiden uit dit infrastructuurprobleem. Doctor meldt momenteel build/idb beschikbaar; dit bewijst nog geen geslaagde capture. |
| Gebouwd is niet overal visueel geverifieerd | Register MOC-18/33, 23/24/25 en SYS-7 | Eerst huidige oppervlakken bekijken, niet opnieuw ontwerpen op grond van een open bewijsstatus. |
| Bestaande UX-risico’s zijn al geregistreerd | OFF5, SYS-3c/d/e, LIVE2 en hardware-items in correctieronde | Reproduceren en aan bestaande eigenaar koppelen; niet als nieuw gevonden defect presenteren. |
| Mockup en beschikbare functies verschillen soms | Register MOC-24/25 en MOC-18 | Geen fictieve sorteeropties, biografie, unified personen of verdwenen spelerknoppen ontwerpen. |

## Drie mogelijke aanpakken

1. **Aanbevolen: bestaande richting afmaken.** Maak een volledige functiematrix, beoordeel actuele schermen en ontwerp uitsluitend de gaten en inconsistente onderdelen. Kleinste risico op functieverlies en sluit aan bij Home.
2. Alleen bugs en bewijsachterstand sluiten. Snelste stabilisatie, maar vensters met een afwijkende visuele taal blijven bestaan.
3. Alle schermen opnieuw ontwerpen. Grootste vrijheid, maar veel herwerk en regressierisico; past slecht bij het expliciete behoud van Home.

## Voorgestelde werkvolgorde

### 1. Schermen en functies vastleggen

Maak per route een rij met: platform, toegangspad, huidig beeld, geldend doelbeeld, zichtbare informatie, alle acties en contextacties, backend/capability, focus/Back, loading/leeg/fout/offline, bestaand testbewijs en bestaand werkitem. Controleer ook verborgen capability- en rechtenafhankelijke acties.

Neem minimaal mee:

- Home, hero, Verder kijken, rij-overzichten, Films/Series-landings en volledige catalogi.
- Zoeken, personenresultaten, Ontdekken, filters, sortering, bron- en bibliotheekselectie.
- Film/serie/afleveringdetail, seizoenen, synopsis, cast, extra’s, versies, bronkeuze en contextmenu’s.
- Kijklijst/favorieten, aanvragen en aanvraagdetails, collecties, playlists en personen.
- Mijn Pleya, bibliotheken en hun tabs, servers/verbindingen, activiteit, Samen kijken en Remote-hostbereikbaarheid.
- Profielkeuze, profielbeheer/PIN, inloggen, eerste start, verbindingsformulieren en herstel.
- Instellingen plus alle onderpagina’s en pickers, logs, Over en licenties.
- Speler-OSD, informatiepaneel en alle tabs, hoofdstukken/afleveringen, audio/ondertitels, snelheid/beeldverhouding, autoplay en foutmeldingen.
- Live TV, gids, favorieten, opnames, opnameregels, programmadetails en bevestigingen.
- Offline, reconnect, downloads/synchronisatieregels waar ondersteund, destructieve bevestigingen en tijdelijke meldingen.

Een gedeelde Flutter-screen is niet automatisch een niet-geredesigned scherm: controleer zijn TV-tak. Markeer functies die een platform niet ondersteunt expliciet als niet van toepassing met reden.

### 2. Actuele visuele en interactieve audit

Gebruik Pleya Verify op de afgesproken platformen. Lees report, UI-tree en echte compositorbeelden samen. Beoordeel tekstdichtheid, contrast, leesafstand, afsnijding, focusringen, lege ruimte, geselecteerde versus gefocuste staat, scrollankers, overlays, Back en herstel na detail/speler. Test weinig én veel content, lange Nederlandse labels, ontbrekende artwork, meerdere bronnen en uitvallende verbindingen.

Leg bevindingen vast als bevestigd defect, ontwerpverschil, verbetervoorstel of ontbrekend bewijs. Behoud hardware-only status voor Siri Remote/touch-input en afspeelgedrag dat simulatoren niet bewijzen.

### 3. Mockups ter beoordeling

Gebruik de bestaande ontwerpbron en tokens. Toon per verandering het actuele scherm, voorstel en functielijst naast elkaar. Lever ook focus-, scroll- en lege/foutstaat waar die de bediening veranderen; een mooi rustbeeld is onvoldoende.

Eerste pakket: Home met huidige selectie versus voorstel voor maximaal twaalf recente films (voorstel, geen besluit), plus een alternatief met expliciet benoemde aanbevelingen als bredere inhoud gewenst is. Meet vooraf of de kandidaatpool uitbreiding toelaat. Behoud ontdubbeling, profielzichtbaarheid, stabiele selectie, beperkte artwork-prefetch en instellingen voor automatische wissel/verminderde beweging.

Tweede pakket: de slechtst aansluitende beheer- en subvensters uit de audit. Prioriteit op Mijn Pleya-doorklikken, formulieren/pickers en overlays; definitieve selectie op actuele beelden, niet op bestandsnamen.

Derde pakket: gerichte correcties aan detail/catalogus/speler/Live TV, alleen waar de huidige audit een aantoonbaar gat aanwijst. Bestaande goedgekeurde composities blijven basis.

### 4. Functiebehoud aantonen

Elke bestaande actie krijgt een bestemming in het nieuwe ontwerp en een passende controle. Bij spelerwijzigingen expliciet hoofdstukken, afleveringnavigatie, afspeelinstellingen en beeldverhouding behouden. Bij bronafhankelijke acties Plex én Jellyfin controleren; ontbrekende API-capabilities niet verbergen achter decoratieve knoppen. Onbesliste acties blokkeren goedkeuring van het betreffende scherm.

### 5. Na ontwerpgoedkeuring implementatie plannen

Werk goedgekeurde pakketten uit met Superpowers writing-plans, met exacte eigenaren, regressietests en Verify-journeys. Sluit aan op de bestaande TV0–TV8-verdeling. Reproduceer bugs vóór fixes en bewijs de negatieve controle. Voer per implementatie `scripts/ci_checks.sh`, toepasselijke tests en passende Verify-assertions met visuele inspectie uit. De gezamenlijke hardware/releasegate blijft staan.

## Uitvoeringsstatus

De eerste vier concrete ontwerpen zijn goedgekeurd. De uitvoering begint met het [plan voor tranche 1](../plans/2026-09-23-netflix-redesign-tranche-1.md): hero-uitbreiding en de ontbrekende persoonlijke ingangen. Dit akkoord sluit de audit niet; de overige instellingen, formulieren, detail-, catalogus-, speler- en Live TV-oppervlakken blijven als volgende pakketten open. Twee actuele audit-/formulierwandelingen zijn PASS; resterende platform-, backend- en hardwaredekking staat in de actuele audit expliciet open.

## Verduidelijking van Michel

Bestaande mockups kunnen achterlopen op de werkelijke app. De draaiende huidige build is daarom de nulmeting; broncode helpt de functie-inventarisatie en eerdere ontwerpen verklaren intentie. Geen bestaand mockupbeeld wordt als actuele screenshot gepresenteerd.
