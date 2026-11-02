# S22.5 / A-07 — I1 default-previewherstel (verse review pending)

Fix op docs-only-uitgelijnde basis `7b81` (volledige SHA in freeze); oorspronkelijke22-statenproef op316 en bijbehorende16bronblobs blijven historisch exact behouden. Geen commit/push/authoritywrite/release. I1 is geïmplementeerd; onafhankelijke fixreview moet nog sluiten.

Na bevestigde unpin blijft de serverpin null, ook als het aansluitende itemverzoek faalt. Een kleine contextgebonden retry-intentie laat de bestaande herlaadknop na candidatesherlaad ook het item/default opnieuw lezen. Dezelfde guarded read geldt voor eerste refresh en retry: abort/sequence/item/account/client/generation/admin/capability. Geen nieuwe PUT, pinreconstructie, framework, wire-, identiteit- of TTL-wijziging.

Bewijs: `/tmp/task8-artwork-ui-fix-1102/`.

- `red.log`: verwacht twee itemreads, werkelijk één. `negative.log`: originele component met definitieve testfake faalt op hetzelfde gedrag; `negative-receipt.log`: KILLED en vaste bron via trap/cmp hersteld. Eerste greenfake had nog incoherente oude pin in candidates; deze toolingfout blijft historisch apart.
- `web-tests.log`:114PASS/8 relevante metadata/matching/detailbestanden, inclusief zes late default-retrycontextwissels. `web-check.log`/`browser-script-check.log`:0errors/0warnings; `web-build.log`, `fixture.log`, `codegate.log`:PASS. Geen herhaling van onaangeraakte Go/security/protocol/Dartcohorten; alleen gewijzigde opt-in fixture gecompileerd.
- `browser.log`:4staten/2gerichte herstelproeven PASS, session28510 exit0.320/OLED en1440/light: echte unpin200 → eenmalige synthetische item503 → eigen reloadcandidates200/item200 → zichtbaar standaardbeeld, nullpin en precies één PUT. Geen browsermocks; axe nul, geen overflow/pageerrors. `runtime.log`:6.26sPASS/stopfile-cleanup. Alle vier viewportbeelden persoonlijk gelezen; fullpagecompanions in manifest. Native Verify heeft geen Svelte-Webdoel; geen nativeclaim.
- `freeze.json`:17bron-Gitblobs/SHA256 inclusief werkelijk gebruikte evidencescript,199built-Webfiles; vóór/na bytes gelijk. `fix-only.diff`, `review.diff`, `receipt.json`, `staging.txt`, `manifest.json` en8PNGhashes vormen de reviewoverdracht. Dit blijft frozen dirty bron, geen fictieve clean-SHA-PASS.

Fixturegrens: uitsluitend bestaande `_test.go`, synthetische loopback8845/eigen DB+CacheDir; fixtureheader armt één503 op alleen het eigen synthetische item. Product-unpin/candidates/itemhandlers blijven verder echt; geen product-Go/schema/API-wijziging. Historische async-assertiepogingen (waarvan één ongewijzigde scriptvervanging) en overtollige owner-query429 zijn afzonderlijk bewaard, niet als product-RED of acceptatie geteld. Oorspronkelijke overige22staten/gates blijven geldig; geen nieuwe ontwerp-/app-/provider-/licentieclosure.
