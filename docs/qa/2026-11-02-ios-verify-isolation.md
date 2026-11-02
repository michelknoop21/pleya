# iOS Verify-start en lokale serverimage, 2 november 2026

Roadmap: C-05/A-07. Unified impact: alleen geïsoleerde iOS-testverpakking; geen wijziging van consumentenapp, rechten, timeout of servercontract door de iOS-fix. Dit verslag vult de historische mislukte start in [de bundelrapportage](2026-11-01-joint-release.md) aan; het herschrijft die uitkomst niet.

**Code d69209da690615f6a76f5a53bbb3fff2385e60fc:** de Verify-kopie verwijdert uitsluitend het exacte eigen absolute PackageFrameworks-zoekpad, controleert dat dependencies embedded zijn, tekent gewijzigde nested code expliciet en verifieert signatures. De oorspronkelijke loader bleef vóór main bij de host-CSQLite openen. Een gecontroleerde proef met dezelfde gecompileerde app startte na de correctie; fout getekende eerdere diagnostic-kopieën tellen niet als acceptatie.

40 gerichte runner-tests, drie falende negatieve controles, codegate, normale hooks en [onafhankelijke bronreview](2026-11-02-ios-verify-review.md) PASS. De review beschrijft de latere equivalente testimportcorrectie; de finale gate is daarna opnieuw groen uitgevoerd.

| Nieuwe native proef op schone d69209da6 | Resultaat |
|---|---|
| ios.catalog.header-collapse | PASS, exit0, 156973 ms |
| ios.library.local-offline | PASS, exit0, 34995 ms |

Eén opnieuw gebouwde geïsoleerde Debug-app op bestaande iPhone 17 Pro/iOS27-simulator; de tweede proef hergebruikt aantoonbaar deze voorbereide app. Beide manifests noemen d69209da6 en dirty=false. Geen fysieke UI of toestel gebruikt. Integrator heeft alle negen originele 1206×2622-beelden bekeken: header verdwijnt/keert terug, onderste catalogusrij blijft bereikbaar; offline-index, posters, zoekresultaat, detail en geblokkeerd afspelen zijn zichtbaar. [Beeldmanifest en hashes](assets/2026-11-02-ios-verify-isolation/manifest.json). Dit bewijst deze appflows, geen hardware-/performance- of volledige serveracceptatie.

**Runner-modal:** vijf eerder aangemaakte lokale Verify-diagnostic-crashes bevatten CODESIGNING Invalid Page vóór main en passen bij fout getekende diagnostic-kopieën. Eén proces en de binary-UUID zijn exact gecorreleerd. Er is geen nieuw corresponderend rapport rond het gemelde schermtijdstip gevonden; het screenshot alleen identificeert het proces niet uniek. Geen crash naar Apple verstuurd en geen fysieke modal bediend.

**Serverimage d69209da6:** [begrensde runtimeproef](2026-11-02-server-image-smoke.md) PASS: non-root/read-only, gezondheid200, auth401, schema31, synthetische scan1/1 en stabiele IDs na herstart. Eigen proefresources opgeruimd, bestaande containerstates ongewijzigd. Image2d56d3ead140 bevat migratie32 niet.

**Latere lokale integratie:** metadata-backend219e8d8f9 is afzonderlijk gereviewd en geïntegreerd als7536d754e. Zes veldlocks, bronlagen, veilige unlock en migratie32 zijn lokaal bewezen; de editor en artworkpins blijven open. De bovengenoemde native- en imagebewijzen blijven exact aan d692 gekoppeld en zijn geen nieuwe gecombineerde PASS voor7536. De gewone codegate op geïntegreerde7536 is afzonderlijk terminaal exit0: All checks passed; drie boombrede DCL-scans blijven expliciet CI-only.

Geen publicatie, mainmerge, NAS-mutatie of TestFlight-upload. De specifieke publieke GitHub-publicatie wacht op de gevraagde bevestiging na automatische afwijzing vóór uitvoering. Het volledige server-gapplan blijft open.
