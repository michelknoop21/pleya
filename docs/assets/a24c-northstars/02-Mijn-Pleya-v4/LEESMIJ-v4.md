<!-- anti-slop: off (tekst van Michel, ongewijzigd overgenomen) -->
# Mijn Pleya A — versie 4.1

26 oktober 2026. **Ontwerpmockups, geen gewijzigde Pleya-build.**

## Goedgekeurde keuze

Mijn Pleya blijft de persoonlijke kijkomgeving. Instellingen krijgt één herkenbare ingang na Mijn Pleya in het bestaande topmenu. De aparte Beheer-pagina en het algemene Meer-paneel vervallen. A blijft de gekozen compositie: Big P groot links, de kijklijst één keer rechts, één vaste rij dagelijkse bestemmingen eronder.

Versie 4.1 corrigeert de bronpariteit van de topbalk: profiel links, zoeken vóór de tekstbestemmingen, Series vóór Films en het oorspronkelijke Pleya-woordmerk rechts. Het extra profiel-/statusblok in de pagina is verwijderd. De rest van compositie A blijft gelijk.

## Bestaande tvOS-navbar

Bron: `lib/widgets/tv/tv_top_navigation.dart`, `lib/widgets/tv/tv_top_nav_item.dart`, `lib/widgets/tv/tv_unified_layout.dart` en `lib/navigation/tv/tv_destination.dart`, commit `a48b5e496d5d84a97a78c8649dd4657e31486d9b`.

| Positie | Bestaand gedrag en ontwerp |
| --- | --- |
| Links | Eén profielavatar, zonder tweede accountblok in Mijn Pleya |
| Gecentreerd op het scherm | Zoekicoon, Home, Series, Films, Live TV indien beschikbaar, Mijn Pleya |
| Nieuwe goedgekeurde toevoeging | Instellingen, direct na Mijn Pleya |
| Rechts | Het echte Pleya-woordmerk, geen focusbaar navigatie-item |

De actieve bestemming heeft een witte capsule in dark/OLED, een donkere capsule in light. Remote-focus heeft een afzonderlijke ring. Geen rode underline of rode navigatiepill. Deze beelden tonen de bronvariant zonder Liquid Glass op de topbalk; de bestaande instelling voor Liquid Glass wordt niet gewijzigd. Tokenverhoudingen uit de bron zijn op het 1920×1080-mockupformaat toegepast, geen claim van pixelpariteit met een gedraaide build.

Live TV blijft capability-afhankelijk. De offline-variant behoudt haar bestaande regels: zoeken, Series, Films en Live TV verdwijnen, Home/Mijn Pleya blijven bereikbaar en de bestaande herverbindactie blijft behouden wanneer beschikbaar. Dat is niet dezelfde staat als A15, die uitsluitend ontbrekende Seerr-/Activiteit-koppelingen toont.

Dit pakket vervangt het v3-keuzevoorstel. Historische A08 dient uitsluitend als vergelijkingsmateriaal en niet als bouwinstructie.

## Beelden

| Bestand | Doel |
| --- | --- |
| A10-mijn-pleya-dark.png | Hoofdontwerp, focus op Big P |
| A11-mijn-pleya-light.png | Dezelfde indeling, bestaande lichte Pleya-kleuren |
| A12-mijn-pleya-oled.png | Dezelfde indeling, zwarte OLED-achtergrond |
| A13-instellingen-focus.png | Eén duidelijke focusmarkering op de nieuwe topmenu-ingang |
| A14-profiel-acties.png | Het voorgestelde profiel-actiemenu onder de bestaande avatar links |
| A15-zonder-seerr-en-activiteit.png | Voorbeeld zonder Seerr/Tautulli, geen lege dockplaatsen |

Alle zes PNG's zijn 1920×1080. Open `index-v4.html` voor de statische beeldgalerij met volledige afbeeldingen.

## Scope

**WEL:** Mijn Pleya op tvOS, het profiel-actiemenu, één Instellingen-ingang in het bestaande topmenu en het bereikbaar houden van de bestaande routes via de afgesproken nieuwe ingangen.

**NIET:** Home, Films, Series, Live TV, Zoeken, de speler, iOS-schermen, andere instellingenlayouts, backends, datamodel of een globaal nieuw thema. Het topmenu buiten de nieuwe Instellingen-knop blijft bestaande referentiecontext en wordt niet opnieuw ontworpen. De bestaande gebruikerskeuze voor dark/light/OLED blijft leidend.

## Bronmaterialen

