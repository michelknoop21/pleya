# Pleya Server: back-ups, terugzetten en upgraden

Dit document is voor wie de server beheert. Het zegt waar de back-ups staan, wat erin zit, hoe je er een terugzet en wat er bij een upgrade gebeurt. Het gedrag is getest in `pleya_server/internal/backup/backup_test.go`, `pleya_server/internal/api/backups_api_test.go` en `pleya_server/cmd/pleya-server/backupwork_test.go`. Een kopie buiten de NAS (S25.7) en het beheerscherm (S25.6) zijn nog niet gebouwd.

## De instellingen

| Omgevingsvariabele | Wat ze doet | Standaard |
| --- | --- | --- |
| `PLEYA_SERVER_BACKUP_DIR` | de map in de container waar de back-ups komen | `/backups` |
| `PLEYA_SERVER_BACKUP_TIME` | tijdstip van de dagelijkse back-up, in de tijdzone van `TZ` | `03:30` |
| `PLEYA_SERVER_BACKUP_RETENTION_DAYS` | hoe lang een back-up blijft staan, 1 tot 365 | `14` |
| `PLEYA_SERVER_BACKUP_KEY` | wachtzin voor de geheimen in een back-up, minstens zestien tekens | leeg |
| `PLEYA_SERVER_BACKUP_HOST` | (compose) de hostmap die op `/backups` gemount wordt | `./data/backups` |

Deze waarden staan alleen in de omgeving en niet in `PATCH /settings`. Een bewaartermijn die over de API omlaag kan, kan ook omlaag door iemand die een beheerdersaccount heeft overgenomen, en dan ruimt de server zelf de back-ups op die hem hadden moeten redden.

De nieuwste geslaagde back-up blijft altijd staan, ook als hij ouder is dan de bewaartermijn.

## Wat er in een back-up zit

Een back-up is één tar, `pleya-backup-<tijdstip>-<id>.tar`, met rechten `0600`:

- `manifest.json`: tijdstip, schemaversie, aantallen (titels, gebruikers, bibliotheken, kijkstatus) en hoe de geheimen versleuteld zijn;
- `database.sql.gz`: een `pg_dump` van de database. De rijen van de jobwachtrij en van het back-upregister gaan niet mee;
- `config/...`: de gewone bestanden uit `/config`;
- `secrets.tar.enc`: de geheime bestanden uit `/config` (nu alleen `token-signing.key`), versleuteld met Argon2id en AES-256-GCM.

Zonder `PLEYA_SERVER_BACKUP_KEY` blijft `secrets.tar.enc` weg en staat `secrets_included` op `false`. De ondertekensleutel staat dan niet in de back-up. Na een restore houdt de server de sleutel die er staat, en na verlies van `/config` maakt hij een nieuwe: iedereen logt dan opnieuw in, de catalogus en de kijkstatus blijven.

Met een sleutel is de back-up zonder die sleutel nog steeds bruikbaar voor de database. Bewaar de wachtzin buiten de NAS, in een wachtwoordkluis. Wie de tar én de wachtzin heeft, kan sessies vervalsen; behandel de back-upmap daarom als geheim.

Er is geen endpoint om een back-up te downloaden. Kopiëren gaat via de NAS zelf.

## Waar de map hoort

Zet `PLEYA_SERVER_BACKUP_HOST` bij voorkeur op een andere schijf dan `data/config`. Staan ze op hetzelfde bestandssysteem, dan logt de server bij het opstarten een waarschuwing en zet `GET /backups` `same_failure_domain` op `true`. Dat is geen fout: een back-up op dezelfde schijf beschermt nog altijd tegen een mislukte upgrade of een verkeerde handeling, alleen niet tegen een kapotte schijf.

Maak de map aan met dezelfde eigenaar als `data/config`, anders kan de container er niet in schrijven:

```sh
ssh synology
cd /volume1/docker/pleya-server
mkdir -p data/backups && chown --reference=data/config data/backups
```

`deploy-nas.sh` weigert te deployen zolang die map er niet is. Zie "Upgraden" hieronder voor de reden.

## Handmatig, gepland en de hersteltest

Elke dag op `PLEYA_SERVER_BACKUP_TIME` zet de server een back-up in de jobwachtrij. Is de laatste geslaagde hersteltest ouder dan zeven dagen, dan volgt er direct een hersteltest op die back-up.

