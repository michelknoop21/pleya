# Lokale bibliotheek: metadata en posters

Roadmap: A-06. Productkeuzes uit het gesprek met Michel op 23 oktober 2026.
Dit is het goedgekeurde ontwerp na de grill-me-vragen. Implementatie op `feat/local-library-cache` is gericht en native op iPhone
geverifieerd; onafhankelijke code-/rechten- en fixreview zijn akkoord.
Releasepakket 405 / PR #477 bundelt deze wijziging; fysieke prestatieacceptatie blijft open. De iPhone-kroon gebruikt tijdens slepen nu één doorlopende
scrollactiviteit, zodat elke kleine beweging geen aparte scrollstop veroorzaakt.
Vloeiendheid op het fysieke toestel blijft afzonderlijke acceptatie.

## Afgesproken werking

- Eén instelling **Bibliotheek vooraf opslaan**, standaard uit, geldt voor alle
  voor het actieve Pleya-profiel toegankelijke bibliotheken tegelijk. Geen
  selectie per bibliotheek; geen toegang tot de opslag van andere profielen.
- Bij inschakelen worden alle beschikbare metadata en posters vooraf lokaal
  opgeslagen: films, series, seizoenen en afleveringen, met beschrijvingen,
  genres, castnamen en technische gegevens voor zover de bron ze levert.
  Videobestanden worden hierdoor niet gedownload.
- **Alleen via wifi** staat standaard aan en is instelbaar; de gebruiker kan
  mobiele data toestaan. Ethernet geldt als toegestane vaste verbinding.
- Na de eerste download worden nieuwe en gewijzigde gegevens automatisch
  bijgewerkt binnen de netwerkvoorkeur. Pleya blijft tijdens het bijwerken
  bruikbaar. De browser leest aanwezige lokale gegevens en posters direct.
- De instellingen tonen voortgang, laatste synchronisatie en opslaggebruik.
- Uitschakelen stopt automatisch vooraf ophalen en bijwerken, maar wist niets.
  Een aparte actie **Lokale bibliotheek wissen** verwijdert deze lokale opslag;
  dit is geen verwijdering van serverinhoud of gedownloade video's.
  Wissen raakt alleen deze functie binnen het actieve profiel en annuleert
  lopend werk met een generatiegrens, zodat late antwoorden de gewiste opslag
  niet opnieuw vullen. Na de bevestiging om te wissen krijgt de gebruiker
  meteen de keuze **Vooraf ophalen uitzetten** of **Bibliotheek opnieuw
  ophalen** (aanvulling Michel). Wissen pauzeert het vooraf ophalen; alleen
  de tweede keuze zet het opnieuw aan en start een nieuwe generatie binnen
  de netwerk- en opslagvoorwaarden. Geen keuze, sluiten of onderbreken laat
  vooraf ophalen uitgeschakeld, ook na een herstart. De bestaande eenvoudige
  cache voor gewone navigatie is niet hetzelfde als deze volledige opslag.
- Bij te weinig vrije opslag pauzeert het ophalen, met een zichtbare reden.
  Pleya verwijdert geen oudere gegevens om ruimte te maken. Hervatten gebeurt
  zodra er voldoende ruimte is; de vrije-ruimtebuffer is 256 MiB en het pauze-/hervatpad is gericht getest.
- De opgeslagen bibliotheek blijft offline doorzoekbaar en te bekijken, met
  een offline-aanduiding. Afspelen vereist de server of een los gedownload
  videobestand. Nog niet opgehaalde gegevens worden niet als volledig getoond.

## Verwijderde serverinhoud

Aanvulling van Michel: als de server films of series verwijdert, verwijdert
Pleya ook hun opgeslagen metadata en afbeeldingen. Dit is opruimen van
bevestigd verdwenen inhoud, geen automatische verwijdering bij ruimtegebrek.

Uitvoeringsregels die dit veilig en correct maken:

- Alleen een gezaghebbende verwijdermelding of een volledig geslaagde scan
  van de betreffende bibliotheek mag het verdwijnen van bronitems bevestigen.
  Time-outs, offline servers, ontbrekende pagina's, filters en mislukte of
  afgebroken synchronisaties zijn geen bewijs van verwijdering.
- Opschonen gebeurt zodra zo'n bevestiging wordt verwerkt; Pleya kan een
  verwijdering niet vaststellen zolang er geen servercontact is. Uitschakelen
  start geen achtergrondsynchronisatie, maar houdt het opruimen na een later
  ontvangen geldige verwijderbevestiging niet tegen.
- Een verwijderde serie ruimt ook de lokaal opgeslagen seizoenen en
  afleveringen van die bron op. Afbeeldingen worden pas gewist als ze niet
  meer door andere geldige lokale items worden gebruikt.
- Een titel op meerdere servers blijft zichtbaar zolang er een toegankelijke
  bronkopie bestaat; alleen de verdwenen bronkopie valt weg. Een bron die door
  rechtenverlies niet meer toegankelijk is, mag geen toegankelijke kopie
  achterlaten. Bewaar strikt de bestaande profiel- en rechtenisolatie.
- De eigen opslag van deze functie heeft een afgebakende eigenaar. Opschonen
  raakt geen bestanden die nog nodig zijn voor apart gedownloade video's of
  andere gebruikers/profielen. Snapshots en artwork staan in een eigen map per
  profiel; referenties worden over alle opgeslagen bibliotheken van dat profiel
  bepaald. Afzonderlijke videodownloads blijven buiten deze map.

