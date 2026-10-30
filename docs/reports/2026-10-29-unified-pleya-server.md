# Unified: Pleya Server naast Plex, Jellyfin en Emby

Roadmap: A-07 (serverdeel C-05 / S22, register X5). Besluit: DEC-XXX, protocolvenster bekrachtigd door Michel op 30 oktober 2026 (optie 1, volledig venster). Branch `feat/unified-pleya-server`, basis `main` d9edacc.

## Wat er veranderd is
- Server: `external_ids.tmdb` op film en serie bij een geslaagde match (`store_metadata.go`, `wire.go`), protocol 9.4a, openapi, fixture, `schema.d.ts`.
- App: `PleyaItem.externalIds`, `fetchExternalIds`, `findByIdentity`/`findAllByIdentity` (alleen TMDB, per soort, gepagineerd), Pleya Server identiteitsgeschikt, uitsluiting uit `grouping_service.dart` weg (Pleya Share blijft), geen titelterugval voor paren met Pleya Server, lokale bibliotheekcache pint geen leeg Pleya-antwoord, hidden-library fail-closed voor Pleya-zoektreffers.

## Bewijs (Linux, geen toestel)
- Flutter: 8516 tests in `services media pleya_server providers utils models screens/home screens/tv widgets` groen op 2 na (`local_folder_scan_cache`: chmod 000 helpt niet als root, los van deze wijziging); `assistant` en de gewijzigde suites daarna opnieuw groen.
- Nieuw: `unified_pleya_server_test.dart` (zes paren, alle vier, meerdere servers per type, paging, verversen, herstart, ontkoppelen, offline bron, afspeelplan van de Pleya-bron, Verder kijken, zoeken, afwijkende nummering, seizoenen), `pleya_server_external_ids_test.dart`, uitbreidingen in watchlist-, resolver-, trakt- en lokale-bibliotheektests.
- Negatieve controles rood: Pleya terug in `_neverMergedBackends`, terugvalguard weg, `fetchExternalIds` leeg, niet identiteitsgeschikt, watchlistpredicaat, lokale cache, Go-statusfilter.
- Go: `TestMatchedTitlesCarryTheirTMDBID`, `TestSeriesIDsStayOnTheShow` op lokale Postgres 16; `internal/api` en `catalog` groen; antwoorden gevalideerd met `check_server_responses.py`; `check_protocol.py` groen.
- Echte runtime, lokaal: Go-serverproces (deze branch) met scratch-Postgres en drie ffmpeg-testbestanden. Voor: `external_ids` null; na een matchrij: `{tmdb: 95396}` voor Severance, null voor "Unmatched Show". Echte `PleyaServerClient` leest het, groepeert met een Plex-gevormde bron tot één kaart en houdt een remake apart (`pleya_server_external_ids_live_test.dart`, tag live). De matchrij is met SQL gezet: de TMDB-provider is hier niet bereikbaar.
- `scripts/ci_checks.sh --with-unused`: format, codegenvers, analyze en DCL groen; alleen "native format" faalt omdat `swift-format` hier ontbreekt (geen nativebestanden gewijzigd).
- Onafhankelijke review: 0 kritiek, 5 belangrijk, 6 klein. Vijf belangrijke en M2 tot M4 verwerkt met tests. M1 (Plex-titel zonder TMDB geeft blijvend "niet alles gecontroleerd") en M5/M6 blijven bewust staan.

