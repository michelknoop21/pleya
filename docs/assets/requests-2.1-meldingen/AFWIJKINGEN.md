# Afwijkingen: app nu tegenover de goedgekeurde set

Roadmap: A-20/A-21. Peildatum 9 november 2026, code op `main` `6a23216`.

## Waar dit op gebaseerd is

| Bron | Wat het dekt |
|---|---|
| Screenshot van Michel, iPhone, 9 november ([bewijs](bewijs/2026-11-09-alle-aanvragen.png)) | Alleen de lijst Alle aanvragen |
| Code-analyse op `main` | Alle andere schermen en sheets |

Ik heb in deze omgeving geen iOS-build gedraaid. Bij de schermen achter de lijst is dus niet bevestigd hoe ze op een toestel ogen. Een simulatorronde met Pleya Verify hoort daarom bij de fixstap.

De goedgekeurde staten staan in [Requests 2.0](../requests-2.0/README.md). Codes als 7B verwijzen naar die set.

## 1. Aanvragenlijst (7A tot en met 7K): grootste afwijking

| # | Goedgekeurd | App nu | Oorzaak in de code | Voorstel |
|---|---|---|---|---|
| 1 | Telefoonkop "Aanvragen" met een contextregel eronder (profiel, rol, server, aantal) | Kop "Alle aanvragen" of "Mijn aanvragen". De contextregel ontbreekt, dus de kop zegt hetzelfde als de segmentknop eronder | `lib/screens/seerr/seerr_requests_screen.dart:691` | Op de telefoon "Aanvragen" plus de contextregel, zoals 7A en 7B |
| 2 | Bereikkeuze als pil-segment: wit gevuld voor de keuze, geen omlijning | `SegmentedTabGroup` met een omlijnde container en een rood streepje onder de keuze | `lib/screens/seerr/seerr_requests_screen_body.dart:21` | Het pil-segment uit 7B (`.seg` in `requests-2.0/src/rq.css`) |
| 3 | Statusfilters als losse chips, de gekozen chip rood omlijnd. Telefoon toont drie chips en een uitklapknop | Dezelfde omlijnde segmentgroep als het bereik, met grote vlakken. "Beschikbaar" en "Afgewezen" vallen buiten beeld zonder vervaging | `seerr_requests_screen_body.dart:55` (`_filterRow`, `TabChipStyle.segmented`) | De chiprij van 7B met de vervaagde rand |
| 4 | Alle rijen in één kaart, gescheiden door een haarlijn. Compacte rij: titel, één regel met soort, seizoen, aanvrager en datum, rechts de status | Elke aanvraag is een eigen kaart met 6 px marge. Soort/jaar, seizoenen en "Aangevraagd door" staan elk op een eigen regel | `lib/widgets/seerr_request_row.dart:131-174` (losse regels), `:183` (kaart) en `:204` (marge) | Eén `lrows`-kaart met één metaregel, zoals 7B |
| 5 | Status als capsule met een gekleurde stip (amber, groen, rood) | Kleine getinte rechthoek (`_lifecycleChip`: tekst 10 px, radius 4), met daarnaast een tweede, gevulde groene badge met schaduw en icoon, bedoeld voor op posters | `seerr_request_row.dart:284-300` en `:154`; `lib/widgets/seerr_status_badge.dart:43-54` | Eén capsule per rij. "Deels beschikbaar" vervangt "Afgerond" in plaats van ernaast te staan |
| 6 | Op de telefoon geen "..." in de rij: tikken opent het menu (8A tot en met 8C). Knoppen alleen waar ze iets doen (Goedkeuren/Afwijzen, Annuleren) | Onder 640 px breedte gaan de acties onder de rij. Staat er alleen "...", dan krijgt die een eigen regel rechtsonder. Daardoor ontstaat de grote lege ruimte in de screenshot | `seerr_request_row.dart:67` (`_besideMinWidth = 640`) en `:194` | Op de telefoon "..." weglaten en het menu openen met een lange druk of via de rij. Inline alleen echte acties |
| 7 | Zoekbalk hoort bij Ontdekken (1A), niet bij de lijst | Een zoekveld "Zoek een film of serie om aan te vragen" boven de lijst | `lib/screens/seerr/seerr_requests_list_parts.dart:12` (`SeerrRequestsDiscoverBar`) | Verplaatsen naar de lege staat (7G: Ontdekken en Zoeken), of houden als kleine knop in de kop. Productkeuze voor Michel |

## 2. Detail film/serie (3A tot en met 3H)

- De status staat nu als gevulde badge met schaduw onder de titel (`lib/screens/seerr/seerr_media_detail_parts.dart:138`). De set gebruikt een capsule met stip en een uitlegregel ("Door jou aangevraagd op 6 oktober").
- Afwijking: dezelfde badge-familie als in punt 5 hierboven.
- Wat niet gecontroleerd is zonder een toestel:
  - de verdeling over de knoppenrij
  - de hero-hoogte

## 3. Aanvraagformulier en doel (4, 5, 6)

- `lib/widgets/seerr_request_sheet.dart` heeft dezelfde onderdelen als de set: 4K-schakelaar, limiet, seizoenen per stuk, en server/profiel/map voor beheerders.
- In de code zijn geen structurele afwijkingen gevonden. Visuele afwijkingen, zoals de chipstijl in de sheet, zijn niet vastgesteld zonder een toestel.

## 4. Beheer (8A tot en met 8L)

- `lib/widgets/seerr_request_actions_sheet.dart` toont een posterkop en per recht een actie. Dat komt overeen met 8A tot en met 8C.
- De afwijking zit in de ingang:
  - de telefoon opent het menu via de losse "..." uit punt 6
  - de set opent het via de rij zelf

## 5. Waarom je meldingen en notificaties niet ziet

Niets ervan staat op `main`.

| Onderdeel | Waar het staat | Status |
|---|---|---|
| Meldingen afhandelen (lijst, gesprek, reageren, oplossen, heropenen) | `feat/seerr-issues-ios`, PR #654 | Open, niet gemerged. Alleen iPhone, alleen als Seerr is ingesteld, je account `canViewIssues` heeft en de server `/issue` kent |
| Notificatiecentrum, voorkeuren, APNs-push via Pleya Server | WIP-commit `5c5c284` op `feat/pleya-request-style-20261107` | Geen PR, ongesplitst, ongereviewd. Migratie `0035_push.sql` botst met `0035_metadata_round_cursor.sql` op main. DEC-XXX heeft nog geen nummer |
| Probleem melden (`POST /issue`) | Nergens | Nieuw in deze set (familie 10). Wacht op een besluit van Michel |
| Push voor Seerr-gebeurtenissen (A-21-PUSH-2; dit ID staat alleen in de masterlist op `5c5c284`, niet op main) | Nergens | Open. Vraagt een geverifieerde koppeling tussen de Pleya- en de Seerr-gebruiker |

Wat nodig is om het in de app te krijgen, in deze volgorde:
1. PR #654 restylen naar familie 9 van deze set. Dan pas reviewen en mergen.
2. De WIP-commit splitsen in vier PR's: request-style, push-server, notificatiescherm en Filmbeeld. Daarbij de migratie hernummeren, de DEC een nummer geven en de masterlist en het protocol meenemen.
3. Na een besluit over Probleem melden: `POST /issue` in `SeerrClient`, plus de ingangen op de titelpagina en in de speler.
4. Notificaties en meldingen ook op iPad, Mac en TV, zoals families 9, 11 en 12 laten zien.
