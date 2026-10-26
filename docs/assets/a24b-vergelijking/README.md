# A-24b: northstar naast build

Vergelijkingsbladen voor ronde A-24b (Roadmap A-24). Op elk blad staat links de northstar uit [`docs/assets/a24b-northstars/`](../a24b-northstars/README.md), rechts de screenshot uit de simulator in dezelfde staat. Bijbehorende toets per regel: [`docs/plans/AFWIJKINGEN_A24B.md`](../../plans/AFWIJKINGEN_A24B.md).

De screenshots komen uit Pleya Verify-runs met de fixtures `catalog.studio-art.v1` (zes Blender-films, CC BY, posters en achtergronden) en `watchlist.studio.v1`. iPhone Instellingen draaide op de iPhone SE-simulator (750x1334), iPhone Mijn Pleya op de iPhone 17 Pro-simulator (1206x2622), Apple TV op de Apple TV 4K-simulator (3840x2160). Geen van deze beelden komt van echte hardware.

## De zes hoofdvergelijkingen

| Bestand | Northstar | Build-staat |
| --- | --- | --- |
| `01-iphone-instellingen-donker.jpg` | `01-ios-studio-dark.webp` | hoofdpagina Donker, na scrollen, en OLED |
| `02-iphone-instellingen-licht.jpg` | `03-ios-studio-light.webp` | hoofdpagina Licht en Weergave Licht |
| `03-appletv-instellingen-donker.jpg` | `02-tvos-studio-dark.webp` | Weergave in OLED en Donker, focus op Thema |
| `04-appletv-instellingen-licht.jpg` | `04-tvos-studio-light.webp` | Weergave in Licht, focus op Thema |
| `05-iphone-mijn-pleya.jpg` | `00-ios-geselecteerd.png` | bovenkant in OLED, Donker en Licht |
| `06-appletv-mijn-pleya.jpg` | `01-tvos-landing.png` | landing in OLED en Donker, focus op Profiel wisselen |

## Aanvullende staten

| Bestanden | Wat |
| --- | --- |
| `iphone-instellingen-*.jpg` | de vervolgborden uit `alle-instellingen/ios/` naast Weergave, Bibliotheek & Home, Afspelen, Taal, Ondertitelstijl, Downloads, Koppelingen, Servers en bronnen, Geavanceerd en Back-up, in drie thema's |
| `appletv-instellingen-{weergave,afspelen,taal,bronnen}.jpg` | de borden `02-weergave-01`, `03-afspelen-01`, `04-taal-ondertitels-01` en `10-bronnen-01` naast dezelfde categorie, donker en licht |
| `iphone-mijn-pleya-gescrold.jpg`, `iphone-mijn-pleya-leeg.jpg` | onderkant van de pagina, en de lege toestand (lege catalogus, geen kijklijst) |
| `appletv-mijn-pleya-posterfocus.jpg` | `02-tvos-posterfocus.png` naast focus op de tweede poster |
| `appletv-mijn-pleya-instellingenfocus.jpg` | `03-tvos-instellingenfocus.png` naast focus op Instellingen |
| `appletv-mijn-pleya-conditioneel.jpg` | `04-tvos-conditioneel.png` naast een profiel zonder kijklijst en een profiel met Seerr |
| `appletv-mijn-pleya-licht.jpg` | `05-tvos-licht.png` naast Licht |

## Herkomst per blad

De bladen `01`, `02`, `06` en `appletv-mijn-pleya-posterfocus` zijn na de reviewronde opnieuw gemaakt met de eindcode (`819e0997`): App-taal staat niet meer in Weergave en een TV-kijklijstkaart toont zijn titel op twee regels. Blad `05` komt van `bd1b80cc`, de iPhone-build met Big P van eerder in fase 6. De overige bladen komen uit de bouwfasen: iPhone Instellingen-vervolgborden van `68a49409`, Apple TV Instellingen van `df4ceefa`, iPhone Mijn Pleya gescrold en leeg van `b7d28c92`, Apple TV Mijn Pleya van `43de9fc9`. Na die standen zijn de Apple TV-schermen alleen via de Verify-ronde van fase 6 nagelopen, zonder nieuwe bladen; zie `AFWIJKINGEN_A24B.md` onder "Bewijsronde fase 6".