## Tweede ronde (na /code-review high en opmerkingen Michel)
- Jaar-bucket opgelost: `CanonicalMediaIdentity.resolutionKey` (titel zonder jaar voor film en serie) bepaalt nu welke items een id-lookup krijgen. Zelfde TMDB-nummer met ander jaar op de twee servers voegt samen; een ander nummer (remake) of ander soort blijft apart. Regressietest `the same proven TMDB number folds even when the two servers disagree on the year`, rood zonder de wijziging. De samenvoeging zelf blijft op identieke nummers; de jaar-gevoelige terugval gebruikt nog `bucketKey`.
- Review-punten verwerkt: scan breekt niet meer op een mislukte Pleya-lookup en een mislukte lookup telt als onbekend in de lokale cache; geen tweede verzoek direct na `fetchItem`; lookup met limiet 500; SQL beperkt tot film en serie (test met negatieve controle); een identiteit zonder TMDB-nummer telt voor Pleya Server als niet van toepassing in plaats van mislukt; `pleya_server/CLAUDE.md` bijgewerkt.
- Pleya Share: `MediaBackend.local` stond al in `_neverMergedBackends` en is onveranderd; geen lokaal pad is aangeraakt.
- `local_folder_scan_cache_test.dart` is als gewone gebruiker (`tester`) opnieuw gedraaid: groen. De twee falers waren root-artefacten.
- `swift-format` ontbreekt in deze omgeving; de native formatcontrole moet in CI draaien. Geen gate is omzeild.
- *Achterhaald in de derde en vijfde ronde (filter `external_id`, nummers uit het lijstantwoord).* Bewust niet opgelost: een titel die op de servers anders heet (bijv. "The Office (US)" tegenover "The Office") vindt de identiteitszoekactie niet, want het contract kent geen zoekopdracht op nummer. De catalogusgroepering (resolutionKey) heeft dat probleem ook bij verschillende titels. Dat vraagt een serverfilter op `external_id` en dus een eigen protocolbesluit.
- De echte serverproef zet de matchrij met SQL; de automatische TMDB-keten (nfo, zoeken, `Decide`) heeft eigen Go-tests (`internal/metadata`) maar is niet tegen echt TMDB gedraaid.

## Niet bewezen
- iPhone en Apple TV met Plex en Pleya Server tegelijk: geen toestel, simulator of toegang tot Michels Plex of NAS in deze sessie. Geen voor/na-schermopname, geen bronkeuze of afspelen op een toestel. De keten tot en met bronkeuze en afspeelplan is op code- en servernivel getest; "unified werkt" is daarmee nog niet op een toestel aangetoond.
- Geen echte Plex of Emby; hun kant is nagebootst met de bestaande fake-clients.
- *Achterhaald in de vijfde ronde: de harness heeft nu een tweede fixtureserver en er is een scenario, dat nog niet op een simulator gedraaid heeft.* Het fixtureprotocol voor Verify heeft nog geen tweede server per scenario (zie DEC-101); er is geen Verify-scenario gemaakt.

## Bekende beperkingen
- *Achterhaald in de vijfde ronde: nummers uit het lijstantwoord voegen ook bij verschillende titels samen; alleen titels zonder meegestuurde nummers lopen nog via de titel.* De catalogus vergelijkt alleen items met gelijke genormaliseerde titel (het jaar telt niet meer mee). Een titel die per server anders heet blijft in het raster twee kaarten, terwijl de bronkeuze hem wel op nummer vindt. Dit is een open gat tegenover de wens "ook bij verschillende titels": oplossen vraagt een goedkope id-route voor Plex en Jellyfin (nu één verzoek per item) en is niet gedaan.
- Een Pleya Server zonder match, of een oudere serverversie, blijft eigen kaarten tonen.
- Plex-titel zonder TMDB-nummer, of een oudere Pleya Server: de server staat in de dekking als `cannotBeAsked` (niet gecontroleerd, geen negatieve cache). Dekking wordt voor zo'n profiel dus nooit volledig; dat is bewust gekozen boven een onterecht "niet aanwezig".

