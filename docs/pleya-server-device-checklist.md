# Pleya Server: toestelcontrole van de keten (iOS en tvOS)

Dit is de lijst voor de ronde op echte toestellen. De serverkant van dezelfde keten is op de
testinstance bewezen met `pleya_server/scripts/chain-smoke.sh` (25 oktober 2026, alles groen); wat
hier staat is wat alleen een toestel kan laten zien. Dezelfde stappen op iOS en op tvOS, zodat een
verschil tussen de twee meteen opvalt.

## Voor je begint

De testinstance luistert alleen op `127.0.0.1` van de NAS en heeft bewust geen tunnel. Een toestel
komt er dus niet bij. Kies één van de twee en zeg het, dan zet ik het klaar:

1. `PLEYA_SERVER_BIND` van de testinstance tijdelijk op het LAN-adres van de NAS, de toestellen op
   hetzelfde wifi, server toevoegen als `http://<nas>:8833`. Daarna weer terug naar loopback.
2. De productie-instantie (`https://web.pleya.app`) gebruiken. Dat raakt productie aan en vraagt
   een back-up vooraf en jouw go.

Inloggen met de testgebruiker uit `test-credentials.txt` op de NAS. Gebruik de build die PS-5- en
PS-9-gedrag bevat; de hardwareronde van PS-5 (criterium 4) staat nog open en dit is daar het moment voor.

## Stappen

Noteer per stap `ja`, `nee` of `deels` en een zin wat je zag. Een `nee` is een bevinding, geen mislukking
van de ronde.

| # | Stap | Wat je moet zien |
| --- | --- | --- |
| 1 | Server toevoegen en inloggen | Bibliotheken Films, Kids en Series verschijnen met aantallen. |
| 2 | Bibliotheek Films openen | Posters staan er, titels hebben een samenvatting en genres, scrollen blijft vloeiend. |
| 3 | Zoeken op een titel | Het resultaat komt binnen een paar seconden en bevat de titel. |
| 4 | Een film afspelen (direct play) | Beeld en geluid starten, vooruitspoelen springt zonder haperen, de audio- en ondertitelkeuze toont de sporen. |
| 5 | Audiospoor zonder taal | Een spoor zonder taaltag (veel series, bijvoorbeeld Friends) heet "onbekend" en is kiesbaar. Er wordt geen taal gegokt. |
| 6 | Stoppen halverwege en hervatten | Opnieuw openen biedt hervatten op de plek van stoppen. |
| 7 | Tweede toestel | Open dezelfde film op het andere toestel (iOS of tvOS): de positie staat op wat je net deed, en Verder kijken toont hem. |
| 8 | Transcode | Speel een film die dit toestel niet direct kan (HEVC of DTS-HD op iOS). Beeld start binnen ongeveer drie seconden en seek werkt binnen wat al is omgezet. |
| 9 | Sessie opruimen | Sluit de speler. `GET /transcode-sessions` is daarna leeg (ik controleer dat aan serverkant). |
| 10 | Download (alleen iOS) | Een korte film downloaden, offline afspelen, daarna online: de kijkstatus komt terug. |
| 11 | Download na herstart (alleen iOS) | Start een download, sluit de app geforceerd vóór hij klaar is, open hem opnieuw. De download rondt af en wordt gecontroleerd; een bestand dat niet klopt wordt geweigerd. |

Stap 11 is de herstartcontrole uit PR 493 en is alleen op een echt toestel te bewijzen.

## Waar de uitkomst heen gaat

De uitkomst per stap komt bij S15.2 in `docs/PLEYA-SERVER-MASTERLIST.md`, met datum en build. Een stap
die niet gehaald is krijgt een eigen regel en een eigen fix; de ronde wordt daarna alleen voor die stap
herhaald. Code, CI en hardware worden apart gemeld: groen in de ene zegt niets over de andere.
