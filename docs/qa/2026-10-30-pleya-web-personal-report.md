# C-05 / S8.5–S8.6 — persoonlijke webfuncties

Nog ongecommit vervolg op `e67184d79`; pakket 5 en het totaalplan blijven open. Bestaande persoonlijke routes, client, spelertransport, dialoog, select en cursorpager hergebruikt. Geen nieuw contract of afhankelijkheid.

Detail heeft favoriet aan/uit, gehele beoordeling 1–10 en wissen, en expliciet bekeken/onbekeken voor film/aflevering. Acties staan alleen aan bij de bijbehorende servervlag; geen writes vanuit een lokale beoordelingskeuze vóór Opslaan. UI verandert pas na bevestiging; fout bewaart de bestaande staat en dubbel klikken stuurt één verzoek. Een oude accountactie gebruikt nooit het nieuwe account; late resultaten na accountwissel of verlaten detail worden verworpen. Bekijkmarkering start geen playback en voegt geen nieuwe ownershipvelden toe. De gekozen videoversie blijft behouden.

Mijn Pleya linkt naar de eigen favorietenlijst met cursorpaginering, lege staat, fout en herhalen met behoud van eerdere resultaten. Een oudere server krijgt geen niet-ondersteunde verzoeken. Verouderde commentaartekst die bestaande beheerfuncties ontkende is verwijderd.

**Bewijs deze uitvoeringsronde:** ontbrekende component/route eerst rood, daarna publieke tests groen. Laatste gerichte ronde 12 bestanden / 129 tests PASS; accountguard tijdelijk verwijderd → oude-accounttest rood, hersteld 11 API-tests PASS. Sveltecheck 0 fouten/waarschuwingen. `scripts/ci_checks.sh` PASS; brede hardlinter-/unusedscans blijven CI-only. Webbundel 174 bestanden / 2,2 MiB en Go releasebuild groen. Vier permanente browserregressies PASS op desktop/mobiel rechtstreeks tegen deze Go-embedbinary.

Eigen disposable testserver op loopback 18837: twee synthetische accounts, favoriet/beoordeling/bekekenstatus na echte verversing, B ziet A niet, terug naar A blijft correct, beoordeling wissen, favoriet verwijderen/onbekeken en mislukte favoriet behoudt staat. Mijn Pleya-favorieten gevuld bij A en leeg bij B. Vijf breedtes 1920/1440/1280/390/320: axe 0 en horizontale overloop 0. Browserproef en beelden: `.build/pleya-completion-evidence/web-personal/`; manifest in `2026-10-29-pleya-completion-images.md`.

S15.9-keuze afzonderlijk vastgelegd: eerst migratievoorstel afbakenen, geen importvrijgave. Zie `../pleya-server-plex-migration-proposal.md` voor scope en de onbesliste volgorde vóór S15.5.

Open: volledige Mijn Pleya-/geschiedenis-/downloadscope, serie-hervatten, overige pakketten, onafhankelijke eindreview en adversariële review, CI, NAS/hardware. Geen push/merge/deploy/release of productiegebruik.
