# MCP-laag: lokaal implementatie- en acceptatiebewijs

Hercontrole 9 november 2026: het onderstaande beschrijft historisch bewijs op de oude basis. De onafhankelijke review trok de veiligheidsacceptatie in. De herstelbranch op huidige main biedt uitsluitend 49 gecontroleerde leesroutes uit 121 expliciet geclassificeerde operaties; mutaties, credentials en binaire downloads zijn geblokkeerd. OperationId-bevestiging geeft geen toestemming. Actueel gedrag en de open G1-grens staan in [het protocol](../pleya-protocol-mcp.md).

5 november 2026. Roadmap C-05/S16. Eigenaar Michel Knoop. Branch `work/server-completion-20261105`, basis `bd106da29`. Nog geen commit, CI, NAS of releaseacceptatie. Het beperkte instellingenvenster is lokaal gesloten; de volledige S16-acceptatie blijft open.

De G1-eis uit het afzonderlijke Big P/MCP-plan (branch `docs/bigp-mcp-roadmap`, commit `1d66b211fb2f62160660d5ef8880735fdcfff970`) blijft open: gedeelde operations, menselijke approval en secretvrije agentuitkomsten, ook op oude REST-paden. De operationId-bevestiging in dit transport is geen menselijk akkoord. De huidige SDK-journey bewijst bestaande handlers, geen G1-closure. Het [G1-contractvoorstel](../pleya-server-mcp-g1-window-proposal.md) is nog niet geaccordeerd.

De server gebruikt Streamable HTTP op `/mcp`, standaard uit via `mcp_enabled`. Alle 118 OpenAPI-operaties zijn gegenereerde tools die dezelfde API-handlers, rechten en bodygrenzen aanroepen. Destructieve mutaties vragen een expliciete operationId-bevestiging. Audit bewaart de oorspronkelijke aanvrager. Web biedt aan/uit, het echte toolregister en configuratie met een placeholdertoken. De native capabilityparser leest `mcp` en houdt oude servers op false.

Bewijs staat onder `/Volumes/SSD/Codex/tasks/pleya-server-completion-20261105/`:

- `final-validation.log`: Go vet, settings, MCP-transport, API-autorisatie, audit, bodygrenzen, trusted proxy en echte SDK-client PASS. De SDK-journey gebruikt de productie-scanhandler met FFmpeg en wegwerp-Postgres: bibliotheken, scan, gebruiker/rechten, leestoken en instellingen, inclusief mutatieaudit. Contractfixtures en generatorcheck voor 118 operaties PASS; drie generatorselftests en drie proxytests PASS. Serverbinary lokaal gebouwd. De oorspronkelijke afsluitende clientgate faalde op de toen ontbrekende getter; dat is later hersteld.
- `client-final.log`: 184 Webtests PASS, schema/typecheck en Webbuild PASS, Svelte nul fouten/nul waarschuwingen; algemene gate `All checks passed`. De eerste native run vond alleen de verouderde fixturetelling.
- `gate-mcp-final.log`: finale algemene gate `All checks passed`. De drie brede optionele lintercontroles blijven aan CI.
- `mcp-security-final2.log`: na de extra matrixcontrole, rol-/scopeafhankelijk leesregister, directe rolverlaging, privé discovery met TTL 0 en aparte tokenlimieten PASS. Vier gecontroleerde mutanten bewijzen de filter-, metadata-, cache- en limiterasserties; daarna alle gerichte MCP/API-tests en de productie-scanjourney groen.
- `native-final.log`: na bijwerken van 154 naar 156 fixtures, 215 gerichte native tests PASS. Geen brede lokale suite gedraaid.
- `mcp-actor-negative.log`, `mcp-scheme-negative.log`, `mcp-body-negative.log`: gecontroleerde gedragsfouten zonder de betreffende fixes; positieve regressies daarna groen.
- `mcp-screenshot-manifest.md`: acht echte pw-beelden, browserbediening, 118 tools, toetsenbord en desktop-/mobiele toegankelijkheidscontrole. `browser-final.log` bevat de expliciet gestopte synthetische fixture.

Onafhankelijke code-review heeft de veiligheidsfixes en native extractie beoordeeld zonder nieuwe blocker. De finale onafhankelijke fix-, document- en beeldreview is PASS zonder open scoped bevindingen. Lokale SDK-interoperabiliteit vervangt geen acceptatie met de bedoelde externe MCP-applicatie. Daarom blijven alle S16-regels gedeeltelijk. Het instellingenvenster sluit op dit lokale bewijs; geen externe client-, NAS- of releaseclosure.

De werkmap, taakbuilds, logs en screenshots blijven bewaard onder beheer van Michel Knoop. Alleen eigen synthetische database/netwerk en tijdelijke browserstate zijn opgeruimd. Off-site herstel, boekenvoorwaarden, realtime, fysieke apparaten en de volledige vervangingsgate zijn door deze proeven niet gesloten.
