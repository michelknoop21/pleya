# C-05 — herstel van offline downloads en posters

Roadmap: C-05 / S23.3 / S14. Lokale opvolging op `f0ffe59a`; geen push, merge, deploy of release. Pakket 4 en de fysieke toestelgate zijn nog open.

- Bestaande manager hervat een onderbroken Pleya-download met dezelfde versie en haalt de sidecar opnieuw op. Geen nieuwe downloadservice of extra downloadaanvraag.
- Accountscope blijft exact: een wachtrij van A gebruikt geen actieve B. Offline replay stuurt één backlog met het oorspronkelijke tijdstip en opent geen live eigendom. Echte offlineproef bewaart de nieuwere canonieke toestand: positie0/revision79 vóór én na replay, wachtrij leeg. Dit bewijst geen automatische canonieke overname van oudere offline voortgang.
- Cache houdt account-ID en fysiek server-ID apart. Daardoor staat de poster na herstel op de plaats waar offline UI hem leest, ook na het verwijderen van een verbinding.
- Systeemmediabediening gebruikt bestaande lokale posters/afbeeldingscache als bytes voor header-authenticatie; een afgesloten account of verouderde asynchrone laadactie publiceert geen nieuwe URL/metadata.
- iOS Verify-installeerstap volgt nu de bestaande tvOS-driver: een koude herstart installeert dezelfde app niet opnieuw. De eerder waargenomen vault-MAC-fout is met dezelfde binary rood→groen; geen productauthenticatie gewijzigd.

**Bewijs.** `ci_checks.sh`24 PASS (hardlinter/ongebruikte code blijven CI), daarna156 gerichte Flutter-tests PASS. Negatieve controles per reparatie in de tests/uitvoeringsledger. Go HLS-cookieauth404→200 en verlopen-headerkarakterisering PASS; protocolcheck PASS. Gegenereerde webtypen bijgewerkt, webcheck0fouten/0waarschuwingen en100 eerdere gerichte tests PASS.

**Native.** `ios-pleya-download-recovery-1793306376831` PASS:21151852bytes, SHA256 gelijk aan synthetische bron, echte digestcontrole na herstart, lokale frame en UUID-sidecar. `file-proof.json`: fysieke serverposter aanwezig, accountposter afwezig. Werkelijk offline/online replay: `ios-pleya-real-download-offline-1793305090936`. iOS playback met laatste artworkcode: `1793307018265` PASS. Bewijs onder `.build/pleya-completion-evidence/`; [beeldenmanifest](2026-10-29-pleya-completion-images.md).

**Open.** Fysieke platforms, onbereikbare digest als aparte skip, token-/rechtenacceptatie en volledige milestoneA; lange mediatransportauth wacht op het afzonderlijke voorstel. NAS/production, CI, systeem-NowPlayingpixels en release niet geverifieerd. Andere pakketten blijven in uitvoering.
