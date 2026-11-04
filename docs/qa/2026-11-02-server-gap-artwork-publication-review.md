# Task7 — verse onafhankelijke CI2-publicatiefixreview

2026-11-02 · Roadmap C-05/S22.5/S14.5, A-07 · **PASS; CI2 gesloten binnen deze afgebakende publicatiegrens.** Geen Critical, Important of Minor bevindingen. Alleen nieuwe opt-in ApiCache-publicatie, detail-/SourceAll-callers, deterministische regressies, QA en afzonderlijke S22.5-statusdelta beoordeeld. BI1/BI2/CI1 niet heraudit. Geen sourcewrites, tests/builds/Docker/UI/NAS/netwerk/commit uitgevoerd; uitsluitend dit ignored rapport geschreven.

## Exacte freeze

`/tmp/task7-artwork-publish-1102/publication-fix.diff`:7bestanden/478regels, SHA256 `bc952cb8e8481e3c5c46367453c5e5ec3624539c75ed4cf261be09f761bf701b`. `final-freeze.json`:48paden, SHA256 `51b4994eff72e8bc2f4bec14bc76426eadeeccbbcad912a4a0e501adbd7771be`. Zelf alle48SHA256/Gitblobs en18receiptartefacthashes exact geverifieerd. Finale keten heeft47bron-/contract-/fixture-/historische-QA-paden vóór/na gelijk; nieuwe publicatie-QA is daarna de48e. Eerdere Go-/protocolblobs zijn volgens finale vergelijking ongewijzigd; geen herhaalde backendacceptatie geclaimd.

## Correctnessbeoordeling

`ApiCache.putIfCurrent` reserveert een vaste gedeelde strook synchronisch vóór de eerste encode-await. Encoders kunnen parallel lopen; publicatie wacht daarna op zijn voorganger, hercontroleert live ownership/context vlak vóór SQL en houdt zijn strook vast tot de insertfuture voltooit. Daarmee kan een reeds geaccepteerde oude A niet ná de nieuwere B eindigen, ook niet via een tweede wrapper op dezelfde database/key. Encoding-/guard-/SQL-excepties verlaten het tryblok via dezelfde finally; de eigen completer wordt zonder fout voltooid nadat de voorganger klaar is, zodat een fout de volgende write niet vergiftigt. Zestien vaste client-isolatestroken introduceren geen groeiende keyregistry; collisions kunnen alleen enkele guarded keys serialiseren, geen globale cachesluis.

De detailcaller behoudt de bestaande accepted/non-titlevoorwaarde en hercontroleert readOrder, bronmodus en gesloten client pas aan de echte publicatiegrens. SourceAll bindt de opt-in aan actuele server-/libraryzichtbaarheid, callerannulering, applied-identiteit en presentatie. De bestaande definitieve resultaatcontrole blijft staan. Standaard `put` gebruikt dezelfde default tryIsolateRun/jsonEncode als voorheen en neemt geen strook; bestaande watchledger en watch-statewritegedrag zijn niet omgebouwd. Geen nieuw wiremodel, TTL, revision- of eventmechanisme.

## Bewijs en praktische limieten

Oorspronkelijk `red.log`: beide daadwerkelijke consumers schrijven Old A waar New B verwacht is, bij dezelfde applied-identiteit en actuele digest B. `green2.log` sluit beide. De nieuwe GREEN ordent A→B; hij beweert expliciet niet dat B vóór vrijlaten van A al gepubliceerd was. Het aparte wrapperbewijs houdt een echte Drift-upsertawait vast met twee wrappers op één DB/key; B encodeert wel maar voltooit niet te vroeg. Parallelle andere keys publiceren door. Encoder-/throwing-guardfoutrelease en live context na encode zijn gericht getest; SQL-errorrelease volgt daarnaast rechtstreeks uit dezelfde finally, niet uit een afzonderlijk beweerde SQL-fouttest. Detail-close en SourceAll-cancel tijdens encode leveren geen late row.

Twee compileerbare mutationREDs voor volgorde en liveownership, telkens finally/SHA-exact hersteld. Finale bestaande evidence:463DartPASS/20bestanden plus canonieke gatePASS; drie brede DCLchecks expliciet CI-onlySKIP. Historisch green.log blijft als eerdere failure onderscheiden. Geen fasecounts opgeteld, volledige suite/native/pixels/liveprovider/schema33image/NAS/release niet geclaimd.

## Afzonderlijke authoritydelta

Alleen S22.5 in `docs/PLEYA-SERVER-MASTERLIST.md:517` is additief veranderd; rij blijft `[~]`, overige rijen en aantallen gelijk, relatieve QA-links bestaan. Task6Webreview wordt actueel als gesloten aangevuld, Task7backend/client uitsluitend lokaal beschreven; Webselector/credits/visuele acceptatie/schema33image/NAS/gecombineerde release blijven open. **Ook de conditionele exacte vervanging “Laatste onafhankelijke publicatiefixreview pending.” → “Laatste onafhankelijke publicatiefixreview PASS, CI2 gesloten.” is inhoudelijk goedgekeurd op basis van deze PASS**, mits uitsluitend die frase wijzigt en alle genoemde grenzen blijven staan. Dit vereist geen nieuwe source-/evidencepass.
