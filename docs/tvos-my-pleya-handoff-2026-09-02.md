# Handoff: Mijn Pleya op tvOS, stand op 2 september 2026


> **Afgerond sessiedocument.** Het werk hierin is klaar en de bevindingen zijn
> overgenomen in [tvos-redesign-register.md](tvos-redesign-register.md) en
> [tvos-fysieke-correctieronde.md](tvos-fysieke-correctieronde.md). Dit bestand blijft
> staan voor het bewijs en de redenering; zoek de actuele stand niet hier maar in
> [DESIGN-INDEX.md](DESIGN-INDEX.md).

Wat af is, wat bewezen is, en waar de volgende sessie begint. De audit zelf en
het bewijs erachter staan in `docs/tvos-my-pleya-audit-2026-09-02.md`.

## Stand

Branch `claude/netflix-redesign-b4x21v`, bovenop merge-baseline `450007f` en
UX-commit `1479835`. Werkboom bevat de wijzigingen van deze ronde plus het al
bestaande, niet-getrackte `docs/sessions/2026-09-02.md`, dat buiten scope blijft
en niet gestaged wordt.

Fysieke acceptance op een echte Apple TV: niet gedraaid. Geen TestFlight, geen
buildnummer, geen release-record, geen merge naar main.

## Wat Pleya Verify nu kan, en wat er is bijgebouwd

| Capability | Stand |
|---|---|
| app bouwen, starten, fixture, sign-in | bestond |
| UP, DOWN, LEFT, RIGHT, SELECT | bestond |
| MENU/BACK | bestond in de driver, is nu ook in scenario's bewezen |
| PLAY_PAUSE | gebouwd (HID 44, de spatiebalk; zie de kanttekening hieronder) |
| LONG SELECT | gebouwd, echte `idb ui key --duration` |
| focus lezen, focusgeschiedenis, ui_tree, viewport, screenshots | bestond |
| route- en paginastaat opvragen | gebouwd, `GET /v1/route` |
| bewijs per invoer (focus/route/scherm vóór en ná, events ertussen) | gebouwd |
| `wait_until` op een gefocuste id | gebouwd |
| geometrie-assertions, evidence bundle | bestond |
| Mijn Pleya adresseerbaar | gebouwd, `my_pleya.tile[...]`, `my_pleya.section[...]`, `screen.my_pleya` |

Kanttekening bij PLAY_PAUSE: de HID-toetsenbordpagina kent geen play/pause, en de
consumer-pagina waar die code wel op staat is via `idb ui key` niet bereikbaar.
tvOS bindt de spatiebalk aan het transport, dus dat is de enige route die er is.
Buiten een spelende speler gedraagt spatie zich als Select. Dat is nog niet in de
simulator tegen een echt spelende titel getoetst; doe dat voordat een scenario
erop bouwt.

## Wat gerepareerd is en met welk bewijs

Drie oorzaken, alle drie op de gedeelde plek gerepareerd. Zie DEC-088 en DEC-089.

- `TvNestedSurface` (`lib/navigation/tv/tv_nested_surface.dart`) geeft elke
  geneste TV-route een deterministische focus-entry die niet afhangt van een
  `GlobalKey` die iemand vergat door te geven, en die ook werkt voor een
  `StatelessWidget`.
- `TvNestedBackOwner` plus `handleBackKeyFocusMove` (`lib/focus/key_event_utils.dart`)
  zorgen dat een `onBack` die een focusverplaatsing is zich binnen een geneste
  route terugtrekt, zodat de backketen van de shell aan de beurt komt.
  `TvBrowseRail` is de enige omgezette aanroepplek.
- `_verticalNeighbour` in `tv_my_pleya_screen.dart` rekent met echte rijen in
  plaats van een vaste stap door een platte lijst.

Bewezen op de tvOS-simulator met echte HID-invoer, dezelfde route vóór en ná:

