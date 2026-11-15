# Catalogusposters — release en afgebakend bewijs

Roadmap: A-06/A-07; C-05/S2.14/S22.6. Code [PR #682](https://github.com/michelknoop21/pleya/pull/682),
gebouwd uit merge `8820ca925d46bb2faffecea791665afabf823447`.
[Build 462](../RELEASES.md) is op 11 november 2026 beschikbaar voor interne TestFlight-testers
op iOS, tvOS en macOS. App Store Connect is teruggelezen op 10 november 23:51:35 UTC
(11 november 00:51:35 CET): alle drie `VALID`, `IN_BETA_TESTING`, niet verlopen.

## Clientbewijs

- 66 gerichte Flutter-tests: eigen bronclient/cache per afbeelding, beide serverrichtingen,
  ontbrekend pad/client, lege URL, laadfout, bestaande/verdwenen lokale cache en eindige terugval.
  Negatieve controles falen zonder de bijbehorende fix.
- [Volledige PR-CI](https://github.com/michelknoop21/pleya/actions/runs/42915648539) en
  [main-CI](https://github.com/michelknoop21/pleya/actions/runs/42919924407):
  14.647 geslaagd, 246 overgeslagen, nul fouten. Bestaande Linux-goldens blijven gelijk;
  vier rasterkostentests slagen, inclusief begrensde cacheopzoekingen bij 130 en 500 kaarten.
- [Native iOS-bewijs](https://github.com/michelknoop21/pleya/actions/runs/42915648565):
  `ios.unified.artwork-fallback` PASS op iPhone 16e / iOS 26.2,
  390×844 logisch / 1170×2532 pixels.
  Bron A blijft de titel en het jaartal 2022 leveren zonder poster; de poster uit bron B
  verschijnt bij twee bronnen. Requestlog en exacte synthetische kleur bevestigen die herkomst.
  Het bewijs is onafhankelijk beoordeeld. Runner meldt `dirty:true` na native builds;
  de CI-mergeboom is gelijk aan de beoordeelde bronboom. Dit is simulatorbewijs,
  geen fysiek tvOS-/iPhone-bewijs.

## Serverbewijs

Normale private NAS-uitrol uit dezelfde merge, schema 37 behouden, nieuwe image
`10dd7a3fda23efc18f3301b7ddc399bb4deb4ccaa2b275f2fd1a3ffd20892a70` gezond;
lokale en publieke readiness groen. Vorige image en bronnen zijn bewaard voor terugval.
Filmscan: 3.190 bestanden, nul fouten. Seriescan: 24.366 bestanden, nul fouten.
De twee waargenomen items Art of Nottingham en Featurettes zijn na de gewone scan extras,
blijven aanwezig en behouden item-/versie-/bestands-ID. De bestaande gewone catalogusfilter
geeft voor beide samen nul resultaten. Kijkstatusbehoud is met een geïsoleerde PostgreSQL-/ffmpeg-
regressie getest; er is geen live vergelijking van persoonlijke kijkstatus uitgevoerd.

## Open

The Simple Life heeft nog geen toegepaste identiteit: TMDB `ambiguous`,
`application_state=unknown`, geen jaar. De correcte serie uit 2003 (TMDB 4406) moet via de
bestaande eigenaar-/beheerdermatch worden bevestigd; de benodigde ingelogde beheersessie
is nog niet beschikbaar. Hiervoor is geen recht uitgebreid, token aangemaakt of
identiteit rechtstreeks in de database gewijzigd. De terugval gebruikt uitsluitend bronnen
waarvan al is vastgesteld dat ze dezelfde titel vertegenwoordigen.
