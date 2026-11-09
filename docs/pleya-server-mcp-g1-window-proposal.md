# Voorstel: gedeelde operations en menselijke goedkeuring

Roadmap C-05/S16, G0 en G1 uit het bestaande Big P/MCP-plan op `docs/bigp-mcp-roadmap`, commit `1d66b211fb2f62160660d5ef8880735fdcfff970`. Dit voorstel vervangt de zes S16-regels niet. Status: nog geen contractvrijgave.

Het geopende instellingenvenster betrof alleen `mcp_enabled`. Het lokale transport hergebruikt de bestaande API-rechten en vraagt een operationId als bevestiging. Dat voldoet nog niet aan G1: een agent kan die tekst zelf invullen. Het oorspronkelijke plan vereist een vertrouwde menselijke goedkeuring, duurzame operations en bescherming tegen een omweg via bestaande REST-routes. Geheimen horen niet in agentresultaten. De huidige MCP-code is daarom uitsluitend een lokaal transport- en integratiepakket, standaard uit, geen vrijgegeven agentbeheer.

## Begrensde uitbreiding

Open de contracten voor één gedeelde getypeerde managementlaag: capabilities lezen, een operation voorbereiden, preview/status ophalen en goedgekeurd uitvoeren, met geldige annulering/herhaling. De exacte routefamilie wordt `/pleya/v1/management/operations`; geen vrije browser-toolcall of modelgestuurde URL. De operatie bevat actor, credential/grant, actie, concrete resources, parameterhash, verwachte revisie, verval en idempotencysleutel. Uitkomsten onderscheiden uitgevoerd, geweigerd, mislukt en onbekend. Bestaande job-ID’s blijven leidend.

Menselijk akkoord bindt aan die exacte preview en versie. Voor herstel, sleutelrotatie, rol-/credentialacties gebruiken we een oorspronggebonden WebAuthn-bevestiging met user verification. Een API-token of zelf ingevulde `confirm` kan geen approval afgeven. Gewone beheerknoppen gebruiken dezelfde operations; persoonlijke playbackticks krijgen geen nieuwe handmatige bevestigingsstap.

Alle API-tokens blijven automatisering. Oude schrijvende REST-paden voor de betrokken beheercapabilities vereisen dezelfde goedgekeurde operation, zodat geen omweg ontstaat. De overgang krijgt expliciete compatibiliteitsregels, getypeerde foutcodes, fixtures en server-/web-/Darttests. Rechten worden bij prepare, approve en execute opnieuw gecontroleerd. Er komt geen verruiming van bestaande canonieke metadatarechten. Routinepredelegatie blijft uit totdat grenzen expliciet gekozen zijn.

Credentialuitgifte, wachtwoorden en providergeheimen lopen via vertrouwde menselijke invoer. De agent ziet alleen een ontvangstbewijs en operationstatus, geen nieuw geheim. Een ontbrekende secretinvoer blijft een benoemde wachtstatus. Het bestaande rechtencontract krijgt de benodigde grants-read en revisie om incrementele wijzigingen veilig voor te bereiden.

Nieuwe voorwaartse migraties bewaren operations, approvals, credentialbinding en revisiebewijs. Migratie-/upgrade-/rollbackproeven gebruiken uitsluitend geïsoleerde data. Er is geen persoons- of kijkstatusmigratie en geen OAuth-/hosted koppeling in dit venster. De overige G2–G5-scope en vier afzonderlijke clientproeven uit het oorspronkelijke plan blijven bestaan.

## Sluitbewijs

Oude REST-bypass, approval door de agent zelf, gewijzigde resources/parameters/revisie, verlopen preview, ingetrokken rechten, dubbele uitvoering, crash tijdens uitvoering en secretredactie krijgen negatieve controles. Een gewone knop en een agent gebruiken dezelfde operation. Een afgebroken of onbesliste uitvoering wordt nooit als succes getoond. Onafhankelijke adversariële review en de bestaande contract-/clientgates blijven vereist.

Dit voorstel geeft geen toestemming voor productie, credentialregistratie, clouddata of publicatie. Eerst worden de exacte action-/routeklassen en migraties uitgewerkt binnen het akkoord op dit venster.