## Derde ronde (hersteldoel na tweede review)
- Fouten en cache: `IdentityLookupUnavailable` en `IdentityLookupUnsupported` (geen brede `StateError`-vangst). De scan tolereert alleen die twee, `MediaServerHttpException` en `TimeoutException`; een onverwachte `StateError` breekt hem nog steeds (test). Een mislukte opvraag slaat niets op; een antwoord van een server die het veld kent wordt als `pleyaLocalExternalIdsFinal` bewaard, ook als het leeg is, dus geen netwerk per schermopbouw; oude of niet-finale snapshots vragen opnieuw. Getest: 429, 500, 503, onbereikbaar, offline, timeout, herstel.
- Identiteit: opzoeken op `external_id=tmdb:<n>` (nieuwe optionele queryparameter plus capability `external_id_lookup`), per bibliotheek van de juiste soort, rechten en `libraryId` blijven kloppen, titel en jaar spelen geen rol. Ontbrekende capability is `Unsupported`, transport is `Unavailable`; geen van beide telt als gecontroleerde afwezigheid. De eerdere fail-closed regel voor verborgen bibliotheken is vervallen omdat treffers nu hun bibliotheek hebben.
- Kosten: nummers komen mee met lijst- en detailantwoorden (cache 60 s, max 5000). Gemeten met 600 Plex- en 300 Pleya-titels: 0 detailverzoeken naar de Pleya Server, 300 id-opvragingen op Plex (alleen titels die op beide staan). Server: geen query voor pagina's zonder film of serie (test, rood zonder guard) en kindguard in de SQL van het filter.
- Protocol: `pleya_server/CLAUDE.md` is teruggezet op de oorspronkelijke tekst. Het venster staat als scoped venster in DEC-XXX met de zes regels getoetst; Michel heeft het op 30 oktober 2026 bekrachtigd. De verouderde zin in CLAUDE.md over tabellen die niet bestaan (`metadata_candidates` bestaat sinds 0013) is niet aangepast en blijft een aparte docs-correctie.
- Nog steeds open: toestel- en Verify-bewijs, en de dubbele serie van Michel op iPhone en Apple TV.

## Vierde ronde (herreview van bd6b3d5)
- Verwerkt: I2/I4 `UncheckedSourceReason.cannotBeAsked` in plaats van uitsluiting uit de noemer (de eerdere "niet van toepassing"-regel is vervallen, test omgedraaid); I1 de scan vraagt een niet-finaal Pleya-antwoord opnieuw (de retentietak is voor Pleya nu onbereikbaar omdat de mapper geen `updatedAt` zet; de guard en test zijn defensief, de negatieve controle slaat daarom niet aan); M4 de server accepteert alleen `tmdb:` met kale cijfers (test, rood zonder regex); M6 rapport rechtgezet.
- Open en bewust: I3 lijsten buiten de bibliotheekpagina's (zoeken, hubs, Verder kijken) vullen de nummercache niet; I6 zie hierboven. I5 (bekrachtiging van het scoped venster) is op 30 oktober 2026 afgerond.

## Vijfde ronde (eindkandidaat cfe2e59 en verder)
Per soort bewijs apart.

**Unit- en integratietests (Linux, deze sessie)**
- Verschillende titels: identiteit beslist. Nummers die al in het lijstantwoord zitten (Plex `includeGuids`, Jellyfin `ProviderIds`, Pleya `external_ids`) voegen samen, ook bij een andere titel en een ander jaar; de titel verzamelt alleen kandidaten voor een opvraag. Remakes en verschillende series met dezelfde titel blijven apart (`unified_carried_identity_test.dart`, 13 tests).
- Kosten, gemeten met 600 Plex- en 300 Pleya-titels waarvan de lijst de nummers draagt: 0 id-opvragingen bij koude start, herbouw en accountwissel; een herscan met meegeleverde Guid 0, zonder 2. Zonder Guid en zonder gedeelde titel: 0 opvragingen en geen samenvoeging. De eerdere 300 Plex-opvragingen gelden alleen nog voor een Plex-server die de Guid-array niet meestuurt; dat blijft een echte kostenpost, één verzoek per titel die op beide staat.
- Identiteitsketen zonder SQL: `TestIdentityChainFromProviderToWire` laat de echte metadata-runner een match maken en leest het nummer via de API terug.
- Cachevernieuwing: metadatawijziging, serverupgrade (oud antwoord zonder veld, daarna met veld), rechtenwijziging en accountwissel getest, elk met een pad dat echt bereikt wordt.
- Gewijzigde Flutter-testbestanden (12): 446 groen. Verify-runner 405 groen, fixture-server 158 groen.
- Go-suite volledig in de gepinde testimage (`scripts/test-image.sh`: Go 1.26.10, ffmpeg 5.1.9) tegen de Docker-testdatabase uit `scripts/test-db.sh`: 29 pakketten groen, exit 0. De loudness-fout van eerder (`measured_duration_mismatch: gemeten 200 ms, probe 3000 ms`) komt alleen met de lokale ffmpeg 6.1.1 en ook op basis d9edacc; met de gepinde 5.1.9 slaagt `internal/loudness`. Reproduceren: `go test ./internal/loudness/ -run TestMeasureTracksARealLevelDifference -count=1` met systeem-ffmpeg 6.x.
- `local_folder_scan_cache_test.dart` op cfe2e59 als niet-rootgebruiker (uid 1000): 5 groen.
- `scripts/ci_checks.sh --with-unused` op cfe2e59 volledig groen, native formatting inbegrepen: `swift-format` uit de Swift 6.1-image (via Docker), clang-format 18 en ktlint 1.5.0. Geen gate overgeslagen.
- GitHub CI heeft op deze branch niet gedraaid: de workflows starten op `main`, `integration/**` en pull requests, en een handmatige dispatch geeft 403 voor deze sessie. Er is geen PR aangemaakt.

