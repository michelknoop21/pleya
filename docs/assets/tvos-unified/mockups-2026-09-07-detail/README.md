# Mockup 37, detailcorrectie, voorgedragen op 7 september 2026

**Status: KANDIDAAT.** Nog niet goedgekeurd. Deze set hoort bij MOC-09 en MOC-10, die allebei
nog op OPEN staan in `docs/tvos-redesign-register.md`.

## Waar deze set vandaan komt

Twee meldingen op een fysieke Apple TV: de synopsis wordt afgekapt zonder dat je hem kunt
openen, en de detailpagina voelt opgeblazen.

## Wat er in zit

| Nr | Bestand | Wat het vastlegt |
|----|---------|------------------|
| 37 A | `37-detail-a` | Filmdetail in rust, informatiegroep compact, eerste rail in beeld |
| 37 B | `37-detail-b` | Lange synopsis afgekapt op drie regels, met "Meer lezen" gefocust |
| 37 C | `37-detail-c` | Seriedetail met seizoenchips en een actieve afleveringenrail (PB-4) |
| 37 D | `37-detail-d` | De volledige synopsis als scrollbaar paneel |

## Wat deze set corrigeert aan 09 en 10

De goedgekeurde mockups 09 en 10 blijven de compositie-authority, maar twee dingen erin
halen de eigen tokens niet, en die zijn hier rechtgetrokken:

- 09 rendert vier regels synopsis, terwijl hoofdstuk 8.3 er drie toestaat. Hier geklemd op drie.
- Beide eindigen ongeveer zes pixels van de onderrand, tegen hoofdstuk 8.1 (56) en DEC-087
  (`bottomSafeInset` 81) in. De informatiegroep en de rail zijn daarom omhoog geschoven.

## Wat er nieuw is en dus een eigen besluit vraagt

In 09 noch 10 staat een affordance om de volledige synopsis te lezen. 37 B en 37 D leggen die
vast en horen daarom onder een eigen DEC-nummer, voorgesteld als DEC-109.

## In welke taal deze set staat

Niet in die van 09 en 10. Die twee komen uit de goedgekeurde set van 3 september en dragen nog
de oude herotypografie: ArchivoBlack in kapitalen met brede letterspatiëring, en metadata als
omkaderde chips. Sindsdien is de herotaal veranderd met DEC-095 en mockup 30: Inter 56 in
zinsvorm met `letter-spacing: -.01em`, puntgescheiden metadata zonder kaders, een
schermvullende backdrop, en de railband van 346 uit DEC-087. De draaiende app tekent Home ook
zo. Deze set volgt daarom mockup 30, niet de letter van 09 en 10.

Wat dat concreet verandert ten opzichte van 09 en 10: de titel staat in zinsvorm, de
metadataregel is puntgescheiden, de backdrop is schermvullend in plaats van een band van 780
met een harde onderrand, en de kaarten in de rail zijn 615x346 conform DEC-087 in plaats van de
320x180 en 400x225 die in de mockup-CSS stonden. Het register zegt daar zelf over dat DEC-087
die mockupmaten opzij zet.

## Verticale verdeling

De informatiegroep is onderaan verankerd, zoals de code hem tekent (`Align(bottomLeft)`), zodat
een extra regel omhoog groeit en de rail blijft staan. De rail piept, precies zoals mockup 30 A1
dat goedgekeurd doet: label en kaarten staan in beeld, het bijschrift valt onder de vouw en DOWN
scrolt door.

## De art-map

`build.mjs` verwacht een `art`-map naast `src` die niet in de repo staat. Deze set is gebouwd met
`PLEYA_MOCKUP_ART=~/Downloads/mockups-tvos/_src/art`.
