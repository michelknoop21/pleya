# Een programma via MCP koppelen

Dit is lokale transportdocumentatie. De gedeelde menselijke approval-/operationlaag uit het Big P/MCP-plan is nog niet gebouwd. Gebruik dit pakket niet als vrijgegeven agentbeheer; er is geen NAS- of productievrijgave.

Roadmap C-05/S16. Gebruik dit na acceptatie en uitrol van de MCP-kandidaat. Het document bewijst geen bestaande NAS-uitrol van deze functionaliteit.

Open Beheer, Beveiliging, Agents en API-tokens. MCP staat na een upgrade standaard uit zolang de instelling nooit is opgeslagen. Kies MCP inschakelen. Het paneel leest daarna het actuele adres, het aantal tools en de toollijst van de server.

Maak een afzonderlijk API-token aan voor het programma. Kies uitsluitend alleen lezen. Deze lokale proef biedt geen beheertools of credentialuitgifte. Een beheertoken is geen vervanging voor de ontbrekende menselijke goedkeuringslaag. Het geheim is slechts eenmaal zichtbaar. Kopieer vervolgens de MCP-configuratie en vervang de placeholder `<API_TOKEN>` in de configuratie van het programma. De kopieerknop leest of kopieert geen bestaande sessiecredential.

Een configuratie heeft deze vorm, met het eigen serveradres:

```json
{
  "mcpServers": {
    "pleya": {
      "type": "http",
      "url": "http://127.0.0.1:8832/mcp",
      "headers": {"Authorization": "Bearer <API_TOKEN>"}
    }
  }
}
```

Laat het programma eerst initialiseren en de tools opvragen. Begin met `listLibraries`: de lijst moet dezelfde bibliotheken tonen als het account achter het token. Een leestoken ziet alleen het beperkte leesregister en mag geen instelling wijzigen. Bij HTTP 429 wacht het programma volgens `Retry-After` voordat het opnieuw aanvraagt. Beheer- en credentialtools zijn uitgesloten, ook als een agent zelf een bevestiging invult. De bestaande REST-API heeft nog geen G1-goedkeuringslaag; geef de agent geen beheertoken voor een alternatieve REST-aanroep.

Een ingetrokken token werkt ook niet meer voor volgende MCP-aanvragen. MCP uitschakelen sluit het transport voor nieuwe aanvragen; de gewone API blijft beschikbaar. Er is geen migratie nodig. Een oudere server kent de nieuwe instelling niet en biedt deze bediening niet aan.

Transport, argumenten en antwoordgrenzen staan in [het MCP-protocolhoofdstuk](pleya-protocol-mcp.md). Bewaar server- en clientacceptatie los van de lokale ontwikkelproeven.
