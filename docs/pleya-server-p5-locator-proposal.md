# P5: de locator voor leesvoortgang

**Status:** beslisvoorstel, niet geaccepteerd.
**Datum:** 10 oktober 2026
**Auteur:** Michel Knoop
**Betreft:** poort P5 uit de masterlijst (tabel 2.3 en hoofdstuk 4), taak S6.1. Blokkeert S6 en via
S6 ook S9, S12, S14, S16, S20 en S21. In het contractvoorstel
[docs/pleya-server-contract-window-3.md](pleya-server-contract-window-3.md) wachten de pakketten E
(manifest en publicatiebestanden) en F (leesvoortgang) hierop. P5 is nodig maar niet genoeg:
DEC-149 punt 3 laat S6 ook aan de vrijgave van PS-15 hangen. Een geaccepteerd P5 geeft dus niets
vrij zolang PS-15 dicht staat; het legt alleen vast welke vorm er landt zodra dat gebeurt.

## Wat P5 is

De inhoud is al gekozen en staat verspreid: VRAGENLIJST 26 (afwijking van 4 september 2026), RB-12
bijgesteld, H.2 en J.6 (`0016`). Wat ontbreekt is het besluit als DEC, en de bronnen spreken elkaar
nog tegen: RB-4, de tweede alinea van RB-12, J.5 (`POST /reading-state`) en deel I S6 (validatie van
"CFI-string, spine-index, fractie") noemen nog `{cfi, spine_index, fraction}`. P5 maakt één vorm
bindend voor server, web en app, en maakt de rest achterhaald.

## Het besluit

1. **De locator is een Readium Locator.** Gedragen velden:
   - `href` (verplicht): het relatieve zip-pad van een `readingOrder`-item, zoals het manifest van
     pakket E het noemt. Het manifest staat in dezelfde map als de bestanden
     (`/ebooks/{id}/publication/`), dus manifest-`href`, locator-`href` en zip-pad zijn dezelfde
     tekst. De server normaliseert bij het schrijven: een voorloopslash eraf (sommige native
     Readium-toolkits schrijven er een), `.`-segmenten weg. Hij weigert `..` buiten de root, een
     schema, een backslash en NUL. Een fragment (`#id`) mag; het blijft staan.
   - `type` (verplicht): het mediatype van die resource.
   - `locations.totalProgression` (verplicht voor Pleya, optioneel in Readium): 0 tot en met 1.
   - `locations.progression` (verplicht): 0 tot en met 1 binnen de resource.
   - `locations.position` (optioneel): informatief, nooit gebruikt om te herstellen, omdat twee
     engines de positielijst verschillend kunnen tellen.
   - `locations.partialCfi` (optioneel): fijnere plaats voor een engine die hem kan lezen.
   - `title` (optioneel): de koptekst van de resource, voor weergave.
   - `text` hoort er niet bij. Het is bedoeld voor bladwijzers en markeringen (PS-16); de client
     haalt het weg voor hij schrijft, en het gesloten schema weigert het.
2. **Naast de locator staat de publicatiedigest**: de SHA-256 van het EPUB-bestand, dezelfde waarde
   als `Publication.file.sha256` en de sterke `ETag` uit pakket A. Geen tweede identiteit van het
   bestand.
3. **Herstellen gaat in deze volgorde.** Is de opgeslagen digest gelijk aan de huidige, dan `href`
   plus `progression`, verfijnd met `partialCfi` als de engine dat kan. Wijkt de digest af, dan
   alleen `totalProgression`, en de client meldt dat het boek is vervangen. Een locator wordt nooit
   blind op een ander bestand toegepast.
4. **De server valideert vorm, geen inhoud.** Bereiken, verplichte velden, de `href`-regels en een
   digest van 64 hex-tekens. Of `href` in de spine voorkomt controleert hij niet. De rest bewaart hij
   ongewijzigd: `locations` is het enige open object, zodat een engine-upgrade die een veld toevoegt
   geen migratie vraagt. Het geheel mag 4 KiB JSON zijn. Een ongeldige vorm geeft `400`
   `reading.locator_invalid` met `details.field`.
5. **`progress` heeft één bron.** De server leidt het af uit `locations.totalProgression`; de client
   stuurt het niet apart. `finished` is een eigen veld, want "uit" is iets anders dan 1,0.
