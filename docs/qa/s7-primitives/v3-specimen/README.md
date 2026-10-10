# Specimen v3: kaart, hero en rail (S7 commitgrens 4)

Statische vooruitblik op `MediaCard`, `Hero` en `HubRail` voordat taak 2 tot en met 4 van
`docs/superpowers/plans/2026-10-10-pleya-web-s7-commitgrens4.md` iets bouwen. Er is nog geen
Svelte geschreven en `pleya_web/src` is niet aangeraakt. Het specimen gebruikt de waarden uit
`pleya_web/src/styles/tokens.css` (thema dark), de maatvoering uit
`docs/assets/pleya-web-northstar/src/web.css` en ArchivoBlack voor de herotitel, geladen uit
`pleya_web/static/fonts` via een relatief pad. Het artwork bestaat uit CSS-verlopen met de titel
erin; er zit geen TMDb-materiaal in.

`v3.html` opent zonder server. Met `?only=kaarten`, `?only=hero` of `?only=rail` toont hij één
sectie; zo zijn de losse opnamen gemaakt, met `pw screenshot --full-page` op 393, 1024 en 1600.

## Wat waar staat

| Bestand | Inhoud | Ligt naast |
| --- | --- | --- |
| `v3@{393,1024,1600}.png` | het hele specimen | geen één-op-één |
| `kaarten@*.png`, `kaarten-vs-16@*.png` | elf kaartstaten: rust, hover met acties, toetsenbordfocus, voortgang, gezien, nieuw, aflevering in Verder kijken, volgende aflevering (wide), geen artwork, twee versies, en gezien plus nieuw | `16-kaartstaten@1600` (beeld 16 bestaat alleen op 1600) |
| `hero@*.png`, `hero-vs-01@*.png` | drie heroes: A met Afspelen en synopsis, B zoals de routes hem in deze grens aanroepen (alleen Meer info, lange titel), C zonder artwork. 21:9 op 1600, 16:9 op 1024, portret van 520 op 393 | `01-home` op dezelfde breedte |
| `rail@*.png`, `rail-vs-01@*.png` | Verder kijken met voortgang, Volgende afleveringen (wide, zonder "Alles bekijken"), Recent toegevoegd met nieuw-punten en de pijlen zoals ze bij hover verschijnen | `01-home` op dezelfde breedte |

De opdracht noemde beeld 12 en 14 voor de rail. Die bevatten geen rail (12 is inloggen, 14 de
onbereikbare server), dus de rail ligt naast 01, waar alle vier de soorten rijen staan. In de
uitsnede van 01 staat ook Verder lezen; die boekrij is S9 en hoort niet bij deze grens.

## Bewuste verschillen met de northstar

- **Volgende aflevering is 1,78 keer zo breed als een poster.** Beeld 16 tekent de Fallout-kaart
  even breed als een poster, terwijl het bijschrift in datzelfde beeld en de rij in 01 de 1,78 hanteren.
  Het specimen volgt het bijschrift en 01; op 1600 is de kaart 338 breed.
- **Synopsis en leeftijdsbadge.** `Item` draagt ze nog niet (PS-7N, S4). Hero A toont een synopsis
  om te laten zien waar hij komt; hero B is de vorm die de routes in deze grens krijgen, zonder
  synopsis en zonder lege ruimte. De leeftijdsbadge staat nergens.
- **Geen segmentindicator, geen rotatie.** Weggelaten tot er een besluit ligt (DESIGN.md hoofdstuk 8).
- **Geen artwork op het paneel met een haarlijn.** Beeld 16 tekent dit vlak plat op `--surface`; het
  specimen gebruikt `--panel` met de rand van 7 procent uit v2, zodat hij op `--bg` ook zonder
  kleurverschil loskomt. Dezelfde keuze bij hero C.
- **Pijlen in de rail.** De northstar tekent ze niet. Het specimen zet ze als ronde knop van 44 op de
  helft van de posterhoogte, half over de inzet, alleen vanaf 900 en alleen met een muis. De linker is
  aan het begin uitgeschakeld.
- **Hover-acties op smal.** Een kaart van 110 breed kan 40 + 34 + 34 plus tussenruimte niet dragen, dus
  onder 900 worden de knoppen 34 en 30. Op een touchscherm verschijnt de overlay niet; dit geldt voor
  een smal venster met een muis.
- **Gewichten.** De bundel heeft Inter 400, 500 en 700, dus de paginatitel van het specimen staat op
  700 en niet op de 800 uit v2. De kaarten en de hero gebruiken alleen gewichten die bestaan.
- **Teksten in het Nederlands**, zoals de northstar, om de vergelijking leesbaar te houden. In de app
  komen ze via `t()` met Engelse sleutels; de Nederlandse locale is commitgrens 5.

## Waar Michel op beslist

1. **"Meer info" als tweede heroknop.** De secundaire capsule (`--fill-2` met i-pictogram) uit 01 naar
   `/items/{id}`, altijd aanwezig. Ja of nee.
2. **Hoe de hero eruitziet zolang Afspelen ontbreekt.** Tot PS-4W geeft geen route een `playHref` mee,
   dus elke hero is in de praktijk hero B: één secundaire knop, op 393 over de volle breedte. Laten
   zoals getekend, of "Meer info" wit en primair maken zolang hij alleen staat.
3. **Segmentindicator.** Weggelaten in dit specimen en in het plan. Ja betekent dat hij samen met de
   rotatie in S8 komt, niet in deze grens.

Kleiner, en alleen bij bezwaar: de vorm van de railpijlen en het geen-artworkvlak op `--panel` in plaats van
`--surface`. Beide volgen v2.
