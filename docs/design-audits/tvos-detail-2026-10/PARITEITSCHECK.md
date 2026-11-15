# Pariteit met `2026-10-30`

Referenties staan buiten de repo in `/Volumes/SSD/Projects/PlexFlixNetwork/pleya-northstar-refs/2026-10-30/` (`01.png` en `03.png` tot en met `12.png`, 3840 x 2160). Per scherm naast de simulator gelegd, de activiteitsregel opnieuw op 31 oktober. Maten in 1920-punten via `TvHig`. Het Verify-bewijs staat in `MANIFEST.md`. Besluit: [DEC-171](../../DECISIONS.md).

| Punt in het beeld | Beeld | Resultaat | Toelichting |
|---|---|---|---|
| Smalle zijbalk links | 01, 03, 06 | afwijking | de inklapbare topnavigatie blijft, besluit Michel. Alleen de linkermarge volgt het beeld |
| Tabs Serie, Season N, witte pil onder focus, omlijnde pil op de open tab | 01, 03 | gehaald | `tvos.detail.series`, `tvos.detail.season` |
| Titellogo met tekstterugval | 03, 06 | gehaald, per backend | Pleya Server levert geen logo op de wire, daar staat de titel |
| Metaregel en scores | 03, 06 | gehaald, per backend | wat de backend levert; zonder score geen icoon |
| Kijkwijzer "age 8+" | 03, 06 | niet gebouwd | geen backend mapt hem; hij verschijnt niet als gat |
| Regisseur | 06 | gehaald | |
| Geen Meer lezen naast de synopsis | 03, 06 | gehaald | loopt de tekst over, dan is de synopsis zelf de focusstop boven de acties en opent Select de volle tekst (DEC-109 blijft bereikbaar) |
| Witte pil Hervatten met ring en resterende tijd | 06 | gehaald | `06-hero`. Onder focus groeit de pil vanaf zijn linkerrand en blijft hij op de marge; tekst 23 pt halfvet, ring 28 pt |
| Ronde acties | 01, 03, 06 | gehaald | volgorde uit het actiemodel |
| Activiteit met avatars en namen | 01, 03, 06 | gehaald, met afwijking | "Activity by you, omarf753, and 1 other". Avatars zijn initialen, het protocol kent geen avatar. Plex zegt "Watched by" uit zijn eigen pad |
| Seizoensactiviteit onder de acties | 01 | gehaald | eigen namen per seizoen op Pleya Server |
| Technische labels rechts | 06 | gehaald, per backend | een voorspelling, zie `detail_track_preview.dart`. Zonder sporen geen label |
| Lange audiowaarde in het paneel | 12 | gehaald | de waarde staat kleiner en halfvet rechts (20 pt), zodat een volledig spoor met Atmos op één regel past |
| Rij seizoensposters met naam en aantal | 03, 04 | gehaald | |
| Brede kaarten met seizoenkaart en A1, A2 met vinkje | 01 | gehaald | `01-season-card`, `01-episode` |
| Cast & Crew met ronde portretten | 04, 06, 07 | gehaald | initialen zonder foto |
| Ratings & Reviews | 07 | gehaald, alleen films | Plex-reviews op film |
| Discussies, kaart met naam, context, datum, tekst | 04, 05, 07, 08 | gehaald, met afwijking | bron is Trakt. Likes alleen als getal, geen like-knop en geen reacties op reacties |
| Discussies per seizoen | 04 | afwijking | seizoensreacties staan op tab Serie, de seizoentab blijft de compositie van 01 |
| Trailers & Extras | 05, 08 | gehaald, per backend | geen extras, geen sectie |
| Collectie, Meer met acteur | 05, 08, 09 | gehaald, per backend | eigen bibliotheek |
| Tracks-sectie, pagina soundtrack | 10, 11 | weggelaten | besluit Michel; de onderkant van 10 wijkt daarmee af |
| Paneel Meer acties rechts, kop, witte pil | 12 | gehaald | `12-panel` |
| Audiostream, Ondertitels | 12 | gehaald | met de huidige waarde |
| Add to List | 12 | gehaald, per backend | heet Toevoegen aan kijklijst. Plex en Jellyfin; niet op Pleya Server, zie DEC-171 |
| Add To Playlist / Collection | 12 | gehaald, per backend | Plex, Jellyfin en Emby; alleen Playlist zonder beheerrechten; niet op Pleya Server |
| Watch Trailer, gekeken, Beheren, Bestandsinformatie | 12 | gehaald | Beheren alleen met rechten en vóór Bestandsinformatie. Van de twee markeringen staat alleen die in het paneel die de ronde knop niet doet; Afspelen vanaf het begin alleen zonder ronde herstartknop |
| More Ways to Watch | 12 | niet gebouwd | geen bron in Pleya; versies staan op de rij Versie |
| Achtergrond uit het artwork, vast tijdens scrollen | 03, 04, 06, 07 | gehaald | één vaste laag: het geblurde artwork door één kleurmatrix, die 0,7 van de kleur en 0,3 van de helderheid houdt, in het donker naar grijs 40 in plaats van zwart. Witte tekst houdt minstens 4,5:1 boven elke kleur (`tv_detail_page_test.dart`). Prestaties op een echte Apple TV staan open |
| Nederlandse en Engelse labels door elkaar | 12 | afwijking | de app volgt de taalkeuze |

Discussies komen pas onder de hero binnen. Een net geopende pagina vraagt Trakt niets, dus de eerste secties kunnen later verschijnen dan op de referentie.
