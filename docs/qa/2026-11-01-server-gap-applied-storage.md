# A1: duurzame toegepaste metadata-identiteit

1 november 2026. Roadmap C-05/S4/S22/S14.5, basis e2a81f9e0876dfb2d926b489a27ef8be74030e6d. Binnen het expliciet geopende [metadata-venster](../DECISIONS.md#metadata-venster-2026-11-01), alleen interne opslag/runner/migratie. Geen API/OpenAPI/client/UIwijziging en geen live-uitrol.

Migratie 0031 voegt op bestaande metadata_candidates een nullable applied-provider/ID-paar en duurzame unknown/pending/applied/failed-toestand met één vaste veilige foutcategorie toe. Oude matched/manual/details-rijen krijgen geen verzonnen toegepast bewijs. Alleen succesvolle guarded Details-publicatie legt applied vast, atomair met de bestaande velden/bronnen/artwork. SaveCandidate alleen bewijst niets. Nieuwe keuze, ook hetzelfde ID, wordt pending met behoud van applied A; failure behoudt A en gekozen B, reject trekt applied in. Bestaande monotone kandidaatgeneratie bewaakt oude antwoorden; betrokken metadata-itemtijden blijven monotoon, ook bij gelijke of gewijzigde velden en een reeds toekomstige tijd.

Interne overdracht: MetadataMatchStatus(ctx,itemID) geeft requested/applied-provider/ID, status, veilige foutcode en bestaande kandidaat-updated_at in één query. Alleen bestaande film/serie; geen kandidaat betekent unknown. De nieuwe Item-/lookup/statuswire en actuele client-/cacheconsumers volgen in A2/B1 en zijn hier nog niet gebouwd.

Gecontroleerde onbekende-matched herverwerking zonder currentPass-bump, zonder ambiguous/rejected automatisch te kiezen of toekomstige retry te omzeilen. Een oude brede pass-tak kon die bestaande grenzen wel omzeilen; elf oude/newpass- en NFO-tegenvoorbeelden bewijzen de aangescherpte invariant, gewone eligible passherverwerking en de aparte zevendaagse keyless NFO-klok. Oude done-fixtures gebruiken nu echte publicatie in plaats van alleen kandidaatopslag.

| Controle | Resultaat |
|---|---|
| Nieuwe feature-RED | Vijf nieuwe catalogushoofdtests met subcases rood op ontbrekend schema/herverwerking |
| Brede relevante GREEN | 196 hoofdtests /283 inclusief subtests PASS, 0 SKIP/FAIL |
| Definitieve extra target/artworkguard-delta | 25 hoofdtests /79 inclusief subtests PASS, 0 SKIP/FAIL |
| Laatste oude/newpass-negatieven gevolgd door GREEN | 1 hoofdtest /12 inclusief subtests PASS |
| Negatieve controles | Acht bedoelde behavioral FAILs met SHA256-exact bronherstel |
| Vet en canonieke protocolcheck | Exit 0; geen protocolskips |
| Historische migraties | Alle dertig bestaande SQLbestanden bytegelijk |

Echte encrypted proef: schema30 naar31, herstel van31 met requested B/applied A/failed, herstel van30 en opnieuw31; rijen/config behouden, oude matched opnieuw unknown. De vaste historische24→30-rehearsal blijft groen en ongewijzigd. Verse stores/runners gebruiken duurzame testdata; geen fysieke proces-/NAS-/hardwareproef.

Tijdens deze module zijn bestaande gaten voor candidate.ItemID en ProviderArtwork.ItemID buiten de gelockte target elk rood aangetoond en met kleine early-rejects gesloten. De laatste artworkguard is na de brede basisrun gericht geverifieerd, met eigen negatief en vet. Eerdere harnasfouten (fixtureduur/Sync/vaste schemagrens/ongebruikte testvariabele) zijn afzonderlijk gecorrigeerd; zij tellen niet als productfix.

Volledige logs/scripts: /tmp/task5-gap-restore-1101/applied-a1-*, precieze selectors/overdrachtsinterface in .superpowers/sdd/METADATA-IMPLEMENTATIE/task-1-report.md. Alles via de gedeelde Pleya-wachtrij, bestaande gepinde testimage en eigen wegwerp-Postgres. Geen echte provider, sleutel, paidcall, UI, NAS, push/merge/deploy. Onafhankelijke adversariële review: spec en correctness akkoord, geen Critical/Important. Eén Minor is geverifieerd en uitsluitend als testcomment verduidelijkt: de uncertain-return-wrapper simuleert een niet-gepubliceerde uitkomst, geen echte rollback of netwerkstoring. Bestaande echte transactierollbacktests blijven groen. Normale commithooks volgen bij de lokale commit.
