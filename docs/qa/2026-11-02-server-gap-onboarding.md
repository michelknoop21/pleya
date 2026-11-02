# S11 — hervatbare bestaande setupketen

2 november 2026 · Roadmap C-05/S11.1–S11.3, Unified impact: bestaande serverbibliotheken blijven dezelfde concrete bronnen; geen identiteits-/catalogusmodelwijziging. Basis `6b784e0b973cf95ba628a95c59c625da7d2fce06`, lokaal dirty-sourcebewijs, geen commit of release. Eén productwriter; onafhankelijke spec/correctness/security/visuele review en normale hooks staan nog open.

De bestaande `/setup` verbindt nu eigenaar → aangeboden opslag → bibliotheek of bevestigde `.env`-overname → scan/Home. Bestaande auth-, library-, adopt- en scanservices zijn hergebruikt. De werkelijke sessie, opgeslagen bibliotheken/roots en laatste scan bepalen welke handelingen al gedaan zijn; openen/herladen schrijft niets. Vóór create/start wordt opnieuw gelezen zodat een verloren antwoord of ander tabblad geen tweede bibliotheek/scan veroorzaakt. Een nog niet opgeslagen rootkeuze is alleen een interne URL-draft en wordt bij reload tegen verse aangeboden roots gevalideerd; dit is geen opgeslagen voltooiingsvlag. Niet opgeslagen formuliertekst blijft in geheugen.

`server_name` gaat alleen mee bij bestaand `setup_accepts_name`; het setup-onlyveld blijft buiten de gesloten cookieloginbody. De bestaande cookielogin/refresh blijft behouden. Setupcode en wachtwoord gaan niet naar URL/browseropslag. Read-only media worden geaccepteerd; hostmounts aanmaken blijft operatorwerk. Een niet-bereikbare opgeslagen root wordt zichtbaar gehouden, ook bij een oude geslaagde scan. Done met nul titels is een geldige lege uitkomst, failed/cancelled behoudt een expliciete retry. Ready member/restricted krijgen404 en vragen geen beheerdata; account-/client-/generatie-/abortguards begrenzen late uitkomsten. Loginreturn accepteert uitsluitend `/setup` voor een actuele beheerder.

## Exacte bewijsgrens

[Bronfreeze](assets/2026-11-02-server-gap-onboarding/source-freeze.json):22 bron-/test-/READMEbestanden, SHA256 én Gitblob, op6b784e0b. Freeze-SHA256 `d7cd24036292f27df28fab3f6b0c8236883ed163c057b6700c9b186a694e4f12`; built-Web boomhash `09655d7a97687f3e6ea0a20d96dafef77d0cad77b3e53ebdd8cd4eaa01e330a1`. [Achterafcontrole](assets/2026-11-02-server-gap-onboarding/source-freeze-verified.json) bevestigt exact dezelfde bron-/Webbytes na de finale browserrun. Een latere broncommit moet deze blobs bevatten; geen fictieve clean-SHA-nativePASS.

| Gerichte controle | Terminale uitkomst |
|---|---|
| Finale Webcohort,13 bestanden incl caller/auth/session/gate/i18n | **206 PASS**, geen testskip/failure |
| Zes compileerbare mutaties: rol, account, dubbel scannen, URL-fase, ontbrekende root, setupnaam/login | Elk1bedoelde gedragsFAIL; byte-/SHA-exact herstel; **44 herstelde S11-tests PASS** |
| Svelte-check / Webbuild | **0errors/0warnings / PASS** |
| Canonieke `scripts/ci_checks.sh` / diffcheck | **All checks passed / PASS**; drie standaard brede DCL-scans CI-only SKIP |
| Eigen opt-in Go-fixture | Fixture-vet en echte HTTP/DB/jobs/scanner terminal **PASS**,18,0s |
| Finale echte browserjourney | **PASS**,1owner/1library/1scan na reloads; adopt-ID behouden; lege echte scan geslaagd; member/restricted0beheeraanvragen |

Mutatienegatieven zijn vóór twee laatste tekstcorrecties uitgevoerd (enkelvoud “1 titel”, vertaald bibliotheektype). `negative-copy-delta.json` reconstrueert SHA-exact de geteste Wizard door uitsluitend die twee template-labels terug te vervangen. Daarna finale206PASS/check/build/gate en volledige frozen browserrun; geen guard-/APIgedragsdelta. Fasecounts worden niet bij elkaar opgeteld.

