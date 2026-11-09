# MCP-transport van Pleya Server

Roadmap C-05/S16. Dit is een lokale leesproef, standaard uit. G1, de gedeelde server-side menselijke goedkeuringslaag, ontbreekt. De agent kan geen beheer- of credentialhandelingen via dit register uitvoeren. Een door de agent ingevulde `confirm` is geen menselijk akkoord. Externe client-, CI-, apparaat-, NAS- en releaseacceptatie blijven afzonderlijk open.

## Verbinden en rechten

`POST /mcp` gebruikt stateless Streamable HTTP met JSON-antwoorden en een bestaand bearercredential. Gebruik voor agents een afzonderlijk leestoken. Een cookie of MCP-session-ID geeft geen rechten. Alleen een bevoegde beheerder kan `mcp_enabled` via de bestaande settingsroute wijzigen. Uitgeschakeld geeft het transport 404.

Iedere geregistreerde tool doorloopt de bestaande rol-, token- en bibliotheekautorisatie opnieuw. De lijst is privé, heeft TTL 0 en volgt de actuele rol en het tokenbereik. Het inschakelen van MCP geeft geen aanvullende rechten.

## Expliciet geclassificeerd register

[De classificatietabel](../pleya_server/scripts/mcp_policy.json) legt voor iedere OpenAPI-operatie de operationId, methode, het pad, de toegangskeuze en een reden vast. Alleen gecontroleerde JSON-GET-operaties worden tools. De generator faalt bij een onbekende operatie, gewijzigd pad of methode, ontbrekende reden of verouderde classificatie. Een nieuwe GET of POST wordt dus niet automatisch beschikbaar.

Het huidige register bevat 49 leestools. Alle mutaties, account- en tokenuitgifte, login, refresh, setup, streamcredentials en binaire leveringen zijn uitgesloten. Ook back-updownloads zijn uitgesloten omdat hun inhoud geheimen kan bevatten. Een directe aanroep van een uitgesloten naam bereikt geen API-handler. De bestaande REST-API is hiermee niet voorzien van G1: de oude REST-bypassbescherming en de bijbehorende goedkeuringstest blijven onderdeel van de nog niet geïmplementeerde G1-laag. Geef agents geen beheertoken om deze grens via REST te omzeilen.

`gen_mcp_tools.py --check` controleert classificatie en gegenereerd register. Toolbeschrijvingen behandelen bibliotheekinhoud en logregels als onvertrouwde gegevens.

## Grenzen en antwoorden

JSON-RPC-arrays worden vóór SDK-dispatch geweigerd, ongeacht protocolversie. Alle MCP-aanvragen delen per geauthenticeerde gebruiker één budget: 60 direct, daarna één per seconde. Meerdere tokens van dezelfde gebruiker delen dat budget. Een volle kaart verwijdert geen actieve gebruikersbudgetten om nieuwe aanvragen toe te laten. HTTP 429 bevat `Retry-After`; de REST-limiter blijft afzonderlijk.

Argumenten hebben gesloten schema's onder `path`, `query` en waar nodig `header`. Andere doeladressen en Authorization-/Cookie-argumenten zijn niet toegestaan. De envelope blijft begrensd op 264 KiB. Binnenste dispatch behoudt de bestaande bodylimiet en maintenance-gate.

JSON- en tekstantwoorden komen als tekstcontent terug, maximaal 1 MiB per aanroep. Gebruik de bestaande paginering. Binaire antwoorden worden geweigerd; er zijn geen resource-links met ruwe Host-headers of gereflecteerde streamcredentials.

## Audit en open goedkeuring

Een bestaande handler behoudt haar onderwerp in `UserID` en `SessionID`. De MCP-adapter legt de geverifieerde aanvrager afzonderlijk vast als `actor_user_id` en `actor_session_id` in het auditdetail. Dat is geen nieuwe approval-laag en maakt uitgesloten mutaties niet beschikbaar. Het [G1-voorstel](pleya-server-mcp-g1-window-proposal.md) beschrijft de nog vereiste actor-/resource-/parameterbinding, expiratie, revisies en bescherming van alle ingangen.
