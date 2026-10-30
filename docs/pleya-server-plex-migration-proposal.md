# S15.9 — afbakening Plex-migratie vóór de vervangingsgate

Status: voorstel, 30 oktober 2026. Roadmap C-05; S15.9 / PS-12. Michel koos eerst afbakenen (DEC-168). Geen import, productiegebruik, protocolwijziging of PS-12-vrijgave.

## Wat over moet komen

De bestaande architectuur [hoofdstuk 19 en PS-12](pleya-server-architecture.md#19-migratie-vanaf-plex) en de [replacementmatrix, migratie](PLEYA-SERVER-REPLACEMENT-MATRIX.md) blijven leidend. Per expliciet gekoppelde gebruiker: bekekenstatus, hervatpositie, favorieten en verzamelingen waar een equivalent bestaat. Afspeellijsten met volgorde blijven een matrixblocker; dit voorstel verklaart ze niet optioneel. Canonieke huidige kijkstatus en een volledige reeks historische kijkgebeurtenissen zijn verschillende gegevens: een actuele Plex-positie levert geen bewijs van jaren gebeurtenisgeschiedenis. Voor dat laatste moet eerst de beschikbare bron en exportdekking worden vastgesteld. Er wordt geen geschiedenis verzonnen uit alleen `viewCount` of een laatst-gezien-datum.

Geen wachtwoorden, Plex-accounttokens of interne Plex-identiteiten overnemen als Pleya-sleutel. Plex blijft draaien. Geen doorlopende sync en geen Jellyfin-migratie binnen PS-12. Bestaande Plex/Jellyfin/local/Share-koppelingen blijven functioneren.

## Identiteit en gebruiker

1. Maak een expliciete, door de eigenaar beoordeelde koppeltabel van bronserver plus brongebruiker naar een bestaand Pleya-account. Gebruikersnaam of huishoudelijk eigenaarstoken is geen bewijs van dezelfde persoon. Beperkte gebruikers krijgen uitsluitend hun toegestane bibliotheken; geen standaardkoppeling aan de eigenaar.
2. Hergebruik de bestaande driestapsregel: gedeelde GUID, gedeelde externe identiteit, daarna genormaliseerde titel/jaar én soort. Meer dan één kandidaat blijft ambigu; een zwakkere stap lost een conflict in een sterkere stap niet op. Afleveringen vereisen de juiste serie en seizoen-/afleveringidentiteit. Remakes, meerdere bronbibliotheken, herbouwde Plex-sleutels en ontbrekende externe IDs krijgen expliciete fixtures.
3. Titel/jaar-kandidaten zijn geen zekere identiteit: voor een schrijfronde moeten die afzonderlijk worden bevestigd. Toon nul, één of meerdere kandidaten en de herkomst van de match. Geen titelheuristiek als bewezen unified deduplicatie presenteren.
4. Gebruik na bevestiging uitsluitend Pleya-item-UUID's voor de bestemming. `ratingKey` mag hoogstens een bronannotatie in het begrensde migratiejournaal zijn; nooit primaire of vreemde sleutel in producttabellen.

## Gereedschap en conflictregels

Een afzonderlijk, eenmalig migratiecommando hergebruikt de bestaande catalogus-, rechten- en kijkstate-eigenaren. Geen tweede clientprovider, parallelle geschiedenisopslag of nieuwe openbare route zonder een apart protocolvoorstel. Broninloggegevens blijven tijdelijk in geheugen of een expliciet aangewezen privé-invoer; geen token in URL, rapport, shellargument of log.

Elke uitvoering begint verplicht met een droogloop: bronsnapshot/digest, bron- en doelschema/binary, expliciete gebruikerskoppelingen, aantallen per soort en per gebruiker, zekere matches, handmatig te bevestigen kandidaten, ambigu/niet gevonden, geweigerde rechten, ongeldige tijden, conflicten en niet ondersteunde inhoud. Rapporten hebben dezelfde privacygrens als de bron; synthetische fixtures voor ontwikkeling. Geen productie-export tijdens deze afbakening.

Voorstel voor schrijven: behoud bestaande, nieuwere Pleya-status. Vergelijk werkelijke bronwijzigingstijd met doelrevisie; bij ontbrekende/onvergelijkbare tijd of een gewijzigde doelrevisie sinds de droogloop: overslaan en expliciet conflict rapporteren. Niet simpelweg de hoogste positie of de laatste importtijd laten winnen. Geen passieve import die actieve playback overneemt, `play_count` verdubbelt of een markering als nieuwe kijksessie telt. Favorieten en collectie-/playlistlidmaatschap worden alleen volgens de goedgekeurde vervangings-/mergekeuze gewijzigd, niet stilzwijgend gewist.

De schrijfronde bindt aan exact het beoordeelde rapport en de bestemmingsrevisies. Elke eenheid heeft een idempotentiesleutel op importdigest/gebruiker/Pleya-item/handeling; tweede identieke uitvoering verandert niets. Een onderbreking kan gecontroleerd hervatten; gewijzigde bron of mapping vereist een nieuwe droogloop. Gebruik transacties per beoordeelde eenheid en een journaal met aantallen en conflicten. Herstelbaarheid moet vooraf bewezen zijn: verse versleutelde back-up inclusief `/config`, herstelproef op een afzonderlijke testdatabase, en een controle dat terugzetten geen nieuwe kijkacties buiten de import vernietigt. Een volledige terugzetactie blijft een afzonderlijk bevestigd onderhoudsmoment.

## Volgorde en vrijgave

De masterlijst noemt PS-12.0 na S15, terwijl S15.9 een besluit vóór S15.5 vereist. Voorgestelde oplossing, nog te besluiten: vrijgeven van de noodzakelijke PS-12-uitvoering en testacceptatie vóór S15.5, nadat de benodigde serverfuncties en herstelpoorten beschikbaar zijn; Plex blijft aan. Geen S15.5-PASS met een nog onbesliste geschiedeniskeuze. Collectie-/playlistblockers houden hun eigen S19-afhankelijkheid en verdwijnen niet door eerst kijkstatus te bouwen.

Na akkoord: opgenomen en geanonimiseerde antwoordfixtures → pure match-/conflicttests → geïsoleerde testimport met twee gebruikers → onafhankelijke adversariële review → herhaalde import/onderbreking/herstelproef → beoordeeld rapport van de echte bron → afzonderlijke toestemming voor werkelijk schrijven. Nieuwe contractvelden of routes krijgen eerst hun eigen compatibiliteitstoets/venster. Een ontwikkelvrijgave is geen productieautorisatie.

Benodigde besluiten vóór uitvoering: (1) PS-12-volgorde expliciet vóór S15.5 vrijgeven, (2) bevestigen welke bron volledige historische gebeurtenissen beschikbaar stelt en of actuele status plus die gebeurtenissen vereist zijn, (3) expliciete merge-/vervangingskeuze voor bestaande doelgegevens. Het voorstel vraagt geen credentials of exportbestanden in de chat.

## Acceptatie

Twee gebruikers met dezelfde titel lekken geen status. Ambigue titel, serie/remakeconflict, gewijzigde rechten, ontbrekende datum, toekomst-/ongeldige positie en veranderde doelrevisie schrijven niets. Een nieuwe Pleya-kijkactie blijft behouden. De droogloop schrijft geen productgegevens. Herhalen is idempotent, afbreken hervat zonder duplicatie, collecties/afspeellijsten behouden de bevestigde inhoud en volgorde. Rapport, herstelde back-up en steekproeven per gekoppelde gebruiker horen bij de gate; een geslaagde fixture is geen bewijs van een echte migratie.
