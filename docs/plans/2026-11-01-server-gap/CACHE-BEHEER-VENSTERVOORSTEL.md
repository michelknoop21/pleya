# Voorstel: begrensd artworkcache-beheervenster

Status: GEOPEND door Michel op2november2026: “Open dit beperkte cachebeheer-venster (aanbevolen)”. Roadmap C-05/S4.6; bestaande richting J-api-schema-migratie.md:90 (`GET /artwork/cache`, `DELETE /artwork/cache`). Getest checkpoint e8aba921f blijft intact. Michels opdracht voor servergapontwikkeling autoriseert het werk, maar docs/agents/server.md houdt het wirecontract expliciet bevroren tot een afzonderlijk vensterbesluit. Dit document vraagt uitsluitend die bestaande twee beheeroppervlakken concreet vrij te geven; geen nieuwe providers, uploads, MCP, NAS of releasehandeling.

## Uitkomst voor de beheerder

In de bestaande Opslag-pagina ziet een admin de omvang en het aantal verkleinde artworkbestanden en kan die afgeleide cache na bevestiging leegmaken. Het scherm legt uit dat verkleinde posters/achtergronden opnieuw worden gemaakt. De bestaande mediaroottabel/hercheck en navigatie blijven werken. De taak is zichtbaar in de bestaande takenlijst: wachtend/lopend/geslaagd/fout, met bestaande retry/cancel waar toepasselijk. Geen assistent nodig.

## Exacte additieve contractscope

- Optionele capability `artwork_cache_admin`, onbekend/afwezig geldt als false. Alleen true wanneer de volledige stats-/purgeketen beschikbaar is; nieuwe UI roept de routes anders niet aan.
- `GET /artwork/cache`, klasse admin. Gesloten antwoord met `bytes` (niet-negatieve int64) en `files` (niet-negatieve integer), uitsluitend de afgeleide `artwork-sizes`-cache. Geen paden, bestandsnamen, credentials of individuele mediatitels. Onbereikbare/leesmislukte cache is een fout, geen fictieve nulstand; ontbrekende lege cache telt nul.
- `DELETE /artwork/cache`, klasse admin, gesloten body `{"confirm":"purge"}`. Alleen deze exacte bevestiging kan één duurzame `artwork_cache_purge`-taak via de bestaande jobsvoorziening inplannen; succesvolle ontvangst202 betekent nog niet klaar. Herhaald klikken dedupliceert zolang dezelfde taak wacht/loopt. Geen vrije map/type/queryparameter en geen extra operatieframework.
- De nieuwe jobsoort gebruikt de bestaande jobstatus-/retry-/cancel-/foutstructuren en de bestaande jobsroutes. Geen nieuwe statusenum, generieke cacheobjecten of operationsendpoint. Audit voor ontvangen mutatie en bestaand jobresultaat; bestaande rollen/intrekking/origin-/CSRF-regels blijven leidend.
- Alleen nieuwe routes/schemas/capability/foutfixtures die deze twee acties werkelijk nodig hebben. Bestaande veldbetekenissen en gesloten bodies ongewijzigd. Gebruik bestaande passende foutcodes; een aantoonbaar noodzakelijke nieuwe code blijft tot dit oppervlak begrensd. Zes protocolcompatibiliteitsregels, OpenAPI/generator/fixturetests en onafhankelijke securityreview zijn verplicht.

## Wat dit niet als afgerond presenteert

Purge raakt uitsluitend vervangbare ladderbestanden onder de door de server bepaalde cachemap. Originele/media-/providerbestanden, gepinde bronbytes in `artwork-pins`, metadata/pinintent, config, sleutels, backups, ondertitel- en transcodecache blijven behouden. Pin-cacheverlies en de bewaarde host503 hebben hun eigen hersteltest; een beheerknop mag die niet veroorzaken door actief gebruikte tijdelijke bestanden te verwijderen. Het cachepad of een symlink mag niet naar echte media ontsnappen.

Dit is het bestaande S4.6-oppervlak, niet de volledige opslaggap. Quota/limietinstellingen en automatisch ouderdom-/ruimtebeleid, overige cachetypen/actieve leases en algemene ENOSPC-beheerdekking blijven expliciet open tot hun eigen gecontroleerde uitvoering. Deze opening schrapt die vereisten niet en introduceert geen willekeurige standaardlimiet of instelling.

## Acceptatie vóór lokale integratie

1. Echte cached trede maken; stats bytes/aantal exact, nulcache en lees-/ENOSPC-fouten eerlijk. Niet meetellen of verwijderen: tijdelijke `.incoming-*`, directories, symlinks/andere bestanden buiten de exact ondersteunde afgeleide namen.
2. DELETE zonder/verkeerde bevestiging, member/guest/intrekking/originfout en afwezige capability sturen niets of weigeren veilig; oude clients/servers blijven werken. Dedupe/audit/jobfout/cancel/retry werkelijk testen.
3. Purge tijdens een vastgehouden render/response bewijst: lopende aanvragen leveren hun bytes correct, tijdelijke uitvoer niet corrupt, na gereed geen stale resized publicatie en opnieuw openen maakt dezelfde juiste afbeelding. Bestanden worden niet blind tijdens een actieve schrijver verwijderd; fouten blijven zichtbaar in de taak.
4. Identieke bron/pin-/item-/file-/persoonlijke rijen en bron/config/backups voor/na. Geen recursief RemoveAll op een willekeurig pad. Een partial-deletefout wordt geen geslaagde leegmelding.
5. Echte beheerflow op normale synthetische server plus 320/390/1440-beelden, toetsenbord/fout/herhaal en regressie van bestaande Opslag-bediening. Geen nieuwe mockupronde; bestaande R3-componenten.

Interne pin-cache503-diagnose en bestaande interne cachecorrecties kunnen onafhankelijk doorgaan. Het specifieke vensterbesluit is ontvangen; wire-/beheerimplementatie mag binnen deze scope beginnen nadat het besluit in de eigen implementatiebranch is vastgelegd. Geen publicatie zolang de afzonderlijke publieke GitHub-bestemming niet bevestigd is.
