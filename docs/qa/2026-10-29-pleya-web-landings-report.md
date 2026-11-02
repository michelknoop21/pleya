# C-05 / S8.2 — Films en Series

Vervolg na `1057b578` en de NFO-reparatie `da0e67dd`; pakket 5 blijft open. Bestaande PageHeader, HubRail, API-client en bibliotheekcatalogus hergebruikt, zonder nieuw protocol of afhankelijkheid.

Films en Series hebben eigen landingen en navigatieslots. Per toegankelijke bibliotheek: recent toegevoegd, nog niet gezien, maximaal drie grootste bevolkte genres, onlangs bekeken; Series begint met volgende en nieuwe afleveringen. Lege rijen verdwijnen. Verder kijken blijft uitsluitend op Home. Persoonlijke/filterrijen volgen capabilities; oude servers krijgen alleen bestaande aanvragen.

Alles bekijken opent de juiste bibliotheek met de werkelijke filter- en sorteerquery. Bij meerdere bibliotheken blijven alle bronnen expliciet bereikbaar via het bestaande bibliotheekoverzicht, gefilterd op soort. Geen gezamenlijke sortering of onterechte deduplicatie geclaimd: de soortbrede globale catalogus blijft onder S8.3 open. Een lege soort geeft een uitweg naar Mijn Pleya.

**Bewijs.** Nieuwe publieke componenttest eerst rood; navigatie-/overzichttests zes rood vóór aansluiting. Laatste gerichte ronde: 16 bestanden / 157 tests PASS; Sveltecheck 0 fouten/waarschuwingen; productie-webbundel groen. Acht blijvende browserregressies PASS op desktop/mobiel, inclusief echte URL-geschiedenis en oude-servervariant zonder facet/genre/watch-aanvragen. Eigen Go-testinstance met synthetische NFO-media: echte genres na `da0e67dd`, Family-doorklik levert exact de recovery-titel. Films op 1920/1440/1280/390/320: axe 0 en horizontale overloop 0, alle beelden bekeken. Series heeft componentbewijs voor echte next-up/recent-APIcallers en browserbewijs voor de lege staat; gevulde Series/hardware/NAS zijn nog geen PASS.

Browserbewijs via de bestaande lokale Vite-proxy, geen bewijs dat deze webbundel al door productie wordt geserveerd. `.build/pleya-completion-evidence/web-landings/proof.json`; logs `/tmp/pleya-completion-web-landings-*`. Onafhankelijke eindreview, CI en overige pakketten blijven open; geen productie, merge of release.
