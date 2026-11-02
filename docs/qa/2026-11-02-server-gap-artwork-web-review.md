# Task8 artwork-Web — onafhankelijke scopedreview

Roadmap S22.5/A-07. **CHANGES NEEDED door I1; overige spec/auth/visuelepariteit PASS binnen dit pakket.** Exact frozen dirty pakket op `316e8510a7e2fc45117551991f0b3c4fbeabf7d8`,17stagingpaden (16bron+QA),834diffregels. Eén complete read-onlypass; geen tests/gates/builds/Docker/UI/netwerk/productwrites. Alleen dit ignored rapport geschreven. Gesloten backend/schema/wire niet opnieuw geaudit.

## Critical

Geen.

## Important

**I1 — Aangeboden reload herstelt het bronvoorbeeld na mislukte post-unpin-refresh niet.** `pleya_web/src/lib/admin/metadata/ArtworkEditor.svelte:85`–`:91`, `:43`–`:57`, `:143`.

Concreet scenario: bestaande posterpin wordt succesvol losgemaakt; de response bevestigt pin=null. De component wist `defaults`, waarna uitsluitend de aansluitende `client.item(id)` door een tijdelijke netwerk-/serverfout mislukt. De zichtbare boodschap zegt correct dat de pin verwijderd is en “het bronvoorbeeld kon niet worden ververst. Herlaad om opnieuw te proberen.” Na netwerkherstel klikt de beheerder op **Afbeeldingskeuzes herladen**. Dat verhoogt alleen attempt. De effect-run haalt uitsluitend candidates op; bij dezelfde item/client/accountcontext is changed=false en wordt defaults niet opnieuw ingevuld. Er volgt geen nieuwe itemread. Zelfs herhaald klikken verwijdert wel de foutmelding maar laat het geldige bronbeeld permanent als leeg/fallback zien tot een volledige paginanavigatie. Dit is een defect herstelpad, geen dataverliesclaim.

Laat de bestaande reload/retry daadwerkelijk de noodzakelijke item/defaultread hernemen, met dezelfde abort/sequence/item/account/capabilitygrens en zonder de bevestigde unpin terug te draaien. Vereiste gerichte regressie: succesvolle unpin→eerste itemread faalt→verbinding hersteld→eigen reload→nieuwe itemread en werkelijk nieuw bron-artwork-ID zichtbaar; geen extra PUT of herstelde pin. Bestaande succesvolle-unpin- en409-tests dekken deze volgorde niet. Bronmatig bevestigd; conform opdracht geen nieuwe test uitgevoerd. Root heeft dit onafhankelijk bronmatig bevestigd vóór rapportclosure.

## Minor

Geen afzonderlijke bevindingen.

## Overig beoordeeld

Expliciete selectie/preview versus serverbevestigde pin, gezamenlijke poster/backdropbody, null-unpin, behoud bij409/429/source-loss, provideruitval/keyless/unknown-uitwegen en bestaande match/veldenroutes gelezen. Nieuwe mutaties zijn itemgebonden; currentguards bewaken sequence/client/generation/subject/admin/capability vóór verwerking van late reads/writes. Item-/account-/rol-/capabilityverlies wist context en annuleert reads; previewloader bewaakt zijn vastgelegde context vóór/na blobawait. Artwork-onlycapability opent dezelfde editor zonder ongeautoriseerde veldread. Geen nieuwe provider/key/upload/vrijeURL of product-Go/schemawijziging; Go-delta is opt-in `_test.go` met synthetische bron/cache en loopbackruntime.

NL/EN-bron-/taal-/pin-/foutteksten en creditssectie gelezen. TMDB-logo/link en voorgeschreven Engelstalige notice zijn zichtbaar, ook bij bestaande matchpreview; geen S22.7-app/provider/commerciëleacceptatie uit afgeleid. Bestaande componenten/actiehiërarchie blijven; geen mockupronde of nieuwe northstar geïnterpreteerd.

## Persoonlijk bekeken beeld-/hashbewijs

Beide contactbladen met alle22staten bekeken. Nader persoonlijk gelezen:8viewportoriginelen (`320-oled-preview`, `390-light-source-loss`, `1440-dark-unpin409`, `1440-dark-pinned`, `390-dark-rate429`, `1920-oled-preview`, `1280-light-provider-unavailable`, `390-oled-series`) plus4fullpagecompanions (smalleOLEDpreview, source-loss,409,confirmedunpin). Tekst/bediening/credits passen, selectie/focus onderscheidbaar, pin/foutstatus eerlijk; geen nieuwe visuele blocker. Fullpage sticky-shellposities zijn de vastgelegde capturegrens, geen productoverlapbevinding. Geen claim alle44beelden afzonderlijk op volledige resolutie gelezen te hebben; alle22staten zijn via de boards beoordeeld.

Alle16sourceSHA256/Gitblobs en199built-Webhashes exact. FreezeSHA `cdc226c792a6883bb49914927b38d841f94563baf5e61e83485c64a5d314950a`; receiptSHA `085541f85dcc58d24909068205439c3e8f6a2ab7627ac84d3044230a10929e77`. Alle receipt-artifacthashes en44PNGhashes kloppen. Logs zelf gelezen:107tests/8filesPASS; Svelte0errors/0warnings; buildPASS; canonieke gatePASS met drie expliciete bredeDCL-SKIPs. Contextmutant faalt op bedoelde lateconfirmassertions en bronherstel is bevestigd door huidige hashes. Finale browser22staten/13scenario’sPASS en runtime53.35sPASS; historische argument-/seriefixturefouten niet als acceptatie meegeteld. Geen mocks als productbewijs verkocht; browser is echte lokale synthetische handlerketen. I1 heeft nog geen runtimebewijs.

Alle overige reviewgrenzen blijven: geen native/PleyaVerify-, NAS/liveprovider-/licentie-/releaseclosure. Eén gezamenlijke geverifieerde fixronde en verse scopedfixreview via root nodig. Geen denied/pending/onzekere uitvoeractie.