## Unified impact en bestaande bouwstenen

De gedeelde catalogus, identiteit en bronkeuze blijven eigenaar; geen tweede
catalogus per leverancier. Beoordeel Plex, Jellyfin, Emby, lokale mappen/Pleya
Share en Pleya Server afzonderlijk op hun bestaande leesmogelijkheden. Alleen
beschikbare metadata worden opgeslagen; geen verzonnen API of gelijkheid.
De netwerkkeuze en voortgang horen bij de bestaande instellingen/providerflow.
Profielwissels moeten lopend werk annuleren en mogen nooit catalogi mengen.

Broninspectie op main `71521bd7`:

- `lib/services/image_cache_service.dart`: bestaande persistente artworkcache
  in Application Support, met 14 dagen stalePeriod en een grens van 3000
  bestanden. Deze begrensde cache biedt op zichzelf geen garantie dat alle
  vooraf opgeslagen posters bewaard blijven. Onderzoek de werkelijke
  cache-evictie en een afgebakende persistente opslag voor deze functie.
- `lib/screens/libraries/tabs/library_browse_tab.dart`, `_prefetchImages`:
  haalt slechts twee rasterrijen vooruit en maakt een
  `CachedNetworkImageProvider` zonder de expliciete cacheKey en zonder de
  `ResizeImage`-vorm van de posterweergave. `OptimizedMediaImage` gebruikt wel
  `artworkCacheKey` en `ResizeImage`; dit is een concrete mismatch, nog geen
  gemeten verklaring voor alle wachttijd of het stotteren.
- `lib/services/unified_catalog/unified_artwork_prefetcher.dart`: bestaand
  voorbeeld dat provider, cachesleutel en decodevorm wel met de weergave deelt,
  met begrensde gelijktijdigheid en een vooruitlaadvenster.
- `lib/services/unified_catalog/catalog_service.dart` en
  `lib/providers/unified_catalog_provider.dart`: huidige gepagineerde merge en
  profielgebonden lifecycle. De lokale projectie sluit op deze eigenaren aan via een profielgebonden provider
  en een afzonderlijke persistente opslag; de gewone tijdelijke cache blijft begrensd.
- `lib/services/api_cache.dart` en `lib/database/`: bestaande Drift/API-cache
  en offline/downloadopslag; een herbruikbare bouwsteen, geen bewijs dat de
  volledige lokale catalogus al bestaat. Geen ongedifferentieerd gebruik van
  download-pinning als eigenaar voor deze nieuwe functie.
- `lib/providers/offline_mode_provider.dart`: bestaande monitoring van netwerk,
  wifi/ethernet en bereikbare servers; voorkom een tweede losse netwerkmonitor.

Een volledige bibliotheekdownload kan lang duren. iOS bepaalt hoeveel werk
doorloopt als de app niet actief is; beloof geen onbeperkte achtergrondtijd.
Werk moet onderbreekbaar en hervatbaar zijn zonder de bestaande snapshot te
verliezen. De concrete planning daarvan is implementatieonderzoek.

## Verificatie vóór oplevering

1. Negatieve controles voor cache-identiteit, profielisolatie en hervatten.
2. Een gevulde fixture geheel lokaal doorzoeken en bekijken na herstart zonder
   netwerk. Eerste download, incrementele wijziging en ontbrekende velden.
3. Verwijdering van film en serie inclusief kinderen; twee bronkopieën,
   gedeelde afbeeldingen en aparte videodownloads blijven correct.
4. Een offline/halve/mislukte scan verwijdert niets; late antwoorden na een
   profielwissel schrijven niets in het volgende profiel.
5. Wifi/mobiele data, uitzetten tijdens ophalen, lage opslag en handmatig wissen.
6. Gerichte tests en `scripts/ci_checks.sh`; native Pleya Verify en gelezen
   beelden voor instellingen, voortgang en offline weergave. Afzonderlijke
   prestatiemetingen voor langzaam kroon-slepen en cache-hit/miss-paden;
   eindpuntassertions bewijzen geen vloeiende frames.
7. Onafhankelijke code-/rechtenreview, normale PR-checks en review vóór merge.
   TestFlight-beschikbaarheid en fysiek vloeiend scrollen apart aantonen.

## Vergelijking

Infuse Library Mode bewaart metadata lokaal; Pre-Cache Images voegt vooraf
opgehaalde afbeeldingen toe. Direct Mode haalt naar behoefte op. Pleya neemt
de gekozen lokale werking over binnen de eigen gedeelde architectuur.

- [Infuse Library/Direct Mode](https://support.firecore.com/hc/en-us/articles/360006462093-Streaming-from-Plex-Emby-and-Jellyfin)
- [Firecore over metadata en posters vooraf ophalen](https://community.firecore.com/t/spinning-circle-never-goes-away/41883/6)
- [Firecore over opslaggebruik en metadata wissen](https://community.firecore.com/t/how-to-clear-delete-streamed-cache-in-infuse/38487)
- [Plex Mobile: wifi en opslaglimiet voor videodownloads](https://support.plex.tv/articles/205671068-settings-plex-mobile/)

De geraadpleegde Infuse-uitleg specificeert niet expliciet wat uitschakelen
met bestaande bestanden doet. Behouden bij uitschakelen is Michels eigen
afgesproken Pleya-keuze, geen claim over Infuse.
