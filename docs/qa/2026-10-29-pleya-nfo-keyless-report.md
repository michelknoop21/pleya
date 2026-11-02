# C-05 / S4.1 — NFO zonder TMDB-sleutel

Probleem: `main` startte de bestaande metadata-worker alleen met een TMDB-sleutel. Een gewone scan kon slagen terwijl lokale `movie.nfo` nooit metadata leverde. Dit blokkeerde de echte genrerijen van S8.2. Geen nieuwe velden, routes, tabellen of protocolvrijgave.

De bestaande Runner ondersteunt nu een lokale ronde zonder provider. De worker start altijd; een ingestelde TMDB-sleutel behoudt dezelfde providerketen. De lokale ronde leest NFO via de bestaande begrensde sidecarlezer en past die met de bestaande bronrang toe. Ontbrekende NFO wist niets. Lokale rondes wijzigen geen providerkandidaten of providercache, ook bij een opslagfout. `sidecar_applied` telt het werk in de bestaande metadatalog.

**Bewijs.** Nieuwe publieke Runner-test eerst rood (nil-provider werd aangeroepen). 143 gerichte Go-tests in metadata/catalog/cmd PASS met echte geïsoleerde Postgres, nul skips; bestaande tests bewaken bronrang en handmatige correcties. Afzonderlijke negatieve controles rood bij herstel van kandidaatregistratie voor een lokale fout en bij cache-opruiming zonder provider; bron telkens hersteld en metadata-tests daarna groen. Serverbinary lokaal gebouwd.

Echte eigen disposable instance, uitsluitend synthetische media: vóór reparatie scan `done`/nul fouten maar NFO-dekking 0/2. Na vervanging van alleen de gelabelde testbinary en herstart: NFO/samenvatting/genres 2/2, genrepoort open, API-facetten Family en Science Fiction elk één titel. Geen externe providersleutel of betaalde call gebruikt. Hash en resultaat staan in `.build/pleya-completion-evidence/web-landings/nfo-keyless-proof.json`. Browser toont echte genrerijen en Family-doorklik levert exact de recovery-fixture.

Open: overige NFO-dekking, afleverings-/seizoensmetadata, metadata-venster, onafhankelijke eindreview, CI en hardwareacceptatie. Geen productie, merge of release.
