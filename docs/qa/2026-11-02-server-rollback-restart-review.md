# Onafhankelijke operator-/evidencereview — restartpolicy

**PASS binnen dit afgebakende pakket.** Geen Critical/Important/Minor bevestigd. Basis6b784; beoordeeld: nieuw rollback-restart-QArapport/assets, gewijzigde operatorrollbackpassage en uitsluitend de extra bewijsalinea in S25.4. Geen codeheraudit, runtimeherhaling, tests/builds/Docker/NAS/UI/netwerk- of productwrites. Alleen dit ignored rapport geschreven.

## Bewijscontrole

- Alle **18 lokale evidencehashes** en **5 behouden assethashes** matchen hun manifests. Voor/na-JSON is bytegelijk; baseline-container-ID/naam/states zijn vóór/recovery/cleanup bytegelijk. Links naar QA/assets bestaan.
- Negatief is werkelijk daemonbewijs, geen aangenomen terugkeer: `negative-events.jsonl` toont `die` met exitCode75 en daarna `start` van dezelfde nieuwe image. `negative-inspect.json` toont exact image e4c685ff…964a92, policy`unless-stopped`, RestartCount1 en schema32. `negative-restart.log` bevat restore202/voltooiing, nieuwe startup en opnieuw migraties31/32 vanaf30. Hiermee blijft de eerdere handmatig gestopte imageproef geldig, maar is nu aanvullend de automatische herstartval bevestigd.
- Positieve orchestratie `run.py:85–93` wijzigt alleen de eigen containerC naar`restart=no`, leest de werkelijke policy terug, gebruikt de gewone APIconfirmation/restore202 en controleert `docker wait`75 plus schema30. Dezelfde volledige snapshot/keyhash wordt **vóór imagewisseling** vergeleken. Daarna wordt de gestopte eigen container vervangen door de exact bewaarde oude image6729466e…5803b met normale`unless-stopped`-policy; ready200 en gelijke snapshot volgen. Geen RunTo/neerwaartse SQL, authbypass of productpatch.
- De digestquery neemt alle kolommen van de tien opgesomde tabellen via gesorteerd row_to_json mee, zonder uitgesloten velden. Signingkey-SHA256 komt overeen. Het archiefbewijs bevat normale manual/upgradebackups op schema30 met versleutelde configgeheimen; de SQLdump blijft gzip zoals het rapport expliciet zegt. Dit blijft geselecteerd synthetisch behoud, geen claim over iedere producttabel.
- `execution.log` en `timeline.log` lopen door tot POSITIVE PASS02:00:46. De buitenste shell-exit is na transportverlies **onbekend** en wordt nergens als exit0 verkocht. Dat ontkracht niet de afzonderlijk vastgelegde operationele75 via daemon-events/waitassertion en de geobserveerde herstart/schema-uitkomst. Cleanup is afzonderlijk als exit0 vastgelegd; eigen DB/rol/container/mounts/geheimen/archieven afwezig, bestaande resources volgens genoemde snapshots intact. Geen actie door deze reviewer om dat opnieuw op de daemon te meten.

## Operatorveiligheid en autoriteit

De gewijzigde handleiding legt de juiste volgorde vast: passende oude image/backup/config bewaren; uitsluitend huidige server vóór restore op no en controleren; geen Compose-recreate van de nieuwe image tussendoor;202 niet als voltooiing behandelen; exit/schema/config controleren; nieuwe image gestopt houden; pas de passende oude image weer normaal laten herstarten.

De nieuwe foutpassage is essentieel en correct: een pre-maintenanceweigering is geen restore, en de oorspronkelijke policy mag pas terug nadat binary/schema aantoonbaar passen. Er staat **geen** blind herstel van`unless-stopped` op de nieuwe image na een onzekere/geslaagde schema-terugzetting. De normale auth-, versieguard- en bevestigingsgrenzen blijven gelden.

S25.4 krijgt alleen aanvullend lokaal bewijs; checkbox/andere taken veranderen niet. De operatorclaim over historische schema30/32 is zorgvuldig onderscheiden van huidige schema33/pins, exacte NAS-productieimage, offsite/sleutelrecovery, hardware en volledige server-gap-/releaseclosure. De eerdere imageproef en deze restartproef vullen elkaar aan; geen geschiedenis is ten onrechte naar productieacceptatie opgewaardeerd.

Geen resterende blocker voor dit document-/bewijscommit. Geen denied/pending toolactie; vrijgave van NAS/livehandelingen blijft afzonderlijk bij root/Michel.
