# G0: actuele routebasis voor Big P en MCP

5 november 2026. Roadmap C-05/S16. Eigenaar Michel Knoop. Basis `bd106da29` plus lokale transportimplementatie. Dit is voorbereiding op het bestaande integratieplan, geen vervanging van de zes S16-regels of nieuwe contractvrijgave.

Het oorspronkelijke plan op `docs/bigp-mcp-roadmap`, commit `1d66b211fb2f62160660d5ef8880735fdcfff970`, inventariseert 109 expliciete routes. De actuele router bevat 121: 118 OpenAPI-operaties, health, ready en `/mcp`. De statische bundel en protocolterugval tellen niet als expliciete route. Alle 118 OpenAPI-operaties hebben een echte routerregistratie. Geen oorspronkelijke route ontbreekt na normaliseren van protocolprefix en parameternamen.

Er zijn twaalf toevoegingen: MCP-transport; cache GET/DELETE; veldmetadata GET; overrides PUT/DELETE; metadatazoekopdracht, kandidaat, kandidaatartwork en matchstatus GET; artworkkandidaten GET en pinselectie PUT. Het bewijsbestand `g0-route-inventory.json` onder `/Volumes/SSD/Codex/tasks/pleya-server-completion-20261105/` bewaart methode/pad, handler/bronregel, operationId, categorie, mogelijke secretinvoer/-uitvoer en de afwezigheid van duurzame operations/approval. De routerhash bindt de inventaris aan de gelezen bron. De categorieën zijn een eerste indeling, geen nieuwe autorisatiepolicy.

Het hergebruik staat vast: bestaande handlers, actuele rollen/scopes, bibliotheekrechten, jobs, audit, metadata en pins. Het lokale MCP-register is protocolafleiding. Het is nog geen gedeelde getypeerde action-/operationlaag. De SDK-proeven bewijzen transport en bestaande handlerketens; zij bewijzen niet de vier afzonderlijke clientketens van G4/G5.

G1 moet menselijke approval en idempotency ook voor bestaande REST-paden afdwingen. De huidige zelf ingevulde operationId-bevestiging is geen menselijk akkoordbewijs. Credentialuitgifte en wachtwoordinvoer mogen geen geheimen aan een agent teruggeven of door agentcontext laten lopen. De huidige directe koppeling van zulke REST-operaties wordt door dit G0-bewijs niet vrijgegeven voor productie.

Het [begrensde G1-voorstel](../pleya-server-mcp-g1-window-proposal.md) legt de benodigde operation-/revision-/approvalcontracten voor. Het eerdere akkoord op `mcp_enabled` opende uitsluitend die instelling en bijbehorende bestaande status. Routinepredelegatie, hosted koppeling en clouddata blijven apart. Metadatarechten worden door deze voorbereiding niet verruimd of versmald. G0 blijft gedeeltelijk zolang de contract- en daadwerkelijke actionpolicy-afbakening niet is gesloten.
