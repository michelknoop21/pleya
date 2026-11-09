# MCP-instelling: begrensd contractvenster

Michel gaf op 5 november 2026 expliciet akkoord op dit venster: alleen `mcp_enabled`, bijbehorende types en fixtures, en de bestaande MCP-status. Roadmap C-05/S16. Het MCP-transport zelf staat buiten OpenAPI.

`Settings` krijgt een optioneel antwoordveld `mcp_enabled`, met `SettingBoolean {value: boolean, source: SettingSource}`. Nieuwe servers leveren het altijd; de ingebouwde default is false. Oude servers mogen het veld missen. `SettingsPatch` krijgt de booleaanse sleutel `mcp_enabled`. Null, tekst, getallen en onbekende sleutels worden geweigerd vóór opslag. De bestaande admincontrole, tokenbereiken en mutatieaudit blijven gelden. Geen migratie nodig: de bestaande instellingenopslag bewaart JSON-waarden.

Dit is additief binnen protocolmajor 1. Er verdwijnt geen veld, geen bestaande enum verandert, en bestaand gedrag blijft gelijk zolang de default false geldt. De bestaande capability `mcp` en `ServerDetail.mcp` volgen de actuele instelling. Er komen geen nieuwe REST-operaties of foutcodes bij. Webtypes worden opnieuw gegenereerd en de settingsfixture krijgt de nieuwe waarde. Native clients gebruiken voor MCP de bestaande capabilityparser; zij hebben geen beheerinstellingenmodel.

Het venster is op 5 november 2026 lokaal gesloten, zie [bewijs](qa/2026-11-05-server-mcp.md). De sluitcriteria zijn schema-/fixturevalidatie, generatorcontrole, gerichte backend- en Webtests, ingelogde lokale MCP-acceptatie en onafhankelijke review. Een groene deeltest sluit het venster niet. NAS, hardware, migratiekeuzes en releasepublicatie krijgen door dit besluit geen vrijgave.
