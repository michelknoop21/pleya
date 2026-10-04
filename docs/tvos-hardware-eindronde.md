# tvOS-hardware-eindronde, TV9

Checklist voor de laatste ronde op de Apple TV 4K, volgens `docs/unified-2026-closure.md` §7. Eén
vaste build: de archive die in fase 3 van het TV9-plan wordt gemaakt en die daarna ongewijzigd naar
TestFlight gaat. Vraagt een punt hieronder een codewijziging, dan gaat de gate weer open (§7 punt
5): nieuwe SHA, nieuwe archive, en de delen van deze lijst die de wijziging raakt opnieuw.

## Build-identiteit

Ingevuld op 24 september, vóór de upload naar TestFlight.

| Veld | Waarde |
|---|---|
| SHA op `main` | `3bd976dff2579c436e4145c1958df993a6af7b41` |
| Versie en buildnummer | 2.8.0 (299), TestFlight tvOS |
| Configuratie en compile-time flags | Release, `tvos_archive`-lane (geen extra `--dart-define`) |
| SHA-256 van de `.xcarchive` | `433bb27ab73f795697f88bc00141551bff808a25d21e170c35b7b35e054a0176` (`Pleya-tvOS-299-3bd976df.xcarchive`) |
| Binary markers geteld | 5 van 5: `tv.search.pill` (VIS1), `media-detail.season-chips` (VIS2), `appearance.rows` (APP1), `TvHig` en `TvSettingsDensity` (DENS1); Verify-ids uit de registerlijst zitten niet in een Release-binary |

## 1. PLR6 eerst

PLR6 is de enige blokkerende `HARDWARE ONLY`-rij. Hij gaat vooraan, zodat een fout de ronde meteen
stopt in plaats van na een uur routes.

1. Start een film en open het spelerpaneel (swipe omlaag of de info-knop).
2. Zet de focus op een rij in het paneel.
3. Druk één keer op Menu. Verwacht: het paneel sluit en de speler loopt door.
4. Druk nog een keer op Menu. Verwacht: de speler sluit en je staat terug op de detailpagina.

Hangt de afstandsbediening na stap 3 of 4, of moet de app geforceerd dicht: stop de ronde, stuur
het lognummer mee (debuglogging vooraf aan) en noteer de stap. De Dart-kant is groen
(`test/widgets/tv_info_panel_test.dart`, contract "Menu closes the panel from a focused row"), dus
een fout hier zit in het native drukpad.

## 2. Geluid

| Rij | Wat je doet | Goed is |
|---|---|---|
| AUD1 | Speler, Audio-tabblad, Volumeversterking op +50%, +100%, +200% | Elke stap hoorbaar luider |
| AUD3 | Zelfde, bij een luide scène | Geen vervorming of kraak bij +200% |

## 3. Routes

Per route de vier pijlen, Select, Menu, lang Select en Play/Pause waar dat iets doet. Let op: de
focusring nooit afgesneden, de kolom behouden na terugkeer, nooit twee focusindicatoren, geen
paneel of pagina zonder uitweg. De kolom "Simulator" zegt welk Verify-scenario de route met Menu
terug al groen heeft op de fase-2-SHA; die routes zijn op hardware een controle, de rest is nieuw
terrein.

| Route | Simulator | Hardware |
|---|---|---|
| Home | `tvos.home.hero-return-from-route` | controle |
| Films (catalogus) | `tvos.catalog.sort-order`, `tvos.catalog.rail-sort-focus` | controle |
| Series (catalogus) | geen journey met Menu terug | HARDWARE ONLY |
| Overige catalogi | geen | HARDWARE ONLY |
| Filters | alleen de sorteerkant (`tvos.catalog.sort-order`) | bronfilter en bibliotheekfilter HARDWARE ONLY |
| Sorteren | `tvos.catalog.sort-order` | controle |
| Detail | `tvos.detail.movie`, `tvos.detail.context-menu`, `media-detail.episode-refresh` | controle |
| Bronkeuze | geen (MOC-11 alleen als golden) | HARDWARE ONLY |
| Speler | `tvos.player.osd` | controle |
| Spelerpaneel | `tvos.player.panel` | na PLR6 |
| Zoeken | `tvos.search.results` | controle |
| Mijn Pleya | `tvos.my-pleya.sections`, `tvos.my-pleya.regression` | controle |
| Bibliotheken | `tvos.my-pleya.libraries-bronbeheer` | controle, plus REV1b |
| Kijklijst | geen (WL2 ACCEPTANCE GAP) | HARDWARE ONLY |
| Aanvragen | `tvos.my-pleya.requests-discover` zonder Menu | HARDWARE ONLY |
| Activiteit | geen (ACT1 wacht op PS-9) | HARDWARE ONLY |
| Instellingen | `tvos.settings.*`, `tvos.my-pleya.section-settings` | controle, plus DENS1 |
| Profielwissel | `tvos.profile.picker` | controle, plus PROF1 |
| Offline | `tvos.offline.home` zonder Menu | HARDWARE ONLY |
| Herstel na verbroken server | `tvos.nav.reconnect-pill-focus` zonder Menu | HARDWARE ONLY |

