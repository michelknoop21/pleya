# Onafhankelijke fixed-image pin-cachebewijsreview

**PASS (scoped) — doelcohort hostcacheverlies12/12 bewezen; volledige runtime blijft exit1. Geen Critical, Important of Minor in deze begrensde bewijsclosure.** Roadmap C-05/S22.5. Onafhankelijke review van `/tmp/task5-pin-cache-green-1102`; geen herhaling van de code-/unitreview. Geen tests, Docker/browser, build, subagents, product-/authoritywrites of andere bestanden gewijzigd; uitsluitend dit rapport.

## Exacte bron en image

Normale gitarchive/Dockerfilebuild op `9e607e4cce5d6b870c9b7b2edb00f9a0bd5ea1bc` is aan image `sha256:f8cbfced5549c72bcb28196649845cab83f6c87a5ce440d026a2a7b2c6de9647`, linux/amd64 en exact revisionlabel gebonden. Buildscript/uitvoer, `source-proof.json`, `image.txt` en runtimeinspectie sluiten aan. Productie-pinsSHA `adf1cb96afe792fa0b14b974087f2ba101017db3a73948322e880f37d8f6b55a` is dezelfde eerder onafhankelijk gereviewde fix.

Persoonlijk geverifieerd: alle42 artifact-SHA’s, alle8 behouden oudeRED-bindingshashes, alle609 source-manifestbestanden en409 niet-gegenereerde serverbestanden tegen daadwerkelijke Git-blobs exact. Webhergebruik is begrensd en juist:0ae/9e hebben dezelfde WebGit-tree7828f4ea…, alle200 oude bundlebestanden zijn byte-/SHA-gelijk aan het eerdere manifest en in het nieuwe buildcontext opgenomen. Dockerfileblob gelijk; alle41 vastgelegde migrationdirectorybestanden met Gitblobs/SHA persoonlijk op beide revisies vergeleken, exact. Dit is geen nieuwe Webbuild/browserproef of nieuw restorebewijs.

## Doelcohort en werkelijk resultaat

`host-probe.py` verwijdert per ronde daadwerkelijk de hostmap via `shutil.rmtree`, noteert einde en hostafwezigheid en begint direct de normale authenticated artworkGET; geen extra mkdir, slaap of guestinspectie tussen deletion en GET. Alle12 originele rijen persoonlijk gecontroleerd: hostmap na verwijdering afwezig, na GET terug, GET200 en identieke baselineSHA/ETag, volledige pinrij exact gelijk. De helper hasht de werkelijk gelezen responsebytes; de vergelijkingen betreffen status én ETag én SHA, niet alleen200. Pin-ID blijft01a19b92-5a44-7000-96d9-8b7a0aa5d555 binnen dezelfde fixture. De SQL-intentvergelijking betreft de hele opgeslagen rij na elke ronde.

Timestamps opnieuw uit de nanoseconden berekend: delete-end→GET-start0.043–0.074 **milliseconden**, dus43–74microseconden. Volgorde begin/einde verwijderen→begin/eindeGET klopt in alle rijen. Logs, host-outcome en host-summary ondersteunen hetzelfde12/12resultaat; de ongewijzigde oude16c1image reproduceerde503 in ronde1 in afzonderlijke synthetische fixture. Geen gelijke pin-ID tussen die verschillende fixtures verondersteld.

Dit is voldoende runtimebewijs voor de beoogde bounded host-rmtree/immediateGET-regressie, samen met de al afzonderlijk gereviewde deterministische syscall-RED/GREEN. Het is een eindig cohort zonder retry-instrumentatie: geen bewijs dat elk mogelijk mounttimingvenster verdwenen is of dat de interne virtiofs-oorzaak bekend is.

## Niet-groene optionele proef blijft expliciet

Na het geslaagde cohort verwijderde het harnas de hostcachemap en verplaatste de hostposter. De extra missing-sourceassertie verwachtte503, kreeg200 en stopte werkelijk met traceback/terminal1. `exits.json`, `optional-source-probe.json` en REPORT herschrijven dit niet als overallPASS. Guestcache-/bronzichtbaarheid op dat verzoek en responsehash zijn niet vastgelegd. Geldige eerder gecachte bytes mogen zonder bronhercontrole worden geleverd; uit deze waarneming volgt daarom geen bewezen productfout of bronverlies-PASS. Exacte oorzaak blijft onbepaald. Changed-source werd niet uitgevoerd. Geen nieuwe poging of fixture als compensatie geclaimd.

Deze optionele onbesliste proef maakt het daarvoor volledig afgeronde doelcohort niet ongeldig, maar verhindert iedere claim dat alle geplande runtimechecks groen zijn. Bronverlies/bronvervanging blijven voor deze image onbewezen; eerdere gerichte tests blijven afzonderlijk bewijs.

## Resources en acceptatiegrenzen

Vooraf bestaande containertabellen zijn bytegelijk voor/na; cleanupdelta bewaart alle oude images en toont alleen de nieuweimage erbij. Beschermde PG283651dc… blijft dezelfde ID/exited; eigen serverc959322d…, PG463d8f9e… en netwerk8c2b1276… en eigen fixturedata/keys zijn volgens finally/cleanupbewijs verwijderd. Nondefaultnetwerken blijven gelijk. Defaultbridge-ID wijzigde; oorzaak onbekend, geen bridge-/restart-/pruneactie in de uitvoeringsscripts. Cleanup is uitgevoerd ondanks terminal1.

Als aanvullende bron-equivalentie zijn9e/e8-Git-trees lib, ios, tvos, macos, android, windows, linux en pleya_verify persoonlijk gelijk bevonden. Dat is uitsluitend bronpariteit en verplaatst geen nieuwe native-runtimeclaim naar9e. Geen nieuwe backup/restore/rollback/Webbrowser/native/provider/hardware/NAS/offsite-/releaseacceptatie bewezen. EACCES/ENOSPC/contextcancel waren geen imagecohortscenario’s; die blijven bij eerder gerichte tests. Brede S4.6-cachebeheeruitvoering is afzonderlijk en buiten deze review.

Geen blocker voor het vastleggen van de **begrensde hostcachefixacceptatie12/12** met bovengenoemde grenzen; root blijft integratie-/authorityeigenaar. De hele run en optionele bronproeven mogen daarbij niet als groen worden gelabeld.