| Sectie | Vóór | Ná |
|---|---|---|
| Bibliotheken | focus op de scope, DOWN dood, Menu sluit niet | focus/back nog te herdraaien (zie hieronder) |
| Servers | geen sleutel, `StatelessWidget`, dus geen entry | opent op een control, Menu herstelt de tegel |
| Logs en diagnose | geen `FocusableTab`, dus geen entry | opent op `ActionBar[0]`, RIGHT loopt, Menu herstelt de tegel |
| Opties | entry hing op `isKeyboardMode` | opent op `settings_appearance`, DOWN loopt, Menu herstelt de tegel |

Bundels staan onder `.build/pleya-verify/tvos-my-pleya-section-*`.

## Wat open staat, in volgorde van belang

1. **Bibliotheken op TV is inhoudelijk en visueel nog het oude scherm.** Eén
   bibliotheek, geen kiezer, desktop-titelbalk, rode tabonderstreping, inhoud tot
   iets over de helft van het beeld, en een linkermarge die niet met de hub
   overeenkomt. Dit is de kern van de hardwaremelding over "Media". Behoud de
   bedrijfslogica van `LibrariesScreen`; bouw een TV-presentatie met een
   expliciete bronkiezer. De iOS- en macOS-presentatie mag niet breken.
   Zie bevinding 3 in de audit voor de exacte oorzaak in `_buildAppBarTitle`.
2. **De vertaling van de tegel klopt niet met het scherm.** In het Nederlands
   heet de tegel "Media" en het scherm "Bibliotheken". Kies één naam.
3. **Kijklijst, Aanvragen, Downloads en Activiteit zijn niet geauditeerd.** De
   fixture `catalog.mixed.v1` toont er geen tegel voor. Er is een rijkere fixture
   nodig, met een Seerr-server, een download en iets dat speelt.
4. **Dubbele automation-id's.** `/v1/ui_tree` meldt `discover.rail[0]` en
   `discover.rail.item[0.0]` dubbel, omdat twee landings tegelijk gemount staan en
   de instance-suffix de landing niet noemt.
5. **`TvBrowseRail` beantwoordt DOWN altijd met `handled`** terwijl `_moveHub` bij
   de laatste hub meteen terugkeert, en er is geen `onNavigateDown` om op terug te
   vallen zoals UP dat via `onNavigateUp` wel heeft.
6. **De brede journey en de visuele vergelijking over alle oppervlakken** zijn
   niet gedraaid. `pleya_verify/scenarios/tvos.my-pleya.sections.yaml` loopt alle
   zes bereikbare secties in één keer af en is daar het startpunt voor.
7. **P1 tot en met P8 uit de opdracht zijn deze ronde niet opnieuw getoetst.** Ze
   komen uit de vorige ronde en zijn hier niet aangeraakt.

## Invarianten die overeind moeten blijven

- 78 bekende golden failures uit de featurebranch. Niet met `--update-goldens`
  groen maken.
- `docs/sessions/2026-09-02.md` blijft ongetrackt en buiten elke commit.
- `2853ffe` is vervallen en mag nergens meer als baseline dienen.
- De tvOS-invoerroute: een druk gaat via `tvos_sim.sh` en idb HID, nooit via het
  automation-transport. `driver_routing_test.dart` bewaakt dat met een
  bronscan, en die test kent de exacte methodesignatuur, dus een wijziging
  daaraan moet de test meenemen.
- Flutter staat gepind op 3.44.0 in `.fvmrc`. Op deze machine staat 3.44.4 op
  PATH; zet `/Volumes/SSD/flutter-sdks/3.44.0/flutter/bin` ervoor, anders weigert
  elk script.
- `dart run tool/generate_automation_ids_yaml.dart` valt op deze machine om met
  `type 'InvalidType' is not a subtype of type 'FunctionType'`. Dat is een
  omgevingsprobleem dat ook op schone main optreedt. De bewezen omweg is een
  tijdelijke Flutter-testhost die de echte `main()` aanroept; nooit met de hand in
  de YAML schrijven.

## Volgende commando's

```bash
export PATH="/Volumes/SSD/flutter-sdks/3.44.0/flutter/bin:$PATH"
cd pleya_verify/runner
dart run bin/verify.dart run ../scenarios/tvos.my-pleya.section-libraries.yaml
dart run bin/verify.dart run ../scenarios/tvos.my-pleya.sections.yaml
```