6. **Conflicten volgen het revisieprincipe zonder lease (RB-4).** De eerste schrijving: bestaat er
   nog geen rij voor (gebruiker, publicatie), dan wordt een schrijving met `base_revision` afwezig of
   `0` toegepast zolang de digest klopt (regel 7), en de nieuwe staat krijgt `revision` 1. Een eerste
   schrijving met een andere `base_revision` dan `0` verwijst naar een staat die niet bestaat en wordt
   niet toegepast: `applied: false`, zonder `state`. Uitzondering: zet die schrijving `finished`,
   dan geldt de regel voor expliciete handelingen hieronder en wordt hij wel toegepast, met de
   locator uit de aanvraag en `revision` 1. Er is geen nieuwere positie om te beschermen, en
   "uitgelezen" weigeren omdat de client een basis noemt die nergens naar wijst helpt niemand. De
   digest moet ook dan kloppen (regel 7). Bij een bestaande rij: met `base_revision` gelijk
   aan de actuele `revision` wordt de schrijving toegepast. Wijkt hij af, dan verandert er niets en antwoordt
   de server met de actuele staat en `applied: false`. Zonder `base_revision` wint de laatste
   schrijving. Het zetten of wissen van `finished` geldt als expliciete handeling en wordt ook met een
   verouderde basis toegepast, dezelfde regel als `mark_watched` in specificatie 14.1a punt 5. Met
   een verouderde basis wordt dan **alleen** `finished` toegepast; de locator uit dezelfde aanvraag
   wordt genegeerd, zodat een oud toestel dat "uitgelezen" tikt de positie van een nieuwer toestel
   niet terugzet. `applied` is in dat geval `true` en `revision` loopt op.
7. **Een schrijving met een andere digest dan het huidige bestand wordt niet toegepast.** Het bestand
   is na het openen vervangen; de locator hoort bij bytes die er niet meer zijn. De server antwoordt
   met de actuele staat (of zonder `state` als er nog geen is) en `applied: false`, zonder foutcode. De client haalt de publicatie opnieuw
   op en valt terug op `totalProgression`. Zonder deze regel zou een toestel dat het oude bestand nog
   open heeft een correcte positie op het nieuwe bestand overschrijven. Ook `finished` wordt in dat
   geval niet toegepast: uitgelezen zijn gaat over het boek, maar de aanvraag komt van een client die
   aantoonbaar een verouderd beeld heeft.
8. **`device_name` op de staat** komt uit `last_session_id` naar `sessions.device_name`: "Verder
   lezen, laatst op iPad". Binnen leesvoortgang is dit de lezer van `last_session_id`; dezelfde
   koppeling bestaat voor kijkstatus in pakket G. Intrekken van een sessie is een `UPDATE` op
   `revoked_at` (`RevokeSession`, `internal/auth/sessions.go:107`) en geen `DELETE`, dus
   `ON DELETE SET NULL` vuurt daarbij niet. De lezer filtert daarom op `sessions.revoked_at IS NULL`:
   na intrekken blijft de naam in de database staan en verschijnt hij niet meer in het antwoord.
   `SET NULL` dekt alleen een sessie die werkelijk verwijderd wordt.

## Waarom deze keuze

Het is de vorm die de gekozen webengine zelf produceert: `@readium/navigator` (VRAGENLIJST 15) geeft
en neemt Readium Locators, dus het web schrijft en leest zonder vertaallaag. De app-reader op
`feat/ebooks` rekent al in dezelfde termen (`BookReaderPosition.totalProgression` in
`lib/books/book_reader_page.dart`) en heeft nog geen engine; een native Readium-toolkit achter de
Flutter-reader levert hetzelfde formaat. `totalProgression` verplicht maken geeft elke engine een
terugval die altijd werkt, en de digest maakt die terugval de enige toegestane uitkomst bij een
vervangen bestand.

## Afgewezen

| Alternatief | Waarom niet |
| --- | --- |
| EPUB CFI als primaire identiteit | engines schrijven CFI's verschillend en de toolkit leest hem niet overal terug; hij blijft optioneel als `partialCfi` |
| `{cfi, spine_index, fraction}` uit RB-4 en J.5 | vervangen door VRAGENLIJST 26; spine-index is afgeleid, geen identiteit |
| alleen `position` of een paginanummer | hangt aan de positietelling van één engine; een paginalabel komt uit `page-list` en bestaat niet in elk boek (golden 06) |
| een eigen Pleya-locator | geen engine produceert hem, dus elke client krijgt een vertaallaag |
| `watch_states` hergebruiken met `position_ms` | betekeniswijziging (regel 3) en lease-semantiek die een lezer niet heeft (RB-4) |

## Gevolgen

| Waar | Gevolg |
| --- | --- |
| Server | tabel `reading_states` (pakket F), validatie van de vorm in een pure functie, `progress` afgeleid. Manifest (pakket E) gebruikt dezelfde `href`-normalisatie als de validatie: één functie, twee aanroepers. |
| Pleya Web | de webreader (S12) geeft de locator van `@readium/navigator` door en filtert `text` weg. Verder lezen (S9) toont `progress` en `device_name`. |
| Flutter-app | `ReadingLocator` in `pleya_wire.dart` (H.5 punt 2), gedeeld met de reader op `feat/ebooks`. De reader kiest een engine die Readium Locators uitgeeft; een engine die alleen een paginanummer of spine-index kent voldoet niet (H.4). Vóór `POST /reading-state` moet de stille `_postJson`-fout uit backlog 24.3 dicht (H.5 punt 5). |
| Reader op `feat/ebooks` | drie concrete aanpassingen. `BookTocLocator.entryId` (`lib/books/book_toc.dart:89`) is een id van een inhoudsopgave-item; de positie in de toc volgt voortaan uit de `href` (met fragment) van de toc-items in het manifest, en `entryId` wordt daarvan afgeleid in plaats van opgeslagen. `BookReaderPosition.pageLabel` komt uit de `pageList` van het manifest (pakket E), dezelfde bron als de `page-list` die de klasse al noemt. De `href` die de app schrijft heeft geen voorloopslash; de server normaliseert hem wel, maar de app vergelijkt lokaal opgeslagen en serverposities alleen goed als ze dezelfde vorm hebben. |
| Unified Library | leesvoortgang is per server; er is geen tweede boekenbron in de Unified-laag, dus geen samenvoeging. |

