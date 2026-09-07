# Mockup 37, detailcorrectie, goedgekeurd

| Veld | Waarde |
|------|--------|
| Status | APPROVED DESIGN TARGET |
| Goedgekeurd door | Michel Knoop |
| Datum | 7 september 2026 |
| Set | 37 A tot en met D: filmdetail, lange synopsis, seriedetail met seizoenchips, volledige synopsis |
| In de repo | `docs/assets/tvos-unified/mockups-2026-09-07-detail/` |
| Bron | `docs/assets/tvos-unified/src/pages/37-detail-*.html` |
| Besluit | [DEC-109](DECISIONS.md#dec-109) |
| Komt uit | Twee fysieke meldingen: de synopsis wordt afgekapt zonder dat hij te openen is, en de detailpagina voelt opgeblazen |
| Dekt | MOC-09 (filmdetail), MOC-10 (seriedetail, seizoenchips met één actieve afleveringenrail) |

## De tekst in het beeld is niet de status

Dezelfde situatie als bij 09 tot en met 25 en bij 34 tot en met 36: de notitie in de PNG's zegt
nog niet "APPROVED". **Dit manifest is de statusautoriteit, niet de tekst in het beeld.**

## Wat de goedkeuring dekt

Compositie, hiërarchie, dichtheid, framing, componentfamilie, en de focus- en kaarttaal. Een
schermafbeelding is geen functionele specificatie. Waar het beeld en een eerder besluit elkaar
tegenspreken wint het besluit; die gevallen staan hieronder.

## Wat deze set corrigeert aan 09 en 10

09 en 10 blijven de compositie-authority voor alles wat 37 niet aanraakt, maar twee dingen in
09 en 10 halen de eigen tokens niet:

1. 09 rendert vier regels synopsis, terwijl hoofdstuk 8.3 er drie toestaat. 37 klemt op drie.
2. 09 en 10 eindigen ongeveer zes pixels van de onderrand, tegen hoofdstuk 8.1 (56) en
   [DEC-087](DECISIONS.md#dec-087) (`bottomSafeInset` 81) in. 37 schuift de informatiegroep en de
   rail omhoog om die inset weer echt te geven.

Waar het beeld verder van 09/10 afwijkt zonder dat het hier genoemd wordt, geldt het beeld niet
als correctie maar als de nieuwe herotaal, zie hieronder.

## Wat er nieuw is: de volledige synopsis

09 noch 10 heeft een affordance om de volledige synopsis te lezen. 37 B en 37 D leggen die vast
onder [DEC-109](DECISIONS.md#dec-109): een compacte focusbare "Meer lezen"-actie die alleen bij
echte overflow bestaat, en een scrollbaar paneel dat hem opent.

## In welke taal deze set staat

Niet in die van 09 en 10. Die twee dragen nog de oude herotypografie uit de goedgekeurde set van
3 september: ArchivoBlack in kapitalen met brede letterspatiëring, en metadata als omkaderde
chips. Sinds [DEC-095](DECISIONS.md#dec-095) en mockup 30 is de herotaal veranderd: Inter 56 in
zinsvorm met `letter-spacing: -.01em`, puntgescheiden metadata zonder kaders, een schermvullende
backdrop, en de railband 346 uit [DEC-087](DECISIONS.md#dec-087). De draaiende app tekent Home
al zo. **37 volgt mockup 30, niet de letter van 09 en 10.**

Concreet ten opzichte van 09 en 10: de titel staat in zinsvorm, de metadataregel is
puntgescheiden, de backdrop is schermvullend in plaats van een band van 780 met een harde
onderrand, en de kaarten in de rail zijn 615x346 conform DEC-087 in plaats van de 320x180 en
400x225 die in de mockup-CSS stonden. Het register zegt daar zelf over dat DEC-087 die
mockupmaten opzij zet.

## Verticale verdeling

De informatiegroep is onderaan verankerd, zoals de code hem tekent (`Align(bottomLeft)`), zodat
een extra regel omhoog groeit en de rail blijft staan. De rail piept zoals mockup 30 A1 dat
goedgekeurd doet: label en kaarten staan in beeld, het bijschrift valt onder de vouw en DOWN
scrolt door.

## De correctie die al verwerkt is

Op de eerste voordracht botste de afleveringenteller met de Menu-hint in 37 C. Dat is gecorrigeerd
vóór goedkeuring; de PNG in de repo is de gecorrigeerde versie.

## Open gedragspunt uit de mockupronde

In 37 C valt de synopsis van de gefocuste aflevering onder de schermrand. Die moet in beeld komen
zodra de rail focus krijgt en meescrolt. Dat is gedrag en geen nieuwe mockup, en hoort bij de
bouw van MOC-10.

## De beelden

| Nr | Bestand | SHA256 |
|----|---------|--------|
| 37 A | 37-detail-a.png | `54002c7e06d00619dc83c44194b3856faf6d2d829033c6a30215e66103dca28b` |
| 37 B | 37-detail-b.png | `204a8fe4407b76230a1d24dde129c7c417fce694a64247489f4dcf362bb20ec7` |
| 37 C | 37-detail-c.png | `66f293378e6dd9c22b5efde274378f4dff19476a9c7e19b8d44e6cdf68aa8192` |
| 37 D | 37-detail-d.png | `10ba19aee257eced4fa1468b83eaca6e6819514d77615b36b3d6f69bc97d0e32` |

## Wanneer er opnieuw akkoord nodig is

Dezelfde vier gevallen als bij 09 tot en met 36: een andere compositie dan het beeld tekent, een
componentfamilie die niet in de set voorkomt, een dichtheid die van de getekende afwijkt, en een
gedragswijziging die het beeld niet kan tonen maar die een eerder productbesluit raakt.