**Simulator**
- Niet gedraaid: deze omgeving is Linux zonder Xcode. Het scenario `ios.unified.two-servers.yaml` valideert (alle 145 scenario's), de harness voor een tweede fixtureserver en `connections_seed` is getest in de runner, maar het scenario zelf heeft nog geen screenshots opgeleverd. Rechten per bibliotheek en Plex zitten er niet in: de fixture kent geen rechten per gebruiker en spreekt alleen het Pleya-protocol.

**Fysieke toestellen**
- Niets gedraaid. Zie de checklist hieronder.

## Eindreview van cfe2e59 en herstel
Twee onafhankelijke reviewers (server/protocol/Verify en client): 0 kritiek, 6 belangrijk, 8 klein. Elke bevinding is eerst tegen de code gecontroleerd; bij elke correctie hoort een test die zonder de correctie rood was.
- Client I1 (belangrijkste): Plex-bibliotheekpagina's en -zoekresultaten liepen via `PlexMetadataDto.fromJson`, dat de Guid-array weggooit. De meting "0 opvragingen" gold dus alleen voor items met een al gevulde `raw`. Nu bewaren `_createTaggedMetadata*` de Guid via `fromJsonWithGuids`; test door de echte `PlexClient` (pagina en zoeken), rood zonder.
- Server I1: de tweede fixtureserver meldde `setup_required: true`, waardoor de app hem als afgemeld zou zien. `unified.pair.b.v1` is nu een server met eigenaar; fixturetest rood zonder.
- Server I2: de offline-stap tikte op `series.2`, dat bij een offline B niet bestaat. Het scenario wacht nu op twee kaarten en controleert Severance op index 1.
- Server I3 en M2: DEC-XXX (Pleya Server in unified) is rechtgezet: dekking is `cannotBeAsked`, het veld lezen vraagt geen vlag en `external_id_lookup` hoort bij de parameter; de punten lopen weer 1 tot en met 6.
- Server I4: het besluitnummer is vervangen door DEC-XXX; het nummer volgt bij de merge.
- Server M3: het verzoekenlog van de tweede fixture komt in de bundel (`fixture/requests-second.jsonl`); runnertest rood zonder.
- Server M4: de cursorvingerafdruk van een filterset zonder `external_id` is weer gelijk aan die van voor de upgrade; Go-test rood zonder.
- Client M1: een `external_ids` die niet aan het contract voldoet telt als niet gestuurd, dus als onbekend en niet als definitief "geen nummers".
- Client M2: nummers uit het verse lijstantwoord winnen ook bij een ongewijzigd bewaarde rij (Plex-rij met dezelfde `updatedAt`); test rood zonder.
- Client M3: een oudere Pleya Server zonder `external_id_lookup` maakt het assistentantwoord niet meer "onbekend" als een andere server de titel bewijst. Bewijst geen enkele server hem, dan blijft het antwoord onbekend en gaat er geen verzoek naar Seerr: die NAS kan hem onder een andere titel hebben, en een titelpagina vervangt het nummer niet (besluit 4). Een eerste versie van dit herstel liet de titelpagina beslissen; de herreview ving dat af, met een test die rood was op die versie.
- Client M4 (meer Plex-opvragingen door de titelemmer zonder jaar) verdwijnt grotendeels met client I1 en is niet apart aangepakt.
- Herhaalde gates na het herstel: `scripts/ci_checks.sh --with-unused` groen (native incluis); Go-suite in de gepinde image 29 pakketten groen, geen SKIP; gewijzigde Flutter-tests (14 bestanden) 545 groen; Verify-runner 405 en fixture-server 160 groen; scenario valideert; `check_protocol.py` groen.

## Ter beslissing (Michel), los van het protocolbesluit
Client I2: een Pleya Server zonder `external_id_lookup`, of een titel zonder TMDB-nummer, staat in de dekking als `cannotBeAsked`. Daardoor wordt een negatief antwoord niet gecachet en vraagt elke opbouw van de kijklijstbeschikbaarheid alle servers opnieuw (zoeken plus id-opvragingen per titel). Dat is eerlijk ("niet gecontroleerd"), maar kost bij een grote kijklijst honderden verzoeken per bezoek tot de NAS is bijgewerkt. Opties: (a) zo laten, want de NAS krijgt de nieuwe server tegelijk met de app; (b) het negatieve antwoord van de wél gevraagde servers cachen samen met de structurele `cannotBeAsked`, met de capability in de cachesleutel; (c) een server zonder capability niet meetellen als geschikt. Niet gebouwd zonder keuze.

## Toestelchecklist (pas na de autonome ketentests hierboven)
**Build.** De eindcommit van `feat/unified-pleya-server` (de SHA staat in het bericht bij deze ronde). Apple TV via `/pleya-tvbuild` op die SHA, met eerst `scripts/bump_build_number.sh`. iPhone als development-build vanuit Xcode op dezelfde SHA en hetzelfde buildnummer, niet via TestFlight (de interne groep stuurt elke upload door). Beide moeten Release zijn (zie de controle in de skill).
**Nodig.** Plex blijft draaien. Een Pleya Server op de NAS met deze branch, want zonder `external_ids` en `external_id_lookup` blijft alles apart; de serverupdate is een deployment en wacht op jouw akkoord. Welke dubbele serie je zag, met titel en jaar zoals hij op Plex en op de Pleya Server staat, en of de Pleya Server hem als TMDB-match heeft.
**Wat telt als resultaat.**
1. Series: die serie staat één keer, met twee bronnen. Een remake met dezelfde naam staat apart.
2. Bronkeuze: beide servers staan erin; kies Plex, speel een aflevering, kies dan Pleya Server, speel dezelfde aflevering. Seizoenen en afleveringen kloppen per bron.
3. Zet de Pleya Server even uit (of haal het netwerk weg): de kaart opent op Plex zonder doodlopend scherm; daarna weer aan en beide zijn kiesbaar.
4. Zoeken, Home en Verder kijken tonen de titel ook één keer.
5. Een titel zonder match op de Pleya Server blijft twee kaarten; dat is gewenst.
Een fout is: twee kaarten bij een bewezen match, één kaart bij een remake, of een bron die niet afspeelt.

## Herreview van het herstel (5f0632d)
Nieuwe reviewer, niet de hersteller: 0 kritiek, 2 belangrijk, 1 klein, alle drie verwerkt.
- I-1: de offline-stap wachtte op `complete: true`, maar een cursor waarvan het ophalen mislukt raakt nooit uitgeput. De stap wacht nu op twee kaarten.
- I-2: zie client M3 hierboven (regressie in de eerste versie van dat herstel, nu met test).
- M-1: verwijzingen in ROADMAP, CHANGELOG en masterlist heten nu "DEC-XXX (Pleya Server in unified)", zodat het nummer bij de merge niet op een ander DEC-XXX-besluit terechtkomt.
