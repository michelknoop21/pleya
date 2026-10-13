# Bibliotheekredesign: implementatiecontract

Roadmap: A-06 / A-08 / A-17; Web C-05. Itemstatus blijft in VIS-COL-PLAY1.

Michel geeft op 12 oktober 2026 opdracht tot inbouwen van de gekozen stijl.
Laatste ontwerpcorrecties: achtergrond volgt selectie; alle achtergrondbeelden
zijn uniform geblurd; kaartgeometrie en density blijven behouden.

## Ontwerpautoriteit

De goedgekeurde referentiebeelden zijn bewaard in [approved](assets/library-redesign/approved/). De oorspronkelijke reviewcollectie staat in
`/Users/michelknoop/.codex/visualizations/2026/10/08/01a11aa6-fe0a-72c2-b24b-4c1fb9d3f88c/collections-playlists/`.
Gekozen: `cn08-approved-reference-proposals/renders/voorstel-1-zwevend.png`.
Vervolgvensters: `selected-style-followup/`; latere correctie met voorrang:
`dynamic-density-preview/renders/{sintel,charge}-selected.png`.
Deze tabletbeelden bewijzen geen runtime- of hardwaregedrag.

## Reconstructiemap

| Ontwerpdeel | Bestaande eigenaar / gedrag | Implementatieplicht | Bewijs |
| --- | --- | --- | --- |
| Zwevende lokale navigatie | LibrariesScreen; bestaande tabs, bronkiezer en acties | Dezelfde handlers/focusnodes, geen rode lijn; telefoon heeft een eigen 48px navigatierij | Implementatie + gerichte geometrie-/focustests; native beeldreview afzonderlijk |
| Selectiegebonden sfeer | Bestaande concrete MediaItem/MediaPlaylist of representativeSource van UnifiedMediaGroup | Brongebonden artwork; TV focus, desktop hover/focus, mobiel zichtbare kaart; geen extra tap | Native catalogus Verify + Web keyboardbeeld; fixturebewijs |
| Bladeren | LibraryBrowseTab, MobileCatalogScreen, TvUnifiedCatalogScreen | Alle filters/sortering/paging/focus/sourcekeuze behouden | Open |
| Aanbevolen | LibraryRecommendedTab, MobileLandingScreen, TvDiscoveryLandingScreen | Bestaande rails/projecties en activering behouden; geen eerste-film lock | Open |
| Collecties/afspeellijsten | Bibliotheektabs en TvPersonalMediaOverviewScreens / PersonalMediaProvider | Visuele covers, titel/aantal/bron, retry/partial failure en terugkeer behouden | Open |
| Eigen cover / eerste maximaal vier leden | Bestaande backendmetadata en ledenvolgorde | Provenance/capability vaststellen; geen samenvoeging op naam of kunstmatige herhaling | S19/S22 toets open |
| Pleya Web | Bestaande libraries route en media grid; S19.3 voor ontbrekende collecties/playlists | Bestaande routes stileren; ontbrekende endpoints/routes niet fictief maken | Fase-/protocoltoets open |

Geen nieuwe globale shell, bronmodel, rechten of opslagcontract. Een visuele
wijziging verplaatst geen bronautoriteit en voegt geen mutatie toe. Mobiele
selectie verandert uitsluitend sfeer; openen blijft de bestaande enkele tap.

Code complete, tests complete, Verify/visuele vergelijking en hardwareacceptatie
worden afzonderlijk geregistreerd. Ontwerpapproval is geen releaseacceptatie.

## Uitgangsstand en begrenzing

Implementatie op `codex/library-approved-redesign`, vanaf actuele main `ceecbaed`.
MainScreen gebruikt MobileLanding/MobileCatalog alleen voor de telefoon; iPad en
andere brede bestaande routes gebruiken de TV-landings/catalogusadapters. De
vier brongebonden bibliotheektabs blijven een eigen route. Geen herintroductie
van historische tabs in de unified TV-shell tegen DEC-092.

