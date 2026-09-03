# Plan: Mijn Pleya-secties op TV-schaal en op één uitlijning

Vervolg op `docs/tvos-my-pleya-audit-2026-09-02.md`. Die ronde repareerde focus,
Back en rastertraversal, waardoor de secties bedienbaar werden. Wat er niet in
zat is hoe ze eruitzien. Dit is dat werk, apart, met eigen voor- en nabewijs.

## Het probleem, gemeten

Acht van de tien Mijn Pleya-secties zijn ongewijzigde mobiel- of desktopschermen
die in de TV-shell op hun eigen schaal getekend worden. Op tien voet afstand
leest dat als uitvergroot, en de pagina's staan onderling niet op één lijn.

Linkermarge van de paginakop, gemeten op dezelfde 3840px-opname:

| Scherm | Kop | Groeplabel | Kaart |
|---|---|---|---|
| Mijn Pleya (hub) | 3,9% | 3,9% | 3,9% |
| Servers (TV-native) | 3,9% | 5,9% | 5,5% |
| Instellingen | 1,5% | 9,6% | 9,25% |
| Bibliotheken | 2,0% | 0,5% | 0,5% |

Drie schermen, drie koppen, drie verschillende randen. Binnen Instellingen alleen
al drie randen op één pagina.

De dichtheid komt uit vaste logische waarden in `lib/widgets/settings_section.dart`
die voor een telefoon en een desktopvenster zijn gekozen en op TV niet meeschalen:

- `kSettingsMaxWidth = 880` op een canvas van 1038 breed, dus de kaart stopt op
  85% en de rest van het beeld blijft leeg;
- `kSettingRowPadding = symmetric(horizontal: 16, vertical: 6)`;
- groepskop `EdgeInsets.fromLTRB(20, 24, 20, 10)`, kaartmarge `fromLTRB(16, 0, 16, 8)`;
- pictogram `size: 20` in een tegel van ongeveer 40.

Ter vergelijking spreekt de hub in `TvMyPleyaLayout`: `tileTitleFontSize` 15,
`tileSubtitleFontSize` 12, `tileIconSize` 19, `tileMinHeight` 74, alles maal
`TvLayoutConstants.scaleOf`. Het pictogram in Instellingen is ten opzichte van het
scherm ongeveer twee keer zo groot als dat van de hub. Instellingen toont vijf
rijen en snijdt de zesde af.

Daarbovenop staat chrome die niet bij het redesign hoort: `CustomAppBar` in
Instellingen en Logs, een tabstrip met rode onderstreping en een desktoptitelbalk
met potlood- en verversknop in Bibliotheken, een afgeronde kaartcontainer met
scheidingslijnen uit de desktopinstellingen.

In dezelfde opname staan ook onvertaalde strings tussen de Nederlandse
("Library Visibility", "Home Layout", "Choose which libraries appear in the menu").
Die horen bij dit werk omdat ze op hetzelfde scherm zichtbaar zijn, maar het is
een losse i18n-taak.

## Aanpak

Vier stappen, elk met eigen bewijs. Stap 2 kan niet zonder stap 1, stap 4 niet
zonder stap 3.

### 1. Eén gedeeld TV-paginaframe

`TvServersScreen` is de referentie en is vier regels: `TvTopNavLayout.pageInset * scale`
horizontaal, kop op `TvMyPleyaLayout.pageTitleFontSize * scale`, `titleGap`, dan de
hergebruikte body. Die vier regels horen in `TvNestedSurface`, dat er al is en al
elke geneste route omhult.

`TvNestedRoute` krijgt een `title`; `TvMyPleyaSection.title` bestaat al en wordt
doorgegeven. Het frame ondersteunt zowel een box-body als slivers, omdat
Instellingen, Logs en Bibliotheken op slivers gebouwd zijn en anders eerst
omgeschreven moeten worden voordat er iets uitgelijnd kan worden.

Het frame hangt een `AutomationNode` om de inhoudskolom, zodat de marge meetbaar
wordt in plaats van geschat.

`TvServersScreen` levert daarna zijn eigen frame in, anders staat de marge er twee
keer in.

### 2. Uitlijning meetbaar maken

`pleya_verify` krijgt een unaire geometriepredicaat `leftInset` dat de linkerrand
van een knoop tegen de veilige zone van de viewport meet. Elke sectie krijgt in
zijn scenario een assertie dat de inhoudskolom op de TV-marge staat.

Daarmee is uitlijning een controle en geen mening, en breekt een scherm dat later
zijn eigen marge terugzet meteen een run.

### 3. TV-dichtheid voor de instellingenlijst

Alleen `lib/widgets/settings_section.dart`. De vaste waarden krijgen een
TV-variant die met `TvLayoutConstants.scaleOf` meeschaalt en zich op de tegeltaal
van de hub richt: dezelfde titel- en ondertitelgrootte, hetzelfde pictogramformaat,
en geen `kSettingsMaxWidth`-cap maar de volle breedte binnen de paginamarge.

Mobiel en desktop veranderen niet. De vertakking gaat op `PlatformDetector.isTV()`
of op de aanwezigheid van `TvShellSurface`, niet op schermbreedte, want een breed
desktopvenster is geen TV.

Dit raakt Instellingen en alles wat dezelfde primitieven gebruikt in één keer, wat
het punt is: geen negen losse patches.

### 4. Oude chrome uitzetten waar de shell al een kop tekent

Per scherm, wanneer `TvShellSurface.isPresent(context)`:

- Instellingen en Logs laten hun `CustomAppBar` weg;
- Over laat de titel van `FocusedScrollScaffold` weg;
- Bibliotheken is de grootste en heeft een eigen TV-presentatie nodig met een
  expliciete bibliotheekkiezer. Dat punt staat al apart in de handoff en gaat
  verder dan styling, want de gebruiker kan op TV nu geen andere bibliotheek
  kiezen.

## Volgorde en bewijs

Per stap: `flutter analyze`, de gerichte tests, en een Pleya Verify-run van de
geraakte secties met screenshots. De scenario's staan er al
(`pleya_verify/scenarios/tvos.my-pleya.section-*.yaml`) en draaien voor en na.

Voor de visuele vergelijking over alle oppervlakken heen hoort er aan het eind één
ronde langs Home, Series, Films, Search, de hub en de zes secties, met de vraag of
ze één ontwerp vormen: dezelfde paginarand, dezelfde kophiërarchie, dezelfde
focusring, dezelfde kaartradius, dezelfde tekstschaal.

## Risico's

Goldens gaan bewegen zodra stap 1 of 3 landt. De 78 bekende failures uit de
featurebranch blijven buiten beschouwing; wat deze ronde bewust verandert wordt per
golden bekeken en pas daarna bijgewerkt, nooit met een blanket `--update-goldens`.

`settings_section.dart` wordt door meer dan alleen TV gebruikt. De vertakking moet
aantoonbaar niets aan iOS en macOS veranderen, en dat is met de bestaande goldens
van die platforms te controleren.

Bibliotheken raakt bedrijfslogica zodra er een kiezer bij komt. Die logica blijft
staan; wat verandert is de presentatie en de manier waarop een bron gekozen wordt.
