# Herstelregister: iCloud-voorkeurensync (DEC-131)

Aangelegd op 24 september 2026 bij DEC-131. Eén rij per punt uit de audit van dezelfde dag. De
statusladder is `OPEN`, `CODE CLOSED`, `UNIT VERIFIED`, `HARDWARE OPEN`, `DEFERRED`. Een rij krijgt
bij `CODE CLOSED` de SHA, bij `UNIT VERIFIED` het testbestand, en houdt `HARDWARE OPEN` tot het
recept uit de spec (§7) op twee ingelogde toestellen is gedraaid met datum, build en toestellen.

Spec: `docs/superpowers/specs/2026-09-24-icloud-sync-repair-design.md`.
Plan: `docs/superpowers/plans/2026-09-24-icloud-sync-repair.md`.

| Punt | Wat | Status | SHA | Bewijs |
|---|---|---|---|---|
| B1 | `listen()` in productie | OPEN | | |
| B2 | reconcile vergelijkt met de store | OPEN | | |
| B3 | envelop op de draad en bij toepassen | OPEN | | |
| B4 | verwijdering reist als tombstone | OPEN | | |
| B5 | oudere build wist nieuwe sleutels (prune) | OPEN | | |
| B6 | uit en weer aan binnen één sessie | OPEN | | |
| B7 | status bij uitgelogd iCloud | OPEN | | |
| B8 | quota-melding overleeft een reconcile | OPEN | | |
| B9 | accountwissel leest eerst | OPEN | | |
| B10 | taalvoorkeur op de juiste sleutel | OPEN | | |
| B11 | acht stille sleutels en de guard | OPEN | | |
| B12 | profielscope Jellyfin en Pleya Server | DEFERRED | | DEC-131, Consequences |
| B13 | lokale write tijdens remote batch | OPEN | | |
| A1 | event-sink op de platformthread | OPEN | | |
| A2 | reconcile na de initiële download | OPEN | | |
| A3 | sleutelaantal gemeten | OPEN | | |
| A4 | revisieblob begrensd | DEFERRED | | DEC-131, Consequences |

## Hardwareronde

Nog niet gedraaid. Recept: spec §7. Vul per rij datum, build en toestellen in; een vinkje zonder
die drie is geen bewijs.