Bestaande broncovers worden gebruikt. Als een cover ontbreekt, vraagt de native
kaart alleen de eerste vier posities via de bestaande `fetchCollectionPage` of
`fetchPlaylistPage`, met abort, metadata-versie en concrete clientbinding. Bij
Plex gaat bibliotheekcontext mee. Een aanwezige serverthumbnail gaat vóór een
automatische playlistcomposite. De compositor vult korte lijsten niet aan met
herhalingen; een dubbele positie die echt in een playlist staat blijft behouden.
Dit is deterministische presentatie van bestaande serverdata, geen nieuwe
opslag, upload of synchronisatie-API. Coverbeheer en Pleya Server/Web S19/S22
blijven open; Web heeft nog geen collectie-/playlistendpoints of routes.

Gerichte toetsen: cover 1/2/3/4, eigen cover, duplicates, late response, selectie,
leeg/vervangen resultaat, focus op verborgen route, bronlabels en partial failure.
Negatieve controles tonen oud artwork na leeg/vervangen resultaat en focusdiefstal
zonder de guards. De geneste TV-grid gebruikt de beschikbare constraintsbreedte;
de eerste integratierun reproduceerde 67px overflow met de oude schermbreedte.

Verify: `tvos.library.atmosphere` PASS op een verse aparte simulator, met drie
native beelden (kalibratiefixture; geen hardwarebewijs). De bestaande simulator
weigerde de Verify TopShelf-installatie. iOS generieke build stuitte op macOS
`lipo -verify_arch arm64 x86_64`; een alleen-ARM64 simulatorbuild slaagde. Geen
releaseconfiguratie of SDK-bron aangepast. Verdere native/visuele review wordt
in het bestaande register bijgewerkt; de screenshotmanifest en reviews staan
in `.build/reports/` buiten tracked source.

## Verificatiestand 12 oktober

Codegate inclusief unused groen (`library-codegate-delivery.log`). Gerichte
clienttests, Web check/build/tests en negatieve controles zijn groen na herstel.
De onafhankelijke whole-diff-review en gecombineerde fixreview bevatten geen
open codebevindingen. Touch-Web selecteert nu in beide assen centraal en samplet
na layout; de telefoonnavigatie heeft een eigen rij met minstens 44px touchhoogte.

Native catalogus: tvOS Verify 25 stappen en iPhone Verify 20 stappen groen,
beelden gelezen met kalibratie-artwork. De laatste tvOS-linkbuild gebruikte alleen
een commandoregelzoekpad naar de bestaande MoltenVK-simulatorarchive; de iOS-build
alleen ARM64 vanwege de lokale lipo-beperking. Alleen de geïsoleerde Verify-kopieën
werden gesigneerd/geïnstalleerd; releaseconfiguratie en dependencies bleven gelijk.
Een production-widgetbeeld dekt collectiekaarten met 1/2/3/4 leden en eigen cover,
met expliciet synthetische artwork. Dit is geen native-server/hardwareacceptatie.

Bestaande bronbibliotheek-, iPad- en aanvullende persoonlijke schermbeelden
worden als begrensd bewijs in het screenshotmanifest opgenomen. Ongeteste
platformen, echte backendcoververversing/synchronisatie, hardware en release
blijven open onder VIS-COL-PLAY1 en S19/S22; geen volledige acceptatieclaim.

## CI-correctieronde 13 oktober

PR #329 is gemerged (644cfe69). De volledige testsuite telde 11164 geslaagde
tests, twaalf golden-afwijkingen en 211 skips. Zonder bruikbare bronartwork
moet de sfeerlaag transparant blijven en houdt het catalogusvenster zijn
bestaande lift, met de shell als eigenaar wanneer aanwezig. Een gerichte
negatieve controle bevestigt de ongewenste opaque laag. De bestaande Linux-workflow 38380971041 slaagde met 27 gerichte goldentests.
Exact zeven discoveryreferenties zijn gewijzigd en onafhankelijk inhoudelijk
goedgekeurd; de vijf catalogus-/shellreferenties bleven ongewijzigd. Dit verandert
geen handlers, density, servercontract, prioriteit of hardwareacceptatie.
