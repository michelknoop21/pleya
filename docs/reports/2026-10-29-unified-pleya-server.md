# Unified: Pleya Server naast Plex, Jellyfin en Emby

Roadmap: A-07 (serverdeel C-05 / S22, register X5). Besluit: DEC-XXX. Branch `feat/unified-pleya-server`, basis `main` d9edacc.

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

## Niet bewezen
- iPhone en Apple TV met Plex en Pleya Server tegelijk: geen toestel, simulator of toegang tot Michels Plex of NAS in deze sessie. Geen voor/na-schermopname, geen bronkeuze of afspelen op een toestel. De keten tot en met bronkeuze en afspeelplan is op code- en servernivel getest; "unified werkt" is daarmee nog niet op een toestel aangetoond.
- Geen echte Plex of Emby; hun kant is nagebootst met de bestaande fake-clients.
- Het fixtureprotocol voor Verify heeft nog geen tweede server per scenario (zie DEC-101); er is geen Verify-scenario gemaakt.

## Bekende beperkingen
- De bucket is titel plus jaar: dezelfde serie met een ander jaar op de twee servers wordt niet opgezocht en blijft twee kaarten.
- Een Pleya Server zonder match, of een oudere serverversie, blijft eigen kaarten tonen.
- Plex-titel zonder TMDB-nummer: Pleya Server kan hem niet bewijzen en staat dan als niet gecontroleerd in de dekking.
