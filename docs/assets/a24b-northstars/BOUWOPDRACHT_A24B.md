# Pleya A-24b: bouw de gekozen noordsterren daadwerkelijk na

De eerste implementatieronde is onvoldoende: Instellingen heeft vooral de bestaande structuur met andere styling gekregen, terwijl Mijn Pleya vrijwel onveranderd is gebleven. **Ronde A-24b herstelt beide.** De onderstaande twee keuzes staan vast; vraag ze niet opnieuw.

- **Instellingen iOS en tvOS: Apple TV+ Studio, richting 02.** Volg de categorieën, groepen, visuele hiërarchie, directe schakelaars, achtergrond, koppen en live voorbeeldkaart uit `01-Instellingen/`.
- **Mijn Pleya iOS en tvOS: Editorial, richting 01.** Bouw ook deze pagina's om volgens `02-Mijn-Pleya/`. De andere Mijn Pleya-varianten vervallen.
- **Warm gebroken wit:** uitsluitend binnen Instellingen, inclusief onderliggende instellingenpagina's. Houd Mijn Pleya, Home en de rest van Pleya bij hun eigen thema.

## Betekenis van pariteit

**De broncode bepaalt welke functies en voorkeuren bestaan, hun waarde, provider, validatie en voorwaarde. De gekozen mockups bepalen waar en hoe die functies getoond worden.** 'Code wint' is dus geen argument om de oude categorieën, iconen, knoppen of schermopbouw te houden.

1. Lees `START-HIER.md`, `VISUELE_ACCEPTATIE.md` en bekijk de **vier primaire ankers in volledig formaat**, daarna alle relevante vervolgschermen.
2. Lees de actuele Pleya-`main` en de voortgang van A-24a. Controleer in ieder geval:
   - `lib/screens/settings/settings_screen.dart`, `lib/screens/settings/parts/settings_tv_page.dart`, alle instellingenroutes, providers en i18n
   - `lib/screens/my_pleya_screen.dart`, `my_pleya_cards.dart`
   - `lib/screens/tv/tv_my_pleya_screen.dart`, `tv_my_pleya_header.dart`, `tv_my_pleya_tiles.dart`, `tv_my_pleya_sections.dart`
   - focusbeheer, thema, bovenste navigatie, bestaande tests en unified-libraryverbindingen
3. Vul voor **iedere daadwerkelijk bestaande** instelling en Mijn Pleya-bestemming de pariteitsmatrix in: `platform | huidige plek | route/provider | bediening | zichtbaarheidsvoorwaarde | nieuwe mockupgroep | nieuwe zichtbare plek | test`. Begin met `PARITY_TEMPLATE.csv`, voeg ontbrekende bestaande routes toe en verwijder conceptitems die de code niet ondersteunt. Bewijs dat er geen bestaande functie verdwijnt.
4. Laat vervolgens de mockupstructuur leidend zijn. **Verplaats of groepeer de bestaande instellingen daadwerkelijk**. Behoud de functionele code achter elke actie. Koppen, uitleg, iconen, directe toggles en preview zijn onderdeel van het ontwerp, geen vrijblijvende decoratie.
5. Maak op **iOS en tvOS een complete tweede ronde**, inclusief hoofdinstellingen, Weergave, andere instellingenfamilies, de hoofdpagina Mijn Pleya, focus-/conditietoestanden en light/dark/OLED. Bouw in kleine stappen met bestaande Flutter-componenten; vermijd een parallelle configuratiebron of nieuwe design-engine.

## Specifieke eisen Instellingen

