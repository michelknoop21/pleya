# Begrensd metadata-contractvenster

Scoped venster geopend door Michel op 1 november 2026, antwoord op de concrete vraag bij dit document: “Open dit additieve metadata-venster (aanbevolen)”. Roadmap C-05/S4/S22/S14.5. De opdracht voor volledige lokale ontwikkeling blijft gelden; dit document concretiseert uitsluitend de nieuwe protocoloppervlakken die volgens de serverregels een expliciet scoped besluit nodig hebben. Geen productie-, migratie-uitrol-, sleutel-, upload- of MCP-vrijgave.

## Gewenste gebruikersuitkomst

Een beheerder zoekt vanuit een titel op naam met optioneel jaar, kiest een visuele kandidaat en ziet keuze ontvangen versus werkelijk toegepast. Velden bewerken met locks en poster/backdrop kiezen met pin blijven aparte acties. Gewone knoppen werken zonder assistent. Bestaande R3-richting en bronvoorrang blijven gelden, zonder nieuwe mockupronde of revisiewerkbank.

## Bestaand contract blijft geldig

`Item.external_ids` en query `external_id` behouden hun huidige betekenis, ook voor oude clients. De nieuwe release krijgt additief bewijs van de daadwerkelijk toegepaste identiteit. Oude servers/clients blijven hun bestaande pad gebruiken. Bij de nieuwe capability mag een nieuwe client nooit intentie of oude cache als toegepast bewijs gebruiken. Geen semantiekuitzondering op protocolregel 3 nodig.

| Toevoeging | Begrensde vorm |
|---|---|
| `Item.applied_external_ids` | Optioneel veld met dezelfde providers/typevorm als bestaande ExternalIds, eerst alleen TMDB. Afwezig/null/onbekend is geen bewijs. Alle Item-antwoorden lezen dezelfde atomair gepubliceerde toestand. |
| `capabilities.applied_external_identity` | Standaard false; true alleen wanneer applied-antwoorden en lookup samen beschikbaar zijn. Nieuwe Flutter-/Big P-consumers en opgeslagen/cache-identiteiten kiezen dan uitsluitend applied. |
| Query `applied_external_id` op `GET /libraries/{id}/items` | Zelfde TMDB-idvorm als bestaande lookup, maar uitsluitend werkelijk toegepast. Samen met legacy `external_id` is 400. Cursors binden de gekozen filterset. |
| `GET /items/{id}/metadata-match` | Requested/applied-id afzonderlijk, `application_state` pending/applied/failed/unknown en optioneel veilige foutcode. Nieuwe unknown-safe status; 202 op bestaande PUT blijft alleen ontvangst betekenen. |
| `GET /items/{id}/metadata-search` | Item bepaalt movie/show; verplichte titelquery, optioneel jaar, maximaal twintig kandidaten. ID, titel, optioneel oorspronkelijke titel/jaar/posterref. Geen confidence, auto-keuze of vaste fictieve zoekresultaten. |
| `GET /items/{id}/metadata-candidates/{external_id}` | Alleen bij een gekozen kandidaat begrensde samenvatting en beeldrefs ophalen. Geen fan-out van twintig Details-calls en geen gegarandeerde immutable preview. |
| `GET /items/{id}/metadata-candidate-artwork` | Alleen gevalideerde provider-image-ref naar de bestaande vaste TMDB-host, geen vrije URL. Bestaande byte-/timeout-/redirectgrenzen hergebruiken, gelimiteerde beeldkeuze en cache. |
| `GET /items/{id}/metadata` | Effectieve bewerkbare waarden met bron en lock, geen secrets of interne bestandsdata. |
| `PUT /items/{id}/overrides` | Gesloten gedeeltelijke typed map voor title, year, summary, genres, content_rating en people. Expliciet leeg is een handmatige keuze; titel niet leeg. Bestaande scanner/providerpaden respecteren locks. |
| `DELETE /items/{id}/overrides/{field}` | Alleen ondersteund veld ontgrendelen. Actuele onderliggende bron veilig opnieuw bepalen; bij onvoldoende bewijs niet stil de lock/waarde verliezen. Geen algemeen undo-/revisiesysteem. |
| `GET /items/{id}/artwork-candidates` | Begrensde kandidaten voor poster/backdrop met itemgebonden keuze-ID, rol, bron en optionele taal. |
| `PUT /items/{id}/artwork` | Kies een geldig itemgebonden kandidaat-ID voor poster/backdrop en pin de keuze, null ontpint. Geen binaire upload, vrije URL of wijziging van bronbestanden. |

Nieuwe routes vallen onder bestaande adminautoriteit, actuele bibliotheek-/gebruikersscope, audit en veilige bestaande bevestigingspatronen. Zoek/status/override/artwork krijgen afzonderlijke capabilitydekking waar gedeeltelijke servers anders verkeerd zouden worden aangeroepen. Geen nieuwe verplichte velden op oude requests; gesloten bestaande bodies blijven gesloten. Technische type-/omvangsgrenzen, status/foutcodefixtures en onbekende-waardenafhandeling worden met het contract uitgewerkt en vóór merge inhoudelijk gereviewd. Deze opening geeft geen vrijbrief voor andere routes of providers.

## Interne opslag en upgradegrens

Gebruik bestaande kandidaten en bronlagen. Applied-provider/id worden alleen bij succesvolle guarded publicatie vastgelegd; failure behoudt toegepast bewijs en reject trekt het in. Oude matched/manual-rijen niet zonder bewijs als coherente applied-publicatie backfillen. Laat bestaande rijen gecontroleerd opnieuw door de matcher lopen; tijdelijk kan de nieuwe client minder titels samenvoegen. Overrides en artworkkeuzes krijgen alleen aantoonbaar noodzakelijke opslag, geen vier nieuwe generieke heads/revisions/operations/previews-entiteiten.

Benodigde nieuwe lokale migratiebestanden vallen binnen deze functionaliteit en krijgen synthetisch upgrade-/backup-/restorebewijs plus onafhankelijke review. Er wordt geen nieuwe migratie op de NAS of productie uitgevoerd zonder de gebruikelijke aparte vrijgave. Bestaande data en overige soorten blijven behouden.

## Acceptatie vóór integratie

- A naar B: requested en applied lopen niet door elkaar; ontbrekende B-velden/beelden tonen geen oude A als B. Manual/NFO volgen DEC-153. Providerfout en onzekere commit verliezen geen bruikbare bestaande toestand.
- Huidige Flutter-/Big P-lookup, Unified-groepering en opgeslagen/cache-identiteiten gebruiken bij capability true uitsluitend applied. Oude server zonder capability houdt bestaande compatibiliteit; Plex/Jellyfin worden niet gewijzigd.
- Vrij zoeken, kandidaat lezen, bevestigen, pending/applied/fout, annuleren/retry, veldlock en artworkpin werken met echte synthetische serverdata, lege/fout/stale/revokegevallen en drie achtergrondrondes/herstart.
- Bestaande routes en oude contractfixtures blijven geldig. Nieuwe requests alleen na capabilitycheck; protocol-/schema-/clienttests en negatieve controles, afzonderlijke securityreview waar de projectregels dat eisen.
- UI behoudt alle bestaande acties en rechten, met visuele controle op 320/390/1440 en overige afgesproken breedtes. Mockupgoedkeuring is geen runtimebewijs.

De interne providerreplacement/manual-ID-correctie wordt eerst afgerond en gereviewd. Daarna volgen de goedgekeurde additieve wireoppervlakken binnen deze grens. Dit opent geen andere contracten en geeft geen live-uitrolvrijgave.
