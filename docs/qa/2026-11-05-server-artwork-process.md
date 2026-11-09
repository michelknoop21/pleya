# Artworkcoördinatie tussen serverprocessen

5 november 2026. Roadmap C-05/S4.4, bestaande veilige purgegrens S4.6. Eigenaar Michel Knoop. Branch `work/server-completion-20261105`, basis `bd106da29`. Geen API-/schemawijziging.

Twee processen met dezelfde laddercache deelden de bestaande single-flightgroep niet. De nieuwe echte subprocessproef rendert daarom op de oude code twee keer dezelfde trede (`artwork-process-red.log`). Unix gebruikt nu gedeelde directoryleases voor lezen/renderen en een exclusieve lease voor purge. Een koude render neemt bovendien één van 64 vaste, gehashte lockslots en controleert de cache opnieuw. Er komen geen lockbestanden per titel/generatie bij. De eigen lease van `Open` blijft tot de response-descriptor is geopend; achtergrondwerk houdt bij callerannulering zijn afzonderlijke lease.

De eerste grove directorylock verhinderde twee parallelle koude renders. De bestaande regressie wees dit af (`artwork-process.log`). De gedeelde directorylease plus aparte slots herstelt dat. Verschillende sleutels kunnen op hetzelfde slot vallen en wachten dan; de bovengrens van twee lokale renders en snelle warme lezingen blijven bewezen. Dit belooft geen globale fairness tussen processen.

Bewijs staat onder `/Volumes/SSD/Codex/tasks/pleya-server-completion-20261105/`:

- `artwork-open-lease-negative.log` en `artwork-purge-lease-negative.log`: zonder de betreffende lease faalt de bedoelde response-/annuleringsassertie.
- `artwork-final.log`: Go vet en het volledige artworkpakket PASS; twee echte processen leveren één render voor dezelfde koude trede. Annuleerbare purge, behoud van geopende responsebytes, twee koude renders naast warme cache, 64-slotgrens en symlink-/hardlinkweigering zijn groen. De gerichte APIcachecohorten en volledige scan/metadata/pinproef slagen; twee opt-in proeven zijn SKIP: browserfixture en de echte ENOSPC-proef. De browserfixture krijgt geen bewijsclaim; ENOSPC is afzonderlijk uitgevoerd zoals hieronder vastgelegd. Actuele lokale serverbinary gebouwd, algemene gate `All checks passed`; drie brede optionele lintercontroles blijven bij CI.
- `artwork-enospc-fixed.log`: echte volle 1 MiB-tmpfs PASS, geen ladderpublicatie en stats 0/0. De eerste run in `artwork-enospc.log` vond uitsluitend een leeg vast lockslot. De oude assertie vereiste een volledig lege directory en is aangescherpt naar geen tijdelijke renderbytes of ladderpublicatie, met hoogstens één leeg regulier lockslot. Geen filesystembeveiliging versoepeld.
- `artwork-platforms.log`: artworktestbinary compileert voor darwin/arm64 en windows/amd64. Dit is geen runtimeproef op die platforms. Niet-Unix behoudt uitsluitend bestaande proceslokale single-flight; veilig cachebeheer was daar al niet beschikbaar.
- Onafhankelijke code-review vond de render-naar-open-race; de aanvullende eigen Open-lease en gerichte regressie zijn beoordeeld als PASS zonder open scoped bevindingen.

Automatisch ouderdom-/ruimtebeleid, quota, overige cachetypen, niet-Unix-procescoördinatie en NAS-/bestandssysteemacceptatie blijven open. S4.4 blijft daarom gedeeltelijk. Alleen eigen testcontainers en tijdelijk testmateriaal zijn opgeruimd; bron, taakbuilds en bewijs blijven bewaard onder beheer van Michel Knoop.

Hercontrole 9 november 2026: de oorspronkelijke purge kon warme lezingen blokkeren bij een render in een ander proces. De reparatie geeft de lokale schrijfgate vrij tussen pogingen op de exclusieve proceslock. De lokale proef gebruikt een Linux-bestandssysteem; NFS, SMB en Docker-bindmounts naar een NAS zijn niet geaccepteerd. Op die opslag blijft procesoverschrijdende coördinatie onbewezen.
