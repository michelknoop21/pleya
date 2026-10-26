# Studio-art voor Pleya Verify

Posters (2:3) en achtergronden (16:9) voor de fixture `catalog.studio-art.v1`
en de kijklijstseed `watchlist.studio.v1`. Ze bestaan zodat een screenshot van
Instellingen of Mijn Pleya echte filmbeelden toont in plaats van effen vlakken.
De fake server leest deze bestanden ongewijzigd in; `test/studio_art_test.dart`
legt per bestand de sha256 vast, dus elke run serveert dezelfde bytes.

Alle beelden komen van de open films van de Blender Foundation en Blender
Studio. Ze stonden al in deze repo onder `docs/assets/ios-unified/detail-2026/`
(commit 96cdde7a) en zijn hier alleen bijgesneden met `sips`.

| Bestand | Film | Rechthebbende | Licentie | Bewerking |
| --- | --- | --- | --- | --- |
| `sintel-poster.jpg` | Sintel (2010) | Blender Foundation | CC BY 3.0 | `sintel-poster.jpg` bijgesneden tot 448x672 |
| `sintel-backdrop.jpg` | Sintel (2010) | Blender Foundation | CC BY 3.0 | `sintel-wide.jpg` bijgesneden tot 1188x668 |
| `bbb-poster.jpg` | Big Buck Bunny (2008) | Blender Foundation | CC BY 3.0 | midden van `bbb-wide.jpg`, 444x666 |
| `bbb-backdrop.jpg` | Big Buck Bunny (2008) | Blender Foundation | CC BY 3.0 | `bbb-wide.jpg` bijgesneden tot 1188x668 |
| `tears-poster.jpg` | Tears of Steel (2012) | Blender Foundation | CC BY 3.0 | bijgesneden tot 448x672 |
| `spring-poster.jpg` | Spring (2019) | Blender Animation Studio | CC BY 4.0 | bijgesneden tot 446x669 |
| `charge-poster.jpg` | Charge (2022) | Blender Studio | CC BY 4.0 | bijgesneden tot 424x636 |
| `coffeerun-poster.jpg` | Coffee Run (2020) | Blender Studio | CC BY 4.0 | bijgesneden tot 532x798 |
| `tears-backdrop.jpg`, `spring-backdrop.jpg`, `charge-backdrop.jpg`, `coffeerun-backdrop.jpg` | als de poster | als de poster | als de poster | 16:9-uitsnede uit het midden van de poster, opgeschaald naar 1280x720 |

Voor vier films bestaat in de repo geen breed beeld, vandaar de uitsnede uit de
poster. Die is zachter dan een echte still; Sintel en Big Buck Bunny staan
daarom vooraan in de rijen die de Studio-kop en de Home-hero lezen.

Naamsvermelding volgens de licenties: (c) Blender Foundation, www.blender.org,
en (c) Blender Studio, studio.blender.org. Alleen voor test- en
simulatorbewijs; deze map gaat niet mee in een app-build.