Echte REDhistorie blijft onderscheiden: het oude eigenaarformulier faalde op adminresume; de echte browser vond setupnaam in de gesloten loginbody en een fasewissel vóór bewaarde draft-URL. Beide hebben gerichte assertion-RED/GREEN. Een latere adoptfixture miste een geldige bestaande RootSpec-trustbron; dat was fixtureontwikkeling, geen product-RED. De transportonderbreking startte de laatste onzekere testcase niet; na herstel eerst bronnen/queue/eigen cleanup gecontroleerd. Finale logs vervangen geen historische failureclaims.

## Browser en visueel

[Manifest](assets/2026-11-02-server-gap-onboarding/manifest.json):14 primaire viewportframes +14 full-pagecompanions,320/390/1600,dark/OLED/light. Alle14 finale primaire beelden persoonlijk bekeken tegen goedgekeurde40–44:620px setupkolom, bestaande Steps/Field/Panel/Alert, smalle bediening in documentflow, bereikbare CTA’s en geen horizontale setupoverflow. Werkelijke counters in plaats van een verzonnen percentage/totaal; bestaande MediaCardvoorvertoning en Home tonen de gescande synthetische titel. Homebron is ongewijzigd; zijn frame bewijst de bestemming/titel, geen nieuwe algemene Home-UIreview. Eén axecontrole op320light:0violations, geen volledige toegankelijkheidsclaim.0pageerrors.

Alle browseraanvragen gaan naar echte Go-handlers op de eigen fixture, geen browserroute-mocks. De availability-fout is een expliciet geïnjecteerde503 in de opt-in testserver; herstel loopt via dezelfde echte leesroute. De echte scanner verwerkt een read-only gemount synthetisch videobestand en later een lege read-only map. De fixture controleert daadwerkelijk readable+readOnly. Live-IDbehoud bij adopt is gemeten; slugbehoud komt daarnaast uit de bestaande ongewijzigde adoptstore/tests, niet uit een nieuw wireveld. Pleya Verify heeft geen Svelte-Webtarget; geen native-/hardware-/NASbewijs.

## Isolatie en resterende grenzen

Eigen netwerk `pleya-s11-1102`, PGcontainer `pleya-s11-db-1102`, fixture `pleya-s11-fixture-1102`, rol/database`s11`, label`pleya.task=s11-1102`, uitsluitend loopback8853. Postgres gebruikte eigen tmpfs, geen bestaand volume. Seedcontainer`--rm`; normale trap sluit eigen fixture/PG/netwerk af. Geen beschermde PG/network, NAS, productiecredentials, Dockerimagebuild, push/merge/commit/deploy of publieke retry. Fixturecontrols bestaan uitsluitend in opt-in `_test.go`, niet in de productbinary.

De brede verse-installatiematrix, echte operatorfouten met hostuid/mount/poort/proxy, operationele restore/rollback en hardware-/releaseacceptatie blijven apart. Deze slice levert de bestaande S11-keten en het hierboven beschreven lokale bewijs; geen volledige C-05-/Plex-vervangingsclosure. Masterlijst/ROADMAP/OpenAPI/globale APItypes zijn voor root onveranderd gelaten. De aangetoonde verouderde README-status is lokaal gecorrigeerd naar bestaande bediening en de operatorgrens.

Exacte commando’s en logs: `/tmp/pleya-s11-1102/{local-checks.sh,negative-chain.sh,negatives.py,runtime.sh,freeze.py}` en bijbehorende `check-final.log`, `tests-final.log`, `build-final.log`, `gate-final.log`, `negatives.json`, `restored-green.log`, `browser.log`, `runtime.log`. Onafhankelijk reviewpakket: `.superpowers/sdd/METADATA-IMPLEMENTATIE/s11-review-package.md`.

**Reviewclosure:** [onafhankelijke security/correctness/beeldreview](2026-11-02-server-gap-onboarding-review.md) PASS zonder bevindingen. Dezelfde reviewer heeft ook roots drie lokale S11-statusregels substantieel gecontroleerd; brede installatie/NAS/release blijven open. De22 bronblobs zijn onveranderd. Normale hooks volgen bij roots lokale commit.
