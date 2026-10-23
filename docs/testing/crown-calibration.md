# Eén scrollkroon — IOS-CROWN-CAL1 / A-06

## Actueel besluit: directe schuifbalk

Michel heeft op 23 oktober 2026 de afstandskandidaat op zijn iPhone afgekeurd:
het scrollen blijft te snel om nauwkeurig te bedienen. Zijn vervolgbesluit is
expliciet: dezelfde draaiende kroon loopt van bovenaan de bibliotheek naar het
einde onderaan het scherm, in één doorlopende haal. Nauwkeurig bijstellen doet
hij in de lijst zelf. Geen fijnregeling naar links, tweede knop of instelling.
Dit vervangt de eerdere keuze voor extra halen en precisie binnen de kroon.

`CrownDragMotion` gebruikt `position-direct-v3`. Vastpakken verandert de
scrollpositie niet. De resterende afstand tot de boven- of onderrand bepaalt
lineair het resterende bibliotheekbereik. Er is geen snelheids- of
afstandsversnelling. Omkeren volgt dezelfde verankerde positie; stilhouden geeft
geen extra beweging. Aan de randen zijn het echte begin en einde bereikbaar.
Bij een greep op de kroon op zijn actuele positie komt de positie op de rail
rechtstreeks overeen met het deel van de bibliotheek dat is doorlopen.

Het bestaande uiterlijk, tandwiel, rotatie, fade, alfabetlabel en de voelbare
rateltikjes blijven behouden. Reduce motion houdt de rotatie stil. Een gewone
veeg in de lijst houdt zijn normale scrollrichting en schaal. In de proefapp
is normaal lijstscrollen nu ook ingeschakeld.

## Integratie en grenzen

Unified impact: dezelfde `ScrollCrown` voor unified/mixed catalogus,
bibliotheektabs en overige telefoonschermen. Providers, sortering, capabilities
en rechten veranderen niet. Desktop, tablet en TV houden `AlphaJumpBar`.

Kop en inhoud van een geneste bibliotheek tellen samen als scrollbereik. De
doorlopende native sleepactie en globale vingercoördinaten blijven behouden,
zodat het inklappen van de kop geen extra scrollbeweging veroorzaakt. Het
binnenbereik blijft tijdens een haal bevroren wanneer meer items worden geladen.
Een daadwerkelijk bereikte onderrand volgt het naladen alleen terwijl de kroon
daar wordt vastgehouden; loslaten stopt dit.

Een volledige bibliotheek op een korte rail blijft een grove positionering:
bij 10.000 titels is één punt niet één titel. Dat is geen precisieclaim. De lijst
is bedoeld om daarna de exacte titel te kiezen, volgens Michels keuze.
Pleya Verify gebruikt uitsluitend geïsoleerde fixtures; geen live-providerclaim.

## Historie en bewijs

De 15 baselinepogingen bij 100 titels zijn een onvolledige nulmeting. De
snelheidskandidaat `velocity-relative-v1` is fysiek afgekeurd; taak 2 duurde
26,98 s, met 1.999 titels overschrijding en 10 correcties.

Ook `distance-relative-v2` is fysiek afgekeurd. De opgeslagen poging duurde
83,44 s, met 1.165 titels overschrijding en uiteindelijk nog 51,13 titels naast
het doel. Het bestand is behouden als `crown-distance-current.json` in de
geïsoleerde proefapp en buiten de repository gekopieerd. De eerdere technische
simulaties zijn geen bewijs van menselijke bruikbaarheid. Beide formules zijn
uitsluitend als historische negatieve controle in tests bewaard.

Actuele tests controleren één haal naar ieder eindpunt bij 100/1.000/10.000
titels, een constante verhouding zonder versnelling, omkeren, aanraken zonder
sprong, naladen, loslaten, gewoon lijstscrollen en behoud van rotatie/haptiek.
Negatieve controle: deze directe-positiecontracten falen op de afgekeurde
formule. Native grid/list-scenario's toetsen de echte gedeelde kroon.

## Korte fysieke proef

De afzonderlijke **Pleya kroonmeting** toont 10.000 genummerde A–Z-titels:

1. Sleep dezelfde kroon in één haal naar het einde en terug naar het begin.
2. Schuif in de lijst zelf één titel terug.

Geen herhalingsronde of vragenlijst. De actuele titel blijft zichtbaar na
loslaten. De proef schrijft `Documents/crown-direct-current.json`; de oude
baseline-, snelheids- en afstandsbestanden worden niet vervangen. Herstel
controleert bronhash/model en bewaart oude bytes bij een nieuwe sessie.
Michel heeft in dezelfde sessie expliciet gevraagd: “Ga door tot en met build
naar testflight”. Alleen voor deze kroonwijziging is daarmee interne iOS-
TestFlight-distributie vóór de nieuwe fysieke acceptatie toegestaan. Groene
PR-checks, onafhankelijke review en een gemergede bron blijven vereist.
Fysieke acceptatie blijft open; dit is geen externe/store-release.

```bash
flutter test --no-pub test/widgets/scroll_crown \
  test/screens/libraries/alpha_scroll_handle_test.dart \
  test/automation/automation_input_test.dart
PLEYA_KEEP_BUILDS=1 python3 tool/build_crown_calibration.py app-simulator
PLEYA_KEEP_BUILDS=1 python3 tool/build_crown_calibration.py device
```

De builder controleert `nl.michelknoop.pleya.verify` en codesign, gebruikt lege
entitlements en herstelt tijdelijk aangepaste native projectbestanden. Geen
productiegegevens, verbindingen, vault of NAS in de meetopstelling.
