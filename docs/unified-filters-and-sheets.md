# Unified filters en actie-, beheer- en keuzevensters

Roadmap: REG-01, A-06, A-08, A-13. Bronkeuze/rechten sluiten aan op A-07/A-02; platformvarianten op hun bestaande A-pakketten.

## Opdracht en grens

Michel, 10 oktober 2026: neem de filtermethode en rustige vensteropmaak uit de aangeleverde Plex-screenshots als visuele referentie voor Pleya. Maak eerst Pleya-mockups en gerenderde screenshots als Northstar, vraag expliciet ontwerpaccoord en implementeer daarna pas. Dit is geen goedgekeurde mockupset en geen opdracht om Plex-functionaliteit zonder meer over te nemen.

De functionaliteit werkt vanaf het begin vanuit de unified library voor de beschikbare koppelingen **Emby, Jellyfin, Plex en PleyaShare**, afzonderlijk en in gemengde bibliotheken, met voorbereiding op **Pleya Server**. Het projectbrede uitgangspunt staat in [ROADMAP.md](ROADMAP.md#unified-first). Bestaande lokale/offline-routes blijven intact. Uniforme bediening betekent niet dat iedere bron alle serverfuncties aanbiedt of dat iedere gebruiker beheerrechten heeft.

**Verduidelijking Michel, 10 oktober 2026:** Pleya Server is nog in ontwikkeling. Bouw filters, acties en vensters op de bestaande gedeelde modellen, capabilitycontroles en adapters, zodat serverfuncties later via die aansluiting toegevoegd kunnen worden zonder apart UI-pad of herbouw van de filterlogica. Behoud en toets al beschikbare Pleya Server-functionaliteit. Noteer per ontbrekende functie het bestaande aansluitpunt, benodigde contractbesluit en bijbehorende servertaak. Nog te bouwen servermogelijkheden zijn geen nieuwe blokkade voor oplevering op de beschikbare koppelingen; daadwerkelijk gebruikte serverfuncties houden hun bestaande acceptatie-/releasegates. Geen fictieve endpoints, vooruitgebouwde serverfeatures of extra framework. 'Voorbereid' is geen claim van werkende integratie.

De nieuwe scope vervangt de primaire stroom A-21 niet, verandert geen prioriteit of protocolpoort en start geen parallelle implementatiestroom buiten de bestaande WIP-limiet. Detailstatus en bewijs blijven in de bestaande [iOS-werklijst](ios-unified-implementation-register.md), overige platformregisters en, voor serverwerk, de [servermasterlijst](PLEYA-SERVER-MASTERLIST.md). Deze brief is geen tweede takenregister.

## Eerst inventariseren, dan tekenen

Inventariseer de bestaande unified routes, filterstaat, modellen, service-/adaptereigenaren, acties en rechten. Maak een compacte matrix per filter/actie en per genoemde koppeling: ondersteund met bewijs, niet ondersteund, onbekend, nog te onderzoeken of nog niet beschikbaar/gepland. Controleer Emby afzonderlijk, ook waar het code met Jellyfin deelt. Beoordeel PleyaShare via zijn daadwerkelijke verbindings- en deelcontract, niet als een verzonnen Plex/Jellyfin-backend. Scheid bij Pleya Server de bestaande ondersteuning van geplande aansluitingen; contracten die nog niet zijn besloten blijven expliciet open.

Vertaal een bibliotheek-ingang naar de bestaande unified catalogus met een bronfilter. Bouw geen tweede browser per leverancier. Houd bestaande persoonlijke filtervoorkeuren, tijdelijke bronfilters, navigatiecontext en terugkeer naar dezelfde selectie uit elkaar. Leg ontbrekende backendmogelijkheden vast bij het bestaande werkpakket; een mockup is geen toestemming om een server-/protocolpoort over te slaan.

## Functionele eisen voor het ontwerp

- **Filters over de geselecteerde, toegankelijke bronnen.** Combineer filters volgens een expliciet contract voor AND/OR, selectie en reset. Filter niet uitsluitend het eerste ingeladen scherm. Paginering, sortering, deduplicatie en eventuele aantallen moeten dezelfde scope gebruiken. Claim geen exacte telling als brondekking of paging onvolledig is. Ontbrekende metadata of een offline/ongeschikte bron is niet hetzelfde als nul resultaten; toon de beperking en bied alleen eerlijke keuzes.
- **Titel versus bronkopie.** Een samengevoegde titel behoudt zijn onderliggende server-/itemidentiteiten. Technische filters zoals 4K, Dolby Vision, HDR10+ en Atmos moeten op een daadwerkelijk beschikbare passende versie te herleiden zijn: combineer niet het beeldkenmerk van kopie A en het audiokenmerk van kopie B tot een fictieve match. Bewaar die context naar detail, bestandsinfo en bron-/afspeelkeuze.
- **Persoonlijke en brongebonden acties.** Leg per actie vast of deze geldt voor Pleya/profiel, persoonlijke brondata of een specifieke serverkopie. Neem bestaande afspraken over kijkstatus, historie, ratings, kijklijst, playlists en synchronisatie over; introduceer geen onbesloten cross-server-sync. Maak bij meerdere mogelijke doelen de relevante bron expliciet. Een gekozen afbeelding of representatieve catalogusbron bepaalt nooit stilzwijgend het doel van een beheeractie.
- **Capabilities en rechten.** Toon alleen toegestane acties volgens het bestaande beleid. Bied bij ontbrekende functionaliteit een begrijpelijke beperking waar nodig, zonder werkende functies van andere bronnen te verbergen. Behoud controle in UI én servicelaag, inclusief profielwissel, geleende/gedeelde verbinding en gewijzigde rechten. Metadata, artwork, match, verwijderen en serveronderhoud blijven gescheiden van gewone gebruikersacties. Een nieuw venster verleent geen extra rechten en impliceert geen nieuw Pleya Server-schrijfcontract.
- **Veilige terugkeer en verversen.** Annuleren, terug, toepassen en fouten behouden een bruikbare bron-/filtercontext. Werk na succes de betrokken unified weergave bij. Een gedeeltelijk geslaagde actie wordt geen algemene succesmelding en mag nooit de verkeerde kopie aanpassen.

## Northstar-set door Opus

Gebruik de screenshots voor sheet-hiërarchie, afgeronde oppervlakken, lijstregels, witruimte, titel/subtitel, terug/sluiten, onderliggende paginacontext, selectievinkjes en een duidelijke bevestiging. Houd Pleya-branding en consistente vertalingen. Neem de gemengde Nederlands/Engelse labels, dubbele acties of backendbeperkingen uit de referentie niet klakkeloos over.

Ontwerp ten minste:

1. Filter-hoofdvenster, lange/gescrolde lijst, filterwaardekeuze, actieve filters en wissen/toepassen.
2. Itemacties en lijstkeuze, inclusief toevoegen aan een lijst en resultaatmelding.
3. Beheer-/instellingenvenster voor een item met een vervolgvenster en expliciete bronkeuze waar nodig.
4. Artworkselectie: poster, achtergrond en titelafbeelding, met duidelijk doel en bereik van de wijziging.
5. Match/selectie, inclusief huidige match, ontbrekende afbeeldingen en lege/foutresultaten.
6. Afspeelgeschiedenis, inclusief leeg, laden, fout en beperkte brondekking.
7. Bestandsinfo en streamdetails van de daadwerkelijk geselecteerde bronkopie.

Voeg de relevante toestanden voor één bron, meerdere bronnen, dezelfde titel op meerdere servers, een gewone gebruiker, eigenaar/beheerder, geleende/gedeelde verbinding en een onbereikbare of niet-ondersteunende bron toe. Een cel mag alleen niet van toepassing zijn met reden; maak geen kunstmatige volledige combinatie van alle schermen en alle toestanden. Label toekomstige Pleya Server-toestanden als gepland; teken ze binnen dezelfde unified vensters, zonder daarmee API-beschikbaarheid of implementatieacceptatie te suggereren.

De aangeleverde vormreferentie is iPhone. Gebruik de bestaande platformpresentaties en contracten voor iPad, desktop, Android en TV waar gedeeld gedrag geraakt wordt. Geen gekopieerde mobiele sheet op TV; behoud D-pad/focus/terug. Een iPhone-mockup keurt geen andere platformvormgeving goed.

Lever een klein manifest met per mockup: scherm/toestand, platform/maat, referentiebestand, welke visuele eigenschappen bindend worden, unified bron-/rechtenscenario en open afwijkingen. Pas na expliciet akkoord van Michel zijn de Pleya-mockups de implementatie-Northstar. Grafische uitvoering en onafhankelijke visuele review volgen de bestaande Opus-regel.

## Referentiebeelden uit de opdracht

De onderstaande bestanden zijn door Michel in deze chat aangeleverd. Dit manifest identificeert de referenties, niet reeds gegenereerde Pleya-mockups. De originele bestanden zijn nog niet in deze repository opgenomen; maak ze toegankelijk voor de ontwerpsessie voordat de Northstar-set wordt gemaakt. Vervang ontbrekende screenshots niet door verzonnen referenties. Publiceer geen privégegevens uit de screenshots in mockups.

| Bestand | Referentie |
| --- | --- |
| `IMG_8843.png` | Itemactiemenu met lange lijst en iconen |
| `IMG_8844.png` | Lijstkeuze met terug, selectievakje en Klaar |
| `IMG_8845.jpeg` | Resultaatmelding na toevoegen aan kijklijst |
| `IMG_8847.png` | Itembeheer als groter venster met vervolgstappen |
| `IMG_8850.jpeg` | Artworkkeuze voor poster, achtergrond en titelafbeelding |
| `IMG_8851.png` | Matchresultaten en huidige selectie |
| `IMG_8852.png` | Lege afspeelgeschiedenis en verversen |
| `IMG_8853.png` | Bestandsinfo, bron en streamdetails |
| `IMG_8855.png` | Filter-hoofdvenster en snelle filters |
| `IMG_8856.png` | Vervolg van de lange filterlijst |

## Implementatie- en acceptatiepoort

Inventaris/gedrag en matrix → Opus-mockups met screenshots → expliciet ontwerpaccoord → implementatie in bestaande gedeelde eigenaren/adapters → gerichte tests, onafhankelijke code-/visuele review, Pleya Verify en toepasselijk echte-server-/hardwarebewijs.

Toets de beschikbare functies van elke genoemde koppeling zelfstandig en minimaal een relevante gemengde bibliotheek; dek ongelijke capabilities/rechten, een titel met meerdere bronkopieën, technisch gecombineerde filters, profielwissel en gedeeltelijke uitval af. Voor Pleya Server worden al werkende paden op regressies getoetst. Voor ontbrekende serverfuncties volstaan nu een beoordeeld bestaand aansluitpunt, vastgelegde afhankelijkheid/open contractvraag en tests op de eerlijke niet-ondersteunde toestand. Contracttests voor latere integratie volgen alleen een daadwerkelijk vastgesteld contract; echte-serveracceptatie van die functies volgt zodra ze binnen hun fase beschikbaar zijn. Ontbrekend bewijs blijft gepland/onbekend, nooit geslaagd. Dit blokkeert geen oplevering die deze toekomstige functies niet claimt of nodig heeft.

Een fixture of groene CI bewijst geen fysieke acceptatie. Scheid goedgekeurd ontwerp, gebouwd, gemerged, getest, visueel geverifieerd en gepubliceerd. Bestaande release-/server-/protocolgates blijven gelden. Geen nieuwe generieke filterengine, stateframework of appherbouw zonder aangetoonde noodzaak en afzonderlijk besluit.