REV1b: open Mijn Pleya, Bibliotheken, en kies een Jellyfin-bibliotheek met een onbekend
collectietype. Ze moet te openen zijn.

## 4. Systeem

| Rij | Wat je doet |
|---|---|
| J2 4K-output | Apple TV op 4K, Home en detail bekijken: scherp, niets geschaald of afgesneden |
| J4 overscan | Instellingen van de tv met overscan aan: focusring en tekst blijven binnen beeld |
| J8 VoiceOver | VoiceOver aan, Home, detail en Instellingen: elk focusdoel wordt voorgelezen |
| J9 Reduce Motion | Toegankelijkheid, Verminder beweging aan: geen hero-wissel of schuifanimatie |
| MOC-31 | Taal en ondertitels: de vier lagen, een serie met eigen keuze houdt die keuze |
| MOC-33 | Spelerinfopaneel is het enige spelermenu |

## 5. Rijen met HARDWARE OPEN

Code en simulator zijn dicht; op de tv bekijken of het klopt.

| Rij | Waar kijken |
|---|---|
| DENS1 | Instellingen, filmdetail, seriedetail op de 77 inch: leest het nu normaal |
| VIS1 | Zoeken: pil half zo breed als het scherm, aantal rechts in de pil |
| VIS2 | Seriedetail: "Afleveringen", seizoenchips en aantal op één regel, nergens overlap |
| APP1 | Uiterlijk: LEFT vanuit elke rij naar de actieve categorie, RIGHT naar de eerste rij |
| OFF6 | Server kort weg en terug terwijl je in Mijn Pleya staat: je blijft op dezelfde pagina |
| PROF1 | Profielknop linksboven: profielpoort, Menu sluit hem en de focus staat op de knop |
| PLR10 | Slaaptimer: "5 min" met spatie |
| PLR11 | Volgende aflevering en Aftiteling overslaan met focus: geen zwarte hoekjes in de rand (alleen als de Liquid Glass-fix in deze build zit) |
| LANG1 | Taalkeuze blijft hangen tussen afleveringen van dezelfde serie |
| LIB7, MYP1 | Mijn Pleya en Bibliotheken als bronbeheer |

De rijen LIB8, HERO8, HERO9, NLX2, NLX3 en de UX23-rijen staan in de correctieronde nog op
`VERIFY/SIM OPEN`. Ze horen bij de Netflix-redesignlijn en zitten al in deze build. De simulator
kan ze niet tonen omdat de `/v1`-fixture geen hero-statussen, releasedata of collecties levert, dus
op de tv:

| Rij | Waar kijken |
|---|---|
| HERO8 | Home-hero: capsule `Bekeken`, `Bezig · <percentage>` of `Niet bekeken`, knoppen blijven op hun plek |
| HERO9, UX23-HERO | Home-hero wisselt door tot twaalf recente films, geen dubbele |
| LIB8 | Mijn Pleya, `Jouw verzameling`: Collecties en Afspeellijsten openen en Menu brengt je terug |
| NLX2, UX23-ROWS | Home-indeling: rijen met dezelfde naam zijn te onderscheiden (`Films · Zolder`) |
| NLX3, UX23-PREF | Verbinding toevoegen: alle zes routes bereikbaar met de pijlen |

## Uitslag doorgeven

Per rij "goed" of "fout". Bij fout: wat je deed, wat je zag, een foto als het om beeld gaat, en het
lognummer (`ice.pleya.app/logs/<nummer>`).
