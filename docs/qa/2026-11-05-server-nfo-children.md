# Lokale NFO voor seizoenen en afleveringen

5 november 2026. Roadmap C-05/S4.1. Eigenaar Michel Knoop. Branch `work/server-completion-20261105`, basis `bd106da29`. Lokale implementatie en finale gecombineerde gate PASS; geen CI-, NAS- of apparaatacceptatie.

De parser accepteert nu `season` en `episodedetails`, met dezelfde veld- en castvalidatie als films en series. De metadata-ronde leest `season.nfo` naast de geselecteerde aflevering van dat seizoen en een afleverings-NFO met precies dezelfde bestandsnaam als de video. De vaste afleveringsnaam volgt de [officiële NFO-beschrijving](https://kodi.wiki/view/NFO_files/Episodes). Er wordt geen metadata van een ander niveau overgenomen. Kinderen met beschikbare mediabestanden lopen alleen langs de bestaande lokale sidecarpublicatie, ook wanneer een provider actief is. NFO-IDs veranderen geen koppeling of kijkidentiteit; externe artworkadressen worden niet opgehaald.

Herlezen volgt het bestaande zevendaagse sidecarbeleid. De integratieproef maakt de controle expliciet ouder dan acht dagen. Een nieuwe scan zonder videowijziging hoeft NFO dus niet onmiddellijk te herlezen. Titel-/nummeridentiteit uit de scanner blijft leidend, zoals bij bestaande film-NFO; deze wijziging voegt geen editie- of handmatige matchsemantiek toe.

Bewijs onder `/Volumes/SSD/Codex/tasks/pleya-server-completion-20261105/`:

- `nfo-child-red.log`: beide nieuwe XMLsoorten worden op de oude parser geweigerd.
- `metadata-extraction-compile.log`: de oorspronkelijke grote catalogus- en runnerbestanden zijn eerst zonder gedragswijziging opgesplitst; drie pakketten compileren. Het origineel en de fragmenthashes blijven bewaard. De onafhankelijke vergelijking vond alleen de bedoelde functiewijziging in `MetadataDue`.
- `nfo-children.log`: 181 top-level tests PASS, nul FAIL/SKIP. Volledige betrokken catalogus-, metadata- en parserpakketten plus twee gerichte scannertests. Go vet PASS. De echte FFmpeg-/Postgresketen bewijst eigen kindmetadata/herkomst, geen kindkandidaten, geen overerving bij ontbrekende NFO, gewijzigde NFO zonder gewijzigde video en behoud van item-/versie-ID.

De onafhankelijke implementatiereview vond geen concrete blocker. `nfo-child-integration-negative.log` faalt op ontbrekende kindmetadata wanneer de nieuwe selectie wegvalt. `nfo-final.log` bewijst daarna de positieve scanketen, gezamenlijke MCP-/API-regressies, de SDK-journey met productie-scanhandler, een actuele lokale serverbinary en `All checks passed` voor de algemene gate. De drie optionele brede lintercontroles blijven bij CI. De volledige gezamenlijke metadata-/artworkacceptatie in S22.8 blijft afzonderlijk open.

Hercontrole 9 november 2026: de eerdere vergelijking beperkte zich tot een extractiestap. Het uiteindelijke gedrag wijzigt ook Round, one en de sidecarselectie. De onafhankelijke review vond ontbrekende negatieve controles; S4.1 staat weer gedeeltelijk. Nummercontrole, titelvoorrang en meerafleveringsbestanden blijven open productkeuzes.
