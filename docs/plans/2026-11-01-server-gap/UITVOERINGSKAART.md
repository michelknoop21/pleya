# Pleya Server, uitvoeringskaart

1 november 2026. Opdracht Michel: maak een prompt als Michel en begin het volledige gapplan te ontwikkelen. Ontwikkeling is vrijgegeven; push, merge, publicatie, productie-/NAS-mutaties en nieuwe protocolvensters niet automatisch.

Roadmap: C-05. Detailtaken blijven bij de bestaande S-eigenaar. Deze kaart bewaart werkverdeling en afhankelijkheden, geen vervangende productstatuslijst. De huidige primaire werkstroom is de eigen branch `feat/pleya-server-gap-integration`, vanaf `63a4d5faef23c32dfbb10cccb597d159cef32fcd`, onder deze taakmap. Bronworktree was schoon. De native worktreefunctie meldde dat cloudworktrees niet beschikbaar zijn; de geïsoleerde Git-worktree is vervolgens aangemaakt. Geen bestaande branch of gewijzigde bestanden overgenomen of overschreven.

| Pakket | Bestaande mapping | Uitvoerbare lokale grens en acceptatie | Afhankelijkheid |
|---|---|---|---|
| 1 | S25.3-S25.7, S15.3 | Herstel vooraf valideren, upgrade-/rollbackproeven op synthetische lokale data, bestaande baseline expliciet vastleggen. Corrupt herstel mag geen onderhoud starten of livegegevens wijzigen. | Eerste pakket; echte off-site bestemming/sleutel en productieproxyconfig blijven apart. |
| 2 | S4/S22/S14.5 | Gevraagde versus toegepaste match coherent maken; metadata- en artworkcorrecties behouden; bestaande lokale cachefixes niet opnieuw bouwen. | Bestaande runner-/publicatiegrens. Nieuwe zoek-/editor-/artworkroutes vereisen exact protocolvoorstel/besluit. |
| 3 | S13/S17/S18/S20/S23, S15.6 | Hervatten, spoorwissels en lange playback over credentialverloop op lokale echte stack; negatieve controles voor gevonden fouten. | Concrete nieuwe startpositievelden pas na scoped protocolbesluit. Hardwareacceptatie blijft open tot fysieke ronde. |
| 4 | S2/S4/S5/S10 | Cataloguscorrectheid, samples/extras, probleemitems en veilig cachebeheer afmaken. | Behoud itemidentiteit; dubbele/edities niet destructief samenvoegen. Watcher en editie-kijkstaat niet verzinnen. |
| 5 | S11/S15.4/S25 | Hervatbare setup en operatorherstel, bestaande backend hergebruiken. | Basis uit pakket 1; externe bestemming door Michel. |
| 6 | S10.7/S15.2-S15.3/S19/S20/S23 | Account-/rechtenisolatie, intrekking en dagelijkse clientketens; R3 rechtstreeks uitwerken zonder nieuwe mockupronde. | Bestaande rechten; leeftijdsrestricties binnen één bibliotheek zijn een productkeuze. UI mag bezette Mac niet overnemen. |
| 7 | S21, S16 | Realtime met pollingterugval; Big P/MCP uitsluitend volgens apart plan. | Hergebruik `docs/bigp-mcp-roadmap` commit `1d66b211fb2f62160660d5ef8880735fdcfff970`; geen tweede schrijver, geen nieuwe MCP-exposure zonder toestemming. |
| 8 | S15/P7/P8, afzonderlijk PS-12 | Complete relevante journeys, security-/hardwarebewijs en vervangingsacceptatie verzamelen, concrete releasekandidaat voorbereiden. | Productkeuzes/migratiebehoud, exacte contractvensters en afzonderlijk releaseakkoord. Plex blijft draaien. |

Eén implementatieschrijver tegelijk. De coördinator beheert roadmap/masterlijst, opdrachten, integratie en bewijs. Een onafhankelijke reviewer beoordeelt ieder samenhangend modulepakket; één fixronde en scoped fixreview waar nodig, geen vrijblijvende herhaalde audit. Zware controles door `pleya-heavy`; uitsluitend eigen gelabelde tijdelijke resources opruimen.

Bij aanvang waren de andere Pleya-documentatietaken idle en de CrossOver/Equinoxe-taak actief. Er is geen parallelle schrijver op deze branch. Dalf38 blijft verboden. Dit document geeft geen credentials vrij.
