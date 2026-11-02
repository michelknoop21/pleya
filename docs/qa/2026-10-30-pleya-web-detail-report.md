# C-05 / S8.5 — detail, versiekeuze en lange seizoenen

Vervolg na `2b30dbdb`; pakket 5 blijft open. Bestaande detail-/spelerroute, Select, Artwork, VersionPanel en cursorpager hergebruikt. Geen protocol, databasemodel of afhankelijkheid toegevoegd.

De detailpagina toont bestaande samenvatting, genres, kijkwijzer en bekende cast-/regierollen; ontbrekende velden verdwijnen en personen krijgen geen verzonnen route. Breed verschijnt de backdrop met leesbare scrim, smal een 16:9-voorvertoning. Versiekeuze stuurt hetzelfde stabiele UUID naar hervatten en vanaf het begin; de speler weigert een onbekend of expliciet leeg versie-ID zonder een andere versie te openen. Playbackacties volgen de servercapability.

Seizoenen/afleveringen blijven bereikbaar voorbij de eerste honderd via de bestaande cursor. Een fout in deze sectie bewaart de titelmetadata; opnieuw proberen haalt alleen die sectie op. Aanvragen delen de route-eigen annulering.

**Bewijs.** Publieke tests eerst rood voor metadata, versie/capability, onbekend/leeg ID en cursor/sectieherstel. Laatste gerichte ronde: 15 bestanden / 142 tests PASS; Sveltecheck 0 fouten/waarschuwingen. API-typen bytegelijk met het contract, webbundel groen en Go `build -tags release` met die bundel groen. Twaalf blijvende browserregressies PASS op desktop/mobiel rechtstreeks tegen de Go-binary. Testcontexts loggen voortaan uit; herhaalde proefcontexts hadden terecht de limiet van acht actieve streamsessies bereikt, die is ongewijzigd.

Eigen disposable Postgres/server op loopback 18837, drie bibliotheken, twee echte videoversies en 102 afleveringen. Browser: tweede versie gekozen, UUID gelijk in request én effectief plan, werkelijk gedecodeerde frames; 100 → 102 afleveringen; onbekende versie opent geen speler. Vijf breedtes 1920/1440/1280/390/320: axe 0 en horizontale overloop 0, beelden bekeken. Opnamen met afgeronde animaties; geladen backdrop ook met pixelcontrole zichtbaar op alle desktopbreedtes. `.build/pleya-completion-evidence/web-detail/proof.json` registreert de Go-embedbron, geen Vite-only-claim.

Open: persoonlijke detailacties/Mijn Pleya, serie-hervatten en overige detail-/productspecificaties, onafhankelijke eindreview, CI, NAS/hardware en totale pakketsluiting. Geen productie, merge of release.