## Migratie

Aan bestaande tabellen verandert niets. `watch_states` blijft ongemoeid, er is op de server geen
leesvoortgang om over te zetten, en de app op `main` bewaart geen leesvoortgang (alleen demodata op
`feat/ebooks`).

In de commit van pakket F komt `reading_states` erbij: (`user_id`, `publication_id`) als sleutel,
`locator jsonb NOT NULL`, `publication_digest` (64 hex-tekens) `NOT NULL`, `progress` als
gegenereerde kolom uit `locator->'locations'->>'totalProgression'`, `finished`, `revision`,
`updated_at` en `last_session_id` (FK `sessions`, `SET NULL`). `user_id` en `publication_id` vallen
weg met `CASCADE`. Een index op `(user_id, updated_at DESC) WHERE finished = false` bedient Verder
lezen. J.6 plant nummer `0016`; het echte nummer volgt bij het committen (contractvoorstel 8.1).
Terugdraaien is de tabel droppen, en er is geen backfill.

**Wat er met een staat gebeurt als de publicatie verdwijnt.** Een vervangen bestand houdt zijn
publicatie-id (de groeperingssleutel is ISBN of titel plus eerste auteur, H.2), dus de staat blijft
en de digest wijkt af: terugval op `totalProgression`. Een bestand dat tijdelijk ontbreekt krijgt
`missing_since` en houdt zijn rij, dus ook zijn staat. Pas wanneer de publicatie werkelijk wordt
verwijderd, of de bibliotheek, verdwijnt de staat met `CASCADE`. Wordt hetzelfde boek daarna opnieuw
toegevoegd, dan is het een nieuwe publicatie zonder staat. Dat is bewust: een staat naar een nieuwe
rij overzetten op titel zou een tweede identiteit invoeren, en de kans is klein (een boekenbibliotheek
verwijderen vraagt de bevestiging uit 17e.3).

## Wat S6 hiermee kan en niet kan

**Kan:** pakket E en F bouwen en landen; leesvoortgang tussen web en app laten reizen zonder
vertaling (O, regel 60); Verder lezen vullen; een vervangen boek herkennen en terugvallen op de
totale voortgang.

**Kan niet zonder de vrijgave van PS-15:** iets van het bovenstaande landen. P5 legt de vorm vast,
DEC-149 punt 3 houdt S6 dicht tot PS-15 vrijgegeven is.

**Kan niet, en hoort er niet in:** bladwijzers en markeringen (PS-16; `text` zit daarom niet in de
vorm), leesgeschiedenis (DEC-128 punt 6), voortgang binnen een vervangen bestand behouden op
woordniveau, en een positie op een bestand herstellen waarvan de digest afwijkt.

## Voorgestelde DEC-tekst

> ## DEC-NNN: de locator voor leesvoortgang is een Readium Locator met de publicatiedigest ernaast
>
> **Status:** voorgesteld. Sluit poort P5, het DEC-deel van taak S6.1; manifest en publicatiebestanden
> (de rest van S6.1) blijven pakket E.
>
> **Decision:** Leesvoortgang draagt een Readium Locator met verplicht `href` (genormaliseerd
> zip-intern pad uit het manifest), `type`, `locations.progression` en `locations.totalProgression`,
> en optioneel `locations.position` (informatief) en `locations.partialCfi`. Ernaast staat de SHA-256
> van het EPUB-bestand, gelijk aan `Publication.file.sha256`. Een client herstelt op `href` plus
> `progression` alleen bij gelijke digest, anders op `totalProgression` met een melding. De server
> normaliseert `href` en valideert de vorm; `locations` bewaart hij ongewijzigd en `progress` leidt
> hij af uit `totalProgression`. Een eerste schrijving past toe met `base_revision` afwezig of `0`.
> Conflicten volgen `base_revision` zonder lease, met `finished` als
> expliciete handeling die bij een verouderde basis alleen zichzelf toepast. Een schrijving met een
> andere digest dan het huidige bestand wordt niet toegepast. Dit bindt de webreader en de app-reader
> op `feat/ebooks`.
>
> **Consequences:** RB-4, de tweede alinea van RB-12, J.5 en deel I S6 (de vorm
> `{cfi, spine_index, fraction}`) zijn achterhaald. Pakket E en F uit contractvenster 3 mogen landen
> zodra ook PS-15 vrijgegeven is (DEC-149 punt 3); dit besluit geeft PS-15 niet vrij.
>
> Afgewezen: CFI als primaire identiteit, CFI plus spine-index plus fractie, alleen `position` of
> paginanummer, een eigen locator, en `watch_states` hergebruiken.
