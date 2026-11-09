# PS-14: meetproxy voor onbekende bibliotheeksoort

5 november 2026. Roadmap C-05 / voorwaarde vóór S3. Eigenaar: Michel Knoop.

`scripts/ps14_kind_proxy.py` voert de bestaande meetopzet uit PS-14 hoofdstuk 11 uit. Hij voegt uitsluitend aan `GET /pleya/v1/libraries` één synthetische bibliotheek met `kind: books` toe en geeft voor de items van die ene ID een lege pagina. Andere antwoorden worden doorgestuurd, inclusief binaire streams. De vaste upstream ontvangt dezelfde autorisatie; de proxy logt geen aanvragen, credentials of bodies en volgt geen redirects. Dubbele antwoordheaders blijven behouden. Voor de herschreven bibliothekenlijst worden conditionele cacheheaders verwijderd en geldt `no-store`.

De proxy staat buiten de servermodule. Er is geen productie-import, migratie of wijziging van `LibraryKind`. De begrensde MCP-instelling geeft geen toestemming voor de boeken-API. Laag C en het validatorbesluit blijven voorwaarden vóór het boekenvenster.

Lokaal starten tegen de eigen synthetische testserver:

```sh
python3 scripts/ps14_kind_proxy.py --upstream http://127.0.0.1:18864 --port 18865
```

`--bind` is standaard `127.0.0.1`. Een meting op een fysiek toestel vereist een apart bereikbaar testadres. Gebruik uitsluitend de geïsoleerde testinstance: normale mutaties worden transparant doorgegeven, dus dit instrument maakt een productie-upstream niet veilig voor acceptatietests.

De gerichte zelftest controleert de twee herschrijvingen, behoud van bestaande bibliotheken en autorisatie, doorgifte van POST-bodies/status, een binaire stroom groter dan 1 MiB, dubbele cookies en weigering van credentials in de upstream-URL of een absoluut aanvraagdomein. De drie zelftests slagen in `final-validation.log` (2,53 seconden), via de SSD-startcontrole en normale wachtrij. De onafhankelijke code-review vond geen blocker. De proxy weigert chunked requestbodies en bodies groter dan 1 MiB; gebruik hem uitsluitend voor deze leesmeting, niet voor uploads of algemene serveracceptatie.

Laag C blijft open op iOS, tvOS en desktop. Per platform ontbreken nog de beelden en waarnemingen van bibliotheekoverzicht, openen, zoeken/hubs en herstart met cache. De aanwezigheid van gekoppelde toestellen is geen acceptatiebewijs. Er is geen client geïnstalleerd of op een fysiek toestel gestart voor deze meting.

De verse read-only apparaatcontrole op 5 november kon via CoreDevice geen verbinding leggen met de gekoppelde iPhone en Apple TV (code 4000). Een paired-vermelding bewijst dus geen bereikbaarheid. Er zijn geen apps geïnstalleerd, gestart of omgezet naar een andere server. De twee beperkte inventarisresultaten blijven bij het taakbewijs; zij sluiten laag C niet.
