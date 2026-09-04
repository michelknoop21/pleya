# tvOS-mockups 09 tot en met 25: CANDIDATE-set

Status op 3 september 2026: **candidate**. Geen northstar, niet goedgekeurd, geen
implementation authority. Elke mockup wordt eerst tegen de actuele branch en productiecode
geauditeerd. Het auditrapport met de eindmatrix staat in `01-code-parity-audit.md`: geen enkel
beeld is approval-ready, zestien vragen revisie en vijftien productbesluiten staan open. De
correcties die geen besluit nodig hadden zijn al in de HTML en de PNG's doorgevoerd.

Datum van de beelden: 3 september 2026. Zeventien beelden op 1920x1080, genummerd 09 tot en met 25 omdat
ze aansluiten op de acht northstar-schermen (01 tot en met 08) in
`docs/assets/tvos-unified/northstar/` op de branch `claude/netflix-redesign-b4x21v`
(worktree `pleya-teleport`). De Mijn Pleya-secties Instellingen-index, Bibliotheken, Servers,
Over, Logs en Samen Kijken hebben al mockups van 2 september in
`docs/assets/tvos-unified/mockups-2026-09-02/`; die zijn hier bewust niet overgedaan.

Alle beelden zijn HTML tegen dezelfde tokens, geschoten met headless Chromium, met echt
TMDb-artwork. De getoonde titels zijn niet bindend, de UI eromheen wel.

## Waarom deze schermen

Dit zijn de tvOS-oppervlakken die nog geen beeld in de nieuwe taal hadden. De code-inventaris
en de openstaande bevindingen uit `docs/tvos-fysieke-correctieronde.md` wijzen dezelfde kant op:
detail, contextmenu en overlays (OVR1, BACK1, FOC1, ART1), de Mijn Pleya-bestemmingen die nog
op desktop- of mobiele layouts draaien (Kijklijst, Aanvragen, Activiteit), en de schermen
buiten de shell (speler, profielkiezer, inloggen, offline-staat).

| Nr | Scherm | Wat het beeld vastlegt | Bron in de baseline |
|----|--------|------------------------|---------------------|
| 09 | Filmdetail | Backdrop met lokale scrim links, geen zoom (ART1), witte Hervatten-CTA met resttijd, bronregel met Wijzigen, geen zichtbare terugknop (BACK1) | hoofdstuk 15 |
| 10 | Seriedetail | Zelfde kop, seizoenchips, afleveringenrail 16:9; alleen de gefocuste aflevering draagt synopsis | hoofdstuk 15, 33.4 |
| 11 | Bronkeuze | Source picker via Wijzigen: witte ring, geen Emby, geen "Onthoud mijn keuze", één markering per rij, auth-fout in amber | hoofdstuk 14, DEC-064 |
| 12 | Contextmenu | Compacte sheet van 760 breed binnen de veilige zone (OVR1), groepsacties uit het contract, Bron wijzigen onderaan | hoofdstuk 23 |
| 13 | Zoeken | Zoekveld, native toetsenbord schematisch, secties Films en Collecties; titel onder de kaart is het open SEARCH1-besluit | hoofdstuk 16 |
| 14 | Kijklijst | Catalogusgrid van 33.5 met de bestaande chips Alles, Films, Series, Beschikbaar en de sorteerchip; aanvragen zit in de item-sheet | hoofdstuk 20 |
| 15 | Aanvragen | Seerr in de railtaal, status als capsule op de kaart, eigen aanvragen als rij eronder | hoofdstuk 20 |
| 16 | Nu aan het kijken | Sessies als kaarten; servertaken als open vraag; Samen Kijken en Pleya Remote staan er niet in | hoofdstuk 18.2, DEC-070 |
| 17 | Live TV | Gids met nu-lijn, favorieten, opnamemarkering, detailbalk onderaan | hoofdstuk 19 |
| 18 | Speler | OSD tijdens intro: witte Intro overslaan, rode progreslijn, hoofdstukmarkers, geen rode knoppen | hoofdstuk 8.2, 34 |
| 19 | Speler-infopaneel | Na veeg omlaag: audio, ondertitels en stijl in drie kolommen; vervangt het paneel met de hardcoded oude accentkleur | hoofdstuk 34.2 |
| 20 | Instellingen, Uiterlijk | Subpagina: themakeuze als tegels, dichtheid als stappen, schakelaars als rijen, live voorbeeld | audit 2 september |
| 21 | Profiel kiezen | Wie kijkt er, vier profielen op een rij, slot op een PIN-profiel | hoofdstuk 22 |
| 22 | Inloggen | Eerste start met Plex en Jellyfin, QR-flow rechts, Jellyfin-uitweg tijdens het wachten | hoofdstuk 21.1 |
| 23 | Offline | Alle servers offline met momentopname, serverlijst met auth-fout in amber | hoofdstuk 21.2, 21.5 |
| 24 | Collectie | Concreet serveritem met bron in de kop; geen cross-server merge | hoofdstuk 31.8 |
| 25 | Persoon | Filmografie als rail, rol op de kaart | geen hoofdstuk, afgeleid van 33.3 |

## Wat overal hetzelfde is

Topnav op y 44 tot 96 met de cluster gecentreerd, profielchip links, wordmark-lockup rechts,
pagina-inset 75 (catalogusgrid 56), achtergrond `#141414`, oppervlakken `#1F1F1F` en `#2F2F2F`,
focus als witte ring van 4 op een gap van 8, artwork schaalt 1,05 bij focus, menutegels en
rijen schalen niet. Rood `#E5140F` alleen als progreslijn en op de opnamemarkering, amber
`#FFB020` alleen als semantisch punt (auth-fout, nieuwe aflevering, aanvraagstatus). Elke
primaire actie is een witte capsule.

De speler (18 en 19) en de schermen vóór de shell (21, 22) tonen geen topnav. Detail en
collectie houden hem staan, gedimd achter een overlay.

Op het OLED-thema is de achtergrond `#000000` in plaats van `#141414`; de mockups van
2 september zijn daarop gemeten. Verder verandert er niets.

## Open besluiten

De vijftien productbesluiten staan genummerd onderaan `01-code-parity-audit.md`. De drie die de
hele set raken: topnav op gepushte routes, de zichtbare terugknop (BACK1), en broncoverage
buiten de bronkiezer. Samen Kijken blijft een aparte surface; de mockup van 2 september blijft
daarvoor de autoriteit.

## Opnieuw bouwen

```
cd ~/Downloads/mockups-tvos/_src
node build.mjs            # alles
node build.mjs 11 12      # alleen deze nummers
```

`tv.css` bevat de tokens, `pages/*.html` de fragmenten, `art/` het artwork dat de pagina's
gebruiken, `assets/` de fonts en het wordmark. Playwright komt uit de globale installatie
onder `/opt/homebrew`.
