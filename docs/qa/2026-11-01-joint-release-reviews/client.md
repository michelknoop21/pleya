# Gezamenlijke releasebundel — onafhankelijke CLIENT/CACHE/UNIFIED review

Roadmap C-03/C-05/A-06c. **PASS binnen onderstaande begrensde scope.** Productbasis `d8cd3c77e025887128cea625699be025a1ad19a0`; de afzonderlijk beoordeelde iOS-lipo-configuratie verandert deze clientcode niet. Geen product-/authoritywrites, tests, netwerk, Docker, NAS of UI uitgevoerd; alleen dit ignored verslag geschreven.

## Bevindingen

- **Critical:** geen.
- **Important:** geen geverifieerde bevinding.
- **Minor:** geen.

## Beoordeling

Releasepakket, baseline-inventaris, B1/B2-QA, oorspronkelijke onafhankelijke reviews en verse fixreviews, TV-integratiebewijs en gecombineerde terminale logs gelezen. De inventaris is provenance van de oudere165 commits, geen nieuwe volledige58k-audit. De concrete cachecommits825b8ab6f/c978427a8/4f56323cd, B1 36a2ec504, B2 164894243 en TV d9e691ed9 zijn daadwerkelijk ancestors van d8cd. Na B2 zijn geen wijzigingen in `lib/services`, `lib/providers`, `lib/assistant`, `lib/media` of `lib/utils` tot d8cd aanwezig. Alle16 B2-fixfreezehashes komen met de kandidaat overeen.

**Identiteit/compatibiliteit.** Applied/legacy/unknown is door mapper, wirecache, lokale profielopslag en live lookup gekwalificeerd. Oude ongekwalificeerde intentie wordt bij applied/unknown/nullclient geen nieuw bewijs; expliciet legacy en andere backends behouden hun bestaande pad. De bron wordt door de detailed-return gedragen, recente IDmemo wordt bij capabilitywissel gewist, en late resultaten worden op bron-/clientcontext begrensd. `lib/services/local_library/local_library_sync.dart:142` vervangt ook retained identiteit en verwijdert oude raw/finalclaims bij onbekende/mislukte lookup. `lib/providers/local_library_provider.dart:780` geeft de gekwalificeerde grens door aan de cataloguscache.

**Cache en groepsintegratie.** `lib/services/unified_catalog/catalog_service.dart:602` weigert bare IDcache voor applied/unknown/offline-Pleya via client én bestaande bibliotheek-/itembackend; resolver-passcontrole voorkomt laat legacybewijs vóór cachepublicatie. Dezelfde trustcontext is door home/search/discovery/FindRun/copyproof bedraad. `lib/services/unified_catalog/source_resolver.dart:329` controleert actuele bron-/visibilitycontext, herkwalificeert persisted claims en houdt empty/hidden-only appliedresultaten unchecked. B2 behoudt expliciet bestaande TTL zonder iedere cachehit live te herverifiëren; dat is geen onvoorwaardelijke versheidsclaim. Finale assistanttargetuitgifte volgt pas na alle awaits en synchrone identity-/visibilityhercontrole; episodebewijs blijft aan parent/server/ordinal gebonden. De eerder gevonden B1-I1 en B2-I1/I2/I3 zijn in code en fixreviews gesloten.

**Viewport/readboundary.** `lib/providers/unified_catalog_provider.dart:400` trekt een hard readboundary onmiddellijk in; alleen dezelfde bevoegde bibliotheken houden de bestaande viewport bij normale achtergrondverversing. `:307` vervangt waargenomen concrete bronnen, behoudt slechts nog niet waargenomen bronnen bij incomplete refresh, en onderscheidt split/rematch van een sessionkey. Dit omzeilt de applied-lookupgrens niet: concrete copy-/targetkwalificatie blijft afzonderlijk. De LRU-querycache is acht sleutels en wordt bij inhoud-/toegangsrevisie gewist. `lib/widgets/tv/tv_catalog_card_grid.dart:379` corrigeert uitsluitend de werkelijk gefocuste behouden kaart na late insert, met postframe-/kolom-/focusguards; de private globale celkey bewaart focusstate bij verplaatsing tussen Row-parents. Geen overlappende conflictoplossing met B1/B2 of nieuwe bronselectieregel gevonden.

## Bewijs en grenzen

B1/B2 fasebewijs en hun negatieve controles worden uit de bestaande onafhankelijke reviews overgenomen, niet als één nieuwe suite opgeteld. B2-finale gate is inmiddels terminaal All checks passed; de oude fixreview-pendingpassage is historische stand. Gelezen gecombineerde `release-candidate-local-checks.log`: codegate PASS,376 gerichte Fluttertests PASS,2 idb-timeouttests PASS; `release-native-repair.log`:11 inputcontracttests en zes native scenario’s terminal PASS op schone d8cd. De nativebeelden behoren bij de UI-seat; deze reviewer heeft ze in deze bundelpass niet opnieuw bekeken en claimt geen nieuwe visuele gate.

Geen volledige heraudit van oudere persoonlijke functies/playback/auth/offline/copy-watch, servermigraties/provider/API-security, Cinema/Web-UI of authorityreconciliatie; deze blijven bij hun bestaande bewijs en andere bundelseats. De afzonderlijke iOS-configfix heeft eigen PASS, daadwerkelijke iOS-buildacceptatie is hierdoor niet bewezen. Fysieke Siri Remote/touch/Bluetooth, performance/jank, echte cache-aan/uit/warm/koud/offlinematrix, PR/main-CI, NAS-upgrade/rollback en TestFlight/deploy blijven aparte poorten. **Geen cliëntintegratieblocker gevonden; dit is geen release-/deploymentreceipt.**
