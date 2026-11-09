# Gecombineerd metadata- en artworkbehoud

5 november 2026. Roadmap: C-05 / S22.8. Eigenaar: Michel Knoop.
Bron: `bd106da29` plus de nieuwe integratietest op `work/server-completion-20261105`.

De bestaande losse proeven dekten veldoverrides, publicatiewissels en artworkpins. De nieuwe proef combineert die operaties op dezelfde titel en echte wegwerp-Postgres. Voor dit bewijs is geen metadata-productcode gewijzigd.

De proef publiceert match A, vergrendelt titel en samenvatting, pint de poster en kiest eenmaal match B. Drie providerrondes lezen de staat via nieuwe Store-instanties. Iedere ronde verwerkt ook een scannerupdate via `ResolveItem`, de bestaande schrijfgrens. De test controleert de gekozen en gepubliceerde provideridentiteit, dat de provider geen nieuwe zoekopdracht krijgt, behoud van beide locks en de volledige pin, en de zichtbare catalogusvelden. De bestaande referentiesnapshot bewaakt item-, file- en versie-identiteit en kijkstatus, geschiedenis, lijsten en downloads.

Bewijs, via SSD-startcontrole en de normale gedeelde wachtrij:

- `metadata-verified.log`: drie gerichte metadata-integratietests PASS, nul SKIP. Omvat de gecombineerde proef en de bestaande tests voor providerfout/overrides en lege vervanging na drie rondes.
- `client-artwork.log`: 85 tests PASS voor zoek-/artwork-URLs, applied refs, pinverversing en de gedeelde maatvoering. De shadercompiler geeft waarschuwingen voor de Skia-backend; de tests slagen. Dit is geen beeldacceptatie.
- `ci-checks.log`: `All checks passed`, inclusief analyzer, formattering, codegenfreshness en native format. Boombrede optionele lintercontroles zijn volgens de standaardinstelling overgeslagen.
- Onafhankelijke eerste review vond dat de test match B iedere ronde opnieuw koos. Dat kon verlies van de keuze maskeren. Hersteld naar eenmaal kiezen, daarna alleen opnieuw due maken, met expliciete identiteitsasserties. Onafhankelijke fixreview PASS, geen open bevindingen.

Een tweede proef, `TestMetadataFullScanPreservesLocksPinBytesAndWatchState`, voert de volledige bestandsscan uit met een echt FFmpeg-bestand en de bestaande scanner. Na eenmaal match B kiezen volgen drie providerrondes en drie scans. De API levert daarna dezelfde pinbytes, SHA-256 en ETag, ook na het verwijderen van de eigen pincache. File-ID, kijkstatus, geschiedenis en favorieten blijven behouden. `final-validation.log` legt deze proef vast als PASS, zonder SKIP.

Logs, tijdelijke runner en taakbuilds blijven op `/Volumes/SSD/Codex/tasks/pleya-server-completion-20261105/`, onder beheer van Michel Knoop. De taakdatabase en het eigen netwerk worden na iedere run verwijderd; geen NAS of bestaande database gebruikt. De opgehaalde gepinde Go-image en taakgebonden buildcaches blijven behouden.

Dit is lokaal ketenbewijs met een synthetische provider en geldige PNG-bytes. Een nieuwe Store is geen procesherstart. Live providers, provider-SSRF, native beeldacceptatie, NAS en fysieke apparaten zijn hiermee niet gezamenlijk bewezen. S22.8 blijft gedeeltelijk; venster 8 is niet gesloten.