De hersteltest maakt een tijdelijke database `pleya_restoretest_<willekeurig>`, zet de dump daarin terug, draait de migraties van de huidige server en telt titels, gebruikers, bibliotheken en kijkstatus na tegen het manifest. De echte database wordt niet aangeraakt. De gebruiker uit `DATABASE_URL` moet daarvoor een database mogen aanmaken; met de standaard `compose.yaml` mag dat.

```sh
A=<access_token van owner of admin>
B=http://127.0.0.1:8832/pleya/v1

curl -s -H "Authorization: Bearer $A" $B/backups                       # lijst, instellingen, waarschuwingen
curl -s -X POST -H "Authorization: Bearer $A" $B/backups               # nu een back-up (202)
curl -s -H "Authorization: Bearer $A" $B/backups/<id>                  # status en laatste hersteltest
curl -s -X POST -H "Authorization: Bearer $A" $B/backups/<id>/verify   # hersteltest nu (202)
```

Een tweede back-up terwijl er een wacht of loopt geeft `409 server.backup_busy`. Een mislukte back-up draagt de code van zijn oorzaak in `failure_code`: `storage.full` bij een volle schijf, `server.database_unavailable` als de database weg was.

## Terugzetten

Een restore zet de database en `/config` terug naar het moment van de back-up. Alles wat daarna gebeurde verdwijnt: kijkstatus, nieuwe gebruikers, sessies, instellingen, scans en het auditlog.

```sh
# De zin staat in restore_confirmation van de back-up en moet letterlijk terug.
curl -s -H "Authorization: Bearer $A" $B/backups/<id> | jq -r .restore_confirmation
curl -s -X POST -H "Authorization: Bearer $A" -H 'Content-Type: application/json' \
  -d '{"confirm":"herstel 2026-10-23T01:30:00Z: kijkstatus, gebruikers, sessies, instellingen en scans van daarna gaan verloren"}' \
  $B/backups/<id>/restore
```

Wat er dan gebeurt:

1. De server controleert alles wat vooraf te controleren is: de zin, of er geen back-up loopt, of het bestand leesbaar is, of het schema niet nieuwer is dan de server en of `PLEYA_SERVER_BACKUP_KEY` op de geheimen past. Een fout hier wijzigt niets.
2. Hij gaat in onderhoud: elke aanvraag krijgt `503 server.maintenance`, `/readyz` meldt niet gereed.
3. De dump gaat in één transactie terug. Mislukt dat, dan is de database ongewijzigd.
4. De bestanden uit `/config` worden teruggeschreven.
5. Het proces stopt met code 75 en compose start de container opnieuw, ook na een mislukte restore. Mislukte stap 3, dan start hij op de oude database; mislukte stap 4, dan staat de teruggezette database naast de `/config` van daarvoor en zegt het log welk bestand niet terug kon.

Na de herstart leest de server de back-upmap opnieuw in. Back-ups van na het teruggezette moment staan daarna weer in de lijst; de geschiedenis van hersteltests van vóór de restore niet.

Zonder Pleya kan het ook: `tar -xf <back-up>.tar database.sql.gz` en `zcat database.sql.gz | psql`. Doe dat alleen op een lege database, want de dump begint niet met het opruimen van wat er al staat.

## Upgraden

Een nieuwe image die migraties meebrengt, maakt vóór de eerste migratie zelf een back-up (`trigger: upgrade`). Lukt die niet, bijvoorbeeld omdat `/backups` niet gemount of niet beschrijfbaar is, dan start de server niet en zegt het log waarom. Dat is opzet: migraties lopen alleen vooruit, en zonder back-up is er geen weg terug.

Start je een oudere image op een database die een nieuwere image al gemigreerd heeft, dan weigert de server te starten met de melding dat de database nieuwer is dan de binary. Terug naar de oude versie gaat alleen door de upgrade-back-up terug te zetten met die oude versie, of door de nieuwe image weer te starten.

## Vier foutcodes

| Wat er misgaat | Code | Waar je hem ziet |
| --- | --- | --- |
| schijf vol | `storage.full` (507) | `failure_code` van een back-up, en elk endpoint dat niet kan schrijven |
| database weg | `server.database_unavailable` (503) | elk endpoint, en `failure_code` van een back-up |
| omzetter crasht | `playback.transcode_failed` (502) | `POST /playback/plan` |
| bronbestand kapot | `playback.file_corrupt` (422) | `POST /playback/plan` als ook een tweede analyse van het bestand mislukt |

De test `TestFailurePathsEachHaveTheirOwnCode` laat alle vier met een echte oorzaak optreden: `/dev/full` als schijf, een database op een poort waar niets luistert, een ffmpeg die aan een segfault sterft en een bestand vol rommel.
