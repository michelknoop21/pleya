# Mockupset 43: Instellingen, Big P, Geheugen

Status: APPROVED (Michel, 11 oktober 2026), in de herziene vorm met het overzicht in lopende tekst als hoofdscherm. Het plan staat in `docs/plans/2026-10-11-big-p-geheugen.md`.
Roadmap: BP-08a.

Het hoofdscherm "Geheugen" is een overzicht dat Big P in de tweede persoon schrijft, in secties: Overzicht, Voorkeuren, Niet voor jou, Huishouden en Kijkgewoonten, plus Overig als er zulke herinneringen zijn. Onder de tekst staan drie vervolgvragen ("Duik dieper") en vast onderin het invoerveld "Vraag of werk bij". De schakelaar, het lijstbeheer en het wissen zitten achter de menuknop rechtsboven.

Onder het overzicht ligt nog steeds een lijst korte feiten per Pleya-profiel, bewaard op het apparaat zelf. Elke herinnering heeft een tekst van hooguit 200 tekens, een van vijf categorieën (Voorkeuren, Niet voor mij, Huishouden, Kijkgewoonten, Overig), een herkomst en twee datums. Taalvoorkeuren staan er niet in: die hebben hun eigen instellingen. De leeftijden van de kinderen staan er ook niet in. Het overzicht verwijst ervoor naar Kinderprofiel en het lijstscherm toont ze als verwijsrij buiten de lijst, zodat "Alle herinneringen wissen" ze niet raakt.

De lijst en de sheets volgen northstar 14 (iPhone), het tv-beeld volgt mockup 31 A. Het gespreksbeeld 43 K gebruikt het paneel en de bevestigingskaart van 39 G.

## De beelden

| Paneel | Bestand | Formaat |
| --- | --- | --- |
| 43 A, overzicht | `43-a-overzicht.png` | iPhone 402x874 |
| 43 A, einde van de scroll | `43-a-overzicht-onder.png` | iPhone 402x874 |
| 43 B, laadstaat "Bijwerken" | `43-b-genereren.png` | iPhone 402x874 |
| 43 C, menu achter de drie puntjes | `43-c-menu.png` | iPhone 402x874 |
| 43 D, herinneringen beheren | `43-d-beheren.png` | iPhone 402x874 |
| 43 E, herinnering bewerken | `43-e-bewerken.png` | iPhone 402x874 |
| 43 F, herinnering toevoegen | `43-f-toevoegen.png` | iPhone 402x874 |
| 43 G, alles wissen bevestigen | `43-g-wissen.png` | iPhone 402x874 |
| 43 H, bijwerken via het invoerveld | `43-h-bijwerken.png` | iPhone 402x874 |
| 43 I, geheugen uit | `43-i-uit.png` | iPhone 402x874 |
| 43 J, nog geen herinneringen | `43-j-leeg.png` | iPhone 402x874 |
| 43 K, onthouden in het gesprek | `43-k-gesprek.png` | iPhone 402x874 |
| 43 L, iPad liggend | `43-l-ipad.png` | iPad 1180x820 |
| 43 M, tvOS | `43-m-tvos.png` | tvOS 1920x1080 |

Elk PNG heeft een HTML-bestand met dezelfde naam. De PNG's zijn 2x.

Bij de beelden:

- 43 A bestaat uit twee beelden omdat het overzicht niet op één telefoonscherm past. Het invoerveld ligt boven de tekst met een verloop naar de achtergrondkleur.
- 43 D toont het filter "Niet voor mij" (2 van 6), zodat zoekveld, chips, lijst, teller, de verwijsrij Leeftijden kinderen en de knop samen in één beeld passen.
- 43 G opent vanuit het menu en ligt daarom over het overzicht, niet meer over de lijst.
- 43 H: wie in het invoerveld iets schrijft dat een bestaande herinnering tegenspreekt, krijgt een kaart met wat verdwijnt en wat ervoor terugkomt. De focus staat op "Niet vervangen".
- 43 K: de cursieve regels boven de twee ballonnen zijn toelichting bij de mockup en komen niet in de app. De ballonnen staan nooit tegelijk in beeld. In de eerste staat het voorstel onder het antwoord op de vraag, niet in plaats ervan.
- 43 L heeft geen menuknop: de rechterkolom toont dezelfde vier acties en de vervolgvragen.
- 43 M: de leestekst is 29 px, de kleinste tekst op het scherm 23 px. De tegel "Vraag of werk bij" heeft focus: witte ring van 2,5 px, geen schaal.

## Opnieuw renderen

```
python3 gen43.py                  # HTML en PNG's
python3 gen43.py --html           # alleen HTML
python3 gen43.py 43-e-bewerken    # een enkel beeld
```

De generator schrijft de HTML uit `bp43.js` en `bp43.css` en maakt de PNG's met Playwright (Chromium, `device_scale_factor=2`) via het Python-pakket `playwright`. Het `pw screenshot`-commando heeft geen optie voor de schaalfactor en levert dus 1x. Lettertypen komen uit `assets/fonts/`, posters en Big P uit `docs/assets/ios-unified/detail-2026/` en `docs/assets/tvos-unified/src/assets/`.

## Vastgelegd bij het akkoord

Het overzicht wordt door het model geschreven uit de opgeslagen feiten, en alleen opnieuw als de feiten zijn gewijzigd (het plan noemt de drie andere aanleidingen: taalwissel, nieuw formaat, handmatig). Zonder ingesteld model of zonder verbinding toont het scherm de feiten per categorie als lijst. De feiten blijven de waarheid: het overzicht is afgeleid en wordt nooit zelf bewerkt. Wie iets wil veranderen, doet dat via het invoerveld of in "Herinneringen beheren". De uitwerking staat in het plan.

## Open ontwerpkeuzes

Kleur van de gevaaractie op tv. Op iPhone en iPad is "Alle herinneringen wissen" een tekstactie in accentrood. In 43 M staat de tegel in de gewone rustkleur met een prullenbak. De uitkomst van ACTION-ERROR-CONTRAST in `docs/tvos-fysieke-correctieronde.md` bepaalt de kleur hier.

Uit de eerste ronde staan nog open: de geselecteerde chip is wit gevuld (accentrood is de andere kandidaat), de focusring op tv is 2,5 px met 6 px tussenruimte waar mockup 31 A 4 px op 8 tekende, en de tabbalk blijft staan op het geheugenscherm zoals in northstar 14.
