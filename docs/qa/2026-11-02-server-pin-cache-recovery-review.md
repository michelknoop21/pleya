# Onafhankelijke pin-cache503-fixreview

**PASS — geen Critical, Important of Minor in deze afgebakende codefix.** Roadmap C-05/S22.5. Verse onafhankelijke review van de twee bevroren Go-bestanden op `fix/server-cache-recovery-1102`, basis/HEAD `e8aba921f595712b33711e68cda57f95dd06a1f8`. Geen tests, Docker/browser, subagents, product-/authoritywrites, build, commit, push of NAS uitgevoerd; alleen dit rapport geschreven.

## Correctheid en scope

`pleya_server/internal/artwork/pins.go:378–402` beperkt herstel tot de private atomische cachewrite: contextcheck vóór elke poging, uitsluitend `errors.Is(err, os.ErrNotExist)` opnieuw proberen, maximaal drie pogingen, twee mogelijke10ms-pauzes via annuleerbare timer. Succes en niet-ENOENT komen direct terug; EACCES/ENOSPC worden niet gemaskeerd. Annulering tijdens de pauze retourneert de contextfout; vóór de volgende poging wordt de context nogmaals gecontroleerd.

Elke poging gebruikt `writeCacheAttempt` (`:404–427`): opnieuw MkdirAll, unieke temp, write/fsync/close, Rename en deferred tempcleanup. Deze volledige body persoonlijk byte-exact aan de oorspronkelijke HEAD-writer vergeleken. Beide productiecallers (`:360`, `:475`) geven hun bestaande context door. Retry bevindt zich ná bronread/beeldvalidatie/digestcontrole en, bij Resolve, opgeslagen pincontrole; hij herhaalt alleen dezelfde bytes onder dezelfde pin-ID/SHA/extensie. Geen extra providerrequest, bronherkeuze, duurzame pinwrite, generatie-/rechten-/API/schemawijziging of ruimere foutverhulling. Bestaande Prepare-contextcheck na schrijven en Resolve-contextselect blijven behouden. Permanente filesystemfouten blijven zichtbaar; voortdurend verdwijnen geeft na de derde ENOENT een fout, geen vals succes.

## Oorzaak en gericht bewijs

Het behouden oude image16c1f89d… reproduceert host-rmtree→GET503 in ronde1; `host-rounds.json`, `host-outcome.json` en serverlogregels60–61 binden CreateTempENOENT aan dezelfde pin. Diagnose-exit0 betekent REPRODUCED, geen herstel-PASS. De codecallchain bewijst dat CreateTemp pas na een succesvolle MkdirAll wordt bereikt. De bekende syscallgrens is daarmee nauwkeurig vastgesteld; exacte virtiofs-/kernelinterne oorzaak blijft onbekend.

`pin_cache_test.go:18–85` gebruikt echte CreateTemp/Rename-fouten na gecontroleerd mapverlies, vervolgens de daadwerkelijke productie-attempt voor herstel. De private functieparameter is een lokale seam, geen globale hook of mockfilesystem; de eerste fout wordt door een echte syscall geproduceerd. Dit bewijst de ENOENT-herstelgrens, niet de virtiofs-internals of de volledige HTTP-callchain. De no-retry-baseline persoonlijk vergeleken: uitsluitend seamrefactor met `return attempt()`, dezelfde oorspronkelijke writerbody en twee contextcallers; geen testafzwakking.

Ruwe logs persoonlijk gelezen/geteld: RED vier hoofdtests/zes inclusief subtests FAIL, één/drie PASS, nulSKIP; beide filesystemgrenzen geven bedoelde gedrags-RED, geen compile-/infrastructuurfout. Eerste unitGREEN vijf/negenPASS; finale unit incl. permanente Rename-/tempcleanup zes/tienPASS. Finalebron test tevens permanente ENOENT/max3, directe EACCES/ENOSPC, annuleerbare pauze, vooraf geannuleerd request zonder write en exacte herstelde outputbytes/enkel definitief bestand. Bestaande artwork/API-regressies17/32PASS, nulFAIL/SKIP; onder meer bronverlies/vervanging, duurzame identiteit, rechten/rematch/GC en decodegate. `vet.log` leeg; scripts met set-e en `observed-exits.json` registreren RED1, regressies/vet0, finaleunit0. Eerste platformmismatch125 blijft apart infrastructuurbewijs. Deze review heeft niets opnieuw uitgevoerd.

## Integriteit en resterende grens

Alle31 artifact-SHA’s persoonlijk herberekend: exact. Werkelijke finale productie-SHA `adf1cb96afe792fa0b14b974087f2ba101017db3a73948322e880f37d8f6b55a`; test-SHA `b28518e1c880f560a4c0d9f211ceb342258d57867b2d8be9338bcfe317981970`, beide exact source-freeze. Fixdiff-SHA `4834abc8d930bc820d6d2bad0f18ebff461a515013e90541e6a41cb460517417` exact. HEAD blijft e8; alleen bedoelde productiefile gewijzigd plus nieuwe testfile. `git diff --check` in review exit0.

Geen codeblocker gevonden voor deze kleine herstelpatch. Normale bevroren fixed-imagebuild en verse host→guestGREEN blijven expliciet pending bij root: deze PASS is code-/gericht-bewijsreview en sluit de oorspronkelijke runtimefout nog niet als fixed-imageacceptatie. Brede S4.6-cachebeheeruitbreiding, andere retries/providerbeleid, NAS, hardware, release en authorityregistratie vallen buiten deze fix; daarvan is hier niets geïmplementeerd of geclaimd.