- **tvOS:** de mockuprail met categorieën en bijbehorende iconen, bovenkop `Instellingen`, ondertitel `Jouw kijkervaring, tot in detail.`, grote sectietitel `Zo ziet jouw Pleya eruit` bij Weergave, warme achtergrondwash en een bijpassend licht gebroken-wit thema.
- **tvOS:** laat een bestaande booleaanse voorkeur als **directe schakelaar in de rij** zien. Select op de **hele rij** wijzigt de waarde; de switch is geen tweede focusstop. Keuzevelden of diepere opties kunnen naar een sheet of detail leiden. Houd één duidelijke remote-focus, behoud topnavigatie en focusherstel.
- **tvOS:** `Live voorbeeld` met `Jouw bibliotheek`, modusregel en `Bekijk voorbeeld`, plus waar zinvol de posters/echte content. Bouw een werkende preview op basis van de actuele voorkeur. Is iets alleen met gegevens te tonen, gebruik fixturedata voor de simulatorvergelijking en test daarnaast de lege productievariant.
- **iOS:** volg de voorbeeldgroepen, subtiele rij-indeling, icoonbehandeling, kop `Maak Pleya helemaal van jou.` en echte media-art. Maak `Live voorbeeld` op Weergave conform de iPhone-mockup. Behoud de zoekfunctie, veilige marges en bestaand headergedrag tijdens scrollen.
- Iedere huidige voorkeur krijgt een plaats in de gekozen categorieën/groepen. Als er méér instellingen zijn dan op het bord passen, laat de groep scrollen of verdeel deze over logische subpagina's in dezelfde stijl. Niets stilletjes verbergen.

## Specifieke eisen Mijn Pleya

- **iOS:** vervang de huidige knoppen/tegelmatrix door de compacte Editorial-indeling: profiel, serverstatus, zichtbare kijklijst/posterrail, rustige contentrijen, bescheiden maar herkenbare Big P-kaart, overige bestemmingen onder logische groepen. Alle bestaande acties blijven werken, inclusief profielwissel en bibliotheek-longpress.
- **tvOS:** volg `01-tvos-landing.png`: compacte profielregel met `Profiel wisselen`, zichtbare serverstatus, brede kijklijst, compacte contentgroepen links en Big P/beheer rechts. Gebruik `02-tvos-posterfocus.png`, `03-tvos-instellingenfocus.png`, `04-tvos-conditioneel.png` en `05-tvos-licht.png` om focus, ontbrekende modules en thema exact te toetsen.
- Geen Downloads op Apple TV. Toon aanvragen, Seerr, collecties, afspeellijsten, activiteit, Big P of bronacties alleen als de huidige code ze onder de betreffende omstandigheden aanbiedt.
- Behoud tvOS-topnavigatie, focusherstel, posterfocus zonder overlapping, teruggedrag, serverstatus als niet-focusbaar, en de bestaande provideracties.

## Verplichte tweede vergelijking, vóór gereedmelding

Leg de **werkelijk gerenderde screenshots** op hetzelfde platform en in dezelfde staat direct naast de gekozen mockups. Dit is een harde acceptatiestap, geen vrijblijvende beschouwing achteraf.

| Vergelijking | Northstar | Build-screenshot |
| --- | --- | --- |
| iPhone Instellingen, donker/licht | `01-Instellingen/images/01-ios-studio-dark.webp` / `03-ios-studio-light.webp` | Actuele iOS-simulator |
| Apple TV Instellingen, donker/licht | `01-Instellingen/images/02-tvos-studio-dark.webp` / `04-tvos-studio-light.webp` | Actuele tvOS-simulator |
| iPhone Mijn Pleya | `02-Mijn-Pleya/images/00-ios-geselecteerd.png` | Actuele iOS-simulator |
| Apple TV Mijn Pleya | `02-Mijn-Pleya/images/01-tvos-landing.png` | Actuele tvOS-simulator |

Loop `VISUELE_ACCEPTATIE.md` regel voor regel langs. Noteer **ieder** verschil onder `AFWIJKINGEN_A24B.md`: platform, controlepunt, wat de mockup laat zien, wat de build laat zien, reden, oplossing of expliciet nog open. 'Zo dicht mogelijk' zonder zichtbare vergelijking is geen acceptatie. Neem poster-/achtergrond-testfixtures op voor visuele screenshots zodat ontbreken van testdata niet onterecht als stylingfout of excuus geldt; behoud daarnaast het correcte lege pad.

Run relevante analyzer-, widget-, navigatie-, focus- en simulatorcontroles. Test tevens opslag van switches, platform-/capabilitycondities, donkere/licht/OLED-kleuren, navigatie terug, destructieve bevestigingen, VoiceOver en grotere tekst waar relevant. Rapporteer welke controles niet op echte hardware konden.

Maak een afgebakende PR met pariteitstabel, zes hoofdvergelijkingen plus aanvullende staten, expliciete afwijkingen en testresultaten. **Geen automatische merge.** Stop de implementatieronde pas als **beide** schermfamilies in de build aantoonbaar zijn veranderd of vermeld per niet voltooid scherm het blokkadepunt.
