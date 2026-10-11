# Mockupset 43: Instellingen, Big P, Geheugen

Status: PROPOSED (11 oktober 2026). Nog niet bouwen tot akkoord van Michel.
Roadmap: BP-08a.

Het geheugen is een lijst korte feiten per Pleya-profiel, bewaard op het apparaat zelf. Elke herinnering heeft een tekst van hooguit 200 tekens, een van vijf categorieën (Voorkeuren, Niet voor mij, Huishouden, Kijkgewoonten, Overig), een herkomst en twee datums. Taalvoorkeuren staan er niet in: die hebben hun eigen instellingen. De leeftijden van de kinderen staan er ook niet in. Het scherm toont ze als verwijsrij naar Kinderprofiel, buiten de lijst, zodat "Alle herinneringen wissen" ze niet raakt.

De instellingenschermen volgen northstar 14 (iPhone) en mockup 31 A (tvOS). Het gespreksbeeld 43 G gebruikt het paneel en de bevestigingskaart van 39 G.

## De beelden

| Paneel | Bestand | Formaat | Wat het vastlegt |
| --- | --- | --- | --- |
| 43 A | `43-a-hoofdscherm.png` | iPhone 402x874 | Schakelaar met uitleg en het kader over cloudmodellen, zoekveld, filterchips, lijst met teller. |
| 43 A, vervolg | `43-a-hoofdscherm-onder.png` | iPhone 402x874 | Hetzelfde scherm aan het einde van de scroll: verwijsrij Leeftijden kinderen, "Herinnering toevoegen", "Vraag Big P over je geheugen" en de tekstknop om alles te wissen. |
| 43 B | `43-b-bewerken.png` | iPhone 402x874 | Sheet voor een bestaande herinnering: tekst, categorie, herkomst, datums, Opslaan, Annuleren, Verwijderen. |
| 43 C | `43-c-toevoegen.png` | iPhone 402x874 | Sheet voor een nieuwe herinnering: leeg veld, teller 0/200, Opslaan uitgeschakeld, de hint over wachtwoorden en medische gegevens. |
| 43 D | `43-d-wissen.png` | iPhone 402x874 | Bevestigdialoog. Annuleren is de standaardknop, Wissen staat ernaast als rode tekst. |
| 43 E | `43-e-uit.png` | iPhone 402x874 | Schakelaar uit: melding dat niets wordt onthouden of gebruikt, de lijst gedimd maar bewaard. |
| 43 F | `43-f-leeg.png` | iPhone 402x874 | Geheugen aan, nul herinneringen. |
| 43 G | `43-g-gesprek.png` | iPhone 402x874 | Twee momenten in het gesprek: Big P stelt een herinnering voor (focus op "Niet onthouden"), en de gebruiker vraagt er zelf om, met de link "Bekijk geheugen". |
| 43 H | `43-h-ipad.png` | iPad liggend 1180x820 | Links schakelaar, zoekveld en categorieën met aantallen, in het midden de lijst, rechts het detailpaneel. |
| 43 I | `43-i-tvos.png` | tvOS 1920x1080 | Twee kolommen zoals mockup 31 A. Eén rij heeft focus: witte ring, geen schaal. Alle tekst is 23 px of groter. |

Elk PNG heeft een HTML-bestand met dezelfde naam. De PNG's zijn 2x.

43 A bestaat uit twee beelden omdat de inhoud niet op één telefoonscherm past. De regels "1. Big P stelt voor, jij beslist" en "2. Je vraagt er zelf om" in 43 G zijn toelichting bij de mockup en komen niet in de app: de twee ballonnen staan nooit tegelijk in beeld.

## Opnieuw renderen

```
python3 gen43.py                  # HTML en PNG's
python3 gen43.py --html           # alleen HTML
python3 gen43.py 43-b-bewerken    # een enkel beeld
```

De generator schrijft de HTML uit `bp43.js` en `bp43.css` en maakt de PNG's met Playwright (Chromium, `device_scale_factor=2`) via het Python-pakket `playwright`. Het `pw screenshot`-commando heeft geen optie voor de schaalfactor en levert dus 1x. Lettertypen komen uit `assets/fonts/`, posters en Big P uit `docs/assets/ios-unified/detail-2026/` en `docs/assets/tvos-unified/src/assets/`.

## Open ontwerpkeuzes

1. Kleur van "Alle herinneringen wissen" op tv. Op iPhone en iPad is het een tekstknop in accentrood. Op tv staat hij in 43 I in de gewone rustkleur met een prullenbak, omdat een rode foutkleur in rust daar nu niet leesbaar is. Dat hangt aan ACTION-ERROR-CONTRAST in `docs/tvos-fysieke-correctieronde.md`; de uitkomst daarvan bepaalt de kleur hier.
2. Zoeken op tv. 43 I heeft geen zoekveld. Het voorstel is zoeken via het systeemtoetsenbord, zoals de zoekpagina dat doet, en bij zes herinneringen kan het ook zonder.
3. Geselecteerde chip. Filter- en categoriechips zijn wit gevuld als ze gekozen zijn, net als op tv. Accentrood is de andere kandidaat.
4. "Geheugen gebruiken" op tv is een rij met de waarde "Aan" en een chevron. Een schakelaar in de rij, zoals bij "Onthoud keuzes per serie" in 31 A, kan ook.
5. Focusring op tv: 2,5 px met een tussenruimte van 6 px. Mockup 31 A tekende 4 px op 8.
6. De herkomstregel "Voorgesteld door Big P, door jou bevestigd" loopt op iPhone over twee regels. Een kortere tekst houdt de rijen even hoog.
7. De tabbalk blijft staan op het geheugenscherm, zoals in northstar 14.