- Logo: `assets/branding/pleya_logo.png` uit Pleya, lokaal `assets/pleya_logo.png`.
- Navbar-woordmerk: oorspronkelijke lagen `assets/branding/pleya_wordmark_mark.png` en `assets/branding/pleya_wordmark_text.png`, lokaal onder `assets/`. Over elkaar met behoud van beeldverhouding, alleen de letters volgen de themakleur, zoals `lib/widgets/pleya_wordmark.dart` voorschrijft.
- Big P: `assets/branding/bigp/still-zwaaien.png`, lokaal `assets/bigp-still-zwaaien.png`.
- Inter: echte Regular/Medium/Bold-fonts uit `assets/fonts`.
- Kleuren: `lib/theme/mono_theme.dart`, `lib/theme/mono_tokens.dart`. Merkrood `#E5140F`, amber `#FFB020`; dark `#141414`, OLED `#000000`, light `#F7F7F8`.
- Assets en eerdere northstars: snapshot `61ed9e84fa7f29dd106c66d567553b9878106374`.
- Extra routecontrole: snapshot `a48b5e496d5d84a97a78c8649dd4657e31486d9b`.
- De echte posterpixels komen uit `reference/01-tvos-a24b.png`. Geen gegenereerde filmaffiches. Profielnaam en titels zijn voorbeelddata. De avatar gebruikt bewust de echte initialenfallback uit `lib/profiles/profile_avatar.dart` en `lib/utils/initials_palette.dart`: M op `#1565C0` voor Michel. Geen foto verzonnen. In de app blijft de ingestelde profielfoto leidend.

## Belangrijkste pariteitsdetail: Servers

De huidige tvOS-instellingenlijst gebruikt `ConnectionsSection`. De bestaande Mijn Pleya-serverpagina is `TvServersPage` en toont méér: online/offline/herauthenticatie, bibliotheekaantal, gebruiker en een statusdialoog vóór een verwijderactie. Die schermen zijn dus niet bewezen equivalent.

**Implementatie-eis:** behoud `TvServersPage` via **Instellingen > Koppelingen > Servers**, inclusief status-eerst-bediening, Sluiten als veilige standaardfocus, verwijderen met bevestiging en correcte Terug-focus. Alleen de bestaande verbindingenlijst aanbieden voldoet niet aan deze pariteit.

De bestaande navbar-avatar opent direct de profielkiezer. Het kleine actiemenu in A14 is het eerder voorgestelde ontwerp, niet een screenshot van bestaand gedrag. Wissel profiel behoudt daar de shellcallback met `AccountUiActions.openProfiles(asGate: true)`. Uitloggen behoudt `AccountUiActions.logout` met bevestiging en bestaande cleanup. Geen nieuwe afmeldsemantiek.

## Focusafspraken

Bij eerste binnenkomst is de Big P-kaart één focusobject, niet de kaart plus nog een afzonderlijke knop. In de kaart is Vraag Big P alleen de zichtbare actieaanduiding. Als Big P niet beschikbaar is, geldt de bestaande capabilityregel en gaat de focus naar de eerste toegestane contentactie.

- Rechts vanaf Big P gaat naar de eerste kijklijstposter. Links vanaf de eerste poster gaat terug naar Big P.
- Links/rechts doorloopt de zichtbare docktegels. Geen lege focusplaatsen bij verborgen opties.
- Omhoog vanuit het dock gaat naar de dichtstbijzijnde contentactie. Omhoog vanuit de inhoud biedt toegang tot de bestaande topnavigatie, inclusief Instellingen.
- In het voorstel opent de bestaande avatar links een klein, benoemd accountmenu, direct onder dezelfde ingang. De achtergrond, inclusief topmenu, is dan niet focusbaar. Omhoog/omlaag wisselt tussen twee acties. Back/Menu sluit het menu en herstelt focus op die avatar. Geen tweede profielknop in de pagina.
- Links/rechts volgt de bestaande navbarvolgorde, zonder wrapping of focusstop op het woordmerk. Instellingen wordt aan het eind van de bestemmingengroep toegevoegd. Over een andere bestemming focussen verandert de actieve pagina niet.
- Terug uit een bestaande bestemming herstelt de aanroepende focus. Instellingen onthoudt de terugkeer naar de topmenu-ingang.
- De actieve navigatiebestemming en toetsenbord/remote-focus zijn verschillend zichtbaar. Eén focusring tegelijk.

## Vergelijkingsmateriaal

`reference/01-tvos-a24b.png` en `reference/00-ios-a24b.png` zijn echte projectreferenties. `reference/A08-voorgaand-voorstel.png` toont het vorige ontwerp met Beheer. De officiële Apple TV-appreferentie dient als kwaliteitsvergelijking voor leesbaarheid, duidelijke bestemmingen en de scheiding tussen profiel en content; de zijbalk wordt niet overgenomen.

Apple-bron: https://support.apple.com/en-euro/guide/tv/atvb59b423ba/27/tvos/27

## Verificatie en grenzen

De beelden zijn gerenderd uit bewerkbare SVG-broncode en visueel gecontroleerd. De routemapping is opgenomen in `pariteit-v4.csv`. De controle bewaakt ook de exacte navbarvolgorde, één profielingang, het originele woordmerk en de aparte actieve/focusstaat. Het ontwerp is statisch. Simulatorfocus, alle combinaties van rechten/koppelingen, dynamische teksten en een fysieke Siri Remote zijn **niet getest**. Er is geen Pleya-appcode gewijzigd en er is niets uitgebracht.

## Opnieuw renderen

Vereist Node.js, `sharp` en Fontconfig. Vanuit deze map:

```bash
FONTCONFIG_FILE="$PWD/fonts.conf" node render-northstars.cjs --v4
```

De fontconfig gebruikt de meegeleverde Inter-fonts. Eerdere ontwerpvarianten in de renderbron zijn historisch; alleen `--v4` correspondeert met dit pakket.
